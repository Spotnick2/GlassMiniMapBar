# Glass MiniMap Bar public API

For other addons that want the bar to open from their own button, or match their glass. First
consumer: **Glass MiniMap** (its bottom-left disc on the glass minimap ring). Code: `PublicAPI.lua`.

## Stability

- `GlassMiniMapBar.PUBLIC_API_VERSION` changes on **any incompatible change** (a function's
  arguments or meaning, a removal). Adding a function doesn't change it. Check it before calling:

  ```lua
  local gmb = rawget(_G, "GlassMiniMapBar")
  if gmb and gmb.PUBLIC_API_VERSION == 1 then ... end
  ```
- Add `## OptionalDeps: GlassMiniMapBar` to your TOC so Glass MiniMap Bar loads first. Calls are
  safe from your file scope, `ADDON_LOADED` or `PLAYER_LOGIN`, before or after Glass MiniMap Bar
  builds its bar.
- `GlassMiniMapBar.API` is NOT this: it's the internal client adapter.
- Nothing here hands out a live table; your callbacks run under `pcall` (`/gmb failures` lists
  their errors).

## Version 1

### `GlassMiniMapBar.UseLauncher(frame, opts) -> ok, why`
The bar opens from `frame` (your button) instead of our minimap button, which stays hidden for as
long as yours is attached. That's never saved: the player's own choice comes back on release, or
next session without you. The bar opens toward the middle of the screen from wherever `frame` is
(or the player's direction setting). Your button's look stays yours.

`opts.setIcon(icon, coords)` (optional) is called whenever the launcher's face changes: the last
button used (when the player turned that option on) or the arrow toward the bar. `icon` is a file
path, a file ID or an atlas name (an AddOns-list entry may use one: check
`C_Texture.GetAtlasInfo(icon)` and use `SetAtlas`); `coords` is nil or `{ left, right, top, bottom }`.

Returns `false, why` when `frame` isn't a frame.

### `GlassMiniMapBar.LauncherClick(frame, mouse)`, `LauncherEnter(frame)`, `LauncherLeave(frame)`
Call these from your button's `OnClick`, `OnEnter` and `OnLeave` (we never hook your frame).
They're ignored unless `frame` is the one passed to `UseLauncher`. Click: left toggles the bar,
right repeats the last button or opens our options, shift-right or middle opens our options.
Enter opens the bar in hover mode and shows our tooltip.

```lua
disc:RegisterForClicks("AnyUp")
disc:SetScript("OnClick", function(self, mouse) GlassMiniMapBar.LauncherClick(self, mouse) end)
disc:SetScript("OnEnter", function(self) GlassMiniMapBar.LauncherEnter(self) end)
disc:SetScript("OnLeave", function(self) GlassMiniMapBar.LauncherLeave(self) end)
GlassMiniMapBar.UseLauncher(disc, { setIcon = function(icon, coords) ... end })
```

### `GlassMiniMapBar.ReleaseLauncher()`
Back to our own minimap button (shown again unless the player hid it).

### `GlassMiniMapBar.SetGlassTint(r, g, b, a, wash) -> ok`
The body tint of the bar and its round buttons, so they follow your theme. `r, g, b` in 0..1;
`a` nil keeps each surface's own alpha; `wash` multiplies the built top-down wash (1 = as built,
0..2). No arguments: the look as built. Remembered before the bar exists and applied to buttons
that arrive later. `false` for values out of range. While `FollowsSuite()` is true the colours
are kept but not painted: Glass UI's look is on the bar.

### `GlassMiniMapBar.FollowsSuite() -> bool`
True while we follow Glass UI's suite look: its tint and wash are on the bar and the round
buttons. A host that themes us through `SetGlassTint` stops calling it while this is true, so the
bar has one driver (Glass MiniMap reads it with `rawget` and calls it under `pcall` before each
`SetGlassTint`). Decided once per session, at our `ADDON_LOADED`, so it is settled before any
`PLAYER_LOGIN`; it changes only after a `/reload`. Added within version 1.

### `GlassMiniMapBar.OpenOptions()`
Opens our page in Options > AddOns.

## Not in the API

The bar's layout, its settings, the button lists and the collector are internal and may change
in any release.
