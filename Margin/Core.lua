local _, ns = ...

-- The main window's layout when none is chosen: "ledger" or "classic" (the one place to change it).
ns.DEFAULT_THEME = "ledger"

ns.defaults = {
  ahCut = 0.05,       -- fraction the AH keeps when a sale completes
  ahChance = 0.8,     -- how often a listing sells; the deposit is lost when it does not
  sellAllVendor = false, -- vendor "sell all" ignores the AH ("do not bother with the AH")
  minAge = nil,       -- reserved: max Auctionator data age in days
  sortKey = "vendor", -- "vendor" or "ah"
  showAll = true,     -- list unprofitable / grey recipes too
  resale = "vendor",  -- leveling cost minus what the result sells for: "vendor" | "ah" | "off"
  profitScope = "known", -- Profit tab: "known" recipes only, or "all" of the profession's recipes
  odds = "worst",     -- skill-up odds for yellow/green recipes: "worst" (bottom of each band) or "typical"
  routeLock = true,   -- keep the route fixed until you press Re-plan
  useRep = false,     -- false: base (worst-case) prices, rep-locked items unavailable; true: use my reputation
  merchantList = true, -- open the vendor buy list beside a vendor that sells route items
  ahList = true,      -- open the shopping list beside the auction house
  useTrainer = true,  -- route may include recipes you still have to learn from a trainer
  theme = ns.DEFAULT_THEME, -- main window layout and palette: "ledger" or "classic" (ns.Layouts)
  -- autoFullScan: nil (default: on when Auctionator is absent) | true | false
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

-- How long the heavy jobs take (scan, route planning, redraw): /margin perf shows count, average and worst, in ms
local perf = {}
function ns.PerfNote(name, ms)
  local p = perf[name]
  if not p then p = { n = 0, total = 0, max = 0 }; perf[name] = p end
  p.n, p.total = p.n + 1, p.total + ms
  if ms > p.max then p.max = ms end
end
function ns.PerfReport()
  local names = {}
  for k in pairs(perf) do names[#names + 1] = k end
  table.sort(names)
  if #names == 0 then return ns.Print("nothing timed yet") end
  for _, k in ipairs(names) do
    local p = perf[k]
    ns.Print(("%s: %d runs, avg %.1f ms, worst %.1f ms, total %.0f ms"):format(k, p.n, p.total / p.n, p.max, p.total))
  end
end
function ns.PerfReset() perf = {} end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
  if name ~= "Margin" then return end
  MarginDB = MarginDB or {}
  -- Lookups made before the 2-hour retry rule were remembered for 12 hours whether or not they found anything,
  -- which hid unpriced items from the AH button: age those entries once so they are asked for again.
  if not MarginDB.searchedFix then
    for id, t in pairs(MarginDB.searched or {}) do MarginDB.searched[id] = t - 10 * 3600 end
    MarginDB.searchedFix = true
  end
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
  elseif msg == "ignored" or msg:match("^unignore") then
    -- /margin ignored lists them; /margin unignore <name or id> brings one back
    local want = msg:match("^unignore%s+(.+)$")
    local list = ns.IgnoredList()
    if not want then
      if #list == 0 then return ns.Print("no crafts are ignored (right-click a recipe row in the Ledger)") end
      for _, c in ipairs(list) do ns.Print(("ignored: %s (%d)"):format(c.name, c.id)) end
      return ns.Print("/margin unignore <name or id> brings one back")
    end
    for _, c in ipairs(list) do
      if tostring(c.id) == want or c.name:lower():find(want, 1, true) then
        return ns.SetCraftIgnored(c.id, c.name, c.prof, false)
      end
    end
    ns.Print("no ignored craft matches " .. want)
  elseif msg == "perf" then
    ns.PerfReport()
  elseif msg == "perf reset" then
    ns.PerfReset(); ns.Print("timings cleared")
  elseif msg == "dump" then
    ns.Dump()
  elseif msg:match("^step") then
    -- /margin step 2 shows only the second step's shopping lists; /margin step all (or no number) the whole route
    local n = tonumber(msg:match("^step%s+(%d+)"))
    if msg:match("^step%s+craft") and ns.S.shopCraft then
      ns.S.shopOnCraft = true; ns.S.shopStep = nil
      if ns.RefreshUI then ns.RefreshUI() end
      return ns.Print(ns.ShopStepLabel({ segs = {} }))
    end
    local plan = ns.CurrentPlan and ns.CurrentPlan()
    if not plan then return ns.Print("open a profession window once first") end
    local steps = ns.ShopSteps(plan)
    if n and steps[n] then
      ns.SetShopStep(steps[n].index)
      ns.Print(ns.ShopStepLabel(plan))
    else
      ns.SetShopStep(nil)
      if n then ns.Print(("this route has %d steps"):format(#steps)) end
    end
    if ns.RefreshUI then ns.RefreshUI() end
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
  elseif msg == "fullscan" then
    ns.FullScan()
  elseif msg:match("^autoscan") then
    local m = msg:match("autoscan%s+(%a+)")
    if m == "on" or m == "off" then ns.SetOpt("autoFullScan", m == "on") end
    local auto = ns.Opt("autoFullScan")
    ns.Print("scan the AH by itself when it opens:", auto == nil and ("default (" .. (Auctionator and "off, Auctionator is installed" or "on") .. ")") or tostring(auto))
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
    if ns.Report then ns.Report() else ns.Print("/margin report is not available; /margin dump writes the route to SavedVariables.") end
  elseif msg:match("^theme") then
    local m = msg:match("theme%s+(%a+)")
    local names = ns.Layouts and ns.Layouts.list() or {}
    if m and not (ns.SetTheme and ns.SetTheme(m)) then ns.Print("no such theme:", m) end
    ns.Print("theme:", ns.Layouts and ns.Layouts.activeName() or "?", "(/margin theme " .. table.concat(names, " | ") .. ")")
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
