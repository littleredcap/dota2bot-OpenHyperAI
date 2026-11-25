local function yes() return true end
local function no() return false end
local function empty() return {} end
local NONE = 0

local file = assert(io.open('bots/FunLib/jmz_func.lua', 'rb'))
local source = file:read('*a')
file:close()
local first = assert(source:find('function J.GetHeroesTargetingUnit(', 1, true))
local last = assert(source:find('function J.GetSameUnitType(', first, true))
local laneSafety = assert(loadstring(source:sub(first, last - 1)))

local function fixture(core, overridden)
    local state = {time = 180, creepHP = 30, orders = {}, hp = 0.9}
    local heroName = 'npc_dota_hero_test'
    local creep = {x = 200, GetHealth = function() return state.creepHP end}
    local partner = {x = 260, IsAlive = yes}
    local bot = {x = 0}
    local enemy = {x = 260, GetAttackRange = function() return 500 end,
        GetAttackTarget = function() return state.pressure and bot or nil end}
    local tower = {x = 700, GetAttackTarget = function() return state.tower and bot or nil end}
    bot.GetUnitName = function() return heroName end
    bot.GetLevel = function() return 5 end
    bot.GetAssignedLane = function() return 3 end
    bot.GetLocation = function() return bot.x end
    bot.GetAttackRange = function() return 450 end
    bot.GetAttackDamage = function() return 50 end
    bot.IsInvulnerable, bot.IsIllusion, bot.IsDisarmed = no, no, no
    bot.IsAlive, bot.IsHero, bot.IsUsingAbility, bot.IsChanneling = yes, yes, no, no
    bot.HasModifier = function(_, name) return name == 'modifier_tango_heal' end
    bot.WasRecentlyDamagedByAnyHero = function() return state.pressure end
    bot.WasRecentlyDamagedByCreep, bot.WasRecentlyDamagedByTower = no, no
    bot.GetNearbyHeroes = function() return state.enemy and {enemy} or {} end
    bot.GetNearbyTowers = function() return state.tower and {tower} or {} end
    bot.GetNearbyLaneCreeps = function(_, _, hostile)
        if not hostile or state.noCreeps then return {} end
        return state.manyCreeps and {creep, creep, creep} or {creep}
    end
    bot.GetItemSlotType = function() return 0 end
    bot.FindItemSlot = function() return -1 end
    bot.SetTarget = function() end
    bot.Action_MoveToLocation = function(_, point) state.orders[#state.orders + 1] = {'move', point} end
    bot.Action_MoveToUnit = function(_, target) state.orders[#state.orders + 1] = {'approach', target} end
    bot.Action_AttackUnit = function(_, target) state.orders[#state.orders + 1] = {'attack', target} end

    local utils = {BuggyHeroesDueToValveTooLazy = {[heroName] = overridden}, GameStates = {},
        NumHumanBotPlayersInTeam = function() return 0, 5 end, IsTeamPushingSecondTierOrHighGround = no,
        GetLastSeenEnemyIdsNearLocation = empty}
    local j = {
        Utils = utils, GetPosition = function() return core and 1 or 5 end,
        IsPosxHuman = function() return not overridden end, IsInLaningPhase = yes,
        GetEnemiesAroundAncient = function() return 0 end,
        IsValid = function(unit) return unit ~= nil end,
        IsValidHero = function(unit) return unit == enemy or unit == partner end,
        IsValidBuilding = function(unit) return unit == tower end,
        IsSuspiciousIllusion = no, IsChasingTarget = no, IsThereNonSelfCoreNearby = no,
        GetHP = function() return state.hp end, CanNotUseAction = no, CanBeAttacked = yes,
        GetAttackProDelayTime = function() return 0.3 end,
        WillKillTarget = function(_, damage) return state.creepHP <= damage end,
        IsCore = function(unit) return unit == partner or core end,
        GetLanePartner = function() return state.partner and partner or nil end,
        IsInRange = function(a, b, range) return math.abs(a.x - b.x) <= range end,
    }
    local modules = {['bots/FunLib/utils'] = utils, ['bots/FunLib/jmz_func'] = j,
        ['bots/FunLib/version'] = {}, ['bots/FunLib/localization'] = {},
        ['game/botsinit'] = {CreateGeneric = empty}}
    local env = setmetatable({
        J = j, GetScriptDirectory = function() return 'bots' end, GetBot = function() return bot end,
        require = function(name) return assert(modules[name], name) end,
        GetTeam = function() return 2 end, GetOpposingTeam = function() return 3 end,
        GetTeamPlayers = empty, GetGameMode = function() return 0 end,
        GetLaneFrontLocation = function(_, _, offset) return offset end,
        GetLaneFrontAmount = function() return 0.5 end,
        GetUnitToUnitDistance = function(a, b) return math.abs(a.x - b.x) end,
        RandomVector = function() return 0 end, RandomFloat = function() return 0.1 end,
        DotaTime = function() return state.time end, GameTime = function() return state.time end,
        TEAM_RADIANT = 2, LANE_TOP = 1, LANE_MID = 2, LANE_BOT = 3,
        ITEM_SLOT_TYPE_MAIN = 1, BOT_MODE_NONE = 0, GAMEMODE_1V1MID = 1, GAMEMODE_MO = 2,
        BOT_ACTION_DESIRE_NONE = NONE, BOT_MODE_DESIRE_NONE = NONE, BOT_MODE_DESIRE_VERYLOW = 0.1,
    }, {__index = _G})
    env.dofile = function(path) return setfenv(assert(loadfile(path .. '.lua')), env)() end
    setfenv(laneSafety, env)()
    setfenv(assert(loadfile('bots/mode_laning_generic.lua')), env)()
    return state, env, creep, enemy
end

local function expect(state, mode, kind, target)
    state.orders = {}
    mode.Think()
    if kind == nil then assert(#state.orders == 0); return end
    assert(#state.orders == 1, 'there must be one lane order per tick')
    assert(state.orders[1][1] == kind and state.orders[1][2] == target, 'unexpected lane order')
end

do
    local state, mode, creep = fixture(true, true)
    assert(mode.GetDesire() == 0.9, 'override lane assignment and last-hit desire must load')
    expect(state, mode, 'attack', creep)
    state.enemy, state.pressure = true, true
    expect(state, mode, 'move', -1200)
    state.enemy, state.pressure = false, false
    expect(state, mode, 'attack', creep)
end

do
    local state, mode, _, enemy = fixture(false, true)
    state.partner, state.enemy = true, true
    mode.GetDesire()
    expect(state, mode, 'attack', enemy)
    state.manyCreeps = true
    expect(state, mode, 'move', -500)
    state.time = state.time + 0.2
    state.manyCreeps = false
    expect(state, mode, 'attack', enemy)
end

do
    local state, mode, creep = fixture(true, false)
    mode.GetDesire()
    state.creepHP = 65
    expect(state, mode, nil)
    state.creepHP = 30
    expect(state, mode, 'attack', creep)
    state.tower = true
    expect(state, mode, 'move', -1200)
end
print('PASS: lane last hits resume after pressure, support yields farm, and unsafe harass does not replace positioning')
