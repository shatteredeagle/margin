local _, ns = ...

-- Tooltip builders for list entries (ViewModel.lua kinds), shared by the layouts.
-- ns.Tips.Entry(tt, entry) adds the lines for any entry and returns false when it has none.

local Tips = {}
ns.Tips = Tips

local function money(c) return ns.T.Money(c) end
local HINT = { 0.6, 0.9, 1 }
local NOTE = { 0.7, 0.7, 0.7 }

-- Reagents, cost, sales, skill-up chance and net of a recipe row (Calc.lua's Evaluate row).
function Tips.Recipe(tt, d)
  tt:AddLine(d.r.name)
  for _, l in ipairs(d.lines) do
    tt:AddDoubleLine(l.count .. "x " .. ns.ItemName(l.item),
      l.unit and (money(l.unit * l.count) .. " (" .. l.src .. ")") or "no price", 1, 1, 1, 1, 1, 1)
  end
  tt:AddDoubleLine("Cost", money(d.cost))
  local vend, ah = ns.Revenue(d.r)
  tt:AddDoubleLine("Vendor sale", money(vend))
  tt:AddDoubleLine("AH sale (net)", money(ah))
  tt:AddDoubleLine(ns.Opt("odds") == "typical" and "Skill-up chance (typical)" or "Skill-up chance (worst case)",
    ("%d%%"):format(ns.Odds(d.r.diff) * 100))
  if d.net and (ns.Opt("resale") or "off") ~= "off" then
    tt:AddDoubleLine("Net per craft (resale - cost)", ns.T.Signed(-d.net))
  end
end

local HOW = { trainer = "trainer", ah = "buy the pattern on the AH", vendor = "buy the pattern from a vendor" }

local function craftHint(tt, e)
  if e.quote then
    tt:AddLine("Click: plan a craft run (pick how many; see what to buy, the cost and the profit).", HINT[1], HINT[2], HINT[3], true)
  elseif e.craft and not e.craft.learnFirst then
    tt:AddLine(e.craft.count and ("Click: open it in the profession window, craft %d."):format(e.craft.count)
      or "Click: open it in the profession window.", HINT[1], HINT[2], HINT[3], true)
  elseif e.craft and e.craft.learnFirst then
    tt:AddLine("Learn it first: see \"Recipes to learn\".", NOTE[1], NOTE[2], NOTE[3], true)
  end
end

local SECTIONS = {
  history = { "Completed steps", "What raised your skill, with what it cost at today's prices. Click to show or hide." },
  stock = { "Crafted stock", "What this route has made and you are holding (bags and bank), and what it would fetch. The right-hand figure takes the better of vendor and AH for each item.",
    "AH values are after the AH cut and the deposit you would lose on listings that do not sell. Click to show or hide the items." },
  steps = { "Steps", "The cheapest recipe for each stretch of skill, and its net: what the crafts cost minus what the results sell for (with the resale setting)." },
  learn = { "Recipes to learn", "Recipes the route uses that you still have to learn, and what learning them costs." },
  shop = { "Shopping list", "What the route needs, minus what you already hold. AH items whose listings Margin has seen are costed by buying the cheapest listings first." },
}

function Tips.Entry(tt, e)
  local k = e.kind
  if k == "recipe" or k == "step" then
    Tips.Recipe(tt, e.data)
    craftHint(tt, e)
  elseif k == "prep" then
    tt:AddLine(e.name)
    if e.mode == "make" then
      tt:AddLine(("%d needed for %s; making them costs less than buying them."):format(e.needed, e.forName), 1, 1, 1, true)
      if e.have > 0 then tt:AddLine(("You already hold %d, so only %d are left to make."):format(e.have, e.units), 0.6, 1, 0.6, true) end
      tt:AddLine("Do this before the step below.", NOTE[1], NOTE[2], NOTE[3], true)
      craftHint(tt, e)
    else
      tt:AddLine(("You hold the %d that %s needs."):format(e.have, e.forName), 0.6, 1, 0.6, true)
    end
  elseif k == "section" then
    local s = SECTIONS[e.key]
    if not s then return false end
    tt:AddLine(s[1])
    tt:AddLine(s[2], 1, 1, 1, true)
    if s[3] then tt:AddLine(s[3], NOTE[1], NOTE[2], NOTE[3], true) end
    if e.key == "stock" then
      tt:AddDoubleLine("All to a vendor", money(e.vendorTotal))
      tt:AddDoubleLine("All on the AH (net)", money(e.ahTotal))
    end
  elseif k == "stock" then
    tt:AddLine(e.name)
    tt:AddDoubleLine("Holding", e.count)
    tt:AddDoubleLine("Vendor, each", money(e.vendorEach))
    tt:AddDoubleLine("AH, each (net)", e.ahEach and money(e.ahEach) or "no price")
    tt:AddDoubleLine("Made in step", table.concat(e.steps, ", "))
  elseif k == "learn" then
    tt:AddLine(e.name)
    tt:AddLine(("%s: %s, requires %d skill."):format(HOW[e.how] or e.how, money(e.fee), e.rank), 1, 1, 1, true)
    if e.how == "trainer" then
      tt:AddLine("Forever trainer data (EG Link); not every trainer is listed.", NOTE[1], NOTE[2], NOTE[3], true)
    elseif e.item then
      tt:AddLine(("Recipe item: %s"):format(ns.ItemName(e.item)), NOTE[1], NOTE[2], NOTE[3], true)
    end
  elseif k == "shop" then
    tt:AddLine(e.name)
    tt:AddDoubleLine("Source", e.src or "no price")
    tt:AddDoubleLine("Route needs", e.count)
    tt:AddDoubleLine("You hold", e.have)
    if e.sup then
      tt:AddDoubleLine("Listed on the AH", e.sup)
      if e.short > 0 then tt:AddLine(("Short by %d: the AH does not have enough. Only what exists is priced here."):format(e.short), 1, 0.4, 0.4, true) end
    end
    if e.unit and e.buy > 1 and e.cost then
      tt:AddDoubleLine("Average each", money(math.floor(e.cost / math.max(1, math.min(e.buy, e.sup or e.buy)))))
    end
  elseif k == "history" then
    tt:AddLine(e.name)
    tt:AddDoubleLine("Skill", ("%d to %d"):format(e.from, e.to))
    if e.crafts > 0 then tt:AddDoubleLine("Crafts", e.crafts) end
    if e.cost > 0 then tt:AddDoubleLine("Cost (today's prices)", money(e.cost)) end
  elseif k == "gap" then
    tt:AddLine(("%d-%d: no priced recipe"):format(e.from, e.to))
    tt:AddLine("No recipe you can use here has a price for all its reagents. Look them up at the auction house.", 1, 1, 1, true)
  else
    return false
  end
end
