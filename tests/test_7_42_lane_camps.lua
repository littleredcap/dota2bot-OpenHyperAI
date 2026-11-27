local function yes() return true end
local function no() return false end
local function empty() return {} end
local function point(x, y) return {x = x, y = y} end
local function distance(a, b) return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2) end

local function fixture(stack)
    local state = {now = stack and 176 or 118, lastShot = 0, orders = {}}
    local function unit(x, y, team)
        return {x = x, y = y, IsCreep = yes, IsAlive = yes,
            GetLocation = function(self) return self end, GetTeam = function() return team end,
            GetCurrentMovementSpeed = function() return 300 end,
            GetAttackTarget = function(self) return self.target end}
    end
    local camp = {team = 2, type = 'small', location = point(800, 400)}
    local tower = unit(0, 0, 2)
    local neutral = unit(800, 400, 4)
    local waveCreep = unit(200, 0, 2)
    local carry = unit(1000, 200, 2)
    local support = unit(800, 160, 2)
    state.neutrals = {neutral}
    carry.IsBot, carry.GetPlayerID = yes, function() return 2 end
    carry.GetAttackDamage, carry.GetSecondsPerAttack = function() return 160 end, function() return 1 end
    carry.GetUnitName = function() return 'npc_dota_hero_sniper' end
    support.GetAttackRange = function() return 450 end
    support.WasRecentlyDamagedByAnyHero = no
    support.GetNearbyNeutralCreeps = function() return state.neutrals end
    support.GetNearbyLaneCreeps = function() return stack and {} or {waveCreep} end
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
        GetEnemiesNearLoc = empty, GetLastSeenEnemiesNearLoc = empty,
        CanLeaveLane = function() return not state.unsafeLane end,
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
        GetTower = function() return tower end, GetLaneFrontLocation = function() return point(1450, 0) end,
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
    local plan = assert(mode.Plan(support, 3))
    assert(plan.kind == 'pull' and #state.orders == 0)
    assert(mode.Think(support, plan) and state.orders[1].attack == neutral)
    assert(mode.Think(support, plan) and #state.orders == 1, 'preserve the aggro shot')
    state.lastShot = 118
    assert(mode.Think(support, plan) and state.orders[2].move == plan.goal)
    neutral.target = wave
    assert(not mode.Think(support, plan) and support.ohaLaneCamp == nil, 'finish only once the creeps engage')
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

print('PASS: lane pull interception, camp claims, attack windup, stack confirmation and farm owner')
