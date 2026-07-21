--!strict
--[=[
	Utility functions to configure ProximityPrompts based upon input key maps.

	@util ProximityPromptInputUtils
]=]

const require = require("../../Loader").load()

const InputKeyMap = require("InputKeyMap")
const InputKeyMapList = require("InputKeyMapList")
const InputModeType = require("InputModeType")
const InputModeTypes = require("InputModeTypes")
const InputTypeUtils = require("InputTypeUtils")
const SlottedTouchButtonUtils = require("SlottedTouchButtonUtils")
const t = require("t")

const ProximityPromptInputUtils = {}

--[=[
	Creates an InputKeyMapList from a ProximityPrompt.

	@within ProximityPromptInputUtils
	@param prompt ProximityPrompt
	@return InputKeyMapList
]=]
function ProximityPromptInputUtils.newInputKeyMapFromPrompt(prompt: ProximityPrompt): InputKeyMapList.InputKeyMapList
	assert(t.instanceIsA("ProximityPrompt")(prompt), "Bad prompt")

	return InputKeyMapList.new("custom", {
		InputKeyMap.new(InputModeTypes.Gamepads, { prompt.GamepadKeyCode }),
		InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { prompt.KeyboardKeyCode }),
		InputKeyMap.new(InputModeTypes.Touch, { SlottedTouchButtonUtils.createSlottedTouchButton("primary1") }),
	}, {
		bindingName = prompt.ActionText,
		rebindable = false,
	})
end

--[=[
	Sets the key codes for a ProximityPrompt to match an InputKeyMapList.

	@within ProximityPromptInputUtils
	@param prompt ProximityPrompt
	@param inputKeyMapList InputKeyMapList
]=]
function ProximityPromptInputUtils.configurePromptFromInputKeyMap(
	prompt: ProximityPrompt,
	inputKeyMapList: InputKeyMapList.InputKeyMapList
): ()
	assert(t.instanceIsA("ProximityPrompt")(prompt), "Bad prompt")
	assert(InputKeyMapList.isInputKeyMapList(inputKeyMapList), "Bad inputKeyMapList")

	const keyboard = ProximityPromptInputUtils.getFirstInputKeyCode(inputKeyMapList, InputModeTypes.KeyboardAndMouse)
	const gamepad = ProximityPromptInputUtils.getFirstInputKeyCode(inputKeyMapList, InputModeTypes.Gamepads)

	if keyboard then
		prompt.KeyboardKeyCode = keyboard
	end

	if gamepad then
		prompt.GamepadKeyCode = gamepad
	end
end

--[=[
	Picks the first KeyCode that matches the InputModeType.

	@within ProximityPromptInputUtils
	@param inputKeyMapList InputKeyMapList
	@param inputModeType InputModeType
	@return KeyCode?
]=]
function ProximityPromptInputUtils.getFirstInputKeyCode(
	inputKeyMapList: InputKeyMapList.InputKeyMapList,
	inputModeType: InputModeType.InputModeType
): Enum.KeyCode?
	assert(InputKeyMapList.isInputKeyMapList(inputKeyMapList), "Bad inputKeyMapList")
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")

	const inputTypesForInputMode: { InputTypeUtils.InputType } = inputKeyMapList:GetInputTypesList(inputModeType)
	for _, entry in inputTypesForInputMode do
		if typeof(entry) == "EnumItem" and entry.EnumType == Enum.KeyCode then
			return entry :: any
		end
	end

	return nil
end

return ProximityPromptInputUtils
