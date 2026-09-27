-- The bar: layout, opening and closing, the launcher's clicks and face.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadAddon({ before = function()
    for _, n in ipairs({ "DBM", "BugSack", "AtlasLoot", "Leatrix_Plus", "Leatrix_Maps" }) do
        WoW.LDBI():Register(n, { icon = "Interface\\Icons\\" .. n, iconCoords = { 0.1, 0.9, 0.1, 0.9 } }, {})
    end
end })
launcher()._cx, launcher()._cy = 900, 700      -- top-right corner, like the minimap

local B, db = GlassMiniMapBar.Bar, GlassMiniMapBarDB
local size, gap, pad = db.buttonSize, B.GAP, GlassMiniMapBar.Glass.Inset("large")

eq(bar():IsShown(), false, "closed at login")
eq(B.Direction(), "left", "auto: opens toward the middle (launcher on the right)")

-- Hover opens; staying on the bar keeps it; leaving closes after the delay.
launcher()._scripts.OnEnter(launcher())
eq(bar():IsShown(), true, "hover opens")
eq(bar()._width, pad * 2 + 5 * size + 4 * gap, "one row of five")
eq(bar()._height, pad * 2 + size, "one line tall")
local p = bar()._points[1]
eq(p[1], "TOPRIGHT", "anchored by its right edge (grows left)")
eq(p[2], launcher(), "...to the launcher")

WoW.mouseOver[bar()] = true
WoW.tick(5)
eq(bar():IsShown(), true, "mouse on the bar keeps it open")
WoW.mouseOver[bar()] = nil
WoW.tick(0.5)
eq(bar():IsShown(), true, "still open inside the hide delay")
WoW.tick(0.5)
eq(B.IsOpen(), false, "closing after the delay")
eq(bar():IsShown(), true, "...still shown while it shrinks into the launcher")
WoW.finishAnimations()
eq(bar():IsShown(), false, "hidden once the shrink finishes")

-- A right-click menu a button opened keeps the bar while the mouse is on it.
B.Open()
DropDownList1 = CreateFrame("Frame", "DropDownList1", UIParent)
WoW.mouseOver[DropDownList1] = true
WoW.tick(5)
eq(bar():IsShown(), true, "mouse on an open menu keeps the bar")
WoW.mouseOver[DropDownList1] = nil
WoW.tick(1)
WoW.finishAnimations()
eq(bar():IsShown(), false, "closes once the mouse leaves the menu")

-- Buttons: alphabetical, reading order, scaled to the size.
B.Open()
local atlas = entry("LibDBIcon10_AtlasLoot").btn
local pt = atlas._points[1]
eq(pt[3], "TOPLEFT", "placed from the bar's top-left")
eq(pt[4] * atlas._scale, pad + size / 2, "AtlasLoot first (x)")
eq(atlas._scale, size / 31, "scaled from 31 px to the button size")
eq(atlas._level, GlassMiniMapBar.Glass.ContentLevel(bar()), "at the glass content level")

-- Hidden in the options: out of the bar.
GlassMiniMapBar.SetHidden("LibDBIcon10_DBM", true)
eq(entry("LibDBIcon10_DBM").btn._shown, false, "hidden button not shown")
eq(bar()._width, pad * 2 + 4 * size + 3 * gap, "bar shrinks")
GlassMiniMapBar.SetHidden("LibDBIcon10_DBM", false)

-- Wrapping: two per row, rows stack downward from the top-right corner.
GlassMiniMapBar.Set("perRow", 2)
eq(bar()._height, pad * 2 + 3 * size + 2 * gap, "three lines of two")
eq(bar()._width, pad * 2 + 2 * size + gap, "two wide")
GlassMiniMapBar.Set("perRow", 12)

-- Vertical.
GlassMiniMapBar.Set("direction", "down")
eq(bar()._points[1][1], "TOPLEFT", "down: hangs under the launcher")
eq(bar()._height, pad * 2 + 5 * size + 4 * gap, "down: tall")
GlassMiniMapBar.Set("direction", "auto")

