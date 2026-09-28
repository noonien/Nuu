# NuuKit UI kit

- **Mockups:** <https://claude.ai/artifact/2b8Q697XdKeYNaHMsn96QX> (a design canvas, pinned in the claude.ai sidebar)
- **Plan:** [PLAN.md](PLAN.md)
- **Status and next steps:** [NuuKit/UI/status.md](../../NuuKit/UI/status.md); the API in use:
  [NuuKit/UI/examples.lua](../../NuuKit/UI/examples.lua); in game, `/nuukit ui` opens the widget gallery

## Reading the mockups

Boards named `Kit:` (green tags) are what NuuKit ships: widgets, themes, textures, window handling, states.
Boards named `Example:` (cream tags) are windows NuuRoad and NuuProfessions build themselves from kit parts; the kit
does not ship them. Everything is drawn at 1.25x game pixels (body text 11 -> 14 px). Most boards take a theme
(and accent) from their Tweaks; the first board's Appearance panel is live.

| Board | What it shows |
| --- | --- |
| Kit widgets + example: NuuRoad options (live) | theme / accent / chrome / opacity picker, every basic control in its states, a small tracker |
| Example: NuuRoad tracker | title bar, progress, current step, step list, target strip |
| Kit: button tones and attention | 7 tones x 5 styles, 8 attention animations |
| Kit: menus and dropdowns (live select) | select, searchable select, context menu + submenu, multi-select, title-bar menu |
| Example: NuuProfessions planner | header, tabs, sections, route table, summary, status strip |
| Kit: theme tokens | every colour token for every flat theme |
| Kit: art themes (on an example window) | Horde and Alliance drawn with textures |
| Kit: lists, text, tooltips, slots, window handling | list + scrollbar, empty state, multi-line fields, tooltip choice, item slots, move/resize/collapse |
| Kit: tree, panes, fields, progress, notices, states | folder tree, split panes, money and number fields, bars, notices, loading and error states |
| Kit: type and keyboard focus | type scale mapped to client fonts, the focus ring and its default / opt-in scope |

## Source copy

`mockups/boards/` holds the canvas source (`canvas.json` and one `.dc.html` per board) in case the link is lost;
the files render only inside the canvas, not as plain HTML. `mockups/textures/` holds the mockups' PNG textures
and the first version of their script; the kit's own generator is `NuuKit/Tools/Textures.py`, which writes TGA
into `NuuKit/Media/`. The link is the source of truth; refresh this copy after changing the canvas.
