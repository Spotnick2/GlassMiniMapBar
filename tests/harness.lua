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

-- Lua files listed in the TOC, in load order. `all` includes Libs\.
function tocFiles(all)
    local files = {}
    for line in io.lines("GlassMiniMapBar.toc") do
        line = line:gsub("\r", "")
        if line:match("%.lua$") and not line:match("^#") and (all or not line:match("^Libs\\")) then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

-- Load the addon the way the client does, in a fresh session: every TOC file
-- (the stub stands in for Libs\) with (name, ns), then ADDON_LOADED and
-- PLAYER_LOGIN. opts.db: saved variables. opts.before(): runs after the
-- files load and before ADDON_LOADED (make buttons that exist "before us").
function loadAddon(opts)
    opts = opts or {}
    GlassMiniMapBar, GlassMiniMapBarDB = nil, nil
    WoW.reset()
    local ns = {}
    for _, file in ipairs(tocFiles()) do
        local chunk = assert(loadfile(file))
        chunk("GlassMiniMapBar", ns)
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
