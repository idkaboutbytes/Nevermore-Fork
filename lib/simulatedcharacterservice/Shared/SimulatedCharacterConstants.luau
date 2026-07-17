--!strict
--[=[
	Constants shared by SimulatedCharacterService runtimes.

	@class SimulatedCharacterConstants
]=]

const SimulatedCharacterConstants = {}

SimulatedCharacterConstants.Modes = table.freeze({
	KINEMATIC = 0,
	KNOCKBACK = 1,
	RAGDOLL = 2,
})

SimulatedCharacterConstants.DEFAULT_SIMULATION_RATE = 20
SimulatedCharacterConstants.DEFAULT_SNAPSHOT_RATE = 10
SimulatedCharacterConstants.DEFAULT_INTERPOLATION_DELAY = 0.1
SimulatedCharacterConstants.DEFAULT_MAX_EXTRAPOLATION = 0.25
SimulatedCharacterConstants.DEFAULT_NAVIGATION_CELL_SIZE = 4
SimulatedCharacterConstants.DEFAULT_NAVIGATION_AGENT_RADIUS = 2
SimulatedCharacterConstants.DEFAULT_FLOW_FIELD_REFRESH = 0.25
SimulatedCharacterConstants.DEFAULT_FLOW_FIELD_PRUNE_INTERVAL = 5
SimulatedCharacterConstants.DEFAULT_FLOW_FIELD_LIFETIME = 10
SimulatedCharacterConstants.DEFAULT_OBSTACLE_TAG = "SimulatedCharacterObstacle"

SimulatedCharacterConstants.DEFAULT_MOVE_SPEED = 12
SimulatedCharacterConstants.DEFAULT_TURN_SPEED = math.rad(360)
SimulatedCharacterConstants.DEFAULT_STOPPING_DISTANCE = 2
SimulatedCharacterConstants.DEFAULT_HITBOX_RADIUS = 2
SimulatedCharacterConstants.DEFAULT_HITBOX_HEIGHT = 6
SimulatedCharacterConstants.DEFAULT_CULL_DISTANCE = 250
SimulatedCharacterConstants.DEFAULT_KNOCKBACK_DAMPING = 2
SimulatedCharacterConstants.DEFAULT_GROUND_FRICTION = 8

SimulatedCharacterConstants.RAGDOLL_CONSTRAINT_ATTRIBUTE = "SimulatedCharacterRagdollConstraint"
SimulatedCharacterConstants.RAGDOLL_MOTOR_ATTRIBUTE = "SimulatedCharacterRagdollMotor"

return table.freeze(SimulatedCharacterConstants)
