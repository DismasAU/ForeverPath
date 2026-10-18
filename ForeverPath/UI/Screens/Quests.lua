-- Screen 14: quests. The quests ForeverPath knows (dungeon quests from
-- ForeverDungeonJournal, attunement quests from Attune) plus everything in
-- the player's log, grouped by zone or by the goal they feed, with the
-- details, chain, objectives and rewards of the selected one.
local _, ns = ...

local Widgets = ns.UI.Widgets
local Theme = ns.UI.Theme
local C = Theme.Colors

ns.UI.Screens = ns.UI.Screens or {}

local ROW = 40
local GROUP_ROW = 28
local SIDE = 262
local MAX_OBJECTIVES = 5
local MAX_REWARDS = 4

local TABS = { { key = "zone", label = "By zone" }, { key = "goal", label = "By goal" }, { key = "completed", label = "Completed" } }
local DIFFICULTY_HEX = { trivial = "questTrivial", easy = "questEasy", standard = "questStandard", hard = "questHard", impossible = "questImpossible" }
local BADGE_KIND = { Ready = "ok", ["In log"] = "info", Available = "partial", Locked = "text", Done = "ok" }

local function markerFor(label)
  if label == "Done" then return "+", "ok" end
  if label == "Ready" then return "?", "questStandard" end
  if label == "Locked" then return "!", "questTrivial" end
  if label == "In log" then return "!", "text2" end
  return "!", "questStandard"
end

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

