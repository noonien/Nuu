# UI kit: status

Where the NuuKit UI kit stands (2026-09-28), what is known to be wrong or untried, and what to do next. Read with
[docs/ui-kit/PLAN.md](../../docs/ui-kit/PLAN.md) (the design), [examples.lua](examples.lua) (the API in use) and
[README.md](README.md) (how widgets are written).

## Done

**Design.** Mockups on a claude.ai canvas, pinned in the sidebar: <https://claude.ai/artifact/2b8Q697XdKeYNaHMsn96QX>,
with a source copy in `docs/ui-kit/mockups/`. Decisions made along the way:

- The kit ships reusable parts only. The tracker, guide browser, planner, options windows and bug report form
  are the addons' own, built from kit parts.
- The kit holds no settings. Addons pass in their own look table, window-placement table, and (`bind`) the
  tables their settings live in.
- Captions and labels are sentence case, never all capitals.
- Art themes use real textures, kept restrained: faint tiled grain, a thin 9-slice frame, plates. A close button
  drawn as a texture looked wrong twice; it is a bright X in an outlined square, with the plate only on hover.
- Money never shows a zero coin (`96s`, not `0g 96s`).
- Keyboard focus follows text fields by default. Full keyboard control is opt-in per window, because that window
  then holds the keyboard.
- Checkboxes, chevrons and check marks are drawn by the kit, not the client's gold art, so they take the theme.

**Architecture.** The first kit was rebuilt after measuring six designs on one screen (`Tests/Bench/`): shared
methods through one class per widget type (copied onto frames if a client refuses frames a metatable), a pool per
widget type, colour-only hover, colours and fonts worked out once per look, cached natural sizes, a layout pass that
stops where sizes stop changing and places only edges that moved, and whole-pixel placement everywhere. A props
schema and a declarative layer were measured and rejected: slower, and no easier to use. [README.md](README.md) has
the details.

**API.** One spec table per widget (`col:Button{ "Save", tone = "accent" }`); callbacks only for the player's
changes; `bind = { table, key }` with `default`, `Reset()` and `IsStored()` on every value widget; clearing
deletes, and the pools behind it are never seen by the addon.

**Code.** Every widget of the plan's phases 1 to 6:

| File | What |
| --- | --- |
| `Theme/Themes.lua` | Midnight, Slate, Obsidian, and the art themes Horde and Alliance; `UI.AddTheme`; accents; status colours; `UI.MediaPath` |
| `Theme/Look.lua` | colour maths, `UI.ResolveLook`, `UI.LookTokens`, `UI.ButtonColors`, text styles, `Kit.FormatMoney` / `Kit.ParseMoney`, `UI.ShortKey`; pure Lua |
| `Base/Core.lua` | `Kit.NewUI`, `UI.Define` / `UI.Make`, classes, pools, `SetLook` / `Paint` / `OnLook`, the per-look colour cache, `bind`, pixels, `UI.Hover` |
| `Base/Draw.lua` | plates, 9-slices (one per art theme, kept), tiles, glyphs drawn with lines |
| `Base/Layout.lua` | `Column`, `Row`, `Spacer`, `Rule`, `UI.Part`, the layout pass (`UI.LayoutNow`), `stack:SetState` for loading / empty / error |
| `Base/Scroll.lua`, `Focus.lua`, `Drag.lua`, `Tooltip.lua` | the slim scroll bar, keyboard focus and the Tab order, moving and sizing by hand, tooltips |
| `Base/Text.lua` | `Text`, `Section`, `Tag`, `Notice`, `Card` |
| `Controls/Buttons.lua` | `Button`, `ConfirmButton`, `Link`, `ResetButton`, `GlyphButton`, `widget:Attract` |
| `Chrome/Window.lua`, `Tabs.lua` | `UI:Window`, `UI:Panel` (chrome, move / resize / collapse / place / Escape, status with Undo, keyboard control); `Tabs`, `Disclosure` |
| `Controls/Fields.lua`, `Forms.lua` | `Input`, `Search`, `TextArea`, `MoneyInput`, `NumberInput`, `Toggle`, `Slider`, `UI:TabChain`; `Setting`, `Choices` |
| `Controls/Menus.lua` | `UI:OpenMenu` (headers, keys, checks, radios, submenus, search), `Select`, `SearchSelect`, `MultiSelect` |
| `Display/Lists.lua`, `Tables.lua` | `ScrollArea`, `List` (a screenful of rows, reused), `Tree`, `SplitPanes`; `Table`, `Pager`, `Figures` |
| `Display/Feedback.lua`, `Slots.lua` | `ProgressBar`, `SegmentBar`; `UI:StripPanel`, `Slot` (secure slots never pooled) |
| `Theme/LookPicker.lua` | the Appearance section |
| `../Dev/Gallery.lua`, `../Dev/Report.lua` | development only: `/nuukit ui` (every widget, and a Pooling tab), `/nuukit report` |

