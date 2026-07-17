--!strict
--!optimize 2
--[=[
	A lightweight server-authoritative simulated character.

	@class SimulatedCharacter
]=]

const Players = game:GetService("Players")

const require = require("../../Loader").load()

const Maid = require("Maid")
const MathUtils = require("MathUtils")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")
const SimulatedCharacterUtils = require("SimulatedCharacterUtils")

const SimulatedCharacter = {}
SimulatedCharacter.ClassName = "SimulatedCharacter"
SimulatedCharacter.__index = SimulatedCharacter

export type SimulatedCharacter = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_service: any,
		_id: number,
		_listIndex: number,
		_flockIndex: number,
		_flockSeparation: Vector2,
		_flockSteering: Vector2,
		_definition: SimulatedCharacterTypes.ResolvedCharacterDefinition,
		_position: Vector2,
		_groundY: number,
		_height: number,
		_yaw: number,
		_velocity: Vector2,
		_verticalVelocity: number,
		_mode: number,
		_stateStartedAt: number,
		_targetPlayer: Player?,
		_targetPosition: Vector2?,
		_destroyed: boolean,
	},
	SimulatedCharacter
))

function SimulatedCharacter.new(
	service: any,
	id: number,
	definition: SimulatedCharacterTypes.ResolvedCharacterDefinition,
	position: Vector2,
	groundY: number,
	yaw: number,
	ragdolled: boolean
): SimulatedCharacter
	const self: SimulatedCharacter = setmetatable({} :: any, SimulatedCharacter)
	self._maid = Maid.new()
	self._service = service
	self._id = id
	self._listIndex = 0
	self._flockIndex = 0
	self._flockSeparation = Vector2.zero
	self._flockSteering = Vector2.zero
	self._definition = definition
	self._position = position
	self._groundY = groundY
	self._height = 0
	self._yaw = yaw
	self._velocity = Vector2.zero
	self._verticalVelocity = 0
	self._mode = if ragdolled
		then SimulatedCharacterConstants.Modes.RAGDOLL
		else SimulatedCharacterConstants.Modes.KINEMATIC
	self._stateStartedAt = service:_getTime()
	self._targetPlayer = nil
	self._targetPosition = nil
	self._destroyed = false
	return self
end

--[=[
	Returns the character's numeric network id.

	@within SimulatedCharacter
	@return number
]=]
function SimulatedCharacter.GetId(self: SimulatedCharacter): number
	return self._id
end

--[=[
	Returns the character definition name.

	@within SimulatedCharacter
	@return string
]=]
function SimulatedCharacter.GetDefinitionName(self: SimulatedCharacter): string
	return self._definition.Name
end

--[=[
	Returns the current authoritative world CFrame.

	@within SimulatedCharacter
	@return CFrame
]=]
function SimulatedCharacter.GetCFrame(self: SimulatedCharacter): CFrame
	return SimulatedCharacterUtils.toCFrame(self._position.X, self._position.Y, self._groundY, self._height, self._yaw)
end

--[=[
	Returns the current X/Z simulation position.

	@within SimulatedCharacter
	@return Vector2
]=]
function SimulatedCharacter.GetPosition(self: SimulatedCharacter): Vector2
	return self._position
end

--[=[
	Returns the size of the lightweight authoritative hitbox. No physical Part is
	created or replicated for this hitbox.

	@within SimulatedCharacter
	@return Vector3
]=]
function SimulatedCharacter.GetHitboxSize(self: SimulatedCharacter): Vector3
	const diameter = self._definition.HitboxRadius * 2
	return Vector3.new(diameter, self._definition.HitboxHeight, diameter)
end

--[=[
	Moves toward an arbitrary X/Z destination using the navigation grid.

	@within SimulatedCharacter
	@param position Vector2 | Vector3
]=]
function SimulatedCharacter.MoveTo(self: SimulatedCharacter, position: Vector2 | Vector3)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	self._targetPlayer = nil
	self._targetPosition = SimulatedCharacterUtils.toPlanarPosition(position)
end

--[=[
	Chases a player's current character position. Characters chasing the same
	player share one flow field.

	@within SimulatedCharacter
	@param player Player
]=]
function SimulatedCharacter.Chase(self: SimulatedCharacter, player: Player)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(typeof(player) == "Instance" and player:IsA("Player"), "Bad player")
	self._targetPlayer = player
	self._targetPosition = nil
end

--[=[
	Stops kinematic movement without changing the current physical mode.

	@within SimulatedCharacter
]=]
function SimulatedCharacter.Stop(self: SimulatedCharacter)
	self._targetPlayer = nil
	self._targetPosition = nil
	if self._mode == SimulatedCharacterConstants.Modes.KINEMATIC then
		self._velocity = Vector2.zero
	end
end

