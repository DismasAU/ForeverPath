-- Screen 02: crafting goal details with the requirements table.
local _, ns = ...

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local C = Theme.Colors
local Status = ns.Status
local Util = ns.Util

ns.UI.Screens = ns.UI.Screens or {}

local ROW = 40
local COLUMNS = { need = 40, have = 40, missing = 54, price = 74, subtotal = 74, source = 150 }
local SORTS = { { key = "missing", label = "Sort: Missing" }, { key = "name", label = "Sort: Name" }, { key = "need", label = "Sort: Need" } }
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"

local function sortLabel(key)
  for _, s in ipairs(SORTS) do if s.key == key then return s.label end end
  return SORTS[1].label
end

local function createMaterialRow(content, index)
  local row = Widgets.Frame(content, nil, { frameType = "Button" })
  row:SetHeight(ROW)
  row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(index - 1) * ROW)
  row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -(index - 1) * ROW)
  local tint = Widgets.Texture(row, C.missing, 0, "BACKGROUND")
  tint:SetAllPoints(row)
  local line = Widgets.HLine(row, C.black, 0.55)
  line:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  Widgets.SetColor(highlight, C.white, 0.03)

  local icon = Widgets.ItemIcon(row, 28)
  icon:SetPoint("LEFT", row, "LEFT", 10, 0)
  local sourceFrame = CreateFrame("Frame", nil, row)
  sourceFrame:SetSize(COLUMNS.source, ROW)
  sourceFrame:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  sourceFrame.tags = {}
  local subtotal = Widgets.Text(row, "secondaryBright", "", { justify = "RIGHT", width = COLUMNS.subtotal })
  subtotal:SetPoint("RIGHT", sourceFrame, "LEFT", -10, 0)
  local price = Widgets.Text(row, "secondaryBright", "", { justify = "RIGHT", width = COLUMNS.price })
  price:SetPoint("RIGHT", subtotal, "LEFT", -10, 0)
  local missing = Widgets.Text(row, "body", "", { justify = "RIGHT", width = COLUMNS.missing })
  missing:SetPoint("RIGHT", price, "LEFT", -10, 0)
  local check = row:CreateTexture(nil, "OVERLAY")
  check:SetTexture(CHECK)
  check:SetSize(16, 16)
  check:SetPoint("RIGHT", price, "LEFT", -12, 0)
  if check.SetVertexColor then check:SetVertexColor(C.ok[1], C.ok[2], C.ok[3]) end
  check:Hide()
  local have = Widgets.Text(row, "body", "", { justify = "RIGHT", width = COLUMNS.have })
  have:SetPoint("RIGHT", missing, "LEFT", -10, 0)
  local need = Widgets.Text(row, "body", "", { justify = "RIGHT", width = COLUMNS.need })
  need:SetPoint("RIGHT", have, "LEFT", -10, 0)
  local name = Widgets.Text(row, "body", "")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
  name:SetPoint("RIGHT", need, "LEFT", -10, 0)
  local note = Widgets.Text(row, "note", "")
  note:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 1)
  note:SetPoint("RIGHT", need, "LEFT", -10, 0)
  row.tint, row.icon, row.name, row.note, row.need, row.have, row.missing, row.check, row.price, row.subtotal, row.sourceFrame =
    tint, icon, name, note, need, have, missing, check, price, subtotal, sourceFrame

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
      if previous then
        tag:SetPoint("LEFT", previous, "RIGHT", 4, 0)
      else
        tag:SetPoint("LEFT", sourceFrame, "LEFT", 0, 0)
      end
      tag:Show()
      previous = tag
    end
    for i = #list + 1, #sourceFrame.tags do
      sourceFrame.tags[i]:Hide()
    end
  end

  Widgets.SetItemTooltip(row, function(self) return self.itemID end, function(self)
    local m = self.material
    if not m then return nil end
    local lines = { string.format("Per craft: %d", m.perCraft), string.format("Bags: %d", m.ownedBags or 0) }
    if m.ownedBank then
      lines[#lines + 1] = string.format("Bank: %d (%s)", m.ownedBank, m.bankSource == "live" and "live" or (m.bankSource == "cached" and "snapshot" or "client reported"))
    end
    for _, alt in ipairs(m.altSources or {}) do
      lines[#lines + 1] = string.format("%s has %d (%s%s)", alt.name, alt.count, alt.freshness, ns.db and ns.db.settings.includeAlts and ", counted" or ", not counted")
    end
    if (m.reserved or 0) > 0 then
      lines[#lines + 1] = string.format("Reserved by higher-priority goals: %d", m.reserved)
    end
    if m.alternatives and #m.alternatives > 0 then
      lines[#lines + 1] = "Alternative reagents: " .. Util.Join(m.alternatives)
    end
    local price = ns.PriceProvider.GetPrice(m.itemID)
    if price then
      lines[#lines + 1] = string.format("Vendor price: %s each%s", Widgets.Money(price.copper, true), price.vendor and (" from " .. price.vendor) or "")
    else
      lines[#lines + 1] = "Price: no data (visit a vendor that sells it; AH prices arrive later)"
    end
    for _, hint in ipairs(ns.SourceProvider.Sources(m.itemID)) do
      if hint.kind ~= "vendor" then lines[#lines + 1] = (hint.label or "?") .. (hint.detail and (" - " .. hint.detail) or "") end
    end
    return lines
  end)
  Widgets.ShiftClickLinks(row, function(self) return self.itemID end)
  return row
end

local function createHero(screen)
  local hero = Widgets.Panel(screen, nil, { pad = 0 })
  hero:SetHeight(136)
  local body = hero.body
  local icon = Widgets.ItemIcon(body, 64)
  icon:SetPoint("TOPLEFT", body, "TOPLEFT", 16, -16)
  local name = Widgets.Text(body, "hero", "")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 16, -2)
  local meta = Widgets.Text(body, "secondary", "")
  meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
  hero.chips = {}
  for i = 1, 3 do
    local chip = Widgets.Chip(body, "info", "")
    if i == 1 then
      chip:SetPoint("TOPLEFT", meta, "BOTTOMLEFT", 0, -10)
    else
      chip:SetPoint("LEFT", hero.chips[i - 1], "RIGHT", 6, 0)
    end
    chip:Hide()
    hero.chips[i] = chip
  end

  local completionLabel = Widgets.Text(body, "label", "Completion", { caps = true })
  local percent = Widgets.Text(body, "bigNumberLarge", "", { color = C.gold, justify = "RIGHT" })
  percent:SetPoint("TOPRIGHT", body, "TOPRIGHT", -18, -18)
  completionLabel:SetPoint("TOPLEFT", body, "TOPRIGHT", -270, -24)
  local bar = Widgets.ProgressBar(body, 10, "gold")
  bar:SetPoint("TOPLEFT", completionLabel, "BOTTOMLEFT", 0, -10)
  bar:SetPoint("RIGHT", body, "RIGHT", -18, 0)
  local reagents = Widgets.Text(body, "small", "")
  reagents:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -8)
  reagents:SetPoint("RIGHT", body, "RIGHT", -18, 0)
  local divider = Widgets.Engraved(body, true)
  divider:SetHeight(90)
  divider:SetPoint("RIGHT", completionLabel, "LEFT", -18, -30)

  local quantityLabel = Widgets.Text(body, "label", "Quantity", { caps = true, justify = "CENTER" })
  quantityLabel:SetPoint("TOP", divider, "TOP", -70, 0)
  local stepper = Widgets.Stepper(body, function(value)
    if not screen.goal then return end
    if screen.goal.type == "REACH_SKILL" then
      ns.GoalService.SetRank(screen.goal.id, value)
    elseif screen.goal.target.itemID or screen.goal.type == "APPLY_ENCHANT" then
      ns.GoalService.SetQuantity(screen.goal.id, value)
    end
  end)
  stepper:SetPoint("TOP", quantityLabel, "BOTTOM", 0, -8)
  -- Keep the name block clear of the quantity stepper at small window sizes.
  name:SetPoint("RIGHT", stepper, "LEFT", -20, 0)
  meta:SetPoint("RIGHT", stepper, "LEFT", -20, 0)

  -- "Set waypoint": the map pin for the next quest step, when one is recorded.
  local waypoint = Widgets.Button(body, "Set waypoint", { width = 110, onClick = function()
    local view = screen.view
    if not (view and view.waypoint) then return end
    local ok, message = ns.QuestProvider.SetWaypoint(view.waypoint)
    ns.UI.MainFrame.SetStatus(message, ok and "ok" or "error")
  end })
  waypoint:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 16, 10)
  waypoint:Hide()
  hero.waypoint = waypoint

  hero.icon, hero.name, hero.meta, hero.percent, hero.bar, hero.reagents, hero.stepper = icon, name, meta, percent, bar, reagents, stepper
  return hero
end

local BIND_LABELS = { [1] = "Binds when picked up", [2] = "Binds when equipped", [3] = "Binds when used", [4] = "Quest item" }

local function describeItem(itemID)
  if not ns.Compat.GetItemInfo then return "" end
  local ok, _, _, _, itemLevel, _, itemType, itemSubType, _, _, _, _, _, _, bindType = pcall(ns.Compat.GetItemInfo, itemID)
  if not ok then return "" end
  local parts = {}
  if itemSubType and itemSubType ~= "" then parts[#parts + 1] = itemSubType elseif itemType then parts[#parts + 1] = itemType end
  if itemLevel and itemLevel > 1 then parts[#parts + 1] = "Item level " .. itemLevel end
  if bindType and BIND_LABELS[bindType] then parts[#parts + 1] = BIND_LABELS[bindType] end
  return table.concat(parts, " - ")
end

local function Create(parent)
  local screen = CreateFrame("Frame", nil, parent)

  -- Breadcrumb row
  local crumbs = CreateFrame("Frame", nil, screen)
  crumbs:SetHeight(24)
  crumbs:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, 0)
  crumbs:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, 0)
  local crumbGoals = Widgets.Text(crumbs, "secondary", "My Goals", { color = C.text2 })
  crumbGoals:SetPoint("LEFT", crumbs, "LEFT", 2, 0)
  local crumbButton = CreateFrame("Button", nil, crumbs)
  crumbButton:SetAllPoints(crumbGoals)
  crumbButton:SetScript("OnClick", function() ns.UI.MainFrame.ShowScreen("goals") end)
  local crumbRest = Widgets.Text(crumbs, "secondary", "")
  crumbRest:SetPoint("LEFT", crumbGoals, "RIGHT", 0, 0)
  local remove = Widgets.Button(crumbs, "Remove goal", { onClick = function()
    if screen.goal then
      ns.GoalService.Remove(screen.goal.id)
      ns.UI.MainFrame.SetStatus("Goal removed.", "info")
    end
  end })
  remove:SetPoint("RIGHT", crumbs, "RIGHT", 0, 0)
  local tracked = Widgets.Checkbox(crumbs, "Show in tracker", function(checked)
    if screen.goal then ns.GoalService.SetTracked(screen.goal.id, checked) end
  end)
  tracked:SetPoint("RIGHT", remove, "LEFT", -14, 0)
  screen.crumbRest, screen.tracked, screen.remove = crumbRest, tracked, remove

  local hero = createHero(screen)
  hero:SetPoint("TOPLEFT", crumbs, "BOTTOMLEFT", 0, -6)
  hero:SetPoint("TOPRIGHT", crumbs, "BOTTOMRIGHT", 0, -6)
  screen.hero = hero

  local tabs = Widgets.Tabs(screen, {
    { key = "requirements", label = "Requirements" },
    { key = "tree", label = "Dependency Tree" },
    { key = "craftwise", label = "CraftWise" },
    { key = "notes", label = "Notes" },
  }, function(key)
    screen.tab = key
    screen:Refresh()
  end)
  tabs:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, -10)
  tabs:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", -330, -10)
  screen.tabs = tabs
  screen.tab = "requirements"
  local sort = Widgets.Dropdown(screen, sortLabel("missing"), 150, function(self)
    local current = ns.chardb and ns.chardb.ui.materialSort or "missing"
    local items = {}
    for _, s in ipairs(SORTS) do items[#items + 1] = { text = s.label:gsub("Sort: ", ""), value = s.key, selected = s.key == current } end
    Widgets.Menu(self, items, function(value)
      if ns.chardb then ns.chardb.ui.materialSort = value end
      screen:Refresh()
    end)
  end)
  sort:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", 0, -36)
  local alts = Widgets.Checkbox(screen, "Include alts' bags", function(checked)
    if ns.db then ns.db.settings.includeAlts = checked and true or false end
    ns.UI.MainFrame.SetStatus(checked and "Alts' bags and banks now count as owned." or "Only this character's bags and bank count as owned.", "info")
    ns.UI.MainFrame.RequestRefresh()
  end)
  alts:SetPoint("RIGHT", sort, "LEFT", -14, 0)
  Widgets.SetTooltip(alts, "Include alts' bags", { "Counts the snapshotted bags and bank of your other characters as owned.", "Snapshots are taken whenever you log in or out on a character." })
  screen.sort, screen.alts = sort, alts

  local table_ = Widgets.Panel(screen, nil, { pad = 0 })
  table_:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -1)
  table_:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  local body = table_.body
  local header = Widgets.Frame(body, nil, { bg = C.sidebar })
  header:SetHeight(26)
  header:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  header:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
  local headerLine = Widgets.HLine(header, C.black, 1)
  headerLine:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", 0, 0)
  headerLine:SetPoint("BOTTOMRIGHT", header, "BOTTOMRIGHT", 0, 0)
  local hSource = Widgets.Text(header, "tableHeader", "Source", { caps = true, width = COLUMNS.source })
  hSource:SetPoint("RIGHT", header, "RIGHT", -10, 0)
  local hSubtotal = Widgets.Text(header, "tableHeader", "Subtotal", { caps = true, justify = "RIGHT", width = COLUMNS.subtotal })
  hSubtotal:SetPoint("RIGHT", hSource, "LEFT", -10, 0)
  local hPrice = Widgets.Text(header, "tableHeader", "Unit price", { caps = true, justify = "RIGHT", width = COLUMNS.price })
  hPrice:SetPoint("RIGHT", hSubtotal, "LEFT", -10, 0)
  local hMissing = Widgets.Text(header, "tableHeader", "Missing", { caps = true, justify = "RIGHT", width = COLUMNS.missing })
  hMissing:SetPoint("RIGHT", hPrice, "LEFT", -10, 0)
  local hHave = Widgets.Text(header, "tableHeader", "Have", { caps = true, justify = "RIGHT", width = COLUMNS.have })
  hHave:SetPoint("RIGHT", hMissing, "LEFT", -10, 0)
  local hNeed = Widgets.Text(header, "tableHeader", "Need", { caps = true, justify = "RIGHT", width = COLUMNS.need })
  hNeed:SetPoint("RIGHT", hHave, "LEFT", -10, 0)
  local hMaterial = Widgets.Text(header, "tableHeader", "Material", { caps = true })
  hMaterial:SetPoint("LEFT", header, "LEFT", 48, 0)

  local footer = Widgets.Frame(body, nil, { bg = C.sidebar })
  footer:SetHeight(40)
  footer:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
  footer:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  local footerLine = Widgets.HLine(footer, C.black, 1)
  footerLine:SetPoint("TOPLEFT", footer, "TOPLEFT", 0, 0)
  footerLine:SetPoint("TOPRIGHT", footer, "TOPRIGHT", 0, 0)
  local buyLabel = Widgets.Text(footer, "secondary", "Buy all missing:")
  buyLabel:SetPoint("LEFT", footer, "LEFT", 12, 0)
  local buyValue = Widgets.Text(footer, "secondary", "no price data", { color = C.text3 })
  buyValue:SetPoint("LEFT", buyLabel, "RIGHT", 6, 0)
  local shopping = Widgets.Button(footer, "Add to shopping list", { onClick = function()
    if screen.goal and ns.chardb then
      ns.chardb.shopping = ns.chardb.shopping or { bought = {}, included = {} }
      ns.chardb.shopping.included = ns.chardb.shopping.included or {}
      ns.chardb.shopping.included[screen.goal.id] = true
      ns.UI.MainFrame.ShowScreen("shopping")
    end
  end })
  shopping:SetPoint("RIGHT", footer, "RIGHT", -10, 0)
  screen.shoppingButton = shopping
  local craftwise = Widgets.Button(footer, "Open CraftWise >", { primary = true, onClick = function()
    screen.tabs:Select("craftwise")
    screen.tab = "craftwise"
    screen:Refresh()
  end })
  craftwise:SetPoint("RIGHT", shopping, "LEFT", -8, 0)
  local routeText = Widgets.Text(footer, "secondary", "CraftWise: no price data", { color = C.text3, justify = "RIGHT" })
  routeText:SetPoint("RIGHT", craftwise, "LEFT", -14, 0)
  screen.craftwiseButton, screen.routeText, screen.buyValue = craftwise, routeText, buyValue

  local scroll = Widgets.ScrollArea(body)
  scroll:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
  scroll:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 1)
  screen.scroll = scroll
  screen.pool = Widgets.Pool(scroll.content, createMaterialRow)
  screen.tableMessage = Widgets.EmptyState(body, "", "")
  screen.tableMessage:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -40)
  screen.tableMessage:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -40)
  screen.tableMessage:SetHeight(120)
  screen.tableMessage:Hide()
  screen.table = table_

  local treeView = ns.UI.CraftingTree.Create(screen)
  treeView:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -8)
  treeView:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  treeView:Hide()
  screen.treeView = treeView
  local craftwiseView = ns.UI.CraftWiseView.Create(screen)
  craftwiseView:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -8)
  craftwiseView:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  craftwiseView:Hide()
  screen.craftwiseView = craftwiseView

  screen.empty = Widgets.EmptyState(screen, "No goal selected", "Add a crafting goal from My Goals or the search box, then pick it here.")
  screen.empty:SetPoint("TOPLEFT", screen, "TOPLEFT", 0, -120)
  screen.empty:SetPoint("TOPRIGHT", screen, "TOPRIGHT", 0, -120)
  screen.empty:SetHeight(100)

  local TAB_TEXT = {
    notes = { "Notes", "Per-goal notes arrive in a later version." },
  }

  local function sortMaterials(materials, key)
    local copy = {}
    for i, m in ipairs(materials) do copy[i] = m end
    if key == "name" then
      table.sort(copy, function(a, b) return ns.ItemProvider.GetName(a.itemID) < ns.ItemProvider.GetName(b.itemID) end)
    elseif key == "need" then
      table.sort(copy, function(a, b) return a.required > b.required end)
    else
      table.sort(copy, function(a, b)
        if a.missing ~= b.missing then return a.missing > b.missing end
        return a.required > b.required
      end)
    end
    return copy
  end

  local function sourceTags(material)
    local tags = {}
    if material.missing == 0 then
      tags[#tags + 1] = "In bags"
    end
    if material.ownedBank and material.ownedBank > 0 then
      tags[#tags + 1] = "Bank"
    end
    for _, candidate in ipairs(ns.ProfessionProvider.FindRecipesForItem(material.itemID)) do
      tags[#tags + 1] = candidate.learned and ("Craft - " .. (candidate.recipe.professionName or "?")) or "Recipe not learned"
      break
    end
    local alts = material.altSources or {}
    if alts[1] then
      tags[#tags + 1] = string.format("Alt: %s (%d)", alts[1].name, alts[1].count)
    end
    for _, hint in ipairs(ns.SourceProvider.Sources(material.itemID)) do
      if hint.kind == "vendor" then
        tags[#tags + 1] = "Vendor: " .. (hint.name or "?")
        break
      end
    end
    for _, hint in ipairs(ns.SourceProvider.Sources(material.itemID)) do
      if (hint.kind == "gather" or hint.kind == "drop" or hint.kind == "quest") and not hint.unavailable then
        tags[#tags + 1] = hint.gatherer and (hint.label .. " - " .. hint.gatherer) or hint.label
        break
      end
    end
    for _, crafter in ipairs(ns.CharacterProvider.CanCraft(material.itemID)) do
      tags[#tags + 1] = "Craft - Alt: " .. crafter.name
      break
    end
    if #tags == 0 then
      tags[1] = "Unknown source"
    end
    return tags
  end

  local function showChrome(visible)
    for _, widget in ipairs({ crumbs, hero, tabs, sort, alts, table_ }) do
      if visible then widget:Show() else widget:Hide() end
    end
    if visible then screen.empty:Hide() else screen.empty:Show() end
  end

  function screen:Refresh()
    local goal = ns.GoalService.GetSelected()
    self.goal = goal
    if not goal then
      showChrome(false)
      treeView:Hide()
      craftwiseView:Hide()
      self.empty:Set("No goal selected", "Add a crafting goal from My Goals or the search box, then pick it here.")
      return
    end
    local ELSEWHERE = { COMPLETE_ATTUNEMENT = { "Attunement goal", "Attunements" }, COMPLETE_QUEST = { "Quest goal", "Quests" }, REACH_REPUTATION = { "Reputation goal", "Reputations" } }
    if ELSEWHERE[goal.type] then
      showChrome(false)
      treeView:Hide()
      craftwiseView:Hide()
      self.empty:Set(ELSEWHERE[goal.type][1], string.format("%s is planned on the %s screen.", ns.GoalService.Name(goal), ELSEWHERE[goal.type][2]))
      return
    end
    showChrome(true)
    local view = ns.UI.MainFrame.views[goal.id] or ns.Planner.Evaluate(goal)
    self.view = view
    local item = view.item or {}
    local itemName = item.name or (goal.target.itemID and ("Item " .. goal.target.itemID)) or ns.GoalService.Name(goal)
    local learn, skill, enchant = view.learn, view.skill, view.enchant
    if skill then itemName = ns.GoalService.Name(goal) end
    crumbRest:SetText(string.format("  >  Crafting  >  %s%s|r", Theme.Hex.text, itemName))
    tracked:SetChecked(goal.tracked)
    alts:SetChecked(ns.db and ns.db.settings.includeAlts == true)

    hero.icon:SetItem(item.icon, item.quality)
    local quantity = (goal.target.itemID or enchant) and goal.target.quantity or 1
    hero.name:SetText(Theme.QualityText(itemName, item.quality) .. (quantity > 1 and (Theme.Hex.text2 .. "  x" .. quantity .. "|r") or ""))
    if enchant then
      local recipe = enchant.recipe
      hero.meta:SetText(string.format("%s enchant%s - %s", recipe.professionName or "Profession",
        enchant.need > 1 and (" - needs " .. enchant.need) or "",
        enchant.kind == "plans" and "taught by " .. ns.ItemProvider.GetName(enchant.teachItemID) or "taught by a trainer"))
    elseif learn then
      local recipe = learn.recipe
      hero.meta:SetText(string.format("%s recipe%s - %s", recipe.professionName or "Profession",
        learn.need > 1 and (" - needs " .. learn.need) or "",
        learn.kind == "plans" and "taught by " .. ns.ItemProvider.GetName(learn.teachItemID) or (learn.kind == "combine" and "item-use combine" or "taught by a trainer")))
    elseif skill then
      hero.meta:SetText(string.format("Profession skill - you are at %d%s", skill.current, skill.max > 0 and (", cap " .. skill.max) or ""))
    else
      hero.meta:SetText(describeItem(goal.target.itemID))
    end
    local chips = {}
    if enchant then
      if enchant.learned then
        chips[#chips + 1] = { "ok", "Known" }
      elseif enchant.blocked == "profession" then
        chips[#chips + 1] = { "missing", "No " .. (enchant.recipe.professionName or "profession") }
      elseif enchant.blocked == "skill" then
        chips[#chips + 1] = { "partial", string.format("Needs %s %d - you have %d", enchant.recipe.professionName or "skill", enchant.need, enchant.have or 0) }
      else
        chips[#chips + 1] = { "partial", "Not learned" }
      end
      if not enchant.learned then
        if enchant.kind == "plans" then
          chips[#chips + 1] = { "info", view.plan and view.plan.stepsMissing == 0 and "Formula in bags" or "Needs the formula" }
        else
          chips[#chips + 1] = { "info", enchant.trainer and enchant.trainer.name and ("Trainer: " .. enchant.trainer.name) or "Trainer (not recorded yet)" }
        end
      end
      chips[#chips + 1] = { enchant.remaining <= 0 and "ok" or "info", string.format("%d of %d cast%s", enchant.casts, enchant.quantity, enchant.quantity == 1 and "" or "s") }
      if not enchant.learned and #enchant.knownBy > 0 then chips[#chips + 1] = { "info", Util.Join(enchant.knownBy) .. " know" .. (#enchant.knownBy == 1 and "s" or "") .. " it" } end
    elseif learn then
      if learn.learned then
        chips[#chips + 1] = { "ok", "Learned" }
      elseif learn.blocked == "profession" then
        chips[#chips + 1] = { "missing", "No " .. (learn.recipe.professionName or "profession") }
      elseif learn.blocked == "skill" then
        chips[#chips + 1] = { "partial", string.format("Needs %s %d - you have %d", learn.recipe.professionName or "skill", learn.need, learn.have or 0) }
      else
        chips[#chips + 1] = { "ok", string.format("%s %d", learn.recipe.professionName or "Profession", learn.have or 0) }
      end
      if learn.kind == "plans" then
        chips[#chips + 1] = { "info", view.plan and view.plan.isComplete and "Plans in bags" or "Needs the plans" }
      elseif learn.kind == "trainer" then
        chips[#chips + 1] = { "info", learn.trainer and learn.trainer.name and ("Trainer: " .. learn.trainer.name) or "Trainer (not recorded yet)" }
      end
      if #learn.knownBy > 0 then chips[#chips + 1] = { "info", Util.Join(learn.knownBy) .. " know" .. (#learn.knownBy == 1 and "s" or "") .. " it" } end
    elseif skill then
      chips[#chips + 1] = { skill.reached and "ok" or "info", string.format("%s %d / %d", skill.professionName, skill.current, skill.target) }
      if skill.reached then
        chips[#chips + 1] = { "ok", "Reached" }
      elseif view.skillPlan then
        chips[#chips + 1] = { view.skillPlan.covered and "ok" or "partial", string.format("%d craft%s over %d recipe%s", view.skillPlan.total, view.skillPlan.total == 1 and "" or "s", #view.skillPlan.list, #view.skillPlan.list == 1 and "" or "s") }
        if not view.skillPlan.covered then chips[#chips + 1] = { "missing", string.format("No recipe for %d-%d", view.skillPlan.gaps[1].from, view.skillPlan.gaps[1].to) } end
      end
      if skill.capBlocked then chips[#chips + 1] = { "partial", "Cap " .. skill.max .. " - train the next rank" } end
    elseif view.recipe then
      local skill
      for _, p in ipairs(ns.ProfessionProvider.GetCharacterProfessions()) do
        if p.name == view.recipe.professionName then skill = p end
      end
      if skill then
        chips[#chips + 1] = { "ok", string.format("%s - you have %d", skill.name, skill.skillLevel or 0) }
      elseif view.recipe.professionName then
        chips[#chips + 1] = { "info", view.recipe.professionName }
      end
      if view.status == Status.RECIPE_NOT_LEARNED or view.recipeStatus == "unlearned" then
        local craft = view.tree and view.tree.root and view.tree.root.craft
        if craft and craft.combine then
          chips[#chips + 1] = { "ok", "Combine - anyone can" }
        elseif craft and craft.unavailable then
          chips[#chips + 1] = { "missing", "Recipe not learned - " .. craft.unavailable }
        elseif craft and craft.crafter and not craft.crafter.isCurrent then
          chips[#chips + 1] = { "partial", craft.crafter.name .. " can learn it" }
        else
          chips[#chips + 1] = { "partial", "Recipe not learned" }
        end
        if view.recipe.skill and view.recipe.skill.min > 1 then
          chips[#chips + 1] = { "info", string.format("Needs %s %d", view.recipe.professionName or "skill", view.recipe.skill.min) }
        end
      else
        chips[#chips + 1] = { "ok", "Recipe known" }
      end
      if (view.recipe.quantityMax or 1) > 1 or (view.recipe.quantityMin or 1) > 1 then
        local yield = view.recipe.quantityMin == view.recipe.quantityMax and tostring(view.recipe.quantityMin) or (view.recipe.quantityMin .. "-" .. view.recipe.quantityMax)
        chips[#chips + 1] = { "info", "Makes " .. yield .. " per craft" }
      end
    elseif view.obtain then
      chips[#chips + 1] = { "info", "Obtain" }
      if view.hint and view.hint.label then
        chips[#chips + 1] = { "info", view.hint.label }
      end
      if view.questline and view.questline.line then
        local line = view.questline.line
        chips[#chips + 1] = { line.complete and "ok" or "info", string.format("%s - %d of %d steps", line.attune.name, line.done, line.total) }
      end
      if goal.type == "CRAFT_ITEM" then
        chips[#chips + 1] = { "missing", "No known recipe" }
      end
    else
      chips[#chips + 1] = { "missing", ns.StatusLabel[view.status] or "Unknown" }
    end
    for i, chip in ipairs(hero.chips) do
      if chips[i] then
        chip:SetChip(chips[i][1], chips[i][2])
        chip:Show()
      else
        chip:Hide()
      end
    end
    if view.waypoint then hero.waypoint:Show() else hero.waypoint:Hide() end
    if not hero.stepper.box:HasFocus() then
      hero.stepper:SetValue(skill and goal.target.rank or goal.target.quantity or 1)
    end
    hero.stepper:SetEnabledState(skill ~= nil or enchant ~= nil or goal.target.itemID ~= nil)
    local percent = ns.Overview.Percent(view)
    hero.percent:SetText(percent and (percent .. "%") or "-")
    hero.bar:SetKind(percent == 100 and "ok" or "gold")
    hero.bar:SetValue((percent or 0) / 100)
    if skill then
      hero.reagents:SetText(skill.reached and view.message or string.format("%d of %d skill points - %d craft%s planned", math.max(0, skill.current - skill.start), math.max(0, skill.target - skill.start),
        view.plan and view.plan.craftsNeeded or 0, view.plan and view.plan.craftsNeeded == 1 and "" or "s"))
    elseif enchant and (enchant.remaining <= 0 or not view.progress) then
      hero.reagents:SetText(view.message or "")
    elseif enchant then
      hero.reagents:SetText(string.format("%d of %d reagents in your bags - %d cast%s to do", view.progress.ownedUnits, view.progress.requiredUnits, enchant.remaining, enchant.remaining == 1 and "" or "s"))
    elseif learn and view.plan and view.plan.step then
      hero.reagents:SetText(view.nextStep or view.message or "")
    elseif view.progress and view.plan.obtain then
      hero.reagents:SetText(string.format("%d of %d in your bags%s", view.progress.ownedUnits, view.progress.requiredUnits, view.sourceText and (" - " .. view.sourceText) or ""))
    elseif view.progress then
      hero.reagents:SetText(string.format("%d of %d reagents in your bags - %d craft%s needed", view.progress.ownedUnits, view.progress.requiredUnits, view.plan.craftsNeeded, view.plan.craftsNeeded == 1 and "" or "s"))
    else
      hero.reagents:SetText(view.message or "")
    end

    local sortKey = ns.chardb and ns.chardb.ui.materialSort or "missing"
    sort:SetLabel(sortLabel(sortKey))
    if self.tab == "tree" then
      table_:Hide()
      sort:Hide()
      alts:Hide()
      craftwiseView:Hide()
      treeView:Show()
      treeView:Render(view)
      return
    end
    treeView:Hide()
    if self.tab == "craftwise" then
      table_:Hide()
      sort:Hide()
      alts:Hide()
      craftwiseView:Show()
      craftwiseView:Render(view)
      return
    end
    craftwiseView:Hide()
    if self.tab ~= "requirements" then
      self.pool:HideFrom(1)
      scroll:SetContentHeight(1)
      local text = TAB_TEXT[self.tab] or TAB_TEXT.notes
      self.tableMessage:Set(text[1], text[2])
      self.tableMessage:Show()
      return
    end
    if not view.plan then
      self.pool:HideFrom(1)
      scroll:SetContentHeight(1)
      self.tableMessage:Set(ns.StatusLabel[view.status] or "Unavailable", view.message or "")
      self.tableMessage:Show()
      return
    end
    if #view.plan.materials == 0 and (learn or skill or enchant) then
      -- Nothing to gather: a trainer visit, a recipe already known, a skill reached.
      self.pool:HideFrom(1)
      scroll:SetContentHeight(1)
      self.tableMessage:Set(view.nextStep or "Nothing to gather", view.message or "")
      self.tableMessage:Show()
      buyValue:SetText("-")
      Widgets.SetTextColor(buyValue, C.text3)
      routeText:SetText("")
      return
    end
    self.tableMessage:Hide()
    local materials = sortMaterials(view.plan.materials, sortKey)
    local buyTotal, pricedRows, unpricedRows = 0, 0, 0
    for index, material in ipairs(materials) do
      local row = self.pool:Get(index)
      local info = ns.ItemProvider.GetItem(material.itemID)
      row.itemID = material.itemID
      row.material = material
      row.icon:SetItem(info.icon, info.quality)
      local label = info.name or ("Item " .. material.itemID)
      if not info.loaded and not info.name then label = label .. " (loading...)" end
      row.name:SetText(Theme.QualityText(label, info.quality))
      local noteParts = {}
      local sub = describeItem(material.itemID)
      if sub ~= "" then noteParts[#noteParts + 1] = (sub:match("^([^%-]+)") or sub):gsub("%s+$", "") end
      local craftable = ns.ProfessionProvider.FindRecipesForItem(material.itemID)
      if #craftable > 0 then noteParts[#noteParts + 1] = "craftable" end
      row.note:SetText(table.concat(noteParts, " - "))
      row.need:SetText(tostring(material.required))
      row.have:SetText(tostring(material.owned))
      Widgets.SetTextColor(row.have, Widgets.CountColor(material.owned, material.required))
      if material.missing > 0 then
        row.missing:SetText(tostring(material.missing))
        Widgets.SetTextColor(row.missing, C.missing)
        row.missing:Show()
        row.check:Hide()
      else
        row.missing:SetText("")
        row.check:Show()
      end
      local price = ns.PriceProvider.GetPrice(material.itemID)
      if price then
        row.price:SetText(Widgets.Money(price.copper, true))
        row.subtotal:SetText(material.missing > 0 and Widgets.Money(price.copper * material.missing, true) or Theme.ColorText("text3", "-"))
        if material.missing > 0 then buyTotal = buyTotal + price.copper * material.missing else buyTotal = buyTotal end
        pricedRows = pricedRows + 1
      else
        row.price:SetText(Theme.ColorText("text3", "?"))
        row.subtotal:SetText(Theme.ColorText("text3", material.missing > 0 and "?" or "-"))
        if material.missing > 0 then unpricedRows = unpricedRows + 1 end
      end
      row:SetTags(sourceTags(material))
      if material.missing > 0 and material.owned > 0 then
        Widgets.SetColor(row.tint, C.partial, 0.045)
      elseif material.missing > 0 then
        Widgets.SetColor(row.tint, C.missing, 0.07)
      else
        Widgets.SetColor(row.tint, C.black, 0)
      end
    end
    self.pool:HideFrom(#materials + 1)
    scroll:SetContentHeight(#materials * ROW)
    local compare = ns.CraftWise.Compare(view.fullTree or view.tree, { priceOf = ns.PriceProvider.GetPrice, marketOf = ns.PriceProvider.GetMarket })
    if compare and compare.hybrid.cost then
      routeText:SetText("CraftWise route: " .. Widgets.Money(compare.hybrid.cost, true) .. (compare.hybrid.unknown > 0 and Theme.ColorText("text3", string.format(" (+%d unpriced)", compare.hybrid.unknown)) or ""))
      Widgets.SetTextColor(routeText, C.text)
    elseif compare and compare.recommended == "buy" then
      routeText:SetText("CraftWise: buy the item - " .. Widgets.Money(compare.buy.cost, true))
      Widgets.SetTextColor(routeText, C.text)
    else
      routeText:SetText("CraftWise: no price data")
      Widgets.SetTextColor(routeText, C.text3)
    end
    screen.compare = compare
    if pricedRows > 0 then
      local gold = ns.CharacterProvider.AccountGold()
      local afford = ns.ShoppingList.Affordable(buyTotal, gold)
      local affordText = ""
      if afford == "now" then
        affordText = Theme.ColorText("ok", "  - affordable")
      elseif afford == "account" then
        affordText = Theme.ColorText("partial", string.format("  - short %s here, alts cover it", Widgets.Money(buyTotal - (gold.current or 0), true)))
      elseif afford == "no" then
        affordText = Theme.ColorText("missing", string.format("  - short %s", Widgets.Money(buyTotal - (gold.account or gold.current or 0), true)))
      end
      buyValue:SetText(Widgets.Money(buyTotal, true) .. affordText .. (unpricedRows > 0 and Theme.ColorText("text3", string.format("  (+%d unpriced)", unpricedRows)) or ""))
      Widgets.SetTextColor(buyValue, C.text)
    else
      buyValue:SetText("no price data")
      Widgets.SetTextColor(buyValue, C.text3)
    end
  end

  return screen
end

ns.UI.Screens.crafting = { label = "Crafting", Create = Create }
