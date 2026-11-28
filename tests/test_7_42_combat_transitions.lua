local function yes() return true end
local function no() return false end
local function empty() return {} end
local function pos(x, y, z) return {x = x, y = y or 0, z = z or 0} end
local function distance(a, b) return math.sqrt((a.x - b.x)^2 + ((a.y or 0) - (b.y or 0))^2) end
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
        unit.GetLocation = function(self) return pos(self.x, self.y) end
        unit.GetPlayerID = function(self) return self.id end
        unit.GetTeam = function(self) return self.side end
        unit.GetUnitName = function() return 'npc_dota_hero_test' end
        unit.GetAttackTarget = function(self) return self.target end
        unit.IsAlive = function(self) return self.alive ~= false end
        unit.CanBeSeen = function(self) return self.visible ~= false end
        unit.IsInvulnerable, unit.IsAttackImmune, unit.IsNull, unit.IsIllusion = no, no, no, no
        unit.IsHero, unit.IsCourier = yes, no
        unit.HasModifier, unit.GetNearbyTowers, unit.GetNearbyLaneCreeps = no, empty, empty
        unit.GetHealth = function() return 1000 end
        unit.GetHealthRegen = function() return 0 end
        unit.GetAttackRange = function() return 700 end
        unit.GetAttackDamage = function(self) return self.damage or 100 end
        unit.GetSecondsPerAttack = function() return 1 end
        unit.IsChanneling, unit.IsDisarmed, unit.IsStunned, unit.IsHexed, unit.IsNightmared, unit.IsRooted = no, no, no, no, no, no
        unit.GetCurrentMovementSpeed = function() return 300 end
        unit.GetEstimatedDamageToTarget = function() return 5 end
        unit.GetExtrapolatedLocation = unit.GetLocation
    end
    bot.GetLevel, bot.FindItemSlot = function() return 12 end, function() return -1 end
    bot.GetAssignedLane = function() return state.lane or 2 end
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
    bot.WasRecentlyDamagedByHero = function(_, attacker) return attacker == state.hitBy end
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
        GetLastSeenEnemiesNearLoc = function() return state.recent or {} end,
        GetVisibleThreatAt = function() return 0, false, 0 end,
        GetLocationToLocationDistance = distance,
        VectorTowards = function(a, b, step)
            local length = distance(a, b)
            return pos(a.x + (b.x - a.x) * step / length, a.y + (b.y - a.y) * step / length)
        end,
        GetTeamFightLocation = function() return pos(650) end,
        GetDistance = distance, WeAreStronger = no, IsInLaningPhase = no, IsInTeamFight = yes,
        GetTeamFountain = function() return pos(-6000) end,
        GetDistanceFromEnemyFountain = function() return 7300 end,
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
        GetGameMode = function() return 1 end,
        GetTeamForPlayer = function(id) return id <= 4 and 2 or 3 end,
        GetAncient = function() return state.ancient end,
        GetHeightLevel = function(point) return point.x > 1000 and 2 or 1 end,
        GetIncomingTeleports = function() return state.teleports end,
        IsLocationVisible = function(location) return not location.hidden end,
        Vector = pos, IsLocationPassable = yes,
        GetTeamPlayers = function() return {1, 2, 3, 4} end, GetTeamMember = function(i) return members[i] end,
        GetUnitList = function(kind)
            if kind == 3 then return state.courier and {state.courier} or {} end
            return kind == 1 and members or opponents
        end,
        require = function(name) return assert(modules[name], name) end,
        DotaTime = function() return state.time end, GetDroppedItemList = empty,
        GetUnitToUnitDistance = distance, GetUnitToLocationDistance = distance, RemapValClamped = remap,
        UNIT_LIST_ALLIED_HEROES = 1, UNIT_LIST_ENEMY_HEROES = 2, UNIT_LIST_ENEMIES = 3,
        BOT_MODE_NONE = 0, BOT_MODE_DESIRE_NONE = 0, BOT_MODE_DESIRE_VERYHIGH = 0.9,
        BOT_MODE_DESIRE_MODERATE = 0.5, BOT_MODE_DESIRE_ABSOLUTE = 1, BOT_ACTION_DESIRE_NONE = 0,
        BOT_ACTION_DESIRE_VERYHIGH = 0.9,
        BOT_ACTION_TYPE_DELAY = 5, BOT_MODE_WARD = 6, ITEM_SLOT_TYPE_BACKPACK = 2, DAMAGE_TYPE_ALL = 3,
        DAMAGE_TYPE_PHYSICAL = 1,
    }, {__index = _G})
    env.dofile = function(name)
        if name == 'bots/FunLib/aba_special_units' then return {GetDesire = function() return 0 end} end
        return setfenv(assert(loadfile(name .. '.lua')), env)()
    end
    setfenv(assert(loadstring(source:sub(allyFirst, allyLast - 1) .. source:sub(first, last - 1))), env)()
    j.GetPostFightCoverage=function() return nil end
    local path = rescue and 'bots/mode_team_roam_generic.lua' or 'bots/mode_attack_generic.lua'
    setfenv(assert(loadfile(path)), env)()
    return state, env, bot, core, backup, enemy, reinforcement, j
