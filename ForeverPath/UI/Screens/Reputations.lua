-- Screen 15: reputations. Every faction with its standing and progress,
-- grouped as the client groups them; a faction panel with the target
-- standing, the quests that give reputation and the rewards each standing
-- unlocks; one click makes a standing a goal.
local _, ns = ...

local Widgets = ns.UI.Widgets
local Theme = ns.UI.Theme
local C = Theme.Colors

ns.UI.Screens = ns.UI.Screens or {}

local ROW = 40
local GROUP_ROW = 28
local SIDE = 262
local MAX_QUESTS = 5
local MAX_REWARDS = 6

local function createGroupRow(content)
  local row = Widgets.Frame(content, nil, { bg = C.sidebar })
  row:SetHeight(GROUP_ROW)
  local label = Widgets.Text(row, "label", "", { caps = true, color = C.text })
  label:SetPoint("LEFT", row, "LEFT", 10, 0)
  local count = Widgets.Text(row, "small", "")
  count:SetPoint("LEFT", label, "RIGHT", 8, 0)
  row.label, row.count = label, count
  return row
end

local function createFactionRow(content, index, screen)
  local row = Widgets.Frame(content, nil, { frameType = "Button" })
  row:SetHeight(ROW)
  local line = Widgets.HLine(row, C.black, 0.55)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 10, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  Widgets.HoverFill(row, C.white, 0.03)
  local standing = Widgets.Text(row, "secondaryBright", "", { justify = "RIGHT", width = 70 })
  standing:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  local name = Widgets.Text(row, "body", "")
  name:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -6)
  name:SetPoint("RIGHT", standing, "LEFT", -10, 0)
  local bar = Widgets.ProgressBar(row, 5, "gold")
  bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 12, 8)
  bar:SetPoint("RIGHT", standing, "LEFT", -10, 0)
  local goalLine = Widgets.Text(row, "note", "", { color = C.gold, justify = "RIGHT" })
  goalLine:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -10, 2)
  row.standing, row.name, row.bar, row.goalLine = standing, name, bar, goalLine
  row:SetScript("OnClick", function(self)
    if self.factionID then screen:Select(self.factionID) end
  end)
  function row:SetSelected(selected)
    if selected then
      Widgets.SetBackdrop(self, C.raised, C.bronzeDim)
    elseif self.SetBackdrop then
      self:SetBackdrop(nil)
    end
  end
  return row
end

