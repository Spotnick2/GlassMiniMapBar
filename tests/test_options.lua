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

-- The button list: one box per collected button, checked = shown.
local rows = O._test.rows
eq(#rows, 2, "a row per collected button")
eq(rows[1].label._text, "BugSack |cff808080(hidden by its addon)|r", "an owner-hidden button says so")
eq(rows[2].label._text, "DBM", "DBM listed")
eq(rows[2]:GetChecked(), true, "shown by default")
rows[2]:SetChecked(false); rows[2]._scripts.OnClick(rows[2])
eq(db.hidden.LibDBIcon10_DBM, true, "unchecking hides it")
rows[2]:SetChecked(true); rows[2]._scripts.OnClick(rows[2])
eq(db.hidden.LibDBIcon10_DBM, nil, "checking shows it again")

-- A button collected later appears on the next refresh.
WoW.LDBI():Register("Attune_Broker", { icon = "a" }, {})
eq(#rows, 3, "the list follows the collector")

done("test_options")
