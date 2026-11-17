local _, ns = ...

-- Margin's own full auction house scan. One ReplicateItems request returns every auction; each is folded
-- into the price and listing depth of the items Margin cares about (reagents, products, pattern items),
-- so no item-by-item lookups are needed. The AH allows one such scan every 15 minutes (Auctionator keeps
-- the same limit). Auctionator, when installed, is still used for prices; this adds fresher prices and
-- the depth Auctionator does not keep.

local COOLDOWN = 15 * 60
local BATCH = 400
local running, progress, startedAt = false, 0, 0
local frame

local function readable(v)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

local function ahOpen()
  return (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown())
end

-- Every item whose price or supply a recipe, route or profit figure needs.
function ns.WatchItems()
  local watch = {}
  local function add(id) if id then watch[id] = true end end
  for _, prof in pairs(ns.Char().profs) do
    for _, list in ipairs({ prof.recipes, prof.unlearned or {}, prof.every or {} }) do
      for _, r in ipairs(list) do
        add(r.out)
        for _, rg in ipairs(r.reagents) do add(rg.item) end
        for _, o in ipairs(r.teach or {}) do add(o.item) end
      end
    end
  end
  return watch
end

-- "running", progress 0..1  |  "cooldown", seconds left  |  "ready"
function ns.FullScanState()
  if running then return "running", progress end
  local wait = COOLDOWN - (time() - (MarginDB.lastFullScan or 0))
  if wait > 0 then return "cooldown", wait end
  return "ready"
end

local function stop(message)
  running = false
  if frame then frame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE") end
  if message then ns.Print(message) end
end

local function finish(by, watch, total)
  local results = ns.FinishListings(by, watch, 40)
  local priced, listed = 0, 0
  for item, res in pairs(results) do
    ns.NoteDepth(item, res.flat, res.capped)
    if res.price then
      ns.NoteAHPrice(item, res.price)
      priced = priced + 1
    end
    if #res.flat > 0 then listed = listed + 1 end
  end
  MarginDB.lastFullScan = time()
  running = false
  progress = 1
  ns.Print(("Full scan done: %d auctions seen, %d of the %d items Margin watches are for sale."):format(
    total, priced, (function() local n = 0 for _ in pairs(watch) do n = n + 1 end return n end)()))
  if ns.InvalidatePlan then ns.InvalidatePlan() end
  if ns.RefreshUI then ns.RefreshUI() end
end

-- Walk the replicate list in slices, a few hundred auctions per frame, so the game does not freeze.
local function process()
  local AH = C_AuctionHouse
  local total = AH.GetNumReplicateItems() or 0
  local watch = ns.WatchItems()
  local by, i = {}, 0
  local ticker
  ticker = C_Timer.NewTicker(0, function()
    if not running then return ticker:Cancel() end -- the AH closed
    local stopAt = math.min(i + BATCH, total)
    while i < stopAt do
      local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = AH.GetReplicateItemInfo(i)
      ns.AddListing(by, watch, readable(itemID), readable(count), readable(buyout))
      i = i + 1
    end
    progress = 0.2 + 0.8 * (total > 0 and i / total or 1)
    if i >= total then
      ticker:Cancel()
      finish(by, watch, total)
    end
  end)
end

function ns.FullScan()
  if not ahOpen() then return ns.Print("Open the auction house first.") end
  local state, v = ns.FullScanState()
  if state == "running" then return ns.Print("A full scan is already running.") end
  if state == "cooldown" then
    return ns.Print(("The AH allows a full scan every 15 minutes: %d:%02d to go."):format(math.floor(v / 60), math.floor(v) % 60))
  end
  if not (C_AuctionHouse and C_AuctionHouse.ReplicateItems) then
    return ns.Print("This client has no full-scan call.")
  end
  frame = frame or CreateFrame("Frame")
  frame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  frame:RegisterEvent("AUCTION_HOUSE_CLOSED")
  frame:SetScript("OnEvent", function(self, event)
    if event == "REPLICATE_ITEM_LIST_UPDATE" and running then
      self:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
      progress = 0.2
      process()
    elseif event == "AUCTION_HOUSE_CLOSED" and running then
      stop("Full scan stopped: the auction house closed.")
    end
  end)
  running, progress, startedAt = true, 0.05, GetTime()
  MarginDB.lastFullScan = time() -- counts from the request, as the AH does
  ns.Print("Full scan started. The game may stutter for a moment.")
  C_AuctionHouse.ReplicateItems()
  C_Timer.After(90, function() -- the server never answered
    if running and progress < 0.2 and GetTime() - startedAt >= 85 then stop("Full scan timed out; try again later.") end
  end)
end
