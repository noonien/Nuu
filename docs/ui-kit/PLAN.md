# NuuKit UI kit: implementation plan

The UI kit is the part of NuuKit that draws things: widgets, themes, window chrome, and the states between them. It
is ported from OpenRoad's `UI/Theme.lua`, reshaped so the look can change while windows are open and so an addon
can build a window in a few lines. Mockups: see [README.md](README.md).

## Scope

The kit ships reusable parts only. NuuRoad and NuuProfessions build their own screens from them.

| The kit ships | The addons build |
| --- | --- |
| themes, accents, art textures, window chrome | the tracker, guide browser, editor (NuuRoad) |
| windows: move, resize, collapse, Escape, placement | the planner and its tabs (NuuProfessions) |
| layout (column, row), sections, tabs | each addon's options window |
| buttons, fields, toggles, sliders, menus, selects | the bug report form |
| lists, tree, split panes, scroll areas, slots | anything that knows about guides, quests or recipes |
| tooltips, progress bars, notices, empty / loading / error states | |
| the look picker (theme, accent, chrome), the focus ring | |

The kit holds no settings. An addon passes in its own tables and callbacks (the look, window positions), and the
kit reads and writes only what it is handed.

## Easy to use: the rules

1. **One object per addon.** `ns.UI = ns.Kit.NewUI(ns, look)` in `Core.lua`, once. Everything else hangs off it.
2. **One call per widget.** Positional arguments only for what every call needs (the caption); everything else is
   an options table with defaults, so the common case is one short line.
3. **Containers place what they make.** `col:Button("Save")` creates the button in `col` and stacks it. No
   `SetPoint` for ordinary layouts; `UI:Button(parent, "Save")` and `SetPoint` still work for anything custom.
4. **Plain frames.** A widget is a WoW frame with a few added methods. No classes, mixins, XML, templates, or
   registration calls to learn.
5. **Theme changes cost the addon nothing.** Every widget repaints itself when the look changes.
6. **The same callback names everywhere.** `onClick()` for actions, `onChange(value)` for anything with a value,
   `onPick(item)` for lists and menus.
7. **Fail soft.** A missing texture or client API gives the flat look or a plain fallback, never an error.
8. **OpenRoad names where they exist**, so ports from OpenRoad are mostly mechanical.

`NuuKit/UI/examples.lua` shows the API in use, one example per area. Beyond the sections below it settles:

- `UI:Paint(frame, fn)`: something the addon draws itself joins the repaint; `fn(tokens)` runs now and after every
  look change.
- Fields in a window join its Tab order in the order they are made; `win:TabOrder(list)` only overrides it.
- `container:SetState("loading" | "empty" | "error", text, opts)` on any container, `SetState(nil)` to go back, so
  states need no widgets of their own.
- `List` takes `search = field`: it filters as the player types, and the arrow keys and Enter work from the field.
- `win:Status(text, { undo = fn })` for the strip at the foot of a window. A window made with `status = true` (or
  a hint string) keeps the strip always, so its body never resizes when a message comes or goes; the client redraws
  what scrolls in a resized body, and its edges can come out a pixel different.
- `tone` takes a colour as well as a name; `hold = seconds` makes a button hold-to-confirm.
- `Kit.FormatMoney(copper)` and `Kit.ParseMoney(text)`, ported from OpenRoad's `Prices`.

## What using it looks like

```lua
-- NuuRoad/Core.lua: once. `look` is NuuRoad's own saved table, or nil for the defaults.
ns.UI = ns.Kit.NewUI(ns, NuuRoadDB.look)

-- A whole window.
local UI = ns.UI
local win = UI:Window({ key = "browser", title = "Choose a guide", width = 520, height = 560,
    place = NuuRoadDB.windows, resizable = true })

local body = win:Column({ gap = 8 })
body:Search({ placeholder = "Search guides", onChange = Filter })
local list = body:List({ grow = true, rowHeight = 30, draw = DrawGuideRow, onPick = PickGuide })

local buttons = body:Row({ align = "right" })
buttons:Button("Cancel", { onClick = function() win:Hide() end })
buttons:Button("Start guide", { tone = "accent", onClick = StartGuide })

list:SetItems(guides)

-- The options window's Appearance section: the picker reports a change, the addon keeps it.
section:LookPicker(NuuRoadDB.look, function(look)
    NuuRoadDB.look = look
    ns.UI:SetLook(look)  -- every open NuuRoad window repaints
end)
```

