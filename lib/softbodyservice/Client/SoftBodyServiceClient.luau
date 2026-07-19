--!strict
--!optimize 2
--[=[
	Coordinates lightweight, client-only soft-body animation for player characters
	and explicitly registered character models.

	@class SoftBodyServiceClient
	@client
]=]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")
const HttpService = game:GetService("HttpService")

const require = require("../../Loader").load()

const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const SoundEffectService = require("SoundEffectService")
const SoftBodyCharacter = require("SoftBodyCharacter")
const SoftBodyConfigUtils = require("SoftBodyConfigUtils")
const WellKnownSoundGroups = require("WellKnownSoundGroups")

type SoftBodyConfig = SoftBodyConfigUtils.SoftBodyConfig
type SoftBodyConfigPatch = SoftBodyConfigUtils.SoftBodyConfigPatch

const SoftBodyServiceClient = {}
SoftBodyServiceClient.ServiceName = "SoftBodyServiceClient"

export type SoftBodyServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_characters: { [Model]: SoftBodyCharacter.SoftBodyCharacter },
		_automaticCharacters: { [Model]: boolean },
		_visualFolder: Folder,
		_sfxSoundGroup: SoundGroup,
		_renderStepName: string,
		_config: SoftBodyConfig,
		_enabled: boolean,
		_affectOtherPlayers: boolean,
		_started: boolean,
		_destroyed: boolean,
	},
	{} :: typeof({ __index = SoftBodyServiceClient })
))

