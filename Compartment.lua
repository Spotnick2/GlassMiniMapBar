-- Compartment.lua: Blizzard's "AddOns" compartment, as buttons in the bar.
--
-- The compartment (Blizzard_Minimap\Mainline\AddonCompartment.lua) is a list,
-- AddonCompartmentFrame.registeredAddons, of { text, icon, func, funcOnEnter,
-- funcOnLeave }: one per addon whose TOC names an AddonCompartmentFunc (filled
-- in bulk by RegisterAddons at PLAYER_ENTERING_WORLD), plus any added by
-- RegisterAddon at runtime (LibDBIcon's AddButtonToCompartment among them).
-- Every path that changes the list ends in UpdateDisplay (RegisterAddons,
-- RegisterAddon, and LibDBIcon's RemoveButtonFromCompartment, which removes
-- its entry directly), so a hook there, reconciled on the next frame, sees
-- all of them. Opening the bar reconciles too, as a backstop.
--
-- Each entry becomes a button of ours in the bar. Its callbacks are called the
-- way the two known callers expect:
--   click   func(nil, { buttonName = mouse }, ourButton)
--   hover   funcOnEnter(ourButton, entry) / funcOnLeave(ourButton, entry)
-- Blizzard's TOC wrapper reads only buttonName (and ignores a hover's second
-- argument); LibDBIcon's passes the click's third argument to the broker's
-- OnClick as the frame to anchor to, and its hover reads entry.text. Nothing
-- beyond those two is promised: another custom entry gets the same calls.
--
-- Duplicates: a LibDBIcon button that also put itself in the compartment is
-- the same addon twice. When its minimap button is in the bar (collected and
-- shown by its addon), the compartment copy is left out: known identity first
-- (the button's own compartmentData IS the entry), then the same title (colour
-- and texture codes stripped, case ignored; a minimap button's "_" read as a
-- space, since LibDBIcon object names stand in for spaces with it:
-- LibDBIcon10_Leatrix_Maps is the AddOns list's "Leatrix Maps", seen on
-- 70374; and a LibDBIcon button's data object label and text: Portal
-- Roulette's button is LibDBIcon10_PortalRoulette, its entry "Portal
-- Roulette"), only when exactly one bar button
-- has it. A compartment entry is kept whenever its minimap button isn't in the bar.
--
-- The option `compartment` (on by default): while on, the entries are in the
-- bar and Blizzard's AddOns button is hidden (API.SystemHider: reparented,
-- deferred, given back in Edit Mode); off gives the button back. Only one
-- addon should manage AddonCompartmentFrame.

GlassMiniMapBar = GlassMiniMapBar or {}
local API = GlassMiniMapBar.API
local Collector = GlassMiniMapBar.Collector
local Compartment = {}
GlassMiniMapBar.Compartment = Compartment

Compartment.PREFIX = "AddOns:"   -- entry names in the hidden/order lists
Compartment.SIZE = 31            -- a LibDBIcon button's size: the bar scales every button alike

local byData = setmetatable({}, { __mode = "k" })   -- entry data -> entry name
local pool = {}                                     -- spare buttons
local scheduled, started, enabled = false, false, false
local hider

local function frame() return rawget(_G, "AddonCompartmentFrame") end

-- "|cff7fd4ffGlass|r Mail" -> "Glass Mail".
function Compartment.CleanText(s)
    if type(s) ~= "string" then return nil end
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

local function key(s)
    s = Compartment.CleanText(s)
    return s and s:lower() or nil
end

