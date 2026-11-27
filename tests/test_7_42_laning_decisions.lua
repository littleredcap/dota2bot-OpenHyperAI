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

local function fixture(core, overridden, startMid)
    local state = {time = 180, creepHP = 30, orders = {}, hp = 0.9, mid = startMid}
    local heroName = 'npc_dota_hero_test'
    local creep = {x = 200, GetHealth = function() return state.creepHP end,
        GetTeam = function() return 3 end, GetUnitName = function() return 'npc_dota_creep_badguys_melee' end,
        GetLocation = function() return 200 end, GetHealthRegen = function() return 0 end, GetIncomingTrackingProjectiles = empty,
        GetActualIncomingDamage = function(_, damage) return damage end, IsCreep = yes}
    local partner = {x = 260, IsAlive = function() return not state.partnerDead end,
        DistanceFromFountain = function() return state.partnerAtBase and 0 or 6000 end,
        HasModifier = function(_, m) return m == 'modifier_teleporting' and state.partnerTP end,
        WasRecentlyDamagedByAnyHero = function() return state.partnerHit end,
        GetPlayerID = function() return 2 end,
        IsDisarmed = function() return state.partnerDisarmed end,
        GetAttackRange = function() return 150 end, GetAttackTarget = function() end,
        GetAttackDamage = function() return state.partnerDamage or 50 end, GetAttackCombatProficiency = function() return 1 end,
        GetItemSlotType = function() return 0 end, FindItemSlot = function() return -1 end,
        GetUnitName = function() return 'npc_dota_hero_partner' end, GetSecondsPerAttack = function() return 1.5 end}
    local bot = {x = 0}
    local enemy = {x = 260, IsCreep = no, GetAttackRange = function() return 500 end,
        GetLocation = function(self) return self.x end,
        GetAttackTarget = function()
            return state.pressure and not state.betweenAttacks and bot or state.enemyCreep
        end,
        GetAttackCombatProficiency = function() return 1 end,
        GetAttackDamage = function() return state.enemyDamage or 50 end,
        GetLastAttackTime = function() return state.enemyLastAttackTime or state.time - 1 end}
    enemy.IsInvulnerable, enemy.HasModifier = no, no
    enemy.GetHealth = function() return state.enemyHealth or 1000 end
    local tower = {x = 700, GetAttackTarget = function() return state.tower and bot or nil end}
    local openingTower = {x = 1600, IsAlive = yes, GetLocation = function(self) return self.x end}
    bot.GetPlayerID = function() return state.playerID or 1 end
    bot.GetUnitName = function() return heroName end
    bot.GetLevel = function() return 5 end
    bot.GetTeam = function() return 2 end
    bot.GetAssignedLane = function() return state.mid and 2 or 3 end
    bot.GetLocation = function() return bot.x end
    bot.GetAttackRange = function() return 450 end
    bot.GetAttackDamage = function() return 50 end
    bot.GetAttackCombatProficiency = function() return state.proficiency or 1 end
    bot.GetSecondsPerAttack = function() return 1.5 end
    bot.GetLastAttackTime = function() return state.previousShot or 0 end
    bot.GetAttackTarget = function() return state.attackTarget end
    bot.IsInvulnerable, bot.IsIllusion, bot.IsDisarmed = no, no, no
    bot.IsAlive, bot.IsHero, bot.IsUsingAbility, bot.IsChanneling = yes, yes, no, no
    bot.HasModifier = function(_, name) return name == 'modifier_tango_heal' end
    bot.WasRecentlyDamagedByAnyHero = function() return state.pressure or state.wasHit end
    bot.WasRecentlyDamagedByCreep = function() return state.creepAggro end
    bot.WasRecentlyDamagedByTower = no
    bot.GetNearbyHeroes = function(_, _, hostile)
        if not hostile then return state.partner and {partner} or {} end
        return state.enemies or (state.enemy and {enemy} or {})
    end
    bot.GetNearbyTowers = function() return (state.tower or state.towerIdle) and {tower} or {} end
    bot.GetNearbyLaneCreeps = function(_, _, hostile)
        if not hostile then return state.allies or (state.allyWave and {creep} or {}) end
        if state.creeps then return state.creeps end
        if state.noCreeps then return {} end
        return state.manyCreeps and {creep, creep, creep} or {creep}
    end
    bot.GetItemSlotType = function() return 0 end
    bot.FindItemSlot = function() return -1 end
    bot.SetTarget = function() end
    bot.Action_MoveToLocation = function(_, point) state.orders[#state.orders + 1] = {'move', point} end
    bot.Action_MoveToUnit = function(_, target) state.orders[#state.orders + 1] = {'approach', target} end
    bot.Action_AttackUnit = function(_, target) state.orders[#state.orders + 1] = {'attack', target} end
    bot.Action_ClearActions = function(_, stop) state.orders[#state.orders + 1] = {'hold', stop} end

    local utils = {BuggyHeroesDueToValveTooLazy = {[heroName] = overridden}, GameStates = {},
        NumHumanBotPlayersInTeam = function() return 0, 5 end, IsTeamPushingSecondTierOrHighGround = no,
        GetLastSeenEnemyIdsNearLocation = empty}
    local j = {
        Utils = utils, GetPosition = function() return core and (state.mid and 2 or 1) or 5 end,
        IsPosxHuman = no, IsInLaningPhase = yes, IsModeTurbo = no,
        GetEnemiesAroundAncient = function() return 0 end,
        IsValid = function(unit) return unit ~= nil end,
        IsValidHero = function(unit) return unit == enemy or unit == partner or unit == state.secondEnemy end,
        IsValidBuilding = function(unit) return unit ~= nil and (unit == tower or unit == openingTower or unit == state.fallbackTower) end,
        IsSuspiciousIllusion = no, IsChasingTarget = no, IsThereNonSelfCoreNearby = no,
        GetHP = function(unit) return unit == bot and state.hp or (unit == partner and state.partnerHP)
            or (unit.IsCreep and state.deniable and 0.4 or 0.75) end,
        CanNotUseAction = no, CanBeAttacked = yes, CannotBeKilled = function() return state.enemyProtected end,
        CanKillTarget = function(unit, damage) return unit:GetHealth() <= damage end,
        IsAttacking = function(unit) return unit == bot and state.attacking or unit == enemy and state.enemyWindup end,
        GetAttackProDelayTime = function(unit) return unit == enemy and state.enemyEta or 0.3,
            unit == enemy and state.enemyRelease or 0.18, unit == bot and state.attackWait or 0 end,
        GetTotalAttackWillRealDamage = function(unit, eta)
            if state.finishingDamageAt ~= nil and eta >= state.finishingDamageAt then return state.creepHP end
            if state.incomingDamageAt ~= nil then return eta >= state.incomingDamageAt and state.incomingDamage or 0 end
            return state.incomingDamage or 0
        end,
        WillKillTarget = function(unit, damage) return unit:GetHealth() <= damage + (state.incomingDamage or 0) end,
        IsCore = function(unit) return unit == partner and not state.partnerSupport or unit == bot and core end,
        GetAlliesNearLoc = function() return state.partner and {bot, partner} or {bot} end,
        IsDisabled = no, IsRetreating = function(unit) return unit == partner and state.partnerRetreat end,
        AdjustLocationWithOffsetTowardsFountain = function(point, offset) return point - offset end,
        GetLastSeenEnemiesNearLoc = function(location)
            return state.towerDive and (state.threatSpot == nil or state.threatSpot == location) and {6, 7} or {}
        end,
        GetEnemiesNearLoc = empty,
        GetLanePartner = function() return state.partner and partner or nil end,
        CanFollowLaneFight = function() return state.partner and not state.partnerRetreat end,
        IsInRange = function(a, b, range) return math.abs(a.x - b.x) <= range end,
        IsKeyWordUnit = function(word, unit) return unit:GetUnitName():find(word, 1, true) ~= nil end,
        GetLocationTowardDistanceLocation = function(unit, _, distance) return unit.x - distance end,
    }
    local modules = {['bots/FunLib/utils'] = utils, ['bots/FunLib/jmz_func'] = j,
        ['bots/FunLib/version'] = {}, ['bots/FunLib/localization'] = {Get = empty},
        ['bots/FunLib/lane_camp'] = {
            Plan = function() return state.campPlan end,
            Cancel = function(unit, reason) unit.ohaLaneCamp=nil; state.cancelCamp=reason end,
            Think = function(_, plan) state.orders[#state.orders + 1] = {'camp', plan}; return true end,
        },
        ['game/botsinit'] = {CreateGeneric = empty}}
    local env = setmetatable({
        J = j, GetScriptDirectory = function() return 'bots' end, GetBot = function() return bot end,
        require = function(name) return assert(modules[name], name) end,
        GetTeam = function() return 2 end, GetOpposingTeam = function() return 3 end,
        GetTeamPlayers = empty, GetGameMode = function() return 0 end,
        GetGameState = function() return 0 end, GAME_STATE_PRE_GAME = 1,
        GetTower = function(_, id) if id == 13 or id == 15 then return state.fallbackTower end; return openingTower end,
        TOWER_TOP_1 = 10, TOWER_MID_1 = 11, TOWER_BOT_1 = 12,
        TOWER_TOP_2 = 13, TOWER_BOT_2 = 15,
        GetLaneFrontLocation = function(_, _, offset) return offset end,
        GetLaneFrontAmount = function() return 0.5 end,
        GetUnitToUnitDistance = function(a, b) return math.abs(a.x - b.x) end,
        GetUnitToLocationDistance = function(unit, point) return math.abs(unit.x - point) end,
        GetHeightLevel = function(point) return state.uphill and point > bot.x and 2 or 1 end,
        IsLocationPassable = yes,
        PointToLineDistance = function() return {within = false, distance = 2000} end,
        RandomVector = function() return 0 end, RandomFloat = function() return 0.1 end,
        DotaTime = function() return state.time end, GameTime = function() return state.time end,
        TEAM_RADIANT = 2, LANE_TOP = 1, LANE_MID = 2, LANE_BOT = 3,
        ITEM_SLOT_TYPE_MAIN = 1, BOT_MODE_NONE = 0, GAMEMODE_1V1MID = 1, GAMEMODE_MO = 2,
        DAMAGE_TYPE_PHYSICAL = 1,
        BOT_ACTION_DESIRE_NONE = NONE, BOT_MODE_DESIRE_NONE = NONE, BOT_MODE_DESIRE_VERYLOW = 0.1,
    }, {__index = _G})
    env.dofile = function(path) return setfenv(assert(loadfile(path .. '.lua')), env)() end
    setfenv(laneSafety, env)()
    setfenv(assert(loadfile('bots/mode_laning_generic.lua')), env)()
    return state, env, creep, enemy, bot, tower
end

local function expect(state, mode, kind, target)
    state.orders = {}
    mode.Think()
    if kind == nil then assert(#state.orders == 0); return end
    assert(#state.orders == 1, 'there must be one lane order per tick')
    assert(state.orders[1][1] == kind and state.orders[1][2] == target, 'unexpected lane order')
    -- The next decision scenario starts after any pending order's windup.
    state.time = math.max(state.time, mode.GetBot().ohaLaningAttackUntil or state.time)
end

do
    local state, mode, _, _, bot = fixture(true, false, true)
    assert(mode.Think == nil and bot.ohaEngineMid, 'supported ranged mids let the engine issue creep attacks')
    assert(mode.GetDesire() == 0.74 and #state.orders == 0, 'evaluating a contested mid wave issues no orders')
    local _, override = fixture(true, true, true)
    assert(type(override.Think) == 'function', 'heroes without engine lane control keep their scripted attacks')
end

do
    local state, env, _, _, bot = fixture(false, false)
    local firstIdle = assert(source:find('function J.CheckBotIdleState()', 1, true))
    local lastIdle = assert(source:find('function J.AreTreesBetween', firstIdle, true))
    setfenv(assert(loadstring(source:sub(firstIdle, lastIdle - 1))), env)()
    env.BOT_ACTION_TYPE_MOVE_TO, env.BOT_ACTION_TYPE_IDLE, env.BOT_ACTION_TYPE_PICK_UP_RUNE = 1, 2, 3
    bot.GetCurrentActionType = function() return 1 end
    bot.GetActiveMode, bot.DistanceFromFountain = function() return 8 end, function() return 4000 end
    bot.IsRooted = no
    env.J.IsTryingtoUseAbility, env.J.IsDefending, env.J.IsDoingRoshan, env.J.IsDoingTormentor = no, no, no, no
    for t = 0, 11 do
        state.time, bot.x = 1260 + t, t % 2 == 0 and 0 or 105
        env.J.CheckBotIdleState()
    end
    assert(bot.ohaIdleRecoveryUntil > state.time and #state.orders == 0, 'wandering on passable ground recovers without issuing orders from desire')
    bot.ohaIdleRecoveryUntil = nil
    for t = 0, 12 do state.time, bot.x = 1300 + t, t * 100; env.J.CheckBotIdleState() end
    assert(not bot.ohaIdleRecoveryUntil, 'continued travel refreshes the distance sample')
    env.J.IsTryingtoUseAbility = yes
    for t = 0, 12 do state.time = 1320 + t; env.J.CheckBotIdleState() end
    assert(not bot.ohaIdleRecoveryUntil, 'channeling and casting do not trigger recovery')
end

do
    local state, mode, creep, enemy, bot = fixture(true, false)
    state.mid = true
    assert(mode.GetDesire() == 0.9)
    mode.Think()
    assert(#state.orders == 1 and state.orders[1][2] == creep)
    state.time = state.time + 0.1
    state.creepHP = 150
    assert(mode.GetDesire() == 0.9, 'retain the lane until the ordered shot has time to start')
    expect(state, mode, nil)
    state.enemy, state.hp = true, 0.26
    enemy.x = 710
    assert(mode.J.IsLaningUnderPressure(bot, {enemy}), 'do not reenter melee control range at critical health')
    mode.GetDesire()
    expect(state, mode, 'move', -1200)
end

do
    local state, mode = fixture(false, false)
    state.time = 60
    assert(mode.GetDesire() == 0.72, 'an off-lane support still needs to reach its assigned first tower')
    expect(state, mode, 'move', mode.GetTower():GetLocation())
end

do
    local state, mode, creep, _, bot = fixture(true, false)
    state.mid, state.enemy, state.pressure, state.hp = true, true, true, 0.61
    mode.GetTower().x = -450
    assert(mode.J.GetLaningHoldTower(bot) == mode.GetTower(), 'a ranged mid can stay under a safe tower after a trade')
    assert(mode.GetDesire() == 0.82)
    expect(state, mode, 'attack', creep)
    state.towerDive = true
    assert(not mode.J.GetLaningHoldTower(bot), 'lose the assignment when enemies can dive the hold position')
end

do
    local state, mode, creep, enemy = fixture(true, false)
    state.enemy, state.enemyCreep, state.enemyWindup, state.enemyEta, state.enemyRelease = true, creep, true, 0.16, 0
    state.creepHP, state.enemyDamage, state.incomingDamage = 70, 40, 30
    mode.GetDesire()
    expect(state, mode, 'attack', creep)
end

do
    local state, env, creep, enemy, bot = fixture(true, false)
    state.partner, state.partnerHP, state.hp, state.enemy, state.pressure = true, 0.92, 0.54, true, true
    bot.GetAttackRange = function() return 150 end
    bot.x, enemy.x, env.GetTower().x = 100, 350, -450
    assert(env.GetDesire() == 0.82, 'can hold a safe tower wave after a bad trade even with a healthy partner online')
    expect(state, env, 'attack', creep)
    local j = env.J
    local validHero = j.IsValidHero
    j.IsValidHero = function(unit) return unit == bot or validHero(unit) end
    j.CanCastOnNonMagicImmune, j.CanCastOnTargetAdvanced = yes, yes
    enemy.IsDisarmed, enemy.GetSecondsPerAttack = no, function() return 1.4 end
    assert(j.GetLaningPeelTarget(bot, bot, {enemy}, 300) == enemy, 'peel a current attacker without moving into cast range')
    assert(j.GetLaningPeelTarget(bot, bot, {enemy}, 225) == nil, 'do not chase the attacker for a peel')
    j.IsDisabled = yes
    assert(j.GetLaningPeelTarget(bot, bot, {enemy}, 300) == nil, 'preserve the existing disable')
    state.towerDive = true
    assert(j.GetLaningHoldTower(bot) == nil, 'cede the tower anchor if the enemy can reach it')
end

do
    local state, mode, creep, _, bot = fixture(true, false)
    state.partner, state.partnerHP, state.hp, state.enemy, state.pressure = true, 0.92, 0.54, true, true
    bot.x, mode.GetTower().x = 100, -450
    state.creepHP, state.incomingDamage, state.incomingDamageAt = 70, 30, 0.45
    assert(mode.GetDesire() == 0.82)
    local hit, _, reserve = mode.J.GetLaningLastHitTarget(bot, {creep}, nil, mode.J.GetLaningAttackDamage(bot), {}, true)
    assert(not hit and reserve, 'the covered creep will enter last-hit range after the next projectile')
    expect(state, mode, nil)
    state.incomingDamageAt = 0.2
    expect(state, mode, 'attack', creep)
end

do
    local state, mode, creep = fixture(true, false)
    local deny = setmetatable({x = 170, GetHealth = function() return 25 end, GetTeam = function() return 2 end}, {__index = creep})
    state.mid, state.allies, state.deniable, state.attackTarget = true, {deny}, true, creep
    state.creepHP, state.incomingDamage, state.incomingDamageAt = 70, 28, 0.45
    mode.GetDesire()
    expect(state, mode, 'hold', true)
end

do
    local state, mode, creep = fixture(false, false)
    local deny = setmetatable({x = 170, GetHealth = function() return 25 end, GetTeam = function() return 2 end}, {__index = creep})
    state.partner, state.noCreeps, state.allies, state.deniable = true, true, {deny}, true
    assert(mode.GetDesire() == 0.7, 'a side-lane support stays for an available deny')
    expect(state, mode, 'attack', deny)
end

do
    local state, mode, _, _, bot = fixture(false, false)
    mode.GetTower().x = 300
    state.partner, state.partnerDead, state.towerDive, state.threatSpot = true, true, true, 0
    state.fallbackTower = {x = -1300, GetLocation = function(self) return self.x end}
    assert(mode.J.GetSideLaneHoldTower(bot) == state.fallbackTower, 'fall back to T2 while the lane partner respawns')
end

do
    local state, mode, creep, _, support = fixture(false, false)
    state.partner, state.creepHP, state.partnerDamage = true, 60, 25
    state.finishingDamageAt = 0.55
    assert(mode.J.CanSupportTakeLaneLastHit(support, creep), 'secure the creep if core damage cannot beat the deny')
    state.partnerDamage = 70
    assert(not mode.J.CanSupportTakeLaneLastHit(support, creep), 'leave the kill to a core that can finish it')
    creep.GetUnitName = function() return 'npc_dota_badguys_siege_upgraded' end
    assert(not mode.J.CanSupportTakeLaneLastHit(support, creep), 'apply the same rule to upgraded siege creeps')
end

do
    local state, mode = fixture(false, true)
    state.partner, state.campPlan = true, {}
    assert(mode.GetDesire() == 0.63)
    expect(state, mode, 'camp', state.campPlan)
end

for _, overridden in ipairs({false, true}) do
    local state, mode, creep, enemy, bot = fixture(false, overridden)
    local tower = mode.GetTower()
    tower.x = 300
    state.partner, state.partnerHP, state.partnerHit = true, 0.36, true
    state.hp, state.partnerRetreat = 0.68, true
    assert(mode.GetDesire() == 0.82, 'the healthier side laner takes over the protected wave')
    expect(state, mode, 'attack', creep)
    state.partnerTP, state.partnerRetreat = true, false
    expect(state, mode, 'attack', creep)
    bot.GetAttackRange = function() return 150 end
    expect(state, mode, 'approach', creep)
    state.partnerTP = false
    state.partnerHP, state.partnerAtBase, state.partnerRetreat = 1, true, false
    assert(mode.J.GetSideLaneHoldTower(bot) == tower, 'continue coverage while the partner heals at fountain')
    state.partnerAtBase, state.partnerHP, state.partnerHit = false, 1, false
    assert(not mode.J.GetSideLaneHoldTower(bot), 'hand the wave back when the partner returns')
    state.partnerHP, state.partnerHit, state.hp = 0.68, true, 0.49
    assert(not mode.J.GetSideLaneHoldTower(bot), 'the more injured partner remains free to reset')
    state.hp, state.partnerDead, state.towerDive = 0.7, true, true
    assert(not mode.J.GetSideLaneHoldTower(bot), 'an enemy dive cancels the assignment even with a dead partner')
    state.towerDive, state.hp = false, 0.22
    assert(not mode.J.GetSideLaneHoldTower(bot), 'both laners can leave when neither can safely hold')
end

do
    local state, mode, _, enemy, bot = fixture(true, false)
    local j = mode.J
    j.IsDoingRoshan, j.IsDoingTormentor, j.IsInTeamFight = no, no, no
    bot.DistanceFromFountain, bot.GetActiveMode = function() return 5900 end, function() return 0 end
    local tower = mode.GetTower()
    tower.x = 300
    state.partner, state.partnerSupport, state.partnerHP, state.hp = true, true, 0.8, 0.42
    state.enemy, enemy.x = true, 1450
    assert(j.GetSafeLaneSupplyTower(bot) == tower, 'wait for real supply behind a covered T1 even when the lane is contested')
    state.partnerRetreat = true
    assert(not j.GetSafeLaneSupplyTower(bot), 'without the support a low core may reset')
    state.partnerRetreat = false
    bot.x = 550
    assert(not j.GetSafeLaneSupplyTower(bot), 'standing in front of the tower is not shelter')
    bot.x, enemy.x, state.pressure = 0, 400, true
    assert(not j.GetSafeLaneSupplyTower(bot), 'actual pursuit cannot be masked by the nearby support')
end
print('PASS: low carry can receive real lane supply from a sheltered tower, never through a dive')

do
    local carryState, carryMode, _, _, carry = fixture(true, false)
    local supportState, supportMode, _, _, support = fixture(false, false)
    local function afterTrade(state, hp, otherHP)
        state.partner, state.wasHit, state.partnerHit = true, true, true
        state.hp, state.partnerHP = hp, otherHP
    end
    carryMode.GetTower().x, supportMode.GetTower().x = 300, 300
    carryState.partnerSupport, supportState.playerID = true, 3
    afterTrade(carryState, 0.63, 0.65)
    afterTrade(supportState, 0.65, 0.63)
    assert(carryMode.J.GetSideLaneHoldTower(carry) and not supportMode.J.GetSideLaneHoldTower(support),
        'both laners independently leave the wave with the core at comparable health')
    afterTrade(carryState, 0.38, 0.69)
    afterTrade(supportState, 0.69, 0.38)
    assert(not carryMode.J.GetSideLaneHoldTower(carry) and supportMode.J.GetSideLaneHoldTower(support),
        'the support takes over when the core is in worse shape')
end

do
    local state, mode, creep = fixture(true, true)
    assert(mode.GetDesire() == 0.9, 'override lane assignment and last-hit desire must load')
    expect(state, mode, 'attack', creep)
    state.enemy, state.pressure = true, true
    expect(state, mode, 'attack', creep)
    state.hp = 0.6
    expect(state, mode, 'move', -1200)
    state.betweenAttacks, state.hp = true, 0.4
    expect(state, mode, 'move', -1200)
    state.enemy, state.pressure, state.hp = false, false, 0.9
    expect(state, mode, 'attack', creep)
end

do
    local state, mode, _, enemy = fixture(false, true)
    state.partner, state.enemy = true, true
    mode.GetDesire()
    expect(state, mode, 'attack', enemy)
    state.manyCreeps = true
    expect(state, mode, 'attack', enemy)
    state.time = state.time + 0.2
    state.creepAggro = true
    expect(state, mode, 'move', -500)
    state.creepAggro = false
    expect(state, mode, 'attack', enemy)
end

do
    local state, mode, creep = fixture(true, false)
    assert(mode.GetDesire() == 0.9, 'a carry with a bot support still prioritizes a reachable last hit')
    mode.GetDesire()
    state.creepHP = 65
    expect(state, mode, 'move', -450)
    state.creepHP = 30
    expect(state, mode, 'attack', creep)
    state.tower = true
    expect(state, mode, 'move', -1200)
end

do
    local state, mode, creep, enemy = fixture(false, false)
    state.partner, state.enemy = true, true
    mode.GetDesire()
    expect(state, mode, 'attack', enemy)
    state.partnerDisarmed = true
    expect(state, mode, 'attack', creep)
    state.partnerDisarmed, state.incomingDamage = false, state.creepHP
    expect(state, mode, 'attack', enemy)
    state.incomingDamage = 0
    expect(state, mode, 'attack', enemy)
    state.manyCreeps = true
    expect(state, mode, 'attack', enemy)
    state.creepAggro = true
    expect(state, mode, 'move', -500)
    state.creepAggro = false
    state.towerIdle = true
    expect(state, mode, 'move', -500)
end
print('PASS: lane last hits resume after pressure, support yields farm, and unsafe harass does not replace positioning')

for _, overridden in ipairs({false, true}) do
    local state, mode, creep, enemy, bot, tower = fixture(true, overridden)
    bot.GetAssignedLane = function() return 2 end
    state.enemy, state.mid = true, true
    mode.GetDesire()
    expect(state, mode, 'attack', creep)
    state.creepHP = 100
    expect(state, mode, 'attack', enemy)
    tower.x, state.towerIdle = 825, true
    expect(state, mode, nil)
end
print('PASS: ranged mid takes the last hit first and harasses only within a safe opening')

for _, overridden in ipairs({false, true}) do
    local state, mode, creep, enemy, bot, tower = fixture(true, overridden)
    local ranged = setmetatable({x = 380, GetUnitName = function() return 'npc_dota_creep_badguys_ranged' end}, {__index = creep})
    local distant = setmetatable({x = 630}, {__index = creep})
    state.creeps = {distant, creep, ranged}
    mode.GetDesire()
    expect(state, mode, 'attack', ranged)
    state.attacking, state.attackTarget = true, creep
    expect(state, mode, nil)
    state.tower = true
    expect(state, mode, 'move', -1200)
    state.tower, state.attacking, state.incomingDamage = false, false, 40
    expect(state, mode, 'move', -450)
    state.incomingDamage, state.creeps = 0, {distant}
    expect(state, mode, 'move', distant.x - (bot:GetAttackRange() - 105))
    tower.x, state.towerIdle = 825, true
    expect(state, mode, 'move', -450)
    state.towerIdle, state.creeps = false, {creep}
    state.enemy, state.pressure, state.secondEnemy = true, true, {x = 270, GetAttackRange = enemy.GetAttackRange,
        GetAttackTarget = function() return bot end}
    state.enemies = {enemy, state.secondEnemy}
    expect(state, mode, 'move', -1200)
end
do
    local state, mode, creep = fixture(true, false)
    local j = mode.J
    j.GetLaningLastHitTarget = function() return creep, true, false, false end
    local point = -250
    j.GetLaningCreepPosition = function() return point end
    local deny = {x = 110}
    j.GetLaningDenyTarget = function() return deny, false end
    mode.GetDesire()
    expect(state, mode, 'move', point)
    point = nil
    mode.GetDesire()
    expect(state, mode, 'attack', deny)
end
do
    local state, mode, creep, enemy, bot, tower = fixture(false, false)
    state.partner, state.partnerHP, state.enemy = true, 0.9, true
    state.creepHP, state.allies = 250, {creep, creep}
    enemy.GetAttackRange = function() return 150 end
    local j, hp = mode.J, mode.J.GetHP
    j.GetHP = function(unit) if unit == enemy then return 0.45 end; return hp(unit) end
    assert(mode.GetDesire() == 0.71, 'stay in lane for pressure with friendly creeps and local core')
    expect(state, mode, 'attack', enemy)
    state.partnerRetreat = true
    assert(not j.GetSideLanePressureTarget(bot, {enemy}, nil, 450), 'do not pressure alone')
    state.partnerRetreat = false
    tower.x = enemy.x + 560
    assert(not j.GetSideLanePressureTarget(bot, {enemy}, tower, 450), 'do not pressure within enemy tower range')
    enemy.x = 640
    assert(not j.GetSideLanePressureTarget(bot, {enemy}, nil, 450), 'do not submit a long attack order')
    local allyCreep = {x = 420}
    state.allies = {allyCreep, allyCreep}
    j.VectorTowards = function(origin, _, step) return origin + step end
    enemy.x = 550
    local step = j.GetSideLanePressureStep(bot, {enemy}, nil)
    assert(step == 125, 'step into range while the opponent contests a covered wave')
    state.partnerRetreat = true
    assert(not j.GetSideLanePressureStep(bot, {enemy}, nil), 'do not advance when the core leaves')
    state.partnerRetreat = false
    enemy.x = 760
    assert(not j.GetSideLanePressureStep(bot, {enemy}, nil), 'do not chase after the opponent leaves the wave')
    enemy.x = 260
    state.allies = {creep}
    assert(not j.GetSideLanePressureTarget(bot, {enemy}, nil, 450), 'no pressure without a friendly wave')

    local friendly = setmetatable({GetTeam=function() return 2 end}, {__index=creep})
    state.allies, state.enemyCreep = {friendly, friendly}, friendly
    j.GetHP = function(unit) if unit == enemy then return 0.97 end; return hp(unit) end
    assert(not j.GetSideLanePressureTarget(bot, {enemy}, nil, 450), 'do not hit the full-health target just for standing nearby')
    enemy.IsFacingLocation = yes
    local canFollow = j.CanFollowLaneFight
    j.CanFollowLaneFight = no
    assert(j.GetSideLanePressureTarget(bot, {enemy}, nil, 450) == enemy,
        'use a covered angle before enemy attack windup without interrupting the allied core')
    local second = setmetatable({x = 425, GetAttackRange = function() return 500 end}, {__index = enemy})
    local valid = j.IsValidHero
    j.IsValidHero = function(unit) return unit == second or valid(unit) end
    assert(not j.GetSideLanePressureTarget(bot, {enemy, second}, nil, 450),
        'do not pre-pressure into the second enemy')
    j.IsValidHero = valid
    enemy.IsFacingLocation = nil
    j.CanFollowLaneFight = canFollow
    state.enemyWindup = true
    assert(j.GetSideLanePressureTarget(bot, {enemy}, nil, 450) == enemy, 'contest the exposed enemy before a low-HP threshold')
    expect(state, mode, 'attack', enemy)
    local lastHit = j.GetLaningLastHitTarget
    j.GetLaningLastHitTarget = function() return creep end
    expect(state, mode, 'attack', creep)
    j.GetLaningLastHitTarget = lastHit
    state.allyWave, state.allies = false, {friendly}
    assert(not j.GetSideLanePressureTarget(bot, {enemy}, nil, 450), 'no healthy-target trade without a covered wave')
end

do
    local state, mode, _, enemy, bot = fixture(false, false)
    local j = mode.J
    state.partner, state.partnerHP, state.enemy, state.creepHP = true, 0.54, true, 250
    local partner = j.GetLanePartner(bot)
    enemy.GetSecondsPerAttack, enemy.IsDisarmed = function() return 1.5 end, no
    j.CanCastOnNonMagicImmune, j.CanCastOnTargetAdvanced = yes, yes
    enemy.GetAttackTarget = function() return partner end
    assert(not j.GetSideLaneCoverAttack(bot, {enemy}), 'a target pointer alone is not an imminent hit')
    state.enemyWindup = true
    assert(j.GetLaningPeelTarget(bot, partner, {enemy}, 450, true) == enemy, 'stop a verified windup before the weak core takes damage')
    assert(mode.GetDesire() == 0.75)
    expect(state, mode, 'attack', enemy)
    state.enemyWindup, state.partnerHit = false, false
    assert(not j.GetSideLaneCoverAttack(bot, {enemy}), 'release the peel after the threat ends')
    state.enemyWindup, state.secondEnemy = true, {x=270, GetAttackRange=enemy.GetAttackRange, GetAttackTarget=function() return bot end}
    state.enemies = {enemy, state.secondEnemy, state.secondEnemy}
    assert(not j.GetSideLaneCoverAttack(bot, state.enemies), 'do not take an unsafe support trade against a rotation')
end
print('PASS: both lane modes prefer reachable ranged creeps, preserve attack windups and respect tower pressure')

for _, overridden in ipairs({false, true}) do
    local state, mode, creep, enemy, bot = fixture(true, overridden)
    state.enemy, state.attacking, state.attackTarget = true, true, enemy
    mode.GetDesire()
    expect(state, mode, 'attack', creep)
    state.attacking, state.attackTarget, state.attackWait = false, creep, 0.36
    mode.GetDesire()
    expect(state, mode, 'hold', true)
    state.attackWait, state.attackTarget = nil, nil
    mode.Think()
    state.time = state.time + 0.15
    assert(not mode.J.HasPendingLaningLastHit(bot), 'a superseded order may immediately be reconsidered')

    state.enemy, state.allyWave, state.creepHP = false, true, 100
    bot.GetAttackRange = function() return 150 end
    creep.x = 310
    mode.GetDesire()
    expect(state, mode, 'move', 195)
end

do
    local state, mode, creep, _, bot = fixture(true, false)
    local ready = true
    bot.GetUnitName = function() return 'npc_dota_hero_skeleton_king' end
    bot.GetAbilityByName = function(_, name)
        assert(name == 'skeleton_king_mortal_strike')
        return {IsTrained = yes, IsActivated = yes, IsCooldownReady = function() return ready end,
            GetSpecialValueInt = function(_, key) assert(key == 'crit_mult'); return 160 end}
    end
    state.creepHP = 75
    assert(mode.GetDesire() == 0.9, 'a ready Mortal Strike makes this creep a last hit')
    expect(state, mode, 'attack', creep)
    ready = false
    assert(mode.GetDesire() ~= 0.9, 'do not predict bonus damage while Mortal Strike is on cooldown')
    expect(state, mode, 'move', -450)
end

for _, overridden in ipairs({false, true}) do
    local state, mode, _, _, bot = fixture(true, overridden)
    state.time, state.noCreeps = -5, true
    assert(mode.GetDesire() == 0.72, 'distant cores leave the rune area in time for the first wave')
    expect(state, mode, 'move', 1600)
    bot.x, state.time = 1500, 25
    assert(mode.GetDesire() ~= 0.72, 'reaching the lane ends the rally order')
    bot.x, state.time, state.allyWave, state.enemy = 0, 180, true, true
    mode.GetDesire()
    expect(state, mode, 'move', -450)
end
print('PASS: first-wave commitment reaches the assigned lane and cores position behind their wave')

for _, overridden in ipairs({false, true}) do
    local state, mode, creep, enemy, bot = fixture(true, overridden)
    state.mid, state.enemy = true, true
    bot.GetAssignedLane = function() return 2 end
    mode.GetDesire()
    state.creepHP, state.incomingDamage, state.incomingDamageAt = 70, 28, 0.45
    assert(mode.GetDesire() == 0.7, 'keep lane control when a shot will become available soon')
    expect(state, mode, nil)
    state.finishingDamageAt = 0.82
    expect(state, mode, nil)
    state.finishingDamageAt, state.incomingDamageAt = nil, 0.95
    expect(state, mode, 'attack', enemy)
    state.incomingDamageAt = nil
    state.incomingDamage = 0
    expect(state, mode, 'attack', enemy)
    state.finishingDamageAt, state.incomingDamage = nil, 28
    state.incomingDamageAt = 0.2
    expect(state, mode, 'attack', creep)
    state.creepHP, state.incomingDamageAt = 30, nil
    state.incomingDamage = 0
    state.enemyCreep, state.enemyWindup, state.enemyEta = creep, true, 0.16
    expect(state, mode, 'attack', enemy)
    state.enemyCreep, state.enemyWindup, state.proficiency, state.creepHP = nil, false, 0.5, 25
    expect(state, mode, 'attack', creep)
    state.proficiency, state.creepHP, state.manyCreeps = 1, 100, true
    expect(state, mode, nil)
    state.creepHP, state.allies, state.enemyCreep, state.enemyWindup, state.enemyEta = 135, {creep, creep, creep}, creep, true, 0.25
    expect(state, mode, 'attack', enemy)
    state.uphill = true
    expect(state, mode, nil)
    state.allyWave, state.allies, state.enemy, state.uphill = false, nil, false, false
    local far = setmetatable({x = 700}, {__index = creep})
    state.creeps = {far}
    expect(state, mode, 'move', 355)
    state.creepHP = 30
    expect(state, mode, 'move', 355)
end
print('PASS: reserve a shot for the next last-hit window, respect incoming denies, and trade with lane cover')

for _, overridden in ipairs({false, true}) do
    local state, mode, creep, enemy, bot = fixture(true, overridden)
    state.mid = true
    bot.GetAssignedLane = function() return mode.LANE_MID end
    bot.GetAttackCombatProficiency, enemy.GetAttackCombatProficiency = nil, nil
    assert(mode.GetDesire() == 0.9, 'the client without attack-type proficiency can still select a last hit')
    expect(state, mode, 'attack', creep)
    state.creepHP, state.attacking, state.attackTarget = 120, true, creep
    expect(state, mode, nil)
    state.previousShot = 1
    expect(state, mode, 'hold', true)
    state.creepHP = 30
    expect(state, mode, nil)
    state.enemy = true
    state.enemyCreep, state.enemyWindup, state.enemyEta, state.attacking = creep, true, 0.16, false
    expect(state, mode, 'attack', enemy)
end
print('PASS: missing combat proficiency falls back to physical damage and a finished order does not renew an auto-attack')

do
    local timingStart = assert(source:find('local function GetAttackSpeedMultiplier(', 1, true))
    local timingEnd = assert(source:find('function J.GetCreepAttackActivityWillRealDamage(', timingStart, true))
    local j = {IsAttacking = function(bot) return bot.windup end}
    local env = setmetatable({J = j, GameTime = function() return 100 end,
        GetUnitToUnitDistance = function(a, b) return math.abs(a.x - b.x) end}, {__index = _G})
    setfenv(assert(loadstring(source:sub(timingStart, timingEnd - 1))), env)()
    local target = {x=670}
    local sniper = {x=0, GetAttackSpeed = function() return 120 end, GetAttackPoint = function() return 0.24 end,
        GetAttackRange = function() return 550 end, GetCurrentMovementSpeed = function() return 300 end,
        GetLastAttackTime = function() return 99 end, GetSecondsPerAttack = function() return 1.35 end,
        GetAttackTarget = function() return target end, GetAnimCycle = function() return 0.12 end,
        GetAttackProjectileSpeed = function() return 3000 end}
    local impact, release = j.GetAttackProDelayTime(sniper, target)
    assert(math.abs(release - 0.6) < 0.0001 and math.abs(impact - (0.6 + 515 / 3000)) < 0.0001)
    target.x, sniper.windup = 400, true
    impact, release = j.GetAttackProDelayTime(sniper, target)
    assert(math.abs(release - 0.1) < 0.0001 and impact > release, 'finish the current shot without adding a second windup')
end

do
    local state, env, _, _, bot = fixture(true, false)
    state.mid, state.enemy, state.time = true, true, 120
    bot.GetAssignedLane = function() return env.LANE_MID end
    bot.GetActiveMode, bot.GetActiveModeDesire = function() return 0 end, function() return 0 end
    env.BOT_ACTION_TYPE_IDLE, env.BOT_ACTION_TYPE_PICK_UP_RUNE = 1, 2
    bot.GetCurrentActionType = function() return env.BOT_ACTION_TYPE_IDLE end
    bot.GetNearbyCreeps = empty
    bot.Action_PickUpRune = function(_, rune) state.picked = rune end
    env.J.GetEnemiesNearLoc, env.J.Utils.CountEnemyHeroesNear = empty, function() return 0 end
    env.J.GetMP = function() return 0.9 end
    env.GetAncient = function() return {GetLocation = function() return -3000 end} end
    env.Vector, env.TEAM_DIRE = function(x) return x end, 3
    env.RUNE_POWERUP_1, env.RUNE_POWERUP_2, env.RUNE_BOUNTY_1, env.RUNE_BOUNTY_2 = 1, 2, 3, 4
    env.RUNE_STATUS_AVAILABLE, env.RUNE_STATUS_UNKNOWN, env.RUNE_STATUS_MISSING, env.RUNE_WATER = 1, 2, 3, 4
    env.BOT_MODE_DESIRE_HIGH, env.BOT_MODE_DESIRE_MODERATE = 0.75, 0.5
    local runeId, runeDistance, runeStatus = env.RUNE_POWERUP_1, 60, env.RUNE_STATUS_AVAILABLE
    env.GetRuneType = function() return env.RUNE_WATER end
    env.GetRuneStatus = function() return runeStatus end
    env.GetRuneSpawnLocation = function() return runeDistance end
    local requireFixture = env.require
    env.require = function(name) return name == 'bots/Customize/general' and {} or requireFixture(name) end
    local runeFile = assert(io.open('bots/mode_rune_generic.lua', 'rb'))
    local runeSource = runeFile:read('*a')
    runeFile:close()
    local runeMode = setfenv(assert(loadstring(runeSource .. '\nreturn X')), env)()
    runeMode.UpdateWisdom = function() end
    local getBestRune = runeMode.GetBestRune
    runeMode.GetBestRune = function() return runeId, runeDistance end
    runeMode.GetScaledDesire = function(desire) return desire end
    for _, id in ipairs({env.RUNE_POWERUP_1, env.RUNE_POWERUP_2}) do
        runeId = id
        assert(env.GetDesire() > 0, 'an idle mid laner in a 1v1 can take either nearby water rune')
        env.Think()
        assert(state.picked == id)
    end
    runeDistance = 480
    assert(env.GetDesire() == 0, 'keep a reachable last hit instead of leaving for water')
    runeStatus = env.RUNE_STATUS_UNKNOWN
    assert(env.GetDesire() == 0, 'do not leave a last hit to check a rune with unknown status')
    runeId = -1
    assert(env.GetDesire() == 0)
    env.Think()

    state.time, runeDistance, runeStatus = 366, 480, env.RUNE_STATUS_AVAILABLE
    env.GetTeamMember = function() return bot end
    env.GetRuneType = function() return 5 end
    env.GetRuneStatus = function(id)
        return id == env.RUNE_POWERUP_1 and runeStatus or env.RUNE_STATUS_MISSING
    end
    env.GetRuneSpawnLocation = function(id) return id == env.RUNE_POWERUP_1 and runeDistance or 3000 end
    runeMode.GetBestRune = getBestRune
    runeMode.GetBountyAssignment = function() return env.RUNE_BOUNTY_1, 300 end
    local distractions = {GetActualIncomingDamage = function(_, damage) return damage end, GetHealth = function() return 30 end}
    bot.GetNearbyCreeps = function() return {distractions} end
    assert(env.GetDesire() == 0.88, 'an available nearby power rune takes precedence over a closer bounty')
    env.Think()
    local order = state.orders[#state.orders]
    assert(order[1] == 'move' and order[2] == runeDistance, 'move to the rune without detouring to hit a creep')
    runeStatus = env.RUNE_STATUS_MISSING
    env.Think()
    assert(state.orders[#state.orders][1] == 'hold', 'cancel the move when the rune is taken before arrival')
    runeDistance, runeStatus = 50, env.RUNE_STATUS_AVAILABLE
    assert(env.GetDesire() == 0.88)
    env.Think()
    assert(state.picked == env.RUNE_POWERUP_1, 'claim the rune as soon as it is in reach')
end
print('PASS: stay for a reachable last hit, collect water and power runes, and cancel a lost rune move')

do
    local state, env, creep, _, bot = fixture(false, false)
    local j = env.J
    local file = assert(io.open('bots/ability_item_usage_generic.lua', 'rb'))
    local source = file:read('*a')
    file:close()
    local tpStart = assert(source:find('X.ConsiderItemDesire["item_tpscroll"] = function', 1, true))
    local tpEnd = assert(source:find('X.ConsiderItemDesire["item_urn_of_shadows"]', tpStart, true))
    local laneStart = assert(source:find('function X.GetLaningTPLocation(', 1, true))
    local laneEnd = assert(source:find('function X.GetPushTPLocation(', laneStart, true))
    env.X = {ConsiderItemDesire={}, GetNumHeroWithinRange=function() return 0 end,
        IsInvFull=function() return state.buy end, GetNumStashItem=function() return 1 end,
        IsThereRecipeInStash=yes, IsFarmingAlways=no, CanJuke=yes}
    env.bot, env.botName, env.team = bot, bot:GetUnitName(), 2
    env.BOT_MODE_RETREAT, env.BOT_MODE_LANING = 7, 8
    env.BOT_MODE_DESIRE_MODERATE, env.BOT_ACTION_DESIRE_HIGH, env.BOT_ACTION_DESIRE_NONE = 0.5, 0.75, 0
    j.GetShrapnelEscapeLocation, j.IsItemAvailable = function() end, function() end
    j.IsDefending, j.IsPushing, j.IsGoingOnSomeone, j.IsInTeamFight, j.IsDoingRoshan, j.IsStuck = no, no, no, no, no, no
    j.GetAllyCount, j.GetAttackProjectileDamageByRange = function() return 1 end, function() return 0 end
    j.GetTeamFountain, j.GetMP = function() return -7000 end, function() return 0.5 end
    j.ShouldKeepLaningWave = function() return state.sourceWave end
    j.GetNearbyHeroes, j.Role, j.GetModifierTime = empty, {ShouldTpToDefend=no}, function() return 4 end
    bot.GetHealth = function() return state.hp * 1000 end
    bot.IsRooted = no
    bot.HasModifier = function(_, m) return state.rupture and m == 'modifier_bloodseeker_rupture' end
    bot.GetActiveMode, bot.GetActiveModeDesire = function() return state.mode or 7 end, function() return 0.8 end
    bot.DistanceFromFountain = function() return state.atBase and 0 or 6500 end
    bot.GetActualIncomingDamage = function(_, damage) return damage end
    env.GetLaneFrontAmount = function() return 0.5 end
    env.GetAmountAlongLane = function(lane) state.destinationLane = lane; return {amount=0, distance=6000} end
    j.CanCommitToLaneTeleport = function(_, at, requireClear)
        return not state.unsafe and (not requireClear or #j.GetLastSeenEnemiesNearLoc(at, 1100) == 0)
    end
    local utilFile = assert(io.open('bots/FunLib/jmz_func.lua', 'rb'))
    local util = utilFile:read('*a')
    utilFile:close()
    local a = assert(util:find('function J.GetTeleportHomeLane(', 1, true))
    local b = assert(util:find('function J.TraceLaneTeleport(', a, true))
    env.LaneTeleportPolicy = dofile('bots/FunLib/lane_teleport_policy.lua')
    env.GetUnitToLocationDistance = function(_, at) return state.atBase and 6000 or math.abs(bot.x-at) end
    setfenv(assert(loadstring(util:sub(a, b-1))), env)()
    setfenv(assert(loadstring(source:sub(laneStart, laneEnd-1) .. source:sub(tpStart, tpEnd-1))), env)()
    local teleport = env.X.ConsiderItemDesire.item_tpscroll
    env.GetTower().x = 300
    state.partner, state.partnerHP, state.partnerHit, state.hp, state.buy = true, 0.28, true, 0.66, true
    assert(teleport() == 0, 'the healthy cover does not recall for an item while its partner resets')
    state.buy, state.rupture = false, true
    local desire, destination = teleport()
    assert(desire > 0 and destination == j.GetTeamFountain(), 'immediate escape from Rupture retains priority')
    state.rupture, state.partner, state.hp, state.pressure = false, false, 0.17, true
    desire, destination = teleport()
    assert(desire > 0 and destination == j.GetTeamFountain(), 'a critically wounded laner can recall')
    state.atBase, state.mode, state.hp, state.pressure = true, 8, 1, false
    bot.GetAssignedLane = function() return env.LANE_TOP end
    desire, destination = teleport()
    assert(desire > 0 and destination == 50,
        'return to the actual side lane behind the T1 even when the default role lane differs')
    bot.ohaCarryLaneRecoveryUntil = state.time + 20
    j.GetLastSeenEnemiesNearLoc = function() return {6, 7} end
    assert(teleport() == 0, 'the same contested lane is unsafe immediately after a forced reset')
    state.partner, state.partnerHP = true, 0.9
    local front = env.GetLaneFrontLocation()
    j.GetLastSeenEnemiesNearLoc = function(at) return at == front and {6, 7} or {} end
    assert(teleport() > 0, 'a clear protected landing with a healthy support is usable despite a contested front')
    state.partner = false
    state.mode, state.hp = 7, 0.83
    assert(teleport() > 0, 'return from a reset into a clear rear landing even if the front is contested and support is away')
    j.GetLastSeenEnemiesNearLoc = empty
    assert(teleport() > 0, 'return on a clear lane even during the recovery window')
    state.unsafe = true
    assert(teleport() == 0, 'do not teleport back into a dangerous landing')

    state.atBase, state.unsafe, state.buy, state.sourceWave = false, false, true, true
    env.GetAmountAlongLane = function() return {amount=0.5, distance=0} end
    assert(teleport() == 0, 'keep a safe wave even if a recipe is still in the stash')
    state.sourceWave = false
    assert(teleport() == 0, 'stash upgrade cannot spend a scroll during the lane phase')
    j.IsInLaningPhase = no
    desire, destination = teleport()
    assert(desire > 0 and destination == j.GetTeamFountain(), 'can complete the item after the safe wave is gone')

    local front = env.GetTower(nil, env.TOWER_TOP_1)
    state.fallbackTower = {GetLocation = function() return 1700 end}
    front.x, state.unsafe = 6000, false
    local defend = env.X.GetDefendTPLocation
    assert(defend(env.LANE_TOP) == 5700, 'defensive teleports choose a landing beside a living tower')
    j.CanCommitToLaneTeleport = function(_, point) return point ~= 5700 end
    assert(defend(env.LANE_TOP) == 1400, 'use the rear tower if the forward landing is dangerous')

    env.IsLocationVisible = yes
    local second = setmetatable({}, {__index = creep})
    env.GetUnitList = function() return state.wave or {} end
    assert(not env.X.CanTeleportToFarm(200, 150), 'no teleport for an empty visible lane')
    state.wave = {creep, second}
    assert(env.X.CanTeleportToFarm(200, 150), 'a safe landing and a real wave can justify the farm teleport')
    j.CanCommitToLaneTeleport = function(_, point) return point ~= 200 end
    assert(not env.X.CanTeleportToFarm(200, 150), 'a safe landing alone does not justify walking into a dangerous wave')
end
print('PASS: stagger fountain resets and choose safe teleport destinations for lanes, towers, and visible waves')

do
    local s, env, creep, enemy, bot = fixture(true)
    bot.GetAttackRange = function() return 150 end
    creep.x = 950
    creep.GetLocation = function() return creep.x end
    s.allies = {{x=850}, {x=910}}
    local function position()
        return env.J.GetLaningCreepPosition(bot, env.LANE_BOT, {creep}, nil, {})
    end
    assert(position() == 835, 'the melee core rejoins a visible wave with two allied creeps covering its approach')
    s.allies = {{x=850}}
    assert(position() == nil, 'a single covering creep cannot justify the longer approach')
    s.allies, s.towerDive = {{x=850}, {x=910}}, true
    assert(position() == nil, 'do not walk into recently seen opponents to catch a wave')
    creep.x, enemy.x, s.towerDive = 250, 275, false
    local rival = setmetatable({x=350}, {__index=enemy})
    s.secondEnemy = rival
    local safe = env.J.GetLaningCreepPosition(bot, env.LANE_BOT, {creep}, nil, {enemy,rival})
    assert(safe and safe < bot.x, 'a zoned melee hero waits behind the wave instead of walking back into both opponents')
end

do
    local state, mode, creep, enemy, bot = fixture(true, false)
    state.enemy, state.enemyHealth, state.creepHP = true, 30, 250
    assert(mode.J.GetSideLaneFinishTarget(bot, {enemy}) == enemy)
    mode.GetDesire()
    expect(state, mode, 'attack', enemy)
    state.creepHP = 30
    expect(state, mode, 'attack', creep)
    state.creepHP, state.enemyProtected = 250, true
    assert(mode.J.GetSideLaneFinishTarget(bot, {enemy}) == nil, 'do not gamble into protection')
    state.enemyProtected, enemy.x = false, 500
    assert(mode.J.GetSideLaneFinishTarget(bot, {enemy}) == nil, 'do not chase a low enemy out of reach')
end
print('PASS: take an immediate safe finishing hit without dropping a real last hit')

do
    local state, mode, creep, _, bot = fixture(true, false)
    state.campPlan, bot.ohaLaneCamp = {kind='pull'}, {kind='pull'}
    assert(mode.GetDesire() == 0.9, 'an active pull does not hide an immediate core last hit')
    mode.Think()
    assert(state.orders[1][1] == 'attack' and state.orders[1][2] == creep
        and state.cancelCamp == 'last-hit-now', 'issue the last hit, not the camp order')
end

do
    local state, mode, creep, _, bot = fixture(false, false)
    state.noCreeps, state.deniable = true, true
    local ranged = setmetatable({x=170, GetTeam=function() return 2 end,
        GetUnitName=function() return 'npc_dota_creep_goodguys_ranged' end}, {__index=creep})
    state.allies = {ranged}
    state.campPlan, bot.ohaLaneCamp = {kind='pull'}, {kind='pull'}
    mode.J.GetSideLanePressureTarget = function() return {x=350} end
    assert(mode.GetDesire() == 0.76, 'make a reachable ranged deny compete correctly')
    mode.Think()
    assert(state.orders[1][1] == 'attack' and state.orders[1][2] == ranged
        and state.cancelCamp == 'deny-now', 'deny the ranged creep before an optional pull or poke')
end

do
    local state, mode, creep, _, bot = fixture(false, false)
    local j = mode.J
    state.partner = true
    local partner = j.GetLanePartner(bot)
    partner.x = creep.x + 400
    partner.GetTeam = function() return 2 end
    partner.GetAttackProjectileSpeed = function() return 1000 end
    assert(j.CanSupportTakeLaneLastHit(bot, creep), 'do not reserve the last hit for a distant uncommitted core')
    partner.GetAttackTarget = function() return creep end
    assert(not j.CanSupportTakeLaneLastHit(bot, creep), 'respect a committed core order when the timing still works')
    state.partnerRetreat = true
    assert(j.CanSupportTakeLaneLastHit(bot, creep), 'release a retreating core reservation')
    creep.GetIncomingTrackingProjectiles = function() return {{caster=partner, is_attack=true, location=100}} end
    assert(not j.CanSupportTakeLaneLastHit(bot, creep), 'do not steal a lethal projectile already fired by the retreating core')
end
print('PASS: 9107324797 lane arbitration: queued pull, ranged deny, and last-hit ownership')

do
    local state, mode, creep, _, bot = fixture(false, false)
    local j = mode.J
    state.noCreeps, state.deniable, state.partner = true, true, true
    local partner = j.GetLanePartner(bot)
    local ranged = setmetatable({x=165, GetTeam=function() return 2 end,
        GetUnitName=function() return 'npc_dota_creep_goodguys_ranged' end}, {__index=creep})
    local melee = setmetatable({x=175, GetTeam=function() return 2 end}, {__index=creep})
    state.allies = {ranged, melee}
    local winding = true
    local previousDelay = j.GetAttackProDelayTime
    partner.GetAttackTarget = function() return winding and ranged or nil end
    j.GetAttackProDelayTime = function(unit, target)
        if unit == partner then return 0.15, 0.10, 0 end
        return previousDelay(unit, target)
    end
    j.IsAttacking = function(unit) return unit == partner and winding end
    expect(state, mode, 'attack', melee)
    winding = false
    expect(state, mode, 'attack', ranged)
end
print('PASS: duo deny divides targets only while an earlier allied lethal swing is committed')
