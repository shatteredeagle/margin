local _, ns = ...

-- /margin probe: saves what Forever reports about UNLEARNED recipes of the open
-- profession (source text, requirements, difficulty) into MarginDB.probeUnlearned[profession].
local T = C_TradeSkillUI

local function flat(t, depth)
  if type(t) ~= "table" then return t end
  depth = depth or 0
  local o = {}
  for k, v in pairs(t) do
    if type(v) == "table" then o[k] = depth < 3 and flat(v, depth + 1) or "<table>"
    elseif type(v) ~= "function" then o[k] = v end
  end
  return o
end

local function call(f, ...)
  if not f then return "no function" end
  local r = { pcall(f, ...) }
  if not r[1] then return "ERR:" .. tostring(r[2]) end
  table.remove(r, 1)
  return flat(r)
end

function ns.Probe()
  if not (T and T.IsTradeSkillReady and T.IsTradeSkillReady()) then
    ns.Print("Open a profession window first.")
    return
  end
  local base = T.GetBaseProfessionInfo()
  local out = { time = date("%Y-%m-%d %H:%M:%S"), prof = base and base.professionName,
    skill = base and base.skillLevel, unlearned = {}, counts = { learned = 0, unlearned = 0 } }
  for _, id in ipairs(T.GetAllRecipeIDs()) do
    local info = T.GetRecipeInfo(id)
    if info and info.learned then
      out.counts.learned = out.counts.learned + 1
    elseif info then
      out.counts.unlearned = out.counts.unlearned + 1
      -- only keep those in the user's skill range, to keep the file readable
      if (info.maxTrivialLevel or 0) >= (base.skillLevel or 0) and (info.maxTrivialLevel or 0) <= (base.skillLevel or 0) + 80
        and #out.unlearned < 40 then
        out.unlearned[#out.unlearned + 1] = {
          id = id, name = info.name, trivial = info.maxTrivialLevel, diff = info.relativeDifficulty,
          info = flat(info),
          source = call(T.GetRecipeSourceText, id),
          requirements = call(T.GetRecipeRequirements, id),
          description = call(T.GetRecipeDescription, id),
          skillLineInfo = call(T.GetRecipeInfoForSkillLineAbility, info.skillLineAbilityID),
        }
      end
    end
  end
  MarginDB.probeUnlearned = MarginDB.probeUnlearned or {}
  MarginDB.probeUnlearned[out.prof or "unknown"] = out
  ns.Print(("probe saved: %d learned, %d unlearned, %d kept. /reload to write."):format(
    out.counts.learned, out.counts.unlearned, #out.unlearned))
end
