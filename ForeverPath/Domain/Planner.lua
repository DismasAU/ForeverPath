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
    reputation = ns.ReputationProvider,
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
  if goal.type == "REACH_REPUTATION" then
    return Planner.EvaluateReputation(view, goal, deps)
  end
  if goal.type == "APPLY_ENCHANT" then
    return Planner.EvaluateEnchant(view, goal, deps)
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

-- "a Tailoring trainer", "an Enchanting trainer".
local function article(word)
  return (type(word) == "string" and word:match("^[AEIOUaeiou]")) and "an" or "a"
end

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

-- What each of this character's professions can train: recipes taught by a
-- trainer (recorded, or classic data) that it has not learned, at or below
-- its skill ("now") or within the next `window` points ("soon").
-- { { profession, skill, max, scanned, now = { { recipe, rank, cost, trainer, zone } }, soon = {...}, cost } }
Planner.TRAIN_WINDOW = 25

function Planner.Trainable(deps, professionName, window)
  deps = deps or Planner.DefaultDeps()
  window = window or Planner.TRAIN_WINDOW
  local data = deps.data
  local profession = deps.profession
  local out = {}
  if not (data and data.ForProfession and profession and profession.GetCharacterProfessions) then return out end
  local ok, list = pcall(profession.GetCharacterProfessions)
  local scanned = {}
  if profession.GetScannedProfessions then
    local okScan, scans = pcall(profession.GetScannedProfessions)
    for _, p in ipairs(okScan and scans or {}) do scanned[p.name] = true end
  end
  for _, p in ipairs(ok and list or {}) do
    if not professionName or string.lower(p.name or "") == string.lower(professionName) then
      local skillLine = p.skillLine or (data.ProfessionID and data.ProfessionID(p.name))
      local current = p.skillLevel or 0
      local entry = { profession = p.name, skill = current, max = p.maxSkillLevel or 0, scanned = scanned[p.name] == true, now = {}, soon = {}, cost = 0 }
      for _, spellID in ipairs(skillLine and data.ForProfession(skillLine) or {}) do
        local recipe = data.Get(spellID)
        local trainer = recipe and recipe.trainer
        if trainer and not (profession.IsLearned and profession.IsLearned(spellID)) then
          local rank = tonumber(trainer.rank) or (recipe.skill and recipe.skill.min) or 0
          local row = { recipe = recipe, rank = rank, cost = tonumber(trainer.cost) or 0, trainer = trainer.name, zone = trainer.zone, classic = trainer.classic }
          if rank <= current then
            entry.now[#entry.now + 1] = row
            entry.cost = entry.cost + row.cost
          elseif rank <= current + window then
            entry.soon[#entry.soon + 1] = row
          end
        end
      end
      local function byRank(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return (a.recipe.name or "") < (b.recipe.name or "")
      end
      table.sort(entry.now, byRank)
      table.sort(entry.soon, byRank)
      out[#out + 1] = entry
    end
  end
  return out
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

---------------------------------------------------------------------------
-- Questlines (quest goals and quest-reward items)
---------------------------------------------------------------------------
local QUEST_STEP = { Quest = true, ["Pick Up"] = true, ["Turn In"] = true }

-- "Pick up Elemental Aid from Prate Cloudseer in Thousand Needles" for a
-- questline step (or a bare quest: { questID, name }).
function Planner.QuestStepText(QP, step)
  local t = step.type or "Quest"
  if t == "Level" then return "Reach level " .. tostring(step.wowheadID or step.name) end
  if t == "Item" then
    return string.format("Collect %d x %s", step.count or 1, step.name or "item") .. (step.location and (" - " .. step.location) or "")
  end
  if not QUEST_STEP[t] then return (step.typeLabel or t) .. ": " .. tostring(step.name) end
  local questID = step.questID
  local s = step.questState or (questID and QP.State(questID)) or {}
  local name = step.name or (questID and QP.Name(questID)) or "the quest"
  local entry = step.entry or (questID and QP.Get and QP.Get(questID)) or nil
  local fallbackZone = step.location or (entry and entry.location) or nil
  if s.ready or (t == "Turn In" and s.inLog) then
    local turnin = questID and QP.Turnin and QP.Turnin(questID) or nil
    local zone = (turnin and turnin.zone) or fallbackZone
    return "Turn in " .. name .. (turnin and turnin.name and (" to " .. turnin.name) or "") .. (zone and (" in " .. zone) or "")
  elseif s.inLog then
    local progress = QP.ObjectiveText(s)
    return "Finish " .. name .. (progress ~= "" and (": " .. progress) or "")
  end
  local giver = questID and QP.Giver and QP.Giver(questID) or nil
  local zone = (giver and giver.zone) or fallbackZone
  return "Pick up " .. name .. (giver and giver.name and (" from " .. giver.name) or "") .. (zone and (" in " .. zone) or "")
end

-- The map point for a questline step, when one is recorded.
function Planner.QuestWaypoint(QP, step)
  if not step or not QUEST_STEP[step.type or "Quest"] or not step.questID or not QP.Waypoint then return nil end
  return QP.Waypoint(step.questID)
end

-- Items the open quests of a line (or one quest) still ask for:
-- { { itemID, quantity, name, questName } }, the same item summed across quests.
function Planner.QuestlineItems(QP, line, questID)
  local out, byItem, seenQuest = {}, {}, {}
  if not QP.RequiredItems then return out end
  local function add(qid, qname)
    if seenQuest[qid] then return end
    seenQuest[qid] = true
    for _, item in ipairs(QP.RequiredItems(qid)) do
      if item.itemID then
        local row = byItem[item.itemID]
        if not row then
          row = { itemID = item.itemID, quantity = 0, name = item.name, questName = qname }
          byItem[item.itemID] = row
          out[#out + 1] = row
        end
        row.quantity = row.quantity + (item.count or 1)
      end
    end
  end
  if line then
    for _, step in ipairs(line.steps) do
      if QUEST_STEP[step.type] and step.questID and not step.done and not (step.questState and step.questState.completed) then
        add(step.questID, step.name)
      end
    end
  elseif questID then
    add(questID, QP.Name(questID))
  end
  return out
end

-- 1 bind on pickup, 2 on equip, 3 on use, 4 quest item; nil when unknown.
function Planner.BindType(itemID, deps)
  local Compat = ns.Compat
  if Compat and Compat.GetItemInfo then
    local ok, name, _, _, _, _, _, _, _, _, _, _, _, _, bind = pcall(Compat.GetItemInfo, itemID)
    if ok and name and tonumber(bind) then return tonumber(bind) end
  end
  local data = deps and deps.data
  return data and data.ItemBind and data.ItemBind(itemID) or nil
end

-- The quest that rewards an item (for this faction) and the chain that
-- leads to it: { quest = entry, line }, or nil. Classic-db quests only
-- count for items that cannot be bought (bind on pickup, quest items) or
-- that have no other route (opts.noRoute): a potion some old quest also
-- rewards is still bought, not quested for.
function Planner.RewardQuestline(itemID, deps, opts)
  local QP = deps.quest
  if not (QP and QP.IsAvailable and QP.IsAvailable() and QP.QuestsRewarding) then return nil end
  local faction = QP.Faction and QP.Faction() or nil
  local first
  local classicOK
  local function allowClassic()
    if classicOK == nil then
      local bind = Planner.BindType(itemID, deps)
      classicOK = (bind == 1 or bind == 4) or (opts and opts.noRoute) or false
    end
    return classicOK
  end
  for _, entry in ipairs(QP.QuestsRewarding(itemID)) do
    if entry.classic and not allowClassic() then
      -- skipped: buyable, and something else sells or drops it
    elseif not faction or not entry.faction or entry.faction == "Both" or entry.faction == faction then
      local line = QP.Questline and QP.Questline(entry.id) or nil
      if line then return { quest = entry, line = line } end
      first = first or { quest = entry }
    end
  end
  return first
end

local function lowerFirst(text)
  return text:sub(1, 1):lower() .. text:sub(2)
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
      view.nextStep = "Visit " .. article(recipe.professionName) .. " " .. (recipe.professionName or "profession") .. " trainer"
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

-- Enchant goals: cast an enchant (or an Engineering tinker) a number of
-- times. Casts already seen count towards the goal; for the rest the tree is
-- the enchant itself with its formula or trainer visit (while unlearned) and
-- the reagents below it, and the plan is those reagents. The view carries
-- `enchant = { recipe, spellID, learned, knownBy, profession, hasProfession,
-- need, have, skillOK, blocked, kind, teachItemID, trainer, casts, quantity,
-- remaining }`.
function Planner.EvaluateEnchant(view, goal, deps)
  local target = goal.target
  local recipe = Planner.RecipeByID(target.spellID, deps)
  view.item = { name = (recipe and recipe.name) or target.name or ("Enchant " .. tostring(target.spellID)), icon = (recipe and recipe.icon) or target.icon, quality = 1, loaded = true, exists = true }
  if not recipe then
    view.status = Status.ITEM_INVALID
    view.message = string.format("No enchant with spell id %s is in the catalogue or your recorded professions.", tostring(target.spellID))
    return view
  end
  if not recipe.enchant then
    view.status = Status.ITEM_INVALID
    view.message = string.format("%s makes an item: add it as a crafting goal instead.", recipe.name or "That recipe")
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
  local quantity = target.quantity or 1
  local casts = math.min(tonumber(target.casts) or 0, quantity)
  local enchant = {
    recipe = recipe, spellID = target.spellID, learned = learned, knownBy = knownBy,
    profession = profession, hasProfession = profession ~= nil, need = need,
    have = profession and profession.skillLevel or nil,
    skillOK = profession ~= nil and (profession.skillLevel or 0) >= need,
    kind = recipe.teachItemID and "plans" or "trainer",
    teachItemID = recipe.teachItemID, trainer = recipe.trainer,
    casts = casts, quantity = quantity, remaining = quantity - casts,
  }
  if not profession then
    enchant.blocked = "profession"
  elseif not enchant.skillOK then
    enchant.blocked = "skill"
  end
  view.enchant = enchant
  view.recipe = recipe
  local name = recipe.name or "the enchant"
  if enchant.remaining <= 0 then
    view.plan = Planner.StepPlan(true)
    view.progress = Planner.Progress(view.plan)
    view.message = string.format("%s cast %d time%s.", name, casts, casts == 1 and "" or "s")
    view.nextStep = "Mark the goal complete"
    return view
  end

  local ctx = inventoryContext(deps)
  local root = { recipe = recipe, quantity = enchant.remaining, learned = learned }
  local tree = DependencyResolver.Resolve(root, ctx.resolverOpts(goal.routes))
  view.tree = tree
  view.fullTree = Planner.FullTree(root, goal, ctx)
  local direct = DependencyResolver.DirectCounts(tree)
  local plan, err = CraftingEngine.BuildPlan(recipe, enchant.remaining, function(reagentID)
    return direct[reagentID] or 0
  end, { includeBank = ctx.includeBank, includeAlts = ctx.includeAlts })
  if not plan then
    view.status = Status.RECIPE_DATA_INVALID
    view.message = tostring(err)
    return view
  end
  plan.enchant = true
  plan.castsDone = casts
  -- The reagents can all be in the bags while the formula or the training is not.
  plan.stepsMissing = 0
  local formulaNode
  for _, child in ipairs(tree.root.children) do
    if child.learn then formulaNode = child end
    if (child.learn or child.step) and child.missing > 0 then plan.stepsMissing = plan.stepsMissing + 1 end
  end
  plan.isComplete = plan.totals.missing == 0 and plan.stepsMissing == 0
  view.plan = plan
  view.progress = Planner.Progress(plan)
  if casts > 0 then
    -- Casts done count as finished; the reagents in hand cover the rest.
    view.progress.percent = math.floor((casts * 100 + (view.progress.percent or 0) * enchant.remaining) / quantity + 0.5)
  end
  view.inventoryNote = Planner.DescribeInventory(ctx.bankNote, ctx.includeBank, ctx.includeAlts)

  local parts = {}
  if casts > 0 then
    parts[#parts + 1] = string.format("%d of %d cast%s done.", casts, quantity, quantity == 1 and "" or "s")
  end
  if enchant.blocked == "profession" then
    parts[#parts + 1] = string.format("You do not have %s on this character.", recipe.professionName or "the profession")
  elseif enchant.blocked == "skill" then
    parts[#parts + 1] = string.format("Needs %s %d; you have %d.", recipe.professionName or "skill", need, profession.skillLevel or 0)
  end
  if not learned then
    if formulaNode then
      local info = deps.item and deps.item.GetItem and deps.item.GetItem(recipe.teachItemID) or nil
      local plansName = (type(info) == "table" and info.name) or ("item " .. recipe.teachItemID)
      if formulaNode.missing <= 0 then
        parts[#parts + 1] = string.format("%s is in your bags: read it to learn %s.", plansName, name)
        view.nextStep = "Read " .. plansName
      else
        local sourceText = Planner.SourceText(formulaNode.hint)
        parts[#parts + 1] = string.format("Get %s%s.", plansName, sourceText and (" - " .. sourceText) or (formulaNode.noRoute and " (soulbound, no source recorded yet)" or ""))
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
        view.nextStep = "Visit " .. article(recipe.professionName) .. " " .. (recipe.professionName or "profession") .. " trainer"
      end
    end
  end
  if plan.totals.missing == 0 then
    parts[#parts + 1] = string.format("All materials for %d cast%s are on hand.", enchant.remaining, enchant.remaining == 1 and "" or "s")
  else
    parts[#parts + 1] = string.format("%d material%s still missing for %d cast%s.",
      plan.totals.materialsMissing, plan.totals.materialsMissing == 1 and "" or "s", enchant.remaining, enchant.remaining == 1 and "" or "s")
  end
  if not view.nextStep then
    if plan.totals.missing == 0 then
      view.nextStep = string.format("Cast %d x %s", enchant.remaining, name)
    else
      local top
      for _, material in ipairs(plan.materials) do
        if material.missing > 0 and (not top or material.missing > top.missing) then top = material end
      end
      local info = deps.item and deps.item.GetItem and deps.item.GetItem(top.itemID) or nil
      view.nextStep = string.format("Obtain %d x %s", top.missing, (type(info) == "table" and info.name) or ("item " .. top.itemID))
    end
  end
  if enchant.blocked == "skill" then
    view.nextStep = string.format("Reach %s %d", recipe.professionName or "skill", need)
  elseif enchant.blocked == "profession" then
    view.nextStep = "Learn " .. (recipe.professionName or "the profession")
  end
  if not learned and #knownBy > 0 then
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
  local line = QP.Questline and QP.Questline(questID) or nil
  local state = chain[#chain].state
  local playerLevel = QP.PlayerLevel()
  local requires = entry and entry.requires or nil
  local quest = {
    questID = questID, entry = entry, state = state, chain = chain, next = nextStep, playerLevel = playerLevel,
    levelBlocked = requires ~= nil and requires > playerLevel, requires = requires,
    label = QP.StateLabel(state, entry, playerLevel), line = line,
  }
  view.quest = quest
  if state.ready then view.item.icon = QP.ICON_READY end
  if line and line.next and line.next ~= line.target and not state.inLog and not state.completed and quest.label == "Available" then
    quest.label = "Locked"
  end

  -- Progress: the chain's steps when Attune knows it, else the journal chain.
  if line then
    view.progress = { percent = line.percent, ownedUnits = line.done, requiredUnits = line.total, materialsHave = line.done, materialsTotal = line.total }
  else
    local done, partial = 0, 0
    for _, step in ipairs(chain) do
      if step.state.completed then done = done + 1
      elseif step == nextStep and step.state.inLog then partial = step.state.fraction end
    end
    local percent = #chain > 0 and math.floor((done + partial) * 100 / #chain + 0.5) or 0
    view.progress = { percent = percent, ownedUnits = done, requiredUnits = #chain, materialsHave = done, materialsTotal = #chain }
  end
  if state.completed then view.progress.percent = 100 end

  -- What the open quests of the chain ask for, laid out like reagents so the
  -- requirement rows, the tree and the shopping list carry them.
  local items = (not state.completed) and Planner.QuestlineItems(QP, line, questID) or {}
  local ctx = inventoryContext(deps)
  local tree = DependencyResolver.Resolve({ key = "quest:" .. tostring(questID),
    step = { kind = "quest", questID = questID, name = name, icon = view.item.icon, items = items } }, ctx.resolverOpts(goal.routes))
  view.tree = tree
  view.plan = Planner.StepItemsPlan(tree, state.completed)
  view.inventoryNote = Planner.DescribeInventory(ctx.bankNote, ctx.includeBank, ctx.includeAlts)
  quest.items = items

  local function where(step)
    local e = step.entry
    if not e then return nil end
    if e.pickup then return e.pickup end
    if e.start and e.start.label then return e.start.label end
    return e.location
  end
  local lineStep = line and line.next or nil
  if state.completed then
    view.message = string.format("%s is completed.", name)
    view.nextStep = "Mark the goal complete"
  elseif quest.levelBlocked then
    view.message = string.format("Needs level %d; you are %d.", requires, playerLevel)
    view.nextStep = string.format("Reach level %d", requires)
  elseif lineStep then
    local text = Planner.QuestStepText(QP, lineStep)
    view.nextStep = text
    view.waypoint = Planner.QuestWaypoint(QP, lineStep)
    if lineStep == line.target then
      view.message = text .. "."
    else
      view.message = string.format("First %s (step %d of %d of %s, before %s).", lowerFirst(text), math.min(line.done + 1, line.total), line.total, line.attune.name, name)
    end
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
    local turnin = (entry and entry.turnin) or (QP.Turnin and QP.Turnin(questID) or nil)
    local at = type(turnin) == "table" and turnin.label or turnin
    view.message = string.format("Ready to turn in%s.", at and (" at " .. at) or "")
    view.nextStep = "Turn in " .. name
    view.waypoint = Planner.QuestWaypoint(QP, { type = "Quest", questID = questID })
  elseif state.inLog then
    local progress = QP.ObjectiveText(state)
    view.message = string.format("In your log%s.", progress ~= "" and (": " .. progress) or (entry and entry.objective and (": " .. entry.objective) or ""))
    view.nextStep = "Finish " .. name
  else
    local pickup = where(chain[#chain])
    if pickup then
      view.message = string.format("Pick up %s from %s.", name, pickup)
      view.nextStep = "Pick up " .. name
    else
      -- No journal text: the recorded giver (quest facts) names the place.
      local text = Planner.QuestStepText(QP, { type = "Quest", questID = questID, name = name, questState = state })
      view.message = text .. "."
      view.nextStep = text
    end
    if entry and entry.objective then view.message = view.message .. " " .. entry.objective end
    view.waypoint = Planner.QuestWaypoint(QP, { type = "Quest", questID = questID })
  end
  return view
end

-- Reputation goals: progress is the standing itself (anchored at the value
-- when the goal was made); the view carries `reputation = { record,
-- progress, quests, rewards }` and names the first open quest that gives
-- reputation as the next step.
function Planner.EvaluateReputation(view, goal, deps)
  local RP = deps.reputation
  local target = goal.target
  view.item = { name = target.name or ("Faction " .. tostring(target.factionID)), icon = target.icon or (RP and RP.ICON) or nil, quality = 1, loaded = true, exists = true }
  if not RP or not RP.IsAvailable() then
    view.status = Status.PROVIDER_UNAVAILABLE
    view.message = "This client does not expose the faction API ForeverPath needs."
    return view
  end
  local progress = RP.Progress(target.factionID, target.standing, target.startValue)
  if not progress then
    view.status = Status.ITEM_INVALID
    view.message = string.format("%s is not in your reputation list yet.", target.name or ("Faction " .. tostring(target.factionID)))
    return view
  end
  local record = progress.record
  view.item.name = record.name
  local quests = RP.QuestsFor(record.name, record.factionID or goal.target.factionID)
  local rewards = RP.Rewards(target.factionID)
  view.reputation = { record = record, progress = progress, quests = quests, rewards = rewards, targetLabel = progress.targetLabel }
  view.progress = { percent = progress.percent, ownedUnits = math.max(0, (record.value or 0) - progress.start), requiredUnits = math.max(0, progress.targetMin - progress.start), materialsHave = 0, materialsTotal = 0 }
  view.plan = Planner.StepPlan(progress.reached)
  if progress.reached then
    view.message = string.format("%s with %s reached.", progress.targetLabel, record.name)
    view.nextStep = "Mark the goal complete"
    return view
  end
  local openQuest
  for _, quest in ipairs(quests) do
    if not quest.state.completed and not openQuest then openQuest = quest end
  end
  view.message = string.format("%d more reputation to %s with %s (you are %s, %d / %d into it%s).", progress.remaining, progress.targetLabel, record.name,
    record.standingLabel, record.into or 0, record.span or 0, record.unmet and "; not met yet" or "")
  if openQuest then
    view.message = view.message .. string.format(" Quest %s gives +%d.", openQuest.name, openQuest.amount)
    view.nextStep = string.format("%s (+%d)", openQuest.name, openQuest.amount)
  else
    view.nextStep = string.format("Earn %d reputation with %s", progress.remaining, record.name)
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
  view.inventoryNote = Planner.DescribeInventory(ctx.bankNote, ctx.includeBank, ctx.includeAlts)

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
