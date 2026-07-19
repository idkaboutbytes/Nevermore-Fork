# SoftBodyService

`SoftBodyServiceClient` adds a springy squash-and-stretch effect to humanoid
characters when they jump and land. The effect is entirely client-side and
visual:

- It never changes `HumanoidRootPart.CFrame`, assembly velocity, humanoid
  properties, source part sizes, collision properties, or network ownership.
- It lazily clones a stripped, anchored visual proxy the first time a character
  deforms, then mirrors the real animated body at render time.
- It changes the proxy body-part sizes and spacing to squash vertically and
  expand horizontally while the untouched source character remains the
  authoritative physical rig.
- It uses one scalar spring per character and one shared render-step callback
  for every character, rather than one connection or spring per limb.

There is no server service and no networking to register. Every client that
registers `SoftBodyServiceClient` renders the effect independently.

## Setup

Request the service from your client `ServiceBag`:

```luau
-- GameServiceClient.luau
const require = require("@game/ReplicatedStorage/Packages/Nevermore/Loader").load()

const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const SoftBodyServiceClient = require("SoftBodyServiceClient")

const GameServiceClient = {}
GameServiceClient.ServiceName = "GameServiceClient"

function GameServiceClient.Init(self, serviceBag: ServiceBag.ServiceBag)
	self._maid = Maid.new()
	self._softBodyService = serviceBag:GetService(SoftBodyServiceClient)
end

function GameServiceClient.Destroy(self)
	self._maid:Destroy()
end

return GameServiceClient
```

That is sufficient. When the ServiceBag starts, current and future player
characters are registered automatically. Respawns are cleaned up and replaced
without creating duplicate controllers.

By default, each client renders the effect for the local player and every other
player. To render only the local character:

```luau
self._softBodyService:SetAffectOtherPlayers(false)
```

This option does not affect what another client chooses to render.

## Configuring the feel

Call `Configure()` before or after the service starts. Changes become the
defaults for future characters and are also applied to currently tracked
characters.

```luau
self._softBodyService:Configure({
	JumpImpulse = 11,
	LandingImpulse = 22,
	SpringSpeed = 14,
	SpringDamper = 0.35,
	MaximumVerticalScaleChange = 0.34,
	HorizontalExpansion = 0.9,
	PositionScaleInfluence = 0.75,
	LandingSoundId = "rbxassetid://YOUR_SOUND_ID",
	LandingSoundVolume = 0.4,
})
```

| Setting | Default | Purpose |
| --- | ---: | --- |
| `JumpImpulse` | `9` | Stretch impulse applied when entering `Jumping` |
| `LandingImpulse` | `18` | Maximum squash impulse applied on landing |
| `MinimumLandingSpeed` | `8` | Downward speed required for a landing reaction |
| `MaximumLandingSpeed` | `70` | Downward speed that produces the full landing impulse |
| `SpringSpeed` | `12` | Oscillation speed; larger values settle more quickly |
| `SpringDamper` | `0.42` | Damping ratio; lower values wobble for longer |
| `MaximumDeformation` | `1` | Clamp applied to the spring before rendering |
| `MaximumVerticalScaleChange` | `0.28` | Maximum proportion removed from or added to body-part height |
| `HorizontalExpansion` | `0.8` | Blend toward volume-preserving width/depth expansion |
| `PositionScaleInfluence` | `0.7` | How much spacing between body parts follows the squash |
| `ScaleAccessories` | `false` | Whether accessory handles resize with body parts |
| `LandingSoundEnabled` | `true` | Whether qualifying landings play the configured sound |
| `LandingSoundId` | Roblox landing sound | Sound asset played at the character's root part |
| `LandingSoundVolume` | `0.35` | Maximum volume; softer qualifying landings are quieter |
| `LandingSoundPlaybackSpeed` | `1` | Playback speed and pitch of the landing sound |
| `LandingSoundRollOffMinDistance` | `5` | Distance before positional attenuation begins |
| `LandingSoundRollOffMaxDistance` | `70` | Maximum audible distance of the landing sound |

