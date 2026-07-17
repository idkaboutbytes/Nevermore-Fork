--!strict
--[=[
	Client-side mirror of [DataService].

	Receives the full profile as one Squash buffer (`profileLoaded`) and then
	applies `valueChanged` deltas on top of it. The store is read-only with one
	exception: [DataServiceClient.SetSetting] may ask the server to change a
	setting. Everything else is server-authoritative and has no setter.

	@class DataServiceClient
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const ObservableMap = require("ObservableMap")
const Observable = require("Observable")
const Rx = require("Rx")
const t = require("t")
const Promise = require("Promise")
const Squash = require("Squash")
const TableUtils = require("TableUtils")
const ProfileData = require("ProfileData")
const DataServiceNetwork = require("DataServiceNetwork")
const DataServiceUtils = require("DataServiceUtils")

const DataServiceClient = {}
DataServiceClient.ServiceName = "DataServiceClient"

export type DataServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,

		_data: ObservableMap.ObservableMap<string, any>,
		_dataPromise: Promise.Promise<any>,
	},
	{} :: typeof({ __index = DataServiceClient })
))

function DataServiceClient.Init(self: DataServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()

	self._data = self._maid:Add(ObservableMap.new())
	self._dataPromise = self._maid:GivePromise(Promise.new())
end

function DataServiceClient.Start(self: DataServiceClient)
	DataServiceNetwork.packets.profileLoaded.listen(function(value: { data: buffer, hiddenKeys: { string } })
		const cursor = Squash.frombuffer(value.data)
		const success, profile = pcall(ProfileData.Schema.des, cursor)

		if not success then
			warn(`[DataServiceClient] - Failed to deserialize profile ({profile})`)
			return
		end

		-- Hidden keys ride along blanked out to keep the buffer schema-shaped,
		-- so drop them rather than surface a placeholder as if it were real
		for _, keyName in value.hiddenKeys do
			DataServiceUtils.writeValuePath(profile, keyName, nil)
		end

		for keyName, keyValue in profile do
			self._data:Set(keyName, keyValue)
		end

		self._dataPromise:Resolve(self:GetData())
	end)

	DataServiceNetwork.packets.valueChanged.listen(function(value: { name: string, value: any })
		DataServiceUtils.writeObservableValuePath(self._data, value.name, value.value)
	end)
end

--[=[
	Resolves with the local player's profile data once the server has sent it.
	Resolves immediately if it has already arrived.

	@within DataServiceClient
	@return Promise<any>
]=]
function DataServiceClient.PromiseDataStore(self: DataServiceClient): Promise.Promise<any>
	return Promise.resolved(self._dataPromise)
end

--[=[
	Returns a copy of the currently replicated profile data.

	@within DataServiceClient
	@return any
]=]
function DataServiceClient.GetData(self: DataServiceClient): any
	return TableUtils.assign({}, self._data :: any)
end

--[=[
	Gets a value out of the replicated profile. Supports nested dot-separated
	paths.

	```lua
	DataServiceClient:GetValue("Coins")
	DataServiceClient:GetValue("Inventory.MaxItems")
	```

	@within DataServiceClient
	@param keyName string
	@return any
]=]
function DataServiceClient.GetValue<T>(self: DataServiceClient, keyName: string): T?
	assert(t.string(keyName), "Bad keyName")

	return DataServiceUtils.readObservableValuePath(self._data, keyName) :: T?
end

--[=[
	Observes the whole replicated profile, firing with the current data and
	again on every change.

	@within DataServiceClient
	@return Observable<any>
]=]
function DataServiceClient.Observe(self: DataServiceClient): Observable.Observable<any>
	return Observable.new(function(sub)
		const maid = Maid.new()

		const function update()
			sub:Fire(self:GetData())
		end

		maid:GiveTask(self._data.KeyValueChanged:Connect(update))
		update()

		return maid
	end)
end

--[=[
	Observes a single value in the replicated profile. Supports nested
	dot-separated paths.

	```lua
	DataServiceClient:ObserveAtKey("Coins")
	DataServiceClient:ObserveAtKey("Inventory.MaxItems")
	```

	@within DataServiceClient
	@param keyName string
	@return Observable<any>
]=]
function DataServiceClient.ObserveAtKey<T>(self: DataServiceClient, keyName: string): Observable.Observable<T?>
	assert(t.string(keyName), "Bad keyName")

	const rootKey, path = DataServiceUtils.splitValuePath(keyName)
	if not path then
		return self._data:ObserveAtKey(rootKey) :: any
	end

	return self._data:ObserveAtKey(rootKey):Pipe({
		Rx.map(function(rootValue: any): any
			return DataServiceUtils.readValuePath(rootValue, path)
		end) :: any,
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Gets a setting. Settings are the keys of the profile template's Settings
	table.

	```lua
	DataServiceClient:GetSetting("MusicEnabled")
	```

	@within DataServiceClient
	@param name string
	@return any
]=]
function DataServiceClient.GetSetting<T>(self: DataServiceClient, name: string): T?
	assert(DataServiceUtils.isSettingName(name), `Bad name, {tostring(name)} is not a setting`)

	return self:GetValue(DataServiceUtils.getSettingPath(name)) :: T?
end

--[=[
	Asks the server to change a setting, and applies it locally straight away.

	The local store updates before this returns, so observers have already fired
	with the new value by the time the request reaches the server. The server has
	the final say: if it refuses, it sends the real value back and the local store
	snaps to it through the ordinary replication path. There is no acknowledgement
	and no rejection signal -- observing the setting is how you find out.

	Only settings whose default is a primitive can be set from here. Errors rather
	than no-ops on a bad name or value, since an honest caller is checked against
	the same rules the server uses and so should never be refused.

	```lua
	DataServiceClient:SetSetting("MusicEnabled", false)
	```

	@within DataServiceClient
	@param name string
	@param value any
]=]
function DataServiceClient.SetSetting(self: DataServiceClient, name: string, value: any)
	assert(DataServiceUtils.isWritableSettingName(name), `Bad name, {tostring(name)} is not a writable setting`)
	assert(DataServiceUtils.isValidSettingValue(name, value), `Bad value for setting {name}`)

	const path = DataServiceUtils.getSettingPath(name)
	const rootKey = DataServiceUtils.splitValuePath(path)
	assert(self._data:ContainsKey(rootKey), "Profile hasn't loaded")

	if DataServiceUtils.readObservableValuePath(self._data, path) == value then
		return
	end

	-- Applied first, sent second. The wire cannot beat this either way -- ByteNet
	-- batches sends to the next heartbeat -- but doing it in this order is what
	-- makes "observers have fired by the time this returns" a guarantee.
	DataServiceUtils.writeObservableValuePath(self._data, path, value)
	DataServiceNetwork.packets.settingRequested.send({
		name = name,
		value = value,
	})
end

--[=[
	Observes a setting, firing with the current value and again on every change,
	including when the server rolls back a change it refused.

	```lua
	DataServiceClient:ObserveSetting("MusicEnabled")
	```

	@within DataServiceClient
	@param name string
	@return Observable<any>
]=]
function DataServiceClient.ObserveSetting<T>(self: DataServiceClient, name: string): Observable.Observable<T?>
	assert(DataServiceUtils.isSettingName(name), `Bad name, {tostring(name)} is not a setting`)

	return self:ObserveAtKey(DataServiceUtils.getSettingPath(name))
end

function DataServiceClient.Destroy(self: DataServiceClient)
	self._maid:Destroy()
end

return DataServiceClient
