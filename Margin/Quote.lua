local _, ns = ...

-- The craft planner: click a recipe on the Profit tab, pick how many to craft, and see what to buy, what
-- it costs and what you would net. The numbers come from ns.Quote (Calc.lua); this is only the window.

local ROWS, ROW_H, WIDTH = 9, 22, 400
local frame, recipe, qty, offset = nil, nil, 1, 0
local quote

local function money(c) return ns.Money(c) end

-- Profit or loss the same way as everywhere: green + earn, red - lose.
local function signed(p)
  if p == nil then return "|cff909090?|r" end
  local r = math.floor(math.abs(p) + 0.5)
  if r == 0 then return money(0) end
  return (p > 0 and "|cff60ff60+|r" or "|cffff6060-|r") .. money(r)
end

local function itemName(id)
  local n = C_Item.GetItemNameByID(id)
  if not n then C_Item.RequestLoadItemDataByID(id) end
  return n or ("item " .. id)
end

local function setQty(n)
  qty = math.max(1, math.min(9999, math.floor(tonumber(n) or 1)))
  MarginDB.quoteQty = MarginDB.quoteQty or {}
  if recipe then MarginDB.quoteQty[recipe.id] = qty end
  offset = 0
  ns.RefreshQuote()
end

local function build()
  frame = CreateFrame("Frame", "MarginQuote", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(WIDTH, 470)
  frame:SetPoint("CENTER", 120, 0)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)         -- clicking it raises it above the other Margin windows
  frame:SetClampedToScreen(true)
  frame:SetScript("OnMouseWheel", function(_, d)
    local max = quote and math.max(0, #quote.list - ROWS) or 0
    offset = math.max(0, math.min(max, offset - d * 2))
    ns.RefreshQuote()
  end)
  frame:Hide()
  tinsert(UISpecialFrames, "MarginQuote")
  frame.TitleText:SetText("Craft plan")

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetSize(30, 30)
  frame.icon:SetPoint("TOPLEFT", 14, -32)
  frame.name = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.name:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 8, -1)
  frame.name:SetWidth(WIDTH - 70)
  frame.name:SetJustifyH("LEFT")
  frame.name:SetWordWrap(false)
  frame.sub = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.sub:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -2)
  frame.sub:SetWidth(WIDTH - 70)
  frame.sub:SetJustifyH("LEFT")
  frame.sub:SetWordWrap(false)

  -- how many to craft
  frame.qtyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.qtyLabel:SetPoint("TOPLEFT", 14, -76)
  frame.qtyLabel:SetText("Crafts")
  local function small(text, x, w, click)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, -72)
    b:SetText(text)
    b:SetScript("OnClick", click)
    return b
  end
  frame.minus = small("-", 64, 24, function() setQty(qty - (IsShiftKeyDown() and 10 or 1)) end)
  frame.edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  frame.edit:SetSize(46, 20)
  frame.edit:SetPoint("TOPLEFT", 98, -73)
  frame.edit:SetAutoFocus(false)
  frame.edit:SetNumeric(true)
  frame.edit:SetMaxLetters(4)
  frame.edit:SetJustifyH("CENTER")
  frame.edit:SetScript("OnEnterPressed", function(self) self:ClearFocus(); setQty(self:GetText()) end)
  frame.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus(); self:SetText(tostring(qty)) end)
  frame.edit:SetScript("OnEditFocusLost", function(self) setQty(self:GetText()) end)
  frame.plus = small("+", 150, 24, function() setQty(qty + (IsShiftKeyDown() and 10 or 1)) end)
  local x = 184
  frame.presets = {}
  for _, n in ipairs({ 5, 10, 25 }) do
    frame.presets[#frame.presets + 1] = small(tostring(n), x, 34, function() setQty(n) end)
    x = x + 36
  end
  frame.max = small("Max", x, 44, function() if quote and quote.maxHeld > 0 then setQty(quote.maxHeld) end end)
  frame.max:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Most you can craft from what you already hold")
    GameTooltip:AddLine("Counts the base materials in your bags and bank. +/- change by 1, or 10 with Shift.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  frame.max:SetScript("OnLeave", GameTooltip_Hide)

  -- the money, at a glance
  frame.sum = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.sum:SetPoint("TOPLEFT", 14, -104)
  frame.sum:SetWidth(WIDTH - 28)
  frame.sum:SetJustifyH("LEFT")
  frame.sum:SetSpacing(3)
  frame.warn = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.warn:SetPoint("TOPLEFT", 14, -190)
  frame.warn:SetWidth(WIDTH - 28)
  frame.warn:SetJustifyH("LEFT")
  frame.warn:SetTextColor(1, 0.82, 0.4)

  frame.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 36, ROW_H)
    row:SetPoint("TOPLEFT", 14, -214 - (i - 1) * ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 0, 0)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(170)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.mid = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.mid:SetPoint("LEFT", 196, 0)
    row.mid:SetWidth(76)
    row.mid:SetJustifyH("RIGHT")
    row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.right:SetPoint("LEFT", 276, 0)
    row.right:SetWidth(88)
    row.right:SetJustifyH("RIGHT")
    frame.rows[i] = row
  end

  frame.open = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.open:SetSize(WIDTH - 28, 24)
  frame.open:SetPoint("BOTTOM", 0, 14)
  frame.open:SetScript("OnClick", function()
    if not recipe then return end
    ns.OpenRecipe(recipe.id, qty, recipe.prof)
  end)
end

function ns.RefreshQuote()
  if not (frame and frame:IsShown() and recipe) then return end
  quote = ns.Quote(recipe, qty)
  local r = recipe
  frame.icon:SetTexture(r.icon)
  frame.name:SetText(r.name)
  frame.sub:SetText(("makes %d x %s"):format(quote.units, r.out and itemName(r.out) or "nothing you can sell"))
  if not frame.edit:HasFocus() then frame.edit:SetText(tostring(qty)) end
  frame.max:SetEnabled(quote.maxHeld > 0)

  local L = {}
  L[#L + 1] = ("You pay now        %s"):format(money(quote.cash))
  L[#L + 1] = ("All reagents        %s  |cff909090(held ones at market price)|r"):format(money(quote.fullCost))
  if r.out then
    L[#L + 1] = ("Sells for          vendor %s   AH %s"):format(
      quote.revenue.vendor and money(quote.revenue.vendor) or "|cff909090?|r",
      quote.revenue.ah and money(quote.revenue.ah) or "|cff909090?|r")
    L[#L + 1] = ("|cffffd700Net profit|r        vendor %s   AH %s"):format(signed(quote.profit.vendor), signed(quote.profit.ah))
  else
    L[#L + 1] = "|cff909090This recipe makes nothing you can sell.|r"
  end
  frame.sum:SetText(table.concat(L, "\n"))

  local warns = {}
  if r.train or r.teach or r.extra then warns[#warns + 1] = "You have not learned this recipe yet." end
  if quote.unpriced > 0 then warns[#warns + 1] = ("%d reagent%s with no price: profit not shown."):format(quote.unpriced, quote.unpriced > 1 and "s" or "") end
  if #quote.short > 0 then
    local names = {}
    for _, id in ipairs(quote.short) do names[#names + 1] = itemName(id) end
    warns[#warns + 1] = "Not enough on the AH: " .. table.concat(names, ", ") .. "."
  end
  frame.warn:SetText(table.concat(warns, " "))

  -- the list: what to make first, then what to buy (still-to-buy first)
  local list = {}
  for _, m in ipairs(quote.made) do
    if m.crafts > 0 then
      list[#list + 1] = { icon = m.recipe.icon, name = "|cff9fb4ffmake|r " .. m.recipe.name .. (m.have > 0 and (" |cff909090(have %d)|r"):format(m.have) or ""),
        mid = ("~%d crafts"):format(m.crafts), right = m.unit and money(m.unit * m.units) or "?" }
    end
  end
  for _, s in ipairs(quote.shop) do
    local flag = s.short > 0 and (" |cffff6060(AH has %d)|r"):format(s.sup or 0) or ""
    list[#list + 1] = { icon = C_Item.GetItemIconByID(s.item),
      name = itemName(s.item) .. (s.have > 0 and (" |cff909090(have %d)|r"):format(s.have) or "") .. flag,
      mid = s.buy == 0 and "|cff60ff60have enough|r" or ("buy " .. s.buy),
      right = s.buy == 0 and "" or (s.cost and money(s.cost) or "|cff909090no price|r") }
  end
  quote.list = list
  local max = math.max(0, #list - ROWS)
  if offset > max then offset = max end
  for i = 1, ROWS do
    local row, e = frame.rows[i], list[i + offset]
    if e then
      row.icon:SetTexture(e.icon)
      row.name:SetText(e.name)
      row.mid:SetText(e.mid)
      row.right:SetText(e.right)
      row:Show()
    else
      row:Hide()
    end
  end
  frame.open:SetText(("Open in profession window, craft %d"):format(qty))
  frame.open:SetEnabled(not (r.train or r.teach or r.extra))
end

-- Open the planner for a recipe (the recipe table from a Profit/Leveling row, `row.r`).
function ns.OpenQuote(r)
  if not r then return end
  if not frame then build() end
  recipe = r
  qty = math.max(1, (MarginDB.quoteQty and MarginDB.quoteQty[r.id]) or 5)
  offset = 0
  -- beside the main window when it is open (never on top of it), else the middle of the screen
  local main = _G.MarginFrame
  frame:ClearAllPoints()
  if main and main:IsShown() then
    frame:SetPoint("TOPLEFT", main, "TOPRIGHT", 6, 0)
    frame:SetFrameLevel(main:GetFrameLevel() + 10)
  else
    frame:SetPoint("CENTER", 120, 0)
  end
  frame:Show()
  frame:Raise()
  ns.RefreshQuote()
end

-- prices and bags move: keep an open planner current
local ev = CreateFrame("Frame")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:SetScript("OnEvent", function() if frame and frame:IsShown() then ns.RefreshQuote() end end)
