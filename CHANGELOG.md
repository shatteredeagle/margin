# Changelog

## Unreleased

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
