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
local buyList, sellList, mode = {}, {}, "buy" -- list is whichever the tab shows
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

local computeSell -- below

local function compute()
  buyList = {}
  local plan = ns.CurrentPlan()
  if not plan then list = buyList; sellList = {}; return end
  for _, it in ipairs(plan.shop) do
    local index, price, stack, avail = findIndex(it.item)
    if index then
      local unit = price / stack
      local cheaper = it.src == "ah" and it.unit and unit > it.unit + 0.001 -- the AH beats this vendor
      local have = effectiveHave(it.item)
      buyList[#buyList + 1] = { item = it.item, need = it.count, have = have, buy = math.max(0, it.count - have),
        stack = stack, price = price, unit = unit, cheaper = cheaper, avail = avail }
    end
  end
  local function rank(r) return r.buy > 0 and not r.cheaper and 1 or (r.buy > 0 and 2 or 3) end
  for i, r in ipairs(buyList) do r.i = i end
  table.sort(buyList, function(a, b)
    if rank(a) ~= rank(b) then return rank(a) < rank(b) end
    return a.i < b.i
  end)
  computeSell(plan)
  list = mode == "sell" and sellList or buyList
end

---------------------------------------------------------------------------
-- Selling the route's crafted items
---------------------------------------------------------------------------

-- The route's crafted items sitting in your bags. Never an item a later step or the shopping
-- list uses as a reagent (that would sell your own materials).
computeSell = function(plan)
  sellList = {}
  local reagent = {}
  for _, seg in ipairs(plan.segs) do
    if not seg.gap then
      for _, rg in ipairs(seg.row.r.reagents) do reagent[rg.item] = true end
    end
  end
  for _, it in ipairs(plan.shop) do reagent[it.item] = true end
  local seen = {}
  for _, seg in ipairs(plan.segs) do
    local r = not seg.gap and seg.row.r
    if r and r.out and not reagent[r.out] then
      local row = seen[r.out]
      if not row then
        local count = (C_Item.GetItemCount and C_Item.GetItemCount(r.out, false)) or 0 -- bags only
        local unit = ns.VendorSell(r.out)
        if count > 0 and unit and unit > 0 then
          -- the AH figure already has the cut and the expected lost deposit taken off (Prices.lua)
          local ahNet = ns.AHNetPerUnit(r.out)
          row = { item = r.out, sell = true, count = count, unit = unit, value = count * unit, steps = {},
            ahNet = ahNet, ahBetter = not ns.Opt("sellAllVendor") and ahNet ~= nil and ahNet > unit }
          seen[r.out] = row
          sellList[#sellList + 1] = row
        end
      end
      if row then row.steps[#row.steps + 1] = ("%d-%d"):format(seg.from, seg.to) end
    end
  end
end

local sellBusy = false

local function bagUnits(items)
  local n = 0
  for item in pairs(items) do
    n = n + ((C_Item.GetItemCount and C_Item.GetItemCount(item, false)) or 0)
  end
  return n
end

local function doSell(rows)
  if sellBusy then return end
  local slots, wanted = {}, {}
  for _, r in ipairs(rows) do wanted[r.item] = true end
  local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
  for bag = 0, lastBag do
    local n = (C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0
    for slot = 1, n do
      local info = C_Container.GetContainerItemInfo(bag, slot)
      if info and wanted[info.itemID] and not info.isLocked then
        slots[#slots + 1] = { bag = bag, slot = slot, item = info.itemID }
      end
    end
  end
  if #slots == 0 then
    ns.Print("Found nothing to sell in your bags (are the stacks locked or in the bank?).")
    return
  end
  local before = bagUnits(wanted)
  ns.Print(("Selling %d stacks (%d items)..."):format(#slots, before))
  sellBusy = true
  forbidden = false
  local i = 0
  local function finishUp()
    C_Timer.After(0.6, function()
      sellBusy = false
      local sold = before - bagUnits(wanted)
      if sold > 0 then
        ns.Print(("Sold %d crafted items."):format(sold))
      elseif forbidden then
        ns.Print("The game blocked selling from an addon here, so nothing was sold. Right-click the items to sell them yourself.")
      else
        ns.Print("Nothing was sold. Is the vendor window still open? /margin debug shows more.")
      end
      ns.RefreshMerchant()
    end)
  end
  local function step()
    i = i + 1
    local t = slots[i]
    if not t or forbidden or not (MerchantFrame and MerchantFrame:IsShown()) then return finishUp() end
    -- re-read the slot: only sell it if it still holds the item we meant
    local info = C_Container.GetContainerItemInfo(t.bag, t.slot)
    if info and info.itemID == t.item and not info.isLocked then
      local ok, err = pcall(C_Container.UseContainerItem, t.bag, t.slot) -- with a vendor open this sells the stack
      if not ok then ns.Print("Selling failed:", tostring(err)); return finishUp() end
      if MarginDB.debug then ns.Print("[sell]", t.bag, t.slot, t.item, "stack", info.stackCount) end
    end
    C_Timer.After(0.12, step)
  end
  step()
end

-- Two-step confirm without the game's popup: the first click arms the button, a second within a
-- few seconds sells. `armed` is the row (or "all") waiting for it.
local armed
local function arm(key, rows, label)
  if armed and armed.key == key then
    armed = nil
    doSell(rows)
    return ns.RefreshMerchant()
  end
  armed = { key = key, label = label }
  C_Timer.After(6, function()
    if armed and armed.key == key then armed = nil; ns.RefreshMerchant() end
  end)
  ns.RefreshMerchant()
end

local function sellTotals(rows)
  local n, v = 0, 0
  for _, r in ipairs(rows) do n = n + r.count; v = v + r.value end
  return n, v
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
  for _, r in ipairs(buyList) do if buyable(r) then rows[#rows + 1] = r end end
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
  frame:SetSize(WIDTH, 134 + ROWS * ROW_H)
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
  local function tabButton(x, text, m)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(80, 20)
    b:SetPoint("TOPLEFT", x, -28)
    b:SetText(text)
    b:SetScript("OnClick", function() mode = m; offset = 0; armed = nil; ns.RefreshMerchant() end)
    return b
  end
  frame.tBuy = tabButton(12, "Buy", "buy")
  frame.tSell = tabButton(96, "Sell", "sell")

  frame.skipAH = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  frame.skipAH:SetSize(22, 22)
  frame.skipAH:SetPoint("TOPLEFT", 186, -27)
  frame.skipAH.text:SetText("Don't bother with the AH")
  frame.skipAH.text:SetFontObject("GameFontNormalSmall")
  frame.skipAH:SetScript("OnClick", function(self)
    ns.SetOpt("sellAllVendor", self:GetChecked() and true or false)
    ns.RefreshMerchant()
  end)
  frame.skipAH:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine("Sell everything to the vendor")
    GameTooltip:AddLine("Off: items the AH would pay more for (after the cut and the deposit you lose when a listing does not sell) are left out of \"Sell all\".", 1, 1, 1, true)
    GameTooltip:AddLine("On: sell them all to the vendor anyway.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  frame.skipAH:SetScript("OnLeave", GameTooltip_Hide)

  frame.info:SetPoint("TOPLEFT", 14, -54)
  frame.info:SetWidth(WIDTH - 28)
  frame.info:SetJustifyH("LEFT")
  frame.info:SetWordWrap(false)

  frame.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 24, ROW_H)
    row:SetPoint("TOPLEFT", 12, -74 - (i - 1) * ROW_H)
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
    row.buy:SetScript("OnClick", function()
      local d = row.data
      if not d then return end
      if d.sell then arm(d.item, { d }) else buyOne(d) end -- keyed by item: the rows are rebuilt on every refresh
    end)
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
  frame.all:SetScript("OnClick", function()
    if mode == "sell" then
      local rows = {}
      for _, r in ipairs(sellList) do if not r.ahBetter then rows[#rows + 1] = r end end
      if #rows > 0 then arm("all", rows) end
    else
      buyAll()
    end
  end)

  frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.note:SetPoint("BOTTOMLEFT", 14, 10)
  frame.note:SetWidth(WIDTH - 28)
  frame.note:SetJustifyH("LEFT")
end

function ns.RefreshMerchant()
  if not (frame and frame:IsShown()) then return end
  compute()
  frame.tBuy:SetEnabled(mode ~= "buy")
  frame.tSell:SetEnabled(mode ~= "sell")
  frame.skipAH:SetShown(mode == "sell")
  frame.skipAH:SetChecked(ns.Opt("sellAllVendor") and true or false)
  local cost, any = 0, false
  if mode == "buy" then
    for _, r in ipairs(buyList) do
      if buyable(r) then any = true; cost = cost + lotsFor(r) * r.price end
    end
    frame.info:SetText(any and ("Still to buy here: %s   (you have %s)"):format(ns.Money(cost), ns.Money(GetMoney()))
      or "Nothing more to buy here for your route.")
  else
    local value = 0
    for _, r in ipairs(sellList) do
      if not r.ahBetter then any = true; value = value + r.value end
    end
    frame.info:SetText(#sellList > 0 and ("Crafted items in your bags: %s at this vendor"):format(ns.Money(value))
      or "No crafted items from your route in your bags.")
  end
  offset = math.max(0, math.min(offset, math.max(0, #list - ROWS)))
  for i = 1, ROWS do
    local row, r = frame.rows[i], list[i + offset]
    row.data = r
    if r then
      row.icon:SetTexture(C_Item.GetItemIconByID(r.item))
      local n = C_Item.GetItemNameByID(r.item)
      if not n then C_Item.RequestLoadItemDataByID(r.item) end
      row.name:SetText(n or ("item " .. r.item))
      if r.sell then
        row.sub:SetText(("%d in bags  -  %s  (step %s)%s"):format(r.count, ns.Money(r.value), table.concat(r.steps, ", "),
          r.ahBetter and ("  |cffffd070AH ~%s each|r"):format(ns.Money(r.ahNet)) or ""))
        row.name:SetTextColor(1, 1, 1)
        row.buy:SetShown(true)
        row.buy:SetText(armed and armed.key == r.item and ("Sure? %d"):format(r.count) or ("Sell %d"):format(r.count))
        row.buy:SetEnabled(not sellBusy)
      elseif r.cheaper then
        row.sub:SetText("|cffffd070the AH is cheaper|r")
        row.name:SetTextColor(0.7, 0.7, 0.7)
        row.buy:SetShown(false)
      elseif r.buy == 0 then
        row.sub:SetText(("need %d, you have %d"):format(r.need, r.have))
        row.name:SetTextColor(0.5, 0.8, 0.5)
        row.buy:SetShown(false)
      else
        row.sub:SetText(("need %d, have %d  -  %s"):format(r.need, r.have, ns.Money(lotsFor(r) * r.price)))
        row.name:SetTextColor(1, 1, 1)
        row.buy:SetShown(buyable(r))
        row.buy:SetText(("Buy %d"):format(r.buy))
        row.buy:SetEnabled(not busy)
      end
      row:Show()
    else
      row:Hide()
    end
  end
  frame.all:SetShown(any)
  if mode == "sell" then
    frame.all:SetEnabled(any and not sellBusy)
    local allRows = {}
    for _, r in ipairs(sellList) do if not r.ahBetter then allRows[#allRows + 1] = r end end
    local n, v = sellTotals(allRows)
    frame.all:SetText(sellBusy and "Selling..." or (armed and armed.key == "all"
      and ("Click again: sell %d items for %s"):format(n, ns.Money(v)) or "Sell all crafted items"))
    frame.note:SetText(any and "Click twice to confirm. Skips items the AH pays more for (unless you tick the box) and anything a later step uses." or "")
  else
    frame.all:SetEnabled(any and not busy)
    frame.all:SetText(busy and "Buying..." or (MarginDB.buyPerClick and "Buy next stack (click per stack)" or "Buy everything for the route"))
    frame.note:SetText(any and "Buys only what you still need; stops if bags are full or gold runs out." or "")
  end
end

-- Remember what this vendor charges per unit for plain-gold, unlimited items (feeds Prices.lua).
local function record()
  for i = 1, GetMerchantNumItems() do
    local price, stack, avail, purchasable, ext = merchantInfo(i)
    local id = GetMerchantItemID(i)
    if id and price and price > 0 and not ext and purchasable ~= false and (avail or -1) < 0 then
      ns.NoteVendorPrice(id, price / math.max(1, stack or 1))
    end
  end
end

local function showHere()
  record()
  if not ns.Opt("merchantList") then return end
  if not frame then build() end
  compute()
  local anyBuy, anySell = false, #sellList > 0
  for _, r in ipairs(buyList) do if buyable(r) then anyBuy = true end end
  if not (anyBuy or anySell) or frame:IsShown() then return end
  mode = anyBuy and "buy" or "sell"
  compute()
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
  elseif event == "MERCHANT_UPDATE" then
    record()
    ns.RefreshMerchant()
  elseif event == "MERCHANT_CLOSED" then
    issued, busy = {}, false
    if frame then frame:Hide() end
  else
    ns.RefreshMerchant()
  end
end)
