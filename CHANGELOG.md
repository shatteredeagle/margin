# Changelog

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
