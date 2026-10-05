# Writing kit widgets

How the UI kit is built, for whoever adds or changes a widget. Using the kit is shown in `examples.lua`; where it
stands is in `status.md`.

The design was chosen by measurement (`Tests/Bench/`): widgets are frames whose methods come from one shared class
per type; hover and other state changes repaint colours only; colours and fonts are worked out once per look;
natural sizes are cached, and a layout pass measures again only what changed, going up only while sizes change and
placing only edges that moved; every edge sits on whole screen pixels; and a pool per widget type makes a cleared
screen's rebuild take its frames back instead of making new ones.

Read `Base/Core.lua` (the widget model) and `Base/Layout.lua` (stacks and the pass) first; `Base/Text.lua` and
`Controls/Buttons.lua` are the reference widgets. Comments in the kit's voice (plain English, what and why), ASCII
only, sentence-case captions.

### A widget type

```lua
UI.Define("Tag", {
    stretch = false,                  -- see UI.Define in Core.lua for every field
    Build = function(w) ... end,      -- once per frame: regions, sub-parts, scripts
    Init = function(w, spec) ... end, -- every make, pooled too: ALL state from the spec
    Release = function(w) ... end,    -- optional: stop OnUpdate, timers, close menus
    methods = {
        Measure = function(self, width) return naturalWidth, naturalHeight end,
        Sized = function(self, width, height) end,   -- optional: the layout resized it
        Paint = function(self, t) end,      -- the look: fonts (UI.ApplyStyle), art, colours
        PaintState = function(self, t) end, -- hover / press / disable / select: colours only
        SetText = function(self, text) ... self:Changed() end,
    },
})
```

- **No per-instance closures.** Scripts are file-level functions (`w:SetScript("OnEnter", onEnter)`); the handler finds
  its widget through the frame (`frame` is the widget, or store `sub.kitOwner = w` on sub-frames). Callbacks from the
  spec are stored as fields (`w.kitOnChange = spec.onChange`). A "frame" reset on release depends on it: the setup calls a
  type's Build makes on its widget's own frame (scripts, hooks, clicks, mouse, movable, strata, clipping...; the
  list is `SETUP` in `Core.lua`) are recorded once per type and made again after every reset, so they must be the
  same for every widget of the type. A frame setting not in that list belongs in Init, which runs on every make.
- **Init resets everything.** A pooled widget keeps whatever its last use left: text, shown/hidden parts, enabled,
  selection, scroll, timers, values. Optional parts are made lazily in Init the first time a spec needs them, then
  shown or hidden on every Init.
- **Build must not depend on the spec**, because the frame is reused for other specs. (`def.Create(ui, parent, spec)`
  exists for the rare frame that must be made differently, such as a secure template.)
- **Paint vs PaintState.** Hover and other state changes call `w:PaintState(w.ui.tokens)`. It must not set fonts,
  must not call `Changed`, and must not allocate: get colours from `UI.Colour`, `UI.Tone`, `UI.Faded`, `UI.Mixed`,
  `UI.ButtonColorsOf` (cached per look) instead of `UI.Alpha`, `UI.Mix`, `UI.TokenColor`.