## How it works

### One UI per addon

`Kit.NewUI(ns, look)` returns a table holding that addon's look, its computed tokens, and a weak-keyed list of the
widgets it made. In development both addons share one kit but each gets its own UI, so NuuRoad and NuuProfessions
can wear different looks. Constructors live on the UI (`UI:Button(parent, ...)`) and on every container
(`col:Button(...)`), which passes itself as the parent and stacks the result.

### Looks, themes and tokens

- A **look** is the addon's choice: `{ theme = "midnight", accent = nil, opacity = 1, textSize = "normal",
  reduceMotion = false }`. A missing field takes the default. `accent = nil` means the theme's own accent.
- A **theme** is data in `UI/Theme/Themes.lua`: the planes (window, band, hairline, surface, raised, border), text and
  muted colours, the default accent, and for an art theme its textures. Built in: Midnight (OpenRoad's look),
  Slate, Obsidian, Horde, Alliance. `Kit.UI.AddTheme(key, def)` adds more. Every theme is dark: pale text with a
  hard shadow on dark planes. Light themes were dropped with Parchment, since the colour choices do not hold on a
  light window; supporting one again means a second set of status, coin and accent colours.
- **Tokens** are the colours widgets paint with, computed once per look change by `UI/Theme/Look.lua`: the planes with
  the opacity applied; the accent plus its derived text, fill, hover fill, wash and 65 / 80 % edges; the status
  colours (danger, done, warning, gain, estimate, pattern) and coin colours. The formulas are the mockups' `makeTokens`. `Look.lua` is pure Lua and
  never touches a frame, so it is unit-tested.
- The status colours never follow the accent.

### Painting

Each widget has one `Paint(t)` that sets every colour from the tokens `t`, plus its own state (hover, pressed,
active, disabled). Creating a widget registers it and paints it once; a state change calls `widget:Repaint()`.
`UI:SetLook(look)` recomputes the tokens and repaints every registered widget. Widgets never keep a colour from
creation, which is why OpenRoad cannot switch themes live (its surfaces, glows and a hardcoded hover blue are set
once).

### Windows and chrome

`UI:Window(opts)` makes a movable, clamped window with a title band, a close button (a bright X in an outlined
square, the textured plate on hover), optional resize grip and collapse, and Escape to close (`UISpecialFrames`,
as OpenRoad's `CloseOnEscape`). With `place` and `key` its position and size go into `place[key]`.

- **Flat chrome:** a backdrop in the theme's colours.
- **Art chrome:** the theme's textures, each optional: a tiled background (`SetTexture(file, "REPEAT", "REPEAT")`
  with `SetHorizTile` / `SetVertTile`), a 9-slice frame drawn by the kit's own `NineSlice` (8 textures plus a
  centre, cut with `SetTexCoord`, so corners keep their size and edges stretch), a header band, and button plates.
  Any texture that does not load falls back to the flat piece, checked the way OpenRoad's `loadTexture` does.
- **In-play frames** (`UI:Panel({ inPlay = true })`, used for the tracker and the target strip) are always flat and
  translucent, with the text shadow, and follow the look's opacity.

### Layout

`Column` and `Row` stack their children with a gap and padding, align them, and hand spare room to children marked
`grow`. Hidden children take no space. They lay out again when their size changes. Anything else uses `SetPoint`
directly.

### Text

`UI:Text(parent, text, style)` with the styles from the type board: `title`, `window`, `heading`, `body`, `label`,
`link`, `fine`, `number`, `key`. The faces come from the client's own font objects (`GameFontNormal`,
`NumberFontNormal`, falling back to `Fonts\FRIZQT__.TTF` and `Fonts\ARIALN.TTF`), the sizes from the look's
`textSize`. Game fonts have one weight, so the hierarchy is size and colour. Sentence case only, ASCII only.

### Motion

`widget:Attract("breathe" | "pulse" | "shimmer" | "flash" | "trail")` and `widget:Attract(nil)`. Breathe,
shimmer and flash are built on `CreateAnimationGroup`; pulse (a 1 pixel ring leaving the edge) and trail (dashes
marching round the edge) are drawn by hand in `OnUpdate`, since a Scale animation thickens and blurs a 1 pixel
line. Kinds combine as a list, `widget:Attract({ "trail", "breathe" })`; breathe and flash share one wash, so a
list keeps the first of the two. One attracting widget per window; the look's `reduceMotion` turns them all off, the trail's dashes standing
still. Without animation groups a widget shows a still highlight instead.

### Keyboard focus

By default focus follows text fields: Tab and Shift-Tab (OpenRoad's `TabChain`), Enter commits, Escape gives the
keys back to the game, and arrow keys move through a list while its search field has focus. A window can opt in to
full keyboard control (`win:TakeKeyboard(true)`); that window holds the keyboard, so the game's keybinds stop while
it is open. The focus ring is the kit's: a gap, then an accent line.

### Tooltips

`UI:Tooltip(owner, filler, opts)` keeps OpenRoad's behaviour: Blizzard's `GameTooltip`, with the game's item or
recipe tooltip chained under it. A themed tooltip is an open question (below); the call stays the same whichever way
it goes.

## Files

All under `NuuKit/`, added to `NuuKit.toc` in this order, before `NuuKit.lua`.

| File | Holds |
| --- | --- |
| `UI/Theme/Themes.lua` | theme data, `Kit.UI.AddTheme` |
| `UI/Theme/Look.lua` | colour maths and tokens; money parse and format (pure Lua) |
| `UI/Base/UI.lua` | `Kit.NewUI`, the widget list, `SetLook`, shared bits (click sound, focus clearing, texture loading) |
| `UI/Base/Layout.lua` | `Column`, `Row` |
| `UI/Base/Text.lua` | text styles, `Section`, `Tag`, `Notice`, `Card` |
| `UI/Chrome/Window.lua` | `Window`, `Panel`, `NineSlice`, chrome, move / resize / collapse / place / Escape |
| `UI/Controls/Buttons.lua` | `Button` (tones and styles), `GlyphButton`, `ResetButton`, `ConfirmButton`, `Attract` |
| `UI/Controls/Fields.lua` | `Input`, `Search`, `TextArea`, `MoneyInput`, `NumberInput`, `Toggle`, `Slider`, `TabChain` |
| `UI/Chrome/Tabs.lua` | `Tabs`, `Disclosure` |
| `UI/Controls/Menus.lua` | the one menu frame; `Select`, `SearchSelect`, `MultiSelect`, context menus, submenus |
| `UI/Display/Lists.lua` | `ScrollArea`, `List`, `Tree`, `SplitPanes` |
| `UI/Display/Feedback.lua` | `ProgressBar`, `SegmentBar`, `EmptyState`, `Loading`, `ErrorState`, `StatusStrip` (with Undo) |
| `UI/Display/Tables.lua` | `Table`, `Pager`, `Figures` |
| `UI/Controls/Forms.lua` | `Setting`, `Choices` |
| `UI/Display/Slots.lua` | `StripPanel`, `Slot` (quality edge, count, key hint, quest mark, raid marker, cooldown) |
| `UI/Base/Tooltip.lua` | `Tooltip`, `HideTooltip` |
| `UI/Theme/LookPicker.lua` | the Appearance picker (theme cards, accent swatches, class colour, chrome, opacity) |
| `Media/<theme>/*.tga` | art textures |
| `Tools/Textures.py` | the texture generator (moved from `docs/ui-kit/mockups/textures/gen.py`), writing TGA |
| `Dev/Gallery.lua` | development only, never shipped: every widget in every state, for checking in game |

`Dev/Gallery.lua` opens from a developer-only `/nuukit ui` command, alongside the other diagnostics.

## Phases

Each phase ends with something visible in the gallery. Where it helps, one addon uses it straight away, and the
client results go into the API compatibility record.

1. **Look and paint.** `Themes`, `Look`, `UI`, `Text`, and a gallery that shows the text styles on a flat panel.
   Unit tests for the tokens. In game: `SetLook` switches the gallery between all four flat themes and any accent
   with the window open.
2. **Windows, layout, buttons.** `Window` (flat chrome), `Panel`, `Column` / `Row`, `Section`, `Tabs`, `Disclosure`,
   `Button` with all tones and styles, `GlyphButton`, `ResetButton`, `ConfirmButton`. NuuRoad and NuuProfessions
   each open an empty options window built with them.
3. **Fields and menus.** `Input`, `Search`, `NumberInput`, `MoneyInput`, `Toggle`, `Slider`, `TabChain`, the menu
   frame and every select, and `LookPicker`. Both options windows get their Appearance section, so looks are
   chosen and saved by the addons from here on.
4. **Lists and text.** `ScrollArea`, `List` (rows sized once and reused, hover / selected / disabled, empty
   state), `Tree`, `SplitPanes`, `TextArea`, `Tooltip`, focus with list arrow keys, and opt-in keyboard windows.
5. **Feedback and slots.** `ProgressBar`, notices, loading and error states, `StatusStrip`, `Attract` and the
   animations, `StripPanel`, `Slot`.
6. **Art themes.** `Tools/Textures.py` writes TGA into `Media/`, then `NineSlice`, tiled backgrounds, bands, plates,
   the Horde and Alliance themes, and the flat fallback for every piece.

## From OpenRoad's `UI/Theme.lua`

| OpenRoad | Kit | Change |
| --- | --- | --- |
| `Theme.colors`, `fontSizes` | `Themes.lua`, `Look.lua`, text styles | per-look tokens; art themes |
| `Surface`, `Text` | `Panel`, `UI:Text` | repaints; named text styles |
| `Button(parent, caption, width, primary, tooltip)` | `Button(caption, opts)` | tones x styles; `primary` becomes `tone = "accent"` |
| `GlyphButton`, `ResetButton`, `ConfirmButton` | same names | glow built from tokens, not captured at creation |
| `Toggle`, `DropButton`, `Select` | same names | `onChange(value)` |
| `Input`, `TabChain`, `ClearFocusOnClick` | `Input`, `TabChain`, built into `Window` | commit behaviour kept |
| `ScrollFrame` | `ScrollArea` | same slim bar |
| `Slider` | `Slider` | |
| `Menu`, `OpenMenu`, `CloseMenu` | `Menus.lua` | adds submenus, search, multi-select, headers; one frame per UI |
| `Disclosure` | `Disclosure`, `Section` | `Section` is the folding header with a rule |
| `StripPanel(key, rail)` | `StripPanel(opts)` | placement from `place`, not `ns.modules.Config` |
| `SlotChrome`, `ShortKey` | `Slot`, text style `key` | |
| `Tooltip`, `HideTooltip`, `CloseOnEscape` | same, `CloseOnEscape` built into `Window` | |

Captions follow the kit's rule: sentence case, never all capitals (OpenRoad's START and SAVE are not ported as
written).

## Testing

- **Unit tests** (`Tests/`, run by `Tests/TestRunner.lua` under Lua 5.1): tokens for every theme and a sample of
  accents (derived colours, light-theme darkening, opacity), art falling back to flat when a theme has no
  texture, money parsing and formatting (no zero coins: `96s`, not `0g 96s`), and the layout sums for `Column` and
  `Row`.
- **In game:** the gallery, phase by phase. Each client API the kit relies on (tiled textures, `SetTexCoord`
  9-slices, animation groups, `EnableKeyboard` with `SetPropagateKeyboardInput`, cooldown frames, TGA loading)
  gets a row in a Nuu `docs/api-compatibility.md` with build, date and fallback, the way OpenRoad keeps its own.

## Open questions

1. **Where the kit sits in a release.** Texture paths are `Interface\AddOns\<addon>\<kit folder>\Media\...`. In
   development that is `NuuKit`. `Kit.lua` should set the root once from the loading addon's name, but the folder
   an embedded kit lives in is not decided.
2. **One look or two.** Each addon keeps its own look. Should NuuProfessions offer "use NuuRoad's look"
   (`_G.NuuRoad.UI:GetLook()` when NuuRoad is loaded), or should the two share one choice?
3. **Accent clashes.** Gold is close to warning amber, Rose and the Paladin colour to the pattern pink, Ember to
   orange difficulty. Drop those accents, or shift the status colours when one is picked?
4. **Themed tooltips.** Keep Blizzard's tooltip (it matches the chained item tooltip), or theme ours and leave the
   chained one as Blizzard's?
5. **Texture format.** TGA (uncompressed, as OpenRoad's arrow notes suggest) unless the client takes BLP; the
   Forever client's PNG support is unknown.
