local _, ns = ...

-- How much of an item is actually for sale. Auctionator keeps only the lowest price, but a route can
-- need more of something than the whole market holds (120 bear meat when 40 are listed), and buying
-- deeper into the listings costs more per unit. Whenever an AH search shows an item's listings, the
-- cheapest ones are kept here: MarginDB.depth[item] = { t = when, p = { price, qty, price, qty, ... } }
-- (copper per unit, cheapest first). `capped` means more listings existed than were kept.

local AGE = 3 * 86400 -- stale after three days

function ns.NoteDepth(itemID, flat, capped)
  if not MarginDB then return end
  MarginDB.depth = MarginDB.depth or {}
  MarginDB.depth[itemID] = { t = time(), p = flat, capped = capped or nil }
  if ns.InvalidatePlan then ns.InvalidatePlan() end
end

function ns.Depth(itemID)
  local d = MarginDB and MarginDB.depth and MarginDB.depth[itemID]
  if d and time() - d.t < AGE then return d end
end

-- Units listed. nil when unknown: never looked at, too old, or the listings were cut off.
function ns.Supply(itemID)
  local d = ns.Depth(itemID)
  if not d or d.capped then return nil end
  local total = 0
  for i = 2, #d.p, 2 do total = total + d.p[i] end
  return total
end

-- Buying n units, cheapest listing first: the cost and how many units that got. nil when there is no data.
function ns.WalkCost(itemID, n)
  local d = ns.Depth(itemID)
  if not d then return nil end
  local left, cost, got = n, 0, 0
  for i = 1, #d.p, 2 do
    if left <= 0 then break end
    local take = math.min(left, d.p[i + 1])
    cost, got, left = cost + take * d.p[i], got + take, left - take
  end
  return cost, got
end
