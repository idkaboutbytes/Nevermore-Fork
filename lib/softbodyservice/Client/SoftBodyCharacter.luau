--!strict
--!optimize 2
--[=[
	Renders a squash-and-stretch visual proxy over a humanoid character while
	leaving the source character's physical parts unchanged.

	@class SoftBodyCharacter
	@client
]=]

const CollectionService = game:GetService("CollectionService")
const HttpService = game:GetService("HttpService")
const Players = game:GetService("Players")

const require = require("../../Loader").load()

const Maid = require("Maid")
const MathUtils = require("MathUtils")
const SoftBodyConfigUtils = require("SoftBodyConfigUtils")
const SoundUtils = require("SoundUtils")
const Spring = require("Spring")
const SpringUtils = require("SpringUtils")

type SoftBodyConfig = SoftBodyConfigUtils.SoftBodyConfig
type SoftBodyConfigPatch = SoftBodyConfigUtils.SoftBodyConfigPatch

type VisualPartState = {
	visualPart: BasePart,
	restoreLocalTransparency: number,
	hiddenBySoftBody: boolean,
	sourceMesh: SpecialMesh?,
	visualMesh: SpecialMesh?,
}

const LANDING_STATES: { [Enum.HumanoidStateType]: boolean } = table.freeze({
	[Enum.HumanoidStateType.Landed] = true,
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.GettingUp] = true,
})

const SoftBodyCharacter = {}
SoftBodyCharacter.ClassName = "SoftBodyCharacter"
SoftBodyCharacter.__index = SoftBodyCharacter

export type SoftBodyCharacter = typeof(setmetatable(
	{} :: {
		_character: Model,
		_visualParent: Instance,
		_sfxSoundGroup: SoundGroup,
		_maid: Maid.Maid,
		_visualMaid: Maid.Maid,
		_config: SoftBodyConfig,
		_spring: Spring.Spring<number>,
		_visualModel: Model?,
		_visualParts: { [BasePart]: VisualPartState },
		_visualBones: { [Bone]: Bone },
		_humanoid: Humanoid?,
		_rootPart: BasePart?,
		_enabled: boolean,
		_falling: boolean,
		_minimumVerticalVelocity: number,
		_visualDirty: boolean,
		_visualActive: boolean,
		_cloneFailed: boolean,
		_destroyed: boolean,
	},
	SoftBodyCharacter
))

--[=[
	Creates a visual soft-body controller for a character model. The visual parent
	should be a client-owned container under Workspace.

	@within SoftBodyCharacter
	@param character Model
	@param config SoftBodyConfigPatch?
	@param visualParent Instance?
	@return SoftBodyCharacter
]=]
function SoftBodyCharacter.new(
	character: Model,
	config: SoftBodyConfigPatch?,
	visualParent: Instance?,
	sfxSoundGroup: SoundGroup
): SoftBodyCharacter
	assert(typeof(character) == "Instance" and character:IsA("Model"), "Bad character")
	assert(visualParent == nil or typeof(visualParent) == "Instance", "Bad visualParent")
	assert(typeof(sfxSoundGroup) == "Instance" and sfxSoundGroup:IsA("SoundGroup"), "Bad sfxSoundGroup")
	const self = setmetatable({}, SoftBodyCharacter) :: SoftBodyCharacter

	self._character = character
	self._visualParent = visualParent or workspace
	self._sfxSoundGroup = sfxSoundGroup
	self._maid = Maid.new()
	self._visualMaid = Maid.new()
	self._config = SoftBodyConfigUtils.resolve(config)
	self._spring = Spring.new(0)
	self._spring.Speed = self._config.SpringSpeed
	self._spring.Damper = self._config.SpringDamper
	self._visualModel = nil
	self._visualParts = {}
	self._visualBones = {}
	self._humanoid = nil
	self._rootPart = nil
	self._enabled = true
	self._falling = false
	self._minimumVerticalVelocity = 0
	self._visualDirty = true
	self._visualActive = false
	self._cloneFailed = false
	self._destroyed = false

	for _, descendant in character:GetDescendants() do
		self:_handleDescendantAdded(descendant)
	end
	self._maid:Add(character.DescendantAdded:Connect(function(descendant)
		self:_handleDescendantAdded(descendant)
		self._visualDirty = true
		self._cloneFailed = false
	end))
	self._maid:Add(character.DescendantRemoving:Connect(function(descendant)
		self:_handleDescendantRemoving(descendant)
		self._visualDirty = true
		self._cloneFailed = false
	end))

	return self
