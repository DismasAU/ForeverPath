-- Screen 13: equipment. Every slot with what is worn, GearQuest Forever's
-- best pick for it and the goal that targets it; a slot panel with the
-- stat comparison and the other options, each one click from a goal.
local _, ns = ...

local Widgets = ns.UI.Widgets
local Theme = ns.UI.Theme
local C = Theme.Colors

ns.UI.Screens = ns.UI.Screens or {}

local SIDE = 262
local SLOT_ROW = 43
local OPTION_ROW = 30
local MAX_STATS = 8
local MAX_OPTIONS = 4
local LEFT_COLUMN = 9

local STATUS = { bis = { "Best in slot", "ok" }, upgrade = { "Upgrade found", "info" }, empty = { "Empty", "missing" } }

local function createSlotRow(parent, screen)
  local row = Widgets.Frame(parent, nil, { frameType = "Button" })
  row:SetHeight(SLOT_ROW)
  local line = Widgets.HLine(row, C.black, 0.45)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  Widgets.HoverFill(row, C.white, 0.03)
  local icon = Widgets.ItemIcon(row, 30)
  icon:SetPoint("LEFT", row, "LEFT", 8, 0)
  local slotLabel = Widgets.Text(row, "label", "", { caps = true })
  slotLabel:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -1)
  local badge = Widgets.Badge(row, "", "ok")
  badge:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  local name = Widgets.Text(row, "secondaryBright", "")
  name:SetPoint("TOPLEFT", slotLabel, "BOTTOMLEFT", 0, -2)
  name:SetPoint("RIGHT", badge, "LEFT", -8, 0)
  local goalLine = Widgets.Text(row, "note", "", { color = C.gold })
  goalLine:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
  goalLine:SetPoint("RIGHT", badge, "LEFT", -8, 0)
  row.icon, row.slotLabel, row.badge, row.name, row.goalLine = icon, slotLabel, badge, name, goalLine
  row:SetScript("OnClick", function(self)
    if self.slotKey then screen:Select(self.slotKey) end
  end)
  Widgets.SetItemTooltip(row, function(self) return self.itemID end)
  function row:SetSelected(selected)
    if selected then
      Widgets.SetBackdrop(self, C.raised, C.bronzeDim)
    elseif self.SetBackdrop then
      self:SetBackdrop(nil)
    end
  end
  return row
end

local function createOptionRow(content, index, screen)
  local row = CreateFrame("Frame", nil, content)
  row:SetHeight(OPTION_ROW)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * OPTION_ROW)
  row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * OPTION_ROW)
  local line = Widgets.HLine(row, C.rowLine, 1)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  local icon = Widgets.ItemIcon(row, 20)
  icon:SetPoint("LEFT", row, "LEFT", 0, 0)
  local add = Widgets.Button(row, "+ Goal", { width = 56, height = 20, onClick = function()
    if row.itemID then screen:AddGoalFor(row.itemID) end
  end })
  add:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  local name = Widgets.Text(row, "secondaryBright", "")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, 1)
  name:SetPoint("RIGHT", add, "LEFT", -6, 0)
  local meta = Widgets.Text(row, "note", "")
  meta:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 0)
  meta:SetPoint("RIGHT", add, "LEFT", -6, 0)
  row.icon, row.add, row.name, row.meta = icon, add, name, meta
  Widgets.SetItemTooltip(row, function(self) return self.itemID end)
  return row
end

