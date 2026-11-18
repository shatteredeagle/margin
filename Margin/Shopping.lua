local _, ns = ...

-- The shopping list beside the auction house: what the route still needs after your
-- bags and bank, each with a Search that opens the item in the game's own buy view
-- with the count filled in (buying stays your click). Same approach as Polestar's
-- auction house buys: select the browse result, then send the quantity event once
-- the listings arrive.

local W, T = ns.W, ns.T
local WIDTH, HEIGHT = 360, 420
local frame, list = nil, {}
local searching = {} -- item -> count to fill in when its listings arrive
local keyWait        -- item whose auction key the client is still loading

local function readable(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function ahOpen()
  local F = AuctionHouseFrame
  return F and F.IsShown and F:IsShown() and C_AuctionHouse and C_AuctionHouse.MakeItemKey and true or false
end

local function owned(item)
  local f = (C_Item and C_Item.GetItemCount) or GetItemCount
  return f(item, true) or 0 -- bags and bank
end

-- Purchases the AH has confirmed but that have not reached the bags yet (the modern AH
-- delivers by mail). MarginDB.credits[item] = { base = bag count when bought, units, t }.
-- Counted as owned until the bags catch up, so a bought item is ticked off at once.
local WEEK = 7 * 86400
function ns.Transit(item)
  local c = MarginDB.credits and MarginDB.credits[item]
  if not c then return 0 end
  local have = owned(item)
  if have >= c.base + c.units or time() - c.t > WEEK then
    MarginDB.credits[item] = nil
    return 0
  end
  return c.base + c.units - have
end

local function credit(item, units)
  MarginDB.credits = MarginDB.credits or {}
  local c = MarginDB.credits[item]
  if c and ns.Transit(item) > 0 then
    c.units = c.units + units
    c.t = time()
  else
    MarginDB.credits[item] = { base = owned(item), units = units, t = time() }
  end
end

local lastConfirm -- the commodity purchase the player just confirmed: { item, qty, t }
if C_AuctionHouse and C_AuctionHouse.ConfirmCommoditiesPurchase then
  hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(item, qty)
    item, qty = readable(item), readable(qty)
    if type(item) == "number" and type(qty) == "number" then
      lastConfirm = { item = item, qty = qty, t = GetTime() }
    end
  end)
end

local function openItem(item)
  local AH = C_AuctionHouse
  local key = AH.MakeItemKey(item)
  if not AH.GetItemKeyInfo(key) then keyWait = item; return end
  keyWait = nil
  AuctionHouseFrame:SelectBrowseResult({ itemKey = key, minPrice = 0, totalQuantity = 0 })
end

-- The AH stays in an item's buy view (with its purchase pending) after a search, and
-- selecting another item from there never gets its listings. Blizzard's Back button
-- returns to browse mode first, so do that, then wait for the AH's search cooldown.
local pending -- { item, count }

local function debug(...)
  if MarginDB and MarginDB.debug then ns.Print("[ah]", ...) end
end

local function backToBrowse()
  local F, M = AuctionHouseFrame, AuctionHouseFrameDisplayMode
  if not (F and M and F.GetDisplayMode and F.SetDisplayMode) then return false end
  local mode = F:GetDisplayMode()
  debug("display mode", tostring(mode), "Buy", tostring(M.Buy), "CommoditiesBuy", tostring(M.CommoditiesBuy), "ItemBuy", tostring(M.ItemBuy))
  if mode == M.CommoditiesBuy or mode == M.ItemBuy then
    F:SetDisplayMode(M.Buy)
    return true
  end
  return false
end

local function throttleReady()
  local AH = C_AuctionHouse
  return not AH.IsThrottledMessageSystemReady or AH.IsThrottledMessageSystemReady()
end

local function go()
  if not pending then return end
  if not ahOpen() then pending = nil; return end
  if not throttleReady() then debug("waiting for the AH cooldown"); return end -- AUCTION_HOUSE_THROTTLED_SYSTEM_READY retries
  local p = pending
  pending = nil
  searching[p.item] = p.count
  debug("selecting item", p.item, "count", p.count)
  openItem(p.item)
end

local function search(item, count)
  if not (ahOpen() and AuctionHouseFrame.SelectBrowseResult) then return end
  pending = { item = item, count = count }
  local wentBack = backToBrowse()
  C_Timer.After(wentBack and 0.3 or 0, go)
end

