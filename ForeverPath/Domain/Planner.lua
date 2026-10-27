-- Evaluates a goal against the providers and produces a view model for the UI.
--
-- Providers are injected (deps table) so the planner is testable with mocks:
--   deps.item        GetItem(itemID) -> { itemID, exists, loaded, name, link, icon, quality }
--   deps.profession  IsAvailable(), HasScanData(), GetScannedProfessions(),
--                    FindRecipesForItem(itemID) -> { { recipe = r, learned = bool }, ... },
--                    GetRecipe(recipeID, refresh) -> recipe
--   deps.inventory   GetCounts(itemID) -> { bags, bank, bankSource, bankScannedAt }
--   deps.catalogue   the recipe catalogue (Data/Recipes.lua): Lookup(itemID) -> static recipe hints, Get, ForProfession, Sources ...
--   deps.settings    { includeBank = bool }
--   deps.ledger      Allocation ledger shared across goals (EvaluateAll creates one)
--   deps.characters  Sources(itemID) -> alt hints (optional)
--   deps.sources     Sources(itemID) -> vendor / drop / quest / gather hints (optional)
--
-- CRAFT_ITEM goals plan the recipe. OBTAIN_ITEM goals, and crafting goals
-- whose item has no recorded recipe but at least one known source, plan the
-- item itself as something to get (EvaluateObtain).
local _, ns = ...

local Readiness = ns.Readiness
local CraftingEngine = ns.CraftingEngine
local RecipeModel = ns.RecipeModel
local GoalModel = ns.GoalModel
local Util = ns.Util
local Log = ns.Log
local DependencyResolver = ns.DependencyResolver
local Allocation = ns.Allocation

local Planner = {}
ns.Planner = Planner

function Planner.DefaultDeps()
  return {
    item = ns.ItemProvider,
    profession = ns.ProfessionProvider,
    inventory = ns.InventoryProvider,
    catalogue = ns.Data.Recipes,
    characters = ns.CharacterProvider,
    sources = ns.SourceProvider,
    price = ns.PriceProvider,
    attune = ns.AttuneProvider,
    quest = ns.QuestProvider,
    reputation = ns.ReputationProvider,
    settings = ns.db and ns.db.settings or {},
  }
end

-- Whether this character has learned a recipe spell (false without the
-- profession provider, or when it raises - which is logged).
local function isLearned(deps, spellID)
  local profession = deps.profession
  return profession ~= nil and Log.Try(profession.IsLearned, spellID) == true
end