-- Click mode: hover does nothing, left-click toggles, a click elsewhere closes.
B.Close()
WoW.finishAnimations()
GlassMiniMapBar.Set("openOn", "click")
launcher()._scripts.OnEnter(launcher())
eq(bar():IsShown(), false, "click mode: hover doesn't open")
launcher():Click("LeftButton")
eq(bar():IsShown(), true, "left-click opens")
check(bar()._events.GLOBAL_MOUSE_DOWN, "listens for clicks elsewhere while open")
WoW.mouseOver[bar()] = true
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
eq(bar():IsShown(), true, "a click on the bar keeps it")
WoW.mouseOver[bar()] = nil
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
WoW.finishAnimations()
eq(bar():IsShown(), false, "a click elsewhere closes it")
check(not bar()._events.GLOBAL_MOUSE_DOWN, "stops listening when closed")
GlassMiniMapBar.Set("openOn", "hover")

-- Right-click without the last-used option: the options panel.
launcher():Click("RightButton")
eq(WoW.settingsOpened, "Glass MiniMap Bar", "right-click opens Options > AddOns")

-- Last used: the launcher wears the button's icon and right-click repeats it.
local obj = launcher().dataObject
eq(obj.icon, B.ARROWS.left, "arrow toward the bar by default")
GlassMiniMapBar.Set("lastUsed", true)
local lp = entry("LibDBIcon10_Leatrix_Plus").btn
local clicks = {}
lp.dataObject.OnClick = function(_, mouse) table.insert(clicks, mouse) end
lp:Click("RightButton")
eq(db.last.name, "LibDBIcon10_Leatrix_Plus", "last used recorded")
eq(obj.icon, "Interface\\Icons\\Leatrix_Plus", "launcher wears its icon")
eq(obj.iconCoords[1], 0.1, "...with its coords")
WoW.settingsOpened = nil
launcher():Click("RightButton")
eq(clicks[2], "RightButton", "right-click on the launcher repeats it, same mouse button")
eq(WoW.settingsOpened, nil, "...instead of opening the options")
WoW.shift = true
launcher():Click("RightButton")
eq(WoW.settingsOpened, "Glass MiniMap Bar", "shift-right-click still opens the options")
WoW.shift = false
GlassMiniMapBar.Set("lastUsed", false)
eq(obj.icon, B.ARROWS.left, "option off: back to the arrow")

-- Animation: grows out of the launcher-side edge, along the bar's length.
local grow, shrink = bar()._anims[1], bar()._anims[2]
B.Close(); WoW.finishAnimations()
B.Open()
check(grow._playing, "opening plays the grow")
local sc = grow._animations[1]
eq(sc._origin, "RIGHT", "grows from the edge next to the launcher")
eq(sc._from[1], B.GROW.from, "...starting squashed along its length")
eq(sc._from[2], 1, "...not in height")
-- Back on the launcher mid-shrink: it grows again instead of vanishing.
B.Close()
check(shrink._playing, "closing plays the shrink")
WoW.mouseOver[launcher()] = true
WoW.tick(0.02)
check(B.IsOpen(), "hovering the launcher mid-shrink reopens it")
check(not shrink._playing and grow._playing, "...shrink stopped, grow replayed")
WoW.mouseOver[launcher()] = nil
WoW.finishAnimations()
eq(bar():IsShown(), true, "a finished grow leaves it open")
-- Direction up: grows upward from the bottom edge, in height.
GlassMiniMapBar.Set("direction", "up")
B.Close(); WoW.finishAnimations(); B.Open()
eq(sc._origin, "BOTTOM", "up: grows from the bottom edge")
eq(sc._from[2], B.GROW.from, "up: squashed in height")
GlassMiniMapBar.Set("direction", "auto")
-- Off: instant, no animation.
GlassMiniMapBar.Set("animate", false)
B.Close()
eq(bar():IsShown(), false, "animate off: closes at once")
local plays = grow._plays
B.Open()
eq(grow._plays, plays, "animate off: no grow")
GlassMiniMapBar.Set("animate", true)

-- A launcher on the left half opens right.
launcher()._cx = 100
eq(B.Direction(), "right", "auto: opens right from the left half")

done("test_bar")
