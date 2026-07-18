--!strict
--[=[
	@class DataService
]=]

const HttpService = game:GetService("HttpService")
const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const require = require("../Loader").load()

const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const RxPlayerUtils = require("RxPlayerUtils")
const ProfileStore = require("ProfileStore")
const ObservableSet = require("ObservableSet")
const ObservableMap = require("ObservableMap")
const Observable = require("Observable")
const Signal = require("Signal")
const Rx = require("Rx")
const t = require("t")
const Promise = require("Promise")
const PromiseUtils = require("PromiseUtils")
const PromiseMaidUtils = require("PromiseMaidUtils")
const BindToCloseService = require("BindToCloseService")
const CmdrService = require("CmdrService")
const Squash = require("Squash")
const TableUtils = require("TableUtils")
const AttributeUtils = require("AttributeUtils")
const DataServiceProfile = require("DataServiceProfile")
const DataServiceNetwork = require("DataServiceNetwork")
const DataServiceUtils = require("DataServiceUtils")

const PROFILE_NAME = "Default"
const PROFILE_VERSION = 1

-- How long a transaction callback may run before it loses its locks. Generous:
-- a callback that has not decided by now is never going to.
const TRANSACTION_TIMEOUT_SECONDS = 10

-- Kept under Roblox's 30 second BindToClose budget, so a profile that never
-- reports its save cannot hold the shutdown open until it is killed anyway
const SAVE_TIMEOUT_SECONDS = 20

const DataService = {}
DataService.ServiceName = "DataService"

export type DataService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_bindToCloseService: BindToCloseService.BindToCloseService,
		_cmdrService: CmdrService.CmdrService,

		_attributeKeys: ObservableSet.ObservableSet<string>,
		_hiddenKeys: ObservableSet.ObservableSet<string>,
		_profileList: ObservableMap.ObservableMap<Player, ProfileStore.Profile<any>>,
		_customReplicators: ObservableMap.ObservableMap<string, (Player, any, string) -> ()>,
		_valueChanged: Signal.Signal<Player, string, any>,

		_lockedPlayers: { [Player]: true },
		_playerUnlocked: Signal.Signal<>,
		_profileData: DataServiceProfile.ProfileDefinition,

		DataStore: ProfileStore.ProfileStore<any>,
	},
	{} :: typeof({ __index = DataService })
))

