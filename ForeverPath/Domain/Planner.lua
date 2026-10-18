-- Evaluates a goal against the providers and produces a view model for the UI.
--
-- Providers are injected (deps table) so the planner is testable with mocks:
--   deps.item        GetItem(itemID) -> { itemID, exists, loaded, name, link, icon, quality }
--   deps.profession  IsAvailable(), HasScanData(), GetScannedProfessions(),
--                    FindRecipesForItem(itemID) -> { { recipe = r, learned = bool }, ... },
--                    GetRecipe(recipeID, refresh) -> recipe
--   deps.inventory   GetCounts(itemID) -> { bags, bank, bankSource, bankScannedAt }
--   deps.data        Lookup(itemID) -> static recipe hints (future)
--   deps.settings    { includeBank = bool }
--   deps.ledger      Allocation ledger shared across goals (EvaluateAll creates one)
--   deps.characters  Sources(itemID) -> alt hints (optional)
--   deps.sources     Sources(itemID) -> vendor / drop / quest / gather hints (optional)
--
-- CRAFT_ITEM goals plan the recipe. OBTAIN_ITEM goals, and crafting goals
-- whose item has no recorded recipe but at least one known source, plan the
-- item itself as something to get (EvaluateObtain).
local _, ns = ...

local Status = ns.Status
local CraftingEngine = ns.CraftingEngine
local RecipeModel = ns.RecipeModel
local GoalModel = ns.GoalModel
local Util = ns.Util
local DependencyResolver = ns.DependencyResolver
local Allocation = ns.Allocation

local Planner = {}
ns.Planner = Planner

function Planner.DefaultDeps()
  return {
    item = ns.ItemProvider,
    profession = ns.ProfessionProvider,
    inventory = ns.InventoryProvider,
    data = ns.Data and ns.Data.Recipes,
    characters = ns.CharacterProvider,
    sources = ns.SourceProvider,
    price = ns.PriceProvider,
    attune = ns.AttuneProvider,
    quest = ns.QuestProvider,
    settings = ns.db and ns.db.settings or {},
  }
end

local function professionList(deps)
  local names = {}
  local ok, list = pcall(deps.profession.GetScannedProfessions)
  if ok and type(list) == "table" then
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
    if type(counts) == "table" and counts.bankSource and counts.bankSource ~= "none" and not ctx.bankNote then
      ctx.bankNote = counts
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
      soulbound = deps.data and deps.data.IsSoulbound or nil,
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
  if deps.data and deps.data.Lookup then
    local hints = deps.data.Lookup(itemID)
    if type(hints) == "table" then
      for _, hint in ipairs(hints) do
        if not (hint.recipeID and seen[hint.recipeID]) then
          local learned = false
          if hint.recipeID and not hint.combine and deps.profession and deps.profession.IsLearned then
            local ok, known = pcall(deps.profession.IsLearned, hint.recipeID)
            learned = ok and known == true
          end
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

