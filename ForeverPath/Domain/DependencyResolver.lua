-- Recursive dependency resolution. Pure Lua, no API access.
--
-- Turns "craft N of this recipe" into a tree: each reagent becomes a node with
-- the units needed, what the inventory covers (through an Allocation ledger so
-- nothing is counted twice) and what is still missing. A missing reagent that
-- the character can craft is expanded into its own reagents, so Linen Bag ->
-- Bolt of Linen Cloth -> Linen Cloth is traced to the raw material. Per-item
-- route overrides (goal.routes) force "craft" or "buy" for a reagent.
local _, ns = ...

local CraftingEngine = ns.CraftingEngine
local Allocation = ns.Allocation

local DependencyResolver = {}
ns.DependencyResolver = DependencyResolver

DependencyResolver.MAX_DEPTH = 6
DependencyResolver.Routes = { CRAFT = "craft", BUY = "buy" }
DependencyResolver.RouteLabels = { craft = "Craft", buy = "Buy", vendor = "Vendor", gather = "Gather", drop = "Drop", quest = "Quest", alt = "Alt", altcraft = "Alt crafts", learn = "Learn recipe", combine = "Combine", train = "Train" }
-- Preferred default route when no learned recipe exists: certain and cheap
-- first. "combine" is an item-use recipe anyone can do; "learn" is a catalogue
-- recipe someone on the account could learn and craft.
DependencyResolver.RouteRank = { vendor = 1, alt = 2, altcraft = 3, combine = 3, gather = 4, drop = 5, quest = 6, learn = 7, buy = 9 }
-- A craft nobody on the account can do today: shown as the pathway when no
-- real route exists, never recommended over one.
DependencyResolver.UNAVAILABLE_RANK = 10

local function statusFor(node)
  if node.depth == 0 and not node.claims then return "root" end
  if node.missing <= 0 then return "have" end
  if node.owned > 0 then return "partial" end
  return "missing"
end

-- Picks the craft option to use: learned first, then a combine (anyone can),
-- then a catalogue recipe someone could learn, then any other.
local function bestCraft(options)
  local combine, learnable, fallback
  for _, option in ipairs(options) do
    if option.kind == "craft" and not option.cycle then
      if option.learned then return option end
      if option.combine then combine = combine or option
      elseif not option.unavailable then learnable = learnable or option
      else fallback = fallback or option end
    end
  end
  return combine or learnable or fallback
end

-- A catalogue recipe nobody has learned is only a route when a character on
-- the account has the profession at the required skill. Otherwise it is
-- marked unavailable with the reason, and still shown as information.
local function qualifyCraft(option, opts)
  if option.learned or option.combine then return end
  if not opts.crafters then
    -- Nobody to ask: an unlearned recipe is information, not a route.
    option.unavailable = true
    option.reason = "not learned"
    return
  end
  local recipe = option.recipe
  local people = opts.crafters(recipe.professionName, recipe.professionID) or {}
  option.crafters = people
  local need = recipe.skill and recipe.skill.min or 0
  for _, person in ipairs(people) do
    if (person.skillLevel or 0) >= need then
      option.crafter = person
      break
    end
  end
  if #people == 0 then
    option.unavailable = true
    option.reason = "no " .. (recipe.professionName or "crafter") .. " on this account"
  elseif not option.crafter then
    option.unavailable = true
    option.reason = string.format("needs %s %d; %s has %d", recipe.professionName or "skill", need, people[1].name or "?", people[1].skillLevel or 0)
  end
end

