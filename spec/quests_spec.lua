local wow = require("spec.wow")

describe("Quest prompts", function()
	local ns, w

	local function fire(event)
		for _, widget in ipairs(w.widgets) do
			if widget.events[event] and widget.scripts.OnEvent then widget.scripts.OnEvent(widget, event) end
		end
	end

	-- The footer: the one frame listening for pad presses that isn't the crossbar's or the editor's.
	local function bar()
		for _, widget in ipairs(w.widgets) do
			if rawget(widget, "Prompts") then return widget end
		end
	end

	local function press(key) bar():Fire("OnGamePadButtonDown", key) end

	local function lastCall()
		return w.questCalls[#w.questCalls]
	end

	before_each(function()
		ns, w = wow.boot({ questPrompts = true }, nil)
	end)
	after_each(wow.restore)

	describe("when they run", function()
		it("start off on retail until turned on", function()
			ns, w = wow.boot({}, nil)
			assert.is_false(ns.QuestPromptsEnabled())
			fire("QUEST_DETAIL")
			assert.is_nil(bar())
		end)

		it("start on with Forever's Gamepad UI off", function()
			ns, w = wow.bootForever({}, nil)
			w.gamepadUI = false
			assert.is_true(ns.QuestPromptsEnabled())
			fire("QUEST_DETAIL")
			assert.is_true(bar():IsShown())
		end)

		it("stay out of Blizzard's Gamepad UI, which has its own", function()
			ns, w = wow.bootForever({}, nil)
			fire("QUEST_DETAIL")
			assert.is_nil(bar())
		end)

		it("can be turned off on Forever", function()
			ns, w = wow.bootForever({ questPrompts = false }, nil)
			w.gamepadUI = false
			fire("QUEST_DETAIL")
			assert.is_nil(bar())
		end)

		it("never start in combat", function()
			w.combat = true
			fire("QUEST_DETAIL")
			assert.is_nil(bar())
		end)

		it("give the pad back the moment combat starts", function()
			fire("QUEST_DETAIL")
			fire("PLAYER_REGEN_DISABLED")
			assert.is_false(bar():IsShown())
		end)

		it("take the cursor Blizzard turned on with the window, whose clicks share A and B", function()
			w.cursorControl = true
			fire("QUEST_DETAIL")
			assert.is_false(w.cursorControl)
		end)

		it("sit under the window that opened", function()
			fire("QUEST_DETAIL")
			assert.equal(QuestFrame, bar().point[2])
			fire("GOSSIP_SHOW")
			assert.equal(GossipFrame, bar().point[2])
		end)
	end)

	describe("Blizzard's own buttons", function()
		local function faded()
			for _, button in ipairs({ QuestFrameAcceptButton, QuestFrameDeclineButton, QuestFrameCompleteButton, QuestFrameCompleteQuestButton,
				QuestFrameGoodbyeButton, QuestFrameGreetingGoodbyeButton, QuestFrameCloseButton, GossipFrame.GreetingPanel.GoodbyeButton, GossipFrameCloseButton }) do
				assert.is_equal(QuestFrameAcceptButton.alpha, button.alpha)
			end
			return QuestFrameAcceptButton.alpha
		end

		it("fade while the prompts show, so there is one set of answers", function()
			fire("QUEST_DETAIL")
			assert.equal(0, faded())
		end)

		it("come back when the window closes", function()
			fire("QUEST_DETAIL")
			fire("QUEST_FINISHED")
			assert.equal(1, faded())
		end)

		it("come back the moment combat starts", function()
			fire("QUEST_DETAIL")
			fire("PLAYER_REGEN_DISABLED")
			assert.equal(1, faded())
		end)

		it("come back for a cursor the player toggles, and fade when it goes", function()
			fire("QUEST_DETAIL")
			LeanPad_ToggleCursor()
			assert.equal(1, faded())
			LeanPad_ToggleCursor()
			assert.equal(0, faded())
		end)

		it("come back when a cursor appears by any other route, on the next press", function()
			fire("QUEST_DETAIL")
			w.cursorControl = true
			press("PADLSHOULDER")
			assert.equal(1, faded())
		end)

		it("come back for a quest the cursor has to answer", function()
			w.quest.pvp = true
			fire("QUEST_DETAIL")
			press("PAD1")
			assert.equal(1, faded())
		end)

		it("are never touched while the prompts are off", function()
			ns, w = wow.boot({}, nil)
			fire("QUEST_DETAIL")
			fire("QUEST_FINISHED")
			fire("GOSSIP_CLOSED")
			assert.is_nil(QuestFrameAcceptButton.alpha)
		end)
	end)

	describe("closing", function()
		it("close with their own window", function()
			fire("QUEST_DETAIL")
			fire("QUEST_FINISHED")
			assert.is_false(bar():IsShown())
			fire("GOSSIP_SHOW")
			fire("GOSSIP_CLOSED")
			assert.is_false(bar():IsShown())
		end)

		it("survive a gossip window closing as the quest it led to opens", function()
			fire("GOSSIP_SHOW")
			fire("QUEST_DETAIL")
			fire("GOSSIP_CLOSED")
			assert.is_true(bar():IsShown())
		end)

		it("survive a quest finishing as its gossip reopens", function()
			fire("QUEST_DETAIL")
			fire("GOSSIP_SHOW")
			fire("QUEST_FINISHED")
			assert.is_true(bar():IsShown())
		end)

		it("cope with a close before anything opened", function()
			assert.has_no.errors(function() fire("QUEST_FINISHED") end)
		end)
	end)

	describe("a quest offer", function()
		before_each(function() fire("QUEST_DETAIL") end)

		it("names its buttons", function()
			assert.equal("Accept    Decline", bar().Prompts.text)
			w.glyphs.PAD1, w.glyphs.PAD2 = "|A:glyph-a:0:0|a", "|A:glyph-b:0:0|a"
			fire("QUEST_DETAIL")
			assert.equal("|A:glyph-a:18:18|a Accept    |A:glyph-b:18:18|a Decline", bar().Prompts.text)
		end)

		it("accepts on A and declines on B, taking both presses", function()
			press("PAD1")
			assert.same({ "AcceptQuest" }, lastCall())
			assert.is_false(bar().propagate)
			press("PAD2")
			assert.same({ "CloseQuest" }, lastCall())
			assert.is_false(bar().propagate)
		end)

		it("acknowledges an auto-accepted quest", function()
			QuestFrame.autoQuest = true
			press("PAD1")
			assert.same({ "AcknowledgeAutoAcceptQuest" }, lastCall())
		end)

		it("hands a PvP quest to the cursor instead of confirming it", function()
			w.quest.pvp = true
			fire("QUEST_DETAIL")
			press("PAD1")
			assert.same({}, w.questCalls)
			assert.is_true(w.cursorControl)
		end)

		it("leaves the D-pad and other buttons to their bindings", function()
			press("PADDUP")
			assert.is_true(bar().propagate)
			press("PADLSHOULDER")
			assert.is_true(bar().propagate)
		end)

		it("leaves every button to a cursor the player brought up", function()
			w.cursorControl = true
			press("PAD1")
			assert.same({}, w.questCalls)
			assert.is_true(bar().propagate)
		end)
	end)

	describe("quest progress", function()
		it("continues on A once the quest can be completed", function()
			fire("QUEST_PROGRESS")
			press("PAD1")
			assert.same({ "CompleteQuest" }, lastCall())
		end)

		it("offers no confirm while it can't, and does nothing on A", function()
			w.quest.completable = false
			fire("QUEST_PROGRESS")
			assert.equal("Goodbye", bar().Prompts.text)
			press("PAD1")
			assert.same({}, w.questCalls)
		end)

		it("says goodbye on B", function()
			fire("QUEST_PROGRESS")
			press("PAD2")
			assert.same({ "CloseQuest" }, lastCall())
		end)
	end)

	describe("turning in", function()
		it("completes straight away with no reward choice", function()
			fire("QUEST_COMPLETE")
			press("PAD1")
			assert.same({ "GetQuestReward", 0 }, lastCall())
		end)

		it("takes a lone reward without choosing", function()
			w.quest.choices = { { "Sword", 1 } }
			fire("QUEST_COMPLETE")
			press("PAD1")
			assert.same({ "GetQuestReward", 1 }, lastCall())
		end)

		it("won't complete among several rewards until one is chosen", function()
			w.quest.choices = { { "Sword", 1 }, { "Shield", 2 }, { "Staff", 3 } }
			fire("QUEST_COMPLETE")
			assert.equal("Choose your reward", bar().Choice.text)
			assert.equal("Choose    Goodbye", bar().Prompts.text)
			press("PAD1")
			assert.same({}, w.questCalls)
		end)

		it("walks the rewards with the D-pad and takes the one shown", function()
			w.quest.choices = { { "Sword", 1 }, { "Shield", 2 }, { "Staff" } }
			fire("QUEST_COMPLETE")
			press("PADDRIGHT")
			assert.equal("|T1:16|t Sword", bar().Choice.text)
			assert.is_false(bar().propagate)
			press("PADDDOWN")
			assert.equal("|T2:16|t Shield", bar().Choice.text)
			press("PAD1")
			assert.same({ "GetQuestReward", 2 }, lastCall())
		end)

		it("starts from the last reward going backwards, and wraps", function()
			w.quest.choices = { { "Sword", 1 }, { "Shield", 2 }, { "Staff" } }
			fire("QUEST_COMPLETE")
			press("PADDUP")
			assert.equal("Staff", bar().Choice.text)
			press("PADDDOWN")
			assert.equal("|T1:16|t Sword", bar().Choice.text)
		end)

		it("copes with a reward not loaded yet", function()
			w.quest.choices = { {}, { "Shield", 2 } }
			fire("QUEST_COMPLETE")
			press("PADDDOWN")
			assert.equal("...", bar().Choice.text)
		end)

		describe("Blizzard's reward buttons", function()
			local sword, shield, fixed

			local function rewardButton(kind, id)
				local button = CreateFrame("Button")
				button.type, button.id, button.entered, button.left = kind, id, 0, 0
				function button:OnEnter() self.entered = self.entered + 1 end
				function button:OnLeave() self.left = self.left + 1 end
				table.insert(QuestInfoFrame.rewardsFrame.RewardButtons, button)
				return button
			end

			before_each(function()
				w.quest.choices = { { "Sword", 1 }, { "Shield", 2 } }
				fixed, sword, shield = rewardButton("reward", 1), rewardButton("choice", 1), rewardButton("choice", 2)
				fire("QUEST_COMPLETE")
			end)

			it("show nothing until a reward is chosen", function()
				assert.equal(0, sword.entered)
				assert.is_nil(w.quest.clicked)
			end)

			it("highlight the chosen reward and show its tooltip, as a mouse over would", function()
				press("PADDRIGHT")
				assert.equal(sword, w.quest.clicked)
				assert.equal(1, sword.entered)
				assert.equal(0, fixed.entered)
			end)

			it("move the tooltip to the next reward", function()
				press("PADDRIGHT")
				press("PADDRIGHT")
				assert.equal(1, sword.left)
				assert.equal(shield, w.quest.clicked)
				assert.equal(1, shield.entered)
			end)

			it("skip a button not on the page", function()
				sword.shown = false
				press("PADDRIGHT")
				assert.is_nil(w.quest.clicked)
				assert.equal(0, sword.entered)
			end)

			it("hide the tooltip when the window closes, or the page changes", function()
				press("PADDRIGHT")
				fire("QUEST_FINISHED")
				assert.equal(1, sword.left)
				fire("QUEST_COMPLETE")
				press("PADDRIGHT")
				fire("QUEST_DETAIL")
				assert.equal(2, sword.left)
			end)

			it("leave a list page's choosing alone", function()
				w.quest.available = { "One", "Two" }
				fire("QUEST_GREETING")
				press("PADDDOWN")
				assert.equal(0, sword.entered)
				assert.is_nil(w.quest.clicked)
			end)
		end)

		it("hands a quest that costs gold to the cursor", function()
			w.quest.money = 500
			fire("QUEST_COMPLETE")
			press("PAD1")
			assert.same({}, w.questCalls)
			assert.is_true(w.cursorControl)
		end)

		it("completes when the quest costs nothing", function()
			w.quest.money = 0
			fire("QUEST_COMPLETE")
			press("PAD1")
			assert.same({ "GetQuestReward", 0 }, lastCall())
		end)
	end)

	describe("choosing from a list", function()
		it("selects a greeting's quests, available then active", function()
			w.quest.available, w.quest.active = { "New quest" }, { "Old quest" }
			fire("QUEST_GREETING")
			assert.equal("New quest", bar().Choice.text)
			press("PAD1")
			assert.same({ "SelectAvailableQuest", 1 }, lastCall())
			press("PADDDOWN")
			assert.equal("Old quest", bar().Choice.text)
			press("PAD1")
			assert.same({ "SelectActiveQuest", 1 }, lastCall())
		end)

		it("selects gossip quests and options, and leaves by closing the gossip", function()
			w.quest.gossipAvailable = { { title = "New quest", questID = 11 } }
			w.quest.gossipActive = { { title = "Old quest", questID = 22 } }
			w.quest.gossipOptions = { { name = "Tell me more", orderIndex = 3 } }
			fire("GOSSIP_SHOW")
			press("PAD1")
			assert.same({ "GossipAvailable", 11 }, lastCall())
			press("PADDDOWN")
			press("PAD1")
			assert.same({ "GossipActive", 22 }, lastCall())
			press("PADDDOWN")
			assert.equal("Tell me more", bar().Choice.text)
			press("PAD1")
			assert.same({ "GossipOption", 3 }, lastCall())
			press("PADDDOWN")
			assert.equal("New quest", bar().Choice.text)
			press("PAD2")
			assert.same({ "CloseGossip" }, lastCall())
		end)

		it("does nothing on A with nothing to select", function()
			fire("GOSSIP_SHOW")
			press("PAD1")
			assert.same({}, w.questCalls)
			assert.equal("", bar().Choice.text)
		end)

		it("leaves the D-pad alone with a single choice", function()
			w.quest.gossipOptions = { { name = "Goodbye then", orderIndex = 1 } }
			fire("GOSSIP_SHOW")
			press("PADDDOWN")
			assert.is_true(bar().propagate)
		end)
	end)

	describe("the settings page", function()
		it("keeps the choice per profile, in LeanPad's settings", function()
			ns.OpenOptions()
			local box
			for _, widget in ipairs(w.widgets) do
				if rawget(widget, "Check") and widget.point and widget.point[1] == "RIGHT" then
					local isQuests
					for _, other in ipairs(w.widgets) do
						if other.kind == "FontString" and other.text == "Answer quests with the pad" and other.point[5] == widget.point[5] then isQuests = true end
					end
					if isQuests then box = widget end
				end
			end
			assert.is_truthy(box)
			box:Fire("OnClick")
			assert.is_false(ns.db.questPrompts)
		end)
	end)

	it("sets Blizzard's interact icons for LeanPad's layout on Forever only", function()
		assert.is_nil(ns.CVARS.SoftTargetIconGameObject)
		ns = wow.bootForever({}, nil)
		assert.equal("1", ns.CVARS.SoftTargetIconGameObject)
		assert.equal("20", ns.CVARS.SoftTargetInteractRange)
	end)
end)
