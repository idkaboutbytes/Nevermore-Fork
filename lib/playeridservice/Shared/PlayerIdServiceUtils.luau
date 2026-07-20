--!strict
--[=[
	Validated access to the replicated uint8 player identifier.

	@util PlayerIdServiceUtils
]=]

const require = require("../../Loader").load()

const Observable = require("Observable")
const PlayerIdServiceConstants = require("PlayerIdServiceConstants")
const Rx = require("Rx")
const RxAttributeUtils = require("RxAttributeUtils")
const t = require("t")

const PlayerIdServiceUtils = {}

function PlayerIdServiceUtils.isPlayerId(value: any): boolean
	return type(value) == "number"
		and value % 1 == 0
		and value >= PlayerIdServiceConstants.MIN_PLAYER_ID
		and value <= PlayerIdServiceConstants.MAX_PLAYER_ID
end

--[=[
	Returns a player's current replicated ID, or nil while unassigned.

	@param player Player
	@return number?
]=]
function PlayerIdServiceUtils.getId(player: Player): number?
	assert(t.instanceIsA("Player")(player), "Bad player")
	const value = player:GetAttribute(PlayerIdServiceConstants.PLAYER_ID_ATTRIBUTE)
	return if PlayerIdServiceUtils.isPlayerId(value) then value :: number else nil
end

--[=[
	Observes a player's validated replicated ID. Emits nil while unassigned.

	@param player Player
	@return Observable<number?>
]=]
function PlayerIdServiceUtils.observeId(player: Player): Observable.Observable<number?>
	assert(t.instanceIsA("Player")(player), "Bad player")
	return RxAttributeUtils.observeAttribute(player, PlayerIdServiceConstants.PLAYER_ID_ATTRIBUTE):Pipe({
		Rx.map(function(value)
			return if PlayerIdServiceUtils.isPlayerId(value) then value :: number else nil
		end) :: any,
		Rx.distinct() :: any,
	}) :: any
end

return PlayerIdServiceUtils
