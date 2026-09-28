-- Saved variables: defaults filled, junk repaired, the user's data kept.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadAddon()
local db = GlassMiniMapBarDB
eq(db.openOn, "hover", "default: open on hover")
eq(db.direction, "auto", "default direction")
eq(db.skin, true, "default: glass skin on")
eq(db.lastUsed, false, "default: last-used launcher off (an option)")
eq(type(db.hidden), "table", "hidden list")
eq(type(db.minimap), "table", "LibDBIcon table")
eq(db, GlassMiniMapBar.db, "the addon uses the saved table itself")

loadAddon({ db = { hidden = { LibDBIcon10_DBM = true }, minimap = { minimapPos = 200 }, openOn = "sideways",
                   perRow = 500, buttonSize = "big", direction = "north", last = { mouse = "LeftButton" } } })
db = GlassMiniMapBarDB
eq(db.hidden.LibDBIcon10_DBM, true, "hidden buttons kept")
eq(db.minimap.minimapPos, 200, "launcher position kept")
eq(db.openOn, "hover", "bad openOn repaired")
eq(db.perRow, 30, "perRow clamped")
eq(db.buttonSize, 28, "non-number size reset")
eq(db.direction, "auto", "bad direction repaired")
eq(db.last, nil, "a 'last' without a name is dropped")

GlassMiniMapBar.Set("buttonSize", 3)
eq(db.buttonSize, 20, "Set clamps to the limits")
GlassMiniMapBar.Set("lock", true)
eq(db.minimap.lock, true, "lock lives in LibDBIcon's table")
eq(db.lock, nil, "...not in ours")
eq(WoW.LDBI().locked.GlassMiniMapBar, true, "launcher locked")
GlassMiniMapBar.Set("lock", false)
eq(WoW.LDBI().locked.GlassMiniMapBar, nil, "launcher unlocked")

done("test_db")
