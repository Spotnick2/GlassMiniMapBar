-- The public API (PublicAPI.lua, docs/PUBLIC-API.md): another addon's button
-- as the launcher, before and after we build; our own button kept hidden for
-- the whole attachment and given back; the face; the handlers; the tint.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function hostButton()
    local b = CreateFrame("Button", nil, UIParent)
    b._width, b._height = 30, 30
    b._cx, b._cy = 900, 600
    return b
end

-- Attached BEFORE our PLAYER_LOGIN (the host loaded first): applied at build.
local host, faces = nil, {}
loadAddon({ before = function()
    WoW.LDBI():Register("DBM", { icon = "Interface\\Icons\\DBM", OnClick = function() end }, {})
    host = hostButton()
    eq(GlassMiniMapBar.PUBLIC_API_VERSION, 1, "the API version")
    check(GlassMiniMapBar.UseLauncher(host, { setIcon = function(icon, coords) faces[#faces + 1] = icon end }),
        "UseLauncher before the bar exists")
end })
local G, B = GlassMiniMapBar, GlassMiniMapBar.Bar
local native = B._test.native()
eq(B.Launcher(), host, "the bar opens from the host's button")
eq(native._shown, false, "our own minimap button is hidden")
check(not G.Orb.IsSkinned(host), "the host's button keeps the host's look")
check(G.Orb.IsSkinned(native), "ours still wears its glass")
eq(faces[#faces], B.ARROWS.left, "the host hears the launcher's face (the arrow toward the bar)")
eq(GlassMiniMapBarDB.minimap.hide, nil, "nothing saved: the player's own choice is untouched")

-- LibDBIcon showing our button again (lib:Show, Refresh, its login pass): hidden again.
WoW.LDBI():Show("GlassMiniMapBar")
eq(native._shown, false, "re-shown by LibDBIcon: hidden again while attached")

-- The handlers: the host's scripts call them; another frame is ignored.
G.LauncherEnter(host)
check(B.IsOpen(), "LauncherEnter opens it (hover mode)")
local p = B.Frame()._points[1]
eq(p[2], host, "the bar is anchored to the host's button")
eq(p[1], "TOPRIGHT", "...and opens toward the middle (host on the right half)")
G.LauncherLeave(host)
B.Close(); WoW.finishAnimations()
local stranger = hostButton()
G.LauncherClick(stranger, "LeftButton")
check(not B.IsOpen(), "a click from another frame is ignored")
G.LauncherClick(host, "LeftButton")
check(B.IsOpen(), "LauncherClick toggles it")
G.LauncherClick(host, "LeftButton")
WoW.finishAnimations()
check(not B.IsOpen(), "...and closes it")
WoW.settingsOpened = nil
G.LauncherClick(host, "RightButton")
eq(WoW.settingsOpened, "Glass MiniMap Bar", "right-click: our options")

-- Last used: the face follows.
G.Set("lastUsed", true)
entry("LibDBIcon10_DBM").btn:Click("LeftButton")
eq(faces[#faces], "Interface\\Icons\\DBM", "the host's face shows the last button used")
G.Set("lastUsed", false)

-- Release: our button back (the player hadn't hidden it), the bar on it.
G.ReleaseLauncher()
eq(B.Launcher(), native, "released: the bar opens from our button again")
eq(native._shown, true, "...shown again")
G.LauncherClick(host, "LeftButton")
check(not B.IsOpen(), "...and the old host's clicks are ignored")
WoW.LDBI():Show("GlassMiniMapBar")
eq(native._shown, true, "no longer suppressed")

-- A player who hid our button: release keeps it hidden.
GlassMiniMapBarDB.minimap.hide = true
native:Hide()
G.UseLauncher(host)
G.ReleaseLauncher()
eq(native._shown, false, "released: still hidden, as the player chose")
GlassMiniMapBarDB.minimap.hide = nil

-- Attached AFTER build; released before build cancels.
loadAddon()
local h2 = hostButton()
check(GlassMiniMapBar.UseLauncher(h2), "UseLauncher after the bar exists")
eq(GlassMiniMapBar.Bar.Launcher(), h2, "...applied at once")
check(not GlassMiniMapBar.UseLauncher("nope"), "not a frame: refused")
loadAddon({ before = function()
    GlassMiniMapBar.UseLauncher(hostButton())
    GlassMiniMapBar.ReleaseLauncher()
end })
eq(GlassMiniMapBar.Bar.Launcher(), GlassMiniMapBar.Bar._test.native(), "released before build: our own button")
eq(GlassMiniMapBar.Bar._test.native()._shown, true, "...shown")

-- The tint: the bar and the orbs, remembered before build, reset with no arguments.
loadAddon({ before = function()
    WoW.LDBI():Register("DBM", { icon = "dbm" }, {})
    GlassMiniMapBar.SetGlassTint(0.05, 0.06, 0.08, 0.62, 0.5)
end })
local glass = GlassMiniMapBar.Bar._test.glass()
local WASH = GlassMiniMapBar.Glass.STYLE.wash
-- The wash is a gradient: SetAlpha doesn't reach it (the stub ignores it, as
-- the client does), so it's the gradient's peak that changes.
local function peak(tex) return tex._gradient and tex._gradient[3].a end
eq(glass.tint._color[4], 0.62, "remembered before build: the bar's body")
eq(peak(glass.wash), WASH * 0.5, "...its wash, through the gradient")
local orb = GlassMiniMapBar.Orb._test.skins[entry("LibDBIcon10_DBM").btn]
eq(orb.tint._color[4], 0.62, "...and the orbs")
eq(peak(orb.wash), WASH * 0.5, "...the orbs' wash too")
WoW.LDBI():Register("Late", { icon = "late" }, {})
WoW.flushTimers(0)
eq(GlassMiniMapBar.Orb._test.skins[entry("LibDBIcon10_Late").btn].tint._color[1], 0.05, "an orb made later is tinted too")
check(GlassMiniMapBar.SetGlassTint(0.3, 0.6, 0.9), "a tint without alpha")
eq(glass.tint._color[4], glass.tint.glassColor[4], "...keeps the surface's own alpha")
check(not GlassMiniMapBar.SetGlassTint(2, 0, 0), "out of range: refused")
GlassMiniMapBar.SetGlassTint()
eq(glass.tint._color[1], glass.tint.glassColor[1], "no arguments: as built")
eq(peak(glass.wash), WASH, "...wash too")
eq(peak(orb.wash), WASH, "...and the orbs' wash")
check(GlassMiniMapBar.SetGlassTint(0.1, 0.1, 0.1, 0.5, 2), "a doubled wash")
eq(peak(glass.wash), math.min(1, WASH * 2), "...is the built wash doubled, at most 1")
GlassMiniMapBar.SetGlassTint()

eq(next(GlassMiniMapBar.failures), nil, "no failures")
done("test_public_api")