function DataService.Init(self: DataService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._bindToCloseService = self._serviceBag:GetService(BindToCloseService)
	self._cmdrService = self._serviceBag:GetService(CmdrService)

	self._attributeKeys = self._maid:Add(ObservableSet.new())
	self._hiddenKeys = self._maid:Add(ObservableSet.new())
	self._profileList = self._maid:Add(ObservableMap.new())
	self._customReplicators = self._maid:Add(ObservableMap.new())
	self._valueChanged = self._maid:Add(Signal.new())

	self._lockedPlayers = setmetatable({}, { __mode = "k" }) :: any
	self._playerUnlocked = self._maid:Add(Signal.new())
	self._profileData = DataServiceProfile.Lock()

	self.DataStore = ProfileStore.New(self:GetStoreNameAndVersion(), TableUtils.deepCopy(self._profileData.Template))
end

function DataService.Start(self: DataService)
	-- Swapped before the subscription below, which starts loading profiles the
	-- moment it runs -- any player already present would otherwise load against
	-- the live store and only then get moved onto the mock
	if RunService:IsStudio() then
		warn(`[DataService] - Using Mock DataStore`)
		self.DataStore = self.DataStore.Mock :: any
	end

	local function getCommandProfile(player: Player): ProfileStore.Profile<any>
		const loaded, profileOrError = self:PromiseProfile(player):Yield()
		if not loaded then
			error(tostring(profileOrError))
		end

		const profile = profileOrError :: ProfileStore.Profile<any>
		if not profile:IsActive() then
			error(`Profile is not active for {player.Name}`)
		end
		return profile
	end

	local function encodeCommandValue(value: any): string
		const encoded, resultOrError = (pcall :: any)(HttpService.JSONEncode, HttpService, value)
		if not encoded then
			error(`Data cannot be displayed as JSON: {resultOrError}`)
		end
		return resultOrError :: string
	end

	local function decodeCommandValue(serializedValue: string): any
		const decoded, value = (pcall :: any)(HttpService.JSONDecode, HttpService, serializedValue)
		return if decoded then value else serializedValue
	end

	self._cmdrService:RegisterCommand({
		Name = "read-data",
		Description = "Reads a player's full profile or a dot-separated data path.",
		Group = "DefaultAdmin",
		Args = {
			{
				Type = "player",
				Name = "player",
				Description = "The player whose data should be read.",
			},
			{
				Type = "string",
				Name = "path",
				Description = "An optional dot-separated path, such as Inventory.Items.",
				Optional = true,
			},
		},
		Run = function(_, player: Player, path: string?)
			const profile = getCommandProfile(player)
			const hasPath = type(path) == "string" and path ~= ""
			const value = if hasPath then DataServiceUtils.readValuePath(profile.Data, path :: string) else profile.Data
			if value == nil then
				return `{player.Name}.{path} = nil (path does not exist)`
			end

			return `{player.Name}.{if hasPath then path else "Data"} = {encodeCommandValue(value)}`
		end,
	})

	self._cmdrService:RegisterCommand({
		Name = "write-data",
		Description = "Overwrites an existing data path with JSON or a bare string.",
		Group = "DefaultAdmin",
		Args = {
			{
				Type = "player",
				Name = "player",
				Description = "The player whose data should be changed.",
			},
			{
				Type = "string",
				Name = "path",
				Description = "The existing dot-separated path to overwrite.",
			},
			{
				Type = "string",
				Name = "newValue",
				Description = "JSON for typed values and tables, or unquoted text for a string.",
			},
		},
		Run = function(_, player: Player, path: string, serializedValue: string)
			const newValue = decodeCommandValue(serializedValue)
			if newValue == nil then
				error("JSON null cannot be written to profile data")
			end

			const profile = getCommandProfile(player)
			const candidateData = TableUtils.deepCopy(profile.Data)
			const wroteValue, writeError = pcall(DataServiceUtils.writeValuePath, candidateData, path, newValue)
			if not wroteValue then
				error(`Cannot write data path {path}: {writeError}`)
			end

			const cursor = Squash.cursor()
			const isValid, validationError = pcall(self._profileData.Schema.ser, cursor, candidateData)
			if not isValid then
				error(`New value does not match {DataServiceProfile.GetName()}.Schema: {validationError}`)
			end
			const validationCursor = Squash.frombuffer(Squash.tobuffer(cursor))
			const decoded, schemaDataOrError = pcall(self._profileData.Schema.des, validationCursor)
			if not decoded then
				error(`{DataServiceProfile.GetName()}.Schema could not read the validated value: {schemaDataOrError}`)
			end
			if DataServiceUtils.readValuePath(schemaDataOrError, path) == nil then
				error(`Data path {path} is not represented by {DataServiceProfile.GetName()}.Schema`)
			end

			const resolvedValue = DataServiceUtils.readValuePath(candidateData, path)
			self:SetValue(player, path, resolvedValue)
			const saved, saveError = self:SaveProfile(player):Yield()
			if not saved then
				error(`Data changed in memory but the immediate save failed: {saveError}`)
			end

			return `Set {player.Name}.{path} = {encodeCommandValue(resolvedValue)}`
		end,
	})

	self._cmdrService:RegisterCommand({
		Name = "reset-data",
		Description = "Deletes a player's profile and disconnects them so defaults load on rejoin.",
		Group = "DefaultAdmin",
		Args = {
			{
				Type = "player",
				Name = "player",
				Description = "The player whose profile should be reset.",
			},
		},
		Run = function(_, player: Player)
			getCommandProfile(player)
			const reset, resetError = self:DeleteProfileAsync(player):Yield()
			if not reset then
				error(resetError)
			end

			return `Reset {player.Name}'s data. They must rejoin to load the defaults.`
		end,
	})

	self._maid:GiveTask(self._bindToCloseService:RegisterPromiseOnCloseCallback(function()
		return self:SaveAllProfilesAsync()
	end))

	self._maid:Add(RxPlayerUtils.observePlayersBrio():Subscribe(function(brio)
		const maid, player = brio:ToMaidAndValue()

		maid:GivePromise(self:LoadProfileAsync(player))
			:Then(function(profile: ProfileStore.Profile<any>)
				const hiddenKeys = self._hiddenKeys:GetList()

				const cursor = Squash.cursor()
				self._profileData.Schema.ser(cursor, DataServiceUtils.getReplicatedData(profile.Data, hiddenKeys))
				DataServiceNetwork.packets.profileLoaded.sendTo({
					data = Squash.tobuffer(cursor),
					hiddenKeys = hiddenKeys,
				}, player)

				for _, keyName in self._attributeKeys:GetList() do
					AttributeUtils.setAttribute(player, keyName, (profile.Data :: any)[keyName])
				end
			end)
			:Catch(function(...): ...any
				warn(`[DataService] - Promise failed during profile loading for {player.UserId} ({...})`)
			end)
	end))

	DataServiceNetwork.packets.settingRequested.listen(
		function(payload: { name: string, value: unknown }, player: Player?)
			const profile = self:GetProfile(player :: Player)
			if not profile or not profile:IsActive() then
				return
			end

			if not DataServiceUtils.isWritableSettingName(payload.name) then
				return
			end

			const path = DataServiceUtils.getSettingPath(payload.name)
			const currentValue = DataServiceUtils.readValuePath(profile.Data, path)
			if currentValue == nil then
				return
			end

			if not DataServiceUtils.isValidSettingValue(payload.name, payload.value) then
				-- Never SetValue here. It returns early when the value is unchanged,
				-- which a refusal always is, so nothing would be sent and the client
				-- would keep believing its own guess forever.
				self:ReplicateValue(player :: Player, path, currentValue)
				return
			end

			self:SetValue(player :: Player, path, payload.value)
		end
	)
end

--[=[
	Returns the current name and version of the DataStore

	@within DataService
	@returns string, string
]=]
function DataService.GetStoreNameAndVersion(self: DataService)
	const storeName = self._profileData.StoreName or PROFILE_NAME
	const storeVersion = self._profileData.StoreVersion or PROFILE_VERSION
	assert(type(storeName) == "string" and storeName ~= "", "Bad profile StoreName")
	assert(type(storeVersion) == "number" and storeVersion >= 1 and storeVersion % 1 == 0, "Bad profile StoreVersion")
	return `{storeName}_{storeVersion}`
end

--[=[
	Adds a custom replicator for a profile path. The callback replaces ordinary
	DataService replication for that path and all of its descendants. It also runs
	for hidden paths, allowing a feature service to expose a narrower projection of
	the hidden server data.

	The callback receives the player, changed value, and exact changed path.

	@within DataService
	@param keyName string
	@param callback (Player, any, string) -> ()
	@returns string
]=]
function DataService.AddReplicator(self: DataService, keyName: string, callback: (Player, any, string) -> ()): string
	assert(t.string(keyName), "Bad keyName")
	assert(t.callback(callback), "Bad callback")
	self._customReplicators:Set(keyName, callback)

	return keyName
end

--[=[
	Marks a key as hidden from ordinary DataService replication. Hidden keys live
	in the player's profile and save like any other value. The client is sent a
	blanked-out placeholder of the same shape, and later changes are withheld unless
	a feature installs a narrower projection with [DataService.AddReplicator].

	Set hidden keys before any profile loads. Hiding a key that has already
	replicated does not retract the copy the client is holding.

	```lua
	DataService:SetHiddenKey("PurchaseHistory")
	DataService:SetHiddenKey("Inventory.SecretSeed")
	```

	@within DataService
	@param keyName string
	@returns string
]=]
function DataService.SetHiddenKey(self: DataService, keyName: string): string
	assert(t.string(keyName), "Bad keyName")
	assert(not self._attributeKeys:Contains(keyName), `Cannot hide {keyName}, it is an attribute key`)

	-- Settings have to replicate: a refused [DataServiceClient.SetSetting] is
	-- rolled back by replicating the real value, and ReplicateValue sends nothing
	-- for a hidden key, so the client would keep its own guess forever. Rooted
	-- rather than exact, since hiding "Settings" and hiding "Settings.Foo" break
	-- it in different ways -- and the second would push a hidden value to a client
	-- that was sent a blanked root.
	assert(
		DataServiceUtils.splitValuePath(keyName) ~= DataServiceUtils.getSettingsKey(),
		`Cannot hide {keyName}, settings must replicate`
	)

	self._hiddenKeys:Add(keyName)

	return keyName
end

--[=[
	Unmarks a hidden key. The value replicates again from its next change
	onwards -- the client is not backfilled with what it missed.

	@within DataService
	@param keyName string
	@returns boolean
]=]
function DataService.RemoveHiddenKey(self: DataService, keyName: string): boolean
	assert(t.string(keyName), "Bad keyName")

	return self._hiddenKeys:Remove(keyName)
end

--[=[
	Returns whether a key is hidden from the client.

	@within DataService
	@param keyName string
	@returns boolean
]=]
function DataService.IsHiddenKey(self: DataService, keyName: string): boolean
	assert(t.string(keyName), "Bad keyName")

	for _, hiddenKey in self._hiddenKeys:GetList() do
		if DataServiceUtils.valuePathsOverlap(hiddenKey, keyName) then
			return true
		end
	end

	return false
end

--[=[
	Marks a key as an attribute key. The value is mirrored onto the Player
	instance as an attribute of the same name, both for profiles already loaded
	and for every profile that loads afterwards, and is kept in sync on change.

	The key must be a valid attribute name, which rules out the dot-separated
	paths [DataService.SetValue] accepts. Note that attributes replicate to every
	client, so an attribute key cannot also be hidden.

	```lua
	DataService:SetAttributeKey("Level")
	```

	@within DataService
	@param keyName string
	@returns string
]=]
function DataService.SetAttributeKey(self: DataService, keyName: string): string
	assert(t.string(keyName), "Bad keyName")
	assert(AttributeUtils.isValidAttributeName(keyName), `Bad keyName, {keyName} is not a valid attribute name`)
	assert(not self._hiddenKeys:Contains(keyName), `Cannot set attribute key {keyName}, it is a hidden key`)

	self._attributeKeys:Add(keyName)

	for _, player in self._profileList:GetKeyList() do
		const profile = self._profileList:Get(player)

		if profile and profile:IsActive() then
			AttributeUtils.setAttribute(player, keyName, (profile.Data :: any)[keyName])
		end
	end

	return keyName
end

--[=[
	Unmarks an attribute key and clears the attribute from every loaded player.
	The underlying value stays in the profile.

	@within DataService
	@param keyName string
	@returns boolean
]=]
function DataService.RemoveAttributeKey(self: DataService, keyName: string): boolean
	assert(t.string(keyName), "Bad keyName")

	if not self._attributeKeys:Remove(keyName) then
		return false
	end

	for _, player in self._profileList:GetKeyList() do
		player:SetAttribute(keyName, nil)
	end

	return true
end

--[=[
	Returns whether a key is mirrored onto the Player instance as an attribute.

	@within DataService
	@param keyName string
	@returns boolean
]=]
function DataService.IsAttributeKey(self: DataService, keyName: string): boolean
	assert(t.string(keyName), "Bad keyName")

	return self._attributeKeys:Contains(keyName)
end

--[=[
	Replicates a specified value to a certain client

	@within DataService
	@param player Player
	@param keyName string
	@param keyValue any
	@returns boolean
]=]
function DataService.ReplicateValue(self: DataService, player: Player, keyName: string, keyValue: any): boolean
	assert(self._profileList:Get(player), "Player data hasn't loaded")
	assert(t.string(keyName), "Bad keyName")
	assert(t.any(keyValue), "Bad keyValue")

	if self._attributeKeys:Contains(keyName) then
		AttributeUtils.setAttribute(player, keyName, keyValue)
	end

	-- Fired before the hidden-key check: hiding a key withholds it from the
	-- client, but it is still the player's data and still observable here
	self._valueChanged:Fire(player, keyName, keyValue)

	-- Prefer the most specific registered ancestor. This lets a feature own one
	-- branch while still receiving path-level writes beneath it.
	local customReplicator = self._customReplicators:Get(keyName)
	local customReplicatorPathLength = if customReplicator then #keyName else 0
	if not customReplicator then
		for replicatorPath, candidate in self._customReplicators do
			if
				string.sub(keyName, 1, #replicatorPath + 1) == replicatorPath .. "."
				and #replicatorPath > customReplicatorPathLength
			then
				customReplicator = candidate
				customReplicatorPathLength = #replicatorPath
			end
		end
	end

	if customReplicator then
		const success, resultOrErr = (pcall :: any)(function(...)
			return customReplicator(...)
		end, player, keyValue, keyName)

		if not success then
			warn(`[DataService] - Failed while replicating {keyName:upper()} ({resultOrErr})`)
			return false
		end

		return true
	end

	if self:IsHiddenKey(keyName) then
		return true
	end

	DataServiceNetwork.packets.valueChanged.sendTo({
		name = keyName,
		value = keyValue,
	}, player)

	return true
end

--[=[
	Gets a players profile if it exists

	@within DataService
	@param player Player
	@returns ProfileStore.Profile<any>?
]=]
function DataService.GetProfile(self: DataService, player: Player): ProfileStore.Profile<any>?
	assert(t.instanceIsA("Player")(player), "Bad player")
	return self._profileList:Get(player) or nil
end

--[=[
	Waits for a player's profile, resolving as soon as it is loaded.

	Only ever waits -- unlike [DataService.LoadProfileAsync] it never starts a
	session, so it is what you want from anything that merely needs the profile
	rather than owns loading it. [DataService.Start] does the loading.

	Rejects if the player leaves first, so a caller cannot be left waiting on a
	profile that is never coming.

	```lua
	DataService:PromiseProfile(player):Then(function(profile)
		print(profile.Data.Coins)
	end)
	```

	@within DataService
	@param player Player
	@returns Promise<ProfileStore.Profile<any>>
]=]
function DataService.PromiseProfile(self: DataService, player: Player): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")

	const profile = self:GetProfile(player)
	if profile then
		return Promise.resolved(profile)
	end

	const promise = Promise.new()

	-- whilePromise owns the listeners for exactly as long as the promise is
	-- pending. Keyed into the service maid on top of that, so a Destroy while we
	-- are still waiting takes them with it.
	self._maid[promise] = PromiseMaidUtils.whilePromise(promise, function(maid: Maid.Maid)
		maid:GiveTask(self._profileList:ObserveAtKey(player):Subscribe(function(profileValue: any)
			if profileValue then
				promise:Resolve(profileValue)
			end
		end))

		maid:GiveTask(Players.PlayerRemoving:Connect(function(removingPlayer: Player)
			if removingPlayer == player then
				promise:Reject("Player left before their profile loaded")
			end
		end))
	end)

	promise:Finally(function()
		self._maid[promise] = nil
	end)

	return promise
end

--[=[
	Loads a profile within a Promise

	@within DataService
	@param player Player
	@returns Promise<any>
]=]
function DataService.LoadProfileAsync(self: DataService, player: Player): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")
	const userId = player.UserId

	if self._profileList:ContainsKey(player) then
		return Promise.resolved(self._profileList:Get(player))
	end

	return Promise.new(function(resolve, reject: (...any) -> ())
		const profile = self.DataStore:StartSessionAsync(tostring(userId), {
			Cancel = function()
				return player.Parent ~= Players
			end,
		})

		if not profile or player.Parent ~= Players then
			player:Kick("Your data failed to load, please rejoin.")
			return reject()
		end

		profile:AddUserId(userId)
		profile:Reconcile()
		profile.OnSessionEnd:Connect(function()
			-- We remove it from here because this function declares the profile officialy void
			-- Unlike our remove methods, this is most reliable
			self._profileList:Remove(player)

			if player.Parent == Players then
				player:Kick("There has been an error with your data, please rejoin.")
			end
		end)

		self._profileList:Set(player, profile)
		resolve(profile)
	end)
end

--[=[
	Deletes a profile within a Promise

	@within DataService
	@param player Player
	@returns Promise.Promise<any>
]=]
function DataService.DeleteProfileAsync(self: DataService, player: Player)
	assert(t.instanceIsA("Player")(player), "Bad player")

	return Promise.new(function(resolve, reject: (...any) -> ())
		const profile = assert(self:GetProfile(player))
		const userId = tostring(player.UserId)

		if profile ~= nil and profile:IsActive() then
			profile:EndSession()
		end

		const success, resultOrErr = pcall(function(userId)
			return self.DataStore:RemoveAsync(userId)
		end, userId)

		if success then
			resolve(success)
		else
			warn(`[DataService] - Failed while deleting profile for {userId} ({resultOrErr})`)
			reject(resultOrErr)
		end
	end)
end

--[=[
	Flushes a player's profile to the DataStore, resolving once the write has
	actually landed rather than once it has been asked for.

	Resolves immediately for a player with no profile, or whose session already
	ended -- there is nothing to save and nothing to wait for.

	@within DataService
	@param player Player
	@return Promise<()>
]=]
function DataService.SaveProfile(self: DataService, player: Player): Promise.Promise<any>
	assert(t.instanceIsA("Player")(player), "Bad player")

	const profile = self:GetProfile(player)
	if not profile or not profile:IsActive() then
		return Promise.resolved()
	end

	-- Profile:Save() spawns the write and returns straight away, so the profile
	-- has to tell us when it is done. Connected first: the save can land before
	-- the call returns.
	const promise = PromiseUtils.fromSignal((profile :: any).OnAfterSave)
	profile:Save()

	return PromiseUtils.timeout(SAVE_TIMEOUT_SECONDS, promise)
end

--[=[
	Flushes every loaded profile, resolving once they have all landed. Registered
	as a [BindToCloseService] callback so a shutdown waits for it.

	@within DataService
	@return Promise<()>
]=]
function DataService.SaveAllProfilesAsync(self: DataService): Promise.Promise<any>
	const promises = {}

	for _, player in self._profileList:GetKeyList() do
		table.insert(promises, self:SaveProfile(player))
	end

	return PromiseUtils.all(promises)
end

--[=[
	Gets a Value from within a players profile

	@within DataService
	@param player Player
	@param keyName string
	@returns any
]=]
function DataService.GetValue<T>(self: DataService, player: Player, keyName: string): T?
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.string(keyName), "Bad keyName")

	const profile = self:GetProfile(player)
	assert(profile ~= nil and profile:IsActive(), "Bad profile")

	return DataServiceUtils.readValuePath(profile.Data, keyName) :: T?
end

--[=[
	Observes a player's whole profile, firing with the current data and again on
	every change. Completes nothing when the player leaves -- it simply stops
	firing, since the profile is gone.

	Fires a deep copy, so mutating what you receive does not touch the profile.
	Prefer [DataService.ObserveAtKey] unless you really need the whole thing.

	@within DataService
	@param player Player
	@return Observable<any>
]=]
function DataService.Observe(self: DataService, player: Player): Observable.Observable<any>
	assert(t.instanceIsA("Player")(player), "Bad player")

	return Observable.new(function(sub)
		const maid = Maid.new()

		const function update()
			const profile = self:GetProfile(player)
			if profile then
				sub:Fire(TableUtils.deepCopy(profile.Data))
			end
		end

		maid:GiveTask(self._valueChanged:Connect(function(changedPlayer: Player)
			if changedPlayer == player then
				update()
			end
		end))

		update()

		return maid
	end)
end

--[=[
	Observes a single value in a player's profile, firing with the current value
	and again on every change. Supports nested dot-separated paths.

	```lua
	DataService:ObserveAtKey(player, "Coins")
	DataService:ObserveAtKey(player, "Inventory.MaxItems")
	```

	@within DataService
	@param player Player
	@param keyName string
	@return Observable<any>
]=]
function DataService.ObserveAtKey<T>(self: DataService, player: Player, keyName: string): Observable.Observable<T?>
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.string(keyName), "Bad keyName")

	const rootKey = DataServiceUtils.splitValuePath(keyName)

	return Observable.new(function(sub)
		const maid = Maid.new()

		const function update()
			const profile = self:GetProfile(player)
			if profile then
				sub:Fire(DataServiceUtils.readValuePath(profile.Data, keyName))
			end
		end

		maid:GiveTask(self._valueChanged:Connect(function(changedPlayer: Player, changedKey: string)
			-- Any write sharing our root key can move this path, in either
			-- direction: writing "Inventory" changes "Inventory.MaxItems", and
			-- writing "Inventory.MaxItems" changes "Inventory"
			if changedPlayer == player and DataServiceUtils.splitValuePath(changedKey) == rootKey then
				update()
			end
		end))

		update()

		return maid
	end):Pipe({
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Sets a Value from within the players profile

	```lua
	DataService:SetValue(player, "Coins", 100)
	DataService:SetValue(player, "Inventory.MaxItems", 50)
	DataService:SetValue(player, "Coins", function(coins)
		return coins + 100
	end)

	DataService:SetValue(player, "Inventory.MaxItems", function(maxItems)
		return maxItems + 5
	end)
	```


	@within DataService
	@param player Player
	@param keyName string
	@param keyValue any
	@returns any
]=]
function DataService.SetValue(self: DataService, player: Player, keyName: string, keyValue: any)
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.string(keyName), "Bad keyName")
	assert(t.any(keyValue), "Bad keyValue")

	const profile = self:GetProfile(player)
	assert(profile ~= nil and profile:IsActive(), "Bad profile")

	const currentValue = DataServiceUtils.readValuePath(profile.Data, keyName)
	local newValue = nil

	const isCallback = t.callback(keyValue)
	if isCallback then
		newValue = keyValue(TableUtils.deepCopy(currentValue))
	else
		newValue = keyValue
	end

	if TableUtils.deepEquivalent(currentValue, newValue) then
		return newValue
	end

	DataServiceUtils.writeValuePath(profile.Data, keyName, newValue)
	self:ReplicateValue(player, keyName, newValue)

	return newValue
