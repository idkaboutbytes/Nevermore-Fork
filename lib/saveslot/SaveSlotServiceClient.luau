--!strict
--[=[
	Client-side save-slot metadata and selection API. Slot contents remain
	server-only; account-facing UI receives only metadata and active slot IDs from
	DataServiceClient.

	@class SaveSlotServiceClient
]=]

const require = require("../Loader").load()

const DataServiceClient = require("DataServiceClient")
const Maid = require("Maid")
const Observable = require("Observable")
const Promise = require("Promise")
const Rx = require("Rx")
const SaveSlotConstants = require("SaveSlotConstants")
const SaveSlotNetwork = require("SaveSlotNetwork")
const SaveSlotTypes = require("SaveSlotTypes")
const SaveSlotUtils = require("SaveSlotUtils")
const ServiceBag = require("ServiceBag")

const SaveSlotServiceClient = {}
SaveSlotServiceClient.ServiceName = "SaveSlotServiceClient"

export type SaveSlotServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_dataServiceClient: DataServiceClient.DataServiceClient,
	},
	{} :: typeof({ __index = SaveSlotServiceClient })
))

local function invokeMutationAsync(query: any, request: any): Promise.Promise<any>
	return Promise.spawn(function(resolve, reject: (...any) -> ())
		const invoked, response = pcall(query.invoke, request)
		if not invoked then
			reject(response)
			return
		end
		if type(response) ~= "table" or response.success ~= true then
			reject(if type(response) == "table" then response.error else "Invalid server response")
			return
		end
		resolve(response.slotId)
	end)
end

