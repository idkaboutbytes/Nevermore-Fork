# InputKeyMapUtils Guide

`inputkeymaputils` is a Nevermore library for managing keybindings and input mappings across multiple input devices (Keyboard & Mouse, Gamepad, Touch/Slotted Touch Buttons).

---

## 1. Core Architecture

| Component | Responsibility |
| --- | --- |
| `InputKeyMap` | Maps a single `InputModeType` (e.g. `KeyboardAndMouse`, `Gamepads`, `Touch`) to a set of input keys/types (`Enum.KeyCode.Space`, `SlottedTouchButton`, etc.). |
| `InputKeyMapList` | Represents a named game action binding (e.g., `"JUMP"`, `"INTERACT"`, `"CROUCH"`) that contains multiple `InputKeyMap` instances. |
| `InputKeyMapListProvider` | Package-level provider for creating and organizing default `InputKeyMapList` instances. Registers itself with `InputKeyMapRegistryServiceShared`. |
| `InputKeyMapRegistryServiceShared` | Shared registry managing all active `InputKeyMapListProvider` instances across the game. |
| `InputKeyMapService` | Server-side service orchestrating the registry and translation services. |
| `InputKeyMapServiceClient` | Client-side service managing localization entries and input mode subscriptions. |
| `InputKeyMapListUtils` | Client utility functions to observe active keybindings based on the player's active input mode. |
| `ProximityPromptInputUtils` | Utility functions for configuring Roblox `ProximityPrompt` objects directly from `InputKeyMapList` instances. |

---

## 2. Setting Up Services

### Server Setup

Initialize `InputKeyMapService` in your server bootstrap script:

```luau
--!strict
const require = require("Path/To/Loader").load()

const InputKeyMapService = require("InputKeyMapService")
const ServiceBag = require("ServiceBag")

const serviceBag = ServiceBag.new()
serviceBag:GetService(InputKeyMapService)

serviceBag:Init()
serviceBag:Start()
```

### Client Setup

Initialize `InputKeyMapServiceClient` in your client bootstrap script:

```luau
--!strict
const require = require("Path/To/Loader").load()

const InputKeyMapServiceClient = require("InputKeyMapServiceClient")
const ServiceBag = require("ServiceBag")

const serviceBag = ServiceBag.new()
serviceBag:GetService(InputKeyMapServiceClient)

serviceBag:Init()
serviceBag:Start()
```

---

## 3. Creating Keybinding Providers

Create an `InputKeyMapListProvider` to define bindings for a subsystem or feature (e.g., vehicle controls, character movement):

```luau
--!strict
const require = require("Path/To/Loader").load()

const InputKeyMap = require("InputKeyMap")
const InputKeyMapList = require("InputKeyMapList")
const InputKeyMapListProvider = require("InputKeyMapListProvider")
const InputModeTypes = require("InputModeTypes")
const SlottedTouchButtonUtils = require("SlottedTouchButtonUtils")

const CharacterInputProvider = InputKeyMapListProvider.new("CharacterControls", function(self, serviceBag)
	-- Jump Action
	self:Add(InputKeyMapList.new("JUMP", {
		InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.KeyCode.Space }),
		InputKeyMap.new(InputModeTypes.Gamepads, { Enum.KeyCode.ButtonA }),
		InputKeyMap.new(InputModeTypes.Touch, { SlottedTouchButtonUtils.createSlottedTouchButton("primary1") }),
	}, {
		bindingName = "Jump",
		rebindable = true,
	}))

	-- Interact Action
	self:Add(InputKeyMapList.new("INTERACT", {
		InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.KeyCode.E }),
		InputKeyMap.new(InputModeTypes.Gamepads, { Enum.KeyCode.ButtonX }),
		InputKeyMap.new(InputModeTypes.Touch, { SlottedTouchButtonUtils.createSlottedTouchButton("primary2") }),
	}, {
		bindingName = "Interact",
		rebindable = true,
	}))
end)

return CharacterInputProvider
```

To register and retrieve the provider, fetch it via `ServiceBag`:

```luau
local characterInputs = serviceBag:GetService(CharacterInputProvider)
local jumpBindingList = characterInputs:GetInputKeyMapList("JUMP")
```

---

## 4. Observing Active Keybindings on the Client

Use `InputKeyMapListUtils` to reactively observe the active key binding as the player switches input devices (e.g., from Keyboard to Gamepad):

```luau
--!strict
const require = require("Path/To/Loader").load()

const InputKeyMapListUtils = require("InputKeyMapListUtils")
const Maid = require("Maid")

local maid = Maid.new()

-- Observe active input types for "JUMP"
maid:GiveTask(InputKeyMapListUtils.observeActiveInputTypesList(jumpBindingList, serviceBag):Subscribe(function(inputTypes)
	if inputTypes and #inputTypes > 0 then
		local primaryInput = inputTypes[1]
		print("Current active input key for Jump:", primaryInput)
	end
end))
```

---

## 5. ProximityPrompt Integration

Use `ProximityPromptInputUtils` to synchronize Roblox `ProximityPrompt` objects with your `InputKeyMapList`:

```luau
--!strict
const require = require("Path/To/Loader").load()

const ProximityPromptInputUtils = require("ProximityPromptInputUtils")

-- Automatically configure prompt keycodes for Keyboard & Gamepad from the binding list
ProximityPromptInputUtils.configurePromptFromInputKeyMap(myProximityPrompt, interactBindingList)
```