end

--[=[
    Like SetValue but not limited to one value

	```lua
	DataService:UpdateProfile(player, function(data)
		data.Coins += 100
		data.Level += 1

		return data
	end)
	```

    @within DataService
    @param player Player
    @param callback (data) -> data
    @returns any
]=]
function DataService.UpdateProfile(self: DataService, player: Player, callback: (any) -> any)
	assert(t.instanceIsA("Player")(player), "Bad player")
	assert(t.callback(callback), "Bad callback")

	const profile = self:GetProfile(player)
	assert(profile ~= nil and profile:IsActive(), "Bad profile")

	const currentData = profile.Data
	const newData = callback(TableUtils.deepCopy(currentData))
	const pendingReplication = DataServiceUtils.deepDiffPaths(currentData, newData)

	TableUtils.deepOverwrite(profile.Data, newData)
	for keyName, value in pendingReplication do
		self:ReplicateValue(player, keyName, value)
	end

	return newData
end

--[=[
	Applies one change across two profiles atomically -- a trade, a gift, buying
	something for somebody else. Either both profiles commit or neither does, so
	nothing can be created or destroyed in between.

	The callback receives a deep copy of each player's data and returns the two
	new versions. Return nothing to veto: the transaction rejects and neither
	profile is touched, which is how you turn down a trade that no longer adds up.

	```lua
	DataService:TransactionAsync(seller, buyer, function(sellerData, buyerData)
		if buyerData.Coins < 100 or not table.find(sellerData.Inventory, itemId) then
			return -- veto, nothing is written
		end

		buyerData.Coins -= 100
		sellerData.Coins += 100
		table.remove(sellerData.Inventory, table.find(sellerData.Inventory, itemId))
		table.insert(buyerData.Inventory, itemId)

		return sellerData, buyerData
	end)
	```

	The callback may yield, but the less it does the better. It holds both
	players' transaction locks while it runs, it has TRANSACTION_TIMEOUT_SECONDS
	to finish before it is abandoned and the transaction rejects, and if either
	profile is written by anything else in the meantime the transaction rejects
	rather than commit on top of a stale read.

	@within DataService
	@param playerA Player
	@param playerB Player
	@param callback (dataA, dataB) -> (dataA?, dataB?)
	@return Promise<any, any> -- Both players' new data
]=]
function DataService.TransactionAsync(
	self: DataService,
	playerA: Player,
	playerB: Player,
	callback: (any, any) -> (any?, any?)
): Promise.Promise<any>
	assert(t.instanceIsA("Player")(playerA), "Bad playerA")
	assert(t.instanceIsA("Player")(playerB), "Bad playerB")
	assert(playerA ~= playerB, "Cannot transact a player with themselves")
	assert(t.callback(callback), "Bad callback")

	return Promise.spawn(function(resolve, reject: (...any) -> ())
		const maid = Maid.new()

		-- Locked in a fixed order every time. Two transactions sharing a player
		-- can otherwise each hold the lock the other is waiting on
		const ordered = { playerA, playerB }
		table.sort(ordered, function(left: Player, right: Player)
			return left.UserId < right.UserId
		end)

		for _, player in ordered do
			while self._lockedPlayers[player] do
				self._playerUnlocked:Wait()
			end

			self._lockedPlayers[player] = true
		end

		-- Every exit below runs through the maid, so the locks come back whether
		-- we commit, veto, error or time out
		maid:GiveTask(function()
			for _, player in ordered do
				self._lockedPlayers[player] = nil
			end

			self._playerUnlocked:Fire()
		end)

		const profileA = self:GetProfile(playerA)
		const profileB = self:GetProfile(playerB)

		if not (profileA and profileA:IsActive() and profileB and profileB:IsActive()) then
			maid:DoCleaning()
			return reject("Both players must have an active profile")
		end

		-- Snapshots to compare against once the callback is done, so a write that
		-- lands while it yields cannot be silently overwritten
		const originalA = TableUtils.deepCopy(profileA.Data)
		const originalB = TableUtils.deepCopy(profileB.Data)

		-- The callback gets its own thread. Run inline, one that never returns
		-- would take this thread down with it and strand both locks for good
		const callbackPromise = maid:GivePromise(Promise.spawn(function(resolveCallback, rejectCallback)
			const ranCallback, resultA, resultB =
				pcall(callback, TableUtils.deepCopy(originalA), TableUtils.deepCopy(originalB))

			if not ranCallback then
				return rejectCallback(resultA)
			end

			resolveCallback(resultA, resultB)
		end))

		maid:GiveTask(task.delay(TRANSACTION_TIMEOUT_SECONDS, function()
			callbackPromise:Reject(`Transaction timed out after {TRANSACTION_TIMEOUT_SECONDS} seconds`)
		end))

		const success, newDataA, newDataB = callbackPromise:Yield()

		if not success then
			maid:DoCleaning()
			return reject(newDataA)
		end

		if newDataA == nil or newDataB == nil then
			maid:DoCleaning()
			return reject("Transaction vetoed by callback")
		end

		if not (profileA:IsActive() and profileB:IsActive()) then
			maid:DoCleaning()
			return reject("A profile ended its session during the transaction")
		end

		if
			not TableUtils.deepEquivalent(profileA.Data, originalA)
			or not TableUtils.deepEquivalent(profileB.Data, originalB)
		then
			maid:DoCleaning()
			return reject("A profile changed during the transaction")
		end

		-- Commit. Nothing below yields, so no other code observes one profile
		-- written and the other not
		const changedA = DataServiceUtils.getChangedRootKeys(originalA, newDataA)
		const changedB = DataServiceUtils.getChangedRootKeys(originalB, newDataB)

		TableUtils.deepSync(profileA.Data, newDataA)
		TableUtils.deepSync(profileB.Data, newDataB)

		maid:DoCleaning()

		-- Replicated a whole root key at a time: a dot-separated path cannot say
		-- "this item left the array", and a trade is mostly removals
		for _, keyName in changedA do
			self:ReplicateValue(playerA, keyName, (profileA.Data :: any)[keyName])
		end

		for _, keyName in changedB do
			self:ReplicateValue(playerB, keyName, (profileB.Data :: any)[keyName])
		end

		resolve(newDataA, newDataB)
	end)
end

function DataService.Destroy(self: DataService)
	self._maid:Destroy()
end

return DataService
