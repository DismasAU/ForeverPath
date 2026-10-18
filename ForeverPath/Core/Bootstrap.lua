-- Startup wiring. Runs last in the TOC.
local _, ns = ...

local Events = ns.Events
local Log = ns.Log
local Compat = ns.Compat

local Bootstrap = {}
ns.Bootstrap = Bootstrap

function Bootstrap.OnAddonLoaded(addonName)
  if addonName ~= ns.ADDON_NAME or ns.loaded then
    return
  end
  ns.Database.Load()

  if Compat.GetAddOnMetadata then
    local ok, version = pcall(Compat.GetAddOnMetadata, ns.ADDON_NAME, "Version")
    if ok and type(version) == "string" and version ~= "" then
      ns.VERSION = version
    end
  end

  ns.ItemProvider.Init()
  ns.ProfessionProvider.Init()
  ns.InventoryProvider.Init()
  ns.CharacterProvider.Init()
  ns.VendorProvider.Init()
  ns.TrainerProvider.Init()
  ns.AuctionPriceProvider.Init()
  ns.SourceProvider.Init()
  ns.AttuneProvider.Init()
  ns.QuestProvider.Init()
  ns.EquipmentProvider.Init()
  ns.ReputationProvider.Init()
  ns.GoalService.Init()
  ns.GoalCompletion.Init()
  ns.UI.MainFrame.Init()
  ns.UI.Tracker.Init()

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
    Log.Debug("Player login; %d goal(s) saved", ns.goals and ns.goals:Count() or 0)
  end)
end

-- Addon compartment (minimap addon menu) entry declared in the TOC.
function _G.ForeverPath_OnAddonCompartmentClick()
  ns.UI.MainFrame.Toggle()
end

Bootstrap.Init()
