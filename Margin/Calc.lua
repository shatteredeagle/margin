local _, ns = ...

-- Skill-up chance by relative difficulty (orange, yellow, green, grey).
local CHANCE = { [0] = 1.0, [1] = 0.75, [2] = 0.25, [3] = 0 }
ns.CHANCE = CHANCE

-- Cost of one craft. Returns total copper, list of reagent lines, missing count.
function ns.RecipeCost(r)
  local total, lines, missing = 0, {}, 0
  for _, rg in ipairs(r.reagents) do
    local unit, src = ns.BuyPrice(rg.item)
    lines[#lines + 1] = { item = rg.item, count = rg.count, unit = unit, src = src }
    if unit then total = total + unit * rg.count else missing = missing + 1 end
  end
  return total, lines, missing
end

-- Net proceeds of selling the result: vendor sell price, and AH price after the cut.
function ns.Revenue(r)
  if not r.out then return nil, nil end
  local vend = ns.VendorSell(r.out)
  local ah = ns.AHPrice(r.out)
  if vend then vend = vend * r.qty end
  if ah then ah = math.floor(ah * r.qty * (1 - ns.Opt("ahCut"))) end
  return vend, ah
end

-- One row per craftable recipe with cost, both profit figures and cost per skill-up.
function ns.Evaluate(prof)
  local rows = {}
  for _, r in ipairs(prof.recipes) do
    local cost, lines, missing = ns.RecipeCost(r)
    local vend, ah = ns.Revenue(r)
    local chance = (CHANCE[r.diff] or 0) * r.ups
    rows[#rows + 1] = {
      r = r, cost = cost, lines = lines, missing = missing,
      vendorProfit = vend and (vend - cost) or nil,
      ahProfit = ah and (ah - cost) or nil,
      chance = chance,
      perUp = chance > 0 and cost / chance or nil,
    }
  end
  return rows
end

-- Fully priced profitable recipes first (best profit first), then every
-- recipe that lacks a price, so an empty price database is visible, not blank.
function ns.ProfitRows(rows, key)
  local out, unpriced = {}, {}
  local field = key == "ah" and "ahProfit" or "vendorProfit"
  for _, row in ipairs(rows) do
    if row.missing > 0 or row[field] == nil then
      unpriced[#unpriced + 1] = row
    elseif row[field] > 0 then
      out[#out + 1] = row
    end
  end
  table.sort(out, function(a, b) return a[field] > b[field] end)
  for _, row in ipairs(unpriced) do out[#out + 1] = row end
  return out, field
end

-- Cheapest skill-ups first; unpriced recipes that can still skill up follow.
function ns.LevelingRows(rows)
  local out, unpriced = {}, {}
  for _, row in ipairs(rows) do
    if row.chance > 0 then
      if row.missing == 0 then out[#out + 1] = row else unpriced[#unpriced + 1] = row end
    end
  end
  table.sort(out, function(a, b) return a.perUp < b.perUp end)
  for _, row in ipairs(unpriced) do out[#out + 1] = row end
  return out
end
