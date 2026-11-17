local _, ns = ...

-- Popup beside a vendor: the route's shopping-list items this vendor sells, with
-- one button to buy what is still missing (after your bags and bank).
--
-- Overbuy guard: every chunk is sized from need - (what the bags hold, or what an
-- unconfirmed purchase will bring), the next chunk waits until the bags show the
-- last one, and a stalled purchase stops the run. Quantities above the vendor's
-- per-call limit (GetMerchantItemMaxStack) are bought in several calls. If the
-- client refuses purchases made from a timer (ADDON_ACTION_FORBIDDEN), Margin
-- switches to one chunk per click and remembers it (MarginDB.buyPerClick).

local ROWS, ROW_H, WIDTH = 8, 38, 350
local frame, offset, list = nil, 0, {}
local busy = false
local issued = {}     -- item -> { base, units, t }: bought, not yet visible in the bags
local forbidden = false

local function debug(...)
  if MarginDB and MarginDB.debug then ns.Print("[buy]", ...) end
end

local function owned(item)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  return f(item, true) or 0
end

-- What the bags hold, counting an unconfirmed purchase as already arrived.
local function effectiveHave(item)
  local h = owned(item) + (ns.Transit and ns.Transit(item) or 0)
  local i = issued[item]
  if i and GetTime() - i.t < 3 and h < i.base + i.units then return i.base + i.units end
  return h
end

local function merchantInfo(i)
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local t = C_MerchantFrame.GetItemInfo(i)
    if type(t) == "table" then
      return t.price, t.stackCount, t.numAvailable, t.isPurchasable, t.hasExtendedCost
    end
  end
  if GetMerchantItemInfo then
    local name, _, price, stack, avail, purchasable, _, ext = GetMerchantItemInfo(i)
    if name then return price, stack, avail, purchasable, ext end
  end
end

-- Merchant slot of an item for plain gold: index, price per lot, units per lot, stock (-1 unlimited).
local function findIndex(item)
  for i = 1, GetMerchantNumItems() do
    if GetMerchantItemID(i) == item then
      local price, stack, avail, purchasable, ext = merchantInfo(i)
      if price and not ext and purchasable ~= false then
        return i, price, math.max(1, stack or 1), avail or -1
      end
    end
  end
end

local function compute()
  list = {}
  local plan = ns.CurrentPlan()
  if not plan then return end
  for _, it in ipairs(plan.shop) do
    local index, price, stack, avail = findIndex(it.item)
    if index then
      local unit = price / stack
      local cheaper = it.src == "ah" and it.unit and unit > it.unit + 0.001 -- the AH beats this vendor
      local have = effectiveHave(it.item)
      list[#list + 1] = { item = it.item, need = it.count, have = have, buy = math.max(0, it.count - have),
        stack = stack, price = price, unit = unit, cheaper = cheaper, avail = avail }
    end
  end
  local function rank(r) return r.buy > 0 and not r.cheaper and 1 or (r.buy > 0 and 2 or 3) end
  for i, r in ipairs(list) do r.i = i end
  table.sort(list, function(a, b)
    if rank(a) ~= rank(b) then return rank(a) < rank(b) end
    return a.i < b.i
  end)
end

local function lotsFor(r) return math.ceil(r.buy / r.stack) end
local function buyable(r) return r.buy > 0 and not r.cheaper and not (r.avail == 0) end

---------------------------------------------------------------------------
-- Buying
---------------------------------------------------------------------------

local function chunk(item, need)
  local index, price, stack, avail = findIndex(item)
  if not index then return nil, "not sold here" end
  local remaining = need - effectiveHave(item)
  if remaining <= 0 then return 0 end
  local lotsNeeded = math.ceil(remaining / stack)
  local maxLots = 1
  if stack == 1 and GetMerchantItemMaxStack then maxLots = math.max(1, GetMerchantItemMaxStack(index) or 1) end
  local lots = math.min(lotsNeeded, maxLots)
  if avail >= 0 then lots = math.min(lots, avail) end
  lots = math.min(lots, math.floor(GetMoney() / price))
  if lots <= 0 then return nil, avail == 0 and "sold out" or "not enough gold" end
  issued[item] = { base = owned(item), units = lots * stack, t = GetTime() }
  forbidden = false
  debug("buy", item, "lots", lots, "x", stack, "index", index)
  BuyMerchantItem(index, lots)
  if forbidden then
    issued[item] = nil
    return nil, "blocked"
  end
  return lots * stack
