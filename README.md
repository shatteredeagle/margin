# Margin

WoW Forever addon: shows profitable crafts and the cheapest recipes to level a profession, priced from Auctionator (no scanner of its own).

- `/margin` opens the window. Open each profession once so it gets scanned.
- Profit tab: reagents bought at the cheaper of vendor / AH price, results sold to a vendor or on the AH (after the cut, `/margin cut 5`).
- Leveling tab: cost per expected skill-up (orange 100%, yellow 75%, green 25%).
- Vendor reagent prices: Auctionator's merchant cache wins; a bundled table (threads, salt, vials, dyes, spices, flux...) fills in the rest. Regenerate it with `tools/gen_vendor.py` (see its docstring).

MIT licensed.

Trainer recipes: the Route tab can include recipes you still have to learn, using Forever trainer data
from Efficient Games' EG Link output (CC BY 4.0, see THIRD_PARTY.md). Coverage is partial: only trainers
players have opened are listed. Toggle it with the "Trainer recipes" button on the Route tab.
