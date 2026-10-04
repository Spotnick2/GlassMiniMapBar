-- wow_stubs.lua: a minimal WoW: Forever mock for Lua 5.1 unit tests.
-- dofile("tests/wow_stubs.lua") FIRST in every test; drive it via the WoW table.
-- Modelled on GlassUnitFrames' and GlassPanel's stubs, trimmed to what a
-- minimap button bar touches, plus fakes of Minimap and LibDBIcon.
--
-- What it models, on purpose:
-- - STRICT globals: reading any global it does not define is an error. The
--   stub is the allowlist of APIs verified present in the API dump.
-- - EVENT names: RegisterEvent throws on a name the API dump does not declare.
-- - METHOD calls: every widget method called is recorded (WoW.methodsCalled)
--   so test_methods.lua can check each against the dump's widget methods.
-- - The widget METATABLE is a real method table, like the client's, because
--   the addon calls methods through getmetatable(CreateFrame("Frame")).__index
--   on buttons whose own SetPoint/Show/... it has replaced.
-- The vendored libraries (Libs\, LibStub included) are not loaded:
-- WoW.installFakeLibs registers fakes with the calls the addon makes into
-- the real LibStub, which the embedded LibGlass-1.0 brings (harness.lua
-- loads it from the checkout, as the client loads the TOC's XML line).

WoW = {}
local DUMP = os.getenv("GLASSMMB_API_DUMP") or "C:/Projects/References/forever-api-1.60.1.70009.md"

--------------------------------------------------------------------------------
-- Known events (from the dump when present)
--------------------------------------------------------------------------------

WoW.KNOWN_EVENTS = {}
do
    local f = io.open(DUMP, "r")
    if f then
        local inEvents = false
        for line in f:lines() do
            if line:match("^## Documented events") then inEvents = true
            elseif line:match("^## ") then inEvents = false
            elseif inEvents then
                local name = line:match("^([A-Z][A-Z0-9_]+)%s+%(")
                if name then WoW.KNOWN_EVENTS[name] = true end
            end
        end
        f:close()
    end
    if next(WoW.KNOWN_EVENTS) == nil then
        for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "GLOBAL_MOUSE_DOWN" }) do
            WoW.KNOWN_EVENTS[e] = true
        end
    end
end

--------------------------------------------------------------------------------
-- Widgets
--------------------------------------------------------------------------------

local Methods = {}   -- implementations, by method name

local function record(w, name)
    WoW.methodsCalled[(rawget(w, "_type") or "?") .. ":" .. name] = true
end

-- The shared method table: any Capitalised name is a method (a no-op unless
-- implemented below); anything else reads as nil, like a missing field.
local MethodTable = setmetatable({}, {
    __index = function(_, k)
        if type(k) ~= "string" or not k:match("^%u") then return nil end
        return function(self, ...)
            record(self, k)
            local impl = Methods[k]
            if impl then return impl(self, ...) end
            return nil
        end
    end,
})
local widgetMT = { __index = MethodTable }

local function newWidget(wtype, parent, name)
    local w = setmetatable({ _type = wtype, _parent = parent, _shown = true, _points = {},
                             _scripts = {}, _events = {}, _children = {}, _regions = {},
                             _level = parent and parent._level and (parent._level + 1) or 1,
                             _width = 0, _height = 0, _name = name, _scale = 1, _alpha = 1 }, widgetMT)
    return w
end

local function adopt(parent, w)
    if parent and parent._children then table.insert(parent._children, w) end
end

local SCRIPTED = { Frame = true, Button = true, CheckButton = true, StatusBar = true, GameTooltip = true }

function CreateFrame(ftype, name, parent, template)
    local w = newWidget(ftype, parent, name)
    w._template = template
    adopt(parent, w)
    table.insert(WoW.frames, w)
    if name then rawset(_G, name, w) end
    if template == "UICheckButtonTemplate" or template == "UIPanelButtonTemplate" then
        w.Text = newWidget("FontString", w)
    end
    return w
end

function Methods.Show(w) if not w._shown then w._shown = true; if w._scripts.OnShow then w._scripts.OnShow(w) end end end
function Methods.Hide(w) if w._shown then w._shown = false; if w._scripts.OnHide then w._scripts.OnHide(w) end end end
function Methods.SetShown(w, v) if v then Methods.Show(w) else Methods.Hide(w) end end
function Methods.IsShown(w) return w._shown end
function Methods.IsVisible(w)
    local p = w
    while p do if not p._shown then return false end; p = p._parent end
    return true
end
function Methods.SetPoint(w, ...) table.insert(w._points, { ... }) end
function Methods.ClearAllPoints(w) w._points = {} end
function Methods.GetPoint(w, i)
    local p = w._points[i or 1]
    if p then return p[1], p[2], p[3], p[4], p[5] end
