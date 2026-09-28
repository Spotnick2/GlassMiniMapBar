-- Options.lua: the panel under Options > AddOns.
--
-- A canvas category (Settings.RegisterCanvasLayoutCategory) with plain
-- template widgets. UICheckButtonTemplate and UIPanelButtonTemplate are
-- measured present on Forever (PORTING-TBC-TO-FOREVER.md, "UI templates").
-- Numbers use - / + steppers: exact values, no slider drag to fiddle with.

GlassMiniMapBar = GlassMiniMapBar or {}
local Options = {}
GlassMiniMapBar.Options = Options
local API = GlassMiniMapBar.API
local Collector = GlassMiniMapBar.Collector

local panel
local controls = {}              -- widgets that mirror a setting: { refresh = fn }

-- A check button with a label we own (template label fields have moved
-- between UI versions).
local function checkbox(parent, label)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(label)
    cb.label = fs
    return cb
end

local function button(parent, text, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width or 24, 22)
    b:SetText(text)
    return b
end

local function heading(parent, text, anchor, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, y or -16)
    fs:SetText(text)
    return fs
end

-- A boolean setting. `get`/`set` default to GlassMiniMapBar.db[key] / Set(key).
local function toggle(parent, anchor, key, label, get)
    local cb = checkbox(parent, label)
    cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
    get = get or function() return GlassMiniMapBar.db[key] == true end
    cb:SetScript("OnClick", function(self) GlassMiniMapBar.Set(key, self:GetChecked() == true) end)
    table.insert(controls, { refresh = function() cb:SetChecked(get()) end })
    return cb
end

-- A number setting with - / + steppers inside the LIMITS range.
local function stepper(parent, anchor, key, label, fmt)
    local lim = GlassMiniMapBar.LIMITS[key]
    local minus = button(parent, "-")
    minus:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    value:SetWidth(48)
    value:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    local plus = button(parent, "+")
    plus:SetPoint("LEFT", value, "RIGHT", 2, 0)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", plus, "RIGHT", 8, 0)
    fs:SetText(label)
    local function refresh() value:SetText(fmt:format(GlassMiniMapBar.db[key])) end
    local function step(sign)
        GlassMiniMapBar.Set(key, GlassMiniMapBar.db[key] + sign * lim[3])
        refresh()
    end
    minus:SetScript("OnClick", function() step(-1) end)
    plus:SetScript("OnClick", function() step(1) end)
    table.insert(controls, { refresh = refresh })
    return minus
end

Options.DIRECTIONS = { "auto", "left", "right", "up", "down" }
local DIRECTION_TEXT = { auto = "Auto (toward the screen centre)", left = "Left", right = "Right", up = "Up", down = "Down" }