end

do
    local _, _, bot, ally, _, _, _, j = fixture(false)
    assert(j.GetAvailableFightAllies(bot, ally:GetLocation(), 900) == 1)
    ally.IsChanneling = yes
    assert(j.GetAvailableFightAllies(bot, ally:GetLocation(), 900) == 0, 'a channeling ally cannot rotate into the fight')
    ally.IsChanneling, ally.IsStunned = no, yes
    assert(j.GetAvailableFightAllies(bot, ally:GetLocation(), 900) == 0, 'a stunned ally does not provide immediate backup')
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
do
    local state = {x = 500, slowed = true, zones = {}, time = 500}
    local bot = {
        HasModifier = function(_, name) return state.slowed and name == 'modifier_sniper_shrapnel_slow' end,
        IsRooted = function() return state.rooted end, IsMagicImmune = no,
        GetLocation = function() return pos(state.x) end, GetTeam = function() return 2 end,
        GetNearbyTowers = empty, GetUnitName = function() return 'npc_dota_hero_test' end,
        IsInvulnerable = no, IsHero = yes, IsAlive = yes, IsIllusion = no, GetAbilityByName = no,
        Action_MoveToLocation = function(_, point) state.order = point end,
    }
    local j = {
        Utils = {GameStates = {}}, GetChronosphereAvoidanceLocation = function() end,
        CanNotUseAction = function() return state.channeling end, IsValidBuilding = no,
        GetTeamFountain = function() return pos(0) end,
        AdjustLocationWithOffsetTowardsFountain = function(point, step) return pos(point.x - step) end,
        GetLocationToLocationDistance = distance,
        VectorAway = function(origin, center, step) return pos(origin.x + (origin.x < center.x and -step or step)) end,
    }
    local env = setmetatable({J = j, GetAvoidanceZones = function() return state.zones end,
        DotaTime = function() return state.time end, GetUnitToLocationDistance = function(_, point) return math.abs(state.x-point.x) end,
        IsLocationVisible = function(point) return not point.hidden end, IsLocationPassable = yes,
        GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
        require = function(name) if name:find('jmz_func', 1, true) then return j end; return {} end,
        BOT_MODE_DESIRE_ABSOLUTE = 1,
    }, {__index = _G})
    local start = assert(source:find('function J.GetShrapnelEscapeLocation(', 1, true))
    local finish = assert(source:find('function J.GetChronosphereAvoidanceLocation(', start, true))
    setfenv(assert(loadstring(source:sub(start, finish - 1))), env)()
    setfenv(assert(loadfile('bots/mode_roam_generic.lua')), env)()
    local hostile = {location = pos(780), radius = 400,
        caster = {IsNull = no, GetTeam = function() return 3 end},
        ability = {IsNull = no, GetName = function() return 'sniper_shrapnel' end}}
    state.zones = {hostile}
    assert(env.GetDesire() == 1 and not state.order)
    env.Think()
    assert(state.order.x == 180, 'leave a movement margin beyond the short visible edge')
    hostile.location.hidden = true
    assert(j.GetShrapnelEscapeLocation(bot).x == -25, 'do not use hidden center coordinates')
    state.zones, state.order, state.channeling = {}, nil, true
    env.Think()
    assert(not state.order, 'do not cancel a committed channel')
    state.slowed, state.channeling = false, false
    state.time = 500.6
    env.Think()
    assert(state.order.x == -25, 'keep the exit on the first clear tick at the boundary')
    state.order, state.time = nil, 502.1
    env.Think()
    assert(not state.order, 'release the escape after two clear seconds')
    state.slowed, state.rooted = true, true
    assert(j.GetShrapnelEscapeLocation(bot) == nil, 'do not take a walking path while rooted')

    state.slowed, state.rooted, state.time = false, false, 520
    local watcherExit = pos(-700)
    bot.ohaWatcherRecoveryUntil = 528
    j.GetStalledWatcherExit = function() return not state.channeling and watcherExit or nil end
    assert(env.GetDesire() == 0.86, 'the scripted move competes with the stalled native Watcher mode')
    env.Think()
    assert(state.order == watcherExit, 'the selected movement mode issues the validated order')
    state.order, state.time = nil, 520.2
    env.Think()
    assert(not state.order, 'allow the walking order to run')
    state.channeling, state.time = true, 522
    env.Think()
    assert(not state.order, 'the movement mode rechecks safety after selection')
end

print('PASS: stop unsafe fights and rescue orders, including before visible hostile teleports finish')
print('PASS: leave perceived Shrapnel promptly and preserve a channel already in progress')