function SaveSlotServiceClient.Init(self: SaveSlotServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._dataServiceClient = self._serviceBag:GetService(DataServiceClient)
end

--[=[
	Resolves when the local DataService profile mirror is available.

	@within SaveSlotServiceClient
	@return Promise
]=]
function SaveSlotServiceClient.ReadyAsync(self: SaveSlotServiceClient): Promise.Promise<any>
	return self._dataServiceClient:PromiseDataStore()
end

--[=[
	Returns server-side slot selection configuration.

	@within SaveSlotServiceClient
	@return Promise<SaveSlotConfig>
]=]
function SaveSlotServiceClient.GetConfigAsync(_self: SaveSlotServiceClient): Promise.Promise<any>
	return Promise.spawn(function(resolve, reject: (...any) -> ())
		const success, response = pcall(SaveSlotNetwork.queries.getConfig.invoke, nil)
		if success and type(response) == "table" then
			resolve(response)
		else
			reject(response)
		end
	end)
end

--[=[
	Returns whether explicit slot selection is required.

	@within SaveSlotServiceClient
	@return Promise<boolean>
]=]
function SaveSlotServiceClient.GetExplicitSelectionRequiredAsync(self: SaveSlotServiceClient): Promise.Promise<any>
	return self:GetConfigAsync():Then(function(config: SaveSlotTypes.SaveSlotConfig)
		return config.explicitSelection
	end)
end

--[=[
	Returns the active slot ID, or nil when no slot is selected.

	@within SaveSlotServiceClient
	@return string?
]=]
function SaveSlotServiceClient.GetActiveSlotId(self: SaveSlotServiceClient): SaveSlotTypes.SlotId?
	return SaveSlotUtils.toOptionalSlotId(self._dataServiceClient:GetValue(SaveSlotConstants.ACTIVE_SLOT_ID_PATH))
end

--[=[
	Returns the last slot selected in this or a previous session.

	@within SaveSlotServiceClient
	@return string?
]=]
function SaveSlotServiceClient.GetLastActiveSlotId(self: SaveSlotServiceClient): SaveSlotTypes.SlotId?
	return SaveSlotUtils.toOptionalSlotId(self._dataServiceClient:GetValue(SaveSlotConstants.LAST_ACTIVE_SLOT_ID_PATH))
end

--[=[
	Observes the active slot ID.

	@within SaveSlotServiceClient
	@return Observable
]=]
function SaveSlotServiceClient.ObserveActiveSlotId(
	self: SaveSlotServiceClient
): Observable.Observable<SaveSlotTypes.SlotId?>
	return self._dataServiceClient:ObserveAtKey(SaveSlotConstants.ACTIVE_SLOT_ID_PATH):Pipe({
		Rx.map(SaveSlotUtils.toOptionalSlotId) :: any,
	}) :: any
end

--[=[
	Returns sorted metadata for all local-player slots.

	@within SaveSlotServiceClient
	@return { SaveSlotMetadata }
]=]
function SaveSlotServiceClient.GetSlotList(self: SaveSlotServiceClient): { SaveSlotTypes.SaveSlotMetadata }
	return SaveSlotUtils.getSlotList(self._dataServiceClient:GetValue(SaveSlotConstants.METADATA_PATH))
end

--[=[
	Observes sorted slot metadata.

	@within SaveSlotServiceClient
	@return Observable
]=]
function SaveSlotServiceClient.ObserveSlotList(
	self: SaveSlotServiceClient
): Observable.Observable<{ SaveSlotTypes.SaveSlotMetadata }>
	return self._dataServiceClient:ObserveAtKey(SaveSlotConstants.METADATA_PATH):Pipe({
		Rx.map(SaveSlotUtils.getSlotList) :: any,
	}) :: any
end

--[=[
	Returns metadata for one slot.

	@within SaveSlotServiceClient
	@param slotId string
	@return SaveSlotMetadata?
]=]
function SaveSlotServiceClient.GetSlotMetadata(
	self: SaveSlotServiceClient,
	slotId: SaveSlotTypes.SlotId
): SaveSlotTypes.SaveSlotMetadata?
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return SaveSlotUtils.getSlotMetadata(self._dataServiceClient:GetValue(SaveSlotConstants.METADATA_PATH), slotId)
end

--[=[
	Observes metadata for one slot. Emits nil after the slot is deleted.

	@within SaveSlotServiceClient
	@param slotId string
	@return Observable
]=]
function SaveSlotServiceClient.ObserveSlotMetadata(
	self: SaveSlotServiceClient,
	slotId: SaveSlotTypes.SlotId
): Observable.Observable<SaveSlotTypes.SaveSlotMetadata?>
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return self._dataServiceClient:ObserveAtKey(SaveSlotConstants.METADATA_PATH):Pipe({
		Rx.map(function(metadataMap)
			return SaveSlotUtils.getSlotMetadata(metadataMap, slotId)
		end) :: any,
	}) :: any
end

--[=[
	Returns the slot ID assigned to an index.

	@within SaveSlotServiceClient
	@param slotIndex number
	@return string?
]=]
function SaveSlotServiceClient.GetSlotIdFromIndex(self: SaveSlotServiceClient, slotIndex: number): SaveSlotTypes.SlotId?
	assert(type(slotIndex) == "number", "Bad slotIndex")
	return SaveSlotUtils.getSlotIdFromIndex(
		self._dataServiceClient:GetValue(SaveSlotConstants.METADATA_PATH),
		slotIndex
	)
end

--[=[
	Returns whether the local metadata mirror contains a slot.

	@within SaveSlotServiceClient
	@param slotId string
	@return boolean
]=]
function SaveSlotServiceClient.HasSlot(self: SaveSlotServiceClient, slotId: SaveSlotTypes.SlotId): boolean
	return self:GetSlotMetadata(slotId) ~= nil
end

--[=[
	Requests creation of a slot owned by the local player.

	@within SaveSlotServiceClient
	@param slotIndex number
	@param metadata SaveSlotMetadataInput?
	@return Promise<string>
]=]
function SaveSlotServiceClient.CreateSlotAsync(
	_self: SaveSlotServiceClient,
	slotIndex: number,
	metadata: SaveSlotTypes.SaveSlotMetadataInput?
): Promise.Promise<any>
	assert(
		type(slotIndex) == "number"
			and slotIndex % 1 == 0
			and slotIndex >= 1
			and slotIndex <= SaveSlotConstants.MAX_SLOT_COUNT,
		"Bad slotIndex"
	)
	assert(metadata == nil or type(metadata) == "table", "Bad metadata")
	return invokeMutationAsync(SaveSlotNetwork.queries.createSlot, {
		slotIndex = slotIndex,
		slotName = if metadata and metadata.SlotName then metadata.SlotName else "",
		summary = if metadata and metadata.Summary then metadata.Summary else "",
	})
end

--[=[
	Requests selection of a slot owned by the local player.

	@within SaveSlotServiceClient
	@param slotId string
	@return Promise<string>
]=]
function SaveSlotServiceClient.SelectSlotAsync(
	_self: SaveSlotServiceClient,
	slotId: SaveSlotTypes.SlotId
): Promise.Promise<any>
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return invokeMutationAsync(SaveSlotNetwork.queries.selectSlot, slotId)
end

--[=[
	Requests deletion of an inactive slot owned by the local player.

	@within SaveSlotServiceClient
	@param slotId string
	@return Promise<string>
]=]
function SaveSlotServiceClient.DeleteSlotAsync(
	_self: SaveSlotServiceClient,
	slotId: SaveSlotTypes.SlotId
): Promise.Promise<any>
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	return invokeMutationAsync(SaveSlotNetwork.queries.deleteSlot, slotId)
end

--[=[
	Requests a name and/or summary change for one local-player slot.

	@within SaveSlotServiceClient
	@param slotId string
	@param metadata SaveSlotMetadataInput
	@return Promise<string>
]=]
function SaveSlotServiceClient.SetSlotMetadataAsync(
	_self: SaveSlotServiceClient,
	slotId: SaveSlotTypes.SlotId,
	metadata: SaveSlotTypes.SaveSlotMetadataInput
): Promise.Promise<any>
	assert(SaveSlotUtils.isSlotId(slotId), "Bad slotId")
	assert(type(metadata) == "table", "Bad metadata")
	return invokeMutationAsync(SaveSlotNetwork.queries.setMetadata, {
		slotId = slotId,
		hasSlotName = metadata.SlotName ~= nil,
		slotName = metadata.SlotName or "",
		hasSummary = metadata.Summary ~= nil,
		summary = metadata.Summary or "",
	})
end

function SaveSlotServiceClient.Destroy(self: SaveSlotServiceClient)
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return SaveSlotServiceClient
