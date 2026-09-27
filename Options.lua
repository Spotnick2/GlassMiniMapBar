-- Options.lua: the panel under Options > AddOns.
--
-- A canvas category (Settings.RegisterCanvasLayoutCategory), built by hand
-- the way Priestly's is: the Classic templates (OptionsSliderTemplate,
-- InterfaceOptionsCheckButtonTemplate) are not in this client, and a missing
-- template doesn't throw, it just yields a bare frame. So every widget asks
-- for its template, checks for a region the template should bring, and draws
-- its own art when the template didn't apply. Numbers use - / + steppers.

GlassMiniMapBar = GlassMiniMapBar or {}
local Options = {}
GlassMiniMapBar.Options = Options
local API = GlassMiniMapBar.API
local Collector = GlassMiniMapBar.Collector

local panel
local controls = {}              -- widgets that mirror a setting: { refresh = fn }
local rows = {}                  -- button list checkboxes, reused across refreshes

local CHECK_ART = {
    normal = "Interface\\Buttons\\UI-CheckBox-Up", pushed = "Interface\\Buttons\\UI-CheckBox-Down",
    highlight = "Interface\\Buttons\\UI-CheckBox-Highlight", checked = "Interface\\Buttons\\UI-CheckBox-Check",
}

local function safeFrame(ftype, parent, template, proof)
    local ok, f = pcall(CreateFrame, ftype, nil, parent, template)
    if ok and f then return f, f[proof] ~= nil end
    return CreateFrame(ftype, nil, parent), false
end

local function checkbox(parent, label)
    local cb, templated = safeFrame("CheckButton", parent, "UICheckButtonTemplate", "Text")
    cb:SetSize(24, 24)
    if not templated then
        cb:SetNormalTexture(CHECK_ART.normal)
        cb:SetPushedTexture(CHECK_ART.pushed)
        cb:SetHighlightTexture(CHECK_ART.highlight)
        cb:SetCheckedTexture(CHECK_ART.checked)
    end
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText(label)
    cb.label = fs
    return cb
end

local function button(parent, text, width)
    local b, templated = safeFrame("Button", parent, "UIPanelButtonTemplate", "Text")
    b:SetSize(width or 24, 22)
    if not templated then
        local bg = b:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(b)
        bg:SetColorTexture(0.2, 0.25, 0.32, 0.9)
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("CENTER")
        b:SetFontString(fs)
    end
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

local listTop, listNote
local COLUMN_WIDTH, ROW_HEIGHT, PER_COLUMN = 210, 24, 14

-- One checkbox per collected button, two or three columns, checked = shown.
local function refreshList()
    local entries = Collector.entries
    for i, e in ipairs(entries) do
        local cb = rows[i]
        if not cb then
            cb = checkbox(panel, "")
            cb:SetScript("OnClick", function(self)
                GlassMiniMapBar.SetHidden(self.entryName, not self:GetChecked())
            end)
            rows[i] = cb
        end
        local col, row = math.floor((i - 1) / PER_COLUMN), (i - 1) % PER_COLUMN
        cb:ClearAllPoints()
        cb:SetPoint("TOPLEFT", listTop, "BOTTOMLEFT", col * COLUMN_WIDTH, -4 - row * ROW_HEIGHT)
        cb.entryName = e.name
        cb.label:SetText(e.wanted and e.display or (e.display .. " |cff808080(hidden by its addon)|r"))
        cb:SetChecked(not GlassMiniMapBar.db.hidden[e.name])
        cb:Show()
        cb.label:Show()
    end
    for i = #entries + 1, #rows do
        rows[i]:Hide()
        rows[i].label:Hide()
    end
    listNote:SetShown(#entries == 0)
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

    listTop = heading(panel, "Buttons (uncheck to hide)", a, -18)
    listNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    listNote:SetPoint("TOPLEFT", listTop, "BOTTOMLEFT", 0, -8)
    listNote:SetText("No minimap buttons collected yet. Try /gmb scan.")
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

Options._test = { panel = function() return panel end, rows = rows }
