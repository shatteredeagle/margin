local _, ns = ...

-- Plug-in points for the UI. Layouts (whole main windows: classic, ledger, later workbench and tracker)
-- register here; so do the tabs, the chips (a setting shown as "Name: value", click for the next
-- value), the list columns and every option of the Settings panel. A layout iterates the registry
-- instead of hard-coding them, so adding a tab, chip, column or option is one registration.
--
-- The public entry points other modules call (ns.RefreshUI, ns.ToggleUI, ns.OpenForProfession) live
-- here too and go to whichever layout is chosen (option "theme").

local UI = { tabs = {}, chips = {}, columns = {}, settings = {}, groups = {} }
ns.UI = UI

local function byOrder(a, b)
  if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
  return a.key < b.key
end

-- { key, title, order, chips = { chip keys }, search = bool, replan = bool }
function UI.RegisterTab(def)
  UI.tabs[#UI.tabs + 1] = def
  table.sort(UI.tabs, byOrder)
end

function UI.Tab(key)
  for _, t in ipairs(UI.tabs) do if t.key == key then return t end end
end

-- { key, label = "Resale:", values = { ... }, text = fn(value) or table, opt = option key (default key),
--   highlight = fn(value), apply = fn(value) (after the option is stored), tooltip = { title, body } }
function UI.RegisterChip(def)
  UI.chips[def.key] = def
end

function UI.ChipText(def)
  local v = ns.Opt(def.opt or def.key)
  local text = type(def.text) == "function" and def.text(v) or (def.text and def.text[tostring(v)]) or tostring(v)
  return def.label, text, def.highlight and def.highlight(v) or false
end

-- The next value of a chip's option.
function UI.CycleChip(key)
  local def = UI.chips[key]
  if not def then return end
  local cur, vals = ns.Opt(def.opt or def.key), def.values
  local nxt = vals[1]
  for i, v in ipairs(vals) do if v == cur then nxt = vals[i % #vals + 1] end end
  UI.Apply(def.opt or def.key, nxt, def.apply)
end

-- Columns of a tab: { key, title (string or fn), width, align, sort = sort column index }.
function UI.RegisterColumn(tab, def)
  UI.columns[tab] = UI.columns[tab] or {}
  local list = UI.columns[tab]
  list[#list + 1] = def
end

function UI.Columns(tab) return UI.columns[tab] or {} end

-- Settings panel entries: { group, key, kind = "segmented" | "check" | "number", label, hint,
--   options = { { value, label } } (segmented), get = fn() / set = fn(v) (when not a plain option),
--   percent = true (number shown as 0-100, stored as a fraction), apply = fn(v), order }
function UI.RegisterSetting(def)
  if not UI.groups[def.group] then
    UI.groups[def.group] = { name = def.group, order = def.groupOrder or 100, column = def.column or 1, list = {} }
  end
  local g = UI.groups[def.group]
  g.list[#g.list + 1] = def
  UI.settings[#UI.settings + 1] = def
end

-- Groups sorted for display.
function UI.Groups()
  local out = {}
  for _, g in pairs(UI.groups) do out[#out + 1] = g end
  table.sort(out, function(a, b)
    if a.order ~= b.order then return a.order < b.order end
    return a.name < b.name
  end)
  return out
end

function UI.SettingValue(def)
  if def.get then return def.get() end
  local v = ns.Opt(def.key)
  if def.percent and type(v) == "number" then return math.floor(v * 100 + 0.5) end
  return v
end

-- Store a setting and redraw everything. apply runs after the store (re-plan, scan, theme switch).
function UI.Apply(key, value, apply)
  ns.SetOpt(key, value)
  if apply then apply(value) end
  if ns.RefreshUI then ns.RefreshUI() end
end

function UI.SetSetting(def, value)
  if def.set then
    def.set(value)
    if ns.RefreshUI then ns.RefreshUI() end
    return
  end
  if def.percent then
    local n = tonumber(value)
    if not n then return ns.RefreshUI() end
    value = math.min(100, math.max(0, n)) / 100
  end
  UI.Apply(def.key, value, def.apply)
end

---------------------------------------------------------------------------
-- Layouts
--   ns.Layouts.register(name, { title, palette, order,
--     build(), refresh(), redraw(), show(), hide(), isShown(), scrollTop(), frame() })
-- refresh() redraws when shown (and drops cached data); the registry calls it from ns.RefreshUI.
-- redraw() only rebuilds text from what is cached (ns.RedrawUI, when item names arrive).
---------------------------------------------------------------------------

local layouts, order = {}, {}
local Layouts = {}
ns.Layouts = Layouts
local DEFAULT = ns.DEFAULT_THEME or "ledger"

function Layouts.register(name, def)
  def.name = name
  if not layouts[name] then order[#order + 1] = name end
  layouts[name] = def
  table.sort(order, function(a, b) return (layouts[a].order or 0) < (layouts[b].order or 0) end)
end

function Layouts.get(name) return layouts[name] end

-- names in display order
function Layouts.list()
  local out = {}
  for i, n in ipairs(order) do out[i] = n end
  return out
end

function Layouts.activeName()
  local n = ns.Opt("theme")
  if layouts[n] then return n end
  if layouts[DEFAULT] then return DEFAULT end
  return order[1]
end

function Layouts.active()
  return layouts[Layouts.activeName() or ""]
end

local function applyPalette()
  local L = Layouts.active()
  ns.T.Set(L and L.palette or "ledger")
end

-- Switch the main window's look and layout, live: the open window closes and the new one opens in
-- its place, and the companions repaint in the new palette.
function ns.SetTheme(name)
  if not layouts[name] then return false end
  local old = Layouts.active()
  local wasShown = old and old.isShown()
  if old and old.name ~= name and wasShown then old.hide() end
  ns.SetOpt("theme", name)
  applyPalette()
  if wasShown and old.name ~= name then layouts[name].show() end
  ns.RefreshUI()
  return true
end

function ns.UIScrollTop()
  local L = Layouts.active()
  if L and L.scrollTop then L.scrollTop() end
end

-- Redraw everything: the plan is recomputed, then the main window and the companions.
function ns.RefreshUI()
  ns.InvalidatePlan()
  if ns.RefreshShopping then ns.RefreshShopping() end
  if ns.RefreshMerchant then ns.RefreshMerchant() end
  if ns.RefreshQuote then ns.RefreshQuote() end
  local L = Layouts.active()
  if L then L.refresh() end
end

-- Item names arrived: rebuild the text only. Never re-plans (ns.RefreshUI does), or every name that
-- loads would plan every route again.
function ns.RedrawUI()
  local L = Layouts.active()
  if L then (L.redraw or L.refresh)() end
  if ns.RefreshShopping then ns.RefreshShopping() end
  if ns.RefreshMerchant then ns.RefreshMerchant() end
  if ns.RefreshQuote then ns.RefreshQuote() end
end

-- The open main window of the chosen layout (companions dock beside it), or nil.
function ns.MainWindow()
  local L = Layouts.active()
  local f = L and L.frame and L.frame()
  return f and f:IsShown() and f or nil
end

function ns.ToggleUI()
  local L = Layouts.active()
  if not L then return end
  if L.isShown() then L.hide() else L.show(); ns.RefreshUI() end
end

-- Show the window on a given profession (the profession window's button uses this).
function ns.OpenForProfession(name)
  local L = Layouts.active()
  if not L then return end
  ns.SetProfession(name)
  if not L.isShown() then L.show() end
  ns.RefreshUI()
end

-- Any Margin window open (used to skip work while none is).
function ns.AnyWindowShown()
  for _, L in pairs(layouts) do if L.isShown() then return true end end
  for _, name in ipairs({ "MarginShopping", "MarginMerchant", "MarginQuote" }) do
    local f = _G[name]
    if f and f:IsShown() then return true end
  end
  return false
end

-- Palette for the chosen layout once the saved options are loaded.
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", applyPalette)
