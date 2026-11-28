local function yes() return true end
local function no() return false end
local function empty() return {} end
local function point(x, y) return {x = x, y = y} end
local function distance(a, b) return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2) end

local function fixture(stack, mirrored)
    local own, foe, lane, sign = 2, 3, 3, 1
    if mirrored then own, foe, lane, sign = 3, 2, 1, -1 end
    local state = {now = stack and 176 or 118, lastShot = 0, orders = {}}
    local function unit(x, y, team)
        return {x = x, y = y, IsCreep = yes, IsAlive = yes,
            GetLocation = function(self) return self end, GetTeam = function() return team end,
            GetUnitName = function(self) return self.name or '' end,
            GetCurrentMovementSpeed = function() return 300 end,
            GetAttackTarget = function(self) return self.target end}
    end
    local camp = {team = own, type = 'small', location = point(sign * 800, 400)}
    state.camp = camp
    local tower = unit(0, 0, own)
    local neutral = unit(sign * 800, 400, 4)
    local waveCreep = unit(sign * 200, 0, own)
    local rearCreep = unit(sign * 170, 0, own)
    local carry = unit(sign * 1000, 200, own)
    carry.GetAssignedLane = function() return lane end
    carry.WasRecentlyDamagedByAnyHero = function() return state.coreHit end
    state.wave = {waveCreep, rearCreep}
    state.front = sign * 1450
    local support = unit(sign * 800, 160, own)
    state.neutrals = {neutral}
    carry.IsBot, carry.GetPlayerID = yes, function() return 2 end
    carry.GetAttackDamage, carry.GetSecondsPerAttack = function() return 160 end, function() return 1 end
    carry.GetHealth = function() return 1000 end
    carry.GetUnitName = function() return 'npc_dota_hero_sniper' end
    support.GetAttackRange = function() return 450 end
    support.WasRecentlyDamagedByAnyHero = no
    support.GetNearbyNeutralCreeps = function() return state.neutrals end
    support.GetNearbyLaneCreeps = function(_, _, hostile)
        if hostile then return state.enemyWave or {} end
        return not stack and state.wave or {}
    end
    state.laneUnit = function(x, enemy) return unit(sign * x, 0, enemy and foe or own) end
    support.GetLastAttackTime = function() return state.lastShot end
    support.Action_AttackUnit = function(_, target) state.orders[#state.orders + 1] = {attack = target} end
    support.Action_MoveToLocation = function(_, loc) state.orders[#state.orders + 1] = {move = loc} end
    support.Action_ClearActions = function() end
    local j = {
        GetPosition = function(unit) return unit == support and 5 or 1 end,
        IsCore = function(unit) return unit == carry end, GetHP = function() return 0.9 end,
        IsRetreating = no, IsGoingOnSomeone = no, CanBeAttacked = yes,
        IsKeyWordUnit = function(word, creep) return creep:GetUnitName():find(word, 1, true) ~= nil end,
        IsValid = function(unit) return unit ~= nil and not unit.dead end,
        IsValidBuilding = function(unit) return unit == tower end,
        HasItem = function(_, name) return not state.noFarmer and name == 'item_maelstrom' end,
        IsInRange = function(a, b, radius) return distance(a, b) <= radius end,
        GetAlliesNearLoc = function() return {carry} end,
        GetLanePartner = function() return not state.noCarry and carry or nil end,
        IsValidHero = function(x) return x == carry end,
        GetEnemiesNearLoc = function(point)
            if state.unsafeLane and point == carry then return {neutral} end
            if state.campInvaded and point == camp.location then return {neutral} end
            return {}
        end, GetLastSeenEnemiesNearLoc = empty,
        CanLeaveLane = function() return not state.unsafeLane and not state.roamBlocked end,
        GetVisibleThreatAt = function() return state.unsafeLane and 300 or 0 end,
        GetLocationToLocationDistance = distance, GetAttackProDelayTime = function() return 0.3, 0.3 end,
        VectorTowards = function(origin, target, steps)
            local span = distance(origin, target)
            return point(origin.x + (target.x - origin.x) * steps / span, origin.y + (target.y - origin.y) * steps / span)
        end,
        Site = {IsSmallCamp = function(camp) return camp.type == 'small' end, IsAncientCamp = no,
            GetCampStackTime = function() return 56 end},
    }
    local env = setmetatable({
        GetScriptDirectory = function() return 'bots' end,
        require = function() return j end,
        DotaTime = function() return state.now end,
        GetNeutralSpawners = function() return {camp} end,
        IsLocationVisible = function(loc) return not state.hidden and not (state.campFog and loc == camp.location) end,
        GetUnitList = function() return not stack and state.wave or {} end, UNIT_LIST_ALLIED_CREEPS = 1,
        GetUnitToLocationDistance = distance, IsLocationPassable = function(loc)
            return not (state.centerBlocked and distance(loc, camp.location) < 5)
                and not (state.blockY and math.abs(loc.y - state.blockY) < 6)
        end,
        GetAmountAlongLane = function(_, loc) return {amount = loc.x / 10000, distance = math.abs(loc.y)} end,
        GetLocationAlongLane = function(_, amount) return point(amount * 10000, 0) end,
        GetTower = function(team) return team == own and tower or nil end,
        GetOpposingTeam = function() return foe end,
        GetUnitToUnitDistance = distance,
        GetLaneFrontLocation = function() return point(state.front, 0) end,
        GetTeamPlayers = function() return {1, 2} end, GetTeamMember = function(slot) return slot == 1 and support or carry end,
        TEAM_RADIANT = 2, TEAM_NEUTRAL = 4, LANE_TOP = 1, LANE_BOT = 3, TOWER_TOP_1 = 10, TOWER_BOT_1 = 12,
    }, {__index = _G})
    local mode = setfenv(assert(loadfile('bots/FunLib/lane_camp.lua')), env)()
    return state, support, carry, neutral, waveCreep, mode
end

do
    local state, support, carry, neutral, wave, mode = fixture(false)
    state.now, wave.x, state.wave[2].x = 59, -1100, -1150
    assert(not mode.Plan(support, 3), 'respect the first camp spawn')
    state.now, support.x = 72, 200
    local early = assert(mode.Plan(support, 3))
    assert(early.attackAt > state.now + 3, 'make time to walk from lane before the earliest release window')
    assert(mode.Think(support, early) and distance(support, state.orders[1].move) <= 420
        and distance(neutral, state.orders[1].move) < distance(support, neutral))

    state.now, support.ohaLaneCamp = 112, nil
    carry.GetAssignedLane = function() return 1 end
    state.camp.type, state.camp.team = 'large', 3
    wave.x, state.wave[2].x = 200, 170
    assert(mode.Plan(support, 1), 'offlane can use a clear route from a non-ancient hard camp')
end

do
    local state, support, _, neutral, _, mode = fixture(false)
    state.campFog, state.neutrals, support.y = true, {}, -110
    local probe = assert(mode.Plan(support, 3))
    assert(probe.kind == 'probe' and probe.target == nil and distance(support, probe.goal) <= 360,
        'check the near side of a pull camp without assuming a neutral is alive')
    assert(mode.Think(support, probe) and state.orders[1].move == probe.goal and state.orders[1].attack == nil,
        'scouting issues only a short move')
    state.campFog, state.neutrals = false, {neutral}
    support.x, support.y = probe.goal.x, probe.goal.y
    local pull = assert(mode.Plan(support, 3))
    assert(pull.kind == 'pull' and pull.target == neutral, 're-evaluate the actual wave and newly visible camp')
    state.campFog, state.campInvaded = true, true
    assert(not mode.Plan(support, 3), 'skip a scout toward an unsafe camp')
end

do
    local state, support, _, neutral, wave, mode = fixture(false)
    support.y = state.camp.location.y - 1600
    wave.x, state.wave[2].x = -1040, -1070
    local scans = 0
    support.GetNearbyNeutralCreeps = function()
        scans = scans + 1
        return {neutral}
    end
    local approach = assert(mode.Plan(support, 3))
    assert(approach.kind == 'probe' and scans == 0 and distance(support, approach.goal) <= 240,
        'a visible camp just outside scan range still gets a bounded approach')
    assert(mode.Think(support, approach) and state.orders[1].move == approach.goal and scans == 0,
        'visibility alone does not clear an approach before the camp can be scanned')
    support.x, support.y = approach.goal.x, approach.goal.y
    local pull = assert(mode.Plan(support, 3))
    assert(scans > 0 and pull.kind == 'pull' and pull.target == neutral,
        'plan the actual pull once the bot can inspect the camp and the wave')
end

do
    local state, support, _, neutral, wave, mode = fixture(false)
    state.camp.location.y, neutral.y, support.y = 1240, 1240, 700
    wave.x, state.wave[2].x, state.centerBlocked = -850, -880, true
    local pull = assert(mode.Plan(support, 3))
    assert(pull.kind == 'pull' and pull.target == neutral, 'a walkable 1,240-unit route uses the visible neutral')
    assert(mode.Think(support, pull) and state.orders[1].move.y == 810,
        'approach only as far as the attack range even when the camp center is blocked')
    support.ohaLaneCamp = nil
    state.blockY = 620
    assert(not mode.Plan(support, 3), 'keep rejecting a blocked corridor')
    state.blockY, neutral.GetCurrentMovementSpeed = nil, function() return 250 end
    assert(not mode.Plan(support, 3), 'reject a neutral that takes too long to reach the lane')
end

do
    local state, support, carry, neutral, wave, mode = fixture(false)
    state.unsafeLane = true
    assert(mode.Plan(support, 3) == nil, 'keep the lane partner covered')
    state.unsafeLane, state.hidden = false, true
    assert(mode.Plan(support, 3) == nil, 'use visible camps')
    state.hidden = false
    carry.ohaFarmCampClaim = {location = point(800, 400), expires = 123}
    assert(mode.Plan(support, 3) == nil, 'leave a camp already being farmed')
    carry.ohaFarmCampClaim = nil
    state.front = -1450
    assert(not mode.Plan(support, 3), 'the same unsigned distance behind our tower is not a push')
    state.front, state.coreHit = 1450, true
    assert(not mode.Plan(support, 3), 'a recently attacked core needs its support')
    state.coreHit, state.noCarry = false, true
    assert(not mode.Plan(support, 3), 'do not pull for an absent lane core')
    state.noCarry = false
    local plan = assert(mode.Plan(support, 3))
    assert(plan.kind == 'pull' and #state.orders == 0)
    assert(mode.Think(support, plan) and #state.orders == 0, 'wait if the wave has not reached the release window')
    state.now = plan.attackAt
    assert(mode.Think(support, plan) and state.orders[1].attack == neutral)
    assert(mode.Think(support, plan) and #state.orders == 1, 'preserve the aggro shot')
    state.lastShot = state.now + 0.2
    assert(mode.Think(support, plan) and #state.orders == 1, 'projectile release alone is not aggro')
    neutral.target = support
    assert(mode.Think(support, plan) and state.orders[2].move == plan.goal)
    wave.x, neutral.target = 760, wave
    assert(mode.Think(support, plan) and not support.ohaLastConfirmedPull, 'one isolated creep does not prove a pull')
    state.wave[2].x, state.wave[2].target = 770, neutral
    assert(not mode.Think(support, plan) and support.ohaLaneCamp == nil, 'finish only once two lane creeps engage')
    assert(support.ohaLastConfirmedPull.caught == 2, 'attribute engagement to the actual lane creeps')
end

do
    local state, support, _, neutral, _, mode = fixture(true)
    state.noFarmer = true
    assert(mode.Plan(support, 3) == nil, 'stack only when a nearby core can clear it')
    state.noFarmer = false
    local plan = assert(mode.Plan(support, 3))
    assert(plan.kind == 'stack' and plan.owner == 2)
    assert(mode.Think(support, plan))
    state.lastShot, state.now = 176, 176.3
    assert(mode.Think(support, plan) and state.orders[2].move == plan.goal)
    state.now = 180.5
    assert(mode.Think(support, plan) and support.ohaStackedCamp == nil, 'do not reserve a failed stack')
    local replacement = {}
    for key, value in pairs(neutral) do replacement[key] = value end
    state.neutrals[2] = replacement
    assert(not mode.Think(support, plan) and support.ohaStackedCamp.owner == 2)
end

do
    local state, support, carry, neutral, _, mode = fixture(false)
    local plan = assert(mode.Plan(support, 3))
    state.now = plan.attackAt
    assert(mode.Think(support, plan))
    neutral.target = support
    state.campInvaded = true
    assert(not mode.Think(support, plan) and not support.ohaLastConfirmedPull, 'cancel a contested camp on the next tick')
end

do
    local state, support, carry, neutral, _, mode = fixture(false)
    local plan = assert(mode.Plan(support, 3))
    state.now = plan.attackAt
    assert(mode.Think(support, plan))
    carry.ohaFarmCampClaim = {location = neutral, expires = plan.expires}
    assert(not mode.Think(support, plan), 'recheck a camp claimed during setup')
end

do
    local state, support, _, _, _, mode = fixture(false)
    local plan = assert(mode.Plan(support, 3))
    assert(mode.Think(support, plan))
    state.now, state.wave = plan.attackAt, {}
    assert(not mode.Think(support, plan) and #state.orders == 0, 'do not aggro after the wave has passed')
end

do
    local state, support, _, _, _, mode = fixture(false, true)
    assert(mode.Plan(support, 1), 'Dire top uses the reversed lane direction')
    assert(not mode.Plan(support, 3), 'do not use unverified offlane camp geometry')
    state.roamBlocked = true
    assert(mode.Plan(support, 1), 'allow a short safe pull even if a longer roam is blocked')
    state.unsafeLane = true
    assert(not mode.Plan(support, 1), 'do not leave the endangered core')
end

do
    local state, support, _, neutral, wave, mode = fixture(false)
    local plan = assert(mode.Plan(support, 3))
    state.now = plan.attackAt + 0.8
    wave.x, state.wave[2].x, neutral.y = 520, 490, 500
    assert(not mode.Think(support, plan) and #state.orders == 0, 'recompute interception after the neutral moves')
end

print('PASS: lane pull interception, camp claims, attack windup, stack confirmation and farm owner')

for _, mirrored in ipairs({false, true}) do
    local state, support, _, neutral, _, mode = fixture(false, mirrored)
    local lane, direction = mirrored and 1 or 3, mirrored and -1 or 1
    state.wave = {state.laneUnit(410), state.laneUnit(380), state.laneUnit(170), state.laneUnit(110)}
    state.wave[4].name = 'npc_dota_creep_ranged'
    state.enemyWave = {state.laneUnit(1000, true), state.laneUnit(1050, true), state.laneUnit(1120, true)}
    assert(not mode.Plan(support, lane), 'keep the support with a sizeable incoming enemy wave')
    state.enemyWave = {}
    local plan = assert(mode.Plan(support, lane))
    assert(plan.half and plan.half[4].unit == state.wave[4], 'aim for only the tail of a full wave with an ordinary small camp')
    local travel = 300 * (plan.attackAt - state.now)
    for _, creep in ipairs(state.wave) do creep.x = creep.x + direction * travel end
    state.now = plan.attackAt
    assert(mode.Think(support, plan) and state.orders[1].attack == neutral, 'launch on the trailing pair')
    neutral.target = support
    state.wave[3].x, state.wave[4].x = direction * 780, direction * 750
    state.wave[3].target, state.wave[4].target = neutral, neutral
    assert(not mode.Think(support, plan) and support.ohaLastConfirmedPull.half, 'verify the actual lane-creep contact')
end

do
    local state, support, _, _, _, mode = fixture(false)
    state.wave = {state.laneUnit(200), state.laneUnit(190), state.laneUnit(180), state.laneUnit(170)}
    state.wave[4].name = 'npc_dota_creep_ranged'
    assert(not mode.Plan(support, 3), 'an unseparated full wave would feed an ordinary small camp surviving creeps')
end
