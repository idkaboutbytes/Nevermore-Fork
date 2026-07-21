--!strict
--[=[
	List of InputKeyMaps for different input modes (Keyboard, Gamepad, Touch, etc.).

	@class InputKeyMapList
]=]

const require = require("../../Loader").load()

const Brio = require("Brio")
const InputChordUtils = require("InputChordUtils")
const InputKeyMap = require("InputKeyMap")
const InputModeType = require("InputModeType")
const InputTypeUtils = require("InputTypeUtils")
const Maid = require("Maid")
const Observable = require("Observable")
const ObservableCountingMap = require("ObservableCountingMap")
const ObservableMap = require("ObservableMap")
const RxBrioUtils = require("RxBrioUtils")
const StateStack = require("StateStack")
const ValueObject = require("ValueObject")
const t = require("t")

export type InputKeyMapListOptions = {
	bindingName: string?,
	rebindable: boolean?,
}

const InputKeyMapList = {}
InputKeyMapList.ClassName = "InputKeyMapList"
InputKeyMapList.__index = InputKeyMapList

export type InputKeyMapList = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_listName: string,
		_bindingName: ValueObject.ValueObject<string>,
		_rebindable: ValueObject.ValueObject<boolean>,
		_inputModeTypeToInputKeyMap: ObservableMap.ObservableMap<InputModeType.InputModeType, InputKeyMap.InputKeyMap>,
		_inputTypesForBinding: ObservableCountingMap.ObservableCountingMap<InputTypeUtils.InputType>?,
		_isTapInWorld: StateStack.StateStack<boolean>?,
		_isRobloxTouchButton: StateStack.StateStack<boolean>?,
	},
	{} :: typeof({ __index = InputKeyMapList })
))

--[=[
	Returns true if the value is an InputKeyMapList.

	@within InputKeyMapList
	@param value any
	@return boolean
]=]
function InputKeyMapList.isInputKeyMapList(value: any): boolean
	return type(value) == "table" and value.ClassName == "InputKeyMapList"
end

function InputKeyMapList.new(
	listName: string,
	inputKeyMaps: { InputKeyMap.InputKeyMap },
	options: InputKeyMapListOptions?
): InputKeyMapList
	assert(t.string(listName) and listName ~= "", "Bad listName")
	assert(t.table(inputKeyMaps), "Bad inputKeyMaps")

	const self = setmetatable({}, InputKeyMapList) :: InputKeyMapList

	self._maid = Maid.new()
	self._listName = listName

	const opts = options or {}
	self._bindingName = self._maid:Add(ValueObject.new(opts.bindingName or listName, "string"))
	self._rebindable =
		self._maid:Add(ValueObject.new(if opts.rebindable ~= nil then opts.rebindable else false, "boolean"))

	self._inputModeTypeToInputKeyMap = self._maid:Add(ObservableMap.new())

	for _, inputKeyMap in inputKeyMaps do
		assert(InputKeyMap.isInputKeyMap(inputKeyMap), "Bad inputKeyMap")
		self:AddInputKeyMap(inputKeyMap)
	end

	return self
end

--[=[
	Adds an input key map to this list.

	@within InputKeyMapList
	@param inputKeyMap InputKeyMap
]=]
function InputKeyMapList.AddInputKeyMap(self: InputKeyMapList, inputKeyMap: InputKeyMap.InputKeyMap): ()
	assert(InputKeyMap.isInputKeyMap(inputKeyMap), "Bad inputKeyMap")

	const keyModeType = inputKeyMap:GetInputModeType()
	if self._inputModeTypeToInputKeyMap:Get(keyModeType) then
		error(string.format("Already registered key mode type %q", tostring(keyModeType)))
	end

	self._maid:GiveTask(inputKeyMap)
	self._inputModeTypeToInputKeyMap:Set(keyModeType, inputKeyMap)
end

