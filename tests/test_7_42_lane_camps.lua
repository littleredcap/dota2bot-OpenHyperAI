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
            GetCurrentMovementSpeed = function() return 300 end,
            GetAttackTarget = function(self) return self.target end}
    end
    local camp = {team = own, type = 'small', location = point(sign * 800, 400)}
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
    carry.GetUnitName = function() return 'npc_dota_hero_sniper' end
    support.GetAttackRange = function() return 450 end
    support.WasRecentlyDamagedByAnyHero = no
    support.GetNearbyNeutralCreeps = function() return state.neutrals end
    support.GetNearbyLaneCreeps = function(_, _, hostile) return not stack and not hostile and state.wave or {} end
    support.GetLastAttackTime = function() return state.lastShot end
    support.Action_AttackUnit = function(_, target) state.orders[#state.orders + 1] = {attack = target} end
    support.Action_MoveToLocation = function(_, loc) state.orders[#state.orders + 1] = {move = loc} end
    support.Action_ClearActions = function() end
    local j = {
        GetPosition = function(unit) return unit == support and 5 or 1 end,
        IsCore = function(unit) return unit == carry end, GetHP = function() return 0.9 end,
        IsRetreating = no, IsGoingOnSomeone = no, IsKeyWordUnit = no, CanBeAttacked = yes,
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
        GetLocationToLocationDistance = distance, GetAttackProDelayTime = function() return 0.3, 0.3 end,
        VectorTowards = function(origin, target, steps)
            local span = distance(origin, target)
            return point(origin.x + (target.x - origin.x) * steps / span, origin.y + (target.y - origin.y) * steps / span)
        end,
        Site = {IsSmallCamp = yes, IsAncientCamp = no, GetCampStackTime = function() return 56 end},
    }
    local env = setmetatable({
        GetScriptDirectory = function() return 'bots' end,
        require = function() return j end,
        DotaTime = function() return state.now end,
        GetNeutralSpawners = function() return {camp} end, IsLocationVisible = function() return not state.hidden end,
        GetUnitToLocationDistance = distance, IsLocationPassable = yes,
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

print('PASS: lane pull interception, camp claims, attack windup, stack confirmation and farm owner')
