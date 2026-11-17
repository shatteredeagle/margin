local _, ns = ...

local API = "Margin"

-- Vendor buy price: what Auctionator saw at a merchant, else the bundled table.
local function vendorBuy(A, itemID)
  return A.GetVendorPriceByItemID(API, itemID) or ns.VENDOR_SEED[itemID]
end

-- Cheapest unit price to acquire an item: vendor buy price (Auctionator's
-- merchant cache, falling back to the bundled seed), otherwise the AH price.
-- Returns copper, source ("vendor" | "ah") or nil when nothing is known.
function ns.BuyPrice(itemID)
  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  if not A then return nil end
  local vendor = vendorBuy(A, itemID)
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
