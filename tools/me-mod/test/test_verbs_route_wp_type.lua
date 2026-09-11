-- test_verbs_route_wp_type.lua — route/waypoint verbs against a mission
-- state where the ME's `me_route` panel module IS loaded.
--
-- test_verbs_route.lua covers the same verbs with panel_route absent, which
-- is the string-fallback path. This file covers the shape the verbs actually
-- have to produce inside DCS: `wpt.type` holding a reference into
-- panel_route.actions, with the (type, action) pair readable back out of it.
--
-- Why it matters: ED's save serializes a waypoint as
--     type = s.type.type, action = s.type.action
-- (me_mission.lua:4045-4046 air, 4240-4241 ground). Indexing a *string* with
-- .type yields nil in Lua rather than raising, so a bare-string wpt.type is
-- written to the .miz as type=nil/action=nil and the post-save reload dies in
-- waypointActionToType (me_route.lua:2414). Every test here therefore ends by
-- round-tripping the waypoint through ED's own save + reload expressions.
--
-- Run via:
--   cd tools/me-mod/test && lua5.1 test_verbs_route_wp_type.lua
-- Or through the harness:
--   pwsh tools/me-mod/test/run-tests.ps1

local here = (arg and arg[0] and arg[0]:match('^(.*[\\/])')) or './'
package.path = here .. '?.lua;' .. package.path

local mock = require('mock_me_mission')
local mock_route = require('mock_me_route')
package.preload['me_mission']    = function() return mock end
package.preload['me_map_window'] = function() return mock end
package.preload['me_route']      = function() return mock_route end

package.path = here .. '../lua/?.lua;' .. here .. '../lua/?/init.lua;' .. package.path

local verbs = require('dcs_sms_me.verbs')

-- ============================================================
-- Test helpers
-- ============================================================

local passed, failed, errors = 0, 0, {}

local function assert_eq(actual, expected, name)
    if actual == expected then
        passed = passed + 1
    else
        failed = failed + 1
        table.insert(errors, string.format(
            '%s: expected %s, got %s', name, tostring(expected), tostring(actual)))
    end
end

local function assert_true(cond, name) assert_eq(cond and true or false, true, name) end

-- ed_save_point — the exact expressions ED's save path uses to serialize a
-- waypoint's mode into the .miz (me_mission.lua:4045-4046 / 4240-4241).
-- Returns the two values that land in the file.
local function ed_save_point(wp)
    return wp.type.type, wp.type.action
end

-- ed_reload_point — what fixWaypointForGroup does with those two values on
-- the next mission load (me_mission.lua:1029 → me_route.lua:2410-2430).
-- Returns ok, result_or_error the way pcall does, so a test can assert the
-- reload survives rather than crashing the ME.
local function ed_reload_point(saved_type, saved_action, group_type)
    return pcall(mock_route.waypointActionToType, saved_type, saved_action, group_type)
end

-- assert_survives_save_reload — the invariant every write verb must hold.
local function assert_survives_save_reload(wp, group_type, want_type, want_action, label)
    local saved_type, saved_action = ed_save_point(wp)
    assert_eq(saved_type, want_type, label .. ': .miz type')
    assert_eq(saved_action, want_action, label .. ': .miz action')
    local ok = ed_reload_point(saved_type, saved_action, group_type)
    assert_true(ok, label .. ': post-save reload survives')
    -- The legacy flat field must never contradict the table the save
    -- actually reads from.
    assert_eq(wp.action, wp.type.action,
        label .. ': wpt.action tracks wpt.type.action')
end

local function new_vehicle_group(name)
    mock.new_mission()
    local created = verbs.group_create_vehicle({
        country = 'Russia', type = 'T-72B', name = name, north = 0, east = 0 })
    assert_true(created.ok, name .. ': group created')
    return mock.group_by_name[name]
end

local function new_plane_group(name)
    mock.new_mission()
    local created = verbs.group_create_plane({
        country = 'USA', type = 'F-16C_50', name = name, north = 0, east = 0 })
    assert_true(created.ok, name .. ': group created')
    return mock.group_by_name[name]
end

