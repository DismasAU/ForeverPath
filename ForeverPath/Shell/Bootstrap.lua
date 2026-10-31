-- Startup wiring. Runs last in the TOC.
local _, ns = ...

local Events = ns.Events
local Log = ns.Log
local Compat = ns.Compat
local Util = ns.Util

local Bootstrap = {}
ns.Bootstrap = Bootstrap

-- Init order: providers first, then the services that install hooks into
-- them (TrainerProvider -> Recipes.SetTrainerLookup, GoalService ->
-- CharacterProvider.SetGoalSource, the UI -> Util.SetMoneyRenderer at load).
Bootstrap.INIT_ORDER = {
  "Share", "ItemProvider", "ProfessionProvider", "InventoryProvider", "CharacterProvider",
  "VendorProvider", "TrainerProvider", "AuctionPriceProvider", "SourceProvider",
  "AttuneProvider", "ClassicDB", "LootLearner", "QuestieBridge", "QuestFactsProvider",
  "QuestProvider", "EquipmentProvider", "ReputationProvider",
  "GoalService", "GoalCompletion",
  "UI.MainFrame", "UI.Tracker", "UI.MinimapButton", "UI.Toast",
}

local function moduleAt(path)
  local module = ns
  for part in path:gmatch("[^.]+") do
    module = type(module) == "table" and module[part] or nil
  end
  return module
end

-- Runs every Init in order. One that raises is logged and skipped, so the
-- rest of the addon still loads.
function Bootstrap.InitModules()
  for _, path in ipairs(Bootstrap.INIT_ORDER) do
    local module = moduleAt(path)
    if type(module) == "table" and type(module.Init) == "function" then
      Log.Try(module.Init)
    else
      Log.Error("Module %s is missing; it was not started.", path)
    end
  end
end

function Bootstrap.OnAddonLoaded(addonName)
  if addonName ~= ns.ADDON_NAME or ns.loaded then
    return
  end
  ns.Database.Load()

  local version = Util.SafeCall(Compat.GetAddOnMetadata, ns.ADDON_NAME, "Version")
  if type(version) == "string" and version ~= "" then
    ns.VERSION = version
  end

  Bootstrap.InitModules()

  ns.loaded = true
  Log.Debug("ForeverPath %s loaded on %s build %s (interface %s)", tostring(ns.VERSION),
    tostring(Compat.client.version), tostring(Compat.client.build), tostring(Compat.client.interface))
  if not Compat.client.isForever then
    Log.Debug("This does not look like a World of Warcraft: Forever client; some features may be unavailable.")
  end
  Events.Fire("FP_READY")
end

function Bootstrap.Init()
  Events.Init()
  Events.RegisterWoW("ADDON_LOADED", Bootstrap.OnAddonLoaded)
  Events.RegisterWoW("PLAYER_REGEN_ENABLED", Events.FlushCombatQueue)
  Events.RegisterWoW("PLAYER_LOGIN", function()
    Log.Debug("Player login; %d goal(s) saved", ns.GoalService.Count())
  end)
end

-- Addon compartment (minimap addon menu) entry declared in the TOC.
function _G.ForeverPath_OnAddonCompartmentClick()
  ns.UI.MainFrame.Toggle()
end

Bootstrap.Init()
