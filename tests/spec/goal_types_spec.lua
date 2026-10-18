local H = require("harness")
local Mock = H.Mock

-- Tailoring (skill line 197) recipes from the real catalogue, by spell id.
local WOOLEN_BOLT, WOOLEN_BOOTS, HEAVY_PANTS, SILK_BOLT = 2964, 2401, 3850, 3839
local ARCANA_PATTERN = 5773                     -- Pattern: Robes of Arcana (125 / 145 / 175), named for the screens
local LINEN_BOLT = 2963
local HAMMER, HAMMER_PLANS = 21161, 18592        -- Sulfuron Hammer (Blacksmithing 300, plans)
local SULFURAS_COMBINE = 21160
local WOOL, WOOLEN_CLOTH, THREAD, PANTS_ITEM = 2592, 2997, 2321, 4316

local function tailor(ns, skill, max, scanned)
  Mock.professionSlots = { 1 }
  Mock.professionInfo = { [1] = { name = "Tailoring", skillLevel = skill, maxSkillLevel = max or 150, skillLine = 197, icon = 136249 } }
  if scanned ~= false then

    ns.chardb.professions[197] = { name = "Tailoring", skillLevel = skill, maxSkillLevel = max or 150, scannedAt = Mock.now, recipeCount = 4, learnedCount = 4 }
  end
end

local function names()
  Mock.AddItem(WOOL, { name = "Wool Cloth" })
  Mock.AddItem(WOOLEN_CLOTH, { name = "Bolt of Woolen Cloth" })
  Mock.AddItem(THREAD, { name = "Coarse Thread" })
  Mock.AddItem(PANTS_ITEM, { name = "Heavy Woolen Pants", quality = 2 })
  Mock.AddItem(4306, { name = "Silk Cloth" })
  Mock.AddItem(4305, { name = "Bolt of Silk Cloth" })
  Mock.AddItem(ARCANA_PATTERN, { name = "Pattern: Robes of Arcana", quality = 2 })
  Mock.AddItem(HAMMER_PLANS, { name = "Plans: Sulfuron Hammer", quality = 4 })
end