-- The compartment's list as it stands (plain tables only).
function Compartment.List()
    local f = frame()
    local list = f and rawget(f, "registeredAddons")
    if type(list) ~= "table" then return {} end
    local out = {}
    for _, data in ipairs(list) do
        if type(data) == "table" then out[#out + 1] = data end
    end
    return out
end

-- The compartment entries that already have their minimap button in the bar.
local function duplicates(list)
    local dup = {}
    local lib = LibStub and LibStub("LibDBIcon-1.0", true)
    if lib and type(lib.objects) == "table" then
        for _, btn in pairs(lib.objects) do
            local data = type(btn) == "table" and rawget(btn, "compartmentData")
            local name = data and API.W.GetName(btn)
            local e = name and Collector.byName[name]
            if e and e.wanted and not e.own then dup[data] = true end
        end
    end
    -- The same title, unambiguous only: one shown minimap button with it. A
    -- LibDBIcon button's titles are its name and its data object's label and
    -- text: LibDBIcon10_PortalRoulette is "Portal Roulette" (text).
    local count = {}
    for _, e in ipairs(Collector.entries) do
        if not e.own and e.wanted then
            local titles = { (e.display:gsub("_", " ")) }
            local obj = rawget(e.btn, "dataObject")
            if type(obj) == "table" then
                -- Indexed, not rawget: a broker object is a proxy whose
                -- fields live in LibDataBroker's attributestorage.
                titles[2], titles[3] = obj.label, obj.text
            end
            local seen = {}
            for i = 1, 3 do
                local k = key(titles[i])
                if k and not seen[k] then
                    seen[k] = true
                    count[k] = (count[k] or 0) + 1
                end
            end
        end
    end
    for _, data in ipairs(list) do
        if not dup[data] then
            local k = key(data.text)
            if k and count[k] == 1 then dup[data] = true end
        end
    end
    return dup
end

--------------------------------------------------------------------------------
-- Our buttons
--------------------------------------------------------------------------------

local function onClick(self, mouse)
    local data = self.compartmentData
    if not data then return end
    GameTooltip:Hide()
    if type(data.func) == "function" then
        API.Try("compartment:" .. tostring(self.entryName), data.func, nil, { buttonName = mouse }, self)
    end
    local e = Collector.byName[self.entryName]
    if e then API.Try("click", Collector.onClick, e, mouse) end
end

local function onEnter(self)
    local data = self.compartmentData
    if not data then return end
    if type(data.funcOnEnter) == "function" then
        API.Try("compartment:enter", data.funcOnEnter, self, data)
    else
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine(Compartment.CleanText(data.text) or "?")
        GameTooltip:Show()
    end
end

local function onLeave(self)
    local data = self.compartmentData
    if data and type(data.funcOnLeave) == "function" then
        API.Try("compartment:leave", data.funcOnLeave, self, data)
    else
        GameTooltip:Hide()
    end
end

-- A button shaped like a LibDBIcon one (border, background, icon), so the
-- orb skin and the bar's layout treat it like every other button.
local function newButton()
    local b = table.remove(pool)
    if b then return b end
    b = CreateFrame("Button", nil, Collector.host)
    b:SetSize(Compartment.SIZE, Compartment.SIZE)
    b:RegisterForClicks("AnyUp")
    b.background = b:CreateTexture(nil, "BACKGROUND")
    b.background:SetTexture(136467)                -- Interface\Minimap\UI-Minimap-Background
    b.background:SetSize(24, 24)
    b.background:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    b.border = b:CreateTexture(nil, "OVERLAY")
    b.border:SetTexture(136430)                    -- Interface\Minimap\MiniMap-TrackingBorder
    b.border:SetSize(50, 50)
    b.border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b:SetHighlightTexture(136477)                  -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", onEnter)
    b:SetScript("OnLeave", onLeave)
    return b
end

local function uniqueName(text)
    local base = Compartment.PREFIX .. (Compartment.CleanText(text) or "?")
    local name, n = base, 1
    while Collector.byName[name] do
        n = n + 1
        name = base .. " (" .. n .. ")"
    end
    return name
end

local function add(data)
    local b = newButton()
    b.compartmentData = data
    if data.icon then
        API.SetIcon(b.icon, data.icon)
    else
        b.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    local name = uniqueName(data.text)
    b.entryName = name
    if Collector.AddOwn(b, name, Compartment.CleanText(data.text) or "?") then
        byData[data] = name
    else
        b.compartmentData = nil
        pool[#pool + 1] = b
    end
end

local function remove(data)
    local name = byData[data]
    byData[data] = nil
    local e = name and Collector.byName[name]
    if e and Collector.RemoveOwn(name) then
        e.btn.compartmentData = nil
        pool[#pool + 1] = e.btn
    end
end

-- Make the bar's compartment buttons match the compartment (none while the
-- option is off). Returns whether anything changed.
function Compartment.Sync()
    scheduled = false
    if not Collector.host then return false end
    local list = enabled and Compartment.List() or {}
    local dup = duplicates(list)
    local want, changed = {}, false
    for _, data in ipairs(list) do
        if not dup[data] then want[data] = true end
    end
    -- Stale entries go first: an addon that removed and re-registered its
    -- entry before this sync gets its old name back ("AddOns:<title>", not
    -- "<title> (2)"), so the player's hidden/order/last-used still apply.
    local gone = {}
    for data in pairs(byData) do
        if not want[data] then gone[#gone + 1] = data end
    end
    for _, data in ipairs(gone) do remove(data); changed = true end
    for _, data in ipairs(list) do
        if want[data] and not byData[data] then add(data); changed = true end
    end
    if changed then Collector.Changed() end
    return changed
end

function Compartment.Request()
    if scheduled then return end
    scheduled = true
    C_Timer.After(0, function() API.Try("compartment:sync", Compartment.Sync) end)
end

-- The option: entries in the bar and Blizzard's button hidden, or neither.
function Compartment.SetEnabled(on)
    enabled = on and true or false
    if not frame() then return end
    if not started then
        started = true
        if type(frame().UpdateDisplay) == "function" then
            hooksecurefunc(frame(), "UpdateDisplay", function() Compartment.Request() end)
        end
    end
    if enabled or hider then
        hider = hider or API.SystemHider("AddonCompartmentFrame")
        hider.Set(enabled)
    end
    Compartment.Request()
end

function Compartment.IsEnabled() return enabled end

Compartment._test = { byData = byData, pool = pool, duplicates = duplicates, hider = function() return hider end }
