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
changes; `bind = { table, key }` with `default`, `Reset()` and `IsStored()` on every value widget; `data` for the
addon's own values; `AddTexture` / `AddText` / `AddFrame` for decorations; clearing deletes, and the pools behind it
are never seen by the addon.

**Reset on release, by marks.** WoW never frees a frame, so a released widget's frame is used again. Every
release lets go of what pointed at the widget (the kit's tooltip, a menu, the focus ring) and what the kit held for
the addon (spec, callbacks, `data`), and puts away its Adds. What an addon did to the widget itself with the plain
API is undone only when the addon marked it: `w:Customize(ui.Custom.events)` (flags that add up: `events`,
`parts`, `frame`; none means `frame` and `parts`), kept as one number on the widget, each undone by its cheapest
call, `frame` by `SetToDefaults`, events, the keyboard and the kit's setup
made again (recorded once per type from Build). Alpha and scale need no mark: the widget's own `SetAlpha` and
`SetScale` note a value off the default, and release puts back only that. Resetting every widget was measured first (below)
and cost about 9 us a widget for widgets nobody touched. In development the audit (`Dev/Audit.lua`, on from
`NuuKit.lua`, `/nuukit audit`) checks the marks without wrapping anything: while it is on, a class's metatable
answers `__index` through a function that sees the widget and, through `debugstack`, the caller, and notes changes
from outside the kit's `UI/` files. Every wrong mark is an error: bad flags, a change no reset undoes and a change
after a clear with `error()` at the call; a change without its mark, a mark nothing needed and a `frame` mark where
`events` would do on release, through the client's error handler (an `error()` mid-release would break a `Clear`). The kit's own frames are
made with `UI.NewFrame`, which marks them, so neither the `parts` reset nor the audit takes them for an addon's.
[README.md](README.md) has the table of kinds and the audit's limits.

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
pooling (a rebuild makes no frames, and nothing of a widget's last use survives), the reset on release (a marked
change does not reach the next use, an unmarked one does, and the audit raises each wrong mark; `Reset.lua`), and
the costs that matter (hover
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
| Clear and rebuild | 26 ms, 130 frames made, 588 KB kept | 4.5 ms, 0 frames made, 1 KB kept (8.0 ms with the reset on release, below) |

Methods are shared through metatables in this client. Every shown gallery widget sits on whole screen pixels (183
of 183).

What `SetToDefaults` does on a frame in build 70009: it puts back alpha, scale, strata, level, shown, size, anchors,
movable, clamped, ID, enabled, button text, attributes, scripts and hooks, hit rect insets, clipping, ignoring the
parent's alpha and scale, resizable and its bounds, key propagation and toplevel, and turns the mouse off. It keeps
the parent, the wheel, registered events, the keyboard, animation groups, regions, children and Lua fields. One call
costs about 1.2-1.6 us.

Resetting released frames, clearing and rebuilding the same 60-row screen (about 250 widgets):

| | First run (no stray check yet) | Second run (with the stray check) |
| --- | --- | --- |
| No reset | 4.37 ms | 5.76 ms |
| Reset | 6.54 ms (+50%) | 8.03 ms (+39% over no reset) |
| `SetToDefaults` only | +17% | +9% |
| `UnregisterAllEvents` only | +12% | +4% |
| `SetToDefaults` + events | +27% | +18% |
| `SetToDefaults` + the kit's setup | +38% | +26% |

The reset is about 9 us a widget. Between the two runs "no reset" went from 4.37 to 5.76 ms: the stray check, added
in between, ran on every release, and it listed a widget's regions and children on nearly every one, because the
kit's widgets parented to a stack (its texts, its buttons) and parts the kit made later raised the counts it
compared. That is why only marked widgets are reset now; the stray check runs only for a `parts` mark and takes the
counts again after it looks. Not measured in the client since: the report's reset lines are now "no reset",
"marked only (default, none)" and "every widget, in full". On the bench (client calls, clear and rebuild): 8306
resetting every widget, 5320 marked only, 5574 before for no reset with the stray check. All of this happens on
releases only: building, hover, updates, look changes and resize do not change. The
client features the kit uses are all there; see [docs/api-compatibility.md](../../docs/api-compatibility.md).

## Not verified, and known issues

- **Seen, not gone through.** The gallery was looked over in the client and looked right, and the report checked
  what it can measure. The row-by-row checks in `docs/api-compatibility.md` (what each animation, field and menu
  should do) have not been gone through one by one.
- **The audit in the client.** Tested on the stand-in only (the whole smoke suite, gallery and examples included,
  logs nothing with it on). Not yet run in the client: whether this client's `debugstack` lines are what it expects
  (it keys the kit's files on the last folder before `UI/`, e.g. `NuuKit/UI/`), and what it costs while on.
- **Marks are the addon's to get right.** An unmarked change reaches the widget's next use in a release build; the
  audit only finds it in development, and only on uses that happen there.
- **The kit's own parts are not reset.** Measured on a button's label (build 70009): a changed font, anchor and
  shadow carry over to the widget's next use; its colour comes back (the kit repaints it). The documented rule: a
  widget's parts are the kit's; customize through the spec or an Add.
- **Animation groups** an addon makes on a widget are kept by `SetToDefaults`; stopping them would mean listing them
  on every release. Not handled; in the README's list of what is not undone, and the audit raises an error when one
  is made.
- **References kept after a release** reach the frame's next use: a documented rule. The audit raises an error for a
  change made through one in development; release builds do not look.
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
