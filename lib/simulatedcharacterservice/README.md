# SimulatedCharacterService

`SimulatedCharacterService` runs lightweight, server-authoritative NPC roots on
a flat X/Z plane. The server stores numbers rather than physical character
models. Each client clones, animates, interpolates, ragdolls, and culls its own
visual models.

The package is designed for dozens of NPCs. Characters may overlap by default,
or use optional flock groups for lightweight local avoidance and coordinated
movement.

## Architecture

- The server simulates all roots at 20 Hz and publishes interest-managed
  ByteNet snapshots at 10 Hz.
- `TimeSyncService` gives snapshots a shared timestamp so clients interpolate
  approximately 100 ms behind the server.
- Navigation uses a flat X/Z occupancy grid. Direct paths skip flow-field work;
  blocked paths share one cached flow field per chased player.
- The server hitbox is a CFrame plus `HitboxRadius` and `HitboxHeight`. It does
  not allocate a Part, incur physics cost, or replicate an invisible Part.
- `TemplateProvider` transfers a model only when a client needs to render it.
- `ClientCulling` checks simulated characters at 10 Hz with squared X/Z
  distance. A culled NPC has no model in Workspace.
- Visible NPCs share one `RenderStepped` connection and one animation driver.

## Templates

Keep game-specific models outside the package. Create a Folder in your game's
asset hierarchy and point the service at it during server initialization:

```text
ReplicatedStorage
└── Assets
    └── SimulatedCharacters
        ├── Zombie
        └── Skeleton
```

```luau
const ReplicatedStorage = game:GetService("ReplicatedStorage")

simulatedCharacters:SetTemplateContainer(
	ReplicatedStorage:WaitForChild("Assets"):WaitForChild("SimulatedCharacters")
)
```

The selected Folder receives the `SimulatedCharacterTemplateContainer`
CollectionService tag. The shared tagged provider therefore discovers the same
container on the server and clients. On the server, TemplateProvider moves the
real models beneath its non-replicating `Camera` and leaves lightweight
tombstones in the Folder. Clients download a model only when they need to render
it.

Give each model a `PrimaryPart` or a part named `HumanoidRootPart`.

A template may contain a normal Roblox `Animate` hierarchy. The service reads
its idle and walk animation objects, disables the cloned `LocalScript`, and
plays those tracks from the shared renderer. It does not run one animation
script per NPC.

Animation resolution is:

1. `IdleAnimationId` or `WalkAnimationId` in the registered definition.
2. The NPC template's `Animate` hierarchy.
3. The local player's default `Animate` hierarchy or applied
   `HumanoidDescription`.

Set `UseDefaultAnimations = false` to disable steps 2 and 3.

## Server setup

Acquire the service from the game's existing `ServiceBag`, then configure one
explicit navigation region and register character definitions during startup:

```luau
const SimulatedCharacterService = require("SimulatedCharacterService")

local simulatedCharacters = serviceBag:GetService(SimulatedCharacterService)

simulatedCharacters:ConfigureNavigation({
	Min = Vector2.new(-256, -256),
	Max = Vector2.new(256, 256),
	CellSize = 4,
	AgentRadius = 2,
	ObstacleTag = "SimulatedCharacterObstacle",
})

simulatedCharacters:RegisterCharacter("Zombie", {
	TemplateName = "Zombie",
	MoveSpeed = 10,
	TurnSpeed = math.rad(360),
	StoppingDistance = 3,
	HitboxRadius = 2,
	HitboxHeight = 6,
	CullDistance = 220,
	UseDefaultAnimations = true,
	FlockGroup = "Undead",
})
```

The client must acquire `SimulatedCharacterServiceClient` through its own
`ServiceBag`. Its lifecycle starts culling, time synchronization, networking,
rendering, pooling, and animation automatically.

```luau
const SimulatedCharacterServiceClient = require("SimulatedCharacterServiceClient")

local simulatedCharactersClient = serviceBag:GetService(SimulatedCharacterServiceClient)
```

## Spawning and movement

```luau
local zombie = simulatedCharacters:SpawnCharacter("Zombie", {
	CFrame = CFrame.new(0, 3, 0),
})

zombie:Chase(player)

-- Or move toward a fixed destination.
zombie:MoveTo(Vector3.new(100, 0, -40))

zombie:Stop()
zombie:Teleport(CFrame.new(20, 3, 20))
zombie:Destroy()
```