-- Builds the option list for an item: every known recipe plus "buy" and any
-- static source hints. Returns options, soulbound.
local function buildOptions(itemID, opts, path)
  local options = {}
  local candidates = opts.findRecipes and opts.findRecipes(itemID) or {}
  for _, candidate in ipairs(candidates or {}) do
    local recipe = candidate.recipe
    if type(recipe) == "table" and type(recipe.reagents) == "table" then
      local cycle = false
      for _, reagent in ipairs(recipe.reagents) do
        if path[reagent.itemID] then cycle = true end
      end
      local option = {
        kind = "craft",
        recipe = recipe,
        name = recipe.name,
        learned = candidate.learned and true or false,
        static = candidate.static and true or false,
        combine = recipe.combine and true or nil,
        professionName = recipe.professionName,
        professionID = recipe.professionID,
        yield = recipe.quantityMin or 1,
        cycle = cycle,
        skill = recipe.skill,
        teachItemID = recipe.teachItemID,
        tools = recipe.tools,
      }
      qualifyCraft(option, opts)
      options[#options + 1] = option
    end
  end
  local hints = opts.sources and opts.sources(itemID) or nil
  if type(hints) == "table" then
    for _, hint in ipairs(hints) do
      if type(hint) == "table" and hint.kind and hint.kind ~= "craft" then
        options[#options + 1] = { kind = hint.kind, label = hint.label, detail = hint.detail, name = hint.name, count = hint.count,
          skill = hint.skill, gatherer = hint.gatherer, unavailable = hint.unavailable and true or nil }
      end
    end
  end
  options[#options + 1] = { kind = "buy" }
  -- An item that binds when picked up cannot be bought, mailed or crafted by an alt for you.
  local soulbound = opts.soulbound and opts.soulbound(itemID) or false
  if soulbound then
    for _, option in ipairs(options) do
      if option.kind == "buy" or option.kind == "alt" or option.kind == "altcraft" then
        option.unavailable = true
        option.reason = "soulbound"
      end
    end
  end
  return options, soulbound
end

-- Merges duplicate reagent slots into one requirement list (same rule as the engine).
local function reagentList(recipe)
  local list, byItem = {}, {}
  for _, reagent in ipairs(recipe.reagents) do
    local entry = byItem[reagent.itemID]
    if entry then
      entry.quantity = entry.quantity + reagent.quantity
    else
      entry = { itemID = reagent.itemID, quantity = reagent.quantity, alternatives = reagent.alternatives }
      byItem[reagent.itemID] = entry
      list[#list + 1] = entry
    end
  end
  return list
end

-- Requirements beyond the reagents: the plans or pattern that teaches an
-- unlearned recipe, and the item a combine is used from when it is not spent
-- (any one of the listed tools will do, so only the first is required).
local function extraRequirements(craft)
  local extras = {}
  if craft.teachItemID then
    extras[#extras + 1] = { itemID = craft.teachItemID, learn = true, learnFor = craft.recipe.name }
  end
  if craft.tools and craft.tools[1] then
    extras[#extras + 1] = { itemID = craft.tools[1], tool = true, toolFor = craft.recipe.name }
  end
  return extras
end

local function expand(node, opts, ledger, path, tree)
  local recipe = node.craft.recipe
  local crafts = node.craft.crafts
  path[node.itemID] = true
  local index = 0
  local function addChild(itemID, perCraft, quantity, fields)
    index = index + 1
    local child = {
      key = node.key .. ">" .. itemID,
      itemID = itemID,
      depth = node.depth + 1,
      parentKey = node.key,
      index = index,
      perCraft = perCraft,
      quantity = quantity,
      children = {},
    }
    for k, v in pairs(fields or {}) do child[k] = v end
    DependencyResolver.ResolveNode(child, opts, ledger, path, tree)
    node.children[#node.children + 1] = child
  end
  for _, extra in ipairs(extraRequirements(node.craft)) do
    addChild(extra.itemID, 0, 1, extra)
  end
  -- A trainer recipe nobody has learned: a "train it" step with the trainer
  -- recorded for it (name, zone, cost) when one has been visited.
  local craft = node.craft
  if craft.static and not craft.learned and not craft.combine and not craft.teachItemID then
    index = index + 1
    local step = {
      kind = "train", spellID = recipe.recipeID, name = recipe.name, professionName = craft.professionName,
      icon = recipe.icon, rank = recipe.skill and recipe.skill.min or nil, trainer = recipe.trainer, who = craft.crafter,
    }
    local child = { key = node.key .. ">train:" .. tostring(recipe.recipeID), step = step, depth = node.depth + 1,
      parentKey = node.key, index = index, perCraft = 0, quantity = 1, children = {} }
    DependencyResolver.ResolveNode(child, opts, ledger, path, tree)
    node.children[#node.children + 1] = child
  end
  for _, reagent in ipairs(reagentList(recipe)) do
    addChild(reagent.itemID, reagent.quantity, reagent.quantity * crafts, { alternatives = reagent.alternatives })
  end
  path[node.itemID] = nil
end

-- Fills in inventory, options, route and (when crafting) children for a node.
function DependencyResolver.ResolveNode(node, opts, ledger, path, tree)
  tree.byKey[node.key] = node
  -- A step (train a recipe) is not an item: nothing to count, buy or expand.
  if node.step then
    node.claims = false
    node.owned, node.ownedBags, node.reserved, node.available = 0, 0, 0, 0
    node.missing = node.quantity
    node.status = "missing"
    node.options = {}
    node.route, node.routeSource = "train", "default"
    return node
  end
  -- Every node below the root claims inventory. So does the root of an
  -- "obtain item" tree: there is no recipe to craft it with, the item itself
  -- is what the player needs to get.
  node.claims = node.depth > 0 or node.obtain == true
  if node.claims then
    local raw = opts.counts and opts.counts(node.itemID) or 0
    local taken = ledger:Take(node.itemID, raw, node.quantity, opts.includeBank, opts.includeAlts)
    node.owned = taken.total
    node.ownedBags = taken.bags
    node.ownedBank = taken.bank
    node.ownedAlts = taken.alts
    node.altSources = taken.altSources
    node.bankSource = taken.bankSource
    node.bankScannedAt = taken.bankScannedAt
    node.reserved = taken.reserved
    -- What was free for this node before it claimed (shown as "Have").
    node.available = taken.availableTotal
    node.availableBags = taken.availableBags
    node.availableBank = taken.availableBank
    node.availableAlts = taken.availableAlts
    node.missing = math.max(0, node.quantity - node.owned)
  else
    node.owned, node.ownedBags, node.reserved, node.available = 0, 0, 0, 0
    node.missing = node.quantity
  end
  node.status = statusFor(node)

  node.options, node.soulbound = buildOptions(node.itemID, opts, path)
  local craftOption = bestCraft(node.options)
  local override = opts.routes and opts.routes[node.itemID] or nil
  -- A gathering material with a "refine a lower tier" recipe (Medium Leather
  -- from Light Leather) is gathered or bought by default; crafting it from
  -- the tier below is only a route when the player asks for it.
  node.raw = (node.depth > 0 or node.obtain) and opts.isRaw and opts.isRaw(node.itemID) and true or nil
  if node.depth == 0 and opts.rootRecipe then
    node.route, node.routeSource = "craft", "root"
  elseif override == "craft" and craftOption then
    node.route, node.routeSource = "craft", "override"
  elseif override == "buy" then
    node.route, node.routeSource = "buy", "override"
  elseif craftOption and craftOption.learned and not node.raw then
    node.route, node.routeSource = "craft", "default"
  else
    node.route, node.routeSource = "buy", "default"
    local bestRank = DependencyResolver.RouteRank.buy
    local buyOption
    for _, option in ipairs(node.options) do
      if option.kind == "buy" then buyOption = option end
      local rank = DependencyResolver.RouteRank[option.kind]
      if option.kind ~= "craft" and not option.unavailable and rank and rank < bestRank then
        bestRank = rank
        node.route = option.kind
        node.hint = option
      end
    end
    if node.route == "buy" and buyOption and buyOption.unavailable then
      -- Soulbound and nothing else known: no real route yet.
      bestRank = DependencyResolver.UNAVAILABLE_RANK + 1
      node.noRoute = true
    end
    -- A catalogue recipe nobody has learned: a combine anyone can do ranks
    -- with alt crafting, a learnable recipe just above the Auction House, and
    -- one nobody can do is only shown when there is no other way at all.
    if craftOption and not craftOption.cycle and not node.raw then
      local rank = craftOption.combine and DependencyResolver.RouteRank.combine
        or (craftOption.unavailable and DependencyResolver.UNAVAILABLE_RANK or DependencyResolver.RouteRank.learn)
      if rank < bestRank then
        node.route, node.routeSource = "craft", craftOption.combine and "combine" or "learn"
        node.hint, node.noRoute = nil, nil
      end
    end
  end
  node.craftOption = craftOption

  if node.route == "craft" and node.missing > 0 then
    local option = craftOption
    if node.depth == 0 and opts.rootRecipe then
      -- The root always crafts with the goal's own recipe.
      option = { kind = "craft", recipe = opts.rootRecipe, learned = true, professionName = opts.rootRecipe.professionName, yield = opts.rootRecipe.quantityMin or 1 }
    end
    local crafts = CraftingEngine.CraftsNeeded(node.missing, option.yield)
    node.craft = {
      recipe = option.recipe,
      recipeID = option.recipe.recipeID,
      professionName = option.professionName,
      learned = option.learned,
      static = option.static,
      combine = option.combine,
      crafter = option.crafter,
      crafters = option.crafters,
      unavailable = option.unavailable and (option.reason or "no crafter") or nil,
      skill = option.skill,
      -- The plans are a requirement only while nobody has learned the recipe.
      teachItemID = (not option.learned and not option.combine) and option.teachItemID or nil,
      tools = option.tools,
      crafts = crafts,
      yield = option.yield,
      expectedOutput = crafts * (option.yield or 1),
    }
    node.craft.surplus = node.craft.expectedOutput - node.missing
    if node.depth >= (opts.maxDepth or DependencyResolver.MAX_DEPTH) then
      node.blocked = "depth"
    else
      expand(node, opts, ledger, path, tree)
    end
  elseif craftOption == nil and override == "craft" then
    node.blocked = "no-recipe"
  end
  for _, option in ipairs(node.options) do
    if option.kind == "craft" and option.cycle and not node.craft then
      node.blocked = node.blocked or "cycle"
    end
  end
  return node
end

-- root = { recipe = <RecipeModel>, quantity = n }
-- opts: findRecipes(itemID), counts(itemID), includeBank, routes, ledger, maxDepth, sources(itemID)
-- root = { recipe, quantity } crafts the recipe's output (the root never
-- claims inventory: the goal is to make it). root = { itemID, quantity } is
-- an "obtain" tree: the root is the item itself, claims inventory like any
-- other node, and expands into a craft only through a learned recipe.
function DependencyResolver.Resolve(root, opts)
  opts = opts or {}
  if type(root) ~= "table" or (type(root.recipe) ~= "table" and type(root.itemID) ~= "number") then
    return nil, "recipe or itemID required"
  end
  local quantity = tonumber(root.quantity) or 1
  if quantity < 1 then quantity = 1 end
  local ledger = opts.ledger or Allocation.New()
  local obtain = type(root.recipe) ~= "table"
  local tree = { byKey = {}, ledger = ledger, obtain = obtain }
  opts.rootRecipe = (not obtain) and root.recipe or nil
  local itemID = obtain and root.itemID or root.recipe.outputItemID
  local node = {
    key = tostring(itemID),
    itemID = itemID,
    depth = 0,
    index = 1,
    quantity = quantity,
    children = {},
    obtain = obtain or nil,
  }
  DependencyResolver.ResolveNode(node, opts, ledger, {}, tree)
  tree.root = node
  tree.summary = DependencyResolver.Summarize(tree)
  return tree
end

-- Post-order walk collecting counts, missing leaves and craft steps.
function DependencyResolver.Summarize(tree)
  local summary = { nodes = 0, resolved = 0, leaves = {}, missingLeaves = {}, crafts = {}, maxDepth = 0, blocked = 0 }
  local leafByItem = {}
  local function walk(node)
    local allChildrenResolved = true
    for _, child in ipairs(node.children) do
      walk(child)
      if child.missing > 0 then allChildrenResolved = false end
    end
    if node.claims or node.step then
      summary.nodes = summary.nodes + 1
      if node.missing <= 0 then summary.resolved = summary.resolved + 1 end
      if node.depth > summary.maxDepth then summary.maxDepth = node.depth end
      if node.blocked then summary.blocked = summary.blocked + 1 end
      if node.missing > 0 and #node.children == 0 then
        summary.leaves[#summary.leaves + 1] = node
        local leafKey = node.itemID or node.key
        local entry = leafByItem[leafKey]
        if not entry then
          entry = { itemID = node.itemID, step = node.step, name = node.step and node.step.name or nil, count = 0, route = node.route, nodes = {},
            professionName = node.craftOption and node.craftOption.professionName or nil,
            recipeLearned = node.craftOption and node.craftOption.learned or false,
            hint = node.hint and node.hint.detail or nil, altName = node.hint and node.hint.name or nil,
            gatherer = node.hint and node.hint.gatherer or nil,
            learn = node.learn or nil, learnFor = node.learnFor, tool = node.tool or nil,
            soulbound = node.soulbound or nil, noRoute = node.noRoute or nil }
          leafByItem[leafKey] = entry
          summary.missingLeaves[#summary.missingLeaves + 1] = entry
        end
        entry.count = entry.count + node.missing
        entry.nodes[#entry.nodes + 1] = node
      end
    end
    if node.craft and node.claims and node.missing > 0 then
      summary.crafts[#summary.crafts + 1] = {
        key = node.key,
        itemID = node.itemID,
        crafts = node.craft.crafts,
        units = node.missing,
        expectedOutput = node.craft.expectedOutput,
        professionName = node.craft.professionName,
        learned = node.craft.learned,
        static = node.craft.static,
        combine = node.craft.combine,
        crafter = node.craft.crafter,
        unavailable = node.craft.unavailable,
        teachItemID = node.craft.teachItemID,
        ready = allChildrenResolved,
        node = node,
      }
    end
    node.childrenResolved = allChildrenResolved
  end
  walk(tree.root)
  table.sort(summary.missingLeaves, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return (a.itemID or 0) < (b.itemID or 0)
  end)
  return summary
end

-- Counts for the direct reagents (depth 1), keyed by itemID, in the shape the
-- crafting engine's inventory lookup expects: what was free for this goal
-- (after higher-priority goals claimed theirs). Lets the flat requirements
-- plan share the tree's allocation instead of counting inventory a second time.
function DependencyResolver.DirectCounts(tree)
  local counts = {}
  for _, child in ipairs(tree.root.children) do
    if child.itemID then counts[child.itemID] = {
      bags = child.availableBags or 0,
      bank = child.availableBank,
      alts = child.availableAlts,
      altSources = child.altSources,
      bankSource = child.bankSource,
      bankScannedAt = child.bankScannedAt,
      reserved = child.reserved,
    } end
  end
  return counts
end

-- Visible rows for a tree view.
-- opts.collapsed = { [key] = true }, opts.unresolvedOnly = bool
-- Each row: { node, isLast, guides = { [depth] = true when the ancestor at that depth continues } }
function DependencyResolver.Flatten(tree, opts)
  opts = opts or {}
  local rows = {}
  local function visible(node)
    if not opts.unresolvedOnly then return true end
    return node.depth == 0 or node.missing > 0
  end
  local function walk(node, guides, isLast)
    rows[#rows + 1] = { node = node, isLast = isLast, guides = guides, hasChildren = #node.children > 0,
      collapsed = opts.collapsed and opts.collapsed[node.key] or false }
    if opts.collapsed and opts.collapsed[node.key] then return end
    local shown = {}
    for _, child in ipairs(node.children) do
      if visible(child) then shown[#shown + 1] = child end
    end
    for index, child in ipairs(shown) do
      local childGuides = {}
      for depth, continues in pairs(guides) do childGuides[depth] = continues end
      childGuides[node.depth] = not isLast
      walk(child, childGuides, index == #shown)
    end
  end
  walk(tree.root, {}, true)
  return rows
end

-- Other trees that need itemID: { { goalID, quantity } }.
function DependencyResolver.UsesOf(trees, itemID, excludeGoalID)
  local uses = {}
  for goalID, tree in pairs(trees or {}) do
    if goalID ~= excludeGoalID and tree and tree.byKey then
      local total = 0
      for _, node in pairs(tree.byKey) do
        if node.itemID == itemID and node.claims then total = total + node.quantity end
      end
      if total > 0 then uses[#uses + 1] = { goalID = goalID, quantity = total } end
    end
  end
  table.sort(uses, function(a, b) return a.goalID < b.goalID end)
  return uses
end

-- Plain-text rendering for chat / debugging.
function DependencyResolver.Describe(tree, nameOf)
  nameOf = nameOf or function(id) return "Item " .. tostring(id) end
  local lines = {}
  for _, row in ipairs(DependencyResolver.Flatten(tree)) do
    local node = row.node
    local indent = string.rep("  ", node.depth)
    local text
    if node.step then
      local trainer = node.step.trainer
      text = string.format("%strain: %s%s", indent, node.step.name,
        trainer and trainer.name and (" at " .. trainer.name .. (trainer.zone and (" (" .. trainer.zone .. ")") or "")) or (" (" .. (node.step.professionName or "profession") .. " trainer)"))
    elseif node.depth == 0 and not node.claims then
      text = string.format("%s%s x%d (%d craft%s)", indent, nameOf(node.itemID), node.quantity, node.craft and node.craft.crafts or 0, node.craft and node.craft.crafts == 1 and "" or "s")
    else
      local via = node.route == "craft" and ("craft" .. (node.craft and node.craft.professionName and (" - " .. node.craft.professionName) or "")
        .. (node.craft and node.craft.unavailable and (" [" .. node.craft.unavailable .. "]") or "")) or node.route
      if node.noRoute then via = "no known route (soulbound)" end
      local prefix = node.learn and "learn: " or (node.tool and "using: " or "")
      text = string.format("%s%s%s x%d: %d/%d %s%s", indent, prefix, nameOf(node.itemID), node.quantity, node.owned, node.quantity,
        node.missing > 0 and ("missing " .. node.missing .. " via " .. via) or "have",
        node.blocked and (" [" .. node.blocked .. "]") or "")
    end
    lines[#lines + 1] = text
  end
  lines[#lines + 1] = string.format("%d of %d dependencies resolved", tree.summary.resolved, tree.summary.nodes)
  return lines
end
