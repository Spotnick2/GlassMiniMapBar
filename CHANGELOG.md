# Glass MiniMap Bar Changelog

## v1.0.1 - 2026-10-04

### Fixed

- **No more "measured on …" line in chat at every login.** On a newer game client, the addon
  announced which build it was tested on each time you logged in. Players never needed that; it
  is gone.

### Under the hood

- The glass look now comes from LibGlass, a small library shared by the Glass
  addons and included in the download (nothing extra to install). The bar and the buttons look
  and behave exactly as before; a future fix to the glass reaches every Glass addon you use.

## v1.0.0 - 2026-09-27

First release, for World of Warcraft: Forever (client 1.60.1).

**If you want more, use [HidingBar](https://www.curseforge.com/wow/addons/hidingbar)**: this is a
small, streamlined take on it.

### Read this if you use HidingBar

- **Disable HidingBar (and HidingBar_Options) first.** Both collect the same minimap buttons and
  would fight over them.

### Added

- **Your addons' minimap buttons, gathered into one liquid-glass bar** that grows out of a glass
  launcher on the minimap ring. Hover the launcher to open it (or set it to open on click); it
  closes by itself when the mouse leaves, and stays open while you're in a menu one of its buttons
  opened.
- **A round glass skin** on every collected button, matching the bar. It can be turned off.
- **Hide and order the buttons** in Options → AddOns → Glass MiniMap Bar: move buttons between
  Hidden and Shown in bar, and set their place with Up / Down.
- **Last used** (optional): the launcher shows the last button you used, and right-clicking the
  launcher uses it again.
- The bar opens toward the middle of the screen from wherever the launcher sits, and can wrap into
  rows or columns. Direction, buttons per row, button size and the closing delay are all options.
- `/gmb` opens the options; `/gmb scan` lists what was collected and what was skipped.