local function professionList(deps)
  local names = {}
  local list = Log.Try(deps.profession.GetScannedProfessions)
  if type(list) == "table" then
    for _, p in ipairs(list) do
      names[#names + 1] = p.name or ("profession " .. tostring(p.professionID))
    end
  end
  return names
end

-- Inventory settings and the resolver options shared by both planning paths.
local function inventoryContext(deps)
  local includeBank = deps.settings and deps.settings.includeBank
  if includeBank == nil then
    includeBank = true
  end
  local includeAlts = deps.settings and deps.settings.includeAlts == true
  local ctx = { includeBank = includeBank, includeAlts = includeAlts }
  ctx.lookup = function(reagentID)
    local counts = deps.inventory and deps.inventory.GetCounts and deps.inventory.GetCounts(reagentID) or 0
    -- The first counts that report a bank: DescribeInventory says where bank numbers come from.
    if type(counts) == "table" and counts.bankSource and counts.bankSource ~= "none" and not ctx.bankCounts then
      ctx.bankCounts = counts
    end
    return counts
  end
  ctx.resolverOpts = function(routes)
    return {
      findRecipes = Planner.RecipeFinder(deps),
      counts = ctx.lookup,
      includeBank = includeBank,
      routes = routes,
      ledger = deps.ledger or Allocation.New(),
      includeAlts = includeAlts,
      sources = Planner.SourceFinder(deps),
      crafters = deps.characters and deps.characters.WithProfession or nil,
      soulbound = deps.catalogue and deps.catalogue.IsSoulbound or nil,
      isRaw = deps.sources and deps.sources.IsRawMaterial or nil,
    }
  end
  return ctx
end

-- Every recipe producing itemID: recorded ones first, then catalogue entries
-- not already recorded. A catalogue recipe this character has learned (but
-- never scanned) still counts as learned.
function Planner.Candidates(itemID, deps)
  local candidates, seen = {}, {}
  if deps.profession and deps.profession.FindRecipesForItem then
    for _, candidate in ipairs(deps.profession.FindRecipesForItem(itemID) or {}) do
      candidates[#candidates + 1] = candidate
      if candidate.recipe and candidate.recipe.recipeID then seen[candidate.recipe.recipeID] = true end
    end
  end
  if deps.catalogue and deps.catalogue.Lookup then
    local hints = deps.catalogue.Lookup(itemID)
    if type(hints) == "table" then
      for _, hint in ipairs(hints) do
        if not (hint.recipeID and seen[hint.recipeID]) then
          local learned = hint.recipeID ~= nil and not hint.combine and isLearned(deps, hint.recipeID)
          candidates[#candidates + 1] = { recipe = hint, learned = learned, static = true }
        end
      end
    end
  end
  return candidates
end

local function chooseCandidate(candidates)
  local learned, unlearned
  for _, candidate in ipairs(candidates) do
    if candidate.learned and not learned then
      learned = candidate
    elseif not candidate.learned and not unlearned then
      unlearned = candidate
    end
  end
  return learned, unlearned
end

local buildCraftPlan

-- The Planner function that evaluates each non-item goal type. Item goals
-- (CRAFT_ITEM, OBTAIN_ITEM) are planned by Evaluate itself.
local EVALUATORS = {
  COMPLETE_ATTUNEMENT = "EvaluateAttunement",
  LEARN_RECIPE = "EvaluateLearn",
  REACH_SKILL = "EvaluateSkill",
  COMPLETE_QUEST = "EvaluateQuest",
  REACH_REPUTATION = "EvaluateReputation",
  APPLY_ENCHANT = "EvaluateEnchant",
}

local function evaluate(goal, deps)
  local view = { goal = goal, readiness = Readiness.OK, message = "", candidates = {} }

  if not goal or not GoalModel.IsSupported(goal.type) then
    view.readiness = Readiness.UNSUPPORTED_GOAL
    view.message = "These goals are not supported by this version of ForeverPath."
    return view
  end
  local evaluator = EVALUATORS[goal.type]
  if evaluator then
    return Planner[evaluator](view, goal, deps)
  end

  local itemID = goal.target.itemID
  local quantity = goal.target.quantity

  -- Item information (may still be loading; that does not block recipe lookup).
  if deps.item and deps.item.GetItem then
    view.item = deps.item.GetItem(itemID)
  end
  view.item = view.item or { itemID = itemID, exists = nil, loaded = false }
  if view.item.exists == false then
    view.readiness = Readiness.ITEM_INVALID
    view.message = string.format("Item %d does not exist on this client. Check the item ID.", itemID)
    return view
  end
  if view.item.unavailable then
    view.readiness = Readiness.ITEM_UNAVAILABLE
    view.message = string.format("The server returned no data for item %d.", itemID)
    return view
  end

  if not deps.profession or not deps.profession.IsAvailable() then
    view.readiness = Readiness.PROVIDER_UNAVAILABLE
    view.message = "This client does not expose the profession API ForeverPath needs (C_TradeSkillUI). Crafting goals cannot be evaluated here."
    return view
  end

  local candidates = Planner.Candidates(itemID, deps)
  view.candidates = candidates
  local learned, unlearned = chooseCandidate(candidates)
  local obtain = goal.type == "OBTAIN_ITEM"
  local catalogue = deps.catalogue and deps.catalogue.IsAvailable and deps.catalogue.IsAvailable() or false

  if #candidates == 0 and not obtain and not catalogue and not deps.profession.HasScanData() then
    view.readiness = Readiness.RECIPES_NOT_SCANNED
    view.message = "No profession data has been captured yet. Open each of your profession windows once (or use /fp scan) so ForeverPath can record your recipes."
    return view
  end

  -- A recipe nobody here has learned: plan the item as something to get. The
  -- resolver lays the craft out anyway (reagents, the plans that teach it,
  -- who on the account could craft it) so the whole path is visible.
  if #candidates > 0 and not learned and not obtain then
    view.recipe = unlearned.recipe
    view.recipeStatus = "unlearned"
    return Planner.EvaluateObtain(view, goal, deps, Planner.Sources(itemID, deps))
  end

  -- Obtain goals, and crafting goals with no recipe, plan the item as
  -- something to get (drop, vendor, quest, alt, or a craft of the shortfall
  -- when a learned recipe exists). A crafting goal only falls through when at
  -- least one source is known, so "no recipe" stays an explicit status.
  if #candidates == 0 or obtain then
    local sources = Planner.Sources(itemID, deps)
    if not obtain and #sources == 0 then
      view.readiness = Readiness.RECIPE_NOT_FOUND
      local scanned = professionList(deps)
      view.message = string.format(
        "No recipe producing this item was found in your scanned professions (%s), and no vendor, loot table or gathering source is recorded for it. It may belong to a profession you have not scanned, or come from somewhere ForeverPath does not know yet (/fp sources).",
        #scanned > 0 and Util.Join(scanned) or "none")
      return view
    end
    return Planner.EvaluateObtain(view, goal, deps, sources)
  end

  -- Refresh from the live API when possible; fall back to the cached copy.
  local recipe = learned.recipe
  if deps.profession.GetRecipe then
    local refreshed, isLive = deps.profession.GetRecipe(recipe.recipeID, true)
    if refreshed then
      recipe = refreshed
      view.recipeIsLive = isLive and true or false
    end
  end
  view.recipe = recipe

  local valid, reason = RecipeModel.Validate(recipe)
  if not valid then
    view.readiness = Readiness.RECIPE_DATA_INVALID
    view.message = string.format("Cached recipe data for %s is invalid (%s). Re-open the profession window to rescan.", recipe.name or "this recipe", reason)
    return view
  end

  local plan = buildCraftPlan(view, goal, deps, { recipe = recipe, quantity = quantity }, quantity)
  if not plan then return view end
  view.plan = plan
  view.progress = Planner.Progress(plan)

  if plan.isComplete then
    view.message = string.format("All materials for %d craft%s are on hand.", plan.craftsNeeded, plan.craftsNeeded == 1 and "" or "s")
  else
    view.message = string.format("%d material%s still missing for %d craft%s.",
      plan.totals.materialsMissing, plan.totals.materialsMissing == 1 and "" or "s",
      plan.craftsNeeded, plan.craftsNeeded == 1 and "" or "s")
  end
  if view.recipeIsLive == false then
    view.message = view.message .. string.format(" Recipe data cached from scan (%s).", Util.FormatAgo(recipe.scannedAt))
  end
  return view
end

-- The craft pipeline every recipe goal shares: resolve `root` (claiming
-- inventory through the ledger), then build the flat requirements plan for
-- `crafts` from the tree's depth-1 claims so both agree and nothing is
-- counted twice. Sets view.tree, view.fullTree and view.inventoryNote.
-- Returns the plan, or nil after setting the error on the view.
function buildCraftPlan(view, goal, deps, root, crafts)
  local ctx = inventoryContext(deps)
  local tree = DependencyResolver.Resolve(root, ctx.resolverOpts(goal.routes))
  view.tree = tree
  view.fullTree = Planner.FullTree(root, goal, ctx)
  local direct = DependencyResolver.DirectCounts(tree)
  local plan, err = CraftingEngine.BuildPlan(root.recipe, crafts, function(reagentID)
    return direct[reagentID] or 0
  end, { includeBank = ctx.includeBank, includeAlts = ctx.includeAlts })
  if not plan then
    view.readiness = Readiness.RECIPE_DATA_INVALID
    view.message = tostring(err)
    return nil
  end
  view.inventoryNote = Planner.DescribeInventory(ctx.bankCounts, ctx.includeBank, ctx.includeAlts)
  return plan
end

-- Returns a view:
--   { goal, status, message, item, recipe, plan, tree, fullTree, candidates, recipeIsLive, inventoryNote, progress,
--     craftwise }
-- craftwise is CraftWise.Compare over the full tree with deps.price, so every
-- screen reads the same comparison instead of computing its own.
function Planner.Evaluate(goal, deps)
  deps = deps or Planner.DefaultDeps()
  local view = evaluate(goal, deps)
  local tree = view.fullTree or view.tree
  view.craftwise = tree and ns.CraftWise.Compare(tree, { prices = deps.price }) or nil
  return view
end

-- CraftWise compares buying with crafting at every level, so it needs a tree
-- where every learned recipe is expanded. When the goal has route overrides
-- ("buy" collapses a subtree) a second tree without them is resolved on a
-- private ledger; otherwise the plan's own tree already is the full tree.
function Planner.FullTree(rootSpec, goal, ctx)
  if type(goal.routes) ~= "table" or next(goal.routes) == nil then return nil end
  local opts = ctx.resolverOpts(nil)
  opts.ledger = Allocation.New()
  local tree = DependencyResolver.Resolve(rootSpec, opts)
  return tree
end

-- A recipe by spell id: the catalogue first, then a recorded profession window.
function Planner.RecipeByID(spellID, deps)
  local data, profession = deps.catalogue or {}, deps.profession or {}
  local recipe = Log.Try(data.Get, spellID)
  if type(recipe) ~= "table" then recipe = Log.Try(data.GetCombine, spellID) end
  if type(recipe) ~= "table" then recipe = Log.Try(profession.GetRecipe, spellID, false) end
  return type(recipe) == "table" and recipe or nil
end

-- This character's standing in a profession: { name, skillLevel, maxSkillLevel, icon, source }
-- from the live profession list, else from a recorded window; nil without either.
function Planner.CurrentSkill(professionName, professionID, deps)
  deps = deps or Planner.DefaultDeps()
  local profession = deps.profession
  if not profession then return nil end
  local function matches(p)
    return (professionName and p.name == professionName) or (professionID and professionID ~= 0 and (p.skillLine == professionID or p.professionID == professionID))
  end
  for _, p in ipairs(Log.Try(profession.GetCharacterProfessions) or {}) do
    if matches(p) then
      return { name = p.name, skillLevel = p.skillLevel or 0, maxSkillLevel = p.maxSkillLevel or 0, icon = (p.icon ~= 0) and p.icon or nil, source = "live" }
    end
  end
  for _, p in ipairs(Log.Try(profession.GetScannedProfessions) or {}) do
    if matches(p) then
      return { name = p.name, skillLevel = p.skillLevel or 0, maxSkillLevel = p.maxSkillLevel or 0, source = "recorded" }
    end
  end
  return nil
end

-- A plan shaped like an obtain plan for a goal with a single step (train a
-- recipe) or nothing left to get; every screen reading plan.materials works.
function Planner.StepPlan(complete)
  local missing = complete and 0 or 1
  return {
    obtain = true, step = true, craftsNeeded = 0, outputPerCraft = 1, outputPerCraftMax = 1, expectedOutput = 0, quantityWanted = 1,
    materials = {},
    totals = { required = 1, owned = 1 - missing, missing = missing, materialsMissing = missing },
    isComplete = complete and true or false,
  }
end

-- A plan material row for a resolved tree node.
local function nodeMaterial(node)
  local owned = node.owned or 0
  local missing = node.missing or math.max(0, node.quantity - owned)
  return {
    itemID = node.itemID, perCraft = 1, required = node.quantity,
    owned = owned, ownedBags = node.ownedBags, ownedBank = node.ownedBank, ownedAlts = node.ownedAlts,
    altSources = node.altSources, bankSource = node.bankSource, reserved = node.reserved, missing = missing,
    questItem = node.questItem, questName = node.questName,
  }
end

local function countMissing(materials)
  local n = 0
  for _, m in ipairs(materials) do
    if m.missing > 0 then n = n + 1 end
  end
  return n
end

-- A step plan whose materials are the items hanging below the step (what a
-- quest asks for); complete when the step itself is done.
function Planner.StepItemsPlan(tree, complete)
  local plan = Planner.StepPlan(complete)
  for _, child in ipairs(tree and tree.root and tree.root.children or {}) do
    plan.materials[#plan.materials + 1] = nodeMaterial(child)
  end
  if not complete then plan.totals.materialsMissing = countMissing(plan.materials) end
  return plan
end

-- 1 bind on pickup, 2 on equip, 3 on use, 4 quest item; nil when unknown.
-- The client's answer (deps.item) first, then the catalogue's (deps.catalogue).
function Planner.BindType(itemID, deps)
  local item, data = deps and deps.item, deps and deps.catalogue
  local bind = item and item.BindType and Log.Try(item.BindType, itemID)
  if bind then return bind end
  return data and data.ItemBind and data.ItemBind(itemID) or nil
end

-- Source hints for one item through the same finders the resolver uses.
function Planner.Sources(itemID, deps)
  local finder = Planner.SourceFinder(deps)
  if not finder then return {} end
  return finder(itemID) or {}
end

-- "Dropped by Lord Cobrahn - Wailing Caverns (DungeonJournal)"
function Planner.SourceText(hint)
  if not hint then return nil end
  local label = hint.label or DependencyResolver.RouteLabels[hint.kind] or "Obtain"
  if hint.detail and hint.detail ~= "" then
    return label .. " - " .. hint.detail
  end
  return label
end

-- Plans a goal whose target is obtained rather than crafted with a known
-- recipe. The tree's root is the item itself and claims inventory like any
-- other node; it still expands into a craft when a learned recipe exists
-- (an OBTAIN_ITEM goal for a craftable item).
function Planner.EvaluateObtain(view, goal, deps, sources)
  local itemID, quantity = goal.target.itemID, goal.target.quantity
  local ctx = inventoryContext(deps)
  local tree = DependencyResolver.Resolve({ itemID = itemID, quantity = quantity }, ctx.resolverOpts(goal.routes))
  view.tree = tree
  view.fullTree = Planner.FullTree({ itemID = itemID, quantity = quantity }, goal, ctx)
  view.obtain = true
  view.sources = sources or {}
  local root = tree.root
  view.hint = root.hint or view.sources[1]
  view.sourceText = Planner.SourceText(view.hint)

  local plan
  if root.craft and root.missing > 0 then
    view.recipe = root.craft.recipe
    local direct = DependencyResolver.DirectCounts(tree)
    local err
    plan, err = CraftingEngine.BuildPlan(root.craft.recipe, root.missing, function(reagentID)
      return direct[reagentID] or 0
    end, { includeBank = ctx.includeBank, includeAlts = ctx.includeAlts })
    if not plan then
      view.readiness = Readiness.RECIPE_DATA_INVALID
      view.message = tostring(err)
      return view
    end
    plan.obtainOwned = root.owned
  else
    plan = Planner.ObtainPlan(root)
  end
  view.plan = plan

  -- A quest reward: the chain that leads to the quest becomes the plan, and
  -- what its open quests ask for hangs below the item.
  if root.missing > 0 and not root.craft then
    local questline = Planner.RewardQuestline(itemID, deps, { noRoute = root.noRoute })
    if questline then
      local QP = deps.quest
      local quest, line = questline.quest, questline.line
      local step = line and line.next or nil
      if not line then
        step = { type = "Quest", questID = quest.id, name = quest.name, questState = QP.State(quest.id) }
      end
      questline.step = step
      if step then
        questline.stepText = Planner.QuestStepText(QP, step)
      elseif line and line.complete then
        questline.stepText = string.format("%s is done - the reward should be in your bags", quest.name or "The quest")
      end
      local items = Planner.QuestlineItems(QP, line, quest.id)
      if #items > 0 then
        for _, child in ipairs(DependencyResolver.AttachItems(tree, root, items, ctx.resolverOpts(goal.routes))) do
          plan.materials[#plan.materials + 1] = nodeMaterial(child)
        end
        plan.totals.materialsMissing = countMissing(plan.materials)
      end
      questline.items = items
      view.questline = questline
      view.hint = view.hint or { kind = "quest", label = "Quest reward: " .. (quest.name or "?"), detail = quest.instance, questID = quest.id, quest = quest.name }
      root.route, root.routeSource, root.noRoute = "quest", "quest", nil
      root.hint = root.hint or view.hint
      view.sourceText = Planner.SourceText(view.hint)
      view.nextStep = questline.stepText
      view.waypoint = step and Planner.QuestWaypoint(QP, step) or nil
    end
  end
  view.progress = Planner.Progress(plan)
  view.inventoryNote = Planner.DescribeInventory(ctx.bankCounts, ctx.includeBank, ctx.includeAlts)

  local name = view.item and view.item.name or ("Item " .. itemID)
  if root.missing <= 0 then
    view.message = string.format("All %d x %s on hand.", quantity, name)
  elseif view.questline then
    local q, line = view.questline.quest, view.questline.line
    view.message = string.format("%d of %d on hand. Reward from %s%s.%s", root.owned, quantity, q.name or "a quest",
      line and string.format(" (%s, step %d of %d)", line.attune.name, math.min(line.done + 1, line.total), line.total) or "",
      view.questline.stepText and (" Next: " .. view.questline.stepText .. ".") or "")
  elseif root.craft then
    view.message = string.format("%d of %d on hand; %s %d more %s - %d material%s still missing.",
      root.owned, quantity, root.craft.combine and "combine" or "craft", root.craft.crafts, Planner.CraftNote(root.craft, deps),
      plan.totals.materialsMissing, plan.totals.materialsMissing == 1 and "" or "s")
  elseif root.noRoute then
    view.message = string.format("%d of %d on hand. %s is soulbound and no drop, quest or recipe is recorded for it yet.", root.owned, quantity, name)
  elseif view.sourceText then
    view.message = string.format("%d of %d on hand. %s", root.owned, quantity, view.sourceText)
  else
    view.message = string.format("%d of %d on hand. No source recorded yet: try the Auction House, or /fp sources once a vendor or loot table has been seen.", root.owned, quantity)
  end
  if goal.type == "CRAFT_ITEM" and not view.recipe then
    view.message = "No recipe recorded; planned as an item to obtain. " .. view.message
  elseif view.recipeStatus == "unlearned" and not root.craft and root.missing > 0 then
    local option = root.craftOption
    local recipe = view.recipe
    view.message = string.format("%s (%s) is not learned%s. ", recipe.name or "The recipe", recipe.professionName or "profession",
      option and option.reason and option.reason ~= "not learned" and (": " .. option.reason) or "") .. view.message
  end
  return view
end

-- "with Blacksmithing (Thandrel, 300; needs Plans: Sulfuron Hammer)" for a
-- craft node; names the crafter, the missing plans, or why nobody can craft it.
function Planner.CraftNote(craft, deps)
  if craft.combine then
    return "by using " .. (craft.recipe and craft.recipe.name or "the items together")
  end
  local text = "with " .. (craft.professionName or "a profession")
  local notes = {}
  if craft.learned then
    return text
  end
  if craft.unavailable then
    notes[#notes + 1] = craft.unavailable
  elseif craft.crafter then
    notes[#notes + 1] = (craft.crafter.isCurrent and "you" or craft.crafter.name) .. (craft.crafter.skillLevel and (" at " .. craft.crafter.skillLevel) or "")
  end
  if craft.teachItemID then
    local teach = deps and deps.item and deps.item.GetItem and deps.item.GetItem(craft.teachItemID)
    notes[#notes + 1] = "needs " .. (teach and teach.name or ("item " .. craft.teachItemID))
  elseif craft.recipe and craft.recipe.trainer and craft.recipe.trainer.name then
    local trainer = craft.recipe.trainer
    notes[#notes + 1] = string.format("trainer %s%s%s", trainer.name, trainer.zone and (", " .. trainer.zone) or "",
      trainer.rank and (", needs " .. trainer.rank) or "")
  elseif craft.static then
    notes[#notes + 1] = "learned from a trainer"
  end
  if #notes > 0 then
    text = text .. " (" .. table.concat(notes, "; ") .. ")"
  end
  return text
end

-- A plan with the item itself as its only line, shaped like a crafting plan
-- so every screen that reads plan.materials works unchanged.
function Planner.ObtainPlan(root)
  local owned = root.owned or 0
  local missing = root.missing or math.max(0, root.quantity - owned)
  local material = nodeMaterial(root)
  return {
    obtain = true, outputItemID = root.itemID, quantityWanted = root.quantity, craftsNeeded = 0,
    outputPerCraft = 1, outputPerCraftMax = 1, expectedOutput = 0,
    materials = { material },
    totals = { required = root.quantity, owned = math.min(owned, root.quantity), missing = missing, materialsMissing = missing > 0 and 1 or 0 },
    isComplete = missing == 0,
  }
end

-- { percent (0..100), ownedUnits, requiredUnits, materialsHave, materialsTotal }
function Planner.Progress(plan)
  if not plan then return nil end
  local required, owned = plan.totals.required, plan.totals.owned
  local have = 0
  for _, material in ipairs(plan.materials) do
    if material.missing == 0 then have = have + 1 end
  end
  return {
    percent = required > 0 and math.floor(owned * 100 / required + 0.5) or 100,
    ownedUnits = owned,
    requiredUnits = required,
    materialsHave = have,
    materialsTotal = #plan.materials,
  }
end

-- Source hints for the resolver: static data plus alt characters.
function Planner.SourceFinder(deps)
  local static = deps.catalogue and deps.catalogue.Sources
  local characters = deps.characters and deps.characters.Sources
  local sources = deps.sources and deps.sources.Sources
  local finders = {}
  if static then finders[#finders + 1] = static end
  if sources then finders[#finders + 1] = sources end
  if characters then finders[#finders + 1] = characters end
  if #finders == 0 then return nil end
  return function(itemID)
    local out = {}
    for _, fn in ipairs(finders) do
      local hints = Log.Try(fn, itemID)
      if type(hints) == "table" then
        for _, hint in ipairs(hints) do out[#out + 1] = hint end
      end
    end
    return out
  end
end

-- Recipe lookup used by the resolver: recorded recipes plus the catalogue.
function Planner.RecipeFinder(deps)
  return function(itemID)
    return Planner.Candidates(itemID, deps)
  end
end

-- Evaluates a list of goals in the given order; returns id -> view.
-- Goals share one allocation ledger, so inventory claimed by an earlier
-- (higher-priority) goal is not counted as owned by a later one.
function Planner.EvaluateAll(goals, deps)
  deps = deps or Planner.DefaultDeps()
  local ownLedger = deps.ledger == nil
  if ownLedger then
    deps.ledger = Allocation.New()
  end
  local views = {}
  for _, goal in ipairs(goals or {}) do
    views[goal.id] = Planner.Evaluate(goal, deps)
  end
  if ownLedger then
    deps.ledger = nil
  end
  return views
end

function Planner.DescribeInventory(counts, includeBank, includeAlts)
  local suffix = includeAlts and " Alts' snapshots count as owned." or ""
  if includeBank == false then
    return "Bags only (bank excluded in settings)." .. suffix
  end
  if not counts or counts.bankSource == nil or counts.bankSource == "none" then
    return "Bags only. Bank contents unknown until you visit a bank." .. suffix
  end
  if counts.bankSource == "live" then
    return "Bags + bank (bank open, live)." .. suffix
  end
  if counts.bankSource == "cached" then
    return string.format("Bags + bank snapshot (%s).", Util.FormatAgo(counts.bankScannedAt)) .. suffix
  end
  if counts.bankSource == "client" then
    return "Bags + bank as reported by the client." .. suffix
  end
  return "Bags + bank." .. suffix
end

-- Helpers the PlannerProfessions / PlannerQuests parts share with this
-- file. Not for other modules.
Planner.Shared = {
  inventoryContext = inventoryContext,
  isLearned = isLearned,
  buildCraftPlan = buildCraftPlan,
}
