local H = require("harness")
local Mock = H.Mock

-- Bolt of Woolen Cloth (spell 2964) is a trainer recipe: the catalogue carries
-- no requirement for it (minSkill 1) until a trainer window has been seen.
local WOOLEN = 2964

local function services()
  return {
    { name = "Tailoring", type = "header" },
    { spellID = WOOLEN, name = "Bolt of Woolen Cloth", type = "unavailable", skill = "Tailoring", rank = 75, cost = 500 },
    { spellID = 2963, name = "Bolt of Linen Cloth", type = "used", skill = "Tailoring", rank = 1, cost = 0 },
    { spellID = 3755, name = "Linen Bag", type = "available", skill = "Tailoring", rank = 45, cost = 300 },
    { spellID = 999999, name = "Mystery Craft", type = "available", skill = "Tailoring", rank = 10, cost = 1 },
    { spellID = 12345, name = "Apprentice Riding", type = "available" },
  }
end

describe("TrainerProvider", function()
  local ns, TP
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    TP = ns.TrainerProvider
  end)

  it("is absent until a trainer window exists, then records every recipe on offer with its requirement", function()
    assert_false(TP.IsAvailable())
    assert_match(TP.Status(), "API unavailable")
    assert_nil(TP.Requirement(WOOLEN))
    Mock.zone = "Stormwind City"
    Mock.subzone = "Mage Quarter"
    Mock.OpenTrainer("Georgio Bolero", services())
    Mock.RunTimers()
    assert_true(TP.IsAvailable())
    local trainer = Mock.trainer
    assert_eq(trainer.filters.unavailable, 1, "too-advanced recipes made visible")
    assert_eq(trainer.filters.used, 1, "known recipes made visible")
    local req = TP.Requirement(WOOLEN)
    assert_eq(req.rank, 75)
    assert_eq(req.skill, "Tailoring")
    assert_eq(req.cost, 500)
    assert_eq(req.trainer, "Georgio Bolero")
    assert_eq(req.zone, "Stormwind City")
    assert_eq(req.subzone, "Mage Quarter")
    assert_eq(TP.Requirement(2963).rank, 1, "already-known recipes are recorded too")
    assert_eq(TP.Requirement(999999).rank, 10, "a spell the catalogue lacks still counts on a profession trainer")
    assert_nil(TP.Requirement(12345), "no requirement, nothing to record")
    local recipes, trainers = TP.Count()
    assert_eq(recipes, 4)
    assert_eq(trainers, 1)
    assert_match(TP.Status(), "^Trainer requirements: 4 recipes from 1 trainer%.$")
    assert_match(TP.Describe(WOOLEN), "^Georgio Bolero %(Stormwind City %- Mage Quarter%), needs Tailoring 75, ")
    assert_eq(ns.db.trainerNPCs["Georgio Bolero"].recipes, 4)
    assert_eq(ns.db.trainers[WOOLEN].rank, 75, "persisted account-wide")
    Mock.CloseTrainer()
    assert_eq(trainer.filters.unavailable, 0, "filters put back on close")
    assert_eq(trainer.filters.used, 0)
    assert_eq(trainer.filters.available, 1)
    assert_false(TP.open)
  end)

  it("feeds the catalogue: required skill, crafter checks, messages and chat", function()
    local Recipes = ns.Data.Recipes
    local before = Recipes.Get(WOOLEN)
    assert_eq(before.skill.min, 1)
    assert_nil(before.trainer)
    assert_match(Recipes.Lines(before.outputItemID)[1], "trainer %(requirement not recorded yet%)")
    Mock.zone = "Stormwind City"
    Mock.OpenTrainer("Georgio Bolero", services())
    Mock.RunTimers()
    Mock.CloseTrainer()
    local recipe = Recipes.Get(WOOLEN)
    assert_eq(recipe.skill.min, 75)
    assert_eq(recipe.skill.source, "trainer")
    assert_eq(recipe.trainer.name, "Georgio Bolero")
    assert_eq(recipe.trainer.cost, 500)
    assert_match(Recipes.Lines(recipe.outputItemID)[1], "^Tailoring 75 %(yellow 70, grey 85%): Bolt of Woolen Cloth x1 %- trainer Georgio Bolero %(Stormwind City%)")
    -- A 50-skill tailor cannot craft it; at 100 the craft is the route and the message names the trainer.
    local woolen = recipe.outputItemID
    Mock.AddItem(woolen, { name = "Bolt of Woolen Cloth" })
    Mock.AddItem(2592, { name = "Wool Cloth" })
    Mock.professionSlots = { 1 }
    Mock.professionInfo = { [1] = { name = "Tailoring", skillLevel = 50, maxSkillLevel = 150, skillLine = 197 } }
    local goal = ns.GoalService.AddCraftGoal(woolen, 1)
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.tree.root.craftOption.reason, "needs Tailoring 75; Thandrel has 50")
    Mock.professionInfo[1].skillLevel = 100
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.tree.root.route, "craft")
    assert_match(view.message, "craft 1 more with Tailoring %(you at 100; trainer Georgio Bolero, Stormwind City, needs 75%)")
    ns.Commands.Dispatch("trainers")
    assert_output("Georgio Bolero %(Stormwind City%): 4 recipes")
    ns.Commands.Dispatch("catalogue")
    assert_output("Trainer requirements: 4 recipes from 1 trainer")
  end)

  it("adds a 'train it' step to the tree, the shopping list and CraftWise for an unlearned trainer recipe", function()
    local Recipes = ns.Data.Recipes
    local woolen = Recipes.Get(WOOLEN).outputItemID
    Mock.AddItem(woolen, { name = "Bolt of Woolen Cloth" })
    Mock.AddItem(2592, { name = "Wool Cloth" })
    Mock.professionSlots = { 1 }
    Mock.professionInfo = { [1] = { name = "Tailoring", skillLevel = 100, maxSkillLevel = 150, skillLine = 197 } }
    local goal = ns.GoalService.AddCraftGoal(woolen, 1)
    -- Before any trainer visit the step is there, without a trainer.
    local view = ns.Planner.Evaluate(goal)
    local root = view.tree.root
    assert_eq(root.route, "craft")
    local step = root.children[1]
    assert_not_nil(step.step)
    assert_eq(step.step.kind, "train")
    assert_eq(step.step.name, "Bolt of Woolen Cloth")
    assert_eq(step.step.professionName, "Tailoring")
    assert_nil(step.step.trainer)
    assert_eq(step.route, "train")
    assert_eq(step.missing, 1)
    assert_false(step.claims)
    assert_eq(root.children[2].itemID, 2592, "then the reagents")
    assert_match(ns.DependencyResolver.Describe(view.tree)[2], "train: Bolt of Woolen Cloth %(Tailoring trainer%)")
    local list = ns.ShoppingList.Build({ { goal = goal, view = view } })
    local stepRow
    for _, r in ipairs(list.rows) do if r.step then stepRow = r end end
    assert_eq(stepRow.category, "learn")
    assert_eq(stepRow.key, "train:" .. WOOLEN)
    assert_eq(stepRow.sources[1], "Train - Tailoring trainer (not yet recorded)")
    assert_nil(stepRow.cost)
    assert_eq(list.counts.learn, 1)
    -- After the visit: trainer, zone and cost everywhere.
    Mock.zone = "Stormwind City"
    Mock.OpenTrainer("Georgio Bolero", services())
    Mock.RunTimers()
    Mock.CloseTrainer()
    view = ns.Planner.Evaluate(goal)
    step = view.tree.root.children[1]
    assert_eq(step.step.trainer.name, "Georgio Bolero")
    assert_eq(step.step.rank, 75)
    assert_match(ns.DependencyResolver.Describe(view.tree)[2], "train: Bolt of Woolen Cloth at Georgio Bolero %(Stormwind City%)")
    assert_eq(view.tree.summary.nodes, 3, "the bolt itself, the step and the cloth: the step counts as a dependency")
    local stepLeaf
    for _, leaf in ipairs(view.tree.summary.missingLeaves) do if leaf.step then stepLeaf = leaf end end
    assert_eq(stepLeaf.name, "Bolt of Woolen Cloth")
    list = ns.ShoppingList.Build({ { goal = goal, view = view } }, { gold = { current = 10000, account = 10000 } })
    for _, r in ipairs(list.rows) do if r.step then stepRow = r end end
    assert_eq(stepRow.sources[1], "Train - Georgio Bolero (Stormwind City)")
    assert_eq(stepRow.cost, 500)
    assert_eq(stepRow.affordable, "now")
    assert_eq(list.cost.remaining, 500, "the training cost is part of what you pay")
    local lines = ns.ShoppingList.Lines(list, ns.ItemProvider.GetName, nil, function(c) return c .. "c" end)
    local trainLine
    for _, line in ipairs(lines) do if line:find("Train Bolt") then trainLine = line end end
    assert_eq(trainLine, "  Train Bolt of Woolen Cloth - Train - Georgio Bolero (Stormwind City) - 500c")
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(#overview.missing, 1, "steps are not missing materials")
    assert_eq(overview.missing[1].itemID, 2592)
    -- CraftWise: the training cost is part of crafting, never of buying.
    local compare = ns.CraftWise.Compare(view.tree, { priceOf = function(id) if id == 2592 then return { copper = 10, source = "vendor" } end end })
    assert_eq(compare.craft.cost, 530)
    assert_eq(compare.craft.unknown, 0)
    local trainEntry
    for _, entry in ipairs(compare.hybrid.buyList) do if entry.choice == "train" then trainEntry = entry end end
    assert_eq(trainEntry.name, "Bolt of Woolen Cloth")
    assert_eq(trainEntry.cost, 500)
    assert_eq(compare.unpriced, 0)
    -- Screens render the step without touching item APIs.
    ns.UI.MainFrame.Show()
    ns.UI.MainFrame.ShowScreen("shopping")
    Mock.RunTimers()
    local shopping = ns.UI.MainFrame.screens.shopping
    local found
    for _, row in ipairs(shopping.pool.rows) do
      if row:IsShown() and row.name:GetText():find("Train: Bolt of Woolen Cloth", 1, true) then found = row end
    end
    assert_not_nil(found, "the shopping screen lists the train step")
    assert_eq(found.key, "train:" .. WOOLEN)
    ns.UI.MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
  end)

  it("ignores class trainers, copes with missing functions and merges repeat visits", function()
    Mock.OpenTrainer("Warrior Trainer", { { spellID = 100, name = "Charge", type = "available", skill = "Warrior", rank = 1 } }, { tradeskill = false })
    Mock.RunTimers()
    Mock.CloseTrainer()
    assert_eq((TP.Count()), 0, "class trainers are skipped")
    Mock.OpenTrainer("Georgio Bolero", services(), { noSkillReq = true })
    Mock.RunTimers()
    Mock.CloseTrainer()
    assert_eq((TP.Count()), 0, "without the requirement function nothing useful is known")
    Mock.OpenTrainer("Georgio Bolero", services(), { noLink = true })
    Mock.RunTimers()
    Mock.CloseTrainer()
    assert_eq((TP.Count()), 3, "without spell links, names are matched against the catalogue (Mystery Craft is not in it)")
    assert_eq(TP.Requirement(WOOLEN).rank, 75)
    assert_nil(TP.Requirement(999999))
    ns.db.trainers, ns.db.trainerNPCs = {}, {}
    -- Two cities: the latest trainer wins the location, the rank is the same.
    Mock.zone = "Ironforge"
    Mock.OpenTrainer("Georgio Bolero", services())
    Mock.RunTimers()
    Mock.CloseTrainer()
    Mock.zone = "Darnassus"
    Mock.OpenTrainer("Me'lynn", { { spellID = WOOLEN, name = "Bolt of Woolen Cloth", type = "available", skill = "Tailoring", rank = 75, cost = 500 } })
    Mock.RunTimers()
    Mock.CloseTrainer()
    assert_eq(TP.Requirement(WOOLEN).trainer, "Me'lynn")
    assert_eq(TP.Requirement(WOOLEN).zone, "Darnassus")
    assert_eq(TP.Requirement(3755).trainer, "Georgio Bolero")
    local recipes, trainers = TP.Count()
    assert_eq(recipes, 4)
    assert_eq(trainers, 2)
    -- When the client cannot say what kind of trainer it is, only profession skills count.
    Mock.OpenTrainer("Odd NPC", {
      { spellID = 200, name = "Journeyman Riding", type = "available", skill = "Riding", rank = 75 },
      { spellID = 300, name = "Heavy Linen Bandage", type = "available", skill = "First Aid", rank = 40 },
    }, { tradeskill = "unknown" })
    Mock.RunTimers()
    Mock.CloseTrainer()
    assert_nil(TP.Requirement(200))
    assert_eq(TP.Requirement(300).rank, 40)
  end)
end)
