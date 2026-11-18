# Margin UI redesign: three directions

Design phase only. Nothing here changes addon code. Open `mockups.html` beside this file: every direction there is live (tabs, sorting, cards, the two-click Sure?, the unpriced lookup, settings), rendered from one shared data model so the three layouts are provably showing the same features.

Sample data throughout: a Leatherworker at 160/225 with a locked route to 225, worst-case odds, resale at the vendor. Prices are plausible, not live.

## What the current UI gets wrong (and every direction fixes)

Read from `Margin/UI.lua`, `Shopping.lua`, `Merchant.lua`, `AH.lua`, `ProfessionButton.lua`:

| Spot | Today | Why it hurts |
|---|---|---|
| Header row | Six `UIPanelButtonTemplate` buttons: Profit, Leveling, Route, Profession, `Sell: vendor` / `Resale: vendor`, `Show: everything` / `Unlearned recipes: on` | Navigation, a selector and two settings look identical, and two buttons change meaning per tab. |
| "My reputation" | A checkbox jammed into the title bar at (6, -2) | A worst-case/typical planning option sits where a window title belongs. |
| Info line | One `FontString`, 330 px, `SetWordWrap(false)`: profession, skill, counts, lock date, odds mode, two possible warnings, concatenated | Truncates exactly when it has something important to say. |
| Re-plan vs Search | Both anchored `TOPRIGHT -34, -58`, toggled by tab | Works, but the right corner changes job per tab. |
| Route list | History, steps, prep rows, "Recipes to learn" and "Shopping list" all in one 16-row list; section titles are rows with gold text; "make" rows are indented with six spaces; "Completed steps" is a row starting with `>` / `v` | A long route reads as 25 undifferentiated rows; the sections do not scan. |
| Cards | 154 x 46, label truncates at 100 px, selected = 2 px gold edge texture | Cramped; "selected" is hard to see; the delta hides in `GameFontHighlightSmall`. |
| Profession | Click-to-cycle button | Three professions means up to two wrong clicks. |
| AH | Three right-aligned buttons whose widths change with the count ("Margin: 14 unpriced", "Margin: 23 left (click to stop)") | The row shifts while it runs; shift-click and right-click are invisible affordances. |
| Vendor | `Buy` / `Sell` buttons and the "Don't bother with the AH" checkbox share the header; Sell confirmation and errors go to chat | The checkbox only applies to Sell all, and the blocked case ("the game blocked selling") is easy to miss. |
| Options | Spread over header buttons, the title bar, the vendor popup and seven slash commands | Nothing discoverable; no single place to see how the route is being priced. |

Shared fixes in all three directions: a header band with profession dropdown + skill bar, real section bands, pills for `learn` / `make` / `have` / `AH` / `vendor` / `done`, a Settings panel, a one-strip AH companion, segmented Buy/Sell in the vendor popup with the error shown in the window, and the same money and sign formatters everywhere.

## Shared tokens (semantic; identical in all directions)