-- ============================================================
-- waypoint add / insert
-- ============================================================

-- The 2026-09-07 Discord repro, end to end: create a vehicle group, append
-- two waypoints, and confirm the route survives ED's save + reload.
local function test_add_vehicle_waypoint_survives_save_reload()
    local g = new_vehicle_group('veh-add')
    local r = verbs.waypoint_add({ name = 'veh-add', north = 1000, east = 1000,
        speed = 8, type = 'Turning Point', action = 'Off Road' })
    assert_true(r.ok, 'add: ok — ' .. tostring(r.error))

    local wp = g.route.points[2]
    assert_eq(type(wp.type), 'table', 'add: wpt.type normalized to the actions entry')
    assert_eq(wp.type, mock_route.actions.offRoad, 'add: exact panel_route.actions reference')
    assert_survives_save_reload(wp, 'vehicle', 'Turning Point', 'Off Road', 'add')

    -- Second add inherits from a waypoint whose type is now a TABLE. Feeding
    -- that back into insert_waypoint's `type` argument unflattened would nest
    -- one actions entry inside the next.
    local r2 = verbs.waypoint_add({ name = 'veh-add', north = 2000, east = 2000, speed = 8 })
    assert_true(r2.ok, 'add 2: ok — ' .. tostring(r2.error))
    local wp2 = g.route.points[3]
    assert_eq(type(wp2.type), 'table', 'add 2: wpt.type is an actions entry, not nested')
    assert_survives_save_reload(wp2, 'vehicle', 'Turning Point', 'Off Road', 'add 2 (inherited)')
end

local function test_insert_vehicle_waypoint_survives_save_reload()
    local g = new_vehicle_group('veh-ins')
    local r = verbs.waypoint_insert({ name = 'veh-ins', before = 1,
        north = 500, east = 500, speed = 8 })
    assert_true(r.ok, 'insert: ok — ' .. tostring(r.error))
    assert_survives_save_reload(g.route.points[2], 'vehicle',
        'Turning Point', 'Off Road', 'insert')
end

local function test_add_plane_landing_waypoint_survives_save_reload()
    local g = new_plane_group('air-add')
    local r = verbs.waypoint_add({ name = 'air-add', north = 9000, east = 9000,
        type = 'Land', action = 'Landing' })
    assert_true(r.ok, 'air add: ok — ' .. tostring(r.error))
    assert_survives_save_reload(g.route.points[2], 'plane', 'Land', 'Landing', 'air add')
end

-- ============================================================
-- set-type / set-action / set-mode
-- ============================================================

local function test_set_type_pairs_canonical_action()
    local g = new_plane_group('air-st')
    verbs.waypoint_add({ name = 'air-st', north = 9000, east = 9000 })
    local r = verbs.waypoint_set_type({ name = 'air-st', index = 1, wp_type = 'Land' })
    assert_true(r.ok, 'set_type: ok — ' .. tostring(r.error))
    assert_eq(r.type, 'Land', 'set_type: response type is a flat string')
    assert_eq(r.action, 'Landing', 'set_type: response action paired')
    assert_survives_save_reload(g.route.points[2], 'plane', 'Land', 'Landing', 'set_type')
end

local function test_set_type_turning_point_keeps_existing_action()
    -- 'Turning Point' is shared by every ground formation, so set-type must
    -- leave the action alone rather than snapping it to a canonical one.
    local g = new_vehicle_group('veh-st')
    verbs.waypoint_add({ name = 'veh-st', north = 1000, east = 1000, action = 'On Road' })
    local r = verbs.waypoint_set_type({ name = 'veh-st', index = 1, wp_type = 'Turning Point' })
    assert_true(r.ok, 'set_type TP: ok — ' .. tostring(r.error))
    assert_survives_save_reload(g.route.points[2], 'vehicle',
        'Turning Point', 'On Road', 'set_type TP')
end

