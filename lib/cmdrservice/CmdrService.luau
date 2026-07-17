--!strict
--[=[
	@class CmdrService
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const PermissionService = require("PermissionService")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const CmdrServiceUtils = require("CmdrServiceUtils")

const CmdrService = {}
CmdrService.ServiceName = "CmdrService"
CmdrService.ServerOnly = true

export type CmdrService = typeof(setmetatable(
	{} :: {
		_serviceBag: ServiceBag.ServiceBag,
		_maid: Maid.Maid,
		_permissionService: PermissionService.PermissionService,
		_promiseCmdr: Promise.Promise<any>,
	},
	{} :: typeof({ __index = CmdrService })
))

function CmdrService.Init(self: CmdrService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._permissionService = self._serviceBag:GetService(PermissionService)

	self._promiseCmdr = Promise.spawn(function(resolve, reject)
		local cmdr = nil
		const success, err = pcall(function()
			cmdr = require("Cmdr")
		end)

		if not success then
			return reject(err)
		end

		resolve(cmdr)
	end)
end

function CmdrService.Start(self: CmdrService)
	self:PromiseCmdr():Then(function(cmdr)
		CmdrServiceUtils.writeServiceBagInContext(cmdr.Registry, self._serviceBag)

		task.spawn(function()
			cmdr:RegisterDefaultCommands()
		end)

		cmdr.Registry:RegisterHook("BeforeRun", function(context)
			if not context.Executor then
				return
			end

			local permissionPromise = self._permissionService:PromiseIsAdmin(context.Executor)
			if permissionPromise:IsPending() then
				return "Still loading permissions"
			end

			local hasPermissionResult, isAdmin = permissionPromise:Yield()
			if not hasPermissionResult then
				return type(isAdmin) == "string" and isAdmin or "Failed to check admin permissions"
			end

			if not isAdmin then
				return `You don't have permission to run this command`
			end

			return nil
		end)
	end)
end

--[=[
	Returns the promised Cmdr instance
	@within CmdrService
	@return Promise<any>
]=]
function CmdrService.PromiseCmdr(self: CmdrService)
	return self._promiseCmdr
end

return CmdrService
