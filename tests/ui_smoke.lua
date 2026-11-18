-- UI smoke test: loads every Margin file in .toc order inside a small stub of the WoW API, then builds
-- and drives the windows (both layouts, every tab, chip, sort, card, section, the Settings panel, the
-- slash commands, the AH strip and shopping list, the vendor popup, the profession button and the craft
-- planner). It fails on any Lua error, which is what used to show up only in game: a nil global, a
-- local used before it is defined, a method called on the wrong thing.
--
-- The stubs are deliberately small and honest: widget objects only have the methods real widgets have
-- (a misspelt or invented method fails here as it would in game), getters return plain values, and
-- events and timers run only when the test fires them. What it cannot check: layout and looks, real
-- event order, secure/taint rules, and anything the real API returns that the stubs do not model.
--
-- Run from the repo root: lua5.1 tests/ui_smoke.lua   (prints "ui smoke ok")

local printed = {}
local realPrint = print
print = function(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  printed[#printed + 1] = table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------

-- Methods that exist on real widgets and need no state here.
local NOOP = {}
for name in ([[
SetPoint ClearAllPoints SetAllPoints SetTexture SetColorTexture SetTexCoord SetVertexColor SetDesaturated
SetFontObject SetFont SetTextColor SetJustifyH SetJustifyV SetWordWrap SetNonSpaceWrap SetSpacing SetAlpha
SetFrameStrata SetToplevel SetClampedToScreen EnableMouse EnableMouseWheel SetMovable RegisterForDrag
RegisterForClicks SetHighlightTexture LockHighlight UnlockHighlight SetOrientation SetObeyStepOnDrag
SetValueStep SetThumbTexture SetAutoFocus SetMaxLetters SetNumeric SetTextInsets SetDrawLayer SetBlendMode
SetOwner AddLine AddDoubleLine ClearLines CopyFontObject SetShadowOffset SetShadowColor SetItemByID
StartMoving StopMovingOrSizing HighlightText SetNormalTexture SetPushedTexture UnregisterAllEvents SetScale
SetHitRectInsets SetFontString SetNormalFontObject SetHighlightFontObject SetDisabledFontObject Raise Lower
]]):gmatch("%S+") do NOOP[name] = function() end end

local events = {}      -- event -> list of frames
local allFrames = {}
local Obj = {}         -- methods with state
local KNOWN_TYPES = { Frame = true, Button = true, CheckButton = true, EditBox = true, Slider = true,
  GameTooltip = true, Texture = true, FontString = true, Font = true, StatusBar = true }

local function new(otype, name, parent)
  assert(KNOWN_TYPES[otype], "CreateFrame: unknown frame type " .. tostring(otype))
  local o = setmetatable({}, { __index = function(_, k) return Obj[k] or NOOP[k] end })
  rawset(o, "_type", otype)
  rawset(o, "_name", name)
  rawset(o, "_children", {})
  rawset(o, "_scripts", {})
  rawset(o, "_shown", true)
  rawset(o, "_w", 0)
  rawset(o, "_h", 0)
  rawset(o, "_enabled", true)
  rawset(o, "_level", parent and ((parent._level or 0) + 1) or 0)
  if parent then
    rawset(o, "_parent", parent)
    table.insert(parent._children, o)
  end
  if name then _G[name] = o end
  if otype ~= "Texture" and otype ~= "FontString" and otype ~= "Font" then allFrames[#allFrames + 1] = o end
  return o
end

local function run(o, script, ...)
  local f = o._scripts[script]
  if f then return f(o, ...) end
end

function Obj.SetScript(o, k, f) o._scripts[k] = f end
function Obj.GetScript(o, k) return o._scripts[k] end
function Obj.HookScript(o, k, f)
  local old = o._scripts[k]
  if not old then o._scripts[k] = f; return end
  o._scripts[k] = function(...) old(...); f(...) end
end
function Obj.Show(o) if not o._shown then o._shown = true; run(o, "OnShow") end end
function Obj.Hide(o) if o._shown then o._shown = false; run(o, "OnHide") end end
function Obj.SetShown(o, v) if v then o:Show() else o:Hide() end end
function Obj.IsShown(o) return o._shown end
function Obj.IsVisible(o)
  local p = o
  while p do
    if not p._shown then return false end
    p = p._parent
  end
  return true
end
function Obj.GetParent(o) return o._parent end
function Obj.SetParent(o, p)
  o._parent = p
  if p then table.insert(p._children, o) end
end
function Obj.GetChildren(o)
  local out = {}
  for _, c in ipairs(o._children) do if c._type ~= "Texture" and c._type ~= "FontString" then out[#out + 1] = c end end
  return unpack(out)
end
function Obj.GetName(o) return o._name end
function Obj.GetObjectType(o) return o._type end
function Obj.IsForbidden() return false end
function Obj.IsMouseEnabled() return true end
function Obj.SetSize(o, w, h) o._w, o._h = w, h end
function Obj.SetWidth(o, w) o._w = w end
function Obj.SetHeight(o, h) o._h = h end
function Obj.GetWidth(o) return o._w end
function Obj.GetHeight(o) return o._h end
function Obj.GetSize(o) return o._w, o._h end
function Obj.GetRect(o) return 0, 0, o._w, o._h end
function Obj.GetFrameLevel(o) return o._level end
function Obj.SetFrameLevel(o, l) o._level = l end
function Obj.CreateTexture(o) return new("Texture", nil, o) end
function Obj.CreateFontString(o) return new("FontString", nil, o) end
function Obj.SetText(o, t)
  assert(t == nil or type(t) == "string" or type(t) == "number", "SetText with a " .. type(t))
  o._text = t and tostring(t) or ""
end
function Obj.GetText(o) return o._text or "" end
-- roughly 6 px a character, with colour codes and textures left out
function Obj.GetStringWidth(o) return #((o._text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) * 6 end
function Obj.GetStringHeight() return 12 end
function Obj.GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Obj.SetEnabled(o, v) o._enabled = v and true or false end
function Obj.Enable(o) o._enabled = true end
function Obj.Disable(o) o._enabled = false end
function Obj.IsEnabled(o) return o._enabled end
function Obj.SetChecked(o, v) o._checked = v and true or false end
function Obj.GetChecked(o) return o._checked end
function Obj.SetMinMaxValues(o, a, b) o._min, o._max = a, b end
function Obj.GetMinMaxValues(o) return o._min or 0, o._max or 0 end
function Obj.SetValue(o, v)
  if o._type == "Slider" then
    v = math.max(o._min or 0, math.min(o._max or 0, v))
    if v ~= o._value then o._value = v; run(o, "OnValueChanged", v, true) end
  else
    o._value = v
  end
end
function Obj.GetValue(o) return o._value or 0 end
function Obj.GetThumbTexture(o)
  if not o._thumb then rawset(o, "_thumb", new("Texture", nil, o)) end
  return o._thumb
end
function Obj.RegisterEvent(o, e)
  events[e] = events[e] or {}
  for _, f in ipairs(events[e]) do if f == o then return end end
  table.insert(events[e], o)
end
function Obj.UnregisterEvent(o, e)
  for i, f in ipairs(events[e] or {}) do if f == o then table.remove(events[e], i); return end end
end
function Obj.SetFocus(o) if not o._focus then o._focus = true; run(o, "OnEditFocusGained") end end
function Obj.ClearFocus(o) if o._focus then o._focus = false; run(o, "OnEditFocusLost") end end
function Obj.HasFocus(o) return o._focus and true or false end
function Obj.Click(o, button) return run(o, "OnClick", button or "LeftButton", false) end
function Obj.NumLines() return 0 end

---------------------------------------------------------------------------
-- The WoW globals Margin uses
---------------------------------------------------------------------------

function CreateFrame(otype, name, parent, template)
  local f = new(otype, name, parent)
  if otype ~= "GameTooltip" then f._shown = true end
  if template == "BasicFrameTemplateWithInset" then
    f.TitleText = f:CreateFontString()
    f.CloseButton = new("Button", nil, f)
  elseif template == "UICheckButtonTemplate" then
    f.text = f:CreateFontString()
  end
  return f
end
function CreateFont(name) return new("Font", name) end
for _, n in ipairs({ "GameFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalSmall",
  "GameFontDisableSmall", "GameFontNormalLarge", "GameFontHighlightLarge" }) do _G[n] = new("Font", n) end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
GameTooltip = CreateFrame("GameTooltip", "GameTooltip", UIParent)
function GameTooltip_Hide() GameTooltip:Hide() end
UISpecialFrames = {}
tinsert = table.insert
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
time = os.time
date = os.date
local now = 1000
function GetTime() return now end
function IsShiftKeyDown() return false end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function GetBuildInfo() return "1.0.0", "1", "Nov 1 2026", 16001 end
function GetMoney() return 5000000 end
function hooksecurefunc(t, name, fn)
  local old = t[name]
  t[name] = function(...) local a, b, c = old(...); fn(...); return a, b, c end
end
EventRegistry = { RegisterCallback = function() end }
SlashCmdList = {}
NUM_BAG_SLOTS = 4
ITEM_REQ_SKILL = "Requires %s (%d)"

-- timers run only when flush() says so
local timers = {}
C_Timer = {}
function C_Timer.After(d, fn) timers[#timers + 1] = { t = now + d, fn = fn } end
function C_Timer.NewTicker(d, fn, n)
  local tk = { cancelled = false, left = n }
  function tk.Cancel(self) self.cancelled = true end
  local function tick()
    if tk.cancelled then return end
    fn(tk)
    if tk.left then tk.left = tk.left - 1; if tk.left <= 0 then return end end
    if not tk.cancelled then C_Timer.After(math.max(d, 0.01), tick) end
  end
  C_Timer.After(math.max(d, 0.01), tick)
  return tk
end
local function flush(horizon)
  local stop, runs = now + (horizon or 200), 0
  while #timers > 0 and runs < 5000 do
    table.sort(timers, function(a, b) return a.t < b.t end)
    local t = table.remove(timers, 1)
    if t.t > stop then table.insert(timers, 1, t); break end
    now = math.max(now, t.t)
    runs = runs + 1
    t.fn()
  end
  now = now + 1
end

local function fire(event, ...)
  local list = {}
  for i, f in ipairs(events[event] or {}) do list[i] = f end
  for _, f in ipairs(list) do run(f, "OnEvent", event, ...) end
end

---------------------------------------------------------------------------
-- Sample data: a Leatherworker at 160/225 (and a Cook), plausible prices
---------------------------------------------------------------------------

local NAMES = {
  [2318] = "Light Leather", [2319] = "Medium Leather", [4234] = "Heavy Leather", [4235] = "Heavy Hide",
  [4236] = "Cured Heavy Hide", [4289] = "Salt", [4291] = "Silken Thread", [2321] = "Fine Thread",
  [2320] = "Coarse Thread", [2325] = "Black Dye", [8167] = "Turtle Scale", [3383] = "Elixir of Wisdom",
  [4265] = "Heavy Armor Kit", [4253] = "Barbaric Gloves", [5964] = "Barbaric Shoulders", [7277] = "Light Leather Bracers",
  [4249] = "Hillman's Belt", [7373] = "Dusky Leather Leggings", [8347] = "Turtle Scale Gloves", [8385] = "Pattern: Turtle Scale Gloves",
  [2672] = "Stringy Wolf Meat", [2680] = "Spiced Wolf Meat", [2678] = "Mild Spices", [5966] = "Guardian Gloves",
}
local SELL = { [4265] = 700, [4253] = 1500, [5964] = 1800, [7277] = 100, [4249] = 600, [4236] = 100, [7373] = 2400,
  [8347] = 2500, [4234] = 150, [2680] = 50, [5966] = 2200 }
local bags = { [4234] = 12, [4236] = 3, [4253] = 2, [4249] = 4, [4289] = 30, [5964] = 3 }

C_Item = {}
function C_Item.GetItemNameByID(id) return NAMES[id] end
function C_Item.GetItemIconByID(id) return "Interface\\Icons\\INV_Misc_" .. id end
function C_Item.RequestLoadItemDataByID() end
function C_Item.GetItemInfo(id)
  if not NAMES[id] then return nil end
  return NAMES[id], nil, 1, 1, 1, "Trade Goods", "Leather", 20, "", "icon", SELL[id] or 0
end
function C_Item.GetItemCount(id) return bags[id] or 0 end
function C_Item.GetItemInfoInstant(id) return NAMES[id] and id or nil end
GetItemCount = C_Item.GetItemCount

C_TradeSkillUI = {}
openRecipeCalls = 0
function C_TradeSkillUI.OpenRecipe() openRecipeCalls = openRecipeCalls + 1 end
function C_TradeSkillUI.OpenTradeSkill() end
function C_TradeSkillUI.IsTradeSkillReady() return false end
function C_TradeSkillUI.IsDataSourceChanging() return false end
function C_TradeSkillUI.GetBaseProfessionInfo() return { professionName = "Leatherworking", professionID = 165 } end
function C_TradeSkillUI.GetAllRecipeIDs() return {} end

C_AuctionHouse = {}
function C_AuctionHouse.ConfirmCommoditiesPurchase() end
function C_AuctionHouse.MakeItemKey(id) return { itemID = id } end
function C_AuctionHouse.GetItemKeyInfo() return { itemName = "x" } end
function C_AuctionHouse.IsThrottledMessageSystemReady() return true end
function C_AuctionHouse.GetCommoditySearchResultInfo(_, i) return i <= 2 and { unitPrice = 290 + i * 10, quantity = 20 } or nil end
function C_AuctionHouse.GetNumCommoditySearchResults() return 2 end
function C_AuctionHouse.GetItemSearchResultInfo() return { quantity = 1, buyoutAmount = 5000 } end
function C_AuctionHouse.ReplicateItems() end
function C_AuctionHouse.GetNumReplicateItems() return 0 end
function C_AuctionHouse.CalculateCommodityDeposit() return 30 end

AuctionHouseFrameDisplayMode = { Buy = 1, CommoditiesBuy = 2, ItemBuy = 3 }
AuctionHouseFrameMixin = { Event = { CommoditiesQuantitySelectionChanged = "qty" } }
AuctionHouseFrame = CreateFrame("Frame", "AuctionHouseFrame", UIParent)
AuctionHouseFrame:SetSize(800, 540)
AuctionHouseFrame:Hide()
local ahMode = 1
function AuctionHouseFrame.SelectBrowseResult() ahMode = 2 end
function AuctionHouseFrame.GetDisplayMode() return ahMode end
function AuctionHouseFrame.SetDisplayMode(_, m) ahMode = m end
function AuctionHouseFrame.TriggerEvent() end

MerchantFrame = CreateFrame("Frame", "MerchantFrame", UIParent)
MerchantFrame:Hide()
local MERCHANT = { { 2321, 100, 1 }, { 4289, 50, 5 }, { 4291, 600, 1 }, { 2325, 1000, 1 } }
function GetMerchantNumItems() return #MERCHANT end
function GetMerchantItemID(i) return MERCHANT[i] and MERCHANT[i][1] end
function GetMerchantItemInfo(i)
  local m = MERCHANT[i]
  if not m then return nil end
  return NAMES[m[1]], "icon", m[2] * m[3], m[3], -1, true, nil, false
end
function GetMerchantItemMaxStack() return 20 end
function BuyMerchantItem(index, qty)
  local id = MERCHANT[index][1]
  bags[id] = (bags[id] or 0) + qty
end

local bagSlots = { { itemID = 5964, stackCount = 3 }, { itemID = 4236, stackCount = 3 }, { itemID = 4253, stackCount = 2 }, { itemID = 4249, stackCount = 4 }, { itemID = 4234, stackCount = 12 } }
C_Container = {}
function C_Container.GetContainerNumSlots(bag) return bag == 0 and #bagSlots or 0 end
function C_Container.GetContainerItemInfo(bag, slot)
  local s = bag == 0 and bagSlots[slot]
  if not s or s.sold then return nil end
  return { itemID = s.itemID, stackCount = s.stackCount, isLocked = false }
end
function C_Container.UseContainerItem(bag, slot)
  local s = bagSlots[slot]
  if bag == 0 and s and not s.sold then s.sold = true; bags[s.itemID] = math.max(0, (bags[s.itemID] or 0) - s.stackCount) end
end

ProfessionsFrame = CreateFrame("Frame", "ProfessionsFrame", UIParent)
ProfessionsFrame:SetSize(900, 600)
ProfessionsFrame.CloseButton = CreateFrame("Button", nil, ProfessionsFrame)
ProfessionsFrame:Hide()

function GetNumFactions() return 0 end
function GetFactionInfo() return nil end
function GetProfessions() return 1, 2 end
function GetProfessionInfo(i)
  if i == 1 then return "Leatherworking", nil, 160, 225 end
  return "Cooking", nil, 100, 150
end

---------------------------------------------------------------------------
-- Load the addon in .toc order
---------------------------------------------------------------------------

local ns = {}
local toc = assert(io.open("Margin/Margin.toc")):read("*a")
local files = {}
for line in toc:gmatch("[^\r\n]+") do
  if line:match("^[%w_./\\-]+%.lua%s*$") then files[#files + 1] = line:gsub("%s+$", "") end
end
assert(#files > 10, "read the .toc")
for _, f in ipairs(files) do
  local chunk = assert(loadfile("Margin/" .. f))
  chunk("Margin", ns)
end
fire("ADDON_LOADED", "Margin")

local function recipe(id, name, out, diff, trivial, reagents, extra)
  local r = { id = id, name = name, icon = "Interface\\Icons\\R" .. id, diff = diff, trivial = trivial, ups = 1,
    out = out, qty = 1, reagents = {}, prof = "Leatherworking" }
  for i = 1, #reagents, 2 do r.reagents[#r.reagents + 1] = { item = reagents[i], count = reagents[i + 1] } end
  for k, v in pairs(extra or {}) do r[k] = v end
  return r
end

local t0 = time()
MarginDB.prices = {}
for id, p in pairs({ [4234] = 300, [4235] = 400, [8167] = 500, [8385] = 15000, [2318] = 40, [2672] = 30, [5966] = 9000 }) do
  MarginDB.prices[id] = { p = p, t = t0 }
end
MarginDB.vendor = { [4289] = { low = 50, high = 50 }, [4291] = { low = 600, high = 600 }, [2321] = { low = 100, high = 100 },
  [2320] = { low = 10, high = 10 }, [2325] = { low = 1000, high = 1000 }, [2678] = { low = 20, high = 20 } }
MarginDB.depth = { [4234] = { t = t0, p = { 300, 50, 350, 40 } } }
MarginDB.chars = { ["Tester-Realm"] = {
  profs = {
    Leatherworking = { id = 165, skill = 160, max = 225, scanSkill = 160, time = t0,
      recipes = {
        recipe(3780, "Heavy Armor Kit", 4265, 1, 170, { 4234, 5, 2320, 1 }),
        recipe(3771, "Barbaric Gloves", 4253, 0, 175, { 4234, 4, 4236, 1, 4291, 2 }),
        recipe(3818, "Cured Heavy Hide", 4236, 2, 170, { 4235, 1, 4289, 3 }),
        recipe(3779, "Barbaric Shoulders", 5964, 0, 180, { 4234, 8, 4236, 1, 2321, 2 }),
        recipe(9065, "Light Leather Bracers", 7277, 3, 100, { 2318, 6, 2320, 4 }),
        recipe(3767, "Hillman's Belt", 4249, 2, 165, { 2319, 4, 2321, 1 }),
        recipe(3770, "Guardian Gloves", 5966, 0, 190, { 4234, 4, 4236, 1, 3383, 1 }),
        recipe(3777, "Heavy Leather Ball", nil, 1, 175, { 4234, 2, 2321, 1 }),
      },
      unlearned = {
        recipe(9195, "Dusky Leather Leggings", 7373, 0, 195, { 4234, 10, 2325, 2 }, { train = { rank = 165, fee = 1500 } }),
        recipe(10518, "Turtle Scale Gloves", 8347, 0, 205, { 4234, 6, 8167, 8 }, { teach = { { item = 8385, rank = 175, rep = false } } }),
      },
      every = { recipe(10520, "Big Voodoo Robe", nil, 0, 215, { 4234, 10 }, { extra = true }) },
    },
    Cooking = { id = 185, skill = 100, max = 150, scanSkill = 100, time = t0,
      recipes = { recipe(2546, "Spiced Wolf Meat", 2680, 0, 130, { 2672, 1, 2678, 1 }, { prof = "Cooking" }) } },
  },
  history = { Leatherworking = {
    { t = t0 - 2 * 86400, from = 150, to = 155, id = 3780, name = "Heavy Armor Kit", icon = "i", crafts = 7, cost = 12000 },
    { t = t0 - 86400, from = 155, to = 160, id = 3771, name = "Barbaric Gloves", icon = "i", crafts = 5, cost = 21000 },
  } },
} }
fire("PLAYER_LOGIN")

---------------------------------------------------------------------------
-- Helpers to drive the frames
---------------------------------------------------------------------------

local clicks = 0
local function click(f, button)
  assert(f, "click on nil")
  local s = f:GetScript("OnClick")
  assert(s, "no OnClick on a clicked control")
  clicks = clicks + 1
  s(f, button or "LeftButton", false)
  flush(3) -- short of the 6 s a "Sure?" stays armed, so two clicks confirm

end

local function hover(f)
  local e = f:GetScript("OnEnter")
  if e then e(f) end
  local l = f:GetScript("OnLeave")
  if l then l(f) end
end

local function shownRows(list)
  local out = {}
  for _, r in ipairs(list.rows) do if r:IsShown() and r.entry then out[#out + 1] = r end end
  return out
end

local function visitRows(list, doClick)
  for _, r in ipairs(shownRows(list)) do
    hover(r)
    if doClick and r.entry and r.entry.kind ~= "section" then click(r) end
  end
  local wheel = list:GetScript("OnMouseWheel")
  wheel(list, -1); wheel(list, -1); wheel(list, 1); wheel(list, 5)
end

local function sectionRow(list, key)
  list:SetOffset(0)
  for _, r in ipairs(shownRows(list)) do
    if r.entry.kind == "section" and r.entry.key == key then return r end
  end
end

local function kinds(list)
  local seen = {}
  for _, e in ipairs(list.entries) do seen[e.kind] = (seen[e.kind] or 0) + 1 end
  return seen
end

---------------------------------------------------------------------------
-- The Ledger window
---------------------------------------------------------------------------

assert(ns.Layouts.activeName() == "ledger", "Ledger is the default layout")
ns.SetProfession("Leatherworking")
SlashCmdList.MARGIN("")
local ledger = ns.Layouts.get("ledger")
local win = ledger.frame()
assert(win and win:IsShown(), "the Ledger window opens")
local inEscape = false
for _, n in ipairs(UISpecialFrames) do if n == "MarginLedger" then inEscape = true end end
assert(inEscape, "Escape closes the Ledger")

for _, tab in ipairs(win.tabs.tabs) do
  click(tab)
  assert(ns.S.tab == tab.key)
  -- every chip through all its values
  for key, chip in pairs(win.chips) do
    if chip:IsShown() then
      for _ = 1, #ns.UI.chips[key].values do click(chip); hover(chip) end
    end
  end
  -- sorting: click, click again to reverse, right-click resets
  for _, b in ipairs(win.cols) do
    if b:IsShown() and b.sort then
      click(b); click(b); hover(b); click(b, "RightButton")
      assert(ns.S.sortCol == nil, "right-click resets the sort")
    end
  end
  click(win.cols[2]) -- leave a sort on for the row pass
  if win.search:IsShown() then
    win.search:SetFocus()
    win.search:SetText("heavy")
    win.search:GetScript("OnTextChanged")(win.search, true)
    win.search:GetScript("OnEscapePressed")(win.search)
  end
  visitRows(win.list, true)
  click(win.cols[2], "RightButton")
end

-- Profit tab: all recipes show the unlearned ones; their rows say how to learn them
click(win.tabs.tabs[1])
ns.SetOpt("profitScope", "all")
ns.RefreshUI()
local blue = 0
for _, e in ipairs(win.list.entries) do if e.kind == "recipe" and e.unlearned then blue = blue + 1 end end
assert(blue >= 2, "unlearned recipes listed with the all scope")
visitRows(win.list, true)
ns.SetOpt("profitScope", "known")

-- Route tab: cards, sections, history and stock, Re-plan
click(win.tabs.tabs[3])
assert(ns.S.tab == "route")
local k = kinds(win.list)
assert(k.section and k.step and k.shop, "route list has sections, steps and a shopping list")
for i, c in ipairs(win.cards) do
  assert(c:IsShown(), "card " .. i .. " shown")
  hover(c)
  click(c)
end
ns.SetOpt("resale", "vendor"); ns.SetOpt("useTrainer", true); ns.RefreshUI()
for _, key in ipairs({ "history", "stock" }) do
  local r = sectionRow(win.list, key)
  assert(r, "section " .. key .. " present")
  hover(r)
  click(r)
end
assert(ns.S.showHistory and ns.S.showStock, "history and stock expanded")
k = kinds(win.list)
assert(k.history and k.stock, "expanded rows listed")
-- shopping list by step: clicking its band walks the steps and back to the whole route, and a step's list is
-- smaller than the whole route's
do
  local plan = ns.CurrentPlan()
  local steps = ns.ShopSteps(plan)
  local function sectionRow(list, key) -- the shopping band is at the bottom: scroll to it
    for i, e in ipairs(list.entries) do
      if e.kind == "section" and e.key == key then list:SetOffset(i - 1) end
    end
    for _, r in ipairs(shownRows(list)) do
      if r.entry.kind == "section" and r.entry.key == key then return r end
    end
  end
  assert(#steps >= 1, "route has steps with their own shopping")
  local band = sectionRow(win.list, "shop")
  assert(band and band.entry.pick, "shopping band offers a step choice")
  assert(ns.S.shopStep == nil)
  click(band)
  assert(ns.S.shopStep == steps[1].index, "first click shows the first step")
  assert(#(ns.ShopOf(plan)) <= #plan.shop)
  for _ = 1, #steps do click(sectionRow(win.list, "shop")) end
  assert(ns.S.shopStep == nil, "after the last step the whole route returns")
  SlashCmdList.MARGIN("step 1")
  assert(ns.S.shopStep == steps[1].index, "/margin step 1")
  SlashCmdList.MARGIN("step all")
  assert(ns.S.shopStep == nil, "/margin step all")
end
for _ = 1, 30 do visitRows(win.list, true) end
win.list:SetOffset(0)
for i = 1, 40 do
  visitRows(win.list, true)
  win.list:SetOffset(i * 3)
end
click(win.replan)
hover(win.replan)
ns.SetOpt("routeLock", false); ns.RefreshUI(); ns.SetOpt("routeLock", true); ns.RefreshUI()

-- profession dropdown
click(win.prof)
assert(win.prof.menu:IsShown(), "dropdown opens")
click(win.prof.menu.items[1]) -- Cooking (sorted)
assert(ns.S.prof == "Cooking", "profession chosen from the dropdown")
for _, tab in ipairs(win.tabs.tabs) do click(tab); visitRows(win.list, true) end
click(win.prof); click(win.prof.menu.items[2])
assert(ns.S.prof == "Leatherworking")

-- Settings panel: every control
click(win.gear)
assert(win.settings:IsShown(), "settings open")
for _, ctl in ipairs(win.settings.controls) do
  local def = ctl.def
  if def.key ~= "theme" then
    if def.kind == "segmented" then
      for _, b in ipairs(ctl.buttons) do click(b) end
      click(ctl.buttons[1])
    elseif def.kind == "check" then
      click(ctl); click(ctl); hover(ctl)
    else
      ctl:SetFocus(); ctl:SetText("30"); ctl:GetScript("OnEnterPressed")(ctl)
      ctl:SetFocus(); ctl:SetText("x"); ctl:GetScript("OnEscapePressed")(ctl)
    end
  end
end
assert(ns.Opt("ahCut") == 0.3 and ns.Opt("routeTarget") == 30, "number boxes store their values")
ns.SetOpt("ahCut", 0.05); ns.SetOpt("ahChance", 0.8); ns.SetOpt("routeTarget", nil); ns.RefreshUI()
click(win.settings.close)
assert(not win.settings:IsShown())

-- the theme control in Settings switches to classic, live
click(win.gear)
for _, ctl in ipairs(win.settings.controls) do
  if ctl.def.key == "theme" then
    for _, b in ipairs(ctl.buttons) do if b.value == "classic" then click(b) end end
  end
end
assert(ns.Layouts.activeName() == "classic" and not win:IsShown() and MarginFrame:IsShown(), "switched to classic live")
assert(ns.T.current == "classic", "classic palette")

---------------------------------------------------------------------------
-- The classic window (the fallback layout)
---------------------------------------------------------------------------

local cf = MarginFrame
for _, b in ipairs({ cf.tProfit, cf.tLevel, cf.tRoute }) do
  click(b)
  click(cf.tSort); click(cf.tSort); click(cf.tSort)
  click(cf.tAll); click(cf.tAll)
  if cf.scope:IsShown() then click(cf.scope); click(cf.scope) end
  for _, h in ipairs(cf.hdr) do click(h); click(h); hover(h); click(h, "RightButton") end
  for _, r in ipairs(cf.rows) do if r:IsShown() then hover(r); click(r) end end
  if cf.replan:IsShown() then click(cf.replan); hover(cf.replan) end
  for _, c in ipairs(cf.cards) do if c:IsShown() then click(c) end end
end
click(cf.rep); click(cf.rep); hover(cf.rep)
click(cf.tProf)
SlashCmdList.MARGIN("theme ledger")
assert(ns.Layouts.activeName() == "ledger" and win:IsShown() and not cf:IsShown(), "back to the Ledger")

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

for _, cmd in ipairs({ "theme", "theme bogus", "odds typical", "odds worst", "lock", "lock", "rep", "rep",
  "route 200", "route", "chance 70", "chance 80", "cut 5", "coverage", "list", "list", "buy", "debug", "debug",
  "report", "dump", "autoscan on", "autoscan off", "autoscan", "fullscan", "scan" }) do
  SlashCmdList.MARGIN(cmd)
  flush()
end

---------------------------------------------------------------------------
-- Craft planner (a Profit row click)
---------------------------------------------------------------------------

click(win.tabs.tabs[1])
for _, r in ipairs(shownRows(win.list)) do
  if r.entry.quote then click(r); break end
end
assert(MarginQuote and MarginQuote:IsShown(), "craft planner opens from a Profit row")
for _, key in ipairs({ "minus", "plus", "max", "open" }) do
  if MarginQuote[key] then click(MarginQuote[key]) end
end
for _, b in ipairs(MarginQuote.presets or {}) do click(b) end
-- type a quantity, then Best, then open it: the open button must call the protected API inside the click
MarginQuote.edit:SetFocus(); MarginQuote.edit:SetText("7"); MarginQuote.edit:GetScript("OnEnterPressed")(MarginQuote.edit)
assert(MarginDB.quoteQty and next(MarginDB.quoteQty) and select(2, next(MarginDB.quoteQty)) == 7, "typed quantity kept")
hover(MarginQuote.best)
click(MarginQuote.best)
local before = openRecipeCalls
MarginQuote.open:GetScript("OnClick")(MarginQuote.open, "LeftButton")
assert(openRecipeCalls == before + 1, "Quote's open button selects the recipe inside the click, not from a timer")
flush()
MarginQuote:Hide()

-- a Leveling row click reaches C_TradeSkillUI.OpenRecipe in the same call
click(win.tabs.tabs[2])
for _, r in ipairs(shownRows(win.list)) do
  local e = r.entry
  if e.craft and not e.craft.learnFirst then
    before = openRecipeCalls
    r:GetScript("OnClick")(r, "LeftButton")
    assert(openRecipeCalls == before + 1, "a row click selects the recipe synchronously")
    break
  end
end
flush()

-- item names arriving only redraw: no re-planning, no dropped plans
click(win.tabs.tabs[3])
local S2 = ns.S
S2.showHistory, S2.showStock = true, true
ns.SetProfession("Leatherworking")
ns.RefreshUI()
local k2 = kinds(win.list)
assert(k2.history and k2.stock and k2.shop, "Route tab with history and stock expanded")
-- one redraw first: the first plan after a re-plan creates the lock, and the locked route is planned once
-- more under its lock (that is the planner's own cache, not the names path)
ns.RedrawUI()
local plans, invalidations = 0, 0
local realPlan, realInvalidate = ns.Plan, ns.InvalidatePlan
ns.Plan = function(...) plans = plans + 1; return realPlan(...) end
ns.InvalidatePlan = function(...) invalidations = invalidations + 1; return realInvalidate(...) end
local oldEntries = win.list.entries
for _ = 1, 5 do fire("GET_ITEM_INFO_RECEIVED", 4234, true) end
flush()
assert(win.list.entries ~= oldEntries, "the names redraw happened")
assert(plans == 0 and invalidations == 0, ("GET_ITEM_INFO_RECEIVED re-planned (%d plans, %d invalidations)"):format(plans, invalidations))
ns.Plan, ns.InvalidatePlan = realPlan, realInvalidate

---------------------------------------------------------------------------
-- Auction house: the strip, the lookup, the shopping list
---------------------------------------------------------------------------

AuctionHouseFrame:Show()
fire("AUCTION_HOUSE_SHOW")
flush()
assert(MarginAHStrip and MarginAHStrip:IsShown(), "AH strip shown")
for _, seg in ipairs(MarginAHStrip.segments) do hover(seg) end
click(MarginAHStrip.scan); click(MarginAHStrip.scan); click(MarginAHStrip.scan)
click(MarginAHStrip.full)
if not MarginShopping or not MarginShopping:IsShown() then click(MarginAHStrip.list) end
assert(MarginShopping and MarginShopping:IsShown(), "shopping list open at the AH")
click(MarginAHStrip.lookup, "RightButton")
click(MarginAHStrip.lookup)
fire("COMMODITY_SEARCH_RESULTS_UPDATED", 4234)
fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
flush()
click(MarginShopping.step); hover(MarginShopping.step) -- one step's list
ns.RefreshShopping()
click(MarginShopping.step)
while ns.S.shopStep do click(MarginShopping.step) end
for _, r in ipairs(shownRows(MarginShopping.list)) do
  hover(r)
  if r.search and r.search:IsShown() then click(r.search) end
end
fire("COMMODITY_PURCHASE_SUCCEEDED")
fire("BAG_UPDATE_DELAYED")
flush()
ns.SetTheme("classic"); ns.SetTheme("ledger") -- companions repaint while open
fire("AUCTION_HOUSE_CLOSED")
AuctionHouseFrame:Hide()
flush()

---------------------------------------------------------------------------
-- Vendor: buy and sell
---------------------------------------------------------------------------

ns.SetProfession("Leatherworking")
ns.RefreshUI()
MerchantFrame:Show()
fire("MERCHANT_SHOW")
flush()
assert(MarginMerchant and MarginMerchant:IsShown(), "vendor popup opens beside a vendor that sells route items")
local m = MarginMerchant
for _, b in ipairs(m.mode.buttons) do
  click(b)
  for _, r in ipairs(shownRows(m.list)) do
    hover(r)
    if r.action and r.action:IsShown() then click(r.action); click(r.action); flush() end
  end
  click(m.all)
  click(m.all)
  if m.skipAH:IsShown() then click(m.skipAH); click(m.skipAH) end
  hover(m.all)
end
fire("ADDON_ACTION_FORBIDDEN", "Margin")
fire("MERCHANT_UPDATE")
fire("PLAYER_MONEY")
flush()
fire("MERCHANT_CLOSED")
MerchantFrame:Hide()

---------------------------------------------------------------------------
-- Profession window button
---------------------------------------------------------------------------

ProfessionsFrame:Show()
fire("TRADE_SKILL_SHOW")
flush()
assert(MarginProfessionButton and MarginProfessionButton:IsShown(), "Margin button on the profession window")
hover(MarginProfessionButton)
win:Hide()
click(MarginProfessionButton)
assert(win:IsShown(), "the profession button opens the window")

-- events the addon listens to, fired once each with the windows open
for _, e in ipairs({ "SKILL_LINES_CHANGED", "GET_ITEM_INFO_RECEIVED", "BAG_UPDATE_DELAYED", "UPDATE_FACTION",
  "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED" }) do
  fire(e, 3771)
  flush()
end

-- closing and reopening
SlashCmdList.MARGIN("")
assert(not win:IsShown())
SlashCmdList.MARGIN("")
assert(win:IsShown())

print = realPrint
if os.getenv("SMOKE_CHAT") then for _, l in ipairs(printed) do print("  chat: " .. l) end end
print(("%d clicks, %d frames, %d chat lines"):format(clicks, #allFrames, #printed))
print("ui smoke ok")
