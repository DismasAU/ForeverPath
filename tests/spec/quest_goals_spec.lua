local H = require("harness")
local Mock = H.Mock

-- Wailing Caverns quests as ForeverDungeonJournal ships them, trimmed.
local HIDES, SMART_DRINKS, LEADERS = 1486, 1491, 914
local POOLS, OASIS, BEINGS, HAMUUL, NARA = 870, 877, 880, 1489, 1490
local HORNS = 865
local LEGGINGS, PACK = 6480, 918
local ONYXIA_Q1 = 4182

local function installJournal()
  Mock.InstallDungeonJournal({
    ["Wailing Caverns"] = {
      level = "17-24", location = "The Barrens",
      bosses = {},
      quests = {
        { id = HIDES, name = "Deviate Hides", faction = "Both", level = 17, requires = 13, objective = "Bring 20 Deviate Hides to Nalpak.",
          pickup = "Nalpak, above the entrance to Wailing Caverns, The Barrens", turnin = "Nalpak, above the entrance to Wailing Caverns, The Barrens",
          rewards = "Choose: Slick Deviate Leggings or Deviate Hide Pack\n4,640 XP - 18s", rewardSummary = "18s", liveXPFallback = 1600,
          rewardChoice = true, rewardItems = { { LEGGINGS, "Slick Deviate Leggings", 2 }, { PACK, "Deviate Hide Pack", 1 } } },
        { id = SMART_DRINKS, name = "Smart Drinks", faction = "Both", level = 18, requires = 13, objective = "Bring 6 Wailing Essence to Mebok Mizzyrix.",
          pickup = "Mebok Mizzyrix, Ratchet, The Barrens", turnin = "Mebok Mizzyrix, Ratchet, The Barrens", rewardItems = {} },
        { id = LEADERS, name = "Leaders of the Fang", faction = "Both", level = 21, requires = 15, objective = "Kill the four Druids of the Fang.",
          pickup = "Nara Wildmane, Thunder Bluff", turnin = "Nara Wildmane, Thunder Bluff", rewardChoice = true, rewardItems = { { 6481, "Crescent Staff", 3 } } },
        { id = 9999, name = "Horde Only", faction = "Horde", level = 20, rewardItems = {} },
      },
    },
  }, {}, {
    chains = {
      [SMART_DRINKS] = { { id = HORNS, name = "Raptor Horns" } },
      [LEADERS] = { { id = POOLS, name = "The Forgotten Pools" }, { id = OASIS, name = "The Stagnant Oasis" }, { id = BEINGS, name = "Altered Beings" }, { id = HAMUUL, name = "Hamuul Runetotem" }, { id = NARA, name = "Nara Wildmane" } },
    },
    starts = { [POOLS] = { mapID = 1413, x = 0.52, y = 0.30, label = "Tonga Runetotem - The Crossroads", targetName = "Tonga Runetotem" } },
    xp = { [POOLS] = 680 },
  })
end

local function installAttune()
  Mock.InstallAttune({
    attunes = { { ID = "40", NAME = "Onyxia's Lair", GROUP = "RAIDS", FACTION = "Alliance", ICON = "ony", GROUPSIZE = 40 } },
    steps = { { ID_ATTUNE = "40", ID = "20", TYPE = "Quest", STEP = "", LOCATION = "Burning Steppes", ID_WOWHEAD = tostring(ONYXIA_Q1), ICON = "q", FOLLOWS = "0", STAGE = "1" } },
    quests = { [ONYXIA_Q1] = { 48, 2 } },
    questGivers = { [ONYXIA_Q1] = { 1428, 65.0, 24.0, "Helendis Riverhorn" } },
    questRewards = { [ONYXIA_Q1] = { fixed = { { 2770, 5 } } } },
  }, { lang = { Q1_4182 = "Dragonkin Menace" } })
end

