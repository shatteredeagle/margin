-- Probe 2: C_TradeSkillUI shapes on Forever. Open a profession window, /mgprobe, /reload.
MarginDB = MarginDB or {}

local function safe(f, ...)
  local r = { pcall(f, ...) }
  if not r[1] then return "ERR:" .. tostring(r[2]) end
  table.remove(r, 1)
  return r
end

local function flat(t, depth)
  if type(t) ~= "table" then return t end
  depth = depth or 0
  local o = {}
  for k, v in pairs(t) do
    if type(v) == "table" then
      o[k] = depth < 3 and flat(v, depth + 1) or "<table>"
    elseif type(v) ~= "function" then
      o[k] = v
    end
  end
  return o
end

local function dump()
  local T = C_TradeSkillUI
  local out = { time = date("%Y-%m-%d %H:%M:%S"), fns = {} }
  local names = {}
  for k, v in pairs(T) do if type(v) == "function" then names[#names + 1] = k end end
  table.sort(names)
  out.fns = names
  out.baseProf = flat(safe(T.GetBaseProfessionInfo))
  out.isReady = safe(T.IsTradeSkillReady)
  out.professions = flat(safe(GetProfessions))
  local ids = T.GetAllRecipeIDs()
  out.numIds = #ids
  out.recipes = {}
  for i = 1, math.min(#ids, 25) do
    local id = ids[i]
    local e = { id = id, info = flat(safe(T.GetRecipeInfo, id)) }
    local s = safe(T.GetRecipeSchematic, id, false)
    e.schematic = flat(s)
    e.outputItem = flat(safe(T.GetRecipeOutputItemData, id))
    e.itemLink = safe(T.GetRecipeItemLink, id)
    out.recipes[#out.recipes + 1] = e
  end
  return out
end

SLASH_MGPROBE1 = "/mgprobe"
SlashCmdList.MGPROBE = function()
  local ok, res = pcall(dump)
  MarginDB.probe2 = ok and res or { error = tostring(res) }
  print("|cff66ccffMargin|r probe2 saved. /reload to flush.")
end