describe("SkillPlanner", function()
  local ns, SP
  before_each(function()
    ns = H.fresh()
    SP = ns.SkillPlanner
  end)

  local function candidate(id, min, yellow, grey, extra)
    local c = { spellID = id, recipe = { recipeID = id, name = "R" .. id, outputItemID = id, quantityMin = 1, reagents = {} },
      learned = true, learnable = false, skill = { min = min, yellow = yellow, green = math.floor((yellow + grey) / 2), grey = grey }, weight = 1 }
    for k, v in pairs(extra or {}) do c[k] = v end
    return c
  end

  it("knows the skill-up chance and difficulty at every point", function()
    local skill = { min = 100, yellow = 125, green = 137, grey = 150 }
    assert_eq(SP.Chance(skill, 100), 1)
    assert_eq(SP.Chance(skill, 124), 1)
    assert_eq(SP.Chance(skill, 125), 1, "yellow starts at the threshold with full chance")
    assert_eq(SP.Chance(skill, 145), 0.2)
    assert_eq(SP.Chance(skill, 150), 0)
    assert_eq(SP.Chance(nil, 1), 0)
    assert_eq(SP.Chance({ min = 1, yellow = 0, grey = 0 }, 1), 0, "unknown thresholds never give points")
    assert_eq(SP.Difficulty(skill, 110), "orange")
    assert_eq(SP.Difficulty(skill, 130), "yellow")
    assert_eq(SP.Difficulty(skill, 140), "green")
    assert_eq(SP.Difficulty(skill, 160), "grey")
  end)

  it("plans segments with learned recipes first, expected crafts rounded up, and gaps", function()
    local plan = SP.Plan(100, 130, {
      candidate(1, 1, 110, 130),                   -- orange to 110, then fading
      candidate(2, 1, 120, 140, { weight = 5 }),    -- orange to 120
      candidate(3, 1, 150, 170, { learned = false, learnable = true }),
    })
    assert_eq(plan.from, 100)
    assert_eq(plan.to, 130)
    assert_true(plan.covered)
    assert_eq(#plan.gaps, 0)
    -- 100-110: both give a sure point (full chance up to and at the yellow
    -- threshold); recipe 1 is lighter. From 111 recipe 2 is still orange
    -- while recipe 1 fades, and through 120-129 recipe 2's yellow beats 1's green.
    assert_eq(plan.segments[1].id, 1)
    assert_eq(plan.segments[1].from, 100)
    assert_eq(plan.segments[1].to, 111)
    assert_eq(plan.segments[1].crafts, 11)
    assert_eq(plan.segments[1].difficulty, "orange")
    assert_eq(plan.segments[2].id, 2)
    assert_eq(plan.segments[2].from, 111)
    assert_eq(plan.segments[2].to, 130, "recipe 2 stays better through its yellow range")
    assert_gt(plan.segments[2].crafts, 10)
    assert_eq(#plan.list, 2, "the unlearned recipe is never used while a learned one gives points")
    assert_eq(plan.list[1].spellID, 1)
    assert_eq(plan.list[2].spellID, 2)
    assert_eq(plan.total, plan.segments[1].crafts + plan.segments[2].crafts)
    assert_match(SP.Lines(plan)[1], "^100%-111: 11 x R1 %(orange%)$")
    -- Beyond every learned recipe the learnable one fills in, with its own requirement respected.
    plan = SP.Plan(130, 170, { candidate(1, 1, 110, 130), candidate(3, 140, 150, 170, { learned = false, learnable = true }) })
    assert_false(plan.covered)
    assert_eq(plan.gaps[1].from, 130)
    assert_eq(plan.gaps[1].to, 140, "the learnable recipe needs 140 first")
    assert_eq(plan.segments[2].id, 3)
    assert_false(plan.segments[2].learned)
    assert_match(SP.Lines(plan)[1], "no recipe you know")
    assert_match(SP.Lines(plan)[2], "not learned")
    -- An unlearned recipe whose requirement is unknown is never planned.
    plan = SP.Plan(130, 140, { candidate(3, 1, 150, 170, { learned = false, learnable = false }) })
    assert_eq(#plan.list, 0)
    assert_eq(#plan.gaps, 1)
    assert_eq(SP.Plan(150, 150, {}).total, 0)
  end)

  it("prefers the cheapest expected cost when reagent prices are known", function()
    local cheap = candidate(1, 1, 100, 140, { cost = 100 })      -- yellow from 100: chance 1 at 100, 0.5 at 120
    local pricey = candidate(2, 1, 150, 170, { cost = 300 })      -- orange throughout
    local plan = SP.Plan(100, 130, { cheap, pricey })
    assert_eq(plan.segments[1].id, 1, "at full chance the cheap recipe wins")
    local last = plan.segments[#plan.segments]
    assert_eq(last.id, 2, "once the cheap recipe's chance drops below a third, the orange one is cheaper per point")
    -- Priced beats unpriced on a tie, and cost decides between priced recipes.
    local unpriced = candidate(3, 1, 150, 170)
    plan = SP.Plan(100, 105, { pricey, unpriced })
    assert_eq(plan.segments[1].id, 2)
  end)
end)

describe("Learn-recipe goals", function()
  local ns
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    names()
  end)

  it("validates and titles the new goal types", function()
    local GoalModel = ns.GoalModel
    assert_true(GoalModel.IsSupported("LEARN_RECIPE"))
    assert_true(GoalModel.IsSupported("REACH_SKILL"))
    assert_nil((GoalModel.New("LEARN_RECIPE", { name = "x" })), "spellID required")
    assert_nil((GoalModel.New("REACH_SKILL", { professionName = "Tailoring" })), "rank required")
    assert_nil((GoalModel.New("REACH_SKILL", { professionName = "Tailoring", rank = 5000 })), "rank bounded")
    local learn = GoalModel.New("LEARN_RECIPE", { spellID = WOOLEN_BOLT, name = "Bolt of Woolen Cloth", professionName = "Tailoring" })
    assert_eq(GoalModel.Title(learn), "Learn recipe: Bolt of Woolen Cloth")
    assert_eq(GoalModel.Name(learn), "Bolt of Woolen Cloth")
    local skill = GoalModel.New("REACH_SKILL", { professionName = "Tailoring", rank = 225 })
    assert_eq(GoalModel.Title(skill), "Reach Tailoring 225")
    assert_eq(GoalModel.Name(skill), "Tailoring 225")
    assert_true(GoalModel.SetRank(skill, 300))
    assert_eq(skill.target.rank, 300)
    assert_false(GoalModel.SetRank(learn, 300))
    assert_true(GoalModel.Validate(skill))
  end)

  it("searches the catalogue by recipe name and profession", function()
    local Recipes = ns.Data.Recipes
    local hits = Recipes.Search("bolt of woolen", 5)
    assert_eq(hits[1].spellID, WOOLEN_BOLT)
    assert_eq(hits[1].professionName, "Tailoring")
    hits = Recipes.Search("Bolt of Woolen Cloth", 5)
    assert_eq(hits[1].spellID, WOOLEN_BOLT, "exact name first")
    assert_eq(#Recipes.Search("zzzz-nothing", 5), 0)
    assert_gt(#Recipes.ForProfession(197), 100)
    assert_eq(#Recipes.ForProfession(0), 0)
    local id, name = Recipes.FindProfession("tailor")
    assert_eq(id, 197)
    assert_eq(name, "Tailoring")
    assert_nil(Recipes.FindProfession("Dancing"))
    assert_gt(#Recipes.Professions(), 5)
  end)

  it("plans a trainer recipe as a train step, blocked by profession or skill, and completes when learned", function()
    local ok, message, goal = ns.GoalService.AddRecipeFromInput("Bolt of Woolen Cloth")
    assert_true(ok, message)
    assert_eq(goal.type, "LEARN_RECIPE")
    assert_eq(goal.target.spellID, WOOLEN_BOLT)
    assert_eq(goal.target.professionName, "Tailoring")
    assert_eq(ns.GoalService.Title(goal), "Learn recipe: Bolt of Woolen Cloth")
    -- No tailoring at all.
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.status, ns.Status.OK)
    assert_eq(view.learn.kind, "trainer")
    assert_false(view.learn.hasProfession)
    assert_eq(view.learn.blocked, "profession")
    assert_match(view.message, "^You do not have Tailoring on this character%. Train at any Tailoring trainer")
    assert_eq(view.nextStep, "Learn Tailoring")
    assert_not_nil(view.tree.root.step)
    assert_eq(view.tree.root.step.kind, "train")
    assert_eq(view.tree.root.key, "train:" .. WOOLEN_BOLT)
    assert_eq(view.tree.summary.nodes, 1)
    assert_true(view.plan.step)
    assert_eq(#view.plan.materials, 0)
    assert_eq(ns.Overview.Percent(view), 0)
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Learn Tailoring")
    assert_eq(#overview.missing, 0)
    -- A tailor at 100: nothing blocks, the requirement is not recorded yet.
    tailor(ns, 100)
    view = ns.Planner.Evaluate(goal)
    assert_true(view.learn.skillOK)
    assert_nil(view.learn.blocked)
    assert_eq(view.nextStep, "Visit a Tailoring trainer")
    overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Train Bolt of Woolen Cloth")
    local list = ns.ShoppingList.Build({ { goal = goal, view = view } })
    assert_eq(list.rows[1].key, "train:" .. WOOLEN_BOLT)
    assert_eq(list.rows[1].category, "learn")
    -- After a trainer visit the step names the trainer and the cost; at 50 skill it is blocked.
    Mock.zone = "Stormwind City"
    Mock.OpenTrainer("Georgio Bolero", { { spellID = WOOLEN_BOLT, name = "Bolt of Woolen Cloth", type = "unavailable", skill = "Tailoring", rank = 75, cost = 500 } })
    Mock.RunTimers()
    Mock.CloseTrainer()
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.learn.need, 75)
    assert_match(view.message, "^Train at Georgio Bolero, Stormwind City for 5s 0c%.$")
    assert_eq(view.nextStep, "Train at Georgio Bolero")
    assert_eq(view.tree.root.step.trainer.name, "Georgio Bolero")
    tailor(ns, 50)
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.learn.blocked, "skill")
    assert_match(view.message, "^Needs Tailoring 75; you have 50%. Train at Georgio Bolero")
    assert_eq(view.nextStep, "Reach Tailoring 75")
    overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Reach Tailoring 75")
    assert_eq(overview.nextSteps[1].badge, "Skill")
    -- An alt that knows it is mentioned.
    ns.db.characters["Miravelle-Stormhold"] = { key = "Miravelle-Stormhold", name = "Miravelle", realm = "Stormhold", level = 40, class = "Mage", lastSeen = Mock.now - 60,
      bags = { items = {} }, professions = { { name = "Tailoring", skillLevel = 120, maxSkillLevel = 150, skillLine = 197 } }, knownRecipes = { [WOOLEN_BOLT] = true } }
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.learn.knownBy[1], "Miravelle")
    assert_match(view.message, "Miravelle already knows it%.$")
    -- Learning it (NEW_RECIPE_LEARNED) completes the goal with its own toast.
    tailor(ns, 100)
    Mock.FireEvent("NEW_RECIPE_LEARNED", WOOLEN_BOLT)
    Mock.RunTimers()
    assert_eq(goal.status, "COMPLETED")
    assert_eq(goal.target.completedBy, "auto")
    assert_output("Goal complete: Learned: Bolt of Woolen Cloth%.")
    assert_eq(ns.UI.Toast.lastShown.title, "Recipe learned")
    view = ns.Planner.Evaluate(goal)
    assert_true(view.learn.learned)
    assert_true(view.plan.isComplete)
    assert_match(view.message, "already learned")
    -- Adding it again just selects the existing goal (reopened).
    local again, msg2 = ns.GoalService.AddRecipeGoal(WOOLEN_BOLT)
    assert_eq(again.id, goal.id)
    assert_match(msg2, "^Already a goal")
    assert_eq(again.status, "ACTIVE")
  end)

  it("plans a pattern recipe as the pattern to get, then to read", function()
    Mock.AddItem(HAMMER_PLANS, { name = "Plans: Sulfuron Hammer", quality = 4 })
    Mock.professionSlots = { 1 }
    Mock.professionInfo = { [1] = { name = "Blacksmithing", skillLevel = 300, maxSkillLevel = 300, skillLine = 164 } }
    local goal, message = ns.GoalService.AddRecipeGoal(HAMMER)
    assert_not_nil(goal, message)
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.learn.kind, "plans")
    assert_eq(view.learn.teachItemID, HAMMER_PLANS)
    assert_true(view.obtain)
    assert_eq(view.tree.root.itemID, HAMMER_PLANS)
    assert_true(view.tree.root.learn)
    assert_eq(view.tree.root.learnFor, "Sulfuron Hammer")
    assert_eq(view.plan.materials[1].itemID, HAMMER_PLANS)
    assert_eq(view.plan.materials[1].missing, 1)
    assert_eq(view.nextStep, "Get Plans: Sulfuron Hammer")
    assert_match(view.message, "^Get Plans: Sulfuron Hammer")
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Get Plans: Sulfuron Hammer")
    assert_eq(overview.nextSteps[1].badge, "Recipe")
    assert_eq(overview.missing[1].itemID, HAMMER_PLANS)
    local list = ns.ShoppingList.Build({ { goal = goal, view = view } })
    assert_eq(list.rows[1].itemID, HAMMER_PLANS)
    assert_true(list.rows[1].learn)
    -- With the plans in the bags: read them.
    Mock.SetBag(0, 16, { { HAMMER_PLANS, 1 } })
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.RunTimers()
    view = ns.Planner.Evaluate(goal)
    assert_true(view.plan.isComplete)
    assert_eq(view.nextStep, "Read Plans: Sulfuron Hammer")
    assert_match(view.message, "is in your bags: read it to learn Sulfuron Hammer")
    overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Read Plans: Sulfuron Hammer")
    assert_eq(ns.Overview.Percent(view), 100)
    -- Combines cannot be learned; unknown spells are refused.
    local nope, why = ns.GoalService.AddRecipeGoal(SULFURAS_COMBINE)
    assert_nil(nope)
    assert_match(why, "item%-use combine")
    nope, why = ns.GoalService.AddRecipeGoal(1)
    assert_nil(nope)
    assert_match(why, "No recipe with spell id 1")
    local ok, text = ns.GoalService.AddRecipeFromInput("zzzz-nothing")
    assert_false(ok)
    assert_match(text, "No recipe called")
  end)
end)

describe("Reach-skill goals", function()
  local ns
  before_each(function()
    ns = H.fresh()
    H.login(ns)
    names()
    tailor(ns, 100)
    for _, id in ipairs({ WOOLEN_BOLT, WOOLEN_BOOTS, HEAVY_PANTS, SILK_BOLT, LINEN_BOLT }) do
      ns.chardb.knownRecipes[id] = true
    end
  end)

  it("picks the target, refuses unknown professions and reports a missing one", function()
    assert_eq(ns.GoalService.NextSkillTarget(nil), 75)
    assert_eq(ns.GoalService.NextSkillTarget({ skillLevel = 100, maxSkillLevel = 150 }), 150)
    assert_eq(ns.GoalService.NextSkillTarget({ skillLevel = 150, maxSkillLevel = 150 }), 225)
    local ok, message = ns.GoalService.AddSkillFromInput("dancing 100")
    assert_false(ok)
    assert_match(message, "No profession called")
    ok, message = ns.GoalService.AddSkillFromInput("")
    assert_false(ok)
    local goal
    ok, message, goal = ns.GoalService.AddSkillFromInput("blacksmithing")
    assert_true(ok, message)
    assert_eq(goal.target.professionName, "Blacksmithing")
    assert_eq(goal.target.rank, 75, "no standing: the first cap")
    assert_match(message, "not one of this character's professions yet")
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.status, ns.Status.PROFESSION_MISSING)
    assert_match(view.message, "Blacksmithing is not one of this character's professions")
    assert_eq(ns.StatusLabel[view.status], "Profession not known")
  end)

  it("plans the crafts from the current skill to the target and completes on the skill-up", function()
    local ok, message, goal = ns.GoalService.AddSkillFromInput("tailoring")
    assert_true(ok, message)
    assert_eq(goal.type, "REACH_SKILL")
    assert_eq(goal.target.professionID, 197)
    assert_eq(goal.target.rank, 150, "the current cap")
    assert_eq(goal.target.startRank, 100)
    assert_eq(ns.GoalService.Title(goal), "Reach Tailoring 150")
    local view = ns.Planner.Evaluate(goal)
    assert_eq(view.status, ns.Status.OK)
    local skill = view.skill
    assert_eq(skill.current, 100)
    assert_eq(skill.target, 150)
    assert_eq(skill.percent, 0)
    assert_true(skill.scanned)
    assert_false(skill.capBlocked)
    assert_eq(ns.Overview.Percent(view), 0)
    local plan = view.skillPlan
    assert_true(plan.covered, table.concat(ns.SkillPlanner.Lines(plan), "; "))
    assert_eq(plan.list[1].spellID, SILK_BOLT, "orange to 110 like the pants, but fewer reagents")
    assert_eq(plan.list[1].from, 100)
    assert_eq(plan.list[1].to, 111)
    assert_true(plan.list[1].learned)
    assert_eq(plan.list[2].spellID, HEAVY_PANTS, "the pants fade slower once both are past yellow")
    assert_eq(plan.list[2].from, 111)
    local last = plan.list[#plan.list]
    assert_false(last.learned, "past 145 nothing learned gives points: a pattern recipe with a known requirement fills in")
    assert_not_nil(last.recipe.teachItemID)
    assert_true(last.recipe.skill.min > 1 and last.recipe.skill.min <= last.from)
    assert_eq(last.to, 150)
    local patternItem = last.recipe.teachItemID
    assert_gt(plan.total, 50)
    -- The tree: a skill root with one craft child per recipe, done for the points.
    local root = view.tree.root
    assert_eq(root.step.kind, "skill")
    assert_eq(root.step.name, "Tailoring 150")
    assert_eq(root.quantity, plan.total)
    assert_eq(#root.children, #plan.list)
    assert_eq(root.children[1].itemID, 4305, "Bolt of Silk Cloth first")
    local pants = root.children[2]
    assert_eq(pants.itemID, PANTS_ITEM)
    assert_not_nil(pants.forSkill)
    assert_eq(pants.craft.crafts, plan.list[2].crafts)
    assert_eq(pants.quantity, plan.list[2].crafts)
    assert_eq(pants.route, "craft")
    assert_false(pants.claims)
    assert_eq(pants.children[1].itemID, WOOLEN_CLOTH)
    assert_eq(pants.children[1].quantity, plan.list[2].crafts * 5)
    assert_eq(pants.children[1].route, "craft", "Bolt of Woolen Cloth is a learned craft")
    assert_eq(pants.children[1].children[1].itemID, WOOL)
    local robe = root.children[#root.children]
    assert_eq(robe.craft.recipeID, last.spellID)
    assert_false(robe.craft.learned)
    assert_eq(robe.children[1].itemID, patternItem, "the pattern is a requirement of an unlearned recipe")
    assert_true(robe.children[1].learn)
    assert_match(ns.DependencyResolver.Describe(view.tree)[1], "^Tailoring 150: %d+ crafts over %d recipes")
    assert_match(ns.DependencyResolver.Describe(view.tree, ns.ItemProvider.GetName)[2], "^  Bolt of Silk Cloth x%d+ for skill 100%-111 %(%d+ crafts%)")
    -- Flat materials: reagents merged across the crafts, never the outputs.
    local materials = {}
    for _, m in ipairs(view.plan.materials) do materials[m.itemID] = m end
    assert_nil(materials[PANTS_ITEM])
    assert_gt(materials[WOOLEN_CLOTH].required, 50)
    assert_not_nil(materials[THREAD])
    assert_not_nil(materials[patternItem])
    assert_true(view.plan.skill)
    assert_eq(view.plan.craftsNeeded, plan.total)
    assert_match(view.message, "^100 to 150: about %d+ crafts %- %d+ x Bolt of Silk Cloth %(100%-111%), %d+ x Heavy Woolen Pants %(111%-1%d%d%)")
    assert_match(view.message, "%(1%d%d%-150, learn it first%)")
    assert_match(view.nextStep, "^Craft %d+ x Bolt of Silk Cloth$")
    -- Shopping list: reagents and the pattern, not the pants.
    local list = ns.ShoppingList.Build({ { goal = goal, view = view } })
    local byItem = {}
    for _, r in ipairs(list.rows) do byItem[r.itemID or r.key] = r end
    assert_nil(byItem[PANTS_ITEM])
    assert_eq(byItem[WOOLEN_CLOTH].category, "craft")
    assert_not_nil(byItem[WOOL])
    assert_true(byItem[patternItem].learn)
    -- Overview: with the reagents of the first recipe on hand, the next step is to craft it.
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_match(overview.nextSteps[1].title, "^Obtain %d+ x ")
    Mock.SetBag(0, 20, { { WOOLEN_CLOTH, 2000 }, { THREAD, 2000 } })
    Mock.FireEvent("BAG_UPDATE_DELAYED")
    Mock.RunTimers()
    view = ns.Planner.Evaluate(goal)
    overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_match(overview.nextSteps[1].title, "^Craft %d+ x Heavy Woolen Pants$", "the silk bolts lack their cloth; the pants are ready")
    assert_match(overview.nextSteps[1].detail, "^Tailoring %(skill 111%-1%d%d%) %- for Tailoring 150")
    -- CraftWise: buying the output is never an option; the craft path prices the reagents.
    local compare = ns.CraftWise.Compare(view.tree, { priceOf = function(id)
      if id == WOOL then return { copper = 50 } elseif id == THREAD then return { copper = 10 } elseif id == ARCANA_PATTERN then return { copper = 5000 } end
    end })
    assert_nil(compare.buy.cost)
    assert_eq(compare.rows[2].node.itemID, 4305)
    assert_nil(compare.rows[2].buy, "crafts for skill cannot be bought")
    assert_eq(compare.rows[2].choice, "craft")
    local pantsRow
    for _, r in ipairs(compare.rows) do if r.node == pants then pantsRow = r end end
    assert_nil(pantsRow, "a fresh evaluation built a new tree")
    for _, r in ipairs(compare.rows) do if r.node.itemID == PANTS_ITEM and r.depth == 1 then pantsRow = r end end
    assert_eq(pantsRow.choice, "craft")
    assert_eq(pantsRow.craft, 0, "every reagent of the pants is on hand")
    -- Progress follows the skill, and the skill-up event completes the goal.
    Mock.professionInfo[1].skillLevel = 125
    view = ns.Planner.Evaluate(goal)
    assert_eq(view.skill.percent, 50)
    assert_eq(view.skillPlan.from, 125)
    Mock.professionInfo[1].skillLevel = 150
    Mock.FireEvent("SKILL_LINES_CHANGED")
    Mock.RunTimers()
    assert_eq(goal.status, "COMPLETED")
    assert_output("Goal complete: Tailoring 150 reached%.")
    assert_eq(ns.UI.Toast.lastShown.title, "Skill reached")
    -- Raising the target reopens it from the new standing.
    local again, text = ns.GoalService.AddSkillGoal("Tailoring", 225)
    assert_eq(again.id, goal.id)
    assert_match(text, "^Updated goal: Reach Tailoring 225")
    assert_eq(again.status, "ACTIVE")
    assert_eq(again.target.startRank, 150)
    view = ns.Planner.Evaluate(again)
    assert_true(view.skill.capBlocked)
    assert_match(view.message, "^Your Tailoring cap is 150")
    local unlearned = 0
    for _, entry in ipairs(view.skillPlan.list) do if not entry.learned then unlearned = unlearned + 1 end end
    assert_gt(unlearned, 0, "pattern recipes with a known requirement carry the plan past what is learned")
    assert_true(view.skillPlan.covered)
    assert_match(view.message, "learn it first")
  end)

  it("asks for a profession scan and offers the slash commands", function()
    ns.chardb.professions[197] = nil
    local goal = ns.GoalService.AddSkillGoal("Tailoring", 150)
    local view = ns.Planner.Evaluate(goal)
    assert_false(view.skill.scanned)
    assert_match(view.message, "Open your Tailoring window once")
    local overview = ns.Overview.Build({ { goal = goal, view = view } }, { nameOf = ns.ItemProvider.GetName })
    assert_eq(overview.nextSteps[1].title, "Open your Tailoring window")
    ns.Commands.Dispatch("skill tailoring 140")
    assert_output("Updated goal: Reach Tailoring 140")
    ns.Commands.Dispatch("learn bolt of woolen cloth")
    assert_output("Added goal: Learn recipe: Bolt of Woolen Cloth")
    ns.Commands.Dispatch("learn nothing-like-this")
    assert_output("No recipe called")
    ns.Commands.Dispatch("goals")
    assert_output("Reach Tailoring 140")
    assert_output("Learn recipe: Bolt of Woolen Cloth")
  end)

  it("renders both goal types on every screen and the tracker", function()
    local MainFrame = ns.UI.MainFrame
    local skillGoal = ns.GoalService.AddSkillGoal("Tailoring", 150)
    local learnGoal = ns.GoalService.AddRecipeGoal(WOOLEN_BOLT)
    MainFrame.Show()
    MainFrame.ShowScreen("goals")
    Mock.RunTimers()
    local goals = MainFrame.screens.goals
    local names = {}
    for _, row in ipairs(goals.rowPool.rows) do
      if row:IsShown() then names[#names + 1] = row.name:GetText() end
    end
    assert_eq(#names, 2)
    goals.newGoal.segment:Select("skill")
    goals.newGoal.input:SetText("Tailoring 160")
    assert_true(goals:Submit())
    assert_eq(skillGoal.target.rank, 160)
    goals.newGoal.segment:Select("recipe")
    goals.newGoal.input:SetText("Heavy Woolen Pants")
    assert_true(goals:Submit())
    assert_eq(ns.GoalService.GetSelected().target.spellID, HEAVY_PANTS)
    goals.newGoal.segment:Select("item")
    ns.GoalService.Select(skillGoal.id)
    MainFrame.ShowScreen("crafting")
    Mock.RunTimers()
    local crafting = MainFrame.screens.crafting
    assert_match(crafting.hero.name:GetText(), "Tailoring 160")
    assert_match(crafting.hero.reagents:GetText(), "crafts planned")
    crafting.tabs:Select("tree")
    crafting.tab = "tree"
    crafting:Refresh()
    assert_true(crafting.treeView:IsShown())
    local firstRow = crafting.treeView.pool.rows[1]
    assert_match(firstRow.name:GetText(), "Tailoring 160")
    assert_eq(firstRow.via:GetText(), "Craft for skill")
    crafting.tabs:Select("craftwise")
    crafting.tab = "craftwise"
    crafting:Refresh()
    crafting.tabs:Select("requirements")
    crafting.tab = "requirements"
    ns.GoalService.Select(learnGoal.id)
    crafting:Refresh()
    assert_match(crafting.hero.name:GetText(), "Bolt of Woolen Cloth")
    assert_true(crafting.tableMessage:IsShown(), "a trainer step has nothing to gather")
    MainFrame.ShowScreen("dashboard")
    Mock.RunTimers()
    MainFrame.ShowScreen("shopping")
    Mock.RunTimers()
    ns.UI.Tracker.Refresh()
    assert_true(ns.UI.Tracker.IsShown())
    assert_eq(#ns.Log.errors, 0, ns.Log.errors[1] and ns.Log.errors[1].message or "")
  end)
end)
