-- Game event registration plus a tiny internal message bus.
--
-- Internal messages (prefixed FP_) decouple providers from the UI:
--   FP_GOALS_CHANGED       goals added, removed, selected or edited
--   FP_RECIPES_UPDATED     a profession scan finished (professionID)
--   FP_INVENTORY_UPDATED   bag or bank counts changed
--   FP_ITEM_LOADED         item data arrived from the server (itemID, success)
--   FP_READY               database loaded and providers initialised
local _, ns = ...

local Events = {
  handlers = {},      -- message -> list of functions
  wowHandlers = {},   -- event -> list of functions
  pending = {},       -- debounce keys
  combatQueue = {},   -- functions waiting for combat to end
  frame = nil,
}
ns.Events = Events

function Events.On(message, fn)
  local list = Events.handlers[message]
  if not list then
    list = {}
    Events.handlers[message] = list
  end
  list[#list + 1] = fn
end

function Events.Off(message, fn)
  local list = Events.handlers[message]
  if not list then return end
  for i = #list, 1, -1 do
    if list[i] == fn then
      table.remove(list, i)
    end
  end
end

function Events.Fire(message, ...)
  local list = Events.handlers[message]
  if not list then return end
  for i = 1, #list do
    ns.Log.Call(list[i], ...)
  end
end

function Events.DispatchWoW(event, ...)
  local list = Events.wowHandlers[event]
  if not list then return end
  for i = 1, #list do
    ns.Log.Call(list[i], ...)
  end
end

-- Registers a WoW event handler. Returns false when the client lacks the event.
function Events.RegisterWoW(event, fn)
  if not Events.frame then
    Events.Init()
  end
  if not Events.wowHandlers[event] then
    local ok = ns.Compat.RegisterEvent(Events.frame, event)
    if not ok then
      return false
    end
    Events.wowHandlers[event] = {}
  end
  local list = Events.wowHandlers[event]
  list[#list + 1] = fn
  return true
end

function Events.Init()
  if Events.frame then return end
  if type(CreateFrame) ~= "function" then
    return
  end
  local frame = CreateFrame("Frame", "ForeverPathEventFrame")
  frame:SetScript("OnEvent", function(_, event, ...)
    Events.DispatchWoW(event, ...)
  end)
  Events.frame = frame
end

-- Runs fn once, `delay` seconds after the first request with this key.
-- Later requests before it fires are merged into the same call.
function Events.Debounce(key, delay, fn)
  if Events.pending[key] then
    return
  end
  Events.pending[key] = true
  local function run()
    Events.pending[key] = nil
    ns.Log.Call(fn)
  end
  if ns.Compat.After then
    ns.Compat.After(delay or 0, run)
  else
    run()
  end
end

-- Defers work that touches protected UI until combat ends.
function Events.RunOutOfCombat(fn)
  if not ns.Compat.InCombatLockdown() then
    return ns.Log.Call(fn)
  end
  Events.combatQueue[#Events.combatQueue + 1] = fn
  return false, "deferred"
end

function Events.FlushCombatQueue()
  local queue = Events.combatQueue
  Events.combatQueue = {}
  for i = 1, #queue do
    ns.Log.Call(queue[i])
  end
end