-- Returns a view:
--   { goal, status, message, item, recipe, plan, tree, candidates, recipeIsLive, inventoryNote, progress }
function Planner.Evaluate(goal, deps)
  deps = deps or Planner.DefaultDeps()
  local view = { goal = goal, status = Status.OK, message = "", candidates = {} }

  if not goal or not GoalModel.IsSupported(goal.type) then
    view.status = Status.UNSUPPORTED_GOAL
    view.message = string.format("%s goals are planned for a later release.", goal and GoalModel.Types[goal.type] and GoalModel.Types[goal.type].label or "These")
    return view
  end
  if goal.type == "COMPLETE_ATTUNEMENT" then
    return Planner.EvaluateAttunement(view, goal, deps)
  end
  if goal.type == "LEARN_RECIPE" then
    return Planner.EvaluateLearn(view, goal, deps)
  end
  if goal.type == "REACH_SKILL" then
    return Planner.EvaluateSkill(view, goal, deps)
  end
  if goal.type == "COMPLETE_QUEST" then
    return Planner.EvaluateQuest(view, goal, deps)
  end

  local itemID = goal.target.itemID
  local quantity = goal.target.quantity

  -- Item information (may still be loading; that does not block recipe lookup).
  if deps.item and deps.item.GetItem then
    view.item = deps.item.GetItem(itemID)
  end
  view.item = view.item or { itemID = itemID, exists = nil, loaded = false }
  if view.item.exists == false then
    view.status = Status.ITEM_INVALID
    view.message = string.format("Item %d does not exist on this client. Check the item ID.", itemID)
    return view
  end
  if view.item.unavailable then
    view.status = Status.ITEM_UNAVAILABLE
    view.message = string.format("The server returned no data for item %d.", itemID)
    return view
  end

  if not deps.profession or not deps.profession.IsAvailable() then
    view.status = Status.PROVIDER_UNAVAILABLE
    view.message = "This client does not expose the profession API ForeverPath needs (C_TradeSkillUI). Crafting goals cannot be evaluated here."
    return view
  end

  local candidates = Planner.Candidates(itemID, deps)
  view.candidates = candidates
  local learned, unlearned = chooseCandidate(candidates)
  local obtain = goal.type == "OBTAIN_ITEM"
  local catalogue = deps.data and deps.data.IsAvailable and deps.data.IsAvailable() or false

  if #candidates == 0 and not obtain and not catalogue and not deps.profession.HasScanData() then
    view.status = Status.RECIPES_NOT_SCANNED
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
      view.status = Status.RECIPE_NOT_FOUND
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
    view.status = Status.RECIPE_DATA_INVALID
    view.message = string.format("Cached recipe data for %s is invalid (%s). Re-open the profession window to rescan.", recipe.name or "this recipe", reason)
    return view
  end

  local ctx = inventoryContext(deps)

  -- Resolve the full dependency tree first; it claims inventory through the
  -- ledger. The flat requirements plan then reuses the depth-1 allocations so
  -- both agree and nothing is counted twice.
  local tree = DependencyResolver.Resolve({ recipe = recipe, quantity = quantity }, ctx.resolverOpts(goal.routes))
  view.tree = tree
  view.fullTree = Planner.FullTree({ recipe = recipe, quantity = quantity }, goal, ctx)
  local direct = DependencyResolver.DirectCounts(tree)
  local plan, err = CraftingEngine.BuildPlan(recipe, quantity, function(reagentID)
    return direct[reagentID] or 0
  end, { includeBank = ctx.includeBank, includeAlts = ctx.includeAlts })
  if not plan then
    view.status = Status.RECIPE_DATA_INVALID
    view.message = tostring(err)
    return view
  end
  view.plan = plan
  view.inventoryNote = Planner.DescribeInventory(ctx.bankNote, ctx.includeBank, ctx.includeAlts)
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

-- Attunement goals: progress through the Attune bridge. The view carries
-- `attunement` (AttuneProvider.Progress), a synthetic `item` for icons and
-- names, `progress.percent`, and the next step as the message.
function Planner.EvaluateAttunement(view, goal, deps)
  local attune = deps.attune
  view.item = { name = goal.target.name, icon = goal.target.icon, quality = 1, loaded = true, exists = true }
  if not attune or not attune.IsAvailable() then
    view.status = Status.PROVIDER_UNAVAILABLE
    view.message = "Attunement chains come from the Attune addon. Install and enable Attune to plan this goal."
    return view
  end
  local progress = attune.Progress(goal.target.attuneID)
  if not progress then
    view.status = Status.ITEM_INVALID
    view.message = string.format("Attune has no attunement with id %s.", tostring(goal.target.attuneID))
    return view
  end
  view.attunement = progress
  view.item.name = progress.attune.name
  view.item.icon = progress.attune.icon or view.item.icon
  view.progress = { percent = progress.percent, stepsDone = progress.done, stepsTotal = progress.total }
  if progress.complete then
    view.message = string.format("Attuned: every step of %s is done.", progress.attune.name)
  elseif progress.next then
    view.message = string.format("%d of %d steps done. Next: %s", progress.done, progress.total, attune.StepText(progress.next))
  else
    view.message = string.format("%d of %d steps done.", progress.done, progress.total)
  end
  return view
end

---------------------------------------------------------------------------
-- Learn-recipe and reach-skill goals
---------------------------------------------------------------------------

