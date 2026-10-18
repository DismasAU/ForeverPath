-- Screen 07: account-wide characters. Cards per character (live / snapshot /
-- cached), a banner naming the alt that already holds the most of what your
-- active goals need, and the scope switch that lets the planner count alts'
-- bags as owned.
local _, ns = ...

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local C = Theme.Colors
local Util = ns.Util
local Characters = ns.CharacterProvider

ns.UI.Screens = ns.UI.Screens or {}

local CARD_BASE_HEIGHT = 274      -- everything except the profession rows
local PROF_ROWS = 6               -- 2 primary + up to 4 secondary
local PROF_ROW_HEIGHT = 22
local CARD_GAP = 10
local CARDS_PER_ROW = 3
local MATERIALS = 6
local LINES = 3
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"

local FRESH_BADGE = { live = { "Live", "ok" }, snapshot = { "Snapshot", "info" }, cached = { "Cached", "partial" } }

local function classColor(classFile)
  local colors = _G.RAID_CLASS_COLORS
  if classFile and type(colors) == "table" and colors[classFile] then
    local c = colors[classFile]
    return { c.r, c.g, c.b }
  end
  return C.text
end

local function ageText(record)
  local age = Util.Now() - (record.lastSeen or 0)
  if age >= 86400 then
    local days = math.floor(age / 86400)
    return string.format("%d day%s", days, days == 1 and "" or "s")
  end
  return Util.FormatAgo(record.lastSeen)
end

