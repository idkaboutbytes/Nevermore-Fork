--!strict
--!optimize 2
--[=[
	Client-side distance culling for Instances and lightweight custom objects.

	Custom objects are intended for renderers whose position is already known.
	They avoid `GetBoundingBox()` and use squared X/Z distance checks at a fixed,
	configurable frequency.

	@class ClientCulling
]=]

const CollectionService = game:GetService("CollectionService")
const RunService = game:GetService("RunService")

const require = require("../Loader").load()

const TableUtils = require("TableUtils")

const CULL_TAG = "Cull"
const CULL_SHADOWS_TAG = "CullShadows"
const DEFAULT_UPDATE_FREQUENCY = 10
const DEFAULT_UNCULL_HYSTERESIS = 10

const VALID_CULL_CLASSES: { [string]: boolean } = {
	ParticleEmitter = true,
	Beam = true,
	Trail = true,
	SurfaceGui = true,
	BillboardGui = true,
	PointLight = true,
	SpotLight = true,
	SurfaceLight = true,
	Model = true,
	Part = true,
	MeshPart = true,
	UnionOperation = true,
	WedgePart = true,
	CornerWedgePart = true,
	TrussPart = true,
}

const HAS_ENABLED: { [string]: boolean } = {
	ParticleEmitter = true,
	Beam = true,
	Trail = true,
	SurfaceGui = true,
	BillboardGui = true,
	PointLight = true,
	SurfaceLight = true,
	SpotLight = true,
}

export type CullableEntry = {
	Instance: Instance,
	BoundingBox: { CFrame: CFrame, Size: Vector3 },
	CullDistance: number,
	OriginalParent: Instance?,
	OriginalCastShadow: boolean?,
	OriginalEnabled: boolean?,
	Visible: boolean,
}

export type CullableObject = {
	GetCullPosition: (self: any) -> Vector3,
	GetCullRadius: ((self: any) -> number)?,
	SetCulled: (self: any, culled: boolean) -> (),
}

export type CullableObjectEntry = {
	Object: CullableObject,
	CullDistance: number,
	UncullDistance: number,
	Culled: boolean,
	Index: number,
}

type Callback = (Instance) -> ()

const ClientCulling = {}
ClientCulling.Tag = CULL_TAG
ClientCulling.ShadowTag = CULL_SHADOWS_TAG

ClientCulling._items = {} :: { [Instance]: CullableEntry }
ClientCulling._objects = {} :: { [CullableObject]: CullableObjectEntry }
ClientCulling._objectEntries = {} :: { CullableObjectEntry }
ClientCulling._running = false
ClientCulling._defaultCullDistance = 200
ClientCulling._updateInterval = 1 / DEFAULT_UPDATE_FREQUENCY
ClientCulling._updateAccumulator = 0
ClientCulling._heartbeatConnection = nil :: RBXScriptConnection?
ClientCulling._tagConnections = {} :: { RBXScriptConnection }
ClientCulling._onCulledCallbacks = {} :: { Callback }
ClientCulling._onUnculledCallbacks = {} :: { Callback }

ClientCulling._unrenderedFolder = Instance.new("Folder")
ClientCulling._unrenderedFolder.Name = "Unrendered"
ClientCulling._unrenderedFolder.Parent = script

function ClientCulling.Start()
	if ClientCulling._running then
		return
	end

	ClientCulling._running = true
	ClientCulling._updateAccumulator = 0
	ClientCulling._ensureUnrenderedFolder()

	ClientCulling._heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
		if not ClientCulling._running then
			return
		end

		ClientCulling._updateAccumulator += deltaTime
		if ClientCulling._updateAccumulator < ClientCulling._updateInterval then
			return
		end

		ClientCulling._updateAccumulator %= ClientCulling._updateInterval
		ClientCulling._updateCulling()
	end)

	ClientCulling._observeTag(CULL_TAG)
	ClientCulling._observeTag(CULL_SHADOWS_TAG)
	ClientCulling._updateCulling()
