local _, ns = ...

local API = "Margin"

-- Cheapest unit price to acquire an item: vendor buy price when a merchant
-- has been seen selling it (Auctionator caches those), otherwise the AH price.
-- Returns copper, source ("vendor" | "ah") or nil when nothing is known.
function ns.BuyPrice(itemID)
  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  if not A then return nil end
  local vendor = A.GetVendorPriceByItemID(API, itemID)
  local ah = A.GetAuctionPriceByItemID(API, itemID)
  if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
  if ah then return ah, "ah" end
  return nil
end

function ns.AHPrice(itemID)
  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  return A and A.GetAuctionPriceByItemID(API, itemID) or nil
end

-- Vendor sell price (what a merchant pays you). Item data may not be loaded yet.
function ns.VendorSell(itemID)
  local _, _, _, _, _, _, _, _, _, _, sell = C_Item.GetItemInfo(itemID)
  if sell == nil then C_Item.RequestLoadItemDataByID(itemID) end
  return sell
end
