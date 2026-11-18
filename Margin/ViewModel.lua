local _, ns = ...

-- View model: pure functions that turn the planner's data (Calc.lua) into what a layout draws: list
-- entries, comparison cards, the status line and the warnings. No frames, no colours: an entry carries
-- raw values (copper, counts, difficulty) and its kind; the layout's cells format them. Testable with
-- plain Lua (tests/calc_test.lua).
--
-- Entry kinds and their fields:
--   recipe  icon name diff unlearned learn{rank,togo,how,fee}|learnNote missing cost sale value valueNote
--           sortName sortCost sortSale sortVal data craft quote
--   step    from to icon name diff learn(bool) crafts unit net data craft
--   gap     from to
--   prep    mode("make"|"have") icon name have crafts unit total needed forName craft
--   section key title hint total signed count collapsible open
--   history from to icon name crafts t cost
--   stock   icon name item count vendor ah best steps
--   learn   rank icon name how fee item
--   shop    item icon name have buy count unit cost sup short src recipe

local VM = {}
ns.VM = VM

local function name(id) return ns.ItemName and ns.ItemName(id) or ("item " .. id) end
local function icon(id) return ns.ItemIcon and ns.ItemIcon(id) or nil end

-- One recipe row of the Profit or Leveling tab. tab: "profit" | "level"; key: "vendor" | "ah" (what
-- the Profit tab sells at); mySkill: the profession's skill now.
function VM.RecipeEntry(d, tab, key, mySkill, profName)
  local r = d.r
  local vend, ah = ns.Revenue(r)
  local unlearned = (r.train or r.teach or r.extra) and true or false
  local e = {
    kind = "recipe", icon = r.icon, name = r.name, diff = r.diff, unlearned = unlearned, data = d,
    missing = d.missing, sortName = r.name:lower(),
    craft = { id = r.id, profession = profName, name = r.name, learnFirst = (d.learn ~= nil) or unlearned },
    quote = tab == "profit" and r or nil, -- Profit rows open the craft planner
  }
  if unlearned then
    local L = d.learn
    if L then
      e.learn = { rank = L.rank, togo = math.max(0, L.rank - (mySkill or 0)), how = L.how, fee = L.fee }
    elseif r.teach then
      e.learnNote = "pattern not priced"
    else
      e.learnNote = "source unknown"
    end
  end
  if tab == "profit" then
    e.sale = key == "ah" and ah or vend
  elseif (ns.Opt("resale") or "off") ~= "off" then
    e.sale = d.resale
  end
  e.sortSale = e.sale
  if d.missing > 0 then return e end
  e.cost, e.sortCost = d.cost, d.cost
  if tab == "profit" then
    if not r.out then
      e.valueNote = "makes no item" -- enchants and the like have nothing to sell
    else
      e.value = key == "ah" and d.ahProfit or d.vendorProfit
      e.sortVal = e.value
    end
  elseif d.perUp then
    e.value, e.sortVal = -d.perUp, d.perUp
  else
    e.valueNote = "no skill-up"
  end
  return e
end

-- Search: recipe name or any reagent name.
function VM.Matches(d, q)
  if q == "" or d.r.name:lower():find(q, 1, true) then return true end
  for _, l in ipairs(d.lines) do
    local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(l.item)
    if n and n:lower():find(q, 1, true) then return true end
  end
  return false
end

local SORT_KEYS = { "sortName", "sortCost", "sortSale", "sortVal" }

-- Sorts by a column (1-4); entries with no value for it always go last; ties keep the planner's order.
function VM.Sort(list, col, asc)
  local k = SORT_KEYS[col]
  if not k then return list end
  for i, e in ipairs(list) do e.i = i end
  table.sort(list, function(a, b)
    local x, y = a[k], b[k]
    if x == nil or y == nil then
      if x == y then return a.i < b.i end
      return x ~= nil
    end
    if x == y then return a.i < b.i end
    if asc then return x < y end
    return x > y
  end)
  return list
end