- **Sizes.** `Measure(width)` answers the natural width and height (the height for `width` when the type sets
  `wraps = true`). When something may change the natural size, call `self:Changed()`, never the layout directly.
  `Sized(w, h)` is called when the layout gives the widget a new size; lay out its parts there if anchors cannot.
  `LeastWidth()` (worked out when asked, from the natural widths) is the narrowest it fits in with nothing cut or
  pushed out; a resizable window holds to it. A type that can take less than its natural width (wrapped text) or
  needs more than its parts say (a scroll area's bar) answers its own.
- **Sub-parts** a widget is built from (a section's reset link, a field's glyph button) are made with
  `UI.Make(ui, "Link", parent, spec)` in Build (or lazily in Init) and belong to the widget for good; a part placed by
  hand is sized with `UI.Fit(part)`. A widget that holds a stack for the addon's widgets sets `holds = true` and
  `w.kitInner = stack` (see Card, Section).
- **The kit's frames** are made with `UI.NewFrame(kind, name, parent, template)`, never `CreateFrame`: it marks
  them the kit's, so the `Custom.parts` reset and the audit pass over them.
- **Internal stacks**: `UI.Part(ui, parent, "row" | "column", opts, layout)` makes one (a section's heading and
  body, a setting's rows); the caller appends it. `UI.MakeStack` makes an existing frame a stack.
- **Hover on a part** (a tab, a band, a thumb) that only repaints colours: `UI.Hover(part, owner)`, which sets `hover`
  and calls the owner's `PaintState`. Write your own handlers only when hover does more (a tooltip, a submenu).
- **A part the kit builds widgets from** (a list's row): `UI.Define(name, { internal = true, ... })`, made with
  `UI.Make`; it gets no `ui:` or stack constructor.
- **Pixels**: `UI.Snap`, `UI.Pixels`, `UI.Hairline`, `UI.Stroke`, as before.
- **Focus**: `focusable = true` (or `"field"`) in the def; an inner EditBox registers with
  `UI.RegisterFocusable(ui, box, true)` in Init. `kitKeyArrow` / `kitKeyPress` as before. `UI.FocusOrder`,
  `UI.NextFocus`, `UI.FocusWidget`, `UI.WindowKey` are in `Base/Focus.lua`.
- **Shared helpers already in Base**: `UI.NewScroll(ui, parent)` and `UI.NewScrollBar(ui, parent, source, step)`
  (`Base/Scroll.lua`), `UI.DragFrame` (`Base/Drag.lua`), plates, 9-slices, tiles, glyphs (`Base/Draw.lua`),
  tooltips (`Base/Tooltip.lua`), `UI.WireButton` / `UI.ClickableType` / `UI.InitClickable` (`Controls/Buttons.lua`).

## The API's rules

Every widget follows these; `examples.lua` shows them in use.

- **One spec table per widget.** Its `[1]` is the caption, text, kind or list (`col:Button{ "Save", tone = "accent" }`,
  `col:Text"Hi"`); everything else is named. A list the widget is made of (tabs' entries, choices, figures, panes) is
  the spec's array part. Placed by hand: `ui:Button(parent, { "Save" })`.
- **Layout keys are layout only**: `width`, `height`, `grow`, `minWidth`, `minHeight`, `align`, `valign`,
  `stretch`. A part's own size has its own name (`boxWidth`, `boxHeight`, `barHeight`).
- **Callbacks are for the player.** `onClick(widget)`, `onChange(value, widget)`, `onPick(item)`; code that sets a
  value (`SetValue`, `Select`, `SetAt`) never calls them.
- **Value widgets** answer `GetValue` / `SetValue` and take `bind`, `default`, `Reset()` and `IsStored()` (below).
- **Clearing deletes.** `Clear`, `Remove` and `Release` take widgets away for good (into the pools, which the addon
  never sees); the addon does not use a widget after it clears it.

## Customizing a widget, and what release undoes

WoW never frees a frame, so a cleared widget's frame is used again for the next widget of its type. On every
release the kit lets go of what it holds for the addon and what points at the widget:

- **What the kit held for the addon** (the spec, callbacks, `data`) is dropped, so a widget in a pool keeps nothing
  of the addon's alive.
- **Things pointing at it:** the kit's tooltip for it, a menu anchored to it and the focus ring let go.
- **Decorations** made with `w:AddTexture(layer)`, `w:AddText(style)` and `w:AddFrame(kind)` are put away, and the
  next Add of the same kind on that frame takes them again. They need no mark.

What the addon does to the widget itself with the plain API is undone only when the addon marks the widget with
what it changes, because resetting every widget cost about 9 us a widget in build 70009 and most widgets are never
touched. `w:Customize(flags)` takes flags from `ui.Custom` (also `Kit.UI.Custom`), which add up (each once:
`Custom.frame + Custom.frame` is no flag), and returns the widget; the marks are one number on it. Each flag is
undone by its cheapest call:

| Flag | For | Undone by |
| --- | --- | --- |
| `Custom.events` (1) | `RegisterEvent`, `RegisterUnitEvent`... | `UnregisterAllEvents` (widgets register none of their own) |
| `Custom.parts` (2) | textures, texts and frames made on it with the plain API | hiding them (they stay on the frame, so one made on every use grows by one each time: prefer an Add) |
| `Custom.frame` (4) | everything else: scripts, hooks, strata, mouse, attributes, a text's colour or font... | `SetToDefaults`, `UnregisterAllEvents`, the keyboard off, and the kit's setup made again; covers `Custom.events` |

`w:Customize()` with no flags asks for `Custom.frame + Custom.parts`. Anchors, size, parent and frame level need no mark: the
kit sets them on every use. Nor do alpha and scale: every widget has its own `SetAlpha` and `SetScale`, which note
a value off the default (one field) before calling the client's, and release puts back only a noted one. `UI.resetMode` is `"marked"` by default; `"always"` resets every widget in full, and
nil none (both for measuring).

```lua
row:Button{ "Later" }:SetAlpha(0.6)                         -- no mark
local Custom = ns.UI.Custom
row:Button{ "Bags" }:Customize(Custom.events):RegisterEvent("BAG_UPDATE")
w:Customize(Custom.frame + Custom.parts):HookScript("OnEnter", showMore)
```

**The audit** (`Dev/Audit.lua`, development builds only, on from `NuuKit.lua`) checks the marks. While it is on,
each widget class's metatable answers `__index` through a function, which runs in the frame of the code looking a
method up, so `debugstack` names the caller: a change from outside the kit's `UI/` files is noted on the widget,
with the kind it needs, and the client's own method goes back as it is (nothing is wrapped or copied). On release
the notes are held against the marks. Every wrong mark is an error, every time:

- **At the call**, raised with `error()` at the addon's line, before the change is made:
  - **flags**: `Customize` given anything but `ui.Custom`'s flags, each added once (a string, 0, `frame + frame`).
  - **never**: a change no reset undoes (`CreateAnimationGroup`).
  - **released**: a widget changed after it was cleared.
- **On release**, sent to the client's error handler (`geterrorhandler()`: the error frame, or BugSack), which does
  not unwind: an `error()` there would stop a `Clear` half-way and leave its stack and the pools broken.
  - **missing**: a change the marks do not undo (it reaches the next use), with where it was made and the mark to
    add. A frame an addon made with the widget as its parent is found by looking, and named by where the widget was
    made.
  - **unneeded**: a mark nothing in that use needed, even one set and never used. A mark placed for a change made
    only sometimes fails on the uses without it: mark it where the change is made.
  - **broader**: `Custom.frame` where `Custom.events` would do.

Each is also counted in a log: `/nuukit audit` lists it, most frequent first; `/nuukit audit on`, `off`, `clear`. The report turns it off
while measuring. Its limits: a lookup counts as a call (`if w.SetBackdrop then` is noted), a method kept in a local
and called later is noted where it was looked up, a tail call from an addon passes as the kit's, and methods copied
onto frames (a client that refuses frames a metatable) are not watched.

What no mark undoes, and so is the addon's to avoid:

- **The kit's own parts** (a button's `label`, its plate, a field's box): a reset reaches the widget's frame, not
  its parts, and the kit sets some part settings only once (a label's anchor) or skips ones it believes set (a font).
  Customize through the spec or an Add.
- **Animation groups** made on the widget: `SetToDefaults` keeps them.
- **The addon's own fields** on the widget: use `w.data` (`data = ...` in the spec), which the kit clears.
- **References, timers and anchors** the addon keeps to a widget it cleared: they reach whatever the frame is next.

### `bind`, on every value widget

`bind = { db, "routeBy" }` ties the widget's value to the addon's table:

- The initial value is `db.routeBy`, else `spec.value`, else `spec.default`.
- A change by the player writes `db.routeBy`, then calls `onChange(value, w)`.
- `w:Reset()` forgets the choice (`db.routeBy = nil`), shows `spec.default`, then calls `onChange`.
- `w:IsStored()` answers whether the table holds a choice. It is what a reset link or a `Setting` row shows.

Use `UI.InitValue(w, spec)` in Init and `UI.Commit(w, value)` after a change by the player (both in `Core.lua`);
`Reset` and `IsStored` come with every widget.

## Contracts between files

- **Search to List** (Fields to Lists): a Search field calls `field.kitOnType(text, field)` on every change of its
  text, when set. While `field.kitList` is set, UP / DOWN in the field call `field.kitList:MoveSelection(-1 / 1)`,
  and Enter calls `field.kitList:Activate()`. A List given `search = field` sets both.
- **Windows** (Chrome to all): `ui:Window(spec)` and `ui:Panel(spec)` answer a frame with `kitIsWindow = true`. What
  is made on it goes in its body (`kitInner`), and a fill type (a column, panes, tabs, a scroll area) made straight
  on it fills it (`kitFillChildren`). `win:Status(text, { undo = fn })`, `win:TakeKeyboard(on)`,
  `win:TabOrder(list)`, `win:Toggle()`.

## Tests

`nix-shell -p lua5_1 --run "lua Tests/TestRunner.lua"` from `NuuKit/` runs everything; the kit's parts alone are
`lua Tests/UI/Smoke/Run.lua [Part ...] [--copy]` (`--copy`: methods copied onto frames, the path a client that
refuses frames a metatable takes). Each part is `Tests/UI/Smoke/<Part>.lua` and builds what it checks in
`ctx.testWindow(ui, w, h)`. Cover every widget, its methods and callbacks, and a clear-and-rebuild from the pool with
different specs (see `Pooling.lua`).

A change to the kit keeps its measured cost: compare the client calls of `lua Tests/Bench/Run.lua UI` (the bench
screen) and `lua Tests/Bench/Gallery.lua` (the whole gallery) before and after; in the client, `/nuukit report`.
