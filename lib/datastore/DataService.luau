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
		_profileDataPromise: Promise.Promise<any>,

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
	self._profileDataPromise = self._maid:GivePromise(Promise.new())

	self.DataStore = ProfileStore.New(self:GetStoreNameAndVersion())
end

function DataService.Start(self: DataService)
	self._maid:Add(RxPlayerUtils.observePlayersBrio():Subscribe(function(brio)
		const maid, player = brio:ToMaidAndValue()

		maid:GivePromise(self:LoadProfileAsync(player))
			:Then(function(profile: ProfileStore.Profile<any>)
				const profileData = self._profileDataPromise:Wait()

				const cursor = Squash.cursor()
				profileData.Schema.ser(cursor, profile.Data)
				DataServiceNetwork.packets.profileLoaded.sendTo(Squash.tobuffer(cursor), player)
			end)
			:Catch(function(...): ...any
				warn(`[DataService] - Promise failed during profile loading for {player.UserId} ({...})`)
			end)
	end))

	if RunService:IsStudio() then
		warn(`[DataService] - Using Mock DataStore`)
		self.DataStore = self.DataStore.Mock :: any
	end
end

--[=[
	Sets the ProfileData Module (This HAS to be done, or else data will not be sent)

	@within DataService
	@param module ModuleScript
]=]
function DataService.SetSchema(self: DataService, module: ModuleScript)
	if self._profileDataPromise:IsFulfilled() then
		return
	end

	self._profileDataPromise:Resolve((require :: any)(module))
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
