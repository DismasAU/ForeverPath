-- Screen 06: Attunement planner. Picks an attunement (the selected goal's
-- when it is one), shows the header with progress, the step timeline and
-- the current step. Data and progress come from AttuneBridge.
local _, ns = ...

local Widgets = ns.UI.Widgets
local Theme = ns.UI.Theme
local C = Theme.Colors
local StepStates = ns.AttuneBridge.StepStates

ns.UI.Screens = ns.UI.Screens or {}

local ROW = 38
local SIDE = 262

local STATE_BADGE = { done = { "Done", "ok" }, current = { "Current", "gold" }, locked = { "Locked", "text" } }

-- The quest a step is about (a Quest, Pick Up or Turn In step whose Wowhead
-- id is a quest id), or nil. Read wherever the step is shown, never stored.
local function stepQuestID(step)
  if step.type ~= "Quest" and step.type ~= "Pick Up" and step.type ~= "Turn In" then return nil end
  if not ns.QuestProvider.IsAvailable() then return nil end
  return tonumber(string.match(tostring(step.wowheadID or ""), "^(%d+)"))
end

local function createStepRow(content, index, screen)
  local row = Widgets.ListRow(content, { height = ROW, index = index, divider = false })
  row.selected = Widgets.Texture(row, C.gold, 0, "BACKGROUND")
  row.selected:SetAllPoints(row)
  row:SetScript("OnClick", function(self)
    if self.step and screen then screen:SelectStep(self.step.key) end
  end)
  -- Timeline: a connector line and a node.
  row.connector = Widgets.Texture(row, C.lineDark, 1)
  row.connector:SetWidth(2)
  row.connector:SetPoint("TOP", row, "TOPLEFT", 22, 0)
  row.connector:SetPoint("BOTTOM", row, "BOTTOMLEFT", 22, 0)
  row.node = Widgets.Frame(row, nil, { bg = C.panel, border = C.nodeBorder })
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
    for _, attune in ipairs(ns.AttuneBridge.List()) do
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
      ns.UI.MainFrame.SetAlert(message, goal and "ok" or "error")
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
    local chip = Widgets.Chip(hb, "", "info")
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
  chain.pool = Widgets.Pool(scroll.content, function(content, index) return createStepRow(content, index, screen) end)
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
    local chip = Widgets.Chip(sb, "", "info")
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
  local openQuest = Widgets.Button(sb, "Quests >", { onClick = function()
    if not side.questID then return end
    ns.UI.MainFrame.ShowScreen("quests", nil, side.questID)
  end })
  openQuest:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", -12, 10)
  openQuest:Hide()
  local waypoint = Widgets.Button(sb, "Waypoint", { onClick = function()
    if not side.questID then return end
    local ok, message = ns.QuestProvider.SetWaypoint(ns.QuestProvider.Waypoint(side.questID))
    ns.UI.MainFrame.SetAlert(message, ok and "ok" or "error")
  end })
  waypoint:SetPoint("RIGHT", openQuest, "LEFT", -6, 0)
  waypoint:Hide()
  Widgets.SetTooltip(waypoint, "Set a map waypoint", { "Pins the quest giver (or the turn-in once the quest is ready) on your map.", "Only when a position has been recorded for it." })
  side.openQuest, side.waypoint = openQuest, waypoint
  side.icon, side.title, side.meta, side.chips, side.text, side.alsoLabel, side.alsoText = sIcon, sTitle, sMeta, sChips, sText, alsoLabel, alsoText
  side.empty = Widgets.EmptyState(sb, "Attuned", "Every step is done.")
  side.empty:SetPoint("TOPLEFT", sb, "TOPLEFT", 0, -30)
  side.empty:SetPoint("TOPRIGHT", sb, "TOPRIGHT", 0, -30)
  side.empty:SetHeight(80)
  side.empty:Hide()
  screen.side = side

  screen.empty = Widgets.EmptyState(screen, "Attunements", "")
  Widgets.StackAt(screen.empty, screen, 80, 120)
  screen.empty:Hide()

  local function showContent(visible)
    for _, w in ipairs({ header, chain, side }) do
      if visible then w:Show() else w:Hide() end
    end
    if visible then screen.empty:Hide() else screen.empty:Show() end
  end

  function screen:Select(attuneID)
    if attuneID ~= self.attuneID then self.stepKey = nil end
    self.attuneID = attuneID
    ns.chardb.ui.attunement = attuneID
    self:Refresh()
  end

  -- Shows a step's summary in the side panel; clicking the shown step
  -- again goes back to the current one.
  function screen:SelectStep(key)
    if self.stepKey == key then self.stepKey = nil else self.stepKey = key end
    self:Refresh()
  end

  function screen:Refresh()
    local AttuneBridge = ns.AttuneBridge
    if not AttuneBridge.IsAvailable() then
      picker:Hide()
      addGoal:Hide()
      showContent(false)
      self.empty:Set("Attune is not installed", "ForeverPath reads attunement chains from the Attune addon. Install and enable Attune, then come back.")
      return
    end
    picker:Show()
    addGoal:Show()
    -- Which attunement: the selected goal's, the last picked, or the first listed.
    local goal = ns.GoalService.Selected()
    local goalAttune = goal and goal.type == ns.GoalModel.TypeIDs.COMPLETE_ATTUNEMENT and goal.target.attuneID or nil
    local attuneID = self.attuneID
    -- A newly selected attunement goal takes over; an explicit picker choice otherwise stays.
    if goalAttune and (goal.id ~= self.lastGoalID or not attuneID) then attuneID = goalAttune end
    self.lastGoalID = goal and goal.id or nil
    attuneID = attuneID or ns.chardb.ui.attunement
    if not attuneID or not AttuneBridge.Get(attuneID) then
      local first = AttuneBridge.List()[1]
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
    local progress = AttuneBridge.Progress(attuneID)
    self.progress = progress
    self:RefreshHeader(progress)
    self:RefreshTimeline(progress)
    self:RefreshSide(progress)
  end

  -- Header: picker, add-goal button, name, meta, chips and progress bar.
  function screen:RefreshHeader(progress)
    local attune = progress.attune
    local attuneID = self.attuneID
    picker:SetLabel(attune.name)
    local existing = ns.GoalService.FindAttunementGoal(attuneID)
    addGoal:SetLabel(existing and (existing.status == ns.GoalModel.Statuses.COMPLETED and "Goal completed" or "Goal added") or "+ Add goal")
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
    local chipData = { { string.format("%d of %d steps", progress.done, progress.total), progress.complete and "ok" or "info" } }
    if progress.next then chipData[#chipData + 1] = { "Next: " .. progress.next.name, "info" } end
    if progress.complete then chipData[#chipData + 1] = { "Attuned", "ok" } end
    for i, chip in ipairs(header.chips) do
      if chipData[i] then chip:SetChip(chipData[i][1], chipData[i][2]) chip:Show() else chip:Hide() end
    end
    header.percent:SetText(progress.percent .. "%")
    header.bar:SetKind(progress.complete and "ok" or "gold")
    header.bar:SetValue(progress.percent / 100)
    header.stepsText:SetText(progress.complete and "Attuned" or string.format("%d step%s to go", progress.total - progress.done, (progress.total - progress.done) == 1 and "" or "s"))
  end

  -- Timeline: one row per step with its state's node and badge.
  function screen:RefreshTimeline(progress)
    local number = 0
    for index, step in ipairs(progress.steps) do
      local row = chain.pool:Get(index)
      row.step = step
      if step.type ~= "End" then number = number + 1 end
      row.number:SetText(step.type ~= "End" and tostring(number) or "")
      row.icon:SetItem(step.icon, 1)
      row.name:SetText(step.state == StepStates.DONE and Theme.ColorText("text2", step.name) or (step.state == StepStates.CURRENT and Theme.ColorText("text", step.name) or Theme.ColorText("text3", step.name)))
      local detailParts = { step.typeLabel }
      if step.location then detailParts[#detailParts + 1] = step.location end
      if step.side then detailParts[#detailParts + 1] = "side quest" end
      if step.inLog and not step.done then detailParts[#detailParts + 1] = "in your log" end
      row.detail:SetText(table.concat(detailParts, " - "))
      local badge = STATE_BADGE[step.state] or STATE_BADGE.locked
      row.badge:SetBadge(badge[1], badge[2])
      if step.state == StepStates.DONE then
        Widgets.SetBackdrop(row.node, C.ok, C.okDark)
        row.nodeMark:SetText("")
        Widgets.SetColor(row.connector, C.okDark, 1)
      elseif step.state == StepStates.CURRENT then
        Widgets.SetBackdrop(row.node, C.panel, C.gold)
        row.nodeMark:SetText(Theme.ColorText("gold", "o"))
        Widgets.SetColor(row.connector, C.lineDark, 1)
      else
        Widgets.SetBackdrop(row.node, C.panel, C.nodeBorder)
        row.nodeMark:SetText("")
        Widgets.SetColor(row.connector, C.lineDark, 1)
      end
      row:SetAlpha(step.state == StepStates.LOCKED and 0.7 or 1)
      Widgets.SetColor(row.selected, C.gold, self.stepKey == step.key and 0.08 or 0)
      if index == 1 then row.connector:SetPoint("TOP", row, "LEFT", 22, 0) else row.connector:SetPoint("TOP", row, "TOPLEFT", 22, 0) end
      if index == #progress.steps then row.connector:SetPoint("BOTTOM", row, "LEFT", 22, 0) else row.connector:SetPoint("BOTTOM", row, "BOTTOMLEFT", 22, 0) end
    end
    chain.pool:HideFrom(#progress.steps + 1)
    chain.scroll:SetContentHeight(#progress.steps * ROW)
    chain.count:SetText(string.format("%d / %d", progress.done, progress.total))
  end

  -- Side panel: the selected step, else the current one.
  function screen:RefreshSide(progress)
    local step, stepNumber
    if self.stepKey then
      local n = 0
      for _, s in ipairs(progress.steps) do
        if s.type ~= "End" then n = n + 1 end
        if s.key == self.stepKey then step, stepNumber = s, n break end
      end
      if not step then self.stepKey = nil end
    end
    step = step or progress.next
    side:SetTitle(self.stepKey and step and string.format("Step %d of %d", stepNumber or 0, progress.total) or "Current step")
    side.questID = nil
    if not step then
      for _, w in ipairs({ side.icon, side.title, side.meta, side.text, side.alsoLabel, side.alsoText, side.openQuest, side.waypoint }) do w:Hide() end
      for _, chip in ipairs(side.chips) do chip:Hide() end
      side.empty:Show()
      return
    end
    side.empty:Hide()
    for _, w in ipairs({ side.icon, side.title, side.meta, side.text, side.alsoLabel, side.alsoText }) do w:Show() end
    side.icon:SetItem(step.icon, 1)
    side.title:SetText(step.name)
    side.meta:SetText(step.typeLabel .. (step.location and (" - " .. step.location) or "") .. (step.state == StepStates.DONE and " - done" or (step.state == StepStates.LOCKED and " - locked" or "")))
    local sideChips = {}
    if step.groupSize and step.groupSize > 1 then
      sideChips[#sideChips + 1] = { (step.groupSize > 5 and "Raid quest - " or "Group quest - ") .. step.groupSize .. " players", "info" }
    elseif step.groupSize == 1 then
      sideChips[#sideChips + 1] = { "Solo quest", "ok" }
    end
    if step.questLevel then sideChips[#sideChips + 1] = { "Requires level " .. step.questLevel, "info" } end
    if step.inLog then sideChips[#sideChips + 1] = { "Quest in your log", "ok" } end
    if step.type == "Item" then sideChips[#sideChips + 1] = { string.format("Collect %d", step.count), "info" } end
    for i, chip in ipairs(side.chips) do
      if sideChips[i] then chip:SetChip(sideChips[i][1], sideChips[i][2]) chip:Show() else chip:Hide() end
    end
    local explain = {
      Quest = "Complete and turn in this quest.", ["Pick Up"] = "Pick up this quest.", ["Turn In"] = "Turn in this quest.",
      Item = "Get this item into your bags.", Kill = "Kill this creature (Attune records it).", Interact = "Speak with this NPC (Attune records it).",
      Click = "Use this object (Attune records it).", Level = "Keep levelling.", Rep = "Raise the reputation.", Attune = "Finish the other attunement first.",
    }
    local summary = screen:StepSummary(step)
    side.text:SetText(#summary > 0 and table.concat(summary, "\n") or (explain[step.type] or ""))
    local questID = stepQuestID(step)
    side.questID = questID
    if questID then side.openQuest:Show() else side.openQuest:Hide() end
    if questID and ns.QuestProvider.Waypoint(questID) then side.waypoint:Show() else side.waypoint:Hide() end
    local others = {}
    for _, s in ipairs(progress.current) do
      if s ~= step then others[#others + 1] = s.name .. (s.side and " (side)" or "") end
    end
    side.alsoText:SetText(#others > 0 and table.concat(others, ", ") or Theme.ColorText("text3", "nothing else is open yet"))
  end

  -- What a step asks of the player, one line per fact: a quest's state,
  -- objectives, giver, turn-in, items to bring and rewards; an item's bag
  -- count and sources; a level step's distance.
  function screen:StepSummary(step)
    local lines = {}
    local function add(label, value)
      lines[#lines + 1] = Theme.Hex.text2 .. label .. ":|r " .. value
    end
    local QP = ns.QuestProvider
    local questID = stepQuestID(step)
    if questID then
      local detail = QP.Detail(questID)
      local entry, state = detail.entry, detail.state
      local label, kind, key = QP.StateLabel(state, entry)
      -- The chain knows what the journal does not: earlier steps still block this one.
      if key == ns.Planner.QuestStates.AVAILABLE and step.state == StepStates.LOCKED then label, kind = QP.StateText(ns.Planner.QuestStates.LOCKED) end
      add("State", Theme.ColorText(kind == "ok" and "ok" or (kind == "info" and "gold" or "text"), label))
      if state.inLog and #state.objectives > 0 then
        for _, o in ipairs(state.objectives) do
          lines[#lines + 1] = "  - " .. (o.finished and Theme.Hex.text3 or Theme.Hex.text) .. (o.text or "") .. (o.finished and " (done)" or "") .. "|r"
        end
      elseif entry and entry.objective then
        add("Objective", entry.objective)
      end
      if detail.giver then add("Pick up", detail.giver.label) end
      if detail.turnin then add("Turn in", detail.turnin.label) end
      for _, item in ipairs(detail.items) do
        add("Bring", string.format("%d x %s (%d/%d)%s", item.count, item.name, math.min(item.have, item.count), item.count,
          item.source and (" - " .. (item.source:match("^([^,]+)") or item.source)) or ""))
      end
      if #detail.rewards > 0 then
        add(detail.rewardChoice and "Reward (choose one)" or "Rewards", QP.RewardText(detail.rewards))
      end
      local facts = QP.Facts(questID)
      if facts and facts.note then add("Note", facts.note) end
    elseif step.type == "Item" then
      local itemID = tonumber(step.wowheadID)
      if itemID then
        local counts = ns.InventoryProvider.GetCounts(itemID)
        add("In bags", string.format("%d of %d", counts.bags or 0, step.count or 1))
        for _, hint in ipairs(ns.SourceProvider.WhereFrom(itemID)) do
          if hint.label then
            add("Source", hint.label .. (hint.detail and (" - " .. hint.detail) or ""))
            break
          end
        end
      end
    elseif step.type == "Level" then
      local level = ns.Compat.PlayerLevel()
      local target = tonumber(step.wowheadID) or 0
      add("You are", level >= target and ("level " .. level .. " - done") or string.format("level %d - %d to go", level, target - level))
    end
    return lines
  end

  return screen
end

ns.UI.Screens.attunements = { label = "Attunements", Create = Create }
