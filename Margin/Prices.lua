local _, ns = ...

-- Prices come from Auctionator when it is installed, otherwise from what Margin itself
-- has seen: AH searches (NoteAHPrice) and vendors you have opened (NoteVendorPrice), with
-- the bundled vendor table (VendorData.lua) as the last resort for vendor reagents.

local API = "Margin"
local WEEK = 7 * 86400

-- Ask the game to load an item's data, but only once a minute per item. Asking on every call made each answer
-- (GET_ITEM_INFO_RECEIVED) trigger another redraw, and an item that does not exist in Forever never loads, so
-- the window redrew itself in a loop.
local asked = {}
local function requestOnce(itemID)
  local last = asked[itemID]
  if not last or GetTime() - last > 60 then
    asked[itemID] = GetTime()
    C_Item.RequestLoadItemDataByID(itemID)
  end
end

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

-- Auctionator's price when it has one, else Margin's own. When both exist the newer one wins (Margin's
-- own full scan or search can be fresher than Auctionator's last visit).
function ns.AHPrice(itemID)
  local A = auctionator()
  local theirs = A and A.GetAuctionPriceByItemID(API, itemID)
  local ours = ns.Observed(itemID)
  if theirs and ours then
    local o = MarginDB.prices[itemID]
    local age = A.GetAuctionAgeByItemID and A.GetAuctionAgeByItemID(API, itemID) -- days since Auctionator saw it
    if type(age) == "number" and (time() - o.t) / 86400 < age then return ours end
    return theirs
  end
  return theirs or ours
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
  if sell == nil then requestOnce(itemID) end
  return sell
end

-- Deposit the AH takes when you list `count` of an item for 12 hours (kept if it sells, lost if it
-- does not). The game's own calculation when it has one, else 15% of the vendor value.
function ns.Deposit(itemID, count)
  count = count or 1
  local AH = C_AuctionHouse
  if AH and AH.CalculateCommodityDeposit then
    local ok, d = pcall(AH.CalculateCommodityDeposit, itemID, 1, count)
    if ok and type(d) == "number" then return d end
  end
  local sell = ns.VendorSell(itemID)
  return sell and math.floor(sell * 0.15 * count) or 0
end

-- What one unit is worth sold on the AH: the price after the cut, minus the deposit you
-- expect to lose when it does not sell (ahChance is how often it does).
function ns.AHNetPerUnit(itemID)
  local ah = ns.AHPrice(itemID)
  if not ah then return nil end
  local net = ah * (1 - ns.Opt("ahCut"))
  local loss = ns.Deposit(itemID, 1) * (1 - ns.Opt("ahChance"))
  return math.floor(net - loss)
end

-- Whether the game has this item at all. The profession window's full recipe list and the bundled
-- Classic tables mention items that do not exist in Forever; they can never be priced or sold.
-- (GetItemInfoInstant reads the client's own item table, so no server round trip.)
function ns.ItemExists(itemID)
  if C_Item and C_Item.GetItemInfoInstant then
    local ok, got = pcall(C_Item.GetItemInfoInstant, itemID)
    if ok then return got ~= nil end
  end
  return true -- cannot tell: assume it does
end

-- An item's name, or nil while the game has not given it (asked for at most once a minute).
function ns.ItemName(itemID)
  local n = C_Item.GetItemNameByID(itemID)
  if n then return n end
  requestOnce(itemID)
  return nil
end