end

--[=[
	Returns the source character model.

	@within SoftBodyCharacter
	@return Model
]=]
function SoftBodyCharacter.GetCharacter(self: SoftBodyCharacter): Model
	return self._character
end

--[=[
	Applies a partial configuration to this character.

	@within SoftBodyCharacter
	@param config SoftBodyConfigPatch
]=]
function SoftBodyCharacter.Configure(self: SoftBodyCharacter, config: SoftBodyConfigPatch): ()
	assert(not self._destroyed, "SoftBodyCharacter is destroyed")
	self._config = SoftBodyConfigUtils.resolve(config, self._config)
	self._spring.Speed = self._config.SpringSpeed
	self._spring.Damper = self._config.SpringDamper
end

--[=[
	Returns a copy of the resolved configuration.

	@within SoftBodyCharacter
	@return SoftBodyConfig
]=]
function SoftBodyCharacter.GetConfig(self: SoftBodyCharacter): SoftBodyConfig
	return table.clone(self._config)
end

--[=[
	Enables or disables visual deformation. Disabling immediately restores the
	source character's local visibility.

	@within SoftBodyCharacter
	@param enabled boolean
]=]
function SoftBodyCharacter.SetEnabled(self: SoftBodyCharacter, enabled: boolean): ()
	assert(type(enabled) == "boolean", "Bad enabled")
	assert(not self._destroyed, "SoftBodyCharacter is destroyed")
	if self._enabled == enabled then
		return
	end

	self._enabled = enabled
	if not enabled then
		self:Reset()
	end
end

--[=[
	Returns whether visual deformation is enabled.

	@within SoftBodyCharacter
	@return boolean
]=]
function SoftBodyCharacter.IsEnabled(self: SoftBodyCharacter): boolean
	return self._enabled
end

--[=[
	Adds velocity to the deformation spring. Positive impulses squash the body;
	negative impulses stretch it. This can also drive visual hit reactions.

	@within SoftBodyCharacter
	@param amount number?
]=]
function SoftBodyCharacter.Impulse(self: SoftBodyCharacter, amount: number?): ()
	assert(not self._destroyed, "SoftBodyCharacter is destroyed")
	const impulse = amount or self._config.LandingImpulse * 0.5
	assert(type(impulse) == "number" and impulse == impulse and math.abs(impulse) < math.huge, "Bad amount")
	if self._enabled then
		self._spring:Impulse(impulse)
	end
end

--[=[
	Stops the spring, hides the visual proxy, and restores the source character.

	@within SoftBodyCharacter
]=]
function SoftBodyCharacter.Reset(self: SoftBodyCharacter): ()
	assert(not self._destroyed, "SoftBodyCharacter is destroyed")
	self:_deactivateVisual()
	self._spring.Target = 0
	self._spring.Position = 0
	self._spring.Velocity = 0
end

