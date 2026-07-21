--!strict
--[=[
	Centralizes input of keys. You can construct a new provider in a package
	and key bindings can be recovered from it.

	@class InputKeyMapListProvider
]=]

const require = require("../../Loader").load()

const RunService = game:GetService("RunService")

const InputKeyMapList = require("InputKeyMapList")
const InputKeyMapRegistryServiceShared = require("InputKeyMapRegistryServiceShared")
const Maid = require("Maid")
const ObservableList = require("ObservableList")
const ServiceBag = require("ServiceBag")
const t = require("t")

const InputKeyMapListProvider = {}
InputKeyMapListProvider.ClassName = "InputKeyMapListProvider"
InputKeyMapListProvider.ServiceName = "InputKeyMapListProvider"
InputKeyMapListProvider.__index = InputKeyMapListProvider

export type CreateDefaultsCallback = (self: InputKeyMapListProvider, serviceBag: ServiceBag.ServiceBag) -> ()
export type InputKeyMapListProvider = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_providerName: string,
		_createDefaults: CreateDefaultsCallback,
		_inputKeyMapLists: { [string]: InputKeyMapList.InputKeyMapList },
		_inputMapLists: ObservableList.ObservableList<InputKeyMapList.InputKeyMapList>,
	},
	{} :: typeof({ __index = InputKeyMapListProvider })
))

function InputKeyMapListProvider.new(
	providerName: string,
	createDefaults: CreateDefaultsCallback
): InputKeyMapListProvider
	assert(t.string(providerName), "Bad providerName")
	assert(t.callback(createDefaults), "Bad createDefaults")

	const self = setmetatable({}, InputKeyMapListProvider) :: InputKeyMapListProvider

	self._providerName = providerName
	self.ServiceName = providerName
	self._createDefaults = createDefaults

	return self
end

function InputKeyMapListProvider.Init(self: InputKeyMapListProvider, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()

	self:_ensureDefaultsInit()

	self._maid:GiveTask(self._serviceBag:GetService(InputKeyMapRegistryServiceShared):RegisterProvider(self))
end

function InputKeyMapListProvider.Start(_self: InputKeyMapListProvider): ()
	-- Connection phase
end

--[=[
	Gets this provider's name.

	@within InputKeyMapListProvider
	@return string
]=]
function InputKeyMapListProvider.GetProviderName(self: InputKeyMapListProvider): string
	return self._providerName
end

--[=[
	Gets an input key map list for the given name. Errors if not defined.

	@within InputKeyMapListProvider
	@param keyMapListName string
	@return InputKeyMapList
]=]
function InputKeyMapListProvider.GetInputKeyMapList(
	self: InputKeyMapListProvider,
	keyMapListName: string
): InputKeyMapList.InputKeyMapList
	assert(t.string(keyMapListName), "Bad keyMapListName")

	const keyMapList = self:FindInputKeyMapList(keyMapListName)
	if not keyMapList then
		error(string.format("Bad keyMapListName %q", tostring(keyMapListName)))
	end

	return keyMapList
end

--[=[
	Finds an input key map list for the given name.

	@within InputKeyMapListProvider
	@param keyMapListName string
	@return InputKeyMapList?
]=]
function InputKeyMapListProvider.FindInputKeyMapList(
	self: InputKeyMapListProvider,
	keyMapListName: string
): InputKeyMapList.InputKeyMapList?
	assert(t.string(keyMapListName), "Bad keyMapListName")

	if RunService:IsRunning() and not self._inputKeyMapLists then
		error("Not initialized, make sure to retrieve via serviceBag and init")
	end

	if not self._inputKeyMapLists then
		self._maid = Maid.new()
	end

	self:_ensureDefaultsInit()

	return self._inputKeyMapLists[keyMapListName]
end

--[=[
	Adds an InputKeyMapList to the provider.

	@within InputKeyMapListProvider
	@param inputKeyMapList InputKeyMapList
]=]
function InputKeyMapListProvider.Add(
	self: InputKeyMapListProvider,
	inputKeyMapList: InputKeyMapList.InputKeyMapList
): ()
	assert(InputKeyMapList.isInputKeyMapList(inputKeyMapList), "Bad inputKeyMapList")

	if self._inputKeyMapLists[inputKeyMapList:GetListName()] then
		error(string.format("Already added %q", inputKeyMapList:GetListName()))
	end

	self._inputKeyMapLists[inputKeyMapList:GetListName()] = inputKeyMapList
	self._maid:GiveTask(inputKeyMapList)
	self._maid:GiveTask(self._inputMapLists:Add(inputKeyMapList))
end

--[=[
	Observes InputKeyMapLists as a Brio stream.

	@within InputKeyMapListProvider
	@return Observable<Brio<InputKeyMapList>>
]=]
function InputKeyMapListProvider.ObserveInputKeyMapListsBrio(self: InputKeyMapListProvider): any
	return self._inputMapLists:ObserveItemsBrio()
end

function InputKeyMapListProvider._ensureDefaultsInit(self: InputKeyMapListProvider): ()
	if not self._inputKeyMapLists then
		self._inputMapLists = ObservableList.new()
		self._maid:GiveTask(self._inputMapLists)

		self._inputKeyMapLists = {}

		self._createDefaults(self, self._serviceBag)
	end
end

function InputKeyMapListProvider.Destroy(self: InputKeyMapListProvider): ()
	if self._maid then
		self._maid:DoCleaning()
	end

	self._inputKeyMapLists = {}
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return InputKeyMapListProvider
