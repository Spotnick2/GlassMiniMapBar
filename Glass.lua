-- Glass.lua: this addon's instance of the "liquid glass" material.
--
-- The material lives in the embedded library LibGlass-1.0
-- (Libs\LibGlass-1.0, from github.com/Spotnick2/LibGlass through .pkgmeta
-- externals; the TOC loads it first). Its contract, write-up and textures are
-- there: material changes are LibGlass PRs, not edits here.
--
-- An instance, not the library itself: STYLE and the setters are this addon's
-- own, so nothing here touches another glass addon's surfaces. Every call site
-- keeps the dot-call shape (Glass.Apply, Glass.Inset, Glass.STYLE, ...).
-- Three materials (LibGlass's presets): Pearl (r11: clean with a softer wash,
-- gloss and frost; Glass UI's suite theme and our default), clean, and
-- classic (the library's default, our look before Pearl). The instance is
-- built once, at ADDON_LOADED, after Suite.lua has asked Glass UI which one
-- (#37): nothing may read GlassMiniMapBar.Glass at file scope.
-- Glass.MEDIA is the library's folder: the round button's own textures use
-- Orb.MEDIA.

GlassMiniMapBar = GlassMiniMapBar or {}
local GMB = GlassMiniMapBar
GMB.PEARL_MINOR = 11
GMB.MATERIALS = { "pearl", "clean", "classic" }
GMB.MATERIAL_LABELS = { pearl = "Pearl", clean = "Clean", classic = "Classic" }

function GMB.IsMaterial(name) return GMB.MATERIAL_LABELS[name] ~= nil end

-- Build the instance with `preset`, once. Returns true, or false and why:
-- "library-too-old" (the LibGlass that won LibStub predates Pearl) or
-- "build-failed" (New errored). After a failure the instance is classic,
-- which every LibGlass builds (New with no preset). GMB.GlassPreset is what
-- was built, GMB.GlassMinor the library's MINOR at the attempt.
function GMB.BuildGlass(preset)
    if GMB.Glass then return true end
    local lib, minor = LibStub("LibGlass-1.0")
    GMB.GlassMinor = minor
    local why
    if preset == "pearl" and (type(minor) ~= "number" or minor < GMB.PEARL_MINOR) then
        why = "library-too-old"
    else
        -- classic is New's default: no preset name, so a pre-r11 copy builds it too.
        local opts = preset ~= "classic" and { preset = preset } or nil
        local ok, made = pcall(lib.New, lib, opts)
        if ok and made then
            GMB.Glass, GMB.GlassPreset = made, preset
            return true
        end
        why = "build-failed"
    end
    GMB.Glass, GMB.GlassPreset = lib:New(), "classic"
    return false, why
end
