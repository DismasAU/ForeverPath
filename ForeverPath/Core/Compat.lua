-- Client compatibility layer. All direct WoW API discovery happens here so the
-- rest of the addon never has to ask "which client is this?".
--
-- World of Warcraft: Forever (interface 16001) is a Retail 12.x based engine:
-- the C_* namespaces exist and most legacy globals (GetItemInfo, GetItemCount,
-- GetContainerItemInfo, GetTradeSkillInfo) are gone. Each capability is resolved
-- to the modern function first and the legacy one as a fallback, so the addon
-- also degrades gracefully on other clients. See API_COMPATIBILITY.md.
local _, ns = ...

local Compat = {}
ns.Compat = Compat

local function pick(...)
  for i = 1, select("#", ...) do
    local candidate = select(i, ...)
    if type(candidate) == "function" then
      return candidate
    end
  end
  return nil
end

function Compat.Detect()
  local version, build, buildDate, interface = "unknown", "unknown", "unknown", 0
  if type(GetBuildInfo) == "function" then
    local ok, v, b, d, i = pcall(GetBuildInfo)
    if ok then
      version, build, buildDate, interface = v or version, b or build, d or buildDate, tonumber(i) or 0
    end
  end
  Compat.client = {
    version = version,
    build = build,
    date = buildDate,
    interface = interface,
    projectID = WOW_PROJECT_ID,
    isForever = interface >= 16000 and interface < 20000,
  }

  local cItem = type(C_Item) == "table" and C_Item or {}
  Compat.GetItemInfo = pick(cItem.GetItemInfo, _G.GetItemInfo)
  Compat.GetItemInfoInstant = pick(cItem.GetItemInfoInstant, _G.GetItemInfoInstant)
  Compat.GetItemCount = pick(cItem.GetItemCount, _G.GetItemCount)
  Compat.GetItemIconByID = pick(cItem.GetItemIconByID)
  Compat.RequestLoadItemDataByID = pick(cItem.RequestLoadItemDataByID)
  Compat.IsItemDataCachedByID = pick(cItem.IsItemDataCachedByID)
  Compat.DoesItemExistByID = pick(cItem.DoesItemExistByID)

  local cContainer = type(C_Container) == "table" and C_Container or {}
  Compat.GetContainerNumSlots = pick(cContainer.GetContainerNumSlots, _G.GetContainerNumSlots)
  if type(cContainer.GetContainerItemInfo) == "function" then
    local getInfo = cContainer.GetContainerItemInfo
    -- Modern API: returns a ContainerItemInfo table.
    Compat.GetContainerSlot = function(bag, slot)
      local info = getInfo(bag, slot)
      if type(info) == "table" and info.itemID then
        return info.itemID, info.stackCount or 1
      end
      return nil
    end
  elseif type(_G.GetContainerItemInfo) == "function" then
    local getInfo = _G.GetContainerItemInfo
    -- Legacy API: multiple returns, itemID is the 10th value.
    Compat.GetContainerSlot = function(bag, slot)
      local _, count, _, _, _, _, _, _, _, itemID = getInfo(bag, slot)
      if itemID then
        return itemID, count or 1
      end
      return nil
    end
  else
    Compat.GetContainerSlot = nil
  end

  local cAddOns = type(C_AddOns) == "table" and C_AddOns or {}
  Compat.GetAddOnMetadata = pick(cAddOns.GetAddOnMetadata, _G.GetAddOnMetadata)

  -- Merchant window: C_MerchantFrame.GetItemInfo (table) or legacy GetMerchantItemInfo (multiple returns).
  Compat.GetMerchantNumItems = pick(_G.GetMerchantNumItems)
  Compat.GetMerchantItemLink = pick(_G.GetMerchantItemLink)
  local cMerchant = type(C_MerchantFrame) == "table" and C_MerchantFrame or {}
  if type(cMerchant.GetItemInfo) == "function" then
    Compat.GetMerchantItem = function(index)
      local info = cMerchant.GetItemInfo(index)
      if type(info) ~= "table" then return nil end
      return { name = info.name, price = info.price, stack = info.stackCount, numAvailable = info.numAvailable,
        hasExtendedCost = info.hasExtendedCost, isPurchasable = info.isPurchasable }
    end
  elseif type(_G.GetMerchantItemInfo) == "function" then
    Compat.GetMerchantItem = function(index)
      local name, _, price, stack, numAvailable, isPurchasable, _, extendedCost = _G.GetMerchantItemInfo(index)
      if name == nil and price == nil then return nil end
      return { name = name, price = price, stack = stack, numAvailable = numAvailable, hasExtendedCost = extendedCost and true or false, isPurchasable = isPurchasable }
    end
  else
    Compat.GetMerchantItem = nil
  end

  -- Merchant window: C_MerchantFrame.GetItemInfo (table) or legacy GetMerchantItemInfo (multiple returns).
  Compat.GetMerchantNumItems = pick(_G.GetMerchantNumItems)
  Compat.GetMerchantItemLink = pick(_G.GetMerchantItemLink)
  local cMerchant = type(C_MerchantFrame) == "table" and C_MerchantFrame or {}
  if type(cMerchant.GetItemInfo) == "function" then
    Compat.GetMerchantItem = function(index)
      local info = cMerchant.GetItemInfo(index)
      if type(info) ~= "table" then return nil end
      return { name = info.name, price = info.price, stack = info.stackCount, numAvailable = info.numAvailable,
        hasExtendedCost = info.hasExtendedCost, isPurchasable = info.isPurchasable }
    end
  elseif type(_G.GetMerchantItemInfo) == "function" then
    Compat.GetMerchantItem = function(index)
      local name, _, price, stack, numAvailable, isPurchasable, _, extendedCost = _G.GetMerchantItemInfo(index)
      if name == nil and price == nil then return nil end
      return { name = name, price = price, stack = stack, numAvailable = numAvailable, hasExtendedCost = extendedCost and true or false, isPurchasable = isPurchasable }
    end
  else
    Compat.GetMerchantItem = nil
  end
  Compat.InCombatLockdown = pick(_G.InCombatLockdown) or function() return false end
  Compat.After = (type(C_Timer) == "table" and type(C_Timer.After) == "function") and C_Timer.After or nil
  -- Quest state (attunement steps): C_QuestLog on this engine, legacy globals as fallback.
  Compat.IsQuestFlaggedCompleted = (type(C_QuestLog) == "table" and type(C_QuestLog.IsQuestFlaggedCompleted) == "function") and C_QuestLog.IsQuestFlaggedCompleted
    or (type(_G.IsQuestFlaggedCompleted) == "function" and _G.IsQuestFlaggedCompleted) or nil
  Compat.IsOnQuest = (type(C_QuestLog) == "table" and type(C_QuestLog.IsOnQuest) == "function") and C_QuestLog.IsOnQuest or nil

  Compat.hasTradeSkillUI = type(C_TradeSkillUI) == "table"
    and type(C_TradeSkillUI.GetRecipeSchematic) == "function"
    and type(C_TradeSkillUI.GetRecipeInfo) == "function"
  Compat.hasLegacyTradeSkill = type(_G.GetTradeSkillInfo) == "function"
  Compat.hasProfessionList = type(_G.GetProfessions) == "function" and type(_G.GetProfessionInfo) == "function"
  Compat.hasTrainerWindow = type(_G.GetNumTrainerServices) == "function" and type(_G.GetTrainerServiceInfo) == "function"
  Compat.hasBankTabs = type(C_Bank) == "table"
    and type(C_Bank.FetchPurchasedBankTabIDs) == "function"
    and type(Enum) == "table" and type(Enum.BankType) == "table"

  -- Enum values with fallbacks matching the Retail 12.x definitions.
  local enum = type(Enum) == "table" and Enum or {}
  Compat.reagentTypeBasic = (enum.CraftingReagentType and enum.CraftingReagentType.Basic) or 1
  Compat.bankTypeCharacter = (enum.BankType and enum.BankType.Character) or 0
  Compat.reagentBagIndex = (enum.BagIndex and enum.BagIndex.ReagentBag) or 5
  Compat.numBagSlots = tonumber(_G.NUM_BAG_SLOTS) or 4
  Compat.numReagentBagSlots = tonumber(_G.NUM_REAGENTBAG_SLOTS) or 0
  Compat.hasBackdropTemplate = type(_G.BackdropTemplateMixin) == "table"
