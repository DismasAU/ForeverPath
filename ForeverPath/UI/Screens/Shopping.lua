-- Screen 05: material shopping list across goals.
local _, ns = ...

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local C = Theme.Colors
local ShoppingList = ns.ShoppingList

ns.UI.Screens = ns.UI.Screens or {}

local ROW = 35
local COLS = { total = 44, owned = 44, reserved = 56, missing = 54, cost = 74, source = 150 }
local SORTS = { { key = "missing", label = "Sort: Missing" }, { key = "name", label = "Sort: Name" }, { key = "total", label = "Sort: Total" }, { key = "source", label = "Sort: Source" } }
local TABS = { { key = "all", label = "All" }, { key = "buy", label = "Auction House" }, { key = "vendor", label = "Vendors" }, { key = "gather", label = "Gathering" }, { key = "craft", label = "Craftable" }, { key = "learn", label = "To learn" }, { key = "alt", label = "From alts" } }
local STEP_ICON = "Interface\\Icons\\INV_Misc_Book_09"
local MAX_CHIPS = 4

local function sortLabel(key)
  for _, s in ipairs(SORTS) do if s.key == key then return s.label end end
  return SORTS[1].label
end

local function settings()
  if not ns.chardb then return { bought = {}, included = {}, sort = "missing", filter = "all" } end
  ns.chardb.shopping = ns.chardb.shopping or { bought = {}, included = {}, sort = "missing", filter = "all" }
  local s = ns.chardb.shopping
  s.bought = s.bought or {}
  s.included = s.included or {}
  return s
end

-- Included goals: explicit override, else active/queued.
local function isIncluded(goal)
  local override = settings().included[goal.id]
  if override ~= nil then return override end
  return ShoppingList.DefaultIncluded(goal)
end

