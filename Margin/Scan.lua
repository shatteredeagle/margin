local _, ns = ...

local T = C_TradeSkillUI

local function makeRecipe(id, info)
  local s = T.GetRecipeSchematic(id, false)
  local r = {
    id = id,
    name = info.name,
    icon = info.icon,
    diff = info.relativeDifficulty, -- 0 optimal, 1 medium, 2 easy, 3 trivial
    trivial = info.maxTrivialLevel,
    ups = info.numSkillUps or 1,
    canSkillUp = info.canSkillUp,
    out = s and s.outputItemID,
    qty = s and ((s.quantityMin or 1) + (s.quantityMax or 1)) / 2 or 1,
    reagents = {},
  }
  if s then
    for _, slot in ipairs(s.reagentSlotSchematics or {}) do
      local first = slot.reagents and slot.reagents[1]
      if slot.required and first and first.itemID then
        r.reagents[#r.reagents + 1] = { item = first.itemID, count = slot.quantityRequired }
      end
    end
  end
  return r
end

-- Reads every learned recipe of the open profession into MarginDB, plus the
-- unlearned ones a profession trainer teaches (ns.TRAINER) for the route planner.
function ns.Scan(verbose)
  if not (T and T.IsTradeSkillReady and T.IsTradeSkillReady()) then
    if verbose then ns.Print("Open a profession window first.") end
    return
  end
  local base = T.GetBaseProfessionInfo()
  if not base or not base.professionName then return end

  local trainer = ns.TRAINER and ns.TRAINER[base.professionName] or {}
  local recipes, unlearned = {}, {}
  for _, id in ipairs(T.GetAllRecipeIDs()) do
    local info = T.GetRecipeInfo(id)
    if info and not info.isGatheringRecipe and not info.isSalvageRecipe then
      if info.learned then
        recipes[#recipes + 1] = makeRecipe(id, info)
      elseif trainer[id] then
        local r = makeRecipe(id, info)
        r.diff = 0 -- unlearned recipes report no difficulty; the route assumes orange at the trainer rank
        r.train = { rank = trainer[id][1], fee = trainer[id][2] }
        unlearned[#unlearned + 1] = r
      end
    end
  end

  ns.Char().profs[base.professionName] = {
    skill = base.skillLevel, max = base.maxSkillLevel,
    time = time(), recipes = recipes, unlearned = unlearned,
  }
  if verbose then
    ns.Print(base.professionName, #recipes, "recipes scanned,", #unlearned, "trainer recipes")
  end
  if ns.RefreshUI then ns.RefreshUI() end
end

local pending
local f = CreateFrame("Frame")
f:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:SetScript("OnEvent", function()
  if pending then return end
  pending = true
  C_Timer.After(0.5, function() pending = nil; ns.Scan(false) end)
end)
