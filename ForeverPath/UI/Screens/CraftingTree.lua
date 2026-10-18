-- Screen 03: recursive dependency tree (the "Dependency Tree" tab of the
-- Crafting screen). Renders Planner views (view.tree) and lets the player pick
-- a route per reagent. No calculations happen here.
local _, ns = ...

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local C = Theme.Colors
local R = ns.DependencyResolver

local CraftingTree = {}
ns.UI.CraftingTree = CraftingTree

local ROW = 38
local GUIDE = 18
local SIDE = 252
local COLS = { have = 44, status = 70, via = 104, cost = 62 }
local MAX_OPTIONS = 3

local STATUS_BADGE = { have = { "Have", "ok" }, partial = { "Partial", "partial" }, missing = { "Missing", "missing" } }

local function nameOf(itemID)
  return ns.ItemProvider.GetName(itemID)
end

-- "Craft - Tailoring", "AH", "In bags" ... for the Get via column.
-- The root of a crafting tree is the thing being made: it never claims
-- inventory and always crafts. The root of an obtain tree behaves like any
-- other node (it is the item the player needs to get).
local function isCraftRoot(node)
  return node.depth == 0 and not node.claims and not node.step
end

local STEP_ICON = "Interface\\Icons\\INV_Misc_Book_09"

-- Name, icon and quality for a row: an item, or a step such as "train this recipe".
local function displayOf(node)
  if node.step then
    return { name = node.step.name, icon = node.step.icon or STEP_ICON, quality = 1, loaded = true }
  end
  return ns.ItemProvider.GetItem(node.itemID)
end

local function stepVia(step)
  local trainer = step.trainer
  if trainer and trainer.name then
    return "Train - " .. trainer.name .. (trainer.zone and (" (" .. trainer.zone .. ")") or "")
  end
  return "Train - " .. (step.professionName or "profession") .. " trainer"
end

local function viaText(node)
  if node.step then return stepVia(node.step) end
  if isCraftRoot(node) then
    return node.craft and node.craft.professionName and ("Craft - " .. node.craft.professionName) or "Craft"
  end
  if node.missing <= 0 then
    if (node.ownedAlts or 0) > 0 then
      local alt = node.altSources and node.altSources[1]
      return alt and ("Alt: " .. alt.name) or "Alts"
    end
    if (node.ownedBank or 0) > 0 and (node.ownedBags or 0) == 0 then return "Bank" end
    if (node.ownedBank or 0) > 0 then return "Bags + bank" end
    return "In bags"
  end
  if node.route == "alt" and node.hint then
    return "Alt: " .. (node.hint.name or "?")
  end
  if node.route == "altcraft" and node.hint then
    return "Craft on " .. (node.hint.name or "alt")
  end
  if node.route == "craft" and node.craft then
    local craft = node.craft
    local text
    if craft.combine then
      text = "Combine"
    else
      text = craft.professionName and ("Craft - " .. craft.professionName) or "Craft"
      if craft.unavailable then
        text = text .. " (" .. craft.unavailable .. ")"
      elseif not craft.learned and craft.crafter then
        text = text .. (craft.crafter.isCurrent and " (learn" or (" (" .. craft.crafter.name)) .. (craft.teachItemID and ", needs plans)" or ")")
      elseif not craft.learned then
        text = text .. " (not learned)"
      end
    end
    if node.blocked == "depth" then text = text .. " (depth limit)" end
    return text
  end
  if node.noRoute then return "No route (soulbound)" end
  if node.route == "buy" then
    if node.blocked == "cycle" then return "AH (recipe loops)" end
    if node.craftOption and not node.craftOption.learned then return "AH, or learn recipe" end
    if node.craftOption then return "AH (craft available)" end
    return "AH"
  end
  return R.RouteLabels[node.route] or "Obtain"
end

