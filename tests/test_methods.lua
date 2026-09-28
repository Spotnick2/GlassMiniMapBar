-- Every widget method the addon calls must exist on this client.
--
-- The stub answers any Capitalised method call (a no-op for ones it does not
-- implement), so a call to a method Forever lacks would otherwise pass
-- silently. This checks each recorded "Type:Method" against the API dump's
-- widget-method walk. Keep it exercising every handler the addon installs.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local DUMP = os.getenv("GLASSMMB_API_DUMP") or "C:/Projects/References/forever-api-1.60.1.70009.md"
local f = io.open(DUMP, "r")
if not f then
    io.write("test_methods: SKIPPED (no API dump at " .. DUMP .. ")\n")
    os.exit(0)
end
local widget, documented = {}, {}
for line in f:lines() do
    local wm = line:match("^(%a+:%a+)%s*$")
    if wm then widget[wm] = true end
    local fn = line:match("^([%a_]+)%(")
    if fn then documented[fn] = true end
end
f:close()

WoW.methodsCalled = {}
loadAddon({ db = { lastUsed = true }, before = function()
    WoW.LDBI():Register("DBM", { icon = "dbm" }, {})
    WoW.MinimapButton({ name = "HandMadeMinimapButton", script = "OnMouseUp" })
end })
launcher()._cx, launcher()._cy = 900, 700
local L = launcher()
L._scripts.OnEnter(L); L._scripts.OnLeave(L)
entry("LibDBIcon10_DBM").btn:Click("LeftButton")
L:Click("RightButton")
L:Click("LeftButton")
WoW.tick(2)
WoW.fire("GLOBAL_MOUSE_DOWN", "LeftButton")
WoW.finishAnimations()                            -- the shrink's OnFinished
local hand = entry("HandMadeMinimapButton").btn
hand._scripts.OnMouseUp(hand, "RightButton")       -- the hooked OnMouseUp
L:Click("RightButton")                            -- replays it via its mouse scripts
local owned = entry("LibDBIcon10_DBM").btn
owned:Hide(); owned:Show(); WoW.flushTimers(0)    -- deferred owner change
owned:SetScript("OnDragStart", function() end)   -- the drag guard
GlassMiniMapBar.Options._test.panel():Show()
-- Every control on the panel, so each OnClick runs.
for _, w in ipairs(WoW.frames) do
    if w._parent == GlassMiniMapBar.Options._test.panel() and w._scripts.OnClick then
        w._scripts.OnClick(w, "LeftButton")
    end
end
WoW.flushTimers()
for _, k in ipairs({ "skin", "lastUsed" }) do GlassMiniMapBar.Set(k, false); GlassMiniMapBar.Set(k, true) end
for _, d in ipairs({ "left", "right", "up", "down", "auto" }) do GlassMiniMapBar.Set("direction", d) end
GlassMiniMapBar.Set("lock", true)
for _, cmd in ipairs({ "scan", "failures", "open", "reset", "help", "" }) do GlassMiniMapBar._test.slash(cmd) end

local n = 0
for name in pairs(WoW.methodsCalled) do
    n = n + 1
    local method = name:match(":(%a+)$")
    check(widget[name] or documented[method], "method exists on Forever: " .. name)
end
check(n > 40, "recorded a realistic number of methods (" .. n .. ")")
eq(next(GlassMiniMapBar.failures), nil, "no failures recorded while exercising everything")
done("test_methods")