function SoftBodyCharacter._render(self: SoftBodyCharacter): ()
	if self._destroyed then
		return
	end

	self:_updateFallingVelocity()
	if not self._enabled then
		return
	end

	const isAnimating, springPosition = SpringUtils.animating(self._spring, 1e-4)
	if not isAnimating then
		self:_deactivateVisual()
		return
	end
	if not self:_ensureVisualModel() then
		return
	end

	const config = self._config
	const deformation = math.clamp(springPosition, -config.MaximumDeformation, config.MaximumDeformation)
		/ config.MaximumDeformation
	const verticalScale = math.max(0.05, 1 - deformation * config.MaximumVerticalScaleChange)
	const volumePreservingHorizontalScale = 1 / math.sqrt(verticalScale)
	const horizontalScale = MathUtils.lerp(1, volumePreservingHorizontalScale, config.HorizontalExpansion)
	const positionVerticalScale = MathUtils.lerp(1, verticalScale, config.PositionScaleInfluence)
	const positionHorizontalScale = MathUtils.lerp(1, horizontalScale, config.PositionScaleInfluence)
	const rootPart = self:_getRootPart()
	const rootCFrame = if rootPart then rootPart.CFrame else self._character:GetPivot()
	const isFirstPerson = self:_isLocalFirstPerson()

	self._visualActive = true
	for sourcePart, state in self._visualParts do
		const visualPart = state.visualPart
		if sourcePart.Parent == nil or visualPart.Parent == nil then
			self._visualDirty = true
			continue
		end

		-- Humanoids can reapply character part defaults after a model is parented.
		-- Keep the proxy physically inert even if that happens between activations.
		visualPart.Anchored = true
		visualPart.CanCollide = false
		visualPart.CanQuery = false
		visualPart.CanTouch = false
		visualPart.Massless = true

		if not state.hiddenBySoftBody then
			state.restoreLocalTransparency = sourcePart.LocalTransparencyModifier
			state.hiddenBySoftBody = true
		elseif sourcePart.LocalTransparencyModifier ~= 1 then
			state.restoreLocalTransparency = sourcePart.LocalTransparencyModifier
		end
		sourcePart.LocalTransparencyModifier = 1

		const relativeCFrame = rootCFrame:ToObjectSpace(sourcePart.CFrame)
		const relativePosition = relativeCFrame.Position
		visualPart.CFrame = rootCFrame
			* CFrame.new(
				relativePosition.X * positionHorizontalScale,
				relativePosition.Y * positionVerticalScale,
				relativePosition.Z * positionHorizontalScale
			)
			* relativeCFrame.Rotation

		const shouldScale = self:_shouldScalePart(sourcePart)
		const partHorizontalScale = if shouldScale then horizontalScale else 1
		const partVerticalScale = if shouldScale then verticalScale else 1
		const sourceSize = sourcePart.Size

		const sourceMesh = state.sourceMesh
		const visualMesh = state.visualMesh
		if sourceMesh and visualMesh and sourceMesh.Parent and visualMesh.Parent then
			visualPart.Size = sourceSize
			const sourceScale = sourceMesh.Scale
			visualMesh.Scale = Vector3.new(
				sourceScale.X * partHorizontalScale,
				sourceScale.Y * partVerticalScale,
				sourceScale.Z * partHorizontalScale
			)
		else
			visualPart.Size = Vector3.new(
				sourceSize.X * partHorizontalScale,
				sourceSize.Y * partVerticalScale,
				sourceSize.Z * partHorizontalScale
			)
		end

		visualPart.Color = sourcePart.Color
		visualPart.Material = sourcePart.Material
		visualPart.MaterialVariant = sourcePart.MaterialVariant
		visualPart.Reflectance = sourcePart.Reflectance
		visualPart.Transparency = sourcePart.Transparency
		visualPart.CastShadow = sourcePart.CastShadow
		visualPart.LocalTransparencyModifier = if isFirstPerson then 1 else state.restoreLocalTransparency
	end

	for sourceBone, visualBone in self._visualBones do
		if sourceBone.Parent and visualBone.Parent then
			visualBone.Transform = sourceBone.Transform
		else
			self._visualDirty = true
		end
	end
end

function SoftBodyCharacter._handleDescendantAdded(self: SoftBodyCharacter, descendant: Instance): ()
	if descendant:IsA("Humanoid") then
		self:_setHumanoid(descendant)
	elseif descendant:IsA("BasePart") and descendant.Name == "HumanoidRootPart" then
		self._rootPart = descendant
	end
end

function SoftBodyCharacter._handleDescendantRemoving(self: SoftBodyCharacter, descendant: Instance): ()
	if descendant == self._humanoid then
		self:_setHumanoid(nil)
	elseif descendant == self._rootPart then
		self._rootPart = nil
	end
end

function SoftBodyCharacter._setHumanoid(self: SoftBodyCharacter, humanoid: Humanoid?): ()
	self._maid._humanoid = nil
	self._humanoid = humanoid
	self._falling = false
	self._minimumVerticalVelocity = 0
	if not humanoid then
		return
	end

	const maid = Maid.new()
	maid:Add(humanoid.StateChanged:Connect(function(_oldState, newState)
		self:_handleHumanoidState(newState)
	end))
	maid:Add(humanoid:GetPropertyChangedSignal("RootPart"):Connect(function()
		self._rootPart = humanoid.RootPart
	end))
	self._maid._humanoid = maid
	self._rootPart = humanoid.RootPart
	self:_handleHumanoidState(humanoid:GetState())
end

