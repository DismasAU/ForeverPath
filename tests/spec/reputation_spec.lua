local H = require("harness")
local Mock = H.Mock

local ARGENT_DAWN, TIMBERMAW, STORMWIND, IRONFORGE = 529, 576, 72, 47
local SUNFRUIT, DAWN_BOOTS_PATTERN, MANTLE = 13810, 19216, 18182
local HEIRLOOMS, GRUDGE = 96403, 96395

local function factions()
  Mock.SetFactions({
    { name = "Alliance Forces", isHeader = true },
    { name = "Stormwind", factionID = STORMWIND, value = 12000 },
    { name = "Ironforge", factionID = IRONFORGE, value = 2500 },
    { name = "Other", isHeader = true },
    { name = "Argent Dawn", factionID = ARGENT_DAWN, value = 4500 },
    { name = "Timbermaw Hold", factionID = TIMBERMAW, value = -1000 },
  })
end

local function installJournal()
  Mock.InstallDungeonJournal({
    ["Hall of Thanes"] = {
      level = "13-20", location = "Ironforge",
      bosses = {},
      quests = {
        { id = HEIRLOOMS, name = "Important Heirlooms", faction = "Both", level = 15, requires = 10, rewardSummary = "7s  -  Ironforge +100  -  Gnomeregan Exiles +100", rewardItems = {} },
        { id = GRUDGE, name = "An Ancient Grudge", faction = "Both", level = 15, requires = 10, rewardSummary = "Ironforge +250", rewardItems = {} },
      },
    },
  })
end

local function installAtlasFactions()
  Mock.InstallAtlasLoot({
    AtlasLootClassic_Factions = {
      ArgentDawn = { FactionID = ARGENT_DAWN, items = {
        { name = "Exalted", [1] = { { 1, "f529rep8" }, { 2, MANTLE } } },
        { name = "Revered", [1] = { { 1, "f529rep7" }, { 2, SUNFRUIT } } },
        { name = "Honored", [1] = { { 1, "f529rep6" }, { 2, DAWN_BOOTS_PATTERN } } },
        { name = "Friendly", [1] = { { 1, "f529rep5" } } },
      } },
    },
  }, { lazy = true })
end

