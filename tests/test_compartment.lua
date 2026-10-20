-- Blizzard's AddOns compartment in the bar: both registration paths, removal,
-- duplicates, clicks and hovers, and the option.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadAddon({
    before = function()
        WoW.LDBI():Register("DBM", { icon = "dbm", OnClick = function() end }, {})
        WoW.LDBI():Register("BugSack", { icon = "bug", OnClick = function() end }, { hide = true })
    end,
    -- The bulk TOC registration at PLAYER_ENTERING_WORLD (after our login).
    tocAddons = {
        { title = "|cff7fd4ffGlass|r Mail", icon = "Interface\\Icons\\INV_Letter_15" },
        { title = "Gnomesweeper", icon = "atlas:gnome" },
        { title = "dbm" },                        -- same title as a bar button, case aside: a duplicate
    },
})
WoW.flushTimers(0)
local G = GlassMiniMapBar
local C, Compartment = G.Collector, G.Compartment

-- Bulk entries arrive through the UpdateDisplay hook, reconciled next frame.
check(entry("AddOns:Glass Mail") ~= nil, "a TOC compartment entry is in the bar (colour codes dropped)")
eq(entry("AddOns:Glass Mail").display, "Glass Mail", "shown by its plain title")
eq(entry("AddOns:Glass Mail").btn.icon._file, "Interface\\Icons\\INV_Letter_15", "with its file icon")
eq(entry("AddOns:Gnomesweeper").btn.icon._atlas, "atlas:gnome", "or its atlas")
check(entry("AddOns:dbm") == nil, "the same title as exactly one bar button is that button: left out")
check(G.Orb.IsSkinned(entry("AddOns:Gnomesweeper").btn), "compartment buttons wear the orb too")
check(Compartment._test.hider().IsHidden(), "Blizzard's AddOns button is out of sight")

-- A runtime RegisterAddon.
local opened = {}
AddonCompartmentFrame:RegisterAddon({ text = "Late Addon", icon = "late",
    func = function(_, input, menu) table.insert(opened, { input.buttonName, menu }) end })
WoW.flushTimers(0)
local late = entry("AddOns:Late Addon")
check(late ~= nil, "RegisterAddon at runtime reaches the bar")

-- Click: func(nil, { buttonName = mouse }, ourButton).
late.btn:Click("RightButton")
eq(opened[1][1], "RightButton", "the entry's func hears the mouse button")
eq(opened[1][2], late.btn, "...and gets our button as the anchor (LibDBIcon's OnClick frame)")
entry("AddOns:Gnomesweeper").btn:Click("LeftButton")
eq(WoW.compartmentCalls[1].title, "Gnomesweeper", "a TOC wrapper is called")
eq(WoW.compartmentCalls[1].button, "LeftButton", "...with buttonName")
eq(GlassMiniMapBarDB.last.name, "AddOns:Gnomesweeper", "a compartment click counts as last used")
check(C.Replay("AddOns:Late Addon", "LeftButton"), "a compartment button replays like any other")
eq(opened[2][1], "LeftButton", "...through its func")