-- The Profit or Leveling list for a profession, plus the counts for the status line.
-- o: key, showAll, allScope, query, sortCol, sortAsc, profName
function VM.RecipeList(prof, tab, o)
  local rows = ns.Evaluate(prof, nil, false, o.allScope)
  local src
  if tab == "profit" then src = ns.ProfitRows(rows, o.key, o.showAll) else src = ns.LevelingRows(rows, o.showAll) end
  local q = (o.query or ""):lower()
  local list = {}
  for _, d in ipairs(src) do
    if VM.Matches(d, q) then list[#list + 1] = VM.RecipeEntry(d, tab, o.key, prof.skill, o.profName) end
  end
  if o.sortCol then VM.Sort(list, o.sortCol, o.sortAsc) end
  local priced, unpriced = 0, 0
  for _, d in ipairs(rows) do
    if d.missing == 0 then priced = priced + 1 else unpriced = unpriced + 1 end
  end
  return list, { recipes = #rows, priced = priced, unpriced = unpriced, shown = #list }
end

---------------------------------------------------------------------------
-- Route
---------------------------------------------------------------------------

local function historyEntries(list, h, open)
  if #h == 0 then return end
  local spent = 0
  for _, e in ipairs(h) do spent = spent + (e.cost or 0) end
  list[#list + 1] = { kind = "section", key = "history", title = "Completed steps", count = #h, total = spent,
    collapsible = true, open = open }
  if not open then return end
  for i = #h, 1, -1 do
    local e = h[i]
    list[#list + 1] = { kind = "history", from = e.from, to = e.to, icon = e.icon, name = e.name,
      crafts = e.crafts or 0, t = e.t, cost = e.cost or 0 }
  end
end

-- "Crafted stock": what the route has made and you are holding, worth what at a vendor and on the AH.
local function stockEntries(list, rows, open)
  if #rows == 0 then return end
  local items, v, a, best = 0, 0, 0, 0
  for _, r in ipairs(rows) do
    local vv, aa = r.count * r.vendor, r.ah and r.count * r.ah or 0
    items, v, a, best = items + r.count, v + vv, a + aa, best + math.max(vv, aa)
  end
  list[#list + 1] = { kind = "section", key = "stock", title = "Crafted stock", count = items, total = best,
    vendorTotal = v, ahTotal = a, collapsible = true, open = open, icon = rows[1].icon }
  if not open then return end
  for _, r in ipairs(rows) do
    local vv, aa = r.count * r.vendor, r.ah and r.count * r.ah or nil
    list[#list + 1] = { kind = "stock", icon = r.icon, name = r.name, item = r.item, count = r.count,
      vendor = vv, ah = aa, best = math.max(vv, aa or 0), vendorEach = r.vendor, ahEach = r.ah, steps = r.steps }
  end
end

-- The shopping list: what the route needs minus what you hold. AH items with known listings are
-- costed by walking them cheapest first, and a shortage is called out. Returns rows, total still to buy.
function VM.ShopRows(plan)
  local rows, left = {}, 0
  for _, it in ipairs(plan.shop) do
    local have = it.recipe and 0 or ns.Owned(it.item)
    local buy = math.max(0, it.count - have)
    local cost = it.unit and it.unit * buy or nil
    local sup = (it.src == "ah" and not it.recipe) and ns.Supply and ns.Supply(it.item) or nil
    local short = (sup and buy > sup) and (buy - sup) or 0
    if it.src == "ah" and not it.recipe and ns.WalkCost then
      local c = ns.WalkCost(it.item, buy)
      if c then cost = c end
    end
    if cost and not it.recipe then left = left + cost end
    rows[#rows + 1] = { kind = "shop", item = it.item, icon = icon(it.item), name = name(it.item), have = have,
      buy = buy, count = it.count, unit = it.unit, cost = cost, sup = sup, short = short, src = it.src, recipe = it.recipe }
  end
  return rows, left
end

-- Everything the Route list shows, top to bottom. o: profName, showHistory, showStock, history (list),
-- stock (ns.RouteStock rows).
function VM.RouteEntries(plan, o)
  local list = {}
  stockEntries(list, o.stock or {}, o.showStock)
  historyEntries(list, o.history or {}, o.showHistory)
  list[#list + 1] = { kind = "section", key = "steps", title = "Steps", hint = "to " .. plan.target .. ", net",
    total = -plan.cost, signed = true }
  for _, seg in ipairs(plan.segs) do
    if seg.gap then
      list[#list + 1] = { kind = "gap", from = seg.from, to = seg.to }
    else
      local r = seg.row.r
      local n = math.ceil(seg.crafts)
      -- intermediates this step uses that are cheaper to make than to buy, made first
      for _, p in ipairs(seg.prep or {}) do
        if p.crafts > 0 then
          list[#list + 1] = { kind = "prep", mode = "make", icon = p.recipe.icon, name = p.recipe.name, have = p.have,
            crafts = p.crafts, units = p.units, unit = p.unit, total = p.unit and p.unit * p.units or nil,
            needed = p.units + p.have, forName = r.name,
            craft = { id = p.recipe.id, count = p.crafts, profession = p.recipe.prof or o.profName, name = p.recipe.name } }
        elseif p.have > 0 then -- everything needed is already in your bags
          list[#list + 1] = { kind = "prep", mode = "have", icon = p.recipe.icon, name = p.recipe.name, have = p.have,
            needed = p.have, forName = r.name }
        end
      end
      list[#list + 1] = { kind = "step", from = seg.from, to = seg.to, icon = r.icon, name = r.name, diff = r.diff,
        learn = seg.row.learn ~= nil, crafts = n, unit = seg.row.cost, net = -seg.cost, data = seg.row,
        craft = { id = r.id, count = n, profession = o.profName, name = r.name, learnFirst = seg.row.learn ~= nil } }
    end
  end
  if #plan.learn > 0 then
    list[#list + 1] = { kind = "section", key = "learn", title = "Recipes to learn", total = plan.learnCost }
    for _, l in ipairs(plan.learn) do
      local r = l.row.r
      list[#list + 1] = { kind = "learn", rank = l.rank, icon = r.icon, name = r.name, how = l.how, fee = l.fee, item = l.item }
    end
  end
  local shop, left = VM.ShopRows(plan)
  list[#list + 1] = { kind = "section", key = "shop", title = "Shopping list", hint = "still to buy", total = left }
  for _, s in ipairs(shop) do list[#list + 1] = s end
  return list
end

-- The four comparison cards: the route priced with each resale option, then with the other
-- unlearned-recipes setting. planFor(resale, useTrainer) returns a plan; the chosen card uses the
-- real (locked) route, current(). delta: how much better (+) or worse (-) off than the selected card.
local CARD_LABEL = { vendor = "Resale: vendor", ah = "Resale: AH", off = "No resale" }
local CARD_TIP = { vendor = "Crafted items sold to a vendor", ah = "Crafted items sold on the AH (after the cut)",
  off = "Crafted items not sold: reagent cost only" }
function VM.Cards(resale, trainer, planFor, current)
  local cards, sel = {}, nil
  for _, m in ipairs({ "vendor", "ah", "off" }) do
    local plan = (m == resale) and current() or planFor(m, trainer)
    local c = { key = m, label = CARD_LABEL[m], tip = CARD_TIP[m], plan = plan, total = plan.cost + plan.learnCost,
      crafts = math.ceil(plan.crafts), selected = (m == resale), resale = m, useTrainer = trainer }
    cards[#cards + 1] = c
    if c.selected then sel = c end
  end
  sel = sel or cards[1]
  local alt = planFor(resale, not trainer)
  cards[#cards + 1] = { key = "alt", label = trainer and "Learned only" or "With unlearned",
    tip = trainer and "Only recipes you already know" or "Recipes you still have to learn included",
    plan = alt, total = alt.cost + alt.learnCost, crafts = math.ceil(alt.crafts), selected = false,
    resale = resale, useTrainer = not trainer }
  for _, c in ipairs(cards) do
    c.diff = c.total - sel.total
    if c.selected then c.deltaKind = "selected"
    elseif c.diff == 0 then c.deltaKind = "same"
    elseif c.diff > 0 then c.deltaKind = "worse"   -- costs more: shown red "-"
    else c.deltaKind = "better" end                -- costs less: shown green "+"
  end
  return cards, sel
end

---------------------------------------------------------------------------
-- Status line and warnings (warnings go in the banner, which wraps, so nothing is cut off)
---------------------------------------------------------------------------

function VM.Status(tab, counts, target)
  if tab == "route" then return ("route to %d"):format(target or 0) end
  if tab == "level" then
    return ("%d recipes · %s odds"):format(counts.shown, ns.Opt("odds") == "typical" and "typical" or "worst-case")
  end
  return ("%d recipes · %d priced · %d shown"):format(counts.recipes, counts.priced, counts.shown)
end

-- Warnings for the banner, joined into one sentence list. plan: the selected route (Route tab).
function VM.Warnings(tab, prof, o)
  local w = {}
  if prof.dirty then w[#w + 1] = "New recipe learned: open the profession window to refresh." end
  if tab == "profit" and o.allScope and not prof.every then
    w[#w + 1] = "Open the profession window once to load all recipes."
  end
  if tab ~= "route" and o.counts and o.counts.unpriced > 0 then
    w[#w + 1] = ("%d recipe%s wait on unpriced reagents (shown as ?). At the auction house: Margin > Look up."):format(
      o.counts.unpriced, o.counts.unpriced > 1 and "s" or "")
  end
  if tab == "route" and o.plan then
    local names = {}
    for item in pairs(o.plan.constrained or {}) do names[#names + 1] = name(item) end
    table.sort(names)
    if #names > 0 then w[#w + 1] = "Limited by AH supply: " .. table.concat(names, ", ") .. "." end
    local gaps = 0
    for _, seg in ipairs(o.plan.segs) do if seg.gap then gaps = gaps + (seg.to - seg.from) end end
    if gaps > 0 then w[#w + 1] = ("%d skill point%s have no priced recipe."):format(gaps, gaps > 1 and "s" or "") end
  end
  if #w == 0 then return nil end
  return table.concat(w, "  ")
end
