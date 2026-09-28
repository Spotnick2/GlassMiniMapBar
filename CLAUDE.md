# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

GlassMiniMapBar is a **minimap button collector for World of Warcraft: Forever 1.60.1** (Interface
`16001`), written in **Lua 5.1**. It's a single-owner project (Spotnick), on the same stack and
conventions as the sibling Forever addons `..\GlassUnitFrames`, `..\GlassXp` (GlassPanel),
`..\AltStable` and `..\Priestly`. When this file doesn't cover something, check how those handle
it before you invent a new idiom.

**Goal:** a streamlined, liquid-glass replacement for the owner's **HidingBar** setup
(`C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\HidingBar`, by sfmict,
**GPLv3**, so this addon is GPLv3 too and may adapt its code). The owner used one HidingBar
feature: one bar that pops out from its own minimap button on hover, holding every addon's
minimap button. So we keep only that:
- a **launcher**: our own LibDBIcon button on the minimap ring, wearing the glass orb;
- a **glass bar** (the GlassUnitFrames material) beside it, holding the collected buttons;
- **Options > AddOns** panel: a dual list box (Hidden | Shown in bar, arrows, Up/Down for
  the order), hover or click, layout, skin;
- optional **last used**: the launcher wears the last button clicked, and right-click repeats it.

Not ported, on purpose: multiple bars, profiles, free-floating bars, Masque, LibDataBroker
launchers as bar buttons, grabbing Blizzard's default minimap buttons, manual grab lists, the
drag-to-reorder UI, locales. Order is the user's (Up/Down in the options), then alphabetical.

**Status: first version, running in game** (collection, skin and layout confirmed on 70009).
The rest of the in-game checklist under "Unmeasured" is still open.

## Layout

TOC load order: `Libs\*` → `Compat.lua` → `Glass.lua` → `Orb.lua` → `Collector.lua` → `Bar.lua` →
`Options.lua` → `GlassMiniMapBar.lua`.

