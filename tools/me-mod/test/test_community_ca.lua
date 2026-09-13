-- test_community_ca.lua
-- community_ca locates a readable CA bundle for the HTTPS transport. The bug
-- it exists to prevent: handing OpenSSL a cafile it cannot open makes LuaSec
-- report 'error loading CA locations ((null))' — OpenSSL raises a *system*
-- error for an unopenable file and ERR_reason_error_string() returns NULL for
-- those, so the user sees nothing actionable. We check readability ourselves.
package.path = '../lua/dcs_sms_me/?.lua;../lua/?.lua;' .. package.path
package.preload['lfs'] = function()
    return { writedir = function() return 'C:\\SG\\DCS\\' end,
             currentdir = function() return 'D:\\DCS World' end,
             mkdir = function() return true end }
end
local ca = require('dcs_sms_me.community_ca')

local failures = 0
local function check(n, ok, msg) if ok then print('PASS '..n) else print('FAIL '..n..': '..tostring(msg)); failures=failures+1 end end

-- A fake io.open: only the listed paths "exist". Records opens/closes so we
-- can prove the probe never leaks a handle.
local function opener(existing)
    local opened, closed = {}, 0
    local fn = function(path)
        opened[#opened + 1] = path
        if existing[path] then
            return { close = function() closed = closed + 1 end, read = function() return 'x' end }
        end
        return nil, path .. ': No such file or directory'
    end
    return fn, opened, function() return closed end
end

-- ---- dir_from_source() -----------------------------------------------------
-- Plain Lua reports a file chunk as '@<path>'; the DCS Mission Editor's loader
-- reports the bare path (verified live: './MissionEditor/modules/dcs_sms_me\
-- paths.lua'). Both must yield the directory, and non-file chunks must not.
check('dir_from_source: plain-Lua @ form',
      ca.dir_from_source('@C:\\DCS\\MissionEditor\\modules\\dcs_sms_me\\community_ca.lua')
      == 'C:\\DCS\\MissionEditor\\modules\\dcs_sms_me\\')
check('dir_from_source: DCS form without @',
      ca.dir_from_source('./MissionEditor/modules/dcs_sms_me\\community_ca.lua')
      == './MissionEditor/modules/dcs_sms_me\\')
check('dir_from_source: loadstring chunk rejected', ca.dir_from_source('=(load)') == nil)
check('dir_from_source: inline code rejected', ca.dir_from_source('return 1 + 1') == nil)
check('dir_from_source: bare filename has no directory', ca.dir_from_source('init.lua') == nil)
check('dir_from_source: non-string rejected', ca.dir_from_source(nil) == nil)

-- ---- candidates() ----------------------------------------------------------
local cands = ca.candidates()
check('candidates() returns a list', type(cands) == 'table' and #cands > 0, #cands)
check('installed lib payload is tried first',
      cands[1] == 'C:\\SG\\DCS\\dcs-sms\\lib\\cacert.pem', cands[1])

-- The copy that ships inside the installed mod dir: derived from where this
-- very module was loaded from, so it follows the mod wherever it is installed.
local self_dir = debug.getinfo(ca.candidates, 'S').source:sub(2):match('^(.*[/\\])[^/\\]*$')
local has_self_copy, has_me_modules = false, false
for _, p in ipairs(cands) do
    if p == self_dir .. 'cacert.pem' then has_self_copy = true end
    if p:find('MissionEditor', 1, true) and p:find('dcs_sms_me', 1, true) then has_me_modules = true end
end
check('the copy next to the loaded module is a candidate', has_self_copy,
      table.concat(cands, ' | '))
check('the <DCS install>\\MissionEditor\\modules copy is a candidate', has_me_modules,
      table.concat(cands, ' | '))

local seen, dupes = {}, false
for _, p in ipairs(cands) do
    check('candidate is a non-empty string', type(p) == 'string' and p ~= '', tostring(p))
    if seen[p] then dupes = true end
    seen[p] = true
end
check('no duplicate candidates', not dupes, table.concat(cands, ' | '))

-- ---- resolve(): picks the first readable candidate --------------------------
local open1, opened1, closed1 = opener({ ['C:\\SG\\DCS\\dcs-sms\\lib\\cacert.pem'] = true })
local path1 = ca.resolve(open1)
check('resolve() returns the lib payload when it is readable',
      path1 == 'C:\\SG\\DCS\\dcs-sms\\lib\\cacert.pem', path1)
check('resolve() stops at the first hit', #opened1 == 1, table.concat(opened1, ' | '))
check('resolve() closes the handle it opened', closed1() == 1, closed1())

-- ---- resolve(): falls back to the mod-dir copy ------------------------------
local module_copy
for _, p in ipairs(cands) do if p ~= cands[1] then module_copy = p; break end end
local open2, opened2 = opener({ [module_copy] = true })
local path2 = ca.resolve(open2)
check('resolve() falls back when the lib payload is missing', path2 == module_copy, path2)
check('resolve() tried the lib payload first', opened2[1] == cands[1], opened2[1])

-- ---- resolve(): nothing readable → nil + the paths tried --------------------
local open3 = opener({})
local path3, tried3 = ca.resolve(open3)
check('resolve() returns nil when no candidate is readable', path3 == nil, path3)
check('resolve() reports every path it tried',
      type(tried3) == 'table' and #tried3 == #cands, tried3 and #tried3)

if failures > 0 then os.exit(1) end
print('All community_ca tests passed.')
