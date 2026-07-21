--!strict
--[=[
	Constants for soft shutdown.

	@class SoftShutdownConstants
]=]

const require = require("../../Loader").load()

const TableUtils = require("TableUtils")

return TableUtils.deepReadonly({
	IS_SOFT_SHUTDOWN_LOBBY_ATTRIBUTE = "IsSoftShutdownLobby",
	IS_SOFT_SHUTDOWN_UPDATING_ATTRIBUTE = "IsSoftshutdownRebootingServers",
})
