--!strict
--[=[
	Registers server Cmdr commands and game-config-backed argument types.

	@class GameConfigCommandService
	@server
]=]

const TeleportService = game:GetService("TeleportService")

const require = require("../../../Loader").load()

const BadgeUtils = require("BadgeUtils")
const CmdrService = require("CmdrService")
const GameConfigCmdrUtils = require("GameConfigCmdrUtils")
const GameConfigService = require("GameConfigService")
const Maid = require("Maid")
const PlayerUtils = require("PlayerUtils")
const ServiceBag = require("ServiceBag")

const GameConfigCommandService = {}
GameConfigCommandService.ServiceName = "GameConfigCommandService"
GameConfigCommandService.ServerOnly = true

export type GameConfigCommandService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_cmdrService: CmdrService.CmdrService,
		_gameConfigService: GameConfigService.GameConfigService,
	},
	{} :: typeof({ __index = GameConfigCommandService })
))

function GameConfigCommandService.Init(self: GameConfigCommandService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._cmdrService = self._serviceBag:GetService(CmdrService)
	self._gameConfigService = self._serviceBag:GetService(GameConfigService)
end

function GameConfigCommandService.Start(self: GameConfigCommandService): ()
	const picker = self._gameConfigService:GetConfigPicker()
	self._maid:GivePromise(self._cmdrService:PromiseCmdr()):Then(function(cmdr)
		GameConfigCmdrUtils.registerAssetTypes(cmdr, picker)
	end)

	self._cmdrService:RegisterCommand({
		Name = "give-badge",
		Aliases = { "award-badge" },
		Description = "Awards a configured badge to one or more players.",
		Group = "GameConfig",
		Args = {
			{
				Name = "targets",
				Type = "players",
				Description = "Players to award the badge to.",
			},
			{
				Name = "badges",
				Type = "badgeIds",
				Description = "Configured badge keys or numeric IDs.",
			},
		},
	}, function(_context, players: { Player }, badgeIds: { number })
		const awards = {}
		for _, player in players do
			for _, badgeId in badgeIds do
				const success, result = BadgeUtils.promiseAwardBadge(player, badgeId):Yield()
				if not success then
					error(result)
				end
				table.insert(awards, `{PlayerUtils.formatName(player)} badge {badgeId}`)
			end
		end
		return `Awarded: {table.concat(awards, ", ")}`
	end)

	self._cmdrService:RegisterCommand({
		Name = "goto-place",
		Aliases = { "goto-named-place" },
		Description = "Teleports players to a configured place.",
		Group = "GameConfig",
		Args = {
			{
				Name = "players",
				Type = "players",
				Description = "Players to teleport.",
			},
			{
				Name = "place",
				Type = "place",
				Description = "Configured place key or numeric ID.",
			},
			{
				Name = "jobId",
				Type = "string",
				Description = "Optional destination server job ID.",
				Optional = true,
			},
		},
	}, function(context, players: { Player }, placeId: number, jobId: string?)
		assert(type(placeId) == "number" and placeId > 0, "Invalid place ID")
		context:Reply("Commencing teleport...")

		if jobId and jobId ~= "" and jobId ~= "-" then
			for _, player in players do
				TeleportService:TeleportToPlaceInstance(placeId, jobId, player)
			end
		else
			TeleportService:TeleportPartyAsync(placeId, players)
		end
		return "Teleported."
	end)
end

function GameConfigCommandService.Destroy(self: GameConfigCommandService): ()
	self._maid:Destroy()
end

return GameConfigCommandService