do
    local state, _, bot, core, _, enemy, _, j = fixture(false)
    state.time, state.hp, state.hitBy, core.retreating = 672, 0.42, enemy, true
    bot.GetHealth = function() return state.hp * 1000 end
    bot.GetAttackRange = function() return 550 end
    bot.WasRecentlyDamagedByAnyHero = yes
    enemy.x = 850
    j.GetVisibleThreatAt = function() return 280 end
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'retreat when an isolated ranged opponent can finish the losing duel')
    state.time, enemy.x = 675, 540
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'a reachable counterattack permits a less dangerous exchange')
    state.time, state.hitBy, enemy.x = 678, nil, 850
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'a healthy-looking enemy must also be the source of current pressure')
    state.time, state.hitBy, core.retreating = 681, enemy, false
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'available backup keeps the solo rule from overriding the fight')
    state.time, core.retreating, enemy.visible = 684, true, false
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'do not use the attacker through fog')
end

do
    local state, mode, bot, core, _, enemy, reinforcement, j = fixture(false)
    state.time, state.hp, core.retreating, enemy.target = 645, 0.67, true, bot
    enemy.HasModifier = function(_, name) return name == 'modifier_rune_doubledamage' end
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'give ground when the visible empowered enemy targets a lone laner')
    state.time, enemy.target = 648, nil
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'the rune alone does not displace a healthy farming hero')
    enemy.HasModifier, reinforcement.alive = no, true
    enemy.x, reinforcement.x = 1250, 1300
    local third = setmetatable({x=920,id=8}, {__index=enemy})
    j.GetEnemiesNearLoc = function() return {enemy, reinforcement, third} end
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'three stationary enemies outside immediate range are not an automatic rout')
    enemy.GetExtrapolatedLocation = function(self) return pos(self.x - 160) end
    reinforcement.GetExtrapolatedLocation = enemy.GetExtrapolatedLocation
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'an isolated bot withdraws as the group closes before the first hit')
    state.time, reinforcement.alive, core.retreating = 660, false, false
    j.GetEnemiesNearLoc = empty
    bot.ohaOuterTowerHoldUntil = 663
    assert(mode.GetDesire() == 0, 'a tower responder is not pulled away by the scripted attack mode')
end

do
    local state, mode, bot, core, _, enemy, reinforcement, j = fixture(false)
    state.time, state.hp, bot.core, core.retreating = 13 * 60 + 21, 1, true, true
    enemy.x, reinforcement.x, reinforcement.alive = 729, 828, true
    enemy.GetExtrapolatedLocation = function(self) return pos(self.x - 170) end
    local damage, control = 850, true
    j.GetVisibleThreatAt = function(unit, enemies, _, seconds, checkControl)
        assert(unit == bot and #enemies == 2 and seconds == 4.5 and checkControl)
        return damage, control, #enemies
    end

    setfenv(assert(loadfile('bots/mode_retreat_generic.lua')), mode)()
    assert(mode.GetDesire() > mode.BOT_MODE_DESIRE_ABSOLUTE,
        'an isolated ranged core withdraws before taking damage from two closing threats')
    state.time, damage = state.time + 2, 700
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'continue withdrawing while the same control remains reachable')
    control = false
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'nonlethal damage without control leaves an escape margin')
    damage = 1060
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'two opponents can also threaten lethal damage without control')
    state.time, core.retreating = state.time + 2, false
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'available backup prevents the isolated-core rule')
    state.hp, core.x = 0.93, 100
    core.GetAttackRange = function() return 150 end
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), '22:46: high HP does not replace an ally in reach when two opponents can burst the ranged core')
    state.time, core.x = state.time + 2, 670
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'a partner already in contact can cover the ranged core')
    state.time = state.time + 2
    core.retreating, reinforcement.visible = true, false
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'do not use the second opponent through fog')
end

do
    local state, mode, bot, core = fixture(true)
    core.retreating = true
    bot.ohaOuterTowerHoldUntil = state.time + 3
    assert(mode.GetDesire() == 0, 'a tower responder keeps its station instead of acquiring a roaming target')
    bot.HasModifier = function(_, name) return name == 'modifier_warlock_upheaval' end
    assert(mode.GetDesire() > 0, 'a tower assignment still allows escaping an active spell')
end

do
    local state, _, bot, carry, _, enemy, _, j = fixture(false)
    state.time, state.ancient = 2400, pos(3000)
    bot.target, enemy.x, carry.x, carry.damage = enemy, 1450, -11000, 310
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'stop following an enemy onto high ground without damage support')
    state.time, carry.x = 2402, 600
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'a timely core permits the chase')
    carry.x, enemy.x = -11000, 300
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'keep an attack on a target already within reach')
end

