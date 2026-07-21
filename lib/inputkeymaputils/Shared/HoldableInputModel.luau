--!strict
--[=[
	Model for handling held input states.

	@class HoldableInputModel
]=]

const require = require("../../Loader").load()

const Maid = require("Maid")
const Observable = require("Observable")
const Signal = require("Signal")
const StateStack = require("StateStack")
const ValueObject = require("ValueObject")
const t = require("t")

const HoldableInputModel = {}
HoldableInputModel.ClassName = "HoldableInputModel"
HoldableInputModel.__index = HoldableInputModel

export type HoldableInputModel = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_inputStateStack: StateStack.StateStack<boolean>,
		_isInputHeld: ValueObject.ValueObject<boolean>,
		InputHeldChanged: Observable.Observable<boolean>,
		InputTriggered: Signal.Signal<()>,
	},
	{} :: typeof({ __index = HoldableInputModel })
))

function HoldableInputModel.new(): HoldableInputModel
	const self = setmetatable({}, HoldableInputModel) :: HoldableInputModel

	self._maid = Maid.new()
	self._inputStateStack = self._maid:Add(StateStack.new(false, "boolean"))

	self._isInputHeld = self._maid:Add(ValueObject.new(false, "boolean"))
	self._isInputHeld:Observe():Subscribe(function(isHeld)
		self._inputStateStack:SetBaseState(isHeld)
	end)

	self.InputHeldChanged = self._inputStateStack:Observe()
	self.InputTriggered = self._maid:Add(Signal.new())

	return self
end

--[=[
	Sets whether the input is held.

	@within HoldableInputModel
	@param isHeld boolean
]=]
function HoldableInputModel.SetIsInputHeld(self: HoldableInputModel, isHeld: boolean): ()
	assert(t.boolean(isHeld), "Bad isHeld")
	self._isInputHeld.Value = isHeld
end

--[=[
	Fires the InputTriggered signal.

	@within HoldableInputModel
]=]
function HoldableInputModel.FireInputTriggered(self: HoldableInputModel): ()
	self.InputTriggered:Fire()
end

--[=[
	Pushes a held state override onto the state stack.

	@within HoldableInputModel
	@param isHeld boolean
	@return () -> ()
]=]
function HoldableInputModel.PushIsHeld(self: HoldableInputModel, isHeld: boolean): () -> ()
	assert(t.boolean(isHeld), "Bad isHeld")
	return self._inputStateStack:PushState(isHeld)
end

--[=[
	Returns true if the input is currently held.

	@within HoldableInputModel
	@return boolean
]=]
function HoldableInputModel.IsInputHeld(self: HoldableInputModel): boolean
	return self._inputStateStack:GetState()
end

--[=[
	Observes the held state of the input.

	@within HoldableInputModel
	@return Observable<boolean>
]=]
function HoldableInputModel.ObserveIsInputHeld(self: HoldableInputModel): Observable.Observable<boolean>
	return self._inputStateStack:Observe()
end

function HoldableInputModel.Destroy(self: HoldableInputModel): ()
	self._maid:DoCleaning()
	table.clear(self :: any)
	setmetatable(self :: any, nil)
end

return HoldableInputModel
