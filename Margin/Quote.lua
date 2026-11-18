local _, ns = ...

-- The craft planner: click a recipe on the Profit tab, pick how many to craft, and see what to buy, what
-- it costs and what you would net. The numbers come from ns.Quote (Calc.lua); this is only the window.

local W, T = ns.W, ns.T
local ROWS, ROW_H, WIDTH = 9, 22, 400
local frame, recipe, qty, offset = nil, nil, 1, 0
local quote

local function money(c) return T.Money(c) end

-- Profit or loss the same way as everywhere: green + earn, red - lose.
local function signed(p)
  if p == nil then return T.C("dim", "?") end
  return T.Signed(p)
end

local itemName = ns.ItemName

local function setQty(n)
  qty = math.max(1, math.min(9999, math.floor(tonumber(n) or 1)))
  MarginDB.quoteQty = MarginDB.quoteQty or {}
  if recipe then MarginDB.quoteQty[recipe.id] = qty end
  offset = 0
  ns.RefreshQuote()
end

local function build()
  frame = W.Window({ name = "MarginQuote", title = "Craft plan", width = WIDTH, height = 470, point = { "CENTER", 120, 0 } })
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, d)
    local max = quote and math.max(0, #quote.list - ROWS) or 0
    offset = math.max(0, math.min(max, offset - d * 2))
    ns.RefreshQuote()
  end)

  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetSize(30, 30)
  frame.icon:SetPoint("TOPLEFT", 14, -36)
  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame.name = W.Text(frame, "title", "white")
  frame.name:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 8, -1)
  frame.name:SetWidth(WIDTH - 70)
  frame.sub = W.Text(frame, "label", "dim")
  frame.sub:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -3)
  frame.sub:SetWidth(WIDTH - 70)

  -- how many to craft
  frame.qtyLabel = W.Text(frame, "label", "dim")
  frame.qtyLabel:SetPoint("TOPLEFT", 14, -84)
  frame.qtyLabel:SetText("CRAFTS")
  local function small(text, x, w, click)
    local b = W.Button(frame, { text = text, width = w, height = 22, onClick = click })
    b:SetPoint("TOPLEFT", x, -78)
    return b
  end
  frame.minus = small("-", 64, 24, function() setQty(qty - (IsShiftKeyDown() and 10 or 1)) end)
  frame.edit = W.NumberBox(frame, { width = 46, height = 22, maxLetters = 4,
    onCommit = function(text) setQty(text) end,
    onCancel = function(self) self:SetText(tostring(qty)) end })
  frame.edit:SetNumeric(true)
  frame.edit:SetJustifyH("CENTER")
  frame.edit:SetPoint("TOPLEFT", 92, -78)
  frame.plus = small("+", 142, 24, function() setQty(qty + (IsShiftKeyDown() and 10 or 1)) end)
  local x = 174
  frame.presets = {}
  for _, n in ipairs({ 5, 10, 25 }) do
    frame.presets[#frame.presets + 1] = small(tostring(n), x, 34, function() setQty(n) end)
    x = x + 38
  end
  frame.max = small("Max", x, 48, function() if quote and quote.maxHeld > 0 then setQty(quote.maxHeld) end end)
  W.TipText(frame.max, "Most you can craft from what you already hold",
    "Counts the base materials in your bags and bank. +/- change by 1, or 10 with Shift.", nil, "ANCHOR_TOP")

  -- the money, at a glance
  frame.sum = W.Text(frame, "row", "text")
  frame.sum:SetPoint("TOPLEFT", 14, -112)
  frame.sum:SetWidth(WIDTH - 28)
  frame.sum:SetWordWrap(true)
  frame.sum:SetSpacing(3)
  frame.warn = W.Text(frame, "small", "warn")
  frame.warn:SetPoint("TOPLEFT", 14, -192)
  frame.warn:SetWidth(WIDTH - 28)
  frame.warn:SetWordWrap(true)

  frame.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(WIDTH - 28, ROW_H)
    row:SetPoint("TOPLEFT", 14, -214 - (i - 1) * ROW_H)
    row.sep = W.Solid(row, "white", "BORDER", 0.035)
    row.sep:SetPoint("BOTTOMLEFT"); row.sep:SetPoint("BOTTOMRIGHT"); row.sep:SetHeight(1)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 0, 0)
    row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    row.name = W.Text(row, "row", "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(170)
    row.mid = W.Text(row, "small", "text", "RIGHT")
    row.mid:SetPoint("LEFT", 196, 0)
    row.mid:SetWidth(76)
    row.right = W.Text(row, "small", "text", "RIGHT")
    row.right:SetPoint("LEFT", 276, 0)
    row.right:SetWidth(92)
    frame.rows[i] = row
  end

  frame.open = W.Button(frame, { width = WIDTH - 28, height = 24, primary = true, icon = "hammer", text = "",
    onClick = function()
      if not recipe then return end
      ns.OpenRecipe(recipe.id, qty, recipe.prof)
    end })
  frame.open:SetPoint("BOTTOM", 0, 14)
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
  L[#L + 1] = ("All reagents        %s  %s"):format(money(quote.fullCost), T.C("dim", "(held ones at market price)"))
  if r.out then
    L[#L + 1] = ("Sells for          vendor %s   AH %s"):format(
      quote.revenue.vendor and money(quote.revenue.vendor) or T.C("dim", "?"),
      quote.revenue.ah and money(quote.revenue.ah) or T.C("dim", "?"))
    L[#L + 1] = ("%s        vendor %s   AH %s"):format(T.C("accent", "Net profit"), signed(quote.profit.vendor), signed(quote.profit.ah))
  else
    L[#L + 1] = T.C("dim", "This recipe makes nothing you can sell.")
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
      list[#list + 1] = { icon = m.recipe.icon, name = T.C("make", "make") .. " " .. m.recipe.name .. (m.have > 0 and T.C("dim", (" (have %d)"):format(m.have)) or ""),
        mid = ("~%d crafts"):format(m.crafts), right = m.unit and money(m.unit * m.units) or "?" }
    end
  end
  for _, s in ipairs(quote.shop) do
    local flag = s.short > 0 and T.C("loss", (" (AH has %d)"):format(s.sup or 0)) or ""
    list[#list + 1] = { icon = C_Item.GetItemIconByID(s.item),
      name = itemName(s.item) .. (s.have > 0 and T.C("dim", (" (have %d)"):format(s.have)) or "") .. flag,
      mid = s.buy == 0 and T.C("profit", "have enough") or ("buy " .. s.buy),
      right = s.buy == 0 and "" or (s.cost and money(s.cost) or T.C("dim", "no price")) }
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
  frame:Show()
  ns.RefreshQuote()
end

-- prices and bags move: keep an open planner current
local ev = CreateFrame("Frame")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:SetScript("OnEvent", function() if frame and frame:IsShown() then ns.RefreshQuote() end end)
