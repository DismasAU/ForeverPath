-- Farming estimates: how many kills, nodes, skins or casts it takes to get
-- the missing units of an item from a source with a known chance.
-- Pure Lua over resolver hints:
--   hint.chance   1/100 of a percent per loot (classic data or what the loot
--                 learner saw),
--   hint.perLoot  units per successful loot (learned; 1 when unknown),
--   hint.target   the creature, node or zone the estimate names,
--   hint.kind / hint.skill decide the verb.
local _, ns = ...

local Farming = {}
ns.Farming = Farming

local VERBS = { Skinning = { "skin", "skins" }, Herbalism = { "node", "nodes" }, Mining = { "node", "nodes" }, Fishing = { "cast", "casts" } }

-- { count, noun, target, text = "~25 kills of Mangy Wolf" } or nil.
function Farming.Estimate(hint, missing)
  missing = tonumber(missing) or 0
  if type(hint) ~= "table" or missing <= 0 then return nil end
  local chance = math.abs(tonumber(hint.chance) or 0)
  if chance <= 0 then return nil end
  local perLoot = math.max(1, tonumber(hint.perLoot) or 1)
  local expected = math.ceil(missing / (chance / 10000 * perLoot))
  local verb = hint.skill and VERBS[hint.skill]
  if not verb then
    if hint.object or hint.kind == "object" then verb = { "loot", "loots" } else verb = { "kill", "kills" } end
  end
  local noun = expected == 1 and verb[1] or verb[2]
  local target = hint.target or hint.boss or hint.object
  local text = string.format("~%d %s", expected, noun)
  if target then text = text .. (hint.skill == "Fishing" and " in " or " of ") .. target end
  return { count = expected, noun = noun, target = target, text = text }
end
