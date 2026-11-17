local _, ns = ...

local ROWS, ROW_H = 16, 20
local frame, tab, profName = nil, "profit", nil
local offset, total = 0, 0
local sortCol, sortAsc = nil, false -- clicked column (1 name, 2 cost, 3 sale, 4 profit/per-up)

local DIFF_COLOR = { [0] = "ff8040", [1] = "ffff00", [2] = "40c040", [3] = "909090" }

local HEADERS = {
  profit = { "Recipe", "Cost", nil, "Profit" },
  level = { "Recipe", "Cost", nil, "Cost / skill-up" },
  route = { "Skill  recipe / shopping list", "Crafts / qty", "Per unit", "Cost" },
}

-- Own formatter: GetCoinTextureString is not available on Forever.
local function money(c)
  if c == nil then return "?" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. "|cffffd700g|r" end
  if g > 0 or sv > 0 then parts[#parts + 1] = sv .. "|cffc0c0c0s|r" end
  parts[#parts + 1] = cp .. "|cffeda55fc|r"
  local out = table.concat(parts, " ")
  return neg and ("|cffff6060-|r" .. out) or out
end
ns.Money = money

local function itemName(id)
  local n = C_Item.GetItemNameByID(id)
  if not n then C_Item.RequestLoadItemDataByID(id) end
  return n or ("item " .. id)
end

local function setOffset(v)
  local max = math.max(0, total - ROWS)
  offset = math.min(math.max(0, math.floor(v + 0.5)), max)
  frame.bar:SetMinMaxValues(0, max)
  frame.bar:SetValue(offset)
  ns.RefreshUI()
end

local function recipeTooltip(d)
  GameTooltip:AddLine(d.r.name)
  for _, l in ipairs(d.lines) do
    GameTooltip:AddDoubleLine(l.count .. "x " .. itemName(l.item),
      l.unit and (money(l.unit * l.count) .. " (" .. l.src .. ")") or "no price", 1, 1, 1, 1, 1, 1)
  end
  GameTooltip:AddDoubleLine("Cost", money(d.cost))
  local vend, ah = ns.Revenue(d.r)
  GameTooltip:AddDoubleLine("Vendor sale", money(vend))
  GameTooltip:AddDoubleLine("AH sale (net)", money(ah))
  GameTooltip:AddDoubleLine("Skill-up chance", ("%d%%"):format((ns.CHANCE[d.r.diff] or 0) * 100))
end

function ns.SortBy(col, btn)
  if tab == "route" then return end
  if btn == "RightButton" then
    sortCol = nil
  elseif sortCol == col then
    sortAsc = not sortAsc
  else
    sortCol = col
    sortAsc = col == 1 or col == 2 or (col == 4 and tab == "level")
  end
  setOffset(0)
end

local function matches(d, q)
  if d.r.name:lower():find(q, 1, true) then return true end
  for _, l in ipairs(d.lines) do
    local n = C_Item.GetItemNameByID(l.item)
    if n and n:lower():find(q, 1, true) then return true end
  end
end

local SORT_KEYS = { "sortName", "sortCost", "sortSale", "sortVal" }

-- Sorts by the clicked column; entries with no value for it always go last.
local function sortEntries(list)
  local k = SORT_KEYS[sortCol]
  for i, e in ipairs(list) do e.i = i end
  table.sort(list, function(a, b)
    local x, y = a[k], b[k]
    if x == nil or y == nil then
      if x == y then return a.i < b.i end
      return x ~= nil
    end
    if x == y then return a.i < b.i end
    if sortAsc then return x < y end
    return x > y
  end)
end

local function build()
  frame = CreateFrame("Frame", "MarginFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(660, 420)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetScript("OnMouseWheel", function(_, d) setOffset(offset - d * 3) end)
  frame:SetFrameStrata("HIGH")
  frame:Hide()
  tinsert(UISpecialFrames, "MarginFrame")
  frame.TitleText:SetText("Margin")

  local function button(x, w, text, onclick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, -30)
    b:SetText(text)
    b:SetScript("OnClick", onclick)
    return b
  end
  frame.tProfit = button(12, 80, "Profit", function() tab = "profit"; setOffset(0) end)
  frame.tLevel = button(94, 80, "Leveling", function() tab = "level"; setOffset(0) end)
  frame.tRoute = button(176, 80, "Route", function() tab = "route"; setOffset(0) end)
  frame.tProf = button(262, 110, "Profession", function()
    local names = {}
    for n in pairs(ns.Char().profs) do names[#names + 1] = n end
    table.sort(names)
    if #names == 0 then return end
    local idx = 1
    for i, n in ipairs(names) do if n == profName then idx = i % #names + 1 end end
    profName = names[idx]
    setOffset(0)
  end)
  frame.tSort = button(376, 110, "", function()
    ns.SetOpt("sortKey", ns.Opt("sortKey") == "vendor" and "ah" or "vendor")
    ns.RefreshUI()
  end)
  frame.tAll = button(490, 152, "", function()
    ns.SetOpt("showAll", not ns.Opt("showAll"))
    setOffset(0)
  end)

  frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.info:SetPoint("TOPLEFT", 14, -60)
  frame.info:SetWidth(440)
  frame.info:SetJustifyH("LEFT")
  frame.info:SetWordWrap(false)

  frame.searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.searchLabel:SetPoint("TOPLEFT", 470, -62)
  frame.searchLabel:SetText("Search")
  frame.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  frame.search:SetSize(130, 18)
  frame.search:SetPoint("TOPRIGHT", -34, -58)
  frame.search:SetAutoFocus(false)
  frame.search:SetMaxLetters(40)
  frame.search:SetScript("OnTextChanged", function(_, user) if user then setOffset(0) end end)
  frame.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  frame.search:SetScript("OnEscapePressed", function(self)
    self:SetText(""); self:ClearFocus(); setOffset(0)
  end)

  frame.hdr = {}
  local function hdr(i, x, w, just)
    local b = CreateFrame("Button", nil, frame)
    b:SetPoint("TOPLEFT", x, -78)
    b:SetSize(w, 14)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetAllPoints()
    b.text:SetJustifyH(just or "RIGHT")
    b:SetScript("OnClick", function(_, btn) ns.SortBy(i, btn) end)
    b:SetScript("OnEnter", function(self)
      if tab == "route" then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine("Click to sort, click again to reverse.", 1, 1, 1)
      GameTooltip:AddLine("Right-click: back to the default order.", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    frame.hdr[i] = b
  end
  hdr(1, 40, 230, "LEFT")
  hdr(2, 270, 120)
  hdr(3, 395, 110)
  hdr(4, 510, 120)

  frame.bar = CreateFrame("Slider", nil, frame)
  frame.bar:SetOrientation("VERTICAL")
  frame.bar:SetPoint("TOPRIGHT", -8, -96)
  frame.bar:SetPoint("BOTTOMRIGHT", -8, 12)
  frame.bar:SetWidth(14)
  frame.bar:SetObeyStepOnDrag(true)
  frame.bar:SetValueStep(1)
  frame.bar:SetMinMaxValues(0, 0)
  frame.bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  frame.bar:GetThumbTexture():SetSize(14, 24)
  local bg = frame.bar:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.35)
  frame.bar:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v + 0.5)
    if v ~= offset then offset = v; ns.RefreshUI() end
  end)

  frame.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(630, ROW_H)
    row:SetPoint("TOPLEFT", 12, -94 - (i - 1) * ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(16, 16)
    row.icon:SetPoint("LEFT", 2, 0)
    local function col(x, w, just, font)
      local fs = row:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
      fs:SetPoint("LEFT", x, 0)
      fs:SetWidth(w)
      fs:SetJustifyH(just)
      fs:SetWordWrap(false)
      return fs
    end
    row.name = col(24, 232, "LEFT")
    row.cost = col(258, 120, "RIGHT", "GameFontHighlightSmall")
    row.sale = col(383, 110, "RIGHT", "GameFontHighlightSmall")
    row.val = col(498, 120, "RIGHT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:EnableMouseWheel(true)
    row:SetScript("OnMouseWheel", function(_, d) setOffset(offset - d * 3) end)
    row:SetScript("OnEnter", function(self)
      local e = self.entry
      if not (e and (e.data or e.tip)) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if e.data then recipeTooltip(e.data) else e.tip(GameTooltip) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    frame.rows[i] = row
  end
end

-- Entries are what the rows show: { icon, name, cost, sale, val, data | tip }.
local function recipeEntry(d, kind, key)
  local r = d.r
  local vend, ah = ns.Revenue(r)
  local sale = key == "ah" and ah or vend
  local e = { icon = r.icon, data = d, sale = money(sale), sortName = r.name:lower(), sortSale = sale,
    name = ("|cff%s%s|r"):format(DIFF_COLOR[r.diff] or "ffffff", r.name) }
  if d.missing > 0 then
    e.cost = ("|cffff9090%d reagent%s unpriced|r"):format(d.missing, d.missing > 1 and "s" or "")
    e.val = "?"
  else
    e.cost = money(d.cost)
    e.sortCost = d.cost
    if kind == "profit" then
      e.sortVal = key == "ah" and d.ahProfit or d.vendorProfit
      e.val = money(e.sortVal)
    elseif d.perUp then
      e.sortVal = d.perUp
      e.val = money(d.perUp)
    else
      e.val = "|cff909090no skill-up|r"
    end
  end
  return e
end

local function routeEntries(prof)
  local target = ns.Opt("routeTarget") or prof.max
  target = math.min(math.max(target, prof.skill + 1), prof.max)
  local plan = ns.Plan(prof, target)
  local list = {}
  for _, seg in ipairs(plan.segs) do
    if seg.gap then
      list[#list + 1] = { name = ("|cffff9090%d-%d  no priced recipe|r"):format(seg.from, seg.to), cost = "", sale = "", val = "?" }
    else
      local r = seg.row.r
      local n = math.ceil(seg.crafts)
      list[#list + 1] = {
        icon = r.icon, data = seg.row,
        name = ("%d-%d  |cff%s%s|r"):format(seg.from, seg.to, DIFF_COLOR[r.diff] or "ffffff", r.name),
        cost = ("~%d crafts"):format(n), sale = money(seg.row.cost), val = money(seg.cost),
      }
    end
  end
  list[#list + 1] = { name = "|cffffd700Shopping list|r", cost = "", sale = "", val = money(plan.shopCost) }
  for _, it in ipairs(plan.shop) do
    list[#list + 1] = {
      icon = C_Item.GetItemIconByID(it.item), name = itemName(it.item),
      cost = "x " .. it.count, sale = money(it.unit), val = money(it.unit and it.unit * it.count),
      tip = function(tt)
        tt:AddLine(itemName(it.item))
        tt:AddDoubleLine("Source", it.src or "no price")
      end,
    }
  end
  return list, plan, target
end

function ns.RefreshUI()
  if not frame or not frame:IsShown() then return end
  local profs = ns.Char().profs
  if not profName or not profs[profName] then profName = next(profs) end
  local prof = profName and profs[profName]
  local key, showAll = ns.Opt("sortKey"), ns.Opt("showAll")
  frame.tSort:SetText(key == "ah" and "Sell: AH" or "Sell: vendor")
  frame.tAll:SetText(showAll and "Show: everything" or "Show: useful only")
  frame.tAll:SetEnabled(tab ~= "route")
  local count = 0
  for _ in pairs(profs) do count = count + 1 end
  frame.tProf:SetText(profName or "Profession")
  frame.tProf:SetEnabled(count > 1)
  local h = HEADERS[tab]
  local titles = { h[1], h[2], h[3] or (key == "ah" and "AH (net)" or "Vendor"), h[4] }
  for i = 1, 4 do
    local arrow = (tab ~= "route" and sortCol == i) and (sortAsc and " ^" or " v") or ""
    frame.hdr[i].text:SetText(titles[i] .. arrow)
  end
  frame.search:SetShown(tab ~= "route")
  frame.searchLabel:SetShown(tab ~= "route")

  local list = {}
  if prof then
    if tab == "route" then
      local plan, target
      list, plan, target = routeEntries(prof)
      frame.info:SetText(("%s %d/%d  -  route to %d: ~%d crafts, %s  (estimate; /margin route <skill>)"):format(
        profName, prof.skill, prof.max, target, math.ceil(plan.crafts), money(plan.cost)))
    else
      local rows = ns.Evaluate(prof)
      local src
      if tab == "profit" then src = ns.ProfitRows(rows, key, showAll) else src = ns.LevelingRows(rows, showAll) end
      local q = frame.search:GetText():lower()
      for _, d in ipairs(src) do
        if q == "" or matches(d, q) then list[#list + 1] = recipeEntry(d, tab, key) end
      end
      if sortCol then sortEntries(list) end
      local priced = 0
      for _, d in ipairs(rows) do if d.missing == 0 then priced = priced + 1 end end
      frame.info:SetText(("%s %d/%d  -  %d recipes, %d priced, %d shown"):format(
        profName, prof.skill, prof.max, #prof.recipes, priced, #list))
    end
  else
    frame.info:SetText("Open a profession window once to scan it.")
  end

  total = #list
  local max = math.max(0, total - ROWS)
  if offset > max then offset = max end
  frame.bar:SetMinMaxValues(0, max)
  frame.bar:SetValue(offset)

  for i = 1, ROWS do
    local row, e = frame.rows[i], list[i + offset]
    row.entry = e
    if e then
      row.icon:SetTexture(e.icon)
      row.icon:SetShown(e.icon ~= nil)
      row.name:SetText(e.name)
      row.cost:SetText(e.cost)
      row.sale:SetText(e.sale)
      row.val:SetText(e.val)
      row:Show()
    else
      row:Hide()
    end
  end
end

function ns.ToggleUI()
  if not frame then build() end
  if frame:IsShown() then frame:Hide() else frame:Show(); ns.RefreshUI() end
end

-- Item names arrive asynchronously; redraw once they have.
local loader = CreateFrame("Frame")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local queued
loader:SetScript("OnEvent", function()
  if queued or not (frame and frame:IsShown()) then return end
  queued = true
  C_Timer.After(0.3, function() queued = nil; ns.RefreshUI() end)
end)
