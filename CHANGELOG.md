# Changelog

## 0.1.6-alpha
- Fixed: items vendors sell in bundles (Mild Spices, water: 5 at a time) bought only part of what was asked, because the buy call takes a number of items, in multiples of the bundle, and Margin passed the number of bundles. They are now bought in whole bundles, and the first purchase of such an item is checked so that a client that counts bundles instead is detected after at most one bundle of extra.
- **Margin's own full AH scan.** A "Full scan" button (and `/margin fullscan`) reads the whole auction house once and records the price and how much is for sale of every item Margin watches (reagents, products, pattern items): no item-by-item lookups. The AH allows one every 15 minutes. Without Auctionator it runs by itself when you open the AH (`/margin autoscan on|off` to change that). When Auctionator is installed its prices are still used, unless Margin's own scan is newer.
- **The AH's supply is now part of the plan.** Margin records how much of an item is actually listed (and at what prices) whenever an AH search shows it. The planner spends each item's supply in skill order and switches to other recipes when it runs out (what you already hold counts), the route says which items limit it, and the shopping lists flag "only N on the AH" and cost the purchase by walking the listings cheapest first instead of assuming the lowest price for every unit. Supply data is kept for 3 days; items never looked at are assumed plentiful, so the AH button ("Margin: N to look up", was "unpriced") now also looks up the route's AH items whose listings it has not seen.
- Fixed: recipe items filed under a different skill line than their profession were ignored (First Aid's manuals use another line number), so those recipes never got a pattern source. The recipe's own profession is what counts now. Forever's own rank and the vendor price Polestar lists are used ahead of the Classic table, and manuals that need more skill than your current cap still show where they come from in the "Recipes: all" view.
- Every scan attempt, including the ones that give up and why, is logged (last 20 in the save file, and in `/margin dump`), so a profession that does not show up can be diagnosed.
- Items that do not exist in Forever (they come from the profession window's full recipe list and the bundled Classic tables) are no longer counted as "unpriced", and recipes whose product is not a Forever item are left out of the Profit tab's "all recipes" view.
- "Margin: N unpriced" now always says what it is doing. When there is nothing to look up it says why (items already searched in the last 12 hours with no listing, or the Scan filter), it reports waiting for item names, skips items the game cannot name instead of waiting for ever, and a run that went quiet no longer blocks the next click.

## 0.1.5-alpha
- "Margin: N unpriced" now keeps going: when a round of 60 finishes it pauses a moment and starts the next, until nothing unpriced is left (30 rounds at most, then click again). Click the button while it runs to stop it. It listens for Auctionator's "search ended" announcement, so without that it falls back to one round per click.
- AH: a "Scan:" button next to the other AH buttons limits "Margin: N unpriced" (the count and the search) to one profession, or all of them. Click it to cycle.
- "Margin: N unpriced" now also covers the Profit tab's "Recipes: all" view: the reagents and sale prices of the unlearned recipes (and the sale prices of your own, for the AH column), so every profit figure can be filled in. Long lists are searched 60 items per click.
- Vendor prices now include food and drink sold by vendors (bread, water, milk, juice), so cooking recipes that use them can be priced.

## 0.1.4-alpha

- **The route now anticipates colour changes properly.** Recipe colours sit at fixed distances below the grey level (green starts one gap below, yellow two gaps below), and the gap is about half of Classic's for the same recipe. That predicted the colour of all 41 Forever recipes checked against real data, so the planner knows roughly when each recipe will go from orange to yellow to green instead of guessing. Worst-case odds also assume the changes come two skill points sooner. What a recipe shows at your current skill, and what earlier scans saw, still override the model.
- Route: "make" steps now take what you already hold into account. An intermediate you have crafted (for example Cured Medium Hide) is subtracted from what is left to make, the raw materials shrink with it, and a step you have fully covered shows as "have". The route's shopping list also shows what you hold and only totals what is still to buy.
- The route refreshes when your bags change, so it follows you as you craft and buy.

## 0.1.3-alpha

- **Fixed: the vendor Sell buttons never sold.** The two-click confirm remembered the row, but the rows are rebuilt on every refresh, so the second click never matched the first. It now remembers the item.

- One sign convention for money you earn or lose: green + when you come out ahead, red - when you lose money. It applies to the Profit column, "Net / skill-up" on Leveling, the Route steps and comparison cards (the difference to the selected option now reads + when it is better for you), and the recipe tooltip. Plain costs (Cost columns, shopping list, fees) stay unsigned.

- Margin now learns when each recipe changes colour: every scan records the colour it saw, and where a recipe changed between scans the planner uses the narrowed range instead of the one-third guess. It tightens as you level and is shared by all your characters.

- The profession-window Margin button now shows at a default spot even if looking for a better one fails.

## 0.1.2-alpha

- **Fixed: the vendor popup never opened in 0.1.1-alpha** (two helper functions were lost while adding the Sell tab). The profession-window Margin button also failed while looking for a free spot; fixed.

- CI now fails when the addon uses a function name that is never defined (the check that would have caught the vendor popup bug below). New WoW API names go in `tests/allowed_globals.txt`.

- Profit tab: a "Recipes: known / all" button. "All" lists every recipe of the profession with what it would earn; unlearned ones are blue and say where you would learn them (trainer fee, pattern price) and how many skill points you still need, or that the source is unknown. The full list is read from the open profession window the first time you switch to it.

- Fixed: a recipe that sells for more than it costs could be picked over a reliable one just because its skill-up chance was low (profit divided by a small chance looked huge). Recipes are now ranked with profit only bringing the cost down to zero, and ties go to the more reliable recipe.
- `/margin dump` writes the route, per-craft costs, shopping list and settings to the save file for bug reports.

- A recipe you just learned shows up straight away (moved from "unlearned" to your recipes) and the profession is re-read a few times as the game updates; with no profession window open, Margin says a new recipe needs a refresh.

- "Margin: N unpriced": only counts patterns for recipes you could actually reach (within your skill cap, with priced reagents), and items already searched in the last 12 hours that still have no listing are no longer counted, so the number drops after a search. Right-click the button to count them again.

- Planning now uses worst-case skill-up odds by default: yellow recipes count as 25%, green as 5%, and colours are assumed to fade sooner, so the craft counts and shopping list do not come up short on bad luck. `/margin odds typical` switches back to the usual 75% / 25%.

- Route: your skill is followed as you level, even with the profession window closed.
- Route: completed steps are remembered (the recipe that raised your skill, the crafts, the cost and the date) under a "Completed steps" row.
- Route: locked. The recipes it chose stay put while prices change, until you press Re-plan (or change a setting that changes the route). `/margin lock` turns locking off.
- Clicking a recipe while the profession window is closed now lands on that recipe instead of the top of the list.

## 0.1.1-alpha

- Route: crafts that make an intermediate (for example Medium Leather for Heavy Leather) now appear as "make" steps right before the step that uses them, deepest first.
- Vendor Sell tab: the confirmation is now a second click on the button instead of the game's popup, and it reports what it sold (or why nothing sold).
- Releases are now normal releases, so addon managers see them.

## 0.1.0-alpha

First public build. Built for WoW Forever (Interface 16001); not yet tested by anyone but its author.

- Scans your professions and prices every recipe: cheapest of vendor, auction house or crafting the reagent yourself.
- Profit tab (vendor or AH sale, after the AH cut and the deposit lost on unsold listings), Leveling tab (net cost per skill-up) and Route tab (cheapest path to your target skill, with a shopping list and comparison cards for each pricing option).
- The route can include recipes you have not learned yet: trainer recipes (Forever trainer data) and patterns, plans and recipes you can buy on the AH or from a vendor.
- Shopping list beside the auction house with one-click Search that fills in the quantity; AH purchases are ticked off as soon as the AH confirms them.
- Vendor window helper: buy everything the route still needs in confirmed chunks (never more than needed), and sell the route's crafted items (asks first).
- "Margin: N unpriced" button on the auction house searches only the items Margin cannot price. Works through Auctionator or on its own.
- Margin button on the profession window; click a Route row to open that recipe with the craft count filled in.
- Reputation: base (worst-case) prices by default, optional "My reputation" mode.
- No required addons. Auctionator and Polestar are used when installed.
