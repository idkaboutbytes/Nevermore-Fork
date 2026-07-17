--!strict
--!optimize 2
--[=[
	Runs lightweight, server-authoritative simulated characters on a flat X/Z
	plane and replicates their render state to clients.

	@server
	@class SimulatedCharacterService
]=]

const RunService = game:GetService("RunService")

const require = require("../Loader").load()

const Maid = require("Maid")
const ServiceBag = require("ServiceBag")
const SimulatedCharacter = require("SimulatedCharacter")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const SimulatedCharacterNavigationGrid = require("SimulatedCharacterNavigationGrid")
const SimulatedCharacterNetwork = require("SimulatedCharacterNetwork")
const SimulatedCharacterTemplateProvider = require("SimulatedCharacterTemplateProvider")
const SimulatedCharacterTypes = require("SimulatedCharacterTypes")
const SimulatedCharacterUtils = require("SimulatedCharacterUtils")
const TableUtils = require("TableUtils")
const TimeSyncService = require("TimeSyncService")

const SimulatedCharacterService = {}
SimulatedCharacterService.ServiceName = "SimulatedCharacterService"
SimulatedCharacterService.ServerOnly = true

export type SimulatedCharacterService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_timeSyncService: TimeSyncService.TimeSyncService,
		_clock: TimeSyncService.SyncedClock,
		_templateProvider: any,
		_definitions: { [string]: SimulatedCharacterTypes.ResolvedCharacterDefinition },
		_charactersById: { [number]: SimulatedCharacter.SimulatedCharacter },
		_characters: { SimulatedCharacter.SimulatedCharacter },
		_nextCharacterId: number,
		_navigation: SimulatedCharacterNavigationGrid.SimulatedCharacterNavigationGrid?,
		_simulationAccumulator: number,
		_snapshotAccumulator: number,
	},
	{} :: typeof({ __index = SimulatedCharacterService })
))