--[=[
	Applies an authoritative knockback velocity.

	@within SimulatedCharacter
	@param velocity Vector3
]=]
function SimulatedCharacter.ApplyImpulse(self: SimulatedCharacter, velocity: Vector3)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(typeof(velocity) == "Vector3", "Bad velocity")

	self._velocity += Vector2.new(velocity.X, velocity.Z)
	self._verticalVelocity += velocity.Y
	if self._mode ~= SimulatedCharacterConstants.Modes.RAGDOLL then
		self:_setMode(SimulatedCharacterConstants.Modes.KNOCKBACK)
	else
		self._stateStartedAt = self._service:_getTime()
		self._service:_onCharacterStateChanged(self)
	end
end

--[=[
	Launches toward a world position using MathUtils' ballistic trajectory solver.

	@within SimulatedCharacter
	@param target Vector3
	@param speed number
	@param useHighArc boolean?
	@return boolean
]=]
function SimulatedCharacter.LaunchTowards(
	self: SimulatedCharacter,
	target: Vector3,
	speed: number,
	useHighArc: boolean?
): boolean
	assert(typeof(target) == "Vector3", "Bad target")
	assert(type(speed) == "number" and speed > 0, "Bad speed")
	assert(useHighArc == nil or type(useHighArc) == "boolean", "Bad useHighArc")

	local lowTrajectory, highTrajectory, fallbackTrajectory =
		MathUtils.computeTrajectory(self:GetCFrame().Position, target, speed, workspace.Gravity)
	const trajectory = if useHighArc
		then highTrajectory or lowTrajectory
		else lowTrajectory or highTrajectory or fallbackTrajectory
	if not trajectory then
		return false
	end

	self:ApplyImpulse(trajectory)
	return true
end

--[=[
	Enables or disables the cosmetic ragdoll state. The server continues to
	simulate only the authoritative root.

	@within SimulatedCharacter
	@param ragdolled boolean
]=]
function SimulatedCharacter.SetRagdolled(self: SimulatedCharacter, ragdolled: boolean)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(type(ragdolled) == "boolean", "Bad ragdolled")

	if ragdolled then
		self:_setMode(SimulatedCharacterConstants.Modes.RAGDOLL)
	else
		self._height = 0
		self._verticalVelocity = 0
		self._velocity = Vector2.zero
		self:_setMode(SimulatedCharacterConstants.Modes.KINEMATIC)
	end
end

--[=[
	Teleports the authoritative root and immediately replicates the new state.

	@within SimulatedCharacter
	@param cframe CFrame
]=]
function SimulatedCharacter.Teleport(self: SimulatedCharacter, cframe: CFrame)
	assert(not self._destroyed, "SimulatedCharacter is destroyed")
	assert(typeof(cframe) == "CFrame", "Bad cframe")

	const position = cframe.Position
	const lookVector = cframe.LookVector
	self._position = Vector2.new(position.X, position.Z)
	self._groundY = position.Y
	self._height = 0
	self._yaw = math.atan2(-lookVector.X, -lookVector.Z)
	self._velocity = Vector2.zero
	self._verticalVelocity = 0
	self._stateStartedAt = self._service:_getTime()
	self._service:_onCharacterStateChanged(self)
end

function SimulatedCharacter._getTarget(self: SimulatedCharacter): (Vector2?, any?)
	const targetPlayer = self._targetPlayer
	if targetPlayer then
		if targetPlayer.Parent ~= Players then
			self._targetPlayer = nil
			return nil, nil
		end

		const playerCharacter = targetPlayer.Character
		const root = playerCharacter
			and (playerCharacter:FindFirstChild("HumanoidRootPart") or playerCharacter.PrimaryPart)
		if root and root:IsA("BasePart") then
			return Vector2.new(root.Position.X, root.Position.Z), targetPlayer
		end
		return nil, nil
	end

	return self._targetPosition, self._id
end

function SimulatedCharacter._step(self: SimulatedCharacter, deltaTime: number, navigation: any?)
	if self._destroyed then
		return
	end

	if self._mode == SimulatedCharacterConstants.Modes.KINEMATIC then
		self:_stepKinematic(deltaTime, navigation)
	else
		self:_stepPhysical(deltaTime, navigation)
	end
end

