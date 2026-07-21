--!strict
--[=[
	Standardized data type to define an input chord, such as Ctrl+Z.

	@util InputChordUtils
]=]

const require = require("../../../Loader").load()

const EnumUtils = require("EnumUtils")
const t = require("t")

--[=[
	A modifier input chord data type that separates keyCode from modifier keys.

	@type ModifierInputChord { type: "ModifierInputChord", modifiers: { Enum.KeyCode }, keyCode: Enum.KeyCode }
	@within InputChordUtils
]=]
export type ModifierInputChord = {
	type: "ModifierInputChord",
	modifiers: { Enum.KeyCode },
	keyCode: Enum.KeyCode,
}

const InputChordUtils = {}

--[=[
	Checks if the data is a modifier input chord.

	@within InputChordUtils
	@param data any
	@return boolean
]=]
function InputChordUtils.isModifierInputChord(data: any): boolean
	return type(data) == "table"
		and data.type == "ModifierInputChord"
		and type(data.modifiers) == "table"
		and EnumUtils.isOfType(Enum.KeyCode, data.keyCode)
end

--[=[
	Creates a modifier input chord. This chord specifically separates the
	order such that the event only triggers when the keyCode is pressed, but
	also requires the modifier key to be down at the trigger point.

	@within InputChordUtils
	@param modifiers { Enum.KeyCode }
	@param keyCode Enum.KeyCode
	@return ModifierInputChord
]=]
function InputChordUtils.createModifierInputChord(
	modifiers: { Enum.KeyCode },
	keyCode: Enum.KeyCode
): ModifierInputChord
	assert(t.table(modifiers), "Bad modifiers")
	assert(EnumUtils.isOfType(Enum.KeyCode, keyCode), "Bad keyCode")

	return {
		type = "ModifierInputChord",
		modifiers = modifiers,
		keyCode = keyCode,
	}
end

return InputChordUtils
