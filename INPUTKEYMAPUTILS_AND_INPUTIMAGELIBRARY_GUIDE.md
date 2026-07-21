# Using InputKeyMapUtils & InputImageLibrary Together

This guide explains how to use `InputImageLibrary` standalone, as well as how to integrate `inputkeymaputils` with `InputImageLibrary` to build dynamic, responsive UI input prompts that adapt to the player's active control scheme (Keyboard, Gamepad, or Touch).

---

## 1. Overview of InputImageLibrary

`InputImageLibrary` is a sprite and spritesheet rendering system in Nevermore that provides themed input icons (Dark/Light styles) for Keyboard keys, Xbox buttons, PlayStation buttons, Mouse inputs, and Touch actions.

### Basic Standalone Usage of InputImageLibrary

```luau
--!strict
const require = require("Path/To/Loader").load()

const InputImageLibrary = require("InputImageLibrary")

-- Style an existing ImageLabel with the icon for Enum.KeyCode.E
InputImageLibrary:StyleImage(myImageLabel, Enum.KeyCode.E, "Dark")

-- Style an existing ImageLabel with Xbox Button A icon
InputImageLibrary:StyleImage(myButtonLabel, Enum.KeyCode.ButtonA, "Dark", "XBox")
```

---

## 2. Using InputKeyMapUtils & InputImageLibrary in Conjunction

By combining `InputKeyMapListUtils` (from `inputkeymaputils`) with `InputImageLibrary`, your game UI can reactively update prompt icons whenever the local player changes their active input device (e.g., switching from WASD/Mouse to a Gamepad Controller).

### Complete Example: Dynamic Action Prompt UI

Here is a step-by-step pattern for creating a dynamic action prompt UI component:

```luau
--!strict
const require = require("Path/To/Loader").load()

const InputImageLibrary = require("InputImageLibrary")
const InputKeyMapListUtils = require("InputKeyMapListUtils")
const Maid = require("Maid")
const ServiceBag = require("ServiceBag")

-- Create a component that binds an ImageLabel prompt to an InputKeyMapList
local function bindActionPromptImage(
	serviceBag: ServiceBag.ServiceBag,
	inputKeyMapList: any,
	promptImageLabel: ImageLabel,
	preferredStyle: string?
): Maid.Maid
	local maid = Maid.new()
	local style = preferredStyle or "Dark"

	-- Subscribe to the active input key for this action binding
	maid:GiveTask(InputKeyMapListUtils.observeActiveInputTypesList(inputKeyMapList, serviceBag):Subscribe(function(inputTypes)
		if not inputTypes or #inputTypes == 0 then
			promptImageLabel.Visible = false
			return
		end

		local activeInputKey = inputTypes[1]

		-- Handle Enum.KeyCode or Enum.UserInputType
		if typeof(activeInputKey) == "EnumItem" then
			local styled = InputImageLibrary:StyleImage(promptImageLabel, activeInputKey, style)
			if styled then
				promptImageLabel.Visible = true
			else
				-- Fallback if no sprite image was found
				promptImageLabel.Visible = false
			end
		elseif type(activeInputKey) == "table" and activeInputKey.type == "SlottedTouchButton" then
			-- Custom handling for slotted touch buttons on mobile
			promptImageLabel.Visible = true
			-- Optionally apply custom touch button sprite or frame
		else
			promptImageLabel.Visible = false
		end
	end))

	return maid
end

return bindActionPromptImage
```

---

## 3. Detailed Example Workflow

Below is a complete lifecycle example showing setup, provider registration, and UI binding:

### Step 1: Define Your Input Keymap Provider

```luau
-- Shared/Input/GameInputProvider.luau
--!strict
const require = require("Path/To/Loader").load()

const InputKeyMap = require("InputKeyMap")
const InputKeyMapList = require("InputKeyMapList")
const InputKeyMapListProvider = require("InputKeyMapListProvider")
const InputModeTypes = require("InputModeTypes")

const GameInputProvider = InputKeyMapListProvider.new("GameControls", function(self, serviceBag)
	self:Add(InputKeyMapList.new("INTERACT", {
		InputKeyMap.new(InputModeTypes.KeyboardAndMouse, { Enum.KeyCode.E }),
		InputKeyMap.new(InputModeTypes.Gamepads, { Enum.KeyCode.ButtonX }),
	}, {
		bindingName = "Interact",
		rebindable = true,
	}))
end)

return GameInputProvider
```

### Step 2: Bind Provider to UI Prompt on Client

```luau
-- Client/Controllers/PromptController.luau
--!strict
const require = require("Path/To/Loader").load()

const GameInputProvider = require("GameInputProvider")
const InputImageLibrary = require("InputImageLibrary")
const InputKeyMapListUtils = require("InputKeyMapListUtils")
const Maid = require("Maid")
const ServiceBag = require("ServiceBag")

local PromptController = {}

function PromptController.Init(self: any, serviceBag: ServiceBag.ServiceBag)
	self._maid = Maid.new()
	self._serviceBag = serviceBag
	self._inputProvider = self._serviceBag:GetService(GameInputProvider)
end

function PromptController.Start(self: any)
	local interactMapList = self._inputProvider:GetInputKeyMapList("INTERACT")
	local promptImageLabel = workspace.ScreenGui.InteractPrompt.IconLabel :: ImageLabel

	-- Observe active input type and update the icon on the fly
	self._maid:GiveTask(
		InputKeyMapListUtils.observeActiveInputTypesList(interactMapList, self._serviceBag):Subscribe(function(inputTypes)
			if inputTypes and inputTypes[1] then
				local activeKey = inputTypes[1]
				InputImageLibrary:StyleImage(promptImageLabel, activeKey, "Dark")
			end
		end)
	)
end

return PromptController
```

---

## 4. Key Benefits

1. **Seamless Device Switching**: When a player unplugs their controller or moves their mouse, the UI prompt seamlessly updates from controller icons (`ButtonX`) to keyboard icons (`E`).
2. **Theme Support**: `InputImageLibrary` supports `"Dark"` and `"Light"` variants to match your game UI design system.
3. **Clean Teardown**: Binding subscriptions return `Maid` tasks or observables, ensuring memory cleanup when UI frames are destroyed.