--[=[
	Gets the name of this list.

	@within InputKeyMapList
	@return string
]=]
function InputKeyMapList.GetListName(self: InputKeyMapList): string
	return self._listName
end

--[=[
	Gets the translation key for the binding.

	@within InputKeyMapList
	@return string
]=]
function InputKeyMapList.GetBindingTranslationKey(self: InputKeyMapList): string
	return string.format("input_binding_%s", string.lower(self._listName))
end

--[=[
	Sets whether this key map is rebindable.

	@within InputKeyMapList
	@param rebindable boolean
]=]
function InputKeyMapList.SetRebindable(self: InputKeyMapList, rebindable: boolean): ()
	assert(t.boolean(rebindable), "Bad rebindable")
	self._rebindable.Value = rebindable
end

--[=[
	Returns true if rebindable.

	@within InputKeyMapList
	@return boolean
]=]
function InputKeyMapList.IsRebindable(self: InputKeyMapList): boolean
	return self._rebindable.Value
end

--[=[
	Observes rebindable state.

	@within InputKeyMapList
	@return Observable<boolean>
]=]
function InputKeyMapList.ObserveIsRebindable(self: InputKeyMapList): Observable.Observable<boolean>
	return self._rebindable:Observe()
end

--[=[
	Sets the user-facing binding name.

	@within InputKeyMapList
	@param bindingName string
]=]
function InputKeyMapList.SetBindingName(self: InputKeyMapList, bindingName: string): ()
	assert(t.string(bindingName), "Bad bindingName")
	self._bindingName.Value = bindingName
end

--[=[
	Gets the user-facing binding name.

	@within InputKeyMapList
	@return string
]=]
function InputKeyMapList.GetBindingName(self: InputKeyMapList): string
	return self._bindingName.Value
end

--[=[
	Observes the binding name.

	@within InputKeyMapList
	@return Observable<string>
]=]
function InputKeyMapList.ObserveBindingName(self: InputKeyMapList): Observable.Observable<string>
	return self._bindingName:Observe()
end

--[=[
	Gets all registered InputKeyMaps.

	@within InputKeyMapList
	@return { InputKeyMap }
]=]
function InputKeyMapList.GetInputKeyMaps(self: InputKeyMapList): { InputKeyMap.InputKeyMap }
	const list: { InputKeyMap.InputKeyMap } = {}
	for _, inputKeyMap in self._inputModeTypeToInputKeyMap:GetMap() do
		table.insert(list, inputKeyMap)
	end
	return list
end

--[=[
	Finds the InputKeyMap for a given InputModeType.

	@within InputKeyMapList
	@param inputModeType InputModeType
	@return InputKeyMap?
]=]
function InputKeyMapList.FindInputKeyMapForInputMode(
	self: InputKeyMapList,
	inputModeType: InputModeType.InputModeType
): InputKeyMap.InputKeyMap?
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	return self._inputModeTypeToInputKeyMap:Get(inputModeType)
end

--[=[
	Observes the InputKeyMap for a given InputModeType.

	@within InputKeyMapList
	@param inputModeType InputModeType
	@return Observable<InputKeyMap?>
]=]
function InputKeyMapList.ObserveInputKeyMapForInputMode(
	self: InputKeyMapList,
	inputModeType: InputModeType.InputModeType
): Observable.Observable<InputKeyMap.InputKeyMap?>
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")
	return self._inputModeTypeToInputKeyMap:ObserveValueForKey(inputModeType)
end

--[=[
	Observes available InputModeTypes.

	@within InputKeyMapList
	@return Observable<Brio<InputModeType>>
]=]
function InputKeyMapList.ObserveInputModesTypesBrio(
	self: InputKeyMapList
): Observable.Observable<Brio.Brio<InputModeType.InputModeType>>
	return self._inputModeTypeToInputKeyMap:ObserveKeysBrio()
end

