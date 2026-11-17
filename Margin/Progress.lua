local _, ns = ...

-- Keeps the route current as you level and remembers what you did.
--
--  * Your skill is re-read when the game says it changed, so the route moves on even with the
--    profession window closed (recipes' colours are still the ones read at the last scan).
--  * Each skill-up is saved with the recipe that earned it, the crafts it took and what that cost.
--    The recipe is the last one you crafted; crafts are counted per recipe since the last skill-up.

local crafts = {}      -- recipeID -> casts since the last skill-up
local last             -- { id, t }: the last profession craft you finished
local KEEP = 300

local function recipeById(prof, id)
  for _, r in ipairs(prof.recipes) do if r.id == id then return r end end
end

-- Any known recipe of this character, so a craft cast is recognised whichever profession it is.
local function knownRecipe(id)
  for name, prof in pairs(ns.Char().profs) do
    local r = recipeById(prof, id)
    if r then return r, prof, name end
  end
end

function ns.History(profName)
  local h = ns.Char().history
  return h and h[profName] or {}
end

-- Saves a skill-up from `from` to `to` in a profession.
function ns.RecordProgress(profName, from, to)
  if not (profName and from and to and to > from) then return end
  local prof = ns.Char().profs[profName]
  local char = ns.Char()
  char.history = char.history or {}
  local h = char.history[profName] or {}
  char.history[profName] = h

  local r, n
  if last and time() - last.t < 600 then
    r = prof and recipeById(prof, last.id)
    n = crafts[last.id]
  end
  local entry = {
    t = time(), from = from, to = to,
    id = r and r.id, name = r and r.name or "(crafted something we did not see)",
    icon = r and r.icon, crafts = n or 0, cost = 0,
  }
  if r and n then
    local idx = ns.CraftIndex(char.profs)
    entry.cost = (ns.RecipeCost(r, idx)) * n
  end
  local prev = h[#h]
  if prev and prev.id and prev.id == entry.id and prev.to == entry.from and entry.t - prev.t < 3600 then
    prev.to, prev.crafts, prev.cost, prev.t = entry.to, prev.crafts + entry.crafts, prev.cost + entry.cost, entry.t
  else
    h[#h + 1] = entry
    if #h > KEEP then table.remove(h, 1) end
  end
  crafts = {}
  if ns.InvalidatePlan then ns.InvalidatePlan() end
end

-- Reads your current skills from the game and records any that went up.
function ns.RefreshSkills()
  local list = { GetProfessions() }
  local changed = false
  for i = 1, 6 do
    local idx = list[i]
    if idx then
      local name, _, level, maxLevel = GetProfessionInfo(idx)
      local prof = name and ns.Char().profs[name]
      if prof and level and (prof.skill ~= level or prof.max ~= maxLevel) then
        local old = prof.skill
        prof.skill, prof.max = level, maxLevel or prof.max
        if old and level > old then ns.RecordProgress(name, old, level) end
        changed = true
      end
    end
  end
  if changed and ns.RefreshUI then ns.RefreshUI() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("SKILL_LINES_CHANGED")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:SetScript("OnEvent", function(_, event, unit, _, spellID)
  if event == "SKILL_LINES_CHANGED" then
    C_Timer.After(0.2, ns.RefreshSkills)
  elseif unit == "player" and type(spellID) == "number" and not (issecretvalue and issecretvalue(spellID)) then
    if knownRecipe(spellID) then
      crafts[spellID] = (crafts[spellID] or 0) + 1
      last = { id = spellID, t = time() }
    end
  end
end)

---------------------------------------------------------------------------
-- A newly learned recipe shows up without reopening anything by hand
---------------------------------------------------------------------------

local function windowReady()
  return C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady()
end

-- Re-read the open profession a few times: the game's own list can take a moment to say "learned".
-- With no profession window open there is nothing to read, so the window shows a hint instead and
-- the next time you open one it is read as usual.
function ns.ScheduleRescan()
  for _, delay in ipairs({ 0.5, 2, 5 }) do
    C_Timer.After(delay, function() if windowReady() then ns.Scan(false) end end)
  end
  if ns.RefreshUI then ns.RefreshUI() end
end

-- A recipe was learned (id known): move it from "unlearned" to "learned" straight away, using what
-- was scanned for it, and have the profession re-read to get its real colour.
function ns.RecipeLearned(recipeID)
  for _, prof in pairs(ns.Char().profs) do
    for i, r in ipairs(prof.unlearned or {}) do
      if r.id == recipeID then
        table.remove(prof.unlearned, i)
        r.train, r.teach, r.diff, r.learnedAt = nil, nil, 0, time() -- orange until the next scan says otherwise
        prof.recipes[#prof.recipes + 1] = r
        prof.graduated = prof.graduated or {}
        prof.graduated[recipeID] = r
        prof.dirty = true
        if ns.InvalidatePlan then ns.InvalidatePlan() end
        return ns.ScheduleRescan()
      end
    end
  end
  -- not one we had seen: we cannot say which profession it is, so any may need a re-read
  for _, prof in pairs(ns.Char().profs) do prof.dirty = true end
  ns.ScheduleRescan()
end

local learn = CreateFrame("Frame")
for _, e in ipairs({ "NEW_RECIPE_LEARNED", "LEARNED_SPELL_IN_SKILL_LINE", "TRADE_SKILL_DATA_SOURCE_CHANGED", "SPELLS_CHANGED" }) do
  pcall(learn.RegisterEvent, learn, e) -- not every client has every one
end
local spellsQueued
learn:SetScript("OnEvent", function(_, event, a)
  if event == "NEW_RECIPE_LEARNED" and type(a) == "number" and not (issecretvalue and issecretvalue(a)) then
    ns.RecipeLearned(a)
  elseif event == "LEARNED_SPELL_IN_SKILL_LINE" and type(a) == "number" and not (issecretvalue and issecretvalue(a)) then
    ns.RecipeLearned(a) -- the spell is the recipe's craft spell
  elseif event == "SPELLS_CHANGED" or event == "TRADE_SKILL_DATA_SOURCE_CHANGED" then
    -- fires for many reasons: only worth a re-read when a profession window is open
    if spellsQueued or not windowReady() then return end
    spellsQueued = true
    C_Timer.After(2, function() spellsQueued = nil; if windowReady() then ns.Scan(false) end end)
  end
end)

-- Items you craft or buy change what is left to make and buy, so the route follows your bags.
local bagsQueued
local bagFrame = CreateFrame("Frame")
bagFrame:RegisterEvent("BAG_UPDATE_DELAYED")
bagFrame:SetScript("OnEvent", function()
  if bagsQueued then return end
  bagsQueued = true
  C_Timer.After(1, function()
    bagsQueued = nil
    if ns.RefreshUI then ns.RefreshUI() end
  end)
end)
