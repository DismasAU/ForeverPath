-- Consolidated shopping list across goals. Pure Lua over Planner views.
--
-- Every node of every included goal's dependency tree contributes to one row
-- per item: how many units the goals need in total, how many the inventory
-- covers, how many are held by goals that are not on the list (reserved) and
-- how many are still missing. Rows are classified by how the player is
-- expected to get the item (Auction House, vendor, gathering, craft, alt).
local _, ns = ...

local GoalModel = ns.GoalModel

local ShoppingList = {}
ns.ShoppingList = ShoppingList

ShoppingList.Categories = { "buy", "vendor", "gather", "craft", "learn", "alt" }
ShoppingList.CategoryLabels = { buy = "Auction House", vendor = "Vendors", gather = "Gathering / drops", craft = "Craftable", learn = "Recipes to learn", alt = "From alts" }

local ROUTE_CATEGORY = { buy = "buy", vendor = "vendor", gather = "gather", drop = "gather", quest = "gather", craft = "craft", alt = "alt", altcraft = "alt" }

-- Default membership: active and queued goals are on the list, paused are not.
function ShoppingList.DefaultIncluded(goal)
  return goal.status == GoalModel.Statuses.ACTIVE or goal.status == GoalModel.Statuses.QUEUED
end

local function sourceLabels(node)
  local labels = {}
  local function add(label)
    for _, existing in ipairs(labels) do
      if existing == label then return end
    end
    labels[#labels + 1] = label
  end
  if node.learn then
    add("Recipe" .. (node.learnFor and (": teaches " .. node.learnFor) or ""))
  elseif node.tool then
    add("Tool" .. (node.toolFor and (" for " .. node.toolFor) or ""))
  end
  if node.route == "craft" and node.craft then
    if node.craft.combine then
      add("Combine")
    else
      local who = node.craft.unavailable and (" (" .. node.craft.unavailable .. ")")
        or (node.craft.crafter and not node.craft.crafter.isCurrent and (" on " .. node.craft.crafter.name)) or ""
      add("Craft - " .. (node.craft.professionName or "?") .. who)
    end
  elseif node.route == "alt" and node.hint then
    add("Alt: " .. (node.hint.name or "?"))
  elseif node.route == "altcraft" and node.hint then
    add("Craft - Alt: " .. (node.hint.name or "?"))
  end
  if node.soulbound then add("Soulbound") end
  for _, option in ipairs(node.options or {}) do
    if option.kind == "buy" and not option.unavailable then
      add("AH")
    elseif option.kind == "vendor" then
      add("Vendor: " .. (option.name or "?"))
    elseif (option.kind == "gather" or option.kind == "drop" or option.kind == "quest") and not option.unavailable then
      add(option.label or (ns.DependencyResolver and ns.DependencyResolver.RouteLabels[option.kind]) or option.kind)
    elseif option.kind == "craft" and node.route ~= "craft" then
      if option.learned then
        add("Craft - " .. (option.professionName or "?"))
      elseif option.combine then
        add("Combine")
      else
        add("Recipe not learned" .. (option.reason and (" - " .. option.reason) or ""))
      end
    end
  end
  return labels
end

-- Plans to get and recipes to train are listed together; a soulbound item
-- with no real route is listed with drops, not the Auction House.
local function categoryFor(node)
  if node.step or node.learn then return "learn" end
  local category = ROUTE_CATEGORY[node.route] or "buy"
  if category == "buy" and node.soulbound then return "gather" end
  return category
end

-- "Train - Georgio Bolero (Stormwind City)" for a train step.
local function stepLabel(step)
  local trainer = step.trainer
  if trainer and trainer.name then
    return "Train - " .. trainer.name .. (trainer.zone and (" (" .. trainer.zone .. ")") or "")
  end
  return "Train - " .. (step.professionName or "profession") .. " trainer (not yet recorded)"
end

-- Affordability of one amount against the gold you carry and the account's.
-- gold = { current = copper|nil, account = copper|nil }
-- Returns "now" | "account" | "no" | nil (no gold information).
function ShoppingList.Affordable(cost, gold)
  if type(cost) ~= "number" or type(gold) ~= "table" then return nil end
  if type(gold.current) == "number" and cost <= gold.current then return "now" end
  if type(gold.account) == "number" and cost <= gold.account then return "account" end
  if type(gold.current) == "number" or type(gold.account) == "number" then return "no" end
  return nil
end

-- entries: { { goal, view } } in priority order.
-- opts.included(goal) -> bool (default ShoppingList.DefaultIncluded)
-- opts.bought = { [itemID] = true }
-- opts.nameOf(itemID)
-- opts.priceOf(itemID) -> copper per unit | nil (unknown)
-- opts.gold = { current = copper, account = copper } (optional; enables affordability)
function ShoppingList.Build(entries, opts)
  opts = opts or {}
  local included = opts.included or ShoppingList.DefaultIncluded
  local bought = opts.bought or {}
  local nameOf = opts.nameOf or function(itemID) return "Item " .. tostring(itemID) end
  local result = {
    rows = {}, goals = {},
    counts = { all = 0, buy = 0, vendor = 0, gather = 0, craft = 0, learn = 0, alt = 0, bought = 0 },
    units = { total = 0, owned = 0, missing = 0, reserved = 0 },
    cost = { known = 0, pricedRows = 0, unpricedRows = 0, bought = 0, remaining = 0 },
    mail = {},
  }
  local byItem = {}
  local claimedByExcluded = {}
  local stock = {}

  -- Rows are keyed by item id; a train step by "train:<spellID>".
  local function row(key, itemID, step)
    local r = byItem[key]
    if not r then
      r = { key = key, itemID = itemID, step = step, name = step and step.name or nil, total = 0, owned = 0, reserved = 0, missing = 0,
        category = nil, sources = {}, goals = {}, altHolders = {}, bought = bought[key] == true }
      byItem[key] = r
      result.rows[#result.rows + 1] = r
    end
    return r
  end

  for _, entry in ipairs(entries or {}) do
    local goal, view = entry.goal, entry.view
    local isIncluded = included(goal) and true or false
    result.goals[#result.goals + 1] = { goal = goal, included = isIncluded, name = GoalModel.Name(goal, nameOf), quantity = goal.target and goal.target.quantity or 1 }
    local tree = view and view.tree
    if tree and tree.byKey then
      for _, node in pairs(tree.byKey) do
        -- A craft done for skill points is not something to get; its reagents are.
        if (node.claims or node.depth > 0 or (node.step and node.step.kind == "train")) and not node.forSkill then
          local key = node.itemID or ("train:" .. tostring(node.step and node.step.spellID or node.key))
          if node.itemID then
            local full = (node.available or 0) + (node.reserved or 0)
            if full > (stock[node.itemID] or 0) then stock[node.itemID] = full end
          end
          if isIncluded then
            local r = row(key, node.itemID, node.step)
            r.total = r.total + node.quantity
            r.owned = r.owned + (node.owned or 0)
            r.missing = r.missing + (node.missing or 0)
            if node.missing > 0 then
              local category = categoryFor(node)
              if not r.category then r.category = category end
              if node.learn then r.learn = true end
              if node.step then
                local label = stepLabel(node.step)
                local seen = false
                for _, existing in ipairs(r.sources) do if existing == label then seen = true end end
                if not seen then r.sources[#r.sources + 1] = label end
                if node.step.trainer and tonumber(node.step.trainer.cost) then r.stepCost = node.step.trainer.cost end
              end
              for _, label in ipairs(sourceLabels(node)) do
                local seen = false
                for _, existing in ipairs(r.sources) do if existing == label then seen = true end end
                if not seen then r.sources[#r.sources + 1] = label end
              end
              for _, alt in ipairs(node.altSources or {}) do
                r.altHolders[alt.name] = math.max(r.altHolders[alt.name] or 0, alt.count)
              end
              for _, option in ipairs(node.options or {}) do
                if option.kind == "alt" and option.name then
                  r.altHolders[option.name] = math.max(r.altHolders[option.name] or 0, option.count or 0)
                end
              end
            end
            local goalName = result.goals[#result.goals].name
            local listed = false
            for _, g in ipairs(r.goals) do if g == goalName then listed = true end end
            if not listed then r.goals[#r.goals + 1] = goalName end
          elseif node.itemID then
            claimedByExcluded[node.itemID] = (claimedByExcluded[node.itemID] or 0) + (node.owned or 0)
          end
        end
      end
    end
  end

  -- Keep only rows that still need something; compute owned/reserved and totals.
  -- Owned = units physically there for this row (capped at Total); Reserved =
  -- the part of Owned held by goals not on the list; Missing = Total - usable.
  local kept = {}
  for _, r in ipairs(result.rows) do
    if r.missing > 0 then
      r.category = r.category or "buy"
      r.usable = r.owned
      local held = r.itemID and math.min(claimedByExcluded[r.itemID] or 0, math.max(0, (stock[r.itemID] or 0) - r.usable)) or 0
      r.owned = math.min(r.total, r.usable + held)
      r.reserved = r.owned - r.usable
      kept[#kept + 1] = r
      result.counts.all = result.counts.all + 1
      result.counts[r.category] = (result.counts[r.category] or 0) + 1
      if r.bought then result.counts.bought = result.counts.bought + 1 end
      result.units.total = result.units.total + r.total
      result.units.owned = result.units.owned + r.usable
      result.units.missing = result.units.missing + r.missing
      result.units.reserved = result.units.reserved + r.reserved
      -- Estimated cost from the price boundary (vendor and AH prices); a
      -- train step costs what the trainer charges.
      local unit = r.step and r.stepCost or (r.itemID and opts.priceOf and opts.priceOf(r.itemID)) or nil
      if type(unit) == "number" then
        r.unitPrice = unit
        r.cost = unit * r.missing
        result.cost.known = result.cost.known + r.cost
        result.cost.pricedRows = result.cost.pricedRows + 1
        if r.bought then
          result.cost.bought = result.cost.bought + r.cost
        else
          result.cost.remaining = result.cost.remaining + r.cost
        end
        r.affordable = ShoppingList.Affordable(r.cost, opts.gold)
      elseif r.category ~= "craft" and r.category ~= "alt" then
        result.cost.unpricedRows = result.cost.unpricedRows + 1
      end
      -- Mail plan: which alt can send how much of this.
      local remaining = r.missing
      local holders = {}
      for name, count in pairs(r.altHolders) do holders[#holders + 1] = { name = name, count = count } end
      table.sort(holders, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
      end)
      for _, holder in ipairs(holders) do
        if remaining <= 0 then break end
        local send = math.min(remaining, holder.count)
        if send > 0 then
          local plan
          for _, m in ipairs(result.mail) do if m.name == holder.name then plan = m end end
          if not plan then
            plan = { name = holder.name, items = {}, units = 0 }
            result.mail[#result.mail + 1] = plan
          end
          plan.items[#plan.items + 1] = { itemID = r.itemID, count = send }
          plan.units = plan.units + send
          remaining = remaining - send
        end
      end
    end
  end
  result.rows = kept
  table.sort(result.mail, function(a, b)
    if a.units ~= b.units then return a.units > b.units end
    return a.name < b.name
  end)
  result.units.percent = result.units.total > 0 and math.floor(result.units.owned * 100 / result.units.total + 0.5) or 100
  ShoppingList.Sort(result.rows, opts.sort or "missing", nameOf)
  -- Can you pay for what is still to buy? Current gold first, then the
  -- account (alts' snapshotted gold, reachable by mailing).
  local gold = opts.gold
  local remaining = result.cost.remaining
  local aff = { remaining = remaining, unpriced = result.cost.unpricedRows, status = "unknown" }
  if type(gold) == "table" and (type(gold.current) == "number" or type(gold.account) == "number") then
    aff.current = gold.current
    aff.account = gold.account
    aff.status = ShoppingList.Affordable(remaining, gold) or "unknown"
    if type(gold.current) == "number" then aff.shortNow = math.max(0, remaining - gold.current) end
    if type(gold.account) == "number" then aff.shortAccount = math.max(0, remaining - gold.account) end
    if type(gold.current) == "number" and type(gold.account) == "number" then aff.altsGold = math.max(0, gold.account - gold.current) end
  end
  result.affordability = aff

  return result
end

-- Sorts rows in place: "missing" (default), "name", "total", "source".
function ShoppingList.Sort(rows, key, nameOf)
  nameOf = nameOf or function(itemID) return tostring(itemID) end
  local order = { buy = 1, vendor = 2, gather = 3, craft = 4, learn = 5, alt = 6 }
  local function label(r) return r.name or nameOf(r.itemID) end
  table.sort(rows, function(a, b)
    if a.bought ~= b.bought then return not a.bought end
    if key == "name" then
      local na, nb = label(a), label(b)
      if na ~= nb then return na < nb end
    elseif key == "total" then
      if a.total ~= b.total then return a.total > b.total end
    elseif key == "source" then
      local oa, ob = order[a.category] or 9, order[b.category] or 9
      if oa ~= ob then return oa < ob end
      if a.missing ~= b.missing then return a.missing > b.missing end
    else
      if a.missing ~= b.missing then return a.missing > b.missing end
    end
    if a.itemID and b.itemID then return a.itemID < b.itemID end
    return tostring(a.key or a.itemID) < tostring(b.key or b.itemID)
  end)
  return rows
end

-- Rows matching a filter tab ("all" or a category).
function ShoppingList.Filter(rows, category)
  if not category or category == "all" then return rows end
  local out = {}
  for _, r in ipairs(rows) do
    if r.category == category then out[#out + 1] = r end
  end
  return out
end

-- One sentence on whether the remaining cost is payable. moneyFn formats copper.
function ShoppingList.AffordabilityText(aff, moneyFn)
  moneyFn = moneyFn or function(c) return tostring(c) .. "c" end
  if not aff or aff.status == "unknown" then return nil end
  local unpriced = aff.unpriced > 0 and string.format(" (%d item%s unpriced)", aff.unpriced, aff.unpriced == 1 and "" or "s") or ""
  if aff.remaining <= 0 then
    return "Nothing left to pay for" .. unpriced
  end
  if aff.status == "now" then
    return string.format("Affordable now: %s of your %s%s", moneyFn(aff.remaining), moneyFn(aff.current), unpriced)
  elseif aff.status == "account" then
    return string.format("Short by %s on this character; alts hold %s, so the account covers it%s", moneyFn(aff.shortNow), moneyFn(aff.altsGold or 0), unpriced)
  end
  if aff.shortAccount then
    return string.format("Not affordable: short by %s even with every character's gold%s", moneyFn(aff.shortAccount), unpriced)
  end
  return string.format("Not affordable: short by %s%s", moneyFn(aff.shortNow or aff.remaining), unpriced)
end

-- Chat-ready lines. linkOf(itemID) may return an item link; falls back to the name.
-- moneyFn(copper) formats money for the cost line (optional).
function ShoppingList.Lines(list, nameOf, linkOf, moneyFn)
  nameOf = nameOf or function(itemID) return "Item " .. tostring(itemID) end
  local lines = {}
  local goalNames = {}
  for _, g in ipairs(list.goals) do
    if g.included then goalNames[#goalNames + 1] = g.name end
  end
  lines[#lines + 1] = string.format("Shopping list (%d item%s for %s): %d of %d units in hand",
    #list.rows, #list.rows == 1 and "" or "s", #goalNames > 0 and table.concat(goalNames, ", ") or "no goals",
    list.units.owned, list.units.total)
  local affordText = ShoppingList.AffordabilityText(list.affordability, moneyFn)
  if affordText then
    lines[#lines + 1] = "  Cost: " .. affordText
  end
  for _, r in ipairs(list.rows) do
    if r.step then
      lines[#lines + 1] = string.format("  %sTrain %s - %s%s", r.bought and "[done] " or "", r.name or "recipe",
        #r.sources > 0 and table.concat(r.sources, ", ") or "trainer",
        r.cost and moneyFn and (" - " .. moneyFn(r.cost)) or "")
    else
      local label = linkOf and linkOf(r.itemID) or nameOf(r.itemID)
      lines[#lines + 1] = string.format("  %s%d x %s - %s%s", r.bought and "[bought] " or "", r.missing, label,
        #r.sources > 0 and table.concat(r.sources, ", ") or ShoppingList.CategoryLabels[r.category] or "?",
        r.reserved > 0 and string.format(" (%d reserved by other goals)", r.reserved) or "")
    end
  end
  for _, plan in ipairs(list.mail) do
    local parts = {}
    for _, item in ipairs(plan.items) do parts[#parts + 1] = string.format("%d x %s", item.count, nameOf(item.itemID)) end
    lines[#lines + 1] = string.format("  Mail from %s: %s", plan.name, table.concat(parts, ", "))
  end
  return lines
end
