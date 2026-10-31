-- /fp and /foreverpath.
local _, ns = ...

local Log = ns.Log
local Util = ns.Util

local Commands = {}
ns.Commands = Commands

Commands.help = {
  { "/fp", "Open or close the ForeverPath window." },
  { "/fp help", "Show this list." },
  { "/fp add <item> [qty]", "Add a goal by item ID or link (crafting when a recipe is known, otherwise obtain)." },
  { "/fp obtain <item> [qty]", "Add an obtain-item goal (drops, vendors, quests) even if a recipe exists." },
  { "/fp learn <recipe>", "Add a learn-recipe goal by recipe name (catalogue) or spell id: plans to get, or the trainer to visit." },
  { "/fp enchant <enchant> [casts]", "Add an enchant goal by name, spell id or Shift-clicked link: the formula or trainer, the reagents for every cast; completes as you cast it." },
  { "/fp skill <profession> [rank]", "Add a reach-skill goal (default: the next cap): which recipes to craft, how often, and their materials." },
  { "/fp quest <name or id>", "Add a quest goal (dungeon quests, attunement quests, or anything in your log): chain, pick-up, objectives, rewards." },
  { "/fp quests", "List the quests ForeverPath knows that feed your goals, with their state." },
  { "/fp equipment", "Every slot: what is worn, GearQuest Forever's best pick for it, and the goal that targets it." },
  { "/fp rep <faction> [standing]", "Add a reputation goal (default: the next standing): progress, quests that give reputation, rewards per standing." },
  { "/fp reps", "List your factions with their standing, and your reputation goals." },
  { "/fp goals", "List open goals." },
  { "/fp select <n>", "Select goal number n (opens it in Crafting)." },
  { "/fp remove <n>", "Remove goal number n." },
  { "/fp complete <n> | pause <n> | resume <n>", "Change a goal's status." },
  { "/fp tree [n]", "Print the dependency tree of a goal (default: selected)." },
  { "/fp characters", "List snapshotted characters; /fp alts toggles counting their bags." },
  { "/fp snapshot", "Save this character's snapshot now and show what it captured." },
  { "/fp shopping", "Print the shopping list (active and queued goals) to chat." },
  { "/fp sources <item>", "Show where an item comes from (vendors, DungeonJournal, AtlasLoot, item class)." },
  { "/fp vendors", "How much vendor and loot-table data is available." },
  { "/fp recipe <item>", "How an item is made: every catalogue recipe and combine, with skill, plans and reagents." },
  { "/fp catalogue", "Recipe catalogue status (client build it was generated from, counts)." },
  { "/fp trainers", "Trainer requirements recorded from profession trainer windows (recipes, trainers)." },
  { "/fp export", "Copy everything this account has learned on Forever (loot, quest givers, vendors, trainers) as one string to share." },
  { "/fp import", "Paste someone's /fp export: their loot, quest, vendor and trainer data fill in what you have not seen (yours always comes first)." },
  { "/fp shared [remove <n>]", "List the imports (who, when, how much), or remove one." },
  { "/fp train [profession]", "What your professions can train now (unlearned trainer recipes at or below your skill) with the trainer, zone and total cost, and what opens up in the next 25 points." },
  { "/fp prices [item]", "Auction House price status (Auctionator), or every known price for an item." },
  { "/fp celebrate [on|off|test|auto on|off]", "Completion toasts and sound; 'auto' toggles auto-completing goals." },
  { "/fp attunements", "List the attunements Attune knows for your faction, with progress." },
  { "/fp attune <name>", "Add an attunement goal by name (needs the Attune addon)." },
  { "/fp tracker", "Show or hide the compact goal tracker." },
  { "/fp minimap [show|hide]", "Show or hide the minimap button." },
  { "/fp open <dashboard|goals|crafting>", "Open the window on a screen." },
  { "/fp scan [all]", "Record recipes from your professions (opens their windows)." },
  { "/fp status", "Show client capabilities and recorded professions." },
  { "/fp debug", "Toggle diagnostic logging." },
  { "/fp errors", "Show recent errors captured by ForeverPath." },
  { "/fp reset window", "Reset the window, tracker and minimap button positions." },
}

