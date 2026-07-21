--!strict
--[=[
	Binds input mode type to actual key codes/types.

	@class InputKeyMap
]=]

const require = require("../../Loader").load()

const InputModeType = require("InputModeType")
const InputTypeUtils = require("InputTypeUtils")
const Maid = require("Maid")
const Observable = require("Observable")
const ValueObject = require("ValueObject")
const t = require("t")

const InputKeyMap = {}
InputKeyMap.ClassName = "InputKeyMap"
InputKeyMap.__index = InputKeyMap

export type InputKeyMap = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_inputModeType: InputModeType.InputModeType,
		_inputTypesList: ValueObject.ValueObject<{ InputTypeUtils.InputType }>,
	},
	{} :: typeof({ __index = InputKeyMap })
))

--[=[
	Returns true if the value is an InputKeyMap.

	@within InputKeyMap
	@param value any
	@return boolean
]=]
function InputKeyMap.isInputKeyMap(value: any): boolean
	return type(value) == "table" and value.ClassName == "InputKeyMap"
end

function InputKeyMap.new(
	inputModeType: InputModeType.InputModeType,
	inputTypesList: { InputTypeUtils.InputType }
): InputKeyMap
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	assert(t.table(inputTypesList), "Bad inputTypesList")

	const self = setmetatable({}, InputKeyMap) :: InputKeyMap

	self._maid = Maid.new()
	self._inputModeType = inputModeType
	self._inputTypesList = self._maid:Add(ValueObject.new(inputTypesList, "table"))

	return self
end

--[=[
	Gets the input mode type for this map.

	@within InputKeyMap
	@return InputModeType
]=]
function InputKeyMap.GetInputModeType(self: InputKeyMap): InputModeType.InputModeType
	return self._inputModeType
end

--[=[
	Gets the list of input types bound to this mode.

	@within InputKeyMap
	@return { InputType }
]=]
function InputKeyMap.GetInputTypesList(self: InputKeyMap): { InputTypeUtils.InputType }
	return self._inputTypesList.Value
end

--[=[
	Sets the list of input types.

	@within InputKeyMap
	@param inputTypesList { InputType }
]=]
function InputKeyMap.SetInputTypesList(self: InputKeyMap, inputTypesList: { InputTypeUtils.InputType }): ()
	assert(t.table(inputTypesList), "Bad inputTypesList")

	if InputTypeUtils.areInputTypesListsEquivalent(self._inputTypesList.Value, inputTypesList) then
		return
	end

	self._inputTypesList.Value = inputTypesList
end

--[=[
	Observes the list of input types.

	@within InputKeyMap
	@return Observable<{ InputType }>
]=]
function InputKeyMap.ObserveInputTypesList(self: InputKeyMap): Observable.Observable<{ InputTypeUtils.InputType }>
	return self._inputTypesList:Observe()
end

function InputKeyMap.Destroy(self: InputKeyMap): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return InputKeyMap
