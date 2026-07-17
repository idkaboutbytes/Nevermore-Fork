--!strict
--[=[
    @utils CmdrServiceUtils
]=]

const require = require("../../Loader").load()

const ServiceBag = require("ServiceBag")
const Squash = require("Squash")
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
	Group: string?,
	Aliases: { string }?,
	AutoExec: { string }?,
	Args: { CommandArgument }?,
	Run: (...any) -> ...any,
}

export type CommandPacket = {
	metadata: buffer,
	properties: { [string]: any },
}

--> Constants

const assertCommandDefinition = t.interface({
	Name = t.string,
	Description = t.optional(t.string),
	Group = t.optional(t.string),
	Aliases = t.optional(t.array(t.string)),
	AutoExec = t.optional(t.array(t.string)),
	Args = t.optional(t.table),
	Run = t.callback,
})

-- Everything Cmdr accepts on a definition, minus Run. ClientRun and Data are
-- absent on purpose: both are functions the client would need to hold, and a
-- function cannot be sent over a remote.
const REPLICATED_COMMAND_KEYS = table.freeze({ "Name", "Aliases", "AutoExec", "Description", "Args", "Group" })
const COMMAND_METADATA_SCHEMA = Squash.record({
	Name = Squash.string(),
	Group = Squash.opt(Squash.string()),
	Description = Squash.opt(Squash.string()),
})

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

--[=[
	Encodes the known string fields into a compact Squash buffer and leaves the
	remaining client-safe Cmdr properties as a generic table.

	@within CmdrServiceUtils
	@param definition CommandDefinition
	@return CommandPacket
]=]
function CmdrServiceUtils.serializeCommand(definition: CommandDefinition): CommandPacket
	const cursor = Squash.cursor()
	COMMAND_METADATA_SCHEMA.ser(cursor, {
		Name = definition.Name,
		Group = definition.Group,
		Description = definition.Description,
	})

	const properties = {}
	for _, key in REPLICATED_COMMAND_KEYS do
		if key ~= "Name" and key ~= "Group" and key ~= "Description" then
			const value = (definition :: any)[key]
			if value ~= nil then
				properties[key] = value
			end
		end
	end

	return {
		metadata = Squash.tobuffer(cursor),
		properties = properties,
	}
end

--[=[
	Reconstructs a Cmdr command definition from its compact network packet.

	@within CmdrServiceUtils
	@param packet CommandPacket
	@return CommandDefinition
]=]
function CmdrServiceUtils.deserializeCommand(packet: CommandPacket): CommandDefinition
	const metadata = COMMAND_METADATA_SCHEMA.des(Squash.frombuffer(packet.metadata))
	const definition = packet.properties

	definition.Name = metadata.Name
	definition.Group = metadata.Group
	definition.Description = metadata.Description

	return definition :: any
end

return CmdrServiceUtils