do
    local state, mode, bot, core, _, enemy, _, j = fixture(true)
    bot.core = true
    mode.LANE_MID = 2
    bot.GetAssignedLane = function() return mode.LANE_MID end
    mode.GetLaneFrontLocation = function() return pos(100) end
    bot.GetNearbyLaneCreeps = function() return {pos(500)} end
    bot.GetNearbyCreeps = function() error('team roam must leave a mid wave to the lane predictor') end
    j.IsInLaningPhase, j.IsInTeamFight = yes, no
    enemy.target = nil
    assert(mode.GetDesire() == 0, 'the mid laner keeps control of the current wave')
    core.retreating, enemy.target = true, core
    assert(mode.GetDesire() > 0, 'an urgent rescue can still interrupt farming')
    core.retreating, enemy.target = false, nil
    bot.IsCastingAbility, bot.IsUsingAbility, bot.IsInvisible = no, no, no
    j.HasQueuedAction = no
    j.GetAttackProDelayTime = function() return 0.45, 0.28, 0.05 end
    local reserveWave = true
    j.CanSpendLaneTradeTime = function() return not reserveWave end
    state.courier = setmetatable({x=530, IsCourier=yes, IsHero=no}, {__index=enemy})
    state.time = state.time + 1
    assert(mode.GetDesire() == 0, 'a safe courier stays secondary to a timed last hit')
    reserveWave = false
    assert(mode.GetDesire() == 0.75, 'a confirmed in-range courier can use a real gap in the wave')
    bot.Action_AttackUnit = function(_, target, once)
        assert(target == state.courier and once, 'issue one attack without giving a chase order')
        state.orders[#state.orders+1] = target
    end
    mode.Think()
    assert(state.orders[1] == state.courier)
end

do
    local state, _, bot, core, backup, enemy, reinforcement, j = fixture(false)
    state.time, state.recent = 15 * 60, {enemy.id, reinforcement.id}
    core.retreating = true
    assert(not j.CanCommitToLaneTeleport(bot, pos(700)), 'do not teleport alone into two recently seen defenders')
    core.retreating = false
    assert(j.CanCommitToLaneTeleport(bot, pos(700)), 'visible and recently seen copies of one hero count once')
    state.teleports = {{playerid = 7, time_remaining = 2, location = pos(700)}}
    assert(not j.CanCommitToLaneTeleport(bot, pos(700)), 'visible hostile arrivals can invalidate a landing')
    core.retreating, state.teleports = true, {}
    reinforcement.alive = true
    bot.WasRecentlyDamagedByAnyHero = yes
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'withdraw from two close enemies after losing local cover')
    state.time, core.retreating = state.time + 2, false
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'preserve an even local fight after cover arrives')
    enemy.damage, reinforcement.damage, core.target, backup.target = 270, 90, enemy, reinforcement
    backup.retreating = false
    assert(j.GetSupportedFightTarget(bot, {enemy, reinforcement}, {core, backup}) == enemy,
        'prioritize the more dangerous enemy when both targets are reachable and have the same support')
    core.IsStunned = yes
    assert(j.GetSupportedFightTarget(bot, {enemy, reinforcement}, {core, backup}) == reinforcement,
        'an unavailable ally with a stale attack target does not count as following up')
    core.IsStunned = no
    core.retreating = true
    assert(j.GetSupportedFightTarget(bot, {enemy, reinforcement}, {core, backup}) == reinforcement,
        'change target if the ally committed to the first target backs out')
end

do
    local state, _, bot, core, _, enemy, reinforcement, j = fixture(false)
    state.time, state.hp = 48 * 60, 0.48
    bot.WasRecentlyDamagedByAnyHero = yes
    reinforcement.alive = true
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'even numbers do not justify a losing fight at half health')
    state.time = state.time + 2
    j.WeAreStronger = yes
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'continue a favorable fight with the same local numbers')
    j.WeAreStronger = no
    core.x, enemy.x, enemy.target, reinforcement.alive = 7600, 1225, bot, false
    enemy.GetAttackRange = function() return 1100 end
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'disengage from an undefended long-range attacker')
    state.time, enemy.target = state.time + 2, nil
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'one distant enemy without pressure should not force retreat')
end

do
    local state, _, bot, core, _, enemy, reinforcement, j = fixture(false)
    state.time = 11 * 60
    j.GetHP = function(unit) return unit == enemy and 0.4 or 0.9 end
    enemy.GetHealth = function() return 200 end
    bot.GetEstimatedDamageToTarget = function() return 125 end
    core.GetEstimatedDamageToTarget = function() return 115 end
    assert(j.GetSupportedFightTarget(bot, {enemy}, {core}) == enemy,
        'two available allies in range take a short lethal pick without waiting for a first attack')
    reinforcement.alive = true
    assert(not j.GetSupportedFightTarget(bot, {enemy, reinforcement}, {core}), 'another defender closes the pick window')
    reinforcement.alive = false
    core.GetEstimatedDamageToTarget = function() return 80 end
    assert(not j.GetSupportedFightTarget(bot, {enemy}, {core}), 'weak damage does not initiate a pick')
end

do
    local state, _, bot, _, _, enemy, _, j = fixture(false)
    state.time, state.hp = 20 * 60, 0.7
    local tower = {GetAttackTarget = function() return bot end}
    bot.GetNearbyTowers = function() return {tower} end
    j.IsValidBuilding = function(unit) return unit == tower end
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'leave a tower shot when a defender can follow up')
    state.time, enemy.visible = state.time + 2, false
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'unseen hero pressure does not invent a retreat')
end

