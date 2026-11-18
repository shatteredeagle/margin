local _, ns = ...

-- The Ledger layout (docs/ui-redesign/DESIGN.md, direction A): the tabbed window with a strict
-- hierarchy. Title bar; header band (profession dropdown, skill bar, Settings); underline tabs with
-- search or lock + Re-plan at the right; one row of chips naming the settings the tab uses, with a
-- short status; a warning banner that wraps; then the Route cards and one list with section bands, or
-- the sortable Profit / Leveling list. Settings is a panel over the window body, built from the
-- registry (Options.lua).
--
-- Data comes from the view model (ViewModel.lua); this file only lays out and formats.

local T, W, UI, VM = ns.T, ns.W, ns.UI, ns.VM
local S = ns.S

local WIDTH, HEIGHT = 700, 470
local TOP_HEADER, TOP_TABS, TOP_CHIPS, TOP_BODY = 26, 62, 90, 120
local LIST_X = 8
local LIST_W = WIDTH - 2 * LIST_X   -- includes the 12 px scroll bar
local ROW_W = LIST_W - 14
local GAP = 8

local win            -- the window (nil until first shown)
local cache          -- Route data, kept while only scrolling
local pos = {}       -- column positions of the current tab: key -> { x, w }

local PROF_ICON = {
  Alchemy = "Interface\\Icons\\Trade_Alchemy", Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
  Cooking = "Interface\\Icons\\INV_Misc_Food_15", Enchanting = "Interface\\Icons\\Trade_Engraving",
  Engineering = "Interface\\Icons\\Trade_Engineering", ["First Aid"] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
  Leatherworking = "Interface\\Icons\\Trade_LeatherWorking", Tailoring = "Interface\\Icons\\Trade_Tailoring",
  Mining = "Interface\\Icons\\Trade_Mining", Jewelcrafting = "Interface\\Icons\\INV_Misc_Gem_01",
  Inscription = "Interface\\Icons\\INV_Inscription_Tradeskill01", Fishing = "Interface\\Icons\\Trade_Fishing",
}
local function profIcon(name) return PROF_ICON[name or ""] or "Interface\\Icons\\INV_Misc_QuestionMark" end

-- Column positions for a tab from its registered columns: fixed columns packed from the right, the
-- skill range (Route) at the left, then the icon, and the name takes the rest.
local function columnPositions(tab)
  local p, right = {}, ROW_W - GAP
  local cols = UI.Columns(tab)
  for i = #cols, 1, -1 do
    local c = cols[i]
    if c.key ~= "name" and c.key ~= "range" then
      p[c.key] = { x = right - c.width, w = c.width }
      right = right - c.width - GAP
    end
  end
  local left = GAP
  for _, c in ipairs(cols) do
    if c.key == "range" then
      p.range = { x = GAP, w = c.width }
      left = GAP + c.width + 4
    end
  end
  p.icon = { x = left, w = 16 }
  p.name = { x = left + 22, w = right + GAP - (left + 22) - 4 }
  return p
end

---------------------------------------------------------------------------
-- Cells: how each entry kind fills the row's text fields
---------------------------------------------------------------------------

local money, signed, plain, C = T.Money, T.Signed, T.Plain, T.C

local function recipeName(e)
  local color = e.unlearned and "unlearned" or ("diff" .. (e.diff or 3))
  local out = C(color, e.name)
  if e.learn then
    local L = e.learn
    local when = L.togo <= 0 and "learn now" or C("warn", ("skill %d, %d to go"):format(L.rank, L.togo))
    local source = L.how == "trainer" and ("trainer " .. plain(L.fee))
      or (L.how == "ah" and ("pattern " .. plain(L.fee) .. " on the AH") or ("pattern " .. plain(L.fee)))
    out = out .. " " .. C("unlearned", "(") .. when .. C("unlearned", ": " .. source .. ")")
  elseif e.learnNote then
    out = out .. " " .. C("dim", "(" .. e.learnNote .. ")")
  end
  return out
end