local function cycle(parent, anchor)
    local b = button(parent, "", 220)
    b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", b, "RIGHT", 8, 0)
    fs:SetText("Opens toward")
    local function refresh() b:SetText(DIRECTION_TEXT[GlassMiniMapBar.db.direction]) end
    b:SetScript("OnClick", function()
        local cur = GlassMiniMapBar.db.direction
        for i, d in ipairs(Options.DIRECTIONS) do
            if d == cur then
                GlassMiniMapBar.Set("direction", Options.DIRECTIONS[i % #Options.DIRECTIONS + 1])
                break
            end
        end
        refresh()
    end)
    table.insert(controls, { refresh = refresh })
    return b
end

-- The button lists: a classic dual list box. Hidden on the left, Shown in
-- bar on the right (in bar order), arrows between them, Up/Down beside the
-- shown list. One selection across both lists; double-click moves a button
-- across. The mouse wheel scrolls a list longer than its rows.
local LIST_W, ROW_H, ROWS = 240, 20, 8
local listTop
local lists = {}                 -- hidden, shown: { frame, rows, items, offset, empty }
local arrows = {}                -- show, hide, up, down
local selected                   -- a button name, or nil

local function greyed(e)
    return e.wanted and e.display or (e.display .. " |cff808080(hidden by its addon)|r")
end

local refreshList

local function moveAcross(name)
    if not name then return end
    GlassMiniMapBar.SetHidden(name, not GlassMiniMapBar.db.hidden[name])
    refreshList()
end

-- `follow`: bring the selection into view (after a select, move or re-sort);
-- the mouse wheel passes false so it can scroll away from it.
local function fill(list, follow)
    local items = list.items
    local maxOffset = math.max(0, #items - ROWS)
    for i, e in ipairs(items) do
        if follow and e.name == selected then
            if i <= list.offset then list.offset = i - 1
            elseif i > list.offset + ROWS then list.offset = i - ROWS end
        end
    end
    list.offset = math.max(0, math.min(list.offset, maxOffset))
    for r, row in ipairs(list.rows) do
        local e = items[r + list.offset]
        row.name = e and e.name
        row.label:SetText(e and greyed(e) or "")
        row.mark:SetShown(e ~= nil and e.name == selected)
        row:SetShown(e ~= nil)
    end
    list.empty:SetShown(#items == 0)
end

local function makeList(key, title, anchor, x, emptyText)
    local f = CreateFrame("Frame", nil, panel)
    f:SetSize(LIST_W, ROWS * ROW_H + 8)
    f:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", x, -30)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.45)
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local t = f:CreateTexture(nil, "BORDER")
        t:SetColorTexture(0.62, 0.5, 0.22, 0.9)
        if side == "TOP" or side == "BOTTOM" then
            t:SetHeight(1); t:SetPoint(side .. "LEFT"); t:SetPoint(side .. "RIGHT")
        else
            t:SetWidth(1); t:SetPoint("TOP" .. side); t:SetPoint("BOTTOM" .. side)
        end
    end
    local head = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    head:SetPoint("BOTTOMLEFT", f, "TOPLEFT", 2, 4)
    head:SetText(title)
    local empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER")
    empty:SetText(emptyText)

    local list = { frame = f, rows = {}, items = {}, offset = 0, empty = empty }
    for r = 1, ROWS do
        local row = CreateFrame("Button", nil, f)
        row:SetSize(LIST_W - 8, ROW_H)
        row:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4 - (r - 1) * ROW_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints(row)
        hl:SetColorTexture(1, 1, 1, 0.08)
        local mark = row:CreateTexture(nil, "ARTWORK")
        mark:SetAllPoints(row)
        mark:SetColorTexture(0.85, 0.68, 0.12, 0.35)
        mark:Hide()
        row.mark = mark
        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("LEFT", row, "LEFT", 6, 0)
        label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
        label:SetJustifyH("LEFT")
        row.label = label
        row:SetScript("OnClick", function(self)
            selected = self.name
            refreshList()
        end)
        row:SetScript("OnDoubleClick", function(self) moveAcross(self.name) end)
        list.rows[r] = row
    end
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        list.offset = list.offset - delta
        fill(list, false)
    end)
    lists[key] = list
    return f
end

function refreshList()
    local hidden = GlassMiniMapBar.db.hidden
    local h, s, found, at = {}, {}, false, nil
    for _, e in ipairs(Collector.entries) do
        if hidden[e.name] then h[#h + 1] = e else s[#s + 1] = e end
        if e.name == selected then found = true end
    end
    if not found then selected = nil end
    for i, e in ipairs(s) do if e.name == selected then at = i end end
    lists.hidden.items, lists.shown.items = h, s
    fill(lists.hidden, true)
    fill(lists.shown, true)
    arrows.show:SetEnabled(selected ~= nil and hidden[selected] == true)
    arrows.hide:SetEnabled(at ~= nil)
    arrows.up:SetEnabled(at ~= nil and at > 1)
    arrows.down:SetEnabled(at ~= nil and at < #s)
end

local function buildLists(anchor)
    listTop = heading(panel, "Buttons", anchor, -18)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", listTop, "BOTTOMLEFT", 0, -4)
    hint:SetText("Select a button, then use the arrows to show or hide it (or double-click it). Up / Down set its place in the bar.")

    local left = makeList("hidden", "Hidden", listTop, 0, "No hidden buttons")
    local right = makeList("shown", "Shown in bar", listTop, LIST_W + 56, "No buttons collected yet (/gmb scan)")

    arrows.show = button(panel, ">", 36)
    arrows.show:SetPoint("BOTTOM", left, "RIGHT", 28, 4)
    arrows.show:SetScript("OnClick", function() moveAcross(selected) end)
    arrows.hide = button(panel, "<", 36)
    arrows.hide:SetPoint("TOP", left, "RIGHT", 28, -4)
    arrows.hide:SetScript("OnClick", function() moveAcross(selected) end)

    arrows.up = button(panel, "Up", 60)
    arrows.up:SetPoint("BOTTOMLEFT", right, "RIGHT", 8, 4)
    arrows.up:SetScript("OnClick", function()
        if selected then GlassMiniMapBar.MoveButton(selected, -1) end
        refreshList()
    end)
    arrows.down = button(panel, "Down", 60)
    arrows.down:SetPoint("TOPLEFT", right, "RIGHT", 8, -4)
    arrows.down:SetScript("OnClick", function()
        if selected then GlassMiniMapBar.MoveButton(selected, 1) end
        refreshList()
    end)
end

-- Called on every collector change; a no-op until the panel was first shown.
function Options.Refresh()
    if not (listTop and GlassMiniMapBar.db) then return end
    for _, c in ipairs(controls) do c.refresh() end
    refreshList()
end

local function build()
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cff7fd4ffGlass|r MiniMap Bar")
    local sub = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    sub:SetWidth(600)
    sub:SetJustifyH("LEFT")
    sub:SetText("Collects the minimap buttons into one glass bar. These options: right-click the launcher "
        .. "(shift-right-click when it repeats the last button), or /gmb.")

    local h = heading(panel, "Behaviour", sub, -18)
    local a = toggle(panel, h, "openOn", "Open when the mouse is over the launcher (off: open on click)",
        function() return GlassMiniMapBar.db.openOn == "hover" end)
    a:SetScript("OnClick", function(self) GlassMiniMapBar.Set("openOn", self:GetChecked() and "hover" or "click") end)
    a = toggle(panel, a, "lastUsed", "Launcher shows the last button used; right-click it to use it again")
    a = toggle(panel, a, "skin", "Glass skin on the collected buttons")
    a = toggle(panel, a, "animate", "Animate the bar growing out of the launcher")
    a = toggle(panel, a, "lock", "Lock the launcher in place on the minimap",
        function() return GlassMiniMapBar.db.minimap.lock == true end)
    a = stepper(panel, a, "hideDelay", "Seconds before the bar closes", "%.2f")

    h = heading(panel, "Layout", a, -18)
    a = cycle(panel, h)
    a = stepper(panel, a, "perRow", "Buttons per row", "%d")
    a = stepper(panel, a, "buttonSize", "Button size", "%d")

    buildLists(a)
end

-- Called at ADDON_LOADED: the panel is registered then, built on first show.
function Options.Register()
    panel = CreateFrame("Frame", "GlassMiniMapBarOptions")
    panel.name = "Glass MiniMap Bar"
    panel:Hide()
    local built = false
    panel:SetScript("OnShow", function()
        if not built then
            built = true
            API.Try("options", build)
        end
        API.Try("options.refresh", Options.Refresh)
    end)
    Options.category = API.RegisterSettingsPanel(panel, panel.name)
    return panel
end

Options._test = {
    panel = function() return panel end,
    lists = lists,
    arrows = arrows,
    selected = function() return selected end,
}
