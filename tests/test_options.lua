-- The Options > AddOns panel: registered at load, built on first show, and
-- every control drives the setting it shows.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

loadAddon({ before = function()
    WoW.LDBI():Register("DBM", { icon = "dbm" }, {})
    WoW.LDBI():Register("BugSack", { icon = "bug" }, { hide = true })
end })
local O = GlassMiniMapBar.Options
local db = GlassMiniMapBarDB

eq(WoW.settingsCategory and WoW.settingsCategory.name, "Glass MiniMap Bar", "registered under Options > AddOns")
local panel = O._test.panel()
panel:Hide()
panel:Show()
eq(next(GlassMiniMapBar.failures), nil, "built without recorded failures")

-- Every check button and button the panel made, by label text.
local function find(label)
    for _, w in ipairs(WoW.frames) do
        if w._parent == panel and w.label and w.label._text == label then return w end
    end
end
local function buttonsWith(text)
    local out = {}
    for _, w in ipairs(WoW.frames) do
        if w._parent == panel and w._type == "Button" and w._text == text then out[#out + 1] = w end
    end
    return out
end

local skin = find("Glass skin on the collected buttons")
check(skin and skin:GetChecked(), "skin box shows the setting")
skin:SetChecked(false); skin._scripts.OnClick(skin)
eq(db.skin, false, "unchecking turns the skin off")

local hover = find("Open when the mouse is over the launcher (off: open on click)")
hover:SetChecked(false); hover._scripts.OnClick(hover)
eq(db.openOn, "click", "unchecking hover means click")

local last = find("Launcher shows the last button used; right-click it to use it again")
last:SetChecked(true); last._scripts.OnClick(last)
eq(db.lastUsed, true, "last-used option on")

-- Steppers: the first "+" is the hide delay.
local plus = buttonsWith("+")
eq(#plus, 3, "three steppers")
plus[1]._scripts.OnClick(plus[1])
eq(db.hideDelay, 1.0, "hide delay +0.25")
plus[3]._scripts.OnClick(plus[3])
eq(db.buttonSize, 30, "button size +2")

-- The direction cycles.
local dirButton
for _, w in ipairs(WoW.frames) do
    if w._parent == panel and w._text == "Auto (toward the screen centre)" then dirButton = w end
end
check(dirButton, "direction button shows Auto")
dirButton._scripts.OnClick(dirButton)
eq(db.direction, "left", "cycles to Left")

-- The dual list box: Hidden | Shown in bar, arrows, Up / Down.
local lists, arrows = O._test.lists, O._test.arrows
local function labels(list)
    local t = {}
    for _, row in ipairs(list.rows) do if row._shown then t[#t + 1] = row.label._text end end
    return table.concat(t, ",")
end
local function rowOf(list, name)
    for _, row in ipairs(list.rows) do if row._shown and row.name == name then return row end end
end
local function click(w) w._scripts.OnClick(w, "LeftButton") end

eq(labels(lists.hidden), "", "nothing hidden yet")
eq(lists.hidden.empty._shown, true, "...and the hidden list says so")
eq(labels(lists.shown), "BugSack |cff808080(hidden by its addon)|r,DBM", "shown list in bar order, owner-hidden greyed")
eq(arrows.show._enabled, false, "no selection: arrows off")
eq(arrows.hide._enabled, false, "no selection: arrows off (hide)")

-- Select DBM in the shown list, hide it with the < arrow.
click(rowOf(lists.shown, "LibDBIcon10_DBM"))
eq(O._test.selected(), "LibDBIcon10_DBM", "row click selects")
eq(rowOf(lists.shown, "LibDBIcon10_DBM").mark._shown, true, "the selection is marked")
eq(arrows.hide._enabled, true, "a shown selection enables <")
eq(arrows.show._enabled, false, "...not >")
eq(arrows.up._enabled, true, "DBM is second: Up on")
eq(arrows.down._enabled, false, "...Down off (last)")
click(arrows.hide)
eq(db.hidden.LibDBIcon10_DBM, true, "< hides it")
eq(labels(lists.hidden), "DBM", "it moved to the hidden list")
eq(rowOf(lists.hidden, "LibDBIcon10_DBM").mark._shown, true, "still selected over there")
eq(arrows.show._enabled, true, "> now on")
click(arrows.show)
eq(db.hidden.LibDBIcon10_DBM, nil, "> shows it again")

-- Double-click moves across too.
rowOf(lists.shown, "LibDBIcon10_DBM")._scripts.OnDoubleClick(rowOf(lists.shown, "LibDBIcon10_DBM"))
eq(db.hidden.LibDBIcon10_DBM, true, "double-click hides")
rowOf(lists.hidden, "LibDBIcon10_DBM")._scripts.OnDoubleClick(rowOf(lists.hidden, "LibDBIcon10_DBM"))
eq(db.hidden.LibDBIcon10_DBM, nil, "double-click shows")

-- Up / Down set the bar order, which is saved.
click(rowOf(lists.shown, "LibDBIcon10_DBM"))
click(arrows.up)
eq(labels(lists.shown), "DBM,BugSack |cff808080(hidden by its addon)|r", "Up moved DBM first")
eq(names(), "LibDBIcon10_DBM,LibDBIcon10_BugSack", "...in the collector's order too")
eq(db.order[1], "LibDBIcon10_DBM", "order saved")
eq(arrows.up._enabled, false, "first: Up off")
eq(arrows.down._enabled, true, "first: Down on")

-- A button collected later appears in the list, after the ordered ones.
WoW.LDBI():Register("Attune_Broker", { icon = "a" }, {})
WoW.flushTimers(0)
eq(names(), "LibDBIcon10_DBM,LibDBIcon10_BugSack,LibDBIcon10_Attune_Broker", "unordered newcomer goes last")
eq(labels(lists.shown), "DBM,BugSack |cff808080(hidden by its addon)|r,Attune_Broker", "the list follows the collector")

-- Up/Down step over hidden buttons: hide BugSack, move Attune up past it.
GlassMiniMapBar.SetHidden("LibDBIcon10_BugSack", true)
click(rowOf(lists.shown, "LibDBIcon10_Attune_Broker"))
click(arrows.up)
eq(names(), "LibDBIcon10_Attune_Broker,LibDBIcon10_BugSack,LibDBIcon10_DBM", "swapped with the shown neighbour (DBM)")

-- Many buttons: the list scrolls, and keeps the selection in view.
for i = 1, 12 do WoW.LDBI():Register("Extra" .. i, { icon = "x" }, {}) end
WoW.flushTimers(0)
eq(#lists.shown.items, 14, "all shown buttons listed")
lists.shown.frame._scripts.OnMouseWheel(lists.shown.frame, -1)
eq(lists.shown.offset, 1, "the wheel scrolls, even away from the selection")
lists.shown.frame._scripts.OnMouseWheel(lists.shown.frame, -50)
eq(lists.shown.offset, 14 - 8, "...and stops at the end")
click(rowOf(lists.shown, "LibDBIcon10_Extra9"))
click(arrows.down)
check(rowOf(lists.shown, "LibDBIcon10_Extra9") ~= nil, "a moved selection stays in view")

-- The order survives a reload; unknown names keep their place.
local saved = GlassMiniMapBarDB
loadAddon({ db = saved, before = function()
    WoW.LDBI():Register("DBM", { icon = "dbm" }, {})
    WoW.LDBI():Register("Attune_Broker", { icon = "a" }, {})
    WoW.LDBI():Register("Zzz", { icon = "z" }, {})
end })
eq(names(), "LibDBIcon10_Attune_Broker,LibDBIcon10_DBM,LibDBIcon10_Zzz", "saved order applied at login")

done("test_options")
