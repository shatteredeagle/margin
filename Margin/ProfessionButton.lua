local _, ns = ...

-- A "Margin" button on the profession window. Other addons also add things there
-- (WhatsTraining's tab, Auctionator's crafting info, TradeSkillMaster), so instead of one
-- fixed spot it tries four candidate places and takes the first where nothing else that
-- can be clicked overlaps and the button stays on screen. It re-checks every time the
-- window opens, since other addons build their parts late.

local button

local function book() return ProfessionsFrame or TradeSkillFrame end

-- { left, bottom, right, top } of a frame, or nil when it has no position yet.
local function rectOf(f)
  local ok, l, b, w, h = pcall(f.GetRect, f)
  if ok and l and w then return { l, b, l + w, b + h } end
end

local function overlap(a, b, pad)
  pad = pad or 2
  return a[1] < b[3] + pad and a[3] > b[1] - pad and a[2] < b[4] + pad and a[4] > b[2] - pad
end

-- Everything clickable that could be in the way: buttons and edit boxes inside the window,
-- and small clickable frames hanging off it (other addons parent theirs to UIParent or the window).
local function obstacles(parent)
  local list = {}
  local sw = UIParent:GetWidth()
  local function add(f)
    if f == button or f == parent or (f.IsForbidden and f:IsForbidden()) then return end
    if not (f:IsVisible() and f:IsMouseEnabled()) then return end
    local name = f.GetName and f:GetName()
    if name and name:find("^Margin") then return end
    local r = rectOf(f)
    if not r then return end
    if (r[3] or 0) - (r[1] or 0) > sw * 0.6 then return end -- a whole window, not a control
    list[#list + 1] = { r, f }
  end
  local function visit(f, depth)
    for _, c in ipairs({ f:GetChildren() }) do
      if not (c.IsForbidden and c:IsForbidden()) then
        local t = c:GetObjectType()
        if t == "Button" or t == "CheckButton" or t == "EditBox" then add(c) end
        if depth < 3 then visit(c, depth + 1) end
      end
    end
  end
  visit(parent, 1)
  for _, c in ipairs({ UIParent:GetChildren() }) do
    if c ~= parent and not (c.IsForbidden and c:IsForbidden()) then
      local r = c:IsVisible() and c:IsMouseEnabled() and rectOf(c)
      if r and (r[3] - r[1]) < sw * 0.4 then add(c) end
    end
  end
  return list
end

-- Where the button would be for an anchor (only the four anchor kinds used below).
local function candidateRect(point, rel, relPoint, x, y, w, h)
  local rr = rectOf(rel)
  if not rr then return nil end
  local l, b, r, t = rr[1], rr[2], rr[3], rr[4]
  local ax = (relPoint:find("LEFT") and l) or (relPoint:find("RIGHT") and r) or (l + r) / 2
  local ay = (relPoint:find("TOP") and t) or (relPoint:find("BOTTOM") and b) or (b + t) / 2
  local tx, ty = ax + x, ay + y
  local left = point:find("RIGHT") and (tx - w) or tx
  local bottom = (point:find("TOP") and (ty - h)) or (point:find("BOTTOM") and ty) or (ty - h / 2)
  return { left, bottom, left + w, bottom + h }
end

local function place()
  local parent = book()
  if not (parent and button) then return end
  local w, h = button:GetSize()
  local close = parent.CloseButton or (parent.GetName and parent:GetName() and _G[parent:GetName() .. "CloseButton"])
  local candidates = {
    close and { "RIGHT", close, "LEFT", -6, 0 } or nil,
    { "BOTTOMRIGHT", parent, "TOPRIGHT", -6, 1 },
    { "BOTTOMLEFT", parent, "TOPLEFT", 6, 1 },
    { "TOPLEFT", parent, "BOTTOMLEFT", 6, -1 },
  }
  local blockers = obstacles(parent)
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  local chosen
  for _, c in ipairs(candidates) do
    local r = candidateRect(c[1], c[2], c[3], c[4], c[5], w, h)
    if r and r[1] >= 0 and r[2] >= 0 and r[3] <= sw and r[4] <= sh then
      local clear = true
      for _, o in ipairs(blockers) do
        if overlap(r, o[1]) then clear = false; break end
      end
      if clear then chosen = c; break end
    end
  end
  chosen = chosen or candidates[#candidates > 1 and 2 or 1] -- nothing free: above the top-right corner
  button:ClearAllPoints()
  button:SetPoint(chosen[1], chosen[2], chosen[3], chosen[4], chosen[5])
  if MarginDB and MarginDB.debug then ns.Print("[btn] placed at", chosen[1], chosen[3], #blockers, "obstacles") end
end

local function ensure()
  local parent = book()
  if not parent then return end
  if not button then
    button = CreateFrame("Button", "MarginProfessionButton", parent, "UIPanelButtonTemplate")
    button:SetSize(72, 22)
    button:SetText("Margin")
    button:SetScript("OnClick", function()
      local base = C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
      ns.OpenForProfession(base and base.professionName)
    end)
    button:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine("Margin")
      GameTooltip:AddLine("Profit, cheapest leveling route and shopping list for this profession.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
  end
  button:SetParent(parent)
  button:SetFrameLevel(parent:GetFrameLevel() + 20)
  button:Show()
  place()
  -- other addons build their controls a moment after the window opens: look again
  C_Timer.After(0.5, place)
end

local f = CreateFrame("Frame")
f:RegisterEvent("TRADE_SKILL_SHOW")
f:SetScript("OnEvent", function() C_Timer.After(0.1, ensure) end)
if EventRegistry and EventRegistry.RegisterCallback then
  EventRegistry:RegisterCallback("ProfessionsFrame.Show", function() C_Timer.After(0.1, ensure) end, f)
end