-- Margin's own AH search for the items it cannot price: opens each item's buy view in turn
-- (the same way the Search buttons do), and the results events record the cheapest price.
-- Used when Auctionator is not installed.
local scanQ, scanning, scanToken, scanDone = {}, nil, nil, nil
local function nextScan()
  if scanning then return end
  local item = table.remove(scanQ, 1)
  if not item then
    ns.Print("AH search round finished.")
    if ns.InvalidatePlan then ns.InvalidatePlan() end
    if ns.RefreshUI then ns.RefreshUI() end
    local done = scanDone
    scanDone = nil
    if done then done() end
    return
  end
  local token = {}
  MarginDB.searched = MarginDB.searched or {}
  MarginDB.searched[item] = time()
  scanning, scanToken = item, token
  search(item, nil)
  C_Timer.After(6, function() -- an item with no listing may never answer
    if scanToken == token and scanning == item then scanning = nil; nextScan() end
  end)
end

function ns.ScanItems(ids, onDone)
  if not ahOpen() then ns.Print("Open the auction house first."); return end
  if #ids == 0 then ns.Print("Nothing to look up."); return end
  scanDone = onDone
  scanQ = {}
  for i, id in ipairs(ids) do scanQ[i] = id end
  scanning = nil
  nextScan()
end

local function scanArrived(item)
  if scanning == item then
    scanning = nil
    C_Timer.After(0.3, nextScan)
  end
end

-- Rows still to buy first (cheapest source is the AH or unknown), then vendor items, then done ones.
local function compute()
  list = {}
  local plan = ns.CurrentPlan()
  if not plan and not (ns.S.shopOnCraft and ns.S.shopCraft) then return 0 end
  local cost = 0
  for _, it in ipairs((ns.ShopOf(plan))) do
    local transit = ns.Transit(it.item)
    local have = owned(it.item) + transit
    local buy = math.max(0, it.count - have)
    local kind = buy == 0 and "done" or (it.src == "vendor" and "vendor" or "ah")
    local sup = (kind == "ah" and ns.Supply) and ns.Supply(it.item) or nil
    local cash = it.unit and it.unit * buy or nil
    if kind == "ah" and ns.WalkCost then
      local c = ns.WalkCost(it.item, buy)
      if c then cash = c end -- the listings walked cheapest first, not the lowest price times the count
    end
    list[#list + 1] = { item = it.item, need = it.count, have = have, buy = buy, unit = it.unit, kind = kind,
      transit = transit, sup = sup, short = (sup and buy > sup) and (buy - sup) or 0 }
    if cash then cost = cost + cash end
  end
  local rank = { ah = 1, vendor = 2, done = 3 }
  for i, r in ipairs(list) do r.i = i end
  table.sort(list, function(a, b)
    if a.kind ~= b.kind then return rank[a.kind] < rank[b.kind] end
    return a.i < b.i
  end)
  return cost
end

local GROUPS = { { "ah", "Auction house" }, { "vendor", "Vendor" }, { "done", "Done" } }

local function makeRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row.band = W.Solid(row, "panel2")
  row.band:SetAllPoints()
  row.bandLine = W.Solid(row, "border", "BORDER")
  row.bandLine:SetPoint("TOPLEFT"); row.bandLine:SetPoint("TOPRIGHT"); row.bandLine:SetHeight(1)
  row.title = W.Text(row, "small", "accent")
  row.title:SetPoint("LEFT", 8, 0)
  row.total = W.Text(row, "row", "text", "RIGHT")
  row.total:SetPoint("RIGHT", -8, 0)
  row.sep = W.Solid(row, "white", "BORDER", 0.035)
  row.sep:SetPoint("BOTTOMLEFT"); row.sep:SetPoint("BOTTOMRIGHT"); row.sep:SetHeight(1)
  row.btn = CreateFrame("Button", nil, row)
  row.btn:SetSize(28, 28)
  row.btn:SetPoint("LEFT", 8, 0)
  row.icon = row.btn:CreateTexture(nil, "ARTWORK")
  row.icon:SetAllPoints()
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  W.Tip(row.btn, function(tt)
    if not (row.entry and row.entry.item) then return false end
    tt:SetItemByID(row.entry.item)
  end, "ANCHOR_RIGHT")
  row.search = W.Button(row, { width = 84, height = 20, icon = "search", text = "Search",
    onClick = function() if row.entry and row.entry.item then search(row.entry.item, row.entry.buy) end end,
    tooltip = { "Search", "Opens the item in the auction house's buy view with the count filled in. Buying is your click." } })
  row.search:SetPoint("RIGHT", -8, 0)
  row.name = W.Text(row, "row", "text")
  row.name:SetPoint("TOPLEFT", row.btn, "TOPRIGHT", 8, -1)
  row.name:SetPoint("RIGHT", row.search, "LEFT", -6, 0)
  row.have = W.ProgressBar(row, { width = 56, height = 5, color = "profit" })
  row.have:SetPoint("BOTTOMLEFT", row.btn, "BOTTOMRIGHT", 8, 3)
  row.sub = W.Text(row, "label", "dim")
  row.sub:SetPoint("LEFT", row.have, "RIGHT", 6, 0)
  row.sub:SetPoint("RIGHT", row.search, "LEFT", -6, 0)
  row.note = W.Text(row, "label", "dim", "RIGHT")
  row.note:SetPoint("RIGHT", -10, 0)
  return row
