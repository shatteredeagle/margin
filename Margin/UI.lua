local _, ns = ...

local ROWS, ROW_H = 16, 20
local frame, tab, profName = nil, "profit", nil
local offset, total = 0, 0
local shown = ROWS   -- rows visible: fewer on the Route tab, which has the comparison cards
local cache          -- Route tab data, kept while only scrolling
local redraw         -- the draw function (defined below)
local sortCol, sortAsc = nil, false -- clicked column (1 name, 2 cost, 3 sale, 4 profit/per-up)

local DIFF_COLOR = { [0] = "ff8040", [1] = "ffff00", [2] = "40c040", [3] = "909090" }

local HEADERS = {
  profit = { "Recipe", "Cost", nil, "Profit" },
  level = { "Recipe", "Cost", nil, "Net / skill-up" },
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

-- Net cost (reagents minus what the crafts sell for): negative means you come out ahead,
-- so it is green, unlike a negative profit, which is red.
local function netMoney(c)
  if c == nil then return "?" end
  if c >= 0 then return money(c) end
  return "|cff60ff60-|r" .. money(-c)
end

-- Same amount without colour codes, so a delta can be tinted as a whole.
local function plainMoney(c)
  c = math.floor(math.abs(c) + 0.5)
  local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if g > 0 or sv > 0 then out[#out + 1] = sv .. "s" end
  out[#out + 1] = cp .. "c"
  return table.concat(out, " ")
end

local function itemName(id)
  local n = C_Item.GetItemNameByID(id)
  if not n then C_Item.RequestLoadItemDataByID(id) end
  return n or ("item " .. id)
end

local function setOffset(v, scrolling)
  local max = math.max(0, total - shown)
  offset = math.min(math.max(0, math.floor(v + 0.5)), max)
  frame.bar:SetMinMaxValues(0, max)
  frame.bar:SetValue(offset)
  if scrolling then redraw() else ns.RefreshUI() end
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
  if d.net and (ns.Opt("resale") or "off") ~= "off" then
    GameTooltip:AddDoubleLine("Net per craft (cost - resale)", d.net < 0 and ("|cff60ff60-|r" .. money(-d.net) .. " |cff60ff60profit|r") or money(d.net))
  end
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
  frame:SetScript("OnMouseWheel", function(_, d) setOffset(offset - d * 3, true) end)
  frame:SetFrameStrata("HIGH")
  frame:Hide()
  tinsert(UISpecialFrames, "MarginFrame")
  frame.TitleText:SetText("Margin")

  frame.rep = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  frame.rep:SetSize(22, 22)
  frame.rep:SetPoint("TOPLEFT", 6, -2)
  frame.rep.text:SetText("My reputation")
  frame.rep.text:SetFontObject("GameFontNormalSmall")
  frame.rep:SetScript("OnClick", function(self)
    ns.SetOpt("useRep", self:GetChecked() and true or false)
    ns.RefreshUI()
  end)
  frame.rep:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
    GameTooltip:AddLine("Use my reputation")
    GameTooltip:AddLine("Off (default): base vendor prices and no reputation-locked patterns. This is the worst case.", 1, 1, 1, true)
    GameTooltip:AddLine("On: the lowest price you were charged at vendors you opened, and patterns whose reputation you have reached.", 1, 1, 1, true)
    GameTooltip:AddLine("Trainer fees always use base prices.", 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
  end)
  frame.rep:SetScript("OnLeave", GameTooltip_Hide)

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
    if tab == "profit" then
      ns.SetOpt("sortKey", ns.Opt("sortKey") == "vendor" and "ah" or "vendor")
    else -- leveling and route: what the crafted item is assumed to sell for
      local nxt = { vendor = "ah", ah = "off", off = "vendor" }
      ns.SetOpt("resale", nxt[ns.Opt("resale")] or "vendor")
    end
    ns.RefreshUI()
  end)
  frame.tAll = button(490, 152, "", function()
    if tab == "route" then
      ns.SetOpt("useTrainer", not ns.Opt("useTrainer"))
    else
      ns.SetOpt("showAll", not ns.Opt("showAll"))
    end
    setOffset(0)
  end)

  frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.info:SetPoint("TOPLEFT", 14, -60)
  frame.info:SetWidth(400)
  frame.info:SetJustifyH("LEFT")
  frame.info:SetWordWrap(false)

  frame.searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.searchLabel:SetText("Search")
  frame.search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  frame.search:SetSize(130, 18)
  frame.search:SetPoint("TOPRIGHT", -34, -58)
  frame.search:SetAutoFocus(false)
  frame.search:SetMaxLetters(40)
  frame.searchLabel:SetPoint("RIGHT", frame.search, "LEFT", -10, 0)
  frame.search:SetScript("OnTextChanged", function(_, user) if user then setOffset(0) end end)
  frame.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  frame.search:SetScript("OnEscapePressed", function(self)
    self:SetText(""); self:ClearFocus(); setOffset(0)
  end)

  frame.hdr = {}
  local function hdr(i, x, w, just)
    local b = CreateFrame("Button", nil, frame)
    b.px = x
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

  -- Route comparison cards: the same route priced under each option.
  frame.cards = {}
  for i = 1, 4 do
    local c = CreateFrame("Button", nil, frame)
    c:SetSize(154, 46)
    c:SetPoint("TOPLEFT", 12 + (i - 1) * 158, -80)
    c.edge = c:CreateTexture(nil, "BACKGROUND", nil, -1)
    c.edge:SetPoint("TOPLEFT", -2, 2)
    c.edge:SetPoint("BOTTOMRIGHT", 2, -2)
    c.edge:SetColorTexture(1, 0.82, 0, 1)
    c.edge:Hide()
    c.bg = c:CreateTexture(nil, "BACKGROUND")
    c.bg:SetAllPoints()
    c.bg:SetColorTexture(0.08, 0.08, 0.1, 0.9)
    c:SetHighlightTexture("Interface\QuestFrame\UI-QuestTitleHighlight")
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    c.label:SetPoint("TOPLEFT", 6, -4)
    c.label:SetWidth(100)
    c.label:SetJustifyH("LEFT")
    c.label:SetWordWrap(false)
    c.delta = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.delta:SetPoint("TOPRIGHT", -6, -4)
    c.delta:SetJustifyH("RIGHT")
    c.value = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    c.value:SetPoint("BOTTOMLEFT", 6, 5)
    c.sub = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    c.sub:SetPoint("BOTTOMRIGHT", -6, 6)
    c.sub:SetJustifyH("RIGHT")
    c:SetScript("OnClick", function(self) if self.action then self.action() end end)
    c:Hide()
    frame.cards[i] = c
  end

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
    if v ~= offset then offset = v; redraw() end
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
    row:SetScript("OnMouseWheel", function(_, d) setOffset(offset - d * 3, true) end)
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
    if kind == "profit" and not r.out then
      e.val = "|cff909090makes no item|r" -- enchants and the like have nothing to sell
    elseif kind == "profit" then
      e.sortVal = key == "ah" and d.ahProfit or d.vendorProfit
      e.val = money(e.sortVal)
    elseif d.perUp then
      e.sortVal = d.perUp
      e.val = netMoney(d.perUp)
    else
      e.val = "|cff909090no skill-up|r"
    end
  end
  return e
end

-- The Route tab makes room for the comparison cards, so its rows start lower and fewer fit.
local layoutRoute
local function layout(isRoute)
  if layoutRoute == isRoute then return end
  layoutRoute = isRoute
  local dy = isRoute and 52 or 0
  shown = isRoute and 13 or ROWS
  for _, h in ipairs(frame.hdr) do
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", h.px, -78 - dy)
  end
  for i, row in ipairs(frame.rows) do
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 12, -94 - dy - (i - 1) * ROW_H)
  end
  frame.bar:ClearAllPoints()
  frame.bar:SetPoint("TOPRIGHT", -8, -96 - dy)
  frame.bar:SetPoint("BOTTOMRIGHT", -8, 12)
end

-- The route for the profession the window shows: plan, prof, name, target (nil when nothing is scanned).
-- Planning is heavy, so results are kept per setting until prices or scans change (ns.InvalidatePlan);
-- bag updates and scrolling reuse them.
local planCache = {}
function ns.InvalidatePlan() wipe(planCache) end

function ns.CurrentPlan()
  local profs = ns.Char().profs
  local name, prof = profName, profName and profs[profName]
  if not prof then name, prof = next(profs) end
  if not prof then return nil end
  local target = ns.Opt("routeTarget") or prof.max
  target = math.min(math.max(target, prof.skill + 1), prof.max)
  local key = table.concat({ name, prof.skill, prof.time or 0, tostring(ns.Opt("resale")),
    tostring(ns.Opt("useTrainer")), target }, "|")
  local hit = planCache[key]
  if not hit then
    hit = ns.Plan(prof, target, nil, ns.Opt("useTrainer"))
    planCache[key] = hit
  end
  return hit, prof, name, target
end

local function routeEntries(plan)
  local list = {}
  for _, seg in ipairs(plan.segs) do
    if seg.gap then
      list[#list + 1] = { name = ("|cffff9090%d-%d  no priced recipe|r"):format(seg.from, seg.to), cost = "", sale = "", val = "?" }
    else
      local r = seg.row.r
      local n = math.ceil(seg.crafts)
      list[#list + 1] = {
        icon = r.icon, data = seg.row,
        name = ("%d-%d  |cff%s%s|r%s"):format(seg.from, seg.to,
          seg.row.learn and DIFF_COLOR[0] or (DIFF_COLOR[r.diff] or "ffffff"), r.name,
          seg.row.learn and " |cff80c0ff(learn)|r" or ""),
        cost = ("~%d crafts"):format(n), sale = money(seg.row.cost), val = netMoney(seg.cost),
      }
    end
  end
  if #plan.learn > 0 then
    list[#list + 1] = { name = "|cffffd700Recipes to learn|r", cost = "", sale = "", val = money(plan.learnCost) }
    local HOW = { trainer = "trainer", ah = "buy the pattern on the AH", vendor = "buy the pattern from a vendor" }
    for _, l in ipairs(plan.learn) do
      local r = l.row.r
      list[#list + 1] = {
        icon = r.icon, name = r.name,
        cost = ("skill %d, %s"):format(l.rank, l.how == "trainer" and "trainer" or (l.how == "ah" and "AH" or "vendor")),
        sale = "", val = money(l.fee),
        tip = function(tt)
          tt:AddLine(r.name)
          tt:AddLine(("%s: %s, requires %d skill."):format(HOW[l.how] or l.how, money(l.fee), l.rank), 1, 1, 1, true)
          if l.how == "trainer" then
            tt:AddLine("Forever trainer data (EG Link); not every trainer is listed.", 0.7, 0.7, 0.7, true)
          elseif l.item then
            tt:AddLine(("Recipe item: %s"):format(itemName(l.item)), 0.7, 0.7, 0.7, true)
          end
        end,
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
  return list
end

-- The route priced under each option, for the comparison cards, and the list for the current one.
local function routeData()
  local resale, trainer = ns.Opt("resale"), ns.Opt("useTrainer")
  local function planFor(r, t)
    return ns.With({ resale = r, useTrainer = t }, function() return (ns.CurrentPlan()) end)
  end
  local cards, sel = {}, nil
  for _, m in ipairs({ "vendor", "ah", "off" }) do
    local plan = planFor(m, trainer)
    cards[#cards + 1] = {
      label = m == "off" and "No resale (reagents)" or ("Resale: " .. (m == "ah" and "AH" or "vendor")),
      plan = plan, total = plan.cost + plan.learnCost, selected = (m == resale),
      action = function() ns.SetOpt("resale", m); ns.RefreshUI() end,
    }
    if m == resale then sel = cards[#cards] end
  end
  sel = sel or cards[1]
  local alt = planFor(resale, not trainer)
  cards[#cards + 1] = {
    label = trainer and "Learned recipes only" or "With unlearned recipes",
    plan = alt, total = alt.cost + alt.learnCost, selected = false,
    action = function() ns.SetOpt("useTrainer", not trainer); ns.RefreshUI() end,
  }
  return { cards = cards, sel = sel, list = routeEntries(sel.plan), target = sel.plan.target }
end

function ns.RefreshUI()
  ns.InvalidatePlan()
  if ns.RefreshShopping then ns.RefreshShopping() end
  if ns.RefreshMerchant then ns.RefreshMerchant() end
  cache = nil
  if redraw then redraw() end
end

redraw = function()
  if not frame or not frame:IsShown() then return end
  layout(tab == "route")
  frame.rep:SetChecked(ns.Opt("useRep") and true or false)
  -- The current tab's button is greyed out and highlighted, so you can see where you are.
  for name, b in pairs({ profit = frame.tProfit, level = frame.tLevel, route = frame.tRoute }) do
    local selected = tab == name
    b:SetEnabled(not selected)
    if selected then b:LockHighlight() else b:UnlockHighlight() end
  end
  local profs = ns.Char().profs
  if not profName or not profs[profName] then profName = next(profs) end
  local prof = profName and profs[profName]
  local key, showAll = ns.Opt("sortKey"), ns.Opt("showAll")
  if tab == "profit" then
    frame.tSort:SetText(key == "ah" and "Sell: AH" or "Sell: vendor")
  else
    frame.tSort:SetText("Resale: " .. (ns.Opt("resale") or "vendor"))
  end
  if tab == "route" then
    frame.tAll:SetText(ns.Opt("useTrainer") and "Unlearned recipes: on" or "Unlearned recipes: off")
  else
    frame.tAll:SetText(showAll and "Show: everything" or "Show: useful only")
  end
  local count = 0
  for _ in pairs(profs) do count = count + 1 end
  frame.tProf:SetText(profName or "Profession")
  frame.tProf:SetEnabled(count > 1)
  local h = HEADERS[tab]
  local titles = { h[1], h[2], h[3] or (key == "ah" and "AH (net)" or "Vendor"), h[4] }
  if tab == "level" and ns.Opt("resale") == "off" then titles[4] = "Cost / skill-up" end
  for i = 1, 4 do
    local arrow = (tab ~= "route" and sortCol == i) and (sortAsc and " ^" or " v") or ""
    frame.hdr[i].text:SetText(titles[i] .. arrow)
  end
  frame.search:SetShown(tab ~= "route")
  frame.searchLabel:SetShown(tab ~= "route")
  if tab ~= "route" or not prof then for _, c in ipairs(frame.cards) do c:Hide() end end

  local list = {}
  if prof then
    if tab == "route" then
      cache = cache or routeData()
      list = cache.list
      frame.info:SetText(("%s %d/%d  -  route to %d  (what it costs after selling the crafts, plus trainer fees)"):format(
        profName, prof.skill, prof.max, cache.target))
      for i, c in ipairs(frame.cards) do
        local d = cache.cards[i]
        c.action = d.action
        c.label:SetText(d.label)
        c.value:SetText(netMoney(d.total))
        c.sub:SetText(("~%d crafts"):format(math.ceil(d.plan.crafts)))
        c.edge:SetShown(d.selected)
        if d.selected then
          c.delta:SetText("|cffffd700selected|r")
        else
          local diff = d.total - cache.sel.total
          if diff == 0 then
            c.delta:SetText("same")
          else
            c.delta:SetText(("|cff%s%s%s|r"):format(diff > 0 and "ff6060" or "60ff60", diff > 0 and "+" or "-", plainMoney(diff)))
          end
        end
        c:Show()
      end
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
  local max = math.max(0, total - shown)
  if offset > max then offset = max end
  frame.bar:SetMinMaxValues(0, max)
  frame.bar:SetValue(offset)

  for i = 1, ROWS do
    local row, e = frame.rows[i], i <= shown and list[i + offset] or nil
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
