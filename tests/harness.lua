-- harness.lua: the addon loader. dofile it after wow_stubs.lua. The assertions
-- (check / eq / done) are WowTestKit's.

TOC = "GlassMiniMapBar.toc"

-- Every file line of the TOC, in load order (our .lua files, the vendored
-- Libs\ and the embedded LibGlass's .xml), as written.
function tocLines() return Kit.tocLines(TOC) end

-- Lua files listed in the TOC, in load order. `all` includes the vendored Libs\.
function tocFiles(all)
    local files = {}
    for _, file in ipairs(Kit.tocFiles(TOC)) do
        if all or not file:match("^Libs/") then files[#files + 1] = file end
    end
    return files
end

-- The embedded LibGlass-1.0 comes from a checkout, not from Libs\ (gitignored,
-- filled by the packager): $LIBGLASS, else ../LibGlass. No checkout fails the
-- run loudly; a silently skipped library would test nothing.
LIBGLASS_XML = "Libs\\LibGlass-1.0\\LibGlass-1.0.xml"
function libGlassRoot()
    local root = (os.getenv("LIBGLASS") or "../LibGlass"):gsub("\\", "/"):gsub("/$", "")
    local f = io.open(root .. "/LibGlass-1.0.xml", "rb")
    if not f then
        error("LibGlass checkout not found at " .. root .. " (no LibGlass-1.0.xml): clone "
              .. "github.com/Spotnick2/LibGlass there or set LIBGLASS", 0)
    end
    f:close()
    return root
end

-- The Lua files the library's XML loads, as paths, in order: what the client
-- runs for the TOC's XML line. A listed file that is missing fails here.
function libGlassScripts()
    local root = libGlassRoot()
    local f = assert(io.open(root .. "/LibGlass-1.0.xml", "rb"))
    local xml = f:read("*a"):gsub("<!%-%-.-%-%->", "")   -- listed in a comment is not loaded
    f:close()
    local files = {}
    for file in xml:gmatch('<Script%s+file="([^"]+)"') do
        local path = root .. "/" .. file:gsub("\\", "/")
        local src = io.open(path, "rb")
        if not src then error("LibGlass checkout at " .. root .. " is missing " .. file, 0) end
        src:close()
        files[#files + 1] = path
    end
    if #files == 0 then error("LibGlass-1.0.xml at " .. root .. " lists no Script files", 0) end
    return files
end

-- Load the addon the way the client does, in a fresh session: every TOC line
-- with (name, ns), the library's XML expanded in place and the vendored Libs\
-- stood in for by the stub's fakes, then ADDON_LOADED and PLAYER_LOGIN.
-- opts.tocAddons: TOC compartment entries registered after PLAYER_LOGIN.
-- opts.db: saved variables. opts.before(): runs after the files load and
-- before ADDON_LOADED (make buttons that exist "before us").
-- opts.suite: a fake Glass UI (WoW.FakeGlassUI's options, or true), loaded
-- before us as OptionalDeps makes it, and returned second; opts.glassUI: a
-- GlassUI of your own. opts.loaded(): runs between ADDON_LOADED and
-- PLAYER_LOGIN (another addon's login code may run before ours).
function loadAddon(opts)
    opts = opts or {}
    GlassMiniMapBar, GlassMiniMapBarDB, LibStub, GlassUI = nil, nil, nil, nil
    WoW.reset()
    local fakeUI
    if opts.suite then fakeUI = WoW.FakeGlassUI(opts.suite ~= true and opts.suite or nil) end
    if opts.glassUI ~= nil then GlassUI = opts.glassUI end
    local ns, faked = {}, false
    for _, line in ipairs(tocLines()) do
        local files = {}
        if line == LIBGLASS_XML then
            files = libGlassScripts()
        elseif not line:match("%.lua$") then
            error("the harness can't load TOC line " .. line, 0)
        elseif line:match("^Libs\\") then
            if not faked then WoW.installFakeLibs(); faked = true end
        else
            files = { (line:gsub("\\", "/")) }
        end
        for _, file in ipairs(files) do
            local chunk = assert(loadfile(file))
            chunk("GlassMiniMapBar", ns)
        end
    end
    if opts.db then GlassMiniMapBarDB = opts.db end
    if opts.before then opts.before() end
    WoW.fire("ADDON_LOADED", "GlassMiniMapBar")
    if opts.loaded then opts.loaded() end
    WoW.fire("PLAYER_LOGIN")
    -- Blizzard's bulk compartment registration, then PLAYER_ENTERING_WORLD.
    if opts.tocAddons then WoW.RegisterTocAddons(opts.tocAddons) end
    WoW.fire("PLAYER_ENTERING_WORLD", true, false)
    WoW.flushTimers(0)
    return GlassMiniMapBar, fakeUI
end

function launcher() return GlassMiniMapBar.Bar.Launcher() end
function bar() return GlassMiniMapBar.Bar.Frame() end
function entry(name) return GlassMiniMapBar.Collector.byName[name] end
function names()
    local t = {}
    for _, e in ipairs(GlassMiniMapBar.Collector.entries) do t[#t + 1] = e.name end
    return table.concat(t, ",")
end
