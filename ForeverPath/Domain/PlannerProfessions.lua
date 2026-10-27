-- Planner part: learn-recipe, enchant and reach-skill goals, and what each
-- profession can train. Extends ns.Planner (Domain/Planner.lua).
local _, ns = ...

local Status = ns.Status
local Util = ns.Util
local Log = ns.Log
local DependencyResolver = ns.DependencyResolver
local Planner = ns.Planner
local Shared = Planner.Shared
local inventoryContext = Shared.inventoryContext
local isLearned, buildCraftPlan = Shared.isLearned, Shared.buildCraftPlan

-- The account characters that know a recipe spell (empty without the provider).
local function whoKnows(deps, spellID)
  local names = deps.characters and Log.Try(deps.characters.WhoKnows, spellID)
  return type(names) == "table" and names or {}
end

-- What learn and enchant views share about a recipe: whether it is learned,
-- who on the account knows it, and this character's standing in its profession.
local function recipeStanding(deps, recipe, spellID)
  local profession = Planner.CurrentSkill(recipe.professionName, recipe.professionID, deps)
  local need = recipe.skill and recipe.skill.min or 0
  local standing = {
    recipe = recipe, spellID = spellID, learned = isLearned(deps, spellID), knownBy = whoKnows(deps, spellID),
    profession = profession, hasProfession = profession ~= nil, need = need,
    have = profession and profession.skillLevel or nil,
    skillOK = profession ~= nil and (profession.skillLevel or 0) >= need,
    teachItemID = recipe.teachItemID, trainer = recipe.trainer,
  }
  if not profession then
    standing.blocked = "profession"
  elseif not standing.skillOK then
    standing.blocked = "skill"
  end
  return standing
end

-- "a Tailoring trainer", "an Enchanting trainer".
local function article(word)
  return (type(word) == "string" and word:match("^[AEIOUaeiou]")) and "an" or "a"
end

-- The sentence for what blocks a recipe (no profession, skill too low), and
-- the next step that clears it; nil, nil when nothing does.
local function blockedStep(standing, recipe)
  if standing.blocked == "profession" then
    return string.format("You do not have %s on this character.", recipe.professionName or "the profession"),
      "Learn " .. (recipe.professionName or "the profession")
  elseif standing.blocked == "skill" then
    return string.format("Needs %s %d; you have %d.", recipe.professionName or "skill", standing.need, standing.profession.skillLevel or 0),
      string.format("Reach %s %d", recipe.professionName or "skill", standing.need)
  end
  return nil, nil
end

-- Training a recipe: the sentence and the next step, with the trainer when
-- one has been recorded.
local function trainerStep(recipe)
  local trainer = recipe.trainer
  if trainer and trainer.name then
    return string.format("Train at %s%s%s.", trainer.name, trainer.zone and (", " .. trainer.zone) or "",
      trainer.cost and trainer.cost > 0 and (" for " .. Util.FormatMoney(trainer.cost)) or ""), "Train at " .. trainer.name
  end
  return string.format("Train at any %s trainer (the requirement is recorded on your next trainer visit).", recipe.professionName or "profession"),
    "Visit " .. article(recipe.professionName) .. " " .. (recipe.professionName or "profession") .. " trainer"
end

-- The plans (or formula) that teach a recipe: read them when they are in the
-- bags, else get them. node is the plans' tree node.
local function plansStep(node, plansName, recipeName, sourceText)
  if node.missing <= 0 then
    return string.format("%s is in your bags: read it to learn %s.", plansName, recipeName), "Read " .. plansName
  end
  return string.format("Get %s%s.", plansName, sourceText and (" - " .. sourceText) or (node.noRoute and " (soulbound, no source recorded yet)" or "")),
    "Get " .. plansName
end

