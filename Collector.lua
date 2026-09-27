-- Collector.lua: finds the addon buttons around the minimap and takes them
-- into the bar.
--
-- Technique from HidingBar (sfmict, GPLv3), streamlined: a candidate is a
-- NAMED, unprotected, square child of Minimap/MinimapBackdrop between 16 px
-- and half the minimap, with a click or mouse script on itself or a child;
-- LibDBIcon buttons also arrive through its IconCreated callback. Grabbing
-- one replaces its positioning methods on its own table with no-ops, so the
-- owning addon (LibDBIcon repositions on every drag and login) can't pull it
-- back to the minimap; the bar moves it through API.W, the real methods.
-- Show/Hide from the owner are recorded, not applied: the bar decides.
--
-- Nothing here is secure: protected frames are never grabbed, so all of it
-- may run in combat.

GlassMiniMapBar = GlassMiniMapBar or {}
local Collector = {}
GlassMiniMapBar.Collector = Collector
local API = GlassMiniMapBar.API
local W = API.W

Collector.entries = {}             -- ordered by display name
Collector.byName = {}
local entryOf = setmetatable({}, { __mode = "k" })   -- btn -> entry

-- Set by the core: where grabbed buttons live, and who hears about changes.
Collector.host = nil
Collector.onChange = function() end          -- the set or a button's visibility changed
Collector.onClick = function(entry, mouse) end

-- Blizzard's own minimap children, Retail- and Classic-era names (from
-- HidingBar's per-client lists). Never grabbed.
Collector.IGNORE = {
    GameTimeFrame = true, TimeManagerClockButton = true, HelpOpenWebTicketButton = true,
    MinimapBackdrop = true, ExpansionLandingPageMinimapButton = true, QueueStatusButton = true,
    AddonCompartmentFrame = true, MinimapZoomIn = true, MinimapZoomOut = true,
    MiniMapWorldMapButton = true, MiniMapMailFrame = true, MiniMapTracking = true,
    MiniMapTrackingButton = true, MiniMapBattlefieldFrame = true, LFGMinimapFrame = true,
    MinimapZoneTextButton = true, MiniMapLFGFrame = true, GarrisonLandingPageMinimapButton = true,
}
Collector.IGNORE_PATTERNS = {
    "^GatherMatePin%d+$", "^TTMinimapButton%d+$", "^HandyNotes.*Pin",
    "^LibDBIcon10_GlassMiniMapBar$",   -- our own launcher
    "^LibDBIcon10_HidingBar%d+$",      -- HidingBar's, if both are ever enabled
}

-- "LibDBIcon10_DBM" -> "DBM", "AltStableMinimapButton" -> "AltStable".
function Collector.DisplayName(name)
    local n = name:gsub("^LibDBIcon10_", "")
    n = n:gsub("[_%-]?[Mm]ini[Mm]ap[_%-]?[Bb]utton$", ""):gsub("[_%-]?[Mm]ini[Mm]ap[Bb]tn$", "")
    if n == "" then n = name end
    return n
end

local function hasClick(frame, depth)
    for _, s in ipairs({ "OnClick", "OnMouseUp", "OnMouseDown" }) do
        if W.HasScript(frame, s) and W.GetScript(frame, s) then return true end
    end
    if depth < 3 then
        for _, child in ipairs({ W.GetChildren(frame) }) do
            if hasClick(child, depth + 1) then return true end
        end
    end
    return false
end

-- Why `frame` (a child of `parent`) is not a candidate, or nil if it is.
function Collector.Reject(frame, parent)
    if entryOf[frame] then return "grabbed" end
    local name = W.GetName(frame)
    if not name then return "no name" end
    if Collector.IGNORE[name] then return "Blizzard" end
    for _, p in ipairs(Collector.IGNORE_PATTERNS) do
        if name:match(p) then return "ignored" end
    end
    if W.IsForbidden(frame) or W.IsProtected(frame) then return "protected" end
    local w, h = W.GetSize(frame)
    if type(w) ~= "number" or type(h) ~= "number" then return "no size" end
    local pw, ph = W.GetSize(parent)
    if math.max(w, h) <= 16 or math.abs(w - h) >= 5 then return "not a button shape" end
    if type(pw) == "number" and (w >= pw * 0.5 or h >= ph * 0.5) then return "too large" end
    if not hasClick(frame, 0) then return "not clickable" end
    return nil
end

-- Stop animations that would move or fade the button in the bar (LibDBIcon's
-- showOnMouseover fade); rotations and plain timers are harmless.
local function void() end
local function tameAnimations(btn)
    for _, ag in ipairs({ W.GetAnimationGroups(btn) }) do
        for _, a in ipairs({ ag:GetAnimations() }) do
            local t = a:GetObjectType()
            if a:GetTarget() == btn and t ~= "Animation" and t ~= "Rotation" then
                ag:Stop()
                ag.Play, ag.Restart = void, void
                break
            end
        end
    end
end

