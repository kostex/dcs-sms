-- mock_me_route.lua — synthetic stand-in for the ME's `me_route` module
-- (the right-hand Route panel), covering only the surface route_verbs.lua
-- actually touches.
--
-- The interesting part is `actions` + `waypointActionToType`. ED does NOT
-- store a waypoint's mode as two flat strings: `wpt.type` holds a reference
-- into this very `actions` table ({ name=, type=, action= }) and `wpt.action`
-- is deleted, a conversion fixWaypointForGroup performs on every mission load
-- (me_mission.lua:1029-1030). The save path then reads the pair back out of
-- `wpt.type.type` / `wpt.type.action` (me_mission.lua:4045-4046 air,
-- 4240-4241 ground), so anything else in `wpt.type` silently serializes as
-- nil.
--
-- test_verbs_route.lua deliberately does NOT preload this module: it exercises
-- the string-fallback path route_verbs takes in standalone contexts.
-- test_verbs_route_wp_type.lua preloads it to exercise the real ME path.

local M = {}

-- Mirrors DCS's Scripts/utils_common.lua `actions` table verbatim (minus the
-- _() localisation wrapper, which only affects `name`).
M.actions = {
    turningPoint      = { name = 'Turning point',           type = 'Turning Point',      action = 'Turning Point' },
    flyOverPoint      = { name = 'Fly over point',          type = 'Turning Point',      action = 'Fly Over Point' },
    finPoint          = { name = 'Fin point (N/A)',         type = 'Fin Point',          action = 'Fin Point' },
    takeoffRunway     = { name = 'Takeoff from runway',     type = 'TakeOff',            action = 'From Runway' },
    takeoffParking    = { name = 'Takeoff from parking',    type = 'TakeOffParking',     action = 'From Parking Area' },
    takeoffParkingHot = { name = 'Takeoff from parking hot',type = 'TakeOffParkingHot',  action = 'From Parking Area Hot' },
    LandingReFuAr     = { name = 'LandingReFuAr',           type = 'LandingReFuAr',      action = 'LandingReFuAr' },
    takeoffGround     = { name = 'Takeoff from ground',     type = 'TakeOffGround',      action = 'From Ground Area' },
    takeoffGroundHot  = { name = 'Takeoff from ground hot', type = 'TakeOffGroundHot',   action = 'From Ground Area Hot' },
    landing           = { name = 'Landing',                 type = 'Land',               action = 'Landing' },
    offRoad           = { name = 'Offroad',                 type = 'Turning Point',      action = 'Off Road' },
    onRoad            = { name = 'On road',                 type = 'Turning Point',      action = 'On Road' },
    rank              = { name = 'Rank',                    type = 'Turning Point',      action = 'Rank' },
    cone              = { name = 'Cone',                    type = 'Turning Point',      action = 'Cone' },
    vee               = { name = 'Vee',                     type = 'Turning Point',      action = 'Vee' },
    diamond           = { name = 'Diamond',                 type = 'Turning Point',      action = 'Diamond' },
    echelonL          = { name = 'Echelon Left',            type = 'Turning Point',      action = 'EchelonL' },
    echelonR          = { name = 'Echelon Right',           type = 'Turning Point',      action = 'EchelonR' },
    customForm        = { name = 'Custom',                  type = 'Turning Point',      action = 'Custom' },
    onRailroads       = { name = 'On railroads',            type = 'On Railroads',       action = 'On Railroads' },
}

M.alt_types_all = {
    BARO  = { type = 'BARO',  name = 'MSL' },
    RADIO = { type = 'RADIO', name = 'AGL' },
}

local wptByType

-- me_route.lua:2399-2406
local function createWaypointsIndex(actions)
    local idx = {}
    for _, v in pairs(actions) do
        idx[v.type .. ':' .. v.action] = v
    end
    return idx
end

-- me_route.lua:2410-2430. Note the concatenation on the first line: a nil
-- `action` raises "attempt to concatenate local 'action' (a nil value)"
-- exactly as the shipped ME does — that is the crash a .miz written from a
-- bare-string wpt.type produces on its post-save reload.
function M.waypointActionToType(type, action, groupType)
    if not wptByType then
        wptByType = createWaypointsIndex(M.actions)
    end
    local t = wptByType[type .. ':' .. action]
    if not t then
        if groupType == 'plane' or groupType == 'helicopter' or groupType == 'ship' then
            t = M.actions.turningPoint
        else
            if 'On Road' == action then
                t = M.actions.onRoad
            else
                t = M.actions.offRoad
            end
        end
    end
    return t
end

-- Panel refresh hooks. route_verbs' refresh_route_panel pcalls both; count
-- the calls so tests can assert the panel was poked.
M.update_calls = 0
function M.update() M.update_calls = M.update_calls + 1 end

M.actionsListBox = {}
function M.actionsListBox:update(_) end

return M