local function createSide(screen)
  local side = Widgets.Panel(screen, "Faction", { pad = 0 })
  side:SetWidth(SIDE)
  local body = side.body
  local icon = Widgets.ItemIcon(body, 32)
  icon:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -12)
  local title = Widgets.Text(body, "goalName", "", { color = C.goldLight })
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
  title:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local meta = Widgets.Text(body, "small", "")
  meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  meta:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local bar = Widgets.ProgressBar(body, 8, "gold")
  bar:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)
  bar:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local barText = Widgets.Text(body, "small", "")
  barText:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -4)
  barText:SetPoint("RIGHT", body, "RIGHT", -12, 0)

  local targetLabel = Widgets.Text(body, "label", "Target standing", { caps = true })
  targetLabel:SetPoint("TOPLEFT", barText, "BOTTOMLEFT", 0, -10)
  local segment = Widgets.Segment(body, {
    { key = "5", label = "Friendly" }, { key = "6", label = "Honored" }, { key = "7", label = "Revered" }, { key = "8", label = "Exalted" },
  }, function(key)
    side.targetStanding = tonumber(key)
    screen:Refresh()
  end)
  segment:SetPoint("TOPLEFT", targetLabel, "BOTTOMLEFT", 0, -5)
  local toTarget = Widgets.Text(body, "small", "", { wrap = true })
  toTarget:SetPoint("TOPLEFT", segment, "BOTTOMLEFT", 0, -6)
  toTarget:SetPoint("RIGHT", body, "RIGHT", -12, 0)

  local questsLabel = Widgets.Text(body, "label", "Quests that give reputation", { caps = true })
  questsLabel:SetPoint("TOPLEFT", toTarget, "BOTTOMLEFT", 0, -10)
  local questRows = {}
  local previous = questsLabel
  for i = 1, MAX_QUESTS do
    local row = CreateFrame("Button", nil, body)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -4 or 0)
    row:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    row.amount = Widgets.Text(row, "small", "", { justify = "RIGHT", width = 44, color = C.ok })
    row.amount:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    row.name = Widgets.Text(row, "secondary", "")
    row.name:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.name:SetPoint("RIGHT", row.amount, "LEFT", -6, 0)
    row:SetScript("OnClick", function(self)
      if self.questID then
        ns.UI.MainFrame.ShowScreen("quests")
        local quests = ns.UI.MainFrame.screens.quests
        if quests then quests:Select(self.questID) end
      end
    end)
    row:Hide()
    questRows[i] = row
    previous = row
  end
  local questsEmpty = Widgets.Text(body, "small", "", { wrap = true, color = C.text3 })
  questsEmpty:SetPoint("TOPLEFT", questsLabel, "BOTTOMLEFT", 0, -6)
  questsEmpty:SetPoint("RIGHT", body, "RIGHT", -12, 0)

  local rewardsLabel = Widgets.Text(body, "label", "Rewards at the target", { caps = true })
  rewardsLabel:SetPoint("TOPLEFT", questRows[MAX_QUESTS], "BOTTOMLEFT", 0, -10)
  local rewardIcons = {}
  for i = 1, MAX_REWARDS do
    local reward = Widgets.ItemIcon(body, 26)
    if i == 1 then reward:SetPoint("TOPLEFT", rewardsLabel, "BOTTOMLEFT", 0, -5) else reward:SetPoint("LEFT", rewardIcons[i - 1], "RIGHT", 4, 0) end
    reward:Hide()
    Widgets.SetItemTooltip(reward, function(self) return self.itemID end)
    rewardIcons[i] = reward
  end
  local rewardsText = Widgets.Text(body, "small", "", { wrap = true, color = C.text3 })
  rewardsText:SetPoint("TOPLEFT", rewardIcons[1], "BOTTOMLEFT", 0, -4)
  rewardsText:SetPoint("RIGHT", body, "RIGHT", -12, 0)

  local addGoal = Widgets.Button(body, "+ Add goal", { primary = true, onClick = function()
    if not side.factionID then return end
    local existing = ns.GoalService.FindReputationGoal(side.factionID)
    if existing and existing.target.standing == side.targetStanding and existing.status ~= "COMPLETED" then
      ns.UI.MainFrame.OpenGoal(existing.id)
      return
    end
    local goal, message = ns.GoalService.AddReputationGoal(side.factionID, side.targetStanding)
    ns.UI.MainFrame.SetStatus(message, goal and "ok" or "error")
    ns.UI.MainFrame.RequestRefresh()
  end })
  addGoal:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 12, 10)
  addGoal:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  side.icon, side.title, side.meta, side.bar, side.barText, side.targetLabel, side.segment, side.toTarget, side.questsLabel, side.questRows, side.questsEmpty, side.rewardsLabel, side.rewardIcons, side.rewardsText, side.addGoal =
    icon, title, meta, bar, barText, targetLabel, segment, toTarget, questsLabel, questRows, questsEmpty, rewardsLabel, rewardIcons, rewardsText, addGoal
  side.content = { icon, title, meta, bar, barText, targetLabel, segment, toTarget, questsLabel, rewardsLabel, rewardsText, addGoal }
  side.empty = Widgets.EmptyState(body, "No faction selected", "Click a faction to see your standing, the quests that raise it and what it unlocks.")
  side.empty:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -40)
  side.empty:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -40)
  side.empty:SetHeight(80)
  return side
end

