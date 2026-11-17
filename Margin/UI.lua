local _, ns = ...

local ROWS, ROW_H = 16, 20
local frame, tab, profName = nil, "profit", nil
local offset, total = 0, 0

local DIFF_COLOR = { [0] = "ff8040", [1] = "ffff00", [2] = "40c040", [3] = "909090" }

local function money(c)
  if c == nil then return "?" end
  local neg = c < 0
  local s = GetCoinTextureString(math.floor(math.abs(c)))
  return neg and ("|cffff6060-" .. s .. "|r") or s
end

local function setOffset(v)
  local max = math.max(0, total - ROWS)
  offset = math.min(math.max(0, math.floor(v + 0.5)), max)
  frame.bar:SetMinMaxValues(0, max)
  frame.bar:SetValue(offset)
  ns.RefreshUI()
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

  local function button(x, w, onclick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetPoint("TOPLEFT", x, -30)
    b:SetScript("OnClick", onclick)
    return b
  end
  frame.tProfit = button(12, 90, function() tab = "profit"; setOffset(0) end)
  frame.tProfit:SetText("Profit")
  frame.tLevel = button(106, 90, function() tab = "level"; setOffset(0) end)
  frame.tLevel:SetText("Leveling")
  frame.tProf = button(200, 120, function()
    local names = {}
    for n in pairs(ns.Char().profs) do names[#names + 1] = n end
    table.sort(names)
    if #names == 0 then return end
    local idx = 1
    for i, n in ipairs(names) do if n == profName then idx = i % #names + 1 end end
    profName = names[idx]
    setOffset(0)
  end)
  frame.tProf:SetText("Profession")
  frame.tSort = button(324, 120, function()
    ns.SetOpt("sortKey", ns.Opt("sortKey") == "vendor" and "ah" or "vendor")
    ns.RefreshUI()
  end)
  frame.tAll = button(448, 130, function()
    ns.SetOpt("showAll", not ns.Opt("showAll"))
    setOffset(0)
  end)

  frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.info:SetPoint("TOPLEFT", 14, -60)

  local hdr = function(text, x, w, just)
    local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", x, -78)
    fs:SetWidth(w)
    fs:SetJustifyH(just or "RIGHT")
    fs:SetText(text)
    return fs
  end
  hdr("Recipe", 40, 230, "LEFT")
  frame.hCost = hdr("Cost", 270, 120)
  frame.hSale = hdr("Sale", 395, 110)
  frame.hVal = hdr("Profit", 510, 120)

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
      local d = self.data
      if not d then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(d.r.name)
      for _, l in ipairs(d.lines) do
        local name = C_Item.GetItemNameByID(l.item) or ("item " .. l.item)
        GameTooltip:AddDoubleLine(l.count .. "x " .. name,
          l.unit and (money(l.unit * l.count) .. " (" .. l.src .. ")") or "no price", 1, 1, 1, 1, 1, 1)
      end
      GameTooltip:AddDoubleLine("Cost", money(d.cost))
      local vend, ah = ns.Revenue(d.r)
      GameTooltip:AddDoubleLine("Vendor sale", money(vend))
      GameTooltip:AddDoubleLine("AH sale (net)", money(ah))
      GameTooltip:AddDoubleLine("Skill-up chance", ("%d%%"):format((ns.CHANCE[d.r.diff] or 0) * 100))
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    frame.rows[i] = row
  end
end

function ns.RefreshUI()
  if not frame or not frame:IsShown() then return end
  local profs = ns.Char().profs
  if not profName or not profs[profName] then profName = next(profs) end
  local prof = profName and profs[profName]
  local key, showAll = ns.Opt("sortKey"), ns.Opt("showAll")
  frame.tSort:SetText(key == "ah" and "Sell: AH" or "Sell: vendor")
  frame.tAll:SetText(showAll and "Show: everything" or "Show: useful only")
  frame.hSale:SetText(key == "ah" and "AH (net)" or "Vendor")
  frame.hVal:SetText(tab == "profit" and "Profit" or "Cost / skill-up")

  local list = {}
  if prof then
    local rows = ns.Evaluate(prof)
    if tab == "profit" then list = ns.ProfitRows(rows, key, showAll) else list = ns.LevelingRows(rows, showAll) end
    local priced = 0
    for _, d in ipairs(rows) do if d.missing == 0 then priced = priced + 1 end end
    frame.info:SetText(("%s %d/%d  -  %d recipes, %d priced, %d shown"):format(
      profName, prof.skill, prof.max, #prof.recipes, priced, #list))
  else
    frame.info:SetText("Open a profession window once to scan it.")
  end

  total = #list
  local max = math.max(0, total - ROWS)
  if offset > max then offset = max end
  frame.bar:SetMinMaxValues(0, max)
  frame.bar:SetValue(offset)

  for i = 1, ROWS do
    local row, d = frame.rows[i], list[i + offset]
    row.data = d
    if d then
      local r = d.r
      row.icon:SetTexture(r.icon)
      row.name:SetText(("|cff%s%s|r"):format(DIFF_COLOR[r.diff] or "ffffff", r.name))
      local vend, ah = ns.Revenue(r)
      local sale = key == "ah" and ah or vend
      if d.missing > 0 then
        row.cost:SetText(("|cffff9090%d reagent%s unpriced|r"):format(d.missing, d.missing > 1 and "s" or ""))
        row.sale:SetText(money(sale))
        row.val:SetText("?")
      else
        row.cost:SetText(money(d.cost))
        row.sale:SetText(money(sale))
        if tab == "profit" then
          row.val:SetText(money(key == "ah" and d.ahProfit or d.vendorProfit))
        elseif d.perUp then
          row.val:SetText(money(d.perUp))
        else
          row.val:SetText("|cff909090no skill-up|r")
        end
      end
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