**Tests.** `nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"` from `NuuKit/` runs six suites: the core, the
theme and look sums, table columns, and the smoke tests (`Tests/UI/Smoke/`), which build every widget on a stand-in
for the client's frame API (`Tests/Support/Frames.lua`, taught a few of the client's rules) and check behaviour,
pooling (a rebuild makes no frames, and nothing of a widget's last use survives), and the costs that matter (hover
sets no font and lays nothing out, a text change lays out only its row). `lua Tests/UI/Smoke/Run.lua --copy` runs
them with methods copied instead of shared. `Tests/Bench/Run.lua` (the bench screen) and `Tests/Bench/Gallery.lua`
(the whole gallery) count client calls, to compare before and after a change.

## Measured in the client

`/nuukit report` on build 70009 (1.60.1, 3840x2071, UI scale 0.64), 2026-09-28, against the first kit on the same
60-row screen:

| | First kit | This kit |
| --- | --- | --- |
| Build | 27 ms, 621 KB kept | 13 ms, 163-184 KB kept |
| Hover | 24 us | 11 us |
| Click "+1" and layout | 5.1-5.7 ms | 0.38-0.40 ms |
| Look change | 9-10 ms | 2.2 ms |
| Resize | 10.4-11.2 ms | 0.84-0.93 ms |
| Clear and rebuild | 26 ms, 130 frames made, 588 KB kept | 4.5 ms, 0 frames made, 1 KB kept |

Methods are shared through metatables in this client. Every shown gallery widget sits on whole screen pixels (183
of 183). The client features the kit uses are all there; see [docs/api-compatibility.md](../../docs/api-compatibility.md).

## Not verified, and known issues

- **Seen, not gone through.** The gallery was looked over in the client and looked right, and the report checked
  what it can measure. The row-by-row checks in `docs/api-compatibility.md` (what each animation, field and menu
  should do) have not been gone through one by one.
- **The first kit's leak on art themes** (every switch to Horde or Alliance made new textures) is fixed here; each
  plate keeps one 9-slice per theme. It is not measured in the client yet: the report switches flat themes only.
- **Layout timing.** Layout runs on the next frame (a driver `OnUpdate`), or at once through `UI.LayoutNow()`; a
  window lays out as it is shown.
- **Globals.** A window made with a `key` gets a named frame (`<addon>_<key>_Window`), because `UISpecialFrames`
  needs names for Escape. The gallery sets `SLASH_NUUKIT1` and `SlashCmdList.NUUKIT` (development only). Both go
  beyond the one-global rule in AGENTS.md: keep them, or close windows on Escape another way.
- **Rough edges:**
  - `LookPicker`'s theme cards are a fixed 4 per row at 118 px, so the picker wants about 500 px.
  - `Tree` rows draw their own regions rather than kit text widgets.
- **Open questions** from the plan, still open:
  - Where an embedded kit sits in a release. `Kit.folder` or `Kit.mediaRoot` must be set for the textures.
  - Whether NuuProfessions can follow NuuRoad's look.
  - The accents that clash with status colours: Gold, Rose, Ember and the Paladin colour.
  - Themed tooltips, or Blizzard's.

## How to continue

1. **Adopt it in the addons.** Neither addon uses the kit's UI yet. For each addon:
   - Add `look` and `windows` to its SavedVariables.
   - Add `ns.UI = ns.Kit.NewUI(ns, db.look)` to `Core.lua`.
   - Build its options window with a `LookPicker` section (the Setup and Looks examples in `examples.lua`).
2. **Port the screens** from OpenRoad into the addons, built from kit parts: NuuRoad's tracker, guide browser and
   editor, then NuuProfessions' planner. Follow AGENTS.md: take OpenRoad's behaviour, and write sentence-case
   captions. Most of OpenRoad's refreshes change screens in place (`SetText`, `SetValue`, `list:SetItems`); a
   screen that changes shape clears and builds again. Long content goes in a `List`. Not worth porting from
   OpenRoad: tracker refreshes that skip its throttle (kills, step advances), the guide browser re-filtering on
   every tracker refresh while open, and search boxes without a debounce.
3. **Keep the tests green, and the costs.** After a change, run the suites and compare the two benches' client
   calls; in the client, `/nuukit report`.
4. **Releases.** Embed the kit's `Kit.lua`, `Core/`, `UI/` (not `examples.lua`, `status.md` or `README.md`) and
   `Media/` into each addon, and set `Kit.folder`. Never ship `NuuKit.lua`, `Dev/`, `Tests/` or `Tools/`.
5. **Textures.** Change colours, grain or corner sizes in `Tools/Textures.py`, then run
   `uv run --no-project --with numpy --with pillow python NuuKit/Tools/Textures.py` (`--png` also writes PNG copies
   to look at). Corner sizes must stay in step with `UI/Theme/Themes.lua`.