local function createQuestRow(content, index, screen)
  local row = Widgets.Frame(content, nil, { frameType = "Button" })
  row:SetHeight(ROW)
  local line = Widgets.HLine(row, C.black, 0.55)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 22, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  Widgets.HoverFill(row, C.white, 0.03)
  local marker = Widgets.Text(row, "goalName", "!", { justify = "CENTER", width = 16 })
  marker:SetPoint("LEFT", row, "LEFT", 22, 0)
  local level = Widgets.Text(row, "secondary", "", { justify = "RIGHT", width = 34 })
  level:SetPoint("LEFT", marker, "RIGHT", 6, 0)
  local badge = Widgets.Badge(row, "", "ok")
  badge:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  local name = Widgets.Text(row, "body", "")
  name:SetPoint("TOPLEFT", level, "TOPRIGHT", 8, 8)
  name:SetPoint("RIGHT", badge, "LEFT", -10, 0)
  local feeds = Widgets.Text(row, "small", "")
  feeds:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
  feeds:SetPoint("RIGHT", badge, "LEFT", -10, 0)
  row.marker, row.level, row.badge, row.name, row.feeds = marker, level, badge, name, feeds
  row:SetScript("OnClick", function(self)
    if self.questID then screen:Select(self.questID) end
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
  local side = Widgets.Panel(screen, "Quest details", { pad = 0 })
  side:SetWidth(SIDE)
  local body = side.body
  local icon = Widgets.ItemIcon(body, 32)
  icon:SetPoint("TOPLEFT", body, "TOPLEFT", 12, -12)
  local title = Widgets.Text(body, "goalName", "", { color = C.goldLight })
  title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
  title:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local meta = Widgets.Text(body, "small", "", { wrap = true })
  meta:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  meta:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local badge = Widgets.Badge(body, "", "ok")
  badge:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -10)

  local objectivesLabel = Widgets.Text(body, "label", "Objectives", { caps = true })
  objectivesLabel:SetPoint("TOPLEFT", badge, "BOTTOMLEFT", 0, -12)
  side.objectives = {}
  local previous = objectivesLabel
  for i = 1, MAX_OBJECTIVES do
    local frame = CreateFrame("Frame", nil, body)
    frame:SetHeight(22)
    frame:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -4 or -2)
    frame:SetPoint("RIGHT", body, "RIGHT", -12, 0)
    frame.text = Widgets.Text(frame, "secondary", "")
    frame.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.text:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    frame.bar = Widgets.ProgressBar(frame, 5, "gold")
    frame.bar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 1)
    frame.bar:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    frame:Hide()
    side.objectives[i] = frame
    previous = frame
  end
  local callout = Widgets.Frame(body, nil, { bg = C.questReadyBg, border = C.questReadyBorder })
  callout:SetHeight(34)
  callout:SetPoint("TOPLEFT", side.objectives[MAX_OBJECTIVES], "BOTTOMLEFT", 0, -6)
  callout:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  callout.text = Widgets.Text(callout, "secondaryBright", "", { color = C.ok, wrap = true })
  callout.text:SetPoint("TOPLEFT", callout, "TOPLEFT", 8, -5)
  callout.text:SetPoint("BOTTOMRIGHT", callout, "BOTTOMRIGHT", -8, 5)
  callout:Hide()

  local rewardsLabel = Widgets.Text(body, "label", "Rewards", { caps = true })
  rewardsLabel:SetPoint("TOPLEFT", callout, "BOTTOMLEFT", 0, -10)
  side.rewardIcons = {}
  for i = 1, MAX_REWARDS do
    local reward = Widgets.ItemIcon(body, 26)
    if i == 1 then reward:SetPoint("TOPLEFT", rewardsLabel, "BOTTOMLEFT", 0, -5) else reward:SetPoint("LEFT", side.rewardIcons[i - 1], "RIGHT", 4, 0) end
    reward:Hide()
    Widgets.SetItemTooltip(reward, function(self) return self.itemID end)
    side.rewardIcons[i] = reward
  end
  local rewardsText = Widgets.Text(body, "small", "", { wrap = true })
  rewardsText:SetPoint("TOPLEFT", side.rewardIcons[1], "BOTTOMLEFT", 0, -4)
  rewardsText:SetPoint("RIGHT", body, "RIGHT", -12, 0)
  local feedsLabel = Widgets.Text(body, "label", "Feeds your goals", { caps = true })
  feedsLabel:SetPoint("TOPLEFT", rewardsText, "BOTTOMLEFT", 0, -10)
  local feedsText = Widgets.Text(body, "small", "", { wrap = true })
  feedsText:SetPoint("TOPLEFT", feedsLabel, "BOTTOMLEFT", 0, -4)
  feedsText:SetPoint("RIGHT", body, "RIGHT", -12, 0)

  local addGoal = Widgets.Button(body, "+ Add goal", { primary = true, onClick = function()
    if not side.questID then return end
    local existing = ns.GoalService.FindQuestGoal(side.questID)
    if existing then
      ns.UI.MainFrame.OpenGoal(existing.id)
      return
    end
    local goal, message = ns.GoalService.AddQuestGoal(side.questID)
    ns.UI.MainFrame.SetStatus(message, goal and "ok" or "error")
    ns.UI.MainFrame.RequestRefresh()
  end })
  addGoal:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 12, 10)
  local link = Widgets.Button(body, "Link", { onClick = function()
    if side.questID then screen:LinkQuest(side.questID) end
  end })
  link:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -12, 10)
  local watch = Widgets.Button(body, "Watch", { onClick = function()
    if side.questID then screen:WatchQuest(side.questID) end
  end })
  watch:SetPoint("RIGHT", link, "LEFT", -6, 0)
  side.icon, side.title, side.meta, side.badge, side.objectivesLabel, side.callout, side.rewardsLabel, side.rewardsText, side.feedsLabel, side.feedsText, side.addGoal, side.link, side.watch =
    icon, title, meta, badge, objectivesLabel, callout, rewardsLabel, rewardsText, feedsLabel, feedsText, addGoal, link, watch
  side.content = { icon, title, meta, badge, objectivesLabel, rewardsLabel, rewardsText, feedsLabel, feedsText, addGoal, link, watch }
  side.empty = Widgets.EmptyState(body, "No quest selected", "Click a quest in the list to see its chain, objectives and rewards.")
  side.empty:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -40)
  side.empty:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -40)
  side.empty:SetHeight(80)
  return side
end

