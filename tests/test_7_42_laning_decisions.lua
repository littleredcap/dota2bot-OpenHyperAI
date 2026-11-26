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
    local creep = {x = 200, GetHealth = function() return state.creepHP end,
        GetTeam = function() return 3 end, GetUnitName = function() return 'npc_dota_creep_badguys_melee' end,
        GetLocation = function() return 200 end, GetHealthRegen = function() return 0 end,
        GetActualIncomingDamage = function(_, damage) return damage end, IsCreep = yes}
    local partner = {x = 260, IsAlive = function() return not state.partnerDead end,
        DistanceFromFountain = function() return state.partnerAtBase and 0 or 6000 end,
        HasModifier = function(_, m) return m == 'modifier_teleporting' and state.partnerTP end,
        WasRecentlyDamagedByAnyHero = function() return state.partnerHit end,
        GetPlayerID = function() return 2 end,
        IsDisarmed = function() return state.partnerDisarmed end,
        GetAttackRange = function() return 150 end, GetAttackTarget = function() end}
    local bot = {x = 0}
    local enemy = {x = 260, GetAttackRange = function() return 500 end,
        GetLocation = function(self) return self.x end,
        GetAttackTarget = function()
            return state.pressure and not state.betweenAttacks and bot or state.enemyCreep
        end,
        GetAttackCombatProficiency = function() return 1 end,
        GetAttackDamage = function() return state.enemyDamage or 50 end,
        GetLastAttackTime = function() return state.time - 1 end}
    local tower = {x = 700, GetAttackTarget = function() return state.tower and bot or nil end}
    local openingTower = {x = 1600, IsAlive = yes, GetLocation = function(self) return self.x end}
    bot.GetPlayerID = function() return state.playerID or 1 end
    bot.GetUnitName = function() return heroName end
    bot.GetLevel = function() return 5 end
    bot.GetTeam = function() return 2 end
    bot.GetAssignedLane = function() return 3 end
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
        IsValidBuilding = function(unit) return unit == tower or unit == openingTower end,
        IsSuspiciousIllusion = no, IsChasingTarget = no, IsThereNonSelfCoreNearby = no,
        GetHP = function(unit) return unit == bot and state.hp or (unit == partner and state.partnerHP)
            or (unit.IsCreep and state.deniable and 0.4 or 0.75) end,
        CanNotUseAction = no, CanBeAttacked = yes,
        IsAttacking = function(unit) return unit == bot and state.attacking or unit == enemy and state.enemyWindup end,
        GetAttackProDelayTime = function(unit) return unit == enemy and state.enemyEta or 0.3 end,
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
        GetLastSeenEnemiesNearLoc = function() return state.towerDive and {6, 7} or {} end,
        GetEnemiesNearLoc = empty,
        GetLanePartner = function() return state.partner and partner or nil end,
        IsInRange = function(a, b, range) return math.abs(a.x - b.x) <= range end,
        IsKeyWordUnit = function(word, unit) return unit:GetUnitName():find(word, 1, true) ~= nil end,
        GetLocationTowardDistanceLocation = function(unit, _, distance) return unit.x - distance end,
    }
    local modules = {['bots/FunLib/utils'] = utils, ['bots/FunLib/jmz_func'] = j,
        ['bots/FunLib/version'] = {}, ['bots/FunLib/localization'] = {Get = empty},
        ['game/botsinit'] = {CreateGeneric = empty}}
    local env = setmetatable({
        J = j, GetScriptDirectory = function() return 'bots' end, GetBot = function() return bot end,
        require = function(name) return assert(modules[name], name) end,
        GetTeam = function() return 2 end, GetOpposingTeam = function() return 3 end,
        GetTeamPlayers = empty, GetGameMode = function() return 0 end,
        GetGameState = function() return 0 end, GAME_STATE_PRE_GAME = 1,
        GetTower = function() return openingTower end,
        TOWER_TOP_1 = 10, TOWER_MID_1 = 11, TOWER_BOT_1 = 12,
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
    expect(state, mode, 'approach', distant)
    tower.x, state.towerIdle = 825, true
    expect(state, mode, 'move', -450)
    state.towerIdle, state.creeps = false, {creep}
    state.enemy, state.pressure, state.secondEnemy = true, true, {x = 270, GetAttackRange = enemy.GetAttackRange,
        GetAttackTarget = function() return bot end}
    state.enemies = {enemy, state.secondEnemy}
    expect(state, mode, 'move', -1200)
end
print('PASS: both lane modes prefer reachable ranged creeps, preserve attack windups and respect tower pressure')

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
end
print('PASS: collect either nearby water rune and stay for a reachable last hit')
