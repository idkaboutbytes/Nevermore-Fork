# ClientCulling

`ClientCulling` retains the supplied `Cull` and `CullShadows` tag behavior and
adds a lightweight custom-object path for systems whose position is already
known.

Start it once on the client:

```luau
const ClientCulling = require("ClientCulling")

ClientCulling.SetUpdateFrequency(10)
ClientCulling.Start()
```

Existing Instances can still be tagged or explicitly registered:

```luau
local entry = ClientCulling.AddItem(model, 200)
ClientCulling.RemoveItem(entry)
```

A custom object implements three small methods. `GetCullRadius` is optional.
Checks use squared X/Z distance and do not call `GetBoundingBox()`.

```luau
local object = {
	position = Vector3.zero,
}

function object.GetCullPosition(self)
	return self.position
end

function object.GetCullRadius(_self)
	return 2
end

function object.SetCulled(_self, culled)
	if culled then
		-- Release or hide the renderer.
	else
		-- Acquire or show the renderer.
	end
end

ClientCulling.AddObject(object, 250)
ClientCulling.RemoveObject(object)
```

Custom-object storage is dense and removal uses `TableUtils.swapRemove`, so a
transition does not shift every later entry. The default uncull threshold has a
small hysteresis to avoid repeatedly mounting and releasing renderers at the
distance boundary.
