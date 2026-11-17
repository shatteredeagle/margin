local _, ns = ...

local ROWS, ROW_H = 14, 22
local frame, tab, profName = nil, "profit", nil

local function money(c)
  if c == nil then return "?" end
  local neg = c < 0
  local s = GetCoinTextureString(math.abs(c))
  return neg and ("-" .. s) or s
end

local function build()
  frame = CreateFrame("Frame", "MarginFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(560, 400)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("HIGH")
  frame:Hide()
  tinsert(UISpecialFrames, "MarginFrame")
  frame.TitleText:SetText("Margin")

  local function button(text, x, onclick)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(110, 22)
    b:SetPoint("TOPLEFT", x, -32)
    b:SetText(text)
    b:SetScript("OnClick", onclick)
    return b
  end
  frame.tProfit = button("Profit", 12, function() tab = "profit"; ns.RefreshUI() end)
  frame.tLevel = button("Leveling", 126, function() tab = "level"; ns.RefreshUI() end)
  frame.tProf = button("Profession", 240, function()
    local names = {}
    for n in pairs(ns.Char().profs) do names[#names + 1] = n end
    table.sort(names)
    if #names == 0 then return end
    local idx = 1
    for i, n in ipairs(names) do if n == profName then idx = i % #names + 1 end end
    profName = names[idx]
    ns.RefreshUI()
  end)
  frame.tSort = button("Sell: vendor", 354, function()
    ns.SetOpt("sortKey", ns.Opt("sortKey") == "vendor" and "ah" or "vendor")
    ns.RefreshUI()
  end)

  frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.info:SetPoint("TOPLEFT", 14, -62)

  frame.scroll = CreateFrame("ScrollFrame", "MarginScroll", frame, "FauxScrollFrameTemplate")
  frame.scroll:SetPoint("TOPLEFT", 10, -82)
  frame.scroll:SetPoint("BOTTOMRIGHT", -30, 10)
  frame.scroll:SetScript("OnVerticalScroll", function(self, off)
    FauxScrollFrame_OnVerticalScroll(self, off, ROW_H, ns.RefreshUI)
  end)

  frame.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(500, ROW_H)
    row:SetPoint("TOPLEFT", 12, -82 - (i - 1) * ROW_H)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(18, 18)
    row.icon:SetPoint("LEFT")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
    row.name:SetWidth(210)
    row.name:SetJustifyH("LEFT")
    row.cost = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.cost:SetPoint("LEFT", 240, 0)
    row.cost:SetWidth(120)
    row.cost:SetJustifyH("RIGHT")
    row.val = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.val:SetPoint("LEFT", 370, 0)
    row.val:SetWidth(130)
    row.val:SetJustifyH("RIGHT")
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
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
      if d.r.out then
        GameTooltip:AddDoubleLine("Vendor sale", money((ns.Revenue(d.r))))
        GameTooltip:AddDoubleLine("AH sale (net)", money(select(2, ns.Revenue(d.r))))
      end
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
  local key = ns.Opt("sortKey")
  frame.tSort:SetText(key == "ah" and "Sell: AH" or "Sell: vendor")

  local list = {}
  if prof then
    local rows = ns.Evaluate(prof)
    if tab == "profit" then list = ns.ProfitRows(rows, key) else list = ns.LevelingRows(rows) end
    frame.info:SetText(("%s %d/%d  -  %s"):format(profName, prof.skill, prof.max,
      tab == "profit" and "profit per craft" or "cost per skill-up"))
  else
    frame.info:SetText("Open a profession window once to scan it.")
  end

  FauxScrollFrame_Update(frame.scroll, #list, ROWS, ROW_H)
  local off = FauxScrollFrame_GetOffset(frame.scroll)
  for i = 1, ROWS do
    local row, d = frame.rows[i], list[i + off]
    row.data = d
    if d then
      row.icon:SetTexture(d.r.icon)
      row.name:SetText(d.r.name)
      row.cost:SetText("cost " .. money(d.cost))
      if tab == "profit" then
        row.val:SetText(money(key == "ah" and d.ahProfit or d.vendorProfit))
      else
        row.val:SetText(money(math.floor(d.perUp)) .. " /up")
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
