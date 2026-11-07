-- Developer tool, never packaged: takes the screenshots for LeanPad's README and CurseForge page, so they need no
-- hand work. /lpshots tours what can be staged (the settings tabs, the dialogue preview, a demo pop-up) and reloads
-- to save; /lpshots auto photographs each conversation page as you play, once its text has written in. Each shot is
-- saved with the frame's rectangle in screen pixels, for tools/screenshots.js to find the file and crop it.
-- It reaches LeanPad only through its globals: its slash command, frames and settings buttons.

local REVEAL_WAIT = 3 -- seconds for a page's text to finish writing itself in
local PAGES = { GOSSIP_SHOW = "dialogue-npc", QUEST_DETAIL = "dialogue-quest", QUEST_COMPLETE = "dialogue-rewards" }

local shooter = CreateFrame("Frame")
local steps, auto, pending = {}, false, nil

local function say(text) print("|cfff6b73cLeanPad Shots:|r " .. text) end

-- The frame's rectangle in screen pixels from the top left, padded by extra pixels below (for a hint under it).
local function rect(frame, extraBelow)
	local scale, uiHeight = frame:GetEffectiveScale(), UIParent:GetHeight() * UIParent:GetEffectiveScale()
	local px = select(2, GetPhysicalScreenSize()) / uiHeight
	local left, right = frame:GetLeft() * scale * px, frame:GetRight() * scale * px
	local top, bottom = (uiHeight - frame:GetTop() * scale) * px, (uiHeight - frame:GetBottom() * scale) * px
	return math.floor(left), math.floor(top), math.ceil(right), math.ceil(bottom + (extraBelow or 0) * px)
end

-- Records the shot as "name|time|left|top|right|bottom" and takes it; the next step waits for the client's answer.
local function shoot(name, frame, extraBelow)
	LeanPadShotsDB = LeanPadShotsDB or {}
	LeanPadShotsDB[name] = table.concat({ name, time(), rect(frame, extraBelow) }, "|")
	pending = name
	Screenshot()
end

local function nextStep()
	local step = table.remove(steps, 1)
	if not step then
		say("tour done, reloading to save. Then run: cd tools && npm run shots (npm run shots forever on Forever)")
		return C_Timer.After(1, ReloadUI)
	end
	step()
end

-- Each step stages a scene, gives it a moment to draw, then shoots; SCREENSHOT_SUCCEEDED moves to the next.
local function stage(name, setUp, frame, extraBelow)
	table.insert(steps, function()
		setUp()
		C_Timer.After(1, function() shoot(name, frame(), extraBelow) end)
	end)
end

local function settingsTab(index)
	return function()
		SlashCmdList.LEANPAD("settings")
		LeanPadControllerFrame.Options.Tabs[index]:Click()
	end
end

-- The Dialogue tab's preview button, found by its label.
local function previewButton()
	for _, child in ipairs({ LeanPadControllerFrame.Options.Dialogue:GetChildren() }) do
		if child.GetText and child:GetText() == "Show or hide" then return child end
	end
end

StaticPopupDialogs.LEANPADSHOTS_DEMO = {
	text = "Pop-ups answer to the pad: A, B, X and Y press their buttons, left to right.",
	button1 = ACCEPT, button2 = CANCEL, timeout = 0, whileDead = true, hideOnEscape = true,
}

local function tour()
	if InCombatLockdown() then return say("leave combat first.") end
	steps = {}
	stage("settings-controls", settingsTab(1), function() return LeanPadControllerFrame end)
	stage("settings-dialogue", settingsTab(2), function() return LeanPadControllerFrame end)
	stage("dialogue-preview", function()
		previewButton():Click()
		LeanPadControllerFrame:Hide()
	end, function() return LeanPadDialogue end)
	stage("popup", function()
		LeanPadDialogue:Hide()
		StaticPopup_Show("LEANPADSHOTS_DEMO")
	end, function() return StaticPopup1 end, 50)
	table.insert(steps, function()
		StaticPopup_Hide("LEANPADSHOTS_DEMO")
		nextStep()
	end)
	say("touring; keep the game window in front.")
	nextStep()
end

shooter:RegisterEvent("SCREENSHOT_SUCCEEDED")
shooter:RegisterEvent("SCREENSHOT_FAILED")
for event in pairs(PAGES) do shooter:RegisterEvent(event) end
shooter:SetScript("OnEvent", function(_, event)
	if event == "SCREENSHOT_SUCCEEDED" or event == "SCREENSHOT_FAILED" then
		if not pending then return end
		say((event == "SCREENSHOT_SUCCEEDED" and "took " or "failed: ") .. pending)
		pending = nil
		if #steps > 0 or not auto then nextStep() end
		return
	end
	-- Auto: once the page's text has written in, the window as it stands; the newest of each kind wins.
	if not auto then return end
	C_Timer.After(REVEAL_WAIT, function()
		if LeanPadDialogue and LeanPadDialogue:IsShown() then shoot(PAGES[event], LeanPadDialogue) end
	end)
end)

SLASH_LEANPADSHOTS1 = "/lpshots"
SlashCmdList.LEANPADSHOTS = function(msg)
	if msg == "auto" then
		auto = not auto
		return say(auto and "auto on: talk to NPCs and hand in quests; /reload when done, then npm run shots (add forever on Forever)." or "auto off.")
	end
	tour()
end
