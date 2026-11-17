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

local function updateText()
  if not button then return end
  if running then
    button:SetText(("Margin: %d left (click to stop)"):format(#missing(runOutputs)))
  else
    button:SetText(("Margin: %d to look up"):format(#missing(false)))
  end
end

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
    ns.Print(only and ("Nothing unpriced for " .. only .. ". (Scan: button cycles professions.)")
      or "Nothing unpriced: every recipe you have is priced.")
  else
    ns.Print(("Nothing to look up: %d unpriced items were already searched in the last 12 hours and have no listing%s."):format(
      #all, only and (" (" .. only .. " only)") or ""))
    ns.Print("Right-click the button to count them again.")
  end
end

local startRound

function ns.AHRoundDone(token)
  if token ~= runToken or not running then return end
  C_Timer.After(PAUSE, function()
    if token == runToken and running then startRound() end
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
    GameTooltip:AddLine("Looks up what Margin needs: items it has no price for, and items your route buys here whose listings it has not seen lately (to know how much is for sale).", 1, 1, 1, true)
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
    if ns.RefreshUI then ns.RefreshUI() end
  end)
end
