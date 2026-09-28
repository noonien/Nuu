# UI-Test1

The kit's widgets rebuilt on the architecture the bench chose (`Tests/Bench/`, "B + pooling"): shared methods,
colour-only hover, colours and fonts worked out once per look, cached measurements, a layout pass that stops where
sizes stop changing, placement that skips edges that did not move, and a pool per widget type. It loads beside `UI/`
under `Kit.UI1` / `Kit.NewUI1`, so both can be compared in the client (`/nuukit ui` and `/nuukit ui1`).
Development only for now.

Read `Base/Core.lua` (the widget model) and `Base/Layout.lua` (stacks and the pass) first; `Base/Text.lua` and
`Controls/Buttons.lua` are the reference widgets.

## Porting a file from UI/

Port every widget and every behaviour of the old file; keep its comments' voice (plain English, what and why), ASCII
only, sentence-case captions. Keep a behaviour unless it conflicts with the rules below, and say so in a comment when
it changes.

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
  spec are stored as fields (`w.kitOnChange = spec.onChange`).
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
- **Sub-parts** a widget is built from (a section's reset link, a field's glyph button) are made with
  `UI.Make(ui, "Link", parent, spec)` in Build (or lazily in Init) and belong to the widget for good; a part placed by
  hand is sized with `UI.Fit(part)`. A widget that holds a stack for the addon's widgets sets `holds = true` and
  `w.kitInner = stack` (see Card, Section).
- **Internal stacks**: `UI.MakeStack(ui, frame, "row" | "column", opts)`; `stack:Append(part)`.
- **Pixels**: `UI.Snap`, `UI.Pixels`, `UI.Hairline`, `UI.Stroke`, as before.
- **Focus**: `focusable = true` (or `"field"`) in the def; an inner EditBox registers with
  `UI.RegisterFocusable(ui, box, true)` in Init. `kitKeyArrow` / `kitKeyPress` as before. `UI.FocusOrder`,
  `UI.NextFocus`, `UI.FocusWidget`, `UI.WindowKey` are in `Base/Focus.lua`.
- **Shared helpers already in Base**: `UI.NewScroll(ui, parent)` and `UI.NewScrollBar(ui, parent, source, step)`
  (`Base/Scroll.lua`), `UI.DragFrame` (`Base/Drag.lua`), plates, 9-slices, tiles, glyphs (`Base/Draw.lua`),
  tooltips (`Base/Tooltip.lua`), `UI.WireButton` / `UI.ClickableType` / `UI.InitClickable` (`Controls/Buttons.lua`).

## The API, changed from UI/

| UI/ | UI-Test1 |
| --- | --- |
| `col:Button("Save", { tone = "accent" })` | `col:Button{ "Save", tone = "accent" }`: one spec table; its `[1]` is the caption, text, kind or list |
| `ui:Button(parent, "Save", opts)` | `ui:Button(parent, { "Save", ... })` |
| `col:Text("Hi", "title", { wrap = true })` | `col:Text{ "Hi", style = "title", wrap = true }`; `col:Text"Hi"` also works |
| `col:Toggle("Sell back", opts)`, `col:Section("Route", opts)`, `col:Tag("3", opts)`, `col:Notice(text, opts)` | `[1]` is the caption or text |
| `col:GlyphButton("close", opts)` | `col:GlyphButton{ "close", ... }` |
| `col:Tabs(entries, opts)` | `col:Tabs{ entry, entry, ..., value = "plan", onChange = fn }`: the entries are the array part |
| `col:Choices(list, opts)`, `col:Figures(list)`, `win:SplitPanes(panes, opts)` | the list is the array part of the spec |
| `section:LookPicker(look, fn)` | `section:LookPicker{ look = db.look, onChange = fn }` |
| `SetValue(v, silent)`; some setters called onChange | Code never calls `onChange`. `SetValue(v)` from code is always silent; `onChange(value, widget)` is only for the player's changes |
| `Input` `GetText` / `SetText`, `onCommit(text)` | also `GetValue` / `SetValue`; `onChange(text, w)` on commit, `onType(text, w)` live |
| `Tabs:Select(key)` | also `Tabs:SetValue(key)` / `GetValue()` |
| `button.kitClick = fn` (gallery) | `button:SetOnClick(fn)` |
| a part's size in `height` (TextArea box, ProgressBar bar, SegmentBar bar) | `boxHeight`, `barHeight`: `width`, `height`, `grow`, `minWidth`, `minHeight`, `align`, `valign`, `stretch` are layout only |
| `width` of a select's button, a MoneyInput's or NumberInput's box | `boxWidth`; `width` is the whole widget's |
| List / Tree / Table `Select(item)` called onPick; Pager `SetAt` called onChange | from code they are silent; clicks and keys call them |
| `win:Toggle()`, `tabs:Select(key)` | still show/hide and select; with a spec table (`win:Toggle{...}`, `tabs:Select{...}`) they make a toggle or a select |
| Disclosure `onToggle(open)`, window collapse | `onToggle(open, w)`; new `onCollapse(collapsed, win)`, both only for the player's clicks |
| `kitStretch`, `kitRowStretch`, `kitRowAlign` flags | the def's `stretch`, the spec's `stretch` / `valign` |
| nothing | `bind = { table, key }` on value widgets (below) |

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

`nix-shell -p lua5_1 --run "lua Tests/UI1/Run.lua"`, from `NuuKit/`, runs every part whose files exist. Named parts
(`... Run.lua Fields`) load only the core (`Base/`, Text, Buttons) and those parts' own files, so another file
half-written does not stop them; a part checks `ctx.loaded[file]` before using a widget from a file outside its own,
and `ctx.testWindow` falls back to a plain column while `Chrome/Window.lua` is not loaded.
Each part is `Tests/UI1/Smoke/<Part>.lua` and builds what it checks in `ctx.testWindow(ui, w, h)`. Cover every widget,
its methods, its callbacks, and at least one clear-and-rebuild from the pool with different specs (see `Pooling.lua`).
`Tests/UI/Smoke/` has the old kit's checks, to carry over.