local VOIDED = { "SetPoint", "ClearAllPoints", "SetAllPoints", "SetParent", "SetScale", "SetAlpha",
                 "SetFrameStrata", "SetFrameLevel", "SetFixedFrameStrata", "SetFixedFrameLevel",
                 "SetIgnoreParentScale", "StartMoving", "SetSize", "SetWidth", "SetHeight",
                 "SetHitRectInsets", "RegisterForDrag" }

local function installOverrides(btn, entry)
    for _, m in ipairs(VOIDED) do btn[m] = void end
    btn.Show = function() if not entry.wanted then entry.wanted = true; Collector.onChange() end end
    btn.Hide = function() if entry.wanted then entry.wanted = false; Collector.onChange() end end
    btn.SetShown = function(self, show) if show then self:Show() else self:Hide() end end
    btn.IsShown = function() return entry.wanted end
end

local function hookClicks(btn, entry)
    local script = (W.HasScript(btn, "OnClick") and W.GetScript(btn, "OnClick")) and "OnClick" or "OnMouseUp"
    entry.clickScript = script
    W.HookScript(btn, script, function(_, mouse)
        API.Try("click", Collector.onClick, entry, mouse)
    end)
end

local function sortEntries()
    table.sort(Collector.entries, function(a, b)
        local x, y = a.display:lower(), b.display:lower()
        if x ~= y then return x < y end
        return a.name < b.name
    end)
end

-- Take `btn` into the bar. Returns the entry, or nil when it can't be taken.
function Collector.Grab(btn)
    if entryOf[btn] then return entryOf[btn] end
    local name = W.GetName(btn)
    if not name or not Collector.host then return nil end
    if W.IsForbidden(btn) or W.IsProtected(btn) then return nil end
    local entry = { btn = btn, name = name, display = Collector.DisplayName(name), wanted = W.IsShown(btn) }
    local ok, err = pcall(function()
        W.StopMovingOrSizing(btn)
        W.SetIgnoreParentScale(btn, false)
        W.SetFixedFrameStrata(btn, false)
        W.SetFixedFrameLevel(btn, false)
        W.SetHitRectInsets(btn, 0, 0, 0, 0)
        -- No mouse buttons: no more dragging it around the minimap ring.
        -- A client that refuses the empty call must not cost us the button.
        pcall(W.RegisterForDrag, btn)
        W.SetAlpha(btn, 1)
        tameAnimations(btn)
        entry.width = W.GetWidth(btn)
        W.SetParent(btn, Collector.host)
        W.ClearAllPoints(btn)
        W.Hide(btn)                      -- the bar's layout shows what it places
        installOverrides(btn, entry)
        hookClicks(btn, entry)
    end)
    if not ok then
        API.Fail("grab:" .. name, err)
        return nil
    end
    entryOf[btn] = entry
    Collector.byName[name] = entry
    table.insert(Collector.entries, entry)
    sortEntries()
    return entry
end

-- Scan the minimap for candidates. Returns the number newly grabbed and, for
-- /gmb scan, the rejects: { { name = , reason = , secure = }, ... }.
function Collector.Scan()
    local added, rejects = 0, {}
    for _, parentName in ipairs({ "Minimap", "MinimapBackdrop" }) do
        local parent = rawget(_G, parentName)
        if parent then
            for _, child in ipairs({ W.GetChildren(parent) }) do
                local why = Collector.Reject(child, parent)
                if why == nil then
                    if Collector.Grab(child) then added = added + 1 end
                elseif why ~= "grabbed" then
                    local name = W.GetName(child)
                    if name then
                        table.insert(rejects, { name = name, reason = why, secure = API.IsBlizzardGlobal(name) })
                    end
                end
            end
        end
    end
    if added > 0 then Collector.onChange() end
    return added, rejects
end

-- LibDBIcon_IconCreated: (event, button, name).
function Collector.OnIconCreated(_, btn)
    if not btn then return end
    local parent = W.GetParent(btn) or rawget(_G, "Minimap")
    if Collector.Reject(btn, parent) == nil and Collector.Grab(btn) then Collector.onChange() end
end

-- Entries the bar should show: wanted by their addon, not hidden by the user.
function Collector.Visible(hidden)
    local list = {}
    for _, e in ipairs(Collector.entries) do
        if e.wanted and not hidden[e.name] then list[#list + 1] = e end
    end
    return list
end

-- Click a grabbed button again, with the mouse button used last time.
function Collector.Replay(name, mouse)
    local e = Collector.byName[name]
    if not e then return false end
    mouse = mouse or "LeftButton"
    local btn = e.btn
    if e.clickScript == "OnClick" and btn.Click then
        return API.Try("replay:" .. name, function() btn:Click(mouse); return true end) == true
    end
    return API.Try("replay:" .. name, function()
        local down, up = W.GetScript(btn, "OnMouseDown"), W.GetScript(btn, "OnMouseUp")
        if down then down(btn, mouse) end
        if up then up(btn, mouse) end
        return true
    end) == true
end

Collector._test = { entryOf = entryOf }
