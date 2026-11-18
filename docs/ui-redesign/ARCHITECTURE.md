# Margin UI architecture: make it cheap to move things

Goal: restructure the Lua UI so a tab, panel, column, colour or whole layout can be added, moved or removed without touching unrelated code, and so the three directions in `mockups.html` are different *layout tables*, not different codebases. No big-bang rewrite: each step below ships on its own with CI green.

CI today: `luac5.1 -p` on every file, every `.lua` listed in the `.toc`, no unknown globals (`tests/allowed_globals.txt`), and `lua5.1 tests/calc_test.lua`. Every new file goes in the `.toc`; every new WoW global goes in `allowed_globals.txt`.

## Modules

```
Margin/
  Theme.lua      design tokens: colours, fonts, spacing        (ns.T)
  Widgets.lua    the widget kit                                (ns.W)
  Layout.lua     declarative layout: builds frames from tables (ns.L)
  Registry.lua   tabs, panels, columns, row kinds, companions  (ns.UI)
  Windows/
    Main.lua     the main window, as a layout table + glue
    Shopping.lua, Merchant.lua, AHStrip.lua (today's companions, moved onto the kit)
```

### Theme.lua: tokens

One table, read everywhere, never literal colours in widgets.

```lua
ns.T = {
  color = {
    bg = {0.055,0.051,0.063}, panel = {0.09,0.086,0.106}, panel2 = {0.125,0.118,0.145},
    border = {0.29,0.25,0.15}, text = {0.93,0.9,0.84}, dim = {0.58,0.56,0.49}, accent = {0.85,0.7,0.3},
    profit = {0.43,0.91,0.43}, loss = {1,0.42,0.42}, warn = {1,0.82,0.44},
    unlearned = {0.5,0.75,1}, make = {0.62,0.71,1},
    diff = { [0]={1,.5,.25}, [1]={1,.91,.29}, [2]={.31,.82,.31}, [3]={.56,.56,.56} },
  },
  hex = {},                      -- same colours as "rrggbb" for |cff escapes, filled in at load
  font = { title = "GameFontNormal", row = "GameFontHighlight", small = "GameFontHighlightSmall", label = "GameFontNormalSmall" },
  space = { xs = 4, s = 8, m = 12, l = 16 },
  size  = { row = 22, section = 22, chip = 20, button = 22, bar = 9, icon = 16 },
}
function ns.T.Set(name, overrides) ... end   -- swap a palette (Ledger / Workbench / Tracker tokens), re-skins live frames
```

Widgets register a `ReTheme()` closure when created, so `ns.T.Set` can recolour an open window (cheap: it only sets colours and font objects).

### Widgets.lua: the kit

Every widget is `ns.W.Name(parent, opts) -> frame`, uses tokens only, exposes `Set*` methods, and never reads addon state. The row-level pieces are pooled.

| Widget | Opts | Notes |
|---|---|---|
| `Window` | title, width, height, strata, onClose | BasicFrameTemplateWithInset today; later own 1 px border + panel textures. Registers in `UISpecialFrames`. |
| `Panel` | bg, border | a frame with two textures |
| `HeaderBand` | children | horizontal flow with `space.s` gaps (a tiny flow layout: anchors each child `LEFT` to the previous `RIGHT`) |
| `Button` | text, icon, primary, onClick, tooltip | `UIPanelButtonTemplate` first, own skin later |
| `IconButton` | icon (atlas or TGA), tooltip | 22 x 22 |
| `Tab` / `TabStrip` | items, onSelect | underline tabs; `SetSelected(key)` |
| `Chip` | label, value, onClick, tooltip | `SetValue(v)`; the thing that replaces the mode buttons |
| `SegmentedControl` | options, value, onChange | settings and Buy/Sell |
| `Checkbox` | label, tooltip, onChange | `UICheckButtonTemplate` with token colours |
| `NumberBox` | value, min, max, onChange | `InputBoxTemplate` |
| `SearchBox` | placeholder, onChange | |
| `ProgressBar` | value, max, width, label | skill bar, have/need bar (StatusBar or two textures) |
| `Card` | label, value, sub, delta, selected, onClick | 160 x 56 |
| `SectionBand` | title, hint, total, collapsible, onToggle | the band rows that replaced fake header rows |
| `ColumnHeader` | columns {key, title, width, align, sortable}, onSort | draws arrows, right-click resets |
| `Row` | columns | pooled; `SetEntry(entry)` fills cells by `columns[i].key`; variants (prep rail, history dim, gap red, selected) are flags on the entry |
| `Pill` | kind (learn/make/have/ah/vendor/done) | an inline texture + small font string; or `CreateTextureMarkup` inline in the name string, which needs no widget |
| `Banner` | kind (warn/err/ok), text, action | shown/hidden by the window |
| `MoneyText` | `SetMoney(copper)` | wraps `ns.Money`; `SignedMoneyText` wraps `signed` (green +, red -) |
| `Tooltip` | `ns.W.Tip(frame, builder)` | sets OnEnter/OnLeave once; `builder(GameTooltip)` adds lines; the recipe and prep builders move out of UI.lua into `Tooltips.lua` |
| `ScrollList` | rowHeight, visibleRows, makeRow | the existing offset + Slider + pooled rows pattern, made reusable (`SetEntries(list)`, `SetOffset`) |

