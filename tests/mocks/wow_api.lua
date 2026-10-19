-- Mock of the subset of the WoW: Forever API ForeverPath uses.
--
-- The mock mirrors what was verified against the Forever client (build
-- 1.60.1.70450, interface 16001): modern C_* namespaces exist, the legacy
-- globals (GetItemInfo, GetItemCount, GetContainerItemInfo, GetTradeSkillInfo)
-- do not, and registering an unknown event throws.
local Mock = {}

local unpack = unpack or table.unpack

local function deepcopy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for k, v in pairs(value) do copy[deepcopy(k)] = deepcopy(v) end
  return copy
end
Mock.deepcopy = deepcopy

local function contains(list, value)
  for _, v in ipairs(list or {}) do
    if v == value then return true end
  end
  return false
end

Mock.knownEvents = {}
for _, event in ipairs({
  "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT",
  "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
  "BAG_UPDATE", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
  "PLAYERBANKSLOTS_CHANGED", "BANK_TABS_CHANGED",
  "TRADE_SKILL_LIST_UPDATE", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
  "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED",
  "TRAINER_SHOW", "TRAINER_UPDATE", "TRAINER_CLOSED",
  "TRADE_SKILL_DATA_SOURCE_CHANGED", "TRADE_SKILL_DATA_SOURCE_CHANGING",
  "NEW_RECIPE_LEARNED", "SKILL_LINES_CHANGED",
  "ITEM_DATA_LOAD_RESULT", "GET_ITEM_INFO_RECEIVED",
  "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "PLAYER_LEVEL_UP",
  "QUEST_REMOVED", "QUEST_DATA_LOAD_RESULT",
  "PLAYER_EQUIPMENT_CHANGED", "UNIT_INVENTORY_CHANGED", "UPDATE_FACTION",
  "UNIT_SPELLCAST_SUCCEEDED",
  "QUEST_DETAIL", "QUEST_COMPLETE", "QUEST_FINISHED",
}) do
  Mock.knownEvents[event] = true
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local Widget = {}
local WidgetMeta = {
  __index = function(self, key)
    local method = Widget[key]
    if method ~= nil then
      return method
    end
    -- Unknown PascalCase members behave like no-op widget methods; lowercase
    -- keys are plain data fields and stay nil.
    if type(key) == "string" and key:match("^%u") then
      return function() return nil end
    end
    return nil
  end,
}

local function newWidget(frameType, name, parent, template)
  local widget = setmetatable({
    frameType = frameType, name = name, parent = parent, template = template,
    shown = true, width = 0, height = 0, points = {}, scripts = {}, events = {},
    text = "", children = {}, enabled = true,
  }, WidgetMeta)
  if name then
    _G[name] = widget
  end
  if type(parent) == "table" and parent.children then
    table.insert(parent.children, widget)
  end
  table.insert(Mock.frames, widget)
  return widget
end

function Widget:SetSize(w, h) self.width, self.height = w, h end
function Widget:SetWidth(w) self.width = w end
function Widget:SetHeight(h) self.height = h end
function Widget:GetWidth() return self.width end
function Widget:GetHeight() return self.height end
function Widget:GetSize() return self.width, self.height end
function Widget:SetPoint(point, a, b, c, d)
  local relativeTo, relativePoint, x, y
  if type(a) == "number" then
    relativeTo, relativePoint, x, y = self.parent, point, a, b
  else
    relativeTo = a
    if type(b) == "string" then
      relativePoint, x, y = b, c, d
    else
      relativePoint, x, y = point, b, c
    end
  end
  table.insert(self.points, { point, relativeTo, relativePoint, x or 0, y or 0 })
end
function Widget:GetPoint(index)
  local p = self.points[index or 1]
  if not p then return nil end
  return p[1], p[2], p[3], p[4], p[5]
end
function Widget:GetNumPoints() return #self.points end
function Widget:ClearAllPoints() self.points = {} end
function Widget:Show()
  local was = self.shown
  self.shown = true
  if not was then self:Fire("OnShow") end
end
function Widget:Hide()
  local was = self.shown
  self.shown = false
  if was then self:Fire("OnHide") end
end
function Widget:IsShown() return self.shown end
function Widget:IsVisible()
  if not self.shown then return false end
  if type(self.parent) == "table" and self.parent.IsVisible then
    return self.parent:IsVisible()
  end
  return true
end
function Widget:SetScript(handler, fn) self.scripts[handler] = fn end
function Widget:GetScript(handler) return self.scripts[handler] end
function Widget:HasScript() return true end
function Widget:HookScript(handler, fn)
  local previous = self.scripts[handler]
  self.scripts[handler] = function(...)
    if previous then previous(...) end
    fn(...)
  end
end
function Widget:Fire(handler, ...)
  local fn = self.scripts[handler]
  if fn then return fn(self, ...) end
end
function Widget:RegisterEvent(event)
  if Mock.strictEvents and not Mock.knownEvents[event] then
    error("Unknown event: " .. tostring(event))
  end
  self.events[event] = true
end
function Widget:UnregisterEvent(event) self.events[event] = nil end
function Widget:IsEventRegistered(event) return self.events[event] == true end
function Widget:CreateFontString(name, _, template) return newWidget("FontString", name, self, template) end
function Widget:CreateTexture(name, layer)
  local texture = newWidget("Texture", name, self)
  texture.layer = layer or "ARTWORK"
  return texture
end
function Widget:SetText(text)
  self.text = text ~= nil and tostring(text) or ""
  self:Fire("OnTextChanged", true)