end

local function fillRow(row, e)
  local band = e.kind == "section"
  row.band:SetShown(band); row.bandLine:SetShown(band); row.title:SetShown(band); row.total:SetShown(band)
  row.sep:SetShown(not band)
  for _, f in ipairs({ row.btn, row.name, row.have, row.sub }) do f:SetShown(not band) end
  if band then
    row.search:Hide(); row.note:Hide()
    row.title:SetText(e.title:upper() .. "  " .. T.C("dim", "(" .. e.count .. ")"))
    row.total:SetText(e.total and T.Money(e.total) or "")
    return
  end
  local d = e
  row.icon:SetTexture(C_Item.GetItemIconByID(d.item))
  local mail = d.transit > 0 and ("  " .. T.C("unlearned", ("(+%d on the way)"):format(d.transit))) or ""
  row.name:SetText(ns.ItemLabel(d.item) .. mail)
  W.TextColor(row.name, d.kind == "done" and "profit" or (d.kind == "vendor" and "dim" or "text"))
  row.have:SetValue(d.have, d.need)
  if d.kind == "done" then
    row.sub:SetText(("%d / %d"):format(d.have, d.need))
  else
    row.sub:SetText(("%d / %d · buy %d · %s each"):format(d.have, d.need, d.buy, T.Money(d.unit))
      .. (d.short > 0 and ("  " .. T.C("loss", ("only %d on the AH"):format(d.sup))) or ""))
  end
  row.search:SetShown(d.kind == "ah")
  row.search:SetText("Search " .. d.buy)
  row.search:SetEnabled(frame.open and true or false)
  row.note:SetShown(d.kind == "vendor")
  row.note:SetText("buy at a vendor")
end

local function build()
  frame = W.Window({ name = "MarginShopping", title = "Shopping list", width = WIDTH, height = HEIGHT, escape = false })
  frame:EnableMouseWheel(true)
  local head = W.Panel(frame, "panel", false)
  head:SetPoint("TOPLEFT", 1, -frame.top)
  head:SetPoint("TOPRIGHT", -1, -frame.top)
  head:SetHeight(26)
  head.line = W.Solid(head, "border", "BORDER")
  head.line:SetPoint("BOTTOMLEFT"); head.line:SetPoint("BOTTOMRIGHT"); head.line:SetHeight(1)
  frame.info = W.Text(head, "small", "text")
  frame.info:SetPoint("LEFT", 10, 0)
  frame.step = W.Button(head, { width = 130, height = 20, text = "Whole route",
    onClick = function()
      local plan = ns.CurrentPlan()
      if plan or ns.S.shopCraft then ns.CycleShopStep(plan or { segs = {} }) end -- (the craft plan works without a route)
      ns.RefreshUI()
    end,
    tooltip = { "Shop for one step", "Cannot afford everything at once? Pick a step to see only what it needs: buy that, craft, sell, then pick the next step. Click again to move on; after the last step it shows the whole route." } })
  frame.step:SetPoint("RIGHT", -6, 0)
  frame.left = W.Text(head, "small", "text", "RIGHT")
  frame.left:SetPoint("RIGHT", frame.step, "LEFT", -8, 0)
  frame.list = W.ScrollList(frame, { width = WIDTH - 10, height = HEIGHT - frame.top - 26 - 30,
    makeRow = makeRow, fill = fillRow,
    heightOf = function(e) return e.kind == "section" and 22 or 38 end })
  frame.list:SetPoint("TOPLEFT", 5, -(frame.top + 27))
  frame:SetScript("OnMouseWheel", function(_, d) frame.list.Wheel(nil, d) end)
  local foot = W.Panel(frame, "panel", false)
  foot:SetPoint("BOTTOMLEFT", 1, 1); foot:SetPoint("BOTTOMRIGHT", -1, 1); foot:SetHeight(24)
  foot.line = W.Solid(foot, "border", "BORDER")
  foot.line:SetPoint("TOPLEFT"); foot.line:SetPoint("TOPRIGHT"); foot.line:SetHeight(1)
  frame.note = W.Text(foot, "label", "dim")
  frame.note:SetPoint("LEFT", 10, 0)
end

local function wantOpen() -- anything left to buy at the AH?
  for _, r in ipairs(list) do if r.kind == "ah" then return true end end
  return false
end

