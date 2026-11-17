local _, ns = ...

-- The shopping list beside the auction house: what the route still needs after your
-- bags and bank, each with a Search that opens the item in the game's own buy view
-- with the count filled in (buying stays your click). Same approach as Polestar's
-- auction house buys: select the browse result, then send the quantity event once
-- the listings arrive.

local ROWS, ROW_H, WIDTH = 10, 36, 340
local frame, offset, list = nil, 0, {}
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

-- Rows still to buy first (cheapest source is the AH or unknown), then vendor items, then done ones.
local function compute()
  list = {}
  local plan = ns.CurrentPlan()
  if not plan then return 0 end
  local cost = 0
  for _, it in ipairs(plan.shop) do
    local have = owned(it.item)
    local buy = math.max(0, it.count - have)
    local kind = buy == 0 and "done" or (it.src == "vendor" and "vendor" or "ah")
    list[#list + 1] = { item = it.item, need = it.count, have = have, buy = buy, unit = it.unit, kind = kind }
    if it.unit then cost = cost + it.unit * buy end
  end
  local rank = { ah = 1, vendor = 2, done = 3 }
  for i, r in ipairs(list) do r.i = i end
  table.sort(list, function(a, b)
    if a.kind ~= b.kind then return rank[a.kind] < rank[b.kind] end
    return a.i < b.i
  end)
  return cost
end

local function build()
  frame = CreateFrame("Frame", "MarginShopping", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, 82 + ROWS * ROW_H)
  frame:SetFrameStrata("HIGH")
  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnMouseWheel", function(_, d)
    offset = math.max(0, math.min(math.max(0, #list - ROWS), offset - d * 2))
    ns.RefreshShopping()
  end)
  frame:Hide()
  frame.TitleText:SetText("Margin shopping list")

  frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.info:SetPoint("TOPLEFT", 14, -32)
  frame.info:SetWidth(WIDTH - 28)
  frame.info:SetJustifyH("LEFT")
  frame.info:SetWordWrap(false)

  frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.note:SetPoint("BOTTOMLEFT", 14, 10)
  frame.note:SetWidth(WIDTH - 28)
  frame.note:SetJustifyH("LEFT")

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
    row.search = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.search:SetSize(64, 22)
    row.search:SetPoint("RIGHT", 0, 0)
    row.search:SetText("Search")
    row.search:SetScript("OnClick", function() if row.data then search(row.data.item, row.data.buy) end end)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("TOPLEFT", row.btn, "TOPRIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row.search, "LEFT", -6, 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.sub = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.sub:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    row.sub:SetPoint("RIGHT", row.search, "LEFT", -6, 0)
    row.sub:SetJustifyH("LEFT")
    row.sub:SetWordWrap(false)
    frame.rows[i] = row
  end
end

local function wantOpen() -- anything left to buy at the AH?
  for _, r in ipairs(list) do if r.kind == "ah" then return true end end
  return false
end

function ns.RefreshShopping()
  if not (frame and frame:IsShown()) then return end
  local cost = compute()
  local open = ahOpen()
  local _, prof, name, target = ns.CurrentPlan()
  frame.info:SetText(prof and ("%s %d to %d  -  still to buy: %s"):format(name, prof.skill, target, ns.Money(cost))
    or "Open a profession window once to scan it.")
  frame.note:SetText(open and "Search fills in the count; buying is your click."
    or "Open the auction house to search.")
  offset = math.max(0, math.min(offset, math.max(0, #list - ROWS)))
  for i = 1, ROWS do
    local row, d = frame.rows[i], list[i + offset]
    row.data = d
    if d then
      row.icon:SetTexture(C_Item.GetItemIconByID(d.item))
      local n = C_Item.GetItemNameByID(d.item)
      if not n then C_Item.RequestLoadItemDataByID(d.item) end
      row.name:SetText(n or ("item " .. d.item))
      if d.kind == "done" then
        row.sub:SetText(("need %d, you have %d"):format(d.need, d.have))
        row.name:SetTextColor(0.5, 0.8, 0.5)
      else
        row.sub:SetText(("buy %d  (need %d, have %d)  %s each"):format(d.buy, d.need, d.have, ns.Money(d.unit)))
        row.name:SetTextColor(1, 1, 1)
      end
      row.search:SetShown(d.kind == "ah")
      row.search:SetEnabled(open)
      if d.kind == "vendor" then row.sub:SetText(row.sub:GetText() .. "  |cff80c0ffvendor|r") end
      row:Show()
    else
      row:Hide()
    end
  end
end

function ns.ToggleShopping()
  if not frame then build() end
  if frame:IsShown() then frame:Hide(); return end
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
  "ITEM_SEARCH_RESULTS_UPDATED", "ITEM_KEY_ITEM_INFO_RECEIVED", "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "BAG_UPDATE_DELAYED", "GET_ITEM_INFO_RECEIVED" }) do
  ev:RegisterEvent(e)
end
ev:SetScript("OnEvent", function(_, event, a)
  if event == "AUCTION_HOUSE_SHOW" then
    C_Timer.After(0.3, showAtAH)
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    go()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    searching, keyWait, pending = {}, nil, nil
    if frame then frame:Hide() end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    local item = readable(a)
    local AH = C_AuctionHouse
    if type(item) ~= "number" or not AH then return end
    local r = AH.GetCommoditySearchResultInfo(item, 1)
    if type(r) == "table" then ns.NoteAHPrice(item, readable(r.unitPrice)) end
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
  elseif event == "ITEM_KEY_ITEM_INFO_RECEIVED" then
    if keyWait and readable(a) == keyWait and ahOpen() then openItem(keyWait) end
  else
    ns.RefreshShopping()
  end
end)
