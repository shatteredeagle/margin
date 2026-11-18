local _, ns = ...

-- The widget kit. Every widget is ns.W.Name(parent, opts) -> frame, reads colours only from the tokens
-- (ns.T), repaints itself when the palette changes (ns.T.OnChange), and never reads addon state: the
-- layouts and companions fill them. Everything is drawn from solid-colour textures, the game's fonts
-- and a few white glyphs in Media/ tinted by the tokens, so one set of files serves every palette.

local T = ns.T
local W = {}
ns.W = W

local MEDIA = "Interface\\AddOns\\Margin\\Media\\"
W.MEDIA = MEDIA

local function fill(tex, key, alpha)
  local r, g, b = T.RGB(key)
  tex:SetColorTexture(r, g, b, alpha or 1)
end
W.Fill = fill

-- A texture filled with a token, kept in that colour across palette changes.
function W.Solid(parent, key, layer, alpha)
  local t = parent:CreateTexture(nil, layer or "BACKGROUND")
  t.colorKey, t.alpha = key, alpha
  T.OnChange(function() fill(t, t.colorKey, t.alpha) end)
  function t.SetKey(k, a) t.colorKey, t.alpha = k, a; fill(t, k, a) end
  return t
end

-- 1 px border from four textures. b.SetKey(token) recolours it.
function W.Border(f, key, layer)
  local b = { key = key }
  for i = 1, 4 do b[i] = f:CreateTexture(nil, layer or "BORDER") end
  b[1]:SetPoint("TOPLEFT"); b[1]:SetPoint("TOPRIGHT"); b[1]:SetHeight(1)
  b[2]:SetPoint("BOTTOMLEFT"); b[2]:SetPoint("BOTTOMRIGHT"); b[2]:SetHeight(1)
  b[3]:SetPoint("TOPLEFT"); b[3]:SetPoint("BOTTOMLEFT"); b[3]:SetWidth(1)
  b[4]:SetPoint("TOPRIGHT"); b[4]:SetPoint("BOTTOMRIGHT"); b[4]:SetWidth(1)
  function b.SetKey(k)
    b.key = k
    for i = 1, 4 do fill(b[i], k) end
  end
  function b.SetShown(on)
    for i = 1, 4 do b[i]:SetShown(on) end
  end
  T.OnChange(function() b.SetKey(b.key) end)
  return b
end

-- A font string in one of the theme's fonts (title, tab, row, small, label, value) and colour.
function W.Text(parent, kind, colorKey, justify, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  local fo = T.Font(kind)
  if fo then fs:SetFontObject(fo) end
  fs:SetJustifyH(justify or "LEFT")
  fs:SetWordWrap(false)
  fs.colorKey = colorKey or "text"
  T.OnChange(function() fs:SetTextColor(T.RGB(fs.colorKey)) end)
  return fs
end

function W.TextColor(fs, key)
  fs.colorKey = key
  fs:SetTextColor(T.RGB(key))
end

-- One of the white glyphs in Media/, tinted by a token.
function W.Glyph(parent, name, size, colorKey, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture(MEDIA .. name)
  t:SetSize(size, size)
  t.colorKey = colorKey or "accent"
  T.OnChange(function() t:SetVertexColor(T.RGB(t.colorKey)) end)
  function t.SetKey(k) t.colorKey = k; t:SetVertexColor(T.RGB(k)) end
  return t
end

-- Tooltip helper: builder(GameTooltip, frame) adds the lines; returning false shows nothing.
function W.Tip(f, builder, anchor)
  f:HookScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, anchor or "ANCHOR_BOTTOM")
    if builder(GameTooltip, self) == false then GameTooltip:Hide() else GameTooltip:Show() end
  end)
  f:HookScript("OnLeave", GameTooltip_Hide)
end

-- The usual tooltip: a title, a white explanation, a grey note.
function W.TipText(f, title, body, note, anchor)
  W.Tip(f, function(tt)
    tt:AddLine(title)
    if body then tt:AddLine(body, 1, 1, 1, true) end
    if note then tt:AddLine(note, 0.7, 0.7, 0.7, true) end
  end, anchor)
end

