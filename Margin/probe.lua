-- Probe: finds out which tradeskill APIs Forever has and what Auctionator exposes.
-- Open a profession window (any), then /mgprobe, then /reload. Read WTF/.../SavedVariables/Margin.lua.
MarginDB = MarginDB or {}

local function has(name) return _G[name] ~= nil end

local function dump()
  local out = { time = date("%Y-%m-%d %H:%M:%S"), apis = {}, recipes = {} }
  for _, n in ipairs({
    "GetNumTradeSkills", "GetTradeSkillInfo", "GetTradeSkillLine", "GetTradeSkillItemLink",
    "GetTradeSkillNumReagents", "GetTradeSkillReagentInfo", "GetTradeSkillReagentItemLink",
    "GetTradeSkillNumMade", "ExpandTradeSkillSubClass", "GetTradeSkillRecipeLink",
    "GetNumCrafts", "GetCraftInfo", "GetProfessions", "GetProfessionInfo",
  }) do out.apis[n] = has(n) end
  out.apis["C_TradeSkillUI"] = C_TradeSkillUI ~= nil
  out.apis["C_TradeSkillUI.GetAllRecipeIDs"] = C_TradeSkillUI and C_TradeSkillUI.GetAllRecipeIDs ~= nil
  out.apis["C_TradeSkillUI.GetRecipeInfo"] = C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo ~= nil
  out.apis["C_TradeSkillUI.GetRecipeSchematic"] = C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic ~= nil
  out.apis["C_Container.GetContainerItemInfo"] = C_Container and C_Container.GetContainerItemInfo ~= nil
  out.apis["C_Item.GetItemInfoInstant"] = C_Item and C_Item.GetItemInfoInstant ~= nil

  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  out.auctionator = {
    present = A ~= nil,
    vendorCache = AUCTIONATOR_VENDOR_PRICE_CACHE ~= nil,
  }
  if A then
    -- Linen Cloth 2589, Light Leather 2318, Copper Bar 2840, Mageweave 4338
    for _, id in ipairs({ 2589, 2318, 2840, 4338 }) do
      local ok1, ah = pcall(A.GetAuctionPriceByItemID, "Margin", id)
      local ok2, v = pcall(A.GetVendorPriceByItemID, "Margin", id)
      local ok3, age = pcall(A.GetAuctionAgeByItemID, "Margin", id)
      out.auctionator[id] = { ah = ok1 and ah or ("err:" .. tostring(ah)), vendor = ok2 and v or ("err:" .. tostring(v)), age = ok3 and age or nil }
    end
  end

  if has("GetNumTradeSkills") then
    out.skillLine = { GetTradeSkillLine() }
    local n = GetNumTradeSkills()
    out.numTradeSkills = n
    for i = 1, math.min(n, 60) do
      local r = { GetTradeSkillInfo(i) }
      local e = { idx = i, info = r }
      if r[2] ~= "header" then
        e.link = GetTradeSkillItemLink(i)
        e.made = { GetTradeSkillNumMade and GetTradeSkillNumMade(i) }
        e.reagents = {}
        for j = 1, (GetTradeSkillNumReagents(i) or 0) do
          local name, tex, count, have = GetTradeSkillReagentInfo(i, j)
          e.reagents[j] = { name = name, count = count, have = have, link = GetTradeSkillReagentItemLink(i, j) }
        end
      end
      out.recipes[#out.recipes + 1] = e
    end
  end
  return out
end

SLASH_MGPROBE1 = "/mgprobe"
SlashCmdList.MGPROBE = function()
  local ok, res = pcall(dump)
  MarginDB.probe = ok and res or { error = tostring(res) }
  print("|cff66ccffMargin|r probe saved. /reload to flush to disk.")
end
