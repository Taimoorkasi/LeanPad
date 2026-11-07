local wow = require("spec.wow")

describe("Pop-ups from the pad", function()
	local ns, w

	local function fire(event, ...)
		for _, widget in ipairs(w.widgets) do
			if widget.events[event] and widget.scripts.OnEvent then widget.scripts.OnEvent(widget, event, ...) end
		end
	end

	-- What A and B click now, by button name.
	local function clicks()
		local found = {}
		for _, key in ipairs({ "PAD1", "PAD2" }) do
			local override = w.overrides[key]
			found[key] = override and override.click
		end
		return found
	end

	local function hint()
		for _, widget in ipairs(w.widgets) do
			if rawget(widget, "Text") and widget.template == "BackdropTemplate" then return widget end
		end
	end

	before_each(function()
		ns, w = wow.boot({ questPrompts = true }, nil)
	end)
	after_each(wow.restore)

	it("press a pop-up's buttons on A and B, as the player's own clicks, named under it", function()
		StaticPopup1:Show()
		assert.same({ PAD1 = "StaticPopup1Button1", PAD2 = "StaticPopup1Button2" }, clicks())
		assert.is_true(w.overrides.PAD1.priority)
		assert.equal("Accept    Cancel", hint().Text.text)
		assert.equal(StaticPopup1, hint().point[2])
		assert.is_true(ns.PopupAnswering())
		StaticPopup1:Hide()
		assert.same({}, clicks())
		assert.is_false(hint():IsShown())
		assert.is_false(ns.PopupAnswering())
	end)

	it("answer the first pop-up showing, the queue pop and ready check included", function()
		LFGDungeonReadyDialog:Show()
		assert.same({ PAD1 = "LFGDungeonReadyDialogEnterDungeonButton", PAD2 = "LFGDungeonReadyDialogLeaveQueueButton" }, clicks())
		StaticPopup2:Show()
		assert.equal("StaticPopup2Button1", clicks().PAD1)
	end)

	it("take only the buttons showing, and pass over a pop-up with none", function()
		StaticPopup1Button1:Hide()
		StaticPopup1:Show()
		assert.same({ PAD2 = "StaticPopup1Button2" }, clicks())
		assert.equal("Cancel", hint().Text.text)
		StaticPopup1Button2:Hide()
		ReadyCheckFrame:Show()
		assert.same({ PAD1 = "ReadyCheckFrameYesButton", PAD2 = "ReadyCheckFrameNoButton" }, clicks())
	end)

	it("give the pad back as combat starts, and answer a pop-up still up once it ends", function()
		StaticPopup1:Show()
		fire("PLAYER_REGEN_DISABLED")
		assert.same({}, clicks())
		w.combat = true
		StaticPopup1:Hide()
		StaticPopup2:Show()
		assert.same({}, clicks())
		w.combat = false
		fire("PLAYER_REGEN_ENABLED")
		assert.equal("StaticPopup2Button1", clicks().PAD1)
	end)

	it("stay off with the setting off, and with Blizzard's Gamepad UI, which has its own", function()
		ns, w = wow.boot({}, nil)
		StaticPopup1:Show()
		assert.same({}, clicks())
		ns, w = wow.bootForever({}, nil)
		StaticPopup1:Show()
		assert.same({}, clicks())
	end)

	it("take A and B from the dialogue window, for a gossip's confirm", function()
		w.quest.gossipOptions = { { name = "Pay", icon = 1, orderIndex = 0 }, { name = "Bye", icon = 1, orderIndex = 1 } }
		fire("GOSSIP_SHOW")
		StaticPopup1:Show()
		LeanPadDialogue.Input:Fire("OnGamePadButtonDown", "PAD1")
		assert.equal(0, #w.questCalls)
		assert.is_true(LeanPadDialogue.Input.propagate)
	end)
end)
