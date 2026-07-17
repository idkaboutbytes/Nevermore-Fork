--!strict
--[=[
    @utils CmdrServiceUtils
]=]

const require = require("../../Loader").load()

const ServiceBag = require("ServiceBag")
const t = require("t")

const CmdrServiceUtils = {}

--> Types

export type CommandArgument = {
	Type: string,
	Name: string,
	Description: string?,
	Optional: boolean?,
	Default: any?,
}

export type CommandDefinition = {
	Name: string,
	Description: string?,
	Group: any?,
	Aliases: { string }?,
	AutoExec: { string }?,
	Args: { CommandArgument }?,
	Run: (...any) -> ...any,
}

--> Constants

const assertCommandDefinition = t.interface({
	Name = t.string,
	Description = t.optional(t.string),
	Aliases = t.optional(t.array(t.string)),
	AutoExec = t.optional(t.array(t.string)),
	Args = t.optional(t.table),
	Run = t.callback,
})

-- Everything Cmdr accepts on a definition, minus Run. ClientRun and Data are
-- absent on purpose: both are functions the client would need to hold, and a
-- function cannot be sent over a remote.
const REPLICATED_COMMAND_KEYS = table.freeze({ "Name", "Aliases", "AutoExec", "Description", "Args", "Group" })

const function assertNoFunctions(value: any, path: string)
	if type(value) == "function" then
		error(
			`Cannot replicate command field {path}: it is a function. Register this command as a module with CmdrService:RegisterCommandsIn instead.`,
			0
		)
	end

	if type(value) ~= "table" then
		return
	end

	for key, entry in value do
		assertNoFunctions(entry, `{path}.{tostring(key)}`)
	end
end

--[=[
    Gets the ServiceBag within Context:GetStore

    @within CmdrServiceUtils
    @param context any
    @returns ServiceBag.ServiceBag
]=]
function CmdrServiceUtils.getServiceBag(context: any): ServiceBag.ServiceBag
	return context:GetStore("ServiceBag").ServiceBag
end

--[=[
    Writes the ServiceBag into the Context's store

    @within CmdrServiceUtils
    @param context any
]=]
function CmdrServiceUtils.writeServiceBagInContext(context: any, serviceBag: ServiceBag.ServiceBag)
	const store = context:GetStore("ServiceBag")
	store.ServiceBag = serviceBag
end

--[=[
    Returns the part of a command definition that is safe to send to clients: the
    same definition, without its `Run`.

    Stripping Run is the whole point. Cmdr runs a command on whichever machine
    holds a definition with a Run in it, so a client given the real definition
    would execute the command itself rather than asking the server to.

    Errors if anything left over is a function -- a remote cannot carry one, and
    ClientRun, Data, and a function-valued Args or Type all need the module-based
    path instead.

    @within CmdrServiceUtils
    @param definition CommandDefinition
    @return CommandDefinition
]=]
function CmdrServiceUtils.getReplicatedCommand(definition: CommandDefinition): CommandDefinition
	assert(assertCommandDefinition(definition))

	const replicated = {}
	for _, key in REPLICATED_COMMAND_KEYS do
		const value = (definition :: any)[key]

		if value ~= nil then
			assertNoFunctions(value, key)
			replicated[key] = value
		end
	end

	return replicated :: any
end

return CmdrServiceUtils
