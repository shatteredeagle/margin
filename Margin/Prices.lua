local _, ns = ...

-- Prices come from Auctionator when it is installed, otherwise from what Margin itself
-- has seen: AH searches (NoteAHPrice) and vendors you have opened (NoteVendorPrice), with
-- the bundled vendor table (VendorData.lua) as the last resort for vendor reagents.

local API = "Margin"
local WEEK = 7 * 86400

local function auctionator()
  return Auctionator and Auctionator.API and Auctionator.API.v1
end

-- Cheapest price Margin itself saw in an AH search; stale after a week.
function ns.Observed(itemID)
  local o = MarginDB and MarginDB.prices and MarginDB.prices[itemID]
  if o and time() - o.t < WEEK then return o.p end
end

function ns.NoteAHPrice(itemID, copper)
  if type(copper) ~= "number" or copper <= 0 then return end
  MarginDB.prices = MarginDB.prices or {}
  MarginDB.prices[itemID] = { p = copper, t = time() }
  if ns.InvalidatePlan then ns.InvalidatePlan() end
end

-- Unit price a vendor you opened charged (gold-only, unlimited stock). Keeps the lowest
-- and highest seen: a reputation discount lowers the price, so the highest is the base.
function ns.NoteVendorPrice(itemID, copper)
  if type(copper) ~= "number" or copper <= 0 then return end
  MarginDB.vendor = MarginDB.vendor or {}
  local v = MarginDB.vendor[itemID]
  if type(v) ~= "table" then
    MarginDB.vendor[itemID] = { low = copper, high = copper }
  else
    v.low, v.high = math.min(v.low, copper), math.max(v.high, copper)
  end
end

-- What a vendor charges for an item. Default is the worst case: the highest price known
-- (Auctionator's merchant cache, vendors Margin saw, the bundled base prices). With "use my
-- reputation" it is the lowest price you were actually charged, falling back to the base.
function ns.VendorBuy(itemID)
  local A = auctionator()
  local cached = A and A.GetVendorPriceByItemID(API, itemID)
  local own = MarginDB and MarginDB.vendor and MarginDB.vendor[itemID]
  if type(own) ~= "table" then own = nil end
  local seed = ns.VENDOR_SEED and ns.VENDOR_SEED[itemID]
  local best
  if ns.Opt("useRep") then
    for _, v in ipairs({ cached or false, own and own.low or false }) do
      if v and (not best or v < best) then best = v end
    end
    return best or seed
  end
  for _, v in ipairs({ cached or false, own and own.high or false, seed or false }) do
    if v and (not best or v > best) then best = v end
  end
  return best
end

function ns.AHPrice(itemID)
  local A = auctionator()
  return (A and A.GetAuctionPriceByItemID(API, itemID)) or ns.Observed(itemID)
end

-- Cheapest unit price to acquire an item: vendor or AH.
-- Returns copper, source ("vendor" | "ah") or nil when nothing is known.
function ns.BuyPrice(itemID)
  local vendor, ah = ns.VendorBuy(itemID), ns.AHPrice(itemID)
  if vendor and (not ah or vendor <= ah) then return vendor, "vendor" end
  if ah then return ah, "ah" end
  return nil
end

-- Vendor sell price (what a merchant pays you). Item data may not be loaded yet.
function ns.VendorSell(itemID)
  local _, _, _, _, _, _, _, _, _, _, sell = C_Item.GetItemInfo(itemID)
  if sell == nil then C_Item.RequestLoadItemDataByID(itemID) end
  return sell
end
