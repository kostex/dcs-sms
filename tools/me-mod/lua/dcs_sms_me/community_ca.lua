-- community_ca.lua — locate a readable CA bundle (cacert.pem) for the
-- community HTTPS transport.
--
-- WHY THIS EXISTS: LuaSec hands `cafile` straight to
-- SSL_CTX_load_verify_locations(). When OpenSSL cannot *open* that file it
-- raises a SYSTEM error (errno), and ERR_reason_error_string() returns NULL for
-- system errors — so LuaSec's message degrades to the useless
--
--     ssl.wrap: error loading CA locations ((null))
--
-- which is what users saw when <writedir>\dcs-sms\lib\cacert.pem was missing
-- (payload never deployed because install-me-mod couldn't resolve Saved Games,
-- a hand-rolled LuaSec drop that had no CA bundle, antivirus, ...). Probing the
-- candidates ourselves lets us both fall back and say something actionable.
--
-- Two locations are tried, in order:
--   1. <writedir>\dcs-sms\lib\cacert.pem                   — the LuaSec payload
--      install-me-mod deploys next to ssl.dll (unchanged, still primary).
--   2. <the installed mod's own directory>\cacert.pem      — shipped alongside
--      MissionEditor\modules\dcs_sms_me\. That dir is written on every
--      install/update and lives in the DCS install rather than Saved Games, so
--      it is there whenever the mod itself is.

local paths = require('dcs_sms_me.paths')

local M = {}

M.FILE = 'cacert.pem'

local function is_absolute(p)
    return p:match('^%a:[/\\]') ~= nil       -- C:\... / C:/...
        or p:sub(1, 2) == '\\\\'             -- \\server\share
        or p:sub(1, 1) == '/'                -- /unix/style
end

local function with_sep(dir)
    local last = dir:sub(-1)
    if last == '\\' or last == '/' then return dir end
    return dir .. '\\'
end

-- The directory part of a chunk's `source`, or nil when it doesn't name a Lua
-- file. Plain Lua marks file chunks with a leading '@'; DCS's Mission Editor
-- loader hands back the bare path instead ('./MissionEditor/modules/…'), so
-- both forms are accepted and anything that isn't a .lua path (a loadstring
-- chunk, '=(load)', a bare filename) is rejected. Exposed for tests.
function M.dir_from_source(source)
    if type(source) ~= 'string' then return nil end
    local src = source:gsub('^@', '')
    if not src:lower():find('%.lua$') then return nil end
    return src:match('^(.*[/\\])[^/\\]*$')
end

-- Directories that may hold the mod's own copy of the CA bundle. Both a
-- possibly-relative and an absolutised form are offered: DCS's Mission Editor
-- puts RELATIVE entries on package.path ('./MissionEditor/modules/?.lua'), so
-- our own chunk name can be relative to the process working directory.
-- resolve() decides between them by opening, so a wrong guess costs nothing.
local function module_dirs()
    local dirs = {}
    local cwd
    do
        local ok, dir = pcall(function() return require('lfs').currentdir() end)
        if ok and type(dir) == 'string' and dir ~= '' then cwd = with_sep(dir) end
    end

    -- 1. The directory this very file was loaded from. getinfo must be called
    -- from inside a function defined HERE (level 1 = that function), not via
    -- pcall(debug.getinfo, ...) — that reports pcall's own C frame instead.
    local ok, info = pcall(function() return debug.getinfo(1, 'S') end)
    local dir = ok and type(info) == 'table' and M.dir_from_source(info.source) or nil
    if dir then
        dirs[#dirs + 1] = dir
        if cwd and not is_absolute(dir) then
            dirs[#dirs + 1] = cwd .. (dir:gsub('^%.[/\\]', ''))
        end
    end

    -- 2. Derived from the working directory: the ME runs from the DCS install
    -- root (or its bin dir on some installs), and the mod always installs to
    -- <install>\MissionEditor\modules\dcs_sms_me\.
    if cwd then
        local install = cwd:gsub('[/\\]$', '')
        install = install:gsub('[/\\][bB][iI][nN]%-[mM][tT]$', ''):gsub('[/\\][bB][iI][nN]$', '')
        dirs[#dirs + 1] = with_sep(install) .. 'MissionEditor\\modules\\dcs_sms_me\\'
    end

    return dirs
end

-- Every path worth probing, best first. Pure string work — no filesystem hit.
function M.candidates()
    local list, seen = {}, {}
    local function add(p)
        if type(p) == 'string' and p ~= '' and not seen[p] then
            seen[p] = true
            list[#list + 1] = p
        end
    end
    add(paths.LIB_DIR .. M.FILE)
    for _, dir in ipairs(module_dirs()) do add(dir .. M.FILE) end
    return list
end

-- First candidate that actually opens for reading.
-- Returns the path, or nil plus the list of paths tried.
-- `open` is injectable for tests; it defaults to io.open.
function M.resolve(open)
    open = open or io.open
    local tried = M.candidates()
    for _, path in ipairs(tried) do
        local ok, handle = pcall(open, path, 'rb')
        if ok and handle then
            pcall(function() handle:close() end)
            return path
        end
    end
    return nil, tried
end

return M
