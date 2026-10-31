-- Screen 02: crafting goal details with the requirements table.
local _, ns = ...

local Theme = ns.UI.Theme
local Widgets = ns.UI.Widgets
local C = Theme.Colors
local Readiness = ns.Readiness
local Util = ns.Util
local LearnKinds = ns.Planner.LearnKinds

ns.UI.Screens = ns.UI.Screens or {}

local ROW = 40
local COLUMNS = { need = 40, have = 40, missing = 54, price = 74, subtotal = 74, source = 180 }
local SORTS = { { key = "missing", label = "Sort: Missing" }, { key = "name", label = "Sort: Name" }, { key = "need", label = "Sort: Need" } }
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"

local function createMaterialRow(content, index)
  local row = Widgets.ListRow(content, { height = ROW, index = index, divider = 0.55 })
  local tint = Widgets.Texture(row, C.missing, 0, "BACKGROUND")
  tint:SetAllPoints(row)

  local icon = Widgets.ItemIcon(row, 28)
  icon:SetPoint("LEFT", row, "LEFT", 10, 0)
  local sourceFrame = CreateFrame("Frame", nil, row)
  sourceFrame:SetSize(COLUMNS.source, ROW)
  sourceFrame:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  sourceFrame.tags = {}
  Util.SafeCall(sourceFrame.SetClipsChildren, sourceFrame, true)
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
    Widgets.LayoutTags(sourceFrame, list)
  end

  Widgets.SetItemTooltip(row, function(self) return self.itemID end, function(self)
    local m = self.material
    if not m then return nil end
    local lines = { string.format("Per craft: %d", m.perCraft), string.format("Bags: %d", m.ownedBags or 0) }
    if m.ownedBank then
      lines[#lines + 1] = string.format("Bank: %d (%s)", m.ownedBank, m.bankSource == "live" and "live" or (m.bankSource == "cached" and "snapshot" or "client reported"))
    end
    for _, alt in ipairs(m.altSources or {}) do
      lines[#lines + 1] = string.format("%s has %d (%s%s)", alt.name, alt.count, alt.level, ns.GoalService.IncludesAlts() and ", counted" or ", not counted")
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
      lines[#lines + 1] = "Price: no data (record a vendor that sells it, or scan the Auction House with Auctionator)"
    end
    for _, hint in ipairs(ns.SourceProvider.WhereFrom(m.itemID)) do
      lines[#lines + 1] = (hint.label or "?") .. (hint.detail and (" - " .. hint.detail) or "")
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
    local chip = Widgets.Chip(body, "", "info")
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
    ns.UI.MainFrame.ReportFailure(ns.GoalService.SetAmount(screen.goal.id, value))
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
    ns.UI.MainFrame.SetAlert(message, ok and "ok" or "error")
  end })
  waypoint:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 16, 10)
  waypoint:Hide()
  hero.waypoint = waypoint

  hero.icon, hero.name, hero.meta, hero.percent, hero.bar, hero.reagents, hero.stepper = icon, name, meta, percent, bar, reagents, stepper
  return hero
end

local BIND_LABELS = { [1] = "Binds when picked up", [2] = "Binds when equipped", [3] = "Binds when used", [4] = "Quest item" }

local function describeItem(itemID)
  local _, _, _, itemLevel, _, itemType, itemSubType, _, _, _, _, _, _, bindType = Util.SafeCall(ns.Compat.GetItemInfo, itemID)
  local parts = {}
  if itemSubType and itemSubType ~= "" then parts[#parts + 1] = itemSubType elseif itemType then parts[#parts + 1] = itemType end
  if itemLevel and itemLevel > 1 then parts[#parts + 1] = "Item level " .. itemLevel end
  if bindType and BIND_LABELS[bindType] then parts[#parts + 1] = BIND_LABELS[bindType] end
  return table.concat(parts, " - ")
end

-- Requirements table columns after Material, laid out right to left from
-- the header's right edge: { label, width, justify }.
local HEADER_COLUMNS = {
  { "Source", COLUMNS.source },
  { "Subtotal", COLUMNS.subtotal, "RIGHT" },
  { "Unit price", COLUMNS.price, "RIGHT" },
  { "Missing", COLUMNS.missing, "RIGHT" },
  { "Have", COLUMNS.have, "RIGHT" },
  { "Need", COLUMNS.need, "RIGHT" },
}

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

-- "Tailoring recipe - needs 75 - taught by a trainer" and the like.
local function heroMeta(goal, view)
  local learn, skill, enchant = view.learn, view.skill, view.enchant
  if enchant then
    return string.format("%s enchant%s - %s", enchant.recipe.professionName or "Profession",
      enchant.need > 1 and (" - needs " .. enchant.need) or "",
      enchant.kind == LearnKinds.PLANS and "taught by " .. ns.ItemProvider.GetName(enchant.teachItemID) or "taught by a trainer")
  elseif learn then
    return string.format("%s recipe%s - %s", learn.recipe.professionName or "Profession",
      learn.need > 1 and (" - needs " .. learn.need) or "",
      learn.kind == LearnKinds.PLANS and "taught by " .. ns.ItemProvider.GetName(learn.teachItemID) or (learn.kind == LearnKinds.COMBINE and "item-use combine" or "taught by a trainer"))
  elseif skill then
    return string.format("Profession skill - you are at %d%s", skill.current, skill.max > 0 and (", cap " .. skill.max) or "")
  end
  return describeItem(goal.target.itemID)
end

local function knownByChip(knownBy)
  return { Util.Join(knownBy) .. " know" .. (#knownBy == 1 and "s" or "") .. " it", "info" }
end

local function enchantChips(view, chips)
  local enchant = view.enchant
  if enchant.learned then
    chips[#chips + 1] = { "Known", "ok" }
  elseif enchant.blocked == "profession" then
    chips[#chips + 1] = { "No " .. (enchant.recipe.professionName or "profession"), "missing" }
  elseif enchant.blocked == "skill" then
    chips[#chips + 1] = { string.format("Needs %s %d - you have %d", enchant.recipe.professionName or "skill", enchant.need, enchant.have or 0), "partial" }
  else
    chips[#chips + 1] = { "Not learned", "partial" }
  end
  if not enchant.learned then
    if enchant.kind == LearnKinds.PLANS then
      chips[#chips + 1] = { view.plan and view.plan.stepsMissing == 0 and "Formula in bags" or "Needs the formula", "info" }
    else
      chips[#chips + 1] = { enchant.trainer and enchant.trainer.name and ("Trainer: " .. enchant.trainer.name) or "Trainer (not recorded yet)", "info" }
    end
  end
  chips[#chips + 1] = { string.format("%d of %d cast%s", enchant.casts, enchant.quantity, enchant.quantity == 1 and "" or "s"), enchant.remaining <= 0 and "ok" or "info" }
  if not enchant.learned and #enchant.knownBy > 0 then chips[#chips + 1] = knownByChip(enchant.knownBy) end
end

local function learnChips(view, chips)
  local learn = view.learn
  if learn.learned then
    chips[#chips + 1] = { "Learned", "ok" }
  elseif learn.blocked == "profession" then
    chips[#chips + 1] = { "No " .. (learn.recipe.professionName or "profession"), "missing" }
  elseif learn.blocked == "skill" then
    chips[#chips + 1] = { string.format("Needs %s %d - you have %d", learn.recipe.professionName or "skill", learn.need, learn.have or 0), "partial" }
  else
    chips[#chips + 1] = { string.format("%s %d", learn.recipe.professionName or "Profession", learn.have or 0), "ok" }
  end
  if learn.kind == LearnKinds.PLANS then
    chips[#chips + 1] = { view.plan and view.plan.isComplete and "Plans in bags" or "Needs the plans", "info" }
  elseif learn.kind == LearnKinds.TRAINER then
    chips[#chips + 1] = { learn.trainer and learn.trainer.name and ("Trainer: " .. learn.trainer.name) or "Trainer (not recorded yet)", "info" }
  end
  if #learn.knownBy > 0 then chips[#chips + 1] = knownByChip(learn.knownBy) end
end

local function skillChips(view, chips)
  local skill = view.skill
  chips[#chips + 1] = { string.format("%s %d / %d", skill.professionName, skill.current, skill.target), skill.reached and "ok" or "info" }
  if skill.reached then
    chips[#chips + 1] = { "Reached", "ok" }
  elseif view.skillPlan then
    local plan = view.skillPlan
    chips[#chips + 1] = { string.format("%d craft%s over %d recipe%s", plan.total, plan.total == 1 and "" or "s", #plan.list, #plan.list == 1 and "" or "s"), plan.covered and "ok" or "partial" }
    if not plan.covered then chips[#chips + 1] = { string.format("No recipe for %d-%d", plan.gaps[1].from, plan.gaps[1].to), "missing" } end
  end
  if skill.capBlocked then chips[#chips + 1] = { "Cap " .. skill.max .. " - train the next rank", "partial" } end
end

local function recipeChips(view, chips)
  local recipe = view.recipe
  local standing
  for _, p in ipairs(ns.ProfessionProvider.GetCharacterProfessions()) do
    if p.name == recipe.professionName then standing = p end
  end
  if standing then
    chips[#chips + 1] = { string.format("%s - you have %d", standing.name, standing.skillLevel or 0), "ok" }
  elseif recipe.professionName then
    chips[#chips + 1] = { recipe.professionName, "info" }
  end
  if view.recipeStatus == "unlearned" then
    local craft = view.tree and view.tree.root and view.tree.root.craft
    if craft and craft.combine then
      chips[#chips + 1] = { "Combine - anyone can", "ok" }
    elseif craft and craft.unavailable then
      chips[#chips + 1] = { "Recipe not learned - " .. craft.unavailable, "missing" }
    elseif craft and craft.crafter and not craft.crafter.isCurrent then
      chips[#chips + 1] = { craft.crafter.name .. " can learn it", "partial" }
    else
      chips[#chips + 1] = { "Recipe not learned", "partial" }
    end
    if recipe.skill and recipe.skill.min > 1 then
      chips[#chips + 1] = { string.format("Needs %s %d", recipe.professionName or "skill", recipe.skill.min), "info" }
    end
  else
    chips[#chips + 1] = { "Recipe known", "ok" }
  end
  if (recipe.quantityMax or 1) > 1 or (recipe.quantityMin or 1) > 1 then
    local yield = recipe.quantityMin == recipe.quantityMax and tostring(recipe.quantityMin) or (recipe.quantityMin .. "-" .. recipe.quantityMax)
    chips[#chips + 1] = { "Makes " .. yield .. " per craft", "info" }
  end
end

local function obtainChips(goal, view, chips)
  chips[#chips + 1] = { "Obtain", "info" }
  if view.hint and view.hint.label then
    chips[#chips + 1] = { view.hint.label, "info" }
  end
  if view.questline and view.questline.line then
    local line = view.questline.line
    chips[#chips + 1] = { string.format("%s - %d of %d steps", line.attune.name, line.done, line.total), line.complete and "ok" or "info" }
  end
  if goal.type == ns.GoalModel.TypeIDs.CRAFT_ITEM then
    chips[#chips + 1] = { "No known recipe", "missing" }
  end
end

-- The hero's status chips: { { text, kind } }.
local function heroChips(goal, view)
  local chips = {}
  if view.enchant then
    enchantChips(view, chips)
  elseif view.learn then
    learnChips(view, chips)
  elseif view.skill then
    skillChips(view, chips)
  elseif view.recipe then
    recipeChips(view, chips)
  elseif view.obtain then
    obtainChips(goal, view, chips)
  else
    chips[#chips + 1] = { ns.Readiness.Label(view.readiness) or "Unknown", "missing" }
  end
  return chips
end

-- The line under the progress bar: what is in the bags and what is left.
local function heroProgressText(view)
  local learn, skill, enchant = view.learn, view.skill, view.enchant
  if skill then
    if skill.reached and view.message then return view.message end
    return string.format("%d of %d skill points - %d craft%s planned", math.max(0, skill.current - skill.start), math.max(0, skill.target - skill.start),
      view.plan and view.plan.craftsNeeded or 0, view.plan and view.plan.craftsNeeded == 1 and "" or "s")
  elseif enchant and (enchant.remaining <= 0 or not view.progress) then
    return view.message or ""
  elseif enchant then
    return string.format("%d of %d reagents in your bags - %d cast%s to do", view.progress.ownedUnits, view.progress.requiredUnits, enchant.remaining, enchant.remaining == 1 and "" or "s")
  elseif learn and view.plan and view.plan.step then
    return view.nextStep or view.message or ""
  elseif view.progress and view.plan.obtain then
    return string.format("%d of %d in your bags%s", view.progress.ownedUnits, view.progress.requiredUnits, view.sourceText and (" - " .. view.sourceText) or "")
  elseif view.progress then
    return string.format("%d of %d reagents in your bags - %d craft%s needed", view.progress.ownedUnits, view.progress.requiredUnits, view.plan.craftsNeeded, view.plan.craftsNeeded == 1 and "" or "s")
  end
  return view.message or ""
end

local function renderHero(screen, goal, view, itemName)
  local hero = screen.hero
  local item = view.item or {}
  hero.icon:SetItem(item.icon, item.quality)
  local quantity = ns.GoalModel.ShownQuantity(goal)
  hero.name:SetText(Theme.QualityText(itemName, item.quality) .. (quantity > 1 and (Theme.Hex.text2 .. "  x" .. quantity .. "|r") or ""))
  hero.meta:SetText(heroMeta(goal, view))
  local chips = heroChips(goal, view)
  for i, chip in ipairs(hero.chips) do
    if chips[i] then
      chip:SetChip(chips[i][1], chips[i][2])
      chip:Show()
    else
      chip:Hide()
    end
  end
  if view.waypoint then hero.waypoint:Show() else hero.waypoint:Hide() end
  local amount, value = ns.GoalModel.Amount(goal)
  if not hero.stepper.box:HasFocus() then
    hero.stepper:SetValue(value or 1)
  end
  hero.stepper:SetEnabledState(amount ~= nil)
  local percent = ns.Overview.Percent(view)
  hero.percent:SetText(percent and (percent .. "%") or "-")
  hero.bar:SetKind(percent == 100 and "ok" or "gold")
  hero.bar:SetValue((percent or 0) / 100)
  hero.reagents:SetText(heroProgressText(view))
end

-- Fills the material rows. Returns buyTotal, pricedRows, unpricedRows.
local function renderMaterials(screen, materials)
  local prices = ns.GoalService.PriceMaterials(materials)
  for index, material in ipairs(materials) do
    local row = screen.pool:Get(index)
    local info = ns.ItemProvider.GetItem(material.itemID)
    row.itemID = material.itemID
    row.material = material
    row.icon:SetItem(info.icon, info.quality)
    local label = info.name or ("Item " .. material.itemID)
    if not info.loaded and not info.name then label = label .. " (loading...)" end
    row.name:SetText(Theme.QualityText(label, info.quality))
    local noteParts = {}
    local sub = describeItem(material.itemID)
    if sub ~= "" then noteParts[#noteParts + 1] = (sub:match("^(.-)%s+%-%s") or sub) end
    if #ns.ProfessionProvider.FindRecipesForItem(material.itemID) > 0 then noteParts[#noteParts + 1] = "craftable" end
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
    local price = prices.byItem[material.itemID]
    if price then
      row.price:SetText(Widgets.Money(price.copper, true))
      row.subtotal:SetText(material.missing > 0 and Widgets.Money(price.copper * material.missing, true) or Theme.ColorText("text3", "-"))
    else
      row.price:SetText(Theme.ColorText("text3", "?"))
      row.subtotal:SetText(Theme.ColorText("text3", material.missing > 0 and "?" or "-"))
    end
    row:SetTags(ns.SourceProvider.MaterialTags(material))
    if material.missing > 0 and material.owned > 0 then
      Widgets.SetColor(row.tint, C.partial, 0.045)
    elseif material.missing > 0 then
      Widgets.SetColor(row.tint, C.missing, 0.07)
    else
      Widgets.SetColor(row.tint, C.black, 0)
    end
  end
  screen.pool:HideFrom(#materials + 1)
  screen.scroll:SetContentHeight(#materials * ROW)
  return prices.buyTotal, prices.priced, prices.unpriced
end

-- The footer: CraftWise's route and the cost of buying what is missing.
local function renderFooter(screen, view, buyTotal, pricedRows, unpricedRows)
  local routeText, buyValue = screen.routeText, screen.buyValue
  local compare = view.craftwise
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
  if pricedRows == 0 then
    buyValue:SetText("no price data")
    Widgets.SetTextColor(buyValue, C.text3)
    return
  end
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
end

-- An empty requirements table with a message in its place.
local function showTableMessage(screen, title, text)
  screen.pool:HideFrom(1)
  screen.scroll:SetContentHeight(1)
  screen.tableMessage:Set(title, text)
  screen.tableMessage:Show()
end

-- The Requirements tab (and the Notes placeholder).
local function renderRequirements(screen, view, sortKey)
  if screen.tab ~= "requirements" then
    local text = TAB_TEXT[screen.tab] or TAB_TEXT.notes
    showTableMessage(screen, text[1], text[2])
    return
  end
  if not view.plan then
    showTableMessage(screen, ns.Readiness.Label(view.readiness) or "Unavailable", view.message or "")
    return
  end
  if #view.plan.materials == 0 and (view.learn or view.skill or view.enchant) then
    -- Nothing to gather: a trainer visit, a recipe already known, a skill reached.
    showTableMessage(screen, view.nextStep or "Nothing to gather", view.message or "")
    screen.buyValue:SetText("-")
    Widgets.SetTextColor(screen.buyValue, C.text3)
    screen.routeText:SetText("")
    return
  end
  screen.tableMessage:Hide()
  local buyTotal, pricedRows, unpricedRows = renderMaterials(screen, sortMaterials(view.plan.materials, sortKey))
  renderFooter(screen, view, buyTotal, pricedRows, unpricedRows)
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
      ns.UI.MainFrame.ReportFailure(ns.GoalService.Remove(screen.goal.id))
      ns.UI.MainFrame.SetAlert("Goal removed.", "info")
    end
  end })
  remove:SetPoint("RIGHT", crumbs, "RIGHT", 0, 0)
  local tracked = Widgets.Checkbox(crumbs, "Show in tracker", function(checked)
    if screen.goal then ns.UI.MainFrame.ReportFailure(ns.GoalService.SetTracked(screen.goal.id, checked)) end
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

  -- Shows a tab ("requirements", "tree", "craftwise", ...); also what
  -- MainFrame.ShowScreen("crafting", nil, tab) calls.
  function screen:Focus(tab)
    self.tabs:Select(tab)
    self.tab = tab
    self:Refresh()
  end
  local sort = Widgets.Dropdown(screen, Widgets.SortLabel(SORTS, "missing"), 150, function(self)
    local current = ns.chardb.ui.materialSort
    local items = {}
    for _, s in ipairs(SORTS) do items[#items + 1] = { text = s.label:gsub("Sort: ", ""), value = s.key, selected = s.key == current } end
    Widgets.Menu(self, items, function(value)
      ns.chardb.ui.materialSort = value
      screen:Refresh()
    end)
  end)
  sort:SetPoint("BOTTOMRIGHT", hero, "BOTTOMRIGHT", 0, -36)
  local alts = Widgets.Checkbox(screen, "Include alts' bags", function(checked)
    local message, reason = ns.GoalService.SetIncludeAlts(checked)
    ns.UI.MainFrame.SetAlert(message or reason, message and "info" or "error")
  end)
  alts:SetPoint("RIGHT", sort, "LEFT", -14, 0)
  Widgets.SetTooltip(alts, "Include alts' bags", { "Counts the snapshotted bags and bank of your other characters as owned.", "Snapshots are taken whenever you log in or out on a character." })
  screen.sort, screen.alts = sort, alts

  local table_ = Widgets.Panel(screen, nil, { pad = 0 })
  table_:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -1)
  table_:SetPoint("BOTTOMRIGHT", screen, "BOTTOMRIGHT", 0, 0)
  local body = table_.body
  local header = Widgets.TableHeader(body, HEADER_COLUMNS, { "Material", 48 })

  local footer = Widgets.TableFooter(body, 40)
  local buyLabel = Widgets.Text(footer, "secondary", "Buy all missing:")
  buyLabel:SetPoint("LEFT", footer, "LEFT", 12, 0)
  local buyValue = Widgets.Text(footer, "secondary", "no price data", { color = C.text3 })
  buyValue:SetPoint("LEFT", buyLabel, "RIGHT", 6, 0)
  local shopping = Widgets.Button(footer, "Add to shopping list", { onClick = function()
    if screen.goal and ns.GoalService.SetInShopping(screen.goal.id, true) then
      ns.UI.MainFrame.ShowScreen("shopping")
    end
  end })
  shopping:SetPoint("RIGHT", footer, "RIGHT", -10, 0)
  screen.shoppingButton = shopping
  local craftwise = Widgets.Button(footer, "Open CraftWise >", { primary = true, onClick = function()
    screen:Focus("craftwise")
  end })
  craftwise:SetPoint("RIGHT", shopping, "LEFT", -8, 0)
  local routeText = Widgets.Text(footer, "secondary", "CraftWise: no price data", { color = C.text3, justify = "RIGHT" })
  routeText:SetPoint("RIGHT", craftwise, "LEFT", -14, 0)
  screen.craftwiseButton, screen.routeText, screen.buyValue = craftwise, routeText, buyValue

  local scroll = Widgets.TableScroll(body, header, footer)
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

  local chrome = { crumbs, hero, tabs, sort, alts, table_ }

  -- Hides everything but the empty state, which says why.
  function screen:ShowEmpty(title, text)
    for _, widget in ipairs(chrome) do widget:Hide() end
    treeView:Hide()
    craftwiseView:Hide()
    self.empty:Set(title, text)
    self.empty:Show()
  end

  function screen:Refresh()
    local goal = ns.GoalService.Selected()
    self.goal = goal
    if not goal then
      self:ShowEmpty("No goal selected", "Add a crafting goal from My Goals or the search box, then pick it here.")
      return
    end
    -- Goal types planned on their own screen (GoalModel.Types[type].screen).
    local def = ns.GoalModel.Types[goal.type]
    if def and def.screen then
      self:ShowEmpty(def.badge .. " goal", string.format("%s is planned on the %s screen.", ns.GoalService.Name(goal), ns.UI.Screens[def.screen].label))
      return
    end
    for _, widget in ipairs(chrome) do widget:Show() end
    self.empty:Hide()
    local view = ns.GoalService.View(goal.id)
    self.view = view
    local item = view.item or {}
    local itemName = item.name or (goal.target.itemID and ("Item " .. goal.target.itemID)) or ns.GoalService.Name(goal)
    if view.skill then itemName = ns.GoalService.Name(goal) end
    crumbRest:SetText(string.format("  >  Crafting  >  %s%s|r", Theme.Hex.text, itemName))
    tracked:SetChecked(goal.tracked)
    alts:SetChecked(ns.GoalService.IncludesAlts())
    renderHero(self, goal, view, itemName)

    local sortKey = ns.chardb.ui.materialSort
    sort:SetLabel(Widgets.SortLabel(SORTS, sortKey))
    local onTable = self.tab ~= "tree" and self.tab ~= "craftwise"
    for _, widget in ipairs({ table_, sort, alts }) do
      if onTable then widget:Show() else widget:Hide() end
    end
    if self.tab == "tree" then treeView:Show() treeView:Render(view) else treeView:Hide() end
    if self.tab == "craftwise" then craftwiseView:Show() craftwiseView:Render(view) else craftwiseView:Hide() end
    if onTable then renderRequirements(self, view, sortKey) end
  end

  return screen
end

ns.UI.Screens.crafting = { label = "Crafting", Create = Create }
