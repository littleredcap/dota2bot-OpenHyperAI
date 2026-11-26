local function no() return false end
local function empty() return {} end
local function distance(unit, point) return math.abs(unit.x - point) end
local bounty1, bounty2, power1, power2 = 0, 1, 2, 3
local missing, available, unknown = 0, 1, 2

local function fixture()
    local state = {time=900, spots={ [bounty1]=-900, [bounty2]=600, [power1]=-5000, [power2]=5000 },
        status={[bounty1]=missing, [bounty2]=available, [power1]=missing, [power2]=missing}}
    local heroes = {{x=0,role=2}, {x=0,role=5}, {x=12500,role=4,human=true}}
    for slot, hero in ipairs(heroes) do
        hero.action, hero.orders = 1, {}
        hero.GetPlayerID = function() return slot end
        hero.IsAlive = function(self) return not self.dead end
        hero.IsBot = function(self) return not self.human end
        hero.GetLocation = function(self) return self.x end
        hero.GetMostRecentPing = function(self) return self.ping end
        hero.GetCurrentMovementSpeed = function() return 300 end
        hero.GetCurrentActionType = function(self) return self.action end
        hero.GetActiveMode, hero.GetActiveModeDesire = function() return 0 end, function() return 0 end
        hero.GetLevel = function(self) return self.level or 30 end
        hero.GetAttackRange = function() return 600 end
        hero.GetAssignedLane = function(self) return self.role == 2 and 2 or 3 end
        hero.GetNearbyLaneCreeps = function(self) return self.wave and {{}} or {} end
        hero.FindItemSlot = function(self) return self.bottle and 0 or -1 end
        hero.IsInvulnerable, hero.IsChanneling, hero.HasModifier = no, no, no
        hero.WasRecentlyDamagedByAnyHero, hero.WasRecentlyDamagedByTower = no, no
        hero.GetNearbyHeroes, hero.GetNearbyTowers, hero.GetNearbyCreeps = empty, empty, empty
        hero.Action_PickUpRune = function(self, id) self.action=2; table.insert(self.orders, {'pick', id}) end
        hero.Action_MoveToLocation = function(self, point) self.action=3; table.insert(self.orders, {'move', point}) end
        hero.Action_ClearActions = function(self) self.action=1; table.insert(self.orders, {'cancel'}) end
        hero.Action_MoveDirectly = function(self, point) table.insert(self.orders, {'wisdom', point}) end
    end
    local j = {IsCore=function(h) return h.role <= 3 end, IsValidHero=function(h) return h and h:IsAlive() end,
        GetHP=function(h) return h.hp or 1 end, GetMP=function() return 1 end,
        GetPosition=function(h) return h.role end, IsRetreating=function(h) return h.retreat end,
        GetEnemiesNearLoc=empty, GetLastSeenEnemiesNearLoc=function(p) return p == state.threat and {7} or {} end,
        GetLocationTowardDistanceLocation=function(h, p) return (h.x + p) / 2 end,
        IsInLaningPhase=function() return state.time < 600 end, GetLaningHoldTower=function(h) return h.hold end,
        GetLanePartner=function() end, IsPushing=no, IsGoingOnSomeone=no, IsDoingRoshan=no, IsDoingTormentor=no,
        IsDefending=no, IsMeepoClone=no, IsInTeamFight=no, IsThereCoreNearby=no, IsEarlyGame=no, IsLateGame=no,
        GetDistanceFromEnemyFountain=function() return 8000 end, CanNotUseAction=no, IsValid=function(u) return u ~= nil end,
        GetDistance=function(a,b) return math.abs(a-b) end,
        Utils={IsTeamPushingSecondTierOrHighGround=no, CountEnemyHeroesNear=function() return state.defend and 2 or 0 end}}
    local modes = {}
    for i=1,2 do
        local hero = heroes[i]
        local env = setmetatable({GetBot=function() return hero end, GetScriptDirectory=function() return 'bots' end,
            require=function(name) return name:find('jmz_func',1,true) and j or {} end,
            GetTeamPlayers=function() return {1,2,3} end, GetTeamMember=function(n) return heroes[n] end,
            GameTime=function() return state.time end, DotaTime=function() return state.time end,
            GetAncient=function() return {x=9000, GetLocation=function(self) return self.x end} end, GetTeam=function() return 2 end,
            GetTower=function() end, GetOpposingTeam=function() return 3 end,
            GetRuneStatus=function(id) return state.status[id] end, GetRuneType=function(id) return id == power1 and 8 or 0 end,
            GetRuneSpawnLocation=function(id) return state.spots[id] end, GetUnitToLocationDistance=distance,
            Vector=function(x) return x end, Clamp=function(n,lo,hi) return math.max(lo,math.min(hi,n)) end,
            RemapValClamped=function(n,lo,hi,a,b) return a + (b-a)*math.max(0,math.min(1,(n-lo)/(hi-lo))) end,
            RUNE_BOUNTY_1=bounty1, RUNE_BOUNTY_2=bounty2, RUNE_POWERUP_1=power1, RUNE_POWERUP_2=power2,
            RUNE_STATUS_MISSING=missing, RUNE_STATUS_AVAILABLE=available, RUNE_STATUS_UNKNOWN=unknown, RUNE_WATER=8,
            TEAM_RADIANT=2, TEAM_DIRE=3, LANE_MID=2, BOT_MODE_NONE=0, BOT_ACTION_TYPE_IDLE=1,
            BOT_ACTION_TYPE_PICK_UP_RUNE=2, BOT_MODE_DESIRE_NONE=0, BOT_MODE_DESIRE_MODERATE=0.5, BOT_MODE_DESIRE_HIGH=0.75
        }, {__index=_G})
        setfenv(assert(loadfile('bots/mode_rune_generic.lua')), env)()
        modes[i] = env
    end
    return state, heroes, modes
