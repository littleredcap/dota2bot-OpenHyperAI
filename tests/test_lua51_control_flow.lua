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
    local time, orders, target = 600, {}, nil
    local function distance(a, b) return math.abs(a.x - b.x) end
    local enemy = {x = opts.enemyX or 1700, hp = 0.65, IsMagicImmune = no,
        GetLocation = function(self) return self end, GetHealth = function() return 450 end,
        GetAttackRange = function() return 600 end}
    local partner = {x = enemy.x - 200, IsIllusion = no, IsAlive = yes, HasModifier = no,
        GetLocation = function(self) return self end, GetAssignedLane = function() return 2 end,
        GetEstimatedDamageToTarget = function() return 260 end}
    local bot = {
        x = 0, GetUnitName = function() return 'npc_dota_hero_test' end,
        IsAlive = yes, IsHero = yes, IsInvulnerable = no, IsIllusion = no, GetTeam = function() return 2 end,
        IsUsingAbility = no, IsChanneling = no, HasModifier = no,
        WasRecentlyDamagedByTower = no, WasRecentlyDamagedByAnyHero = no,
        GetActiveMode = function() return 0 end, GetNearbyHeroes = empty, GetNearbyTowers = empty,
        GetLocation = function(self) return self end, GetAbilityByName = nilValue,
        GetAbilityInSlot = function(_, slot)
            return opts.ready ~= false and slot == 1 and {IsPassive = no,
                GetName = function() return 'shadow_shaman_voodoo' end, GetCastRange = function() return 500 end} or nil
        end,
        GetCurrentMovementSpeed = function() return 300 end, GetAttackRange = function() return 500 end,
        GetEstimatedDamageToTarget = function() return 200 end,
        GetLevel = function() return opts.level or 4 end,
        GetAssignedLane = function() return opts.own or 1 end,
        GetTarget = function() return target end, SetTarget = function(_, unit) target = unit end,
        Action_MoveToLocation = function(_, point) orders[#orders+1] = {point = point} end,
        Action_AttackUnit = function(_, unit) orders[#orders+1] = {target = unit} end,
        Action_UseAbilityOnLocation = function(_, _, point) orders[#orders+1] = {tp = point} end,
    }
    local scroll = {}
    local j = {
        Utils = {GameStates = {}, IsBotThinkingMeaningfulAction = no, ShouldBotsSpreadOut = no,
            GetItemFromFullInventory = function() return opts.tp and scroll end},
        GetChronosphereAvoidanceLocation = nilValue, GetShrapnelEscapeLocation = nilValue,
        CanNotUseAction = no, GetProperTarget = nilValue,
        GetPosition = function() return opts.position or 4 end, IsAttacking = no,
        IsInLaningPhase = yes, IsRetreating = no, IsDefending = no, HasHealingItem = no,
        IsDisabled = function(unit) return unit == enemy and opts.controlLanded end,
        CanFollowLaneFight = function() return not opts.noFollowUp end,
        WeAreStronger = yes, CanBeAttacked = yes, IsSuspiciousIllusion = no,
        GetHP = function(unit) return unit.hp or 1 end,
        IsInRange = function(unit, point, range) return distance(unit, point) <= range end,
        GetModifierTime = function() return 0 end, GetModifierCount = function() return 0 end,
        GetAlliesNearLoc = function() return opts.noPartner and {} or {partner} end,
        GetEnemiesNearLoc = function(point, range)
            return not opts.enemyGone and distance(point, enemy) <= range and {enemy} or {}
        end,
        IsValidHero = function(unit) return unit == partner or unit == enemy and not opts.enemyGone end,
        IsValidBuilding = function(unit) return unit ~= nil and unit.tower end,
        CanLeaveLane = function() return not opts.unsafeLane end,
        CanCastAbility = function(spell) return not not spell end, IsStunProjectileSpell = no,
        CanCommitToLaneTeleport = function() return not opts.unsafeLanding end,
        CanStartTeleportHere = function() return not opts.unsafeOrigin end,
        GetLocationToLocationDistance = distance, GetLastSeenEnemiesNearLoc = empty,
        GetLocationTowardDistanceLocation = function(_, _, delta) return {x = delta} end,
        AdjustLocationWithOffsetTowardsFountain = function(loc, offset) return {x = loc.x - offset} end,
        VectorTowards = function(loc, _, shift) return {x = loc.x - shift} end,
    }
    local tower = {x = enemy.x - 670, tower = true, GetLocation = function(self) return self end}
    local env = loadProduction('bots/mode_roam_generic.lua', {
        require = function(name) if name:find('jmz_func', 1, true) then return j end; return {} end,
        GetScriptDirectory = function() return 'bots' end,
        GetBot = function() return bot end, GetTeam = function() return 2 end, GetOpposingTeam = function() return 3 end,
        GetTeamPlayers = function() return {1, 2} end, GetTeamMember = function(i) return i == 1 and bot or partner end,
        LANE_TOP = 1, LANE_MID = 2, LANE_BOT = 3,
        TOWER_TOP_1 = 11, TOWER_MID_1 = 12, TOWER_BOT_1 = 13, TOWER_TOP_2 = 21, TOWER_MID_2 = 22, TOWER_BOT_2 = 23,
        GetTower = function(team, id) if team == 2 and id == 12 then return tower end end,
        GetUnitToLocationDistance = distance, GetUnitToUnitDistance = distance, IsLocationPassable = yes,
        DotaTime = function() return time end, Clamp = function(value) return value end,
        BOT_MODE_DESIRE_NONE = 0, BOT_ACTION_DESIRE_NONE = 0,
    })
    env.ConsiderHeroMoveOutsideFountain, env.CanBeAffectedByChainFrost = no, no
    env.ConsiderUseTango = function() return 0 end
    return env, bot, enemy, partner, orders, function(seconds) time = time + seconds end
end

do
    local opts = {}
    local mode, bot, enemy, _, orders = roam(opts)
    assert(mode.GetDesire() == 0.66 and mode.GetDesire() == 0.66 and #orders == 0, 'score a gank without issuing orders')
    mode.Think()
    assert(bot.ohaLaneGank.target == enemy and orders[1].point.x == 1245, 'enter only to the range needed to cast control')
    opts.unsafeLane = true
    assert(mode.GetDesire() == 0 and bot.ohaLaneGank == nil, 'cancel when leaving the original lane becomes unsafe')
end

do
    local opts = {noFollowUp=true}
    local mode, bot, enemy, _, orders = roam(opts)
    bot.x = enemy.x - 450
    assert(mode.GetDesire() == 0.66)
    mode.Think()
    assert(orders[1].point.x == 860 and bot:GetTarget() == nil, 'wait on the safe side when the partner cannot hit')
    opts.noFollowUp = false
    mode.GetDesire()
    mode.Think()
    assert(bot.ohaLaneGank.ready and #orders == 1 and bot:GetTarget() == enemy, 'let the spell open before attacking')
    opts.controlLanded = true
    mode.GetDesire()
    mode.Think()
    assert(orders[2].target == enemy, 'follow the disable when the partner can also follow')
end

for _, opts in ipairs({{unsafeLane=true}, {noPartner=true}, {enemyGone=true}, {own=2}, {position=2}, {level=3}, {ready=false},
    {enemyX=4400}, {enemyX=4400,tp=true,unsafeLanding=true}}) do
    local mode, _, _, _, orders = roam(opts)
    assert(mode.GetDesire() == 0 and #orders == 0, 'an invalid opening cannot win roam mode')
end

do
    local mode, bot, _, partner, orders, advanceTime = roam({enemyX=4400,tp=true})
    assert(mode.GetDesire() == 0.66)
    partner.ohaLaneGank = {lane=2,expires=609}
    mode.Think()
    assert(#orders == 0 and bot.ohaLaneGank == nil, 'only one roamer may claim a destination')
    partner.ohaLaneGank = nil
    advanceTime(1)
    assert(mode.GetDesire() == 0.66)
    mode.Think()
    assert(orders[1].tp.x == 3430 and bot.ohaLaneGank.landing == nil, 'use a safe arrival once')
end

print('PASS: role assignment and live gank planning, departure safety, claim, cancel, and TP')
do
    local mode,bot,_,_,orders=roam({enemyX=4400,tp=true,unsafeOrigin=true})
    assert(mode.GetDesire()==0.66)
    mode.Think()
    assert(#orders==0 and not bot.ohaLaneGank,'a safe landing does not excuse a vulnerable origin')
end
