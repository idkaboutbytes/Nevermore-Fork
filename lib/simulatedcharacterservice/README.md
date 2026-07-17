# SimulatedCharacterService

`SimulatedCharacterService` runs lightweight, server-authoritative NPC roots on
a flat X/Z plane. The server stores numbers rather than physical character
models. Each client clones, animates, interpolates, ragdolls, and culls its own
visual models.

The package is designed for dozens of NPCs that may overlap. It deliberately
does not perform NPC-to-NPC avoidance.

## Architecture

- The server simulates all roots at 20 Hz and publishes ByteNet snapshots at
  10 Hz.
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
})
```

The client must acquire `SimulatedCharacterServiceClient` through its own
`ServiceBag`. Its lifecycle starts culling, time synchronization, networking,
rendering, pooling, and animation automatically.

```luau
const SimulatedCharacterServiceClient = require("SimulatedCharacterServiceClient")

serviceBag:GetService(SimulatedCharacterServiceClient)
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
while knockback can temporarily add visual height above it.

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
- Characters intentionally overlap and do not collide with each other.
- Use `GetCFrame()` and `GetHitboxSize()` for authoritative server-side combat
  checks instead of relying on client limbs.
