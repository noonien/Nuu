# Testing UI-Test1 in the client

UI-Test1 loads beside UI/, so both galleries open side by side:

- `/nuukit ui`: the current kit
- `/nuukit ui1`: UI-Test1

Everything in `docs/api-compatibility.md` applies to both (Line glyphs, TGA art, Translation animations, clipping,
EditBox growth). What follows is only what is new in UI-Test1. Note the build and date with what you find.

## 1. It loads and looks the same

1. `/reload`, then `/nuukit ui1`. No Lua error on load or on open (with `/console scriptErrors 1`).
2. Open `/nuukit ui` too and put the two side by side. Every tab should match: sizes, gaps, colours, fonts, art.
   A difference is a porting bug; note the tab, the widget and what differs.
3. Change the theme on the Look tab of each: every theme, an accent, the class colour, opacity, large text, less
   motion. Everything should repaint, and large text should make everything taller without anything overlapping.

## 2. Hover and state are colours only

1. Hover every kind of button, a section heading, list rows, theme cards and menu items. Each should light up at
   once, with no flicker, no jump in width and no one-frame shift.
2. Resize the window by its grip. The layout should follow smoothly, with nothing a pixel off at the edges.
3. Tables tab: change a Price used cell and a Get it select. Only that row should move; the rest of the table
   should stay still.

## 3. Pooling

1. Pooling tab: its second line says how widgets get their methods. "Shared through metatables" is the design.
   "Copied onto each frame" means this client refused `setmetatable` on a frame; everything still works, but uses
   more memory. Note which one you see.
2. Pooling tab: press Rebuild a few times. After the first build, the line should say `0 made`, with every widget
   taken from the pools.
3. Press Rebuild 20 times. There should be no stutter beyond the first build, and `0 made` in all.
4. Check that the rebuilt rows are fresh: new captions and tones, no row stuck in hover, and each button's click
   reporting its own round in the status line.

## 4. Memory and speed, against UI/

With only the gallery windows open:

1. `/run UpdateAddOnMemoryUsage() print(GetAddOnMemoryUsage("NuuKit"))`. Note it.
2. Open `/nuukit ui` and visit every tab, then run the line in step 1 again.
3. `/reload`, then do the same with `/nuukit ui1`.
4. Pooling tab: Rebuild 20 times, then measure again. The number should barely move. The tab's own line also gives
   the Lua memory each rebuild took.

## 5. Keyboard and focus

In play tab, Full keyboard:

- Tab should reach buttons, toggles, tabs, selects and sliders, with the ring following.
- Enter and Space should press, and the arrows should move sliders and lists.
- Escape should close the window.

Without full keyboard, Tab should move through the text fields only.

## What to send back

For each section: pass, or what went wrong (tab, widget, what you did, what you saw, any Lua error text). The
memory numbers from section 4.