-- A recipe by spell id: the catalogue first, then a recorded profession window.
function Planner.RecipeByID(spellID, deps)
  if deps.data and deps.data.Get then
    local ok, recipe = pcall(deps.data.Get, spellID)
    if ok and type(recipe) == "table" then return recipe end
  end
  if deps.data and deps.data.GetCombine then
    local ok, recipe = pcall(deps.data.GetCombine, spellID)
    if ok and type(recipe) == "table" then return recipe end
  end
  if deps.profession and deps.profession.GetRecipe then
    local ok, recipe = pcall(deps.profession.GetRecipe, spellID, false)
    if ok and type(recipe) == "table" then return recipe end
  end
  return nil
end

-- This character's standing in a profession: { name, skillLevel, maxSkillLevel, icon, source }
-- from the live profession list, else from a recorded window; nil without either.
function Planner.CurrentSkill(deps, professionName, professionID)
  local profession = deps.profession
  if not profession then return nil end
  local function matches(p)
    return (professionName and p.name == professionName) or (professionID and professionID ~= 0 and (p.skillLine == professionID or p.professionID == professionID))
  end
  if profession.GetCharacterProfessions then
    local ok, list = pcall(profession.GetCharacterProfessions)
    for _, p in ipairs(ok and list or {}) do
      if matches(p) then
        return { name = p.name, skillLevel = p.skillLevel or 0, maxSkillLevel = p.maxSkillLevel or 0, icon = (p.icon ~= 0) and p.icon or nil, source = "live" }
      end
    end
  end
  if profession.GetScannedProfessions then
    local ok, list = pcall(profession.GetScannedProfessions)
    for _, p in ipairs(ok and list or {}) do
      if matches(p) then
        return { name = p.name, skillLevel = p.skillLevel or 0, maxSkillLevel = p.maxSkillLevel or 0, source = "recorded" }
      end
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

