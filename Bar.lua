-- Bar.lua: the launcher on the minimap ring and the glass bar it opens.
--
-- The launcher is our own LibDBIcon button (so it drags around the ring like
-- every other minimap button) wearing the orb. The bar is a glass panel
-- (Glass.Apply) anchored beside the launcher; the grabbed buttons are laid
-- out inside it in rows, alphabetically, reading order.
--
-- Opening: hover (default) or click on the launcher. Closing: the mouse has
-- been off the bar, the launcher and any open menu for `hideDelay` seconds;
-- in click mode, a click anywhere else. Right-click on the launcher repeats
-- the last button used when that option is on, else opens the options.
-- Nothing is secure, so all of this works in combat.

GlassMiniMapBar = GlassMiniMapBar or {}
local Bar = {}
GlassMiniMapBar.Bar = Bar
local API = GlassMiniMapBar.API
local Glass = GlassMiniMapBar.Glass
local Orb = GlassMiniMapBar.Orb
local Collector = GlassMiniMapBar.Collector
local W = API.W

Bar.NAME = "GlassMiniMapBar"        -- LibDataBroker / LibDBIcon object name
Bar.GAP = 3                         -- between buttons, and between bar and launcher
Bar.ARROWS = {
    left = "Interface\\Icons\\misc_arrowleft", right = "Interface\\Icons\\misc_arrowright",
    up = "Interface\\Icons\\misc_arrowlup", down = "Interface\\Icons\\misc_arrowdown",
}

local db                             -- GlassMiniMapBarDB, set by Bar.Build
local frame, glass, launcher, dataObject
local hideTimer = 0

local function ldbi() return LibStub("LibDBIcon-1.0", true) end

-- "left" | "right" | "up" | "down", resolving "auto" from which half of the
-- screen the launcher sits in: the bar opens toward the middle.
function Bar.Direction()
    local d = db.direction
    if d ~= "auto" then return d end
    local x = launcher and launcher:GetCenter()
    local half = UIParent:GetWidth() / 2
    if type(x) == "number" and x < half then return "right" end
    return "left"
end

-- Rows stack away from the nearer screen edge: down when the launcher is in
-- the top half (the usual minimap corner), up otherwise.
local function stackDown()
    local _, y = launcher and launcher:GetCenter()
    return not (type(y) == "number" and y < UIParent:GetHeight() / 2)
end

-- Place the visible buttons and size the bar. Returns the number placed.
function Bar.Layout()
    if not frame then return 0 end
    local visible = Collector.Visible(db.hidden)
    for _, e in ipairs(Collector.entries) do W.Hide(e.btn) end

    local dir = Bar.Direction()
    local vertical = dir == "up" or dir == "down"
    local size, gap = db.buttonSize, Bar.GAP
    local pad = Glass.Inset("large")
    local n = #visible
    local perLine = math.max(1, math.min(db.perRow, math.max(n, 1)))
    local lines = math.max(1, math.ceil(n / perLine))
    local long = pad * 2 + perLine * size + (perLine - 1) * gap
    local short = pad * 2 + lines * size + (lines - 1) * gap
    if vertical then frame:SetSize(short, long) else frame:SetSize(long, short) end

    local level = Glass.ContentLevel(frame)
    for i, e in ipairs(visible) do
        local k = i - 1
        local along, across = k % perLine, math.floor(k / perLine)
        local x, y
        if vertical then
            x = pad + across * (size + gap) + size / 2
            y = -(pad + along * (size + gap) + size / 2)
        else
            x = pad + along * (size + gap) + size / 2
            y = -(pad + across * (size + gap) + size / 2)
        end
        local btn = e.btn
        local scale = size / ((type(e.width) == "number" and e.width > 0) and e.width or size)
        W.SetScale(btn, scale)
        W.SetFrameStrata(btn, frame:GetFrameStrata())
        W.SetFrameLevel(btn, level)
        W.ClearAllPoints(btn)
        W.SetPoint(btn, "CENTER", frame, "TOPLEFT", x / scale, y / scale)
        W.Show(btn)
    end

    -- Beside the launcher, first line level with it.
    frame:ClearAllPoints()
    if launcher then
        local half = pad + size / 2
        local down = stackDown()
        if dir == "left" then
            frame:SetPoint(down and "TOPRIGHT" or "BOTTOMRIGHT", launcher, "LEFT", -gap, down and half or -half)
        elseif dir == "right" then
            frame:SetPoint(down and "TOPLEFT" or "BOTTOMLEFT", launcher, "RIGHT", gap, down and half or -half)
        elseif dir == "down" then
            frame:SetPoint("TOPLEFT", launcher, "BOTTOM", -half, -gap)
        else
            frame:SetPoint("BOTTOMLEFT", launcher, "TOP", -half, gap)
        end
    else
        frame:SetPoint("CENTER", UIParent, "CENTER")
    end
    return n