function SoftBodyCharacter._handleHumanoidState(self: SoftBodyCharacter, state: Enum.HumanoidStateType): ()
	if state == Enum.HumanoidStateType.Jumping then
		self._falling = false
		self._minimumVerticalVelocity = 0
		self:Impulse(-self._config.JumpImpulse)
	elseif state == Enum.HumanoidStateType.Freefall then
		self._falling = true
		self._minimumVerticalVelocity = math.min(0, self:_getVerticalVelocity())
	elseif self._falling and LANDING_STATES[state] then
		const landingSpeed = math.max(0, -self._minimumVerticalVelocity)
		self._falling = false
		self._minimumVerticalVelocity = 0
		if landingSpeed >= self._config.MinimumLandingSpeed then
			const strength = math.clamp(
				MathUtils.map(landingSpeed, self._config.MinimumLandingSpeed, self._config.MaximumLandingSpeed, 0.25, 1),
				0.25,
				1
			)
			self:Impulse(self._config.LandingImpulse * strength)

			const config = self._config
			const rootPart = self:_getRootPart()
			if self._enabled and config.LandingSoundEnabled and rootPart then
				const sound = SoundUtils.createSoundFromId({
					SoundId = config.LandingSoundId,
					Volume = config.LandingSoundVolume * MathUtils.lerp(0.6, 1, strength),
					PlaybackSpeed = config.LandingSoundPlaybackSpeed,
					RollOffMinDistance = config.LandingSoundRollOffMinDistance,
					RollOffMaxDistance = config.LandingSoundRollOffMaxDistance,
				})
				sound.Name = "SoftBodyLanding"
				sound.SoundGroup = self._sfxSoundGroup
				sound.Parent = rootPart
				sound:Play()
				SoundUtils.removeAfterTimeLength(sound)
			end
		end
	elseif state == Enum.HumanoidStateType.Dead then
		self._falling = false
		self._minimumVerticalVelocity = 0
		self:Reset()
	end
end

function SoftBodyCharacter._updateFallingVelocity(self: SoftBodyCharacter): ()
	if self._falling then
		self._minimumVerticalVelocity = math.min(self._minimumVerticalVelocity, self:_getVerticalVelocity())
	end
end

function SoftBodyCharacter._getRootPart(self: SoftBodyCharacter): BasePart?
	local rootPart = self._rootPart
	if rootPart and rootPart.Parent then
		return rootPart
	end

	const candidate = self._character:FindFirstChild("HumanoidRootPart")
	if candidate and candidate:IsA("BasePart") then
		self._rootPart = candidate
		return candidate
	end
	return nil
end

function SoftBodyCharacter._getVerticalVelocity(self: SoftBodyCharacter): number
	const rootPart = self:_getRootPart()
	return if rootPart then rootPart.AssemblyLinearVelocity.Y else 0
end

function SoftBodyCharacter._isLocalFirstPerson(self: SoftBodyCharacter): boolean
	if Players.LocalPlayer.Character ~= self._character then
		return false
	end
	const camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - camera.Focus.Position).Magnitude < 1
end

function SoftBodyCharacter._shouldScalePart(self: SoftBodyCharacter, sourcePart: BasePart): boolean
	if sourcePart == self._rootPart or sourcePart.Name == "HumanoidRootPart" then
		return false
	end
	if sourcePart:FindFirstAncestorOfClass("Tool") then
		return false
	end
	if sourcePart:FindFirstAncestorOfClass("Accessory") then
		return self._config.ScaleAccessories
	end
	return true
end

