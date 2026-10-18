-- Crafting > CraftWise tab: three strategy cards (buy the item, craft it,
-- hybrid) and the per-component breakdown, from the goal's full dependency
-- tree and the price boundary (vendor records + Auctionator scans).
local _, ns = ...

local Widgets = ns.UI.Widgets
local Theme = ns.UI.Theme
local C = Theme.Colors
local Util = ns.Util

local CraftWiseView = {}
ns.UI.CraftWiseView = CraftWiseView

local ROW = 27
local COLS = { buy = 86, craft = 86, hybrid = 86, choice = 80, price = 110 }

local function nameOf(itemID)
  return ns.ItemProvider.GetName(itemID)
end

local function money(copper, unknownText)
  if type(copper) ~= "number" then return Theme.ColorText("text3", unknownText or "?") end
  return Widgets.Money(copper, true)
end

local function listText(entries, limit)
  local parts = {}
  for i, entry in ipairs(entries) do
    if i > (limit or 4) then
      parts[#parts + 1] = string.format("+%d more", #entries - (limit or 4))
      break
    end
    if entry.itemID then
      parts[#parts + 1] = string.format("%d %s", entry.count or entry.crafts or 0, nameOf(entry.itemID))
    else
      parts[#parts + 1] = "train " .. (entry.name or "recipe")
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or "-"
end

---------------------------------------------------------------------------
-- Strategy cards
---------------------------------------------------------------------------
local function createCard(parent, key, title)
  local card = Widgets.Frame(parent, nil, { bg = Theme.RGB("#1C1B18"), border = C.line })
  card.key = key
  card.title = Widgets.Text(card, "goalName", title)
  card.title:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
  card.badge = Widgets.Badge(card, "Recommended", "gold")
  card.badge:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -10)
  card.badge:Hide()
  card.total = Widgets.Text(card, "bigNumber", "", { color = C.gold })
  card.total:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -6)
  card.lines = {}
  local previous = card.total
  for i = 1, 3 do
    local line = Widgets.Text(card, "small", "")
    line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -10 or -5)
    line:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    card.lines[i] = line
    previous = line
  end
  card.footer = Widgets.Text(card, "small", "", { color = C.text2 })
  card.footer:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 12, 10)
  card.footer:SetPoint("RIGHT", card, "RIGHT", -12, 0)
  return card
end

