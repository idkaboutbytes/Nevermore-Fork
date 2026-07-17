--!strict
--[=[
	Replicates player data from [DataService] to [DataServiceClient].

	The client announces its listeners are live with `clientReady`; the server
	replies with that player's full data (`loaded`, hidden keys stripped) and then
	streams `updated` deltas. Server-authoritative: the client never writes, and
	the server never listens to `loaded`/`updated`, so a client firing them does
	nothing.

	Values are `unknown` because this store is generic. Pin down a schema and swap
	in precise types if you want the bandwidth back -- that is the point of ByteNet.

	@network DataStoreNetwork
]=]

const require = require("../../Loader").load()

const ByteNet = require("ByteNet")
const TableUtils = require("TableUtils")

return TableUtils.deepReadonly(ByteNet.defineNamespace("DataStore", function()
	return {
		packets = {
			profileLoaded = ByteNet.definePacket({
				value = ByteNet.buff,
			}),

			valueChanged = ByteNet.definePacket({
				value = ByteNet.struct({
					name = ByteNet.string,
					value = ByteNet.unknown,
				}),
			}),
		},
	}
end))
