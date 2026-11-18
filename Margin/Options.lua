local _, ns = ...

-- What the main window offers, registered once for every layout: the tabs, the chips each tab shows,
-- the columns of each list and every option of the Settings panel. Slash commands (Core.lua) read and
-- write the same options.

local UI = ns.UI

-- After a setting that changes what the route means: forget the locked routes.
local function relock()
  for name in pairs(ns.Char().profs) do ns.ClearLock(name) end
end

-- "All recipes" needs the full list, which is only read from an open profession window.
local function loadAll(v)
  if v ~= "all" then return end
  local p = ns.Char().profs[ns.S.prof or ""]
  if p and not p.every and C_TradeSkillUI and C_TradeSkillUI.IsTradeSkillReady and C_TradeSkillUI.IsTradeSkillReady() then
    ns.Scan(false)
  end
end

---------------------------------------------------------------------------
-- Chips
---------------------------------------------------------------------------

UI.RegisterChip({ key = "sortKey", label = "Sell:", values = { "vendor", "ah" }, text = { vendor = "vendor", ah = "AH (net)" },
  tooltip = { "Sell at", "Profit figures with the vendor price, or the AH price after the cut and the deposit you lose on listings that do not sell." } })
UI.RegisterChip({ key = "profitScope", label = "Recipes:", values = { "known", "all" }, text = { known = "known", all = "all" },
  apply = loadAll,
  tooltip = { "Which recipes", "Known: only recipes you have learned. All: every recipe of this profession, learned or not, with what it would earn. Unlearned ones are blue and say where you would learn them.",
    "The full list is read from the profession window, so it needs that window open once." } })
UI.RegisterChip({ key = "showAll", label = "Show:", values = { true, false }, text = { ["true"] = "everything", ["false"] = "useful only" },
  tooltip = { "Show", "Useful only hides recipes that lose money (Profit) or give no skill-up (Leveling)." } })
UI.RegisterChip({ key = "resale", label = "Resale:", values = { "vendor", "ah", "off" }, text = { vendor = "vendor", ah = "AH", off = "none" },
  tooltip = { "What crafted items sell for", "Leveling and Route count the cost of a craft net of what its result sells for: at a vendor, on the AH (after the cut), or not at all." } })
UI.RegisterChip({ key = "odds", label = "Odds:", values = { "worst", "typical" }, text = { worst = "worst case", typical = "typical" },
  apply = relock,
  tooltip = { "Skill-up odds", "Worst case plans with the bottom of each colour band, so you never run short of materials. Typical uses the middle." } })
UI.RegisterChip({ key = "useTrainer", label = "Unlearned recipes:", values = { true, false }, text = { ["true"] = "on", ["false"] = "off" },
  highlight = function(v) return v and true or false end,
  tooltip = { "Unlearned recipes", "On: the route may use recipes you still have to learn from a trainer or a pattern, when they save more than they cost to learn." } })

---------------------------------------------------------------------------
-- Tabs and their columns
---------------------------------------------------------------------------

UI.RegisterTab({ key = "profit", title = "Profit", order = 10, chips = { "sortKey", "profitScope", "showAll" }, search = true })
UI.RegisterTab({ key = "level", title = "Leveling", order = 20, chips = { "resale", "odds", "showAll" }, search = true })
UI.RegisterTab({ key = "route", title = "Route", order = 30, chips = { "resale", "useTrainer", "odds" }, replan = true })

-- cell: which entry field the column shows (the layout formats it by entry kind)
UI.RegisterColumn("profit", { key = "name", title = "Recipe", sort = 1 })
UI.RegisterColumn("profit", { key = "cost", title = "Cost", width = 110, sort = 2 })
UI.RegisterColumn("profit", { key = "sale", title = function() return ns.Opt("sortKey") == "ah" and "AH (net)" or "Vendor" end, width = 110, sort = 3 })
UI.RegisterColumn("profit", { key = "value", title = "Profit", width = 118, sort = 4 })
UI.RegisterColumn("level", { key = "name", title = "Recipe", sort = 1 })
UI.RegisterColumn("level", { key = "cost", title = "Cost", width = 110, sort = 2 })
UI.RegisterColumn("level", { key = "sale", title = function() return ns.Opt("resale") == "off" and "" or "Resale" end, width = 110, sort = 3 })
UI.RegisterColumn("level", { key = "value", title = function() return ns.Opt("resale") == "off" and "Cost / skill-up" or "Net / skill-up" end, width = 118, sort = 4 })
UI.RegisterColumn("route", { key = "range", title = "Skill", width = 56 })
UI.RegisterColumn("route", { key = "name", title = "Recipe / item" })
UI.RegisterColumn("route", { key = "cost", title = "Crafts / qty", width = 84 })
UI.RegisterColumn("route", { key = "sale", title = "Per unit", width = 96 })
UI.RegisterColumn("route", { key = "value", title = "Net", width = 108 })

