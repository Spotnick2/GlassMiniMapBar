-- Compat.lua: the one place this addon touches client APIs that moved, may be
-- absent, or behave differently on WoW: Forever. Everything else calls through
-- GlassMiniMapBar.API. Nothing is injected into _G.

GlassMiniMapBar = GlassMiniMapBar or {}
local API = {}
GlassMiniMapBar.API = API

-- The build the notes this addon relies on were measured on. Bump only after
-- re-measuring in game; tests/test_toc.lua pins the same literal. Until then a
-- development copy says so at login (API.IsDevelopmentCopy); a release keeps
-- quiet.
GlassMiniMapBar.MEASURED_ON_BUILD = "1.60.1.70009"

function API.Print(msg)
    print("|cff7fd4ffGlassMiniMapBar|r " .. msg)
end

function API.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

function API.ClientBuild()
    local version, build = GetBuildInfo()
    return tostring(version) .. "." .. tostring(build)
end

-- The build notice is for whoever re-measures, not for players: a release
-- that still runs on a newer client gains nothing from being told it was
-- measured on an older one, and what flags an addon out of date is the TOC's
-- Interface number. So only a development copy speaks: `dev` from
-- Tools/deploy.ps1, or the raw packager token of an unpackaged checkout.
-- The token is assembled, never written whole: the packager replaces it in
-- every file, and v1.0.1 shipped `version == "v1.0.1"` here, so each release
-- took itself for a development copy.
local VERSION_TOKEN = "@" .. "project-version" .. "@"
function API.IsDevelopmentCopy()
    local version = C_AddOns.GetAddOnMetadata("GlassMiniMapBar", "Version")
    return version == "dev" or version == VERSION_TOKEN
end

-- The one failure recorder: key -> first error, read by /gmb failures.
GlassMiniMapBar.failures = {}

function API.Fail(key, err)
    if GlassMiniMapBar.failures[key] ~= nil then return end
    local msg = "(unprintable error)"
    if type(err) == "string" then
        msg = err
    elseif not API.IsSecret(err) then
        local ok, s = pcall(tostring, err)
        if ok and type(s) == "string" then msg = s end
    end
    GlassMiniMapBar.failures[key] = msg
end

-- Run fn under pcall; a throw is recorded under `key` and nil is returned.
function API.Try(key, fn, ...)
    local ok, a, b = pcall(fn, ...)
    if ok then return a, b end
    API.Fail(key, a)
    return nil
end

-- RegisterEvent throws on an unknown name and returns false on a refusal.
-- Both count as failure, and every failure is reported.
function API.RegisterEvent(frame, name)
    local ok, registered = pcall(frame.RegisterEvent, frame, name)
    if ok and registered ~= false then return true end
    local why = ok and "refused" or tostring(registered)
    API.Fail("event:" .. name, why)
    API.Print("|cffff6060could not register|r " .. name .. " (" .. why .. ")")
    return false
end

-- The widget methods themselves, taken from a Frame's metatable. A grabbed
-- button has SetPoint, SetParent, Show... replaced on its own table so its
-- addon can't pull it back onto the minimap; the bar moves it through these.
-- Frame methods work on Buttons and CheckButtons too (HidingBar does the same).
API.W = getmetatable(CreateFrame("Frame")).__index

-- issecurevariable(name) should be true for a global Blizzard's own code
-- created, false for one an addon's CreateFrame made. UNMEASURED on Forever,
-- so it is only reported by /gmb scan for now; the grab filter is the
-- Collector's name list. If it measures right it can replace the list.
function API.IsBlizzardGlobal(name)
    if not (name and issecurevariable) then return false end
    local ok, secure = pcall(issecurevariable, name)
    return ok and secure == true
end

-- The Settings panel (Options > AddOns). Returns the category, or nil.
function API.RegisterSettingsPanel(panel, name)
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then
        return nil
    end
    local category = Settings.RegisterCanvasLayoutCategory(panel, name)
    Settings.RegisterAddOnCategory(category)
    return category
end

function API.OpenSettings(category)
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
        return true
    end
    return false
end

-- Menus a grabbed button may open (right-click menus): the bar stays open
-- while the mouse is over one, so moving into the menu doesn't hide the
-- button that owns it. Globals looked up late: most are created on demand.
local MENU_FRAMES = { "DropDownList1", "DropDownList2", "L_DropDownList1", "L_DropDownList2",
                      "LibDropDownMenu_List1", "LibDropDownMenu_List2" }
function API.MouseOverMenu()
    for _, name in ipairs(MENU_FRAMES) do
        local f = rawget(_G, name)
        if f and f:IsShown() and f:IsMouseOver() then return true end
    end
    local M = rawget(_G, "Menu")
    if M and M.GetManager then
        local ok, over = pcall(function()
            local menu = M.GetManager():GetOpenMenu()
            return menu and menu:IsMouseOver()
        end)
        if ok and over then return true end
    end
    return false
end