end

-- Open and close animations: the bar grows out of the launcher (scaled from
-- its launcher-side edge while fading in) and shrinks back into it. The
-- client runs them; Lua only picks the edge. Scale animations scale the
-- children too, so the buttons grow with the glass.
Bar.GROW = { duration = 0.18, from = 0.05 }
Bar.SHRINK = { duration = 0.12 }
local ORIGIN = { left = "RIGHT", right = "LEFT", up = "BOTTOM", down = "TOP" }
local grow, shrink, closing = nil, nil, false

local function makeAnim(fromScale, toScale, fromAlpha, toAlpha, duration, smoothing)
    local ag = frame:CreateAnimationGroup()
    local sc = ag:CreateAnimation("Scale")
    sc:SetDuration(duration)
    sc:SetSmoothing(smoothing)
    local al = ag:CreateAnimation("Alpha")
    al:SetFromAlpha(fromAlpha)
    al:SetToAlpha(toAlpha)
    al:SetDuration(duration)
    ag.scale, ag.fromScale, ag.toScale = sc, fromScale, toScale
    return ag
end

-- Point both animations at the edge facing the launcher, squashing along
-- the bar's length only.
local function aim(ag)
    local dir = Bar.Direction()
    local lo, hi = ag.fromScale, ag.toScale
    ag.scale:SetOrigin(ORIGIN[dir], 0, 0)
    if dir == "up" or dir == "down" then
        ag.scale:SetScaleFrom(1, lo)
        ag.scale:SetScaleTo(1, hi)
    else
        ag.scale:SetScaleFrom(lo, 1)
        ag.scale:SetScaleTo(hi, 1)
    end
end

function Bar.IsOpen() return frame ~= nil and frame:IsShown() and not closing end

function Bar.Open()
    if not frame then return end
    Collector.Scan()                    -- late creators: cheap, and only on open
    Bar.Layout()
    hideTimer = db.hideDelay
    local wasShown, wasClosing = frame:IsShown(), closing
    if closing then shrink:Stop() end
    closing = false
    frame:Show()
    frame:Raise()
    if db.animate and (wasClosing or not wasShown) then
        aim(grow)
        grow:Play()
    end
end

function Bar.Close()
    GameTooltip:Hide()
    if not (frame and frame:IsShown()) or closing then return end
    if db.animate then
        closing = true
        grow:Stop()
        aim(shrink)
        shrink:Play()                   -- OnFinished hides the frame
    else
        frame:Hide()
    end
end

function Bar.Toggle()
    if Bar.IsOpen() then Bar.Close() else Bar.Open() end
end

local function mouseIsHome()
    return (frame and frame:IsMouseOver(4, -4, -4, 4))
        or (launcher and launcher:IsMouseOver())
        or API.MouseOverMenu()
end

local function onUpdate(_, elapsed)
    if closing then
        -- Back on the launcher while it shrinks (hover mode): grow it again.
        if db.openOn == "hover" and launcher and launcher:IsMouseOver() then Bar.Open() end
        return
    end
    if mouseIsHome() then
        hideTimer = db.hideDelay
    else
        hideTimer = hideTimer - elapsed
        if hideTimer <= 0 then Bar.Close() end
    end
end

-- A click outside the bar closes it in click mode (hover mode closes on its own).
local function onEvent(_, event)
    if event == "GLOBAL_MOUSE_DOWN" and db.openOn == "click" and not mouseIsHome() then
        Bar.Close()
    end
end

--------------------------------------------------------------------------------
-- The launcher
--------------------------------------------------------------------------------

-- The last-used button's icon, or the arrow toward the bar.
function Bar.UpdateLauncherIcon()
    if not dataObject then return end
    local icon, coords
    local last = db.lastUsed and db.last and Collector.byName[db.last.name]
    if last then
        local obj = last.btn.dataObject     -- a LibDBIcon button: ask its broker
        if type(obj) == "table" and obj.icon then
            icon, coords = obj.icon, obj.iconCoords
        else
            local info = Orb.IconOf(last.btn)
            if info and info.file and not info.atlas then
                local c = info.coords
                icon = info.file
                if #c >= 8 then coords = { c[1], c[5], c[2], c[4] } end   -- UL, UR, LL -> l, r, t, b
            end
        end
    end
    if not icon then icon, coords = Bar.ARROWS[Bar.Direction()], nil end
    dataObject.iconCoords = coords
    dataObject.icon = icon