---------------------------------------------------------------------------
-- Settings (every option in ns.defaults, plus the AH auto-scan and the theme)
---------------------------------------------------------------------------

local S = UI.RegisterSetting

S({ group = "Planning", groupOrder = 10, column = 1, key = "resale", kind = "segmented", label = "Crafted items sell at",
  hint = "Leveling and Route: cost net of what the result sells for",
  options = { { "vendor", "Vendor" }, { "ah", "AH" }, { "off", "Not sold" } } })
S({ group = "Planning", key = "odds", kind = "segmented", label = "Skill-up odds", hint = "Worst case never leaves you short of materials",
  options = { { "worst", "Worst case" }, { "typical", "Typical" } }, apply = relock })
S({ group = "Planning", key = "useTrainer", kind = "check", label = "Route may include unlearned recipes",
  hint = "Trainer recipes and patterns you can buy" })
S({ group = "Planning", key = "routeLock", kind = "check", label = "Keep the route until I press Re-plan",
  hint = "Prices change; your plan does not", apply = function() ns.InvalidatePlan() end })
S({ group = "Planning", key = "routeTarget", kind = "number", label = "Route target skill", hint = "Empty: the profession's maximum",
  get = function() return ns.Opt("routeTarget") end,
  set = function(v)
    local n = tonumber(v)
    ns.SetOpt("routeTarget", (n and n > 0) and math.floor(n) or nil)
  end })
S({ group = "Planning", key = "useRep", kind = "check", label = "Use my reputation",
  hint = "Off: base prices, no rep-locked patterns (worst case)" })

S({ group = "Planning", key = "ignored", kind = "button", label = "Ignored crafts",
  hint = "Crafts left out of every list and route. Right-click a row to ignore one; click here to bring one back",
  text = function()
    local n = #ns.IgnoredList()
    return n == 0 and "None" or (n .. " ignored")
  end,
  onClick = function()
    local items = {}
    for _, c in ipairs(ns.IgnoredList()) do
      items[#items + 1] = { "Stop ignoring: " .. c.name, function() ns.SetCraftIgnored(c.id, c.name, c.prof, false) end }
    end
    if #items == 0 then return ns.Print("no crafts are ignored (right-click a recipe row to ignore it)") end
    ns.W.PopupMenu(items)
  end })

S({ group = "Appearance", groupOrder = 50, column = 1, key = "theme", kind = "segmented", label = "Window layout",
  hint = "Switches at once; /margin theme works too",
  options = function()
    local out = {}
    for _, n in ipairs(ns.Layouts.list()) do out[#out + 1] = { n, ns.Layouts.get(n).title or n } end
    return out
  end,
  get = function() return ns.Layouts.activeName() end,
  set = function(v) ns.SetTheme(v) end })

S({ group = "Prices", groupOrder = 20, column = 2, key = "ahCut", kind = "number", percent = true, label = "AH cut (%)",
  hint = "What the auction house keeps from a sale" })
S({ group = "Prices", key = "ahChance", kind = "number", percent = true, label = "Chance a listing sells (%)",
  hint = "The deposit is lost when it does not" })

S({ group = "Lists", groupOrder = 30, column = 2, key = "profitScope", kind = "segmented", label = "Profit tab: which recipes",
  options = { { "known", "Known" }, { "all", "All" } }, apply = loadAll })
S({ group = "Lists", key = "sortKey", kind = "segmented", label = "Profit tab: sell at",
  options = { { "vendor", "Vendor" }, { "ah", "AH" } } })
S({ group = "Lists", key = "showAll", kind = "segmented", label = "Show",
  options = { { false, "Useful only" }, { true, "Everything" } } })

S({ group = "Companions", groupOrder = 40, column = 2, key = "ahList", kind = "check",
  label = "Open the shopping list at the auction house" })
S({ group = "Companions", key = "merchantList", kind = "check",
  label = "Open the buy list at a vendor that sells route items" })
S({ group = "Companions", key = "sellAllVendor", kind = "check", label = "Sell everything to the vendor",
  hint = "Even items the AH would pay more for" })
S({ group = "Companions", key = "autoFullScan", kind = "segmented", label = "Full AH scan when the AH opens",
  hint = "Auto: only without Auctionator",
  options = { { "auto", "Auto" }, { "on", "On" }, { "off", "Off" } },
  get = function()
    local v = ns.Opt("autoFullScan")
    if v == nil then return "auto" end
    return v and "on" or "off"
  end,
  set = function(v)
    if v == "auto" then ns.SetOpt("autoFullScan", nil) else ns.SetOpt("autoFullScan", v == "on") end
  end })