do
    local state, _, bot, core, backup, enemy, control, j = fixture(false)
    state.time = 15 * 60
    control.alive, control.x, core.x, backup.x, enemy.x = true, 500, 450, 450, 500
    control.GetUnitName = function() return 'npc_dota_hero_warlock' end
    local oldHP = j.GetHP
    j.GetHP = function(unit) if unit == control then return 0.62 end; return oldHP(unit) end
    core.target, backup.retreating = enemy, false
    assert(j.GetSupportedFightTarget(bot, {enemy, control}, {core, backup}) == control,
        'switch from a tank to an exposed major control caster that teammates can reach')
    control.IsSilenced = yes
    assert(j.GetSupportedFightTarget(bot, {control, enemy}, {backup, core}) == enemy,
        'a visibly silenced caster does not get a spell-threat bonus')
    control.IsSilenced, control.IsChanneling = no, yes
    assert(j.GetSupportedFightTarget(bot, {enemy, control}, {core, backup}) == control,
        'prioritize a reachable control caster already channeling')
    control.IsChanneling = no
    control.GetHealth = function() return 160 end
    j.GetHP = function(unit) if unit == control then return 0.8 end; return oldHP(unit) end
    assert(j.GetSupportedFightTarget(bot, {enemy, control}, {core, backup}) == enemy,
        'do not redirect everyone for a healthy caster with no real burst')
    bot.GetEstimatedDamageToTarget = function(_, available, unit) return unit == control and 95 or 10 end
    core.GetEstimatedDamageToTarget = bot.GetEstimatedDamageToTarget
    assert(j.GetSupportedFightTarget(bot, {enemy, control}, {core, backup}) == control,
        'a fragile caster can be a burst target even when its health percentage is high')
    core.IsDisarmed = yes
    assert(j.GetSupportedFightTarget(bot, {enemy, control}, {core, backup}) == nil,
        'do not count burst or existing commitment from a disarmed ally')
    core.IsDisarmed = no
    control.visible = false
    assert(j.GetSupportedFightTarget(bot, {control, enemy}, {backup, core}) == enemy,
        'a threat in fog cannot be selected')
    control.visible, control.x = true, 1250
    assert(j.GetSupportedFightTarget(bot, {enemy, control}, {core, backup}) == enemy,
        'do not march alone to a high-priority caster outside contact range')
    core.target = nil
    assert(j.GetSupportedFightTarget(bot, {enemy, control}, {core, backup}) == nil,
        'do not turn a focus rule into a new teamfight with no commitment')
end

