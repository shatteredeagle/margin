local _, ns = ...

-- A button on the auction house that searches only the items Margin cannot price yet (no
-- full scan): through Auctionator when it is installed, else with Margin's own search. Shift-click also searches unpriced results.
local button

-- Most items looked up per click: Auctionator's search and the AH's own throttling both slow down
-- badly with hundreds of terms, so a long list is worked through in rounds.
local ROUND = 60

-- The profession the lookup is limited to (nil: all of them), if it is still one of yours.
local function scanProfession()
  local name = ns.Opt("scanProf")
  return name and ns.Char().profs[name] and name or nil
end

local function missing(includeOutputs)
  return ns.MissingItems(ns.Char().profs, includeOutputs, ns.Opt("useTrainer"), ns.Opt("profitScope") == "all",
    scanProfession())
end

local function updateText()
  if not button then return end
  button:SetText(("Margin: %d unpriced"):format(#missing(false)))
end

local function markSearched(ids)
  MarginDB.searched = MarginDB.searched or {}
  local now = time()
  for _, id in ipairs(ids) do MarginDB.searched[id] = now end
  -- results arrive a little later; recount then
  C_Timer.After(4, updateText)
  C_Timer.After(15, updateText)
end

local function search(includeOutputs)
  local ids = missing(includeOutputs)
  if #ids > ROUND then
    local rest = #ids - ROUND
    for i = #ids, ROUND + 1, -1 do ids[i] = nil end
    ns.Print(("%d items this round, %d more: click again after it finishes."):format(ROUND, rest))
  end
  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (A and A.MultiSearchExact) then
    markSearched(ids)
    ns.ScanItems(ids) -- no Auctionator: Margin looks the items up itself
    return
  end
  local names, loading = {}, 0
  for _, id in ipairs(ids) do
    local n = C_Item.GetItemNameByID(id)
    if n then names[#names + 1] = n else loading = loading + 1; C_Item.RequestLoadItemDataByID(id) end
  end
  if #names == 0 then
    ns.Print(loading > 0 and "Item names still loading, click again." or "Nothing to look up.")
    return
  end
  local ok, err = pcall(A.MultiSearchExact, "Margin", names)
  if not ok then ns.Print("Search failed:", tostring(err)); return end
  markSearched(ids)
  ns.Print(("Searching %d items%s."):format(#names, loading > 0 and (", " .. loading .. " names still loading") or ""))
end

local function build(parent)
  button = CreateFrame("Button", "MarginAHButton", parent, "UIPanelButtonTemplate")
  button:SetSize(170, 22)
  button:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -8, 2)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then
      MarginDB.searched = nil -- forget what was already searched
      updateText()
      return ns.Print("Forgot earlier searches; every unpriced item counts again.")
    end
    search(IsShiftKeyDown())
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Margin")
    GameTooltip:AddLine("Searches only the reagents Margin has no price for.", 1, 1, 1, true)
    GameTooltip:AddLine("Shift-click: also unpriced crafted results.", 0.7, 0.7, 0.7, true)
    local none = ns.SearchedUnpriced()
    if none > 0 then
      GameTooltip:AddLine(("%d searched in the last 12 hours have no listing and are not counted."):format(none), 1, 0.82, 0, true)
      GameTooltip:AddLine("Right-click: count them again.", 0.7, 0.7, 0.7, true)
    end
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
end

local scanButton
local function scanLabel()
  return "Scan: " .. (scanProfession() or "all")
end

local listButton
local function buildList(parent)
  listButton = CreateFrame("Button", "MarginAHListButton", parent, "UIPanelButtonTemplate")
  listButton:SetSize(110, 22)
  listButton:SetPoint("RIGHT", button, "LEFT", -4, 0)
  listButton:SetText("Shopping list")
  listButton:SetScript("OnClick", function() ns.ToggleShopping() end)

  -- which profession "Margin: N unpriced" looks up: all of them, or one
  scanButton = CreateFrame("Button", "MarginAHScanButton", parent, "UIPanelButtonTemplate")
  scanButton:SetSize(140, 22)
  scanButton:SetPoint("RIGHT", listButton, "LEFT", -4, 0)
  scanButton:SetText(scanLabel())
  scanButton:SetScript("OnClick", function()
    local names = {}
    for n in pairs(ns.Char().profs) do names[#names + 1] = n end
    table.sort(names)
    local cur, nxt = scanProfession(), nil
    if not cur then nxt = names[1] else
      for i, n in ipairs(names) do if n == cur then nxt = names[i + 1] end end
    end
    ns.SetOpt("scanProf", nxt) -- past the last one: back to all
    scanButton:SetText(scanLabel())
    updateText()
  end)
  scanButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("What to look up")
    GameTooltip:AddLine("Limits \"Margin: N unpriced\" to one profession. Click to cycle through all of them.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  scanButton:SetScript("OnLeave", GameTooltip_Hide)
end

local function onShow(tries)
  local parent = AuctionHouseFrame or AuctionFrame
  if not parent then
    if tries < 5 then C_Timer.After(0.2, function() onShow(tries + 1) end) end
    return
  end
  if not button then build(parent) end
  if not listButton then buildList(parent) end
  if scanButton then scanButton:SetText(scanLabel()) end
  updateText()
  button:Show()
end

local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:SetScript("OnEvent", function() onShow(0) end)

-- Refresh the count and the window when Auctionator records new prices
-- (that callback only exists in some Auctionator builds).
local A = Auctionator and Auctionator.API and Auctionator.API.v1
if A and A.RegisterForDBUpdate then
  pcall(A.RegisterForDBUpdate, "Margin", function()
    updateText()
    if ns.RefreshUI then ns.RefreshUI() end
  end)
end