---------------------------------------------------------------------------
-- Panel, Window
---------------------------------------------------------------------------

function W.Panel(parent, bgKey, borderKey)
  local f = CreateFrame("Frame", nil, parent)
  f.bg = W.Solid(f, bgKey or "panel")
  f.bg:SetAllPoints()
  if borderKey ~= false then f.border = W.Border(f, borderKey or "border") end
  return f
end

-- A movable window with a title bar (logo, title, close). Closes on Escape when it has a name.
-- Content goes below f.top (the title bar's height).
function W.Window(o)
  local f = CreateFrame("Frame", o.name, o.parent or UIParent)
  f:SetSize(o.width, o.height)
  f:SetPoint(unpack(o.point or { "CENTER" }))
  f:SetFrameStrata(o.strata or "HIGH")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  if o.name and o.escape ~= false then tinsert(UISpecialFrames, o.name) end
  f.bg = W.Solid(f, "bg")
  f.bg:SetAllPoints()
  f.border = W.Border(f, "border")

  local bar = CreateFrame("Frame", nil, f)
  bar:SetPoint("TOPLEFT", 1, -1)
  bar:SetPoint("TOPRIGHT", -1, -1)
  bar:SetHeight(T.size.title - 1)
  bar.bg = W.Solid(bar, "panel2")
  bar.bg:SetAllPoints()
  bar.line = W.Solid(bar, "border", "BORDER")
  bar.line:SetPoint("BOTTOMLEFT")
  bar.line:SetPoint("BOTTOMRIGHT")
  bar.line:SetHeight(1)
  f.titleBar = bar
  f.logo = W.Glyph(bar, "logo", 16, "accent")
  f.logo:SetPoint("LEFT", 9, 0)
  f.title = W.Text(bar, "title", "accent")
  f.title:SetPoint("LEFT", f.logo, "RIGHT", 7, 0)
  f.title:SetText(o.title or "Margin")
  f.close = W.Button(bar, { width = 18, height = 18, icon = "x", iconSize = 10, onClick = function() f:Hide() end })
  f.close:SetPoint("RIGHT", -5, 0)
  f.top = T.size.title
  function f.SetTitle(_, text) f.title:SetText(text) end
  return f
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------

-- o: text, icon (glyph name), iconSize, width, height, primary, font, onClick(self, mouseButton),
-- rightClick (also take right clicks), tooltip = { title, body, note }, name (global name)
function W.Button(parent, o)
  o = o or {}
  local b = CreateFrame("Button", o.name, parent)
  b:SetSize(o.width or 80, o.height or T.size.button)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.border = W.Border(b, "border")
  b.label = W.Text(b, o.font or "small", "text", o.justify or "CENTER")
  b.label:SetPoint("LEFT", 6, 0)
  b.label:SetPoint("RIGHT", -6, 0)
  if o.icon then
    b.icon = W.Glyph(b, o.icon, o.iconSize or 12, "dim")
    if o.text then
      b.icon:SetPoint("LEFT", 7, 0)
      b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
    else
      b.icon:SetPoint("CENTER")
    end
  end
  b.primary = o.primary
  local function paint()
    fill(b.bg, b.armed and "bannerErr" or "panel2")
    b.border.SetKey((b.armed and "loss") or ((b.hover or b.primary) and "accent") or "border")
    W.TextColor(b.label, b.armed and "white" or (b.primary and "accent" or (b.hover and "white" or "text")))
    if b.icon then b.icon.SetKey(b.primary and "accent" or (b.hover and "text" or "dim")) end
  end
  b.Paint = paint
  T.OnChange(paint)
  b:SetScript("OnEnter", function() b.hover = true; paint() end)
  b:SetScript("OnLeave", function() b.hover = false; paint() end)
  if o.rightClick then b:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  b:SetScript("OnClick", function(self, button) if o.onClick then o.onClick(self, button) end end)
  function b.SetText(self, text) self.label:SetText(text) end
  function b.GetText(self) return self.label:GetText() end
  local nativeEnabled = b.SetEnabled
  function b.SetEnabled(self, on)
    nativeEnabled(self, on and true or false)
    self:SetAlpha(on and 1 or 0.45)
  end
  -- the "Sure?" state of a two-click confirm
  function b.SetArmed(self, on)
    self.armed = on and true or nil
    paint()
  end
  if o.text then b:SetText(o.text) end
  if o.tooltip then W.TipText(b, o.tooltip[1], o.tooltip[2], o.tooltip[3]) end
  return b
end

function W.IconButton(parent, icon, onClick, tooltip)
  return W.Button(parent, { width = 22, height = 22, icon = icon, iconSize = 14, onClick = onClick, tooltip = tooltip })
end

---------------------------------------------------------------------------
-- Tabs, chips, segmented control, checkbox, number and search boxes
---------------------------------------------------------------------------

-- Underline tabs. items = { { key, title, width } }; onSelect(key). strip:SetSelected(key).
function W.TabStrip(parent, items, onSelect)
  local strip = CreateFrame("Frame", nil, parent)
  strip:SetHeight(28)
  strip.tabs = {}
  local prev
  for _, it in ipairs(items) do
    local t = CreateFrame("Button", nil, strip)
    t.key = it.key
    t:SetSize(it.width or 84, 28)
    if prev then t:SetPoint("LEFT", prev, "RIGHT", 2, 0) else t:SetPoint("LEFT", strip, "LEFT", 4, 0) end
    t.text = W.Text(t, "tab", "dim", "CENTER")
    t.text:SetPoint("CENTER", 0, 1)
    t.text:SetText(it.title)
    t.line = W.Solid(t, "accent", "ARTWORK")
    t.line:SetPoint("BOTTOMLEFT", 8, 0)
    t.line:SetPoint("BOTTOMRIGHT", -8, 0)
    t.line:SetHeight(2)
    t:SetScript("OnClick", function() onSelect(it.key) end)
    t:SetScript("OnEnter", function() t.hover = true; strip.Paint() end)
    t:SetScript("OnLeave", function() t.hover = false; strip.Paint() end)
    strip.tabs[#strip.tabs + 1] = t
    prev = t
  end
  function strip.Paint()
    for _, t in ipairs(strip.tabs) do
      local on = t.key == strip.selected
      W.TextColor(t.text, on and "accent" or (t.hover and "text" or "dim"))
      t.line:SetShown(on)
    end
  end
  function strip.SetSelected(_, key)
    strip.selected = key
    strip.Paint()
  end
  T.OnChange(strip.Paint)
  return strip
end

-- A chip names its setting and shows its value ("Resale: vendor"); a click moves to the next value.
-- chip:SetValue(label, value, highlighted) sizes it to fit.
function W.Chip(parent, o)
  o = o or {}
  local c = CreateFrame("Button", nil, parent)
  c:SetHeight(T.size.chip)
  c.bg = W.Solid(c, "panel2")
  c.bg:SetAllPoints()
  c.border = W.Border(c, "border")
  c.text = W.Text(c, "small", "text")
  c.text:SetPoint("LEFT", 8, 0)
  c.chev = W.Glyph(c, "chev", 10, "dim")
  c.chev:SetPoint("RIGHT", -6, 0)
  local function paint()
    c.border.SetKey((c.on or c.hover) and "accent" or "border")
    W.TextColor(c.text, c.on and "accent" or "text")
  end
  T.OnChange(paint)
  c:SetScript("OnEnter", function() c.hover = true; paint() end)
  c:SetScript("OnLeave", function() c.hover = false; paint() end)
  c:SetScript("OnClick", function(self, button) if o.onClick then o.onClick(self, button) end end)
  function c.SetValue(_, label, value, on)
    c.on = on and true or nil
    c.text:SetText(T.C("dim", label) .. " " .. value)
    c:SetWidth(math.max(56, math.ceil(c.text:GetStringWidth()) + 30))
    paint()
  end
  return c
end

-- Segmented control: options = { { value, label } }, onChange(value), segWidth (else sized to the text).
function W.Segmented(parent, o)
  local f = CreateFrame("Frame", nil, parent)
  f.bg = W.Solid(f, "black")
  f.bg:SetAllPoints()
  f.border = W.Border(f, "border")
  f.buttons = {}
  local x = 1
  for i, opt in ipairs(o.options) do
    local b = CreateFrame("Button", nil, f)
    b.value = opt[1]
    b.bg = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.bg:SetAllPoints()
    b.text = W.Text(b, "small", "dim", "CENTER")
    b.text:SetPoint("CENTER")
    b.text:SetText(opt[2])
    local w = o.segWidth or math.max(40, math.ceil(b.text:GetStringWidth()) + 18)
    b:SetSize(w, (o.height or 20) - 2)
    b:SetPoint("TOPLEFT", x, -1)
    if i > 1 then
      local sep = W.Solid(b, "border", "BORDER")
      sep:SetPoint("TOPLEFT", -1, 0)
      sep:SetPoint("BOTTOMLEFT", -1, 0)
      sep:SetWidth(1)
    end
    x = x + w + (i < #o.options and 1 or 0)
    b:SetScript("OnClick", function() if o.onChange then o.onChange(opt[1]) end end)
    if opt[3] then W.TipText(b, opt[2], opt[3]) end
    f.buttons[i] = b
  end
  f:SetSize(x + 1, o.height or 20)
  function f.Paint()
    for _, b in ipairs(f.buttons) do
      local on = b.value == f.value
      if on then fill(b.bg, "panel2") else b.bg:SetColorTexture(0, 0, 0, 0) end
      W.TextColor(b.text, on and "accent" or "dim")
    end
  end
  function f.SetValue(_, v)
    f.value = v
    f.Paint()
  end
  T.OnChange(f.Paint)
  return f
end

-- Checkbox: a 13 px box with the check glyph, optional label to its right. onChange(checked).
function W.Checkbox(parent, o)
  o = o or {}
  local c = CreateFrame("Button", nil, parent)
  c:SetSize(14, 14)
  c.box = CreateFrame("Frame", nil, c)
  c.box:SetSize(13, 13)
  c.box:SetPoint("LEFT")
  c.box.bg = W.Solid(c.box, "black")
  c.box.bg:SetAllPoints()
  c.box.border = W.Border(c.box, "border")
  c.check = W.Glyph(c.box, "check", 11, "accent", "OVERLAY")
  c.check:SetPoint("CENTER")
  if o.label then
    c.text = W.Text(c, "small", "text")
    c.text:SetPoint("LEFT", c.box, "RIGHT", 6, 0)
    c.text:SetText(o.label)
    c:SetWidth(20 + math.ceil(c.text:GetStringWidth()))
  end
  c:SetScript("OnEnter", function() c.box.border.SetKey("accent") end)
  c:SetScript("OnLeave", function() c.box.border.SetKey("border") end)
  function c.SetChecked(_, v)
    c.checked = v and true or false
    c.check:SetShown(c.checked)
  end
  function c.GetChecked() return c.checked end
  c:SetScript("OnClick", function()
    c:SetChecked(not c.checked)
    if o.onChange then o.onChange(c.checked) end
  end)
  if o.tooltip then W.TipText(c, o.tooltip[1], o.tooltip[2], o.tooltip[3]) end
  c:SetChecked(false)
  return c
end

-- A plain edit box drawn with the tokens. onCommit(text) on Enter and when focus leaves; Escape
-- cancels (onCancel lets the owner put the stored value back).
local function editBox(parent, width, height)
  local e = CreateFrame("EditBox", nil, parent)
  e:SetSize(width, height or 20)
  e:SetAutoFocus(false)
  e:EnableMouse(true)
  local fo = T.Font("small")
  if fo then e:SetFontObject(fo) end
  e.bg = W.Solid(e, "black")
  e.bg:SetAllPoints()
  e.border = W.Border(e, "border")
  e:SetScript("OnEditFocusGained", function() e.border.SetKey("accent") end)
  return e
end

function W.NumberBox(parent, o)
  local e = editBox(parent, o.width or 46, o.height)
  e:SetMaxLetters(o.maxLetters or 5)
  e:SetJustifyH("RIGHT")
  e:SetTextInsets(4, 6, 0, 0)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEscapePressed", function(self) self.cancelled = true; self:ClearFocus() end)
  e:SetScript("OnEditFocusLost", function(self)
    self.border.SetKey("border")
    if self.cancelled then
      self.cancelled = nil
      if o.onCancel then o.onCancel(self) end
      return
    end
    if o.onCommit then o.onCommit(self:GetText()) end
  end)
  return e
end

-- Search box with a glyph and a placeholder. onChange(text) as you type; Escape clears it.
function W.SearchBox(parent, o)
  local e = editBox(parent, o.width or 200, o.height or 20)
  e:SetMaxLetters(40)
  e:SetTextInsets(20, 6, 0, 0)
  e.glyph = W.Glyph(e, "search", 12, "dim")
  e.glyph:SetPoint("LEFT", 5, 0)
  e.hint = W.Text(e, "small", "dim")
  e.hint:SetPoint("LEFT", 20, 0)
  e.hint:SetPoint("RIGHT", -6, 0)
  e.hint:SetText(o.placeholder or "Search")
  local function hint() e.hint:SetShown(e:GetText() == "" and not e.focused) end
  e:SetScript("OnEditFocusGained", function() e.focused = true; e.border.SetKey("accent"); hint() end)
  e:SetScript("OnEditFocusLost", function() e.focused = false; e.border.SetKey("border"); hint() end)
  e:SetScript("OnTextChanged", function(self, user)
    hint()
    if user and o.onChange then o.onChange(self:GetText()) end
  end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
    if o.onChange then o.onChange("") end
  end)
  return e
end

---------------------------------------------------------------------------
-- Bars, cards, pills, banners, money
---------------------------------------------------------------------------

-- A two-texture bar (skill bar, have/need bar). bar:SetValue(value, max).
function W.ProgressBar(parent, o)
  o = o or {}
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(o.width or 140, o.height or T.size.bar)
  f.bg = W.Solid(f, "black")
  f.bg:SetAllPoints()
  f.border = W.Border(f, "border")
  f.fill = W.Solid(f, o.color or "accent", "ARTWORK")
  f.fill:SetPoint("TOPLEFT", 1, -1)
  f.fill:SetPoint("BOTTOMLEFT", 1, 1)
  function f.SetValue(_, v, max)
    local frac = (max and max > 0) and math.min(1, math.max(0, (v or 0) / max)) or 0
    f.fill:SetWidth(math.max(1, (f:GetWidth() - 2) * frac))
    f.fill:SetShown(frac > 0)
  end
  function f.SetColorKey(_, key) f.fill.SetKey(key) end
  return f
end

-- Comparison card, 160 x 56: label and delta on line one, value and sub on line two; gold frame when
-- selected.
function W.Card(parent, o)
  o = o or {}
  local c = CreateFrame("Button", nil, parent)
  c:SetSize(o.width or 160, o.height or 56)
  c.bg = W.Solid(c, "panel2")
  c.bg:SetAllPoints()
  c.border = W.Border(c, "border")
  c.inner = CreateFrame("Frame", nil, c)
  c.inner:SetPoint("TOPLEFT", 1, -1)
  c.inner:SetPoint("BOTTOMRIGHT", -1, 1)
  c.innerBorder = W.Border(c.inner, "accent")
  c.label = W.Text(c, "label", "dim")
  c.label:SetPoint("TOPLEFT", 8, -7)
  c.delta = W.Text(c, "label", "text", "RIGHT")
  c.delta:SetPoint("TOPRIGHT", -8, -7)
  c.value = W.Text(c, "value", "text")
  c.value:SetPoint("BOTTOMLEFT", 8, 9)
  c.sub = W.Text(c, "label", "dim", "RIGHT")
  c.sub:SetPoint("BOTTOMRIGHT", -8, 10)
  local function paint()
    c.border.SetKey((c.selected or c.hover) and "accent" or "border")
    c.innerBorder.SetShown(c.selected and true or false)
  end
  T.OnChange(paint)
  c:SetScript("OnEnter", function() c.hover = true; paint() end)
  c:SetScript("OnLeave", function() c.hover = false; paint() end)
  c:SetScript("OnClick", function(self) if self.action then self.action() end end)
  function c.SetSelected(_, on)
    c.selected = on and true or nil
    paint()
  end
  return c
end

-- Pill: a small coloured tag ("learn", "make", "have", "AH", "vendor", "done").
local PILLS = {
  learn = { "pillLearn", "unlearned", "book", "LEARN" },
  make = { "pillMake", "make", "hammer", "MAKE" },
  have = { "pillHave", "profit", "check", "HAVE" },
  done = { "pillHave", "profit", "check", "DONE" },
  ah = { "pillAH", "warn", nil, "AH" },
  cheaper = { "pillAH", "warn", nil, "AH IS CHEAPER" },
  vendor = { "pillLearn", "unlearned", nil, "VENDOR" },
}
function W.Pill(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetHeight(14)
  p.bg = W.Solid(p, "pillLearn")
  p.bg:SetAllPoints()
  p.glyph = W.Glyph(p, "book", 9, "unlearned")
  p.glyph:SetPoint("LEFT", 4, 0)
  p.text = W.Text(p, "label", "unlearned")
  function p.SetKind(_, kind)
    local k = PILLS[kind] or PILLS.learn
    p.bg.SetKey(k[1])
    W.TextColor(p.text, k[2])
    p.text:SetText(k[4])
    p.text:ClearAllPoints()
    if k[3] then
      p.glyph:SetTexture(MEDIA .. k[3])
      p.glyph.SetKey(k[2])
      p.glyph:Show()
      p.text:SetPoint("LEFT", p.glyph, "RIGHT", 3, 0)
      p:SetWidth(math.ceil(p.text:GetStringWidth()) + 21)
    else
      p.glyph:Hide()
      p.text:SetPoint("LEFT", 5, 0)
      p:SetWidth(math.ceil(p.text:GetStringWidth()) + 10)
    end
  end
  return p
end

-- Banner: a strip of text that wraps instead of truncating. banner:SetMessage(kind, text) with kind
-- "warn" | "err" | "ok" | "info"; nil text hides it. Height follows the text.
local BANNERS = {
  warn = { "bannerWarn", "warn", "warn" },
  err = { "bannerErr", "errText", "warn" },
  ok = { "bannerOk", "profit", "check" },
  info = { "panel", "text", nil },
}
function W.Banner(parent, width)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, 22)
  f.bg = W.Solid(f, "bannerWarn")
  f.bg:SetAllPoints()
  f.line = W.Solid(f, "border", "BORDER")
  f.line:SetPoint("BOTTOMLEFT")
  f.line:SetPoint("BOTTOMRIGHT")
  f.line:SetHeight(1)
  f.glyph = W.Glyph(f, "warn", 12, "warn")
  f.glyph:SetPoint("TOPLEFT", 9, -5)
  f.text = W.Text(f, "small", "warn")
  f.text:SetPoint("TOPLEFT", 26, -5)
  f.text:SetWidth(width - 36)
  f.text:SetWordWrap(true)
  f:Hide()
  function f.SetMessage(_, kind, text)
    if not text or text == "" then f:Hide(); return 0 end
    local k = BANNERS[kind] or BANNERS.warn
    f.bg.SetKey(k[1])
    W.TextColor(f.text, k[2])
    f.glyph:SetShown(k[3] ~= nil)
    if k[3] then
      f.glyph:SetTexture(MEDIA .. k[3])
      f.glyph.SetKey(k[2])
    end
    f.text:ClearAllPoints()
    f.text:SetPoint("TOPLEFT", k[3] and 26 or 10, -5)
    f.text:SetText(text)
    local h = math.max(22, math.ceil(f.text:GetStringHeight()) + 10)
    f:SetHeight(h)
    f:Show()
    return h
  end
  return f
end

-- Money text: money:SetMoney(copper); signed:SetSigned(profit) (green + earn, red - lose).
function W.MoneyText(parent, kind, justify)
  local fs = W.Text(parent, kind or "row", "text", justify or "RIGHT")
  function fs.SetMoney(_, c) fs:SetText(T.Money(c)) end
  return fs
end

function W.SignedMoneyText(parent, kind, justify)
  local fs = W.Text(parent, kind or "row", "text", justify or "RIGHT")
  function fs.SetSigned(_, p) fs:SetText(T.Signed(p)) end
  return fs
end

---------------------------------------------------------------------------
-- Scroll list: pooled rows, mouse wheel, a Slider for a scroll bar. Rows can differ in height
-- (heightOf(entry)); the offset is an entry index.
--   o.width, o.height, o.makeRow(list) -> row frame, o.fill(row, entry), o.heightOf(entry)
---------------------------------------------------------------------------

function W.ScrollList(parent, o)
  local L = CreateFrame("Frame", nil, parent)
  L:SetSize(o.width, o.height)
  L.viewH = o.height
  L.rows, L.entries, L.offset = {}, {}, 0
  local heightOf = o.heightOf or function() return T.size.row end
  L.rowWidth = o.width - 14

  local bar = CreateFrame("Slider", nil, L)
  bar:SetOrientation("VERTICAL")
  bar:SetPoint("TOPRIGHT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", 0, 0)
  bar:SetWidth(12)
  bar:SetObeyStepOnDrag(true)
  bar:SetValueStep(1)
  bar:SetMinMaxValues(0, 0)
  bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
  bar:GetThumbTexture():SetSize(12, 22)
  bar.track = W.Solid(bar, "panel")
  bar.track:SetAllPoints()
  L.bar = bar

  function L.Wheel(_, d) L:SetOffset(L.offset - d * 3) end
  L:EnableMouseWheel(true)
  L:SetScript("OnMouseWheel", L.Wheel)

  function L.MaxOffset()
    local h, list = 0, L.entries
    for i = #list, 1, -1 do
      h = h + heightOf(list[i])
      if h > L.viewH + 0.5 then return i end
    end
    return 0
  end

  function L.Draw()
    local list, y, n, i = L.entries, 0, 0, L.offset + 1
    while list[i] do
      local h = heightOf(list[i])
      if y + h > L.viewH + 0.5 then break end
      n = n + 1
      local row = L.rows[n]
      if not row then
        row = o.makeRow(L)
        row:SetWidth(L.rowWidth)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", L.Wheel)
        L.rows[n] = row
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -y)
      row:SetHeight(h)
      row.entry = list[i]
      o.fill(row, list[i])
      row:Show()
      y = y + h
      i = i + 1
    end
    for k = n + 1, #L.rows do
      L.rows[k].entry = nil
      L.rows[k]:Hide()
    end
  end

  function L.SetOffset(_, v)
    local max = L.MaxOffset()
    L.offset = math.min(math.max(0, math.floor((v or 0) + 0.5)), max)
    bar:SetMinMaxValues(0, max)
    bar:SetValue(L.offset)
    bar:SetShown(max > 0)
    L.Draw()
  end

  function L.SetEntries(_, list)
    L.entries = list or {}
    L:SetOffset(L.offset)
  end

  function L.SetViewHeight(_, h)
    L.viewH = h
    L:SetHeight(h)
  end

  bar:SetScript("OnValueChanged", function(_, v)
    v = math.floor(v + 0.5)
    if v ~= L.offset then L.offset = v; L.Draw() end
  end)
  return L
end

---------------------------------------------------------------------------
-- Dropdown: a button that opens a small menu of items { value, text, icon }. o.items() builds the
-- list when it opens; o.onSelect(value). A click anywhere else closes it.
---------------------------------------------------------------------------

-- A small menu at the mouse: items = { { text, fn } }. Click anywhere else closes it.
local popup
function W.PopupMenu(items)
  if not popup then
    popup = {}
    popup.catcher = CreateFrame("Button", nil, UIParent)
    popup.catcher:SetAllPoints(UIParent)
    popup.catcher:SetFrameStrata("DIALOG")
    popup.catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    popup.catcher:Hide()
    popup.menu = W.Panel(UIParent, "panel", "border")
    popup.menu:SetFrameStrata("DIALOG")
    popup.menu:SetFrameLevel(popup.catcher:GetFrameLevel() + 5)
    popup.menu:Hide()
    popup.items = {}
    function popup.Close() popup.menu:Hide(); popup.catcher:Hide() end
    popup.catcher:SetScript("OnClick", popup.Close)
  end
  if #items == 0 then return popup.Close() end
  local width = 190
  for i, it in ipairs(items) do
    local b = popup.items[i]
    if not b then
      b = CreateFrame("Button", nil, popup.menu)
      b:SetHeight(22)
      b.hl = W.Solid(b, "panel2")
      b.hl:SetAllPoints()
      b.hl:Hide()
      b.text = W.Text(b, "row", "text")
      b.text:SetPoint("LEFT", 8, 0)
      b.text:SetPoint("RIGHT", -8, 0)
      b:SetScript("OnEnter", function() b.hl:Show() end)
      b:SetScript("OnLeave", function() b.hl:Hide() end)
      b:SetScript("OnClick", function()
        popup.Close()
        if b.fn then b.fn() end
      end)
      popup.items[i] = b
    end
    b.fn = it[2]
    b.text:SetText(it[1])
    width = math.max(width, math.min(360, b.text:GetStringWidth() + 20))
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22)
    b:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 22)
    b:Show()
  end
  for i = #items + 1, #popup.items do popup.items[i]:Hide() end
  popup.menu:SetSize(width, #items * 22 + 2)
  local x, y = GetCursorPosition()
  local scale = UIParent:GetEffectiveScale()
  popup.menu:ClearAllPoints()
  popup.menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale - 8, y / scale + 8)
  popup.catcher:Show()
  popup.menu:Show()