-- returns range, name, cost, sale, value, pill kind, pill after the name, rail, dim row
local function cells(e)
  local k = e.kind
  if k == "recipe" then
    local cost = e.missing > 0 and C("warn", ("%d reagent%s unpriced"):format(e.missing, e.missing > 1 and "s" or "")) or money(e.cost)
    local sale = (S.tab == "profit" or e.sale) and money(e.sale) or ""
    local value = e.missing > 0 and C("dim", "?") or (e.valueNote and C("dim", e.valueNote) or signed(e.value))
    return nil, recipeName(e), cost, sale, value
  elseif k == "step" then
    local color = e.learn and "diff0" or ("diff" .. (e.diff or 3))
    return C("text", e.from .. "-" .. e.to), C(color, e.name), ("~%d crafts"):format(e.crafts), money(e.unit),
      signed(e.net), e.learn and "learn" or nil, true
  elseif k == "gap" then
    return C("loss", e.from .. "-" .. e.to), C("loss", "no priced recipe"), "", "", C("dim", "?")
  elseif k == "prep" then
    if e.mode == "make" then
      return nil, e.name .. (e.have > 0 and C("dim", (" (you have %d)"):format(e.have)) or ""),
        C("dim", ("~%d crafts"):format(e.crafts)), e.unit and (money(e.unit) .. C("dim", " each")) or "",
        e.total and money(e.total) or C("dim", "?"), "make", false, true
    end
    return nil, e.name .. C("dim", (" (%d in your bags)"):format(e.have)), "", "", "", "have", false, true
  elseif k == "history" then
    return C("dim", e.from .. "-" .. e.to), C("dim", e.name), C("dim", e.crafts > 0 and ("%d crafts"):format(e.crafts) or ""),
      C("dim", date("%b %d", e.t)), e.cost > 0 and money(e.cost) or "", nil, false, false, true
  elseif k == "stock" then
    return nil, e.name .. C("dim", (" x%d"):format(e.count)), C("dim", "vendor ") .. money(e.vendor),
      e.ah and (C("dim", "AH ") .. money(e.ah)) or C("dim", "AH ?"), money(e.best), nil, false, true
  elseif k == "learn" then
    local how = e.how == "trainer" and "trainer" or (e.how == "ah" and "AH" or "vendor")
    return C("dim", "skill " .. e.rank), e.name, C("dim", how), "", money(e.fee)
  elseif k == "shop" then
    local name = e.name .. (e.have > 0 and C("dim", (" (have %d)"):format(e.have)) or "")
      .. (e.short > 0 and C("loss", (" (only %d on the AH)"):format(e.sup)) or "")
    return nil, name, e.buy == 0 and C("profit", "have enough") or ("x " .. e.buy), money(e.unit), money(e.cost)
  end
  return nil, e.name or "", "", "", ""
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function place(fs, key, justify)
  local p = pos[key]
  fs:ClearAllPoints()
  if not p then fs:Hide(); return end
  fs:SetPoint("LEFT", p.x, 0)
  fs:SetWidth(p.w)
  fs:SetJustifyH(justify or "RIGHT")
  fs:Show()
end

local function makeRow(list)
  local row = CreateFrame("Button", nil, list)
  row:SetHeight(T.size.row)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.band = W.Solid(row, "panel2", "BACKGROUND")
  row.band:SetAllPoints()
  row.bandTop = W.Solid(row, "border", "BORDER")
  row.bandTop:SetPoint("TOPLEFT"); row.bandTop:SetPoint("TOPRIGHT"); row.bandTop:SetHeight(1)
  row.bandBottom = W.Solid(row, "border", "BORDER")
  row.bandBottom:SetPoint("BOTTOMLEFT"); row.bandBottom:SetPoint("BOTTOMRIGHT"); row.bandBottom:SetHeight(1)
  row.sep = W.Solid(row, "white", "BORDER", 0.035)
  row.sep:SetPoint("BOTTOMLEFT"); row.sep:SetPoint("BOTTOMRIGHT"); row.sep:SetHeight(1)
  row.hl = W.Solid(row, "accent", "ARTWORK", 0.12)
  row.hl:SetAllPoints()
  row.hl:Hide()
  -- the rail that hangs a prep or stock row off the row it belongs to
  row.railV = W.Solid(row, "border", "ARTWORK")
  row.railV:SetWidth(1)
  row.railH = W.Solid(row, "border", "ARTWORK")
  row.railH:SetHeight(1)
  row.range = W.Text(row, "small", "dim")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.chev = W.Glyph(row, "chevr", 10, "accent")
  row.pill = W.Pill(row)
  row.name = W.Text(row, "row", "text")
  row.title = W.Text(row, "small", "accent")
  row.total = W.Text(row, "row", "text", "RIGHT")
  row.cost = W.Text(row, "small", "text", "RIGHT")
  row.sale = W.Text(row, "small", "text", "RIGHT")
  row.value = W.Text(row, "row", "text", "RIGHT")
  row:SetScript("OnEnter", function(self) if self.entry and self.entry.kind ~= "section" or (self.entry and (self.entry.collapsible or self.entry.pick)) then self.hl:Show() end end)
  row:SetScript("OnLeave", function(self) self.hl:Hide() end)
  W.Tip(row, function(tt, self)
    if not self.entry then return false end
    return ns.Tips.Entry(tt, self.entry)
  end, "ANCHOR_RIGHT")
  row:SetScript("OnClick", function(self, button)
    local e = self.entry
    if not e then return end
    if button == "RightButton" then
      -- a craft you cannot get (a recipe your server never sells): leave it out of everything
      local c = e.craft
      if c and c.id and not (e.kind == "section") then
        W.PopupMenu({ { "Ignore craft: " .. (c.name or ("recipe " .. c.id)), function() ns.SetCraftIgnored(c.id, c.name, c.profession, true) end } })
      end
      return
    end
    if e.kind == "section" and e.collapsible then
      if e.key == "history" then S.showHistory = not S.showHistory else S.showStock = not S.showStock end
      return ns.RefreshUI()
    end
    if e.kind == "section" and e.pick then
      local plan = ns.CurrentPlan()
      if plan then ns.CycleShopStep(plan) end
      return ns.RefreshUI()
    end
    if e.quote then return ns.OpenQuote(e.quote) end
    if e.craft then ns.CraftClick(e.craft) end
  end)
  return row