---------------------------------------------------------------------------
-- Needs of the current character's active goals, from the planner views.
---------------------------------------------------------------------------
local function currentNeeds()
  local needs, order = {}, {}
  for _, view in pairs(ns.UI.MainFrame.views or {}) do
    if view.goal and view.goal.status == "ACTIVE" and view.tree then
      for _, node in pairs(view.tree.byKey) do
        -- What this character cannot cover from its own bags and bank, so
        -- the banner reads the same whether alts are counted or not.
        local short = node.depth > 0 and (node.missing + (node.ownedAlts or 0)) or 0
        if short > 0 then
          if not needs[node.itemID] then order[#order + 1] = node.itemID end
          needs[node.itemID] = (needs[node.itemID] or 0) + short
        end
      end
    end
  end
  table.sort(order, function(a, b)
    if needs[a] ~= needs[b] then return needs[a] > needs[b] end
    return a < b
  end)
  return needs, order
end

---------------------------------------------------------------------------
-- Card
---------------------------------------------------------------------------
local function sectionLabel(parent, text)
  return Widgets.Text(parent, "label", text, { caps = true })
end

local function createCard(content, index, screen)
  local card = Widgets.Panel(content, nil, { pad = 0 })
  local body = card.body

  local portrait = Widgets.Frame(body, nil, { bg = C.black, border = C.bronzeDim })
  portrait:SetSize(38, 38)
  portrait:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -10)
  local portraitTexture = portrait:CreateTexture(nil, "ARTWORK")
  portraitTexture:SetPoint("TOPLEFT", portrait, "TOPLEFT", 2, -2)
  portraitTexture:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", -2, 2)
  card.portrait, card.portraitTexture = portrait, portraitTexture

  local name = Widgets.Text(body, "goalName", "")
  name:SetPoint("TOPLEFT", portrait, "TOPRIGHT", 10, -2)
  local meta = Widgets.Text(body, "small", "")
  meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  meta:SetPoint("RIGHT", body, "RIGHT", -10, 0)
  local badge = Widgets.Badge(body, "Live", "ok")
  badge:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, -10)
  name:SetPoint("RIGHT", badge, "LEFT", -6, 0)
  local age = Widgets.Text(body, "note", "", { justify = "RIGHT", color = C.partial })
  age:SetPoint("TOPRIGHT", badge, "BOTTOMRIGHT", 0, -3)
  local headerLine = Widgets.Engraved(body)
  headerLine:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -56)
  headerLine:SetPoint("TOPRIGHT", body, "TOPRIGHT", -10, -56)
  card.name, card.meta, card.badge, card.age = name, meta, badge, age

  -- Professions
  local profLabel = sectionLabel(body, "Professions")
  profLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -64)
  card.professions = {}
  local previous = profLabel
  for i = 1, PROF_ROWS do
    local row = CreateFrame("Frame", nil, body)
    row:SetHeight(PROF_ROW_HEIGHT - 2)
    row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -4 or -2)
    row:SetPoint("RIGHT", body, "RIGHT", -10, 0)
    row.name = Widgets.Text(row, "secondaryBright", "")
    row.name:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.value = Widgets.Text(row, "small", "", { justify = "RIGHT" })
    row.value:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
    row.bar = Widgets.ProgressBar(row, 5, "gold")
    row.bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
    row.bar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    card.professions[i] = row
    previous = row
  end

  -- Relevant materials (positioned by Arrange, below the profession rows)
  local matLabel = sectionLabel(body, "Relevant materials")
  card.matLabel = matLabel
  card.materials = {}
  for i = 1, MATERIALS do
    local slot = Widgets.ItemIcon(body, 32)
    slot:SetPoint("TOPLEFT", matLabel, "BOTTOMLEFT", (i - 1) * 36, -5)
    slot.count = Widgets.Text(slot, "small", "", { justify = "RIGHT", color = C.text })
    slot.count:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -2, 1)
    slot.outline = Widgets.Frame(slot, nil, { border = C.gold })
    slot.outline:SetPoint("TOPLEFT", slot, "TOPLEFT", -1, 1)
    slot.outline:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", 1, -1)
    Widgets.SetItemTooltip(slot, function(self) return self.itemID end, function(self)
      return self.tip
    end)
    card.materials[i] = slot
  end
  card.materialsEmpty = Widgets.Text(body, "small", "", { color = C.text3 })
  card.materialsEmpty:SetPoint("TOPLEFT", matLabel, "BOTTOMLEFT", 0, -10)

  -- Assigned goals
  local goalsLabel = sectionLabel(body, "Goals")
  goalsLabel:SetPoint("TOPLEFT", matLabel, "BOTTOMLEFT", 0, -46)
  card.goals = {}
  previous = goalsLabel
  for i = 1, LINES do
    local line = Widgets.Text(body, "small", "")
    line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -4 or -2)
    line:SetPoint("RIGHT", body, "RIGHT", -10, 0)
    card.goals[i] = line
    previous = line
  end

  -- Can craft
  local craftLabel = sectionLabel(body, "Can craft for your goals")
  craftLabel:SetPoint("TOPLEFT", goalsLabel, "BOTTOMLEFT", 0, -48)
  card.crafts = {}
  previous = craftLabel
  for i = 1, LINES do
    local line = Widgets.Text(body, "small", "")
    line:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, i == 1 and -4 or -2)
    line:SetPoint("RIGHT", body, "RIGHT", -10, 0)
    card.crafts[i] = line
    previous = line
  end

  local note = Widgets.Text(body, "note", "", { color = C.partial })
  note:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 10, 8)
  local forget = Widgets.Button(body, "Forget", { onClick = function()
    if card.key then
      local ok, err = Characters.Remove(card.key)
      ns.UI.MainFrame.SetStatus(ok and "Character forgotten." or tostring(err), ok and "info" or "error")
      if ok then screen:Refresh() end
    end
  end })
  forget:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -8, 6)
  card.note, card.forget = note, forget

  -- Moves the sections below the profession block so `rows` rows fit.
  function card:Arrange(rows)
    matLabel:ClearAllPoints()
    matLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 10, -(64 + 14 + rows * PROF_ROW_HEIGHT))
  end

  function card:Render(entry, needs, needOrder)
    local record = entry.record
    self.key = entry.key
    local color = classColor(record.classFile)
    name:SetText(record.name or "?")
    Widgets.SetTextColor(name, color)
    local parts = {}
    if (record.level or 0) > 0 then parts[#parts + 1] = "Level " .. record.level end
    if record.race and record.race ~= "" then parts[#parts + 1] = record.race end
    if record.class and record.class ~= "" then parts[#parts + 1] = record.class end
    if record.gold then parts[#parts + 1] = Widgets.Money(record.gold, true) end
    meta:SetText(table.concat(parts, " "))
    local fresh = FRESH_BADGE[entry.freshness] or FRESH_BADGE.cached
    badge:SetBadge(fresh[1], fresh[2])
    if entry.isCurrent then
      age:SetText("")
    else
      age:SetText(ageText(record))
      Widgets.SetTextColor(age, entry.freshness == "cached" and C.partial or C.text3)
    end
    if entry.isCurrent and type(SetPortraitTexture) == "function" then
      portraitTexture:SetTexCoord(0, 1, 0, 1)
      pcall(SetPortraitTexture, portraitTexture, "player")
    else
      portraitTexture:SetTexture(CLASS_ICONS)
      local coords = type(CLASS_ICON_TCOORDS) == "table" and record.classFile and CLASS_ICON_TCOORDS[record.classFile]
      if coords then
        portraitTexture:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
      else
        portraitTexture:SetTexCoord(0, 1, 0, 1)
      end
    end
    self:SetAlpha(entry.freshness == "cached" and 0.8 or 1)

    for i, row in ipairs(self.professions) do
      local p = record.professions and record.professions[i]
      if p then
        row.name:SetText((p.name or "?") .. (p.scanned and Theme.ColorText("text3", " (recorded)") or ""))
        row.value:SetText(string.format("%d / %d", p.skillLevel or 0, p.maxSkillLevel or 0))
        row.bar:SetKind((p.maxSkillLevel or 0) > 0 and (p.skillLevel or 0) >= p.maxSkillLevel and "ok" or "gold")
        row.bar:SetValue((p.maxSkillLevel or 0) > 0 and (p.skillLevel or 0) / p.maxSkillLevel or 0)
        row:Show()
      elseif i == 1 then
        row.name:SetText(Theme.ColorText("text3", "No professions recorded"))
        row.value:SetText("")
        row.bar:SetValue(0)
        row:Show()
      else
        row:Hide()
      end
    end

    -- Materials this character holds that the current goals still need.
    local shown = 0
    for _, itemID in ipairs(needOrder) do
      if shown >= MATERIALS then break end
      local bags = record.bags and record.bags.items and record.bags.items[itemID] or 0
      local bank = record.bank and record.bank.items and record.bank.items[itemID] or 0
      if not entry.isCurrent and bags + bank > 0 then
        shown = shown + 1
        local slot = self.materials[shown]
        local item = ns.ItemProvider.GetItem(itemID)
        slot.itemID = itemID
        slot:SetItem(item.icon, item.quality)
        slot.count:SetText(tostring(bags + bank))
        slot.outline:Show()
        slot.tip = { string.format("%s has %d (bags %d, bank %d)", record.name, bags + bank, bags, bank), string.format("Your goals still need %d", needs[itemID] or 0) }
        slot:Show()
      end
    end
    for i = shown + 1, MATERIALS do self.materials[i]:Hide() end
    if shown == 0 then
      self.materialsEmpty:SetText(entry.isCurrent and "Your own bags are counted in every goal." or (next(needs) and "Nothing your goals need." or "No active goals need materials."))
      self.materialsEmpty:Show()
    else
      self.materialsEmpty:Hide()
    end

    local goals = record.goals or {}
    for i, line in ipairs(self.goals) do
      local g = goals[i]
      if g then
        line:SetText((i == LINES and #goals > LINES) and string.format("+%d more", #goals - LINES + 1) or (g.title or "?"))
        Widgets.SetTextColor(line, C.text)
      elseif i == 1 then
        line:SetText("No open goals")
        Widgets.SetTextColor(line, C.text3)
      else
        line:SetText("")
      end
    end

    -- Needed items this character can craft (learned recipe).
    local crafts = {}
    for _, itemID in ipairs(needOrder) do
      if #crafts >= LINES then break end
      local ids = ns.db and ns.db.itemRecipes and ns.db.itemRecipes[itemID]
      if type(ids) == "table" then
        for recipeID in pairs(ids) do
          local recipe = ns.db.recipes[recipeID]
          local known = entry.isCurrent and ns.ProfessionProvider.IsLearned(recipeID) or (record.knownRecipes and record.knownRecipes[recipeID])
          if recipe and known then
            crafts[#crafts + 1] = string.format("%s %s- %s|r", ns.ItemProvider.GetName(itemID), Theme.Hex.text2, recipe.professionName or "?")
            break
          end
        end
      end
    end
    for i, line in ipairs(self.crafts) do
      if crafts[i] then
        line:SetText(crafts[i])
        Widgets.SetTextColor(line, C.text)
      elseif i == 1 then
        line:SetText(next(needs) and "Nothing your goals need" or "No active goals")
        Widgets.SetTextColor(line, C.text3)
      else
        line:SetText("")
      end
    end

    if entry.isCurrent then
      note:SetText("")
      forget:Hide()
    else
      note:SetText(entry.freshness == "cached" and string.format("Log in on %s to refresh", record.name) or "")
      forget:Show()
    end
  end
  return card
end

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------
local function Create(parent)
  local screen = CreateFrame("Frame", nil, parent)

  -- Banner
  local banner = Widgets.Frame(screen, nil, { bg = Theme.RGB("#1B222A"), border = Theme.RGB("#4A6A8A") })
  banner:SetHeight(58)
  banner:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
  banner:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
  local bannerTitle = Widgets.Text(banner, "body", "", { color = C.text })
  bannerTitle:SetPoint("TOPLEFT", banner, "TOPLEFT", 14, -11)
  local bannerDetail = Widgets.Text(banner, "small", "", { color = C.info })
  bannerDetail:SetPoint("TOPLEFT", bannerTitle, "BOTTOMLEFT", 0, -4)
  local dismiss = Widgets.Button(banner, "Dismiss", { onClick = function()
    screen.bannerDismissed = true
    screen:Refresh()
  end })
  dismiss:SetPoint("RIGHT", banner, "RIGHT", -10, 0)
  local planMail = Widgets.Button(banner, "Plan mail", { primary = true, onClick = function()
    ns.UI.MainFrame.ShowScreen("shopping")
  end })
  planMail:SetPoint("RIGHT", dismiss, "LEFT", -6, 0)
  Widgets.SetTooltip(planMail, "Plan mail", { "Opens the shopping list; the strip under its summary says what each alt can mail you." })
  screen.planMail = planMail
  bannerTitle:SetPoint("RIGHT", planMail, "LEFT", -12, 0)
  bannerDetail:SetPoint("RIGHT", planMail, "LEFT", -12, 0)
  screen.banner, screen.bannerTitle, screen.bannerDetail = banner, bannerTitle, bannerDetail

  -- Scope row
  local scopeRow = CreateFrame("Frame", nil, screen)
  scopeRow:SetHeight(26)
  scopeRow:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
  scopeRow:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
  local scopeLabel = Widgets.Text(scopeRow, "label", "Scope", { caps = true })
  scopeLabel:SetPoint("LEFT", scopeRow, "LEFT", 2, 0)
  local scope = Widgets.Segment(scopeRow, { { key = "character", label = "This character" }, { key = "account", label = "Account-wide" } }, function(key)
    if ns.db then ns.db.settings.includeAlts = key == "account" end
    ns.UI.MainFrame.SetStatus(key == "account" and "Alts' bags and banks now count as owned." or "Only this character's bags and bank count as owned.", "info")
    ns.UI.MainFrame.RequestRefresh()
  end)
  scope:SetPoint("LEFT", scopeLabel, "RIGHT", 10, 0)
  local scopeHint = Widgets.Text(scopeRow, "small", "", { color = C.text3 })
  scopeHint:SetPoint("LEFT", scope, "RIGHT", 12, 0)
  screen.scope, screen.scopeHint = scope, scopeHint
  local legend = { { "ok", "Live" }, { "info", "Snapshot" }, { "partial", "Cached" } }
  local previous
  for i = #legend, 1, -1 do
    local text = Widgets.Text(scopeRow, "small", legend[i][2])
    local dot = Widgets.Dot(scopeRow, legend[i][1])
    if previous then text:SetPoint("RIGHT", previous, "LEFT", -12, 0) else text:SetPoint("RIGHT", scopeRow, "RIGHT", -2, 0) end
    dot:SetPoint("RIGHT", text, "LEFT", -4, 0)
    previous = dot
  end
  screen.scopeRow = scopeRow

  -- Cards
  local scroll = Widgets.ScrollArea(screen)
  scroll:SetPoint("TOPLEFT", scopeRow, "BOTTOMLEFT", 0, -8)
  scroll:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  screen.scroll = scroll
  screen.pool = Widgets.Pool(scroll.content, function(content, index) return createCard(content, index, screen) end)
  screen.empty = Widgets.EmptyState(screen, "No other characters yet", "Log in on each character once; ForeverPath keeps a snapshot of its bags, bank, professions and goals here.")
  screen.empty:SetPoint("TOPLEFT", scopeRow, "BOTTOMLEFT", 0, -60)
  screen.empty:SetPoint("TOPRIGHT", scopeRow, "BOTTOMRIGHT", 0, -60)
  screen.empty:SetHeight(80)
  screen.empty:Hide()

  function screen:LayoutCards(count)
    local width = scroll:GetWidth() or 0
    if width <= 0 then return end
    local cardWidth = math.floor((width - CARD_GAP * (CARDS_PER_ROW - 1)) / CARDS_PER_ROW)
    local cardHeight = CARD_BASE_HEIGHT + (self.profRows or 1) * PROF_ROW_HEIGHT
    for i = 1, count do
      local card = self.pool.rows[i]
      local row, col = math.floor((i - 1) / CARDS_PER_ROW), (i - 1) % CARDS_PER_ROW
      card:ClearAllPoints()
      card:SetSize(cardWidth, cardHeight)
      card:SetPoint("TOPLEFT", scroll.content, "TOPLEFT", col * (cardWidth + CARD_GAP), -row * (cardHeight + CARD_GAP))
    end
    local rows = math.ceil(count / CARDS_PER_ROW)
    scroll:SetContentHeight(rows * cardHeight + math.max(0, rows - 1) * CARD_GAP)
  end
  scroll:HookScript("OnSizeChanged", function() screen:LayoutCards(screen.cardCount or 0) end)

  function screen:Refresh()
    local includeAlts = ns.db and ns.db.settings.includeAlts == true
    scope:Select(includeAlts and "account" or "character")
    scopeHint:SetText(includeAlts and "Alts' snapshots count as owned in every goal" or "Alts are shown for information only")

    local needs, needOrder = currentNeeds()
    local entries = Characters.List()
    self.cardCount = #entries
    -- Every card shows the same number of profession rows so sections line up.
    local rows = 1
    for _, entry in ipairs(entries) do
      rows = math.max(rows, math.min(PROF_ROWS, #(entry.record.professions or {})))
    end
    self.profRows = rows
    for index, entry in ipairs(entries) do
      local card = self.pool:Get(index)
      card:Arrange(rows)
      card:Render(entry, needs, needOrder)
    end
    self.pool:HideFrom(#entries + 1)
    self:LayoutCards(#entries)
    if #entries <= 1 then self.empty:Show() else self.empty:Hide() end

    -- Banner: the alt that covers the most of what is missing.
    local best = not self.bannerDismissed and Characters.BestCoverage(needs) or nil
    if best then
      bannerTitle:SetText(string.format("%s%s|r already has %d of the required materials.", Theme.Hex.info, best.name, best.covered))
      local parts, extra = {}, 0
      for i, item in ipairs(best.items) do
        if i <= 4 then parts[#parts + 1] = string.format("%d %s", item.count, ns.ItemProvider.GetName(item.itemID)) else extra = extra + 1 end
      end
      bannerDetail:SetText(table.concat(parts, ", ") .. (extra > 0 and string.format(", +%d more", extra) or "") .. (includeAlts and " - counted as owned" or " - turn on Account-wide to count them"))
      banner:Show()
      scopeRow:ClearAllPoints()
      scopeRow:SetPoint("TOPLEFT", banner, "BOTTOMLEFT", 0, -10)
      scopeRow:SetPoint("TOPRIGHT", banner, "BOTTOMRIGHT", 0, -10)
    else
      banner:Hide()
      scopeRow:ClearAllPoints()
      scopeRow:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
      scopeRow:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
    end
    self.lastBest = best
  end

  return screen
end

ns.UI.Screens.characters = { label = "Characters", Create = Create }
