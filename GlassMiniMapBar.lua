-- GlassMiniMapBar.lua: saved variables, startup, slash command.
--
-- GlassMiniMapBarDB (account-wide):
--   minimap    LibDBIcon's table for the launcher (minimapPos, lock, hide)
--   hidden     [buttonName] = true for buttons the user hid in the options
--   openOn     "hover" | "click"
--   hideDelay  seconds the mouse may be away before the bar closes
--   direction  "auto" | "left" | "right" | "up" | "down"
--   perRow     buttons per line before wrapping
--   buttonSize px
--   skin       glass orb skin on the collected buttons
--   animate    the bar grows out of the launcher and shrinks back
--   lastUsed   launcher wears the last button used; right-click repeats it
--   last       { name = , mouse = } the last button clicked in the bar

GlassMiniMapBar = GlassMiniMapBar or {}
local ADDON = ...
local API = GlassMiniMapBar.API
local Bar = GlassMiniMapBar.Bar
local Collector = GlassMiniMapBar.Collector

GlassMiniMapBar.DEFAULTS = {
    openOn = "hover", hideDelay = 0.75, direction = "auto", perRow = 12, buttonSize = 28,
    skin = true, lastUsed = false, animate = true,
}
GlassMiniMapBar.LIMITS = {
    hideDelay = { 0.25, 3, 0.25 }, perRow = { 1, 30, 1 }, buttonSize = { 20, 40, 2 },
}

local db

local function clamp(key, v)
    local l = GlassMiniMapBar.LIMITS[key]
    if type(v) ~= "number" then return GlassMiniMapBar.DEFAULTS[key] end
    return math.max(l[1], math.min(l[2], v))
end

-- Fill in what is missing; fix what is malformed. Never wipes the user's data.
function GlassMiniMapBar.LoadDB(saved)
    db = type(saved) == "table" and saved or {}
    if type(db.minimap) ~= "table" then db.minimap = {} end
    if type(db.hidden) ~= "table" then db.hidden = {} end
    for k, v in pairs(GlassMiniMapBar.DEFAULTS) do
        if db[k] == nil or type(db[k]) ~= type(v) then db[k] = v end
    end
    if db.openOn ~= "hover" and db.openOn ~= "click" then db.openOn = "hover" end
    if not Bar.ARROWS[db.direction] and db.direction ~= "auto" then db.direction = "auto" end
    for k in pairs(GlassMiniMapBar.LIMITS) do db[k] = clamp(k, db[k]) end
    if type(db.last) ~= "table" or type(db.last.name) ~= "string" then db.last = nil end
    GlassMiniMapBar.db = db
    return db
end

-- Apply a setting from the options panel (or a slash command).
function GlassMiniMapBar.Set(key, value)
    if key == "lock" then            -- lives in LibDBIcon's table, not ours
        db.minimap.lock = value or nil
        Bar.ApplyLock()
        return
    end
    if GlassMiniMapBar.LIMITS[key] then value = clamp(key, value) end
    db[key] = value
    if key == "skin" then Bar.ApplySkin()
    elseif key == "lastUsed" then Bar.UpdateLauncherIcon()
    elseif key == "animate" then return
    else Bar.Layout(); Bar.UpdateLauncherIcon() end
end

function GlassMiniMapBar.SetHidden(name, hidden)
    db.hidden[name] = hidden and true or nil
    Bar.Layout()
    Bar.UpdateLauncherIcon()
end

function GlassMiniMapBar.OpenOptions()
    local O = GlassMiniMapBar.Options
    if not (O and API.OpenSettings(O.category)) then
        API.Print("the options panel is not available on this client (Options > AddOns).")
    end
end

local function onChange()
    Bar.ApplySkin()
    Bar.Layout()
    Bar.UpdateLauncherIcon()
    if GlassMiniMapBar.Options then GlassMiniMapBar.Options.Refresh() end
end

local function onClick(entry, mouse)
    db.last = { name = entry.name, mouse = mouse }
    Bar.UpdateLauncherIcon()
end

local function start()
    Collector.onChange = onChange
    Collector.onClick = onClick
    Bar.Build(db)
    Collector.Scan()
    onChange()
    -- Addons that make their button late (after a timer, or after their own
    -- PLAYER_LOGIN work). Opening the bar rescans as well.
    for _, delay in ipairs({ 0, 2, 10 }) do C_Timer.After(delay, Collector.Scan) end
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON then
        self:UnregisterEvent("ADDON_LOADED")
        GlassMiniMapBarDB = GlassMiniMapBar.LoadDB(GlassMiniMapBarDB)
        if GlassMiniMapBar.Options then GlassMiniMapBar.Options.Register() end
    elseif event == "PLAYER_LOGIN" then
        API.Try("start", start)
        if API.ClientBuild() ~= GlassMiniMapBar.MEASURED_ON_BUILD then
            API.Print("measured on " .. GlassMiniMapBar.MEASURED_ON_BUILD .. ", this client is "
                .. API.ClientBuild() .. ": if something misbehaves, /gmb failures.")
        end
    end
end)
API.RegisterEvent(events, "ADDON_LOADED")
API.RegisterEvent(events, "PLAYER_LOGIN")

--------------------------------------------------------------------------------
-- /gmb
--------------------------------------------------------------------------------

local function slash(msg)
    local cmd = (msg or ""):lower():match("^%s*(%S*)")
    if cmd == "scan" then
        local added, rejects = Collector.Scan(true)
        API.Print(("%d collected (%d new)."):format(#Collector.entries, added))
        for _, e in ipairs(Collector.entries) do
            local state = db.hidden[e.name] and "hidden by you"
                or (not e.wanted and "hidden by its addon") or "shown"
            API.Print(("  |cff7fd4ff%s|r (%s): %s"):format(e.display, e.name, state))
        end
        for _, r in ipairs(rejects) do
            API.Print(("  skipped %s: %s%s"):format(r.name, r.reason, r.secure and " [secure global]" or ""))
        end
    elseif cmd == "failures" then
        local any = false
        for k, v in pairs(GlassMiniMapBar.failures) do
            any = true
            API.Print(k .. ": " .. v)
        end
        if not any then API.Print("no failures recorded.") end
    elseif cmd == "open" then
        Bar.Open()
    elseif cmd == "reset" then
        db.minimap.minimapPos = nil
        API.Print("launcher position reset: /reload to apply.")
    elseif cmd == "" or cmd == "options" then
        GlassMiniMapBar.OpenOptions()
    else
        API.Print("/gmb [options] | open | scan | failures | reset")
    end
end

SLASH_GLASSMINIMAPBAR1 = "/gmb"
SlashCmdList.GLASSMINIMAPBAR = slash

GlassMiniMapBar._test = { slash = slash, start = start }
