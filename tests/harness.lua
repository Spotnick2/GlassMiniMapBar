-- harness.lua: assertions and the addon loader. dofile it after wow_stubs.lua.

local passed, failed = 0, 0

function check(cond, msg)
    if cond then passed = passed + 1 else
        failed = failed + 1
        io.write("  FAIL: " .. tostring(msg) .. "\n")
    end
end

function eq(actual, expected, msg)
    check(actual == expected, string.format("%s: expected %s, got %s", msg, tostring(expected), tostring(actual)))
end

function done(name)
    io.write(string.format("%s: %d passed, %d failed\n", name, passed, failed))
    os.exit(failed == 0 and 0 or 1)
end

-- Every file line of the TOC, in load order (our .lua files, the vendored
-- Libs\ and the embedded LibGlass's .xml), as written.
function tocLines()
    local lines = {}
    for line in io.lines("GlassMiniMapBar.toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^#") then lines[#lines + 1] = line end
    end
    return lines
end

-- Lua files listed in the TOC, in load order. `all` includes the vendored Libs\.
function tocFiles(all)
    local files = {}
    for _, line in ipairs(tocLines()) do
        if line:match("%.lua$") and (all or not line:match("^Libs\\")) then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
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
-- opts.db: saved variables. opts.before(): runs after the files load and
-- before ADDON_LOADED (make buttons that exist "before us").
function loadAddon(opts)
    opts = opts or {}
    GlassMiniMapBar, GlassMiniMapBarDB, LibStub = nil, nil, nil
    WoW.reset()
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
    WoW.fire("PLAYER_LOGIN")
    WoW.flushTimers(0)
    return GlassMiniMapBar
end

function launcher() return GlassMiniMapBar.Bar.Launcher() end
function bar() return GlassMiniMapBar.Bar.Frame() end
function entry(name) return GlassMiniMapBar.Collector.byName[name] end
function names()
    local t = {}
    for _, e in ipairs(GlassMiniMapBar.Collector.entries) do t[#t + 1] = e.name end
    return table.concat(t, ",")
end