-- Last used with an atlas icon: the launcher shows the atlas (Codex, PR #26).
G.Set("lastUsed", true)
entry("AddOns:Gnomesweeper").btn:Click("LeftButton")
eq(G.Bar._test.native().icon._atlas, "atlas:gnome", "the launcher wears the entry's atlas")
G.Set("lastUsed", false)

-- Removed and registered again before the sync: the same name, so the
-- player's hidden list still applies (Codex, PR #26).
G.SetHidden("AddOns:Glass Mail", true)
local list = AddonCompartmentFrame.registeredAddons
for i, d in ipairs(list) do
    if d.text == "|cff7fd4ffGlass|r Mail" then table.remove(list, i); break end
end
AddonCompartmentFrame:RegisterAddon({ text = "|cff7fd4ffGlass|r Mail", func = function() end })
WoW.flushTimers(0)
check(entry("AddOns:Glass Mail") ~= nil, "re-registered: the same name")
eq(entry("AddOns:Glass Mail (2)"), nil, "...not a second one")
eq(GlassMiniMapBarDB.hidden["AddOns:Glass Mail"], true, "...so it stays hidden")
G.SetHidden("AddOns:Glass Mail", false)

-- LibDBIcon's own entry for a button its addon hides is kept, and its hover
-- callbacks get the entry (they read menu.text: review round 1's blocker).
local lib = WoW.LDBI()
lib:AddButtonToCompartment("DBM")
lib:AddButtonToCompartment("BugSack")
WoW.flushTimers(0)
eq(entry("AddOns:DBM"), nil, "LibDBIcon's compartmentData for a shown bar button: one button, not two")
local bug = entry("AddOns:BugSack")
check(bug ~= nil, "...kept when the minimap button is hidden by its addon")
bug.btn._scripts.OnEnter(bug.btn)
eq(WoW.compartmentEnter, "BugSack", "LibDBIcon's hover reads the entry passed second")
bug.btn._scripts.OnLeave(bug.btn)
eq(WoW.compartmentLeave, "BugSack", "...on leave too")
eq(next(G.failures), nil, "no failure from the hovers")
check(Compartment._test.duplicates(Compartment.List())[lib.objects.DBM.compartmentData], "duplicate found by identity")

-- Hidden by the user in our bar: still the same button, no copy appears.
G.SetHidden("LibDBIcon10_DBM", true)
WoW.flushTimers(0)
eq(entry("AddOns:DBM"), nil, "hiding the bar button doesn't bring the compartment copy in")
G.SetHidden("LibDBIcon10_DBM", false)

-- Removal (LibDBIcon removes its entry directly, then UpdateDisplay).
lib:RemoveButtonFromCompartment("BugSack")
WoW.flushTimers(0)
eq(entry("AddOns:BugSack"), nil, "a removed entry leaves the bar")
eq(#Compartment._test.pool, 1, "its button goes back to the pool")

-- Titles compare exactly (markup and case aside): punctuation matters.
WoW.MinimapButton({ name = "Foo-BarMinimapButton" })
C.Scan()
AddonCompartmentFrame:RegisterAddon({ text = "Foo Bar", func = function() end })
WoW.flushTimers(0)
check(entry("AddOns:Foo Bar") ~= nil, "'Foo Bar' is not 'Foo-Bar'")
-- A LibDBIcon object name's "_" is a space: Leatrix registers both (70374).
WoW.LDBI():Register("Leatrix_Maps", { icon = "bug", OnClick = function() end }, {})
AddonCompartmentFrame:RegisterAddon({ text = "Leatrix Maps", func = function() end })
WoW.flushTimers(0)
eq(entry("AddOns:Leatrix Maps"), nil, "'Leatrix Maps' is LibDBIcon10_Leatrix_Maps: one button")
-- A LibDBIcon button is also its data object's text and label: Portal
-- Roulette's object is "PortalRoulette", its entry "Portal Roulette"; 123's
-- object is "OneTwoThree", its entry "123".
-- Broker objects are LibDataBroker proxies (Codex, PR #33).
local LDB = LibStub("LibDataBroker-1.1")
WoW.LDBI():Register("PortalRoulette", LDB:NewDataObject("PortalRoulette",
    { type = "launcher", text = "Portal Roulette", OnClick = function() end }), {})
AddonCompartmentFrame:RegisterAddon({ text = "Portal Roulette", func = function() end })
WoW.LDBI():Register("OneTwoThree", LDB:NewDataObject("OneTwoThree",
    { type = "data source", label = "123", text = "3 shards", OnClick = function() end }), {})
AddonCompartmentFrame:RegisterAddon({ text = "123", func = function() end })
WoW.flushTimers(0)
eq(entry("AddOns:Portal Roulette"), nil, "'Portal Roulette' is LibDBIcon10_PortalRoulette's text: one button")
eq(entry("AddOns:123"), nil, "'123' is LibDBIcon10_OneTwoThree's label: one button")
-- Ambiguous titles never dedupe.
WoW.MinimapButton({ name = "TwinMinimapButton" })
WoW.MinimapButton({ name = "Twin_MinimapButton" })
C.Scan()
AddonCompartmentFrame:RegisterAddon({ text = "Twin", func = function() end })
WoW.flushTimers(0)
check(entry("AddOns:Twin") ~= nil, "an ambiguous title keeps the compartment entry")

-- Opening the bar reconciles too.
table.insert(AddonCompartmentFrame.registeredAddons, { text = "Sneaky", func = function() end })
G.Bar.Open()
check(entry("AddOns:Sneaky") ~= nil, "opening the bar catches an entry added without UpdateDisplay")

-- The option: off takes the entries out and gives Blizzard's button back.
G.Set("compartment", false)
WoW.flushTimers(0)
eq(entry("AddOns:Gnomesweeper"), nil, "option off: no compartment buttons")
eq(AddonCompartmentFrame:GetParent(), MinimapCluster, "...and the AddOns button is back where Blizzard put it")
G.Set("compartment", true)
WoW.flushTimers(0)
check(entry("AddOns:Gnomesweeper") ~= nil, "on again: back in the bar")
check(Compartment._test.hider().IsHidden(), "...and the AddOns button hidden again")

-- Off at login: the button is never touched.
loadAddon({ db = { compartment = false }, tocAddons = { { title = "Gnomesweeper" } } })
WoW.flushTimers(0)
eq(entry("AddOns:Gnomesweeper"), nil, "off at login: nothing in the bar")
eq(AddonCompartmentFrame:GetParent(), MinimapCluster, "...and the AddOns button left alone")
eq(GlassMiniMapBar.Compartment._test.hider(), nil, "...never even watched")

done("test_compartment")
