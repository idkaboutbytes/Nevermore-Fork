--!strict
--[=[
	This service lets you shut down servers without losing players.
	When game.OnClose is called, players in the server are teleported into a reserved lobby server.
	When the reserved server starts up, it teleports everyone back into updated servers.

	@class SoftShutdownService
	@server
]=]

const Players = game:GetService("Players")
const RunService = game:GetService("RunService")
const Workspace = game:GetService("Workspace")

const require = require("../Loader").load()

const BindToCloseService = require("BindToCloseService")
const DataService = require("DataService")
const Maid = require("Maid")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const SoftShutdownConstants = require("SoftShutdownConstants")
const SoftShutdownTranslator = require("SoftShutdownTranslator")
const TeleportServiceUtils = require("TeleportServiceUtils")
const t = require("t")

const SoftShutdownService = {}
SoftShutdownService.ServiceName = "SoftShutdownService"
SoftShutdownService.ServerOnly = true

export type SoftShutdownService = typeof(setmetatable(
	{} :: {
		_maid: Maid.Maid,
		_serviceBag: ServiceBag.ServiceBag,
		_bindToCloseService: BindToCloseService.BindToCloseService,
		_dataService: DataService.DataService,
		_translator: any,
	},
	{} :: typeof({ __index = SoftShutdownService })
))

--[=[
	Initialize the service. Should be done via [ServiceBag].

	@param serviceBag ServiceBag
]=]
function SoftShutdownService.Init(self: SoftShutdownService, serviceBag: ServiceBag.ServiceBag): ()
	assert(not (self :: any)._serviceBag, "Already initialized")
	assert(t.table(serviceBag), "Bad serviceBag")
	self._serviceBag = serviceBag
	self._maid = Maid.new()

	self._bindToCloseService = self._serviceBag:GetService(BindToCloseService) :: any
	self._dataService = self._serviceBag:GetService(DataService)
	self._translator = self._serviceBag:GetService(SoftShutdownTranslator)
end

function SoftShutdownService.Start(self: SoftShutdownService): ()
	self:_promiseIsLobby():Then(function(isLobby: boolean)
		if isLobby then
			self:_promiseRedirectAllPlayers()
		else
			self._maid:GiveTask(self._bindToCloseService:RegisterPromiseOnCloseCallback(function()
				return self:_promiseTeleportPlayersToLobby()
			end))
		end
	end)
end

function SoftShutdownService._isReservedServer(_self: SoftShutdownService): boolean
	return game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0
end

function SoftShutdownService._promiseIsLobby(self: SoftShutdownService): Promise.Promise<boolean>
	return Promise.resolved(self:_isReservedServer())
end

function SoftShutdownService._promiseTeleportPlayersToLobby(self: SoftShutdownService): Promise.Promise<()>
	const players = Players:GetPlayers()
	if RunService:IsStudio() or #players == 0 or game.JobId == "" then
		return Promise.resolved()
	end

	Workspace:SetAttribute(SoftShutdownConstants.IS_SOFT_SHUTDOWN_UPDATING_ATTRIBUTE, true)

	return self._dataService:SaveAllProfilesAsync():Then(function()
		const initialTeleportOptions = Instance.new("TeleportOptions")
		initialTeleportOptions.ShouldReserveServer = true
		initialTeleportOptions:SetTeleportData({
			isSoftShutdownReserveServer = true,
		})

		-- Collect any players remaining
		const remainingPlayers: { Player } = {}
		(self._maid :: any)._playerAddedCollector = Players.PlayerAdded:Connect(function(player: Player)
			table.insert(remainingPlayers, player)
		end)

		return Promise.spawn(function(resolve, _reject)
			-- Wait to let the teleport GUI be set
			task.delay(1, resolve)
		end)
			:Then(function()
				return TeleportServiceUtils.promiseTeleport(game.PlaceId, players, initialTeleportOptions)
			end)
			:Then(function(teleportResult: TeleportAsyncResult)
				(self._maid :: any)._playerAddedCollector = nil

				-- Construct new teleport options
				const newTeleportOptions = Instance.new("TeleportOptions")
				newTeleportOptions.ServerInstanceId = teleportResult.PrivateServerId
				newTeleportOptions.ReservedServerAccessCode = teleportResult.ReservedServerAccessCode
				newTeleportOptions:SetTeleportData({
					isSoftShutdownReserveServer = true,
				})

				-- Teleport any players that joined during initial teleport
				const promises = {}

				if #remainingPlayers > 0 then
					table.insert(
						promises,
						TeleportServiceUtils.promiseTeleport(game.PlaceId, remainingPlayers, newTeleportOptions)
					)
				end

				self._maid:GiveTask(Players.PlayerAdded:Connect(function(player: Player)
					table.insert(
						promises,
						TeleportServiceUtils.promiseTeleport(game.PlaceId, { player }, newTeleportOptions)
					)
				end))

				return Promise.spawn(function(resolve)
					while #Players:GetPlayers() > 0 and self:_containsPending(promises) do
						task.wait(1)
					end

					resolve()
				end)
			end)
	end)
end

function SoftShutdownService._containsPending(_self: SoftShutdownService, promises: { any }): boolean
	for _, item in promises do
		if item:IsPending() then
			return true
		end
	end

	return false
end

function SoftShutdownService._promiseRedirectAllPlayers(self: SoftShutdownService): Promise.Promise<()>
	Workspace:SetAttribute(SoftShutdownConstants.IS_SOFT_SHUTDOWN_LOBBY_ATTRIBUTE, true)

	-- Wait for some players
	return Promise.spawn(function(resolve, reject)
		task.wait(1) -- Let the teleport GUI be set
		local players = Players:GetPlayers()
		while #players <= 0 do
			task.wait(1)
			players = Players:GetPlayers()
		end

		self._maid:GiveTask(reject)

		resolve(players)
	end):Then(function(players: { Player })
		const teleportOptions = Instance.new("TeleportOptions")
		teleportOptions:SetTeleportData({
			isSoftShutdownArrivingIntoUpdatedServer = true,
		})

		-- Teleport all remaining players
		self._maid:GiveTask(Players.PlayerAdded:Connect(function(player: Player)
			task.wait(1) -- Let the teleport GUI be set
			TeleportServiceUtils.promiseTeleport(game.PlaceId, { player }, teleportOptions)
		end))

		-- Try to keep players in the same group
		return TeleportServiceUtils.promiseTeleport(game.PlaceId, players, teleportOptions)
	end)
end

function SoftShutdownService.Destroy(self: SoftShutdownService): ()
	self._maid:DoCleaning()
end

return SoftShutdownService
