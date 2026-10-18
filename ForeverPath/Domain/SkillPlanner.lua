-- Skill-up planning: which recipes to craft, and how many times, to take a
-- profession from one skill level to another. Pure Lua.
--
-- The classic skill-up rule: a recipe is orange below its yellow threshold
-- (every craft gives a point), then the chance falls linearly to zero at the
-- grey threshold. Expected crafts for a point at skill p are 1 / chance(p).
-- For each point the cheapest recipe is picked: by expected cost when reagent
-- prices are known, else by expected crafts and reagent count. Learned
-- recipes always win; an unlearned recipe whose requirement is known (a
-- trainer visit recorded it, or the plans carry it) only fills points no
-- learned recipe covers, and comes with a "learn it" step in the tree.
local _, ns = ...

local SkillPlanner = {}
ns.SkillPlanner = SkillPlanner

-- Chance (0..1) of a skill point from one craft at skill p.
-- skill = { min, yellow, green, grey }; unknown thresholds give 0.
function SkillPlanner.Chance(skill, p)
  if type(skill) ~= "table" or not tonumber(skill.grey) or not tonumber(skill.yellow) then return 0 end
  if skill.grey <= 0 then return 0 end
  if p < skill.yellow then return 1 end
  if p >= skill.grey then return 0 end
  local span = skill.grey - skill.yellow
  if span <= 0 then return 0 end
  return (skill.grey - p) / span
end

-- "orange", "yellow", "green" or "grey" at skill p.
function SkillPlanner.Difficulty(skill, p)
  if type(skill) ~= "table" then return "grey" end
  if p < (skill.yellow or 0) then return "orange" end
  if p < (skill.green or 0) then return "yellow" end
  if p < (skill.grey or 0) then return "green" end
  return "grey"
end

-- Ranks two choices for one skill point. Each is { candidate, chance, exp }.
local function better(a, b)
  local ca, cb = a.candidate.cost, b.candidate.cost
  if ca and cb then
    local ea, eb = a.exp * ca, b.exp * cb
    if ea ~= eb then return ea < eb end
  elseif (ca == nil) ~= (cb == nil) then
    if a.exp ~= b.exp then return a.exp < b.exp end
    return ca ~= nil
  end
  if a.exp ~= b.exp then return a.exp < b.exp end
  local wa, wb = a.candidate.weight or 0, b.candidate.weight or 0
  if wa ~= wb then return wa < wb end
  return (a.candidate.spellID or 0) < (b.candidate.spellID or 0)
end

-- candidates: { { spellID, recipe, learned, learnable, skill, cost (copper per craft | nil), weight } }
-- Returns:
--   { from, to, segments = { { id, recipe, candidate, learned, from, to, expected, crafts, difficulty } },
--     list = { { spellID, recipe, learned, crafts, expected, from, to } } (one per recipe, by first use),
--     gaps = { { from, to } }, expected, total, covered (true when no gap) }
function SkillPlanner.Plan(current, target, candidates, opts)
  opts = opts or {}
  current, target = tonumber(current) or 0, tonumber(target) or 0
  local result = { from = current, to = target, segments = {}, list = {}, gaps = {}, expected = 0, total = 0, covered = true }
  if target <= current then return result end

  local function pick(p)
    local bestLearned, bestOther
    for _, c in ipairs(candidates or {}) do
      local chance = SkillPlanner.Chance(c.skill, p)
      if chance > 0 then
        local entry = { candidate = c, chance = chance, exp = 1 / chance }
        if c.learned then
          if not bestLearned or better(entry, bestLearned) then bestLearned = entry end
        elseif c.learnable and (c.skill.min or 0) <= p then
          if not bestOther or better(entry, bestOther) then bestOther = entry end
        end
      end
    end
    return bestLearned or bestOther
  end

  local segment
  for p = current, target - 1 do
    local choice = pick(p)
    local id = choice and choice.candidate.spellID or false
    if not segment or segment.id ~= id then
      segment = { id = id, from = p, to = p + 1, expected = 0,
        recipe = choice and choice.candidate.recipe or nil, candidate = choice and choice.candidate or nil,
        learned = choice and choice.candidate.learned or false,
        difficulty = choice and SkillPlanner.Difficulty(choice.candidate.skill, p) or nil }
      result.segments[#result.segments + 1] = segment
    end
    segment.to = p + 1
    if choice then segment.expected = segment.expected + choice.exp end
  end

  local byID = {}
  for _, seg in ipairs(result.segments) do
    if seg.recipe then
      seg.crafts = math.ceil(seg.expected - 1e-9)
      result.expected = result.expected + seg.expected
      result.total = result.total + seg.crafts
      local entry = byID[seg.id]
      if not entry then
        entry = { spellID = seg.id, recipe = seg.recipe, candidate = seg.candidate, learned = seg.learned, crafts = 0, expected = 0, from = seg.from, to = seg.to }
        byID[seg.id] = entry
        result.list[#result.list + 1] = entry
      end
      entry.crafts = entry.crafts + seg.crafts
      entry.expected = entry.expected + seg.expected
      entry.to = math.max(entry.to, seg.to)
    else
      result.gaps[#result.gaps + 1] = { from = seg.from, to = seg.to }
      result.covered = false
    end
  end
  return result
end

-- "150-170: 20 x Bolt of Silk Cloth (orange)" lines, one per segment.
function SkillPlanner.Lines(plan)
  local lines = {}
  for _, seg in ipairs(plan and plan.segments or {}) do
    if seg.recipe then
      lines[#lines + 1] = string.format("%d-%d: %d x %s (%s%s)", seg.from, seg.to, seg.crafts, seg.recipe.name or ("recipe " .. tostring(seg.id)),
        seg.difficulty or "?", seg.learned and "" or ", not learned")
    else
      lines[#lines + 1] = string.format("%d-%d: no recipe you know or could learn covers this", seg.from, seg.to)
    end
  end
  return lines
end
