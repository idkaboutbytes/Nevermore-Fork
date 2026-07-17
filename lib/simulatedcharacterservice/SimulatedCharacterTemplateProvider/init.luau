--!strict
--[=[
	Provides the client-rendered models used by SimulatedCharacterService.

	Place character Model templates beneath this ModuleScript or add template
	containers at runtime through TemplateProvider.AddTemplates.

	@class SimulatedCharacterTemplateProvider
]=]

const require = require("../Loader").load()

const TemplateProvider = require("TemplateProvider")

return TemplateProvider.new(script.Name, script)
