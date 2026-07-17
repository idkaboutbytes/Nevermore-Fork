--!strict
--!optimize 2
--[=[
	Maintains lightweight server-side flock groups and computes planar crowd
	steering without allocating per simulation step.

	@class SimulatedCharacterFlocking
]=]

const require = require("../../Loader").load()

const Maid = require("Maid")
const SimulatedCharacterConstants = require("SimulatedCharacterConstants")
const TableUtils = require("TableUtils")

const NEIGHBOR_RADIUS_SQUARED = SimulatedCharacterConstants.DEFAULT_FLOCK_NEIGHBOR_RADIUS ^ 2

type FlockCharacterDefinition = {
	FlockGroup: string,
	HitboxRadius: number,
}

type FlockCharacter = {
	_id: number,
	_flockIndex: number,
	_flockSeparation: Vector2,
	_flockSteering: Vector2,
	_definition: FlockCharacterDefinition,
	_mode: number,
	_position: Vector2,
	_velocity: Vector2,
}

type FlockGroup = {
	characters: { FlockCharacter },
}

const SimulatedCharacterFlocking = {}
SimulatedCharacterFlocking.ClassName = "SimulatedCharacterFlocking"
SimulatedCharacterFlocking.__index = SimulatedCharacterFlocking

export type SimulatedCharacterFlocking = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_groups: { [string]: FlockGroup },
	},
	SimulatedCharacterFlocking
))

function SimulatedCharacterFlocking.new(): SimulatedCharacterFlocking
	const self: SimulatedCharacterFlocking = setmetatable({} :: any, SimulatedCharacterFlocking)
	self._maid = Maid.new()
	self._groups = {}
	return self
end

--[=[
	Adds an internal simulated character to its configured flock group.

	@within SimulatedCharacterFlocking
	@param character FlockCharacter
]=]
function SimulatedCharacterFlocking.AddCharacter(self: SimulatedCharacterFlocking, character: FlockCharacter)
	const groupName = character._definition.FlockGroup
	character._flockIndex = 0
	character._flockSeparation = Vector2.zero
	character._flockSteering = Vector2.zero
	if groupName == "" then
		return
	end

	local group = self._groups[groupName]
	if not group then
		group = {
			characters = {},
		}
		self._groups[groupName] = group
	end

	character._flockIndex = #group.characters + 1
	table.insert(group.characters, character)
end

--[=[
	Removes an internal simulated character from its flock group.

	@within SimulatedCharacterFlocking
	@param character FlockCharacter
]=]
function SimulatedCharacterFlocking.RemoveCharacter(self: SimulatedCharacterFlocking, character: FlockCharacter)
	const groupName = character._definition.FlockGroup
	const index = character._flockIndex
	character._flockIndex = 0
	character._flockSeparation = Vector2.zero
	character._flockSteering = Vector2.zero
	if groupName == "" or index == 0 then
		return
	end

	const group = self._groups[groupName]
	if not group or group.characters[index] ~= character then
		return
	end

	const lastCharacter = group.characters[#group.characters]
	TableUtils.swapRemove(group.characters, index)
	if lastCharacter and lastCharacter ~= character then
		lastCharacter._flockIndex = index
	end
	if #group.characters == 0 then
		self._groups[groupName] = nil
	end
end

--[=[
	Computes the steering contribution for every active flock member.

	@within SimulatedCharacterFlocking
]=]
function SimulatedCharacterFlocking.Step(self: SimulatedCharacterFlocking)
	for _, group in self._groups do
		const characters = group.characters
		for _, character in characters do
			character._flockSeparation = Vector2.zero
			character._flockSteering = Vector2.zero
			if character._mode ~= SimulatedCharacterConstants.Modes.KINEMATIC then
				continue
			end

			const position = character._position
			local separation = Vector2.zero
			local alignment = Vector2.zero
			local center = Vector2.zero
			local neighborCount = 0
			for _, neighbor in characters do
				if neighbor == character or neighbor._mode ~= SimulatedCharacterConstants.Modes.KINEMATIC then
					continue
				end

				local delta = neighbor._position - position
				const distanceSquared = delta:Dot(delta)
				if distanceSquared > NEIGHBOR_RADIUS_SQUARED then
					continue
				end

				neighborCount += 1
				alignment += neighbor._velocity
				center += neighbor._position
				const separationDistance = character._definition.HitboxRadius
					+ neighbor._definition.HitboxRadius
					+ SimulatedCharacterConstants.DEFAULT_FLOCK_SEPARATION_PADDING
				if distanceSquared > 1e-6 then
					const distance = math.sqrt(distanceSquared)
					if distance < separationDistance then
						separation -= delta / distance * (1 - distance / separationDistance)
					end
				else
					const lowerId = math.min(character._id, neighbor._id)
					const upperId = math.max(character._id, neighbor._id)
					const angle = (lowerId * 97 + upperId * 57) % 6283 / 1000
					delta = Vector2.new(math.cos(angle), math.sin(angle))
					separation += if character._id == lowerId then delta else -delta
				end
			end

			if neighborCount == 0 then
				continue
			end

			const separationMagnitude = separation.Magnitude
			if separationMagnitude > 1 then
				separation /= separationMagnitude
			end
			const weightedSeparation = separation * SimulatedCharacterConstants.DEFAULT_FLOCK_SEPARATION_WEIGHT
			local steering = weightedSeparation
			const alignmentMagnitude = alignment.Magnitude
			if alignmentMagnitude > 1e-4 then
				steering += alignment / alignmentMagnitude * SimulatedCharacterConstants.DEFAULT_FLOCK_ALIGNMENT_WEIGHT
			end
			const cohesionDelta = center / neighborCount - position
			const cohesionMagnitude = cohesionDelta.Magnitude
			if cohesionMagnitude > 1e-4 then
				steering += cohesionDelta / cohesionMagnitude * SimulatedCharacterConstants.DEFAULT_FLOCK_COHESION_WEIGHT
			end

			const steeringMagnitude = steering.Magnitude
			if steeringMagnitude > SimulatedCharacterConstants.DEFAULT_FLOCK_MAX_STEERING then
				steering = steering / steeringMagnitude * SimulatedCharacterConstants.DEFAULT_FLOCK_MAX_STEERING
			end
			character._flockSeparation = weightedSeparation
			character._flockSteering = steering
		end
	end
end

function SimulatedCharacterFlocking.Destroy(self: SimulatedCharacterFlocking)
	for _, group in self._groups do
		for _, character in group.characters do
			character._flockIndex = 0
			character._flockSeparation = Vector2.zero
			character._flockSteering = Vector2.zero
		end
	end
	self._maid:DoCleaning()
	table.clear(self)
	setmetatable(self, nil)
end

return SimulatedCharacterFlocking
