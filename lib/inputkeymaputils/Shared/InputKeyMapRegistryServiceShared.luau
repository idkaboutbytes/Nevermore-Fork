--!strict
--[=[
	Centralized service for registering and looking up InputKeyMapLists across providers.

	@class InputKeyMapRegistryServiceShared
]=]

const require = require("../../Loader").load()

const RunService = game:GetService("RunService")

const Brio = require("Brio")
const InputKeyMapList = require("InputKeyMapList")
const Maid = require("Maid")
const Observable = require("Observable")
const ObservableList = require("ObservableList")
const Rx = require("Rx")
const RxBrioUtils = require("RxBrioUtils")
const ServiceBag = require("ServiceBag")
const t = require("t")

const InputKeyMapRegistryServiceShared = {}
InputKeyMapRegistryServiceShared.ServiceName = "InputKeyMapRegistryServiceShared"

export type InputKeyMapRegistryServiceShared = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_providerLookupByName: { [string]: any },
		_providersList: ObservableList.ObservableList<any>,
	},
	{} :: typeof({ __index = InputKeyMapRegistryServiceShared })
))

function InputKeyMapRegistryServiceShared.Init(
	self: InputKeyMapRegistryServiceShared,
	serviceBag: ServiceBag.ServiceBag
): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()
	self._providerLookupByName = {}

	self._providersList = ObservableList.new()
	self._maid:GiveTask(self._providersList)

	self._maid:GiveTask((self._providersList:ObserveItemsBrio() :: any):Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		const maid = brio:ToMaid()
		const provider = brio:GetValue()
		const providerName = provider:GetProviderName()

		if self._providerLookupByName[providerName] then
			error(string.format("Already have a provider with name %q", providerName))
		end

		self._providerLookupByName[providerName] = provider

		maid:GiveTask(function()
			if self._providerLookupByName[providerName] == provider then
				self._providerLookupByName[providerName] = nil
			end
		end)
	end))
end

--[=[
	Registers a provider with the registry.

	@within InputKeyMapRegistryServiceShared
	@param provider any
	@return () -> ()
]=]
function InputKeyMapRegistryServiceShared.RegisterProvider(
	self: InputKeyMapRegistryServiceShared,
	provider: any
): () -> ()
	assert(provider, "Bad provider")
	assert(self._providersList, "Not initialized")

	return self._providersList:Add(provider)
end

--[=[
	Observes providers as a Brio stream.

	@within InputKeyMapRegistryServiceShared
	@return Observable<Brio<any>>
]=]
function InputKeyMapRegistryServiceShared.ObserveProvidersBrio(
	self: InputKeyMapRegistryServiceShared
): Observable.Observable<Brio.Brio<any>>
	return self._providersList:ObserveItemsBrio()
end

--[=[
	Observes all InputKeyMapLists from registered providers as a Brio stream.

	@within InputKeyMapRegistryServiceShared
	@return Observable<Brio<InputKeyMapList>>
]=]
function InputKeyMapRegistryServiceShared.ObserveInputKeyMapListsBrio(self: InputKeyMapRegistryServiceShared): Observable.Observable<
	Brio.Brio<InputKeyMapList.InputKeyMapList>
>
	return (self:ObserveProvidersBrio() :: any):Pipe({
		RxBrioUtils.flatMapBrio(function(provider): any
			return provider:ObserveInputKeyMapListsBrio()
		end),
	})
end

--[=[
	Gets a registered provider by name.

	@within InputKeyMapRegistryServiceShared
	@param providerName string
	@return any
]=]
function InputKeyMapRegistryServiceShared.GetProvider(self: InputKeyMapRegistryServiceShared, providerName: string): any
	assert(t.string(providerName), "Bad providerName")

	return self._providerLookupByName[providerName]
end

--[=[
	Observes an InputKeyMapList by provider name and list name.

	@within InputKeyMapRegistryServiceShared
	@param providerName any
	@param inputKeyMapListName any
	@return Observable<InputKeyMapList?>
]=]
function InputKeyMapRegistryServiceShared.ObserveInputKeyMapList(
	self: InputKeyMapRegistryServiceShared,
	providerName: any,
	inputKeyMapListName: any
): Observable.Observable<
	InputKeyMapList.InputKeyMapList?
>
	assert(providerName, "Bad providerName")
	assert(inputKeyMapListName, "Bad inputKeyMapListName")

	return (Rx.combineLatest({
		providerName = providerName,
		inputKeyMapListName = inputKeyMapListName,
	}) :: any):Pipe({
		Rx.map(function(state: any): any
			if not (type(state.inputKeyMapListName) == "string" and type(state.providerName) == "string") then
				return nil
			end

			const found = self:FindInputKeyMapList(state.providerName, state.inputKeyMapListName)
			if found then
				return found
			end

			warn(
				string.format(
					"[InputKeyMapRegistryServiceShared.ObserveInputKeyMapList] - Bad inputKey name %q\n%s",
					tostring(state.providerName),
					tostring(state.inputKeyMapListName)
				)
			)

			return nil
		end),
	})
end

--[=[
	Finds an InputKeyMapList by provider name and list name.

	@within InputKeyMapRegistryServiceShared
	@param providerName string
	@param inputKeyMapListName string
	@return InputKeyMapList?
]=]
function InputKeyMapRegistryServiceShared.FindInputKeyMapList(
	self: InputKeyMapRegistryServiceShared,
	providerName: string,
	inputKeyMapListName: string
): InputKeyMapList.InputKeyMapList?
	assert(t.string(providerName), "Bad providerName")
	assert(t.string(inputKeyMapListName), "Bad inputKeyMapListName")

	if not RunService:IsRunning() then
		return nil
	end

	assert(self._providersList, "Not initialized")

	for _, provider in self._providerLookupByName do
		if provider:GetProviderName() == providerName then
			const found = provider:FindInputKeyMapList(inputKeyMapListName)
			if found then
				return found
			end
		end
	end

	return nil
end

function InputKeyMapRegistryServiceShared.Destroy(self: InputKeyMapRegistryServiceShared): ()
	self._maid:DoCleaning()
end

return InputKeyMapRegistryServiceShared
