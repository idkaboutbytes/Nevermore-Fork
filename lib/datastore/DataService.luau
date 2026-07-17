--!strict
--[=[
	@class DataService
]=]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")

const require = require("../Loader").load()

const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const RxPlayerUtils = require("RxPlayerUtils")
const ProfileStore = require("ProfileStore")
const ObservableSet = require("ObservableSet")
const ObservableMap = require("ObservableMap")
const t = require("t")
const Promise = require("Promise")
const Squash = require("Squash")
const TableUtils = require("TableUtils")
const AttributeUtils = require("AttributeUtils")
const ProfileData = require("ProfileData")
const DataServiceNetwork = require("DataServiceNetwork")
const DataServiceUtils = require("DataServiceUtils")

const PROFILE_NAME = "Default"
const PROFILE_VERSION = 1

const DataService = {}
DataService.ServiceName = "DataService"

export type DataService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,

		_attributeKeys: ObservableSet.ObservableSet<string>,
		_hiddenKeys: ObservableSet.ObservableSet<string>,
		_profileList: ObservableMap.ObservableMap<Player, ProfileStore.Profile<any>>,
		_customReplicators: ObservableMap.ObservableMap<string, () -> ()>,

		DataStore: ProfileStore.ProfileStore<any>,
	},
	{} :: typeof({ __index = DataService })
))

function DataService.Init(self: DataService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._attributeKeys = self._maid:Add(ObservableSet.new())
	self._hiddenKeys = self._maid:Add(ObservableSet.new())
	self._profileList = self._maid:Add(ObservableMap.new())
	self._customReplicators = self._maid:Add(ObservableMap.new())

	-- The template has to reach ProfileStore.New: both Reconcile and new-profile
	-- creation read it back off the store, so a store built without one hands out
	-- empty data the schema cannot serialize. Copied because ProfileData is
	-- readonly and ProfileStore takes ownership of the table.
	self.DataStore = ProfileStore.New(self:GetStoreNameAndVersion(), TableUtils.deepCopy(ProfileData.Template))
end

function DataService.Start(self: DataService)
	-- Swapped before the subscription below, which starts loading profiles the
	-- moment it runs -- any player already present would otherwise load against
	-- the live store and only then get moved onto the mock
	if RunService:IsStudio() then
		warn(`[DataService] - Using Mock DataStore`)
		self.DataStore = self.DataStore.Mock :: any
	end

	self._maid:Add(RxPlayerUtils.observePlayersBrio():Subscribe(function(brio)
		const maid, player = brio:ToMaidAndValue()

		maid:GivePromise(self:LoadProfileAsync(player))
			:Then(function(profile: ProfileStore.Profile<any>)
				const hiddenKeys = self._hiddenKeys:GetList()

				const cursor = Squash.cursor()
				ProfileData.Schema.ser(cursor, DataServiceUtils.getReplicatedData(profile.Data, hiddenKeys))
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
end

--[=[
	Returns the current name and version of the DataStore

	@within DataService
	@returns string, string
]=]
function DataService.GetStoreNameAndVersion(self: DataService)
	return `{PROFILE_NAME}_{PROFILE_VERSION}`
end

--[=[
	Adds a custom replicator for the network, customizing how data is sent via the network

	@within DataService
	@param keyName string
	@param callback function
	@returns Symbol
]=]
function DataService.AddReplicator(self: DataService, keyName: string, callback: () -> ()): string
	assert(t.string(keyName), "Bad keyName")
	assert(t.callback(callback), "Bad callback")
	self._customReplicators:Set(keyName, callback)

	return keyName
end

--[=[
	Marks a key as hidden. Hidden keys live in the player's profile and save like
	any other value, but never replicate -- the client is sent a blanked-out
	placeholder of the same shape in its place, and later changes are not sent at
	all.

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

	return self._hiddenKeys:Contains(keyName)
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

	if self._hiddenKeys:Contains(keyName) then
		return true
	end

	const customReplicator = self._customReplicators:Get(keyName)
	if customReplicator then
		const success, resultOrErr = (pcall :: any)(function(...)
			return customReplicator(...)
		end, player, keyValue)

		if not success then
			warn(`[DataService] - Failed while replicating {keyName:upper()} ({resultOrErr})`)
			return false
		end

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

	return (profile.Data :: any)[keyName] :: T?
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

function DataService.Destroy(self: DataService)
	self._maid:Destroy()
end

return DataService