end
function Widget:GetText() return self.text end
function Widget:GetStringWidth() return #(self.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6 end
function Widget:SetAlpha(alpha) self.alpha = alpha end
function Widget:GetAlpha() return self.alpha or 1 end
function Widget:SetFrameLevel(level) self.frameLevel = level end
function Widget:GetFrameLevel() return self.frameLevel or 1 end
function Widget:SetVerticalScroll(offset) self.verticalScroll = offset end
function Widget:GetVerticalScroll() return self.verticalScroll or 0 end
function Widget:SetBackdrop(backdrop) self.backdrop = backdrop end
function Widget:SetBackdropColor(r, g, b, a) self.backdropColor = { r, g, b, a } end
function Widget:SetBackdropBorderColor(r, g, b, a) self.backdropBorderColor = { r, g, b, a } end
function Widget:SetColorTexture(r, g, b, a) self.color = { r, g, b, a } end
function Widget:GetNumber() return tonumber(self.text) or 0 end
function Widget:SetFocus() Mock.focus = self; self:Fire("OnEditFocusGained") end
function Widget:ClearFocus()
  -- Like the client, OnEditFocusLost only fires when the box had focus.
  if Mock.focus == self then
    Mock.focus = nil
    self:Fire("OnEditFocusLost")
  end
end
function Widget:HasFocus() return Mock.focus == self end
function Widget:GetParent() return self.parent end
function Widget:SetParent(parent) self.parent = parent end
function Widget:GetName() return self.name end
function Widget:Enable() self.enabled = true end
function Widget:Disable() self.enabled = false end
function Widget:IsEnabled() return self.enabled end
function Widget:SetScrollChild(child) self.scrollChild = child end
function Widget:GetScrollChild() return self.scrollChild end
function Widget:Click()
  if self.enabled then self:Fire("OnClick", "LeftButton") end
end
function Widget:SetTexture(texture) self.texture = texture end
function Widget:GetTexture() return self.texture end
function Widget:SetTextColor(r, g, b) self.color = { r, g, b } end
function Widget:GetTextColor() return unpack(self.color or { 1, 1, 1 }) end
function Widget:LockHighlight() self.highlightLocked = true end
function Widget:UnlockHighlight() self.highlightLocked = false end
function Widget:IsObjectType(frameType) return self.frameType == frameType end
function Widget:GetObjectType() return self.frameType end
function Widget:GetChildren() return unpack(self.children) end

Mock.newWidget = newWidget