-- Learn-recipe goals: done when this character knows the recipe; until then
-- the tree is the plans item to get (an obtain tree marked `learn`) or the
-- trainer visit as a single step, and the view says what blocks it (no
-- profession, skill too low) and who else on the account knows it.
function Planner.EvaluateLearn(view, goal, deps)
  local target = goal.target
  local recipe = Planner.RecipeByID(target.spellID, deps)
  view.item = { name = (recipe and recipe.name) or target.name or ("Recipe " .. tostring(target.spellID)), icon = (recipe and recipe.icon) or target.icon, quality = 1, loaded = true, exists = true }
  if not recipe then
    view.status = Status.ITEM_INVALID
    view.message = string.format("No recipe with spell id %s is in the catalogue or your recorded professions.", tostring(target.spellID))
    return view
  end
  local learned = false
  if deps.profession and deps.profession.IsLearned then
    local ok, known = pcall(deps.profession.IsLearned, target.spellID)
    learned = ok and known == true
  end
  local profession = Planner.CurrentSkill(deps, recipe.professionName, recipe.professionID)
  local need = recipe.skill and recipe.skill.min or 0
  local knownBy = {}
  if deps.characters and deps.characters.WhoKnows then
    local ok, names = pcall(deps.characters.WhoKnows, target.spellID)
    if ok and type(names) == "table" then knownBy = names end
  end
  local learn = {
    recipe = recipe, spellID = target.spellID, learned = learned, knownBy = knownBy,
    profession = profession, hasProfession = profession ~= nil, need = need,
    have = profession and profession.skillLevel or nil,
    skillOK = profession ~= nil and (profession.skillLevel or 0) >= need,
    kind = recipe.combine and "combine" or (recipe.teachItemID and "plans" or "trainer"),
    teachItemID = recipe.teachItemID, trainer = recipe.trainer,
  }
  view.learn = learn
  local name = recipe.name or "the recipe"
  if learned or learn.kind == "combine" then
    view.plan = Planner.StepPlan(true)
    view.progress = Planner.Progress(view.plan)
    view.message = learned and string.format("%s is already learned.", name) or string.format("%s is an item-use combine: there is nothing to learn.", name)
    view.nextStep = "Mark the goal complete"
    return view
  end

  local ctx = inventoryContext(deps)
  local tree
  if recipe.teachItemID then
    local root = { itemID = recipe.teachItemID, quantity = 1, learn = true, learnFor = recipe.name }
    tree = DependencyResolver.Resolve(root, ctx.resolverOpts(goal.routes))
    view.fullTree = Planner.FullTree(root, goal, ctx)
    view.obtain = true
    view.sources = Planner.Sources(recipe.teachItemID, deps)
    view.hint = tree.root.hint or view.sources[1]
    view.sourceText = Planner.SourceText(view.hint)
    view.plan = Planner.ObtainPlan(tree.root)
  else
    local step = { kind = "train", spellID = target.spellID, name = recipe.name, professionName = recipe.professionName, icon = recipe.icon,
      rank = need > 1 and need or nil, trainer = recipe.trainer }
    tree = DependencyResolver.Resolve({ step = step }, ctx.resolverOpts(goal.routes))
    view.plan = Planner.StepPlan(false)
  end
  view.tree = tree
  view.progress = Planner.Progress(view.plan)
  view.inventoryNote = Planner.DescribeInventory(ctx.bankNote, ctx.includeBank, ctx.includeAlts)

  local parts = {}
  local plansName
  if recipe.teachItemID then
    local info = deps.item and deps.item.GetItem and deps.item.GetItem(recipe.teachItemID) or nil
    plansName = (type(info) == "table" and info.name) or ("item " .. recipe.teachItemID)
  end
  if not profession then
    parts[#parts + 1] = string.format("You do not have %s on this character.", recipe.professionName or "the profession")
    learn.blocked = "profession"
  elseif not learn.skillOK then
    parts[#parts + 1] = string.format("Needs %s %d; you have %d.", recipe.professionName or "skill", need, profession.skillLevel or 0)
    learn.blocked = "skill"
  end
  if recipe.teachItemID then
    if tree.root.missing <= 0 then
      parts[#parts + 1] = string.format("%s is in your bags: read it to learn %s.", plansName, name)
      view.nextStep = "Read " .. plansName
    else
      parts[#parts + 1] = string.format("Get %s%s.", plansName, view.sourceText and (" - " .. view.sourceText) or (tree.root.noRoute and " (soulbound, no source recorded yet)" or ""))
      view.nextStep = "Get " .. plansName
    end
  else
    local trainer = recipe.trainer
    if trainer and trainer.name then
      parts[#parts + 1] = string.format("Train at %s%s%s.", trainer.name, trainer.zone and (", " .. trainer.zone) or "",
        trainer.cost and trainer.cost > 0 and (" for " .. Util.FormatMoney(trainer.cost)) or "")
      view.nextStep = "Train at " .. trainer.name
    else
      parts[#parts + 1] = string.format("Train at any %s trainer (the requirement is recorded on your next trainer visit).", recipe.professionName or "profession")
      view.nextStep = "Visit a " .. (recipe.professionName or "profession") .. " trainer"
    end
  end
  if learn.blocked == "skill" then
    view.nextStep = string.format("Reach %s %d", recipe.professionName or "skill", need)
  elseif learn.blocked == "profession" then
    view.nextStep = "Learn " .. (recipe.professionName or "the profession")
  end
  if #knownBy > 0 then
    parts[#parts + 1] = string.format("%s already know%s it.", Util.Join(knownBy), #knownBy == 1 and "s" or "")
  end
  view.message = table.concat(parts, " ")
  return view
end

-- Candidate recipes for a skill plan: every catalogue recipe of the
-- profession with its thresholds, learned flag, whether its requirement is
-- known (trainer recorded or plans), reagent cost (nil when any price is
-- unknown) and reagent count.
function Planner.SkillCandidates(deps, professionID)
  local Recipes = deps.data
  local out = {}
  if not Recipes or not Recipes.ForProfession or not Recipes.Get then return out end
  local priceOf = deps.price and deps.price.GetPrice or nil
  for _, spellID in ipairs(Recipes.ForProfession(professionID)) do
    local recipe = Recipes.Get(spellID)
    if recipe and recipe.skill then
      local learned = false
      if deps.profession and deps.profession.IsLearned then
        local ok, known = pcall(deps.profession.IsLearned, spellID)
        learned = ok and known == true
      end
      local cost, weight, known = 0, 0, true
      for _, reagent in ipairs(recipe.reagents or {}) do
        weight = weight + reagent.quantity
        local info = priceOf and priceOf(reagent.itemID) or nil
        if info and tonumber(info.copper) then
          cost = cost + info.copper * reagent.quantity
        else
          known = false
        end
      end
      -- The requirement is only known from a recorded trainer visit or from
      -- a pattern whose item data carries it; a pattern at "1" is unknown
      -- (the item table is partial) and must not be planned as learnable.
      local learnable = recipe.skill.source == "trainer" or (recipe.teachItemID ~= nil and (recipe.skill.min or 0) > 1)
      out[#out + 1] = {
        spellID = spellID, recipe = recipe, learned = learned, skill = recipe.skill,
        learnable = learnable,
        cost = known and cost or nil, weight = weight,
      }
    end
  end
  return out
end

-- Flat requirements of a skill tree: the reagents (and plans) directly under
-- every craft node, merged by item, in the shape of a crafting plan.
function Planner.SkillMaterials(tree, plan)
  local materials, byItem = {}, {}
  for _, craft in ipairs(tree.root.children) do
    for _, child in ipairs(craft.children) do
      if child.itemID then
        local m = byItem[child.itemID]
        if not m then
          m = { itemID = child.itemID, perCraft = 0, required = 0, owned = 0, ownedBags = 0, ownedBank = nil, ownedAlts = nil, missing = 0, reserved = 0, learn = child.learn or nil }
          byItem[child.itemID] = m
          materials[#materials + 1] = m
        end
        m.required = m.required + child.quantity
        m.owned = m.owned + (child.owned or 0)
        m.ownedBags = m.ownedBags + (child.ownedBags or 0)
        if child.ownedBank then m.ownedBank = (m.ownedBank or 0) + child.ownedBank end
        if child.ownedAlts then m.ownedAlts = (m.ownedAlts or 0) + child.ownedAlts end
        m.altSources = m.altSources or child.altSources
        m.bankSource = m.bankSource or child.bankSource
        m.reserved = m.reserved + (child.reserved or 0)
        m.missing = m.missing + (child.missing or 0)
      end
    end
  end
  table.sort(materials, function(a, b)
    if a.missing ~= b.missing then return a.missing > b.missing end
    return a.itemID < b.itemID
  end)
  local totals = { required = 0, owned = 0, missing = 0, materialsMissing = 0 }
  for _, m in ipairs(materials) do
    totals.required = totals.required + m.required
    totals.owned = totals.owned + math.min(m.owned, m.required)
    totals.missing = totals.missing + m.missing
    if m.missing > 0 then totals.materialsMissing = totals.materialsMissing + 1 end
  end
  local stepsMissing = 0
  for _, node in pairs(tree.byKey) do
    if node.step and node.depth > 0 and node.missing > 0 then stepsMissing = stepsMissing + 1 end
  end
  return {
    skill = true, craftsNeeded = plan.total or 0, outputPerCraft = 1, outputPerCraftMax = 1, expectedOutput = 0, quantityWanted = plan.to,
    materials = materials, totals = totals, stepsMissing = stepsMissing,
    isComplete = totals.missing == 0 and stepsMissing == 0 and #materials > 0,
  }
end

-- Reach-skill goals: progress is the skill itself; the plan is which learned
-- recipes to craft how many times (SkillPlanner), laid out as a tree whose
-- craft nodes are done for the points, so only their reagents are needed.
function Planner.EvaluateSkill(view, goal, deps)
  local target = goal.target
  local Recipes = deps.data
  local professionID = target.professionID
  if (not professionID or professionID == 0) and Recipes and Recipes.ProfessionID then
    professionID = Recipes.ProfessionID(target.professionName)
  end
  local profession = Planner.CurrentSkill(deps, target.professionName, professionID)
  view.item = { name = target.professionName, icon = (profession and profession.icon) or target.icon, quality = 1, loaded = true, exists = true }
  if not profession then
    view.status = Status.PROFESSION_MISSING
    view.message = string.format("%s is not one of this character's professions.", target.professionName or "That profession")
    return view
  end
  local current = profession.skillLevel or 0
  local start = tonumber(target.startRank) or current
  if start > current then start = current end
  local rank = target.rank
  local percent
  if current >= rank then percent = 100
  elseif rank > start then percent = math.floor(math.max(0, current - start) * 100 / (rank - start) + 0.5)
  else percent = 0 end
  local skill = {
    professionName = profession.name or target.professionName, professionID = professionID, current = current, target = rank, start = start,
    max = profession.maxSkillLevel or 0, percent = percent, reached = current >= rank, icon = profession.icon,
    capBlocked = (profession.maxSkillLevel or 0) > 0 and rank > profession.maxSkillLevel,
  }
  view.skill = skill
  view.progress = { percent = percent, ownedUnits = math.min(current, rank), requiredUnits = rank, materialsHave = 0, materialsTotal = 0 }
  if skill.reached then
    view.plan = Planner.StepPlan(true)
    view.message = string.format("%s %d reached (you are at %d).", skill.professionName, rank, current)
    view.nextStep = "Mark the goal complete"
    return view
  end
  local scanned = false
  if deps.profession and deps.profession.GetScannedProfessions then
    local ok, list = pcall(deps.profession.GetScannedProfessions)
    for _, p in ipairs(ok and list or {}) do
      if p.name == skill.professionName or (professionID and p.professionID == professionID) then scanned = true end
    end
  end
  skill.scanned = scanned

  local candidates = Planner.SkillCandidates(deps, professionID)
  local plan = ns.SkillPlanner.Plan(current, rank, candidates)
  view.skillPlan = plan
  local crafts = {}
  for _, entry in ipairs(plan.list) do
    crafts[#crafts + 1] = { recipe = entry.recipe, crafts = entry.crafts, learned = entry.learned, from = entry.from, to = entry.to }
  end
  local ctx = inventoryContext(deps)
  local step = { kind = "skill", name = string.format("%s %d", skill.professionName, rank), professionName = skill.professionName, professionID = professionID, icon = profession.icon }
  local tree = DependencyResolver.Resolve({ step = step, crafts = crafts, key = "skill:" .. tostring(professionID or skill.professionName) }, ctx.resolverOpts(goal.routes))
  view.tree = tree
  view.fullTree = Planner.FullTree({ step = step, crafts = crafts, key = tree.root.key }, goal, ctx)
  view.plan = Planner.SkillMaterials(tree, plan)
  view.progress.materialsHave = #view.plan.materials - view.plan.totals.materialsMissing
  view.progress.materialsTotal = #view.plan.materials
  view.inventoryNote = Planner.DescribeInventory(ctx.bankNote, ctx.includeBank, ctx.includeAlts)

  local parts = {}
  if skill.capBlocked then
    parts[#parts + 1] = string.format("Your %s cap is %d: a trainer has to raise it before %d is reachable.", skill.professionName, profession.maxSkillLevel, rank)
  end
  if #plan.list > 0 then
    local names = {}
    for _, entry in ipairs(plan.list) do
      names[#names + 1] = string.format("%d x %s (%d-%d%s)", entry.crafts, entry.recipe.name or "?", entry.from, entry.to, entry.learned and "" or ", learn it first")
    end
    parts[#parts + 1] = string.format("%d to %d: about %d craft%s - %s.", current, plan.covered and rank or plan.list[#plan.list].to, plan.total, plan.total == 1 and "" or "s", Util.Join(names))
  end
  if not plan.covered then
    local gap = plan.gaps[1]
    parts[#parts + 1] = string.format("No recipe you know%s covers %d-%d%s.", scanned and " (or could learn with a recorded requirement)" or "", gap.from, gap.to,
      scanned and "; visit a trainer or find a pattern for that range" or "")
  end
  if not scanned then
    parts[#parts + 1] = string.format("Open your %s window once so ForeverPath knows which recipes you have.", skill.professionName)
  end
  view.message = table.concat(parts, " ")
  local first = plan.list[1]
  if first then
    view.nextStep = string.format("Craft %d x %s", first.crafts, first.recipe.name or "?")
  elseif not scanned then
    view.nextStep = "Open the " .. skill.professionName .. " window"
  else
    view.nextStep = "Find a recipe for " .. current .. "+"
  end
  return view
end

-- Quest goals: the chain to do (journal prerequisites, then the quest) with
-- each quest's live state. Progress counts completed quests in the chain
-- plus the objectives of the one in the log. The view carries
-- `quest = { entry, state, chain, next, levelBlocked, playerLevel }`.
function Planner.EvaluateQuest(view, goal, deps)
  local QP = deps.quest
  local target = goal.target
  local questID = target.questID
  view.item = { name = target.name or ("Quest " .. tostring(questID)), icon = target.icon or (QP and QP.ICON) or nil, quality = 1, loaded = true, exists = true }
  if not QP or not QP.IsAvailable() then
    view.status = Status.PROVIDER_UNAVAILABLE
    view.message = "This client does not expose the quest API ForeverPath needs (C_QuestLog)."
    return view
  end
  local entry = QP.Get(questID)
  local name = QP.Name(questID)
  view.item.name = name
  local chain, nextStep = QP.Chain(questID)
  local state = chain[#chain].state
  local playerLevel = QP.PlayerLevel()
  local requires = entry and entry.requires or nil
  local quest = {
    questID = questID, entry = entry, state = state, chain = chain, next = nextStep, playerLevel = playerLevel,
    levelBlocked = requires ~= nil and requires > playerLevel, requires = requires,
    label = QP.StateLabel(state, entry, playerLevel),
  }
  view.quest = quest
  if state.ready then view.item.icon = QP.ICON_READY end

  local done, partial = 0, 0
  for _, step in ipairs(chain) do
    if step.state.completed then done = done + 1
    elseif step == nextStep and step.state.inLog then partial = step.state.fraction end
  end
  local percent = #chain > 0 and math.floor((done + partial) * 100 / #chain + 0.5) or 0
  if state.completed then percent = 100 end
  view.progress = { percent = percent, ownedUnits = done, requiredUnits = #chain, materialsHave = done, materialsTotal = #chain }
  view.plan = Planner.StepPlan(state.completed)

  local function where(step)
    local e = step.entry
    if not e then return nil end
    if e.pickup then return e.pickup end
    if e.start and e.start.label then return e.start.label end
    return e.location
  end
  if state.completed then
    view.message = string.format("%s is completed.", name)
    view.nextStep = "Mark the goal complete"
  elseif quest.levelBlocked then
    view.message = string.format("Needs level %d; you are %d.", requires, playerLevel)
    view.nextStep = string.format("Reach level %d", requires)
  elseif nextStep and nextStep ~= chain[#chain] then
    local s = nextStep.state
    if s.ready then
      view.message = string.format("First turn in %s%s.", nextStep.name, nextStep.entry and nextStep.entry.turnin and (" at " .. nextStep.entry.turnin) or "")
      view.nextStep = "Turn in " .. nextStep.name
    elseif s.inLog then
      local progress = QP.ObjectiveText(s)
      view.message = string.format("First finish %s%s.", nextStep.name, progress ~= "" and (": " .. progress) or "")
      view.nextStep = "Finish " .. nextStep.name
    else
      local pickup = where(nextStep)
      view.message = string.format("First pick up %s%s (required before %s).", nextStep.name, pickup and (" from " .. pickup) or "", name)
      view.nextStep = "Pick up " .. nextStep.name
    end
  elseif state.ready then
    view.message = string.format("Ready to turn in%s.", entry and entry.turnin and (" at " .. entry.turnin) or "")
    view.nextStep = "Turn in " .. name
  elseif state.inLog then
    local progress = QP.ObjectiveText(state)
    view.message = string.format("In your log%s.", progress ~= "" and (": " .. progress) or (entry and entry.objective and (": " .. entry.objective) or ""))
    view.nextStep = "Finish " .. name
  else
    local pickup = where(chain[#chain])
    view.message = string.format("Pick up %s%s.", name, pickup and (" from " .. pickup) or "")
    if entry and entry.objective then view.message = view.message .. " " .. entry.objective end
    view.nextStep = "Pick up " .. name
  end
  return view
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
      view.status = Status.RECIPE_DATA_INVALID
      view.message = tostring(err)
      return view
    end
    plan.obtainOwned = root.owned
  else
    plan = Planner.ObtainPlan(root)
  end
  view.plan = plan
  view.progress = Planner.Progress(plan)
  view.inventoryNote = Planner.DescribeInventory(ctx.bankNote, ctx.includeBank, ctx.includeAlts)

  local name = view.item and view.item.name or ("Item " .. itemID)
  if root.missing <= 0 then
    view.message = string.format("All %d x %s on hand.", quantity, name)
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
  local material = {
    itemID = root.itemID, perCraft = 1, required = root.quantity,
    owned = owned, ownedBags = root.ownedBags, ownedBank = root.ownedBank, ownedAlts = root.ownedAlts,
    altSources = root.altSources, bankSource = root.bankSource, reserved = root.reserved, missing = missing,
  }
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
  local static = deps.data and deps.data.Sources
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
      local ok, hints = pcall(fn, itemID)
      if ok and type(hints) == "table" then
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
