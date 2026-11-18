# Art for the Margin UI redesign

All sources are hand-written geometric SVGs on a 24 x 24 grid (`*.svg`). `tga/` holds 64 x 64 32-bit uncompressed TGA exports with alpha, made with `rsvg-convert` + ImageMagick (both present on this machine; `inkscape` is not). WoW loads TGA/BLP only; PNG is not usable in-game.

Export command used (per file):

```
rsvg-convert -w 64 -h 64 NAME.svg -o NAME.png
magick NAME.png -define tga:image-origin=TopLeft -depth 8 -type TrueColorAlpha tga/NAME.tga
```

Verified: `magick identify tga/logo.tga` -> `TGA 64x64 8-bit sRGB 16402B` (18-byte header + 64·64·4), the layout WoW expects. Ship by copying `tga/*.tga` to `Margin/art/` and referencing `Interface\AddOns\Margin\art\NAME` (no extension). Glyphs are exported in the Ledger accent colour (`#d9b24c`); in-game, prefer a white export plus `texture:SetVertexColor(r, g, b)` from the theme so one file serves every palette. Re-export with `currentColor` -> `#ffffff` for that.

Most of these are **not needed** to implement the designs: item icons come from the game (`C_Item.GetItemIconByID`), and several UI glyphs have game atlases. The table says what each is for and the cheapest way to ship it.

| File | Size | Used for | Ship as |
|---|---|---|---|
| `logo.svg` | 24 (export 64) | title bars, AH strip brand, empty state, profession-window summary line | TGA (`art/logo.tga`); also fine as the addon's `IconTexture` replacement at 64 px |
| `gear.svg` | 24 | Settings button | TGA, or draw as 8 short lines + a ring texture in Lua; or atlas `mechagon-projects` style gear if present on Forever (check first) |
| `search.svg` | 24 | search box, AH Search buttons | TGA, or `Interface\Common\UI-Searchbox-Icon` (present on Classic clients) |
| `chev.svg`, `chevr.svg` | 24 | dropdown and collapsible markers | draw in Lua: `Interface\Buttons\UI-ScrollBar-ScrollDownButton-Up` cropped, or TGA |
| `lock.svg`, `unlock.svg` | 24 | route lock state | TGA, or `Interface\LFGFrame\UI-LFG-ICON-LOCK` |
| `cart.svg` | 24 | shopping list button, Buy buttons | TGA |
| `hammer.svg` | 24 | `make` pill, "Open and craft" | TGA, or `Interface\Icons\Trade_BlackSmithing` cropped |
| `book.svg` | 24 | `learn` pill, "Learn first" | TGA, or `Interface\Icons\INV_Misc_Book_09` |
| `check.svg` | 24 | checkboxes, `have` / `done` pills | `Interface\Buttons\UI-CheckBox-Check` (game) |
| `up.svg`, `down.svg` | 24 | sort arrows | text `^`/`v` today; TGA for a cleaner look |
| `warn.svg` | 24 | banners | `Interface\DialogFrame\UI-Dialog-Icon-AlertNew` (game) or TGA |
| `x.svg` | 24 | close buttons | `UIPanelCloseButton` (game) |
| `coin.svg` | 24 | comparison hints | `Interface\MoneyFrame\UI-GoldIcon` (game) |
| `ask.svg` | 24 | "N unpriced" | TGA |
| `pin.svg` | 24 | "docked" indicator (Tracker) | TGA |
| `expand.svg` | 24 | Tracker Expand button | TGA |
| `replan.svg` | 24 | Re-plan button | TGA |
| `lw.svg` | 24 | Leatherworking badge in the profession dropdown | not needed: use `Interface\Icons\Trade_LeatherWorking` (game); kept as a style reference for profession badges |
| `leather.svg`, `leather2.svg`, `leather3.svg`, `hide.svg`, `hide2.svg`, `cured.svg`, `cured2.svg`, `salt.svg`, `thread.svg`, `thread2.svg`, `cloth.svg`, `gloves.svg`, `shoulders.svg`, `cloak.svg`, `bracers.svg`, `headband.svg`, `tunic.svg`, `pants.svg`, `belt.svg`, `boots.svg` | 24 | stand-ins for item icons in the mock-up only | not shipped: the addon uses the game's item icons |

No gradients, shadows or blur are used anywhere; everything in the mock-ups that is not an icon is a solid colour, a 1 px line or a two-colour bar, all drawable with `SetColorTexture` / `SetGradient` (vertical two-stop, via `CreateColor`).
