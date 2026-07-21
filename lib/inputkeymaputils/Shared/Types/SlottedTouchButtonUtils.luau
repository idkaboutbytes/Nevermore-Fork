--!strict
--[=[
	Utility functions for working with slotted touch buttons.

	@util SlottedTouchButtonUtils
]=]

const require = require("../../../Loader").load()

const InputModeType = require("InputModeType")
const t = require("t")

export type SlottedTouchButtonData = {
	slotId: string,
	inputModeType: InputModeType.InputModeType,
}

const SlottedTouchButtonUtils = {}

--[=[
	Returns true if the input type is a slotted touch button.

	@within SlottedTouchButtonUtils
	@param inputType any
	@return boolean
]=]
function SlottedTouchButtonUtils.isSlottedTouchButton(inputType: any): boolean
	return type(inputType) == "table" and inputType.type == "SlottedTouchButton" and t.string(inputType.slotId)
end

--[=[
	Creates a slotted touch button.

	@within SlottedTouchButtonUtils
	@param slotId string
	@return { type: "SlottedTouchButton", slotId: string }
]=]
function SlottedTouchButtonUtils.createSlottedTouchButton(
	slotId: string
): { type: "SlottedTouchButton", slotId: string }
	assert(t.string(slotId), "Bad slotId")

	return {
		type = "SlottedTouchButton",
		slotId = slotId,
	}
end

--[=[
	Creates slotted touch button data.

	@within SlottedTouchButtonUtils
	@param slotId string
	@param inputModeType InputModeType
	@return SlottedTouchButtonData
]=]
function SlottedTouchButtonUtils.createTouchButtonData(
	slotId: string,
	inputModeType: InputModeType.InputModeType
): SlottedTouchButtonData
	assert(t.string(slotId), "Bad slotId")

	return {
		slotId = slotId,
		inputModeType = inputModeType,
	}
end

--[=[
	Gets slotted touch button data for an inputKeyMapList.

	@within SlottedTouchButtonUtils
	@param inputKeyMapList any
	@return { SlottedTouchButtonData }
]=]
function SlottedTouchButtonUtils.getSlottedTouchButtonData(inputKeyMapList: any): { SlottedTouchButtonData }
	assert(t.table(inputKeyMapList), "Bad inputKeyMapList")

	const slottedTouchButtons: { SlottedTouchButtonData } = {}

	for _, inputKeyMap: any in inputKeyMapList:GetInputKeyMaps() do
		for _, touchButtonData in inputKeyMap:GetInputTypesList() do
			if SlottedTouchButtonUtils.isSlottedTouchButton(touchButtonData) then
				const slottedButtonData = touchButtonData :: any
				table.insert(
					slottedTouchButtons,
					SlottedTouchButtonUtils.createTouchButtonData(
						slottedButtonData.slotId,
						inputKeyMap:GetInputModeType()
					)
				)
			end
		end
	end

	return slottedTouchButtons
end

return SlottedTouchButtonUtils