end

--[=[
	Sets how often distance culling is evaluated.

	@within ClientCulling
	@param updatesPerSecond number
]=]
function ClientCulling.SetUpdateFrequency(updatesPerSecond: number)
	assert(type(updatesPerSecond) == "number" and updatesPerSecond > 0, "Bad updatesPerSecond")
	ClientCulling._updateInterval = 1 / updatesPerSecond
end

--[=[
	Registers an Instance for distance culling.

	@within ClientCulling
	@param instance Instance
	@param cullDistance number
	@return CullableEntry?
]=]
function ClientCulling.AddItem(instance: Instance, cullDistance: number): CullableEntry?
	assert(typeof(instance) == "Instance", "Bad instance")
	assert(type(cullDistance) == "number" and cullDistance >= 0, "Bad cullDistance")

	const existing = ClientCulling._items[instance]
	if existing then
		return existing
	end

	if not ClientCulling._isCullable(instance) then
		return nil
	end

	local cframe, size = ClientCulling._deriveBoundingBox(instance)
	if not cframe or not size then
		warn(`[ClientCulling] - Failed to derive a bounding box for {instance:GetFullName()}`)
		return nil
	end

	const entry: CullableEntry = {
		Instance = instance,
		BoundingBox = {
			CFrame = cframe,
			Size = size,
		},
		CullDistance = cullDistance,
		OriginalParent = instance.Parent,
		OriginalCastShadow = nil,
		OriginalEnabled = nil,
		Visible = true,
	}

	if HAS_ENABLED[instance.ClassName] then
		entry.OriginalEnabled = (instance :: any).Enabled
	end

	if instance:IsA("BasePart") and CollectionService:HasTag(instance, CULL_SHADOWS_TAG) then
		entry.OriginalCastShadow = instance.CastShadow
	end

	ClientCulling._items[instance] = entry
	return entry
end

--[=[
	Registers a lightweight custom object. Custom objects are checked in X/Z and
	do not require a rendered Instance to exist.

	@within ClientCulling
	@param object CullableObject
	@param cullDistance number
	@param uncullDistance number?
	@return CullableObjectEntry
]=]
function ClientCulling.AddObject(
	object: CullableObject,
	cullDistance: number,
	uncullDistance: number?
): CullableObjectEntry
	assert(type(object) == "table", "Bad object")
	assert(type(object.GetCullPosition) == "function", "No object.GetCullPosition")
	assert(object.GetCullRadius == nil or type(object.GetCullRadius) == "function", "Bad object.GetCullRadius")
	assert(type(object.SetCulled) == "function", "No object.SetCulled")
	assert(type(cullDistance) == "number" and cullDistance >= 0, "Bad cullDistance")

	const existing = ClientCulling._objects[object]
	if existing then
		return existing
	end

	const resolvedUncullDistance = uncullDistance
		or math.max(0, cullDistance - math.min(DEFAULT_UNCULL_HYSTERESIS, cullDistance * 0.1))
	assert(
		type(resolvedUncullDistance) == "number"
			and resolvedUncullDistance >= 0
			and resolvedUncullDistance <= cullDistance,
		"Bad uncullDistance"
	)

	const entry: CullableObjectEntry = {
		Object = object,
		CullDistance = cullDistance,
		UncullDistance = resolvedUncullDistance,
		Culled = false,
		Index = #ClientCulling._objectEntries + 1,
	}

	ClientCulling._objects[object] = entry
	table.insert(ClientCulling._objectEntries, entry)

	const camera = workspace.CurrentCamera
	const shouldCull = camera and ClientCulling._shouldCullObject(entry, camera.CFrame.Position) or false
	ClientCulling._setObjectCulled(entry, shouldCull, true)

	return entry
end

