local _, ns = ...

-- Design tokens: colours, fonts, spacing, and the money formatters. Nothing else in the addon writes a
-- literal colour; widgets read ns.T and register a repaint so ns.T.Set can recolour open windows live.
-- Plain Lua: no frame calls at load time (tests/calc_test.lua loads this file without WoW).

local T = {
  color = {},  -- name -> { r, g, b }
  hex = {},    -- name -> "rrggbb", for |cff escapes
  space = { xs = 4, s = 8, m = 12, l = 16 },
  size = { row = 22, section = 22, chip = 20, button = 22, bar = 9, icon = 16, title = 26 },
  current = nil,
}
ns.T = T

-- Semantic colours shared by every palette (DESIGN.md "Shared tokens").
local SHARED = {
  profit = "6ee86e", loss = "ff6b6b", warn = "ffd070",
  gold = "ffd700", silver = "c8c8c8", copper = "eda55f",
  diff0 = "ff8040", diff1 = "ffe84a", diff2 = "4fd04f", diff3 = "909090",
  unlearned = "80c0ff", make = "9fb4ff", white = "ffffff", black = "000000",
  -- pill and banner backgrounds
  pillLearn = "1d3550", pillMake = "22283f", pillHave = "1b3a22", pillAH = "3a2d12",
  bannerWarn = "3a2d12", bannerErr = "4a1f1b", bannerOk = "1b3a22", errText = "ffb0a8",
  tipHint = "9adcff",
}

-- A palette is the seven surface colours plus any shared colour it wants to override.
T.palettes = {
  ledger = { bg = "0e0d10", panel = "17161b", panel2 = "201e25", border = "4b3f26", text = "ece6d6", dim = "958e7d", accent = "d9b24c" },
  -- the colours the old window used (Blizzard's gold, plain greys), for the classic layout and its companions
  classic = { bg = "0b0b0c", panel = "141414", panel2 = "1e1e1e", border = "5a4a30", text = "ffffff", dim = "a0a0a0", accent = "ffd100",
    profit = "60ff60", loss = "ff6060", silver = "c0c0c0", diff1 = "ffff00", diff2 = "40c040" },
}

local function toRGB(h)
  return { tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 }
end

-- Fonts: the game's, re-sized (DESIGN.md: titles 15, rows 13, labels 11). Created on first use, because
-- font objects only exist in the game.
local FONTS = {
  title = { "GameFontNormal", 15, "accent" },
  tab = { "GameFontNormal", 14, "dim" },
  row = { "GameFontHighlight", 13, "text" },
  small = { "GameFontHighlightSmall", 12, "text" },
  label = { "GameFontNormalSmall", 11, "dim" },
  value = { "GameFontHighlight", 15, "text" },
}
local fontObjects = {}

function T.Font(kind)
  local spec = FONTS[kind] or FONTS.row
  local fo = fontObjects[kind]
  if fo then return fo end
  if not CreateFont then return nil end
  fo = CreateFont("MarginFont_" .. kind)
  local base = _G[spec[1]]
  if base then
    fo:CopyFontObject(base)
    local path, _, flags = fo:GetFont()
    if path then fo:SetFont(path, spec[2], flags or "") end
  end
  local c = T.color[spec[3]]
  if c then fo:SetTextColor(c[1], c[2], c[3]) end
  fontObjects[kind] = fo
  return fo
end

local listeners = {}
-- fn() repaints one widget from the current tokens. Runs now and after every palette change.
function T.OnChange(fn)
  listeners[#listeners + 1] = fn
  fn()
end

-- Switch the palette (a name in T.palettes) and repaint everything that registered.
function T.Set(name)
  local p = T.palettes[name] or T.palettes.ledger
  T.current = T.palettes[name] and name or "ledger"
  for k, h in pairs(SHARED) do T.hex[k] = p[k] or h end
  for k, h in pairs(p) do T.hex[k] = h end
  for k, h in pairs(T.hex) do T.color[k] = toRGB(h) end
  for kind, fo in pairs(fontObjects) do
    local c = T.color[FONTS[kind][3]]
    fo:SetTextColor(c[1], c[2], c[3])
  end
  for _, fn in ipairs(listeners) do fn() end
end

-- r, g, b of a token
function T.RGB(name)
  local c = T.color[name] or T.color.text
  return c[1], c[2], c[3]
end

-- text wrapped in a token's colour
function T.C(name, text)
  return "|cff" .. (T.hex[name] or "ffffff") .. tostring(text) .. "|r"
end

---------------------------------------------------------------------------
-- Money. GetCoinTextureString does not exist on Forever, so Margin formats its own.
---------------------------------------------------------------------------

function T.Money(c)
  if c == nil then return "?" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = g .. T.C("gold", "g") end
  if g > 0 or sv > 0 then parts[#parts + 1] = sv .. T.C("silver", "s") end
  parts[#parts + 1] = cp .. T.C("copper", "c")
  local out = table.concat(parts, " ")
  return neg and (T.C("loss", "-") .. out) or out
end

-- Profit or loss, the same way everywhere: green + when you come out ahead, red - when you lose money.
function T.Signed(profit)
  if profit == nil then return "?" end
  local r = math.floor(math.abs(profit) + 0.5)
  if r == 0 then return T.Money(0) end
  if profit > 0 then return T.C("profit", "+") .. T.Money(r) end
  return T.C("loss", "-") .. T.Money(r)
end

-- The amount without colour codes, so a delta can be tinted as a whole.
function T.Plain(c)
  c = math.floor(math.abs(c) + 0.5)
  local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if g > 0 or sv > 0 then out[#out + 1] = sv .. "s" end
  out[#out + 1] = cp .. "c"
  return table.concat(out, " ")
end

ns.Money = T.Money
ns.Signed = T.Signed
ns.PlainMoney = T.Plain

T.Set("ledger")