end

-- Buys `need` of an item in as many chunks as it takes, each confirmed by the bags first.
-- done(ok, why, boughtUnits)
local function runItem(item, need, perClick, done, bought)
  bought = bought or 0
  local units, why = chunk(item, need)
  if not units then return done(false, why, bought) end
  if units == 0 then return done(true, nil, bought) end
  local started = GetTime()
  local function check()
    local iss = issued[item]
    if not iss then return done(false, "cancelled", bought) end
    local got = owned(item) - iss.base
    if got >= iss.units then
      issued[item] = nil
      bought = bought + iss.units
      if perClick or MarginDB.buyPerClick then return done(true, "chunk", bought) end
      return runItem(item, need, perClick, done, bought)
    elseif GetTime() - started > 2.5 then
      issued[item] = nil
      return done(false, got > 0 and "only part arrived" or "nothing arrived (bags full?)", bought + math.max(0, got))
    end
    C_Timer.After(0.1, check)
  end
  C_Timer.After(0.1, check)
end

local function finish(item, ok, why, bought)
  busy = false
  if why == "blocked" then
    MarginDB.buyPerClick = true
    ns.Print("The game only allows one purchase per click here: click again for each stack.")
  elseif not ok then
    ns.Print(("Stopped (%s)."):format(why or "?"))
  end
  if bought and bought > 0 then
    ns.Print(("Bought %d x %s."):format(bought, C_Item.GetItemNameByID(item) or item))
  end
  ns.RefreshMerchant()
end

-- Buys several rows one after another; stops at the first problem.
local function buyRows(rows)
  if busy or #rows == 0 then return end
  busy = true
  ns.RefreshMerchant()
  local function step(i)
    local r = rows[i]
    if not r then
      busy = false
      return ns.RefreshMerchant()
    end
    runItem(r.item, r.need, false, function(ok, why, bought)
      if bought and bought > 0 then
        ns.Print(("Bought %d x %s."):format(bought, C_Item.GetItemNameByID(r.item) or r.item))
      end
      if ok and why ~= "chunk" then return step(i + 1) end
      finish(r.item, ok, why, 0)
    end)
  end
  step(1)
end

local function buyOne(r)
  if busy then return end
  busy = true
  ns.RefreshMerchant()
  runItem(r.item, r.need, false, function(ok, why, bought) finish(r.item, ok, why, bought) end)
end

