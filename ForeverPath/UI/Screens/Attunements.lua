-- Screen 06: Attunement planner. Picks an attunement (the selected goal's
-- when it is one), shows the header with progress, the step timeline and
-- the current step. Data and progress come from AttuneProvider.
local _, ns = ...

local Widgets = ns.UI.Widgets
local Theme = ns.UI.Theme
local C = Theme.Colors

ns.UI.Screens = ns.UI.Screens or {}

local ROW = 38
local SIDE = 262

local STATE_BADGE = { done = { "Done", "ok" }, current = { "Current", "gold" }, locked = { "Locked", "text" } }

local function createStepRow(content, index)
  local row = Widgets.Frame(content, nil, { frameType = "Button" })
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW)
  row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW)
  Widgets.HoverFill(row, C.white, 0.03)
  -- Timeline: a connector line and a node.
  row.connector = Widgets.Texture(row, Theme.RGB("#4A4335"), 1)
  row.connector:SetWidth(2)
  row.connector:SetPoint("TOP", row, "TOPLEFT", 22, 0)
  row.connector:SetPoint("BOTTOM", row, "BOTTOMLEFT", 22, 0)
  row.node = Widgets.Frame(row, nil, { bg = C.panel, border = Theme.RGB("#6B6352") })
  row.node:SetSize(14, 14)
  row.node:SetPoint("CENTER", row, "LEFT", 22, 0)
  row.nodeMark = Widgets.Text(row.node, "label", "", { justify = "CENTER" })
  row.nodeMark:SetPoint("CENTER", row.node, "CENTER", 0, 0)
  row.number = Widgets.Text(row, "label", "", { justify = "RIGHT", width = 20 })
  row.number:SetPoint("LEFT", row, "LEFT", 38, 0)
  row.icon = Widgets.ItemIcon(row, 22)
  row.icon:SetPoint("LEFT", row, "LEFT", 62, 0)
  row.badge = Widgets.Badge(row, "Done", "ok")
  row.badge:SetPoint("RIGHT", row, "RIGHT", -12, 0)
  row.name = Widgets.Text(row, "body", "")
  row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, 1)
  row.name:SetPoint("RIGHT", row.badge, "LEFT", -10, 0)
  row.detail = Widgets.Text(row, "small", "")
  row.detail:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
  row.detail:SetPoint("RIGHT", row.badge, "LEFT", -10, 0)
  local line = Widgets.HLine(row, C.rowLine, 1)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 48, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  return row
end

