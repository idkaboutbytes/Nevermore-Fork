--!strict
--[=[
	@class CmdrService
]=]

const require = require("../Loader").load()

const Maid = require("Maid")
const ObservableMap = require("ObservableMap")
const PermissionService = require("PermissionService")
const Promise = require("Promise")
const ServiceBag = require("ServiceBag")
const t = require("t")
const CmdrServiceNetwork = require("CmdrServiceNetwork")
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

		_commandDefinitions: ObservableMap.ObservableMap<string, CmdrServiceUtils.CommandDefinition>,
	},
	{} :: typeof({ __index = CmdrService })
))

function CmdrService.Init(self: CmdrService, serviceBag: ServiceBag.ServiceBag)
	assert(not (self :: any)._serviceBag, "Already initialized")
	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._permissionService = self._serviceBag:GetService(PermissionService)

	-- Keyed by name so re-registering a command replaces it, exactly as Cmdr's
	-- own registry does
	self._commandDefinitions = self._maid:Add(ObservableMap.new())

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
	-- Answered rather than pushed on join: a client cannot receive anything until
	-- its own registry is live, so it asks when it is ready
	CmdrServiceNetwork.packets.commandsRequested.listen(function(_, player: Player)
		CmdrServiceNetwork.packets.commandsReplicated.sendTo(self._commandDefinitions:GetValueList(), player)
	end)

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
	Registers every command in a container once Cmdr has loaded.

	Cmdr pairs each `Foo` definition with a `FooServer` implementation sitting
	beside it by name, and then *moves* the definition into ReplicatedStorage so
	clients can parse and autocomplete it. The container is left empty afterwards
	-- do not keep anything else in it, and do not expect the modules to stay put.

	Register at boot. Clients read the replicated folders once when they load
	Cmdr, so a client already in the game will not see commands registered later.

	```lua
	CmdrService:RegisterCommandsIn(ServerScriptService.Commands)
	```

	@within CmdrService
	@param container Instance
	@return Promise<()>
]=]
function CmdrService.RegisterCommandsIn(self: CmdrService, container: Instance): Promise.Promise<()>
	assert(typeof(container) == "Instance", "Bad container")

	return self:PromiseCmdr():Then(function(cmdr)
		cmdr.Registry:RegisterCommandsIn(container)
	end)
end

--[=[
	Registers a command from a plain table -- its properties and its Run together,
	no ModuleScripts anywhere -- and replicates it to clients so they can parse and
	autocomplete it.

	`Run` stays on the server. It is stripped before the definition goes out,
	because Cmdr runs a command on whichever machine holds a definition with a Run
	in it, so a client given the real thing would execute it itself instead of
	asking the server.

	Only plain data replicates. `ClientRun`, `Data`, and a function-valued `Args`,
	`Type` or `Default` cannot be sent over a remote -- those need
	[CmdrService.RegisterCommandsIn] and Cmdr's module convention.

	```lua
	CmdrService:RegisterCommand({
		Name = "kill",
		Description = "Kills a player",
		Group = "Admin",
		Args = {
			{ Type = "player", Name = "target", Description = "Who to kill" },
		},
		Run = function(context, target)
			target:BreakJoints()
			return `Killed {target.Name}`
		end,
	})
	```

	@within CmdrService
	@param definition CommandDefinition
	@return Promise<()>
]=]
function CmdrService.RegisterCommand(
	self: CmdrService,
	definition: CmdrServiceUtils.CommandDefinition
): Promise.Promise<()>
	const replicated = CmdrServiceUtils.getReplicatedCommand(definition)

	return self:PromiseCmdr():Then(function(cmdr)
		cmdr.Registry:RegisterCommandObject(definition)

		self._commandDefinitions:Set(replicated.Name, replicated)
		CmdrServiceNetwork.packets.commandsReplicated.sendToAll({ replicated })
	end)
end

--[=[
	Registers every type in a container once Cmdr has loaded. Like commands, the
	modules are moved into ReplicatedStorage, since clients need types to parse
	arguments.

	```lua
	CmdrService:RegisterTypesIn(ReplicatedStorage.CmdrTypes)
	```

	@within CmdrService
	@param container Instance
	@return Promise<()>
]=]
function CmdrService.RegisterTypesIn(self: CmdrService, container: Instance): Promise.Promise<()>
	assert(typeof(container) == "Instance", "Bad container")

	return self:PromiseCmdr():Then(function(cmdr)
		cmdr.Registry:RegisterTypesIn(container)
	end)
end

--[=[
	Registers a single type once Cmdr has loaded.

	:::warning
	Server-only. A type registered this way is not replicated, so clients cannot
	parse or autocomplete arguments using it. Prefer
	[CmdrService.RegisterTypesIn] with a module, which is.
	:::

	@within CmdrService
	@param name string
	@param typeObject any
	@return Promise<()>
]=]
function CmdrService.RegisterType(self: CmdrService, name: string, typeObject: any): Promise.Promise<()>
	assert(t.string(name), "Bad name")
	assert(t.table(typeObject), "Bad typeObject")

	return self:PromiseCmdr():Then(function(cmdr)
		cmdr.Registry:RegisterType(name, typeObject)
	end)
end

--[=[
	Registers every hook in a container once Cmdr has loaded. Each module is
	called with the registry, exactly like a type.

	@within CmdrService
	@param container Instance
	@return Promise<()>
]=]
function CmdrService.RegisterHooksIn(self: CmdrService, container: Instance): Promise.Promise<()>
	assert(typeof(container) == "Instance", "Bad container")

	return self:PromiseCmdr():Then(function(cmdr)
		cmdr.Registry:RegisterHooksIn(container)
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