local function buyAll()
  local rows = {}
  for _, r in ipairs(list) do if buyable(r) then rows[#rows + 1] = r end end
  if MarginDB.buyPerClick then -- one chunk per click: the first row that still needs some
    if rows[1] then buyOne(rows[1]) end
    return
  end
  buyRows(rows)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function build()
  frame = CreateFrame("Frame", "MarginMerchant", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, 112 + ROWS * ROW_H)
  frame:SetFrameStrata("HIGH")
  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, d)
    offset = math.max(0, math.min(math.max(0, #list - ROWS), offset - d * 2))
    ns.RefreshMerchant()
  end)
  frame:Hide()
  frame.TitleText:SetText("Margin: buy for your route")

  frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.info:SetPoint("TOPLEFT", 14, -32)
  frame.info:SetWidth(WIDTH - 28)
  frame.info:SetJustifyH("LEFT")
  frame.info:SetWordWrap(false)

  frame.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 24, ROW_H)
    row:SetPoint("TOPLEFT", 12, -52 - (i - 1) * ROW_H)
    row.btn = CreateFrame("Button", nil, row)
    row.btn:SetSize(28, 28)
    row.btn:SetPoint("LEFT", 0, 0)
    row.icon = row.btn:CreateTexture(nil, "ARTWORK")
    row.icon:SetAllPoints()
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.btn:SetScript("OnEnter", function(self)
      if not row.data then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(row.data.item)
      GameTooltip:Show()
    end)
    row.btn:SetScript("OnLeave", GameTooltip_Hide)
    row.buy = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.buy:SetSize(78, 22)
    row.buy:SetPoint("RIGHT", 0, 0)
    row.buy:SetScript("OnClick", function() if row.data then buyOne(row.data) end end)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.btn, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.buy, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row.buy, "LEFT", -6, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    frame.rows[i] = row
  end

  frame.all = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.all:SetSize(WIDTH - 28, 26)
  frame.all:SetPoint("BOTTOM", 0, 30)
  frame.all:SetScript("OnClick", buyAll)

  frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.note:SetPoint("BOTTOMLEFT", 14, 10)
  frame.note:SetWidth(WIDTH - 28)
  frame.note:SetJustifyH("LEFT")
end

function ns.RefreshMerchant()
  if not (frame and frame:IsShown()) then return end
  compute()
  local cost, any = 0, false
  for _, r in ipairs(list) do
    if buyable(r) then any = true; cost = cost + lotsFor(r) * r.price end
  end
  local gold = GetMoney()
  frame.info:SetText(any and ("Still to buy here: %s   (you have %s)"):format(ns.Money(cost), ns.Money(gold))
    or "Nothing more to buy here for your route.")
  offset = math.max(0, math.min(offset, math.max(0, #list - ROWS)))
  for i = 1, ROWS do
    local row, r = frame.rows[i], list[i + offset]
    row.data = r
    if r then
      row.icon:SetTexture(C_Item.GetItemIconByID(r.item))
      local n = C_Item.GetItemNameByID(r.item)
      if not n then C_Item.RequestLoadItemDataByID(r.item) end
      row.name:SetText(n or ("item " .. r.item))
      if r.cheaper then
        row.sub:SetText("|cffffd070the AH is cheaper|r")
        row.name:SetTextColor(0.7, 0.7, 0.7)
      elseif r.buy == 0 then
        row.sub:SetText(("need %d, you have %d"):format(r.need, r.have))
        row.name:SetTextColor(0.5, 0.8, 0.5)
      else
        row.sub:SetText(("need %d, have %d  -  %s"):format(r.need, r.have, ns.Money(lotsFor(r) * r.price)))
        row.name:SetTextColor(1, 1, 1)
      end
      row.buy:SetShown(buyable(r))
      row.buy:SetText(("Buy %d"):format(r.buy))
      row.buy:SetEnabled(not busy)
      row:Show()
    else
      row:Hide()
    end
  end
  frame.all:SetShown(any)
  frame.all:SetEnabled(any and not busy)
  frame.all:SetText(busy and "Buying..." or (MarginDB.buyPerClick and "Buy next stack (click per stack)" or "Buy everything for the route"))
  frame.note:SetText(any and "Buys only what you still need; stops if bags are full or gold runs out." or "")
end

local function showHere()
  if not ns.Opt("merchantList") then return end
  if not frame then build() end
  compute()
  local any = false
  for _, r in ipairs(list) do if buyable(r) then any = true end end
  if not any or frame:IsShown() then return end
  frame:SetParent(MerchantFrame)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
  frame:Show()
  ns.RefreshMerchant()
end

function ns.ToggleMerchant()
  if not (MerchantFrame and MerchantFrame:IsShown()) then ns.Print("Open a vendor first."); return end
  if not frame then build() end
  if frame:IsShown() then frame:Hide(); return end
  frame:SetParent(MerchantFrame)
  frame:ClearAllPoints()
  frame:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 4, 0)
  frame:Show()
  ns.RefreshMerchant()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "MERCHANT_SHOW", "MERCHANT_CLOSED", "MERCHANT_UPDATE", "BAG_UPDATE_DELAYED",
  "PLAYER_MONEY", "ADDON_ACTION_FORBIDDEN" }) do
  ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, a)
  if event == "ADDON_ACTION_FORBIDDEN" then
    if a == "Margin" then forbidden = true end
  elseif event == "MERCHANT_SHOW" then
    C_Timer.After(0.3, showHere)
  elseif event == "MERCHANT_CLOSED" then
    issued, busy = {}, false
    if frame then frame:Hide() end
  else
    ns.RefreshMerchant()
  end
end)