end

-- Registers an event without letting an unknown event name abort the file.
-- Forever throws from RegisterEvent for events that do not exist on the client.
function Compat.RegisterEvent(frame, event)
  if not frame or type(frame.RegisterEvent) ~= "function" then
    return false, "no frame"
  end
  local ok, err = pcall(frame.RegisterEvent, frame, event)
  if not ok then
    ns.Log.Debug("Event %s is not available on this client: %s", tostring(event), tostring(err))
    return false, err
  end
  return true
end

-- Human readable capability summary used by /fp status.
function Compat.Describe()
  local c = Compat.client or {}
  return {
    { "Client", string.format("%s (build %s, interface %s)", tostring(c.version), tostring(c.build), tostring(c.interface)) },
    { "Forever client", c.isForever and "yes" or "no" },
    { "Item API (C_Item)", Compat.GetItemInfo and "available" or "missing" },
    { "Container API", Compat.GetContainerSlot and "available" or "missing" },
    { "Bank tabs (C_Bank)", Compat.hasBankTabs and "available" or "missing" },
    { "Profession API (C_TradeSkillUI)", Compat.hasTradeSkillUI and "available" or "missing" },
    { "Legacy tradeskill API", Compat.hasLegacyTradeSkill and "available (unused)" or "missing" },
    { "Profession list (GetProfessions)", Compat.hasProfessionList and "available" or "missing" },
    { "Trainer window API", Compat.hasTrainerWindow and "available" or "missing" },
  }
end

Compat.Detect()