local function knownByText(knownBy)
  return string.format("%s already know%s it.", Util.Join(knownBy), #knownBy == 1 and "s" or "")
end

---------------------------------------------------------------------------
-- Learn-recipe and reach-skill goals
---------------------------------------------------------------------------

-- What each of this character's professions can train: recipes taught by a
-- trainer (recorded, or classic data) that it has not learned, at or below
-- its skill ("now") or within the next `window` points ("soon").
-- { { profession, skill, max, scanned, now = { { recipe, rank, cost, trainer, zone } }, soon = {...}, cost } }
Planner.TRAIN_WINDOW = 25

function Planner.Trainable(professionName, window, deps)
  deps = deps or Planner.DefaultDeps()
  window = window or Planner.TRAIN_WINDOW
  local data = deps.data
  local profession = deps.profession
  local out = {}
  if not (data and data.ForProfession and profession and profession.GetCharacterProfessions) then return out end
  local list = Log.Try(profession.GetCharacterProfessions)
  local scanned = {}
  for _, p in ipairs(Log.Try(profession.GetScannedProfessions) or {}) do scanned[p.name] = true end
  for _, p in ipairs(list or {}) do
    if not professionName or string.lower(p.name or "") == string.lower(professionName) then
      local skillLine = p.skillLine or (data.ProfessionID and data.ProfessionID(p.name))
      local current = p.skillLevel or 0
      local entry = { profession = p.name, skill = current, max = p.maxSkillLevel or 0, scanned = scanned[p.name] == true, now = {}, soon = {}, cost = 0 }
      for _, spellID in ipairs(skillLine and Log.Try(data.ForProfession, skillLine) or {}) do
        local recipe = Log.Try(data.Get, spellID)
        local trainer = recipe and recipe.trainer
        if trainer and not isLearned(deps, spellID) then
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
  local learn = recipeStanding(deps, recipe, target.spellID)
  learn.kind = recipe.combine and "combine" or (recipe.teachItemID and "plans" or "trainer")
  local learned, need, knownBy = learn.learned, learn.need, learn.knownBy
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
  view.inventoryNote = Planner.DescribeInventory(ctx.bankCounts, ctx.includeBank, ctx.includeAlts)

  local parts = {}
  local plansName
  if recipe.teachItemID then
    local info = deps.item and deps.item.GetItem and deps.item.GetItem(recipe.teachItemID) or nil
    plansName = (type(info) == "table" and info.name) or ("item " .. recipe.teachItemID)
  end
  local blockedText, blockedNext = blockedStep(learn, recipe)
  parts[#parts + 1] = blockedText
  local stepText
  if recipe.teachItemID then
    stepText, view.nextStep = plansStep(tree.root, plansName, name, view.sourceText)
  else
    stepText, view.nextStep = trainerStep(recipe)
  end
  parts[#parts + 1] = stepText
  view.nextStep = blockedNext or view.nextStep
  if #knownBy > 0 then
    parts[#parts + 1] = knownByText(knownBy)
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
  local enchant = recipeStanding(deps, recipe, target.spellID)
  local learned, knownBy = enchant.learned, enchant.knownBy
  local quantity = target.quantity or 1
  local casts = math.min(tonumber(target.casts) or 0, quantity)
  enchant.kind = recipe.teachItemID and "plans" or "trainer"
  enchant.casts, enchant.quantity, enchant.remaining = casts, quantity, quantity - casts
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

  local plan = buildCraftPlan(view, goal, deps, { recipe = recipe, quantity = enchant.remaining, learned = learned }, enchant.remaining)
  if not plan then return view end
  local tree = view.tree
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

  local parts = {}
  if casts > 0 then
    parts[#parts + 1] = string.format("%d of %d cast%s done.", casts, quantity, quantity == 1 and "" or "s")
  end
  local blockedText, blockedNext = blockedStep(enchant, recipe)
  parts[#parts + 1] = blockedText
  if not learned then
    local stepText
    if formulaNode then
      local info = deps.item and deps.item.GetItem and deps.item.GetItem(recipe.teachItemID) or nil
      local plansName = (type(info) == "table" and info.name) or ("item " .. recipe.teachItemID)
      stepText, view.nextStep = plansStep(formulaNode, plansName, name, Planner.SourceText(formulaNode.hint))
    else
      stepText, view.nextStep = trainerStep(recipe)
    end
    parts[#parts + 1] = stepText
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
  view.nextStep = blockedNext or view.nextStep
  if not learned and #knownBy > 0 then
    parts[#parts + 1] = knownByText(knownBy)
  end
  view.message = table.concat(parts, " ")
  return view
end

-- Candidate recipes for a skill plan: every catalogue recipe of the
-- profession with its thresholds, learned flag, whether its requirement is
-- known (trainer recorded or plans), reagent cost (nil when any price is
-- unknown) and reagent count.
function Planner.SkillCandidates(professionID, deps)
  deps = deps or Planner.DefaultDeps()
  local Recipes = deps.data
  local out = {}
  if not Recipes or not Recipes.ForProfession or not Recipes.Get then return out end
  local priceOf = deps.price and deps.price.GetPrice or nil
  for _, spellID in ipairs(Recipes.ForProfession(professionID)) do
    local recipe = Recipes.Get(spellID)
    if recipe and recipe.skill then
      local learned = isLearned(deps, spellID)
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
  local profession = Planner.CurrentSkill(target.professionName, professionID, deps)
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
  for _, p in ipairs(deps.profession and Log.Try(deps.profession.GetScannedProfessions) or {}) do
    if p.name == skill.professionName or (professionID and p.professionID == professionID) then scanned = true end
  end
  skill.scanned = scanned

  local candidates = Planner.SkillCandidates(professionID, deps)
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
  view.inventoryNote = Planner.DescribeInventory(ctx.bankCounts, ctx.includeBank, ctx.includeAlts)

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