end

function W.Dropdown(parent, o)
  local d
  d = W.Button(parent, { width = o.width or 170, height = o.height or 24, justify = "LEFT", font = "row",
    onClick = function() d:Toggle() end, tooltip = o.tooltip })
  d.itemIcon = d:CreateTexture(nil, "ARTWORK")
  d.itemIcon:SetSize(16, 16)
  d.itemIcon:SetPoint("LEFT", 5, 0)
  d.itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  d.label:ClearAllPoints()
  d.label:SetPoint("LEFT", d.itemIcon, "RIGHT", 6, 0)
  d.label:SetPoint("RIGHT", -20, 0)
  d.chev = W.Glyph(d, "chev", 10, "dim")
  d.chev:SetPoint("RIGHT", -7, 0)

  local catcher = CreateFrame("Button", nil, UIParent)
  catcher:SetAllPoints(UIParent)
  catcher:SetFrameStrata("DIALOG")
  catcher:Hide()
  local menu = W.Panel(UIParent, "panel", "border")
  menu:SetFrameStrata("DIALOG")
  menu:SetFrameLevel(catcher:GetFrameLevel() + 5)
  menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
  menu:Hide()
  menu.items = {}
  d.menu = menu

  function d.Close()
    menu:Hide()
    catcher:Hide()
  end
  catcher:SetScript("OnClick", d.Close)
  d:HookScript("OnHide", d.Close)

  function d.Toggle()
    if menu:IsShown() then return d.Close() end
    local items = o.items()
    if #items == 0 then return end
    for i, it in ipairs(items) do
      local b = menu.items[i]
      if not b then
        b = CreateFrame("Button", nil, menu)
        b:SetHeight(22)
        b.hl = W.Solid(b, "panel2")
        b.hl:SetAllPoints()
        b.hl:Hide()
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 6, 0)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.text = W.Text(b, "row", "text")
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        b.text:SetPoint("RIGHT", -6, 0)
        b:SetScript("OnEnter", function() b.hl:Show() end)
        b:SetScript("OnLeave", function() b.hl:Hide() end)
        b:SetScript("OnClick", function()
          d.Close()
          if o.onSelect then o.onSelect(b.value) end
        end)
        menu.items[i] = b
      end
      b.value = it[1]
      b.text:SetText(it[2])
      W.TextColor(b.text, it[1] == d.value and "accent" or "text")
      b.icon:SetTexture(it[3])
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", 1, -1 - (i - 1) * 22)
      b:SetPoint("TOPRIGHT", -1, -1 - (i - 1) * 22)
      b:Show()
    end
    for i = #items + 1, #menu.items do menu.items[i]:Hide() end
    menu:SetSize(d:GetWidth(), #items * 22 + 2)
    catcher:Show()
    menu:Show()
  end

  function d.SetSelected(_, value, text, icon)
    d.value = value
    d:SetText(text or "")
    d.itemIcon:SetTexture(icon)
  end
  return d
end