--[=[
	Removes an Instance and restores its original state.

	@within ClientCulling
	@param item Instance | CullableEntry
]=]
function ClientCulling.RemoveItem(item: Instance | CullableEntry)
	const instance = ClientCulling._resolveInstance(item)
	if not instance then
		return
	end

	const entry = ClientCulling._items[instance]
	if not entry then
		return
	end

	ClientCulling._setVisible(entry, true)
	ClientCulling._restoreEntry(entry)
	ClientCulling._items[instance] = nil
end

--[=[
	Removes a custom object and makes it visible before releasing it.

	@within ClientCulling
	@param object CullableObject | CullableObjectEntry
]=]
function ClientCulling.RemoveObject(object: CullableObject | CullableObjectEntry)
	const entry = if (object :: any).Object
		then object :: CullableObjectEntry
		else ClientCulling._objects[object :: CullableObject]
	if not entry or ClientCulling._objects[entry.Object] ~= entry then
		return
	end

	ClientCulling._setObjectCulled(entry, false, entry.Culled)
	ClientCulling._objects[entry.Object] = nil

	const lastEntry = ClientCulling._objectEntries[#ClientCulling._objectEntries]
	TableUtils.swapRemove(ClientCulling._objectEntries, entry.Index)
	if lastEntry and lastEntry ~= entry then
		lastEntry.Index = entry.Index
	end
end

--[=[
	Returns whether an Instance is currently culled.

	@within ClientCulling
	@param item Instance | CullableEntry
	@return boolean
]=]
function ClientCulling.IsItemActivelyCulled(item: Instance | CullableEntry): boolean
	const instance = ClientCulling._resolveInstance(item)
	if not instance then
		return false
	end

	const entry = ClientCulling._items[instance]
	const camera = workspace.CurrentCamera
	if not entry or not camera or not ClientCulling._refreshBoundingBox(entry) then
		return false
	end

	return ClientCulling._shouldCull(entry, camera.CFrame.Position)
end

--[=[
	Returns whether a custom object is currently culled.

	@within ClientCulling
	@param object CullableObject | CullableObjectEntry
	@return boolean
]=]
function ClientCulling.IsObjectActivelyCulled(object: CullableObject | CullableObjectEntry): boolean
	const entry = if (object :: any).Object
		then object :: CullableObjectEntry
		else ClientCulling._objects[object :: CullableObject]
	const camera = workspace.CurrentCamera
	return entry ~= nil and camera ~= nil and ClientCulling._shouldCullObject(entry, camera.CFrame.Position)
end

--[=[
	Observes Instance cull transitions.

	@within ClientCulling
	@param callback (Instance) -> ()
	@return () -> ()
]=]
function ClientCulling.OnItemCulled(callback: Callback): () -> ()
	assert(type(callback) == "function", "Bad callback")
	table.insert(ClientCulling._onCulledCallbacks, callback)

	return function()
		const index = table.find(ClientCulling._onCulledCallbacks, callback)
		if index then
			TableUtils.swapRemove(ClientCulling._onCulledCallbacks, index)
		end
	end
end

--[=[
	Observes Instance uncull transitions.

	@within ClientCulling
	@param callback (Instance) -> ()
	@return () -> ()
]=]
function ClientCulling.OnItemUnculled(callback: Callback): () -> ()
	assert(type(callback) == "function", "Bad callback")
	table.insert(ClientCulling._onUnculledCallbacks, callback)

	return function()
		const index = table.find(ClientCulling._onUnculledCallbacks, callback)
		if index then
			TableUtils.swapRemove(ClientCulling._onUnculledCallbacks, index)
		end
	end
end

function ClientCulling._ensureUnrenderedFolder()
	if ClientCulling._unrenderedFolder and ClientCulling._unrenderedFolder.Parent then
		return
	end

	const folder = Instance.new("Folder")
	folder.Name = "Unrendered"
	folder.Parent = script
	ClientCulling._unrenderedFolder = folder
end

function ClientCulling._resolveInstance(item: Instance | CullableEntry): Instance?
	if typeof(item) == "Instance" then
		return item
	end

	return (item :: CullableEntry).Instance
end

function ClientCulling._restoreEntry(entry: CullableEntry)
	const instance = entry.Instance
	if entry.OriginalEnabled ~= nil and HAS_ENABLED[instance.ClassName] then
		(instance :: any).Enabled = entry.OriginalEnabled
	end
	if entry.OriginalCastShadow ~= nil and instance:IsA("BasePart") then
		instance.CastShadow = entry.OriginalCastShadow
	end
end

function ClientCulling._observeTag(tag: string)
	const addedConnection = CollectionService:GetInstanceAddedSignal(tag):Connect(function(instance: Instance)
		const entry = ClientCulling.AddItem(instance, ClientCulling._defaultCullDistance)
		if entry and instance:IsA("BasePart") and CollectionService:HasTag(instance, CULL_SHADOWS_TAG) then
			entry.OriginalCastShadow = instance.CastShadow
		end
	end)

	const removedConnection = CollectionService:GetInstanceRemovedSignal(tag):Connect(function(instance: Instance)
		const entry = ClientCulling._items[instance]
		if not entry then
			return
		end

		if tag == CULL_SHADOWS_TAG and instance:IsA("BasePart") then
			if entry.OriginalCastShadow ~= nil then
				instance.CastShadow = entry.OriginalCastShadow
			end
			entry.OriginalCastShadow = nil
		end

		if
			not CollectionService:HasTag(instance, CULL_TAG)
			and not CollectionService:HasTag(instance, CULL_SHADOWS_TAG)
		then
			ClientCulling.RemoveItem(instance)
		end
	end)

	table.insert(ClientCulling._tagConnections, addedConnection)
	table.insert(ClientCulling._tagConnections, removedConnection)

	for _, instance in CollectionService:GetTagged(tag) do
		const entry = ClientCulling.AddItem(instance, ClientCulling._defaultCullDistance)
		if entry and instance:IsA("BasePart") and CollectionService:HasTag(instance, CULL_SHADOWS_TAG) then
			entry.OriginalCastShadow = instance.CastShadow
		end
	end
end

function ClientCulling._isCullable(instance: Instance): boolean
	return VALID_CULL_CLASSES[instance.ClassName] == true
		or instance:IsA("Model")
		or instance:IsA("BasePart")
		or instance:IsA("Attachment")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
end

function ClientCulling._isObjectCullable(instance: Instance): boolean
	return instance:IsA("Model") or instance:IsA("BasePart")
end

function ClientCulling._fireCallbacks(callbacks: { Callback }, instance: Instance)
	for _, callback in callbacks do
		task.spawn(callback, instance)
	end
end

function ClientCulling._setVisible(entry: CullableEntry, visible: boolean)
	if entry.Visible == visible then
		return
	end

	const instance = entry.Instance
	const hasEnabled = HAS_ENABLED[instance.ClassName]
	const isObjectCullable = ClientCulling._isObjectCullable(instance)

	if hasEnabled then
		(instance :: any).Enabled = if visible then entry.OriginalEnabled ~= false else false
	elseif isObjectCullable then
		if visible then
			if entry.OriginalParent then
				instance.Parent = entry.OriginalParent
			end
		else
			ClientCulling._ensureUnrenderedFolder()
			instance.Parent = ClientCulling._unrenderedFolder
		end
	end

	if entry.OriginalCastShadow ~= nil and instance:IsA("BasePart") then
		instance.CastShadow = if visible then entry.OriginalCastShadow else false
	end

	entry.Visible = visible
	ClientCulling._fireCallbacks(
		if visible then ClientCulling._onUnculledCallbacks else ClientCulling._onCulledCallbacks,
		instance
	)
end

function ClientCulling._setObjectCulled(entry: CullableObjectEntry, culled: boolean, force: boolean?)
	if entry.Culled == culled and not force then
		return
	end

	entry.Culled = culled
	entry.Object:SetCulled(culled)
end

function ClientCulling._updateCulling()
	const camera = workspace.CurrentCamera
	if not camera then
		return
	end

	const cameraPosition = camera.CFrame.Position
	const toRemove: { Instance } = {}

	for instance, entry in ClientCulling._items do
		if not instance.Parent and entry.Visible then
			table.insert(toRemove, instance)
			continue
		end

		if not ClientCulling._refreshBoundingBox(entry) then
			table.insert(toRemove, instance)
			continue
		end

		ClientCulling._setVisible(entry, not ClientCulling._shouldCull(entry, cameraPosition))
	end

	for _, instance in toRemove do
		ClientCulling._items[instance] = nil
	end

	for _, entry in ClientCulling._objectEntries do
		ClientCulling._setObjectCulled(entry, ClientCulling._shouldCullObject(entry, cameraPosition))
	end
end

function ClientCulling._refreshBoundingBox(entry: CullableEntry): boolean
	local cframe, size = ClientCulling._deriveBoundingBox(entry.Instance)
	if not cframe or not size then
		return false
	end

	entry.BoundingBox.CFrame = cframe
	entry.BoundingBox.Size = size
	return true
end

function ClientCulling._shouldCull(entry: CullableEntry, cameraPosition: Vector3): boolean
	const boundingCenter = entry.BoundingBox.CFrame.Position
	const boundingRadius = entry.BoundingBox.Size.Magnitude * 0.5
	const roughDistance = (boundingCenter - cameraPosition).Magnitude

	if roughDistance - boundingRadius > entry.CullDistance then
		return true
	elseif roughDistance + boundingRadius < entry.CullDistance then
		return false
	end

	const closestPoint =
		ClientCulling._getClosestSurfacePosition(entry.BoundingBox.CFrame, entry.BoundingBox.Size, cameraPosition)
	return (closestPoint - cameraPosition).Magnitude >= entry.CullDistance
end

function ClientCulling._shouldCullObject(entry: CullableObjectEntry, cameraPosition: Vector3): boolean
	const objectPosition = entry.Object:GetCullPosition()
	const radius = if entry.Object.GetCullRadius then math.max(0, entry.Object:GetCullRadius()) else 0
	const distance = if entry.Culled then entry.UncullDistance else entry.CullDistance
	const effectiveDistance = distance + radius
	const deltaX = objectPosition.X - cameraPosition.X
	const deltaZ = objectPosition.Z - cameraPosition.Z
	return deltaX * deltaX + deltaZ * deltaZ > effectiveDistance * effectiveDistance
end

function ClientCulling._deriveBoundingBox(instance: Instance): (CFrame?, Vector3?)
	if instance:IsA("Model") or instance:IsA("BasePart") then
		return ClientCulling._deriveForPVInstance(instance)
	elseif instance:IsA("SurfaceGui") or instance:IsA("BillboardGui") then
		return ClientCulling._deriveForGui(instance :: any)
	elseif instance:IsA("Beam") or instance:IsA("Trail") then
		return ClientCulling._deriveForBeamLike(instance :: any)
	elseif instance:IsA("PointLight") or instance:IsA("SpotLight") or instance:IsA("SurfaceLight") then
		return ClientCulling._deriveForLight(instance :: any)
	elseif instance:IsA("Attachment") then
		return instance.WorldCFrame, Vector3.one
	elseif instance:IsA("Decal") or instance:IsA("Texture") then
		return ClientCulling._deriveForTextureLike(instance :: any)
	elseif instance:IsA("ParticleEmitter") then
		return ClientCulling._deriveForEmitter(instance :: any)
	end

	return nil, nil
end

function ClientCulling._deriveForPVInstance(instance: Instance): (CFrame?, Vector3?)
	if instance:IsA("Model") then
		local cframe, size = instance:GetBoundingBox()
		if size.Magnitude >= 0.01 then
			return cframe, size
		end

		const primaryPart = instance.PrimaryPart
		if primaryPart then
			return primaryPart.CFrame, primaryPart.Size
		end

		const firstPart = instance:FindFirstChildWhichIsA("BasePart", true)
		if firstPart then
			return firstPart.CFrame, firstPart.Size
		end
	elseif instance:IsA("BasePart") then
		return instance.CFrame, instance.Size
	end

	return nil, nil
end

function ClientCulling._deriveForGui(instance: any): (CFrame?, Vector3?)
	const adornee = instance.Adornee or instance.Parent
	if adornee and (adornee:IsA("BasePart") or adornee:IsA("Model")) then
		return ClientCulling._deriveForPVInstance(adornee)
	end
	return nil, nil
end

function ClientCulling._deriveForBeamLike(instance: any): (CFrame?, Vector3?)
	const attachment0 = instance.Attachment0
	const attachment1 = instance.Attachment1
	if not attachment0 or not attachment1 then
		return nil, nil
	end

	const position0 = attachment0.WorldPosition
	const position1 = attachment1.WorldPosition
	const center = (position0 + position1) * 0.5
	const delta = position1 - position0
	const length = delta.Magnitude
	const thickness = math.max(instance.Width0 or 1, instance.Width1 or 1, 1)
	if length < 0.001 then
		return CFrame.new(center), Vector3.one * thickness
	end

	return CFrame.lookAt(center, center + delta.Unit), Vector3.new(thickness, thickness, length)
end

function ClientCulling._deriveForLight(instance: any): (CFrame?, Vector3?)
	const parent = instance.Parent
	if parent then
		if parent:IsA("Attachment") then
			return parent.WorldCFrame, Vector3.one
		elseif parent:IsA("BasePart") or parent:IsA("Model") then
			return ClientCulling._deriveForPVInstance(parent)
		end
	end
	return nil, nil
end

function ClientCulling._deriveForTextureLike(instance: any): (CFrame?, Vector3?)
	const parent = instance.Parent
	if parent and parent:IsA("BasePart") then
		return ClientCulling._deriveForPVInstance(parent)
	end
	return nil, nil
end

function ClientCulling._deriveForEmitter(instance: any): (CFrame?, Vector3?)
	const parent = instance.Parent
	if parent then
		if parent:IsA("BasePart") or parent:IsA("Model") then
			return ClientCulling._deriveForPVInstance(parent)
		elseif parent:IsA("Attachment") then
			return parent.WorldCFrame, Vector3.one
		end
	end
	return nil, nil
end

function ClientCulling._getClosestSurfacePosition(boxCFrame: CFrame, boxSize: Vector3, point: Vector3): Vector3
	const localPoint = boxCFrame:PointToObjectSpace(point)
	const halfSize = boxSize * 0.5
	const clampedLocal = Vector3.new(
		math.clamp(localPoint.X, -halfSize.X, halfSize.X),
		math.clamp(localPoint.Y, -halfSize.Y, halfSize.Y),
		math.clamp(localPoint.Z, -halfSize.Z, halfSize.Z)
	)
	return boxCFrame:PointToWorldSpace(clampedLocal)
end

function ClientCulling.Destroy()
	ClientCulling._running = false
	if ClientCulling._heartbeatConnection then
		ClientCulling._heartbeatConnection:Disconnect()
		ClientCulling._heartbeatConnection = nil
	end

	for _, connection in ClientCulling._tagConnections do
		connection:Disconnect()
	end
	table.clear(ClientCulling._tagConnections)

	for _, entry in ClientCulling._items do
		ClientCulling._setVisible(entry, true)
		ClientCulling._restoreEntry(entry)
	end
	for _, entry in ClientCulling._objectEntries do
		ClientCulling._setObjectCulled(entry, false, entry.Culled)
	end

	table.clear(ClientCulling._items)
	table.clear(ClientCulling._objects)
	table.clear(ClientCulling._objectEntries)
	table.clear(ClientCulling._onCulledCallbacks)
	table.clear(ClientCulling._onUnculledCallbacks)

	if ClientCulling._unrenderedFolder then
		ClientCulling._unrenderedFolder:Destroy()
	end
end

return ClientCulling
