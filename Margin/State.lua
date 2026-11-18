local _, ns = ...

-- What every layout shares: which profession and tab are showing, the sort, the planned route (cached),
-- opening a recipe in the game's profession window, and item names. Layouts (UI.lua for the classic
-- window, Ledger.lua, later Workbench and Tracker) read and change this; none keeps its own copy.

local S = {
  prof = nil,        -- profession name the window shows
  tab = "profit",    -- "profit" | "level" | "route"
  sortCol = nil,     -- 1 name, 2 cost, 3 sale, 4 profit / per skill-up; nil: the default order
  sortAsc = false,
  showHistory = false,
  showStock = false,
}
ns.S = S

-- An item's name for display: ns.ItemName (Prices.lua: asks the game at most once a minute), or "item N"
-- while it is loading.
function ns.ItemLabel(id)
  return ns.ItemName(id) or ("item " .. id)
end

function ns.ItemIcon(id)
  return C_Item.GetItemIconByID(id)
end

-- The scanned professions, sorted by name.
function ns.Professions()
  local names = {}
  for n in pairs(ns.Char().profs) do names[#names + 1] = n end
  table.sort(names)
  return names
end

-- The profession the window shows: the chosen one while it is still scanned, else any scanned one.
function ns.ProfName()
  local profs = ns.Char().profs
  if not S.prof then S.prof = ns.Char().lastProf end -- first look this session: the one you had last
  if not S.prof or not profs[S.prof] then S.prof = next(profs) end
  return S.prof, S.prof and profs[S.prof]
end

function ns.SetProfession(name)
  if name and ns.Char().profs[name] then S.prof = name; ns.Char().lastProf = name end
end

-- Next profession in name order (wraps).
function ns.CycleProfession()
  local names = ns.Professions()
  if #names == 0 then return end
  local idx = 1
  for i, n in ipairs(names) do if n == S.prof then idx = i % #names + 1 end end
  S.prof = names[idx]
  ns.Char().lastProf = S.prof
end

-- Which step the shopping lists show: nil is the whole route, else the index of one of the plan's steps. The
-- point: when you cannot buy everything up front, buy what one step needs, craft, sell, then buy the next.
function ns.ShopSteps(plan)
  local steps = {}
  for i, seg in ipairs(plan.segs) do
    if not seg.gap and seg.shop then steps[#steps + 1] = { index = i, seg = seg } end
  end
  return steps
end

-- The shopping list to use for a plan: the whole route's, or the chosen step's (falls back to the whole
-- route when that step no longer exists). Second result: the step (from, to, name) or nil.
function ns.ShopOf(plan)
  if S.shopOnCraft and S.shopCraft then return S.shopCraft.shop, nil, S.shopCraft end -- the craft plan's list
  if not plan then return {}, nil end
  local want = S.shopStep
  local seg = want and plan.segs[want]
  if seg and not seg.gap and seg.shop then return seg.shop, seg end
  return plan.shop, nil
end

-- Make the shopping lists show a craft plan's materials (qty of recipe), until another choice is made.
function ns.ShopForCraft(recipe, qty, quote)
  local shop = {}
  for _, it in ipairs(quote.shop) do
    shop[#shop + 1] = { item = it.item, count = it.need, unit = it.unit, src = it.src }
  end
  S.shopCraft = { name = recipe.name, qty = qty, shop = shop } -- remembered, so it stays a choice beside the route
  S.shopOnCraft = true
  S.shopStep = nil
end

function ns.SetShopStep(index)
  S.shopOnCraft = false
  S.shopStep = index
  ns.Print(index and "shopping lists now show one step" or "shopping lists now show the whole route")
end

-- Next choice: whole route, each step in turn, the craft plan (once you have made one), back to the whole route.
function ns.CycleShopStep(plan)
  local steps = ns.ShopSteps(plan)
  if S.shopOnCraft then S.shopOnCraft = false; S.shopStep = nil; return end
  local nextIndex
  if not S.shopStep then nextIndex = steps[1] and steps[1].index
  else
    for k, st in ipairs(steps) do
      if st.index == S.shopStep then nextIndex = steps[k + 1] and steps[k + 1].index end
    end
  end
  S.shopStep = nextIndex
  if not nextIndex and S.shopCraft then S.shopOnCraft = true end
end

function ns.ShopStepLabel(plan)
  if S.shopOnCraft and S.shopCraft then return ("craft plan: %d x %s"):format(S.shopCraft.qty, S.shopCraft.name) end
  local _, seg = ns.ShopOf(plan)
  if not seg then return "whole route" end
  return ("step %d-%d: %s"):format(seg.from, seg.to, seg.row.r.name)
end

-- Ignore (or take back) a craft everywhere: the routes that used it are planned again.
function ns.SetCraftIgnored(id, name, prof, on)
  if on then ns.IgnoreCraft(id, name, prof) else ns.UnignoreCraft(id) end
  for pname in pairs(ns.Char().profs) do ns.ClearLock(pname) end
  ns.Print(on and ("ignoring " .. (name or id) .. " (Settings > Ignored crafts to bring it back)") or ("no longer ignoring " .. (name or id)))
  if ns.RefreshUI then ns.RefreshUI() end
end

function ns.SetTab(tab)
  S.tab = tab
end

-- Column sort: click to sort, click again to reverse, right-click for the default order. The Route
-- tab is not sortable. Name and cost start ascending, as does per skill-up on Leveling.
function ns.SortBy(col, btn)
  if S.tab == "route" then return end
  if btn == "RightButton" then
    S.sortCol = nil
  elseif S.sortCol == col then
    S.sortAsc = not S.sortAsc
  else
    S.sortCol = col
    S.sortAsc = col == 1 or col == 2 or (col == 4 and S.tab == "level")
  end
  if ns.UIScrollTop then ns.UIScrollTop() end
  if ns.RefreshUI then ns.RefreshUI() end
end

---------------------------------------------------------------------------
-- The route
---------------------------------------------------------------------------

-- The route for the profession the window shows: plan, prof, name, target (nil when nothing is scanned).
-- Planning is heavy, so results are kept per setting until prices or scans change (ns.InvalidatePlan);
-- bag updates and scrolling reuse them.
local planCache = {}
function ns.InvalidatePlan() wipe(planCache) end

-- Forget the locked route for a profession; the next plan is a fresh one.
function ns.ClearLock(name)
  local locks = ns.Char().locks
  if locks and name then locks[name] = nil end
  ns.InvalidatePlan()
end

function ns.CurrentPlan()
  local profs = ns.Char().profs
  local name, prof = S.prof, S.prof and profs[S.prof]
  if not prof then name, prof = next(profs) end
  if not prof then return nil end
  local target = ns.Opt("routeTarget") or prof.max
  target = math.min(math.max(target, prof.skill + 1), prof.max)

  -- A locked route keeps the recipe it chose for each skill point, so price changes do not
  -- reshuffle a route you have started. Changing a setting that changes the route re-locks it.
  local char = ns.Char()
  char.locks = char.locks or {}
  local useLock = ns.Opt("routeLock") and not ns.Opt("noLock")
  local lockKey = table.concat({ tostring(ns.Opt("resale")), tostring(ns.Opt("useTrainer")),
    ns.Opt("useRep") and "rep" or "base", tostring(ns.Opt("odds")), target }, "|")
  local lock = useLock and char.locks[name] or nil
  if lock and lock.key ~= lockKey then lock = nil; char.locks[name] = nil end

  local key = table.concat({ name, prof.skill, prof.scanSkill or 0, prof.time or 0, lockKey,
    lock and lock.t or "free", ns.Opt("noLock") and "n" or "l" }, "|")
  local hit = planCache[key]
  if not hit then
    local t0 = debugprofilestop()
    hit = ns.Plan(prof, target, nil, ns.Opt("useTrainer"), lock and ns.ForceFromPicks(lock.picks) or nil)
    ns.PerfNote("plan", debugprofilestop() - t0)
    planCache[key] = hit
    if useLock and not lock then
      char.locks[name] = { key = lockKey, t = time(), picks = ns.PlanPicks(hit) }
    end
  end
  return hit, prof, name, target
end

-- The route priced under another resale / unlearned-recipes setting (for the comparison cards).
function ns.PlanWith(resale, useTrainer)
  return ns.With({ resale = resale, useTrainer = useTrainer, noLock = true }, function() return (ns.CurrentPlan()) end)
end

---------------------------------------------------------------------------
-- Open a recipe in the game's own profession window with the number to craft filled in.
-- Opens that profession first when it is not the one showing. Crafting itself stays your click.
--
-- Two things make this flaky if done once and blindly: a window that has just opened loads its
-- list afterwards and resets to the first recipe, and the quantity box resets whenever the
-- recipe changes. So: select until the window reports the right recipe, then fill the number,
-- and fill it again a moment later. The box also refuses more than your materials allow, so
-- when it settles on less than the route wants, say so.
---------------------------------------------------------------------------

local function debugPrint(...)
  if MarginDB and MarginDB.debug then ns.Print("[open]", ...) end
end

local function quantityBox()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  return page and page.CreateMultipleInputBox
end

-- The recipe the profession window is showing now, or nil when it cannot be told.
local function selectedRecipe()
  local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
  local form = page and page.SchematicForm
  local ok, info = pcall(function() return form and form.GetRecipeInfo and form:GetRecipeInfo() end)
  return ok and info and info.recipeID or nil
end

local function fillCount(count, announce)
  local box = quantityBox()
  if not (box and box.SetValue and count) then return false end
  pcall(box.SetValue, box, count)
  local got = box.GetValue and box:GetValue()
  debugPrint("quantity set to", count, "box shows", tostring(got))
  if announce and type(got) == "number" and got < count then
    ns.Print(("The window set %d: it only lets you queue what your materials allow (the route wants %d)."):format(got, count))
  end
  return true
end

function ns.OpenRecipe(id, count, professionName)
  local TS = C_TradeSkillUI
  if not (TS and TS.OpenRecipe) then ns.Print("This client has no profession window API."); return end

  -- OpenRecipe and OpenTradeSkill are protected: the game only lets an addon call them while it is handling
  -- your click, never from a timer (calling them later is blocked and logged as ADDON_ACTION_BLOCKED, which
  -- is why selecting a recipe used to work only sometimes). So both are called right here, in the click. The
  -- timer below only watches, and fills in the number once the window shows the recipe.
  local function showing()
    local base = TS.GetBaseProfessionInfo and TS.GetBaseProfessionInfo()
    return TS.IsTradeSkillReady and TS.IsTradeSkillReady() and base and base.professionName == professionName
  end
  local prof = professionName and ns.Char().profs[professionName]
  if not showing() and prof and prof.id and TS.OpenTradeSkill then pcall(TS.OpenTradeSkill, prof.id) end
  pcall(TS.OpenRecipe, id)

  local started, ticker = GetTime(), nil
  ticker = C_Timer.NewTicker(0.25, function()
    local sel = selectedRecipe()
    local elapsed = GetTime() - started
    if TS.IsDataSourceChanging and TS.IsDataSourceChanging() and elapsed < 5 then return end -- still loading
    if sel == id or (sel == nil and elapsed > 1.2) then
      ticker:Cancel()
      if not fillCount(count, false) and count then
        ns.Print(("Craft %d of it (the window has no quantity box here)."):format(count))
      end
      C_Timer.After(0.5, function() fillCount(count, true) end)
      debugPrint("recipe", id, "selected:", tostring(sel), "after", ("%.1fs"):format(elapsed))
    elseif elapsed > 3 then
      ticker:Cancel()
      -- the window opened but on another recipe: selecting needs a click, so ask for one
      ns.Print(("The window is on a different recipe. Click the recipe in Margin once more to select it."))
      debugPrint("gave up; the window shows", tostring(sel))
    end
  end)
end

-- What a click on a row with a craft does: open it, or say it has to be learned first.
function ns.CraftClick(c)
  if not c then return end
  if c.learnFirst then
    ns.Print(("Learn %s first: see \"Recipes to learn\" below."):format(c.name))
  else
    ns.OpenRecipe(c.id, c.count, c.profession)
  end
end
