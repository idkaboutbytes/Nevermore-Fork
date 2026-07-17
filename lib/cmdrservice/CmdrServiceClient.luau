--!strict
--[=[
	@class CmdrServiceClient
]=]

const Players = game:GetService("Players")
const ReplicatedStorage = game:GetService("ReplicatedStorage")
const require = require("../Loader").load()

const Maid = require("Maid")
const PermissionServiceClient = require("PermissionServiceClient")
const Promise = require("Promise")
const PromiseUtils = require("PromiseUtils")
const PromiseInstanceUtils = require("PromiseInstanceUtils")
const ServiceBag = require("ServiceBag")
const StringUtils = require("StringUtils")
const CmdrServiceNetwork = require("CmdrServiceNetwork")

const Player = Players.LocalPlayer

const CmdrServiceClient = {}
CmdrServiceClient.ServiceName = "CmdrServiceClient"

export type CmdrServiceClient = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_permissionServiceClient: PermissionServiceClient.PermissionServiceClient,

		_cmdrPromise: Promise.Promise<any>,
		_cmdrBindingMaid: Maid.Maid?,
	},
	{} :: typeof({ __index = CmdrServiceClient })
))

function CmdrServiceClient.Init(self: CmdrServiceClient, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._permissionServiceClient = self._serviceBag:GetService(PermissionServiceClient)

	-- Listening before asking, so a command registered on the server between our
	-- request and our registry coming up is not missed. Re-registering is
	-- harmless -- Cmdr replaces by name.
	CmdrServiceNetwork.packets.commandsReplicated.listen(function(definitions: { any })
		self:PromiseCmdr():Then(function(cmdrClient)
			for _, definition in definitions do
				cmdrClient.Registry:RegisterCommandObject(definition)
			end
		end)
	end)

	self:PromiseCmdr():Then(function(cmdrClient)
		local store = cmdrClient.Registry:GetStore("ServiceBag")
		store.ServiceBag = self._serviceBag

		cmdrClient.Registry:RegisterHook("BeforeRun", function(context)
			if not context.Executor then
				return
			end

			const permissionPromise = self._permissionServiceClient:PromiseIsAdmin(context.Executor)
			if permissionPromise:IsPending() then
				return "Still loading permissions"
			end

			const hasAdminPermission, isAdmin = permissionPromise:Yield()
			if not hasAdminPermission then
				return "Failed to check admin permissions"
			end

			if not isAdmin then
				return "You don't have permission to run this command"
			end

			return nil
		end)
	end)
end

function CmdrServiceClient.Start(self: CmdrServiceClient)
	task.spawn(function()
		PromiseUtils.all({
			self:PromiseCmdr(),
			self._permissionServiceClient:PromisePermissionProvider(),
		})
			:Then(function(cmdrClient, permissionProvider)
				CmdrServiceNetwork.packets.commandsRequested.send(nil)

				self._maid:GiveTask(permissionProvider:ObserveIsAdmin():Subscribe(function(isAdmin)
					if isAdmin then
						self._setCmdrBindings(self, cmdrClient)
					else
						self._clearCmdrBindings(self, cmdrClient)
					end
				end))
			end)
			:Catch(error)
	end)
end

--[=[
	Returns the Cmdr client instance in a promise

	@within CmdrServiceClient
	@return Promise<any>
]=]
function CmdrServiceClient.PromiseCmdr(self: CmdrServiceClient)
	if self._cmdrPromise then
		return self._cmdrPromise
	end

	self._cmdrPromise = PromiseInstanceUtils.promiseChild(ReplicatedStorage, "CmdrClient")
		:Then(function(cmdrClient)
			return Promise.spawn(function(resolve)
				return resolve(require(cmdrClient))
			end)
		end)
		:Then(function(cmdrClient)
			return cmdrClient
		end)
		:Catch(error)

	return self._cmdrPromise :: Promise.Promise<any> | any
end

function CmdrServiceClient._setCmdrBindings(self: CmdrServiceClient, cmdrClient)
	if self._cmdrBindingMaid then
		return
	end

	const cmdrBindingMaid = Maid.new()
	self._cmdrBindingMaid = cmdrBindingMaid
	cmdrClient:SetActivationUnlocksMouse(true)
	cmdrClient:SetActivationKeys({ Enum.KeyCode.Semicolon })

	cmdrBindingMaid:GiveTask(Player.Chatted:Connect(function(message: string)
		if StringUtils.startsWith(message, "/cmdr") then
			cmdrClient:Show()
		end
	end))
end

function CmdrServiceClient._clearCmdrBindings(self: CmdrServiceClient, cmdrClient)
	if self._cmdrBindingMaid then
		self._cmdrBindingMaid:DoCleaning()
		self._cmdrBindingMaid = nil
	end

	cmdrClient:SetActivationKeys({})
	cmdrClient:Hide()
end

return CmdrServiceClient