do
    local state, env, bot, core, backup, enemy, control, j = fixture(false)
    state.time, bot.id = 15 * 60, 2
    enemy.x, control.x, control.y, control.alive = 600, 680, 100, true
    core.x, core.y, backup.x, backup.y, backup.retreating = 240, 50, 80, 200, false
    core.GetAttackRange = function() return 340 end
    control.GetUnitName = function() return 'npc_dota_hero_warlock' end
    local enemies, allies = {enemy, control}, {core, backup}
    local point = assert(j.GetTeamfightSpreadPoint(bot, enemy, enemies, allies), 'split locally against known AoE')
    assert(point.y < 0 and point.x < 0 and distance(point, enemy) <= 880)
    assert(j.TryTeamfightSpread(bot, enemy, enemies, allies) and #state.orders == 1)
    assert(j.TryTeamfightSpread(bot, enemy, enemies, allies) and #state.orders == 1,
        'do not send duplicate move orders during the sidestep')
    env.IsLocationPassable = function(p) return p.y >= 0 end
    assert(j.GetTeamfightSpreadPoint(bot, enemy, enemies, allies).y > 0,
        'use the safe alternate side if the first choice is blocked')
    assert(not j.TryTeamfightSpread(bot, enemy, enemies, allies),
        'do not preserve an order when its original route becomes unsafe')
    env.IsLocationPassable = no
    assert(j.GetTeamfightSpreadPoint(bot, enemy, enemies, allies) == nil,
        'do not step at all if neither side is passable')
    env.IsLocationPassable = yes
    bot.IsRooted = yes
    assert(j.GetTeamfightSpreadPoint(bot, enemy, enemies, allies) == nil)
    bot.IsRooted, bot.IsChanneling = no, yes
    assert(j.GetTeamfightSpreadPoint(bot, enemy, enemies, allies) == nil, 'do not interrupt your own channel')
    bot.IsChanneling = no
    j.IsAttacking = yes
    assert(j.GetTeamfightSpreadPoint(bot, enemy, enemies, allies) == nil, 'do not throw away an attack already winding up')
    j.IsAttacking = no
    enemy.IsChanneling = yes
    assert(j.GetTeamfightSpreadPoint(bot, enemy, enemies, allies) == nil, 'do not leave an in-range channel uninterrupted')
    enemy.IsChanneling = no
    control.visible = false
    assert(j.GetTeamfightSpreadPoint(bot, enemy, enemies, allies) == nil, 'do not locate an enemy caster through fog')
end

do
    local state, env, bot, core, _, enemy, control, j = fixture(false)
    state.time, bot.x, bot.id, core.x, enemy.x, control.x = 1144, -580, 4, -570, 650, 820
    core.GetAttackRange = function() return 150 end
    control.alive, control.GetUnitName = true, function() return 'npc_dota_hero_warlock' end
    local hub, hold = pos(0), pos(-600)
    local point = assert(j.GetTowerHoldFormationPoint(bot, hub, hold, 1200, {enemy, control}, {bot, core}),
        'split with only a ranged clearer and one frontliner, before auto-attacks start')
    assert(point.x < hold.x and math.abs(point.y) >= 450, 'move sideways behind safety, not toward the casters')
    env.IsLocationPassable = function(p) return p.y > -150 and p.y < 150 end
    assert(not j.GetTowerHoldFormationPoint(bot, hub, hold, 1200, {enemy, control}, {bot, core}),
        'never split into impassable ground')
    env.IsLocationPassable, control.visible = yes, false
    assert(not j.GetTowerHoldFormationPoint(bot, hub, hold, 1200, {enemy, control}, {bot, core}),
        'do not infer an unseen AoE threat')
    local tower = {x=0, y=0}
    bot.ohaOuterTowerHoldUntil = state.time + 3
    bot._defend = {waveClearTower = tower}
    j.IsValidBuilding = function(x) return x == tower end
    j.IsDefending, j.CanCastOnNonMagicImmune, j.CanCastOnTargetAdvanced = yes, yes, yes
    j.IsDisabled = no
    enemy.x, enemy.target = -510, core
    core.WasRecentlyDamagedByHero = function(_, attacker) return attacker == enemy end
    assert(j.GetTowerPeelTarget(bot, {enemy}, 340) == enemy,
        'interrupt a verified attacker within actual cast range')
    assert(not j.GetTowerPeelTarget(bot, {enemy}, 50), 'never walk forward for a defensive peel')
    enemy.target = nil
    assert(not j.GetTowerPeelTarget(bot, {enemy}, 340), 'no peel just because an enemy is visible')
end

do
    local state, _, bot, core, _, enemy, _, j = fixture(false)
    state.time, enemy.x, core.x = 48 * 60, 920, -260
    bot.GetAttackRange = function() return 175 end
    enemy.GetExtrapolatedLocation = function() return pos(enemy.x + 205, enemy.y) end
    assert(j.ShouldHoldFightApproach(bot, enemy), 'do not walk after a hero escaping at nearly our speed')
    bot:SetTarget(enemy)
    assert(j.TryHoldFightApproach(bot, enemy) and state.orders[1].x < 0 and state.target == nil,
        'replace the exposed chase with a bounded step back towards support')
    assert(j.TryHoldFightApproach(bot, enemy) and #state.orders == 1,
        'do not resubmit the same regroup order each tick')
    enemy.x = 220
    assert(not j.ShouldHoldFightApproach(bot, enemy), 'preserve immediate attacks even on a moving target')
    enemy.x = 860
    enemy.IsRooted = yes
    assert(not j.ShouldHoldFightApproach(bot, enemy), 'an immobilized enemy on same ground creates an opening')
    enemy.IsRooted = no
    enemy.x, core.x, core.target = 650, 500, enemy
    enemy.GetExtrapolatedLocation = enemy.GetLocation
    bot.WasRecentlyDamagedByAnyHero = yes
    assert(not j.ShouldHoldFightApproach(bot, enemy), 'nearby active pressure can cover an approach')
    core.IsDisarmed = yes
    assert(j.ShouldHoldFightApproach(bot, enemy), 'a disarmed ally does not make the frontal approach safe')
    do
        local original = j.GetEnemiesNearLoc
        enemy.GetAttackRange = function() return 150 end
        local defenders = {enemy, setmetatable({}, {__index=enemy}), setmetatable({}, {__index=enemy})}
        j.GetEnemiesNearLoc = function() return defenders end
        state.hp = 0.65
        assert(j.ShouldHoldFightApproach(bot, enemy), 'a damaged core without support does not step into three visible defenders')
        defenders[3] = nil
        assert(not j.ShouldHoldFightApproach(bot, enemy), 'the same ground without the visible numbers swing remains playable')
        local threat = j.GetVisibleThreatAt
        j.GetVisibleThreatAt = function(_, _, point, seconds, checkControl)
            assert(point.x > 0 and seconds <= 3.2 and checkControl)
            return 820, true, 2
        end
        assert(j.ShouldHoldFightApproach(bot, enemy), 'two visible enemies can close the prospective escape with control')
        j.GetVisibleThreatAt = threat
        j.GetEnemiesNearLoc = original
    end
    bot.WasRecentlyDamagedByAnyHero, enemy.x = no, 1100
    assert(j.ShouldHoldFightApproach(bot, enemy), 'do not walk uphill into an unsupported target')
    state.time = 300
    assert(not j.ShouldHoldFightApproach(bot, enemy), 'do not disrupt existing early laning micro')
    state.time, enemy.x, core.x = 1800, 600, 500
    j.GetEnemiesNearLoc = function() return {enemy} end
    j.GetAlliesNearLoc = function() return {core} end
    enemy.GetHealth = function() return 900 end
    core.IsDisarmed = no
    core.GetEstimatedDamageToTarget = function() return 90 end
    assert(not j.HasCommittedStunFollowUp(bot, enemy, 80), 'one ranged hero chipping is not follow-up for an exposed melee opener')
    enemy.GetHealth = function() return 150 end
    assert(j.HasCommittedStunFollowUp(bot, enemy, 80), 'a ranged teammate can secure a reachable low-HP target')
    core.IsDisarmed = yes
    assert(not j.HasCommittedStunFollowUp(bot, enemy, 80), 'unavailable ally cannot finish the target')
end

do
    local state, mode, bot, core, _, enemy = fixture(true)
    state.time, enemy.x, core.x, enemy.target = 48 * 60, 560, 495, nil
    bot.GetAttackRange = function() return 175 end
    core.target = enemy
    enemy.GetExtrapolatedLocation = function() return pos(enemy.x + 219) end
    local desire = mode.GetDesire()
    assert(desire == 0.86, 'the live team-roam path proposes a supported visible target: ' .. tostring(desire))
    mode.Think()
    assert(state.orders[1].x < 0 and state.target == nil,
        'the actual mode stages rather than committing a raw follow attack on the escaping target')
    enemy.x = 200
    mode.Think()
    assert(state.orders[2] == enemy and state.target == enemy,
        'the actual mode resumes the fast attack once the target is in reach')
    enemy.visible = false
    mode.Think()
    assert(state.orders[3] == 'cancel' and state.target == nil, 'vision loss clears the existing focus attack')
end

do
    local state, _, bot, channeler, _, enemy, other, j = fixture(false)
    state.time, channeler.x, enemy.x = 36 * 60 + 28, 300, 400
    channeler.IsChanneling, channeler.ohaFightControlTarget = yes, enemy
    enemy.NumModifiers = function() return 1 end
    enemy.GetModifierName = function() return 'modifier_shadow_shaman_shackles' end
    enemy.GetModifierRemainingDuration = function() return 1.5 end
    assert(j.GetAvailableFightAllies(bot, enemy:GetLocation(), 900) == 0, 'a channel still is not a mobile ally')
    assert(j.GetSupportedFightTarget(bot, {enemy}, {channeler}) == enemy,
        'a live, reachable controlled target does not need a teammate to issue the first attack')
    j.NoteFightDisable(channeler, enemy, 0.45, {})
    assert(j.GetFightDisableDelay(bot, enemy) > 0.45, 'later caster waits for imminent allied disable')
    assert(j.GetFightDisableDelay(bot, enemy) >= 1.5, 'a pending cast cannot hide longer observed control')
    state.time = state.time + 0.8
    assert(j.GetFightDisableDelay(bot, enemy) == 1.5, 'after the cast window use the observed disable')
    other.alive, other.x = true, 475
    assert(not j.GetSupportedFightTarget(bot, {enemy, other}, {channeler}), 'do not ignore the other enemy')
    other.alive = false
    enemy.NumModifiers = function() return 0 end
    assert(not j.GetSupportedFightTarget(bot, {enemy}, {channeler}), 'an unrelated or failed channel cannot authorize focus')
    local shot = {caster=channeler, ability={GetName=function() return 'test_stun' end}, location=pos(350)}
    j.IsStunProjectileSpell = function(name) return name == 'test_stun' end
    enemy.GetIncomingTrackingProjectiles = function() return {shot} end
    assert(j.GetFightDisableDelay(bot, enemy) > 0.95, 'an incoming allied stun reserves contact even for a second projectile')
    shot.caster = other
    assert(j.GetFightDisableDelay(bot, enemy) == 0, 'a hostile projectile is not allied control')
    enemy.GetIncomingTrackingProjectiles = empty
    enemy.NumModifiers = function() return 1 end
    enemy.GetModifierRemainingDuration = function() return 0.35 end
    assert(j.GetFightDisableDelay(bot, enemy) < 0.8, 'after impact a slower stun can land as control wears off')
end

print('PASS: live control activates local follow-through without pretending the channeler can rotate')

do
    local state, _, bot, core, _, enemy, other, j = fixture(false)
    state.time, state.hp, bot.core, bot.x = 16 * 60, 0.75, true, 0
    enemy.x, other.x, other.alive = 500, 550, true
    enemy.target, other.target = bot, bot
    enemy.GetEstimatedDamageToTarget = function() return 300 end
    other.GetEstimatedDamageToTarget = function() return 210 end
    j.WeAreStronger, j.IsDisabled = yes, no
    assert(j.ShouldRetreatFromEnemyReinforcements(bot), 'targeted damage forces the focused core to withdraw even in a favorable fight')
    state.time, other.target = state.time + 2, core
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'nearby heroes with split targets are not collective focus')
    other.target, other.visible = bot, false
    assert(not j.ShouldRetreatFromEnemyReinforcements(bot), 'do not read pressure through fog')
    other.visible, other.target, enemy.target = true, core, core
    local hp = j.GetHP
    j.GetHP = function(unit) return unit == core and 0.7 or hp(unit) end
    j.CanCastOnNonMagicImmune, j.CanCastOnTargetAdvanced = yes, yes
    assert(j.GetCoreFocusPeelTarget(bot, {core}, {enemy, other}, 650) == enemy, 'interrupt the larger immediate damage source')
    assert(j.GetCoreFocusPeelTarget(bot, {core}, {enemy, other}, 450) == nil, 'do not walk into danger to save the core')
