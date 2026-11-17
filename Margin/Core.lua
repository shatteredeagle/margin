local _, ns = ...

ns.defaults = {
  ahCut = 0.05,       -- fraction the AH keeps when a sale completes
  ahChance = 0.8,     -- how often a listing sells; the deposit is lost when it does not
  sellAllVendor = false, -- vendor "sell all" ignores the AH ("do not bother with the AH")
  minAge = nil,       -- reserved: max Auctionator data age in days
  sortKey = "vendor", -- "vendor" or "ah"
  showAll = true,     -- list unprofitable / grey recipes too
  resale = "vendor",  -- leveling cost minus what the result sells for: "vendor" | "ah" | "off"
  odds = "worst",     -- skill-up odds for yellow/green recipes: "worst" (bottom of each band) or "typical"
  routeLock = true,   -- keep the route fixed until you press Re-plan
  useRep = false,     -- false: base (worst-case) prices, rep-locked items unavailable; true: use my reputation
  merchantList = true, -- open the vendor buy list beside a vendor that sells route items
  ahList = true,      -- open the shopping list beside the auction house
  useTrainer = true,  -- route may include recipes you still have to learn from a trainer
}

local function chardb()
  MarginDB.chars = MarginDB.chars or {}
  local key = UnitName("player") .. "-" .. GetRealmName()
  MarginDB.chars[key] = MarginDB.chars[key] or { profs = {} }
  return MarginDB.chars[key]
end

function ns.Char() return chardb() end
ns.override = {}
function ns.Opt(k)
  local o = ns.override[k]
  if o ~= nil then return o end
  local v = MarginDB.opts and MarginDB.opts[k]
  if v == nil then return ns.defaults[k] end
  return v
end
function ns.SetOpt(k, v)
  MarginDB.opts = MarginDB.opts or {}
  MarginDB.opts[k] = v
end

-- Runs fn with some options forced (used to price the route under other settings).
function ns.With(over, fn)
  local old = ns.override
  ns.override = over
  local ok, a, b, c = pcall(fn)
  ns.override = old
  if not ok then error(a, 0) end
  return a, b, c
end

function ns.Print(...) print("|cff66ccffMargin|r", ...) end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
  if name ~= "Margin" then return end
  MarginDB = MarginDB or {}
  f:UnregisterEvent("ADDON_LOADED")
end)

SLASH_MARGIN1 = "/margin"
SLASH_MARGIN2 = "/mg"
SlashCmdList.MARGIN = function(msg)
  msg = (msg or ""):lower()
  if msg == "scan" then
    ns.Scan(true)
  elseif msg:match("^route") then
    local n = tonumber(msg:match("route%s+(%d+)"))
    ns.SetOpt("routeTarget", n)
    ns.Print(n and ("route target " .. n) or "route target: profession max")
    if ns.RefreshUI then ns.RefreshUI() end
  elseif msg == "coverage" then
    local all = { "Alchemy", "Blacksmithing", "Cooking", "Enchanting", "Engineering", "First Aid",
      "Leatherworking", "Mining", "Tailoring" }
    local have, lack = {}, {}
    for _, n in ipairs(all) do
      if ns.TRAINER and ns.TRAINER[n] then have[#have + 1] = n else lack[#lack + 1] = n end
    end
    ns.Print("trainer recipe data:", table.concat(have, ", "))
    if #lack > 0 then ns.Print("no trainer data yet for:", table.concat(lack, ", "), "(they still use learned and item-taught recipes)") end
    for name, p in pairs(ns.Char().profs) do
      ns.Print(("%s %d/%d: %d learned, %d unlearned considered"):format(name, p.skill, p.max, #p.recipes, #(p.unlearned or {})))
    end
  elseif msg:match("^odds") then
    local m = msg:match("odds%s+(%a+)")
    if m == "worst" or m == "typical" then
      ns.SetOpt("odds", m)
      if ns.ClearLock then for name in pairs(ns.Char().profs) do ns.ClearLock(name) end end -- the route changes meaning
      if ns.RefreshUI then ns.RefreshUI() end
    end
    ns.Print("skill-up odds:", ns.Opt("odds"), "(/margin odds worst | typical)")
  elseif msg == "lock" then
    ns.SetOpt("routeLock", not ns.Opt("routeLock"))
    ns.Print(ns.Opt("routeLock") and "route locked until you press Re-plan" or "route re-plans whenever prices change")
    if ns.InvalidatePlan then ns.InvalidatePlan() end
    if ns.RefreshUI then ns.RefreshUI() end
  elseif msg == "rep" then
    ns.SetOpt("useRep", not ns.Opt("useRep"))
    ns.Print(ns.Opt("useRep") and "using my reputation (discounts seen at vendors, unlocked patterns)"
      or "using base prices (worst case, ignores reputation)")
    if ns.RefreshUI then ns.RefreshUI() end
  elseif msg == "buy" then
    ns.ToggleMerchant()
  elseif msg == "debug" then
    MarginDB.debug = not MarginDB.debug
    ns.Print("debug", MarginDB.debug and "on" or "off")
  elseif msg == "list" then
    ns.ToggleShopping()
  elseif msg == "probe" then
    ns.Probe()
  elseif msg == "report" then
    ns.Report()
  elseif msg:match("^chance") then
    local pct = tonumber(msg:match("chance%s+(%d+)"))
    if pct then ns.SetOpt("ahChance", math.min(100, pct) / 100); ns.Print("AH sale chance", pct .. "%"); if ns.RefreshUI then ns.RefreshUI() end end
  elseif msg:match("^cut") then
    local pct = tonumber(msg:match("cut%s+(%d+)"))
    if pct then ns.SetOpt("ahCut", pct / 100); ns.Print("AH cut", pct .. "%") end
  else
    ns.ToggleUI()
  end
end
