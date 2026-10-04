-- The manifest, the pinned build, and the media the material names.
dofile("tests/wow_stubs.lua")
dofile("tests/harness.lua")

local toc = io.open("GlassMiniMapBar.toc"):read("*a")
check(toc:find("## Interface: 16001", 1, true), "interface 16001 (1.60.1; 11601 is the transposed-digit bug)")
check(toc:find("## Version: @project-version@", 1, true), "packager version token kept")
check(toc:find("## SavedVariables: GlassMiniMapBarDB", 1, true), "saved variables declared")
check(toc:find("## X-Curse-Project-ID: 1715522", 1, true), "CurseForge project ID (1715522)")
for _, f in ipairs(tocFiles(true)) do
    check(io.open(f, "r") ~= nil, "TOC file exists: " .. f)
end
-- The library first: Glass.lua calls LibStub("LibGlass-1.0") at file scope.
eq(tocLines()[1], LIBGLASS_XML, "LibGlass-1.0 loads first")
eq(tocFiles(true)[1], "Libs/LibStub/LibStub.lua", "then the vendored LibStub")
eq(tocFiles()[1], "Compat.lua", "Compat is the first addon file")
eq(tocFiles()[#tocFiles()], "GlassMiniMapBar.lua", "bootstrap loads last")
-- The packager replaces its tokens in EVERY file, not just the TOC: a token
-- written whole in Lua ships as the version (v1.0.1's IsDevelopmentCopy
-- compared against "v1.0.1"). Assemble it at runtime instead.
for _, f in ipairs(tocFiles(true)) do
    local src = io.open(f, "rb"):read("*a")
    local token = src:match("@project%-[%w-]+@") or src:match("@file%-[%w-]+@")
    check(not token, f .. " holds no packager token (found " .. tostring(token) .. ")")
end
local seen = {}
for _, f in ipairs(tocFiles(true)) do
    check(not seen[f], "TOC lists each file once: " .. f)
    seen[f] = true
end

loadAddon()
eq(GlassMiniMapBar.MEASURED_ON_BUILD, "1.60.1.70009", "MEASURED_ON_BUILD")

-- The build notice: a development copy on another build speaks once per
-- build; a release never does.
local function notice(build, version, saved)
    WoW.build, WoW.version = build, version
    loadAddon({ db = saved })
    WoW.build, WoW.version = "70009", "v1.0.0"
    return table.concat(WoW.chat, "\n"):find("new client build", 1, true) ~= nil
end
local saved = {}
check(notice("70205", "dev", saved), "a deployed dev copy on a new build says so")
eq(saved.seenBuild, "1.60.1.70205", "and remembers the build it announced")
check(not notice("70205", "dev", saved), "but only once: the next login keeps quiet")
check(notice("70300", "dev", saved), "until the build changes again")
check(notice("70205", "@project-version@", {}), "an unpackaged checkout on a new build says so")
local release = {}
check(not notice("70205", "v1.0.0", release), "a release on a new build keeps quiet")
eq(release.seenBuild, nil, "and records nothing, so a later dev copy still hears it")
check(not notice("70009", "dev", {}), "a dev copy on the measured build keeps quiet")

-- Every texture the material names ships with the library (Libs\LibGlass-1.0\Media
-- in the package; the checkout's Media/ here). Ours (the orb) are in Media/.
local root = libGlassRoot()
for size, S in pairs(GlassMiniMapBar.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = root .. "/Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
for _, t in ipairs({ "grain", "track_fade" }) do
    check(io.open(root .. "/Media/" .. t .. ".tga", "rb") ~= nil, "library texture exists: " .. t)
end
for _, t in ipairs({ "orb_mask", "orb_rim", "orb_dark", "orb_shadow" }) do
    check(io.open("Media/" .. t .. ".tga", "rb") ~= nil, "orb texture exists: " .. t)
end
-- Media/ holds our own art only: a library texture left here would be dead weight.
for _, t in ipairs({ "grain", "rim5", "body_mask", "bar_fill" }) do
    check(io.open("Media/" .. t .. ".tga", "rb") == nil, "no copy of the library's " .. t .. " in Media/")
end

-- Glass.MEDIA points into the embedded copy, where the packager puts it; the
-- orb's textures stay in our own folder.
eq(GlassMiniMapBar.Glass.MEDIA, "Interface\\AddOns\\GlassMiniMapBar\\Libs\\LibGlass-1.0\\Media\\", "Glass.MEDIA is the embedded copy's")
eq(GlassMiniMapBar.Orb.MEDIA, "Interface\\AddOns\\GlassMiniMapBar\\Media\\", "Orb.MEDIA is our own folder")
check(GlassMiniMapBar.Glass ~= LibStub("LibGlass-1.0"), "Glass is our own instance, not the library")
local orb = 0
for _, r in ipairs({ launcher():GetRegions() }) do
    local f = r._file
    if type(f) == "string" and f:find("orb_", 1, true) then
        orb = orb + 1
        eq(f:sub(1, #GlassMiniMapBar.Orb.MEDIA), GlassMiniMapBar.Orb.MEDIA, "orb texture drawn from our Media: " .. f)
    end
end
check(orb > 0, "the launcher wears the orb")

done("test_toc")