end

do
    local state, _, bot, _, _, enemy, other, j = fixture(false)
    state.time, state.hp, bot.core = 18 * 60, 0.25, true
    enemy.core, enemy.x, other.x, other.alive, enemy.target, other.target = true, 100, 300, true, bot, bot
    bot.IsRooted, bot.GetAttackRange = yes, function() return 150 end
    bot.GetAttackPoint, bot.GetAnimCycle = function() return 0.3 end, function() return 0.18 end
    bot.target, enemy.FindItemSlot = enemy, function() return -1 end
    enemy.GetEstimatedDamageToTarget, other.GetEstimatedDamageToTarget = function() return 260 end, function() return 215 end
    j.IsDisabled, j.IsAttacking, j.CanKillTarget = function(hero) return hero:IsRooted() end, yes, yes
    j.GetVisibleFightInventoryValue = function(unit) return unit == bot and 4000 or 8000 end
    assert(j.ShouldPreserveCoreFightTrade(bot, {enemy, other}), 'only a lethal already-started strike on a more valuable visible core')
    bot.IsRooted = no
    assert(not j.ShouldPreserveCoreFightTrade(bot, {enemy, other}), 'if the core can move, preserve it instead of trading')
    bot.IsRooted, j.CanKillTarget = yes, no
    assert(not j.ShouldPreserveCoreFightTrade(bot, {enemy, other}), 'do not gamble when it needs another hit')
    j.CanKillTarget, bot.IsStunned = yes, yes
    assert(not j.ShouldPreserveCoreFightTrade(bot, {enemy, other}), 'hard control prevents the last swing')
    bot.IsStunned, enemy.FindItemSlot = no, function() return 4 end
    assert(not j.ShouldPreserveCoreFightTrade(bot, {enemy, other}), 'visible extra life prevents a worthwhile trade')