local function Create(parent)
  local screen = CreateFrame("Frame", nil, parent)
  local EP = ns.EquipmentProvider

  -- Summary strip
  local strip = Widgets.Panel(screen, nil, { pad = 0 })
  strip:SetHeight(64)
  strip:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
  strip:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
  local sb = strip.body
  local cells = {}
  local previous
  for i, label in ipairs({ "Average item level", "Upgrades planned", "Tracked as goals" }) do
    local cell = CreateFrame("Frame", nil, sb)
    cell:SetSize(130, 44)
    if previous then cell:SetPoint("LEFT", previous, "RIGHT", 18, 0) else cell:SetPoint("LEFT", sb, "LEFT", 14, 0) end
    cell.title = Widgets.Text(cell, "label", label, { caps = true })
    cell.title:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
    cell.value = Widgets.Text(cell, "bigNumber", "")
    cell.value:SetPoint("TOPLEFT", cell.title, "BOTTOMLEFT", 0, -4)
    cells[i] = cell
    previous = cell
  end
  strip.cells = cells
  local source = Widgets.Dropdown(sb, "Source: Any", 150, function(self)
    local items = {}
    for _, g in ipairs(EP.SourceGroups) do
      items[#items + 1] = { text = g.label, value = g.key, selected = g.key == screen:SourceFilter() }
    end
    Widgets.Menu(self, items, function(value)
      if ns.chardb and ns.chardb.ui then ns.chardb.ui.equipmentSource = value end
      screen:Refresh()
    end)
  end)
  source:SetPoint("RIGHT", sb, "RIGHT", -12, 0)
  local segment = Widgets.Segment(sb, { { key = "all", label = "All slots" }, { key = "upgrades", label = "Upgrades only" } }, function(key)
    if ns.chardb and ns.chardb.ui then ns.chardb.ui.equipmentFilter = key end
    screen:Refresh()
  end)
  segment:SetPoint("RIGHT", source, "LEFT", -12, 0)
  screen.strip, screen.source, screen.segment = strip, source, segment

  -- Slot detail panel
  local side = Widgets.Panel(screen, "Slot", { pad = 0 })
  side:SetWidth(SIDE)
  side:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, -10)
  side:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  local body = side.body
  local wornLabel = Widgets.Text(body, "label", "Equipped", { caps = true })
  wornLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -10)
  local wornIcon = Widgets.ItemIcon(body, 26)
  wornIcon:SetPoint("TOPLEFT", wornLabel, "BOTTOMLEFT", 0, -4)
  Widgets.SetItemTooltip(wornIcon, function(self) return self.itemID end)
  local wornName = Widgets.Text(body, "secondaryBright", "")
  wornName:SetPoint("TOPLEFT", wornIcon, "TOPRIGHT", 8, 0)
  wornName:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local wornMeta = Widgets.Text(body, "note", "")
  wornMeta:SetPoint("BOTTOMLEFT", wornIcon, "BOTTOMRIGHT", 8, 0)
  wornMeta:SetPoint("RIGHT", body, "RIGHT", -12, 0)

  local target = Widgets.Frame(body, nil, { bg = Theme.RGB("#2B2619"), border = C.gold })
  target:SetHeight(50)
  target:SetPoint("TOPLEFT", wornIcon, "BOTTOMLEFT", 0, -10)
  target:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  target.label = Widgets.Text(target, "label", "Target", { caps = true, color = C.gold })
  target.label:SetPoint("TOPLEFT", target, "TOPLEFT", 8, -5)
  target.icon = Widgets.ItemIcon(target, 24)
  target.icon:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 8, 5)
  Widgets.SetItemTooltip(target.icon, function(self) return self.itemID end)
  target.name = Widgets.Text(target, "secondaryBright", "")
  target.name:SetPoint("TOPLEFT", target.icon, "TOPRIGHT", 6, 1)
  target.name:SetPoint("RIGHT", target, "RIGHT", -8, 0)
  target.meta = Widgets.Text(target, "note", "")
  target.meta:SetPoint("BOTTOMLEFT", target.icon, "BOTTOMRIGHT", 6, 0)
  target.meta:SetPoint("RIGHT", target, "RIGHT", -8, 0)
  target.state = Widgets.Text(target, "note", "", { justify = "RIGHT", color = C.gold })
  target.state:SetPoint("TOPRIGHT", target, "TOPRIGHT", -8, -5)

  local statsLabel = Widgets.Text(body, "label", "Compared with equipped", { caps = true })
  statsLabel:SetPoint("TOPLEFT", target, "BOTTOMLEFT", 0, -10)
  local statRows = {}
  previous = statsLabel
  for i = 1, MAX_STATS do
    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -4 or 0)
    row:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    row.label = Widgets.Text(row, "small", "")
    row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.delta = Widgets.Text(row, "small", "", { justify = "RIGHT", width = 44 })
    row.delta:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.new = Widgets.Text(row, "secondaryBright", "", { justify = "RIGHT", width = 44 })
    row.new:SetPoint("RIGHT", row.delta, "LEFT", -4, 0)
    row.arrow = Widgets.Text(row, "small", ">", { justify = "CENTER", width = 10, color = C.text3 })
    row.arrow:SetPoint("RIGHT", row.new, "LEFT", -2, 0)
    row.old = Widgets.Text(row, "small", "", { justify = "RIGHT", width = 44 })
    row.old:SetPoint("RIGHT", row.arrow, "LEFT", -2, 0)
    row:Hide()
    statRows[i] = row
    previous = row
  end
  local statsNote = Widgets.Text(body, "note", "Stats from the client's item data", { color = C.text3 })
  statsNote:SetPoint("TOPLEFT", statRows[MAX_STATS], "BOTTOMLEFT", 0, -2)

  local optionsLabel = Widgets.Text(body, "label", "Other options for this slot", { caps = true })
  optionsLabel:SetPoint("TOPLEFT", statsNote, "BOTTOMLEFT", 0, -10)
  local options = CreateFrame("Frame", nil, body)
  options:SetPoint("TOPLEFT", optionsLabel, "BOTTOMLEFT", 0, -4)
  options:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  options:SetHeight(MAX_OPTIONS * OPTION_ROW)
  local optionPool = Widgets.Pool(options, function(content, index) return createOptionRow(content, index, screen) end)
  local optionsEmpty = Widgets.Text(body, "small", "", { wrap = true, color = C.text3 })
  optionsEmpty:SetPoint("TOPLEFT", optionsLabel, "BOTTOMLEFT", 0, -6)
  optionsEmpty:SetPoint("RIGHT", body, "RIGHT", -12, 0)

  local openGoal = Widgets.Button(body, "Open goal", { primary = true, onClick = function()
    if side.goal then ns.UI.MainFrame.OpenGoal(side.goal.id) end
  end })
  openGoal:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 12, 10)
  local addTarget = Widgets.Button(body, "+ Goal for target", { onClick = function()
    if side.targetItemID then screen:AddGoalFor(side.targetItemID) end
  end })
  addTarget:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 10)
  side.wornLabel, side.wornIcon, side.wornName, side.wornMeta, side.target, side.statsLabel, side.statRows, side.statsNote, side.optionsLabel, side.options, side.optionPool, side.optionsEmpty, side.openGoal, side.addTarget =
    wornLabel, wornIcon, wornName, wornMeta, target, statsLabel, statRows, statsNote, optionsLabel, options, optionPool, optionsEmpty, openGoal, addTarget
  screen.side = side

  -- Equipped panel: two columns
  local equipped = Widgets.Panel(screen, "Equipped", { pad = 0 })
  equipped:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, -10)
  equipped:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -10, 0)
  local specText = Widgets.Text(equipped.header, "small", "", { justify = "RIGHT" })
  specText:SetPoint("RIGHT", equipped.header, "RIGHT", -10, 0)
  equipped.specText = specText
  local eb = equipped.body
  local divider = Widgets.Texture(eb, C.black, 1, "ARTWORK")
  divider:SetWidth(1)
  divider:SetPoint("TOP", eb, "TOP", 0, 0)
  divider:SetPoint("BOTTOM", eb, "BOTTOM", 0, 0)
  local left = CreateFrame("Frame", nil, eb)
  left:SetPoint("TOPLEFT", eb, "TOPLEFT", 0, 0)
  left:SetPoint("BOTTOMRIGHT", divider, "BOTTOMLEFT", 0, 0)
  local right = CreateFrame("Frame", nil, eb)
  right:SetPoint("TOPLEFT", divider, "TOPRIGHT", 0, 0)
  right:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", 0, 0)
  screen.slotRows = {}
  for index, slot in ipairs(EP.SLOTS) do
    local column = index <= LEFT_COLUMN and left or right
    local row = createSlotRow(column, screen)
    local position = index <= LEFT_COLUMN and index or index - LEFT_COLUMN
    row:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -(position - 1) * SLOT_ROW)
    row:SetPoint("TOPRIGHT", column, "TOPRIGHT", 0, -(position - 1) * SLOT_ROW)
    row.slotKey = slot.key
    screen.slotRows[slot.key] = row
  end
  screen.equipped = equipped
  screen.empty = Widgets.EmptyState(screen, "Equipment", "")
  screen.empty:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, -80)
  screen.empty:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, -80)
  screen.empty:SetHeight(120)
  screen.empty:Hide()

  function screen:SourceFilter()
    local ui = ns.chardb and ns.chardb.ui
    return ui and ui.equipmentSource or "any"
  end

  function screen:Select(slotKey)
    self.slotKey = slotKey
    if ns.chardb and ns.chardb.ui then ns.chardb.ui.equipmentSlot = slotKey end
    self:Refresh()
  end

  function screen:AddGoalFor(itemID)
    local goal, message = ns.GoalService.AddItemGoal(itemID, 1)
    ns.UI.MainFrame.SetStatus(message, goal and "ok" or "error")
    ns.UI.MainFrame.RequestRefresh()
    return goal
  end

  local function statText(value)
    if value == nil then return Theme.ColorText("text3", "-") end
    if value == math.floor(value) then return tostring(value) end
    return string.format("%.1f", value)
  end

  local function renderSide(self, analysis, entry)
    local s = self.side
    s.goal, s.targetItemID = nil, nil
    if not entry then
      s:SetTitle("Slot")
      return
    end
    s:SetTitle(entry.slot.label)
    local worn = entry.equipped
    if worn.itemID then
      s.wornIcon:SetItem(worn.icon, worn.quality)
      s.wornIcon.itemID = worn.itemID
      s.wornName:SetText(Theme.QualityText(worn.name or ("Item " .. worn.itemID), worn.quality))
      s.wornMeta:SetText(worn.ilvl and ("Item level " .. worn.ilvl) or "")
    else
      s.wornIcon:SetItem(nil, 1)
      s.wornIcon.itemID = nil
      s.wornName:SetText(Theme.ColorText("text3", "Nothing equipped"))
      s.wornMeta:SetText("")
    end
    -- Target: the goal's item when one exists, else GearQuest's best pick.
    local goal, best = entry.goal, entry.best
    local targetItemID = goal and goal.target.itemID or (best and best.itemID) or nil
    s.goal, s.targetItemID = goal, targetItemID
    local t = s.target
    if targetItemID then
      local info = ns.ItemProvider.GetItem(targetItemID)
      local candidate
      for _, c in ipairs(entry.candidates) do if c.itemID == targetItemID then candidate = c end end
      t.icon:SetItem(info.icon or (candidate and candidate.icon), info.quality or (candidate and candidate.quality))
      t.icon.itemID = targetItemID
      t.name:SetText(Theme.QualityText(info.name or (candidate and candidate.name) or ("Item " .. targetItemID), info.quality or (candidate and candidate.quality)))
      local metaParts = {}
      if candidate then
        metaParts[#metaParts + 1] = candidate.sourceLabel
        if candidate.zone then metaParts[#metaParts + 1] = candidate.zone end
      elseif goal then
        metaParts[#metaParts + 1] = goal.type == "CRAFT_ITEM" and "Crafting goal" or "Obtain goal"
      end
      t.meta:SetText(table.concat(metaParts, " - "))
      if goal then
        local percent = ns.Overview.Percent(entry.goalView)
        t.state:SetText(string.format("goal%s", percent and (" - " .. percent .. "%") or ""))
        t.label:SetText(Theme.Upper("Target - " .. (goal.type == "CRAFT_ITEM" and "crafting" or "obtain")))
      else
        t.state:SetText(candidate and candidate.rank == 1 and "best pick" or "pick")
        t.label:SetText(Theme.Upper("Target"))
      end
      t:Show()
    else
      t.icon:SetItem(nil, 1)
      t.icon.itemID = nil
      t.name:SetText(Theme.ColorText("text3", analysis.hasGearQuest and "No pick for this slot" or "No upgrade data"))
      t.meta:SetText(analysis.hasGearQuest and "" or "Install GearQuest Forever for per-slot hunts")
      t.state:SetText("")
      t.label:SetText(Theme.Upper("Target"))
      t:Show()
    end
    -- Stat comparison
    local oldStats = worn.itemID and ns.EquipmentProvider.Stats(worn.link or worn.itemID) or {}
    local newStats = targetItemID and ns.EquipmentProvider.Stats(ns.ItemProvider.GetItem(targetItemID).link or targetItemID) or {}
    local rows = {}
    for _, stat in ipairs(ns.EquipmentProvider.STATS) do
      local old, new = oldStats[stat.key], newStats[stat.key]
      if old ~= nil or new ~= nil then rows[#rows + 1] = { label = stat.label, old = old, new = new } end
    end
    for i, row in ipairs(s.statRows) do
      local r = rows[i]
      if r then
        row.label:SetText(r.label)
        row.old:SetText(statText(r.old))
        row.new:SetText(statText(r.new))
        if r.old ~= nil and r.new ~= nil then
          local delta = r.new - r.old
          row.delta:SetText(delta == 0 and Theme.ColorText("text3", "=") or ((delta > 0 and Theme.Hex.ok or Theme.Hex.missing) .. (delta > 0 and "+" or "") .. statText(delta) .. "|r"))
        else
          row.delta:SetText("")
        end
        row:Show()
      else
        row:Hide()
      end
    end
    s.statsNote:SetText(#rows == 0 and Theme.ColorText("text3", "No stat data yet (items load as the client caches them)") or Theme.ColorText("text3", "Stats from the client's item data"))
    -- Other options
    local shown = 0
    for _, candidate in ipairs(entry.candidates) do
      if candidate.itemID ~= targetItemID and candidate.itemID ~= worn.itemID and shown < MAX_OPTIONS then
        shown = shown + 1
        local row = s.optionPool:Get(shown)
        row.itemID = candidate.itemID
        row.icon:SetItem(candidate.icon, candidate.quality)
        row.name:SetText(Theme.QualityText(candidate.name, candidate.quality))
        row.meta:SetText(candidate.sourceLabel .. (candidate.ilvl and (" - ilvl " .. candidate.ilvl) or "") .. (candidate.zone and (" - " .. candidate.zone) or ""))
        local existing = ns.GoalService.Store() and (ns.GoalService.Store():FindByItem("CRAFT_ITEM", candidate.itemID) or ns.GoalService.Store():FindByItem("OBTAIN_ITEM", candidate.itemID))
        row.add:SetLabel(existing and "Goal" or "+ Goal")
        row.add:SetEnabledState(existing == nil)
      end
    end
    s.optionPool:HideFrom(shown + 1)
    if shown == 0 then
      s.optionsEmpty:SetText(analysis.hasGearQuest and "No other pick for this slot at your level, spec and faction." or "GearQuest Forever is not installed; options come from its hunt data.")
      s.optionsEmpty:Show()
    else
      s.optionsEmpty:Hide()
    end
    if goal then s.openGoal:Show() else s.openGoal:Hide() end
    local hasTargetGoal = targetItemID and ns.GoalService.Store() and (ns.GoalService.Store():FindByItem("CRAFT_ITEM", targetItemID) or ns.GoalService.Store():FindByItem("OBTAIN_ITEM", targetItemID)) or nil
    s.addTarget:SetEnabledState(targetItemID ~= nil and not hasTargetGoal)
    s.addTarget:SetLabel(hasTargetGoal and "Goal added" or "+ Goal for target")
  end

  function screen:Refresh()
    local EP = ns.EquipmentProvider
    if not EP or not EP.IsAvailable() then
      strip:Hide()
      equipped:Hide()
      side:Hide()
      self.empty:Set("Equipment unavailable", "This client does not expose the inventory API ForeverPath needs (GetInventoryItemID).")
      self.empty:Show()
      return
    end
    self.empty:Hide()
    strip:Show()
    equipped:Show()
    side:Show()
    local ui = ns.chardb and ns.chardb.ui or {}
    local filter = ui.equipmentFilter or "all"
    if segment.selected ~= filter then segment:Select(filter) end
    local sourceKey = self:SourceFilter()
    for _, g in ipairs(EP.SourceGroups) do
      if g.key == sourceKey then source:SetLabel("Source: " .. g.label) end
    end
    local goals = ns.GoalService.List({ open = true })
    local analysis = EP.Analyze({ source = sourceKey, goals = goals, views = ns.UI.MainFrame.views })
    self.analysis = analysis
    cells[1].value:SetText(tostring(analysis.averageIlvl))
    cells[2].value:SetText(tostring(analysis.upgradesPlanned))
    cells[3].value:SetText(tostring(analysis.trackedGoals))
    specText:SetText(analysis.hasGearQuest and ("Hunts for " .. (analysis.specLabel or "your class") .. " (GearQuest Forever)") or Theme.ColorText("text3", "GearQuest Forever not installed - no upgrade hunts"))

    local slotKey = self.slotKey or ui.equipmentSlot
    local selected
    for _, entry in ipairs(analysis.slots) do
      local row = self.slotRows[entry.slot.key]
      local worn = entry.equipped
      local hide = filter == "upgrades" and entry.status ~= "upgrade" and not entry.goal
      row.itemID = worn.itemID
      row.icon:SetItem(worn.icon, worn.quality)
      row.slotLabel:SetText(Theme.Upper(entry.slot.label))
      row.name:SetText(worn.itemID and Theme.QualityText(worn.name or ("Item " .. worn.itemID), worn.quality) or Theme.ColorText("text3", "Empty"))
      if entry.goal then
        local percent = ns.Overview.Percent(entry.goalView)
        row.goalLine:SetText(string.format("%s %s%s", Theme.ColorText("gold", "o"), ns.GoalService.Name(entry.goal), percent and (" - " .. percent .. "%") or ""))
        row.badge:Hide()
      else
        row.goalLine:SetText("")
        local badge = STATUS[entry.status]
        if badge and (entry.status ~= "empty" or analysis.hasGearQuest) then
          row.badge:SetBadge(badge[1], badge[2])
          row.badge:Show()
        else
          row.badge:Hide()
        end
      end
      row:SetAlpha(hide and 0.35 or 1)
      row:SetSelected(entry.slot.key == slotKey)
      if entry.slot.key == slotKey then selected = entry end
    end
    if not selected then
      selected = analysis.slots[1]
      slotKey = selected and selected.slot.key or nil
      for _, entry in ipairs(analysis.slots) do
        if entry.status == "upgrade" or entry.goal then selected = entry slotKey = entry.slot.key break end
      end
      if slotKey then self.slotRows[slotKey]:SetSelected(true) end
    end
    self.slotKey = slotKey
    renderSide(self, analysis, selected)
  end

  return screen
end

ns.UI.Screens.equipment = { label = "Equipment", Create = Create }