local function Create(parent)
  local screen = CreateFrame("Frame", nil, parent)

  -- Picker row
  local top = CreateFrame("Frame", nil, screen)
  top:SetHeight(26)
  top:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
  local title = Widgets.Text(top, "title", "Attunements")
  title:SetPoint("LEFT", top, "LEFT", 2, 0)
  local picker = Widgets.Dropdown(top, "Choose an attunement", 260, function(self)
    local items = {}
    local lastGroup
    for _, attune in ipairs(ns.AttuneProvider.List()) do
      if attune.group ~= lastGroup then
        items[#items + 1] = { text = Theme.ColorText("text3", string.upper(attune.group)), value = nil, header = true }
        lastGroup = attune.group
      end
      items[#items + 1] = { text = attune.name .. (attune.levels and Theme.ColorText("text3", "  " .. attune.levels) or ""), value = attune.id, selected = attune.id == screen.attuneID }
    end
    Widgets.Menu(self, items, function(value)
      if value then screen:Select(value) end
    end, 300)
  end)
  picker:SetPoint("LEFT", title, "RIGHT", 16, 0)
  local addGoal = Widgets.Button(top, "+ Add goal", { primary = true, width = 110, onClick = function()
    if screen.attuneID then
      local goal, message = ns.GoalService.AddAttunementGoal(screen.attuneID)
      ns.UI.MainFrame.SetStatus(message, goal and "ok" or "error")
      ns.UI.MainFrame.RequestRefresh()
    end
  end })
  addGoal:SetPoint("RIGHT", top, "RIGHT", 0, 0)
  screen.picker, screen.addGoal = picker, addGoal

  -- Header panel
  local header = Widgets.Panel(screen, nil, { pad = 0 })
  header:SetHeight(96)
  header:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -8)
  header:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -8)
  local hb = header.body
  local icon = Widgets.ItemIcon(hb, 48)
  icon:SetPoint("TOPLEFT", hb, "TOPLEFT", 14, -14)
  local name = Widgets.Text(hb, "hero", "")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 14, -2)
  local meta = Widgets.Text(hb, "secondary", "")
  meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
  local chips = {}
  for i = 1, 3 do
    local chip = Widgets.Chip(hb, "info", "")
    if i == 1 then chip:SetPoint("TOPLEFT", meta, "BOTTOMLEFT", 0, -8) else chip:SetPoint("LEFT", chips[i - 1], "RIGHT", 6, 0) end
    chip:Hide()
    chips[i] = chip
  end
  local percent = Widgets.Text(hb, "bigNumberLarge", "", { color = C.gold, justify = "RIGHT" })
  percent:SetPoint("TOPRIGHT", hb, "TOPRIGHT", -18, -14)
  local progressLabel = Widgets.Text(hb, "label", "Progress", { caps = true })
  progressLabel:SetPoint("TOPLEFT", hb, "TOPRIGHT", -250, -20)
  local bar = Widgets.ProgressBar(hb, 10, "gold")
  bar:SetPoint("TOPLEFT", progressLabel, "BOTTOMLEFT", 0, -10)
  bar:SetPoint("RIGHT", hb, "RIGHT", -18, 0)
  local stepsText = Widgets.Text(hb, "small", "")
  stepsText:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
  stepsText:SetPoint("RIGHT", hb, "RIGHT", -18, 0)
  name:SetPoint("RIGHT", progressLabel, "LEFT", -20, 0)
  meta:SetPoint("RIGHT", progressLabel, "LEFT", -20, 0)
  screen.header = header
  header.icon, header.name, header.meta, header.chips, header.percent, header.bar, header.stepsText = icon, name, meta, chips, percent, bar, stepsText

  -- Timeline panel
  local chain = Widgets.Panel(screen, "Quest chain", { pad = 0 })
  chain:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
  chain:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", -(SIDE + 10), 0)
  local chainCount = Widgets.Text(chain.header, "small", "", { justify = "RIGHT" })
  chainCount:SetPoint("RIGHT", chain.header, "RIGHT", -10, 0)
  chain.count = chainCount
  local scroll = Widgets.ScrollArea(chain.body)
  scroll:SetPoint("TOPLEFT", chain.body, "TOPLEFT", 0, -4)
  scroll:SetPoint("BOTTOMRIGHT", chain.body, "BOTTOMRIGHT", 0, 4)
  chain.scroll = scroll
  chain.pool = Widgets.Pool(scroll.content, createStepRow)
  screen.chain = chain

  -- Current step panel
  local side = Widgets.Panel(screen, "Current step", { pad = 0 })
  side:SetWidth(SIDE)
  side:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -10)
  side:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  local sb = side.body
  local sIcon = Widgets.ItemIcon(sb, 36)
  sIcon:SetPoint("TOPLEFT", sb, "TOPLEFT", 12, -12)
  local sTitle = Widgets.Text(sb, "goalName", "")
  sTitle:SetPoint("TOPLEFT", sIcon, "TOPRIGHT", 10, -2)
  sTitle:SetPoint("RIGHT", sb, "RIGHT", -12, 0)
  local sMeta = Widgets.Text(sb, "small", "")
  sMeta:SetPoint("TOPLEFT", sTitle, "BOTTOMLEFT", 0, -3)
  sMeta:SetPoint("RIGHT", sb, "RIGHT", -12, 0)
  local sChips = {}
  for i = 1, 3 do
    local chip = Widgets.Chip(sb, "info", "")
    if i == 1 then chip:SetPoint("TOPLEFT", sIcon, "BOTTOMLEFT", 0, -12) else chip:SetPoint("TOPLEFT", sChips[i - 1], "BOTTOMLEFT", 0, -6) end
    chip:Hide()
    sChips[i] = chip
  end
  local sText = Widgets.Text(sb, "secondary", "", { wrap = true })
  sText:SetPoint("TOPLEFT", sChips[3], "BOTTOMLEFT", 0, -10)
  sText:SetPoint("RIGHT", sb, "RIGHT", -12, 0)
  local alsoLabel = Widgets.Text(sb, "label", "Also open now", { caps = true })
  alsoLabel:SetPoint("TOPLEFT", sText, "BOTTOMLEFT", 0, -14)
  local alsoText = Widgets.Text(sb, "small", "", { wrap = true })
  alsoText:SetPoint("TOPLEFT", alsoLabel, "BOTTOMLEFT", 0, -4)
  alsoText:SetPoint("RIGHT", sb, "RIGHT", -12, 0)
  side.icon, side.title, side.meta, side.chips, side.text, side.alsoLabel, side.alsoText = sIcon, sTitle, sMeta, sChips, sText, alsoLabel, alsoText
  side.empty = Widgets.EmptyState(sb, "Attuned", "Every step is done.")
  side.empty:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, -30)
  side.empty:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, -30)
  side.empty:SetHeight(80)
  side.empty:Hide()
  screen.side = side

  screen.empty = Widgets.EmptyState(screen, "Attunements", "")
  screen.empty:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, -80)
  screen.empty:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, -80)
  screen.empty:SetHeight(120)
  screen.empty:Hide()

  local function showContent(visible)
    for _, w in ipairs({ header, chain, side }) do
      if visible then w:Show() else w:Hide() end
    end
    if visible then screen.empty:Hide() else screen.empty:Show() end
  end

  function screen:Select(attuneID)
    self.attuneID = attuneID
    if ns.chardb then
      ns.chardb.ui = ns.chardb.ui or {}
      ns.chardb.ui.attunement = attuneID
    end
    self:Refresh()
  end

  function screen:Refresh()
    local AP = ns.AttuneProvider
    if not AP.IsAvailable() then
      picker:Hide()
      addGoal:Hide()
      showContent(false)
      self.empty:Set("Attune is not installed", "ForeverPath reads attunement chains from the Attune addon. Install and enable Attune, then come back.")
      return
    end
    picker:Show()
    addGoal:Show()
    -- Which attunement: the selected goal's, the last picked, or the first listed.
    local goal = ns.GoalService.GetSelected()
    local goalAttune = goal and goal.type == "COMPLETE_ATTUNEMENT" and goal.target.attuneID or nil
    local attuneID = self.attuneID
    -- A newly selected attunement goal takes over; an explicit picker choice otherwise stays.
    if goalAttune and (goal.id ~= self.lastGoalID or not attuneID) then attuneID = goalAttune end
    self.lastGoalID = goal and goal.id or nil
    attuneID = attuneID or (ns.chardb and ns.chardb.ui and ns.chardb.ui.attunement) or nil
    if not attuneID or not AP.Get(attuneID) then
      local first = AP.List()[1]
      attuneID = first and first.id or nil
    end
    self.attuneID = attuneID
    if not attuneID then
      showContent(false)
      picker:SetLabel("No attunements for your faction")
      self.empty:Set("Nothing to show", "Attune has no attunements for this faction.")
      return
    end
    showContent(true)
    local progress = AP.Progress(attuneID)
    self.progress = progress
    local attune = progress.attune
    picker:SetLabel(attune.name)
    local existing = ns.GoalService.FindAttunementGoal(attuneID)
    addGoal:SetLabel(existing and (existing.status == "COMPLETED" and "Goal completed" or "Goal added") or "+ Add goal")
    addGoal:SetEnabledState(existing == nil)

    header.icon:SetItem(attune.icon, 1)
    header.name:SetText(Theme.ColorText("gold", attune.name))
    local metaParts = {}
    local group = string.lower(attune.group or "")
    metaParts[#metaParts + 1] = group:find("raid") and "Raid attunement" or (group:find("dungeon") and "Dungeon quests" or (attune.group ~= "" and attune.group or "Attunement"))
    if attune.faction and attune.faction ~= "Both" then metaParts[#metaParts + 1] = attune.faction end
    if attune.levels then metaParts[#metaParts + 1] = "Level " .. attune.levels end
    if attune.groupSize then metaParts[#metaParts + 1] = attune.groupSize .. " players" end
    header.meta:SetText(table.concat(metaParts, " - "))
    local chipData = { { progress.complete and "ok" or "info", string.format("%d of %d steps", progress.done, progress.total) } }
    if progress.next then chipData[#chipData + 1] = { "info", "Next: " .. progress.next.name } end
    if progress.complete then chipData[#chipData + 1] = { "ok", "Attuned" } end
    for i, chip in ipairs(header.chips) do
      if chipData[i] then chip:SetChip(chipData[i][1], chipData[i][2]) chip:Show() else chip:Hide() end
    end
    header.percent:SetText(progress.percent .. "%")
    header.bar:SetKind(progress.complete and "ok" or "gold")
    header.bar:SetValue(progress.percent / 100)
    header.stepsText:SetText(progress.complete and "Attuned" or string.format("%d step%s to go", progress.total - progress.done, (progress.total - progress.done) == 1 and "" or "s"))

    -- Timeline
    local number = 0
    for index, step in ipairs(progress.steps) do
      local row = chain.pool:Get(index)
      row.step = step
      if step.type ~= "End" then number = number + 1 end
      row.number:SetText(step.type ~= "End" and tostring(number) or "")
      row.icon:SetItem(step.icon, 1)
      row.name:SetText(step.state == "done" and Theme.ColorText("text2", step.name) or (step.state == "current" and Theme.ColorText("text", step.name) or Theme.ColorText("text3", step.name)))
      local detailParts = { step.typeLabel }
      if step.location then detailParts[#detailParts + 1] = step.location end
      if step.side then detailParts[#detailParts + 1] = "side quest" end
      if step.inLog and not step.done then detailParts[#detailParts + 1] = "in your log" end
      row.detail:SetText(table.concat(detailParts, " - "))
      local badge = STATE_BADGE[step.state] or STATE_BADGE.locked
      row.badge:SetBadge(badge[1], badge[2])
      if step.state == "done" then
        Widgets.SetBackdrop(row.node, C.ok, C.okDark)
        row.nodeMark:SetText("")
        Widgets.SetColor(row.connector, C.okDark, 1)
      elseif step.state == "current" then
        Widgets.SetBackdrop(row.node, C.panel, C.gold)
        row.nodeMark:SetText(Theme.ColorText("gold", "o"))
        Widgets.SetColor(row.connector, Theme.RGB("#4A4335"), 1)
      else
        Widgets.SetBackdrop(row.node, C.panel, Theme.RGB("#6B6352"))
        row.nodeMark:SetText("")
        Widgets.SetColor(row.connector, Theme.RGB("#4A4335"), 1)
      end
      row:SetAlpha(step.state == "locked" and 0.7 or 1)
      if index == 1 then row.connector:SetPoint("TOP", row, "LEFT", 22, 0) else row.connector:SetPoint("TOP", row, "TOPLEFT", 22, 0) end
      if index == #progress.steps then row.connector:SetPoint("BOTTOM", row, "LEFT", 22, 0) else row.connector:SetPoint("BOTTOM", row, "BOTTOMLEFT", 22, 0) end
    end
    chain.pool:HideFrom(#progress.steps + 1)
    chain.scroll:SetContentHeight(#progress.steps * ROW)
    chain.count:SetText(string.format("%d / %d", progress.done, progress.total))

    -- Current step
    local step = progress.next
    if not step then
      for _, w in ipairs({ side.icon, side.title, side.meta, side.text, side.alsoLabel, side.alsoText }) do w:Hide() end
      for _, chip in ipairs(side.chips) do chip:Hide() end
      side.empty:Show()
      return
    end
    side.empty:Hide()
    for _, w in ipairs({ side.icon, side.title, side.meta, side.text, side.alsoLabel, side.alsoText }) do w:Show() end
    side.icon:SetItem(step.icon, 1)
    side.title:SetText(step.name)
    side.meta:SetText(step.typeLabel .. (step.location and (" - " .. step.location) or ""))
    local sideChips = {}
    if step.groupSize and step.groupSize > 1 then
      sideChips[#sideChips + 1] = { "info", (step.groupSize > 5 and "Raid quest - " or "Group quest - ") .. step.groupSize .. " players" }
    elseif step.groupSize == 1 then
      sideChips[#sideChips + 1] = { "ok", "Solo quest" }
    end
    if step.questLevel then sideChips[#sideChips + 1] = { "info", "Requires level " .. step.questLevel } end
    if step.inLog then sideChips[#sideChips + 1] = { "ok", "Quest in your log" } end
    if step.type == "Item" then sideChips[#sideChips + 1] = { "info", string.format("Collect %d", step.count) } end
    for i, chip in ipairs(side.chips) do
      if sideChips[i] then chip:SetChip(sideChips[i][1], sideChips[i][2]) chip:Show() else chip:Hide() end
    end
    local explain = {
      Quest = "Complete and turn in this quest.", ["Pick Up"] = "Pick up this quest.", ["Turn In"] = "Turn in this quest.",
      Item = "Get this item into your bags.", Kill = "Kill this creature (Attune records it).", Interact = "Speak with this NPC (Attune records it).",
      Click = "Use this object (Attune records it).", Level = "Keep levelling.", Rep = "Raise the reputation.", Attune = "Finish the other attunement first.",
    }
    side.text:SetText(explain[step.type] or "")
    local others = {}
    for _, s in ipairs(progress.current) do
      if s ~= step then others[#others + 1] = s.name .. (s.side and " (side)" or "") end
    end
    side.alsoText:SetText(#others > 0 and table.concat(others, ", ") or Theme.ColorText("text3", "nothing else is open yet"))
  end

  return screen
end

ns.UI.Screens.attunements = { label = "Attunements", Create = Create }
