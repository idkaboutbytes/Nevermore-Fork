--!strict
--[=[
	Orchestrates InputKeyMap backend services on the server.

	@class InputKeyMapService
	@server
]=]

const require = require("../Loader").load()

const InputKeyMapRegistryServiceShared = require("InputKeyMapRegistryServiceShared")
const InputKeyMapTranslator = require("InputKeyMapTranslator")
const ServiceBag = require("ServiceBag")
const t = require("t")

const InputKeyMapService = {}
InputKeyMapService.ServiceName = "InputKeyMapService"
InputKeyMapService.ServerOnly = true

export type InputKeyMapService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_registryService: InputKeyMapRegistryServiceShared.InputKeyMapRegistryServiceShared,
		_translator: any,
	},
	{} :: typeof({ __index = InputKeyMapService })
))

function InputKeyMapService.Init(self: InputKeyMapService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")

	self._serviceBag = serviceBag
	self._registryService = self._serviceBag:GetService(InputKeyMapRegistryServiceShared)
	self._translator = self._serviceBag:GetService(InputKeyMapTranslator)
end

function InputKeyMapService.Destroy(self: InputKeyMapService): ()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return InputKeyMapService