-- Commands that work before the saved variables load; every other one is
-- refused until then (Commands.Dispatch checks).
local BEFORE_LOAD = { help = true, debug = true, errors = true, reset = true, show = true, hide = true }

local handlers = {}

function handlers.help()
  Log.Print("Commands:")
  for _, entry in ipairs(Commands.help) do
    Log.Output(string.format("  |cffffd100%s|r - %s", entry[1], entry[2]))
  end
end

function handlers.debug()
  Log.SetDebug(not Log.debugEnabled)
  Log.Print("Debug logging %s.", Log.debugEnabled and "enabled" or "disabled")
end

function handlers.scan(rest)
  ns.ProfessionProvider.RequestScan(rest == "all")
end

-- Every data module /fp status reports on; each has StatusLine().
local STATUS_MODULES = { "Recipes", "VendorLearner", "TrainerLearner", "QuestProvider", "QuestFactsLearner", "ClassicDBBridge", "LootLearner",
  "Share", "QuestieBridge", "AttuneBridge", "EquipmentProvider", "ReputationProvider", "SourceProvider", "PriceProvider" }

function handlers.status()
  Log.Print("Version %s", tostring(ns.VERSION))
  for _, row in ipairs(ns.Compat.Capabilities()) do
    Log.Output(string.format("  %s: %s", row[1], row[2]))
  end
  local professions = ns.ProfessionProvider.GetScannedProfessions()
  if #professions == 0 then
    Log.Output("  Recorded professions: none (open a profession window or use /fp scan)")
  else
    for _, p in ipairs(professions) do
      Log.Output(string.format("  Recorded %s: %d recipes, %d learned, %s", tostring(p.name), p.recipeCount or 0, p.learnedCount or 0, Util.FormatAgo(p.scannedAt)))
    end
  end
  local known = ns.ProfessionProvider.GetCharacterProfessions()
  if #known > 0 then
    local names = {}
    for _, p in ipairs(known) do
      names[#names + 1] = string.format("%s %s/%s", p.name, tostring(p.skillLevel), tostring(p.maxSkillLevel))
    end
    Log.Output("  Character professions: " .. Util.Join(names))
  end
  Log.Output(string.format("  Goals: %d open, %d completed", ns.GoalService.Count({ open = true }), ns.GoalService.Count({ status = ns.GoalModel.Statuses.COMPLETED })))
  for _, name in ipairs(STATUS_MODULES) do
    local module = ns[name]
    Log.Output("  " .. tostring(ns.Log.Try(module.StatusLine) or (name .. ": status unavailable")))
  end
end

function handlers.goals()
  local goals = ns.GoalService.List({ open = true })
  if #goals == 0 then
    Log.Print("No open goals. Add one with /fp add <item id or link> [qty].")
    return
  end
  local selected = ns.GoalService.SelectedID()
  Log.Print("Goals:")
  for i, goal in ipairs(goals) do
    local marker = goal.id == selected and "*" or " "
    local status = goal.status ~= ns.GoalModel.Statuses.ACTIVE and (" [" .. ns.GoalModel.StatusLabel[goal.status] .. "]") or ""
    Log.Output(string.format("  %s%d. %s%s", marker, i, ns.GoalService.Title(goal), status))
  end
end

-- "add <item text> [qty]" - the quantity is the trailing integer token, if any,
-- provided something precedes it (so "/fp add 2589" is an item, not a quantity).
local function addGoal(rest, goalType)
  rest = Util.Trim(rest or "")
  local itemText, quantity = rest, 1
  local head, tail = rest:match("^(.-)%s+(%d+)$")
  if head and head ~= "" then
    itemText, quantity = head, tonumber(tail)
  end
  local goal, message = ns.GoalService.AddItemFromInput(itemText, quantity, goalType)
  Log.Print("%s", message)
  if goal and ns.UI.MainFrame.IsShown() then
    ns.UI.MainFrame.SetAlert(message, "ok")
  end
end

function handlers.add(rest)
  addGoal(rest, nil)
end

function handlers.obtain(rest)
  addGoal(rest, ns.GoalModel.TypeIDs.OBTAIN_ITEM)
end

local function addTypedGoal(goal, message)
  Log.Print("%s", message)
  if goal and ns.UI.MainFrame.IsShown() then
    ns.UI.MainFrame.SetAlert(message, "ok")
    ns.UI.MainFrame.ShowScreen("crafting")
  end
end

function handlers.learn(rest)
  addTypedGoal(ns.GoalService.AddRecipeFromInput(rest))
end

function handlers.skill(rest)
  addTypedGoal(ns.GoalService.AddSkillFromInput(rest))
end

-- "enchant <name or link> [casts]" - the trailing integer is the cast count.
function handlers.enchant(rest)
  rest = Util.Trim(rest or "")
  local text, quantity = rest, 1
  local head, tail = rest:match("^(.-)%s+(%d+)$")
  if head and head ~= "" then
    text, quantity = head, tonumber(tail)
  end
  addTypedGoal(ns.GoalService.AddEnchantFromInput(text, quantity))
end

function handlers.quest(rest)
  local goal, message = ns.GoalService.AddQuestFromInput(rest)
  Log.Print("%s", message)
  if goal and ns.UI.MainFrame.IsShown() then
    ns.UI.MainFrame.SetAlert(message, "ok")
    ns.UI.MainFrame.ShowScreen("quests")
  end
end

function handlers.rep(rest)
  local goal, message = ns.GoalService.AddReputationFromInput(rest)
  Log.Print("%s", message)
  if goal and ns.UI.MainFrame.IsShown() then
    ns.UI.MainFrame.SetAlert(message, "ok")
    ns.UI.MainFrame.ShowScreen("reputations")
  end
end

function handlers.reps()
  local RP = ns.ReputationProvider
  Log.Print("%s", RP.StatusLine())
  for _, record in ipairs(RP.List()) do
    local goal = ns.GoalService.FindReputationGoal(record.factionID)
    Log.Output(string.format("  %s: %s (%d / %d)%s", record.name, record.standingLabel, record.into or 0, record.span or 0,
      goal and (" [goal: " .. ns.GoalModel.StandingLabels[goal.target.standing] .. "]") or ""))
  end
end

function handlers.equipment()
  local EP = ns.EquipmentProvider
  Log.Print("%s", EP.StatusLine())
  ns.GoalService.EvaluateViews()
  local analysis = ns.GoalService.Equipment()
  for _, entry in ipairs(analysis.slots) do
    local worn = entry.equipped
    local parts = { worn.itemID and (ns.ItemProvider.GetName(worn.itemID) .. (worn.ilvl and (" (" .. worn.ilvl .. ")") or "")) or "empty" }
    if entry.goal then parts[#parts + 1] = "goal: " .. ns.GoalService.Name(entry.goal) end
    if entry.upgrade == "bis" then parts[#parts + 1] = "best in slot"
    elseif entry.best then parts[#parts + 1] = string.format("pick: %s (%s%s)", entry.best.name, entry.best.sourceLabel, entry.best.ilvl and (", ilvl " .. entry.best.ilvl) or "") end
    Log.Output(string.format("  %s: %s", entry.slot.label, table.concat(parts, " - ")))
  end
end

function handlers.quests()
  local QP = ns.QuestProvider
  Log.Print("%s", QP.StatusLine())
  local goals = ns.GoalService.List({ open = true })
  ns.GoalService.EvaluateViews()
  local feeds = ns.GoalService.QuestFeeds()
  local ids = {}
  for questID in pairs(feeds) do ids[#ids + 1] = questID end
  table.sort(ids)
  for _, questID in ipairs(ids) do
    local feed = feeds[questID]
    local names = {}
    for _, g in ipairs(feed.goals) do names[#names + 1] = g.name end
    local label = QP.StateLabel(QP.State(questID), feed.entry)
    Log.Output(string.format("  %s [%s] - %s - feeds %s", feed.entry.name, label, feed.entry.instance or "?", Util.Join(names)))
  end
  if #ids == 0 then
    Log.Output("  No known quest rewards an item or reputation your goals need.")
  end
  for _, goal in ipairs(goals) do
    if goal.type == ns.GoalModel.TypeIDs.COMPLETE_QUEST then
      local view = views[goal.id]
      Log.Output(string.format("  Goal: %s - %s", ns.GoalService.Name(goal), view and view.message or ""))
    end
  end
end

local function resolveOrComplain(rest)
  local goal = ns.GoalService.FindByRef(Util.Trim(rest or ""))
  if not goal then
    Log.Print("No such goal. Use /fp goals to list them.")
  end
  return goal
end

function handlers.remove(rest)
  local goal = resolveOrComplain(rest)
  if not goal then return end
  ns.GoalService.Remove(goal.id)
  Log.Print("Removed %s", ns.GoalService.Title(goal))
end

function handlers.select(rest)
  local goal = resolveOrComplain(rest)
  if not goal then return end
  ns.GoalService.Select(goal.id)
  Log.Print("Selected %s", ns.GoalService.Title(goal))
  if ns.UI.MainFrame.IsShown() then
    ns.UI.MainFrame.ShowScreen("crafting")
  end
end

local function setStatusCommand(status, verb)
  return function(rest)
      local goal = resolveOrComplain(rest)
    if not goal then return end
    ns.GoalService.SetStatus(goal.id, status)
    Log.Print("%s %s", verb, ns.GoalService.Title(goal))
  end
end
handlers.complete = setStatusCommand(ns.GoalModel.Statuses.COMPLETED, "Completed")
handlers.pause = setStatusCommand(ns.GoalModel.Statuses.PAUSED, "Paused")
handlers.resume = setStatusCommand(ns.GoalModel.Statuses.ACTIVE, "Resumed")

function handlers.tree(rest)
  local goal
  if rest and Util.Trim(rest) ~= "" then
    goal = resolveOrComplain(rest)
  else
    goal = ns.GoalService.Selected() or ns.GoalService.List({ open = true })[1]
  end
  if not goal then
    Log.Print("No goal selected. Use /fp goals to list them.")
    return
  end
  ns.GoalService.EvaluateViews()
  local view = ns.GoalService.View(goal.id)
  if not view.tree then
    Log.Print("%s: %s", ns.GoalService.Title(goal), view.message or ns.Readiness.Label(view.readiness) or "no plan")
    return
  end
  Log.Print("Dependency tree for %s:", ns.GoalService.Title(goal))
  for _, line in ipairs(ns.DependencyResolver.Describe(view.tree, ns.ItemProvider.GetName)) do
    Log.Output("  " .. line)
  end
end

function handlers.characters()
  local list = ns.CharacterProvider.List()
  Log.Print("Characters (%d):", #list)
  for _, entry in ipairs(list) do
    local r = entry.record
    local profs = {}
    for _, p in ipairs(r.professions or {}) do profs[#profs + 1] = string.format("%s %d", p.name, p.skillLevel or 0) end
    Log.Output(string.format("  %s%s - level %d %s - %s - %d bag items%s - %s", r.name, entry.isCurrent and " (you)" or "", r.level or 0, r.class or "",
      #profs > 0 and table.concat(profs, ", ") or "no professions", Util.Count(r.bags and r.bags.items or {}), r.bank and " + bank" or "",
      entry.isCurrent and "live" or (entry.level .. " " .. Util.FormatAgo(r.lastSeen))))
  end
  Log.Print("Alts' bags are %s as owned (/fp alts to toggle).", ns.GoalService.IncludesAlts() and "counted" or "not counted")
end

function handlers.sources(rest)
  local parsed = ns.ItemProvider.ParseInput(Util.Trim(rest or ""))
  local itemID = parsed and parsed.itemID
  if not itemID and parsed and parsed.kind == "name" then
    local hits = ns.ItemProvider.SearchByName(parsed.name, 1)
    itemID = hits[1] and hits[1].itemID
  end
  if not itemID then
    Log.Print("Usage: /fp sources <item id, link or name>")
    return
  end
  local lines = ns.SourceProvider.Describe(itemID)
  Log.Print("Sources for %s:", ns.ItemProvider.GetName(itemID))
  if #lines == 0 then
    Log.Output("  none recorded (no vendor visited, no DungeonJournal or AtlasLoot entry, no class hint)")
  end
  for _, line in ipairs(lines) do Log.Output("  " .. line) end
  local price = ns.PriceProvider.GetPrice(itemID)
  if price then Log.Output("  Price: " .. Util.Money(price.copper) .. " each (" .. price.source .. ")") end
end

function handlers.vendors()
  local status = ns.SourceProvider.StatusInfo()
  Log.Print("%s DungeonJournal: %s. AtlasLoot: %s.", ns.VendorLearner.StatusLine(), status.journal, status.atlasloot)
end

function handlers.recipe(rest)
  local parsed = ns.ItemProvider.ParseInput(Util.Trim(rest or ""))
  local itemID = parsed and parsed.itemID
  if not itemID and parsed and parsed.kind == "name" then
    local hits = ns.ItemProvider.SearchByName(parsed.name, 1)
    itemID = hits[1] and hits[1].itemID
  end
  if not itemID then
    Log.Print("Usage: /fp recipe <item id, link or name>")
    return
  end
  local lines = ns.Recipes.Lines(itemID, ns.ItemProvider.GetName)
  Log.Print("How %s is made:", ns.ItemProvider.GetName(itemID))
  if #lines == 0 then
    Log.Output("  no recipe or combine in the catalogue" .. (ns.Recipes.IsAvailable() and "" or " (catalogue missing: run scripts\\extract_db.ps1)"))
  end
  for _, line in ipairs(lines) do Log.Output("  " .. line) end
end

function handlers.catalogue()
  Log.Print("%s", ns.Recipes.StatusLine())
  local info = ns.Recipes.Info()
  if info then
    Log.Output(string.format("  Client build at extraction: %s (%s), hotfix cache build %s. Generated from the client's own tables by tools\\DbExtract; regenerate after a patch with scripts\\extract_db.ps1.",
      tostring(info.build), tostring(info.buildName), tostring(info.hotfixBuild)))
  end
  Log.Output("  " .. ns.TrainerLearner.StatusLine())
end

function handlers.trainers()
  Log.Print("%s", ns.TrainerLearner.StatusLine())
  local trainers = {}
  for name, record in pairs(ns.TrainerLearner.Trainers() or {}) do
    trainers[#trainers + 1] = { name = name, record = record }
  end
  table.sort(trainers, function(a, b) return a.name < b.name end)
  for _, t in ipairs(trainers) do
    local where = t.record.zone or "?"
    if t.record.subzone then where = where .. " - " .. t.record.subzone end
    Log.Output(string.format("  %s (%s): %d recipe%s, %s", t.name, where, t.record.recipes or 0, (t.record.recipes or 0) == 1 and "" or "s", Util.FormatAgo(t.record.seenAt)))
  end
  if #trainers == 0 then
    Log.Output("  Open any profession trainer: every recipe on offer is recorded with the skill it needs, its cost and the trainer's location.")
  end
end

function handlers.export()
  local text, counts = ns.UI.ShareFrame.ShowExport()
  if text then
    Log.Print("Export ready (%s): copy it from the window with Ctrl+C.", ns.Share.CountsLabel(counts))
  else
    Log.Print("Nothing to export: %s", tostring(counts))
  end
end

function handlers.import(rest)
  local text = Util.Trim(rest or "")
  if text ~= "" then
    local ok, message = ns.Share.Import(text)
    Log.Print("%s", message)
    return
  end
  ns.UI.ShareFrame.ShowImport()
  Log.Print("Paste the export into the window and press Import.")
end

function handlers.shared(rest)
  local list = ns.Share.List()
  local index = tonumber((rest or ""):match("^%s*remove%s+(%d+)%s*$"))
  if index then
    local entry = list[index]
    if entry and ns.Share.Remove(entry.author) then
      Log.Print("Removed %s's shared data.", entry.label)
    else
      Log.Print("No import number %d; /fp shared lists them.", index)
    end
    return
  end
  Log.Print("%s", ns.Share.StatusLine())
  for i, entry in ipairs(list) do
    Log.Output(string.format("  %d. %s - %s - exported %s, imported %s", i, entry.label, ns.Share.CountsLabel(entry.counts),
      Util.FormatAgo(entry.at), Util.FormatAgo(entry.importedAt)))
  end
end

function handlers.train(rest)
  local name = Util.Trim(rest or "")
  local plans = ns.Planner.Trainable(name ~= "" and name or nil)
  if #plans == 0 then
    Log.Print(name ~= "" and ("You do not have " .. name .. ".") or "This character has no profession with trainer recipes.")
    return
  end
  for _, plan in ipairs(plans) do
    Log.Print("%s %d/%d: %d recipe%s to train now%s.", plan.profession, plan.skill, plan.max, #plan.now, #plan.now == 1 and "" or "s",
      plan.cost > 0 and (" (" .. Util.Money(plan.cost) .. ")") or "")
    for _, row in ipairs(plan.now) do
      Log.Output(string.format("  %d  %s - %s%s%s%s", row.rank, row.recipe.name or "?", row.cost > 0 and Util.Money(row.cost) or "free",
        row.trainer and (" - " .. row.trainer) or "", row.zone and (" (" .. row.zone .. ")") or "", row.classic and " [classic data]" or ""))
    end
    if #plan.soon > 0 then
      local names = {}
      for i, row in ipairs(plan.soon) do
        if i > 6 then names[#names + 1] = string.format("and %d more", #plan.soon - 6) break end
        names[#names + 1] = string.format("%s (%d)", row.recipe.name or "?", row.rank)
      end
      Log.Output("  Next: " .. table.concat(names, ", "))
    end
    if not plan.scanned then
      Log.Output("  Open your " .. plan.profession .. " window once so recipes you already know are left out.")
    end
  end
end

function handlers.prices(rest)
  local status = ns.PriceProvider.StatusInfo()
  rest = Util.Trim(rest or "")
  if rest == "" then
    Log.Print("%s", status.text)
    if status.lastScan then Log.Output("  Last browse scan: " .. Util.FormatAgo(status.lastScan)) end
    Log.Output("  " .. ns.VendorLearner.StatusLine())
    return
  end
  local parsed = ns.ItemProvider.ParseInput(rest)
  local itemID = parsed and parsed.itemID
  if not itemID and parsed and parsed.kind == "name" then
    local hits = ns.ItemProvider.SearchByName(parsed.name, 1)
    itemID = hits[1] and hits[1].itemID
  end
  if not itemID then
    Log.Print("Usage: /fp prices [item id, link or name]")
    return
  end
  Log.Print("Prices for %s:", ns.ItemProvider.GetName(itemID))
  for _, line in ipairs(ns.PriceProvider.Describe(itemID)) do
    Log.Output("  " .. line)
  end
end

function handlers.attunements()
  local AP = ns.AttuneBridge
  if not AP.IsAvailable() then
    Log.Print("Attune is not installed; attunement goals need it.")
    return
  end
  local list = AP.List()
  Log.Print("%s:", AP.StatusLine())
  for _, attune in ipairs(list) do
    local p = AP.Progress(attune.id)
    local goal = ns.GoalService.FindAttunementGoal(attune.id)
    Log.Output(string.format("  %s%s - %d%% (%d of %d steps)%s%s", attune.name, attune.levels and (" [" .. attune.levels .. "]") or "",
      p.percent, p.done, p.total, p.next and (" - next: " .. AP.StepText(p.next)) or "", goal and " [goal]" or ""))
  end
end

function handlers.attune(rest)
  local goal, message = ns.GoalService.AddAttunementFromInput(rest)
  Log.Print("%s", message)
  if goal and ns.UI.MainFrame.IsShown() then
    ns.UI.MainFrame.SetAlert(message, "ok")
    ns.UI.MainFrame.ShowScreen("attunements")
  end
end

function handlers.celebrate(rest)
  local DB = ns.Database
  rest = Util.Trim(rest or ""):lower()
  if rest == "test" then
    ns.UI.Toast.Test()
    Log.Print("Test toast shown.")
  elseif rest == "on" or rest == "off" then
    DB.SetSetting("toasts", rest == "on")
    DB.SetSetting("completeSound", rest == "on")
    Log.Print("Celebrations %s.", rest)
  elseif rest == "auto on" or rest == "auto off" then
    DB.SetSetting("autoComplete", rest == "auto on")
    Log.Print("Auto-complete %s.", rest:sub(6))
  else
    local function onOff(name) return DB.Setting(name) ~= false and "on" or "off" end
    Log.Print("Auto-complete %s, toasts %s, sound %s. Use /fp celebrate on|off|test, or /fp celebrate auto on|off.",
      onOff("autoComplete"), onOff("toasts"), onOff("completeSound"))
  end
end

function handlers.shopping()
  ns.GoalService.EvaluateViews()
  local list = ns.GoalService.ShoppingList()
  for _, line in ipairs(ns.ShoppingList.Lines(list, ns.ItemProvider.GetName)) do
    Log.Output(line)
  end
end

function handlers.snapshot()
  local record, err = ns.CharacterProvider.Snapshot()
  if not record then
    Log.Print("Snapshot failed: %s", tostring(err))
    return
  end
  local profs = {}
  for _, p in ipairs(record.professions or {}) do
    profs[#profs + 1] = string.format("%s %d/%d%s", p.name, p.skillLevel or 0, p.maxSkillLevel or 0, p.scanned and " (recorded)" or "")
  end
  Log.Print("Snapshot saved for %s: %d bag items%s, %d learned recipes, %d goals.", record.name,
    Util.Count(record.bags.items), record.bank and (", bank " .. Util.Count(record.bank.items) .. " items") or ", no bank data",
    Util.Count(record.knownRecipes), #record.goals)
  Log.Print("Professions (%s): %s", record.professionSource or "?", #profs > 0 and table.concat(profs, ", ") or "none")
end

function handlers.alts()
  Log.Print("%s", ns.GoalService.SetIncludeAlts(not ns.GoalService.IncludesAlts()))
end

function handlers.tracker()
  ns.UI.Tracker.Toggle()
end

function handlers.minimap(rest)
  local arg = Util.Trim(rest or ""):lower()
  local shown
  if arg == "show" or arg == "on" then shown = true
  elseif arg == "hide" or arg == "off" then shown = false
  else shown = ns.db.minimap.hide == true end
  ns.UI.MinimapButton.SetShown(shown)
  Log.Print("Minimap button %s.%s", shown and "shown" or "hidden", shown and "" or " Use /fp minimap to bring it back.")
end

function handlers.open(rest)
  local key = Util.Trim(rest or ""):lower()
  if key == "mygoals" then key = "goals" end
  ns.UI.MainFrame.Show()
  ns.UI.MainFrame.ShowScreen(key ~= "" and key or "dashboard")
end

function handlers.errors()
  if #Log.errors == 0 then
    Log.Print("No errors recorded this session.")
    return
  end
  Log.Print("Last %d error(s):", math.min(10, #Log.errors))
  for i = math.max(1, #Log.errors - 9), #Log.errors do
    local entry = Log.errors[i]
    Log.Output(string.format("  [%s] %s", Util.FormatAgo(entry.time), entry.message:match("^([^\n]*)") or entry.message))
  end
end

function handlers.reset(rest)
  if Util.Trim(rest or "") == "window" then
    ns.UI.MainFrame.ResetWindow()
    Log.Print("Window, tracker and minimap button positions reset.")
  else
    Log.Print("Usage: /fp reset window")
  end
end

function handlers.show()
  ns.UI.MainFrame.Show()
end

function handlers.hide()
  ns.UI.MainFrame.Hide()
end

function Commands.Dispatch(message)
  message = Util.Trim(message or "")
  if message == "" then
    ns.UI.MainFrame.Toggle()
    return
  end
  local command, rest = message:match("^(%S+)%s*(.-)$")
  command = (command or ""):lower()
  local handler = handlers[command]
  if not handler then
    Log.Print("Unknown command '%s'. Type /fp help.", command)
    return
  end
  if not ns.loaded and not BEFORE_LOAD[command] then
    Log.Print("Still loading, try again in a moment.")
    return
  end
  handler(rest)
end

if type(SlashCmdList) == "table" then
  _G.SLASH_FOREVERPATH1 = "/fp"
  _G.SLASH_FOREVERPATH2 = "/foreverpath"
  SlashCmdList["FOREVERPATH"] = function(message)
    Log.Call(Commands.Dispatch, message)
  end
end