local function noteText(node)
  if node.step then
    if node.step.rank and node.step.rank > 1 then
      return string.format("needs %s %d", node.step.professionName or "skill", node.step.rank)
    end
    return node.step.trainer and node.step.trainer.name and "learn from trainer" or "trainer requirement not recorded yet"
  end
  if isCraftRoot(node) then
    return string.format("%d craft%s", node.craft and node.craft.crafts or 0, node.craft and node.craft.crafts == 1 and "" or "s")
  end
  local parts = {}
  if node.craft and node.missing > 0 then
    parts[#parts + 1] = string.format("%d craft%s", node.craft.crafts, node.craft.crafts == 1 and "" or "s")
    if node.craft.surplus > 0 then parts[#parts + 1] = string.format("+%d spare", node.craft.surplus) end
  elseif node.missing > 0 then
    parts[#parts + 1] = string.format("%d missing", node.missing)
  else
    parts[#parts + 1] = "on hand"
  end
  if (node.reserved or 0) > 0 then
    parts[#parts + 1] = string.format("%d reserved by earlier goals", node.reserved)
  end
  return table.concat(parts, " - ")
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------
local function createRow(content, index, tree)
  local row = Widgets.Frame(content, nil, { frameType = "Button", bg = C.raised, border = C.bronzeDim, alpha = 0, borderAlpha = 0 })
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW)
  row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW)
  local line = Widgets.HLine(row, C.black, 0.45)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  Widgets.SetColor(highlight, C.white, 0.03)

  row.guides = {}
  row.elbow = Widgets.Texture(row, C.guide, 1, "ARTWORK")
  row.elbow:SetHeight(1)
  row.stem = Widgets.Texture(row, C.guide, 1, "ARTWORK")
  row.stem:SetWidth(1)

  local chevron = CreateFrame("Button", nil, row)
  chevron:SetSize(16, 16)
  chevron.arrow = Widgets.Arrow(chevron, 8, "down", C.text2)
  chevron.arrow:SetPoint("CENTER", chevron, "CENTER", 0, 0)
  chevron:SetScript("OnClick", function()
    if row.node then tree:ToggleNode(row.node.key) end
  end)
  row.chevron = chevron

  row.icon = Widgets.ItemIcon(row, 28)
  row.name = Widgets.Text(row, "body", "")
  row.qty = Widgets.Text(row, "secondary", "")
  row.note = Widgets.Text(row, "note", "")

  row.cost = Widgets.Text(row, "secondaryBright", "", { justify = "RIGHT", width = COLS.cost })
  row.cost:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  row.via = Widgets.Text(row, "secondary", "", { width = COLS.via })
  row.via:SetPoint("RIGHT", row.cost, "LEFT", -10, 0)
  local statusFrame = CreateFrame("Frame", nil, row)
  statusFrame:SetSize(COLS.status, ROW)
  statusFrame:SetPoint("RIGHT", row.via, "LEFT", -10, 0)
  row.badge = Widgets.Badge(statusFrame, "", "ok")
  row.badge:SetPoint("LEFT", statusFrame, "LEFT", 0, 0)
  row.have = Widgets.Text(row, "number", "", { justify = "RIGHT", width = COLS.have })
  row.have:SetPoint("RIGHT", statusFrame, "LEFT", -10, 0)
  row.name:SetPoint("RIGHT", row.have, "LEFT", -10, 0)
  row.note:SetPoint("RIGHT", row.have, "LEFT", -10, 0)

  row:SetScript("OnClick", function()
    if row.node then tree:SelectNode(row.node.key) end
  end)
  Widgets.SetItemTooltip(row, function(self) return self.node and self.node.itemID end, function(self)
    local node = self.node
    if not node or isCraftRoot(node) then return nil end
    local lines = {
      node.depth == 0 and string.format("Needed: %d (goal target)", node.quantity)
        or string.format("Needed: %d (%d per craft of %s)", node.quantity, node.perCraft or 0, nameOf(tree.byKey and tree.byKey[node.parentKey] and tree.byKey[node.parentKey].itemID or 0)),
      string.format("Free for this goal: %d (bags %d%s)", node.available or 0, node.availableBags or 0, node.availableBank and (", bank " .. node.availableBank) or ""),
    }
    if (node.reserved or 0) > 0 then lines[#lines + 1] = string.format("Reserved by higher-priority goals: %d", node.reserved) end
    if node.craftOption then
      lines[#lines + 1] = string.format("Recipe: %s (%s)%s", node.craftOption.recipe.name or "?", node.craftOption.professionName or "?", node.craftOption.learned and "" or " - not learned")
    end
    lines[#lines + 1] = "Price: no data (CraftWise arrives later)"
    return lines
  end)

  -- Lays out guide lines, chevron, icon and name for the node's depth.
  function row:Layout(entry)
    local node = entry.node
    local depth = node.depth
    local x = 8
    for i = 1, #self.guides do self.guides[i]:Hide() end
    -- Vertical lines for ancestors that continue below this row.
    for level = 1, depth - 1 do
      if entry.guides[level] then
        local guide = self.guides[level]
        if not guide then
          guide = Widgets.Texture(self, C.guide, 1, "ARTWORK")
          guide:SetWidth(1)
          self.guides[level] = guide
        end
        guide:ClearAllPoints()
        guide:SetPoint("TOP", self, "TOPLEFT", x + (level - 1) * GUIDE + 8, 0)
        guide:SetPoint("BOTTOM", self, "BOTTOMLEFT", x + (level - 1) * GUIDE + 8, 0)
        guide:Show()
      end
    end
    if depth > 0 then
      local gx = x + (depth - 1) * GUIDE + 8
      self.stem:ClearAllPoints()
      self.stem:SetPoint("TOP", self, "TOPLEFT", gx, 0)
      if entry.isLast then
        self.stem:SetPoint("BOTTOM", self, "TOPLEFT", gx, -ROW / 2)
      else
        self.stem:SetPoint("BOTTOM", self, "BOTTOMLEFT", gx, 0)
      end
      self.stem:Show()
      self.elbow:ClearAllPoints()
      self.elbow:SetPoint("LEFT", self, "TOPLEFT", gx, -ROW / 2)
      self.elbow:SetWidth(GUIDE - 6)
      self.elbow:Show()
    else
      self.stem:Hide()
      self.elbow:Hide()
    end
    local left = x + depth * GUIDE + (depth > 0 and 6 or 0)
    self.chevron:ClearAllPoints()
    self.chevron:SetPoint("LEFT", self, "LEFT", left, 0)
    if entry.hasChildren then
      self.chevron:Show()
      if self.chevron.arrow.SetRotation then
        self.chevron.arrow:SetRotation(entry.collapsed and 0 or -math.pi / 2)
      end
    else
      self.chevron:Hide()
    end
    local size = depth == 0 and 28 or 24
    self.icon:SetSize(size, size)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("LEFT", self, "LEFT", left + 18, 0)
    self.name:ClearAllPoints()
    self.name:SetPoint("TOPLEFT", self.icon, "TOPRIGHT", 8, -1)
    self.name:SetPoint("RIGHT", self.have, "LEFT", -10, 0)
    self.note:ClearAllPoints()
    self.note:SetPoint("BOTTOMLEFT", self.icon, "BOTTOMRIGHT", 8, 1)
    self.note:SetPoint("RIGHT", self.have, "LEFT", -10, 0)
  end

  function row:SetSelected(selected)
    Widgets.SetBackdrop(self, C.raised, C.bronzeDim, selected and 1 or 0, selected and 1 or 0)
  end
  return row
end

---------------------------------------------------------------------------
-- Selected node panel
---------------------------------------------------------------------------
local function createOptionCard(parent, index, tree)
  local card = Widgets.Frame(parent, nil, { frameType = "Button", bg = Theme.RGB("#1C1B18"), border = C.line })
  card:SetHeight(38)
  local highlight = card:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(card)
  Widgets.SetColor(highlight, C.white, 0.03)
  card.title = Widgets.Text(card, "body", "")
  card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -5)
  card.detail = Widgets.Text(card, "small", "")
  card.detail:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 5)
  card.detail:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  card.cost = Widgets.Text(card, "secondary", "", { justify = "RIGHT", color = C.text3 })
  card.cost:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -5)
  card.best = Widgets.Badge(card, "Best", "gold")
  card.best:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, 6)
  card.title:SetPoint("RIGHT", card.cost, "LEFT", -6, 0)
  card:SetScript("OnClick", function(self)
    if self.option and self.node then tree:ApplyRoute(self.node, self.option) end
  end)
  return card
end

local function createSide(view, tree)
  local side = Widgets.Panel(view, "Selected node", { pad = 0 })
  side:SetWidth(SIDE)
  local body = side.body
  local icon = Widgets.ItemIcon(body, 32)
  icon:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -10)
  local name = Widgets.Text(body, "goalName", "")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -2)
  name:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local sub = Widgets.Text(body, "small", "")
  sub:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  sub:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local count = Widgets.Text(body, "bigNumber", "")
  count:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -8)
  local missing = Widgets.Text(body, "small", "", { color = C.missing, justify = "RIGHT" })
  missing:SetPoint("BOTTOM", count, "BOTTOM", 0, 2)
  missing:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local bar = Widgets.ProgressBar(body, 6, "gold")
  bar:SetPoint("TOPLEFT", count, "BOTTOMLEFT", 0, -5)
  bar:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local waysLabel = Widgets.Text(body, "label", "Ways to get more", { caps = true })
  waysLabel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -10)
  side.cards = {}
  for i = 1, MAX_OPTIONS do
    local card = createOptionCard(body, i, tree)
    if i == 1 then
      card:SetPoint("TOPLEFT", waysLabel, "BOTTOMLEFT", 0, -5)
    else
      card:SetPoint("TOPLEFT", side.cards[i - 1], "BOTTOMLEFT", 0, -4)
    end
    card:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    card:Hide()
    side.cards[i] = card
  end
  local alsoUsed = Widgets.Text(body, "small", "", { wrap = true })
  alsoUsed:SetPoint("TOPLEFT", side.cards[MAX_OPTIONS], "BOTTOMLEFT", 0, -8)
  alsoUsed:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local use = Widgets.Button(body, "Use crafting route", { primary = true, onClick = function()
    if side.node and side.alternative then tree:ApplyRoute(side.node, side.alternative) end
  end })
  use:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 12, 10)
  local link = Widgets.Button(body, "Link", { onClick = function()
    if side.node and side.node.itemID then CraftingTree.LinkItem(side.node.itemID) end
  end })
  link:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 10)
  local reset = Widgets.Button(body, "Default route", { onClick = function()
    if side.node and side.node.itemID and tree.goal then
      ns.GoalService.SetRoute(tree.goal.id, side.node.itemID, nil)
      ns.UI.MainFrame.SetStatus("Route reset to default.", "info")
    end
  end })
  reset:SetPoint("RIGHT", link, "LEFT", -6, 0)
  reset:Hide()
  local empty = Widgets.EmptyState(body, "No component selected", "Click a row in the tree to see how to get it.")
  empty:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -40)
  empty:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -40)
  empty:SetHeight(80)
  side.icon, side.name, side.sub, side.count, side.missing, side.bar, side.waysLabel, side.alsoUsed, side.use, side.link, side.reset, side.empty =
    icon, name, sub, count, missing, bar, waysLabel, alsoUsed, use, link, reset, empty
  side.content = { icon, name, sub, count, missing, bar, waysLabel, alsoUsed, use, link }

  function side:Render(node, goalID)
    self.node = node
    if not node then
      for _, w in ipairs(self.content) do w:Hide() end
      for _, card in ipairs(self.cards) do card:Hide() end
      reset:Hide()
      empty:Show()
      self:SetTitle("Selected node")
      return
    end
    empty:Hide()
    for _, w in ipairs(self.content) do w:Show() end
    local item = displayOf(node)
    self:SetTitle(node.depth == 0 and "Goal item" or (node.step and "Step" or "Selected node"))
    icon:SetItem(item.icon, item.quality)
    name:SetText(Theme.QualityText(item.name or ("Item " .. tostring(node.itemID)), item.quality))
    if node.step then
      local trainer = node.step.trainer
      sub:SetText(trainer and trainer.name
        and string.format("Train at %s%s%s", trainer.name, trainer.zone and (" - " .. trainer.zone) or "", trainer.subzone and (" (" .. trainer.subzone .. ")") or "")
        or string.format("Train at any %s trainer (requirement recorded on your next visit)", node.step.professionName or "profession"))
      count:SetText(string.format("%d|r %s/ %d", 0, Theme.Hex.text3, 1))
      missing:SetText(node.step.rank and node.step.rank > 1 and string.format("needs %s %d", node.step.professionName or "skill", node.step.rank) or "1 step")
      bar:SetKind("gold")
      bar:SetValue(0)
      waysLabel:SetText(Theme.Upper(trainer and trainer.cost and trainer.cost > 0 and ("Training cost: " .. Widgets.Money(trainer.cost, true)) or "Training"))
    elseif isCraftRoot(node) then
      sub:SetText(string.format("Goal target - %d craft%s", node.craft and node.craft.crafts or 0, node.craft and node.craft.crafts == 1 and "" or "s"))
      count:SetText(string.format("%d|r %s/ %d", 0, Theme.Hex.text3, node.quantity))
      missing:SetText(string.format("%d to craft", node.quantity))
      bar:SetKind("gold")
      bar:SetValue(node.childrenResolved and 1 or 0)
      waysLabel:SetText(Theme.Upper("Reagents"))
    else
      sub:SetText(node.depth == 0 and ("Goal item - " .. viaText(node)) or string.format("Depth %d - %s", node.depth, viaText(node)))
      count:SetText(string.format("%s%d|r %s/ %d", Theme.Hex[node.missing > 0 and (node.owned > 0 and "partial" or "missing") or "ok"], node.available or 0, Theme.Hex.text3, node.quantity))
      missing:SetText(node.missing > 0 and string.format("%d missing", node.missing) or "complete")
      Widgets.SetTextColor(missing, node.missing > 0 and C.missing or C.ok)
      bar:SetKind(node.missing > 0 and "gold" or "ok")
      bar:SetValue(node.quantity > 0 and math.min(1, (node.owned or 0) / node.quantity) or 1)
      waysLabel:SetText(Theme.Upper(node.missing > 0 and string.format("Ways to get %d more", node.missing) or "Ways to get it"))
    end

    -- Option cards: craft (best when learned), buy, static hints.
    local options = {}
    if not isCraftRoot(node) then
      for _, option in ipairs(node.options or {}) do
        if #options < MAX_OPTIONS then options[#options + 1] = option end
      end
    else
      for _, child in ipairs(node.children) do
        if #options < MAX_OPTIONS then options[#options + 1] = { kind = "reagent", node = child } end
      end
    end
    self.alternative = nil
    for i, card in ipairs(self.cards) do
      local option = options[i]
      if option then
        card.option, card.node = option, node
        local isCurrent = option.kind == node.route
        local best = option.kind == "craft" and option.learned and not option.cycle and not node.raw
        if option.kind == "craft" then
          local reagents = {}
          for _, reagent in ipairs(option.recipe.reagents or {}) do
            reagents[#reagents + 1] = string.format("%d %s", reagent.quantity, nameOf(reagent.itemID))
          end
          if option.combine then
            card.title:SetText("Combine " .. (option.name or "the items"))
          else
            card.title:SetText(string.format("Craft with %s", option.professionName or "a profession"))
          end
          local state = ""
          if node.raw then
            state = "Gathering material: refining the tier below is off by default - "
          elseif option.combine then
            state = "Anyone can - "
          elseif not option.learned then
            if option.unavailable then
              state = "Recipe not learned: " .. (option.reason or "no crafter") .. " - "
            elseif option.crafter then
              state = (option.crafter.isCurrent and "You can learn it" or (option.crafter.name .. " can learn it")) .. (option.skill and option.skill.min > 1 and (" (" .. option.skill.min .. ")") or "") .. " - "
            else
              state = "Recipe not learned - "
            end
          end
          card.detail:SetText(state .. (option.cycle and "loops back to this item - " or "") .. table.concat(reagents, ", ") .. " per craft")
        elseif option.kind == "buy" then
          card.title:SetText("Buy on the Auction House")
          card.detail:SetText("No price source yet - CraftWise arrives later")
        elseif option.kind == "reagent" then
          card.title:SetText(string.format("%d x %s", option.node.quantity, nameOf(option.node.itemID)))
          card.detail:SetText(viaText(option.node))
          best = false
        else
          card.title:SetText(option.label or R.RouteLabels[option.kind] or "Obtain")
          card.detail:SetText((option.detail or "") .. ((option.kind == "alt" or option.kind == "altcraft") and " - mail planning arrives with the shopping list" or ""))
        end
        local optionPrice = (option.kind == "buy" or option.kind == "vendor") and ns.PriceProvider.GetPrice(node.itemID) or nil
        local costText
        if optionPrice and node.missing > 0 then
          costText = Widgets.Money(optionPrice.copper * node.missing, true) .. (isCurrent and Theme.ColorText("gold", " - current") or "")
        else
          costText = isCurrent and Theme.ColorText("gold", "current") or Theme.ColorText("text3", option.unavailable and "no gatherer" or "no price")
        end
        card.cost:SetText(costText)
        if best then
          Widgets.SetBackdrop(card, Theme.RGB("#2B2619"), C.gold)
          card.best:Show()
        else
          Widgets.SetBackdrop(card, Theme.RGB("#1C1B18"), isCurrent and C.bronzeDim or C.line)
          card.best:Hide()
        end
        if not isCurrent and not self.alternative and (option.kind == "craft" or option.kind == "buy") and not option.cycle then
          self.alternative = option
        end
        card:Show()
      else
        card:Hide()
      end
    end

    -- Also used by other goals.
    local trees = {}
    for id, v in pairs(ns.UI.MainFrame.views or {}) do trees[id] = v.tree end
    local uses = R.UsesOf(trees, node.itemID, goalID)
    if #uses > 0 then
      local parts = {}
      for _, use in ipairs(uses) do
        local goal = ns.GoalService.Store() and ns.GoalService.Store():Get(use.goalID)
        parts[#parts + 1] = string.format("%s x%d", goal and ns.GoalService.Name(goal) or use.goalID, use.quantity)
      end
      alsoUsed:SetText(Theme.ColorText("text2", "Also used by: ") .. table.concat(parts, ", "))
    else
      alsoUsed:SetText(node.depth == 0 and "" or Theme.ColorText("text3", "Not used by other goals"))
    end

    if isCraftRoot(node) or not self.alternative then
      use:Hide()
    else
      use:Show()
      use:SetLabel(self.alternative.kind == "craft" and "Use crafting route" or "Use buying route")
    end
    if not isCraftRoot(node) and node.routeSource == "override" then reset:Show() else reset:Hide() end
    link:SetEnabledState(item.link ~= nil)
  end
  return side
end

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
function CraftingTree.Create(screen)
  local view = CreateFrame("Frame", nil, screen)
  view.collapsed = {}
  view.filter = "all"

  local toolbar = CreateFrame("Frame", nil, view)
  toolbar:SetHeight(28)
  toolbar:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
  toolbar:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)
  local expand = Widgets.Button(toolbar, "Expand all", { onClick = function()
    view.collapsed = {}
    view:Render(view.view)
  end })
  expand:SetPoint("LEFT", toolbar, "LEFT", 0, 0)
  local collapse = Widgets.Button(toolbar, "Collapse all", { onClick = function()
    view.collapsed = {}
    if view.tree then
      for key, node in pairs(view.tree.byKey) do
        if node.depth > 0 and #node.children > 0 then view.collapsed[key] = true end
      end
    end
    view:Render(view.view)
  end })
  collapse:SetPoint("LEFT", expand, "RIGHT", 6, 0)
  local showLabel = Widgets.Text(toolbar, "label", "Show", { caps = true })
  showLabel:SetPoint("LEFT", collapse, "RIGHT", 18, 0)
  local filter = Widgets.Segment(toolbar, { { key = "all", label = "All" }, { key = "unresolved", label = "Unresolved only" } }, function(key)
    view.filter = key
    view:Render(view.view)
  end)
  filter:SetPoint("LEFT", showLabel, "RIGHT", 8, 0)
  view.expand, view.collapse, view.filterSegment = expand, collapse, filter

  local legend = { { "ok", "Have" }, { "partial", "Partial" }, { "missing", "Missing" }, { "gold", "Craftable" }, { "info", "AH" } }
  local previous
  for i = #legend, 1, -1 do
    local text = Widgets.Text(toolbar, "small", legend[i][2])
    local dot = Widgets.Dot(toolbar, legend[i][1])
    if previous then
      text:SetPoint("RIGHT", previous, "LEFT", -12, 0)
    else
      text:SetPoint("RIGHT", toolbar, "RIGHT", -2, 0)
    end
    dot:SetPoint("RIGHT", text, "LEFT", -4, 0)
    previous = dot
  end

  local side = createSide(view, view)
  side:SetPoint("TOPRIGHT", toolbar, "BOTTOMRIGHT", 0, -8)
  side:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
  view.side = side

  local main = Widgets.Panel(view, nil, { pad = 0 })
  main:SetPoint("TOPLEFT", toolbar, "BOTTOMLEFT", 0, -8)
  main:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -10, 0)
  local body = main.body
  local header = Widgets.Frame(body, nil, { bg = C.sidebar })
  header:SetHeight(26)
  header:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
  local headerLine = Widgets.HLine(header, C.black, 1)
  headerLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  local hCost = Widgets.Text(header, "tableHeader", "Est. cost", { caps = true, justify = "RIGHT", width = COLS.cost })
  hCost:SetPoint("RIGHT", header, "RIGHT", -10, 0)
  local hVia = Widgets.Text(header, "tableHeader", "Get via", { caps = true, width = COLS.via })
  hVia:SetPoint("RIGHT", hCost, "LEFT", -10, 0)
  local hStatus = Widgets.Text(header, "tableHeader", "Status", { caps = true, width = COLS.status })
  hStatus:SetPoint("RIGHT", hVia, "LEFT", -10, 0)
  local hHave = Widgets.Text(header, "tableHeader", "Have", { caps = true, justify = "RIGHT", width = COLS.have })
  hHave:SetPoint("RIGHT", hStatus, "LEFT", -10, 0)
  local hComponent = Widgets.Text(header, "tableHeader", "Component", { caps = true })
  hComponent:SetPoint("LEFT", header, "LEFT", 12, 0)

  local footer = Widgets.Frame(body, nil, { bg = C.sidebar })
  footer:SetHeight(40)
  footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  local footerLine = Widgets.HLine(footer, C.black, 1)
  footerLine:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
  footerLine:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
  local resolvedText = Widgets.Text(footer, "secondaryBright", "")
  resolvedText:SetPoint("LEFT", footer, "LEFT", 12, 0)
  local costText = Widgets.Text(footer, "secondary", "Unresolved cost: no price data", { color = C.text3, justify = "RIGHT" })
  costText:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
  local bar = Widgets.ProgressBar(footer, 6, "gold")
  bar:SetPoint("LEFT", resolvedText, "RIGHT", 12, 0)
  bar:SetPoint("RIGHT", costText, "LEFT", -12, 0)
  view.resolvedText, view.costText, view.bar = resolvedText, costText, bar

  local scroll = Widgets.ScrollArea(body)
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
  scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 1)
  view.scroll = scroll
  view.pool = Widgets.Pool(scroll.content, function(content, index) return createRow(content, index, view) end)
  view.message = Widgets.EmptyState(body, "", "")
  view.message:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -40)
  view.message:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -40)
  view.message:SetHeight(120)
  view.message:Hide()

  function view:ToggleNode(key)
    if self.collapsed[key] then self.collapsed[key] = nil else self.collapsed[key] = true end
    self:Render(self.view)
  end

  function view:SelectNode(key)
    self.selectedKey = key
    self:Render(self.view)
  end

  function view:ApplyRoute(node, option)
    if not self.goal or not node or isCraftRoot(node) then return end
    if option.kind ~= "craft" and option.kind ~= "buy" then
      ns.UI.MainFrame.SetStatus("That source is informational; routes can only be craft or buy.", "info")
      return
    end
    local ok, err = ns.GoalService.SetRoute(self.goal.id, node.itemID, option.kind)
    if ok then
      ns.UI.MainFrame.SetStatus(string.format("%s: %s route selected.", nameOf(node.itemID), option.kind == "craft" and "crafting" or "buying"), "ok")
    else
      ns.UI.MainFrame.SetStatus(tostring(err), "error")
    end
  end

  -- Renders a Planner view (uses view.tree). Nil or a view without a tree
  -- shows the status message instead.
  function view:Render(planView)
    self.view = planView
    self.goal = planView and planView.goal
    local tree = planView and planView.tree
    self.tree = tree
    self.byKey = tree and tree.byKey
    if not tree then
      self.pool:HideFrom(1)
      self.scroll:SetContentHeight(1)
      self.message:Set(planView and (ns.StatusLabel[planView.status] or "Unavailable") or "No goal", planView and planView.message or "")
      self.message:Show()
      self.resolvedText:SetText("")
      self.bar:SetValue(0)
      self.side:Render(nil)
      return
    end
    self.message:Hide()
    if not self.selectedKey or not tree.byKey[self.selectedKey] then
      -- Default to the first unresolved reagent, else the root.
      self.selectedKey = tree.root.key
      for _, child in ipairs(tree.root.children) do
        if child.missing > 0 then self.selectedKey = child.key break end
      end
    end
    local rows = R.Flatten(tree, { collapsed = self.collapsed, unresolvedOnly = self.filter == "unresolved" })
    local goalPercent = ns.Overview.Percent(planView)
    for index, entry in ipairs(rows) do
      local row = self.pool:Get(index)
      local node = entry.node
      row.node = node
      row:Layout(entry)
      local item = displayOf(node)
      row.icon:SetItem(item.icon, item.quality)
      row.name:SetText(Theme.QualityText(item.name or ("Item " .. tostring(node.itemID)), item.quality) .. (node.step and "" or Theme.ColorText("text2", "  x" .. node.quantity)))
      row.note:SetText(noteText(node))
      if node.step then
        row.have:SetText(Theme.ColorText("text3", "-"))
        row.badge:SetBadge("Train", "gold")
        local cost = node.step.trainer and node.step.trainer.cost
        row.cost:SetText(cost and cost > 0 and Widgets.Money(cost, true) or Theme.ColorText("text3", "?"))
      elseif isCraftRoot(node) then
        row.have:SetText(Theme.ColorText("text3", "-"))
        row.badge:SetBadge((goalPercent or 0) .. "%", "gold")
        row.cost:SetText(Theme.ColorText("text3", "?"))
      else
        row.have:SetText(string.format("%s%d|r%s/%d", Theme.Hex[node.status == "have" and "ok" or (node.status == "partial" and "partial" or "missing")], node.available or 0, Theme.Hex.text3, node.quantity))
        local badge = STATUS_BADGE[node.status] or STATUS_BADGE.missing
        row.badge:SetBadge(badge[1], badge[2])
        local price = node.missing > 0 and node.route ~= "craft" and ns.PriceProvider.GetPrice(node.itemID) or nil
        if price then
          row.cost:SetText(Widgets.Money(price.copper * node.missing, true))
        else
          row.cost:SetText(Theme.ColorText("text3", node.missing > 0 and (node.route == "craft" and "-" or "?") or "-"))
        end
      end
      row.via:SetText(viaText(node))
      Widgets.SetTextColor(row.via, node.route == "craft" and node.missing > 0 and C.gold or C.text2)
      row:SetSelected(node.key == self.selectedKey)
    end
    self.pool:HideFrom(#rows + 1)
    self.scroll:SetContentHeight(#rows * ROW)
    local summary = tree.summary
    self.resolvedText:SetText(string.format("%d of %d dependencies resolved", summary.resolved, summary.nodes))
    self.bar:SetKind(summary.nodes > 0 and summary.resolved == summary.nodes and "ok" or "gold")
    self.bar:SetValue(summary.nodes > 0 and summary.resolved / summary.nodes or 1)
    self.side:Render(tree.byKey[self.selectedKey], self.goal and self.goal.id)
  end

  return view
end

-- Inserts an item link into the open chat box, or prints it.
function CraftingTree.LinkItem(itemID)
  local item = ns.ItemProvider.GetItem(itemID)
  local link = item and item.link
  if not link then
    ns.UI.MainFrame.SetStatus("Item data not loaded yet.", "info")
    return false
  end
  local inserted = false
  if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
    inserted = ChatFrameUtil.InsertLink(link)
  elseif type(ChatEdit_InsertLink) == "function" then
    inserted = ChatEdit_InsertLink(link)
  end
  if not inserted then
    ns.Log.Print("%s", link)
  end
  return true
end
