local function yes() return true end
local function no() return false end
local function empty() return {} end
local function pos(x) return {x = x} end
local function distance(a, b) return math.abs(a.x - b.x) end
local function remap(n, lo, hi, a, b) return a + (b - a) * math.max(0, math.min(1, (n - lo) / (hi - lo))) end

local file = assert(io.open('bots/FunLib/jmz_func.lua', 'rb'))
local source = file:read('*a')
file:close()
local first = assert(source:find('function J.GetClosestCore(', 1, true))
local last = assert(source:find('function J.IsCreepBetweenMeAndTarget(', first, true))
local allyFirst = assert(source:find('function J.GetClosestAlly(', 1, true))
local allyLast = assert(source:find('function J.GetNearestLaneFrontLocation(', allyFirst, true))

local function fixture(rescue)
    local state = {time = 120, orders = {}, hp = 0.9, teleports = {}}
    local bot = {x = 0, side = 2, id = 1}
    local core = {x = 700, side = 2, id = 4, core = true}
    local fartherCore = {x = 1350, side = 2, id = 2, core = true, retreating = true}
    local backup = {x = 500, side = 2, id = 3, retreating = true}
    local enemy = {x = 650, side = 3, id = 5, target = rescue and core or nil}
    local reinforcement = {x = 700, side = 3, id = 6, alive = false}
    local members, opponents = {bot, fartherCore, backup, core}, {enemy, reinforcement}
    for _, unit in ipairs({bot, core, fartherCore, backup, enemy, reinforcement}) do
        unit.GetLocation = function(self) return pos(self.x) end
        unit.GetPlayerID = function(self) return self.id end
        unit.GetTeam = function(self) return self.side end
        unit.GetUnitName = function() return 'npc_dota_hero_test' end
        unit.GetAttackTarget = function(self) return self.target end
        unit.IsAlive = function(self) return self.alive ~= false end
        unit.CanBeSeen = function(self) return self.visible ~= false end
        unit.IsInvulnerable, unit.IsAttackImmune, unit.IsNull, unit.IsIllusion = no, no, no, no
        unit.IsHero = yes
        unit.HasModifier, unit.GetNearbyTowers, unit.GetNearbyLaneCreeps = no, empty, empty
        unit.GetHealth = function() return 1000 end
        unit.GetHealthRegen = function() return 0 end
        unit.GetAttackRange = function() return 700 end
        unit.GetCurrentMovementSpeed = function() return 300 end
        unit.GetEstimatedDamageToTarget = function() return 5 end
        unit.GetExtrapolatedLocation = unit.GetLocation
    end
    bot.GetLevel, bot.FindItemSlot = function() return 12 end, function() return -1 end
    bot.GetItemSlotType, bot.GetNetWorth = function() return 0 end, function() return 3000 end
    bot.GetNearbyCreeps = empty
    bot.GetActiveMode, bot.GetCurrentActionType = function() return 0 end, function() return 0 end
    bot.GetActiveModeDesire, bot.GetBoundingRadius = function() return 0.3 end, function() return 0 end
    bot.GetTarget = function() return state.target end
    bot.SetTarget = function(_, target) state.target = target end
    bot.Action_AttackUnit = function(_, target) state.orders[#state.orders + 1] = target end
    bot.Action_MoveToLocation = function(_, target) state.orders[#state.orders + 1] = target end
    bot.Action_ClearActions = function() state.orders[#state.orders + 1] = 'cancel' end
    bot.WasRecentlyDamagedByAnyHero, bot.WasRecentlyDamagedByTower = no, no
    bot.WasRecentlyDamagedByCreep = no
    local function near(roster, point, radius)
        local result = {}
        for _, unit in ipairs(roster) do
            if unit:IsAlive() and unit:CanBeSeen() and distance(unit, point) <= radius then
                result[#result + 1] = unit
            end
        end
        return result
    end
    bot.GetNearbyHeroes = function(_, radius, hostile) return near(hostile and opponents or members, bot, radius) end

    local j = {
        IsValidHero = function(unit) return unit ~= nil and unit:IsAlive() and unit:CanBeSeen() end,
        IsValid = function(unit) return unit ~= nil and unit:IsAlive() end,
        CanBeAttacked = yes, IsValidBuilding = no, IsSuspiciousIllusion = no, CanNotUseAction = no,
        IsRetreating = function(unit) return unit.retreating == true end,
        IsCore = function(unit) return unit.core == true end,
        IsInRange = function(a, b, radius) return distance(a, b) <= radius end,
        GetHP = function(unit) return unit == bot and state.hp or 0.8 end, GetMP = function() return 1 end,
        GetAlliesNearLoc = function(point, radius) return near(members, point, radius) end,
        GetEnemiesNearLoc = function(point, radius) return near(opponents, point, radius) end,
        GetTeamFightLocation = function() return pos(650) end,
        GetDistance = distance, WeAreStronger = no, IsInLaningPhase = no, IsInTeamFight = yes,
        IsEarlyGame = no, IsMidGame = no, IsChasingTarget = no,
        GetSpecialModeAllies = empty, GetTotalEstimatedDamageToTarget = function() return 50 end,
        GetMostPushLaneDesire = function() return 2 end, GetMostDefendLaneDesire = function() return 2 end,
        CheckBotIdleState = no, IsThereCoreNearby = yes,
        IsGoingOnSomeone = no, IsFarming = no, IsPushing = no, IsDefending = no,
        IsDoingRoshan = no, IsDoingTormentor = no,
        Role = {IsPvNMode = no}, Utils = {IsValidUnit = function(unit) return unit ~= nil and unit:IsAlive() end},
    }
    local modules = {
        ['bots/FunLib/jmz_func'] = j,
        ['bots/FunLib/utils'] = {SetFrameProcessTime = function() end, BuggyHeroesDueToValveTooLazy = {[bot:GetUnitName()] = true}},
        ['bots/FunLib/enemy_role_estimation'] = {UpdateEnemyHeroPositions = function() end},
        ['game/botsinit'] = {CreateGeneric = empty},
        ['bots/Customize/general'] = {}, ['bots/FunLib/localization'] = {},
        ['bots/FunLib/aba_item'] = {}, ['bots/FunLib/aba_role'] = {},
    }
    local env = setmetatable({
        J = j, GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
        GetTeam = function() return 2 end, GetOpposingTeam = function() return 3 end,
        GetTeamForPlayer = function(id) return id <= 4 and 2 or 3 end,
        GetIncomingTeleports = function() return state.teleports end,
        IsLocationVisible = function(location) return not location.hidden end,
        GetTeamPlayers = function() return {1, 2, 3, 4} end, GetTeamMember = function(i) return members[i] end,
        GetUnitList = function(kind) return kind == 1 and members or opponents end,
        require = function(name) return assert(modules[name], name) end,
        DotaTime = function() return state.time end, GetDroppedItemList = empty,
        GetUnitToUnitDistance = distance, GetUnitToLocationDistance = distance, RemapValClamped = remap,
        UNIT_LIST_ALLIED_HEROES = 1, UNIT_LIST_ENEMY_HEROES = 2,
        BOT_MODE_NONE = 0, BOT_MODE_DESIRE_NONE = 0, BOT_MODE_DESIRE_VERYHIGH = 0.9,
        BOT_MODE_DESIRE_MODERATE = 0.5, BOT_MODE_DESIRE_ABSOLUTE = 1, BOT_ACTION_DESIRE_NONE = 0,
        BOT_ACTION_TYPE_DELAY = 5, BOT_MODE_WARD = 6, ITEM_SLOT_TYPE_BACKPACK = 2, DAMAGE_TYPE_ALL = 3,
    }, {__index = _G})
    env.dofile = function(name)
        if name == 'bots/FunLib/aba_special_units' then return {GetDesire = function() return 0 end} end
        return setfenv(assert(loadfile(name .. '.lua')), env)()
    end
    setfenv(assert(loadstring(source:sub(allyFirst, allyLast - 1) .. source:sub(first, last - 1))), env)()
    local path = rescue and 'bots/mode_team_roam_generic.lua' or 'bots/mode_attack_generic.lua'
    setfenv(assert(loadfile(path)), env)()
    return state, env, bot, core, backup, enemy, reinforcement, j
end

do
    local state, mode, bot, core, _, enemy, reinforcement, j = fixture(true)
    core.retreating = true
    assert(j.GetClosestCore(bot, 1800) == core, 'support finds the actual closest core')
    assert(mode.GetDesire() > 0.9 and #state.orders == 0 and state.target == nil, 'desire should not issue a rescue order')
    mode.Think()
    assert(state.orders[1] == enemy and state.target == enemy)
    reinforcement.alive = true
    mode.Think()
    assert(state.orders[2] == 'cancel' and #state.orders == 2 and state.target == nil, 'drop an unsafe rescue after reinforcement')
    reinforcement.alive = false
    assert(mode.GetDesire() > 0.9)
    mode.Think()
    enemy.target = nil
    assert(mode.GetDesire() == 0)
    mode.OnEnd()
    assert(state.orders[3] == enemy and state.orders[4] == 'cancel', 'stop when the pursuer disengages')
    enemy.target, state.hp = core, 0.2
    assert(mode.GetDesire() == 0, 'do not start a rescue with critically low health')
end

do
    local state, mode, _, core, backup, enemy = fixture(false)
    core.retreating = true
    assert(mode.GetDesire() == 0, 'a team-fight marker alone must not force a solo join')
    backup.retreating = false
    assert(mode.GetDesire() > 0)
    mode.Think()
    assert(state.orders[1] == enemy)
    backup.retreating = true
    mode.Think()
    assert(state.orders[2] == 'cancel' and state.target == nil, 'stop committed attacks as backup withdraws')
    assert(mode.GetDesire() == 0, 'desire smoothing must not preserve a withdrawn decision')
    backup.retreating = false
    assert(mode.GetDesire() > 0)
    mode.Think()
    backup.alive = false
    mode.Think()
    assert(state.orders[3] == enemy and state.orders[4] == 'cancel', 'stop committed attacks when the nearby ally dies')
end

do
    local state, mode, bot, core, backup, enemy, _, j = fixture(true)
    core.retreating = true
    assert(mode.GetDesire() > 0.9)
    mode.Think()
    assert(state.orders[1] == enemy, 'begin a justified rescue before the first hostile teleport')

    local function teleport(id, x, seconds)
        return {playerid = id, location = pos(x), time_remaining = seconds}
    end
    local destination = teleport(8, 700, 2.5)
    destination.location.hidden = true
    state.teleports = {teleport(2, 700, 2), teleport(5, 700, 2), teleport(6, 700, 3),
        teleport(6, 700, 3), teleport(7, 700, 4.5), destination}
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot),
        'ignore friendly, duplicate, distant in time and out-of-vision teleport arrivals')

    destination.location.hidden = false
    state.teleports[#state.teleports + 1] = teleport(7, 750, 1.5)
    assert(mode.GetDesire() == 0, 'cancel team roam before the four enemies arrive')
    mode.Think()
    assert(state.orders[2] == 'cancel' and state.target == nil, 'clear the already-issued rescue order')
    setfenv(assert(loadfile('bots/mode_retreat_generic.lua')), mode)()
    assert(mode.GetDesire() > mode.BOT_MODE_DESIRE_ABSOLUTE, 'give withdrawal priority at high health')

    state.teleports = {}
    state.time = state.time + 0.5
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'hold withdrawal briefly through the teleport handoff')
    state.time = state.time + 1.5
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'stop holding withdrawal if the reinforcements disappear')

    core.retreating, backup.retreating = false, false
    state.teleports = {teleport(6, 700, 2), teleport(7, 750, 1.5), destination}
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'nearby available backup prevents an automatic retreat')
end
print('PASS: stop unsafe fights and rescue orders, including before visible hostile teleports finish')