---------------------------------------------------------------------------
-- State helpers
---------------------------------------------------------------------------
function Mock.FireEvent(event, ...)
  local frames = {}
  for _, frame in ipairs(Mock.frames) do
    if frame.events[event] then frames[#frames + 1] = frame end
  end
  for _, frame in ipairs(frames) do
    frame:Fire("OnEvent", event, ...)
  end
end

-- Runs pending C_Timer callbacks (delays are ignored; order is preserved).
function Mock.RunTimers(limit)
  local runs = 0
  while #Mock.timers > 0 and runs < (limit or 1000) do
    local timer = table.remove(Mock.timers, 1)
    runs = runs + 1
    timer.fn()
  end
  return runs
end

function Mock.ItemLink(itemID)
  local item = Mock.items[itemID]
  local name = item and item.name or ("Item " .. itemID)
  return string.format("|cffffffff|Hitem:%d::::::::60:::::|h[%s]|h|r", itemID, name)
end

function Mock.AddItem(itemID, opts)
  opts = opts or {}
  Mock.items[itemID] = {
    name = opts.name or ("Item " .. itemID),
    quality = opts.quality or 1,
    icon = opts.icon or (100000 + itemID),
    loaded = opts.loaded ~= false,
    sellPrice = opts.sellPrice or 0,
    classID = opts.classID,
    subclassID = opts.subclassID,
    itemType = opts.itemType,
    itemSubType = opts.itemSubType,
    equipLoc = opts.equipLoc,
    ilvl = opts.ilvl,
    stats = opts.stats,
    bind = opts.bind,
  }
  return itemID
end

-- Reputation standings. list = { { name, factionID, value, isHeader, hasRep } } in client order;
-- headers without factionID group what follows.
local STANDING_MIN = { [1] = -42000, [2] = -6000, [3] = -3000, [4] = 0, [5] = 3000, [6] = 9000, [7] = 21000, [8] = 42000 }
local STANDING_MAX = { [1] = -6000, [2] = -3000, [3] = 0, [4] = 3000, [5] = 9000, [6] = 21000, [7] = 42000, [8] = 42999 }
local function standingFor(value)
  local standing = 1
  for s = 1, 8 do if value >= STANDING_MIN[s] then standing = s end end
  return standing
end
local function factionData(entry)
  if not entry then return nil end
  if entry.isHeader and not entry.hasRep then
    return { name = entry.name, isHeader = true, isHeaderWithRep = false, isCollapsed = false }
  end
  local value = entry.value or 0
  local standing = standingFor(value)
  return { name = entry.name, factionID = entry.factionID, reaction = standing, currentStanding = value,
    currentReactionThreshold = STANDING_MIN[standing], nextReactionThreshold = STANDING_MAX[standing],
    isHeader = entry.isHeader == true, isHeaderWithRep = entry.isHeader == true and entry.hasRep == true, isCollapsed = false, atWarWith = entry.atWar == true, isWatched = false }
end
function Mock.SetFactions(list)
  Mock.factions = list
end
function Mock.SetReputation(factionID, value)
  for _, entry in ipairs(Mock.factions) do
    if entry.factionID == factionID then entry.value = value end
  end
  Mock.FireEvent("UPDATE_FACTION")
end

-- Equips an item (slotID = inventory slot) and fires the equipment events.
function Mock.Equip(slotID, itemID)
  Mock.equipment[slotID] = itemID
  Mock.FireEvent("PLAYER_EQUIPMENT_CHANGED", slotID, itemID ~= nil)
  Mock.FireEvent("UNIT_INVENTORY_CHANGED", "player")
end

-- A minimal GearQuest Forever: data = { entries = { { itemId, slot, minLevel, maxLevel, curatedRank, pipelineScore, classes, specs, factions, sourceType, instructions, zone, npc, questName } },
-- facts = { [itemID] = { name, quality, ilvl, reqLevel, sourceType, instructions, zone, npc, questName } }, scoredStats = { [itemID] = { armor=, str= } }, spec = "arms", specLabel = "Arms" }
function Mock.InstallGearQuest(data)
  data = data or {}
  local GQ = { Data = { entries = data.entries or {}, warriorItemFacts = data.facts or {}, scoredStats = data.scoredStats or {} }, Spec = {} }
  GQ.Data.loadCalls = 0
  function GQ.Data:EnsureClassLoaded(classFile)
    self.loadCalls = self.loadCalls + 1
    return data.loadFails ~= true
  end
  function GQ.Data:GetItemDisplayName(itemID)
    local facts = self.warriorItemFacts[itemID]
    return facts and facts.name or nil
  end
  function GQ.Spec:GetDisplaySpec(classFile) return data.spec or "arms" end
  function GQ.Spec:GetSpecLabel(specId, classFile) return data.specLabel or specId end
  _G.GearQuest = GQ
  return GQ
end

-- Merchant window: items = { { itemID, price, stack, numAvailable, extended } }
function Mock.OpenMerchant(name, items)
  Mock.merchant = { name = name, items = {} }
  for i, entry in ipairs(items or {}) do
    Mock.merchant.items[i] = { itemID = entry[1], price = entry[2], stack = entry[3], numAvailable = entry[4], extended = entry[5] }
  end
  Mock.FireEvent("MERCHANT_SHOW")
end

function Mock.CloseMerchant()
  Mock.FireEvent("MERCHANT_CLOSED")
  Mock.merchant = nil
end

-- Profession trainer window. services = { { spellID, name, type = "available"|"unavailable"|"used"|"header",
-- skill = "Tailoring", rank = 75, cost = copper } }. opts.tradeskill (default true),
-- opts.noSkillReq / opts.noLink drop those API functions, opts.filters = initial type filters.
function Mock.OpenTrainer(name, services, opts)
  opts = opts or {}
  Mock.trainer = { name = name, services = services or {}, tradeskill = opts.tradeskill ~= false,
    filters = opts.filters or { available = 1, unavailable = 0, used = 0 }, filterCalls = {} }
  local t = Mock.trainer
  local function visible()
    local list = {}
    for _, s in ipairs(t.services) do
      local kind = s.type or "available"
      if kind == "header" or t.filters[kind] == 1 then list[#list + 1] = s end
    end
    return list
  end
  _G.GetNumTrainerServices = function() return #visible() end
  _G.GetTrainerServiceInfo = function(index)
    local s = visible()[index]
    if not s then return nil end
    return s.name, s.type or "available", nil, true
  end
  _G.GetTrainerServiceCost = function(index)
    local s = visible()[index]
    return s and (s.cost or 0) or nil, 0, 0
  end
  _G.GetTrainerServiceSkillReq = nil
  if not opts.noSkillReq then
    _G.GetTrainerServiceSkillReq = function(index)
      local s = visible()[index]
      if not s or not s.skill then return nil end
      return s.skill, s.rank or 0, (s.rank or 0) > 0
    end
  end
  _G.GetTrainerServiceItemLink = nil
  if not opts.noLink then
    _G.GetTrainerServiceItemLink = function(index)
      local s = visible()[index]
      if not s or not s.spellID then return nil end
      return string.format("|cff71d5ff|Henchant:%d|h[%s]|h|r", s.spellID, s.name)
    end
  end
  _G.GetTrainerServiceTypeFilter = function(filter) return t.filters[filter] end
  _G.SetTrainerServiceTypeFilter = function(filter, on)
    t.filters[filter] = on
    t.filterCalls[#t.filterCalls + 1] = { filter, on }
    Mock.FireEvent("TRAINER_UPDATE")
  end
  if opts.tradeskill == "unknown" then
    _G.IsTradeskillTrainer = nil
  else
    _G.IsTradeskillTrainer = function() return t.tradeskill end
  end
  Mock.FireEvent("TRAINER_SHOW")
end

function Mock.CloseTrainer()
  Mock.FireEvent("TRAINER_CLOSED")
  Mock.trainer = nil
end

-- A minimal AtlasLootClassic: modules = { [moduleName] = { [instanceName] = { items = { { name = boss, npcID, [1] = { { slot, itemID } } } } } } }
function Mock.InstallAtlasLoot(modules, opts)
  opts = opts or {}
  local storage = {}
  for moduleName, contents in pairs(modules) do
    local module = { __atlaslootdata = { addonName = moduleName } }
    for instance, content in pairs(contents) do
      module[instance] = { name = instance, items = content.items, FactionID = content.FactionID, GetName = function(self) return self.name end }
    end
    storage[moduleName] = module
  end
  Mock.atlasLoads = {}
  _G.AtlasLoot = {
    ItemDB = { Storage = opts.lazy and {} or storage },
    Loader = {
      LoadModule = function(self, moduleName, onLoad)
        table.insert(Mock.atlasLoads, moduleName)
        if not storage[moduleName] then return "MISSING" end
        _G.AtlasLoot.ItemDB.Storage[moduleName] = storage[moduleName]
        if onLoad then onLoad(moduleName) end
        return true
      end,
    },
  }
end

-- A minimal ForeverDungeonJournal namespace. db = { [dungeon] = { bosses = { { name, npcID, trash, loot = { { itemID, name, slot, quality, mob } } } },
-- quests = { { id, name, faction, level, requires, objective, pickup, turnin, rewards, rewardChoice, rewardItems = { { itemID, name, quality } } } } } }; shared = SHARED_BY_BOSS.
-- opts.chains = QUEST_PREREQ_CHAINS, opts.starts = QUEST_START_MAPS, opts.xp = FOREVER_QUEST_XP_FALLBACK.
function Mock.InstallDungeonJournal(db, shared, opts)
  opts = opts or {}
  _G.ForeverDungeonJournal_NS = { DB = db, SHARED_BY_BOSS = shared or {}, QUEST_PREREQ_CHAINS = opts.chains or {}, QUEST_START_MAPS = opts.starts or {}, FOREVER_QUEST_XP_FALLBACK = opts.xp or {} }
end

-- A minimal Auctionator: prices = { [itemID] = { price = copper, age = days|nil, mean = copper|nil, available = n|nil } },
-- opts.lastScan (defaults to one hour ago), opts.noDatabase to drop the database object.
function Mock.InstallAuctionator(prices, opts)
  opts = opts or {}
  Mock.auctionatorCalls = {}
  local function entry(itemID) return prices[itemID] end
  _G.Auctionator = {
    API = { v1 = {
      GetAuctionPriceByItemID = function(callerID, itemID)
        assert(type(callerID) == "string" and callerID ~= "", "Auctionator callerID required")
        table.insert(Mock.auctionatorCalls, itemID)
        local e = entry(itemID)
        return e and e.price or nil
      end,
      GetAuctionAgeByItemID = function(callerID, itemID)
        local e = entry(itemID)
        return e and e.age or nil
      end,
    } },
  }
  if not opts.noDatabase then
    _G.Auctionator.Database = {
      GetMeanPrice = function(self, key, days) local e = entry(tonumber(key)) return e and e.mean or nil end,
      GetPriceHistory = function(self, key)
        local e = entry(tonumber(key))
        if e and e.available then return { { available = e.available } } end
        return {}
      end,
    }
  end
  local lastScan
  if opts.lastScan ~= false then lastScan = opts.lastScan or (Mock.now - 3600) end
  _G.AUCTIONATOR_SAVEDVARS = { TimeOfLastBrowseScan = lastScan }
end

-- A minimal Attune: data = { attunes, steps, quests, npcs, questGivers, questRewards }; opts.lang = { ["Q1_<id>"] = name }, opts.toons = Attune_DB.toons.
function Mock.InstallAttune(data, opts)
  opts = opts or {}
  _G.Attune_Data = { attunes = data.attunes or {}, steps = data.steps or {}, quests = data.quests or {}, npcs = data.npcs or {},
    questGivers = data.questGivers, questRewards = data.questRewards }
  local lang = opts.lang or {}
  _G.AttuneLang = setmetatable({}, { __index = function(_, key) return lang[key] or key end })
  _G.Attune_DB = { toons = opts.toons or {} }
end

-- The quest log as C_QuestLog.GetInfo lists it: zone headers then quests, in acceptance order.
local function questLogEntries()
  local entries, zones, byZone = {}, {}, {}
  for _, questID in ipairs(Mock.quests.order) do
    local d = Mock.quests.details[questID] or {}
    local zone = d.zone or "Quests"
    if not byZone[zone] then
      byZone[zone] = {}
      zones[#zones + 1] = zone
    end
    table.insert(byZone[zone], questID)
  end
  for _, zone in ipairs(zones) do
    entries[#entries + 1] = { title = zone, isHeader = true }
    for _, questID in ipairs(byZone[zone]) do
      local d = Mock.quests.details[questID] or {}
      entries[#entries + 1] = { title = d.title or ("Quest " .. questID), questID = questID, level = d.level, isHeader = false }
    end
  end
  return entries
end
Mock.QuestLogEntries = questLogEntries

-- Puts a quest in the log. def = { title, level, zone, objectives = { { text, numFulfilled, numRequired, finished } }, ready }
function Mock.AcceptQuest(questID, def)
  def = def or {}
  Mock.quests.log[questID] = true
  Mock.quests.details[questID] = { title = def.title, level = def.level, zone = def.zone, objectives = def.objectives or {}, ready = def.ready == true }
  local listed = false
  for _, id in ipairs(Mock.quests.order) do if id == questID then listed = true end end
  if not listed then table.insert(Mock.quests.order, questID) end
  Mock.FireEvent("QUEST_ACCEPTED", questID)
  Mock.FireEvent("QUEST_LOG_UPDATE")
end

-- Updates one objective; the quest becomes ready when every objective is finished.
function Mock.SetQuestObjective(questID, index, fulfilled, finished)
  local d = Mock.quests.details[questID]
  if not d then return end
  local o = d.objectives[index]
  if o then
    o.numFulfilled = fulfilled
    if finished ~= nil then o.finished = finished else o.finished = (o.numRequired or 0) > 0 and fulfilled >= o.numRequired end
  end
  local ready = #d.objectives > 0
  for _, obj in ipairs(d.objectives) do if not obj.finished then ready = false end end
  d.ready = ready
  Mock.FireEvent("QUEST_LOG_UPDATE")
end

-- Opens a quest-giver window offering questID (QUEST_DETAIL) at the player's position.
function Mock.OfferQuest(questID, npcName)
  Mock.questNPC = { questID = questID, name = npcName }
  Mock.FireEvent("QUEST_DETAIL", 0)
end

-- Opens the reward window of questID at an NPC (QUEST_COMPLETE).
function Mock.ShowQuestReward(questID, npcName)
  Mock.questNPC = { questID = questID, name = npcName }
  Mock.FireEvent("QUEST_COMPLETE")
end

function Mock.CloseQuestWindow()
  Mock.questNPC = nil
  Mock.FireEvent("QUEST_FINISHED")
end

-- Marks a quest completed and fires the turn-in events.
function Mock.CompleteQuest(questID)
  Mock.quests.completed[questID] = true
  Mock.quests.log[questID] = nil
  Mock.quests.details[questID] = nil
  for i = #Mock.quests.order, 1, -1 do
    if Mock.quests.order[i] == questID then table.remove(Mock.quests.order, i) end
  end
  Mock.FireEvent("QUEST_TURNED_IN", questID)
  Mock.FireEvent("QUEST_LOG_UPDATE")
end

-- The player finishes casting a spell (an enchant, a tradeskill recipe...).
function Mock.CastSpell(spellID, unit)
  Mock.FireEvent("UNIT_SPELLCAST_SUCCEEDED", unit or "player", "Cast-3-1-0-0-0-" .. tostring(spellID), spellID)
end

function Mock.LoadItem(itemID, success)
  local item = Mock.items[itemID]
  if item and success ~= false then
    item.loaded = true
  end
  Mock.FireEvent("ITEM_DATA_LOAD_RESULT", itemID, success ~= false)
end

-- def = { recipeID, name, outputItemID, quantityMin, quantityMax, learned, icon,
--         reagents = { { itemID=, quantity=, reagentType=, required=, alternatives={} } } }
function Mock.AddRecipe(def)
  local slots = {}
  for i, reagent in ipairs(def.reagents or {}) do
    local candidates = { { itemID = reagent.itemID } }
    for _, alt in ipairs(reagent.alternatives or {}) do
      candidates[#candidates + 1] = { itemID = alt }
    end
    slots[i] = {
      reagents = candidates,
      reagentType = reagent.reagentType == nil and 1 or reagent.reagentType,
      quantityRequired = reagent.quantity,
      required = reagent.required,
      slotIndex = i,
      dataSlotIndex = i,
    }
  end
  Mock.tradeskill.recipes[def.recipeID] = {
    info = {
      recipeID = def.recipeID,
      name = def.name,
      learned = def.learned ~= false,
      icon = def.icon or (200000 + def.recipeID),
      categoryID = def.categoryID or 1,
    },
    schematic = {
      recipeID = def.recipeID,
      name = def.name,
      icon = def.icon or (200000 + def.recipeID),
      outputItemID = def.outputItemID,
      quantityMin = def.quantityMin or 1,
      quantityMax = def.quantityMax or def.quantityMin or 1,
      recipeType = def.recipeType or 1,
      reagentSlotSchematics = slots,
      isRecraft = false,
      hasCraftingOperationInfo = false,
    },
  }
  return def.recipeID
end

-- def = { professionID, name, parentProfessionID, parentProfessionName,
--         childProfessionID, skillLevel, maxSkillLevel, recipeIDs = {} }
function Mock.OpenProfession(def)
  Mock.tradeskill.open = def
end

function Mock.CloseProfession()
  Mock.tradeskill.open = nil
end

function Mock.SetBag(bag, size, items)
  local slots = {}
  for i, entry in ipairs(items or {}) do
    slots[i] = { itemID = entry[1], count = entry[2] or 1 }
  end
  Mock.bags[bag] = { size = size, slots = slots }
end

-- list = { { name=, skillLevel=, maxSkillLevel=, skillLine=, slot= }, ... }
function Mock.SetProfessions(list)
  Mock.professionSlots = {}
  Mock.professionInfo = {}
  for i, p in ipairs(list) do
    local index = 10 + i
    Mock.professionSlots[p.slot or i] = index
    Mock.professionInfo[index] = p
  end
end

local function sumBags(itemID, bagIDs)
  local total = 0
  for _, bag in ipairs(bagIDs) do
    local container = Mock.bags[bag]
    if container then
      for _, slot in pairs(container.slots) do
        if slot.itemID == itemID then total = total + slot.count end
      end
    end
  end
  return total
end

function Mock.RunSlash(text)
  local handler = SlashCmdList and SlashCmdList["FOREVERPATH"]
  assert(handler, "slash command not registered")
  handler(text or "")
end

---------------------------------------------------------------------------
-- Install globals
---------------------------------------------------------------------------
local function itemIDFrom(itemInfo)
  if type(itemInfo) == "number" then return itemInfo end
  if type(itemInfo) == "string" then
    local id = itemInfo:match("|Hitem:(%d+)") or itemInfo:match("^item:(%d+)$") or itemInfo:match("^(%d+)$")
    return id and tonumber(id) or nil
  end
  return nil
end

function Mock.install()
  _G.CreateFrame = function(frameType, name, parent, template)
    return newWidget(frameType, name, parent, template)
  end
  _G.CreateFont = function(name) return newWidget("Font", name) end
  _G.CreateColor = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end
  _G.UnitName = function(unit)
    if unit == "questnpc" then return Mock.questNPC and Mock.questNPC.name or nil end
    if unit == "npc" then return (Mock.questNPC and Mock.questNPC.name) or (Mock.trainer and Mock.trainer.name) or (Mock.merchant and Mock.merchant.name) or nil end
    return Mock.character.name
  end
  -- The quest-giver window: GetQuestID names the quest on offer / being turned in.
  _G.GetQuestID = function() return Mock.questNPC and Mock.questNPC.questID or 0 end
  -- Map position and user waypoints (retail-engine C_Map / C_SuperTrack).
  _G.C_Map = {
    GetBestMapForUnit = function() return Mock.position.mapID end,
    GetPlayerMapPosition = function(mapID)
      if mapID ~= Mock.position.mapID then return nil end
      return { GetXY = function() return Mock.position.x, Mock.position.y end }
    end,
    CanSetUserWaypointOnMap = function(mapID) return Mock.waypointMaps == nil or Mock.waypointMaps[mapID] == true end,
    SetUserWaypoint = function(point) Mock.waypoint = point end,
    ClearUserWaypoint = function() Mock.waypoint = nil end,
    HasUserWaypoint = function() return Mock.waypoint ~= nil end,
  }
  _G.C_SuperTrack = { SetSuperTrackedUserWaypoint = function(value) Mock.superTracked = value end }
  _G.UiMapPoint = { CreateFromCoordinates = function(mapID, x, y) return { uiMapID = mapID, position = { x = x, y = y } } end }
  -- The trainer window API is installed by Mock.OpenTrainer; absent by default.
  _G.GetNumTrainerServices = nil
  _G.GetTrainerServiceInfo = nil
  _G.GetTrainerServiceSkillReq = nil
  _G.GetTrainerServiceCost = nil
  _G.GetTrainerServiceItemLink = nil
  _G.GetTrainerServiceTypeFilter = nil
  _G.SetTrainerServiceTypeFilter = nil
  _G.IsTradeskillTrainer = nil
  _G.GetZoneText = function() return Mock.zone end
  _G.GetSubZoneText = function() return Mock.subzone or "" end
  _G.GetMerchantNumItems = function() return Mock.merchant and #Mock.merchant.items or 0 end
  _G.GetMerchantItemLink = function(index)
    local entry = Mock.merchant and Mock.merchant.items[index]
    if not entry then return nil end
    local item = Mock.items[entry.itemID]
    return string.format("|cffffffff|Hitem:%d::::::::60:::::|h[%s]|h|r", entry.itemID, item and item.name or ("Item " .. entry.itemID))
  end
  _G.C_MerchantFrame = {
    GetItemInfo = function(index)
      local entry = Mock.merchant and Mock.merchant.items[index]
      if not entry then return nil end
      local item = Mock.items[entry.itemID]
      return { name = item and item.name, price = entry.price, stackCount = entry.stack or 1, numAvailable = entry.numAvailable or -1,
        hasExtendedCost = entry.extended or false, isPurchasable = true, isUsable = true }
    end,
  }
  _G.UnitLevel = function() return Mock.character.level end
  _G.UnitFactionGroup = function() return Mock.character.faction or "Alliance", Mock.character.faction or "Alliance" end
  _G.C_QuestLog = {
    IsQuestFlaggedCompleted = function(questID) return Mock.quests.completed[questID] == true end,
    IsOnQuest = function(questID) return Mock.quests.log[questID] == true end,
    IsComplete = function(questID)
      local d = Mock.quests.details[questID]
      return d ~= nil and d.ready == true
    end,
    GetNumQuestLogEntries = function()
      local entries = questLogEntries()
      return #entries, #Mock.quests.order
    end,
    GetInfo = function(index)
      local entry = questLogEntries()[index]
      if not entry then return nil end
      return { title = entry.title, questID = entry.questID, level = entry.level, isHeader = entry.isHeader }
    end,
    GetLogIndexForQuestID = function(questID)
      for index, entry in ipairs(questLogEntries()) do
        if entry.questID == questID then return index end
      end
      return nil
    end,
    GetQuestObjectives = function(questID)
      local d = Mock.quests.details[questID]
      local out = {}
      for i, o in ipairs(d and d.objectives or {}) do
        out[i] = { text = o.text, type = o.type or "monster", finished = o.finished == true, numFulfilled = o.numFulfilled or 0, numRequired = o.numRequired or 0 }
      end
      return out
    end,
    GetTitleForQuestID = function(questID)
      local d = Mock.quests.details[questID]
      return (d and d.title) or Mock.quests.titles[questID]
    end,
    RequestLoadQuestByID = function(questID)
      table.insert(Mock.quests.requests, questID)
      Mock.FireEvent("QUEST_DATA_LOAD_RESULT", questID, Mock.quests.titles[questID] ~= nil)
    end,
    AddQuestWatch = function(questID) Mock.quests.watched[questID] = true return true end,
    GetMaxNumQuestsCanAccept = function() return 20 end,
  }
  _G.C_Reputation = {
    GetNumFactions = function() return #Mock.factions end,
    GetFactionDataByIndex = function(index) return factionData(Mock.factions[index]) end,
    GetFactionDataByID = function(factionID)
      for _, entry in ipairs(Mock.factions) do
        if entry.factionID == factionID then return factionData(entry) end
      end
      return nil
    end,
  }
  for standing, label in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }) do
    _G["FACTION_STANDING_LABEL" .. standing] = label
  end
  _G.GetFactionInfo = nil
  _G.GetFactionInfoByID = nil
  _G.GetInventoryItemID = function(unit, slotID)
    if unit ~= "player" then return nil end
    return Mock.equipment[slotID]
  end
  _G.GetInventoryItemLink = function(unit, slotID)
    local id = unit == "player" and Mock.equipment[slotID] or nil
    if not id or not Mock.items[id] then return nil end
    return Mock.ItemLink(id)
  end
  _G.GetInventorySlotInfo = function(name)
    local ids = { HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ChestSlot = 5, WaistSlot = 6, LegsSlot = 7, FeetSlot = 8, WristSlot = 9, HandsSlot = 10,
      Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13, Trinket1Slot = 14, BackSlot = 15, MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18 }
    return ids[name]
  end
  _G.GetQuestLink = function(index)
    local entry = questLogEntries()[index]
    if not entry or entry.isHeader then return nil end
    return string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", entry.questID, entry.level or 0, entry.title)
  end
  _G.UnitClass = function() return Mock.character.class, Mock.character.classFile, Mock.character.classID end
  _G.UnitRace = function() return Mock.character.race, string.upper(Mock.character.race or ""), Mock.character.raceID end
  _G.GetRealmName = function() return Mock.character.realm end
  _G.GetMoney = function() return Mock.character.money end
  _G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 } }
  _G.SetPortraitTexture = function(texture, unit) texture.portrait = unit end
  _G.UIParent = newWidget("Frame", "UIParent")
  _G.SOUNDKIT = { LEVELUP = 888 }
  _G.PlaySound = function(kit, channel) table.insert(Mock.sounds, kit) return true end
  _G.GameTooltip = newWidget("GameTooltip", "GameTooltip")
  _G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) table.insert(Mock.output, tostring(message)) end }
  _G.time = function() return Mock.now end
  _G.GetTime = function() return Mock.now end
  _G.date = os.date
  _G.GetBuildInfo = function() return "1.60.1", "70450", "Oct 17 2026", 16001 end
  _G.WOW_PROJECT_ID = 1
  _G.WOW_PROJECT_MAINLINE = 1
  _G.InCombatLockdown = function() return Mock.combat end
  _G.IsShiftKeyDown = function() return Mock.shift == true end
  _G.GetCurrentKeyBoardFocus = function() return Mock.focus end
  _G.ChatEdit_InsertLink = function() return false end
  _G.ChatFrameUtil = nil
  _G.hooksecurefunc = function(a, b, c)
    local tbl, name, fn
    if type(a) == "table" then tbl, name, fn = a, b, c else tbl, name, fn = _G, a, b end
    local original = tbl[name]
    tbl[name] = function(...)
      local results = { original(...) }
      fn(...)
      return unpack(results)
    end
    table.insert(Mock.hooks, name)
  end
  _G.SlashCmdList = {}
  _G.UISpecialFrames = {}
  _G.BackdropTemplateMixin = {}
  _G.ITEM_QUALITY_COLORS = {
    [0] = { hex = "|cff9d9d9d" }, [1] = { hex = "|cffffffff" }, [2] = { hex = "|cff1eff00" },
    [3] = { hex = "|cff0070dd" }, [4] = { hex = "|cffa335ee" }, [5] = { hex = "|cffff8000" },
  }
  _G.NUM_BAG_SLOTS = 4
  _G.NUM_REAGENTBAG_SLOTS = 0
  _G.Enum = {
    BankType = { Character = 0, Account = 1 },
    BagIndex = { Backpack = 0, ReagentBag = 5, CharacterBankTab_1 = 6 },
    CraftingReagentType = { Modifying = 0, Basic = 1, Finishing = 2, Automatic = 3 },
    TradeskillRecipeType = { Item = 1, Salvage = 2, Enchant = 3, Gathering = 4 },
  }
  _G.C_Timer = {
    After = function(delay, fn) table.insert(Mock.timers, { delay = delay, fn = fn }) end,
  }
  _G.C_AddOns = {
    GetAddOnMetadata = function(name, field)
      if name == "ForeverPath" and field == "Version" then return "0.1.0-test" end
      return nil
    end,
    -- Load-on-demand addons: Mock.addOnLoaders[name] runs the addon's files.
    LoadAddOn = function(name)
      local loader = Mock.addOnLoaders[name]
      if not loader then return false, "MISSING" end
      loader()
      return true
    end,
  }

  _G.C_Item = {
    GetItemInfo = function(itemInfo)
      local id = itemIDFrom(itemInfo)
      local item = id and Mock.items[id]
      if not item or not item.loaded then return nil end
      return item.name, Mock.ItemLink(id), item.quality, item.ilvl or 1, 1, item.itemType or "Trade Goods", item.itemSubType or "Parts", 20, item.equipLoc or "", item.icon,
        item.sellPrice, item.classID or 7, item.subclassID or 1, item.bind or 0, 0, nil, true
    end,
    GetItemInfoInstant = function(itemInfo)
      local id = itemIDFrom(itemInfo)
      local item = id and Mock.items[id]
      if not item then return nil end
      return id, item.itemType or "Trade Goods", item.itemSubType or "Parts", item.equipLoc or "", item.icon, item.classID or 7, item.subclassID or 1
    end,
    GetItemStats = function(itemInfo)
      local id = itemIDFrom(itemInfo)
      local item = id and Mock.items[id]
      if not item or not item.stats then return nil end
      local out = {}
      for k, v in pairs(item.stats) do out[k] = v end
      return out
    end,
    GetDetailedItemLevelInfo = function(itemInfo)
      local id = itemIDFrom(itemInfo)
      local item = id and Mock.items[id]
      if not item or not item.ilvl then return nil end
      return item.ilvl, false, item.ilvl
    end,
    DoesItemExistByID = function(id) return Mock.items[id] ~= nil end,
    IsItemDataCachedByID = function(id) return Mock.items[id] ~= nil and Mock.items[id].loaded end,
    RequestLoadItemDataByID = function(id) table.insert(Mock.loadRequests, id) end,
    GetItemIconByID = function(id) return Mock.items[id] and Mock.items[id].icon or nil end,
    GetItemNameByID = function(id) return Mock.items[id] and Mock.items[id].loaded and Mock.items[id].name or nil end,
    GetItemCount = function(itemInfo, includeBank)
      local id = itemIDFrom(itemInfo)
      if not id then return 0 end
      local total = sumBags(id, { 0, 1, 2, 3, 4, 5 })
      if includeBank then
        total = total + sumBags(id, Mock.bankTabIDs)
      end
      return total
    end,
  }

  _G.C_Container = {
    GetContainerNumSlots = function(bag)
      local container = Mock.bags[bag]
      return container and container.size or 0
    end,
    GetContainerItemInfo = function(bag, slot)
      local container = Mock.bags[bag]
      local entry = container and container.slots[slot]
      if not entry then return nil end
      local item = Mock.items[entry.itemID]
      return {
        itemID = entry.itemID,
        stackCount = entry.count,
        hyperlink = Mock.ItemLink(entry.itemID),
        iconFileID = item and item.icon or 0,
        isLocked = false, isReadable = false, hasLoot = false, isFiltered = false,
        hasNoValue = false, isBound = false,
        itemName = item and item.name or "",
      }
    end,
    GetContainerItemID = function(bag, slot)
      local container = Mock.bags[bag]
      local entry = container and container.slots[slot]
      return entry and entry.itemID or nil
    end,
  }

  _G.C_Bank = {
    FetchPurchasedBankTabIDs = function(bankType)
      if bankType ~= 0 then return {} end
      return deepcopy(Mock.bankTabIDs)
    end,
    CanViewBank = function() return Mock.bankViewable end,
  }

  local ts = Mock.tradeskill
  local function openInfo()
    local open = ts.open
    if not open then
      return { professionID = 0 }
    end
    return {
      professionID = open.childProfessionID or open.professionID,
      parentProfessionID = open.parentProfessionID,
      professionName = open.name,
      parentProfessionName = open.parentProfessionName,
      skillLevel = open.skillLevel or 0,
      maxSkillLevel = open.maxSkillLevel or 0,
    }
  end
  _G.C_TradeSkillUI = {
    GetChildProfessionInfo = openInfo,
    GetBaseProfessionInfo = openInfo,
    GetAllRecipeIDs = function() return ts.open and deepcopy(ts.open.recipeIDs or {}) or {} end,
    GetFilteredRecipeIDs = function() return ts.open and deepcopy(ts.open.recipeIDs or {}) or {} end,
    GetRecipeInfo = function(recipeID)
      local recipe = ts.recipes[recipeID]
      return recipe and deepcopy(recipe.info) or nil
    end,
    GetRecipeSchematic = function(recipeID)
      local recipe = ts.recipes[recipeID]
      if not recipe then return nil end
      local visible = ts.open and contains(ts.open.recipeIDs, recipeID)
      if ts.schematicRequiresOpen and not visible then
        return { recipeID = recipeID, name = recipe.schematic.name, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = {} }
      end
      return deepcopy(recipe.schematic)
    end,
    IsNPCCrafting = function() return ts.npc end,
    IsTradeSkillGuild = function() return ts.guild end,
    IsTradeSkillLinked = function() return ts.linked, ts.linked and "Someone" or nil end,
    IsRecipeProfessionLearned = function(recipeID)
      local recipe = ts.recipes[recipeID]
      return recipe ~= nil and recipe.info.learned
    end,
    OpenTradeSkill = function(skillLine)
      table.insert(ts.openCalls, skillLine)
      local def = ts.openable[skillLine]
      if not def then return false end
      ts.open = def
      Mock.FireEvent("TRADE_SKILL_SHOW")
      Mock.FireEvent("TRADE_SKILL_LIST_UPDATE")
      return true
    end,
    CloseTradeSkill = function()
      ts.open = nil
      ts.closeCalls = (ts.closeCalls or 0) + 1
      Mock.FireEvent("TRADE_SKILL_CLOSE")
    end,
  }

  _G.GetProfessions = function()
    local s = Mock.professionSlots
    return s[1], s[2], s[3], s[4], s[5], s[6]
  end
  _G.GetProfessionInfo = function(index)
    local p = Mock.professionInfo[index]
    if not p then return nil end
    return p.name, p.icon or 0, p.skillLevel or 0, p.maxSkillLevel or 0, 0, 0, p.skillLine
  end

  -- Legacy globals are absent on Forever.
  _G.GetItemInfo = nil
  _G.GetItemInfoInstant = nil
  _G.GetItemCount = nil
  _G.GetContainerItemInfo = nil
  _G.GetContainerNumSlots = nil
  _G.GetTradeSkillInfo = nil
  _G.GetCraftInfo = nil
  _G.GetAddOnMetadata = nil

  -- Addon globals from a previous load.
  _G.ForeverPath = nil
  _G.ForeverPathDB = nil
  _G.ForeverPathCharDB = nil
  _G.ForeverPath_OnAddonCompartmentClick = nil
  _G.ForeverPathMainFrame = nil
  _G.ForeverPathEventFrame = nil
  _G.ForeverPathTracker = nil
  _G.ForeverPathMenu = nil
  _G.ForeverPathSearchBox = nil
  _G.ForeverPathNewGoalInput = nil
end

function Mock.reset()
  Mock.now = 1792147990
  Mock.output = {}
  Mock.frames = {}
  Mock.timers = {}
  Mock.items = {}
  Mock.loadRequests = {}
  Mock.hooks = {}
  Mock.focus = nil
  Mock.shift = false
  Mock.combat = false
  Mock.strictEvents = true
  Mock.bags = {}
  Mock.bankTabIDs = {}
  Mock.bankViewable = false
  Mock.professionSlots = {}
  Mock.professionInfo = {}
  Mock.merchant = nil
  Mock.zone = "Durotar"
  Mock.subzone = nil
  Mock.atlasLoads = {}
  _G.AtlasLoot = nil
  _G.ForeverDungeonJournal_NS = nil
  _G.Auctionator = nil
  _G.AUCTIONATOR_SAVEDVARS = nil
  Mock.auctionatorCalls = {}
  Mock.sounds = {}
  Mock.quests = { completed = {}, log = {}, details = {}, order = {}, titles = {}, requests = {}, watched = {} }
  Mock.questNPC = nil
  Mock.addOnLoaders = {}
  Mock.position = { mapID = 1411, x = 0.5, y = 0.5 }
  Mock.waypoint = nil
  Mock.waypointMaps = nil
  Mock.superTracked = nil
  Mock.equipment = {}
  Mock.factions = {}
  _G.GearQuest = nil
  _G.Attune_Data = nil
  _G.AttuneLang = nil
  _G.Attune_DB = nil
  Mock.character = { name = "Thandrel", level = 60, class = "Warrior", classFile = "WARRIOR", classID = 1, race = "Human", raceID = 1, realm = "Stormhold", money = 2143600 }
  Mock.trainer = nil
  Mock.tradeskill = {
    open = nil, recipes = {}, npc = false, guild = false, linked = false,
    openCalls = {}, openable = {}, schematicRequiresOpen = false, closeCalls = 0,
  }
  Mock.install()
end

return Mock
