-- PublicAPI.lua: a small, stable API for other addons (#25).
--
-- First asked for by Glass MiniMap, the glass minimap reskin: its bottom-left
-- disc becomes the bar's launcher, and the bar follows its theme. The
-- contract is docs/PUBLIC-API.md. What keeps it stable (AltStable's rules):
--
--   * PUBLIC_API_VERSION changes on ANY incompatible change: a function's
--     arguments or meaning, a removal. Adding a function does not bump it.
--   * nothing here hands out a live table of ours.
--   * a consumer's callback runs under pcall: its error stays its own
--     (/gmb failures lists it).
--
-- Named PUBLIC_API_VERSION, not API_VERSION: GlassMiniMapBar.API is the
-- client adapter (Compat.lua), not this.

GlassMiniMapBar = GlassMiniMapBar or {}
local Bar = GlassMiniMapBar.Bar

GlassMiniMapBar.PUBLIC_API_VERSION = 1

local function isFrame(f)
    return type(f) == "table" and type(f.GetObjectType) == "function" and type(f.IsMouseOver) == "function"
end

-- Open the bar from `frame` (another addon's button) instead of our own
-- minimap button, which stays hidden meanwhile (never saved: the player's own
-- choice comes back on ReleaseLauncher, or when the other addon is gone).
-- Safe before or after our PLAYER_LOGIN. `frame` must be shown and sized like
-- a button; its look is the caller's. opts.setIcon(icon, coords): called with
-- the launcher's face (the last button used, or the arrow toward the bar):
-- a file path, a file ID or an atlas name (C_Texture.GetAtlasInfo tells
-- which); coords is nil or { left, right, top, bottom }. Returns true, or
-- false and why.
function GlassMiniMapBar.UseLauncher(frame, opts)
    if not isFrame(frame) then return false, "UseLauncher takes a frame" end
    if opts ~= nil and type(opts) ~= "table" then return false, "opts must be a table" end
    Bar.Attach(frame, opts or {})
    return true
end

-- Back to our own minimap button (shown again unless the player hid it).
function GlassMiniMapBar.ReleaseLauncher()
    Bar.Detach()
end

-- The caller's launcher frame calls these from its OnClick / OnEnter /
-- OnLeave scripts (we never hook someone else's frame). Ignored unless `frame`
-- is the launcher handed to UseLauncher.
function GlassMiniMapBar.LauncherClick(frame, mouse)
    if frame ~= nil and frame == Bar.External() then Bar.OnLauncherClick(frame, mouse) end
end

function GlassMiniMapBar.LauncherEnter(frame)
    if frame ~= nil and frame == Bar.External() then Bar.OnLauncherEnter(frame) end
end

function GlassMiniMapBar.LauncherLeave(frame)
    if frame ~= nil and frame == Bar.External() then Bar.OnLauncherLeave(frame) end
end

-- The body tint of the bar and its round buttons, so they follow the
-- caller's theme. r, g, b in 0..1; a nil alpha keeps each surface's own;
-- wash multiplies the built top-down wash (1 = as built). No arguments: the
-- look as built. Remembered before the bar exists, applied to buttons that
-- arrive later. Returns false for values out of range.
function GlassMiniMapBar.SetGlassTint(r, g, b, a, wash)
    if r == nil then
        Bar.SetGlassTint(nil)
        return true
    end
    local function unit(v) return type(v) == "number" and v >= 0 and v <= 1 end
    if not (unit(r) and unit(g) and unit(b)) or (a ~= nil and not unit(a))
        or (wash ~= nil and not (type(wash) == "number" and wash >= 0 and wash <= 2)) then
        return false
    end
    Bar.SetGlassTint({ r, g, b, a, wash })
    return true
end

-- True while we follow Glass UI's suite look (Suite.lua): its tint and wash
-- are then on the bar and the orbs, and SetGlassTint's colours are kept but
-- not painted. A host that themes us stops calling SetGlassTint while this is
-- true, so the bar has one driver. Decided once per session, at our
-- ADDON_LOADED; false before that. Added within PUBLIC_API_VERSION 1.
function GlassMiniMapBar.FollowsSuite()
    return GlassMiniMapBar.Suite.Applying() == true
end

-- GlassMiniMapBar.OpenOptions() (GlassMiniMapBar.lua) is part of this API too:
-- it opens our page in Options > AddOns.
