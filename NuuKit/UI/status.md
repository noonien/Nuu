# UI kit: status

Where the NuuKit UI kit stands (2026-09-28), what is known to be wrong or untried, and what to do next. Read with
[docs/ui-kit/PLAN.md](../../docs/ui-kit/PLAN.md) (the design) and [examples.lua](examples.lua) (the API in use).

## Done

**Design.** Mockups on a claude.ai canvas, pinned in the sidebar: <https://claude.ai/artifact/2b8Q697XdKeYNaHMsn96QX>,
with a source copy in `docs/ui-kit/mockups/`. Decisions made along the way:

- The kit ships reusable parts only. The tracker, guide browser, planner, options windows and bug report form
  are the addons' own, built from kit parts.
- The kit holds no settings. Addons pass in their own look table and window-placement table.
- Captions and labels are sentence case, never all capitals.
- Art themes use real textures, kept restrained: faint tiled grain, a thin 9-slice frame, plates. A close button
  drawn as a texture looked wrong twice; it is a bright X in an outlined square, with the plate only on hover.
- Money never shows a zero coin (`96s`, not `0g 96s`).
- Keyboard focus follows text fields by default. Full keyboard control is opt-in per window, because that window
  then holds the keyboard.

**Code.** Everything in the plan's phases 1 to 6 is written:

| File | What |
| --- | --- |
| `Theme/Themes.lua` | Midnight, Slate, Obsidian, and the art themes Horde and Alliance; `UI.AddTheme`; accents; status colours; `UI.MediaPath` |
| `Theme/Look.lua` | colour maths, `UI.ResolveLook`, `UI.Tokens`, `UI.ButtonColors` (tones x styles x states), text styles, `Kit.FormatMoney` / `Kit.ParseMoney`, `UI.ShortKey`; pure Lua |
| `Base/UI.lua` | `Kit.NewUI(ns, look)`, `UI.Define`, `SetLook` / `GetLook` / `Paint` / `OnLook` / `RepaintAll`, `Finish`, plates, `NineSlice`, tiling, fonts, glyphs drawn with lines |
| `Base/Layout.lua` | `Column`, `Row`, `Spacer`, `Rule`, `UI.Distribute`, deferred top-down layout (`UI.Invalidate`, `UI.LayoutNow`), `container:SetState` for loading / empty / error |
| `Base/Tooltip.lua` | `UI:Tooltip` (Blizzard's, with the chained item or recipe tooltip), disabled reasons, item tooltips on slots |
| `Base/Text.lua` | `Text`, `Section` (folding, hint, reset), `Tag`, `Notice`, `Card` (a raised plate with a coloured rail, holding a column) |
| `Controls/Buttons.lua` | `Button` (tones, styles, art plates, hold), `ConfirmButton`, `Link`, `ResetButton`, `GlyphButton`, `widget:Attract` (breathe, pulse, shimmer, flash, trail) |
| `Chrome/Window.lua` | `UI:Window`, `UI:Panel` (in play), chrome, move / resize / collapse / place / Escape, `win:Status` with Undo, Tab order, opt-in keyboard control with a focus ring |
| `Chrome/Tabs.lua` | `Tabs` (underline tabs with badges and pages), `Disclosure` |
| `Controls/Fields.lua` | `Input`, `Search`, `TextArea`, `MoneyInput`, `NumberInput` (the wheel steps it while focused), `Toggle`, `Slider`, `UI:TabChain` |
| `Controls/Menus.lua` | `UI:OpenMenu` (headers, keys, danger items, checks, radios, submenus, search), `Select`, `SearchSelect`, `MultiSelect` |
| `Display/Lists.lua` | `UI.NewScroll`, `ScrollArea`, `List` (reused rows, search, keyboard, states, a number gutter, a value column), `Tree`, `SplitPanes` |
| `Display/Feedback.lua` | `ProgressBar` (marks, tones, busy), `SegmentBar` (runs and marks over a range, the value under the cursor for a tooltip, a click or a drag; the axis is the addon's) |
| `Display/Tables.lua` | `Table` (column heads with tooltips, fixed or growing columns, text, money or widget cells, groups that fold, a footer, search; on a `List`), `UI.TableColumns`, `Pager` (pages or records, add and delete), `Figures` (captions over large values, money, signed tones) |
| `Controls/Forms.lua` | `Setting` (name and help beside a control, a reset while changed), `Choices` (buttons in even columns, one picked) |
| `Display/Slots.lua` | `UI:StripPanel`, `Slot` (icon, quality edge, count on a shaded strip, key hint, quest mark, raid marker, cooldown, missing, secure attributes) |
| `Theme/LookPicker.lua` | the Appearance section: theme cards, accents, class colour, opacity, text size, less motion |
| `../Dev/Gallery.lua` | development only: `/nuukit ui` opens every widget in every state |
| `../Media/<theme>/*.tga` | the art themes' textures, made by `../Tools/Textures.py` |

**Tests.** From `NuuKit/`: `nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"`. All seven suites pass. `Tests/` follows the kit's folders:

- `Core/` has one suite per file in `Core/`.
- `UI/ThemeTests.lua`, `UI/BaseTests.lua` and `UI/DisplayTests.lua` cover the pure parts: tokens, looks, button
  colours, money and key hints; the layout sums, pixel snapping, and that every constructor exists; table columns.
- `UI/Smoke/Run.lua` builds the whole gallery against a stand-in for the client's frame API
  (`Support/Frames.lua`), then runs one file per UI part on it, in order, ending with `Keyboard.lua` (its Space
  closes the gallery) and `Examples.lua` (runs `examples.lua`). It switches every theme, clicks every button, and
  drives fields, menus, lists, windows and attention. It caught three real bugs while being written. It says
  nothing about how anything looks.

## Not verified, and known issues

- **Nothing has run in the client yet.** Every client API the kit relies on is listed, with what to look for, in
  [docs/api-compatibility.md](../../docs/api-compatibility.md). The riskiest:
  - Line objects (all glyphs; the fallback is ASCII).
  - TGA loading, and tiling with `SetHorizTile` / `SetVertTile`.
  - `Translation` animations, and `SetClipsChildren` for the shimmer and the window body.
  - Multi-line EditBox growth inside a scroll frame (the `TextArea`).
  - `SetPropagateKeyboardInput` in combat (only for the opt-in keyboard mode).
- **The pixel grid.** WoW lays out in units, not screen pixels (a pixel is `GetEffectiveScale()` times the
  physical screen height over 768; the effective scale alone is wrong), so the kit snaps every place, size and scroll
  offset to whole pixels (`UI.Snap`), draws hairlines exactly one pixel (`UI.Hairline`) and thicker lines as whole
  pixels (`UI.Stroke`), and redoes it on `UI_SCALE_CHANGED` / `DISPLAY_SIZE_CHANGED`. New code that anchors or
  sizes anything by hand, or draws a line, must use these, or its edges drift between 1 and 2 pixels.
- **Layout timing.** Layout runs on the next frame (a driver `OnUpdate`), top-down. A window may show its content
  one frame late. Code that needs sizes at once can call `UI.LayoutNow()`. Wrapped text is measured after its
  width is set; if a paragraph comes out one line short in game, look at `Text`'s `KitNaturalHeight`.
- **Globals.** A window made with a `key` gets a named frame (`<addon>_<key>_Window`), because `UISpecialFrames`
  needs names for Escape. The gallery sets `SLASH_NUUKIT1` and `SlashCmdList.NUUKIT` (development only). Both go
  beyond the one-global rule in AGENTS.md: keep them, or close windows on Escape another way.
- **Departures from OpenRoad**, deliberate:
  - Checkboxes, chevrons and check marks are drawn by the kit, not the client's gold art, so they take the theme.
  - Button constructors take an options table (`Button(caption, opts)`), not OpenRoad's positional arguments.
- **Rough edges:**
  - `MultiSelect`'s All and None rebuild the open menu through `ui.kitMenu.items`.
  - `LookPicker`'s theme cards are a fixed 4 per row at 118 px, so the picker wants about 500 px.
  - `Tree` rows draw their own regions rather than kit text widgets.
  - A `List`'s row content is a `Row` container sized by the list; very tall custom rows are not handled.
- **Open questions** from the plan, still open:
  - Where an embedded kit sits in a release. `Kit.folder` or `Kit.mediaRoot` must be set for the textures.
  - Whether NuuProfessions can follow NuuRoad's look.
  - The accents that clash with status colours: Gold, Rose, Ember and the Paladin colour.
  - Themed tooltips, or Blizzard's.
  - TGA or BLP.

## How to continue

1. **Try it in the client.** Run `link-addons.bat` once if the junctions are missing, then log in, `/reload`, and
   `/nuukit ui`. Go through [docs/api-compatibility.md](../../docs/api-compatibility.md) row by row. Record each
   result with the build and date, and fix what fails. Start with the glyphs, the art themes and the layout of
   the Controls tab.
2. **Keep the tests green.** After a change, run the suites. When a bug is found in the client, add the case to
   the smoke part for that folder if the stand-in can express it. The stand-in (`Tests/Support/Frames.lua`) resolves sizes from
   opposite anchors and runs `OnUpdate` scripts on `tick()`.
3. **Settle the open questions** above; the first matters before any release.
4. **Adopt it in the addons.** Neither addon uses the kit's UI yet. For each addon:
   - Add `look` and `windows` to its SavedVariables.
   - Add `ns.UI = ns.Kit.NewUI(ns, db.look)` to `Core.lua`.
   - Build its options window with a `LookPicker` section (the Setup and Looks examples in `examples.lua`).
5. **Port the screens** from OpenRoad into the addons, built from kit parts: NuuRoad's tracker, guide browser and
   editor, then NuuProfessions' planner. Follow AGENTS.md: take OpenRoad's behaviour, and write sentence-case
   captions.
6. **Releases.** Embed the kit's `Kit.lua`, `Core/`, `UI/` (not `examples.lua` or this file) and `Media/` into each
   addon, and set `Kit.folder`. Never ship `NuuKit.lua`, `Dev/`, `Tests/` or `Tools/`.
7. **Textures.** Change colours, grain or corner sizes in `Tools/Textures.py`, then run
   `uv run --no-project --with numpy --with pillow python NuuKit/Tools/Textures.py` (`--png` also writes PNG copies
   to look at). Corner sizes must stay in step with `UI/Theme/Themes.lua`.
