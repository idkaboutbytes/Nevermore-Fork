# SaveSlot

`SaveSlotService` adapts Nevermore's SaveSlot lifecycle to this fork's
`DataService`. It does not open another DataStore or ProfileStore session.
Instead, each player's existing profile contains account-wide data plus a
`SaveSlots` branch:

```text
Profile
├── account-wide fields
└── SaveSlots
    ├── ActiveSlotId
    ├── LastActiveSlotId
    ├── Metadata[slotId]
    └── Slots[slotId]       (server-only gameplay data)
```

Selecting a slot changes which `Slots[slotId]` table the server API reads and
writes. Slot contents are registered as a hidden DataService path before
profiles load. Clients receive only active IDs and metadata.

This is intentionally different from Quenty's original implementation, which
creates DataStore substores. Your DataService already owns one session-locked
ProfileStore profile per player; opening or swapping a second session would
fight that ownership model.

## ProfileData setup

The consuming game must add this shape to both `ProfileData.Template` and
`ProfileData.Schema`. `SlotDataSchema` is game-specific and must match the data
passed to `SetDefaultSlotData`. Before starting the ServiceBag, configure either
`SetDefaultSlotData` or `SetDefaultSlotDataProvider`; the service will not guess a
schema-dependent default.

```luau
const Squash = require("Squash")

const SlotMetadataSchema = Squash.record({
	SlotId = Squash.string(),
	SlotIndex = Squash.u16(),
	SlotName = Squash.string(),
	CreatedTime = Squash.f64(),
	LastPlayedTime = Squash.f64(),
	Summary = Squash.string(),
})

const SlotDataSchema = Squash.record({
	Coins = Squash.f64(),
	Level = Squash.u16(),
})

local ProfileData = {}

ProfileData.Template = {
	-- Account-wide fields belong outside SaveSlots.
	Settings = {},

	SaveSlots = {
		ActiveSlotId = "",
		LastActiveSlotId = "",
		Metadata = {},
		Slots = {},
	},
}

ProfileData.Schema = Squash.record({
	Settings = Squash.record({}),

	SaveSlots = Squash.record({
		ActiveSlotId = Squash.string(),
		LastActiveSlotId = Squash.string(),
		Metadata = Squash.map(Squash.string(), SlotMetadataSchema),
		Slots = Squash.map(Squash.string(), SlotDataSchema),
	}),
})

return ProfileData
```

Do not put account entitlements, settings, purchase receipts, or other
cross-character state inside `SlotDataSchema` unless each slot should own a
separate copy.

## Server setup

Configure the service after `ServiceBag:Init()` and before
`ServiceBag:Start()`:

```luau
const SaveSlotService = require("SaveSlotService")
const ServiceBag = require("ServiceBag")

local serviceBag = ServiceBag.new()
local saveSlots = serviceBag:GetService(SaveSlotService)

serviceBag:Init()

saveSlots:SetMaxSlotCount(3)
saveSlots:SetDefaultSlotData({
	Coins = 0,
	Level = 1,
})

saveSlots:SetDefaultSummaryProvider(function(_player, slotData)
	return `Level {slotData.Level} - {slotData.Coins} coins`
end)

-- Optional: leave every player unselected until UI or game code chooses.
-- saveSlots:RequireExplicitSelection()

serviceBag:Start()
```

Without explicit selection, joining players select their valid teleport slot,
then their last active slot, then slot index 1. Index 1 is created automatically
when none exists.

## Server usage

Wait for initialization before the first synchronous read:

```luau
saveSlots:ReadyAsync(player):Then(function()
	print(saveSlots:GetActiveSlotId(player))
	print(saveSlots:GetSlotList(player))

	saveSlots:SetValue(player, "Coins", function(coins)
		return coins + 25
	end)

	print(saveSlots:GetValue(player, "Coins"))
end)
```

Slot management is promise-based:

```luau
saveSlots:CreateSlotAsync(player, 2, {
	SlotName = "Mage",
	Summary = "New character",
}):Then(function(slotId)
	return saveSlots:SelectSlotAsync(player, slotId)
end)

saveSlots:SetSlotMetadataAsync(player, slotId, {
	SlotName = "Archmage",
})

-- The active slot cannot be deleted.
saveSlots:DeleteSlotAsync(player, inactiveSlotId)
```

The active data helpers are:

- `GetActiveSlotData(player)`
- `GetLastActiveSlotId(player)`
- `GetValue(player, path)`
- `SetValue(player, path, valueOrCallback)`
- `UpdateActiveSlot(player, callback)`
- `ObserveActiveSlotData(player)`
- `ObserveAtKey(player, path)`
- `ObserveSlotMetadata(player, slotId)`

Writing through these helpers keeps slot routing centralized and refreshes the
configured summary provider. `DataService` remains responsible for autosaving,
shutdown flushing, profile reconciliation, and datastore failure handling.

## Client usage

The client service reads metadata from `DataServiceClient` and uses ByteNet only
for validated mutations:

```luau
const SaveSlotServiceClient = require("SaveSlotServiceClient")

local saveSlotsClient = serviceBag:GetService(SaveSlotServiceClient)

saveSlotsClient:ReadyAsync():Then(function()
	for _, metadata in saveSlotsClient:GetSlotList() do
		print(metadata.SlotIndex, metadata.SlotName, metadata.Summary)
	end
end)

saveSlotsClient:ObserveActiveSlotId():Subscribe(function(slotId)
	print("Active slot", slotId)
end)

saveSlotsClient:CreateSlotAsync(2, { SlotName = "Mage" }):Then(function(slotId)
	return saveSlotsClient:SelectSlotAsync(slotId)
end)
```

Clients cannot read or write slot gameplay data directly. Their mutation
methods can only manage their own slots, and the server validates slot bounds,
ownership, immutable IDs/indexes, active-slot deletion, and metadata lengths.

## Cmdr

The server registers these `DefaultAdmin` commands through `CmdrService`:

- `list-save-slots player`
- `set-save-slot player slotIndex`
- `create-save-slot player slotIndex`
- `delete-save-slot player slotIndex`

## Teleports

To select a known slot after teleporting, include its ID under
`IncomingSaveSlotId` in `TeleportData`. Invalid or deleted IDs fall back to the
normal selection flow.

## Migration note

This storage layout does not read Quenty SaveSlot's old
`SaveSlots.slots.<slotId>` DataStore substores. Existing games using that
package need a one-time migration into the `ProfileData.SaveSlots` branch.