end
function Methods.GetNumPoints(w) return #w._points end
function Methods.SetAllPoints(w, rel) table.insert(w._points, { "ALL", rel }) end
function Methods.SetSize(w, x, y) w._width, w._height = x, y end
function Methods.SetWidth(w, x) w._width = x end
function Methods.SetHeight(w, y) w._height = y end
function Methods.GetWidth(w) return w._width end
function Methods.GetHeight(w) return w._height end
function Methods.GetSize(w) return w._width, w._height end
function Methods.GetCenter(w) return w._cx, w._cy end
function Methods.GetEffectiveScale(w) return w._effScale or 1 end
function Methods.SetScale(w, s) w._scale = s end
function Methods.GetScale(w) return w._scale end
function Methods.SetAlpha(w, a) w._alpha = a end
function Methods.GetAlpha(w) return w._alpha end
function Methods.GetFrameLevel(w) return w._level end
function Methods.SetFrameLevel(w, l) w._level = l end
function Methods.SetFrameStrata(w, s) w._strata = s end
function Methods.GetFrameStrata(w) return w._strata or "MEDIUM" end
function Methods.GetName(w) return w._name end
function Methods.GetParent(w) return w._parent end
function Methods.SetParent(w, p)
    if w._parent and w._parent._children then
        for i, c in ipairs(w._parent._children) do
            if c == w then table.remove(w._parent._children, i); break end
        end
    end
    w._parent = p
    adopt(p, w)
end
function Methods.GetChildren(w) return unpack(w._children) end
function Methods.GetRegions(w) return unpack(w._regions) end
function Methods.IsObjectType(w, t)
    if w._type == t then return true end
    return t == "Frame" and (w._type == "Button" or w._type == "CheckButton")
end
function Methods.GetObjectType(w) return w._type end
function Methods.IsForbidden(w) return false end
function Methods.IsProtected(w) return w._protected == true end
function Methods.EnableMouse(w, v) w._mouse = v end
function Methods.RegisterForClicks(w, ...) w._clicks = { ... } end
function Methods.RegisterForDrag(w, ...) w._drag = { ... } end
function Methods.IsMouseOver(w) return WoW.mouseOver[w] == true end
function Methods.GetChecked(w) return w._checked == true end
function Methods.SetEnabled(w, v) w._enabled = v and true or false end
function Methods.IsEnabled(w) return w._enabled ~= false end
function Methods.SetChecked(w, v) w._checked = v and true or false end
function Methods.SetText(w, t) w._text = t end
function Methods.GetText(w) return w._text end
function Methods.GetAnimationGroups(w) return unpack(w._anims or {}) end

-- Animations: Play marks a group playing; WoW.finishAnimations() completes
-- every playing group (OnFinished), as the client would after its duration.
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
function Methods.Stop(ag) ag._playing = false end
function Methods.IsPlaying(ag) return ag._playing == true end
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
local HANDLERS = { OnClick = true, OnMouseUp = true, OnMouseDown = true, OnEnter = true, OnLeave = true,
                   OnShow = true, OnHide = true, OnUpdate = true, OnEvent = true, OnDragStart = true, OnDragStop = true }
function Methods.HasScript(w, name) return SCRIPTED[w._type] == true and HANDLERS[name] == true end
function Methods.SetScript(w, name, fn) w._scripts[name] = fn end
function Methods.GetScript(w, name) return w._scripts[name] end
function Methods.HookScript(w, name, fn)
    local old = w._scripts[name]
    w._scripts[name] = function(...) if old then old(...) end; fn(...) end
end
function Methods.Click(w, mouse)
    if w._scripts.OnClick then w._scripts.OnClick(w, mouse or "LeftButton", false) end
end
function Methods.RegisterEvent(w, e)
    if not WoW.KNOWN_EVENTS[e] then error("Attempt to register unknown event \"" .. e .. "\"", 2) end
    w._events[e] = true
    return true
end
function Methods.UnregisterEvent(w, e) w._events[e] = nil end

-- Regions.
local function region(w, wtype, layer)
    local r = newWidget(wtype, w)
    r._layer = layer
    if wtype ~= "MaskTexture" then table.insert(w._regions, r) end
    return r
end
function Methods.CreateTexture(w, _, layer) return region(w, "Texture", layer) end
function Methods.CreateMaskTexture(w) return region(w, "MaskTexture") end
function Methods.CreateFontString(w, _, layer) return region(w, "FontString", layer) end
function Methods.SetTexture(t, file) t._file = file; return true end
function Methods.GetTexture(t) return t._file end
function Methods.GetAtlas(t) return t._atlas end
function Methods.SetTexCoord(t, ...) t._coords = { ... } end
function Methods.GetTexCoord(t)
    local c = t._coords or { 0, 0, 0, 1, 1, 0, 1, 1 }
    return unpack(c)