function SoftBodyCharacter._ensureVisualModel(self: SoftBodyCharacter): boolean
	if self._visualModel and self._visualModel.Parent and not self._visualDirty then
		return true
	end
	if self._cloneFailed and not self._visualDirty then
		return false
	end

	self:_deactivateVisual()
	self:_destroyVisualModel()
	self._visualMaid = Maid.new()
	self._visualDirty = false
	const sourceAttribute = `__NevermoreSoftBody_{string.gsub(HttpService:GenerateGUID(false), "%-", "")}`
	const sourcesById: { [number]: Instance } = {}
	local nextId = 0
	for _, descendant in self._character:GetDescendants() do
		if descendant:IsA("BasePart") or descendant:IsA("Bone") then
			nextId += 1
			sourcesById[nextId] = descendant
			descendant:SetAttribute(sourceAttribute, nextId)
		end
	end

	const wasArchivable = self._character.Archivable
	self._character.Archivable = true
	const success, result = pcall(function()
		return self._character:Clone()
	end)
	self._character.Archivable = wasArchivable
	for _, source in sourcesById do
		source:SetAttribute(sourceAttribute, nil)
	end

	if not success or typeof(result) ~= "Instance" or not result:IsA("Model") then
		self._cloneFailed = true
		warn(`[SoftBodyCharacter] - Failed to create visual proxy for {self._character:GetFullName()}: {result}`)
		return false
	end

	const visualModel = result
	visualModel.Name = `{self._character.Name}_SoftBodyVisual`
	visualModel.Archivable = false
	visualModel:SetAttribute("SoftBodyVisual", true)
	self._visualModel = visualModel
	self._cloneFailed = false

	for _, tag in CollectionService:GetTags(visualModel) do
		CollectionService:RemoveTag(visualModel, tag)
	end

	for _, descendant in visualModel:GetDescendants() do
		const sourceId = descendant:GetAttribute(sourceAttribute)
		for _, tag in CollectionService:GetTags(descendant) do
			CollectionService:RemoveTag(descendant, tag)
		end
		descendant:SetAttribute(sourceAttribute, nil)

		if descendant:IsA("BasePart") then
			const source = if type(sourceId) == "number" then sourcesById[sourceId] else nil
			if source and source:IsA("BasePart") then
				descendant.Anchored = true
				descendant.CanCollide = false
				descendant.CanQuery = false
				descendant.CanTouch = false
				descendant.Massless = true
				descendant.LocalTransparencyModifier = 1
				self._visualMaid:Add(descendant:GetPropertyChangedSignal("CanCollide"):Connect(function()
					if descendant.CanCollide then
						descendant.CanCollide = false
					end
				end))
				self._visualParts[source] = {
					visualPart = descendant,
					restoreLocalTransparency = source.LocalTransparencyModifier,
					hiddenBySoftBody = false,
					sourceMesh = source:FindFirstChildWhichIsA("SpecialMesh"),
					visualMesh = descendant:FindFirstChildWhichIsA("SpecialMesh"),
				}
			else
				descendant:Destroy()
			end
		elseif descendant:IsA("Bone") then
			const source = if type(sourceId) == "number" then sourcesById[sourceId] else nil
			if source and source:IsA("Bone") then
				self._visualBones[source] = descendant
			end
		elseif descendant:IsA("Humanoid") then
			descendant.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			descendant.NameDisplayDistance = 0
			descendant.HealthDisplayDistance = 0
			descendant.AutomaticScalingEnabled = false
			descendant.BreakJointsOnDeath = false
			descendant.RequiresNeck = false
			descendant.EvaluateStateMachine = false
			descendant.AutoRotate = false
			descendant.PlatformStand = true
		elseif
			descendant:IsA("JointInstance")
			or descendant:IsA("Constraint")
			or descendant:IsA("WeldConstraint")
			or descendant:IsA("BodyMover")
		then
			-- Parts are positioned directly from the source rig. Retaining physical
			-- links serves no visual purpose and risks coupling the proxy into an
			-- assembly if Roblox or an avatar asset re-enables one later.
			descendant:Destroy()
		elseif
			descendant:IsA("LuaSourceContainer")
			or descendant:IsA("AnimationController")
			or descendant:IsA("Animator")
			or descendant:IsA("Sound")
			or descendant:IsA("ParticleEmitter")
			or descendant:IsA("Beam")
			or descendant:IsA("Trail")
			or descendant:IsA("Light")
			or descendant:IsA("GuiBase2d")
			or descendant:IsA("ProximityPrompt")
			or descendant:IsA("ClickDetector")
			or descendant:IsA("Highlight")
		then
			descendant:Destroy()
		end
	end

	visualModel.Parent = self._visualParent
	return true
end

function SoftBodyCharacter._deactivateVisual(self: SoftBodyCharacter): ()
	if not self._visualActive then
		return
	end

	const isFirstPerson = self:_isLocalFirstPerson()
	for sourcePart, state in self._visualParts do
		if sourcePart.Parent and state.hiddenBySoftBody then
			if sourcePart.LocalTransparencyModifier == 1 then
				sourcePart.LocalTransparencyModifier = if isFirstPerson then 1 else state.restoreLocalTransparency
			end
			state.hiddenBySoftBody = false
		end
		if state.visualPart.Parent then
			state.visualPart.LocalTransparencyModifier = 1
		end
	end
	self._visualActive = false
end

function SoftBodyCharacter._destroyVisualModel(self: SoftBodyCharacter): ()
	const visualModel = self._visualModel
	self._visualModel = nil
	self._visualMaid:Destroy()
	table.clear(self._visualParts)
	table.clear(self._visualBones)
	if visualModel then
		visualModel:Destroy()
	end
end

function SoftBodyCharacter.Destroy(self: SoftBodyCharacter): ()
	if self._destroyed then
		return
	end
	self:_deactivateVisual()
	self:_destroyVisualModel()
	self._destroyed = true
	self._maid:Destroy()
	setmetatable(self, nil)
end

return SoftBodyCharacter
