local H = require("harness")
local Mock = H.Mock

describe("UI shell and screens (mock widgets)", function()
  local ns, MainFrame, frame
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    MainFrame = ns.UI.MainFrame
    Mock.AddItem(2589, { name = "Linen Cloth", quality = 1 })
    Mock.AddItem(2996, { name = "Bolt of Linen Cloth", quality = 1 })
    Mock.AddItem(4238, { name = "Linen Bag", quality = 1 })
    Mock.AddItem(2320, { name = "Coarse Thread", quality = 1 })
    Mock.AddRecipe({ recipeID = 2963, name = "Bolt of Linen Cloth", outputItemID = 2996, reagents = { { itemID = 2589, quantity = 2 } } })
    Mock.AddRecipe({ recipeID = 3755, name = "Linen Bag", outputItemID = 4238, reagents = { { itemID = 2996, quantity = 3 }, { itemID = 2320, quantity = 3 } } })
    Mock.OpenProfession({ professionID = 197, name = "Tailoring", skillLevel = 50, maxSkillLevel = 150, recipeIDs = { 2963, 3755 } })
    Mock.FireEvent("TRADE_SKILL_LIST_UPDATE")
    Mock.RunTimers()
    Mock.SetProfessions({ { slot = 1, name = "Tailoring", skillLevel = 50, maxSkillLevel = 150, skillLine = 197 } })
    Mock.SetBag(0, 16, { { 2589, 5 } })
    MainFrame.Show()
    Mock.RunTimers()
    frame = MainFrame.frame
  end)

  local function screen(key) return MainFrame.screens[key] end

  it("builds the shell: header, sidebar, status bar, screens", function()
    assert_eq(frame.title:GetText(), "ForeverPath")
    assert_eq(frame.charName:GetText(), "Thandrel")
    assert_match(frame.charMeta:GetText(), "Level 60 Warrior")
    assert_match(frame.charMeta:GetText(), "Stormhold")
    assert_eq(frame.versionText:GetText(), "ForeverPath 0.1.0-test")
    assert_not_nil(frame.navButtons.dashboard)
    assert_not_nil(frame.navButtons.characters)
    for _, key in ipairs({ "dashboard", "goals", "crafting", "equipment", "quests", "reputations", "attunements", "characters" }) do
      assert_not_nil(MainFrame.screens[key], "screen " .. key)
    end
    assert_eq(MainFrame.currentScreen, "dashboard")
    assert_true(screen("dashboard"):IsShown())
    assert_false(screen("goals"):IsShown())
    assert_eq(_G.UISpecialFrames[1], "ForeverPathMainFrame")
    assert_match(frame.bagsText:GetText(), "Bags synced")
    assert_match(frame.recipesText:GetText(), "2 recorded")
    assert_match(frame.pill.name:GetText(), "No goals yet")
  end)

  it("switches screens from the sidebar and remembers the last one", function()
    frame.navButtons.goals:Click()
    assert_eq(MainFrame.currentScreen, "goals")
    assert_true(screen("goals"):IsShown())
    assert_false(screen("dashboard"):IsShown())
    assert_eq(ns.chardb.ui.screen, "goals")
    frame.navButtons.quests:Click()
    assert_true(screen("quests"):IsShown())
    MainFrame.Hide()
    local saved = Mock.deepcopy(_G.ForeverPathCharDB)
    local ns2 = H.fresh()
    _G.ForeverPathCharDB = saved
    H.login(ns2)
    ns2.UI.MainFrame.Show()
    assert_eq(ns2.UI.MainFrame.currentScreen, "quests")
  end)

  it("keeps the header divider clear of the tagline and hover fills under text", function()
    -- Divider sits after the wider of title and tagline (the caps tagline here).
    local _, relativeTo, _, x = frame.brandDivider:GetPoint(1)
    assert_eq(relativeTo, frame.title)
    local widest = math.max(frame.title:GetStringWidth(), frame.tagline:GetStringWidth())
    assert_eq(x, widest + 14)
    -- Character lines are bounded by the pill so they truncate, not overlap.
    local _, charRight = frame.charMeta:GetPoint(2)
    assert_eq(charRight, frame.pill)

    -- Goal switcher rows: hover fill lives on the BACKGROUND layer and only
    -- shows while the mouse is over the row (an opaque HIGHLIGHT texture
    -- would cover the text).
    ns.GoalService.AddCraftGoal(2996, 1)
    Mock.RunTimers()
    local menu = MainFrame.OpenGoalSwitcher(frame.pill)
    assert_not_nil(menu)
    local row = menu.rows[1]
    assert_match(row.text:GetText(), "Bolt of Linen Cloth")
    assert_eq(row.hoverFill.layer, "BACKGROUND")
    assert_false(row.hoverFill:IsShown())
    row:Fire("OnEnter")
    assert_true(row.hoverFill:IsShown())
    row:Fire("OnLeave")
    assert_false(row.hoverFill:IsShown())
    ns.UI.Widgets.CloseMenu()

    -- Same for header search suggestions.
    frame.search:SetText("lin")
    frame.search:Fire("OnTextChanged", true)
    local suggestion = frame.suggestions.rows[1]
    assert_not_nil(suggestion)
    assert_eq(suggestion.hoverFill.layer, "BACKGROUND")
    suggestion:Fire("OnEnter")
    assert_true(suggestion.hoverFill:IsShown())
  end)

  it("adds a goal from the header search and opens the crafting screen", function()
    frame.search:SetText("2996")
    frame.search:Fire("OnEnterPressed")
    Mock.RunTimers()
    assert_eq(#ns.GoalService.List(), 1)
    assert_eq(MainFrame.currentScreen, "crafting")
    assert_eq(frame.search:GetText(), "")
    assert_match(frame.alertText:GetText(), "Added goal")
    local crafting = screen("crafting")
    assert_eq(crafting.view.status, ns.Status.OK)
    assert_match(crafting.hero.name:GetText(), "Bolt of Linen Cloth")
    assert_eq(crafting.hero.percent:GetText(), "100%", "5 cloth owned, 2 needed")
    local row = crafting.pool.rows[1]
    assert_true(row:IsShown())
    assert_match(row.name:GetText(), "Linen Cloth")
    assert_eq(row.need:GetText(), "2")
    assert_eq(row.have:GetText(), "5")
    assert_true(row.check:IsShown())
    assert_eq(row.sourceFrame.tags[1].label:GetText(), "In bags")
    assert_match(frame.pill.name:GetText(), "Bolt of Linen Cloth")
    assert_eq(frame.pill.percent:GetText(), "100%")
  end)

  it("shows missing materials, chips and sorting in the crafting screen", function()
    ns.GoalService.AddCraftGoal(4238, 2)
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    local crafting = screen("crafting")
    local view = crafting.view
    assert_eq(view.plan.craftsNeeded, 2)
    assert_eq(crafting.hero.chips[1].label:GetText(), "Tailoring - you have 50")
    assert_eq(crafting.hero.chips[2].label:GetText(), "Recipe known")
    assert_match(crafting.hero.reagents:GetText(), "0 of 12 reagents")
    local first = crafting.pool.rows[1]
    assert_match(first.name:GetText(), "Bolt of Linen Cloth", "missing sort puts the biggest gap first")
    assert_eq(first.need:GetText(), "6")
    assert_eq(first.missing:GetText(), "6")
    assert_eq(first.sourceFrame.tags[1].label:GetText(), "Craft - Tailoring")
    ns.chardb.ui.materialSort = "name"
    crafting:Refresh()
    assert_match(crafting.pool.rows[1].name:GetText(), "Bolt of Linen Cloth")
    assert_match(crafting.pool.rows[2].name:GetText(), "Coarse Thread")
    crafting.tab = "notes"
    crafting:Refresh()
    assert_true(crafting.tableMessage:IsShown())
    assert_match(crafting.tableMessage.text:GetText(), "later version")
    assert_false(crafting.pool.rows[1]:IsShown())
  end)

  it("explains unknown recipes and empty selection", function()
    Mock.AddItem(5000, { name = "Mystery Widget" })
    ns.GoalService.AddCraftGoal(5000, 1)
    MainFrame.ShowScreen("crafting")
    local crafting = screen("crafting")
    assert_eq(crafting.view.status, ns.Status.RECIPE_NOT_FOUND)
    assert_true(crafting.tableMessage:IsShown())
    assert_eq(crafting.hero.chips[1].label:GetText(), "No known recipe")
    ns.GoalService.Remove(ns.GoalService.GetSelected().id)
    Mock.RunTimers()
    assert_true(crafting.empty:IsShown())
    assert_false(crafting.hero:IsShown())
  end)

  it("populates the dashboard with goals, next steps and missing materials", function()
    ns.GoalService.AddCraftGoal(4238, 1)
    ns.GoalService.AddCraftGoal(2996, 1)
    MainFrame.ShowScreen("dashboard")
    Mock.RunTimers()
    local dash = screen("dashboard")
    assert_eq(dash.strip.name:GetText(), "Thandrel")
    assert_match(dash.strip.meta:GetText(), "Level 60 Human Warrior")
    assert_eq(dash.strip.cells[1].title:GetText(), "TAILORING")
    assert_match(dash.strip.cells[3].value:GetText(), "214g")
    assert_match(dash.strip.cells[4].value:GetText(), "2 active")
    assert_true(dash.goalsPanel.pool.rows[1]:IsShown())
    assert_true(dash.goalsPanel.pool.rows[2]:IsShown())
    assert_match(dash.goalsPanel.pool.rows[1].name:GetText(), "Linen Bag")
    assert_match(dash.goalsPanel.pool.rows[1].detail:GetText(), "Missing: 3 Bolt of Linen Cloth, 3 Coarse Thread")
    -- Linen Bag (priority 1) claims the 5 cloth for its 3 intermediate bolts,
    -- so the Bolt goal (priority 2) has nothing left: allocation across goals.
    assert_eq(dash.goalsPanel.pool.rows[2].percent:GetText(), "0%")
    local overview = dash.lastOverview
    assert_eq(#overview.missing, 2, "leaves only: cloth and thread, bolts are crafted")
    local clothRow, threadRow
    for _, row in ipairs(dash.missingPanel.pool.rows) do
      if row.itemID == 2589 then clothRow = row elseif row.itemID == 2320 then threadRow = row end
    end
    assert_eq(clothRow.count:GetText(), "x3", "1 for the bag's bolts + 2 for the bolt goal")
    assert_eq(clothRow.source:GetText(), "Needed by 2 goals")
    assert_eq(threadRow.source:GetText(), "Needed by Linen Bag")
    assert_eq(dash.recommended.pool.rows[1].title:GetText(), "Obtain 3 x Coarse Thread")
    assert_eq(dash.recommended.pool.rows[2].title:GetText(), "Obtain 2 x Linen Cloth")
    dash.goalsPanel.pool.rows[1]:Click()
    assert_eq(MainFrame.currentScreen, "crafting")
    assert_eq(ns.GoalService.GetSelected().target.itemID, 4238)
  end)

  it("manages goals from the My Goals screen", function()
    MainFrame.ShowScreen("goals")
    local goals = screen("goals")
    goals.newGoal.input:SetText("Linen Bag")
    goals.newGoal.stepper:SetValue(3)
    assert_true(goals:Submit())
    Mock.RunTimers()
    local goal = ns.GoalService.GetSelected()
    assert_eq(goal.target.itemID, 4238)
    assert_eq(goal.target.quantity, 3)
    assert_eq(goals.newGoal.stepper:GetValue(), 1, "stepper resets after adding")
    local row = goals.rowPool.rows[1]
    assert_true(row:IsShown())
    assert_match(row.name:GetText(), "Linen Bag")
    assert_match(row.name:GetText(), "x3")
    assert_eq(row.number:GetText(), "1")
    assert_true(row.tracked:GetChecked())
    assert_eq(goals.groupPool.rows[1].label:GetText(), "ACTIVE")
    assert_eq(goals.settings.goalID, goal.id)
    assert_eq(goals.settings.stepper:GetValue(), 3)

    goals.settings.status.segments.PAUSED:Click()
    Mock.RunTimers()
    assert_eq(ns.GoalService.GetSelected().status, "PAUSED")
    assert_eq(goals.groupPool.rows[1].label:GetText(), "PAUSED")
    assert_eq(goals.rowPool.rows[1]:GetAlpha(), 0.62)

    goals.settings.tracker:Click()
    Mock.RunTimers()
    assert_false(ns.GoalService.GetSelected().tracked)

    goals.settings.complete:Click()
    Mock.RunTimers()
    assert_eq(goal.status, "COMPLETED")
    assert_true(goals.empty:IsShown(), "completed goals leave the open tab")
    goals.tabs.tabs.completed:Click()
    Mock.RunTimers()
    assert_true(goals.rowPool.rows[1]:IsShown())
    assert_eq(goals.rowPool.rows[1].percent:GetText(), "100%")
    assert_eq(goals.settings.complete.label:GetText(), "Reopen goal")
    assert_match(frame.footerDone:GetText(), "1 completed")
  end)

  it("drives the compact tracker from tracked goals", function()
    local tracker = ns.UI.Tracker
    assert_false(tracker.IsShown())
    ns.GoalService.AddCraftGoal(4238, 1)
    ns.GoalService.AddCraftGoal(2996, 1)
    Mock.RunTimers()
    assert_true(tracker.IsShown())
    local tf = tracker.frame
    assert_eq(tf.pager:GetText(), "1/2")
    assert_match(tf.name:GetText(), "Linen Bag")
    assert_match(tf.sub:GetText(), "2 unresolved")
    assert_true(tf.pool.rows[1]:IsShown())
    assert_match(tf.pool.rows[1].counter:GetText(), "0")
    assert_match(tf.nextText:GetText(), "Obtain 3 x")
    tracker.Page(1)
    assert_eq(tf.pager:GetText(), "2/2")
    assert_match(tf.name:GetText(), "Bolt of Linen Cloth")
    assert_match(tf.nextText:GetText(), "Obtain 2 x Linen Cloth", "cloth is reserved by the higher-priority bag goal")
    ns.chardb.tracker.collapsed = true
    tracker.Refresh()
    assert_false(tf.body:IsShown())
    assert_match(tf.collapsedText:GetText(), "Bolt of Linen Cloth")
    ns.chardb.tracker.collapsed = false
    tracker.Toggle()
    assert_false(tracker.IsShown())
    assert_true(ns.chardb.tracker.hidden)
    Mock.RunSlash("tracker")
    assert_true(tracker.IsShown())
    ns.GoalService.SetTracked(ns.GoalService.List()[1].id, false)
    ns.GoalService.SetTracked(ns.GoalService.List()[2].id, false)
    Mock.RunTimers()
    assert_false(tracker.IsShown(), "hidden when nothing is tracked")
  end)

  it("accepts Shift-clicked item links into the focused input", function()
    _G.ChatEdit_InsertLink(Mock.ItemLink(2996))
    assert_eq(frame.search:GetText(), Mock.ItemLink(2996), "no focus: header search receives the link")
    frame.search:SetText("")
    MainFrame.ShowScreen("goals")
    local input = screen("goals").newGoal.input
    input:SetFocus()
    _G.ChatEdit_InsertLink(Mock.ItemLink(2589))
    assert_eq(input:GetText(), Mock.ItemLink(2589))
    assert_eq(frame.search:GetText(), "")
    input:ClearFocus()
    Mock.focus = Mock.newWidget("EditBox", "ChatFrame1EditBox")
    _G.ChatEdit_InsertLink(Mock.ItemLink(2589))
    assert_eq(frame.search:GetText(), "", "chat input keeps its link")
    Mock.focus = nil
    MainFrame.Hide()
    _G.ChatEdit_InsertLink(Mock.ItemLink(2589))
    assert_eq(frame.search:GetText(), "")
  end)

  it("links an item from any row on Shift-click", function()
    local captured
    _G.ChatEdit_InsertLink = function(link) captured = link return true end
    ns.GoalService.AddCraftGoal(2996, 10)
    Mock.RunTimers()
    MainFrame.ShowScreen("shopping")
    Mock.RunTimers()
    local shop = screen("shopping")
    local cloth
    for _, row in ipairs(shop.pool.rows) do if row:IsShown() and row.itemID == 2589 then cloth = row end end
    assert_not_nil(cloth, "20 cloth needed, 5 owned")
    cloth:Click()
    assert_nil(captured, "a plain click links nothing")
    Mock.shift = true
    cloth:Click()
    assert_match(captured, "|Hitem:2589:")
    assert_match(frame.alertText:GetText(), "^Linen Cloth linked%.")
    -- The crafting requirements and the dashboard behave the same; the goal row does not navigate.
    captured = nil
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    screen("crafting").pool.rows[1]:Click()
    assert_match(captured, "|Hitem:2589:")
    captured = nil
    MainFrame.ShowScreen("dashboard")
    Mock.RunTimers()
    screen("dashboard").goalsPanel.pool.rows[1]:Click()
    assert_match(captured, "|Hitem:2996:")
    assert_eq(MainFrame.currentScreen, "dashboard")
    Mock.shift = false
    screen("dashboard").goalsPanel.pool.rows[1]:Click()
    assert_eq(MainFrame.currentScreen, "crafting")
    -- Nothing takes the link: it is printed instead.
    _G.ChatEdit_InsertLink = function() return false end
    Mock.shift = true
    assert_true(MainFrame.LinkItem(2589))
    assert_output("|Hitem:2589:")
    Mock.shift = false
    assert_eq(#ns.Log.errors, 0, ns.Log.errors[1] and ns.Log.errors[1].message or "")
  end)

  it("updates when inventory and item data change", function()
    Mock.AddItem(2320, { name = "Coarse Thread", loaded = false })
    ns.GoalService.AddCraftGoal(4238, 1)
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    local crafting = screen("crafting")
    local rows = crafting.pool.rows
    assert_match(rows[2].name:GetText(), "Coarse Thread", "named by the catalogue while the client loads it")
    Mock.LoadItem(2320)
    Mock.RunTimers()
    assert_match(rows[2].name:GetText(), "Coarse Thread")
    Mock.SetBag(1, 16, { { 2996, 3 } })
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.RunTimers()
    local boltRow
    for _, row in ipairs(rows) do
      if row.itemID == 2996 then boltRow = row end
    end
    assert_eq(boltRow.have:GetText(), "3")
    assert_true(boltRow.check:IsShown())
  end)

  it("saves and restores window position per character", function()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", _G.UIParent, "TOPLEFT", 120, -80)
    frame:SetSize(1100, 750)
    MainFrame.SavePosition()
    assert_eq(ns.chardb.window.point, "TOPLEFT")
    assert_eq(ns.chardb.window.width, 1100)
    frame:SetSize(100, 100)
    MainFrame.SavePosition()
    assert_eq(ns.chardb.window.width, 1100, "sizes below the minimum are not saved")
    MainFrame.RestorePosition()
    assert_eq(frame:GetWidth(), 1100)
    ns.chardb.window.width = 5000
    MainFrame.RestorePosition()
    assert_eq(frame:GetWidth(), 1400, "clamped to the maximum")
    MainFrame.ResetWindow()
    assert_eq(ns.chardb.window.point, "CENTER")
    assert_eq(frame:GetWidth(), 1000)
    assert_eq(ns.chardb.tracker.x, -20)
  end)

  it("renders the dependency tree tab with routes, selection and filters", function()
    ns.GoalService.AddCraftGoal(4238, 1)
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    local crafting = screen("crafting")
    crafting.tabs.tabs.tree:Click()
    local tree = crafting.treeView
    assert_true(tree:IsShown())
    assert_false(crafting.table:IsShown())
    assert_false(crafting.sort:IsShown())
    local rows = tree.pool.rows
    assert_match(rows[1].name:GetText(), "Linen Bag")
    assert_match(rows[1].note:GetText(), "1 craft")
    assert_match(rows[2].name:GetText(), "Bolt of Linen Cloth")
    assert_match(rows[2].via:GetText(), "Craft %- Tailoring")
    assert_match(rows[2].note:GetText(), "3 crafts")
    assert_match(rows[3].name:GetText(), "Linen Cloth", "the bolt's own reagent sits under it")
    assert_match(rows[3].have:GetText(), "5")
    assert_match(rows[3].have:GetText(), "/6")
    assert_eq(rows[3].badge.label:GetText(), "PARTIAL")
    assert_true(rows[3].stem:IsShown())
    assert_match(rows[4].name:GetText(), "Coarse Thread")
    assert_eq(rows[4].badge.label:GetText(), "MISSING")
    assert_false(rows[5] and rows[5]:IsShown() or false)
    assert_match(tree.resolvedText:GetText(), "0 of 3 dependencies resolved")

    -- Default selection is the first unresolved direct reagent.
    assert_eq(tree.selectedKey, "4238>2996")
    assert_match(tree.side.name:GetText(), "Bolt of Linen Cloth")
    assert_match(tree.side.count:GetText(), "/ 3")
    assert_match(tree.side.cards[1].title:GetText(), "Craft with Tailoring")
    assert_true(tree.side.cards[1].best:IsShown())
    assert_match(tree.side.cards[1].cost:GetText(), "current")
    assert_match(tree.side.cards[2].title:GetText(), "Auction House")
    -- Option text wraps inside the card and the card grows to fit it.
    for i = 1, 2 do
      local card = tree.side.cards[i]
      assert_true(card.detail.wordWrap, "detail wraps")
      assert_true(card.title.wordWrap, "title wraps")
      assert_true(card.detail:GetWidth() > 0)
      assert_true(card:GetHeight() >= 5 + card.title:GetStringHeight() + 2 + card.detail:GetStringHeight(), "card fits its text")
    end
    local card = tree.side.cards[1]
    local oneLine = card:GetHeight()
    card.detail:SetText("You can learn it - 1 Large Glimmering Shard, 2 Strange Dust, 4 Lesser Astral Essence per craft")
    card:Fit()
    assert_true(card.detail:GetStringHeight() > 12, "a long reagent list takes more than one line")
    assert_true(card:GetHeight() > oneLine, "and the card grows to show all of it")
    assert_eq(tree.side.use.label:GetText(), "Use buying route")
    assert_false(tree.side.reset:IsShown())

    -- Switch the bolt to the buying route: the branch collapses to a leaf.
    tree.side.use:Click()
    Mock.RunTimers()
    assert_eq(ns.GoalService.GetSelected().routes[2996], "buy")
    assert_match(rows[2].via:GetText(), "AH")
    assert_match(rows[3].name:GetText(), "Coarse Thread")
    assert_false(rows[4]:IsShown())
    assert_true(tree.side.reset:IsShown())
    assert_eq(tree.side.use.label:GetText(), "Use crafting route")
    assert_match(frame.alertText:GetText(), "buying route")
    tree.side.reset:Click()
    Mock.RunTimers()
    assert_nil(ns.GoalService.GetSelected().routes)
    assert_true(rows[4]:IsShown())

    -- Collapse, expand all, unresolved filter, selecting the root.
    rows[2].chevron:Click()
    assert_true(tree.collapsed["4238>2996"])
    assert_false(rows[4]:IsShown())
    assert_match(rows[3].name:GetText(), "Coarse Thread")
    tree.expand:Click()
    assert_true(rows[4]:IsShown())
    Mock.SetBag(1, 16, { { 2320, 3 } })
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.RunTimers()
    assert_match(tree.resolvedText:GetText(), "1 of 3")
    assert_eq(rows[4].badge.label:GetText(), "HAVE")
    assert_eq(rows[4].via:GetText(), "In bags")
    tree.filterSegment.segments.unresolved:Click()
    assert_false(rows[4]:IsShown(), "thread is on hand and filtered out")
    rows[1]:Click()
    assert_eq(tree.selectedKey, "4238")
    assert_match(tree.side.cards[1].title:GetText(), "3 x Bolt of Linen Cloth")
    assert_false(tree.side.use:IsShown())

    -- The requirements tab still works and the tree hides.
    crafting.tabs.tabs.requirements:Click()
    assert_false(tree:IsShown())
    assert_true(crafting.table:IsShown())
  end)

  it("shows character cards, the coverage banner and the account-wide scope", function()
    ns.db.characters["Miravelle-Stormhold"] = {
      key = "Miravelle-Stormhold", name = "Miravelle", realm = "Stormhold", level = 52, class = "Shaman", classFile = "SHAMAN", race = "Orc",
      gold = 50000, lastSeen = Mock.now - 7200, bags = { items = { [2589] = 10 }, scannedAt = Mock.now - 7200 },
      professions = { { name = "Tailoring", skillLevel = 120, maxSkillLevel = 150, slot = 1 }, { name = "Skinning", skillLevel = 90, maxSkillLevel = 150, slot = 2 }, { name = "Cooking", skillLevel = 30, maxSkillLevel = 75, slot = 5 } }, knownRecipes = { [2963] = true },
      goals = { { title = "Craft 1x Something" } },
    }
    ns.GoalService.AddCraftGoal(4238, 1)
    MainFrame.ShowScreen("characters")
    Mock.RunTimers()
    local chars = screen("characters")
    assert_true(chars:IsShown())
    assert_true(chars.banner:IsShown())
    assert_match(chars.bannerTitle:GetText(), "Miravelle")
    assert_match(chars.bannerTitle:GetText(), "has 1 of", "5 of 6 cloth are in our bags; Miravelle covers the last one")
    assert_match(chars.bannerDetail:GetText(), "1 Linen Cloth")
    local cards = chars.pool.rows
    assert_eq(cards[1].name:GetText(), "Thandrel")
    assert_eq(cards[1].badge.label:GetText(), "LIVE")
    assert_false(cards[1].forget:IsShown())
    assert_eq(cards[2].name:GetText(), "Miravelle")
    assert_eq(cards[2].badge.label:GetText(), "SNAPSHOT")
    assert_match(cards[2].meta:GetText(), "Level 52 Orc Shaman")
    assert_eq(cards[2].professions[1].name:GetText(), "Tailoring")
    assert_eq(cards[2].professions[1].value:GetText(), "120 / 150")
    assert_eq(cards[2].professions[2].name:GetText(), "Skinning")
    assert_eq(cards[2].professions[3].name:GetText(), "Cooking")
    assert_true(cards[2].professions[3]:IsShown())
    assert_false(cards[2].professions[4]:IsShown())
    assert_eq(chars.profRows, 3, "every card gets the tallest profession block")
    assert_true(cards[2].materials[1]:IsShown())
    assert_eq(cards[2].materials[1].count:GetText(), "10")
    assert_false(cards[2].materials[2]:IsShown())
    assert_match(cards[2].goals[1]:GetText(), "Something")
    assert_match(cards[2].crafts[1]:GetText(), "Bolt of Linen Cloth")
    assert_true(cards[2].forget:IsShown())
    assert_eq(chars.scope.selected, "character")

    chars.scope.segments.account:Click()
    Mock.RunTimers()
    assert_true(ns.db.settings.includeAlts)
    assert_match(chars.bannerDetail:GetText(), "counted as owned")
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    local crafting = screen("crafting")
    assert_true(crafting.alts:GetChecked())
    assert_eq(#crafting.view.tree.summary.missingLeaves, 1)
    assert_eq(crafting.view.tree.summary.missingLeaves[1].itemID, 2320, "only thread is missing once the alt's cloth counts")
    local clothRow
    for _, row in ipairs(crafting.pool.rows) do
      if row.itemID == 2996 then clothRow = row end
    end
    assert_not_nil(clothRow)
    crafting.alts:Click()
    Mock.RunTimers()
    assert_false(ns.db.settings.includeAlts)
    assert_eq(#crafting.view.tree.summary.missingLeaves, 2)

    MainFrame.ShowScreen("characters")
    Mock.RunTimers()
    chars.pool.rows[2].forget:Click()
    assert_nil(ns.db.characters["Miravelle-Stormhold"])
    assert_true(chars.empty:IsShown())
    assert_false(chars.banner:IsShown())
  end)

  it("builds the shopping list screen with chips, bought ticks, filters and chat output", function()
    ns.GoalService.AddCraftGoal(4238, 1)      -- bag: 3 bolts (craft, 6 cloth; 5 in bags) + 3 thread
    ns.GoalService.AddCraftGoal(2996, 1)      -- bolt: 2 cloth (none left)
    ns.GoalService.SetStatus(ns.GoalService.List()[2].id, "PAUSED")
    MainFrame.ShowScreen("shopping")
    Mock.RunTimers()
    local shop = screen("shopping")
    assert_true(shop:IsShown())
    assert_true(frame.navButtons.shopping ~= nil)
    assert_true(shop.chips[1]:IsShown())
    assert_match(shop.chips[1].label:GetText(), "Linen Bag")
    assert_true(shop.chips[1]:GetChecked())
    assert_false(shop.chips[2]:GetChecked(), "paused goals are off by default")
    local rows = shop.pool.rows
    assert_true(rows[1]:IsShown())
    assert_match(rows[1].name:GetText(), "Coarse Thread")
    assert_eq(rows[1].missing:GetText(), "3")
    assert_match(rows[2].name:GetText(), "Bolt of Linen Cloth", "the intermediate to craft is listed too")
    assert_eq(rows[2].total:GetText(), "3")
    assert_match(rows[2].cost:GetText(), "via craft")
    assert_eq(rows[2].sourceFrame.tags[1].label:GetText(), "Craft - Tailoring")
    assert_match(rows[3].name:GetText(), "Linen Cloth")
    assert_eq(rows[3].total:GetText(), "6")
    assert_eq(rows[3].owned:GetText(), "5")
    assert_eq(rows[3].missing:GetText(), "1")
    assert_false(rows[4] and rows[4]:IsShown() or false)
    assert_match(shop.cells[5].value:GetText(), "5 ")
    assert_match(shop.tabs.tabs.all.label:GetText(), "All")
    assert_match(shop.tabs.tabs.buy.label:GetText(), "2")
    assert_match(shop.tabs.tabs.craft.label:GetText(), "1")

    -- Include the paused goal: it needs 2 more cloth, none free.
    shop.chips[2]:Click()
    Mock.RunTimers()
    assert_true(ns.chardb.shopping.included[ns.GoalService.List()[2].id])
    local cloth
    for _, row in ipairs(rows) do if row:IsShown() and row.itemID == 2589 then cloth = row end end
    assert_eq(cloth.total:GetText(), "8")
    assert_eq(cloth.missing:GetText(), "3")
    assert_match(cloth.note:GetText(), "2 goals")

    -- Tick thread as bought: it sinks to the bottom and dims.
    rows[1].bought:Click()
    Mock.RunTimers()
    assert_true(ns.chardb.shopping.bought[2320])
    assert_match(rows[3].name:GetText(), "bought")
    assert_eq(rows[3]:GetAlpha(), 0.5)
    shop.clear:Click()
    Mock.RunTimers()
    assert_nil(ns.chardb.shopping.bought[2320])
    assert_match(rows[1].name:GetText(), "Coarse Thread")

    -- Send to chat prints to the player's own chat frame.
    Mock.output = {}
    shop.send:Click()
    local out = table.concat(Mock.output, " | ")
    assert_match(out, "Shopping list %(3 items")
    assert_match(out, "3 x |c%x+|Hitem:2320[^%]]*%[Coarse Thread%]", "item links are used when the item is loaded")
    assert_match(out, "%[Linen Cloth%]|h|r %- AH")
    assert_match(out, "%[Bolt of Linen Cloth%]|h|r %- Craft")

    -- Links into the screen.
    MainFrame.ShowScreen("dashboard")
    screen("dashboard").missingPanel.shoppingLink:Click()
    assert_eq(MainFrame.currentScreen, "shopping")
    ns.GoalService.Select(ns.GoalService.List()[2].id)
    MainFrame.ShowScreen("crafting")
    screen("crafting").shoppingButton:Click()
    assert_eq(MainFrame.currentScreen, "shopping")
  end)

  it("shows recorded vendor prices in the shopping list and the requirements table", function()
    Mock.OpenMerchant("Tharynn Bouden", { { 2320, 50, 5 } })   -- 5 thread for 50c -> 10c each
    Mock.RunTimers()
    Mock.CloseMerchant()
    assert_eq(ns.db.vendors[2320]["Tharynn Bouden"].price, 10)
    ns.GoalService.AddCraftGoal(4238, 1)
    MainFrame.ShowScreen("shopping")
    Mock.RunTimers()
    local shop = screen("shopping")
    local thread
    for _, row in ipairs(shop.pool.rows) do if row:IsShown() and row.itemID == 2320 then thread = row end end
    assert_not_nil(thread)
    assert_match(thread.cost:GetText(), "30c")
    assert_eq(thread.sourceFrame.tags[1].label:GetText(), "Vendor: Tharynn Bouden")
    assert_match(shop.cells[1].value:GetText(), "30c")
    assert_match(shop.cells[1].sub:GetText(), "1 item unpriced")
    assert_match(shop.cells[2].value:GetText(), "Yes", "214g on hand covers 30c")
    assert_match(shop.cells[2].sub:GetText(), "^.*30c|r of your .*214g|r.*some unpriced")
    assert_match(thread.cost:GetText(), "^|cff[0-9a-fA-F]+%+ |r", "affordable rows are marked +")
    assert_match(shop.tabs.tabs.vendor.label:GetText(), "1")
    -- Broke: the alt's gold decides.
    Mock.character.money = 5
    ns.db.characters["Miravelle-Stormhold"] = { key = "Miravelle-Stormhold", name = "Miravelle", realm = "Stormhold", level = 52, class = "Shaman", gold = 100, lastSeen = Mock.now - 60, bags = { items = {}, scannedAt = Mock.now - 60 }, professions = {}, knownRecipes = {} }
    shop:Refresh()
    assert_match(shop.cells[2].value:GetText(), "With alts' gold")
    assert_match(shop.cells[2].sub:GetText(), "short .*25c|r here; alts hold .*1s|r")
    ns.db.characters["Miravelle-Stormhold"].gold = 10
    shop:Refresh()
    assert_match(shop.cells[2].value:GetText(), "No")
    assert_match(shop.cells[2].sub:GetText(), "short .*15c|r across the account")
    assert_match(thread.cost:GetText(), "^|cff[0-9a-fA-F]+! |r")
    Mock.character.money = 2143600
    ns.db.characters["Miravelle-Stormhold"] = nil
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    local crafting = screen("crafting")
    local req
    for _, row in ipairs(crafting.pool.rows) do if row:IsShown() and row.itemID == 2320 then req = row end end
    assert_match(req.price:GetText(), "10c")
    assert_match(req.subtotal:GetText(), "30c")
    assert_match(crafting.buyValue:GetText(), "30c|r.*affordable")
    local tagTexts = {}
    for _, tag in ipairs(req.sourceFrame.tags) do if tag:IsShown() then tagTexts[#tagTexts + 1] = tag.label:GetText() end end
    assert_deep_eq(tagTexts, { "Vendor: Tharynn Bouden" })
    assert_eq(crafting.view.tree.summary.missingLeaves[1].route, "vendor")
  end)

  it("adds obtain goals for uncraftable items and shows where they come from", function()
    Mock.AddItem(10411, { name = "Footpads of the Fang", quality = 3 })
    Mock.AddItem(10410, { name = "Leggings of the Fang", quality = 3 })
    Mock.InstallDungeonJournal({ ["Wailing Caverns"] = { bosses = {
      { name = "Kresh", npcID = 3653, loot = { { 10411, "Footpads of the Fang", "Feet, Leather", 3 } } },
      { name = "Lord Cobrahn", npcID = 3669, loot = { { 10410, "Leggings of the Fang", "Legs, Leather", 3 } } },
    } } })
    local ok, message, goal = ns.GoalService.AddFromInput("10411", 1)
    assert_true(ok)
    assert_eq(goal.type, "OBTAIN_ITEM", "no recipe is recorded for it, professions are scanned")
    assert_match(message, "Obtain 1x Footpads of the Fang")
    assert_eq(ns.GoalService.AddFromInput("2996", 1) and ns.GoalService.GetSelected().type, "CRAFT_ITEM", "craftable items stay crafting goals")
    ns.GoalService.Select(goal.id)
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    local crafting = screen("crafting")
    assert_eq(crafting.view.status, ns.Status.OK)
    assert_true(crafting.view.obtain)
    assert_eq(crafting.hero.chips[1].label:GetText(), "Obtain")
    assert_eq(crafting.hero.chips[2].label:GetText(), "Dropped by Kresh")
    assert_false(crafting.hero.chips[3]:IsShown())
    assert_match(crafting.hero.reagents:GetText(), "^0 of 1 in your bags %- Dropped by Kresh %- Wailing Caverns")
    assert_false(crafting.tableMessage:IsShown())
    local row = crafting.pool.rows[1]
    assert_match(row.name:GetText(), "Footpads of the Fang")
    assert_eq(row.missing:GetText(), "1")
    assert_eq(row.sourceFrame.tags[1].label:GetText(), "Dropped by Kresh")
    -- Tree tab: the root is the item itself, with its sources as option cards.
    crafting.tabs.tabs.tree:Click()
    Mock.RunTimers()
    local tree = crafting.treeView
    assert_eq(tree.pool.rows[1].via:GetText(), "Drop")
    assert_match(tree.pool.rows[1].have:GetText(), "0|r.*/1")
    assert_match(tree.side.sub:GetText(), "^Goal item %- Drop")
    assert_eq(tree.side.cards[1].title:GetText(), "Dropped by Kresh")
    assert_match(tree.side.cards[1].detail:GetText(), "Wailing Caverns %(DungeonJournal%)")
    assert_match(tree.side.cards[1].cost:GetText(), "current")
    assert_match(tree.side.cards[2].title:GetText(), "Auction House")
    assert_true(tree.side.use:IsShown(), "the AH is an alternative route for the item")
    crafting.tabs.tabs.requirements:Click()
    -- A crafting goal with no recipe falls through to the same plan.
    ns.GoalService.AddCraftGoal(10410, 1)
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    assert_true(crafting.view.obtain)
    assert_eq(crafting.view.goal.type, "CRAFT_ITEM")
    assert_eq(crafting.hero.chips[1].label:GetText(), "Obtain")
    assert_eq(crafting.hero.chips[2].label:GetText(), "Dropped by Lord Cobrahn")
    assert_eq(crafting.hero.chips[3].label:GetText(), "No known recipe")
    assert_match(crafting.hero.reagents:GetText(), "Dropped by Lord Cobrahn")
    -- /fp obtain switches it to an obtain goal.
    Mock.RunSlash("obtain 10410 2")
    assert_output("Updated goal: Obtain 2x Leggings of the Fang")
    assert_eq(crafting.view.goal.type, "OBTAIN_ITEM")
    -- Dashboard and shopping list carry the item and its source.
    MainFrame.ShowScreen("dashboard")
    Mock.RunTimers()
    local dash = screen("dashboard")
    local found
    for _, r in ipairs(dash.goalsPanel.pool.rows) do
      if r:IsShown() and r.name:GetText():find("Footpads") then found = r end
    end
    assert_not_nil(found)
    assert_match(found.detail:GetText(), "Missing: 1 Footpads of the Fang")
    assert_eq(found.meta:GetText(), "Dropped by Kresh")
    assert_eq(found.badge.label:GetText(), "ITEM")
    MainFrame.ShowScreen("shopping")
    Mock.RunTimers()
    local shop = screen("shopping")
    local line
    for _, r in ipairs(shop.list.rows) do if r.itemID == 10411 then line = r end end
    assert_not_nil(line)
    assert_eq(line.category, "gather")
    assert_eq(line.sources[1], "Soulbound", "the client's item index knows it binds on pickup")
    assert_eq(line.sources[2], "Dropped by Kresh")
    assert_eq(line.missing, 1)
  end)


  it("compares buy, craft and hybrid in CraftWise and applies the plan", function()
    -- Bag: 3 bolts (craft: 2 cloth each) + 3 thread. 5 cloth in bags.
    Mock.InstallAuctionator({
      [2589] = { price = 10, age = 0, mean = 11, available = 40 },  -- cloth
      [2320] = { price = 20, age = 0 },                              -- thread
      [2996] = { price = 15, age = 0 },                              -- bolt: cheaper than 2 cloth
      [4238] = { price = 1000, age = 0, mean = 1100, available = 3 },  -- bag
    }, { lastScan = Mock.now - 2 * 3600 })
    ns.GoalService.AddCraftGoal(4238, 1)
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    local crafting = screen("crafting")
    assert_match(frame.pricesText:GetText(), "^AH prices: cached scan %- 2h ago")
    -- Requirements footer: the hybrid total and the open button.
    assert_match(crafting.routeText:GetText(), "CraftWise route:")
    crafting.craftwiseButton:Click()
    assert_eq(crafting.tab, "craftwise")
    local cw = crafting.craftwiseView
    assert_true(cw:IsShown())
    assert_false(crafting.table:IsShown())
    assert_false(cw.empty:IsShown())
    local result = cw.result
    -- 5 owned cloth cover bolt 1 and 2 (4 cloth); bolt 3 needs 2 cloth = 20c vs 15c bought.
    assert_eq(result.buy.cost, 1000)
    assert_eq(result.craft.cost, 10 + 60, "1 cloth + 3 thread")
    assert_eq(result.hybrid.cost, 70, "crafting the bolts (10c of cloth) beats buying them (45c)")
    assert_eq(result.recommended, "hybrid")
    assert_true(cw.cards[3].badge:IsShown())
    assert_false(cw.cards[1].badge:IsShown())
    assert_match(cw.cards[1].total:GetText(), "10s|r")
    assert_match(cw.cards[1].lines[3]:GetText(), "3 listed")
    assert_match(cw.cards[2].lines[3]:GetText(), "Tailoring")
    assert_match(cw.cards[3].footer:GetText(), "^Saves ")
    assert_match(cw.cards[3].footer:GetText(), "30c|r %(93%%%)$")
    assert_match(cw.scanText:GetText(), "AH scan 2h ago")
    assert_eq(cw.badge.label:GetText(), "CACHED")
    local rows = cw.pool.rows
    assert_true(rows[1]:IsShown())
    assert_match(rows[1].name:GetText(), "Bolt of Linen Cloth")
    assert_match(rows[1].buy:GetText(), "45c")
    assert_match(rows[1].craft:GetText(), "10c")
    assert_match(rows[1].choice:GetText(), "Craft")
    assert_match(rows[2].name:GetText(), "Linen Cloth")
    assert_match(rows[3].name:GetText(), "Coarse Thread")
    assert_match(rows[3].choice:GetText(), "Buy")
    assert_match(rows[3].priceText:GetText(), "2h ago")
    assert_true(cw.usePlan:IsShown())
    -- Make bolts worth buying, then apply the plan: the tree follows it.
    _G.Auctionator.API.v1.GetAuctionPriceByItemID = function(_, id) return ({ [2589] = 10, [2320] = 20, [2996] = 3, [4238] = 1000 })[id] end
    crafting:Refresh()
    result = cw.result
    assert_eq(result.plan[2996], "buy")
    assert_eq(result.hybrid.cost, 9 + 60, "three bolts bought at 3c beat 10c of cloth")
    cw.usePlan:Click()
    Mock.RunTimers()
    local goal = ns.GoalService.GetSelected()
    assert_eq(goal.routes[2996], "buy")
    assert_true(crafting.view.fullTree ~= nil, "a full tree is kept for CraftWise once routes exist")
    assert_eq(#crafting.view.tree.root.children[1].children, 0, "the plan tree buys the bolts")
    assert_eq(cw.usePlan.label:GetText(), "Plan in use")
    -- Dashboard panel and the Goals route dropdown reflect it.
    MainFrame.ShowScreen("dashboard")
    Mock.RunTimers()
    local dash = screen("dashboard")
    assert_false(dash.craftwise.empty:IsShown())
    assert_match(dash.craftwise.total:GetText(), "69c")
    assert_match(dash.craftwise.sub:GetText(), "Hybrid plan %- saves")
    assert_match(dash.craftwise.rows[1].value:GetText(), "10s|r")
    assert_match(dash.craftwise.scan:GetText(), "Cached scan %- 2h ago")
    MainFrame.ShowScreen("goals")
    Mock.RunTimers()
    local goals = screen("goals")
    assert_match(goals.settings.route.label:GetText(), "^CraftWise hybrid %- .*69c")
    goals.settings:ApplyRouteMode("default")
    Mock.RunTimers()
    assert_nil(ns.GoalService.GetSelected().routes)
    assert_match(goals.settings.route.label:GetText(), "Default routes")
    goals.settings:ApplyRouteMode("buyall")
    Mock.RunTimers()
    assert_eq(ns.GoalService.GetSelected().routes[2996], "buy")
  end)

  it("shows CraftWise empty states without prices", function()
    ns.GoalService.AddCraftGoal(4238, 1)
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    local crafting = screen("crafting")
    assert_match(crafting.routeText:GetText(), "no price data")
    assert_match(frame.pricesText:GetText(), "Auctionator not installed")
    crafting.tabs.tabs.craftwise:Click()
    local cw = crafting.craftwiseView
    assert_true(cw.empty:IsShown())
    assert_match(cw.empty.text:GetText(), "Auctionator not installed")
    MainFrame.ShowScreen("dashboard")
    Mock.RunTimers()
    local dash = screen("dashboard")
    assert_true(dash.craftwise.empty:IsShown())
    assert_true(dash.craftwise.compare:IsShown())
    dash.craftwise.compare:Click()
    assert_eq(MainFrame.currentScreen, "crafting")
    assert_eq(crafting.tab, "craftwise")
  end)


  it("plans attunements on their own screen and completes them from quest flags", function()
    Mock.InstallAttune({
      attunes = { { ID = "40", NAME = "Onyxia's Lair", GROUP = "RAIDS", FACTION = "Alliance", ICON = "ony", GROUPSIZE = 40 },
                  { ID = "163", NAME = "The Hall of Thanes", GROUP = "DUNGEONS", FACTION = "Alliance", LEVELS = "13-15", ICON = "hall", GROUPSIZE = 5 } },
      steps = {
        { ID_ATTUNE = "40", ID = "10", TYPE = "Level", STEP = "Reach level 48", LOCATION = "", ID_WOWHEAD = "48", ICON = "l", FOLLOWS = "0", STAGE = "1" },
        { ID_ATTUNE = "40", ID = "20", TYPE = "Quest", STEP = "", LOCATION = "Burning Steppes", ID_WOWHEAD = "4182", ICON = "q", FOLLOWS = "10", STAGE = "2" },
        { ID_ATTUNE = "40", ID = "30", TYPE = "Quest", STEP = "", LOCATION = "Stormwind City", ID_WOWHEAD = "4183", ICON = "q", FOLLOWS = "20", STAGE = "3" },
        { ID_ATTUNE = "40", ID = "40", TYPE = "End", STEP = "Attuned", LOCATION = "", ID_WOWHEAD = "0", ICON = "e", FOLLOWS = "30", STAGE = "4" },
        { ID_ATTUNE = "163", ID = "10", TYPE = "Level", STEP = "Reach level 10", LOCATION = "", ID_WOWHEAD = "10", ICON = "l", FOLLOWS = "0", STAGE = "1" },
        { ID_ATTUNE = "163", ID = "20", TYPE = "End", STEP = "Attuned", LOCATION = "", ID_WOWHEAD = "0", ICON = "e", FOLLOWS = "10", STAGE = "2" },
      },
      quests = { [4182] = { 48, 2 }, [4183] = { 48, 1 } },
    }, { lang = { Q1_4182 = "Dragonkin Menace", Q1_4183 = "The True Masters" } })
    Mock.character.level = 60
    -- My Goals: the Attunement segment adds by name.
    MainFrame.ShowScreen("goals")
    Mock.RunTimers()
    local goals = screen("goals")
    goals.newGoal.segment:Select("attunement")
    goals.newGoal.input:SetText("onyxia")
    assert_true(goals:Submit())
    local goal = ns.GoalService.GetSelected()
    assert_eq(goal.type, "COMPLETE_ATTUNEMENT")
    assert_eq(goal.target.attuneID, "40")
    assert_eq(ns.GoalService.Title(goal), "Complete attunement: Onyxia's Lair")
    goals.newGoal.segment:Select("item")
    -- Opening it lands on the Attunements screen.
    MainFrame.OpenGoal(goal.id)
    Mock.RunTimers()
    assert_eq(MainFrame.currentScreen, "attunements")
    local att = screen("attunements")
    assert_eq(att.attuneID, "40")
    assert_eq(att.picker.label:GetText(), "Onyxia's Lair")
    assert_match(att.header.name:GetText(), "Onyxia's Lair")
    assert_match(att.header.meta:GetText(), "^Raid attunement %- Alliance %- 40 players")
    assert_eq(att.header.percent:GetText(), "33%")
    assert_eq(att.header.chips[1].label:GetText(), "1 of 3 steps")
    assert_eq(att.header.chips[2].label:GetText(), "Next: Dragonkin Menace")
    assert_eq(att.addGoal.label:GetText(), "Goal added")
    local rows = att.chain.pool.rows
    assert_eq(rows[1].badge.label:GetText(), "DONE")
    assert_eq(rows[2].badge.label:GetText(), "CURRENT")
    assert_match(rows[2].name:GetText(), "Dragonkin Menace")
    assert_match(rows[2].detail:GetText(), "^Quest %- Burning Steppes")
    assert_eq(rows[3].badge.label:GetText(), "LOCKED")
    assert_eq(rows[4].number:GetText(), "")
    assert_eq(att.side.title:GetText(), "Dragonkin Menace")
    assert_match(att.side.chips[1].label:GetText(), "Group quest %- 2 players")
    assert_eq(att.chain.count:GetText(), "1 / 3")
    -- Dashboard row and next step, tracker, crafting hand-off.
    MainFrame.ShowScreen("dashboard")
    Mock.RunTimers()
    local dash = screen("dashboard")
    local row
    for _, r in ipairs(dash.goalsPanel.pool.rows) do if r:IsShown() and r.goalID == goal.id then row = r end end
    assert_match(row.detail:GetText(), "^Next: Quest: Dragonkin Menace")
    assert_eq(row.meta:GetText(), "1 of 3 steps")
    assert_eq(row.percent:GetText(), "33%")
    assert_eq(row.badge.label:GetText(), "ATTUNEMENT")
    assert_eq(dash.recommended.pool.rows[1].title:GetText(), "Quest: Dragonkin Menace")
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    assert_true(screen("crafting").empty:IsShown())
    assert_match(screen("crafting").empty.text:GetText(), "Attunements screen")
    -- Picker switches attunements; the other one has no goal yet.
    att:Select("163")
    assert_eq(att.picker.label:GetText(), "The Hall of Thanes")
    assert_eq(att.addGoal.label:GetText(), "+ Add goal")
    assert_eq(att.header.percent:GetText(), "100%", "level 60 already covers it")
    att.addGoal:Click()
    Mock.RunTimers()
    assert_not_nil(ns.GoalService.FindAttunementGoal("163"))
    -- Finish the Onyxia quests: the goal completes with a toast.
    Mock.CompleteQuest(4182)
    Mock.CompleteQuest(4183)
    Mock.RunTimers()
    assert_eq(goal.status, "COMPLETED")
    assert_eq(ns.UI.Toast.lastShown.title, "Attunement complete")
    assert_match(ns.UI.Toast.lastShown.detail, "^Attuned: ")
    assert_eq(ns.UI.Toast.shownCount, 2, "both attunement goals completed: Onyxia now, the Hall of Thanes was already done")
    assert_output("Goal complete: Attuned: Onyxia's Lair")
    Mock.RunSlash("attunements")
    assert_output("Onyxia's Lair %- 100%% %(3 of 3 steps%) %[goal%]")
    Mock.RunSlash("attune hall")
    assert_output("Already a goal")
    Mock.RunSlash("attune nothing")
    assert_output("No attunement called")
    assert_eq(#ns.Log.errors, 0, type(ns.Log.errors[1]) == "table" and tostring(ns.Log.errors[1].message or ns.Log.errors[1].text or ns.Log.errors[1][1]) or tostring(ns.Log.errors[1]))
  end)

  it("explains missing Attune on the Attunements screen", function()
    MainFrame.ShowScreen("attunements")
    Mock.RunTimers()
    local att = screen("attunements")
    assert_true(att.empty:IsShown())
    assert_match(att.empty.title:GetText(), "Attune is not installed")
    local ok, message = ns.GoalService.AddAttunementFromInput("onyxia")
    assert_false(ok)
    assert_match(message, "Attune addon")
    Mock.RunSlash("attunements")
    assert_output("Attune is not installed")
  end)

end)