| Token | Value | Use |
|---|---|---|
| profit | `#6ee86e` | green `+` you earn, a card that is better for you |
| loss | `#ff6b6b` | red `-` you lose, a worse card |
| gold / silver / copper | `#ffd700` / `#c8c8c8` / `#eda55f` | the g/s/c suffixes (already what `ns.Money` uses) |
| warn | `#ffd070` | banners, "AH is cheaper", "N reagents unpriced" |
| diff orange / yellow / green / grey | `#ff8040` / `#ffe84a` / `#4fd04f` / `#909090` | recipe colour (today's `DIFF_COLOR`, yellow softened from `ffff00` for legibility on dark) |
| unlearned | `#80c0ff` | blue recipes and `learn` pills |
| make | `#9fb4ff` | `make` rows |

Fonts: the game's. Titles `GameFontNormal` family (Friz Quadrata) at 15; rows `GameFontHighlight` at 13; uppercase labels `GameFontNormalSmall` recoloured to the dim token with 11 px. No shipped TTF is needed. Spacing scale 4 / 8 / 12 / 16. Row height 22 (today 20), section band 22, chips 20, buttons 22.

---

## A · Ledger

**One line.** A refined version of today's tabbed window: same mental model, strict hierarchy.

**Rationale.** People already know "three tabs, a list, four cards". The problems are hierarchy and crowding, not the model. The Ledger keeps the model and gives every element a home.

**Layout in words.** 700 x 470, movable, Escape closes.
1. Title bar: logo, "Margin", close.
2. Header band (panel colour): profession dropdown with icon, skill bar 140 px + `160 / 225`, gear (Settings) at the right. Warning banner (yellow) appears under this band only when there is something to say.
3. Tab strip: Profit · Leveling · Route as underline tabs. Right side: search box on Profit/Leveling; lock state + Re-plan on Route.
4. Chip row: only the chips the tab uses, each naming its setting (`Resale: vendor`, `Odds: worst case`, `Unlearned recipes: on`, `Sell: AH (net)`, `Recipes: all`, `Show: everything`). Right: a short status (`19 recipes · 18 priced · 19 shown`).
5. Route: four cards 160 x 56 (label + delta on line one, value + `~79 crafts` on line two; selected = gold frame), column header, then one scroll list with section bands: Completed steps (collapsible, total on the right) · Steps (to 225, net) · Recipes to learn (total) · Shopping list (still to buy). Prep rows hang off their step with a rail and a `make` pill.
6. Profit / Leveling: column header (sortable, arrow on the active column, right-click resets), rows: icon, name (+ blue learn hint for unlearned), cost, sale, signed value.
7. Settings: a child frame covering the window body, two columns: Planning (resale, odds, unlearned recipes, lock, target, reputation), Prices (AH cut, sale chance), Lists (known/all, useful/everything), Companions (AH list, vendor list, sell everything to vendor).

**Tokens.** bg `#0e0d10`, panel `#17161b`, panel 2 `#201e25`, border `#4b3f26`, text `#ece6d6`, dim `#958e7d`, accent `#d9b24c`.

**Components.** Window, TitleBar, HeaderBand, ProfessionDropdown, SkillBar, TabStrip, Chip, SearchBox, Card, ColumnHeader (sortable), Row (6 column variants: recipe, route step, prep, history, learn, shop), SectionBand, Banner, SettingsPanel (SegmentedControl, Checkbox, NumberBox), Tooltip helper.

**Trade-offs.** Still a single dense list; the shopping list is at the bottom of the Route tab; 700 x 470 is 40 x 50 larger than today.

**Effort.** S to M. Risks: low. Nearly every control already exists; the work is anchoring, section bands and the settings frame. The dropdown needs `UIDropDownMenu_*` (available on Forever) or a 20-line own menu.

---

## B · Workbench

**One line.** Two panes: the plan on the left, the thing you are looking at on the right.

**Rationale.** A route is a sequence of decisions, each with reagents, odds and a shopping impact. Hover tooltips hide that behind the mouse. The Workbench keeps the selected step's breakdown and the live shopping list visible, so you read on the left and act on the right.

**Layout in words.** 860 x 540.
1. Title bar.
2. One header band: profession dropdown, skill bar, the three tabs inline, then lock + Re-plan (Route) or search, and the gear.
3. Route, left pane (540): comparison strip 36 px tall with four segments (short label + delta, value + crafts; selected has a gold underline), then a scroll list of **step cards**: a 54 px rail (step number, from, "to N") and the step body (recipe, `learn` pill, `~n crafts · unit each`, net), with its `make` / `have` rows indented inside the card. Then Recipes to learn.
4. Route, right pane (320): **Detail** for the selected step (icon, name, odds line, reagent lines with source and cost, cost per craft, vendor sale, AH sale, net per craft, "Open and craft n" button, "Learn first" when unlearned), then the **Shopping list** with a thin have/need bar per item and `AH` / `vendor` / `done` pills.
5. Profit / Leveling: list left (name, cost, value); right: Detail for the selected recipe and the view's own controls (Sell at, Recipes, Show / Resale, Odds).
6. Settings: same panel as A.

**Tokens.** bg `#0b0e11`, panel `#131a1f`, panel 2 `#1a2329`, border `#3b4b54`, text `#e6e9e8`, dim `#8d9a9c`, accent `#c9a24a` (brass on slate).

**Components.** Everything in A plus SplitPane, ComparisonStrip, StepCard (rail + body + sub rows), DetailPane (label/value grid), ShopRow (icon, name, pill, have/need bar, total), ViewControls.

**Trade-offs.** Widest window; two scroll regions; the most new layout code. The detail pane duplicates what the tooltip shows (that is the point, but it is more to keep in sync).

**Effort.** M to L. Risks: medium. Selection state per tab, two scroll frames, the detail renderer; "Open and craft n" reuses `ns.OpenRecipe` unchanged.

---

## C · Tracker

**One line.** A narrow checklist you keep open while you play; the analysis is one click away.

**Rationale.** Most of the time you are not analysing, you are doing: craft this, buy that, learn the next recipe. The Tracker leads with the one step that matters now and turns its prep and materials into ticks. It docks beside the AH and vendors, so there is one Margin window instead of three.

**Layout in words.** 320 wide, height follows content to 520.
1. Title bar with the profession name.
2. Skill bar + a small segmented control: Route · Profit · Lvl.
3. Route: a "Priced with resale: vendor · -27g" line (tap: popover with the four options and deltas); a one-line hint when another option would save money ("Resale: AH would save 53g · Use it"); **Now** block: step n of m, recipe name large, `~5 crafts · 54s 90c each · -1g 30s`, checklist of `make` prep (local tick) and raw materials (ticked from your bags), "Open, craft 5" / "Learn first"; **Next**: one row per remaining step; **Shopping** as a checklist with have/need; **Completed** collapsible.
4. Profit / Lvl: two-line rows (name; cost · sells), one signed value column; sort by tapping either header; chips for the view's settings in the footer.
5. Footer: lock state, Re-plan, gear, **Expand** (opens the Ledger window).
6. At the AH the same window docks `TOPLEFT` to the AH `TOPRIGHT` and shows the Shopping section with Search buttons; at a vendor it shows Buy / Sell.

**Tokens.** bg `#09090b`, panel `#121214`, panel 2 `#1b1b1f`, border `#3d352c`, text `#f1ece0`, dim `#938c7e`, accent `#f0b429` (amber).

**Components.** Window, SkillBar, SegmentedControl, SummaryLine + Popover, Banner with action, NowBlock, CheckRow, CompactRow (two lines), SectionBand, Footer, plus the Ledger window for Expand.

**Trade-offs.** Profit and Leveling are cramped at 320 px; it needs a second (full) layout for sorting and comparing; the prep tick is UI state only (the addon cannot know you finished a `make` step except through bag counts, which it already uses for `have`).

**Effort.** M for the Tracker, S to reuse the Ledger for Expand. Risks: low to medium. The dock logic exists in `Shopping.lua` / `Merchant.lua`; the new work is the Now block and check rows.

---

## Companions (all directions)

- **AH strip**: one 26 px strip, left-aligned on the AH top edge (`BOTTOMLEFT` to `TOPLEFT`), segments: Margin brand · `Scan: Leatherworking ▾` · `Shopping list (3)` · `? 14 unpriced · Look up`. Running state: `● Looking up · 11 left · Stop`. Right-click (count again) and shift-click (include crafted results) stay, and the tooltip says so. The strip's width is fixed; only the count changes.
- **Shopping popup** (A, B): 360 wide, header `Leatherworking 160 to 225 · still to buy 50g`, groups Auction house / Vendor / Done with group totals, rows with a have/need bar and `Search n`. (C: the Tracker docks instead.)
- **Vendor popup**: segmented `Buy for the route` / `Sell crafted items`; Buy rows show `need, have, cost` and `Buy n`; `AH is cheaper` and `done` rows are dimmed with no button; "Buy everything for the route" (or "Buy next stack" once `buyPerClick` is set) at the bottom. Sell rows: `n in bags · value · step · AH ~x each`; `Sell n` becomes `Sure? n` for six seconds; the bottom button reads `Click again: sell n items for x`; "Sell everything to the vendor" sits under it; the blocked error shows as a red banner in the window.
- **Profession window**: the button keeps its four-candidate placement. <span>Proposed</span>: a one-line summary under the selected recipe (`Margin: cost · vendor · ±profit · route step`), 12 px, using `ns.Money`. It is the one new feature in this document.

## States

Empty (no profession scanned: logo, one sentence, buttons to open each profession via `C_TradeSkillUI.OpenTradeSkill`), unpriced (banner with a count and an "At the AH: Look up" button; `?` values; "Loading item names…" row), warning banner (replaces the truncating info line), long list (search active, 57 rows), blocked vendor error, recipe tooltip and `make` tooltip.

## Recommendation

**Build the widget kit once, ship the Ledger first, then add the Tracker as a second layout.**

- The Ledger is the shortest path from the current code and fixes every awkward spot above. Every component it needs is also needed by the other two, so nothing is wasted.
- The Tracker is the layout that fits how the addon is actually used (at a vendor, at the AH, crafting) and the owner's brief: one obvious next action, low clutter, ticks. It is cheap once the kit exists because it is mostly a different layout declaration plus the Now block, and its Expand button is the Ledger.
- The Workbench is the best *reading* experience but the most code and the widest window. Take its two best ideas without taking the layout: the persistent **Detail pane** can be a registry panel that the Ledger shows on demand (a `>` toggle at the right edge), and the **have/need bar** goes into the shared ShopRow used by the shopping popup.

Order: kit + Ledger (one release), Tracker (next release), optional Detail pane (later). `ARCHITECTURE.md` has the steps.