function SimulatedCharacter._stepKinematic(self: SimulatedCharacter, deltaTime: number, navigation: any?)
	local targetPosition, targetKey = self:_getTarget()
	if not targetPosition or targetKey == nil then
		self._velocity = Vector2.zero
		return
	end

	const targetDelta = targetPosition - self._position
	const distance = targetDelta.Magnitude
	const arrived = distance <= self._definition.StoppingDistance
	local pathDirection = Vector2.zero
	if not arrived then
		const navigationDirection = if navigation
			then navigation:GetDirection(self._position, targetKey, targetPosition)
			else targetDelta.Unit
		if not navigationDirection or navigationDirection.Magnitude < 1e-4 then
			self._velocity = Vector2.zero
			return
		end
		pathDirection = navigationDirection
	end

	local direction = if arrived then self._flockSeparation else pathDirection + self._flockSteering
	if arrived and distance > 1e-4 then
		const towardTarget = targetDelta / distance
		const towardTargetAmount = direction:Dot(towardTarget)
		if towardTargetAmount > 0 then
			direction -= towardTarget * towardTargetAmount
		end
	end
	if direction.Magnitude < 1e-4 then
		self._velocity = Vector2.zero
		if arrived and distance > 1e-4 then
			self:_turnTowards(targetDelta / distance, deltaTime)
		end
		return
	end
	direction = direction.Unit

	const maximumDistance = math.max(0, distance - self._definition.StoppingDistance)
	const movementDistance = if arrived
		then self._definition.MoveSpeed * deltaTime
		else math.min(self._definition.MoveSpeed * deltaTime, maximumDistance)
	local nextPosition = self._position + direction * movementDistance
	if navigation and not navigation:CanMove(self._position, nextPosition) then
		const pathPosition = self._position + pathDirection * movementDistance
		if arrived or pathDirection.Magnitude < 1e-4 or not navigation:CanMove(self._position, pathPosition) then
			self._velocity = Vector2.zero
			if arrived and distance > 1e-4 then
				self:_turnTowards(targetDelta / distance, deltaTime)
			end
			return
		end
		direction = pathDirection
		nextPosition = pathPosition
	end

	self._velocity = if deltaTime > 0 then (nextPosition - self._position) / deltaTime else Vector2.zero
	self._position = nextPosition
	self:_turnTowards(if arrived and distance > 1e-4 then targetDelta / distance else direction, deltaTime)
end

function SimulatedCharacter._stepPhysical(self: SimulatedCharacter, deltaTime: number, navigation: any?)
	const damping = math.exp(-self._definition.KnockbackDamping * deltaTime)
	self._velocity *= damping
	const nextPosition = self._position + self._velocity * deltaTime

	if not navigation or navigation:CanMove(self._position, nextPosition) then
		self._position = nextPosition
	else
		const xPosition = Vector2.new(nextPosition.X, self._position.Y)
		const zPosition = Vector2.new(self._position.X, nextPosition.Y)
		if navigation:CanMove(self._position, xPosition) then
			self._position = xPosition
			self._velocity = Vector2.new(self._velocity.X, 0)
		elseif navigation:CanMove(self._position, zPosition) then
			self._position = zPosition
			self._velocity = Vector2.new(0, self._velocity.Y)
		else
			self._velocity = Vector2.zero
		end
	end

	self._height += self._verticalVelocity * deltaTime
	self._verticalVelocity -= workspace.Gravity * deltaTime
	if self._height <= 0 then
		self._height = 0
		self._verticalVelocity = 0
		self._velocity *= math.exp(-self._definition.GroundFriction * deltaTime)

		if self._mode == SimulatedCharacterConstants.Modes.KNOCKBACK and self._velocity.Magnitude < 0.25 then
			self._velocity = Vector2.zero
			self:_setMode(SimulatedCharacterConstants.Modes.KINEMATIC)
		end
	end

	if self._velocity.Magnitude > 1e-4 then
		self:_turnTowards(self._velocity, deltaTime)
	end
end

function SimulatedCharacter._turnTowards(self: SimulatedCharacter, direction: Vector2, deltaTime: number)
	if direction.Magnitude < 1e-4 then
		return
	end

	const targetYaw = math.atan2(-direction.X, -direction.Y)
	self._yaw = SimulatedCharacterUtils.moveAngleTowards(self._yaw, targetYaw, self._definition.TurnSpeed * deltaTime)
end

function SimulatedCharacter._setMode(self: SimulatedCharacter, mode: number)
	if self._mode == mode then
		return
	end

	self._mode = mode
	self._stateStartedAt = self._service:_getTime()
	self._service:_onCharacterStateChanged(self)
end

function SimulatedCharacter._getNetworkState(self: SimulatedCharacter): SimulatedCharacterTypes.NetworkState
	return {
		id = self._id,
		x = self._position.X,
		z = self._position.Y,
		groundY = self._groundY,
		height = self._height,
		yaw = self._yaw,
		velocityX = self._velocity.X,
		velocityZ = self._velocity.Y,
		verticalVelocity = self._verticalVelocity,
		mode = self._mode,
		stateStartedAt = self._stateStartedAt,
	}
end

function SimulatedCharacter._destroyInternal(self: SimulatedCharacter)
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._service = nil
	self._maid:DoCleaning()
end

function SimulatedCharacter.Destroy(self: SimulatedCharacter)
	if self._destroyed then
		return
	end

	const service = self._service
	if service then
		service:RemoveCharacter(self)
	else
		self:_destroyInternal()
	end
end

return SimulatedCharacter