function SoftBodyServiceClient.Init(self: SoftBodyServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._characters = {}
	self._automaticCharacters = {}
	const soundEffectService = self._serviceBag:GetService(SoundEffectService)
	self._sfxSoundGroup = soundEffectService:GetOrCreateSoundGroup(WellKnownSoundGroups.SFX)
	const visualFolder = Instance.new("Folder")
	visualFolder.Name = "SoftBodyCharacters"
	visualFolder.Parent = workspace
	self._visualFolder = self._maid:Add(visualFolder)
	self._renderStepName = `SoftBodyServiceClient_{HttpService:GenerateGUID(false)}`
	self._config = SoftBodyConfigUtils.resolve()
	self._enabled = true
	self._affectOtherPlayers = true
	self._started = false
	self._destroyed = false
end

function SoftBodyServiceClient.Start(self: SoftBodyServiceClient): ()
	assert(not self._started, "Already started")
	self._started = true
	self:_bindPlayers()

	RunService:BindToRenderStep(self._renderStepName, Enum.RenderPriority.Last.Value, function()
		for _, character in self._characters do
			character:_render()
		end
	end)
	self._maid:Add(function()
		RunService:UnbindFromRenderStep(self._renderStepName)
	end)
end

--[=[
	Applies a partial configuration to the defaults and every currently tracked
	character.

	@within SoftBodyServiceClient
	@param config SoftBodyConfigPatch
]=]
function SoftBodyServiceClient.Configure(self: SoftBodyServiceClient, config: SoftBodyConfigPatch): ()
	assert(not self._destroyed, "SoftBodyServiceClient is destroyed")
	self._config = SoftBodyConfigUtils.resolve(config, self._config)
	for _, character in self._characters do
		character:Configure(config)
	end
end

--[=[
	Returns a copy of the service's resolved default configuration.

	@within SoftBodyServiceClient
	@return SoftBodyConfig
]=]
function SoftBodyServiceClient.GetConfig(self: SoftBodyServiceClient): SoftBodyConfig
	return table.clone(self._config)
end

--[=[
	Enables or disables deformation for every tracked character.

	@within SoftBodyServiceClient
	@param enabled boolean
]=]
function SoftBodyServiceClient.SetEnabled(self: SoftBodyServiceClient, enabled: boolean): ()
	assert(type(enabled) == "boolean", "Bad enabled")
	assert(not self._destroyed, "SoftBodyServiceClient is destroyed")
	if self._enabled == enabled then
		return
	end

	self._enabled = enabled
	for _, character in self._characters do
		character:SetEnabled(enabled)
	end
end

--[=[
	Returns whether the service is enabled.

	@within SoftBodyServiceClient
	@return boolean
]=]
function SoftBodyServiceClient.IsEnabled(self: SoftBodyServiceClient): boolean
	return self._enabled
end

--[=[
	Controls whether remote player characters are tracked. The local character is
	always tracked. This defaults to `true`.

	@within SoftBodyServiceClient
	@param affectOtherPlayers boolean
]=]
function SoftBodyServiceClient.SetAffectOtherPlayers(self: SoftBodyServiceClient, affectOtherPlayers: boolean): ()
	assert(type(affectOtherPlayers) == "boolean", "Bad affectOtherPlayers")
	assert(not self._destroyed, "SoftBodyServiceClient is destroyed")
	if self._affectOtherPlayers == affectOtherPlayers then
		return
	end

	self._affectOtherPlayers = affectOtherPlayers
	if self._started then
		self:_bindPlayers()
	end
end

--[=[
	Registers any humanoid character, including an NPC. Repeated registration
	returns the cached controller instead of creating duplicates.

	@within SoftBodyServiceClient
	@param character Model
	@param config SoftBodyConfigPatch?
	@return SoftBodyCharacter
]=]
function SoftBodyServiceClient.RegisterCharacter(
	self: SoftBodyServiceClient,
	character: Model,
	config: SoftBodyConfigPatch?
): SoftBodyCharacter.SoftBodyCharacter
	assert(typeof(character) == "Instance" and character:IsA("Model"), "Bad character")
	assert(not self._destroyed, "SoftBodyServiceClient is destroyed")
	const existing = self._characters[character]
	if existing then
		if config then
			existing:Configure(config)
		end
		return existing
	end

	const resolvedConfig = SoftBodyConfigUtils.resolve(config, self._config)
	const softBodyCharacter = SoftBodyCharacter.new(character, resolvedConfig, self._visualFolder, self._sfxSoundGroup)
	softBodyCharacter:SetEnabled(self._enabled)
	self._characters[character] = softBodyCharacter
	return softBodyCharacter
end

--[=[
	Stops tracking a character, restores its local visibility, and destroys its
	visual proxy.

	@within SoftBodyServiceClient
	@param character Model
	@return boolean
]=]
function SoftBodyServiceClient.UnregisterCharacter(self: SoftBodyServiceClient, character: Model): boolean
	assert(typeof(character) == "Instance" and character:IsA("Model"), "Bad character")
	const softBodyCharacter = self._characters[character]
	if not softBodyCharacter then
		return false
	end

	self._characters[character] = nil
	self._automaticCharacters[character] = nil
	softBodyCharacter:Destroy()
	return true
end

--[=[
	Returns the cached controller for a character, if it is tracked.

	@within SoftBodyServiceClient
	@param character Model
	@return SoftBodyCharacter?
]=]
function SoftBodyServiceClient.GetCharacter(
	self: SoftBodyServiceClient,
	character: Model
): SoftBodyCharacter.SoftBodyCharacter?
	return self._characters[character]
end

--[=[
	Triggers a visual squash or stretch on a tracked character. Positive amounts
	squash and negative amounts stretch. Returns false when the character is not
	tracked.

	@within SoftBodyServiceClient
	@param character Model
	@param amount number?
	@return boolean
]=]
function SoftBodyServiceClient.Impulse(self: SoftBodyServiceClient, character: Model, amount: number?): boolean
	assert(typeof(character) == "Instance" and character:IsA("Model"), "Bad character")
	const softBodyCharacter = self._characters[character]
	if not softBodyCharacter then
		return false
	end

	softBodyCharacter:Impulse(amount)
	return true
end

function SoftBodyServiceClient._bindPlayers(self: SoftBodyServiceClient): ()
	const maid = Maid.new()
	self._maid._players = maid
	const localPlayer = Players.LocalPlayer

	local function bindPlayer(player: Player)
		if player ~= localPlayer and not self._affectOtherPlayers then
			return
		end

		const playerMaid = Maid.new()
		local currentCharacter: Model? = nil
		local function handleCharacter(character: Model)
			playerMaid._character = nil
			currentCharacter = character
			self._automaticCharacters[character] = true
			self:RegisterCharacter(character)
			playerMaid._character = function()
				if currentCharacter == character and self._automaticCharacters[character] then
					currentCharacter = nil
					self:UnregisterCharacter(character)
				end
			end
		end

		playerMaid:Add(player.CharacterAdded:Connect(handleCharacter))
		if player.Character then
			handleCharacter(player.Character)
		end
		maid[player] = playerMaid
	end

	maid:Add(Players.PlayerAdded:Connect(bindPlayer))
	maid:Add(Players.PlayerRemoving:Connect(function(player)
		maid[player] = nil
	end))
	for _, player in Players:GetPlayers() do
		bindPlayer(player)
	end
end

function SoftBodyServiceClient.Destroy(self: SoftBodyServiceClient): ()
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._maid:Destroy()
	for character, softBodyCharacter in self._characters do
		self._characters[character] = nil
		softBodyCharacter:Destroy()
	end
	table.clear(self._automaticCharacters)
end

return SoftBodyServiceClient
