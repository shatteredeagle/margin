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

-- Polestar's Codex knows which recipe item teaches each craft, with its required
-- skill, reputation and sources. Used when Polestar is installed; nothing is bundled.
local function codex()
  local C = Polestar and Polestar.Codex
  if not C then return nil end
  if C.IsLoaded and not C.IsLoaded() and C.Load then pcall(C.Load) end
  if C.IsLoaded and not C.IsLoaded() then return nil end
  return C
end

local function teachOptions(C, id, base)
  local out = {}
  local ok, items = pcall(C.RecipeItems, id)
  if not ok or type(items) ~= "table" then return out end
  for _, itemID in ipairs(items) do
    local ok2, rec = pcall(C.Item, itemID)
    if ok2 and type(rec) == "table" and rec.reqSkill == base.professionID and rec.reqSkillRank
      and rec.status ~= "retired" then
      local vendor = false
      for _, src in ipairs(rec.sources or {}) do if src.type == "vendor" then vendor = true end end
      out[#out + 1] = { item = itemID, rank = rec.reqSkillRank, rep = rec.repFaction ~= nil, vendor = vendor }
    end
  end
  return out
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
  local C = codex()
  local recipes, unlearned, taught = {}, {}, 0
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
      elseif C and (info.maxTrivialLevel or 0) > (base.skillLevel or 0) then
        local opts = teachOptions(C, id, base)
        if #opts > 0 then
          local r = makeRecipe(id, info)
          r.diff = 0
          r.teach = opts
          unlearned[#unlearned + 1] = r
          taught = taught + 1
        end
      end
    end
  end

  ns.Char().profs[base.professionName] = {
    skill = base.skillLevel, max = base.maxSkillLevel,
    time = time(), recipes = recipes, unlearned = unlearned,
    codex = C ~= nil, taught = taught, -- Polestar present / recipes taught by items found
  }
  if verbose then
    ns.Print(base.professionName, #recipes, "recipes scanned,", #unlearned - taught, "trainer recipes,",
      taught, "taught by items" .. (C and "" or " (install Polestar to find these)"))
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
