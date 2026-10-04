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
eq(tocFiles(true)[1], "Libs/LibStub/LibStub.lua", "LibStub loads first")
eq(tocFiles()[1], "Compat.lua", "Compat is the first addon file")
eq(tocFiles()[#tocFiles()], "GlassMiniMapBar.lua", "bootstrap loads last")
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

-- Every texture the material and the orb name exists in Media/.
for size, S in pairs(GlassMiniMapBar.Glass.SIZES) do
    for _, key in ipairs({ "mask", "rim", "dark", "shadow" }) do
        local f = "Media/" .. S[key] .. ".tga"
        check(io.open(f, "rb") ~= nil, size .. " texture exists: " .. f)
    end
end
for _, t in ipairs({ "grain", "track_fade", "orb_mask", "orb_rim", "orb_dark", "orb_shadow" }) do
    check(io.open("Media/" .. t .. ".tga", "rb") ~= nil, "texture exists: " .. t)
end

-- Glass.lua is a copy of GlassUnitFrames' material on its MAIN branch: only
-- the namespace lines and the header may differ. Read through git, not the
-- working tree, whose branch another session may have switched.
-- The null device by OS: on Linux (CI), "2>nul" would create a file named
-- nul in the repo, which the packager would then ship.
local NULL = package.config:sub(1, 1) == "\\" and "nul" or "/dev/null"
local upstream = io.popen('git -C ../GlassUnitFrames show main:Glass.lua 2>' .. NULL)
local theirs = upstream and upstream:read("*a") or ""
if upstream then upstream:close() end
if theirs ~= "" then
    local function body(s)
        s = s:gsub("\r", "")
        s = s:gsub("^.-\nlocal ADDON = %.%.%.\n", "")
        s = s:gsub("GlassUF", "GlassMiniMapBar")
        return s
    end
    check(body(io.open("Glass.lua"):read("*a")) == body(theirs),
        "Glass.lua matches GlassUnitFrames main:Glass.lua (copy it back)")
    local gen = io.popen('git -C ../GlassUnitFrames show main:Tools/make_textures.py 2>' .. NULL)
    local g = gen and gen:read("*a") or ""
    if gen then gen:close() end
    check(g:gsub("\r", "") == io.open("Tools/make_textures.py", "rb"):read("*a"):gsub("\r", ""),
        "Tools/make_textures.py matches GlassUnitFrames main (copy it back)")
else
    io.write("  (Glass.lua upstream check skipped: no ../GlassUnitFrames git repo)\n")
end

done("test_toc")
