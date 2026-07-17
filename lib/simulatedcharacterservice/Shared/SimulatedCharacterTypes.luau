--!strict
--[=[
	Shared public types for SimulatedCharacterService.

	@class SimulatedCharacterTypes
]=]

export type CharacterDefinition = {
	TemplateName: string,
	MoveSpeed: number?,
	TurnSpeed: number?,
	StoppingDistance: number?,
	HitboxRadius: number?,
	HitboxHeight: number?,
	CullDistance: number?,
	KnockbackDamping: number?,
	GroundFriction: number?,
	IdleAnimationId: string?,
	WalkAnimationId: string?,
	UseDefaultAnimations: boolean?,
	FlockGroup: string?,
}

export type ResolvedCharacterDefinition = {
	Name: string,
	TemplateName: string,
	MoveSpeed: number,
	TurnSpeed: number,
	StoppingDistance: number,
	HitboxRadius: number,
	HitboxHeight: number,
	CullDistance: number,
	KnockbackDamping: number,
	GroundFriction: number,
	IdleAnimationId: string,
	WalkAnimationId: string,
	UseDefaultAnimations: boolean,
	FlockGroup: string,
}

export type NavigationConfig = {
	Min: Vector2,
	Max: Vector2,
	CellSize: number?,
	AgentRadius: number?,
	ObstacleTag: string?,
}

export type SpawnData = {
	CFrame: CFrame?,
	Position: Vector2?,
	GroundY: number?,
	Yaw: number?,
	Ragdolled: boolean?,
}

export type NetworkState = {
	id: number,
	x: number,
	z: number,
	groundY: number,
	height: number,
	yaw: number,
	velocityX: number,
	velocityZ: number,
	verticalVelocity: number,
	mode: number,
	stateStartedAt: number,
}

export type NetworkDefinition = {
	name: string,
	templateName: string,
	cullDistance: number,
	hitboxRadius: number,
	idleAnimationId: string,
	walkAnimationId: string,
	useDefaultAnimations: boolean,
}

export type NetworkSpawn = {
	serverTime: number,
	definition: NetworkDefinition,
	state: NetworkState,
}

export type NetworkSnapshot = {
	serverTime: number,
	characters: { NetworkState },
}

export type NetworkDebugPoint = {
	x: number,
	z: number,
}

export type NetworkDebugCharacter = {
	id: number,
	hitboxHeight: number,
	stoppingDistance: number,
	hasFlock: boolean,
	hasTarget: boolean,
	targetX: number,
	targetZ: number,
	path: { NetworkDebugPoint },
}

export type NetworkDebugSnapshot = {
	hasNavigation: boolean,
	navigationMinX: number,
	navigationMinZ: number,
	navigationMaxX: number,
	navigationMaxZ: number,
	characters: { NetworkDebugCharacter },
}

return table.freeze({})