- **`Libs\`**: LibStub, CallbackHandler-1.0, LibDataBroker-1.1, LibDBIcon-1.0 (MINOR 56), copied
  from HidingBar and listed file by file in the TOC (no XML, so deploy copies exactly the TOC).
  Other addons embed their own copies; LibStub keeps the newest. The libs are embedded because
  LibDBIcon is both how the launcher lives on the ring and how we hear about new buttons.
- **`Compat.lua`**: `GlassMiniMapBar.API`: `Print`, `IsSecret`, `Fail` / `Try` (**the one failure
  recorder**, `GlassMiniMapBar.failures`, read by `/gmb failures`), `RegisterEvent` (reports
  throws and refusals), `W` (the real widget methods, see Collector), `IsBlizzardGlobal`
  (`issecurevariable`, *unmeasured*, reported by `/gmb scan` only), the Settings calls, and
  `MouseOverMenu` (UIDropDownMenu lists, LibUIDropDownMenu lists, the Retail `Menu` manager).
  `MEASURED_ON_BUILD` lives here.
- **`Glass.lua`**: the material, **copied** from GlassUnitFrames' **`main`** branch
  (`git -C ..\GlassUnitFrames show main:Glass.lua`) with only the namespace lines and header
  changed. `test_toc.lua` fails when the two drift, and the same for `Tools\make_textures.py`.
  Change the material in GlassUnitFrames first (with its `docs/GLASS-MATERIAL.md`), then copy it
  back. `Media\` holds copies of its textures.
- **`Orb.lua`**: the glass material on a circle, for round buttons (the launcher, and the
  collected buttons when the skin option is on). It's a masked tint + wash behind the icon, the
  icon enlarged to 70% and masked round, and `orb_dark` + `orb_rim` over it. It only **adds**
  regions and sets the button's gold ring and dark disc to alpha 0; `Unskin` restores both and the
  icon's size, points and mask. It never touches icon texcoords: LibDBIcon's `updateCoord` owns
  them. Skin state lives in a weak table keyed by button, never as fields on their frame.
  Textures come from **`Tools\make_orb_textures.py`** (ours), which imports the copied
  generator's primitives.
- **`Collector.lua`**: finds and takes the buttons (HidingBar's technique, streamlined):
  - A candidate is a **named**, unprotected, non-forbidden child of `Minimap` or
    `MinimapBackdrop`, square within 5 px, larger than 16 px, smaller than half the minimap, with
    an `OnClick`/`OnMouseUp`/`OnMouseDown` script on itself or a descendant. Blizzard names are
    skipped by the `IGNORE` list (HidingBar's Retail + Vanilla lists), plus patterns (GatherMate
    pins, our launcher, HidingBar's own buttons).
  - Sources: a scan at login, after 0, 2 and 10 s, and on **every bar open**; LibDBIcon's
    `LibDBIcon_IconCreated` callback; and `lib.objects` at startup for icons made before us.
  - **Grabbing** replaces `SetPoint`, `SetParent`, `SetScale`, `SetAlpha`, `SetSize`,
    `RegisterForDrag`, … on the button's **own table** with no-ops, so the owner (LibDBIcon moves
    its buttons on login and on drag) can't pull it back. The bar moves it through **`API.W`**, the
    Frame metatable's methods. `Show`/`Hide`/`SetShown`/`IsShown` record `entry.wanted` and
    schedule a relayout **for the next frame** (`Collector.Changed`, under `API.Try`): never do
    our work inside another addon's call, where a throw would surface in their code. The
    `IconCreated` callback defers the same way. An addon hiding its icon hides it from the bar.
    `SetScript`/`HookScript` refuse `OnDragStart`/`OnDragStop` (LibDBIcon re-sets them on
    `Refresh`/`Unlock`; its drag handler rewrites the owner's saved minimap position), and the
    existing drag scripts are cleared at grab. A grab that throws half-way is **rolled back**
    (overrides removed, parent, points and visibility restored). Alpha/translation
    animations on the button are stopped and their `Play` voided (LibDBIcon's mouseover fade).
    Drag is unregistered.
  - Clicks are heard on the **click targets**: the button itself when it has a click script,
    else its clickable descendants (a named frame whose child Button does the work). Each is
    hooked (`OnClick`, or `OnMouseUp`), and a click remembers its target. `Replay(name, mouse)`
    repeats that target (the first after a reload) with `Button:Click(mouse)` or its mouse
    scripts, and returns false when no handler actually ran.
  - `Scan(report)` builds the skipped-children report (and asks `issecurevariable`) only for
    `/gmb scan`; the scan on every bar open stays cheap.
  - **Nothing is secure**: protected frames are never grabbed, so all of it runs in combat.
- **`Bar.lua`**: the launcher (LibDataBroker object `GlassMiniMapBar`, type `data source`,
  registered with LibDBIcon into `db.minimap`) and the bar (`GlassMiniMapBarFrame`, strata
  `MEDIUM`, `Glass.Apply(..., "large")`). Layout is rows of `perRow` in reading order, buttons
  in the collector's order (`db.order` via
  `Collector.orderOf`, the only copy; the user's, then alphabetical), scaled to `buttonSize` from their own width, at `Glass.ContentLevel`. Direction `auto` opens
  toward the screen centre; extra lines also stack toward the centre (rows down from a top-half
  launcher, up from a bottom-half one; columns left from a right-half one), and the first line
  always sits level with the launcher. Screen halves are compared in UIParent units
  (`GetEffectiveScale`), since the launcher lives in the Minimap's scale. Closing: the mouse has been
  off the bar, launcher and any open menu for `hideDelay` seconds; in click mode also on a
  `GLOBAL_MOUSE_DOWN` elsewhere (registered only while open). The bar **grows out of the launcher** (a client-run Scale + Alpha animation from the
  launcher-side edge, squashed along its length only) and shrinks back on close; the frame hides
  on the shrink's `OnFinished`, and hovering the launcher mid-shrink grows it again (`animate`
  option). A left-click close sets `clickClosed`, so the cursor still resting on the launcher
  doesn't count as hovering back (cleared on leave/enter). Closing hides `GameTooltip` only if it
  belongs to the launcher or a bar button. **Last used** only counts while that button is in the
  bar (not hidden by the user or its addon). Launcher clicks: left toggles;
  right repeats the last used (option on) or opens the options; shift-right or middle always
  opens the options.
- **`Options.lua`**: the Options > AddOns canvas panel, built on first show from
  `UICheckButtonTemplate` / `UIPanelButtonTemplate` (measured present, porting guide "UI
  templates"). The buttons are a **dual list box**: Hidden | Shown in bar (in bar order), `>` /
  `<` between them, `Up` / `Down` beside the shown list, double-click to move across, mouse wheel
  to scroll (it may scroll away from the selection; a select or move brings it back into view,
  background refreshes never do). One rule decides "in the bar": `Collector.InBar` (wanted by its
  addon and not hidden by the user), shared by the bar, Up/Down and the arrow states.
  Plain textures and rows, no backdrop template (`SetBackdrop` isn't in the dump's widget list). Numbers use `-`/`+` steppers; `MinimalSliderWithSteppersTemplate` is also present
  if a slider is ever wanted.
  `Options.Refresh` is a no-op until the panel has been built.
- **`GlassMiniMapBar.lua`**: `GlassMiniMapBarDB` (see the header for keys), `LoadDB` (fills,
  repairs and clamps, never wipes), `Set`, `SetHidden`, `MoveButton` (swaps with the neighbouring
  button **in the bar**, `Collector.Movable`; names not collected this session keep their slot in
  the saved `order`), startup at `PLAYER_LOGIN`, and
  `/gmb [options] | open | scan | failures | reset`.

Forever is **Vanilla content running on Blizzard's Retail (Mainline) codebase**: assume the
Retail API. Advice that cites a TBC or Classic API is usually stale, and that includes
HidingBar's `-Vanilla.lua` and `-TBC.lua` files.

## References: read these before touching an unfamiliar API

- `C:\Projects\References\PORTING-TBC-TO-FOREVER.md` holds the canonical addon-agnostic field
  notes, measured on the live client. Treat them as fact. Other sessions edit this file, so
  write new addon-agnostic findings there, not into a copy here.
- `C:\Projects\References\forever-api-1.60.1.70009.md` is the full API dump: functions, events,
  **widget methods** (the only list of those) and the `_G` walk. It proves a name exists, not
  that it works.
- In game: `/api search <name>`.

## Unmeasured, check in game first

1. ~~Which minimap children exist on Forever.~~ **Measured 2026-09-27 (70009):** the only
   named Blizzard children of `Minimap`/`MinimapBackdrop` are `MinimapBackdrop` and
   `ExpansionLandingPageMinimapButton`, both in `IGNORE`. All 8 of the owner's buttons were
   collected, nothing else. `issecurevariable` flagged both Blizzard names secure and our
   launcher (`LibDBIcon10_GlassMiniMapBar`) not. That's too few addon samples to make it the
   filter yet; the name list stays.
2. ~~The skin on each of the owner's buttons.~~ **Measured:** all 8 skin correctly, AltStable
   (hand-made) included. The bar reads as glass beside the minimap.
3. **Right-click menus from bar buttons** (DBM, Leatrix): the bar must stay open while the
   mouse is in the menu. `API.MouseOverMenu` covers the named list frames and `Menu`.
4. **Last used**: the replay clicks a button inside the *closed* (hidden) bar. Check that
   `Button:Click` fires on a hidden button, and where a handler that anchors a menu to `self`
   (DBM, Leatrix) puts it. If either is wrong, open the bar before replaying.
5. `Button:RegisterForDrag()` with no arguments (unregister): it's under `pcall`, and the drag
   scripts are cleared and guarded regardless, so a failure there is harmless.
6. **The grow animation** (Scale animation origin and `SetScaleFrom` on a frame with masked
   9-sliced regions): look for rim or mask artefacts while it plays.
7. Textures: `orb_*.tga` are new files, so a **client restart** is needed the first time.

## Toolchain and commands

There's no build system. The Lua 5.1 toolchain is at `C:\Program Files (x86)\Lua\5.1\`
(`lua.exe`, `luac.exe`). Use it, not a newer Lua that may be first on `PATH`.

```powershell
pwsh tests\run.ps1                                                    # luac -p on the TOC's files + every tests\test_*.lua
& 'C:\Program Files (x86)\Lua\5.1\lua.exe' tests\test_collector.lua  # one test, run from the repo root
pwsh Tools\deploy.ps1                                                 # -> AddOns\GlassMiniMapBar (TOC files, Libs, Media)
python Tools\make_orb_textures.py                                     # regenerate Media\orb_*.tga
```

- Default AddOns path: `C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns`
  (`-AddOnsPath` to override).
- Deploy rewrites `## Version: @project-version@` to `dev` in the deployed copy only. Never
  commit a literal version over that token.
