local _, ns = ...

-- Skill-up chance by relative difficulty (orange, yellow, green, grey).
local CHANCE = { [0] = 1.0, [1] = 0.75, [2] = 0.25, [3] = 0 }
ns.CHANCE = CHANCE

-- Output item -> recipe, over every scanned profession of this character, so a
-- reagent you can craft yourself is priced at its craft cost when that is cheaper.
local function craftIndex(profs)
  local idx = {}
  for _, prof in pairs(profs) do
    for _, r in ipairs(prof.recipes) do
      if r.out and not idx[r.out] then idx[r.out] = r end
    end
  end
  return idx
end

-- Unit price of an item: cheapest of vendor, AH, or crafting it. Returns
-- copper, source ("vendor" | "ah" | "craft") or nil.
local function unitPrice(item, idx, visiting)
  local buy, src = ns.BuyPrice(item)
  local r = idx[item]
  if r and not visiting[item] then
    visiting[item] = true
    local total, ok = 0, true
    for _, rg in ipairs(r.reagents) do
      local u = unitPrice(rg.item, idx, visiting)
      if u then total = total + u * rg.count else ok = false break end
    end
    visiting[item] = nil
    if ok then
      local craft = total / r.qty
      if not buy or craft < buy then return craft, "craft" end
    end
  end
  return buy, src
end

-- Cost of one craft. Returns total copper, list of reagent lines, missing count.
function ns.RecipeCost(r, idx)
  idx = idx or {}
  local total, lines, missing = 0, {}, 0
  for _, rg in ipairs(r.reagents) do
    local unit, src = unitPrice(rg.item, idx, { [r.out or 0] = true })
    lines[#lines + 1] = { item = rg.item, count = rg.count, unit = unit, src = src }
    if unit then total = total + unit * rg.count else missing = missing + 1 end
  end
  return math.floor(total), lines, missing
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
function ns.Evaluate(prof, profs)
  local rows = {}
  local idx = craftIndex(profs or (ns.Char and ns.Char().profs) or { prof })
  for _, r in ipairs(prof.recipes) do
    local cost, lines, missing = ns.RecipeCost(r, idx)
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

-- Priced recipes best profit first, then unpriced ones. showAll keeps the
-- unprofitable priced recipes too (they sort between the two groups).
function ns.ProfitRows(rows, key, showAll)
  local out, unpriced = {}, {}
  local field = key == "ah" and "ahProfit" or "vendorProfit"
  for _, row in ipairs(rows) do
    if row.missing > 0 or row[field] == nil then
      unpriced[#unpriced + 1] = row
    elseif showAll or row[field] > 0 then
      out[#out + 1] = row
    end
  end
  table.sort(out, function(a, b) return a[field] > b[field] end)
  for _, row in ipairs(unpriced) do out[#out + 1] = row end
  return out, field
end

-- Cheapest skill-ups first, then (showAll) grey recipes by cost, then unpriced.
function ns.LevelingRows(rows, showAll)
  local ups, grey, unpriced = {}, {}, {}
  for _, row in ipairs(rows) do
    if row.missing > 0 then
      if showAll or row.chance > 0 then unpriced[#unpriced + 1] = row end
    elseif row.chance > 0 then
      ups[#ups + 1] = row
    elseif showAll then
      grey[#grey + 1] = row
    end
  end
  table.sort(ups, function(a, b) return a.perUp < b.perUp end)
  table.sort(grey, function(a, b) return a.cost < b.cost end)
  for _, row in ipairs(grey) do ups[#ups + 1] = row end
  for _, row in ipairs(unpriced) do ups[#ups + 1] = row end
  return ups
end
