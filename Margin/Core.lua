local _, ns = ...

ns.defaults = {
  ahCut = 0.05,       -- fraction the AH keeps when a sale completes
  minAge = nil,       -- reserved: max Auctionator data age in days
  sortKey = "vendor", -- "vendor" or "ah"
}

local function chardb()
  MarginDB.chars = MarginDB.chars or {}
  local key = UnitName("player") .. "-" .. GetRealmName()
  MarginDB.chars[key] = MarginDB.chars[key] or { profs = {} }
  return MarginDB.chars[key]
end

function ns.Char() return chardb() end
function ns.Opt(k)
  local v = MarginDB.opts and MarginDB.opts[k]
  if v == nil then return ns.defaults[k] end
  return v
end
function ns.SetOpt(k, v)
  MarginDB.opts = MarginDB.opts or {}
  MarginDB.opts[k] = v
end

function ns.Print(...) print("|cff66ccffMargin|r", ...) end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(_, _, name)
  if name ~= "Margin" then return end
  MarginDB = MarginDB or {}
  f:UnregisterEvent("ADDON_LOADED")
end)

SLASH_MARGIN1 = "/margin"
SLASH_MARGIN2 = "/mg"
SlashCmdList.MARGIN = function(msg)
  msg = (msg or ""):lower()
  if msg == "scan" then
    ns.Scan(true)
  elseif msg == "report" then
    ns.Report()
  elseif msg:match("^cut") then
    local pct = tonumber(msg:match("cut%s+(%d+)"))
    if pct then ns.SetOpt("ahCut", pct / 100); ns.Print("AH cut", pct .. "%") end
  else
    ns.ToggleUI()
  end
end
