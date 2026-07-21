--!strict
--[=[
	Client side utility helpers for observing input modes for the current client.

	@util InputKeyMapListUtils
]=]

const require = require("../../Loader").load()

const InputKeyMap = require("InputKeyMap")
const InputKeyMapList = require("InputKeyMapList")
const InputModeType = require("InputModeType")
const InputModeTypeSelector = require("InputModeTypeSelector")
const InputTypeUtils = require("InputTypeUtils")
const Maid = require("Maid")
const Observable = require("Observable")
const Rx = require("Rx")
const ServiceBag = require("ServiceBag")
const t = require("t")

const InputKeyMapListUtils = {}

--[=[
	Observes the input enums list.

	@within InputKeyMapListUtils
	@param inputKeyMapList InputKeyMapList
	@param serviceBag ServiceBag
	@return InputModeTypeSelector
]=]
function InputKeyMapListUtils.getNewInputModeTypeSelector(
	inputKeyMapList: InputKeyMapList.InputKeyMapList,
	serviceBag: ServiceBag.ServiceBag
): InputModeTypeSelector.InputModeTypeSelector
	assert(InputKeyMapList.isInputKeyMapList(inputKeyMapList), "Bad inputKeyMapList")
	assert(t.table(serviceBag), "Bad serviceBag")

	return InputModeTypeSelector.fromObservableBrio(serviceBag, inputKeyMapList:ObserveInputModesTypesBrio())
end

--[=[
	Observes the input types for the active input map.

	@within InputKeyMapListUtils
	@param inputKeyMapList InputKeyMapList
	@param serviceBag ServiceBag
	@return Observable<InputKeyMap?>
]=]
function InputKeyMapListUtils.observeActiveInputKeyMap(
	inputKeyMapList: InputKeyMapList.InputKeyMapList,
	serviceBag: ServiceBag.ServiceBag
): Observable.Observable<InputKeyMap.InputKeyMap?>
	assert(InputKeyMapList.isInputKeyMapList(inputKeyMapList), "Bad inputKeyMapList")
	assert(t.table(serviceBag), "Bad serviceBag")

	return (InputKeyMapListUtils.observeActiveInputModeType(inputKeyMapList, serviceBag) :: any):Pipe({
		Rx.switchMap(function(activeInputModeType): any
			if activeInputModeType then
				return inputKeyMapList:ObserveInputKeyMapForInputMode(activeInputModeType)
			else
				return Rx.of(nil)
			end
		end),
	}) :: any
end

--[=[
	Observes the input types for the active input map.

	@within InputKeyMapListUtils
	@param inputKeyMapList InputKeyMapList
	@param serviceBag ServiceBag
	@return Observable<{ InputType }?>
]=]
function InputKeyMapListUtils.observeActiveInputTypesList(
	inputKeyMapList: InputKeyMapList.InputKeyMapList,
	serviceBag: ServiceBag.ServiceBag
): Observable.Observable<{ InputTypeUtils.InputType }?>
	assert(InputKeyMapList.isInputKeyMapList(inputKeyMapList), "Bad inputKeyMapList")
	assert(t.table(serviceBag), "Bad serviceBag")

	return (InputKeyMapListUtils.observeActiveInputKeyMap(inputKeyMapList, serviceBag) :: any):Pipe({
		Rx.switchMap(function(activeInputMap): any
			if activeInputMap then
				return activeInputMap:ObserveInputTypesList()
			else
				return Rx.of(nil)
			end
		end) :: any,
		Rx.distinct() :: any,
	}) :: any
end

--[=[
	Observes the active input mode currently selected.

	@within InputKeyMapListUtils
	@param inputKeyMapList InputKeyMapList
	@param serviceBag ServiceBag
	@return Observable<InputModeType?>
]=]
function InputKeyMapListUtils.observeActiveInputModeType(
	inputKeyMapList: InputKeyMapList.InputKeyMapList,
	serviceBag: ServiceBag.ServiceBag
): Observable.Observable<InputModeType.InputModeType?>
	assert(InputKeyMapList.isInputKeyMapList(inputKeyMapList), "Bad inputKeyMapList")
	assert(t.table(serviceBag), "Bad serviceBag")

	return Observable.new((function(sub: any)
		const maid = Maid.new()

		const selector = maid:Add(InputKeyMapListUtils.getNewInputModeTypeSelector(inputKeyMapList, serviceBag))

		maid:GiveTask(selector.Changed:Connect(function()
			sub:Fire(selector.Value)
		end))
		sub:Fire(selector.Value)

		return maid
	end) :: any) :: any
end

return InputKeyMapListUtils
