-- Loads production files in isolated, minimal mock game environments.
local function loadProduction(file, env)
    setmetatable(env, {__index = _G})
    setfenv(assert(loadfile(file)), env)()
    return env
end
local function yes() return true end
local function no() return false end
local function empty() return {} end
local function nilValue() return nil end
local function botForLane(name, top, mid, bot)
    return {stats = {name = name, laneWeights = {top = top, mid = mid, bot = bot}}}
end

local function runRoles(radiant, dire)
    local env = loadProduction('bots/FretBots/RoleDetermination.lua', {
        require = empty,
        GetScriptDirectory = function() return 'bots' end,
        Debug = {IsDebug = no, Print = function() end},
        DOTA_TEAM_BADGUYS = 3,
        LANE_SAFE = 1, LANE_MID = 2, LANE_OFF = 3,
        AllBots = {[2] = radiant, [3] = dire},
    })
    env.RoleDetermination:DetermineRoles()
    return env.AllBots
end

local left = botForLane('radiant mid', 80, 1, 50)
local right = botForLane('dire mid', 90, 2, 75)
local result = runRoles({}, {right})
assert(#result[2] == 0 and result[3][1] == right and right.stats.role == 2)
result = runRoles({left}, {})
assert(#result[3] == 0 and result[2][1] == left and left.stats.role == 2)
local radiantSafe = botForLane('radiant safe', 90, 80, 1)
local direSafe = botForLane('dire safe', 1, 80, 90)
result = runRoles({left, radiantSafe}, {right, direSafe})
assert(result[2][1] == radiantSafe and result[2][2] == left and radiantSafe.stats.role == 1)
assert(result[3][1] == direSafe and result[3][2] == right and direSafe.stats.role == 1)

local function roam(opts)
    local scored = {}
    local pos = opts.pos or 4
    local bot = {
        GetUnitName = function() return 'npc_dota_hero_axe' end,
        IsAlive = yes, IsHero = yes, IsInvulnerable = no, IsIllusion = no,
        GetLocation = function() return 'bot' end, GetAbilityByName = nilValue,
        GetMana = function() return 600 end,
        GetLevel = function() return opts.level or 4 end,
        GetAssignedLane = function() return opts.own or 1 end,
    }
    local J = {
        Utils = {GameStates = {twinGates = {}}},
        GetEnemiesNearLoc = empty,
        GetEnemyCountInLane = function(lane) return (opts.lanes or {})[lane] and 1 or 0 end,
        GetPosition = function() return pos end,
        IsInLaningPhase = function() return opts.laning or false end,
        GetAlliesNearLoc = function() return {{}} end,
        HasItem = function(_, name) assert(name == 'item_tpscroll'); return opts.tp or false end,
    }
    local env = loadProduction('bots/mode_roam_generic.lua', {
        require = function(name) if name:find('jmz_func', 1, true) then return J end; return {} end,
        GetScriptDirectory = function() return 'bots' end,
        GetBot = function() return bot end, GetTeam = function() return 2 end,
        LANE_TOP = 1, LANE_MID = 2, LANE_BOT = 3,
        TOWER_TOP_1 = 11, TOWER_MID_1 = 12, TOWER_BOT_1 = 13,
        GetTower = function(_, tower) return tower end,
        GetLaneFrontLocation = function(_, lane) return lane end,
        GetUnitToLocationDistance = function(unit, lane)
            if unit == bot then return opts.lanes[lane] end
            return 500
        end,
        DotaTime = function() return 600 end,
        RemapValClamped = function(distance) scored[#scored + 1] = distance; return 0.5 end,
        Clamp = function(value) return value end,
        BOT_MODE_DESIRE_NONE = 0, BOT_ACTION_DESIRE_VERYHIGH = 0.9,
        BOT_ACTION_DESIRE_MODERATE = 0.4, BOT_ACTION_DESIRE_HIGH = 0.7,
    })
    assert(env.botLevel == nil, 'test must not rely on a shared level global')
    return env.CheckLaneToGank(pos), scored
end

local desire, scored = roam({lanes = {[1] = 500, [2] = 5000, [3] = 1400}})
assert(desire == 0.6 and #scored == 1 and scored[1] == 1400, 'skip own/distant lane but continue to third')
desire, scored = roam({lanes = {[1] = 400, [2] = 5000}, tp = true})
assert(desire == 0.6 and #scored == 1 and scored[1] == 5000, 'TP allows distant other lane')
desire, scored = roam({lanes = {[2] = 4000}})
assert(desire == 0.6 and #scored == 1 and scored[1] == 4000, '4000 units does not require TP')
desire, scored = roam({lanes = {[1] = 500, [2] = 5000}})
assert(desire == 0 and #scored == 0, 'no qualifying lane')
desire, scored = roam({level = 3, lanes = {[2] = 1000}})
assert(desire == 0 and #scored == 0, 'level 3 cannot initiate pos 4 gank even with eligible lane')
desire, scored = roam({pos = 2, level = 12, laning = true, lanes = {[2] = 1000}})
assert(desire == 0 and #scored == 0, 'mid core remains barred in laning phase')

print('PASS: 3 role-assignment cases and 6 gank-lane cases')