local function Create(parent)
  local screen = CreateFrame("Frame", nil, parent)

  local top = CreateFrame("Frame", nil, screen)
  top:SetHeight(28)
  top:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
  local title = Widgets.Text(top, "title", "Reputations")
  title:SetPoint("LEFT", top, "LEFT", 2, 0)
  local status = Widgets.Text(top, "small", "", { justify = "RIGHT" })
  status:SetPoint("RIGHT", top, "RIGHT", 0, 0)
  screen.status = status

  local side = createSide(screen)
  side:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -8)
  side:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  screen.side = side

  local list = Widgets.Panel(screen, nil, { pad = 0 })
  list:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -8)
  list:SetPoint("BOTTOMRIGHT", side, "BOTTOMLEFT", -10, 0)
  local body = list.body
  local footer = Widgets.Frame(body, nil, { bg = C.sidebar })
  footer:SetHeight(26)
  footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  local footerLine = Widgets.HLine(footer, C.black, 1)
  footerLine:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
  footerLine:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
  local footerText = Widgets.Text(footer, "small", "")
  footerText:SetPoint("LEFT", footer, "LEFT", 12, 0)
  screen.footerText = footerText
  local scroll = Widgets.ScrollArea(body)
  scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 1)
  screen.scroll = scroll
  screen.groupPool = Widgets.Pool(scroll.content, createGroupRow)
  screen.rowPool = Widgets.Pool(scroll.content, function(content, index) return createFactionRow(content, index, screen) end)
  screen.listEmpty = Widgets.EmptyState(body, "No factions", "The client lists no reputations yet.")
  screen.listEmpty:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -40)
  screen.listEmpty:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -40)
  screen.listEmpty:SetHeight(80)
  screen.listEmpty:Hide()
  screen.list = list

  screen.empty = Widgets.EmptyState(screen, "Reputations", "")
  screen.empty:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, -80)
  screen.empty:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, -80)
  screen.empty:SetHeight(120)
  screen.empty:Hide()

  function screen:Select(factionID)
    self.factionID = factionID
    self.side.targetStanding = nil
    if ns.chardb and ns.chardb.ui then ns.chardb.ui.faction = factionID end
    self:Refresh()
  end

  local function renderSide(self, factionID)
    local RP = ns.ReputationProvider
    local s = self.side
    s.factionID = factionID
    local record = factionID and RP.Get(factionID) or nil
    if not record then
      for _, w in ipairs(s.content) do w:Hide() end
      for _, r in ipairs(s.questRows) do r:Hide() end
      for _, r in ipairs(s.rewardIcons) do r:Hide() end
      s.questsEmpty:Hide()
      s.empty:Show()
      s:SetTitle("Faction")
      return
    end
    s.empty:Hide()
    for _, w in ipairs(s.content) do w:Show() end
    s:SetTitle(record.name)
    s.icon:SetItem(RP.ICON, 1)
    s.title:SetText(record.name)
    local color = RP.StandingColor[record.standing] or "text2"
    s.meta:SetText(Theme.ColorText(color, record.standingLabel) .. (record.header and Theme.ColorText("text3", " - " .. record.header) or ""))
    s.bar:SetKind(record.standing >= 8 and "ok" or "gold")
    s.bar:SetValue((record.percentWithin or 0) / 100)
    s.barText:SetText(record.standing >= 8 and "Exalted" or string.format("%d / %d into %s", record.into or 0, record.span or 0, record.standingLabel))
    -- Target standing: the goal's, the last picked, or the next one up.
    local goal = ns.GoalService.FindReputationGoal(factionID)
    local target = s.targetStanding or (goal and goal.status ~= "COMPLETED" and goal.target.standing) or RP.NextStanding(record)
    target = math.max(5, math.min(8, target))
    s.targetStanding = target
    s.segment:Select(tostring(target))
    local progress = RP.Progress(factionID, target, goal and goal.target.startValue or nil)
    if progress.reached then
      s.toTarget:SetText(Theme.ColorText("ok", progress.targetLabel .. " reached"))
    else
      s.toTarget:SetText(string.format("%d reputation to %s", progress.remaining, progress.targetLabel))
    end
    -- Quests
    local quests = RP.QuestsFor(record.name, record.factionID)
    local shown = 0
    for _, quest in ipairs(quests) do
      if shown < MAX_QUESTS then
        shown = shown + 1
        local row = s.questRows[shown]
        row.questID = quest.questID
        row.name:SetText((quest.state.completed and Theme.Hex.text3 or Theme.Hex.text) .. quest.name .. "|r" .. Theme.ColorText("text3", " - " .. quest.label))
        row.amount:SetText("+" .. quest.amount)
        row:Show()
      end
    end
    for i = shown + 1, MAX_QUESTS do s.questRows[i]:Hide() end
    if shown == 0 then
      s.questsEmpty:SetText(ns.QuestProvider and ns.QuestProvider.HasJournal() and "No known dungeon quest rewards this reputation." or "Quest reputation rewards come from ForeverDungeonJournal.")
      s.questsEmpty:Show()
    else
      s.questsEmpty:Hide()
    end
    -- Rewards at the target standing
    local tier
    for _, t in ipairs(RP.Rewards(factionID)) do if t.standing == target then tier = t end end
    local icons = 0
    for _, itemID in ipairs(tier and tier.items or {}) do
      if icons < MAX_REWARDS then
        icons = icons + 1
        local item = ns.ItemProvider.GetItem(itemID)
        local frame = s.rewardIcons[icons]
        frame:SetItem(item.icon, item.quality)
        frame.itemID = itemID
        frame:Show()
      end
    end
    for i = icons + 1, MAX_REWARDS do s.rewardIcons[i]:Hide() end
    if tier and #tier.items > 0 then
      local n = #tier.items
      s.rewardsText:SetText(string.format("%d item%s unlock%s at %s%s", n, n == 1 and "" or "s", n == 1 and "s" or "", progress.targetLabel, n > MAX_REWARDS and (" (" .. (n - MAX_REWARDS) .. " more)") or ""))
    else
      s.rewardsText:SetText(RP.HasAtlasLoot() and (RP.atlas.state == "ready" and "No known reward at this standing." or "Loading AtlasLoot's faction tables...") or "Faction rewards come from AtlasLoot's Factions module.")
    end
    if goal and goal.status ~= "COMPLETED" and goal.target.standing == target then
      s.addGoal:SetLabel("Open goal")
    elseif goal and goal.status ~= "COMPLETED" then
      s.addGoal:SetLabel("Retarget goal to " .. progress.targetLabel)
    else
      s.addGoal:SetLabel("+ Add goal: " .. progress.targetLabel)
    end
  end

  function screen:Refresh()
    local RP = ns.ReputationProvider
    if not RP or not RP.IsAvailable() then
      list:Hide()
      side:Hide()
      self.empty:Set("Reputations unavailable", "This client does not expose the faction API ForeverPath needs.")
      self.empty:Show()
      return
    end
    self.empty:Hide()
    list:Show()
    side:Show()
    status:SetText(Theme.ColorText("text3", RP.Status():gsub("^Reputations: ", "")))
    local ui = ns.chardb and ns.chardb.ui or {}
    local goal = ns.GoalService.GetSelected()
    local goalFaction = goal and goal.type == "REACH_REPUTATION" and goal.target.factionID or nil
    local factionID = self.factionID
    if goalFaction and (goal.id ~= self.lastGoalID or not factionID) then
      factionID = goalFaction
      self.side.targetStanding = nil
    end
    self.lastGoalID = goal and goal.id or nil
    factionID = factionID or ui.faction

    local goals = {}
    for _, g in ipairs(ns.GoalService.List({ open = true })) do
      if g.type == "REACH_REPUTATION" then goals[g.target.factionID] = g end
    end
    local groups, byHeader = {}, {}
    for _, record in ipairs(RP.List()) do
      local key = record.header or "Other"
      local group = byHeader[key]
      if not group then
        group = { label = key, rows = {} }
        byHeader[key] = group
        groups[#groups + 1] = group
      end
      group.rows[#group.rows + 1] = record
    end
    local y, groupIndex, rowIndex, total, first = 0, 0, 0, 0, nil
    for _, group in ipairs(groups) do
      groupIndex = groupIndex + 1
      local groupRow = self.groupPool:Get(groupIndex)
      groupRow:ClearAllPoints()
      groupRow:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
      groupRow:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, -y)
      groupRow.label:SetText(Theme.Upper(group.label))
      groupRow.count:SetText(tostring(#group.rows))
      y = y + GROUP_ROW
      for _, record in ipairs(group.rows) do
        rowIndex = rowIndex + 1
        total = total + 1
        first = first or record.factionID
        local row = self.rowPool:Get(rowIndex)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, -y)
        y = y + ROW
        row.factionID = record.factionID
        row.name:SetText(record.name)
        row.standing:SetText(Theme.ColorText(RP.StandingColor[record.standing] or "text2", record.standingLabel))
        row.bar:SetKind(record.standing >= 8 and "ok" or "gold")
        row.bar:SetValue((record.percentWithin or 0) / 100)
        local g = goals[record.factionID]
        row.goalLine:SetText(g and (Theme.ColorText("gold", "o ") .. ns.GoalModel.StandingLabels[g.target.standing]) or "")
        row:SetSelected(record.factionID == factionID)
      end
    end
    self.rowPool:HideFrom(rowIndex + 1)
    self.groupPool:HideFrom(groupIndex + 1)
    scroll:SetContentHeight(y)
    if total == 0 then self.listEmpty:Show() else self.listEmpty:Hide() end
    local goalCount = 0
    for _ in pairs(goals) do goalCount = goalCount + 1 end
    footerText:SetText(string.format("%d faction%s - %d reputation goal%s", total, total == 1 and "" or "s", goalCount, goalCount == 1 and "" or "s"))
    if not factionID or not RP.Get(factionID) then factionID = first end
    self.factionID = factionID
    renderSide(self, factionID)
  end

  return screen
end

ns.UI.Screens.reputations = { label = "Reputations", Create = Create }