local function Create(parent)
  local screen = CreateFrame("Frame", nil, parent)
  screen.tab = "zone"

  local top = CreateFrame("Frame", nil, screen)
  top:SetHeight(28)
  top:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
  local title = Widgets.Text(top, "title", "Quests")
  title:SetPoint("LEFT", top, "LEFT", 2, 0)
  local tabs = Widgets.Tabs(top, TABS, function(key)
    screen.tab = key
    if ns.chardb and ns.chardb.ui then ns.chardb.ui.questsTab = key end
    screen:Refresh()
  end)
  tabs:SetPoint("LEFT", title, "RIGHT", 18, 0)
  tabs:SetPoint("BOTTOM", top, "BOTTOM", 0, 0)
  tabs:SetWidth(300)
  local feedOnly = Widgets.Checkbox(top, "Only quests that feed a goal", function(checked)
    if ns.chardb and ns.chardb.ui then ns.chardb.ui.questsFeedOnly = checked end
    screen:Refresh()
  end)
  feedOnly:SetPoint("RIGHT", top, "RIGHT", 0, 0)
  screen.tabs, screen.feedOnly = tabs, feedOnly

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
  local feedsText = Widgets.Text(footer, "small", "")
  feedsText:SetPoint("LEFT", footer, "LEFT", 12, 0)
  local logText = Widgets.Text(footer, "small", "", { justify = "RIGHT" })
  logText:SetPoint("RIGHT", footer, "RIGHT", -12, 0)
  screen.footerFeeds, screen.footerLog = feedsText, logText
  local scroll = Widgets.ScrollArea(body)
  scroll:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 1)
  screen.scroll = scroll
  screen.groupPool = Widgets.Pool(scroll.content, createGroupRow)
  screen.rowPool = Widgets.Pool(scroll.content, function(content, index) return createQuestRow(content, index, screen) end)
  screen.listEmpty = Widgets.EmptyState(body, "No quests here", "")
  screen.listEmpty:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -40)
  screen.listEmpty:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -40)
  screen.listEmpty:SetHeight(80)
  screen.listEmpty:Hide()
  screen.list = list

  screen.empty = Widgets.EmptyState(screen, "Quests", "")
  screen.empty:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, -80)
  screen.empty:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, -80)
  screen.empty:SetHeight(120)
  screen.empty:Hide()

  function screen:Select(questID)
    self.questID = questID
    if ns.chardb and ns.chardb.ui then ns.chardb.ui.quest = questID end
    self:Refresh()
  end

  function screen:LinkQuest(questID)
    local state = ns.QuestProvider.State(questID)
    local link
    if state.logIndex and type(GetQuestLink) == "function" then
      local ok, result = pcall(GetQuestLink, state.logIndex)
      if ok and type(result) == "string" then link = result end
    end
    if not link then
      ns.UI.MainFrame.SetStatus("Only quests in your log can be linked.", "info")
      return false
    end
    local inserted = false
    if type(ChatFrameUtil) == "table" and type(ChatFrameUtil.InsertLink) == "function" then
      inserted = ChatFrameUtil.InsertLink(link)
    elseif type(ChatEdit_InsertLink) == "function" then
      inserted = ChatEdit_InsertLink(link)
    end
    if not inserted then ns.Log.Print("%s", link) end
    return true
  end

  function screen:WatchQuest(questID)
    local state = ns.QuestProvider.State(questID)
    if not state.inLog then
      ns.UI.MainFrame.SetStatus("Only quests in your log can be tracked.", "info")
      return false
    end
    if type(C_QuestLog) == "table" and type(C_QuestLog.AddQuestWatch) == "function" then
      pcall(C_QuestLog.AddQuestWatch, questID)
      ns.UI.MainFrame.SetStatus("Quest added to the objective tracker.", "ok")
      return true
    end
    return false
  end

  -- Builds { groups = { { key, label, rows = { { questID, name, level, label, kind, feeds } } } }, feeds, total }
  function screen:Collect()
    local QP = ns.QuestProvider
    local MainFrame = ns.UI.MainFrame
    local goals = ns.GoalService.List({ open = true })
    local feeds = QP.FeedsGoals(goals, MainFrame.views, ns.GoalService.Name)
    local questGoals = {}
    for _, goal in ipairs(ns.GoalService.List()) do
      if goal.type == "COMPLETE_QUEST" and goal.target then questGoals[goal.target.questID] = goal end
    end
    local feedOnly = self.feedOnly:GetChecked()
    local playerLevel = QP.PlayerLevel()
    local groups, byKey = {}, {}
    local seen = {}
    local function group(key, label)
      local g = byKey[key]
      if not g then
        g = { key = key, label = label, rows = {} }
        byKey[key] = g
        groups[#groups + 1] = g
      end
      return g
    end
    local function add(groupKey, groupLabel, questID, name, level, state, entry)
      if seen[questID] then return end
      seen[questID] = true
      local label, kind = QP.StateLabel(state, entry, playerLevel)
      local feed = feeds[questID]
      local goal = questGoals[questID]
      local feedParts = {}
      for _, f in ipairs(feed and feed.goals or {}) do feedParts[#feedParts + 1] = f.name end
      if goal then table.insert(feedParts, 1, "goal: " .. ns.GoalService.Name(goal)) end
      group(groupKey, groupLabel).rows[#group(groupKey, groupLabel).rows + 1] = {
        questID = questID, name = name, level = level, label = label, kind = BADGE_KIND[label] or kind, state = state, entry = entry,
        feeds = feedParts, feed = feed, goal = goal,
      }
    end
    local tab = self.tab
    for _, entry in ipairs(QP.List()) do
      local state = QP.State(entry.id)
      local feeding = feeds[entry.id] ~= nil or questGoals[entry.id] ~= nil
      local include
      if tab == "completed" then include = state.completed
      elseif tab == "goal" then include = feeding and not state.completed
      else include = not state.completed and (not feedOnly or feeding) end
      if include then
        if tab == "goal" then
          local names = {}
          for _, f in ipairs(feeds[entry.id] and feeds[entry.id].goals or {}) do names[#names + 1] = f.name end
          if questGoals[entry.id] then table.insert(names, 1, ns.GoalService.Name(questGoals[entry.id])) end
          local label = table.concat(names, ", ")
          add(label, label, entry.id, entry.name, entry.level, state, entry)
        else
          add(entry.instance or "?", entry.instance or "?", entry.id, entry.name, entry.level, state, entry)
        end
      end
    end
    if tab ~= "completed" then
      for _, log in ipairs(QP.LogEntries()) do
        if not seen[log.questID] then
          local state = QP.State(log.questID)
          local feeding = feeds[log.questID] ~= nil or questGoals[log.questID] ~= nil
          if (tab == "goal" and feeding) or (tab == "zone" and (not feedOnly or feeding)) then
            local key = tab == "goal" and (questGoals[log.questID] and ns.GoalService.Name(questGoals[log.questID]) or "Goals") or (log.zone or "Quest log")
            add(key, key, log.questID, log.title or QP.Name(log.questID), log.level, state, QP.Get(log.questID))
          end
        end
      end
    end
    table.sort(groups, function(a, b) return tostring(a.label) < tostring(b.label) end)
    local total = 0
    for _, g in ipairs(groups) do
      table.sort(g.rows, function(a, b)
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) < (b.level or 0) end
        if a.name ~= b.name then return tostring(a.name) < tostring(b.name) end
        return a.questID < b.questID
      end)
      total = total + #g.rows
    end
    local feedCount = 0
    for _ in pairs(feeds) do feedCount = feedCount + 1 end
    return { groups = groups, feeds = feeds, feedCount = feedCount, total = total, questGoals = questGoals }
  end

  local function renderSide(self, questID, collected)
    local QP = ns.QuestProvider
    local s = self.side
    s.questID = questID
    if not questID then
      for _, w in ipairs(s.content) do w:Hide() end
      for _, o in ipairs(s.objectives) do o:Hide() end
      for _, r in ipairs(s.rewardIcons) do r:Hide() end
      s.callout:Hide()
      s.empty:Show()
      return
    end
    s.empty:Hide()
    for _, w in ipairs(s.content) do w:Show() end
    local entry = QP.Get(questID)
    local state = QP.State(questID)
    local playerLevel = QP.PlayerLevel()
    local label, kind = QP.StateLabel(state, entry, playerLevel)
    s.icon:SetItem(state.ready and QP.ICON_READY or QP.ICON, 1)
    s.title:SetText(QP.Name(questID))
    local metaParts = {}
    local level = (entry and entry.level) or state.level
    if level then metaParts[#metaParts + 1] = Theme.Hex[DIFFICULTY_HEX[QP.Difficulty(level, playerLevel)]] .. "Level " .. level .. "|r" end
    if entry and entry.instance then metaParts[#metaParts + 1] = entry.instance end
    if entry and entry.pickup then metaParts[#metaParts + 1] = (entry.pickup:match("^([^,]+)") or entry.pickup) end
    if entry and entry.requires and entry.requires > playerLevel then metaParts[#metaParts + 1] = Theme.ColorText("missing", "requires level " .. entry.requires) end
    if entry and entry.groupSize and entry.groupSize > 1 then metaParts[#metaParts + 1] = entry.groupSize .. " players" end
    s.meta:SetText(table.concat(metaParts, " - "))
    s.badge:SetBadge(label, BADGE_KIND[label] or kind)

    -- Objectives: live ones when the quest is in the log, the text otherwise, then the chain.
    local lines = {}
    if state.inLog and #state.objectives > 0 then
      for _, o in ipairs(state.objectives) do
        lines[#lines + 1] = { text = o.text or "", value = o.numRequired > 0 and (o.numFulfilled / o.numRequired) or (o.finished and 1 or 0), done = o.finished }
      end
    elseif entry and entry.objective then
      lines[#lines + 1] = { text = entry.objective, value = state.completed and 1 or 0, done = state.completed }
    end
    for _, link in ipairs(entry and entry.chain or {}) do
      local id = tonumber(link.id)
      local done = id and QP.State(id).completed
      lines[#lines + 1] = { text = (done and Theme.Hex.text3 or Theme.Hex.text2) .. "Requires: " .. (link.name or ("quest " .. tostring(link.id))) .. (done and " (done)" or "") .. "|r", value = done and 1 or 0, done = done, chain = true }
    end
    for i, frame in ipairs(s.objectives) do
      local line = lines[i]
      if line then
        frame.text:SetText(line.text)
        frame.bar:SetKind(line.done and "ok" or "gold")
        frame.bar:SetValue(line.value)
        frame:Show()
      else
        frame:Hide()
      end
    end
    if state.ready then
      s.callout.text:SetText("Ready to turn in" .. (entry and entry.turnin and (" - " .. entry.turnin) or ""))
      s.callout:Show()
    elseif state.completed then
      s.callout.text:SetText("Completed")
      s.callout:Show()
    else
      s.callout:Hide()
    end
    -- Rewards
    local rewards = entry and entry.rewards or {}
    for i, iconFrame in ipairs(s.rewardIcons) do
      local reward = rewards[i]
      if reward then
        local item = ns.ItemProvider.GetItem(reward.itemID)
        iconFrame:SetItem(item.icon, item.quality or reward.quality)
        iconFrame.itemID = reward.itemID
        iconFrame:Show()
      else
        iconFrame:Hide()
      end
    end
    local rewardText = entry and (entry.rewardText or entry.rewardSummary) or nil
    if rewardText and rewardText ~= "" then
      rewardText = rewardText:gsub("\n", " - ")
    elseif #rewards > 0 then
      local names = {}
      for _, reward in ipairs(rewards) do names[#names + 1] = reward.name or ns.ItemProvider.GetName(reward.itemID) end
      rewardText = (entry.rewardChoice and "Choose: " or "") .. table.concat(names, ", ")
    else
      rewardText = Theme.ColorText("text3", "No reward data")
    end
    if entry and entry.xp and not (rewardText:find("XP", 1, true)) then rewardText = rewardText .. string.format(" - %d XP", entry.xp) end
    s.rewardsText:SetText(rewardText)
    -- Feeds
    local feed = collected.feeds[questID]
    if feed and #feed.goals > 0 then
      local parts = {}
      for _, f in ipairs(feed.goals) do
        parts[#parts + 1] = string.format("%s: %d missing for %s", ns.ItemProvider.GetName(f.itemID), f.count or 0, f.name)
      end
      s.feedsText:SetText(table.concat(parts, "\n"))
    else
      s.feedsText:SetText(Theme.ColorText("text3", "No open goal needs its rewards"))
    end
    local goal = collected.questGoals[questID]
    s.addGoal:SetLabel(goal and (goal.status == "COMPLETED" and "Goal completed" or "Open goal") or "+ Add goal")
    s.addGoal:SetEnabledState(not (goal and goal.status == "COMPLETED"))
    s.link:SetEnabledState(state.inLog)
    s.watch:SetEnabledState(state.inLog)
  end

  function screen:Refresh()
    local QP = ns.QuestProvider
    if not QP or not QP.IsAvailable() then
      list:Hide()
      side:Hide()
      tabs:Hide()
      feedOnly:Hide()
      self.empty:Set("Quests unavailable", "This client does not expose the quest API ForeverPath needs (C_QuestLog).")
      self.empty:Show()
      return
    end
    self.empty:Hide()
    list:Show()
    side:Show()
    tabs:Show()
    feedOnly:Show()
    local ui = ns.chardb and ns.chardb.ui or {}
    if ui.questsTab and ui.questsTab ~= self.tab then
      self.tab = ui.questsTab
      tabs:Select(self.tab)
    end
    feedOnly:SetChecked(ui.questsFeedOnly == true)

    -- A newly selected quest goal takes over the selection.
    local goal = ns.GoalService.GetSelected()
    local goalQuest = goal and goal.type == "COMPLETE_QUEST" and goal.target.questID or nil
    local questID = self.questID
    if goalQuest and (goal.id ~= self.lastGoalID or not questID) then questID = goalQuest end
    self.lastGoalID = goal and goal.id or nil
    questID = questID or ui.quest

    local collected = self:Collect()
    local y = 0
    local groupIndex, rowIndex = 0, 0
    local firstQuest
    for _, g in ipairs(collected.groups) do
      groupIndex = groupIndex + 1
      local groupRow = self.groupPool:Get(groupIndex)
      groupRow:ClearAllPoints()
      groupRow:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
      groupRow:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, -y)
      groupRow.label:SetText(Theme.Upper(g.label))
      groupRow.count:SetText(tostring(#g.rows))
      y = y + GROUP_ROW
      for _, r in ipairs(g.rows) do
        rowIndex = rowIndex + 1
        firstQuest = firstQuest or r.questID
        local row = self.rowPool:Get(rowIndex)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", 0, -y)
        row:SetPoint("TOPRIGHT", scroll.content, "TOPRIGHT", 0, -y)
        y = y + ROW
        row.questID = r.questID
        local mark, markColor = markerFor(r.label)
        row.marker:SetText(Theme.ColorText(markColor, mark))
        row.level:SetText(r.level and (Theme.Hex[DIFFICULTY_HEX[QP.Difficulty(r.level, QP.PlayerLevel())]] .. "[" .. r.level .. "]|r") or "")
        row.name:SetText(r.name)
        row.feeds:SetText(#r.feeds > 0 and ("Feeds " .. table.concat(r.feeds, ", ")) or Theme.ColorText("text3", r.entry and r.entry.instance and r.entry.source == "attune" and (r.entry.attunement or "Attunement") or ""))
        row.badge:SetBadge(r.label, r.kind)
        row:SetAlpha(r.label == "Locked" and 0.6 or 1)
        row:SetSelected(r.questID == questID)
      end
    end
    self.rowPool:HideFrom(rowIndex + 1)
    self.groupPool:HideFrom(groupIndex + 1)
    scroll:SetContentHeight(y)
    if collected.total == 0 then
      local why
      if self.tab == "completed" then why = "No known quest is completed on this character yet."
      elseif self.tab == "goal" then why = "No known quest rewards something your goals are missing."
      elseif feedOnly:GetChecked() then why = "No known quest feeds a goal. Untick the filter to see every quest."
      elseif not QP.HasJournal() and not QP.HasAttune() then why = "ForeverPath learns quests from ForeverDungeonJournal and Attune; without them only your quest log is listed."
      else why = "Nothing in your log and no known quest for your faction." end
      self.listEmpty:Set("No quests here", why)
      self.listEmpty:Show()
    else
      self.listEmpty:Hide()
    end
    self.footerFeeds:SetText(string.format("%d quest%s feed%s your goals", collected.feedCount, collected.feedCount == 1 and "" or "s", collected.feedCount == 1 and "s" or ""))
    local numQuests, max = QP.LogCapacity()
    self.footerLog:SetText(string.format("Quest log %d / %d", numQuests, max))
    if not questID or (not QP.Get(questID) and not QP.State(questID).inLog) then questID = firstQuest end
    self.questID = questID
    renderSide(self, questID, collected)
  end

  return screen
end

ns.UI.Screens.quests = { label = "Quests", Create = Create }
