local _, ns = ...

-- /margin dump: writes the route, what it costs, the shopping list and the settings behind them as
-- plain text into MarginDB.dump (read it from the SavedVariables file after /reload). The route and
-- its prices only exist while the game runs, so this is the way to hand them to someone else.

local function plain(c)
  if c == nil then return "?" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local s = ("%dg %ds %dc"):format(math.floor(c / 10000), math.floor(c / 100) % 100, c % 100)
  return neg and ("-" .. s) or s
end

local function itemName(id)
  return C_Item.GetItemNameByID(id) or ("item " .. id)
end

local function describe(plan, out, title)
  out[#out + 1] = ("== %s =="):format(title)
  out[#out + 1] = ("target %d, ~%.0f crafts, net %s (reagents %s), trainer/pattern fees %s, shopping %s"):format(
    plan.target, plan.crafts, plain(plan.cost), plain(plan.gross), plain(plan.learnCost), plain(plan.shopCost))
  for _, seg in ipairs(plan.segs) do
    if seg.gap then
      out[#out + 1] = ("  %d-%d  NO PRICED RECIPE"):format(seg.from, seg.to)
    else
      local r, row = seg.row.r, seg.row
      local how = row.learn and (" [learn: %s, skill %d, fee %s]"):format(row.learn.how, row.learn.rank, plain(row.learn.fee)) or ""
      out[#out + 1] = ("  %d-%d  %s%s  ~%d crafts, step net %s, per craft: cost %s resale %s net %s, diff %s, chance %.2f"):format(
        seg.from, seg.to, r.name, how, math.ceil(seg.crafts), plain(seg.cost), plain(row.cost), plain(row.resale),
        plain(row.net), tostring(r.diff), row.chance or 0)
      for _, p in ipairs(seg.prep or {}) do
        out[#out + 1] = ("      make %s x%d (%s each)"):format(p.recipe.name, p.crafts, plain(p.unit))
      end
      for _, l in ipairs(row.lines) do
        out[#out + 1] = ("      %dx %s @ %s (%s)"):format(l.count, itemName(l.item), plain(l.unit), l.src or "NO PRICE")
      end
    end
  end
  out[#out + 1] = "  shopping list:"
  for _, it in ipairs(plan.shop) do
    out[#out + 1] = ("    %dx %s @ %s (%s)%s"):format(it.count, itemName(it.item), plain(it.unit), it.src or "no price",
      it.recipe and " [recipe item]" or "")
  end
end

function ns.Dump()
  local out = {}
  out[#out + 1] = ("Margin dump %s, interface %s"):format(date("%Y-%m-%d %H:%M:%S"), select(4, GetBuildInfo()) or "?")
  local o = {}
  for _, k in ipairs({ "resale", "odds", "useRep", "useTrainer", "routeLock", "routeTarget", "ahCut", "ahChance", "showAll" }) do
    o[#o + 1] = ("%s=%s"):format(k, tostring(ns.Opt(k)))
  end
  out[#out + 1] = "settings: " .. table.concat(o, ", ")
  for name, prof in pairs(ns.Char().profs) do
    out[#out + 1] = ("%s: skill %s (scanned at %s) of %s, %d learned, %d unlearned considered, scanned %s%s"):format(
      name, tostring(prof.skill), tostring(prof.scanSkill), tostring(prof.max), #prof.recipes, #(prof.unlearned or {}),
      date("%H:%M:%S", prof.time or 0), prof.dirty and ", NEEDS REFRESH" or "")
  end
  local nb, tight = 0, 0
  for _, b in pairs(MarginDB.bands or {}) do
    nb = nb + 1
    if (b.y1 and b.y2 and b.y1 >= b.y2 - 3) or (b.g1 and b.g2 and b.g1 >= b.g2 - 3) then tight = nb end
  end
  out[#out + 1] = ("colour edges observed for %d recipes"):format(nb)
  local plan, prof, name = ns.CurrentPlan()
  if plan then
    local lock = ns.Char().locks and ns.Char().locks[name]
    describe(plan, out, ("%s route as shown%s"):format(name, lock and ns.Opt("routeLock") and " (locked)" or ""))
    -- what a fresh plan would pick right now, to see what the lock is holding back
    local fresh = ns.With({ noLock = true }, function() return (ns.CurrentPlan()) end)
    describe(fresh, out, ("%s route if re-planned now"):format(name))
  else
    out[#out + 1] = "no scanned profession yet"
  end
  for pn, h in pairs(ns.Char().history or {}) do
    out[#out + 1] = ("history %s: %d entries"):format(pn, #h)
    for _, e in ipairs(h) do
      out[#out + 1] = ("  %d-%d %s x%d, %s"):format(e.from, e.to, e.name, e.crafts or 0, plain(e.cost))
    end
  end
  out[#out + 1] = "scan log (newest last):"
  for _, l in ipairs(MarginDB.scanLog or {}) do out[#out + 1] = "  " .. l end
  MarginDB.dump = out
  ns.Print(("dump written (%d lines). /reload to save it to disk."):format(#out))
end
