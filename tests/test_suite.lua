-- Following Glass UI's suite (#37; Glass UI's docs/SUITE.md and
-- docs/SUITE-LOOK.md, API 1; Suite.lua): asked once at ADDON_LOADED before
-- any glass, Pearl built, our material suspended but kept, the suite's tint
-- and wash from Suite.Body (no backing) on the bar and the orbs, live, the
-- report, FollowsSuite for Glass MiniMap's single driver, the fallbacks, and
-- the options.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local function near(a, b, msg)
    check(type(a) == "number" and math.abs(a - b) < 1e-6, string.format("%s: expected %s, got %s", msg, tostring(b), tostring(a)))
end
local function peak(tex) return tex._gradient and tex._gradient[3].a end
local function dbm() WoW.LDBI():Register("DBM", { icon = "dbm" }, {}) end
local function orb() return GlassMiniMapBar.Orb._test.skins[entry("LibDBIcon10_DBM").btn] end

-- The decision comes before any glass: nothing is built at file scope.
local atFiles, askedAtBuild, followsAtLoaded, hostTinted
local GMB, ui = loadAddon({ suite = { tint = "smoked" }, db = { material = "clean" }, before = function()
    atFiles = GlassMiniMapBar.Glass
    local build = GlassMiniMapBar.BuildGlass
    GlassMiniMapBar.BuildGlass = function(...)
        askedAtBuild = #GlassUI.Suite._asked
        return build(...)
    end
    GlassUI.Suite._asked = {}
    local theme = GlassUI.Suite.Theme
    GlassUI.Suite.Theme = function(addon)
        table.insert(GlassUI.Suite._asked, addon)
        return theme(addon)
    end
    dbm()
end, loaded = function()
    -- Glass MiniMap's PLAYER_LOGIN may run before ours: the answer is already there.
    followsAtLoaded = GlassMiniMapBar.FollowsSuite()
    if not followsAtLoaded then hostTinted = GlassMiniMapBar.SetGlassTint(0.9, 0.1, 0.1, 0.9) end
end })
eq(atFiles, nil, "no glass while the files load")
eq(askedAtBuild, 1, "Glass UI was asked before the glass was built")
eq(#ui.asked, 1, "asked once")
eq(ui.asked[1], "GlassMiniMapBar", "...by our name")
eq(followsAtLoaded, true, "FollowsSuite is settled at our ADDON_LOADED, before any PLAYER_LOGIN")
eq(hostTinted, nil, "...so a host checking it never sends its tint")
eq(next(GMB.failures), nil, "nothing failed")
for k, v in pairs(GMB.failures) do io.write("    " .. k .. ": " .. v .. "\n") end
GMB.Suite.Start()
eq(#ui.asked, 1, "starting again doesn't ask again: one answer per session")

-- The material: Glass UI's Pearl; ours kept and refused.
check(GMB.Suite.Following(), "following")
eq(GMB.GlassPreset, "pearl", "Pearl built, though our own is Clean")
near(GMB.Glass.STYLE.wash, 0.10, "...Pearl's wash")
eq(GMB.db.material, "clean", "our material still saved")
local ok, why = GMB.SetMaterial("classic")
check(not ok and why == "set in Glass UI", "setting the material: refused, set in Glass UI")
eq(GMB.db.material, "clean", "...and untouched")
GMB._test.slash("material classic")
check(WoW.chat[#WoW.chat]:find("Following Glass UI", 1, true), "/gmb material says it follows Glass UI")
eq(GMB.db.material, "clean", "...and changes nothing")
GMB._test.slash("suite")
check(WoW.chat[#WoW.chat]:find("following Glass UI", 1, true), "/gmb suite says so too")

-- The report: plain values, Glass UI's names.
local r = ui.LastReport()
eq(ui.reports[#ui.reports].addon, "GlassMiniMapBar", "reported as GlassMiniMapBar")
eq(r.api, 1, "report: api 1")
eq(r.built, "pearl", "...built pearl")
eq(r.reason, nil, "...no reason")
eq(r.minor, GMB.GlassMinor, "...LibGlass's minor")
check(type(r.minor) == "number" and r.minor >= 11, "...at least r11")
eq(r.look and r.look.tint, "smoked", "...the suite's tint, in effect")
eq(r.own.backing, true, "...our own backing (none: the bar is unbacked)")
check(type(r.options) == "function", "...a way to open our options")
r.options()
check(WoW.settingsOpened ~= nil, "...which opens them")

-- The suite's tint and Glass UI's numbers on the bar and the orbs.
check(GMB.FollowsSuite(), "FollowsSuite: true")
local glass = GMB.Bar._test.glass()
local WASH = GMB.Glass.STYLE.wash
eq(glass.tint._color[4], 0.62, "smoked: Glass UI's body on the bar")
near(peak(glass.wash), WASH * 0.14 / 0.18, "...its wash, a factor of our Pearl wash")
eq(orb().tint._color[4], 0.62, "...and on the orbs")
near(peak(orb().wash), WASH * 0.14 / 0.18, "...their wash too")
local backed = false
for _, w in ipairs(WoW.frames) do
    for _, region in pairs(w) do
        if type(region) == "table" and region._color and region._color[1] == 0.04 and region._color[2] == 0.05 then backed = true end
    end
end
check(not backed, "Glass UI's backing painted nowhere")

-- A host's SetGlassTint while we follow (an older Glass MiniMap): kept, not painted.
check(GMB.SetGlassTint(0.9, 0.1, 0.1, 0.9, 2), "a host's tint is accepted")
eq(glass.tint._color[1], 0.05, "...but the suite's stays on the bar: one driver")
eq(orb().tint._color[1], 0.05, "...and on the orbs")

-- Live: a fresh payload, copied (mutating it afterwards changes nothing), re-reported.
local reports = #ui.reports
local payload = ui.SetTint("clear")
eq(glass.tint._color[4], 0.24, "clear: Glass UI's clear body on the bar")
near(peak(glass.wash), WASH, "...the built wash")
eq(orb().tint._color[4], 0.35, "...an orb keeps its 0.35 floor")
eq(#ui.reports, reports + 1, "re-reported")
eq(ui.LastReport().look.tint, "clear", "...with the new tint")
payload.tint = "smoked"
GMB.Bar.Paint()
eq(glass.tint._color[4], 0.24, "the payload isn't kept: mutating it changes nothing")
ui.SetTint("purple")
eq(GMB.Suite.Tint(), "clear", "an unknown suite tint: our default, clear")
local throwing = setmetatable({}, { __index = function() error("boom") end })
EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged", throwing)
eq(GMB.Suite.Tint(), "clear", "a payload whose lookups throw: read raw, nothing thrown")

-- Class: our class colour shaded, at the built alpha; unreadable, as built until PLAYER_ENTERING_WORLD.
ui.SetTint("class")
eq(glass.tint._color[1], 0.6, "class: the priest's white, shaded 0.6")
eq(glass.tint._color[4], glass.tint.glassColor[4], "...at the built alpha")
WoW.class = nil
ui.SetTint("smoked")
ui.SetTint("class")
eq(glass.tint._color[1], glass.tint.glassColor[1], "class colour unreadable: as built")
WoW.class = "MAGE"
WoW.fire("PLAYER_ENTERING_WORLD", false, true)
near(glass.tint._color[1], 0.25 * 0.6, "...and painted at PLAYER_ENTERING_WORLD")

-- The options: the material choice disabled while following, Glass UI's page a click away.
GMB.Options._test.panel():Show()
local O = GMB.Options._test
local mat = O.material()
eq(mat.button:IsEnabled(), false, "options: the material is disabled while following")
check(mat.status:GetText():find("Following Glass UI", 1, true), "...says it follows Glass UI")
check(mat.open:IsShown(), "...with Set in Glass UI")
mat.open:Click()
eq(ui.opened, 1, "...which opens Glass UI's page")
eq(next(GMB.failures), nil, "no failures while following")

--------------------------------------------------------------------------------
-- Not following, absent or broken: our own material, SetGlassTint drives.
--------------------------------------------------------------------------------

local function ownLook(label, opts)
    opts.db = { material = "clean" }
    local before = opts.before
    opts.before = function() dbm(); if before then before() end end
    local G = loadAddon(opts)
    eq(G.GlassPreset, "clean", label .. ": our own material")
    eq(G.db.material, "clean", label .. ": ...kept")
    check(not G.Suite.Following(), label .. ": not following")
    check(not G.FollowsSuite(), label .. ": FollowsSuite false")
    G.SetGlassTint(0.9, 0.1, 0.1, 0.9)
    eq(G.Bar._test.glass().tint._color[1], 0.9, label .. ": the host's tint drives the bar")
    eq(next(G.failures), nil, label .. ": no failures")
    return G
end

ownLook("no Glass UI", {})
ownLook("GlassUI without Suite", { glassUI = {} })
ownLook("Suite not a table", { glassUI = { Suite = "yes" } })
ownLook("API 2", { suite = true, before = function() GlassUI.Suite.API = 2 end })
ownLook("API '1'", { suite = true, before = function() GlassUI.Suite.API = "1" end })
ownLook("Theme not a function", { suite = true, before = function() GlassUI.Suite.Theme = true end })
ownLook("Report not a function", { suite = true, before = function() GlassUI.Suite.Report = nil end })
ownLook("Theme throwing", { suite = { answer = function() error("boom") end } })
ownLook("Theme junk", { suite = { answer = function() return "pearl" end } })
ownLook("Theme preset junk", { suite = { answer = function() return { preset = "chrome" } end } })
ownLook("a Theme answer whose lookups throw", { suite = { answer = function()
    return setmetatable({}, { __index = function() error("boom") end })
end } })
ownLook("a Suite whose lookups throw", { glassUI = setmetatable({}, { __index = function() error("boom") end }) })
local _, notReady = nil, nil
_, notReady = loadAddon({ suite = { answer = function() return nil, "not-ready" end } })
eq(GlassMiniMapBar.Suite._test.answer(), "not-ready", "not-ready: recorded for /gmb suite")
local G, nf = loadAddon({ suite = { answer = function() return nil, "not-following" end } })
eq(G.GlassPreset, "pearl", "not following: our own default, Pearl")
eq(nf.LastReport().built, nil, "...reported as our own look")
eq(nf.LastReport().look, nil, "...no suite look")
G.Options._test.panel():Show()
eq(G.Options._test.material().button:IsEnabled(), true, "...the material choice enabled")
eq(G.Options._test.material().open:IsShown(), false, "...no Set in Glass UI")

-- Following without Look or Body (an older API 1): Pearl, but the tint stays the host's.
G, ui = loadAddon({ suite = { noBody = true }, before = dbm })
check(G.Suite.Following(), "no Body: following the material")
eq(G.GlassPreset, "pearl", "...Pearl")
check(not G.FollowsSuite(), "...but not the look: FollowsSuite false")
G.SetGlassTint(0.9, 0.1, 0.1, 0.9)
eq(G.Bar._test.glass().tint._color[1], 0.9, "...so the host's tint drives the bar")
eq(ui.LastReport().look, nil, "...and no look is reported")
G = loadAddon({ suite = { noLook = true } })
check(not G.FollowsSuite(), "no Look: FollowsSuite false")
G = loadAddon({ suite = { noOpen = true } })
G.Options._test.panel():Show()
eq(G.Options._test.material().open:IsShown(), false, "no Open: no Set in Glass UI button")

--------------------------------------------------------------------------------
-- The library: too old for Pearl, or New failing.
--------------------------------------------------------------------------------

-- LibStub answers MINOR 10 for LibGlass (the library itself stays r11: its New
-- checks its own MINOR against LibStub's).
local function oldLibrary()
    local mt = getmetatable(LibStub)
    local call = mt.__call
    mt.__call = function(self, major, silent)
        local lib, minor = call(self, major, silent)
        if major == "LibGlass-1.0" then return lib, 10 end
        return lib, minor
    end
end
G, ui = loadAddon({ suite = true, before = oldLibrary })
eq(G.GlassPreset, "clean", "followed Pearl on LibGlass r10: clean, as the contract has it")
eq(ui.LastReport().built, nil, "...reported unbuilt")
eq(ui.LastReport().reason, "library-too-old", "...library-too-old")
check(G.Suite.MaterialStatus():find("library-too-old", 1, true), "...and the options say why")
G = loadAddon({ before = oldLibrary })
eq(G.GlassPreset, "clean", "our own Pearl on r10: clean")
check(G.failures.material ~= nil, "...recorded in /gmb failures")
check(G.Suite.MaterialStatus():find("Clean in use", 1, true), "...and the options say so")
G, ui = loadAddon({ suite = true, before = function()
    local lib = LibStub("LibGlass-1.0")
    local new = lib.New
    lib.New = function(self, opts) if opts then error("boom") end return new(self, opts) end
end })
eq(ui.LastReport().reason, "build-failed", "New throwing for every preset: build-failed")
eq(G.GlassPreset, "classic", "...and classic, the last resort (New with no preset)")
G, ui = loadAddon({ suite = true, before = function()
    local lib = LibStub("LibGlass-1.0")
    local new = lib.New
    lib.New = function(self, opts) if opts and opts.preset == "pearl" then error("boom") end return new(self, opts) end
end })
eq(ui.LastReport().reason, "build-failed", "New throwing for Pearl only: build-failed")
eq(G.GlassPreset, "clean", "...and clean")

--------------------------------------------------------------------------------
-- Our own material: Pearl by default, saved only when it differs.
--------------------------------------------------------------------------------

G = loadAddon()
eq(G.GlassPreset, "pearl", "an empty profile: Pearl")
eq(G.db.material, nil, "...nothing saved")
check(G.SetMaterial("classic"), "choosing Classic")
eq(G.db.material, "classic", "...saved")
eq(G.GlassPreset, "pearl", "...applied at the next /reload, not now")
check(G.SetMaterial("pearl"), "back to Pearl")
eq(G.db.material, nil, "...the default isn't saved")
check(not G.SetMaterial("chrome"), "an unknown material: refused")
eq(loadAddon({ db = { material = "classic" } }).GlassPreset, "classic", "a saved Classic builds classic")
eq(loadAddon({ db = { material = "chrome" } }).db.material, nil, "a junk material is dropped")
eq(loadAddon({ db = { material = "pearl" } }).db.material, nil, "a saved default is dropped")
G = loadAddon()
G.Options._test.panel():Show()
local m = G.Options._test.material()
eq(m.button:GetText(), "Pearl", "options: Pearl")
m.button:Click()
eq(G.db.material, "clean", "...a click: Clean")
check(m.status:GetText():find("In use until /reload: Pearl", 1, true), "...in use until /reload")
m.button:Click(); m.button:Click()
eq(G.db.material, nil, "...round to Pearl")

-- Follow on, then off: our own material and saved keys come back exactly.
G = loadAddon({ suite = true, db = { material = "classic", skin = false } })
eq(G.GlassPreset, "pearl", "follow on: Pearl")
G = loadAddon({ db = G.db })
eq(G.GlassPreset, "classic", "follow off after a reload: our Classic again")
eq(G.db.skin, false, "...and the other keys untouched")

done("test_suite")
