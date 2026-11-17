# Margin

Tradeskill profit, cheapest leveling route and shopping lists for **WoW Forever**.

## Install

- **By hand:** download `Margin-<version>.zip` from the [Releases](../../releases) page and extract the `Margin` folder into your `Interface/AddOns` folder.
- **Addon manager:** point any manager that installs from GitHub releases at `https://github.com/shatteredeagle/margin`.

Updates are new releases. Type `/margin` in game, or use the Margin button on a profession window. Open each profession once so Margin can scan it.

## What it does

- **Profit tab:** every recipe you know, priced from the cheapest source for each reagent (vendor, auction house, or crafting it yourself), against what the result sells for.
- **Leveling tab:** cost per expected skill-up, net of what the crafts sell for.
- **Route tab:** the cheapest path from your skill to your target, with a shopping list and cards that compare the route under each pricing option. It can include recipes you have not learned yet (trainer recipes and patterns you can buy).
- **At the auction house:** a shopping list with one-click Search that fills in the quantity, an "unpriced" button that looks up only the items Margin needs, and purchases ticked off as the AH confirms them.
- **At a vendor:** buy everything the route still needs (never more than needed), and sell the route's crafted items.
- Click a Route row to open that recipe in the profession window with the craft count filled in.

## Settings

| Command | Does |
|---|---|
| `/margin` | open the window |
| `/margin route 140` | set the route's target skill |
| `/margin rep` | toggle "My reputation" (default off: base, worst-case prices) |
| `/margin cut 5` | AH cut in percent |
| `/margin chance 80` | how often an AH listing sells (the deposit is lost when it does not) |
| `/margin buy`, `/margin list` | toggle the vendor popup / the AH shopping list |
| `/margin coverage` | which professions have trainer data |
| `/margin debug` | print what Margin is doing |

## Dependencies

None required. [Auctionator](https://www.curseforge.com/wow/addons/auctionator) (prices, AH search) and Polestar (extra recipe-item data) are used when installed. Without Auctionator, Margin records the cheapest price it sees in its own searches and the prices of vendors you open.

## Data and credits

Bundled data and where it comes from is in [THIRD_PARTY.md](THIRD_PARTY.md); the generators are in `tools/`. Trainer and vendor data is from Efficient Games' EG Link output for WoW: Forever (CC BY 4.0).

## Development

`lua5.1 tests/calc_test.lua` runs the offline tests; CI also syntax-checks every file. Pushing a tag like `v0.2.0` builds the zip and publishes a release (tags containing `-beta` or `-rc` are marked pre-releases; everything else is a normal release, which is what addon managers follow). Release notes come from `CHANGELOG.md`.

MIT licensed.
