local file = assert(io.open('bots/mode_farm_generic.lua', 'rb'))
local source = file:read('*a')
file:close()
local start = assert(source:find('local function SideWaveUnit', 1, true))
local finish = assert(source:find('local function GetUnclaimedWaveDesire', start, true))

local function pos(x, y, z) return {x = x, y = y or 0, z = z or 0} end
local function distance(a, b)
    a, b = a.p or a, b.p or b
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end
local function yes() return true end
local function no() return false end
local function unit(x, y, name, id, role, mode)
    return {p = pos(x, y), id = id, role = role, mode = mode,
        GetUnitName = function() return name end, GetHealth = function() return 300 end,
        GetLocation = function(self) return self.p end, GetPlayerID = function(self) return self.id end,
        IsIllusion = no, IsChanneling = no, HasModifier = no, IsDisarmed = no, IsRooted = no,
        IsBot = yes, CanBeSeen = yes, WasRecentlyDamagedByAnyHero = no,
        GetActiveMode = function(self) return self.mode end, GetActiveModeDesire = function() return 0.77 end,
        GetCurrentMovementSpeed = function() return 380 end, GetAttackRange = function() return 500 end,
        GetAttackDamage = function() return 165 end, GetSecondsPerAttack = function() return 1 end,
        GetAttackTarget = function() return nil end}
end
local top, mid, bottom = pos(3000,1000), pos(5000,0), pos(3000,-2200)
local lead = unit(5000,0,'core',0,1,12)
local mate = unit(4790,0,'support',1,5,12)
local mate2 = unit(5050,90,'core',2,2,12)
local bot = unit(2720,1000,'bot',3,3,20)
local alt = unit(2510,1000,'alt',4,4,20)
local close = unit(3030,1000,'npc_dota_creep_badguys_melee')
local ranged = unit(3200,1000,'npc_dota_creep_badguys_ranged')
local siege = unit(3290,1000,'npc_dota_badguys_siege')
local own = unit(2780,1000,'npc_dota_creep_goodguys_melee')
local escort = unit(2800,1000,'npc_dota_creep_goodguys_ranged')
local state = {members = {lead,mate,mate2,bot,alt}, hostile = {close,ranged,siege}, friendly = {own,escort}, now = 1200}
local env
local J = {
    IsValid = function(u) return u and not u.dead end, IsValidHero = function(u) return u and not u.dead end,
    GetHP = function(u) return u.hp or 0.9 end, GetPosition = function(u) return u.role end,
    IsMeepoClone = no, IsDisabled = no, IsRetreating = no, IsInTeamFight = no, IsGoingOnSomeone = no,
    IsDefending = no, IsDoingRoshan = no, IsDoingTormentor = no, IsPushing = function(u) return u.mode == 12 end,
    CanCommitToLaneTeleport = function(_, p) return not state.danger or not state.danger(p) end,
    GetLocationToLocationDistance = distance, GetAlliesNearLoc = function() return {lead,mate,mate2} end,
    GetEnemiesNearLoc = function() return {} end,
    AdjustLocationWithOffsetTowardsFountain = function(p,n) return pos(p.x-n,p.y) end,
}
env = setmetatable({
    J=J, team=2, bot=bot, nLaneList={1,2,3}, Vector=pos, LANE_TOP=1, LANE_MID=2, LANE_BOT=3,
    TEAM_RADIANT=2, GetOpposingTeam=function() return 3 end,
    BOT_MODE_PUSH_TOWER_TOP=11,BOT_MODE_PUSH_TOWER_MID=12,BOT_MODE_PUSH_TOWER_BOT=13,
    BOT_MODE_ATTACK=15,BOT_MODE_TEAM_ROAM=16, UNIT_LIST_ENEMY_CREEPS=1,UNIT_LIST_ALLIED_CREEPS=2,
    GetTeamPlayers=function() return state.members end,GetTeamMember=function(i) return state.members[i] end,
    GetLaneFrontLocation=function(_,lane) return ({top,mid,bottom})[lane] end,
    GetAncient=function(team) return team == 2 and pos(0) or pos(10000) end,
    GetUnitList=function(kind) return kind == 1 and state.hostile or state.friendly end,
    GetAmountAlongLane=function(lane,p) return {amount=p.x/10000,distance=math.abs(p.y-({1000,0,-2200})[lane])} end,
    DotaTime=function() return state.now end,GetUnitToUnitDistance=distance,GetUnitToLocationDistance=distance,
    IsLocationPassable=yes,IsLocationVisible=yes,
    AttackFarmTarget=function(target) state.attack=target end,MoveToFarm=function(p) state.move=p end,
}, {__index=_G})
local plan, returnPoint, attack = setfenv(assert(loadstring(source:sub(start,finish-1)
    .. '\nreturn GetRallySideWavePlan, GetSideWaveReturnPoint, AttackSideWave')),env)()
local chosen = assert(plan(), 'one nearby non-core prepares our top wave while three allies remain mid')
assert(chosen.lane == 1 and chosen.mainLane == 2 and #chosen.targetPack == 3)
assert(attack(chosen) and state.attack == siege, 'fast push kills the enemy siege creep first')
env.bot = alt
assert(plan() == nil, 'do not send a second bot to the same or a competing side wave')
env.bot = bot
alt.ohaRallySideWave = {expires=state.now+5}
assert(plan() == nil, 'an existing side-wave assignment reserves the slot')
alt.ohaRallySideWave = nil
state.friendly = {own}
assert(plan() == nil, 'do not leave to clear where no friendly wave can carry the push')
state.friendly = {own,escort}
state.danger = function(p) return p.x >= 4700 end
assert(plan() == nil, 'cancel side work when opponents arrive at the rally')
state.danger = nil
mate2.mode = 15
assert(plan() == nil, 'do not leave as the rally turns into an active fight')
mate2.mode = 12
assert(returnPoint({rally=lead}).x == 4475, 'regroup behind the anchor rather than continuing down the side lane')
state.danger = function(p) return p.x > 4200 end
assert(returnPoint({rally=lead}) == nil, 'do not issue a forced return through unsafe ground')
state.danger = nil
lead.role,mate2.role = 4,5
assert(plan() == nil, 'do not peel a teammate when the main group lacks a damage core')
print('PASS: bounded rally side wave, single assignment and priority return')