end

local function fillSection(row, e)
  row.band:Show(); row.bandTop:Show(); row.bandBottom:Show(); row.sep:Hide()
  row.range:Hide(); row.icon:Hide(); row.pill:Hide(); row.name:Hide(); row.value:Hide()
  row.railV:Hide(); row.railH:Hide()
  local x = 8
  if e.collapsible then
    row.chev:SetTexture(W.MEDIA .. (e.open and "chev" or "chevr"))
    row.chev:ClearAllPoints()
    row.chev:SetPoint("LEFT", x, 0)
    row.chev:Show()
    x = x + 16
  else
    row.chev:Hide()
  end
  local count = e.count and (e.key == "stock" and ("(%d items)"):format(e.count) or ("(%d)"):format(e.count)) or nil
  local hint = e.hint or count
  row.title:ClearAllPoints()
  row.title:SetPoint("LEFT", x, 0)
  row.title:SetWidth(pos.cost and (pos.cost.x - x - GAP) or 300)
  row.title:SetText(e.title:upper() .. (hint and ("  " .. C("dim", hint)) or ""))
  row.title:Show()
  if e.key == "stock" then
    place(row.cost, "cost"); row.cost:SetText(C("dim", "vendor ") .. money(e.vendorTotal))
    place(row.sale, "sale"); row.sale:SetText(C("dim", "AH ") .. money(e.ahTotal))
  else
    row.cost:Hide(); row.sale:Hide()
  end
  place(row.total, "value")
  row.total:SetText(e.signed and signed(e.total) or money(e.total))
end

local function fillRow(row, e)
  if e.kind == "section" then return fillSection(row, e) end
  row.band:Hide(); row.bandTop:Hide(); row.bandBottom:Hide(); row.sep:Show()
  row.title:Hide(); row.total:Hide(); row.chev:Hide()
  local range, name, cost, sale, value, pill, pillAfter, rail, dim = cells(e)
  if range and pos.range then
    place(row.range, "range", "LEFT")
    row.range:SetText(range)
  else
    row.range:Hide()
  end
  local x = pos.icon.x
  if rail then
    -- a short elbow from above into the row, then the content indented past it
    row.railV:ClearAllPoints()
    row.railV:SetPoint("TOPLEFT", x + 6, 0)
    row.railV:SetHeight(T.size.row / 2)
    row.railH:ClearAllPoints()
    row.railH:SetPoint("LEFT", x + 6, 0)
    row.railH:SetWidth(8)
    row.railV:Show(); row.railH:Show()
    x = x + 18
  else
    row.railV:Hide(); row.railH:Hide()
  end
  row.icon:ClearAllPoints()
  row.icon:SetPoint("LEFT", x, 0)
  row.icon:SetTexture(e.icon)
  row.icon:SetShown(e.icon ~= nil)
  row.icon:SetDesaturated(dim and true or false)
  local nx = x + 22
  local nameRight = pos.name.x + pos.name.w
  if pill and not pillAfter then
    row.pill:SetKind(pill)
    row.pill:ClearAllPoints()
    row.pill:SetPoint("LEFT", nx, 0)
    row.pill:Show()
    nx = nx + row.pill:GetWidth() + 6
  end
  row.name:ClearAllPoints()
  row.name:SetPoint("LEFT", nx, 0)
  row.name:SetWidth(0) -- unconstrained, so the text can be measured
  row.name:SetText(name)
  if pill and pillAfter then
    row.pill:SetKind(pill)
    local pw = row.pill:GetWidth()
    local room = nameRight - nx - pw - 6
    row.name:SetWidth(math.max(20, math.min(room, math.ceil(row.name:GetStringWidth()) + 1)))
    row.pill:ClearAllPoints()
    row.pill:SetPoint("LEFT", row.name, "RIGHT", 6, 0)
    row.pill:Show()
  else
    if not pill then row.pill:Hide() end
    row.name:SetWidth(math.max(20, nameRight - nx))
  end
  row.name:Show()
  place(row.cost, "cost"); row.cost:SetText(cost or "")
  place(row.sale, "sale"); row.sale:SetText(sale or "")
  place(row.value, "value"); row.value:SetText(value or "")
