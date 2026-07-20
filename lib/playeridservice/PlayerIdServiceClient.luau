--!strict
--[=[
	Client mirror for reading and observing server-assigned uint8 player IDs.

	@class PlayerIdServiceClient
	@client
]=]

const Players = game:GetService("Players")

const require = require("../Loader").load()

const Maid = require("Maid")
const Observable = require("Observable")
const PlayerIdServiceInterface = require("PlayerIdServiceInterface")
const PlayerIdServiceUtils = require("PlayerIdServiceUtils")
const ServiceBag = require("ServiceBag")
const TieRealmService = require("TieRealmService")

const PlayerIdServiceClient = {}
PlayerIdServiceClient.ServiceName = "PlayerIdServiceClient"

export type PlayerIdServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
	},
	{} :: typeof({ __index = PlayerIdServiceClient })
))

function PlayerIdServiceClient.Init(self: PlayerIdServiceClient, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._serviceBag:GetService(TieRealmService)
	self._maid:Add((PlayerIdServiceInterface :: any).Client:Implement(Players, self))
end

function PlayerIdServiceClient.GetId(_self: PlayerIdServiceClient, player: Player): number?
	return PlayerIdServiceUtils.getId(player)
end

function PlayerIdServiceClient.Observe(_self: PlayerIdServiceClient, player: Player): Observable.Observable<number?>
	return PlayerIdServiceUtils.observeId(player)
end

PlayerIdServiceClient.ObserveId = PlayerIdServiceClient.Observe

function PlayerIdServiceClient.Destroy(self: PlayerIdServiceClient): ()
	self._maid:Destroy()
end

return PlayerIdServiceClient
