--!strict
--[=[
	Validates and resolves configuration for character soft-body animation.

	@util SoftBodyConfigUtils
]=]

const require = require("../../Loader").load()

const TableUtils = require("TableUtils")
const t = require("t")

export type SoftBodyConfig = {
	JumpImpulse: number,
	LandingImpulse: number,
	MinimumLandingSpeed: number,
	MaximumLandingSpeed: number,
	SpringSpeed: number,
	SpringDamper: number,
	MaximumDeformation: number,
	MaximumVerticalScaleChange: number,
	HorizontalExpansion: number,
	PositionScaleInfluence: number,
	ScaleAccessories: boolean,
	LandingSoundEnabled: boolean,
	LandingSoundId: string | number,
	LandingSoundVolume: number,
	LandingSoundPlaybackSpeed: number,
	LandingSoundRollOffMinDistance: number,
	LandingSoundRollOffMaxDistance: number,
}

export type SoftBodyConfigPatch = {
	JumpImpulse: number?,
	LandingImpulse: number?,
	MinimumLandingSpeed: number?,
	MaximumLandingSpeed: number?,
	SpringSpeed: number?,
	SpringDamper: number?,
	MaximumDeformation: number?,
	MaximumVerticalScaleChange: number?,
	HorizontalExpansion: number?,
	PositionScaleInfluence: number?,
	ScaleAccessories: boolean?,
	LandingSoundEnabled: boolean?,
	LandingSoundId: (string | number)?,
	LandingSoundVolume: number?,
	LandingSoundPlaybackSpeed: number?,
	LandingSoundRollOffMinDistance: number?,
	LandingSoundRollOffMaxDistance: number?,
}

const CONFIG_PATCH_CHECK = t.strictInterface({
	JumpImpulse = t.optional(t.number),
	LandingImpulse = t.optional(t.number),
	MinimumLandingSpeed = t.optional(t.number),
	MaximumLandingSpeed = t.optional(t.number),
	SpringSpeed = t.optional(t.number),
	SpringDamper = t.optional(t.number),
	MaximumDeformation = t.optional(t.number),
	MaximumVerticalScaleChange = t.optional(t.number),
	HorizontalExpansion = t.optional(t.number),
	PositionScaleInfluence = t.optional(t.number),
	ScaleAccessories = t.optional(t.boolean),
	LandingSoundEnabled = t.optional(t.boolean),
	LandingSoundId = t.optional(t.union(t.string, t.number)),
	LandingSoundVolume = t.optional(t.number),
	LandingSoundPlaybackSpeed = t.optional(t.number),
	LandingSoundRollOffMinDistance = t.optional(t.number),
	LandingSoundRollOffMaxDistance = t.optional(t.number),
})

const SoftBodyConfigUtils = {}

--[=[
	The default configuration used by new soft-body characters.

	@prop DEFAULT_CONFIG SoftBodyConfig
	@within SoftBodyConfigUtils
]=]
SoftBodyConfigUtils.DEFAULT_CONFIG = table.freeze({
	JumpImpulse = 9,
	LandingImpulse = 18,
	MinimumLandingSpeed = 8,
	MaximumLandingSpeed = 70,
	SpringSpeed = 12,
	SpringDamper = 0.42,
	MaximumDeformation = 1,
	MaximumVerticalScaleChange = 0.28,
	HorizontalExpansion = 0.8,
	PositionScaleInfluence = 0.7,
	ScaleAccessories = false,
	LandingSoundEnabled = true,
	LandingSoundId = "rbxasset://sounds/action_jump_land.mp3",
	LandingSoundVolume = 0.35,
	LandingSoundPlaybackSpeed = 1,
	LandingSoundRollOffMinDistance = 5,
	LandingSoundRollOffMaxDistance = 70,
}) :: SoftBodyConfig

--[=[
	Merges a partial configuration over a base configuration and validates the
	result. Unknown fields are rejected.

	@within SoftBodyConfigUtils
	@param patch SoftBodyConfigPatch?
	@param base SoftBodyConfig?
	@return SoftBodyConfig
]=]
function SoftBodyConfigUtils.resolve(patch: SoftBodyConfigPatch?, base: SoftBodyConfig?): SoftBodyConfig
	const configPatch = patch or {}
	const valid, validationError = CONFIG_PATCH_CHECK(configPatch)
	assert(valid, validationError)

	const result = TableUtils.merge(base or SoftBodyConfigUtils.DEFAULT_CONFIG, configPatch) :: SoftBodyConfig
	for name, value in result do
		if type(value) == "number" then
			assert(value == value and math.abs(value) < math.huge, `{name} must be a finite number`)
		end
	end

	assert(result.JumpImpulse >= 0, "JumpImpulse must be non-negative")
	assert(result.LandingImpulse >= 0, "LandingImpulse must be non-negative")
	assert(result.MinimumLandingSpeed >= 0, "MinimumLandingSpeed must be non-negative")
	assert(
		result.MaximumLandingSpeed > result.MinimumLandingSpeed,
		"MaximumLandingSpeed must exceed MinimumLandingSpeed"
	)
	assert(result.SpringSpeed > 0, "SpringSpeed must be positive")
	assert(result.SpringDamper >= 0, "SpringDamper must be non-negative")
	assert(result.MaximumDeformation > 0, "MaximumDeformation must be positive")
	assert(
		result.MaximumVerticalScaleChange >= 0 and result.MaximumVerticalScaleChange < 1,
		"MaximumVerticalScaleChange must be within [0, 1)"
	)
	assert(
		result.HorizontalExpansion >= 0 and result.HorizontalExpansion <= 1,
		"HorizontalExpansion must be within [0, 1]"
	)
	assert(
		result.PositionScaleInfluence >= 0 and result.PositionScaleInfluence <= 1,
		"PositionScaleInfluence must be within [0, 1]"
	)
	assert(result.LandingSoundId ~= "", "LandingSoundId must not be empty")
	assert(result.LandingSoundVolume >= 0, "LandingSoundVolume must be non-negative")
	assert(result.LandingSoundPlaybackSpeed > 0, "LandingSoundPlaybackSpeed must be positive")
	assert(result.LandingSoundRollOffMinDistance >= 0, "LandingSoundRollOffMinDistance must be non-negative")
	assert(
		result.LandingSoundRollOffMaxDistance >= result.LandingSoundRollOffMinDistance,
		"LandingSoundRollOffMaxDistance must be at least LandingSoundRollOffMinDistance"
	)

	return table.freeze(result)
end

return SoftBodyConfigUtils
