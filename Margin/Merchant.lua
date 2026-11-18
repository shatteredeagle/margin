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

local W, T = ns.W, ns.T
local WIDTH, HEIGHT = 360, 450
local frame, list = nil, {}
local buyList, sellList, mode = {}, {}, "buy" -- list is whichever the tab shows
local busy = false
local issued = {}     -- item -> { base, units, t }: bought, not yet visible in the bags
local forbidden = false
-- what went wrong (or right) last, shown as a banner in the window as well as in chat: { kind, text }
local notice

local function say(kind, text)
  notice = { kind = kind, text = text }
  ns.Print(text)
end

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
    say("warn", "Found nothing to sell in your bags (are the stacks locked or in the bank?).")
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
        say("ok", ("Sold %d crafted items."):format(sold))
      elseif forbidden then
        say("err", "The game blocked selling from an addon here, so nothing was sold. Right-click the items to sell them yourself.")
      else
        say("warn", "Nothing was sold. Is the vendor window still open? /margin debug shows more.")
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
      if not ok then say("err", "Selling failed: " .. tostring(err)); return finishUp() end
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

-- The buy call takes a number of ITEMS, in multiples of the bundle a vendor sells (Mild Spices and water
-- come 5 at a time: asking for 5 buys one bundle, asking for 1 buys one spice). Items sold singly are the
-- same thing. The first time a bundled item is bought it is bought one bundle at a time, so that if this
-- client turns out to count bundles instead, it is noticed (MarginDB.bundleLots) after at most one
-- bundle's worth of extra.
local function chunk(item, need)
  local index, price, stack, avail = findIndex(item)
  if not index then return nil, "not sold here" end
  local remaining = need - effectiveHave(item)
  if remaining <= 0 then return 0 end
  local lotsNeeded = math.ceil(remaining / stack)
  local maxUnits = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(index)) or stack
  local lotsPerCall = math.max(1, math.floor(maxUnits / stack))
  if stack > 1 and not MarginDB.bundleConfirmed then lotsPerCall = 1 end -- prove the unit first
  local lots = math.min(lotsNeeded, lotsPerCall)
  if avail >= 0 then lots = math.min(lots, avail) end
  lots = math.min(lots, math.floor(GetMoney() / price))
  if lots <= 0 then return nil, avail == 0 and "sold out" or "not enough gold" end
  local quantity = MarginDB.bundleLots and lots or lots * stack
  issued[item] = { base = owned(item), units = lots * stack, stack = stack, t = GetTime() }
  forbidden = false
  debug("buy", item, "lots", lots, "x", stack, "quantity", quantity, "index", index)
  BuyMerchantItem(index, quantity)
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
      if iss.stack > 1 and not MarginDB.bundleConfirmed then
        MarginDB.bundleConfirmed = true
        if got == iss.units * iss.stack then
          MarginDB.bundleLots = true -- this client counts bundles, not items
          ns.Print("Noted: this vendor's buy count is in bundles, so it is bought that way from now on.")
        end
      end
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
    say("err", "The game only allows one purchase per click here: click again for each stack.")
  elseif not ok then
    say("err", ("Stopped (%s)."):format(why or "?"))
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

local function setMode(m)
  mode, armed, notice = m, nil, nil
  if frame then frame.list.offset = 0 end
  ns.RefreshMerchant()
end

local function makeRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.sep = W.Solid(row, "white", "BORDER", 0.035)
  row.sep:SetPoint("BOTTOMLEFT"); row.sep:SetPoint("BOTTOMRIGHT"); row.sep:SetHeight(1)
  row.btn = CreateFrame("Button", nil, row)
  row.btn:SetSize(28, 28)
  row.btn:SetPoint("LEFT", 8, 0)
  row.icon = row.btn:CreateTexture(nil, "ARTWORK")
  row.icon:SetAllPoints()
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  W.Tip(row.btn, function(tt)
    if not row.entry then return false end
    tt:SetItemByID(row.entry.item)
  end, "ANCHOR_RIGHT")
  row.action = W.Button(row, { width = 84, height = 20, onClick = function()
    local d = row.entry
    if not d then return end
    notice = nil
    if d.sell then arm(d.item, { d }) else buyOne(d) end -- keyed by item: the rows are rebuilt on every refresh
  end })
  row.action:SetPoint("RIGHT", -8, 0)
  row.name = W.Text(row, "row", "text")
  row.name:SetPoint("TOPLEFT", row.btn, "TOPRIGHT", 8, -1)
  row.name:SetPoint("RIGHT", row.action, "LEFT", -6, 0)
  row.pill = W.Pill(row)
  row.sub = W.Text(row, "label", "dim")
  row.sub:SetPoint("BOTTOMLEFT", row.btn, "BOTTOMRIGHT", 8, 1)
  row.sub:SetPoint("RIGHT", row.action, "LEFT", -6, 0)
  return row
end

