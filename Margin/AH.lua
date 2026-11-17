local _, ns = ...

-- A button on the auction house that has Auctionator search only the items Margin
-- cannot price yet (no full scan). Shift-click also searches unpriced results.
local button

local function missing(includeOutputs)
  return ns.MissingItems(ns.Char().profs, includeOutputs, ns.Opt("useTrainer"))
end

local function updateText()
  if not button then return end
  button:SetText(("Margin: %d unpriced"):format(#missing(false)))
end

local function search(includeOutputs)
  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  if not A or not A.MultiSearchExact then ns.Print("Auctionator search API not found."); return end
  local names, loading = {}, 0
  for _, id in ipairs(missing(includeOutputs)) do
    local n = C_Item.GetItemNameByID(id)
    if n then names[#names + 1] = n else loading = loading + 1; C_Item.RequestLoadItemDataByID(id) end
  end
  if #names == 0 then
    ns.Print(loading > 0 and "Item names still loading, click again." or "Nothing to look up.")
    return
  end
  local ok, err = pcall(A.MultiSearchExact, "Margin", names)
  if not ok then ns.Print("Search failed:", tostring(err)); return end
  ns.Print(("Searching %d items%s."):format(#names, loading > 0 and (", " .. loading .. " names still loading") or ""))
end

local function build(parent)
  button = CreateFrame("Button", "MarginAHButton", parent, "UIPanelButtonTemplate")
  button:SetSize(170, 22)
  button:SetPoint("BOTTOMRIGHT", parent, "TOPRIGHT", -8, 2)
  button:SetScript("OnClick", function() search(IsShiftKeyDown()) end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("Margin")
    GameTooltip:AddLine("Searches only the reagents Margin has no price for.", 1, 1, 1, true)
    GameTooltip:AddLine("Shift-click: also unpriced crafted results.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
end

local listButton
local function buildList(parent)
  listButton = CreateFrame("Button", "MarginAHListButton", parent, "UIPanelButtonTemplate")
  listButton:SetSize(110, 22)
  listButton:SetPoint("RIGHT", button, "LEFT", -4, 0)
  listButton:SetText("Shopping list")
  listButton:SetScript("OnClick", function() ns.ToggleShopping() end)
end

local function onShow(tries)
  local parent = AuctionHouseFrame or AuctionFrame
  if not parent then
    if tries < 5 then C_Timer.After(0.2, function() onShow(tries + 1) end) end
    return
  end
  if not button then build(parent) end
  if not listButton then buildList(parent) end
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