end

local function order(hero, kind, target)
    local last = hero.orders[#hero.orders]
    assert(last and last[1] == kind and last[2] == target, 'expected ' .. kind .. ' ' .. tostring(target))
end

do
    local s, h, m = fixture()
    h[1].x, h[1].wave = 200, true
    assert(m[1].GetDesire() == 0 and m[2].GetDesire() > 0, 'the support covers the rune while the mid takes the wave')
    m[2].Think()
    order(h[2], 'pick', bounty2)
    h[1].x, h[1].wave, s.status[bounty1] = -800, false, available
    assert(m[1].GetDesire() > 0 and m[2].GetDesire() > 0)
    m[1].Think(); m[2].Think()
    order(h[1], 'pick', bounty1); order(h[2], 'pick', bounty2)
    assert(#h[2].orders == 1, 'the second bot keeps its existing request')
    s.defend = true
    m[2].Think()
    order(h[2], 'cancel')
    assert(m[1].GetDesire() == 0, 'base defense preempts collection')
end

do
    local s, h, m = fixture()
    h[1].role = 5
    assert(m[2].GetDesire() == 0 and m[1].GetDesire() > 0, 'both bots resolve an exact tie to the same collector')
    m[1].Think()
    order(h[1], 'pick', bounty2)
    h[2].retreat, s.status[bounty1], s.status[bounty2] = true, available, missing
    assert(m[1].GetDesire() > 0)
    m[1].Think()
    assert(h[1].orders[#h[1].orders-1][1] == 'cancel', 'cancel the old pickup even after selection moved to the other spot')
    order(h[1], 'pick', bounty1)
    s.status[bounty1] = missing
    m[1].Think()
    order(h[1], 'cancel')
end

do
    local s, h, m = fixture()
    s.status[bounty1], s.status[bounty2] = unknown, unknown
    assert(m[2].GetDesire() > 0 and m[1].GetDesire() == 0)
    m[2].Think()
    order(h[2], 'move', s.spots[bounty2])
    h[2].x = s.spots[bounty2] - 80
    m[2].Think()
    order(h[2], 'cancel')
    assert(m[2].GetDesire() == 0 and m[1].GetDesire() == 0, 'nobody immediately rechecks an unconfirmed spot')
    s.status[bounty2] = available
    assert(m[2].GetDesire() > 0)
    m[2].Think()
    order(h[2], 'pick', bounty2)
    h[3].ping = {normal_ping=true, time=s.time, location=s.spots[bounty2]}
    m[2].Think()
    order(h[2], 'cancel')
    assert(m[1].GetDesire() == 0, 'respect the human claim')
end

do
    local s, h, m = fixture()
    s.spots[bounty1], s.spots[bounty2] = 700, -600
    s.status[bounty1], s.status[bounty2] = unknown, unknown
    assert(m[2].GetDesire() > 0)
    m[2].Think()
    order(h[2], 'move', s.spots[bounty1])
end

do
    local s, h, m = fixture()
    s.spots[bounty2], s.threat = 1600, 800
    assert(m[2].GetDesire() == 0 and m[1].GetDesire() == 0, 'avoid the unsafe midpoint despite a clear rune spot')
    s.threat, h[2].hp = nil, 0.25
    assert(m[1].GetDesire() > 0 and m[2].GetDesire() == 0, 'a healthy core can collect if the support needs to reset')
    s.time, h[2].hp, h[2].hold, h[1].wave = 185, 1, true, true
    assert(m[2].GetDesire() == 0 and m[1].GetDesire() == 0, 'do not vacate the side lane or a core last hit for a distant rune')
    s.status[power1], s.spots[power1], h[1].bottle = available, 40, true
    assert(m[1].GetDesire() > 0)
    m[1].Think()
    order(h[1], 'pick', power1)
end

do
    local s, h, m = fixture()
    s.time, h[1].x, h[2].x, h[2].level = 420, -7000, -100, 6
    assert(m[2].GetDesire() > 0)
    m[2].Think()
    order(h[2], 'pick', bounty2)
end
do
    local s, h, m = fixture()
    s.status[bounty1], s.spots[bounty1], s.spots[bounty2] = available, 100, 2300
    h[1].role, h[2].x = 5, -1500
    assert(m[1].GetDesire() > 0 and m[2].GetDesire() > 0)
    m[1].Think(); m[2].Think()
    order(h[1], 'pick', bounty2); order(h[2], 'pick', bounty1)
end
print('PASS: independent bots assign, release and reassign bounty runes while preserving lane and objective duties')
