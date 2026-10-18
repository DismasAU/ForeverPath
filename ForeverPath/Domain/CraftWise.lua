-- CraftWise: buy versus craft versus hybrid, in gold, over a dependency tree.
--
-- Pure Lua. Inputs: a resolved tree (every craftable node expanded, so pass
-- the goal's full tree rather than one with "buy" overrides) and a price
-- lookup. Three strategies for the goal item:
--   buy      buy the finished item on the Auction House
--   craft    craft everything you can and buy every raw material
--   hybrid   per component, whichever of buying or crafting is cheaper
-- plus the per-component breakdown and the route overrides that make the
-- planner follow the hybrid plan.
--
-- Costs are in copper. nil means "unknown" (a price is missing somewhere);
-- `unknown` counts how many priced components were missing so the UI can say
-- "31g 62s (+2 unpriced)". Items already owned cost nothing; items an alt
-- holds cost nothing; gathering, drops and quests are priced at their AH
-- price when one is known (what you would pay instead of farming).
local _, ns = ...

local CraftWise = {}
ns.CraftWise = CraftWise

local function add(total, value)
  if total == nil or value == nil then return nil end
  return total + value
end

-- Evaluates one node; returns the row for it and fills rows (pre-order).
local function evaluate(node, ctx, rows, depth)
  local row = { node = node, itemID = node.itemID, depth = depth, quantity = node.missing or 0, children = {} }
  rows[#rows + 1] = row
  if (node.missing or 0) <= 0 then
    row.choice = node.claims and "owned" or "craft"
    row.buy, row.craft, row.craftPath, row.hybrid = 0, 0, 0, 0
    row.unknown = 0
    return row
  end
  -- A train step costs what the trainer charges, in every strategy.
  if node.step then
    local cost = node.step.trainer and tonumber(node.step.trainer.cost) or nil
    row.buy = nil
    row.craft, row.craftPath, row.hybrid = cost, cost, cost
    row.unknown = cost and 0 or 1
    row.pathUnknown = cost and 0 or 1
    row.choice = "train"
    return row
  end
  local info = ctx.priceOf(node.itemID)
  row.price = info
  row.freshness = info and ns.PriceProvider and ns.PriceProvider.Freshness(info, ctx.now) or nil
  -- A soulbound item has no market, whatever a price source says.
  row.buy = (info and not node.soulbound) and info.copper * node.missing or nil

  if #node.children > 0 then
    local craft, craftPath, unknown, pathUnknown = 0, 0, 0, 0
    for _, child in ipairs(node.children) do
      local sub = evaluate(child, ctx, rows, depth + 1)
      row.children[#row.children + 1] = sub
      if sub.hybrid then craft = craft + sub.hybrid else unknown = unknown + (sub.unknown > 0 and sub.unknown or 1) end
      if sub.craftPath then craftPath = craftPath + sub.craftPath else pathUnknown = pathUnknown + (sub.pathUnknown or 1) end
    end
    row.craftKnown, row.craftUnknown = craft, unknown
    row.craft = unknown == 0 and craft or nil
    row.craftPath = pathUnknown == 0 and craftPath or nil
    row.pathUnknown = pathUnknown
  else
    row.craftPath = row.buy
    row.pathUnknown = row.buy and 0 or 1
  end

  local route = node.route
  if route == "alt" or route == "altcraft" then
    row.choice = route
    row.hybrid = 0
    row.unknown = 0
  elseif #node.children > 0 and row.craft and row.buy then
    row.choice = row.craft <= row.buy and "craft" or "buy"
    row.hybrid = math.min(row.craft, row.buy)
    row.unknown = 0
  elseif #node.children > 0 and row.craft then
    row.choice = "craft"
    row.hybrid = row.craft
    row.unknown = 0
  elseif row.buy then
    row.choice = (route == "buy" or route == "vendor" or #node.children > 0) and (route == "vendor" and "vendor" or "buy") or route
    row.hybrid = row.buy
    row.unknown = 0
  elseif #node.children > 0 then
    row.choice = "craft"
    row.hybrid = nil
    row.unknown = row.craftUnknown
  else
    row.choice = route or "buy"
    row.hybrid = nil
    row.unknown = 1
  end
  if row.choice == "buy" and node.craftOption and node.craftOption.learned then
    row.switchable = true
  end
  return row
end

-- opts: priceOf(itemID) -> priceInfo | nil, marketOf(itemID) (default priceOf), now
function CraftWise.Compare(tree, opts)
  opts = opts or {}
  if type(tree) ~= "table" or type(tree.root) ~= "table" then return nil, "tree required" end
  local ctx = { priceOf = opts.priceOf or function() return nil end, now = opts.now }
  local marketOf = opts.marketOf or ctx.priceOf
  local rows = {}
  local root = tree.root
  local rootRow = evaluate(root, ctx, rows, 0)

  local result = {
    tree = tree, rows = rows, rootRow = rootRow,
    itemID = root.itemID, quantity = root.quantity,
    buy = {}, craft = {}, hybrid = {},
  }

  -- Buy finished: the AH price of the goal item times what is still needed.
  local wanted = root.claims and (root.missing or 0) or root.quantity
  local market = marketOf(root.itemID)
  result.buy.price = market
  result.buy.cost = market and market.copper * wanted or nil
  result.buy.freshness = market and ns.PriceProvider and ns.PriceProvider.Freshness(market, ctx.now) or nil
  result.buy.listings = market and market.listings or nil
  result.buy.avg7 = market and market.avg7 and market.avg7 * wanted or nil

  -- Craft everything: buy every raw material of the full tree.
  if root.claims and #root.children == 0 then
    result.craft.cost = nil
    result.craft.unknown = 1
    result.craft.possible = false
  else
    result.craft.cost = rootRow.craftPath
    result.craft.unknown = rootRow.pathUnknown or 0
    result.craft.possible = #root.children > 0 or (root.missing or 0) <= 0
  end

  -- Hybrid: the cheaper of buying or crafting at every level.
  if root.claims and #root.children == 0 then
    result.hybrid.cost = rootRow.hybrid
    result.hybrid.unknown = rootRow.unknown or 0
  else
    result.hybrid.cost = rootRow.craft
    result.hybrid.unknown = rootRow.craftUnknown or 0
  end

  -- Lists for the hybrid card and the route plan.
  result.hybrid.buyList, result.hybrid.craftList, result.hybrid.ownedList, result.hybrid.altList = {}, {}, {}, {}
  result.plan = {}
  local worst
  local function walk(row, parentChoice)
    local node = row.node
    if row.depth > 0 then
      if row.choice == "owned" then
        if (node.owned or 0) > 0 then result.hybrid.ownedList[#result.hybrid.ownedList + 1] = { itemID = node.itemID, count = node.owned } end
      elseif row.choice == "alt" or row.choice == "altcraft" then
        result.hybrid.altList[#result.hybrid.altList + 1] = { itemID = node.itemID, count = node.missing, name = node.hint and node.hint.name }
      elseif row.choice == "craft" then
        result.hybrid.craftList[#result.hybrid.craftList + 1] = { itemID = node.itemID, crafts = node.craft and node.craft.crafts or 0, count = node.missing, professionName = node.craft and node.craft.professionName }
      else
        result.hybrid.buyList[#result.hybrid.buyList + 1] = { itemID = node.itemID, name = node.step and node.step.name or nil, count = node.missing, cost = row.hybrid, choice = row.choice }
      end
      if (node.owned or 0) > 0 and row.choice ~= "owned" then
        result.hybrid.ownedList[#result.hybrid.ownedList + 1] = { itemID = node.itemID, count = node.owned }
      end
      if node.craftOption and node.craftOption.learned then
        result.plan[node.itemID] = row.choice == "craft" and "craft" or (row.choice == "buy" or row.choice == "vendor") and "buy" or nil
      end
      if row.freshness and row.choice ~= "owned" and row.choice ~= "craft" then
        worst = ns.PriceProvider and ns.PriceProvider.WorstFreshness(worst, row.freshness) or worst
      end
    end
    -- Only descend into components that are crafted in the hybrid plan.
    if row.choice == "craft" or row.depth == 0 then
      for _, child in ipairs(row.children) do walk(child, row.choice) end
    end
  end
  walk(rootRow, nil)
  result.hybrid.freshness = worst

  -- Recommendation: cheapest known strategy; hybrid wins ties.
  local candidates = {}
  if result.hybrid.cost and result.hybrid.unknown == 0 then candidates[#candidates + 1] = { key = "hybrid", cost = result.hybrid.cost } end
  if result.craft.cost and result.craft.unknown == 0 then candidates[#candidates + 1] = { key = "craft", cost = result.craft.cost } end
  if result.buy.cost then candidates[#candidates + 1] = { key = "buy", cost = result.buy.cost } end
  table.sort(candidates, function(a, b)
    if a.cost ~= b.cost then return a.cost < b.cost end
    local order = { hybrid = 1, craft = 2, buy = 3 }
    return order[a.key] < order[b.key]
  end)
  result.recommended = candidates[1] and candidates[1].key or nil
  result.available = result.recommended ~= nil or (result.hybrid.cost ~= nil)
  if result.recommended then
    local best = candidates[1].cost
    result.savings = {}
    for _, key in ipairs({ "buy", "craft", "hybrid" }) do
      local cost = result[key].cost
      if cost and key ~= result.recommended then result.savings[key] = cost - best end
    end
  end
  result.unpriced = 0
  for _, row in ipairs(rows) do
    if row.depth > 0 and row.quantity > 0 and row.choice ~= "owned" and row.choice ~= "craft" and row.choice ~= "alt" and row.choice ~= "altcraft" and not row.buy
      and not (row.choice == "train" and row.hybrid) then
      result.unpriced = result.unpriced + 1
    end
  end
  return result
end

CraftWise.ChoiceLabels = { buy = "Buy", vendor = "Vendor", craft = "Craft", owned = "Owned", alt = "Alt", altcraft = "Alt crafts", gather = "Gather", drop = "Drop", quest = "Quest", train = "Train" }

-- Applies the hybrid plan as per-item route overrides on a goal: "buy" where
-- buying beats crafting, the default (nil) where crafting wins.
-- setRoute(itemID, route) is called for every craftable component.
function CraftWise.ApplyPlan(result, setRoute)
  local changed = 0
  for itemID, route in pairs(result and result.plan or {}) do
    local value = route == "buy" and "buy" or nil
    if setRoute(itemID, value) then changed = changed + 1 end
  end
  return changed
end

-- Routes that buy every craftable component ("buy all materials" mode).
function CraftWise.BuyAllPlan(result)
  local plan = {}
  for itemID in pairs(result and result.plan or {}) do plan[itemID] = "buy" end
  return plan
end

-- Which preset the goal's current overrides match: "default", "hybrid", "buyall" or "custom".
function CraftWise.Mode(result, routes)
  routes = routes or {}
  local function matches(plan)
    for itemID, route in pairs(plan) do
      if (routes[itemID] or nil) ~= (route == "buy" and "buy" or nil) then return false end
    end
    for itemID in pairs(routes) do
      if plan[itemID] == nil and routes[itemID] ~= nil then return false end
    end
    return true
  end
  if next(routes) == nil then return "default" end
  if result and matches(result.plan) then return "hybrid" end
  if result and matches(CraftWise.BuyAllPlan(result)) then return "buyall" end
  return "custom"
end