### Layout.lua: declarative windows

A window is a table. `ns.L.Build(spec, ctx)` creates it; `ns.L.Bind(frame, state)` refreshes it. Children are listed with anchors in the same grammar as `SetPoint`, plus a `flow` helper for rows of controls.

```lua
local LEDGER = {
  kind = "Window", title = "Margin", width = 700, height = 470,
  children = {
    { id = "header", kind = "HeaderBand", point = {"TOPLEFT", 0, -26}, height = 34, flow = {
        { id = "prof", kind = "Button", bind = "profession" },
        { id = "skill", kind = "ProgressBar", width = 140, bind = "skill" },
        { kind = "Spacer" },
        { id = "gear", kind = "IconButton", icon = "gear", onClick = "toggleSettings" } } },
    { id = "tabs", kind = "TabStrip", below = "header", items = "registry:tabs", onSelect = "selectTab" },
    { id = "chips", kind = "HeaderBand", below = "tabs", flow = "registry:chips" },
    { id = "banner", kind = "Banner", below = "chips", bind = "warning" },
    { id = "body", kind = "Slot", below = "banner", fill = true },   -- the selected tab renders here
  },
}
```

`bind` names a key in the state table the window's controller produces (`profession`, `skill`, `warning`, ...). `onClick`/`onSelect` name actions in the controller (`ns.UI.actions.selectTab`). The Workbench adds a `SplitPane` kind with two slots; the Tracker is a 320-wide spec with a `NowBlock` kind. Choosing a layout is `ns.Opt("layout")` -> `ns.L.Build(LAYOUTS[layout])`.