Landing sounds are created with `SoundUtils`, parented to the authoritative
character's root part for positional audio, and routed through the standard
`Master.SoundEffects` group from the `soundgroup` package. Consequently, volume
multipliers and effects applied to `WellKnownSoundGroups.SFX` affect every
soft-body landing sound. Set `LandingSoundEnabled = false` to keep the visual
landing reaction without its sound.

Configuration is strict: unknown fields, non-finite values, invalid ranges, and
negative values where they do not make sense are rejected.

For a stronger cartoony effect, increase both maximum fields and lower the
damper. For a restrained effect, reduce the maximum fields rather than reducing
spring speed; that preserves the responsive timing.

## Per-character customization

Get the cached controller and apply a configuration only to that character:

```luau
local player = game:GetService("Players").LocalPlayer
local character = assert(player.Character)
local softBodyCharacter = assert(self._softBodyService:GetCharacter(character))

softBodyCharacter:Configure({
	SpringDamper = 0.25,
	MaximumVerticalScaleChange = 0.4,
	HorizontalExpansion = 1,
})
```

Calling the service's `Configure()` later updates all characters again. It
merges only the supplied fields, so unrelated per-character values remain
unchanged.

Use `SetEnabled()` on either the service or one controller to toggle the effect.
Disabling restores any offset currently owned by the soft-body controller:

```luau
self._softBodyService:SetEnabled(false)
softBodyCharacter:SetEnabled(true)
```

The service's global enabled state is applied when new characters are
registered. Enabling one controller while the service is globally disabled is
useful as a temporary explicit override, but future global toggles still update
all controllers.

## Manual impulses

`Impulse()` lets combat, abilities, emotes, or environmental effects trigger
the same visual spring without changing character movement:

```luau
-- Positive values squash.
self._softBodyService:Impulse(character, 12)

-- Negative values stretch.
self._softBodyService:Impulse(character, -8)
```

The method returns `false` when the character is not tracked. On an individual
`SoftBodyCharacter`, omitting the amount uses half the configured landing
impulse:

```luau
softBodyCharacter:Impulse()
```

These impulses are local visual effects. A server-authoritative combat system
can send a small validated effect event to nearby clients and let each client
call `Impulse()`; the service itself intentionally does not prescribe or add
that networking.

## NPCs and other humanoid rigs

Player characters are automatic. Register an NPC explicitly:

```luau
local softBodyCharacter = self._softBodyService:RegisterCharacter(workspace.Zombie, {
	JumpImpulse = 0,
	LandingImpulse = 25,
	SpringDamper = 0.3,
})

-- Later:
self._softBodyService:UnregisterCharacter(workspace.Zombie)
```

Repeated registration returns the existing controller, preventing duplicate
effects. `UnregisterCharacter()` restores the source character's local
visibility before destroying its proxy.

The proxy follows the resulting `BasePart.CFrame` values rather than assuming a
specific joint implementation. This supports R6, legacy R15 `Motor6D` rigs,
Avatar Joint Upgrade rigs, and animated NPCs. Bone transforms are mirrored for
skinned meshes. Tool handles follow the compressed spacing but never resize;
accessory resizing is controlled by `ScaleAccessories`.

## Why this does not use a binder

The service already has a single cached controller per character and owns the
complete player/respawn lifecycle. A CollectionService binder would add a tag
and another lifecycle layer without improving ownership. Explicit
`RegisterCharacter()` and `UnregisterCharacter()` cover NPCs and other dynamic
models while keeping the player path automatic.

## Limitations

The first deformation of a character has a one-time clone cost. The proxy is
kept hidden and reused afterward, and its parts are only mirrored while the
spring is moving. Descendant changes mark it for rebuilding on the next active
frame, allowing respawn appearance and accessory changes to remain accurate.

Scripts, animators, sounds, particles, trails, lights, prompts, world-space
GUIs, joints, constraints, and body movers are stripped from the proxy to
prevent duplicated behavior, effects, or physical assemblies. A non-simulating
Humanoid is retained so Roblox continues composing classic and layered clothing
on the visual rig. Proxy models carry the `SoftBodyVisual` attribute and all
proxy parts have `CanQuery`, `CanTouch`, and `CanCollide` disabled. The original
character remains authoritative. Very specialized
characters whose appearance depends on a custom runtime renderer may need their
own visual-proxy integration.
