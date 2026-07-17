--!strict
--[=[
	Shared math and definition helpers for SimulatedCharacterService.

	@util SimulatedCharacterUtils
]=]

const require = require("../../Loader").load()

const MathUtils = require("MathUtils")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")

const SimulatedCharacterUtils = {}

--[=[
	Resolves and validates a registered character definition.

	@within SimulatedCharacterUtils
	@param name string
	@param definition CharacterDefinition
	@return ResolvedCharacterDefinition
]=]
function SimulatedCharacterUtils.resolveDefinition(
	name: string,
	definition: SimulatedCharacterTypes.CharacterDefinition
): SimulatedCharacterTypes.ResolvedCharacterDefinition
	assert(type(name) == "string" and name ~= "", "Bad name")
	assert(type(definition) == "table", "Bad definition")
	assert(type(definition.TemplateName) == "string" and definition.TemplateName ~= "", "Bad TemplateName")
	assert(definition.MoveSpeed == nil or definition.MoveSpeed >= 0, "Bad MoveSpeed")
	assert(definition.TurnSpeed == nil or definition.TurnSpeed >= 0, "Bad TurnSpeed")
	assert(definition.StoppingDistance == nil or definition.StoppingDistance >= 0, "Bad StoppingDistance")
	assert(definition.HitboxRadius == nil or definition.HitboxRadius >= 0, "Bad HitboxRadius")
	assert(definition.HitboxHeight == nil or definition.HitboxHeight >= 0, "Bad HitboxHeight")
	assert(definition.CullDistance == nil or definition.CullDistance >= 0, "Bad CullDistance")
	assert(definition.KnockbackDamping == nil or definition.KnockbackDamping >= 0, "Bad KnockbackDamping")
	assert(definition.GroundFriction == nil or definition.GroundFriction >= 0, "Bad GroundFriction")
	assert(definition.IdleAnimationId == nil or type(definition.IdleAnimationId) == "string", "Bad IdleAnimationId")
	assert(definition.WalkAnimationId == nil or type(definition.WalkAnimationId) == "string", "Bad WalkAnimationId")
	assert(
		definition.UseDefaultAnimations == nil or type(definition.UseDefaultAnimations) == "boolean",
		"Bad UseDefaultAnimations"
	)

	return table.freeze({
		Name = name,
		TemplateName = definition.TemplateName,
		MoveSpeed = definition.MoveSpeed or SimulatedCharacterConstants.DEFAULT_MOVE_SPEED,
		TurnSpeed = definition.TurnSpeed or SimulatedCharacterConstants.DEFAULT_TURN_SPEED,
		StoppingDistance = definition.StoppingDistance or SimulatedCharacterConstants.DEFAULT_STOPPING_DISTANCE,
		HitboxRadius = definition.HitboxRadius or SimulatedCharacterConstants.DEFAULT_HITBOX_RADIUS,
		HitboxHeight = definition.HitboxHeight or SimulatedCharacterConstants.DEFAULT_HITBOX_HEIGHT,
		CullDistance = definition.CullDistance or SimulatedCharacterConstants.DEFAULT_CULL_DISTANCE,
		KnockbackDamping = definition.KnockbackDamping or SimulatedCharacterConstants.DEFAULT_KNOCKBACK_DAMPING,
		GroundFriction = definition.GroundFriction or SimulatedCharacterConstants.DEFAULT_GROUND_FRICTION,
		IdleAnimationId = definition.IdleAnimationId or "",
		WalkAnimationId = definition.WalkAnimationId or "",
		UseDefaultAnimations = definition.UseDefaultAnimations ~= false,
	})
end

--[=[
	Converts a world position into the X/Z simulation plane.

	@within SimulatedCharacterUtils
	@param value Vector2 | Vector3
	@return Vector2
]=]
function SimulatedCharacterUtils.toPlanarPosition(value: Vector2 | Vector3): Vector2
	if typeof(value) == "Vector2" then
		return value
	elseif typeof(value) == "Vector3" then
		return Vector2.new(value.X, value.Z)
	end

	error("Bad planar position")
end

--[=[
	Returns the shortest interpolated angle.

	@within SimulatedCharacterUtils
	@param from number
	@param to number
	@param alpha number
	@return number
]=]
function SimulatedCharacterUtils.lerpAngle(from: number, to: number, alpha: number): number
	const difference = (to - from + math.pi) % (2 * math.pi) - math.pi
	return MathUtils.lerp(from, from + difference, alpha)
end

--[=[
	Moves an angle toward another angle by a maximum delta.

	@within SimulatedCharacterUtils
	@param from number
	@param to number
	@param maxDelta number
	@return number
]=]
function SimulatedCharacterUtils.moveAngleTowards(from: number, to: number, maxDelta: number): number
	const difference = (to - from + math.pi) % (2 * math.pi) - math.pi
	return from + math.clamp(difference, -maxDelta, maxDelta)
end

--[=[
	Builds the rendered root CFrame for a network state.

	@within SimulatedCharacterUtils
	@param x number
	@param z number
	@param groundY number
	@param height number
	@param yaw number
	@return CFrame
]=]
function SimulatedCharacterUtils.toCFrame(x: number, z: number, groundY: number, height: number, yaw: number): CFrame
	return CFrame.new(x, groundY + height, z) * CFrame.Angles(0, yaw, 0)
end

return SimulatedCharacterUtils
