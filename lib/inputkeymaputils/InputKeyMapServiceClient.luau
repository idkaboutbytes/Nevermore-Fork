--!strict
--[=[
	Client service for input key map resolution and translation setup.

	@class InputKeyMapServiceClient
	@client
]=]

const require = require("../Loader").load()

const InputKeyMapList = require("InputKeyMapList")
const InputKeyMapRegistryServiceShared = require("InputKeyMapRegistryServiceShared")
const InputKeyMapTranslator = require("InputKeyMapTranslator")
const InputModeServiceClient = require("InputModeServiceClient")
const Maid = require("Maid")
const PseudoLocalize = require("PseudoLocalize")
const ServiceBag = require("ServiceBag")
const t = require("t")

const InputKeyMapServiceClient = {}
InputKeyMapServiceClient.ServiceName = "InputKeyMapServiceClient"

export type InputKeyMapServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_translator: any,
		_registryService: InputKeyMapRegistryServiceShared.InputKeyMapRegistryServiceShared,
		_inputModeServiceClient: InputModeServiceClient.InputModeServiceClient,
	},
	{} :: typeof({ __index = InputKeyMapServiceClient })
))

function InputKeyMapServiceClient.Init(self: InputKeyMapServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._maid = Maid.new()

	self._inputModeServiceClient = self._serviceBag:GetService(InputModeServiceClient)
	self._translator = self._serviceBag:GetService(InputKeyMapTranslator)
	self._registryService = self._serviceBag:GetService(InputKeyMapRegistryServiceShared)

	self:_ensureLocalizationEntries()
end

--[=[
	Finds an InputKeyMapList by provider name and list name.

	@within InputKeyMapServiceClient
	@param providerName string
	@param listName string
	@return InputKeyMapList?
]=]
function InputKeyMapServiceClient.FindInputKeyMapList(
	self: InputKeyMapServiceClient,
	providerName: string,
	listName: string
): InputKeyMapList.InputKeyMapList?
	assert(t.string(providerName), "Bad providerName")
	assert(t.string(listName), "Bad listName")

	return self._registryService:FindInputKeyMapList(providerName, listName)
end

function InputKeyMapServiceClient._ensureLocalizationEntries(self: InputKeyMapServiceClient): ()
	self._maid:GiveTask(self._registryService:ObserveInputKeyMapListsBrio():Subscribe(function(brio)
		if brio:IsDead() then
			return
		end

		const inputKeyMapList = brio:GetValue()
		const text = inputKeyMapList:GetBindingName()
		const localizationTable = self._translator:GetLocalizationTable()
		const key = inputKeyMapList:GetBindingTranslationKey()
		const source = text
		const context = string.format("InputKeyMapServiceClient.%s", inputKeyMapList:GetListName())
		const localeId = "en"
		const value = text

		localizationTable:SetEntryValue(key, source, context, localeId, value)
		localizationTable:SetEntryValue(
			key,
			source,
			context,
			PseudoLocalize.getDefaultPseudoLocaleId(),
			PseudoLocalize.pseudoLocalize(value)
		)
	end))
end

function InputKeyMapServiceClient.Destroy(self: InputKeyMapServiceClient): ()
	self._maid:DoCleaning()
end

return InputKeyMapServiceClient
