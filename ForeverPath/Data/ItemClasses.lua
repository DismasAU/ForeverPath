-- Item class / subclass heuristics for "where does this come from".
--
-- The client reports every item's classID and subclassID (GetItemInfoInstant),
-- so a Trade Goods item in the Herb subclass is gathered with Herbalism, Metal
-- & Stone is mined, Leather is skinned, Cloth drops from humanoids. These are
-- hints, not facts: they say what kind of source to expect, not which NPC.
-- Keyed by classID, then subclassID (Enum.ItemClass / Enum.ItemTradeskillSubclass).
local _, ns = ...

ns.Data = ns.Data or {}
local ItemClasses = {}
ns.Data.ItemClasses = ItemClasses

-- kind: "gather" (a profession node/skin) or "drop" (killed mobs / fishing).
ItemClasses.byClass = {
  [7] = { -- Tradeskill
    [4] = { kind = "gather", label = "Mining (gems)", detail = "Gems come from mining veins", skill = "Mining" },
    [5] = { kind = "drop", label = "Humanoid drops", detail = "Cloth drops from humanoids" },
    [6] = { kind = "gather", label = "Skinning", detail = "Skin beasts", skill = "Skinning" },
    [7] = { kind = "gather", label = "Mining", detail = "Mine veins and deposits", skill = "Mining" },
    [8] = { kind = "drop", label = "Beast drops / fishing", detail = "Meat drops from beasts; fish are caught" },
    [9] = { kind = "gather", label = "Herbalism", detail = "Pick herbs", skill = "Herbalism" },
    [10] = { kind = "drop", label = "Elemental drops", detail = "Elementals drop motes and essences" },
    [12] = { kind = "gather", label = "Disenchanting", detail = "Disenchant uncommon or better gear", skill = "Enchanting" },
  },
}

-- Returns a hint table (copy) or nil.
function ItemClasses.Lookup(classID, subclassID)
  local byClass = ItemClasses.byClass[classID]
  local hint = byClass and byClass[subclassID]
  if not hint then return nil end
  return { kind = hint.kind, label = hint.label, detail = hint.detail, skill = hint.skill, heuristic = true }
end
