local _, ns = ...

-- The Margin strip on the auction house: one fixed-width strip on the AH's top edge with the brand,
-- the profession filter for lookups, Margin's own full scan, the shopping list, and the lookup that
-- searches only the items Margin cannot price yet (through Auctionator when it is installed, else
-- with Margin's own search). Shift-click the lookup to include unpriced crafted results, right-click
-- to count already-searched items again. Each segment has a fixed width, so changing counts and
-- states never move the others.
local W, T = ns.W, ns.T
local strip -- the strip (built the first time the AH opens)

-- Most items looked up per click: Auctionator's search and the AH's own throttling both slow down
-- badly with hundreds of terms, so a long list is worked through in rounds.
local ROUND = 60

-- The profession the lookup is limited to (nil: all of them), if it is still one of yours.
local function scanProfession()
  local name = ns.Opt("scanProf")
  return name and ns.Char().profs[name] and name or nil
end

local function missing(includeOutputs)
  local ids = ns.MissingItems(ns.Char().profs, includeOutputs, ns.Opt("useTrainer"), ns.Opt("profitScope") == "all",
    scanProfession())
  -- also the items the route buys on the AH whose listings have not been seen lately: a priced item can
  -- still run out (Margin needs to know how much is for sale, not just the lowest price)
  local plan = ns.CurrentPlan()
  if plan then
    local have, recent = {}, time() - 12 * 3600
    for _, id in ipairs(ids) do have[id] = true end
    local searched = MarginDB.searched or {}
    for _, it in ipairs(plan.shop) do
      if it.src == "ah" and not it.recipe and not have[it.item] and not ns.Depth(it.item)
        and not (searched[it.item] and searched[it.item] > recent) and ns.ItemExists(it.item) then
        ids[#ids + 1] = it.item
        have[it.item] = true
      end
    end
  end
  return ids
end

-- A lookup works through the unpriced items in rounds of ROUND, one after another, until none are
-- left (or MAX_ROUNDS, or you click the button again to stop it). Each round waits for the previous
-- search to finish, then pauses a moment, so the AH is never hammered.
local running, runToken, awaiting, rounds, runOutputs = false, nil, nil, 0, false
local lastProgress = 0 -- GetTime() of the last round start: a run that went quiet is not "running" for ever
local MAX_ROUNDS = 30
local nameTries = 0
local PAUSE = 1.5

local updateText -- below, once the strip exists
local function markSearched(ids)
  MarginDB.searched = MarginDB.searched or {}
  local now = time()
  for _, id in ipairs(ids) do MarginDB.searched[id] = now end
  -- results arrive a little later; recount then
  C_Timer.After(4, updateText)
  C_Timer.After(15, updateText)
end

-- Auctionator says when a search ends (its event bus); without that we cannot chain rounds.
local hooked, canChain
local listener = {}
function listener.ReceiveEvent(_, eventName)
  local E = Auctionator and Auctionator.Shopping and Auctionator.Shopping.Tab and Auctionator.Shopping.Tab.Events
  if E and eventName == E.SearchEnd and awaiting and awaiting == runToken then
    local t = awaiting
    awaiting = nil
    if ns.AHRoundDone then ns.AHRoundDone(t) end
  end
end
local function hookAuctionator()
  if hooked then return canChain end
  hooked = true
  local E = Auctionator and Auctionator.Shopping and Auctionator.Shopping.Tab and Auctionator.Shopping.Tab.Events
  if E and E.SearchEnd and Auctionator.EventBus and Auctionator.EventBus.Register then
    canChain = pcall(Auctionator.EventBus.Register, Auctionator.EventBus, listener, { E.SearchEnd })
  end
  return canChain
end

-- Say why there is nothing to do, instead of doing nothing.
local function explainEmpty(includeOutputs)
  local profs = ns.Char().profs
  local all = ns.MissingItems(profs, includeOutputs, ns.Opt("useTrainer"), ns.Opt("profitScope") == "all",
    scanProfession(), true)
  local only = scanProfession()
  if #all == 0 then
    ns.Print(only and ("Nothing unpriced for " .. only .. ". (Scan: on the Margin strip cycles professions.)")
      or "Nothing unpriced: every recipe you have is priced.")
  else
    ns.Print(("Nothing to look up: %d unpriced items were already searched in the last 12 hours and have no listing%s."):format(
      #all, only and (" (" .. only .. " only)") or ""))
    ns.Print("Right-click Look up to count them again.")
  end
end

local startRound

-- The items the round in flight was asked to find, so the end of the round can say which ones turned up nothing.
local sentIds = {}

-- After a round: name the items still without a price (nobody lists them, or the search missed them) and let
-- them be asked for again in about two hours, not twelve.
local function reportUnresolved(ids)
  local none = {}
  for _, id in ipairs(ids) do
    if not ns.AHPrice(id) then
      none[#none + 1] = C_Item.GetItemNameByID(id) or ("item " .. id)
      MarginDB.searched = MarginDB.searched or {}
      MarginDB.searched[id] = time() - 10 * 3600
    end
  end
  if #none > 0 then
    ns.Print(("No listing found for %d item%s: %s%s. Margin asks again in about 2 hours (or run a Full scan)."):format(
      #none, #none > 1 and "s" or "", table.concat(none, ", ", 1, math.min(#none, 8)), #none > 8 and ", ..." or ""))
  end
end

function ns.AHRoundDone(token)
  if token ~= runToken or not running then return end
  local ids = sentIds
  sentIds = {}
  C_Timer.After(PAUSE + 2, function() -- a moment for Auctionator to record what the search found
    if token ~= runToken or not running then return end
    reportUnresolved(ids)
    startRound()
  end)
end

local function stop(message)
  running, runToken, awaiting = false, nil, nil
  if message then ns.Print(message) end
  updateText()
end

local function ahOpen()
  return (AuctionHouseFrame and AuctionHouseFrame:IsShown()) or (AuctionFrame and AuctionFrame:IsShown())
end

-- One round: the next ROUND unpriced items.
startRound = function()
  if not running then return end
  if not ahOpen() then return stop() end
  rounds = rounds + 1
  lastProgress = GetTime()
  local ids = missing(runOutputs)
  if #ids == 0 then
    stop()
    if rounds == 1 then return explainEmpty(runOutputs) end
    return ns.Print("AH lookup finished: nothing unpriced is left to look up.")
  end
  if rounds > MAX_ROUNDS then return stop("AH lookup paused after " .. MAX_ROUNDS .. " rounds. Click again to continue.") end
  local more = math.max(0, #ids - ROUND)
  for i = #ids, ROUND + 1, -1 do ids[i] = nil end
  local token = {}
  runToken = token

  local A = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (A and A.MultiSearchExact) then
    ns.Print(("Looking up %d items%s."):format(#ids, more > 0 and (", " .. more .. " more after") or ""))
    markSearched(ids)
    sentIds = ids
    ns.ScanItems(ids, function() ns.AHRoundDone(token) end) -- Margin's own search; reports when it is done
    return
  end

  local names, sent, loading = {}, {}, 0
  for _, id in ipairs(ids) do
    local n = C_Item.GetItemNameByID(id)
    if n then names[#names + 1] = n; sent[#sent + 1] = id else loading = loading + 1; C_Item.RequestLoadItemDataByID(id) end
  end
  if #names == 0 then -- names are still loading: look again shortly, and give up on ones that never load
    nameTries = nameTries + 1
    if nameTries > 3 then
      markSearched(ids) -- the game cannot name them; do not wait on them for ever
      nameTries = 0
      ns.Print(("Skipped %d items the game could not give names for."):format(#ids))
      C_Timer.After(0.2, function() if token == runToken and running then startRound() end end)
      return
    end
    ns.Print(("Waiting for %d item names to load..."):format(loading))
    C_Timer.After(2, function() if token == runToken and running then startRound() end end)
    return
  end
  nameTries = 0
  local ok, err = pcall(A.MultiSearchExact, "Margin", names)
  if not ok then return stop("Search failed: " .. tostring(err)) end
  markSearched(sent)
  sentIds = sent
  ns.Print(("Searching %d items%s."):format(#names, more > 0 and (", " .. more .. " more after this round") or ""))
  if hookAuctionator() then
    awaiting = token
    C_Timer.After(120, function() -- a search that never reports back must not hang the run
      if awaiting == token then awaiting = nil; ns.AHRoundDone(token) end
    end)
  else
    stop() -- cannot tell when it finished: one round per click
  end
end

local function search(includeOutputs)
  if running and GetTime() - lastProgress < 150 then return stop("Stopped.") end
  running, rounds, runOutputs = true, 0, includeOutputs and true or false
  updateText()
  startRound()
end

local function fullLabel()
  local state, v = ns.FullScanState()
  if state == "running" then return T.C("warn", ("Scanning %d%%"):format(math.floor(v * 100))) end
  if state == "cooldown" then return T.C("dim", ("Full scan %d:%02d"):format(math.floor(v / 60), math.floor(v) % 60)) end
  return "Full scan"
end

local function scanLabel()
  return T.C("dim", "Scan:") .. " " .. (scanProfession() or "all professions")
end

-- AH items the route still has to buy.
local function toBuyHere()
  local plan = ns.CurrentPlan()
  if not plan then return 0 end
  local n = 0
  for _, it in ipairs((ns.ShopOf(plan))) do
    if it.src == "ah" and math.max(0, it.count - (it.recipe and 0 or ns.Owned(it.item))) > 0 then n = n + 1 end
  end
  return n
end

-- One flat segment of the strip: a button with an optional glyph and a fixed width.
local function segment(width, glyph, onClick, rightClick)
  local b = CreateFrame("Button", nil, strip)
  b:SetSize(width, 26)
  b.hl = W.Solid(b, "panel2")
  b.hl:SetAllPoints()
  b.hl:Hide()
  b.sep = W.Solid(b, "border", "BORDER")
  b.sep:SetPoint("TOPRIGHT"); b.sep:SetPoint("BOTTOMRIGHT"); b.sep:SetWidth(1)
  local x = 10
  if glyph then
    b.glyph = W.Glyph(b, glyph, 12, "accent")
    b.glyph:SetPoint("LEFT", 10, 0)
    x = 27
  end
  b.text = W.Text(b, "small", "text")
  b.text:SetPoint("LEFT", x, 0)
  b.text:SetPoint("RIGHT", -8, 0)
  if onClick then
    if rightClick then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function() b.hl:Show() end)
    b:SetScript("OnLeave", function() b.hl:Hide() end)
  end
  local prev = strip.segments[#strip.segments]
  if prev then b:SetPoint("LEFT", prev, "RIGHT", 0, 0) else b:SetPoint("LEFT", 0, 0) end
  strip.segments[#strip.segments + 1] = b
  return b
end

updateText = function()
  if not strip then return end
  if running then
    strip.lookup.text:SetText(T.C("warn", ("Looking up · %d left · Stop"):format(#missing(runOutputs))))
  else
    local n = #missing(false)
    strip.lookup.text:SetText((n > 0 and T.C("warn", n) or T.C("dim", n)) .. " unpriced · Look up")
  end
  strip.scan.text:SetText(scanLabel())
  local buy = toBuyHere()
  strip.list.text:SetText("Shopping list " .. (buy > 0 and T.C("accent", "(" .. buy .. ")") or T.C("dim", "(0)")))
end

local function build(parent)
  strip = W.Panel(parent, "panel", "border")
  _G.MarginAHStrip = strip
  strip:SetSize(740, 26)
  strip:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", 4, 2)
  strip:SetFrameLevel(parent:GetFrameLevel() + 10)
  strip.segments = {}

  strip.brand = segment(84, "logo")
  W.TextColor(strip.brand.text, "accent")
  strip.brand.text:SetText("Margin")

  -- which profession the lookup covers: all of them, or one
  strip.scan = segment(196, "chev", function()
    local names = ns.Professions()
    local cur, nxt = scanProfession(), nil
    if not cur then nxt = names[1] else
      for i, n in ipairs(names) do if n == cur then nxt = names[i + 1] end end
    end
    ns.SetOpt("scanProf", nxt) -- past the last one: back to all
    updateText()
  end)
  W.TipText(strip.scan, "What to look up", "Limits the lookup to one profession. Click to cycle through all of them.")

  -- Margin's own full auction house scan: prices and supply for everything it watches, in one go
  strip.full = segment(124, nil, function() ns.FullScan() end)
  strip.full.text:SetText(fullLabel())
  local acc = 0
  strip.full:SetScript("OnUpdate", function(self, elapsed)
    acc = acc + elapsed
    if acc > 0.5 then acc = 0; self.text:SetText(fullLabel()) end
  end)
  W.TipText(strip.full, "Full scan", "Reads the whole auction house once and records the price and how much is for sale of every item Margin watches (your reagents, products and patterns). The AH allows one every 15 minutes, and the game may stutter for a moment.",
    "Auctionator's prices are still used when it is installed, unless this is newer.")

  strip.list = segment(146, "cart", function() ns.ToggleShopping() end)
  W.TipText(strip.list, "Shopping list", "What the route still needs, with a Search button per item that fills in the count. The number is how many items are still to buy here.")

  strip.lookup = segment(190, "ask", function(_, btn)
    if btn == "RightButton" then
      MarginDB.searched = nil -- forget what was already searched
      updateText()
      return ns.Print("Forgot earlier searches; every unpriced item counts again.")
    end
    search(IsShiftKeyDown())
  end, true)
  strip.lookup.sep:Hide()
  W.Tip(strip.lookup, function(tt)
    tt:AddLine("Look up")
    tt:AddLine("Looks up what Margin needs: items it has no price for, and items your route buys here whose listings it has not seen lately (to know how much is for sale). Click again to stop.", 1, 1, 1, true)
    tt:AddLine("Shift-click: also unpriced crafted results.", 0.7, 0.7, 0.7, true)
    local none = ns.SearchedUnpriced()
    if none > 0 then
      tt:AddLine(("%d searched in the last 12 hours have no listing and are not counted."):format(none), 1, 0.82, 0, true)
    end
    tt:AddLine("Right-click: count searched items again.", 0.7, 0.7, 0.7, true)
  end)
end

local function onShow(tries)
  local parent = AuctionHouseFrame or AuctionFrame
  if not parent then
    if tries < 5 then C_Timer.After(0.2, function() onShow(tries + 1) end) end
    return
  end
  if not strip then build(parent) end
  updateText()
  -- with no Auctionator there is no other source of prices: scan by itself when the AH opens (once the
  -- 15-minute limit allows), unless turned off with /margin autoscan off
  local auto = ns.Opt("autoFullScan")
  if auto == nil then auto = not Auctionator end
  if auto and ns.FullScanState() == "ready" then C_Timer.After(2, function() if ns.FullScanState() == "ready" then ns.FullScan() end end) end
  strip:Show()
end

local f = CreateFrame("Frame")
f:RegisterEvent("AUCTION_HOUSE_SHOW")
f:RegisterEvent("AUCTION_HOUSE_CLOSED")
f:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_CLOSED" then
    running, runToken, awaiting = false, nil, nil
  else
    onShow(0)
  end
end)

-- Refresh the count and the window when Auctionator records new prices
-- (that callback only exists in some Auctionator builds).
local A = Auctionator and Auctionator.API and Auctionator.API.v1
if A and A.RegisterForDBUpdate then
  pcall(A.RegisterForDBUpdate, "Margin", function()
    updateText()
    if ns.MarkStale then ns.MarkStale() end
  end)
end
