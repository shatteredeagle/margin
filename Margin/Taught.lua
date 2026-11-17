local _, ns = ...

-- Reads a recipe item's own tooltip for what Forever really requires: the skill rank
-- ("Requires Leatherworking (125)") and whether a reputation is needed
-- ("Requires <faction> - Honored"). The bundled table (TaughtData.lua) only has Classic
-- Era's rank, which differs from Forever's, so the tooltip wins when it is available.

local cache = {}
local tip

local function readable(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function tooltipLines(itemID)
  local out = {}
  if C_TooltipInfo and C_TooltipInfo.GetItemByID then
    local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
    if ok and type(data) == "table" and data.lines then
      for _, l in ipairs(data.lines) do
        local t = readable(l.leftText)
        if type(t) == "string" then out[#out + 1] = t end
      end
    end
  end
  if #out == 0 then
    tip = tip or CreateFrame("GameTooltip", "MarginScanTip", nil, "GameTooltipTemplate")
    tip:SetOwner(UIParent, "ANCHOR_NONE")
    tip:ClearLines()
    pcall(tip.SetItemByID, tip, itemID)
    for i = 1, tip:NumLines() do
      local fs = _G["MarginScanTipTextLeft" .. i]
      local t = fs and readable(fs:GetText())
      if type(t) == "string" then out[#out + 1] = t end
    end
  end
  return out
end

-- { rank = skill required or nil, rep = needs a reputation } or nil while the item is not loaded.
function ns.RecipeItemInfo(itemID, professionName)
  local c = cache[itemID]
  if c then return c end
  local lines = tooltipLines(itemID)
  if #lines < 2 then
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
    return nil
  end
  local info = { rep = false }
  local fmt = ITEM_REQ_SKILL or "Requires %s"
  local pat = "^" .. fmt:gsub("%%s", "(.+)") .. "$"
  for _, t in ipairs(lines) do
    local req = t:match(pat)
    if req then
      local rank = professionName and req:find(professionName, 1, true) and tonumber(req:match("%((%d+)%)"))
      if rank then
        info.rank = rank
      elseif req:find(" %- ") then
        info.rep = true
        local faction, standing = req:match("^(.-) %- (.+)$")
        info.repFaction = faction
        for i = 1, 8 do
          if _G["FACTION_STANDING_LABEL" .. i] == standing then info.repStanding = i end
        end
      end
    end
  end
  cache[itemID] = info
  return info
end

-- Your standing with a faction (1 Hated .. 8 Exalted), by name; nil when unknown. The
-- reputation list hides factions under collapsed headers, so they are opened for the read
-- and closed again.
local repCache
function ns.RepStanding(factionName)
  if not repCache then
    repCache = {}
    local R = C_Reputation
    local count = (R and R.GetNumFactions) or GetNumFactions
    local expand = (R and R.ExpandFactionHeader) or ExpandFactionHeader
    local collapse = (R and R.CollapseFactionHeader) or CollapseFactionHeader
    local function entry(i)
      local d = R and R.GetFactionDataByIndex and R.GetFactionDataByIndex(i)
      if d then return d.name, d.reaction or d.standingID, d.isHeader, d.isCollapsed end
      local name, _, standing, _, _, _, _, _, isHeader, isCollapsed = GetFactionInfo(i)
      return name, standing, isHeader, isCollapsed
    end
    if count then
      local opened = {}
      local i = 1
      while i <= count() do
        local name, _, isHeader, isCollapsed = entry(i)
        if isHeader and isCollapsed and expand then
          expand(i)
          opened[#opened + 1] = name
        end
        i = i + 1
      end
      for j = 1, count() do
        local name, standing, isHeader = entry(j)
        if name and standing and not isHeader then repCache[name] = standing end
      end
      for _, hname in ipairs(opened) do -- close what we opened, last first so indexes hold
        for j = count(), 1, -1 do
          local name, _, isHeader = entry(j)
          if isHeader and name == hname and collapse then collapse(j) break end
        end
      end
    end
  end
  return repCache[factionName]
end

local repEv = CreateFrame("Frame")
repEv:RegisterEvent("UPDATE_FACTION")
repEv:SetScript("OnEvent", function() repCache = nil end)