- In game: `/console scriptErrors 1`, then `/reload`. Check the AddOns list shows the addon
  enabled and **not flagged out of date**. A brand-new addon folder needs a client restart.
- **HidingBar must be disabled** while this runs: both grab the same buttons and would fight
  over them.

## Addon basics

- One plain `GlassMiniMapBar.toc`, `## Interface: 16001` (**`11601` is a transposed-digit bug**).
- One global namespace table, `GlassMiniMapBar`. Every file starts
  `GlassMiniMapBar = GlassMiniMapBar or {}`.
- Don't copy a shared library's functions into locals (`local F = lib.F`): a newer embedded copy
  upgrades the table in place. `Bar.lua` calls `LibStub(...)` each time for the same reason.
- Keep a `_test` seam table at the bottom of a file to expose internals to tests. Don't promote
  internals to globals.

## Testing

`tests\` follows GlassPanel's: plain Lua 5.1, `tests\wow_stubs.lua` (driven through `WoW`),
`tests\harness.lua` (`check` / `eq` / `loadAddon` / `launcher` / `bar` / `entry`), and
`tests\run.ps1`.

- **The stub is an allowlist**, with strict globals. Before stubbing a global, confirm it's in
  the dump and copy its signature.
- The stub's widget metatable `__index` is a real method **table** (not a function), because the
  addon calls `getmetatable(CreateFrame("Frame")).__index.SetPoint(btn, ...)`.
- `Libs\` isn't loaded in tests: `LibStub` hands out a fake LibDataBroker and a fake LibDBIcon
  (`WoW.LDBI()`), whose `Register` makes a button like the real one (border 136430, background
  136467, icon) and fires `LibDBIcon_IconCreated`. `WoW.MinimapButton{...}` makes a hand-made one.
- Event names are validated against the dump. `test_methods.lua` checks every widget method
  called against the dump's widget-method list, and must keep exercising every handler.
- `WoW.mouseOver[frame] = true` drives `IsMouseOver`; `WoW.tick(s)` runs `OnUpdate`.
- **Mutation-test a new test**: break the behaviour and confirm it goes red.
- Offline tests can't cover rendering, real minimap children, or other addons' handlers.

## Workflow (sibling conventions)

- Issue → branch off `main` → PR with `Closes #N` → review → squash-merge. **The owner merges,
  closes PRs and launches reviews.** Never commit to `main`, never `gh pr merge`. Commit or push
  only when asked. Before committing, `pwsh tests\run.ps1` must be green.