end
function Methods.SetColorTexture(t, r, g, b, a) t._color = { r, g, b, a } end
function Methods.AddMaskTexture(t, m) t._masks = t._masks or {}; table.insert(t._masks, m) end
function Methods.RemoveMaskTexture(t, m)
    for i, x in ipairs(t._masks or {}) do if x == m then table.remove(t._masks, i); return end end
end
function Methods.SetGradient(t, orientation, c1, c2)
    assert(type(c1) == "table" and type(c2) == "table", "SetGradient takes color objects on this API")
end
function Methods.SetFont(fs, file, size, flags) fs._font = { file, size, flags }; return true end

-- GameTooltip: records its lines.
function Methods.SetOwner(tt, owner) tt._owner = owner; tt._lines = {} end
function Methods.GetOwner(tt) return tt._owner end
function Methods.ClearLines(tt) tt._lines = {} end
function Methods.AddLine(tt, text) table.insert(tt._lines, text) end

--------------------------------------------------------------------------------
-- Globals
--------------------------------------------------------------------------------

function WoW.reset()
    WoW.frames = {}
    WoW.chat = {}
    WoW.methodsCalled = WoW.methodsCalled or {}
    WoW.timers = {}
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
end

function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(WoW.chat, table.concat(parts, " "))
end

SlashCmdList = {}
-- Client string alias (in the dump's _G walk); LibStub's version check uses it.
strmatch = string.match
Enum = { UITextureSliceMode = { Stretched = 0, Tiled = 1 } }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
-- WoW.build: the client's build. WoW.version: the TOC's Version, release-shaped
-- by default ("dev" is what Tools/deploy.ps1 writes).
WoW.build, WoW.version = "70009", "v1.0.0"
function GetBuildInfo() return "1.60.1", WoW.build, "Sep 23 2026", 16001 end
C_AddOns = {
    GetAddOnMetadata = function(name, variable)
        if name == "GlassMiniMapBar" and variable == "Version" then return WoW.version end
        return nil
    end,
}
function IsShiftKeyDown() return WoW.shift end
function issecretvalue(v) return false end
-- Blizzard's own globals are "secure": WoW.secureNames[name] = true.
WoW.secureNames = {}
function issecurevariable(t, name)
    if name == nil then name = t end
    return WoW.secureNames[name] == true, nil
end
function hooksecurefunc(t, name, fn)
    local orig = t[name]
    rawset(t, name, function(self, ...) local r = orig(self, ...); fn(self, ...); return r end)
end

-- Timers keep their delay: WoW.flushTimers(upTo) runs those due within upTo.
C_Timer = { After = function(s, fn) table.insert(WoW.timers, { s = s, fn = fn }) end }
function WoW.flushTimers(upTo)
    local run, keep = {}, {}
    for _, t in ipairs(WoW.timers) do
        if upTo == nil or t.s <= upTo then run[#run + 1] = t else keep[#keep + 1] = t end
    end
    WoW.timers = keep
    for _, t in ipairs(run) do t.fn() end
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
    return lib
end

local LDB = { objects = {} }
function LDB:NewDataObject(name, obj) self.objects[name] = obj; return obj end

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
-- Driving
--------------------------------------------------------------------------------

-- Fire an event at every frame registered for it. Errors are NOT caught.
function WoW.fire(event, ...)
    for _, w in ipairs(WoW.frames) do
        local handler = w._scripts.OnEvent
        if handler and w._events[event] then handler(w, event, ...) end
    end
end

-- One rendered frame: OnUpdate on every visible frame.
function WoW.tick(elapsed)
    elapsed = elapsed or 0.02
    local list = {}
    for _, w in ipairs(WoW.frames) do list[#list + 1] = w end
    for _, w in ipairs(list) do
        local fn = w._scripts.OnUpdate
        if fn and Methods.IsVisible(w) then fn(w, elapsed) end
    end
end

WoW.reset()

-- Strict globals.
-- LibStub: the embedded library's own loader reads _G.LibStub before creating it.
local allowNil = { GlassMiniMapBar = true, GlassMiniMapBarDB = true,
                   SLASH_GLASSMINIMAPBAR1 = true, LibStub = true }
setmetatable(_G, { __index = function(_, k)
    if allowNil[k] then return nil end
    error("read of undefined global '" .. tostring(k) .. "' (not stubbed: is it in the API dump?)", 2)
end })