local function createRow(content, index, screen)
  local row = Widgets.Frame(content, nil, { frameType = "Button" })
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW)
  row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW)
  local line = Widgets.HLine(row, C.black, 0.5)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  Widgets.SetColor(highlight, C.white, 0.03)

  row.bought = Widgets.Checkbox(row, "", function(checked)
    if row.key then
      local s = settings()
      s.bought[row.key] = checked and true or nil
      screen:Refresh()
    end
  end)
  row.bought:SetPoint("LEFT", row, "LEFT", 10, 0)
  row.bought:SetWidth(16)
  row.icon = Widgets.ItemIcon(row, 22)
  row.icon:SetPoint("LEFT", row, "LEFT", 32, 0)

  local sourceFrame = CreateFrame("Frame", nil, row)
  sourceFrame:SetSize(COLS.source, ROW)
  sourceFrame:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  sourceFrame.tags = {}
  row.sourceFrame = sourceFrame
  row.cost = Widgets.Text(row, "secondaryBright", "", { justify = "RIGHT", width = COLS.cost })
  row.cost:SetPoint("RIGHT", sourceFrame, "LEFT", -10, 0)
  row.missing = Widgets.Text(row, "body", "", { justify = "RIGHT", width = COLS.missing, color = C.missing })
  row.missing:SetPoint("RIGHT", row.cost, "LEFT", -10, 0)
  row.reserved = Widgets.Text(row, "body", "", { justify = "RIGHT", width = COLS.reserved })
  row.reserved:SetPoint("RIGHT", row.missing, "LEFT", -10, 0)
  row.owned = Widgets.Text(row, "body", "", { justify = "RIGHT", width = COLS.owned })
  row.owned:SetPoint("RIGHT", row.reserved, "LEFT", -10, 0)
  row.total = Widgets.Text(row, "body", "", { justify = "RIGHT", width = COLS.total })
  row.total:SetPoint("RIGHT", row.owned, "LEFT", -10, 0)
  row.name = Widgets.Text(row, "body", "")
  row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 0)
  row.name:SetPoint("RIGHT", row.total, "LEFT", -10, 0)
  row.note = Widgets.Text(row, "note", "")
  row.note:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 0)
  row.note:SetPoint("RIGHT", row.total, "LEFT", -10, 0)

  function row:SetTags(list)
    local previous
    for i, text in ipairs(list) do
      local tag = sourceFrame.tags[i]
      if not tag then
        tag = Widgets.Tag(sourceFrame, text)
        sourceFrame.tags[i] = tag
      end
      tag:SetTag(text)
      tag:ClearAllPoints()
      if previous then tag:SetPoint("LEFT", previous, "RIGHT", 4, 0) else tag:SetPoint("LEFT", sourceFrame, "LEFT", 0, 0) end
      tag:Show()
      previous = tag
    end
    for i = #list + 1, #sourceFrame.tags do sourceFrame.tags[i]:Hide() end
  end

  Widgets.SetItemTooltip(row, function(self) return self.itemID end, function(self)
    local r = self.entry
    if not r then return nil end
    local lines = { "Needed by: " .. table.concat(r.goals, ", ") }
    if r.reserved > 0 then lines[#lines + 1] = string.format("%d owned but reserved by goals not on this list", r.reserved) end
    for name, count in pairs(r.altHolders) do lines[#lines + 1] = string.format("%s has %d", name, count) end
    if r.unitPrice then
      lines[#lines + 1] = string.format("Price: %s each (%s for %d)", Widgets.Money(r.unitPrice, true), Widgets.Money(r.cost, true), r.missing)
      if r.affordable == "now" then
        lines[#lines + 1] = "Affordable with the gold you carry"
      elseif r.affordable == "account" then
        lines[#lines + 1] = "More than you carry; an alt's gold covers it (mail it over)"
      elseif r.affordable == "no" then
        lines[#lines + 1] = "Not affordable even with every character's gold"
      end
    else
      lines[#lines + 1] = "Price: no data (open a vendor that sells it, or scan the AH with Auctionator)"
    end
    return lines
  end)
  return row
end

local function Create(parent)
  local screen = CreateFrame("Frame", nil, parent)

  -- Header row: title, goal chips, send to chat
  local header = CreateFrame("Frame", nil, screen)
  header:SetHeight(26)
  header:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
  local title = Widgets.Text(header, "goalName", "Shopping List", { color = C.gold })
  title:SetPoint("LEFT", header, "LEFT", 2, 0)
  local send = Widgets.Button(header, "Send to chat", { onClick = function() screen:SendToChat() end })
  send:SetPoint("RIGHT", header, "RIGHT", 0, 0)
  screen.chips = {}
  local previous = title
  for i = 1, MAX_CHIPS do
    local chip
    chip = Widgets.Checkbox(header, "", function(checked)
      if chip.goalID then
        settings().included[chip.goalID] = checked
        screen:Refresh()
      end
    end)
    chip:SetPoint("LEFT", previous, "RIGHT", i == 1 and 18 or 14, 0)
    chip:Hide()
    screen.chips[i] = chip
    previous = chip
  end
  screen.chipsMore = Widgets.Text(header, "small", "", { color = C.text3 })
  screen.chipsMore:SetPoint("LEFT", previous, "RIGHT", 10, 0)
  screen.send = send

  -- Summary strip
  local summary = Widgets.Panel(screen, nil, { pad = 0 })
  -- Title (10 px) + value (20 px) + sub (11 px) need the Dashboard strip's
  -- height; at 58 px the in-game fonts overlap.
  summary:SetHeight(76)
  summary:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
  summary:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -8)
  screen.cells = {}
  local labels = { "Estimated total", "Can I afford it?", "Auction House", "Vendors", "Materials in hand" }
  for i = 1, 5 do
    local cell = CreateFrame("Frame", nil, summary.body)
    cell.title = Widgets.Text(cell, "label", labels[i], { caps = true })
    cell.title:SetPoint("TOPLEFT", cell, "TOPLEFT", 12, -10)
    cell.value = Widgets.Text(cell, "bigNumber", "")
    cell.value:SetPoint("TOPLEFT", cell.title, "BOTTOMLEFT", 0, -3)
    cell.value:SetPoint("RIGHT", cell, "RIGHT", -12, 0)
    -- Sub line and bar hang off the value (same as the Dashboard cells) so the
    -- spacing follows the real font heights instead of the cell's bottom edge.
    cell.sub = Widgets.Text(cell, "small", "")
    cell.sub:SetPoint("TOPLEFT", cell.value, "BOTTOMLEFT", 0, -5)
    cell.sub:SetPoint("RIGHT", cell, "RIGHT", -12, 0)
    cell.bar = Widgets.ProgressBar(cell, 6, "gold")
    cell.bar:SetPoint("TOPLEFT", cell.value, "BOTTOMLEFT", 0, -7)
    cell.bar:SetPoint("RIGHT", cell, "RIGHT", -12, 0)
    cell.bar:Hide()
    if i > 1 then
      local divider = Widgets.Engraved(summary.body, true)
      divider:SetHeight(56)
      divider:SetPoint("LEFT", cell, "LEFT", 0, 0)
    end
    screen.cells[i] = cell
  end
  summary.body:SetScript("OnSizeChanged", function(self, width, height)
    local w = math.floor((width or 0) / 5)
    for i, cell in ipairs(screen.cells) do
      cell:ClearAllPoints()
      cell:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * w, 0)
      cell:SetSize(math.max(w, 1), math.max(height or 0, 56))
    end
  end)
  screen.summary = summary

  -- Mail plan strip (only when alts hold something)
  local mail = Widgets.Frame(screen, nil, { bg = Theme.RGB("#1B222A"), border = Theme.RGB("#4A6A8A") })
  mail:SetHeight(30)
  mail:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -8)
  mail:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", 0, -8)
  mail.text = Widgets.Text(mail, "small", "", { color = C.text })
  mail.text:SetPoint("LEFT", mail, "LEFT", 12, 0)
  mail.text:SetPoint("RIGHT", mail, "RIGHT", -12, 0)
  mail:Hide()
  screen.mail = mail

  -- Tabs + sort
  local tabs = Widgets.Tabs(screen, TABS, function(key)
    settings().filter = key
    screen:Refresh()
  end)
  tabs:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -10)
  tabs:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", -200, -10)
  screen.tabs = tabs
  local sort = Widgets.Dropdown(screen, sortLabel("missing"), 150, function(self)
    local current = settings().sort or "missing"
    local items = {}
    for _, s in ipairs(SORTS) do items[#items + 1] = { text = s.label:gsub("Sort: ", ""), value = s.key, selected = s.key == current } end
    Widgets.Menu(self, items, function(value)
      settings().sort = value
      screen:Refresh()
    end)
  end)
  sort:SetPoint("BOTTOMRIGHT", tabs, "BOTTOMRIGHT", 200, 3)
  screen.sort = sort

  -- Table
  local table_ = Widgets.Panel(screen, nil, { pad = 0 })
  table_:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -1)
  table_:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  local body = table_.body
  local thead = Widgets.Frame(body, nil, { bg = C.sidebar })
  thead:SetHeight(26)
  thead:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  thead:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
  local theadLine = Widgets.HLine(thead, C.black, 1)
  theadLine:SetPoint("BOTTOMLEFT", thead, "BOTTOMLEFT", 0, 0)
  theadLine:SetPoint("BOTTOMRIGHT", thead, "BOTTOMRIGHT", 0, 0)
  local hSource = Widgets.Text(thead, "tableHeader", "Get from", { caps = true, width = COLS.source })
  hSource:SetPoint("RIGHT", thead, "RIGHT", -10, 0)
  local hCost = Widgets.Text(thead, "tableHeader", "Est. cost", { caps = true, justify = "RIGHT", width = COLS.cost })
  hCost:SetPoint("RIGHT", hSource, "LEFT", -10, 0)
  local hMissing = Widgets.Text(thead, "tableHeader", "Missing", { caps = true, justify = "RIGHT", width = COLS.missing })
  hMissing:SetPoint("RIGHT", hCost, "LEFT", -10, 0)
  local hReserved = Widgets.Text(thead, "tableHeader", "Reserved", { caps = true, justify = "RIGHT", width = COLS.reserved })
  hReserved:SetPoint("RIGHT", hMissing, "LEFT", -10, 0)
  local hOwned = Widgets.Text(thead, "tableHeader", "Owned", { caps = true, justify = "RIGHT", width = COLS.owned })
  hOwned:SetPoint("RIGHT", hReserved, "LEFT", -10, 0)
  local hTotal = Widgets.Text(thead, "tableHeader", "Total", { caps = true, justify = "RIGHT", width = COLS.total })
  hTotal:SetPoint("RIGHT", hOwned, "LEFT", -10, 0)
  local hMaterial = Widgets.Text(thead, "tableHeader", "Material", { caps = true })
  hMaterial:SetPoint("LEFT", thead, "LEFT", 62, 0)

  local footer = Widgets.Frame(body, nil, { bg = C.sidebar })
  footer:SetHeight(36)
  footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  local footerLine = Widgets.HLine(footer, C.black, 1)
  footerLine:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
  footerLine:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
  local note = Widgets.Text(footer, "small", "Reserved = owned, but held for a paused or excluded goal", { color = C.text3 })
  note:SetPoint("LEFT", footer, "LEFT", 12, 0)
  local clear = Widgets.Button(footer, "Clear bought", { onClick = function()
    settings().bought = {}
    screen:Refresh()
  end })
  clear:SetPoint("RIGHT", footer, "RIGHT", -10, 0)
  screen.clear = clear

  local scroll = Widgets.ScrollArea(body)
  scroll:SetPoint("TOPLEFT", thead, "BOTTOMLEFT", 0, -1)
  scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 1)
  screen.scroll = scroll
  screen.pool = Widgets.Pool(scroll.content, function(content, index) return createRow(content, index, screen) end)
  screen.empty = Widgets.EmptyState(body, "", "")
  screen.empty:SetPoint("TOPLEFT", thead, "BOTTOMLEFT", 0, -40)
  screen.empty:SetPoint("TOPRIGHT", thead, "BOTTOMRIGHT", 0, -40)
  screen.empty:SetHeight(100)
  screen.empty:Hide()

  function screen:Entries()
    local entries = {}
    for _, goal in ipairs(ns.GoalService.List({ open = true })) do
      entries[#entries + 1] = { goal = goal, view = ns.UI.MainFrame.views[goal.id] }
    end
    return entries
  end

  function screen:Build()
    local s = settings()
    return ShoppingList.Build(self:Entries(), { included = isIncluded, bought = s.bought, nameOf = ns.ItemProvider.GetName, sort = s.sort,
      priceOf = function(itemID)
        local info = ns.PriceProvider.GetPrice(itemID)
        return info and info.copper or nil
      end,
      gold = ns.CharacterProvider.AccountGold() })
  end

  function screen:SendToChat()
    local list = self.list or self:Build()
    for _, line in ipairs(ShoppingList.Lines(list, ns.ItemProvider.GetName, function(itemID)
      local item = ns.ItemProvider.GetItem(itemID)
      return item and item.link or nil
    end, function(copper) return Widgets.Money(copper, true) end)) do
      ns.Log.output(line)
    end
    ns.UI.MainFrame.SetStatus("Shopping list printed to your chat frame.", "ok")
  end

  function screen:Refresh()
    local s = settings()
    local list = self:Build()
    self.list = list

    -- Goal chips
    for i, chip in ipairs(self.chips) do
      local g = list.goals[i]
      if g then
        chip.goalID = g.goal.id
        chip.label:SetText(string.format("%s %sx%d|r", g.name, Theme.Hex.text2, g.quantity))
        chip:SetWidth(19 + (chip.label:GetStringWidth() or 40))
        chip:SetChecked(g.included)
        chip:Show()
      else
        chip.goalID = nil
        chip:Hide()
      end
    end
    self.chipsMore:SetText(#list.goals > MAX_CHIPS and string.format("+%d more", #list.goals - MAX_CHIPS) or "")

    -- Summary
    local cells = self.cells
    if list.cost.pricedRows > 0 then
      -- Compact "1g 50s" form: the coin-texture string at 20 px overlaps the sub line.
      cells[1].value:SetText(Widgets.Money(list.cost.known, true))
      cells[1].sub:SetText(list.cost.unpricedRows > 0 and string.format("vendor and AH prices - %d item%s unpriced", list.cost.unpricedRows, list.cost.unpricedRows == 1 and "" or "s") or "vendor and AH prices")
    else
      cells[1].value:SetText(Theme.ColorText("text3", "no price data"))
      cells[1].sub:SetText("open vendors to record prices; scan the AH with Auctionator")
    end
    local aff = list.affordability or { status = "unknown", remaining = 0, unpriced = 0 }
    local money = function(c) return Widgets.Money(c, true) end
    if list.cost.pricedRows == 0 or aff.status == "unknown" then
      cells[2].value:SetText(Theme.ColorText("text3", "?"))
      cells[2].sub:SetText(list.cost.pricedRows == 0 and "no prices to add up" or "gold unknown")
    elseif aff.remaining <= 0 then
      cells[2].value:SetText(Theme.ColorText("ok", "Nothing to pay"))
      cells[2].sub:SetText(list.cost.bought > 0 and "everything priced is marked bought" or "")
    elseif aff.status == "now" then
      cells[2].value:SetText(Theme.ColorText("ok", "Yes"))
      cells[2].sub:SetText(string.format("%s of your %s%s", money(aff.remaining), money(aff.current), aff.unpriced > 0 and " - some unpriced" or ""))
    elseif aff.status == "account" then
      cells[2].value:SetText(Theme.ColorText("partial", "With alts' gold"))
      cells[2].sub:SetText(string.format("short %s here; alts hold %s", money(aff.shortNow or 0), money(aff.altsGold or 0)))
    else
      cells[2].value:SetText(Theme.ColorText("missing", "No"))
      cells[2].sub:SetText(string.format("short %s%s", money(aff.shortAccount or aff.shortNow or aff.remaining), aff.shortAccount and " across the account" or ""))
    end
    cells[3].value:SetText(string.format("%d item%s", list.counts.buy, list.counts.buy == 1 and "" or "s"))
    cells[3].sub:SetText(list.counts.alt > 0 and string.format("%d from alts, %d craftable", list.counts.alt, list.counts.craft) or string.format("%d craftable", list.counts.craft))
    cells[4].value:SetText(string.format("%d item%s", list.counts.vendor, list.counts.vendor == 1 and "" or "s"))
    cells[4].sub:SetText(list.counts.bought > 0 and string.format("%d marked bought", list.counts.bought) or "no vendor data yet")
    cells[5].value:SetText(string.format("%d %s/ %d units|r", list.units.owned, Theme.Hex.text3, list.units.total))
    cells[5].sub:SetText("")
    cells[5].bar:SetKind(list.units.percent >= 100 and "ok" or "gold")
    cells[5].bar:SetValue(list.units.percent / 100)
    cells[5].bar:Show()

    -- Mail plan
    if #list.mail > 0 then
      local parts = {}
      for _, plan in ipairs(list.mail) do
        local items = {}
        for i, item in ipairs(plan.items) do
          if i <= 3 then items[#items + 1] = string.format("%d %s", item.count, ns.ItemProvider.GetName(item.itemID)) end
        end
        parts[#parts + 1] = string.format("%s%s|r can mail %s%s", Theme.Hex.info, plan.name, table.concat(items, ", "), #plan.items > 3 and string.format(" +%d more", #plan.items - 3) or "")
      end
      self.mail.text:SetText(table.concat(parts, "   |   "))
      self.mail:Show()
      tabs:ClearAllPoints()
      tabs:SetPoint("TOPLEFT", self.mail, "BOTTOMLEFT", 0, -10)
      tabs:SetPoint("TOPRIGHT", self.mail, "BOTTOMRIGHT", -200, -10)
    else
      self.mail:Hide()
      tabs:ClearAllPoints()
      tabs:SetPoint("TOPLEFT", summary, "BOTTOMLEFT", 0, -10)
      tabs:SetPoint("TOPRIGHT", summary, "BOTTOMRIGHT", -200, -10)
    end

    -- Tabs and sort
    for _, tab in ipairs(TABS) do
      local count = tab.key == "all" and list.counts.all or (list.counts[tab.key] or 0)
      tabs:SetLabel(tab.key, string.format("%s %s%d|r", tab.label, Theme.Hex.text3, count))
    end
    local filter = s.filter or "all"
    if filter ~= "all" and (list.counts[filter] or 0) == 0 then filter = "all" end
    tabs:Select(filter)
    sort:SetLabel(sortLabel(s.sort or "missing"))

    -- Rows
    local rows = ShoppingList.Filter(list.rows, filter)
    for index, r in ipairs(rows) do
      local row = self.pool:Get(index)
      local item = r.step and { name = r.name, icon = r.step.icon or STEP_ICON, quality = 1 } or ns.ItemProvider.GetItem(r.itemID)
      row.itemID = r.itemID
      row.key = r.key or r.itemID
      row.entry = r
      row.icon:SetItem(item.icon, item.quality)
      local name = item.name or ("Item " .. tostring(r.itemID))
      if r.step then name = "Train: " .. name end
      row.name:SetText(r.bought and Theme.ColorText("text3", name .. (r.step and "  (done)" or "  (bought)")) or Theme.QualityText(name, item.quality))
      row.note:SetText(#r.goals > 1 and string.format("%d goals: %s", #r.goals, table.concat(r.goals, ", ")) or (r.goals[1] or ""))
      row.total:SetText(tostring(r.total))
      row.owned:SetText(tostring(r.owned))
      Widgets.SetTextColor(row.owned, Widgets.CountColor(r.owned, r.total))
      row.reserved:SetText(r.reserved > 0 and tostring(r.reserved) or Theme.ColorText("text3", "-"))
      row.missing:SetText(tostring(r.missing))
      if r.cost then
        local mark = r.affordable == "now" and Theme.ColorText("ok", "+ ") or (r.affordable == "account" and Theme.ColorText("partial", "~ ") or (r.affordable == "no" and Theme.ColorText("missing", "! ") or ""))
        row.cost:SetText(mark .. Widgets.Money(r.cost, true))
      elseif r.category == "craft" then
        row.cost:SetText(Theme.ColorText("text3", "via craft"))
      elseif r.category == "alt" then
        row.cost:SetText(Theme.ColorText("text3", "via alt"))
      elseif r.step then
        row.cost:SetText(Theme.ColorText("text3", "train"))
      else
        row.cost:SetText(Theme.ColorText("text3", "?"))
      end
      row:SetTags(#r.sources > 0 and r.sources or { ShoppingList.CategoryLabels[r.category] or "?" })
      row.bought:SetChecked(r.bought)
      row:SetAlpha(r.bought and 0.5 or 1)
    end
    self.pool:HideFrom(#rows + 1)
    scroll:SetContentHeight(#rows * ROW)
    if #rows == 0 then
      if #list.goals == 0 then
        self.empty:Set("No open goals", "Add a goal from My Goals or the search box; its missing materials appear here.")
      elseif list.counts.all == 0 then
        self.empty:Set("Nothing to buy", "Every material for the selected goals is on hand (or reserved by goals not on this list).")
      else
        self.empty:Set("Nothing in this category", "Pick another tab.")
      end
      self.empty:Show()
    else
      self.empty:Hide()
    end
    clear:SetEnabledState(list.counts.bought > 0)
  end

  return screen
end

ns.UI.Screens.shopping = { label = "Shopping List", Create = Create }