local function fillRow(row, r)
  row.icon:SetTexture(C_Item.GetItemIconByID(r.item))
  row.name:SetText(ns.ItemName(r.item))
  row.pill:Hide()
  row.action:SetArmed(false)
  if r.sell then
    row.sub:SetText(("%d in bags · %s · step %s"):format(r.count, T.Money(r.value), table.concat(r.steps, ", "))
      .. (r.ahBetter and ("  " .. T.C("warn", ("AH ~%s each"):format(T.Plain(r.ahNet)))) or ""))
    W.TextColor(row.name, "text")
    row.action:Show()
    local isArmed = armed and armed.key == r.item
    row.action:SetText(isArmed and ("Sure? %d"):format(r.count) or ("Sell %d"):format(r.count))
    row.action:SetArmed(isArmed)
    row.action:SetEnabled(not sellBusy)
  elseif r.cheaper then
    row.sub:SetText(("need %d, have %d"):format(r.need, r.have))
    W.TextColor(row.name, "dim")
    row.pill:SetKind("cheaper")
    row.pill:ClearAllPoints()
    row.pill:SetPoint("RIGHT", -10, 0)
    row.pill:Show()
    row.action:Hide()
  elseif r.buy == 0 then
    row.sub:SetText(("need %d, you have %d"):format(r.need, r.have))
    W.TextColor(row.name, "profit")
    row.pill:SetKind("done")
    row.pill:ClearAllPoints()
    row.pill:SetPoint("RIGHT", -10, 0)
    row.pill:Show()
    row.action:Hide()
  else
    row.sub:SetText(("need %d, have %d · %s"):format(r.need, r.have, T.Money(lotsFor(r) * r.price)))
    W.TextColor(row.name, "text")
    row.action:SetShown(buyable(r))
    row.action:SetText(("Buy %d"):format(r.buy))
    row.action:SetEnabled(not busy)
  end
end

local function build()
  frame = W.Window({ name = "MarginMerchant", title = "Margin: this vendor", width = WIDTH, height = HEIGHT, escape = false })
  frame:EnableMouseWheel(true)
  local top = frame.top
  frame.mode = W.Segmented(frame, { options = { { "buy", "Buy for the route" }, { "sell", "Sell crafted items" } },
    onChange = setMode })
  frame.mode:SetPoint("TOPLEFT", 10, -(top + 6))
  top = top + 32
  frame.info = W.Banner(frame, WIDTH - 2)
  frame.info:SetPoint("TOPLEFT", 1, -top)
  frame.list = W.ScrollList(frame, { width = WIDTH - 10, height = 200, makeRow = makeRow, fill = fillRow,
    heightOf = function() return 38 end })
  frame:SetScript("OnMouseWheel", function(_, d) frame.list.Wheel(nil, d) end)

  frame.err = W.Banner(frame, WIDTH - 2)
  frame.all = W.Button(frame, { width = WIDTH - 20, height = 24, primary = true, onClick = function()
    notice = nil
    if mode == "sell" then
      local rows = {}
      for _, r in ipairs(sellList) do if not r.ahBetter then rows[#rows + 1] = r end end
      if #rows > 0 then arm("all", rows) end
    else
      buyAll()
    end
  end })
  frame.all:SetPoint("BOTTOMLEFT", 10, 52)
  frame.skipAH = W.Checkbox(frame, { label = "Sell everything to the vendor",
    onChange = function(v) ns.SetOpt("sellAllVendor", v and true or false); ns.RefreshMerchant() end,
    tooltip = { "Sell everything to the vendor",
      "Off: items the AH would pay more for (after the cut and the deposit you lose when a listing does not sell) are left out of \"Sell all\".",
      "On: sell them all to the vendor anyway. Also in Settings." } })
  frame.skipAH:SetPoint("BOTTOMLEFT", 12, 32)
  frame.note = W.Text(frame, "label", "dim")
  frame.note:SetPoint("BOTTOMLEFT", 12, 10)
  frame.note:SetWidth(WIDTH - 24)
  frame.note:SetWordWrap(true)
end

function ns.RefreshMerchant()
  if not (frame and frame:IsShown()) then return end
  compute()
  frame.mode:SetValue(mode)
  frame.skipAH:SetShown(mode == "sell")
  frame.skipAH:SetChecked(ns.Opt("sellAllVendor"))
  local cost, any = 0, false
  local info
  if mode == "buy" then
    for _, r in ipairs(buyList) do
      if buyable(r) then any = true; cost = cost + lotsFor(r) * r.price end
    end
    info = any and ("Still to buy here %s   %s %s"):format(T.Money(cost), T.C("dim", "you have"), T.Money(GetMoney()))
      or "Nothing more to buy here for your route."
  else
    local value = 0
    for _, r in ipairs(sellList) do
      if not r.ahBetter then any = true; value = value + r.value end
    end
    info = #sellList > 0 and ("Crafted items in your bags: %s at this vendor"):format(T.Money(value))
      or "No crafted items from your route in your bags."
  end
  local top = frame.top + 32
  local ih = frame.info:SetMessage("info", info)
  local errH = 0
  local bottom = 84 -- the button, the checkbox and the note
  frame.list:ClearAllPoints()
  frame.list:SetPoint("TOPLEFT", 5, -(top + ih))
  if notice then
    frame.err:SetPoint("BOTTOMLEFT", 1, bottom)
    errH = frame.err:SetMessage(notice.kind, notice.text)
  else
    frame.err:Hide()
  end
  frame.list:SetViewHeight(HEIGHT - (top + ih) - bottom - errH - 4)
  frame.list:SetEntries(list)
  frame.all:SetShown(any)
  frame.all:SetArmed(false)
  if mode == "sell" then
    frame.all:SetEnabled(any and not sellBusy)
    local allRows = {}
    for _, r in ipairs(sellList) do if not r.ahBetter then allRows[#allRows + 1] = r end end
    local n, v = sellTotals(allRows)
    local isArmed = armed and armed.key == "all"
    frame.all:SetText(sellBusy and "Selling..." or (isArmed
      and ("Click again: sell %d items for %s"):format(n, T.Plain(v)) or "Sell all crafted items"))
    frame.all:SetArmed(isArmed and not sellBusy)
    frame.note:SetText(any and "Two clicks to confirm. Skips items the AH pays more for (unless you tick the box) and anything a later step uses." or "")
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
  mode, notice = anyBuy and "buy" or "sell", nil
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
    issued, busy, notice = {}, false, nil
    if frame then frame:Hide() end
  else
    ns.RefreshMerchant()
  end
end)