Keep the grammar small: `point`, `below` (anchor TOPLEFT to the previous child's BOTTOMLEFT with `space.xs`), `fill`, `flow`, `width`, `height`. Anything fancier is a widget, not layout syntax.

### Registry.lua: plug-ins

```lua
ns.UI.RegisterTab{ key = "profit", title = "Profit", order = 10, columns = {...}, entries = fn(state) -> list, chips = {"sellKey","scope","showAll"}, search = true }
ns.UI.RegisterTab{ key = "route",  title = "Route",  order = 30, cards = fn(state), sections = fn(state) -> list, chips = {"resale","useTrainer","odds"}, replan = true }
ns.UI.RegisterChip{ key = "resale", label = "Resale:", values = {"vendor","ah","off"}, text = {vendor="vendor", ah="AH", off="none"}, relocks = true }
ns.UI.RegisterColumn("profit", { key = "profit", title = "Profit", width = 118, align = "RIGHT", cell = "SignedMoney", sort = "sortVal" })
ns.UI.RegisterPanel{ key = "detail", side = "right", width = 320, render = fn(frame, state) }    -- Workbench detail pane, optional in the Ledger
ns.UI.RegisterSetting{ group = "Planning", key = "odds", kind = "segmented", options = {...}, label = "Skill-up odds", hint = "...", relocks = true }
ns.UI.RegisterCompanion{ key = "shopping", anchorTo = "AuctionHouseFrame", render = ... }
```

The main window iterates the registry: tabs in `order`, chips the tab lists, columns the tab lists, settings by group. Adding a column is one `RegisterColumn` call plus the value in the entry; adding a tab is one file. Removing one is deleting its registration. The settings panel is generated from `RegisterSetting`, so a new option is one line and appears in the panel, with the slash command still reading the same `ns.Opt`.

### Entries: the one data contract

Today rows are `{ icon, name, cost, sale, val, data | tip, craft, action }` with colours baked into strings. Keep that shape (it works and the tests do not touch it), but move colouring into cells: an entry carries raw values (`diff`, `unlearned`, `learn`, `profit`, `cost`), and the column's `cell` kind decides formatting (`Money`, `SignedMoney`, `RecipeName`, `Text`). Sections become entries of kind `section`; prep rows carry `kind = "prep"`; history `kind = "history"`. `ScrollList` only needs `#list` and `list[i]`.

## Migration: ordered, each step shippable

1. **Theme.lua + MoneyText.** Add `ns.T`; move `money`, `signed`, `plainMoney`, `DIFF_COLOR` out of UI.lua into it (keep `ns.Money` as the public name). Replace literal `|cff...` codes with `ns.T.hex.*`. No visible change. Test: `calc_test.lua` unchanged; add `tests/theme_test.lua` that loads Theme.lua under plain Lua and asserts `ns.Money(12345)` and `ns.Signed(-50)` strings (they are pure functions).
2. **Widgets.lua, first five.** `Window`, `Button`, `Chip`, `SectionBand`, `ScrollList`, `Tip`. Port the main window's existing controls to them *in place* (same positions). Visible change: none, or the chips. Add any new globals (`CreateColor`, `UIDropDownMenu_Initialize`, `UIDropDownMenu_AddButton`, `UIDropDownMenu_CreateInfo`, `ToggleDropDownMenu`, `CloseDropDownMenus`) to `tests/allowed_globals.txt` when first used.
3. **Entries and cells.** Introduce `cell` kinds; route sections become `section` entries drawn by `SectionBand`; prep rows get the rail. UI.lua shrinks; `RefreshUI` stays the single redraw entry point. Ship: this is already most of the Ledger's readability.
4. **Registry: tabs, chips, columns.** Register the three tabs and the six modes as chips; delete `tSort` / `tAll` and the per-tab `if` chains in `redraw`. The header band (profession dropdown, skill bar, gear) lands here. Ship: the Ledger header.
5. **Settings panel from `RegisterSetting`.** Every option in `ns.defaults` gets a registration; the title-bar checkbox and the vendor checkbox move in; slash commands remain. Ship.
6. **Companions onto the kit.** `AHStrip.lua` replaces the three buttons with one strip (same handlers: `search`, `ns.ToggleShopping`, the Scan cycle). Shopping and Merchant popups use `ScrollList`, `SectionBand`, `SegmentedControl`, `Banner` (the `ADDON_ACTION_FORBIDDEN` message becomes a banner as well as a print). Ship.
7. **Layout.lua.** Express the main window as the `LEDGER` table; `build()` becomes `ns.L.Build(LEDGER)`. Nothing visible changes; now layouts are data. Ship.
8. **Tracker layout.** Add `TRACKER` spec, `NowBlock` and `CheckRow` widgets, `ns.Opt("layout")`, the dock-at-AH/vendor rule, Expand = open the Ledger. Ship as a feature release.
9. **Optional: Detail panel** via `RegisterPanel` (the Workbench's right pane) that the Ledger can show; the Workbench layout itself becomes a third spec if wanted.

Each step touches one layer; `redraw` keeps working between steps because the entry shape and `ns.RefreshUI` do not change until step 3, and step 3 keeps the old fields alongside the new ones for one release.

## Testing

- `tests/calc_test.lua` stays the gate for planner and prices; the UI work must not touch `Calc.lua`.
- Pure UI helpers (money formatting, entry builders, registry ordering, layout table validation) get `tests/ui_test.lua`, run the same way: `lua5.1 tests/ui_test.lua`, and added to the CI job. It loads `Theme.lua`, `Registry.lua` and the entry builders with a stub `ns` and no frames. Layout validation: every child `kind` is a known widget, every `below` names an earlier sibling, every `bind` is a key the controller produces.
- Frame code is checked by the existing syntax and unknown-globals steps; in-game checks are manual (open each tab, each companion, a locked and an unlocked route, an empty character).
- `tests/allowed_globals.txt`: add each WoW API the kit introduces the moment it is used, or CI fails on the next push.

## Art

No image files are required for any direction: borders are 1 px `SetColorTexture`, bars are two textures, section bands are a texture with a 1 px top and bottom line, item icons are the game's (`Interface\Icons\*` via `C_Item.GetItemIconByID`), the gear and search glyphs can be game atlases or the TGAs in `art/`. The logo and pill glyphs ship as 64 x 64 32-bit TGAs (see `art/README.md`) and are referenced with `SetTexture("Interface\\AddOns\\Margin\\art\\logo")`.