-- Ground formations live entirely in the ACTION (type stays 'Turning Point'),
-- and ED's save reads the action out of wpt.type — never wpt.action. Leaving
-- wpt.type stale here meant the formation change was silently dropped on save.
local function test_set_action_formation_reaches_the_miz()
    local g = new_vehicle_group('veh-sa')
    verbs.waypoint_add({ name = 'veh-sa', north = 1000, east = 1000, action = 'Off Road' })
    local r = verbs.waypoint_set_action({ name = 'veh-sa', index = 1, action = 'Rank' })
    assert_true(r.ok, 'set_action Rank: ok — ' .. tostring(r.error))
    assert_eq(r.action, 'Rank', 'set_action Rank: response action')
    assert_survives_save_reload(g.route.points[2], 'vehicle',
        'Turning Point', 'Rank', 'set_action Rank')
end

-- Trains: 'On Railroads' is the one non-airfield action with its own type.
-- While ACTION_CANONICAL_TYPE only listed the airfield actions, set-action
-- left the type at 'Turning Point', and ED substituted Off Road for the
-- illegal pair — the requested mode never reached the .miz.
local function test_set_action_on_railroads_keeps_its_type()
    local g = new_vehicle_group('veh-rail')
    verbs.waypoint_add({ name = 'veh-rail', north = 1000, east = 1000 })
    local r = verbs.waypoint_set_action({ name = 'veh-rail', index = 1,
        action = 'On Railroads' })
    assert_true(r.ok, 'set_action rails: ok — ' .. tostring(r.error))
    assert_eq(r.action, 'On Railroads', 'set_action rails: response action')
    assert_eq(r.type, 'On Railroads', 'set_action rails: response type')
    assert_survives_save_reload(g.route.points[2], 'vehicle',
        'On Railroads', 'On Railroads', 'set_action rails')
end

-- Every action in the CLI's enum must resolve to a legal pair, i.e. ED must
-- return the entry we asked for rather than substituting a fallback.
local function test_every_action_resolves_to_itself()
    local g = new_vehicle_group('veh-all')
    verbs.waypoint_add({ name = 'veh-all', north = 1000, east = 1000 })
    local actions = {
        'Turning Point', 'Fly Over Point', 'From Parking Area',
        'From Parking Area Hot', 'From Ground Area', 'From Ground Area Hot',
        'From Runway', 'Landing', 'LandingReFuAr', 'Off Road', 'On Road',
        'Rank', 'Cone', 'Vee', 'Diamond', 'EchelonL', 'EchelonR', 'Custom',
        'On Railroads',
    }
    for _, action in ipairs(actions) do
        local r = verbs.waypoint_set_action({ name = 'veh-all', index = 1, action = action })
        assert_true(r.ok, 'set_action ' .. action .. ': ok')
        assert_eq(r.action, action, 'set_action ' .. action .. ': action round-trips')
        local saved_type, saved_action = ed_save_point(g.route.points[2])
        assert_eq(saved_action, action, 'set_action ' .. action .. ': reaches the .miz')
        local ok = ed_reload_point(saved_type, saved_action, 'vehicle')
        assert_true(ok, 'set_action ' .. action .. ': reload survives')
    end
end

local function test_set_action_airfield_pairs_type()
    local g = new_plane_group('air-sa')
    verbs.waypoint_add({ name = 'air-sa', north = 9000, east = 9000 })
    local r = verbs.waypoint_set_action({ name = 'air-sa', index = 1,
        action = 'From Parking Area' })
    assert_true(r.ok, 'set_action parking: ok — ' .. tostring(r.error))
    assert_survives_save_reload(g.route.points[2], 'plane',
        'TakeOffParking', 'From Parking Area', 'set_action parking')
end

local function test_set_mode_survives_save_reload()
    local g = new_plane_group('air-sm')
    verbs.waypoint_add({ name = 'air-sm', north = 9000, east = 9000 })
    local r = verbs.waypoint_set_mode({ name = 'air-sm', index = 1, mode = 'Landing' })
    assert_true(r.ok, 'set_mode: ok — ' .. tostring(r.error))
    assert_eq(r.type, 'Land', 'set_mode: response type is a flat string')
    assert_eq(r.action, 'Landing', 'set_mode: response action is a flat string')
    assert_survives_save_reload(g.route.points[2], 'plane', 'Land', 'Landing', 'set_mode')