`MoveTo` and `Chase` ignore Y. `GroundY` remains the root's baseline height,
while knockback can temporarily add visual height above it. Once inside its
stopping distance, a character continues turning on X/Z to face its current
target even though its movement has stopped.

## Flocking and local avoidance

Set `FlockGroup` to a non-empty string to give characters in that group
server-authoritative crowd steering:

```luau
simulatedCharacters:RegisterCharacter("Zombie", {
	TemplateName = "Zombie",
	FlockGroup = "Undead",
})
```

Only characters with the same exact group name influence each other. The
service combines hitbox-based separation, light velocity alignment, and light
cohesion with the existing path direction. If the blended move is blocked, it
falls back to the unmodified navigation direction.

Flocking runs only for kinematic movement. Knockback and ragdoll characters do
not steer or influence their group until they return to kinematic mode. The
calculation uses reusable dense group arrays, squared X/Z distance checks, and
does not add anything to network snapshots.

## Network interest

Spawn and removal messages are sent globally so every client maintains the
complete lightweight NPC registry. This allows an NPC to become visible as
soon as it approaches without needing a second spawn lifecycle.

Periodic movement snapshots and immediate state changes are sent only to
players within that definition's `CullDistance`. Distance checks use X/Z and
include `HitboxRadius`, matching the client culling boundary. When an NPC leaves
range, the server sends one final reliable state so the client cannot leave a
stale model visible, then stops updates until the NPC enters range again.

## Debug drawing

Toggle local debug drawing through the client service:

```luau
simulatedCharactersClient:SetDebug(true)

-- Remove every debug drawing and stop requesting debug data.
simulatedCharactersClient:SetDebug(false)
```

`SetDebug(true)` loads the `Draw` package locally and creates a
`Workspace.SimulatedCharacterDebug` folder visible only to that client. It
requests path data only for nearby NPCs at 5 Hz. Debug requests are rate-limited
on the server, and no debug packets or drawing work run while disabled.

The visualization refreshes at 5 Hz:

- Red boxes are authoritative hitboxes.
- Cyan rings are client culling and network-update ranges.
- Magenta rings are flock neighbor ranges.
- Yellow rings are stopping distances around current targets.
- Green lines show direct or flow-field paths.
- Orange lines show actual movement after flock steering.
- Blue lines are the configured navigation bounds.

Debug defaults to false and is cleaned up automatically with the client
service.

## Knockback and cosmetic ragdolls

```luau
zombie:ApplyImpulse(Vector3.new(25, 35, 0))

zombie:SetRagdolled(true)
zombie:ApplyImpulse(Vector3.new(25, 35, 0))

task.delay(2, function()
	if simulatedCharacters:GetCharacter(zombie:GetId()) then
		zombie:SetRagdolled(false)
	end
end)

-- Uses MathUtils.computeTrajectory internally.
zombie:LaunchTowards(targetPosition, 60)
```

The server simulates only root velocity and height. Client limbs are cosmetic.
For precise ragdolls, tag the intended `Motor6D` objects with the boolean
attribute `SimulatedCharacterRagdollMotor` and the replacement constraints with
`SimulatedCharacterRagdollConstraint`. Without attributes, the renderer falls
back to non-root motors and all `BallSocketConstraint` objects.

## Obstacles and rebuilding

Tag obstacle `BasePart` or `Model` instances with the configured obstacle tag.
Adding or removing the tag schedules a grid rebuild. If a tagged obstacle moves
or resizes without a tag change, rebuild explicitly:

```luau
simulatedCharacters:RebuildNavigation()
```

Keep navigation bounds tight and use the largest cell size that still fits the
gameplay geometry. A 512 by 512 stud region with four-stud cells is a 128 by 128
grid. Flow fields are cached per chase target, so many NPCs chasing the same
player reuse the same path data.

## Performance notes

- Avoid putting cosmetic models on the server; use the template provider.
- Prefer `Chase(player)` when many NPCs share a target. Unique blocked `MoveTo`
  destinations require unique flow fields.
- Character visuals are pooled per template after culling.
- Normal movement, navigation, and culling use X/Z only.
- Characters without a `FlockGroup`, and characters in different groups, may
  overlap. Members of one flock use soft local avoidance rather than Roblox
  physics collisions.
- Use `GetCFrame()` and `GetHitboxSize()` for authoritative server-side combat
  checks instead of relying on client limbs.