describe("ReputationProvider", function()
  local ns, RP
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    RP = ns.ReputationProvider
    factions()
    RP.Invalidate()
    Mock.AddItem(SUNFRUIT, { name = "Blessed Sunfruit" })
    Mock.AddItem(DAWN_BOOTS_PATTERN, { name = "Pattern: Argent Boots", quality = 2 })
    Mock.AddItem(MANTLE, { name = "Chromatic Mantle of the Dawn", quality = 3 })
  end)

  it("lists factions with standings, thresholds, groups and searches them", function()
    assert_true(RP.IsAvailable())
    local list = RP.List()
    assert_eq(#list, 4)
    assert_eq(list[1].name, "Stormwind")
    assert_eq(list[1].header, "Alliance Forces")
    assert_eq(list[1].standing, 6)
    assert_eq(list[1].standingLabel, "Honored")
    assert_eq(list[1].into, 3000)
    assert_eq(list[1].span, 12000)
    assert_eq(list[1].percentWithin, 25)
    assert_eq(list[3].name, "Argent Dawn")
    assert_eq(list[3].header, "Other")
    assert_eq(list[3].standing, 5)
    assert_eq(list[4].standing, 3, "Unfriendly")
    assert_eq(list[4].standingLabel, "Unfriendly")
    local record = RP.Get(ARGENT_DAWN)
    assert_eq(record.name, "Argent Dawn")
    assert_eq(record.header, "Other")
    assert_nil(RP.Get(99999))
    assert_eq(RP.Search("argent", 5)[1].factionID, ARGENT_DAWN)
    assert_eq(RP.Search("Ironforge", 5)[1].factionID, IRONFORGE)
    assert_eq(#RP.Search("zzz", 5), 0)
    assert_eq(RP.StandingByName("exalted"), 8)
    assert_eq(RP.StandingByName("Hon"), 6)
    assert_nil(RP.StandingByName("nope"))
    assert_eq(RP.StandingFor(21000), 7)
    assert_eq(RP.StandingFor(-6001), 1)
    assert_eq(RP.NextStanding(record), 6)
    local progress = RP.Progress(ARGENT_DAWN, 8, 4500)
    assert_eq(progress.remaining, 37500)
    assert_false(progress.reached)
    assert_eq(progress.percent, 0)
    progress = RP.Progress(STORMWIND, 6)
    assert_true(progress.reached)
    assert_eq(progress.percent, 100)
    Mock.SetReputation(ARGENT_DAWN, 23250)
    Mock.RunTimers()
    progress = RP.Progress(ARGENT_DAWN, 8, 4500)
    assert_eq(progress.record.standing, 7)
    assert_eq(progress.percent, 50)
    assert_match(RP.Status(), "^Reputations: 4 factions listed; 0 quest rewards known; faction rewards unavailable")
  end)

  it("knows the quests and rewards that raise a reputation", function()
    installJournal()
    installAtlasFactions()
    ns.QuestProvider.Invalidate()
    RP.questRewards = nil
    local rewards = RP.QuestRewards()
    assert_eq(#rewards["Ironforge"], 2)
    assert_eq(rewards["Ironforge"][1].questID, GRUDGE, "largest reward first")
    assert_eq(rewards["Ironforge"][1].amount, 250)
    assert_eq(#rewards["Gnomeregan Exiles"], 1)
    local quests = RP.QuestsFor("Ironforge")
    assert_eq(quests[1].name, "An Ancient Grudge")
    assert_eq(quests[1].label, "Available")
    Mock.CompleteQuest(GRUDGE)
    Mock.RunTimers()
    assert_eq(RP.QuestsFor("Ironforge")[1].label, "Done")
    -- Rewards per standing, loaded on demand through AtlasLoot's loader.
    assert_eq(RP.atlas.state, "idle")
    local tiers = RP.Rewards(ARGENT_DAWN)
    assert_eq(RP.atlas.state, "ready")
    assert_eq(Mock.atlasLoads[1], "AtlasLootClassic_Factions")
    assert_eq(#tiers, 4)
    assert_eq(tiers[1].standing, 5)
    assert_eq(#tiers[1].items, 0, "rep icons are not items")
    assert_eq(tiers[2].standing, 6)
    assert_eq(tiers[2].items[1], DAWN_BOOTS_PATTERN)
    assert_eq(tiers[4].standing, 8)
    assert_eq(tiers[4].items[1], MANTLE)
    assert_eq(RP.SoldBy(SUNFRUIT)[1].standing, 7)
    -- Hints: reachable at the standing, unavailable below it.
    local hints = RP.Hints(DAWN_BOOTS_PATTERN)
    assert_eq(hints[1].kind, "vendor")
    assert_eq(hints[1].label, "Reputation reward: Argent Dawn (Honored)")
    assert_true(hints[1].unavailable, "Friendly is below Honored")
    assert_match(hints[1].reason, "^needs Honored with Argent Dawn; you are Friendly$")
    Mock.SetReputation(ARGENT_DAWN, 10000)
    Mock.RunTimers()
    hints = RP.Hints(DAWN_BOOTS_PATTERN)
    assert_nil(hints[1].unavailable)
    assert_eq(hints[1].name, "Argent Dawn quartermaster")
    local sources = ns.SourceProvider.Sources(DAWN_BOOTS_PATTERN)
    assert_eq(sources[#sources].label, "Reputation reward: Argent Dawn (Honored)")
    local goal = ns.GoalService.AddObtainGoal(DAWN_BOOTS_PATTERN, 1)
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.tree.root.route, "vendor")
    assert_match(view.message, "Reputation reward: Argent Dawn %(Honored%)")
    assert_match(RP.Status(), "3 quest rewards known; faction rewards from AtlasLoot")
    local lines = RP.Describe(ARGENT_DAWN, ns.ItemProvider.GetName)
    assert_match(lines[1], "^Argent Dawn: Honored %(1000 / 12000 into it%)$")
    assert_match(lines[#lines], "Exalted unlocks: Chromatic Mantle of the Dawn")
  end)
end)

describe("Reputation goals", function()
  local ns, RP
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    RP = ns.ReputationProvider
    factions()
    installJournal()
    installAtlasFactions()
    RP.Invalidate()
    ns.QuestProvider.Invalidate()
    Mock.AddItem(SUNFRUIT, { name = "Blessed Sunfruit" })
    Mock.AddItem(DAWN_BOOTS_PATTERN, { name = "Pattern: Argent Boots", quality = 2 })
    Mock.AddItem(MANTLE, { name = "Chromatic Mantle of the Dawn", quality = 3 })
  end)

  it("plans a standing, follows the quests that give reputation and completes on the standing", function()
    local GoalModel = ns.GoalModel
    assert_true(GoalModel.IsSupported("REACH_REPUTATION"))
    assert_nil((GoalModel.New("REACH_REPUTATION", { factionID = 1, standing = 9 })), "standing bounded")
    local ok, message, goal = ns.GoalService.AddReputationFromInput("ironforge honored")
    assert_true(ok, message)
    assert_eq(goal.type, "REACH_REPUTATION")
    assert_eq(goal.target.factionID, IRONFORGE)
    assert_eq(goal.target.standing, 6)
    assert_eq(goal.target.startValue, 2500)
    assert_eq(ns.GoalService.Title(goal), "Reach Honored with Ironforge")
    assert_eq(ns.GoalService.Name(goal), "Ironforge - Honored")
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.status, ns.Status.OK)
    assert_eq(view.reputation.record.standingLabel, "Neutral")
    assert_eq(view.reputation.progress.remaining, 6500)
    assert_eq(view.progress.percent, 0)
    assert_eq(view.message, "6500 more reputation to Honored with Ironforge (you are Neutral, 2500 / 3000 into it). Quest An Ancient Grudge gives +250.")
    assert_eq(view.nextStep, "An Ancient Grudge (+250)")
    assert_true(view.plan.step)
    assert_eq(ns.Overview.Percent(view), 0)
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "An Ancient Grudge (+250)")
    assert_eq(overview.nextSteps[1].badge, "Neutral")
    assert_match(overview.nextSteps[1].detail, "^Neutral now %- 6500 to go")
    -- Every open quest that gives Ironforge reputation feeds the goal on the Quests screen.
    local feeds = ns.QuestProvider.FeedsGoals({ goal }, { [goal.id] = view }, ns.GoalService.Name)
    assert_not_nil(feeds[GRUDGE])
    assert_eq(feeds[GRUDGE].goals[1].reputation, 250)
    assert_eq(feeds[GRUDGE].goals[1].faction, "Ironforge")
    assert_eq(feeds[GRUDGE].goals[1].name, "Ironforge - Honored")
    local fed = 0
    for _ in pairs(feeds) do fed = fed + 1 end
    assert_eq(fed, 2, "both Ironforge quests")
    assert_eq(#ns.QuestProvider.FeedsGoals({ goal }, {}, ns.GoalService.Name)[GRUDGE].goals, 1, "without a view the provider is asked directly")
    ns.Commands.Dispatch("quests")
    assert_output("An Ancient Grudge %[Available%] %- .* %- feeds Ironforge %- Honored")
    local MainFrame = ns.UI.MainFrame
    MainFrame.Show()
    Mock.RunTimers()
    MainFrame.ShowScreen("quests")
    Mock.RunTimers()
    local quests = MainFrame.screens.quests
    quests.tabs.tabs.goal:Click()
    Mock.RunTimers()
    local labels = {}
    for _, row in ipairs(quests.groupPool.rows) do if row:IsShown() then labels[#labels + 1] = row.label:GetText() end end
    assert_eq(#labels, 1)
    assert_match(labels[1], "IRONFORGE %- HONORED")
    quests:Select(GRUDGE)
    assert_match(quests.side.feedsText:GetText(), "^%+250 Ironforge reputation for Ironforge %- Honored$")
    quests.tabs.tabs.zone:Click()
    MainFrame.Hide()
    -- Defaults: no standing given means the next one up; "exalted argent dawn" also parses.
    local second = select(3, ns.GoalService.AddReputationFromInput("argent dawn"))
    assert_eq(second.target.standing, 6)
    local third = select(3, ns.GoalService.AddReputationFromInput("exalted argent dawn"))
    assert_eq(third.id, second.id, "same faction: the goal is retargeted")
    assert_eq(third.target.standing, 8)
    assert_match(select(2, ns.GoalService.AddReputationFromInput("argent dawn exalted")), "^Updated goal: Reach Exalted with Argent Dawn")
    local nope, why = ns.GoalService.AddReputationFromInput("nothing here")
    assert_false(nope)
    assert_match(why, "No faction called")
    -- Earning reputation moves the goal; reaching the standing completes it.
    Mock.SetReputation(IRONFORGE, 5750)
    Mock.RunTimers()
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.reputation.record.standingLabel, "Friendly")
    assert_eq(view.progress.percent, 50)
    Mock.CompleteQuest(GRUDGE)
    Mock.RunTimers()
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.nextStep, "Important Heirlooms (+100)", "the next open quest")
    Mock.SetReputation(IRONFORGE, 9000)
    Mock.RunTimers()
    assert_eq(goal.status, "COMPLETED")
    assert_eq(goal.target.completedBy, "auto")
    assert_output("Goal complete: Ironforge %- Honored reached%.")
    assert_eq(ns.UI.Toast.lastShown.title, "Reputation reached")
    view = ns.Planner.Evaluate(goal)
    assert_true(view.reputation.progress.reached)
    assert_match(view.message, "^Honored with Ironforge reached%.$")
    -- Raising the target reopens it from the new value.
    local again, text = ns.GoalService.AddReputationGoal(IRONFORGE, 7)
    assert_eq(again.id, goal.id)
    assert_eq(again.status, "ACTIVE")
    assert_eq(again.target.startValue, 9000)
    assert_match(text, "^Updated goal: Reach Revered with Ironforge")
    ns.Commands.Dispatch("reps")
    assert_output("Ironforge: Honored %(0 / 12000%) %[goal: Revered%]")
    ns.Commands.Dispatch("rep timbermaw friendly")
    assert_output("Added goal: Reach Friendly with Timbermaw Hold")
  end)

  it("renders the Reputations screen with groups, the faction panel, quests, rewards and goal buttons", function()
    local MainFrame = ns.UI.MainFrame
    local goal = ns.GoalService.AddReputationGoal(ARGENT_DAWN, 7)
    MainFrame.OpenGoal(goal.id)
    Mock.RunTimers()
    assert_eq(MainFrame.currentScreen, "reputations")
    local screen = MainFrame.screens.reputations
    assert_eq(screen.factionID, ARGENT_DAWN, "the selected goal picks the faction")
    local side = screen.side
    assert_eq(side.title:GetText(), "Argent Dawn")
    assert_match(side.meta:GetText(), "Friendly")
    assert_match(side.barText:GetText(), "^1500 / 6000 into Friendly")
    assert_eq(side.segment.selected, "7", "the goal's target")
    assert_match(side.toTarget:GetText(), "^16500 reputation to Revered")
    assert_eq(side.addGoal.label:GetText(), "Open goal")
    assert_true(side.rewardIcons[1]:IsShown())
    assert_eq(side.rewardIcons[1].itemID, SUNFRUIT)
    assert_match(side.rewardsText:GetText(), "^1 item unlocks at Revered")
    assert_true(side.questsEmpty:IsShown(), "no dungeon quest rewards Argent Dawn here")
    local groups, rows = 0, 0
    for _, row in ipairs(screen.groupPool.rows) do if row:IsShown() then groups = groups + 1 end end
    for _, row in ipairs(screen.rowPool.rows) do if row:IsShown() then rows = rows + 1 end end
    assert_eq(groups, 2)
    assert_eq(rows, 4)
    assert_match(screen.footerText:GetText(), "^4 factions %- 1 reputation goal")
    -- Pick another target: the button retargets the goal.
    side.segment.segments["8"]:Click()
    assert_eq(side.addGoal.label:GetText(), "Retarget goal to Exalted")
    side.addGoal:Click()
    Mock.RunTimers()
    assert_eq(goal.target.standing, 8)
    assert_eq(side.rewardIcons[1].itemID, MANTLE)
    -- Ironforge: quests listed, clicking one opens the Quests screen on it.
    screen:Select(IRONFORGE)
    assert_eq(side.title:GetText(), "Ironforge")
    assert_true(side.questRows[1]:IsShown())
    assert_match(side.questRows[1].name:GetText(), "An Ancient Grudge")
    assert_eq(side.questRows[1].amount:GetText(), "+250")
    assert_match(side.addGoal.label:GetText(), "^%+ Add goal: Friendly")
    side.questRows[1]:Click()
    Mock.RunTimers()
    assert_eq(MainFrame.currentScreen, "quests")
    assert_eq(MainFrame.screens.quests.questID, GRUDGE)
    -- My Goals, Dashboard, Crafting and the tracker cope with reputation goals.
    MainFrame.ShowScreen("goals")
    Mock.RunTimers()
    local goals = MainFrame.screens.goals
    goals.newGoal.segment:Select("reputation")
    goals.newGoal.input:SetText("stormwind exalted")
    assert_true(goals:Submit())
    assert_eq(ns.GoalService.GetSelected().target.factionID, STORMWIND)
    goals.newGoal.segment:Select("item")
    MainFrame.ShowScreen("dashboard")
    Mock.RunTimers()
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    assert_match(MainFrame.screens.crafting.empty.title:GetText(), "Reputation goal")
    ns.UI.Tracker.Refresh()
    assert_true(ns.UI.Tracker.IsShown())
    assert_eq(#ns.Log.errors, 0, ns.Log.errors[1] and ns.Log.errors[1].message or "")
  end)
end)