function SimulatedCharacterService.Init(self: SimulatedCharacterService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._timeSyncService = self._serviceBag:GetService(TimeSyncService)
	self._clock = assert(self._timeSyncService:GetSyncedClock(), "Server clock is unavailable")
	self._templateProvider = self._serviceBag:GetService(SimulatedCharacterTemplateProvider)
	self._definitions = {}
	self._charactersById = {}
	self._characters = {}
	self._nextCharacterId = 1
	self._navigation = nil
	self._simulationAccumulator = 0
	self._snapshotAccumulator = 0

	SimulatedCharacterNetwork.queries.requestInitialState.listen(function(_, player: Player?)
		if not player then
			return {}
		end
		return self:_getInitialState()
	end)
end

function SimulatedCharacterService.Start(self: SimulatedCharacterService)
	self._maid:Add(RunService.Heartbeat:Connect(function(deltaTime: number)
		self:_step(deltaTime)
	end))
end

--[=[
	Configures explicit X/Z navigation bounds and the tagged obstacle grid.

	```lua
	SimulatedCharacterService:ConfigureNavigation({
		Min = Vector2.new(-512, -512),
		Max = Vector2.new(512, 512),
		CellSize = 4,
		ObstacleTag = "SimulatedCharacterObstacle",
	})
	```

	@within SimulatedCharacterService
	@param config NavigationConfig
]=]
function SimulatedCharacterService.ConfigureNavigation(
	self: SimulatedCharacterService,
	config: SimulatedCharacterTypes.NavigationConfig
)
	const navigation = SimulatedCharacterNavigationGrid.new(config)
	self._navigation = navigation
	self._maid._navigation = navigation
end

--[=[
	Rebuilds the navigation grid after moving or resizing tagged obstacles.

	@within SimulatedCharacterService
]=]
function SimulatedCharacterService.RebuildNavigation(self: SimulatedCharacterService)
	const navigation = self._navigation
	if navigation then
		navigation:Rebuild()
	end
end

--[=[
	Registers a character archetype.

	@within SimulatedCharacterService
	@param name string
	@param definition CharacterDefinition
	@return ResolvedCharacterDefinition
]=]
function SimulatedCharacterService.RegisterCharacter(
	self: SimulatedCharacterService,
	name: string,
	definition: SimulatedCharacterTypes.CharacterDefinition
): SimulatedCharacterTypes.ResolvedCharacterDefinition
	assert(self._definitions[name] == nil, `Character definition {name} is already registered`)
	const resolvedDefinition = SimulatedCharacterUtils.resolveDefinition(name, definition)
	self._definitions[name] = resolvedDefinition
	return resolvedDefinition
end

--[=[
	Spawns a server-authoritative simulated character.

	@within SimulatedCharacterService
	@param definitionName string
	@param spawnData SpawnData?
	@return SimulatedCharacter
]=]
function SimulatedCharacterService.SpawnCharacter(
	self: SimulatedCharacterService,
	definitionName: string,
	spawnData: SimulatedCharacterTypes.SpawnData?
): SimulatedCharacter.SimulatedCharacter
	assert(type(definitionName) == "string", "Bad definitionName")
	const definition = assert(self._definitions[definitionName], `Unknown character definition {definitionName}`)
	const data = spawnData or {}
	assert(type(data) == "table", "Bad spawnData")
	assert(data.CFrame == nil or typeof(data.CFrame) == "CFrame", "Bad spawnData.CFrame")
	assert(data.Position == nil or typeof(data.Position) == "Vector2", "Bad spawnData.Position")
	assert(data.GroundY == nil or type(data.GroundY) == "number", "Bad spawnData.GroundY")
	assert(data.Yaw == nil or type(data.Yaw) == "number", "Bad spawnData.Yaw")
	assert(data.Ragdolled == nil or type(data.Ragdolled) == "boolean", "Bad spawnData.Ragdolled")

	local position = data.Position or Vector2.zero
	local groundY = data.GroundY or 0
	local yaw = data.Yaw or 0
	if data.CFrame then
		const cframe = data.CFrame
		const worldPosition = cframe.Position
		position = Vector2.new(worldPosition.X, worldPosition.Z)
		groundY = worldPosition.Y
		yaw = math.atan2(-cframe.LookVector.X, -cframe.LookVector.Z)
	end

	const id = self._nextCharacterId
	assert(id <= 4_294_967_295, "Simulated character id space exhausted")
	self._nextCharacterId += 1

	const character = SimulatedCharacter.new(self, id, definition, position, groundY, yaw, data.Ragdolled == true)
	character._listIndex = #self._characters + 1
	self._charactersById[id] = character
	table.insert(self._characters, character)

	SimulatedCharacterNetwork.packets.spawned.sendToAll(self:_toNetworkSpawn(character))
	return character
end

--[=[
	Removes a character by handle or numeric id. This method is idempotent.

	@within SimulatedCharacterService
	@param characterOrId SimulatedCharacter | number
]=]
function SimulatedCharacterService.RemoveCharacter(
	self: SimulatedCharacterService,
	characterOrId: SimulatedCharacter.SimulatedCharacter | number
)
	const character = if type(characterOrId) == "number"
		then self._charactersById[characterOrId]
		else characterOrId :: SimulatedCharacter.SimulatedCharacter
	if not character or self._charactersById[character._id] ~= character then
		return
	end

	const id = character._id
	self._charactersById[id] = nil
	const index = character._listIndex
	const lastCharacter = self._characters[#self._characters]
	TableUtils.swapRemove(self._characters, index)
	if lastCharacter and lastCharacter ~= character then
		lastCharacter._listIndex = index
	end

	SimulatedCharacterNetwork.packets.removed.sendToAll(id)
	character:_destroyInternal()
end

--[=[
	Returns a character by numeric id.

	@within SimulatedCharacterService
	@param id number
	@return SimulatedCharacter?
]=]
function SimulatedCharacterService.GetCharacter(
	self: SimulatedCharacterService,
	id: number
): SimulatedCharacter.SimulatedCharacter?
	return self._charactersById[id]
end

--[=[
	Returns a snapshot array of all current character handles.

	@within SimulatedCharacterService
	@return { SimulatedCharacter }
]=]
function SimulatedCharacterService.GetCharacters(
	self: SimulatedCharacterService
): { SimulatedCharacter.SimulatedCharacter }
	return table.clone(self._characters)
end

function SimulatedCharacterService._getTime(self: SimulatedCharacterService): number
	return self._clock:GetTime()
end

function SimulatedCharacterService._step(self: SimulatedCharacterService, deltaTime: number)
	const simulationStep = 1 / SimulatedCharacterConstants.DEFAULT_SIMULATION_RATE
	const snapshotStep = 1 / SimulatedCharacterConstants.DEFAULT_SNAPSHOT_RATE
	const boundedDelta = math.min(deltaTime, 0.25)
	self._simulationAccumulator += boundedDelta
	self._snapshotAccumulator += boundedDelta

	local simulationCount = 0
	while self._simulationAccumulator >= simulationStep and simulationCount < 5 do
		self._simulationAccumulator -= simulationStep
		simulationCount += 1
		for _, character in self._characters do
			character:_step(simulationStep, self._navigation)
		end
	end

	if self._snapshotAccumulator >= snapshotStep then
		self._snapshotAccumulator %= snapshotStep
		self:_sendSnapshot()
	end
end

function SimulatedCharacterService._sendSnapshot(self: SimulatedCharacterService)
	if #self._characters == 0 then
		return
	end

	const states = table.create(#self._characters)
	for index, character in self._characters do
		states[index] = character:_getNetworkState()
	end

	SimulatedCharacterNetwork.packets.snapshot.sendToAll({
		serverTime = self:_getTime(),
		characters = states,
	})
end

function SimulatedCharacterService._onCharacterStateChanged(
	self: SimulatedCharacterService,
	character: SimulatedCharacter.SimulatedCharacter
)
	if self._charactersById[character._id] == character then
		SimulatedCharacterNetwork.packets.stateChanged.sendToAll({
			serverTime = self:_getTime(),
			state = character:_getNetworkState(),
		})
	end
end

function SimulatedCharacterService._toNetworkDefinition(
	_self: SimulatedCharacterService,
	definition: SimulatedCharacterTypes.ResolvedCharacterDefinition
): SimulatedCharacterTypes.NetworkDefinition
	return {
		name = definition.Name,
		templateName = definition.TemplateName,
		cullDistance = definition.CullDistance,
		hitboxRadius = definition.HitboxRadius,
		idleAnimationId = definition.IdleAnimationId,
		walkAnimationId = definition.WalkAnimationId,
		useDefaultAnimations = definition.UseDefaultAnimations,
	}
end

function SimulatedCharacterService._toNetworkSpawn(
	self: SimulatedCharacterService,
	character: SimulatedCharacter.SimulatedCharacter
): SimulatedCharacterTypes.NetworkSpawn
	return {
		serverTime = self:_getTime(),
		definition = self:_toNetworkDefinition(character._definition),
		state = character:_getNetworkState(),
	}
end

function SimulatedCharacterService._getInitialState(
	self: SimulatedCharacterService
): { SimulatedCharacterTypes.NetworkSpawn }
	const result = table.create(#self._characters)
	for index, character in self._characters do
		result[index] = self:_toNetworkSpawn(character)
	end
	return result
end

function SimulatedCharacterService.Destroy(self: SimulatedCharacterService)
	while #self._characters > 0 do
		self:RemoveCharacter(self._characters[#self._characters])
	end
	self._maid:DoCleaning()
end

return SimulatedCharacterService