end

-- An illegal (type, action) combination is not an error in ED — its own
-- waypointActionToType substitutes a default (me_route.lua:2415-2425). What
-- must not happen is the verb reporting, or the waypoint carrying, a mode
-- different from the one that reaches the .miz.
local function test_illegal_pair_resolves_consistently()
    local g = new_plane_group('air-ill')
    verbs.waypoint_add({ name = 'air-ill', north = 9000, east = 9000,
        type = 'Land', action = 'Landing' })
    -- 'Turning Point' paired with the waypoint's existing 'Landing' action is
    -- not a legal combination; ED resolves it to a plain turning point.
    local r = verbs.waypoint_set_type({ name = 'air-ill', index = 1,
        wp_type = 'Turning Point' })
    assert_true(r.ok, 'illegal pair: ok — ' .. tostring(r.error))
    assert_eq(r.type, 'Turning Point', 'illegal pair: response type')
    assert_eq(r.action, 'Turning Point', 'illegal pair: response reports the resolved action')
    assert_survives_save_reload(g.route.points[2], 'plane',
        'Turning Point', 'Turning Point', 'illegal pair')
end

-- ============================================================
-- Wire shape — reads always flatten, whichever in-memory shape
-- ============================================================

local function test_reads_report_flat_type_and_action()
    local g = new_vehicle_group('veh-read')
    -- WP0 as the ME leaves it after a mission load: mode in the type table,
    -- no standalone action field.
    g.route.points[1].type = mock_route.actions.offRoad
    g.route.points[1].action = nil
    verbs.waypoint_add({ name = 'veh-read', north = 1000, east = 1000, action = 'On Road' })

    local rl = verbs.route_list({ name = 'veh-read' })
    assert_true(rl.ok, 'route_list: ok')
    assert_eq(rl.points[1].type, 'Turning Point', 'route_list WP0: flat type')
    assert_eq(rl.points[1].action, 'Off Road', 'route_list WP0: action recovered from type table')
    assert_eq(rl.points[2].type, 'Turning Point', 'route_list WP1: flat type')
    assert_eq(rl.points[2].action, 'On Road', 'route_list WP1: flat action')

    local rg = verbs.route_get({ name = 'veh-read' })
    assert_true(rg.ok, 'route_get: ok')
    assert_eq(rg.route.points[1].type, 'Turning Point', 'route_get WP0: flat type')
    assert_eq(rg.route.points[1].action, 'Off Road', 'route_get WP0: flat action')
    assert_eq(rg.route.points[2].action, 'On Road', 'route_get WP1: flat action')

    local wg = verbs.waypoint_get({ name = 'veh-read', index = 0 })
    assert_true(wg.ok, 'waypoint_get: ok')
    assert_eq(wg.waypoint.type, 'Turning Point', 'waypoint_get: flat type')
    assert_eq(wg.waypoint.action, 'Off Road', 'waypoint_get: flat action')

    local added = verbs.waypoint_add({ name = 'veh-read', north = 2000, east = 2000 })
    assert_eq(added.waypoint.type, 'Turning Point', 'waypoint_add response: flat type')
    assert_eq(added.waypoint.action, 'On Road', 'waypoint_add response: flat action')
end

-- ============================================================
-- Test runner
-- ============================================================

test_add_vehicle_waypoint_survives_save_reload()
test_insert_vehicle_waypoint_survives_save_reload()
test_add_plane_landing_waypoint_survives_save_reload()
test_set_type_pairs_canonical_action()
test_set_type_turning_point_keeps_existing_action()
test_set_action_formation_reaches_the_miz()
test_set_action_on_railroads_keeps_its_type()
test_every_action_resolves_to_itself()
test_set_action_airfield_pairs_type()
test_set_mode_survives_save_reload()
test_illegal_pair_resolves_consistently()
test_reads_report_flat_type_and_action()

print(string.format('test_verbs_route_wp_type: %d passed, %d failed', passed, failed))
for _, e in ipairs(errors) do print('  FAIL: ' .. e) end
os.exit(failed == 0 and 0 or 1)