---------------------------------------------------------------------------
-- Breakdown rows
---------------------------------------------------------------------------
local function createRow(content, index)
  local row = CreateFrame("Button", nil, content)
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW)
  row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW)
  local line = Widgets.HLine(row, C.rowLine, 1)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  Widgets.HoverFill(row, C.white, 0.03)
  row.priceText = Widgets.Text(row, "small", "", { width = COLS.price - 14 })
  row.priceText:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  row.dot = Widgets.Dot(row, "ok")
  row.dot:SetPoint("RIGHT", row.priceText, "LEFT", -6, 0)
  row.choice = Widgets.Text(row, "secondary", "", { width = COLS.choice })
  row.choice:SetPoint("RIGHT", row.dot, "LEFT", -10, 0)
  row.hybrid = Widgets.Text(row, "secondaryBright", "", { justify = "RIGHT", width = COLS.hybrid })
  row.hybrid:SetPoint("RIGHT", row.choice, "LEFT", -10, 0)
  row.craft = Widgets.Text(row, "secondary", "", { justify = "RIGHT", width = COLS.craft })
  row.craft:SetPoint("RIGHT", row.hybrid, "LEFT", -10, 0)
  row.buy = Widgets.Text(row, "secondary", "", { justify = "RIGHT", width = COLS.buy })
  row.buy:SetPoint("RIGHT", row.craft, "LEFT", -10, 0)
  row.icon = Widgets.ItemIcon(row, 18)
  row.icon:SetPoint("LEFT", row, "LEFT", 10, 0)
  row.name = Widgets.Text(row, "secondaryBright", "")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
  row.name:SetPoint("RIGHT", row.buy, "LEFT", -10, 0)
  Widgets.SetItemTooltip(row, function(self) return self.itemID end, function(self)
    local r = self.row
    if not r then return nil end
    local lines = {}
    lines[#lines + 1] = string.format("Still needed: %d", r.quantity or 0)
    if r.node and r.node.step then
      local trainer = r.node.step.trainer
      lines[#lines + 1] = trainer and trainer.name and ("Train at " .. trainer.name .. (trainer.zone and (", " .. trainer.zone) or "")) or "Train at a profession trainer (not yet recorded)"
    elseif r.price then
      for _, text in ipairs(ns.PriceProvider.Describe(r.itemID, function(c) return Widgets.Money(c, true) end)) do lines[#lines + 1] = text end
    else
      lines[#lines + 1] = "No price recorded: open a vendor that sells it, or scan the Auction House with Auctionator."
    end
    if r.craftUnknown and r.craftUnknown > 0 then lines[#lines + 1] = string.format("Craft cost incomplete: %d component%s unpriced", r.craftUnknown, r.craftUnknown == 1 and "" or "s") end
    return lines
  end)
  return row
end

local CHOICE_COLOR = { craft = "gold", buy = "info", vendor = "info", owned = "ok", alt = "info", altcraft = "info", gather = "text2", drop = "text2", quest = "text2" }

---------------------------------------------------------------------------
-- The tab
---------------------------------------------------------------------------
function CraftWiseView.Create(screen)
  local view = CreateFrame("Frame", nil, screen)

  local top = CreateFrame("Frame", nil, view)
  top:SetHeight(26)
  top:SetPoint("TOPLEFT", view, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, 0)
  local icon = Widgets.ItemIcon(top, 22)
  icon:SetPoint("LEFT", top, "LEFT", 2, 0)
  local title = Widgets.Text(top, "goalName", "")
  title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
  local badge = Widgets.Badge(top, "Cached", "info")
  badge:SetPoint("LEFT", title, "RIGHT", 10, 0)
  local scanText = Widgets.Text(top, "small", "")
  scanText:SetPoint("LEFT", badge, "RIGHT", 10, 0)
  local rescan = Widgets.Text(top, "small", "Rescan at the Auction House with Auctionator", { color = C.text3, justify = "RIGHT" })
  rescan:SetPoint("RIGHT", top, "RIGHT", -4, 0)
  view.icon, view.title, view.badge, view.scanText = icon, title, badge, scanText

  local cards = {
    createCard(view, "buy", "Buy finished item"),
    createCard(view, "craft", "Craft item"),
    createCard(view, "hybrid", "Hybrid strategy"),
  }
  local CARD_HEIGHT = 150
  for i, card in ipairs(cards) do
    card:SetHeight(CARD_HEIGHT)
    if i == 1 then
      card:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -8)
    else
      card:SetPoint("TOPLEFT", cards[i - 1], "TOPRIGHT", 10, 0)
    end
  end
  view.cards = cards
  view:SetScript("OnSizeChanged", function(self, width)
    local w = math.max(120, math.floor(((width or self:GetWidth() or 600) - 20) / 3))
    for _, card in ipairs(cards) do card:SetWidth(w) end
  end)
  local usePlan = Widgets.Button(cards[3], "Use this plan", { primary = true, onClick = function()
    view:UsePlan()
  end })
  usePlan:SetPoint("BOTTOMRIGHT", cards[3], "BOTTOMRIGHT", -10, 8)
  cards[3].footer:SetPoint("RIGHT", usePlan, "LEFT", -8, 0)
  view.usePlan = usePlan

  -- Breakdown table
  local table_ = Widgets.Panel(view, nil, { pad = 0 })
  table_:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -10)
  table_:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", 0, 0)
  local body = table_.body
  local header = Widgets.Frame(body, nil, { bg = C.sidebar })
  header:SetHeight(26)
  header:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
  local headerLine = Widgets.HLine(header, C.black, 1)
  headerLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  local hPrice = Widgets.Text(header, "tableHeader", "Price data", { caps = true, width = COLS.price })
  hPrice:SetPoint("RIGHT", header, "RIGHT", -10, 0)
  local hChoice = Widgets.Text(header, "tableHeader", "Choice", { caps = true, width = COLS.choice })
  hChoice:SetPoint("RIGHT", hPrice, "LEFT", -10, 0)
  local hHybrid = Widgets.Text(header, "tableHeader", "Hybrid", { caps = true, justify = "RIGHT", width = COLS.hybrid })
  hHybrid:SetPoint("RIGHT", hChoice, "LEFT", -10, 0)
  local hCraft = Widgets.Text(header, "tableHeader", "Craft path", { caps = true, justify = "RIGHT", width = COLS.craft })
  hCraft:SetPoint("RIGHT", hHybrid, "LEFT", -10, 0)
  local hBuy = Widgets.Text(header, "tableHeader", "Buy (AH)", { caps = true, justify = "RIGHT", width = COLS.buy })
  hBuy:SetPoint("RIGHT", hCraft, "LEFT", -10, 0)
  local hComponent = Widgets.Text(header, "tableHeader", "Component", { caps = true })
  hComponent:SetPoint("LEFT", header, "LEFT", 36, 0)

  local footer = Widgets.Frame(body, nil, { bg = C.sidebar })
  footer:SetHeight(30)
  footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  local footerLine = Widgets.HLine(footer, C.black, 1)
  footerLine:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
  footerLine:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
  local totals = Widgets.Text(footer, "secondary", "")
  totals:SetPoint("LEFT", footer, "LEFT", 12, 0)
  local note = Widgets.Text(footer, "small", "Prices from your own scans, not live listings.", { color = C.text3, justify = "RIGHT" })
  note:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
  view.totals = totals

  local scroll = Widgets.ScrollArea(body)
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
  scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 1)
  view.scroll = scroll
  view.pool = Widgets.Pool(scroll.content, createRow)
  view.table = table_

  local empty = Widgets.EmptyState(view, "No price data",
    "CraftWise needs prices. Vendors are recorded when you open them; Auction House prices come from Auctionator scans. Open the Auction House, scan, and come back.")
  empty:SetPoint("TOPLEFT", view, "TOPLEFT", 0, -40)
  empty:SetPoint("TOPRIGHT", view, "TOPRIGHT", 0, -40)
  empty:SetHeight(120)
  empty:Hide()
  view.empty = empty
  view.content = { top, cards[1], cards[2], cards[3], table_ }

  function view:UsePlan()
    if not self.goal or not self.result then return end
    local goalID = self.goal.id
    local changed = ns.CraftWise.ApplyPlan(self.result, function(itemID, route)
      return ns.GoalService.SetRoute(goalID, itemID, route)
    end)
    ns.UI.MainFrame.SetStatus(string.format("CraftWise hybrid plan applied: %d component route%s set.", changed, changed == 1 and "" or "s"), "ok")
    ns.UI.MainFrame.RequestRefresh()
  end

  local function renderCard(card, result, strategy, lines, footerText)
    local cost = strategy.cost
    local unknown = strategy.unknown or 0
    local text = money(cost, "no price")
    if cost and unknown > 0 then text = text .. Theme.ColorText("text3", string.format(" (+%d unpriced)", unknown)) end
    if not cost and unknown > 0 and strategy ~= result.buy then text = Theme.ColorText("text3", string.format("%d component%s unpriced", unknown, unknown == 1 and "" or "s")) end
    card.total:SetText(text)
    for i, line in ipairs(card.lines) do line:SetText(lines[i] or "") end
    card.footer:SetText(footerText or "")
    local recommended = result.recommended == card.key
    if recommended then
      Widgets.SetBackdrop(card, Theme.RGB("#2B2619"), C.gold)
      card.badge:Show()
    else
      Widgets.SetBackdrop(card, Theme.RGB("#1C1B18"), C.line)
      card.badge:Hide()
    end
  end

  local function diffText(result, key)
    if not result.recommended or result.recommended == key then return "cheapest known plan" end
    local savings = result.savings and result.savings[key]
    if not savings then return "not comparable: price missing" end
    return string.format("%s more than %s", Widgets.Money(savings, true), ({ buy = "buying the item", craft = "crafting everything", hybrid = "the hybrid plan" })[result.recommended])
  end

  function view:Render(planView)
    self.view = planView
    self.goal = planView and planView.goal
    local tree = planView and (planView.fullTree or planView.tree)
    if not tree then
      for _, w in ipairs(self.content) do w:Hide() end
      self.empty:Set("Nothing to compare", planView and planView.message or "")
      self.empty:Show()
      self.result = nil
      return
    end
    local result = ns.CraftWise.Compare(tree, {
      priceOf = ns.PriceProvider.GetPrice,
      marketOf = ns.PriceProvider.GetMarket,
    })
    self.result = result
    local status = ns.PriceProvider.Status()
    if not result.available and not result.buy.cost then
      for _, w in ipairs(self.content) do w:Hide() end
      self.empty:Set("No price data", status.text .. ". Vendors are recorded when you open them; Auction House prices come from Auctionator scans.")
      self.empty:Show()
      return
    end
    self.empty:Hide()
    for _, w in ipairs(self.content) do w:Show() end

    local item
    if tree.root.step then
      item = { name = tree.root.step.name, icon = tree.root.step.icon or "Interface\\Icons\\INV_Misc_Note_01", quality = 1 }
    else
      item = ns.ItemProvider.GetItem(result.itemID)
    end
    self.icon:SetItem(item.icon, item.quality)
    self.title:SetText(Theme.QualityText(item.name or ("Item " .. tostring(result.itemID)), item.quality)
      .. Theme.ColorText("text2", tree.root.step and (tree.root.step.kind == "skill" and ("  " .. tostring(result.quantity) .. " crafts") or "") or ("  x" .. tostring(result.quantity))))
    if status.lastScan then
      self.badge:SetBadge("Cached", status.freshness and status.freshness.kind or "info")
      self.scanText:SetText("AH scan " .. (status.freshness and status.freshness.label or "?"))
    else
      self.badge:SetBadge("No scan", "partial")
      self.scanText:SetText(status.text)
    end

    local buy, craft, hybrid = result.buy, result.craft, result.hybrid
    renderCard(self.cards[1], result, buy, {
      "Lowest listing: " .. (buy.price and Widgets.Money(buy.price.copper, true) or Theme.ColorText("text3", "none seen")),
      "7-day average: " .. (buy.price and buy.price.avg7 and Widgets.Money(buy.price.avg7, true) or Theme.ColorText("text3", "-")),
      "Availability: " .. (buy.listings and (buy.listings .. " listed") or Theme.ColorText("text3", "unknown")),
    }, diffText(result, "buy"))
    local rootCraft = tree.root.craft
    renderCard(self.cards[2], result, craft, {
      "Buy all raw materials: " .. money(craft.cost),
      "Owned contribution: " .. (#hybrid.ownedList > 0 and (#hybrid.ownedList .. " item" .. (#hybrid.ownedList == 1 and "" or "s") .. " in bags") or "nothing on hand"),
      "Profession: " .. (rootCraft and rootCraft.professionName or (craft.possible and "known" or "no recipe")),
    }, craft.possible and diffText(result, "craft") or "no learned recipe")
    local hybridLines = {
      "Buy: " .. listText(hybrid.buyList),
      "Craft: " .. listText(hybrid.craftList),
      "Use owned: " .. listText(hybrid.ownedList),
    }
    if #hybrid.altList > 0 then hybridLines[3] = "From alts: " .. listText(hybrid.altList) end
    local hybridFooter
    if result.recommended == "hybrid" then
      local saved = result.savings and (result.savings.buy or result.savings.craft)
      local vs = result.savings and result.savings.buy and result.buy.cost or (result.savings and result.savings.craft and result.craft.cost) or nil
      if saved and vs and vs > 0 then
        hybridFooter = string.format("Saves %s (%d%%)", Widgets.Money(saved, true), math.floor(saved * 100 / vs + 0.5))
      else
        hybridFooter = "cheapest known plan"
      end
    else
      hybridFooter = diffText(result, "hybrid")
    end
    renderCard(self.cards[3], result, hybrid, hybridLines, hybridFooter)
    local mode = ns.CraftWise.Mode(result, self.goal and self.goal.routes)
    self.usePlan:SetEnabledState(mode ~= "hybrid" and next(result.plan) ~= nil)
    self.usePlan:SetLabel(mode == "hybrid" and "Plan in use" or "Use this plan")

    -- Breakdown
    local index = 0
    for _, r in ipairs(result.rows) do
      if r.depth > 0 then
        index = index + 1
        local row = self.pool:Get(index)
        row.itemID, row.row = r.itemID, r
        local step = r.node and r.node.step
        local info = step and { name = "Train: " .. (step.name or "recipe"), icon = step.icon or "Interface\\Icons\\INV_Misc_Book_09", quality = 1 } or ns.ItemProvider.GetItem(r.itemID)
        row.icon:SetItem(info.icon, info.quality)
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", row, "LEFT", 10 + (r.depth - 1) * 14, 0)
        row.name:SetText(Theme.QualityText(info.name or ("Item " .. tostring(r.itemID)), info.quality) .. (step and "" or Theme.ColorText("text2", "  x" .. tostring(r.quantity))))
        if r.quantity <= 0 then
          row.buy:SetText(Theme.ColorText("text3", "-"))
          row.craft:SetText(Theme.ColorText("text3", "-"))
          row.hybrid:SetText(Theme.ColorText("ok", "owned"))
        else
          row.buy:SetText(money(r.buy))
          row.craft:SetText(#r.node.children > 0 and money(r.craftPath) or Theme.ColorText("text3", "-"))
          row.hybrid:SetText(money(r.hybrid))
        end
        local label = ns.CraftWise.ChoiceLabels[r.choice] or r.choice or "?"
        row.choice:SetText(Theme.ColorText(CHOICE_COLOR[r.choice] or "text2", label))
        local f = r.freshness
        if r.quantity <= 0 or r.choice == "craft" then
          row.dot:SetKind("text3")
          row.priceText:SetText(Theme.ColorText("text3", r.choice == "craft" and "from components" or "-"))
        elseif f then
          row.dot:SetKind(f.kind)
          row.priceText:SetText(f.label)
        else
          row.dot:SetKind("missing")
          row.priceText:SetText(Theme.ColorText("text3", "no price"))
        end
      end
    end
    self.pool:HideFrom(index + 1)
    self.scroll:SetContentHeight(index * ROW)
    self.totals:SetText(string.format("Buy all materials %s   -   Hybrid %s%s", money(craft.cost), money(hybrid.cost),
      result.unpriced > 0 and Theme.ColorText("text3", string.format("   (%d unpriced)", result.unpriced)) or ""))
  end

  return view
end