end
print('PASS: recognize direct core focus, peel in range, and preserve only an already committed valuable trade')

do
    local state, mode, bot, core, _, enemy, _, j = fixture(true)
    local onLane, laning = true, true
    local wave = setmetatable({x = 870}, {__index = enemy})
    wave.GetUnitName = function() return 'npc_dota_creep_badguys_flagbearer' end
    wave.IsHero = no
    local imp = setmetatable({x = 350}, {__index = wave})
    imp.GetUnitName = function() return 'npc_dota_warlock_minor_imp' end
    mode.LANE_TOP, mode.LANE_MID, mode.LANE_BOT = 1, 2, 3
    mode.GetAmountAlongLane = function() return {distance = onLane and 200 or 1900} end
    bot.GetAssignedLane = function() return mode.LANE_BOT end
    local creeps = {wave}
    bot.GetNearbyCreeps = function() return creeps end
    enemy.target, enemy.alive, core.retreating = nil, false, false
    wave.alive, imp.alive = true, true
    j.IsInLaningPhase = function() return laning end
    j.IsInTeamFight, j.IsRoshan, j.IsTormentor = no, no, no
    j.GetAttackProDelayTime, j.WillKillTarget = function() return 0.5 end, yes
    j.CanSupportTakeLaneLastHit = yes
    j.GetSupportedFightTarget = function() end
    assert(mode.GetDesire() == 0, 'team roam leaves a ranged support side-lane wave timing to lane mode')
    creeps = {wave, imp}
    assert(mode.GetDesire() > 0, 'a nearby summon remains selectable when a lane creep is first in the list')
    mode.Think()
    assert(state.orders[1] == imp)
    creeps, onLane = {wave}, false
    assert(mode.GetDesire() > 0, 'being assigned a side lane does not claim the entire map')
    onLane = true
    mode.Think()
    assert(#state.orders == 1, 'discard a stale roaming creep order after returning to the side lane')
    laning, j.IsThereCoreNearby = false, no
    assert(mode.GetDesire() > 0)
    mode.Think()
    assert(state.orders[2] == wave, 'after laning the same roaming last hit still executes')
end
print('PASS: side-lane creep orders use lane mode while roaming keeps non-wave targets')
