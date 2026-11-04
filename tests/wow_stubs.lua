-- wow_stubs.lua: GlassMiniMapBar's WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
--
-- The mechanics are WowTestKit's core (tests/kit.lua loads the commit and the
-- build tests/kit.pin names; its README is the reference): strict globals,
-- secrets, event names checked against the build, widgets that record every
-- method called, print with the stray-"|" check done() fails on, timers,
-- fire / fireAllRegistered / tick, check / eq / done. This file adds what a
-- minimap button bar touches beyond those: Minimap and the AddOns
-- compartment, the Settings calls, fakes of LibDataBroker and LibDBIcon, and
-- a fake Glass UI suite. Methods are looked up at call time, so an entry here
-- replaces the core's.
--
-- The vendored libraries (Libs\, LibStub included) are not loaded:
-- WoW.installFakeLibs registers fakes with the calls the addon makes into
-- the real LibStub, which the embedded LibGlass-1.0 brings (harness.lua
-- loads it from the checkout, as the client loads the TOC's XML line).

dofile("tests/kit.lua")
local Methods = WoW.Methods
local newWidget = WoW.newWidget

-- WowTestKit #7: the client's widget metatable has a method TABLE as its
-- __index, and the addon calls methods through it
-- (getmetatable(CreateFrame("Frame")).__index.SetPoint(btn, ...), Compat.lua's
-- API.W) on buttons whose own SetPoint/Show/... it has replaced. The core's is
-- a function; this puts the same lookup behind a table.
do
    local mt = getmetatable(newWidget("Frame"))
    local lookup = mt.__index
    if type(lookup) == "function" then
        mt.__index = setmetatable({}, { __index = function(_, k) return lookup(nil, k) end })
    end
end

--------------------------------------------------------------------------------
-- Templates (CreateFrame's fourth argument)
--------------------------------------------------------------------------------

-- Both templates' label (parentKey Text).
WoW.templates.UICheckButtonTemplate = function(w) w.Text = newWidget("FontString", w) end
WoW.templates.UIPanelButtonTemplate = function(w) w.Text = newWidget("FontString", w) end

--------------------------------------------------------------------------------
-- Widgets: the methods the core doesn't have
--------------------------------------------------------------------------------

function Methods.GetNumPoints(w) return #w._points end
function Methods.GetSize(w) return w._width, w._height end
function Methods.GetCenter(w) return w._cx, w._cy end
function Methods.GetEffectiveScale(w) return w._effScale or 1 end
function Methods.SetScale(w, s) w._scale = s end
function Methods.GetScale(w) return w._scale or 1 end
function Methods.IsObjectType(w, t)
    if w._type == t then return true end
    return t == "Frame" and (w._type == "Button" or w._type == "CheckButton")
end
function Methods.IsProtected(w)
    if WoW.secrets[w._protected] then return w._protected end
    return w._protected == true
end
function Methods.RegisterForClicks(w, ...) w._clicks = { ... } end
function Methods.RegisterForDrag(w, ...) w._drag = { ... } end
function Methods.IsMouseOver(w) return WoW.mouseOver[w] == true end
function Methods.SetHighlightTexture(w, file) w._highlight = file end
function Methods.GetAnimationGroups(w) return unpack(w._anims or {}) end

-- Animations: Play marks a group playing (and counts it); WoW.finishAnimations()
-- completes every playing group (OnFinished), as the client would after its
-- duration. The core doesn't track groups, so these replace its two makers.
function Methods.CreateAnimationGroup(w)
    local ag = newWidget("AnimationGroup", w)
    ag._animations = {}
    w._anims = w._anims or {}
    table.insert(w._anims, ag)
    table.insert(WoW.animGroups, ag)
    return ag
end
function Methods.CreateAnimation(ag, atype)
    local a = newWidget(atype or "Animation", ag)
    table.insert(ag._animations, a)
    return a
end
function Methods.GetAnimations(ag) return unpack(ag._animations) end
function Methods.GetTarget(a) return a._parent and a._parent._parent end
function Methods.Play(ag) ag._playing = true; ag._plays = (ag._plays or 0) + 1 end
function Methods.SetOrigin(a, point) a._origin = point end
function Methods.SetScaleFrom(a, x, y) a._from = { x, y } end
function Methods.SetScaleTo(a, x, y) a._to = { x, y } end
function WoW.finishAnimations()
    for _, ag in ipairs(WoW.animGroups) do
        if ag._playing then
            ag._playing = false
            if ag._scripts.OnFinished then ag._scripts.OnFinished(ag) end
        end
    end
end

-- Scripts. HasScript: every scripted widget type knows these handlers.
local SCRIPTED = { Frame = true, Button = true, CheckButton = true, StatusBar = true, GameTooltip = true }
local HANDLERS = { OnClick = true, OnMouseUp = true, OnMouseDown = true, OnEnter = true, OnLeave = true,
                   OnShow = true, OnHide = true, OnUpdate = true, OnEvent = true, OnDragStart = true, OnDragStop = true }
function Methods.HasScript(w, name) return SCRIPTED[w._type] == true and HANDLERS[name] == true end
function Methods.Click(w, mouse)
    if w._scripts.OnClick then w._scripts.OnClick(w, mouse or "LeftButton", false) end
end

-- Textures.
function Methods.GetTexture(t) return t._file end
function Methods.GetAtlas(t) return t._atlas end
function Methods.SetTexCoord(t, ...) t._coords = { ... } end
function Methods.GetTexCoord(t)
    local c = t._coords or { 0, 0, 0, 1, 1, 0, 1, 1 }
    return unpack(c)
end
function Methods.RemoveMaskTexture(t, m)
    for i, x in ipairs(t._masks or {}) do if x == m then table.remove(t._masks, i); return end end
end
-- The Retail signature: two colour objects, never eight numbers. The core
-- records the gradient (and its SetAlpha ignores a gradient texture, LibGlass
-- #47); this keeps the signature check the old stub had.
local coreSetGradient = Methods.SetGradient
function Methods.SetGradient(t, orientation, c1, c2)
    assert(type(c1) == "table" and type(c2) == "table", "SetGradient takes color objects on this API")
    return coreSetGradient(t, orientation, c1, c2)
end

-- GameTooltip: records its lines.
function Methods.SetOwner(tt, owner) tt._owner = owner; tt._lines = {} end
function Methods.GetOwner(tt) return tt._owner end
function Methods.ClearLines(tt) tt._lines = {} end
function Methods.AddLine(tt, text) table.insert(tt._lines, text) end

--------------------------------------------------------------------------------
-- State WoW.reset() clears besides the core's: the frames Blizzard makes
--------------------------------------------------------------------------------

local function resetMinimap()
    WoW.mouseOver = {}
    WoW.animGroups = {}
    WoW.shift = false
    WoW.settingsOpened = nil
    UIParent = newWidget("Frame", nil, "UIParent")
    UIParent._level = 0
    UIParent._width, UIParent._height = 1024, 768
    GameTooltip = newWidget("GameTooltip", UIParent, "GameTooltip")
    Minimap = CreateFrame("Frame", "Minimap", UIParent)
    Minimap._width, Minimap._height = 140, 140
    MinimapBackdrop = CreateFrame("Frame", "MinimapBackdrop", Minimap)
    MinimapBackdrop._width, MinimapBackdrop._height = 140, 140
    WoW.ldbi = nil
    WoW.compartmentCalls = nil
    -- The AddOns compartment (Blizzard_Minimap\Mainline\AddonCompartment.lua):
    -- RegisterAddon and the bulk RegisterAddons both end in UpdateDisplay.
    MinimapCluster = CreateFrame("Frame", "MinimapCluster", UIParent)
    AddonCompartmentFrame = CreateFrame("Button", "AddonCompartmentFrame", MinimapCluster)
    AddonCompartmentFrame.registeredAddons = {}
    function AddonCompartmentFrame:RegisterAddon(data)
        table.insert(self.registeredAddons, data)
        self:UpdateDisplay()
    end
    function AddonCompartmentFrame:UpdateDisplay() self._displayed = #self.registeredAddons end
    -- EventRegistry (the dump's namespace walk): callbacks get (owner, ...).
    EventRegistry = { callbacks = {} }
    function EventRegistry:RegisterCallback(event, fn, owner)
        self.callbacks[event] = self.callbacks[event] or {}
        table.insert(self.callbacks[event], { fn = fn, owner = owner })
    end
    function EventRegistry:TriggerEvent(event, ...)
        for _, c in ipairs(self.callbacks[event] or {}) do c.fn(c.owner, ...) end
    end
    -- The player's class: WoW.class = nil makes it unreadable (early in a login).
    WoW.class = "PRIEST"
end
table.insert(WoW.onReset, resetMinimap)
resetMinimap()

--------------------------------------------------------------------------------
-- Client APIs (each in the dump)
--------------------------------------------------------------------------------

SlashCmdList = {}
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 } }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
-- WoW.build: the client's build. WoW.version: the TOC's Version, release-shaped
-- by default ("dev" is what Tools/deploy.ps1 writes).
WoW.build, WoW.version = "70450", "v1.0.0"
function GetBuildInfo() return "1.60.1", WoW.build, "Sep 23 2026", 16001 end
C_AddOns = {
    GetAddOnMetadata = function(name, variable)
        if name == "GlassMiniMapBar" and variable == "Version" then return WoW.version end
        return nil
    end,
}
function IsShiftKeyDown() return WoW.shift end
-- UnitClass(unit) -> className, classFilename, classID; C_ClassColor.GetClassColor(className) -> colorRGB.
function UnitClass(unit) if WoW.class then return WoW.class:lower(), WoW.class, 5 end end
WoW.CLASS_COLORS = { PRIEST = { r = 1, g = 1, b = 1 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
C_ClassColor = { GetClassColor = function(className)
    local c = className and WoW.CLASS_COLORS[className:upper()]
    return c and { r = c.r, g = c.g, b = c.b }
end }
C_Texture = { GetAtlasInfo = function(name)
    if type(name) == "string" and name:match("^atlas:") then return { width = 16, height = 16 } end
    return nil
end }

-- The bulk TOC registration at PLAYER_ENTERING_WORLD: addon titles -> globals.
function WoW.RegisterTocAddons(list)
    for _, t in ipairs(list) do
        local data = { text = t.title, icon = t.icon }
        data.func = function(_, menuInputData, menu)
            WoW.compartmentCalls = WoW.compartmentCalls or {}
            table.insert(WoW.compartmentCalls, { title = t.title, button = menuInputData.buttonName, menu = menu })
        end
        table.insert(AddonCompartmentFrame.registeredAddons, data)
    end
    AddonCompartmentFrame:UpdateDisplay()
end
-- Blizzard's own globals are "secure": WoW.secureNames[name] = true.
WoW.secureNames = {}
function issecurevariable(t, name)
    if name == nil then name = t end
    return WoW.secureNames[name] == true, nil
end

-- Settings (Options > AddOns): the canvas category API the addon uses.
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name)
        return { panel = panel, name = name, GetID = function() return name end }
    end,
    RegisterAddOnCategory = function(cat) WoW.settingsCategory = cat end,
    OpenToCategory = function(id) WoW.settingsOpened = id end,
}

--------------------------------------------------------------------------------
-- A minimap button as an addon would make it
--------------------------------------------------------------------------------

-- opts: name, parent (default Minimap), size (31), protected, noClick,
-- script ("OnClick" | "OnMouseUp"), ring (true: gold border + dark disc).
function WoW.MinimapButton(opts)
    local b = CreateFrame(opts.frameType or "Button", opts.name, opts.parent or Minimap)
    b._width, b._height = opts.size or 31, opts.size or 31
    b._protected = opts.protected
    b.clicks = {}
    if not opts.noClick then
        local script = opts.script or "OnClick"
        b._scripts[script] = function(self, mouse) table.insert(self.clicks, mouse) end
    end
    if opts.ring ~= false then
        b.border = b:CreateTexture(nil, "OVERLAY"); b.border._file = 136430
        b.background = b:CreateTexture(nil, "BACKGROUND"); b.background._file = 136467
        b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon._file = "Interface\\Icons\\" .. (opts.name or "x")
        b.icon:SetSize(18, 18)
        b.icon:SetPoint("CENTER", b, "CENTER", 0, 0)
    end
    b:SetPoint("CENTER", Minimap, "CENTER", 60, 30)
    return b
end

--------------------------------------------------------------------------------
-- LibStub with fake LibDataBroker-1.1 and LibDBIcon-1.0
--------------------------------------------------------------------------------

local function newLDBI()
    local lib = { objects = {}, callbacks = {}, locked = {} }
    function lib.RegisterCallback(owner, event, fn)
        lib.callbacks[event] = function(...) fn(...) end
    end
    function lib:Register(name, obj, db)
        local b = WoW.MinimapButton({ name = "LibDBIcon10_" .. name })
        b._scripts.OnClick = function(self, mouse) if obj.OnClick then obj.OnClick(self, mouse) end end
        b._scripts.OnEnter = function(self) if obj.OnEnter then obj.OnEnter(self) end end
        b._scripts.OnLeave = function(self) if obj.OnLeave then obj.OnLeave(self) end end
        b.dataObject, b.db = obj, db
        lib.objects[name] = b
        if db and db.hide then b:Hide() end
        if lib.callbacks.LibDBIcon_IconCreated then lib.callbacks.LibDBIcon_IconCreated("LibDBIcon_IconCreated", b, name) end
        return b
    end
    function lib:GetMinimapButton(name) return lib.objects[name] end
    function lib:Lock(name) lib.locked[name] = true end
    function lib:Unlock(name) lib.locked[name] = nil end
    -- LibDBIcon-1.0.lua:391-404: Hide/Show don't touch the saved table.
    function lib:Hide(name) local b = lib.objects[name]; if b then b:Hide() end end
    function lib:Show(name) local b = lib.objects[name]; if b then b:Show() end end
    -- LibDBIcon-1.0.lua:637-665, as shipped: the entry's hover callbacks read menu.text.
    function lib:AddButtonToCompartment(name)
        local object = lib.objects[name]
        if object and not object.compartmentData then
            object.compartmentData = {
                text = name, icon = object.dataObject.icon, notCheckable = true, registerForAnyClick = true,
                func = function(_, menuInputData, menu) object.dataObject.OnClick(menu, menuInputData.buttonName) end,
                funcOnEnter = function(self, menu) WoW.compartmentEnter = menu.text end,
                funcOnLeave = function(self, menu) WoW.compartmentLeave = menu.text end,
            }
            AddonCompartmentFrame:RegisterAddon(object.compartmentData)
        end
    end
    function lib:RemoveButtonFromCompartment(name)
        local object = lib.objects[name]
        if object and object.compartmentData then
            local list = AddonCompartmentFrame.registeredAddons
            for i = 1, #list do
                if list[i] == object.compartmentData then
                    object.compartmentData = nil
                    table.remove(list, i)
                    AddonCompartmentFrame:UpdateDisplay()
                    return
                end
            end
        end
    end
    return lib
end

-- Like LibDataBroker-1.1.lua:14-46: the fields move into a side storage and
-- the object is an empty proxy, so rawget on it finds nothing.
local LDB = { objects = {} }
function LDB:NewDataObject(name, obj)
    local store = {}
    for k, v in pairs(obj or {}) do store[k] = v end
    obj = setmetatable({}, { __metatable = "access denied",
        __index = function(_, k) return store[k] end,
        __newindex = function(_, k, v) store[k] = v end })
    self.objects[name] = obj
    return obj
end

-- Into the session's LibStub, where the vendored copies would register.
function WoW.installFakeLibs()
    local ldb = LibStub:NewLibrary("LibDataBroker-1.1", 1)
    for k, v in pairs(LDB) do ldb[k] = v end
    ldb.objects = {}
    local ldbi = LibStub:NewLibrary("LibDBIcon-1.0", 1)
    for k, v in pairs(newLDBI()) do ldbi[k] = v end
    WoW.ldbi = ldbi
end
function WoW.LDBI() return WoW.ldbi end

--------------------------------------------------------------------------------
-- A fake Glass UI suite (its docs/SUITE.md and docs/SUITE-LOOK.md, API 1; the
-- numbers are its Suite.BODY, as Glass MiniMap's stub has them). opts.answer:
-- what Theme returns (default: following, Pearl); opts.tint: the suite look's
-- tint; opts.noLook / noBody / noOpen leave those functions out (an older
-- API 1). Every call is recorded; Report keeps each state it was given.
--------------------------------------------------------------------------------

function WoW.FakeGlassUI(opts)
    opts = opts or {}
    local fake = { reports = {}, asked = {}, bodies = {}, tint = opts.tint or "clear" }
    local BODY = {
        clear  = { tint = { 0.13, 0.16, 0.22, 0.24 }, wash = 1, backing = 0.35 },
        smoked = { tint = { 0.05, 0.06, 0.08, 0.62 }, wash = 0.14 / 0.18, backing = 0.92 },
        class  = { classShade = 0.6, wash = 1, backing = 0.35 },
    }
    fake.BODY = BODY
    local S = { API = 1 }
    function S.Theme(addon)
        fake.asked[#fake.asked + 1] = addon
        if opts.answer then return opts.answer() end
        return { name = "pearl", preset = "pearl" }
    end
    function S.Report(addon, state) fake.reports[#fake.reports + 1] = { addon = addon, state = state } end
    if not opts.noLook then
        function S.Look() return { tint = fake.tint, hover = "glow", press = "flash", emptySlots = "frosted", accent = "gold" } end
    end
    if not opts.noBody then
        function S.Body(tint)
            fake.bodies[#fake.bodies + 1] = tint
            local b = BODY[tint or fake.tint]
            if not b then return nil end
            return { tint = b.tint and { b.tint[1], b.tint[2], b.tint[3], b.tint[4] }, classShade = b.classShade,
                     wash = b.wash, backing = { 0.04, 0.05, 0.07, b.backing } }
        end
    end
    if not opts.noOpen then
        function S.Open() fake.opened = (fake.opened or 0) + 1; return true end
    end
    fake.Suite = S
    GlassUI = { Suite = S }
    -- The suite look changes: Glass UI fires its event with a fresh table.
    function fake.SetTint(tint)
        fake.tint = tint
        local payload = { tint = tint, hover = "glow", press = "flash", emptySlots = "frosted", accent = "gold" }
        EventRegistry:TriggerEvent("GlassUI.Suite.LookChanged", payload)
        return payload
    end
    function fake.LastReport() local r = fake.reports[#fake.reports]; return r and r.state end
    return fake
end

-- Strict globals, last.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
Kit.strict({ GlassMiniMapBar = true, GlassMiniMapBarDB = true, GlassUI = true,
             SLASH_GLASSMINIMAPBAR1 = true, LibStub = true })