function ns.RefreshShopping()
  if not (frame and frame:IsShown()) then return end
  local cost = compute()
  frame.open = ahOpen()
  local _, prof, name, target = ns.CurrentPlan()
  frame.info:SetText(prof and ("%s %s to %s"):format(name, T.C("accent", prof.skill), T.C("accent", target))
    or "Open a profession window once to scan it.")
  frame.left:SetText(prof and (T.C("dim", "still to buy ") .. T.Money(cost)) or "")
  do
    local plan = ns.CurrentPlan()
    local _, seg, craft = ns.ShopOf(plan)
    frame.step.label:SetText(craft and "Craft plan" or seg and ("Step %d-%d"):format(seg.from, seg.to) or "Whole route")
  end
  frame.note:SetText(frame.open and "Search fills in the count; buying is your click."
    or "Open the auction house to search.")
  -- grouped: auction house, vendor, done; each with a band and its total
  local entries = {}
  for _, g in ipairs(GROUPS) do
    local rows, total = {}, 0
    for _, r in ipairs(list) do
      if r.kind == g[1] then
        rows[#rows + 1] = r
        local c = r.unit and r.unit * r.buy or 0
        if r.kind == "ah" and ns.WalkCost then c = ns.WalkCost(r.item, r.buy) or c end
        total = total + c
      end
    end
    if #rows > 0 then
      entries[#entries + 1] = { kind = "section", title = g[2], count = #rows, total = g[1] ~= "done" and total or nil }
      for _, r in ipairs(rows) do entries[#entries + 1] = r end
    end
  end
  frame.list:SetEntries(entries)
end

function ns.ToggleShopping(forceShow)
  if not frame then build() end
  if frame:IsShown() and not forceShow then frame:Hide(); return end
  if frame:IsShown() then return ns.RefreshShopping() end
  if ahOpen() then
    frame:SetParent(AuctionHouseFrame)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
  else
    frame:SetParent(UIParent)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
  end
  frame:Show()
  ns.RefreshShopping()
end

local function showAtAH()
  if not ns.Opt("ahList") then return end
  if not frame then build() end
  compute()
  if wantOpen() and not frame:IsShown() then ns.ToggleShopping() end
end

---------------------------------------------------------------------------
-- Events: prefill the count, remember what searches show
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED",
  "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_KEY_ITEM_INFO_RECEIVED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED", "MAIL_INBOX_UPDATE", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
  ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, a)
  if event == "AUCTION_HOUSE_SHOW" then
    C_Timer.After(0.3, showAtAH)
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    go()
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    -- the purchase the player confirmed a moment ago went through: tick it off
    if lastConfirm and GetTime() - lastConfirm.t < 30 then
      credit(lastConfirm.item, lastConfirm.qty)
      if MarginDB.debug then ns.Print("[ah] bought", lastConfirm.qty, "of", lastConfirm.item) end
    end
    lastConfirm = nil
    ns.RefreshShopping()
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    lastConfirm = nil
  elseif event == "AUCTION_HOUSE_CLOSED" then
    searching, keyWait, pending, scanQ, scanning = {}, nil, nil, {}, nil
    if frame then frame:Hide() end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local item = readable(a)
    local AH = C_AuctionHouse
    if type(item) ~= "number" or not AH then return end
    local r = AH.GetCommoditySearchResultInfo(item, 1)
    if type(r) == "table" then ns.NoteAHPrice(item, readable(r.unitPrice)) end
    -- keep the cheapest listings too (how much is for sale, and what it costs to buy deeper)
    local count = readable(AH.GetNumCommoditySearchResults(item))
    if type(count) == "number" then
      local flat, limit = {}, math.min(count, 100)
      for i = 1, limit do
        local ri = AH.GetCommoditySearchResultInfo(item, i)
        local price, qty = type(ri) == "table" and readable(ri.unitPrice), type(ri) == "table" and readable(ri.quantity)
        if price and qty then flat[#flat + 1] = price; flat[#flat + 1] = qty end
      end
      ns.NoteDepth(item, flat, count > limit)
    end
    scanArrived(item)
    local want = searching[item]
    if not want then return end
    searching[item] = nil
    local M = AuctionHouseFrameMixin
    local qe = M and M.Event and M.Event.CommoditiesQuantitySelectionChanged
    if qe and AuctionHouseFrame and AuctionHouseFrame.TriggerEvent then
      C_Timer.After(0, function() if ahOpen() then AuctionHouseFrame:TriggerEvent(qe, want) end end)
    end
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    local key = a
    local item = type(key) == "table" and readable(key.itemID) or nil
    local AH = C_AuctionHouse
    if type(item) ~= "number" or not AH then return end
    searching[item] = nil -- gear and the like: no quantity to fill in
    local r = AH.GetItemSearchResultInfo(key, 1)
    if type(r) == "table" then
      local q = math.max(1, readable(r.quantity) or 1)
      local buyout = readable(r.buyoutAmount)
      if buyout then ns.NoteAHPrice(item, math.floor(buyout / q)) end
    end
    scanArrived(item)
  elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
    if keyWait and readable(a) == keyWait and ahOpen() then openItem(keyWait) end
  else
    ns.RefreshShopping()
  end
end)
