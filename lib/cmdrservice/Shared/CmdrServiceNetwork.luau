--!strict
--[=[
	Replicates table-defined commands from [CmdrService] to [CmdrServiceClient].

	Cmdr normally replicates a command by reparenting its definition ModuleScript
	into ReplicatedStorage, which only works if the definition is a module in the
	first place. [CmdrService.RegisterCommand] takes a plain table instead, so the
	definition is sent over the wire here.

	The client asks with `commandsRequested` once its registry is live, because a
	packet sent before that would be dropped. The server answers that player with
	everything it has, and broadcasts anything registered afterwards. Registering
	the same command twice is harmless -- Cmdr replaces by name.

	The `Run` function never appears here. It is stripped server-side, since a
	definition carrying a Run executes on whatever machine holds it, and a client
	holding one would run the command itself instead of asking the server.

	@network CmdrServiceNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("CmdrService", function()
	return {
		packets = {
			-- Client -> server. Carries nothing: the sender is the whole message.
			commandsRequested = ByteNet.definePacket({
				value = ByteNet.nothing,
			}),

			commandsReplicated = ByteNet.definePacket({
				value = ByteNet.array(ByteNet.struct({
					metadata = ByteNet.buff,
					properties = ByteNet.unknown,
				})),
			}),
		},
	}
end))
