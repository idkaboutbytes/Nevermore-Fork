--!strict
--[=[
	Input-mode values exposed on Player attributes.

	@class PlayerInputModeTypes
]=]

const require = require("../../Loader").load()

const Enums = require("Enums")

export type PlayerInputModeType = "gamepad" | "keyboard" | "touch"

return Enums.new({
	GAMEPAD = "gamepad" :: "gamepad",
	KEYBOARD = "keyboard" :: "keyboard",
	TOUCH = "touch" :: "touch",
})
