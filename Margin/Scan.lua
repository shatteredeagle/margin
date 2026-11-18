local _, ns = ...

local T = C_TradeSkillUI

local function makeRecipe(id, info)
  local s = T.GetRecipeSchematic(id, false)
  local r = {
    id = id,
    prof = nil, -- set by Scan, below
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

-- Polestar's Codex is an optional extra source of recipe items; the bundled table
-- (TaughtData.lua) is the main one, so Margin works without it.
local function codex()
  local C = Polestar and Polestar.Codex
  if not C then return nil end
  if C.IsLoaded and not C.IsLoaded() and C.Load then pcall(C.Load) end
  if C.IsLoaded and not C.IsLoaded() then return nil end
  return C
end

-- The recipe items that teach craft `id`: { item, rank, rep, vendorPrice }. The recipe is already
-- known to be this profession's (it came from its window), so the item's own skill-line number is not
-- checked: Forever files some of them under another line (First Aid's manuals use 2942, not 129).
-- Forever's own data (Polestar's Codex, the item tooltip) comes first; the bundled Classic table fills in.
-- Items needing more skill than your cap go in `later`, kept only to show where a recipe comes from.
local missingTips = 0
local function teachOptions(C, id, base)
  local out, later, seen = {}, {}, {}
  local function add(itemID, fallbackRank, repHint, vendorPrice)
    if seen[itemID] then return end
    seen[itemID] = true
    local info = ns.RecipeItemInfo(itemID, base.professionName)
    if not info then missingTips = missingTips + 1 end
    local rank = info and (info.rank or 0) or fallbackRank or 0
    local o = {
      item = itemID, rank = rank,
      rep = info and info.rep or repHint or false,
      repFaction = info and info.repFaction, repStanding = info and info.repStanding,
      vendorPrice = vendorPrice,
    }
    -- a rank taken from a table (not the tooltip) can be off, so allow some slack before calling it out of reach
    if rank > (base.maxSkillLevel or 0) + (info and 0 or 30) then later[#later + 1] = o else out[#out + 1] = o end
  end
  if C then
    local ok, items = pcall(C.RecipeItems, id)
    for _, itemID in ipairs(ok and type(items) == "table" and items or {}) do
      local ok2, rec = pcall(C.Item, itemID)
      if ok2 and type(rec) == "table" and rec.status ~= "retired" then
        local price
        for _, src in ipairs(rec.sources or {}) do
          if src.type == "vendor" and src.cost and src.cost > 0 and (not price or src.cost < price) then price = src.cost end
        end
        add(itemID, rec.reqSkillRank, rec.repFaction ~= nil, price)
      end
    end
  end
  for _, t in ipairs(ns.TAUGHT and ns.TAUGHT[id] or {}) do add(t[1], t[3]) end
  return out, later
end

-- Reads every learned recipe of the open profession into MarginDB, plus the
-- unlearned ones a profession trainer teaches (ns.TRAINER) for the route planner.
-- Every scan attempt leaves a line in MarginDB.scanLog (the last 20), including the ones that give
-- up and why, so "this profession does not show up" can be answered from the save file.
local function logScan(why, base, extra)
  local log = MarginDB.scanLog or {}
  MarginDB.scanLog = log
  log[#log + 1] = ("%s %s | name=%s id=%s skill=%s/%s | %s"):format(date("%H:%M:%S"), why,
    tostring(base and base.professionName), tostring(base and base.professionID),
    tostring(base and base.skillLevel), tostring(base and base.maxSkillLevel), extra or "")
  while #log > 20 do table.remove(log, 1) end
end

local function scanNow(verbose)
  if not (T and T.IsTradeSkillReady and T.IsTradeSkillReady()) then
    if verbose then ns.Print("Open a profession window first.") end
    local base = T and T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    -- only worth a line when a window is actually up (a profession is being shown but not ready)
    if base and base.professionName then logScan("not ready", base) end
    return
  end
  local base = T.GetBaseProfessionInfo()
  if not base or not base.professionName or base.professionName == "" then
    logScan("no profession info", base, "window ready but GetBaseProfessionInfo gave no name")
    return
  end

  local trainer = ns.TRAINER and ns.TRAINER[base.professionName] or {}
  local C = codex()
  missingTips = 0
  local recipes, unlearned, taught = {}, {}, 0
  -- Every other recipe the window lists, only when "all recipes" is on (it costs a schematic read each).
  -- The cut-off keeps out recipes from much later content that nobody could make or sell yet.
  local wantAll = ns.Opt("profitScope") == "all"
  local every = {}
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
      elseif (info.maxTrivialLevel or 0) > (base.skillLevel or 0) then
        local opts, later = teachOptions(C, id, base)
        if #opts > 0 then
          local r = makeRecipe(id, info)
          r.diff = 0
          r.teach = opts
          unlearned[#unlearned + 1] = r
          taught = taught + 1
        elseif wantAll and (info.maxTrivialLevel or 0) <= 300 then
          local r = makeRecipe(id, info)
          r.diff, r.extra = 0, true
          if #later > 0 then r.teach = later end -- only to show where it comes from; the plan never uses it
          if not r.out or ns.ItemExists(r.out) then every[#every + 1] = r end
        end
      elseif wantAll and (info.maxTrivialLevel or 0) <= 300 then
        local r = makeRecipe(id, info)
        r.diff, r.extra = 0, true
        if not r.out or ns.ItemExists(r.out) then every[#every + 1] = r end -- not a Forever item: not a real recipe here
      end
    end
  end

  ns.ObserveBands(recipes, base.skillLevel) -- before recipes just learned are mixed in below
  local before = ns.Char().profs[base.professionName]
  local oldSkill = before and before.skill
  -- recipes learned a moment ago can be missing from the game's list for a few seconds: keep them
  local graduated = {}
  for id, r in pairs(before and before.graduated or {}) do
    local seen = false
    for _, x in ipairs(recipes) do if x.id == id then seen = true; break end end
    if not seen and time() - (r.learnedAt or 0) < 600 then
      recipes[#recipes + 1] = r
      graduated[id] = r
    end
  end
  for _, r in ipairs(recipes) do r.prof = base.professionName end
  for _, r in ipairs(unlearned) do r.prof = base.professionName end
  for _, r in ipairs(every) do r.prof = base.professionName end
  -- the profession window you have open is the one Margin opens on next time
  if ProfessionsFrame and ProfessionsFrame:IsShown() then
    ns.Char().lastProf = base.professionName
    if ns.S then ns.S.prof = base.professionName end
  end
  ns.Char().profs[base.professionName] = {
    id = base.professionID, skill = base.skillLevel, max = base.maxSkillLevel, scanSkill = base.skillLevel,
    time = time(), recipes = recipes, unlearned = unlearned,
    codex = C ~= nil, taught = taught, -- Polestar present / recipes taught by items found
    graduated = next(graduated) and graduated or nil,
    every = wantAll and every or nil, -- nil when "all recipes" was off at this scan
  }
  logScan("scanned", base, ("%d ids, %d learned, %d unlearned considered"):format(#T.GetAllRecipeIDs(), #recipes, #unlearned))
  if verbose then
    ns.Print(base.professionName, #recipes, "recipes scanned,", #unlearned - taught, "trainer recipes,",
      taught, "taught by items")
  end
  if oldSkill and base.skillLevel > oldSkill and ns.RecordProgress then
    ns.RecordProgress(base.professionName, oldSkill, base.skillLevel)
  end
  ns.needRescan = missingTips > 0 -- recipe item tooltips were not loaded yet; try again when they arrive
  -- a scan on its own never replans: the plan only notes that it is out of date. (A profession with no plan yet is
  -- planned when it is first drawn.)
  if ns.MarkStale then ns.MarkStale() end
  if ns.RedrawUI then ns.RedrawUI() end
end

local pending
function ns.Scan(verbose)
  local t0 = debugprofilestop()
  scanNow(verbose)
  ns.PerfNote("scan", debugprofilestop() - t0)
end

local trailing
local f = CreateFrame("Frame")
f:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:SetScript("OnEvent", function(_, event)
  if event == "TRADE_SKILL_SHOW" then
    ns.rescanTries = 0
    -- what the client reports the moment a profession window opens (First Aid, Cooking, ...)
    MarginDB.scanLog = MarginDB.scanLog or {}
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local ids = T.GetAllRecipeIDs and T.GetAllRecipeIDs()
    table.insert(MarginDB.scanLog, ("%s TRADE_SKILL_SHOW | ready=%s name=%s ids=%s frames: Professions=%s TradeSkill=%s"):format(
      date("%H:%M:%S"), tostring(T.IsTradeSkillReady and T.IsTradeSkillReady()), tostring(base and base.professionName),
      tostring(ids and #ids), tostring(ProfessionsFrame and ProfessionsFrame:IsShown()), tostring(TradeSkillFrame and TradeSkillFrame:IsShown())))
    while #MarginDB.scanLog > 20 do table.remove(MarginDB.scanLog, 1) end
  end
  if pending then return end
  if event == "TRADE_SKILL_LIST_UPDATE" then
    -- the list updates on every craft, filter and search while a profession window is open; re-reading every
    -- recipe each time was a lot of work and garbage. Read again when your skill changed or the read is old.
    local base = T.GetBaseProfessionInfo and T.GetBaseProfessionInfo()
    local last = base and base.professionName and ns.Char().profs[base.professionName]
    if last and time() - (last.time or 0) < 20 then
      -- read recently: not again for every craft; one catch-up read when the gap is over, to pick up new colours
      if not trailing then
        trailing = true
        C_Timer.After(21 - (time() - (last.time or 0)), function() trailing = nil; ns.Scan(false) end)
      end
      return
    end
  end
  pending = true
  C_Timer.After(0.5, function() pending = nil; ns.Scan(false) end)
end)

-- Item data arrives asynchronously: re-read the profession once the recipe items have loaded.
local loader = CreateFrame("Frame")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local queued
loader:SetScript("OnEvent", function()
  -- a recipe item the game can never give a tooltip for would keep this asking for ever: three tries per window
  if not ns.needRescan or queued or (ns.rescanTries or 0) >= 3 then return end
  ns.rescanTries = (ns.rescanTries or 0) + 1
  queued = true
  C_Timer.After(1.5, function() queued = nil; ns.needRescan = false; ns.Scan(false) end)
end)