--[=[
	Gets input types for a given input mode type.

	@within InputKeyMapList
	@param inputModeType InputModeType
	@return { InputType }
]=]
function InputKeyMapList.GetInputTypesList(
	self: InputKeyMapList,
	inputModeType: InputModeType.InputModeType
): { InputTypeUtils.InputType }
	assert(InputModeType.isInputModeType(inputModeType), "Bad inputModeType")

	const inputKeyMap = self:FindInputKeyMapForInputMode(inputModeType)
	if inputKeyMap then
		return inputKeyMap:GetInputTypesList()
	else
		return {}
	end
end

--[=[
	Observes whether tap in world is active for this list.

	@within InputKeyMapList
	@return Observable<boolean>
]=]
function InputKeyMapList.ObserveIsTapInWorld(self: InputKeyMapList): Observable.Observable<boolean>
	self:_ensureInputTypesForBinding()
	return (self._isTapInWorld :: StateStack.StateStack<boolean>):Observe()
end

--[=[
	Observes whether Roblox touch button is active for this list.

	@within InputKeyMapList
	@return Observable<boolean>
]=]
function InputKeyMapList.ObserveIsRobloxTouchButton(self: InputKeyMapList): Observable.Observable<boolean>
	self:_ensureInputTypesForBinding()
	return (self._isRobloxTouchButton :: StateStack.StateStack<boolean>):Observe()
end

--[=[
	Observes input enums list (brio stream of keycodes/input types across all modes).

	@within InputKeyMapList
	@return Observable<Brio<InputType>>
]=]
function InputKeyMapList.ObserveInputEnumsListBrio(
	self: InputKeyMapList
): Observable.Observable<Brio.Brio<InputTypeUtils.InputType>>
	return (self:_ensureInputTypesForBinding():ObserveKeysBrio() :: any):Pipe({
		RxBrioUtils.where(function(value)
			return InputTypeUtils.isKnownInputType(value)
		end),
	})
end

function InputKeyMapList._ensureInputTypesForBinding(self: InputKeyMapList): ObservableCountingMap.ObservableCountingMap<
	InputTypeUtils.InputType
>
	if self._inputTypesForBinding then
		return self._inputTypesForBinding
	end

	const countingMap: ObservableCountingMap.ObservableCountingMap<InputTypeUtils.InputType> =
		self._maid:Add(ObservableCountingMap.new()) :: any
	self._inputTypesForBinding = countingMap
	self._isTapInWorld = self._maid:Add(StateStack.new(false, "boolean"))
	self._isRobloxTouchButton = self._maid:Add(StateStack.new(false, "boolean"))

	self._maid:GiveTask(
		self._inputModeTypeToInputKeyMap
			:ObserveValuesBrio()
			:Subscribe(function(brio: Brio.Brio<InputKeyMap.InputKeyMap>)
				if brio:IsDead() then
					return
				end

				const inputKeyMapMaid = brio:ToMaid()
				const inputKeyMap: InputKeyMap.InputKeyMap = brio:GetValue()

				inputKeyMapMaid:GiveTask(inputKeyMap:ObserveInputTypesList():Subscribe(function(inputTypes)
					const maid = Maid.new()

					for _, inputType in inputTypes do
						if typeof(inputType) == "EnumItem" then
							maid:GiveTask(countingMap:Add(inputType :: any))
						elseif InputTypeUtils.isTapInWorld(inputType) then
							maid:GiveTask((self._isTapInWorld :: StateStack.StateStack<boolean>):PushState(true))
						elseif InputTypeUtils.isRobloxTouchButton(inputType) then
							maid:GiveTask((self._isRobloxTouchButton :: StateStack.StateStack<boolean>):PushState(true))
						elseif InputChordUtils.isModifierInputChord(inputType) then
							maid:GiveTask(countingMap:Add((inputType :: any).keyCode))
						end
					end

					inputKeyMapMaid._current = maid
				end))
			end)
	)

	return self._inputTypesForBinding :: any
end

function InputKeyMapList.Destroy(self: InputKeyMapList): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return InputKeyMapList