describe("QuestProvider", function()
  local ns, QP
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    QP = ns.QuestProvider
    Mock.AddItem(LEGGINGS, { name = "Slick Deviate Leggings", quality = 2 })
    Mock.AddItem(PACK, { name = "Deviate Hide Pack" })
  end)

  it("indexes dungeon and attunement quests with chains, starts and rewards", function()
    assert_true(QP.IsAvailable())
    assert_false(QP.HasJournal())
    assert_eq(QP.Count(), 0)
    assert_match(QP.Status(), "0 known from no data addon; quest log 0 / 20")
    installJournal()
    installAttune()
    QP.Invalidate()
    assert_true(QP.HasJournal())
    assert_true(QP.HasAttune())
    local hides = QP.Get(HIDES)
    assert_eq(hides.name, "Deviate Hides")
    assert_eq(hides.instance, "Wailing Caverns")
    assert_eq(hides.level, 17)
    assert_eq(hides.requires, 13)
    assert_eq(hides.source, "journal")
    assert_eq(#hides.rewards, 2)
    assert_eq(hides.rewards[1].itemID, LEGGINGS)
    assert_true(hides.rewardChoice)
    assert_eq(hides.xp, 1600)
    local leaders = QP.Get(LEADERS)
    assert_eq(#leaders.chain, 5)
    assert_eq(leaders.chain[1].id, POOLS)
    local pools = QP.Get(POOLS)
    assert_eq(pools.source, "chain", "prerequisites that are not dungeon quests still get an entry")
    assert_eq(pools.name, "The Forgotten Pools")
    assert_eq(pools.instance, "Wailing Caverns")
    assert_eq(pools.start.label, "Tonga Runetotem - The Crossroads")
    assert_eq(pools.xp, 680)
    local ony = QP.Get(ONYXIA_Q1)
    assert_eq(ony.name, "Dragonkin Menace")
    assert_eq(ony.source, "attune")
    assert_eq(ony.instance, "Onyxia's Lair")
    assert_eq(ony.attunement, "Onyxia's Lair")
    assert_eq(ony.location, "Burning Steppes")
    assert_eq(ony.pickup, "Helendis Riverhorn")
    assert_eq(ony.requires, 48)
    assert_eq(ony.groupSize, 2)
    assert_eq(ony.rewards[1].itemID, 2770)
    assert_eq(ony.rewards[1].count, 5)
    assert_eq(ony.faction, "Alliance")
    -- Faction filter and search.
    local list = QP.List()
    local ids = {}
    for _, entry in ipairs(list) do ids[entry.id] = true end
    assert_true(ids[HIDES])
    assert_nil(ids[9999], "Horde-only quests are hidden from an Alliance character")
    assert_true(ids[ONYXIA_Q1])
    assert_eq(QP.Search("deviate", 5)[1].questID, HIDES)
    assert_eq(QP.Search("Leaders of the Fang", 5)[1].questID, LEADERS)
    assert_eq(#QP.Search("zzz", 5), 0)
    assert_eq(QP.QuestsRewarding(LEGGINGS)[1].id, HIDES)
    assert_match(QP.Status(), "known from ForeverDungeonJournal and Attune")
    -- Difficulty colours.
    assert_eq(QP.Difficulty(17, 10), "impossible")
    assert_eq(QP.Difficulty(17, 14), "hard")
    assert_eq(QP.Difficulty(17, 17), "standard")
    assert_eq(QP.Difficulty(17, 22), "easy")
    assert_eq(QP.Difficulty(17, 30), "trivial")
  end)

  it("reads the log, objectives, readiness and titles from the client", function()
    installJournal()
    QP.Invalidate()
    local state = QP.State(HIDES)
    assert_false(state.inLog)
    assert_eq(QP.StateLabel(state, QP.Get(HIDES), 10), "Locked", "level 10 cannot take a level-13 quest")
    assert_eq(QP.StateLabel(state, QP.Get(HIDES), 20), "Available")
    assert_eq(QP.StateLabel(state, QP.Get(SMART_DRINKS), 20), "Locked", "Raptor Horns first")
    Mock.CompleteQuest(HORNS)
    assert_eq(QP.StateLabel(QP.State(SMART_DRINKS), QP.Get(SMART_DRINKS), 20), "Available")
    Mock.AcceptQuest(HIDES, { title = "Deviate Hides", level = 17, zone = "The Barrens", objectives = { { text = "Deviate Hide: 3/20", numFulfilled = 3, numRequired = 20 } } })
    Mock.AcceptQuest(77777, { title = "Some Other Quest", level = 12, zone = "Durotar", objectives = { { text = "Explore the place", type = "event", numRequired = 0 } } })
    state = QP.State(HIDES)
    assert_true(state.inLog)
    assert_false(state.ready)
    assert_eq(state.logIndex, 2, "after the zone header")
    assert_eq(state.title, "Deviate Hides")
    assert_eq(#state.objectives, 1)
    assert_eq(state.objectives[1].numFulfilled, 3)
    assert_eq(state.fraction, 0.15)
    assert_eq(QP.ObjectiveText(state), "3/20 Deviate Hide: 3/20")
    assert_eq(QP.StateLabel(state, QP.Get(HIDES), 20), "In log")
    local entries = QP.LogEntries()
    assert_eq(#entries, 2)
    assert_eq(entries[1].zone, "The Barrens")
    assert_eq(entries[2].zone, "Durotar")
    assert_eq(entries[2].title, "Some Other Quest")
    local numQuests, max = QP.LogCapacity()
    assert_eq(numQuests, 2)
    assert_eq(max, 20)
    assert_eq(QP.Name(77777), "Some Other Quest", "log titles name quests the addons do not know")
    Mock.SetQuestObjective(HIDES, 1, 20)
    state = QP.State(HIDES)
    assert_true(state.ready)
    assert_eq(state.fraction, 1)
    assert_eq(QP.StateLabel(state, QP.Get(HIDES), 20), "Ready")
    -- Unknown quests get their title from the client, asynchronously.
    assert_eq(QP.Name(55555), "Quest 55555")
    assert_eq(Mock.quests.requests[1], 55555)
    Mock.quests.titles[55555] = "A Loaded Title"
    Mock.FireEvent("QUEST_DATA_LOAD_RESULT", 55555, true)
    assert_eq(QP.Name(55555), "A Loaded Title")
    assert_eq(#QP.Search("loaded", 5), 0, "titles loaded by id are not searchable by name")
    local lines = QP.Describe(HIDES, ns.ItemProvider.GetName)
    assert_match(lines[1], "^Deviate Hides %[Ready%] %- level 17 %- Wailing Caverns$")
    assert_match(lines[2], "^  Pick up: Nalpak")
    assert_match(lines[#lines], "^  Reward %(choose one%): Slick Deviate Leggings, Deviate Hide Pack$")
  end)
end)

describe("Quest goals", function()
  local ns, QP
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    QP = ns.QuestProvider
    installJournal()
    QP.Invalidate()
    Mock.AddItem(LEGGINGS, { name = "Slick Deviate Leggings", quality = 2 })
    Mock.AddItem(PACK, { name = "Deviate Hide Pack" })
    Mock.AddItem(6481, { name = "Crescent Staff", quality = 3 })
    Mock.character.level = 20
  end)

  it("plans a chained quest step by step and completes on the turn-in", function()
    local GoalModel = ns.GoalModel
    assert_true(GoalModel.IsSupported("COMPLETE_QUEST"))
    assert_nil((GoalModel.New("COMPLETE_QUEST", { name = "x" })), "questID required")
    local ok, message, goal = ns.GoalService.AddQuestFromInput("leaders of the fang")
    assert_true(ok, message)
    assert_eq(goal.type, "COMPLETE_QUEST")
    assert_eq(goal.target.questID, LEADERS)
    assert_eq(goal.target.instance, "Wailing Caverns")
    assert_eq(ns.GoalService.Title(goal), "Complete quest: Leaders of the Fang")
    assert_eq(ns.GoalService.Name(goal), "Leaders of the Fang")
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.status, ns.Status.OK)
    assert_eq(#view.quest.chain, 6)
    assert_eq(view.quest.next.id, POOLS)
    assert_eq(view.quest.label, "Locked")
    assert_eq(view.progress.percent, 0)
    assert_eq(view.message, "First pick up The Forgotten Pools from Tonga Runetotem - The Crossroads (required before Leaders of the Fang).")
    assert_eq(view.nextStep, "Pick up The Forgotten Pools")
    assert_true(view.plan.step)
    assert_eq(ns.Overview.Percent(view), 0)
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Pick up The Forgotten Pools")
    assert_eq(overview.nextSteps[1].badge, "Locked")
    assert_match(overview.nextSteps[1].detail, "^Wailing Caverns %- For Leaders of the Fang")
    assert_eq(#overview.missing, 0)
    -- Level gate.
    Mock.character.level = 10
    view = ns.Planner.Evaluate(goal)
    assert_true(view.quest.levelBlocked)
    assert_eq(view.message, "Needs level 15; you are 10.")
    assert_eq(view.nextStep, "Reach level 15")
    Mock.character.level = 20
    -- Work through the chain.
    Mock.AcceptQuest(POOLS, { title = "The Forgotten Pools", level = 11, zone = "The Barrens", objectives = { { text = "Forgotten Pools explored", type = "event", numRequired = 0 } } })
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.message, "First finish The Forgotten Pools: Forgotten Pools explored.")
    assert_eq(view.nextStep, "Finish The Forgotten Pools")
    Mock.SetQuestObjective(POOLS, 1, 1, true)
    view = ns.Planner.Evaluate(goal)
    assert_match(view.message, "^First turn in The Forgotten Pools")
    assert_eq(view.progress.percent, 17, "one of six in the log and ready")
    for _, id in ipairs({ POOLS, OASIS, BEINGS, HAMUUL, NARA }) do Mock.CompleteQuest(id) end
    Mock.RunTimers()
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.quest.next.id, LEADERS)
    assert_eq(view.quest.label, "Available")
    assert_eq(view.progress.percent, 83)
    assert_eq(view.message, "Pick up Leaders of the Fang from Nara Wildmane, Thunder Bluff. Kill the four Druids of the Fang.")
    assert_eq(view.nextStep, "Pick up Leaders of the Fang")
    Mock.AcceptQuest(LEADERS, { title = "Leaders of the Fang", level = 21, zone = "The Barrens", objectives = {
      { text = "Lord Cobrahn slain: 0/1", numFulfilled = 0, numRequired = 1 }, { text = "Lord Pythas slain: 0/1", numFulfilled = 0, numRequired = 1 } } })
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.quest.label, "In log")
    assert_eq(view.message, "In your log: 0/1 Lord Cobrahn slain: 0/1, 0/1 Lord Pythas slain: 0/1.")
    assert_eq(view.nextStep, "Finish Leaders of the Fang")
    Mock.SetQuestObjective(LEADERS, 1, 1)
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.progress.percent, 92)
    Mock.SetQuestObjective(LEADERS, 2, 1)
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.quest.label, "Ready")
    assert_eq(view.message, "Ready to turn in at Nara Wildmane, Thunder Bluff.")
    assert_eq(view.item.icon, QP.ICON_READY)
    overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Turn in Leaders of the Fang")
    assert_eq(overview.nextSteps[1].badge, "Ready")
    -- Turn in: QUEST_TURNED_IN completes the goal with its toast.
    Mock.CompleteQuest(LEADERS)
    Mock.RunTimers()
    assert_eq(goal.status, "COMPLETED")
    assert_eq(goal.target.completedBy, "auto")
    assert_output("Goal complete: Quest done: Leaders of the Fang%.")
    assert_eq(ns.UI.Toast.lastShown.title, "Quest complete")
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.progress.percent, 100)
    assert_match(view.message, "is completed")
    local again, text = ns.GoalService.AddQuestGoal(LEADERS)
    assert_eq(again.id, goal.id)
    assert_match(text, "^Already a goal")
    -- Quests nobody indexed still work from the log.
    Mock.AcceptQuest(77777, { title = "Some Other Quest", level = 12, zone = "Durotar", objectives = { { text = "Explore", type = "event", numRequired = 0 } } })
    ok, message, goal = ns.GoalService.AddQuestFromInput("some other")
    assert_true(ok, message)
    assert_eq(goal.target.questID, 77777)
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.message, "In your log: Explore.")
    local nope, why = ns.GoalService.AddQuestFromInput("nothing like this")
    assert_false(nope)
    assert_match(why, "No quest called")
  end)

  it("links quests to the item goals their rewards feed, in chat and on the screen", function()
    local MainFrame = ns.UI.MainFrame
    local itemGoal = ns.GoalService.AddObtainGoal(LEGGINGS, 1)
    local views = ns.Planner.EvaluateAll({ itemGoal })
    local feeds = QP.FeedsGoals({ itemGoal }, views, ns.GoalService.Name)
    assert_not_nil(feeds[HIDES])
    assert_eq(feeds[HIDES].goals[1].name, "Slick Deviate Leggings")
    assert_eq(feeds[HIDES].goals[1].count, 1)
    ns.Commands.Dispatch("quests")
    assert_output("Deviate Hides %[Available%] %- Wailing Caverns %- feeds Slick Deviate Leggings")
    ns.Commands.Dispatch("quest deviate hides")
    assert_output("Added goal: Complete quest: Deviate Hides")
    local questGoal = ns.GoalService.GetSelected()
    assert_eq(questGoal.target.questID, HIDES)
    -- The Quests screen: groups, selection, details, goal button, tabs, filter.
    MainFrame.OpenGoal(questGoal.id)
    Mock.RunTimers()
    assert_eq(MainFrame.currentScreen, "quests")
    local screen = MainFrame.screens.quests
    assert_eq(screen.questID, HIDES, "the selected quest goal picks the quest")
    assert_eq(screen.side.title:GetText(), "Deviate Hides")
    assert_match(screen.side.meta:GetText(), "Level 17")
    assert_match(screen.side.meta:GetText(), "Wailing Caverns %- Nalpak")
    assert_match(screen.side.feedsText:GetText(), "^Slick Deviate Leggings: 1 missing for Slick Deviate Leggings")
    assert_match(screen.side.rewardsText:GetText(), "Choose: Slick Deviate Leggings or Deviate Hide Pack")
    assert_eq(screen.side.addGoal.label:GetText(), "Open goal")
    assert_match(screen.footerFeeds:GetText(), "^1 quest feeds your goals")
    assert_match(screen.footerLog:GetText(), "^Quest log 0 / 20")
    local shown, groups = 0, 0
    for _, row in ipairs(screen.rowPool.rows) do if row:IsShown() then shown = shown + 1 end end
    for _, row in ipairs(screen.groupPool.rows) do if row:IsShown() then groups = groups + 1 end end
    assert_eq(shown, 9, "three dungeon quests and six chain prerequisites (five for Leaders, Raptor Horns for Smart Drinks), Horde quest hidden")
    assert_eq(groups, 1)
    -- Only quests that feed a goal.
    screen.feedOnly:Click()
    shown = 0
    for _, row in ipairs(screen.rowPool.rows) do if row:IsShown() then shown = shown + 1 end end
    assert_eq(shown, 1)
    assert_true(ns.chardb.ui.questsFeedOnly)
    screen.feedOnly:Click()
    -- By goal tab lists the feeding quest under the goal's name.
    screen.tabs.tabs.goal:Click()
    Mock.RunTimers()
    assert_eq(screen.tab, "goal")
    local labels = {}
    for _, row in ipairs(screen.groupPool.rows) do if row:IsShown() then labels[#labels + 1] = row.label:GetText() end end
    assert_eq(#labels, 1)
    assert_match(labels[1], "DEVIATE HIDES")
    assert_match(labels[1], "SLICK DEVIATE LEGGINGS")
    -- Selecting a row and the log-only buttons.
    screen.tabs.tabs.zone:Click()
    Mock.RunTimers()
    screen:Select(SMART_DRINKS)
    assert_eq(screen.side.title:GetText(), "Smart Drinks")
    assert_eq(screen.side.addGoal.label:GetText(), "+ Add goal")
    assert_match(screen.side.objectives[2].text:GetText(), "Requires: Raptor Horns")
    assert_false(screen:LinkQuest(SMART_DRINKS), "not in the log")
    Mock.AcceptQuest(SMART_DRINKS, { title = "Smart Drinks", level = 18, zone = "The Barrens", objectives = { { text = "Wailing Essence: 0/6", numFulfilled = 0, numRequired = 6 } } })
    Mock.RunTimers()
    assert_true(screen:LinkQuest(SMART_DRINKS))
    assert_output("|Hquest:1491:18|h%[Smart Drinks%]")
    assert_true(screen:WatchQuest(SMART_DRINKS))
    assert_true(Mock.quests.watched[SMART_DRINKS])
    screen.side.addGoal:Click()
    assert_not_nil(ns.GoalService.FindQuestGoal(SMART_DRINKS))
    -- Completed tab after a turn-in.
    Mock.CompleteQuest(HIDES)
    Mock.RunTimers()
    screen.tabs.tabs.completed:Click()
    Mock.RunTimers()
    shown = 0
    for _, row in ipairs(screen.rowPool.rows) do if row:IsShown() then shown = shown + 1 end end
    assert_eq(shown, 1)
    assert_eq(questGoal.status, "COMPLETED")
    -- Other screens cope with quest goals.
    MainFrame.ShowScreen("goals")
    Mock.RunTimers()
    MainFrame.ShowScreen("dashboard")
    Mock.RunTimers()
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    assert_match(MainFrame.screens.crafting.empty.title:GetText(), "Quest goal")
    ns.UI.Tracker.Refresh()
    assert_true(ns.UI.Tracker.IsShown())
    assert_eq(#ns.Log.errors, 0, ns.Log.errors[1] and ns.Log.errors[1].message or "")
  end)
end)