end

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------

local redraw -- below

local function scrollTop()
  if win then win.list.offset = 0 end
end

local function buildHeader()
  local band = W.Panel(win, "panel", false)
  band:SetPoint("TOPLEFT", 1, -TOP_HEADER)
  band:SetPoint("TOPRIGHT", -1, -TOP_HEADER)
  band:SetHeight(TOP_TABS - TOP_HEADER)
  band.line = W.Solid(band, "border", "BORDER")
  band.line:SetPoint("BOTTOMLEFT"); band.line:SetPoint("BOTTOMRIGHT"); band.line:SetHeight(1)
  win.header = band

  win.prof = W.Dropdown(band, {
    width = 190,
    tooltip = { "Profession", "Choose which of your scanned professions the window shows." },
    items = function()
      local out = {}
      for _, n in ipairs(ns.Professions()) do out[#out + 1] = { n, n, profIcon(n) } end
      return out
    end,
    onSelect = function(name)
      ns.SetProfession(name)
      scrollTop()
      ns.RefreshUI()
    end,
  })
  win.prof:SetPoint("LEFT", 9, 0)
  win.skill = W.ProgressBar(band, { width = 150, height = T.size.bar })
  win.skill:SetPoint("LEFT", win.prof, "RIGHT", 14, 0)
  win.skillText = W.Text(band, "small", "text")
  win.skillText:SetPoint("LEFT", win.skill, "RIGHT", 8, 0)
  win.gear = W.IconButton(band, "gear", function() win.settings:SetShown(not win.settings:IsShown()); redraw() end,
    { "Settings", "Every option in one place: planning, prices, lists, companions and the window layout." })
  win.gear:SetPoint("RIGHT", -9, 0)
end

local function buildTabs()
  local items = {}
  for _, t in ipairs(UI.tabs) do items[#items + 1] = { key = t.key, title = t.title, width = 86 } end
  win.tabs = W.TabStrip(win, items, function(key)
    ns.SetTab(key)
    scrollTop()
    ns.RefreshUI()
  end)
  win.tabs:SetPoint("TOPLEFT", 1, -TOP_TABS)
  win.tabs:SetPoint("TOPRIGHT", -1, -TOP_TABS)
  win.tabs.line = W.Solid(win.tabs, "border", "BORDER")
  win.tabs.line:SetPoint("BOTTOMLEFT"); win.tabs.line:SetPoint("BOTTOMRIGHT"); win.tabs.line:SetHeight(1)

  win.search = W.SearchBox(win.tabs, { width = 220, placeholder = "Search recipes and reagents",
    onChange = function() scrollTop(); redraw() end })
  win.search:SetPoint("RIGHT", -8, 0)

  win.replan = W.Button(win.tabs, { text = "Re-plan", icon = "replan", width = 86, height = 20,
    onClick = function()
      local _, _, name = ns.CurrentPlan()
      ns.ClearLock(name)
      ns.RefreshUI()
    end,
    tooltip = { "Re-plan the route", "The route stays as planned while prices change. Re-plan picks the cheapest recipes again from your skill now." } })
  win.replan:SetPoint("RIGHT", -8, 0)
  win.lockText = W.Text(win.tabs, "label", "dim", "RIGHT")
  win.lockText:SetPoint("RIGHT", win.replan, "LEFT", -10, 0)
  win.lockGlyph = W.Glyph(win.tabs, "lock", 11, "dim")
  win.lockGlyph:SetPoint("RIGHT", win.lockText, "LEFT", -4, 0)
end

local function buildChips()
  local band = W.Panel(win, "panel", false)
  band:SetPoint("TOPLEFT", 1, -TOP_CHIPS)
  band:SetPoint("TOPRIGHT", -1, -TOP_CHIPS)
  band:SetHeight(TOP_BODY - TOP_CHIPS)
  band.line = W.Solid(band, "border", "BORDER")
  band.line:SetPoint("BOTTOMLEFT"); band.line:SetPoint("BOTTOMRIGHT"); band.line:SetHeight(1)
  win.chipBand = band
  win.chips = {}
  for key, def in pairs(UI.chips) do
    local chip = W.Chip(band, { onClick = function() scrollTop(); UI.CycleChip(key) end })
    if def.tooltip then W.TipText(chip, def.tooltip[1], def.tooltip[2], def.tooltip[3]) end
    chip:Hide()
    win.chips[key] = chip
  end
  win.status = W.Text(band, "label", "dim", "RIGHT")
  win.status:SetPoint("RIGHT", -10, 0)
end

local function buildCards()
  win.cards = {}
  local w = math.floor((WIDTH - 20 - 3 * GAP) / 4)
  for i = 1, 4 do
    local c = W.Card(win, { width = w, height = 56 })
    W.Tip(c, function(tt, self)
      local d = self.data
      if not d then return false end
      tt:AddLine(d.label)
      tt:AddLine(d.tip, 1, 1, 1, true)
      tt:AddDoubleLine("Route, net", signed(-d.plan.cost))
      tt:AddDoubleLine("Learning recipes", money(d.plan.learnCost))
      tt:AddDoubleLine("Crafts", ("~%d"):format(d.crafts))
      if not d.selected then tt:AddLine("Click: price the route this way.", 0.6, 0.9, 1, true) end
    end)
    win.cards[i] = c
  end
end

local function buildList()
  win.colHeader = CreateFrame("Frame", nil, win)
  win.colHeader:SetSize(ROW_W, 18)
  win.colHeader.line = W.Solid(win.colHeader, "border", "BORDER")
  win.colHeader.line:SetPoint("BOTTOMLEFT"); win.colHeader.line:SetPoint("BOTTOMRIGHT"); win.colHeader.line:SetHeight(1)
  win.cols = {}
  for i = 1, 5 do
    local b = CreateFrame("Button", nil, win.colHeader)
    b:SetHeight(18)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b.text = W.Text(b, "label", "dim", "RIGHT")
    b.text:SetAllPoints()
    b.arrow = W.Glyph(b, "down", 10, "accent")
    b:SetScript("OnClick", function(self, button) if self.sort then ns.SortBy(self.sort, button) end end)
    W.Tip(b, function(tt, self)
      if not self.sort then return false end
      tt:AddLine("Click to sort, click again to reverse.", 1, 1, 1)
      tt:AddLine("Right-click: back to the default order.", 0.7, 0.7, 0.7)
    end, "ANCHOR_TOP")
    win.cols[i] = b
  end
  win.list = W.ScrollList(win, { width = LIST_W, height = 300, makeRow = makeRow, fill = fillRow })

  -- nothing scanned yet
  local empty = CreateFrame("Frame", nil, win)
  empty:SetSize(420, 140)
  empty.logo = W.Glyph(empty, "logo", 48, "border")
  empty.logo:SetPoint("TOP", 0, 0)
  empty.title = W.Text(empty, "title", "text", "CENTER")
  empty.title:SetPoint("TOP", empty.logo, "BOTTOM", 0, -8)
  empty.title:SetText("Nothing scanned yet")
  empty.text = W.Text(empty, "small", "dim", "CENTER")
  empty.text:SetPoint("TOP", empty.title, "BOTTOM", 0, -6)
  empty.text:SetWidth(380)
  empty.text:SetWordWrap(true)
  empty.text:SetText("Open a profession window once and Margin reads its recipes. It keeps following your skill after that.")
  empty:Hide()
  win.empty = empty
end

-- Settings: a panel over the window body, generated from the registry.
local function buildSettings()
  local p = CreateFrame("Frame", nil, win)
  p:SetPoint("TOPLEFT", 1, -TOP_HEADER)
  p:SetPoint("BOTTOMRIGHT", -1, 1)
  p:SetFrameLevel(win:GetFrameLevel() + 30)
  p:EnableMouse(true)
  p:EnableMouseWheel(true)
  p.bg = W.Solid(p, "bg")
  p.bg:SetAllPoints()
  p:Hide()
  win.settings = p

  local head = W.Panel(p, "panel", false)
  head:SetPoint("TOPLEFT"); head:SetPoint("TOPRIGHT"); head:SetHeight(32)
  head.line = W.Solid(head, "border", "BORDER")
  head.line:SetPoint("BOTTOMLEFT"); head.line:SetPoint("BOTTOMRIGHT"); head.line:SetHeight(1)
  head.glyph = W.Glyph(head, "gear", 14, "accent")
  head.glyph:SetPoint("LEFT", 10, 0)
  head.title = W.Text(head, "title", "accent")
  head.title:SetPoint("LEFT", head.glyph, "RIGHT", 6, 0)
  head.title:SetText("Settings")
  p.close = W.IconButton(head, "x", function() p:Hide(); redraw() end, { "Back", "Close the settings." })
  p.close:SetPoint("RIGHT", -9, 0)
  head.note = W.Text(head, "label", "dim", "RIGHT")
  head.note:SetPoint("RIGHT", p.close, "LEFT", -10, 0)
  head.note:SetText("Shared by all characters")

  local COL_W = math.floor((WIDTH - 2 - 3 * 14) / 2)
  local y = { 42, 42 }
  p.controls = {}
  for _, g in ipairs(UI.Groups()) do
    local col = g.column == 2 and 2 or 1
    local x = col == 1 and 14 or (14 * 2 + COL_W)
    local h5 = W.Text(p, "label", "dim")
    h5:SetPoint("TOPLEFT", x, -y[col])
    h5:SetText(g.name:upper())
    y[col] = y[col] + 18
    for _, def in ipairs(g.list) do
      local ctl
      if def.kind == "segmented" then
        local opts = type(def.options) == "function" and def.options() or def.options
        ctl = W.Segmented(p, { options = opts, onChange = function(v) UI.SetSetting(def, v) end })
      elseif def.kind == "check" then
        ctl = W.Checkbox(p, { onChange = function(v) UI.SetSetting(def, v) end })
      elseif def.kind == "button" then
        ctl = W.Button(p, { width = 110, height = 22, text = def.text(), onClick = def.onClick })
      else
        ctl = W.NumberBox(p, { width = 50,
          onCommit = function(text) UI.SetSetting(def, text) end,
          onCancel = function() redraw() end })
      end
      local rowH = def.hint and 36 or 26
      ctl:SetPoint("TOPRIGHT", p, "TOPLEFT", x + COL_W, -(y[col] + (rowH - ctl:GetHeight()) / 2))
      local labelW = COL_W - ctl:GetWidth() - 12
      local lab = W.Text(p, "small", "text")
      lab:SetPoint("TOPLEFT", x, -(y[col] + (def.hint and 3 or 7)))
      lab:SetWidth(labelW)
      lab:SetText(def.label)
      if def.hint then
        local hint = W.Text(p, "label", "dim")
        hint:SetPoint("TOPLEFT", lab, "BOTTOMLEFT", 0, -2)
        hint:SetWidth(labelW)
        hint:SetWordWrap(true)
        hint:SetText(def.hint)
      end
      ctl.def = def
      p.controls[#p.controls + 1] = ctl
      y[col] = y[col] + rowH
    end
    y[col] = y[col] + 6
  end

  local foot = W.Panel(p, "panel", false)
  foot:SetPoint("BOTTOMLEFT"); foot:SetPoint("BOTTOMRIGHT"); foot:SetHeight(24)
  foot.line = W.Solid(foot, "border", "BORDER")
  foot.line:SetPoint("TOPLEFT"); foot.line:SetPoint("TOPRIGHT"); foot.line:SetHeight(1)
  foot.text = W.Text(foot, "label", "dim")
  foot.text:SetPoint("LEFT", 10, 0)
  foot.text:SetText("Slash commands keep working: /margin route N, odds, lock, rep, cut, chance, theme.")
end

local function syncSettings()
  for _, ctl in ipairs(win.settings.controls) do
    local def = ctl.def
    local v = def.kind ~= "button" and UI.SettingValue(def) or nil
    if def.kind == "button" then
      ctl:SetText(def.text())
    elseif def.kind == "segmented" then
      ctl:SetValue(v)
    elseif def.kind == "check" then
      ctl:SetChecked(v)
    elseif not ctl:HasFocus() then
      ctl:SetText(v ~= nil and tostring(v) or "")
    end
  end
end

local function build()
  win = W.Window({ name = "MarginLedger", title = "Margin", width = WIDTH, height = HEIGHT })
  win:EnableMouseWheel(true)
  buildHeader()
  buildTabs()
  buildChips()
  win.banner = W.Banner(win, WIDTH - 2)
  win.banner:SetPoint("TOPLEFT", 1, -TOP_BODY)
  buildCards()
  buildList()
  buildSettings()
  win:SetScript("OnMouseWheel", function(_, d) win.list.Wheel(nil, d) end)
  win:SetScript("OnHide", function() win.prof.Close() end)
end

---------------------------------------------------------------------------
-- Redraw
---------------------------------------------------------------------------

local function routeData(name)
  local resale, trainer = ns.Opt("resale"), ns.Opt("useTrainer")
  local cards, sel = VM.Cards(resale, trainer, ns.PlanWith, function() return (ns.CurrentPlan()) end)
  local plan = sel.plan
  local list = VM.RouteEntries(plan, { profName = name, showHistory = S.showHistory, showStock = S.showStock,
    history = ns.History(name), stock = ns.RouteStock(plan, true) })
  return { cards = cards, sel = sel, plan = plan, list = list, target = plan.target }
end

local function layoutChips(tab)
  local prev
  for _, c in pairs(win.chips) do c:Hide() end
  for _, key in ipairs(tab and tab.chips or {}) do
    local chip, def = win.chips[key], UI.chips[key]
    if chip and def then
      chip:SetValue(UI.ChipText(def))
      chip:ClearAllPoints()
      if prev then chip:SetPoint("LEFT", prev, "RIGHT", 6, 0) else chip:SetPoint("LEFT", 10, 0) end
      chip:Show()
      prev = chip
    end
  end
end

local function layoutColumns(tab)
  pos = columnPositions(tab)
  local cols = UI.Columns(tab)
  for i, b in ipairs(win.cols) do
    local c = cols[i]
    if c then
      local p = c.key == "name" and { x = pos.icon.x, w = pos.name.x + pos.name.w - pos.icon.x } or pos[c.key]
      local title = type(c.title) == "function" and c.title() or c.title
      local active = c.sort and S.sortCol == c.sort and tab ~= "route"
      b.sort = tab ~= "route" and c.sort or nil
      b:ClearAllPoints()
      b:SetPoint("LEFT", p.x, 0)
      b:SetWidth(p.w)
      local left = c.key == "name" or c.key == "range"
      b.text:SetJustifyH(left and "LEFT" or "RIGHT")
      b.text:SetText((title or ""):upper())
      W.TextColor(b.text, active and "accent" or "dim")
      b.arrow:ClearAllPoints()
      if active then
        b.arrow:SetTexture(W.MEDIA .. (S.sortAsc and "up" or "down"))
        if left then
          b.arrow:SetPoint("LEFT", b, "LEFT", math.ceil(b.text:GetStringWidth()) + 4, 0)
        else
          b.arrow:SetPoint("RIGHT", b, "RIGHT", -math.ceil(b.text:GetStringWidth()) - 4, 0)
        end
        b.arrow:Show()
      else
        b.arrow:Hide()
      end
      b:Show()
    else
      b.sort = nil
      b:Hide()
    end
  end
end

local function layoutBody(isRoute, bannerH, hasProf)
  local top = TOP_BODY + bannerH
  local listTop
  for i, c in ipairs(win.cards) do
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", 10 + (i - 1) * (c:GetWidth() + GAP), -(top + 8))
    c:SetShown(isRoute and hasProf)
  end
  if isRoute then listTop = top + 8 + 56 + 8 else listTop = top + 4 end
  win.colHeader:ClearAllPoints()
  win.colHeader:SetPoint("TOPLEFT", LIST_X, -listTop)
  win.colHeader:SetShown(hasProf)
  win.list:ClearAllPoints()
  win.list:SetPoint("TOPLEFT", LIST_X, -(listTop + 20))
  win.list:SetViewHeight(HEIGHT - (listTop + 20) - 8)
  win.list:SetShown(hasProf)
  win.empty:ClearAllPoints()
  win.empty:SetPoint("TOP", win, "TOP", 0, -(top + 40))
  win.empty:SetShown(not hasProf)
end

local function lockLine(name)
  local lock = ns.Char().locks and ns.Char().locks[name]
  if ns.Opt("routeLock") then
    win.lockGlyph:SetTexture(W.MEDIA .. "lock")
    return lock and ("locked " .. date("%b %d", lock.t)) or "locked"
  end
  win.lockGlyph:SetTexture(W.MEDIA .. "unlock")
  return "re-plans with prices"
end

redraw = function()
  if not (win and win:IsShown()) then return end
  local name, prof = ns.ProfName()
  local tab = UI.Tab(S.tab) or UI.tabs[1]
  local isRoute = tab.key == "route"

  win.prof:SetSelected(name, name or "No profession", profIcon(name))
  win.prof:SetEnabled(#ns.Professions() > 0)
  win.skill:SetValue(prof and prof.skill or 0, prof and prof.max or 1)
  win.skillText:SetText(prof and ("%d / %d"):format(prof.skill, prof.max) or "")
  win.tabs:SetSelected(tab.key)
  win.search:SetShown(tab.search and prof ~= nil)
  win.replan:SetShown(tab.replan and prof ~= nil)
  win.lockText:SetShown(tab.replan and prof ~= nil)
  win.lockGlyph:SetShown(tab.replan and prof ~= nil)
  layoutChips(prof and tab or nil)

  local list, status, warning = {}, "", nil
  if prof then
    if isRoute then
      cache = cache or routeData(name)
      list = cache.list
      status = VM.Status("route", nil, cache.target)
      warning = VM.Warnings("route", prof, { plan = cache.plan })
      win.lockText:SetText(lockLine(name))
      win.replan:SetEnabled(ns.Opt("routeLock") and true or false)
    else
      local allScope = tab.key == "profit" and ns.Opt("profitScope") == "all"
      local counts
      list, counts = VM.RecipeList(prof, tab.key, { key = ns.Opt("sortKey"), showAll = ns.Opt("showAll"),
        allScope = allScope, query = win.search:GetText(), sortCol = S.sortCol, sortAsc = S.sortAsc, profName = name })
      status = VM.Status(tab.key, counts)
      warning = VM.Warnings(tab.key, prof, { allScope = allScope, counts = counts })
    end
  end
  win.status:SetText(status)
  local bannerH = win.banner:SetMessage("warn", warning)
  layoutBody(isRoute, bannerH, prof ~= nil)
  layoutColumns(tab.key)

  if prof and isRoute then
    for i, c in ipairs(win.cards) do
      local d = cache.cards[i]
      c.data = d
      c.action = function()
        ns.SetOpt("resale", d.resale)
        ns.SetOpt("useTrainer", d.useTrainer)
        ns.RefreshUI()
      end
      c.label:SetText(d.label)
      c.value:SetText(signed(-d.total))
      c.sub:SetText(("~%d crafts"):format(d.crafts))
      c:SetSelected(d.selected)
      if d.deltaKind == "selected" then
        c.delta:SetText(C("accent", "selected"))
      elseif d.deltaKind == "same" then
        c.delta:SetText(C("dim", "same"))
      elseif d.deltaKind == "worse" then
        c.delta:SetText(C("loss", "-" .. plain(d.diff)))      -- you would pay this much more
      else
        c.delta:SetText(C("profit", "+" .. plain(-d.diff)))   -- you would save this much
      end
    end
  end
  win.list:SetEntries(list)
  if win.settings:IsShown() then syncSettings() end
end

ns.Layouts.register("ledger", {
  title = "Ledger", palette = "ledger", order = 10,
  build = function() if not win then build() end end,
  refresh = function() cache = nil; redraw() end,
  -- names arrived: rebuild the rows. The plans themselves stay cached (ns.CurrentPlan), so this never re-plans.
  redraw = function() cache = nil; redraw() end,
  show = function() if not win then build() end; win:Show() end,
  hide = function() if win then win:Hide() end end,
  isShown = function() return win ~= nil and win:IsShown() end,
  scrollTop = scrollTop,
  -- for the smoke test and future layouts that embed parts of this one
  frame = function() return win end,
})

-- Item names arrive asynchronously; redraw once they have (text only: ns.RedrawUI never re-plans).
local loader = CreateFrame("Frame")
loader:RegisterEvent("GET_ITEM_INFO_RECEIVED")
local queued
loader:SetScript("OnEvent", function(_, _, itemID)
  if not ns.ItemWasWaiting(itemID) then return end
  if queued or not (win and win:IsShown()) then return end
  queued = true
  C_Timer.After(0.5, function() queued = nil; ns.RedrawUI() end)
end)