- Adversarial review goes through `/codex-consult` (`.claude/skills/codex-consult/`), launched
  by the owner, with Fable as the fallback. Verify its claims before acting, and push back on
  complexity for a single-owner addon.
- Releases: see **Releasing** below.

## Releasing

CurseForge builds from the repository webhook when it sees a tag (the owner sets it up), reading
`.pkgmeta`, and publishes `CHANGELOG.md` as the release notes. The README is the project
description, and it must keep its opening line: **"If you want more, use HidingBar"**, linking
`https://www.curseforge.com/wow/addons/hidingbar`.

1. **Every tag needs a `CHANGELOG.md` entry, committed before the tag is pushed.** A tag without
   one publishes the previous release's notes. Add `## vX.Y.Z - <date>` at the top, written for
   players (what changed for them, not the diff). Anything that behaves differently after
   updating gets its own heading.
2. Merge through a PR, then tag `main`: `git tag v1.0.0 && git push --tags`.
3. The release type comes from the **tag name**: `alpha` / `beta` → that channel, anything else →
   Release. It's a distribution channel, not a stability claim: CurseForge users are on Release
   by default, so a beta tag holds the build back from them. The game client being in beta is
   not a reason to tag beta.
4. **Check the published zip by hand**: `GlassMiniMapBar/` with the TOC's files, `Libs\`, `Media\`
   and `LICENSE`, nothing else. CI (`.github/workflows/package-check.yml`) proves the BigWigs
   packager's zip has that shape, but CurseForge's own packager builds the release and doesn't
   always behave the same (Priestly measured it ignoring an embedded library's `.pkgmeta`).

- `LICENSE` ships in the zip on purpose: GPLv3 requires it. Don't add it to `.pkgmeta`'s ignore.
- The four libraries are committed under `Libs\`, not `.pkgmeta` externals, so the tests, the
  deploy script and the release all use the same files.

## Conventions

- **Right-size for a single maintainer.** Do the simplest thing that works, with no speculative
  abstraction or config. HidingBar has ~60 options; this addon should stay near ten.
- **Measured beats reasoned.** If a claim about the client can be checked in game, check it.
- Match the surrounding code's idiom. Keep pure refactors in their own commit.