end

local function showTip(owner)
    local last = db.lastUsed and db.last and Collector.byName[db.last.name]
    local empty = #Collector.Visible(db.hidden) == 0
    if not (last or empty) then return end
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    GameTooltip:ClearLines()
    GameTooltip:SetPoint("TOP", owner, "BOTTOM", 0, -4)
    GameTooltip:AddLine("Glass MiniMap Bar")
    if empty then GameTooltip:AddLine("No minimap buttons collected yet.", 1, 1, 1) end
    if last then GameTooltip:AddLine("Right-click: " .. last.display, 1, 1, 1) end
    GameTooltip:Show()
end

function Bar.OnLauncherClick(_, mouse)
    GameTooltip:Hide()
    if mouse == "RightButton" and not IsShiftKeyDown() then
        local last = db.lastUsed and db.last
        if last and Collector.Replay(last.name, last.mouse) then return end
        GlassMiniMapBar.OpenOptions()
    elseif mouse == "RightButton" or mouse == "MiddleButton" then
        GlassMiniMapBar.OpenOptions()
    else
        Bar.Toggle()
    end
end

function Bar.OnLauncherEnter(owner)
    if db.openOn == "hover" and not Bar.IsOpen() then Bar.Open() end
    showTip(owner)
end

function Bar.OnLauncherLeave()
    GameTooltip:Hide()
end

function Bar.ApplySkin()
    for _, e in ipairs(Collector.entries) do
        if db.skin then Orb.Skin(e.btn) else Orb.Unskin(e.btn) end
    end
    if launcher then Orb.Skin(launcher) end   -- ours always wears the glass
end

function Bar.ApplyLock()
    local lib = ldbi()
    if not lib then return end
    if db.minimap.lock then lib:Lock(Bar.NAME) else lib:Unlock(Bar.NAME) end
end

function Bar.Launcher() return launcher end
function Bar.Frame() return frame end

-- Build once, at login (LibDBIcon places buttons after PLAYER_LOGIN).
function Bar.Build(database)
    db = database
    frame = CreateFrame("Frame", "GlassMiniMapBarFrame", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetFrameLevel(50)
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)             -- the gaps between buttons keep the bar, not the world
    frame:Hide()
    glass = Glass.Apply(frame, "large")
    frame:SetScript("OnUpdate", onUpdate)
    frame:SetScript("OnEvent", onEvent)
    frame:SetScript("OnShow", function(self) API.RegisterEvent(self, "GLOBAL_MOUSE_DOWN") end)
    frame:SetScript("OnHide", function(self)
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        closing = false
    end)
    grow = makeAnim(Bar.GROW.from, 1, 0, 1, Bar.GROW.duration, "OUT")
    shrink = makeAnim(1, Bar.GROW.from, 1, 0, Bar.SHRINK.duration, "IN")
    shrink:SetScript("OnFinished", function() frame:Hide() end)
    Collector.host = frame

    local LDB = LibStub("LibDataBroker-1.1", true)
    local lib = ldbi()
    if LDB and lib then
        dataObject = LDB:NewDataObject(Bar.NAME, {
            type = "data source",
            text = "Glass MiniMap Bar",
            icon = Bar.ARROWS.left,
            OnClick = Bar.OnLauncherClick,
            OnEnter = Bar.OnLauncherEnter,
            OnLeave = Bar.OnLauncherLeave,
        })
        lib:Register(Bar.NAME, dataObject, db.minimap)
        launcher = lib:GetMinimapButton(Bar.NAME)
        lib.RegisterCallback(Bar, "LibDBIcon_IconCreated", Collector.OnIconCreated)
        -- Buttons LibDBIcon made before we loaded never fire the callback.
        for _, btn in pairs(lib.objects or {}) do Collector.OnIconCreated(nil, btn) end
    else
        API.Fail("launcher", "LibDataBroker-1.1 / LibDBIcon-1.0 missing")
    end
    Bar.ApplyLock()
    return frame
end

Bar._test = {
    glass = function() return glass end,
    tick = onUpdate,
    event = onEvent,
}
