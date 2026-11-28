local function yes() return true end
local function no() return false end
local function none() return {} end
local now, danger, orders, threat = 510, false, {}, 0
local bot, core, foe, second, tower = {x=0,hp=0.33}, {x=200,hp=0.85}, {x=690}, {x=710}, {x=1650}
local me1, me2, friend = {x=370,name='npc_dota_creep_badguys_melee'}, {x=420,name='npc_dota_creep_badguys_melee'}, {x=-330}
local visible, allies = {foe,second}, {core}
local creeps = {me1,me2}
for _, u in ipairs({bot,core,foe,second,tower,me1,me2,friend}) do
    u.GetLocation=function(self) return self.x end
    u.GetAttackRange=function() return 150 end
    u.GetAttackTarget=function(self) return self.target end
    u.GetUnitName=function(self) return self.name end
    u.WasRecentlyDamagedByHero=function(self, enemy) return self.hitBy == enemy end
    u.HasModifier=function(self) return self.teleporting end
    u.IsInvulnerable, u.IsChanneling = no, no
end
bot.GetAssignedLane=function(self) return self.lane or 3 end
bot.GetTeam=function() return 2 end
bot.GetHealth=function(self) return self.hp * 1000 end
bot.GetNearbyLaneCreeps=function(_,_,hostile) return hostile and creeps or {friend} end
bot.WasRecentlyDamagedByAnyHero=no
bot.Action_AttackUnit=function(_, unit, once) assert(once); orders[#orders+1]={'attack',unit} end
bot.Action_MoveToLocation=function(_, point) orders[#orders+1]={'move',point} end
bot.Action_ClearActions=function() orders[#orders+1]={'clear'} end
local j = {
    GetHP=function(unit) return unit.hp end, IsRetreating=function(unit) return unit.retreat end,
    IsValidHero=function(unit) return unit==bot or unit==core or unit==foe or unit==second end,
    IsSuspiciousIllusion=no, CanCastOnMagicImmune=yes, CanBeAttacked=yes, IsDisabled=no,
    IsInRange=function(a,b,range) return math.abs(a.x-b.x)<=range end,
    GetAlliesNearLoc=function() return allies end, GetEnemiesNearLoc=function(point) return danger and visible or (point>=600 and visible or {}) end,
    GetLastSeenEnemiesNearLoc=none, IsValidBuilding=function(a) return a==tower end, IsInLaningPhase=yes,
    IsCore=function(u) return u==bot or u==core end, IsValid=function(u) return u~=nil end,
    AdjustLocationWithOffsetTowardsFountain=function(point,d) return point-d end, IsLaningUnderPressure=no,
    GetVisibleThreatAt=function() return threat end,
}
local f=assert(io.open('bots/FunLib/jmz_func.lua','rb'))
local source=f:read('*a'); f:close()
local env=setmetatable({J=j, LANE_TOP=1,LANE_MID=2,LANE_BOT=3, TOWER_MID_1=21,
    DotaTime=function() return now end, IsLocationPassable=yes, GetOpposingTeam=function() return 3 end,
    GetTower=function(_,index) if index==21 then return tower end end,
    GetAmountAlongLane=function() return {distance=0} end,
    GetUnitToLocationDistance=function(u,p) return math.abs(u.x-p) end}, {__index=_G})
local function extract(first,last)
    local i=assert(source:find(first,1,true)); local k=assert(source:find(last,i+1,true))
    setfenv(assert(loadstring(source:sub(i,k-1))),env)()
end
extract('function J.GetSupportCounterfightPoint','function J.GetAvailableFightAllies')
extract('function J.CanJoinObservedFightByTeleport','function J.GetTeamFightAlliesCount')
extract('function J.ShouldKeepMidOpportunity','function J.ShouldKeepLaningWave')
extract('function J.GetSideLaneCreepDrag','function J.GetLaningDenyTarget')
assert(j.GetSupportCounterfightPoint(bot,visible,800,150,0.4)==nil,'no lone emergency ultimate')
core.x=530
core.target=foe
assert(j.GetSupportCounterfightPoint(bot,visible,800,150,0.4)==foe.x,'cast when healthy core can counterattack')
core.retreat=true
assert(j.GetSupportCounterfightPoint(bot,visible,800,150,0.4)==nil,'do not cast for an ally already leaving')
core.retreat=false
assert(j.CanJoinObservedFightByTeleport(bot,690),'TP to the confirmed fight')
core.target=nil
assert(not j.CanJoinObservedFightByTeleport(bot,690),'do not TP to a group that stopped fighting')
bot.lane, bot.hp = 2, 0.9
assert(j.ShouldKeepMidOpportunity(bot,1),'keep control of an exposed mid wave')
assert(not j.ShouldKeepMidOpportunity(bot,2),'same lane travel uninhibited')
bot.lane=3
assert(j.RunSideLaneCreepDrag(bot,{foe},nil,false) and orders[1][1]=='attack','one fake attack with safely reachable creeps')
now=now+0.1
assert(j.RunSideLaneCreepDrag(bot,{foe},nil,true) and orders[2][1]=='move' and orders[2][2]==-330,
    'cancel on the next tick by moving back, never chase')
j.ObserveSideLaneCreepDrag(bot)
assert(bot.ohaLaneDragSample, 'an order by itself does not count as a pull')
me1.target, me1.x = bot, 295
j.ObserveSideLaneCreepDrag(bot)
assert(not bot.ohaLaneDragSample, 'observe a creep targeting the core and actually moving toward the retreat point')
me1.target, me1.x = nil, 370
assert(not j.RunSideLaneCreepDrag(bot,{foe},nil,false),'do not spam aggro')
now=now+6
assert(not j.RunSideLaneCreepDrag(bot,{foe}, {x=200},true),'a cancel-only pass must not start an attack')
assert(j.RunSideLaneCreepDrag(bot,{foe},nil,false))
danger=true
assert(j.RunSideLaneCreepDrag(bot,{foe},nil,true) and orders[#orders][1]=='clear','cancel if the retreat becomes unsafe')
danger, bot.hp, threat, now = false, 0.57, 60, now + 6
bot.WasRecentlyDamagedByAnyHero = yes
assert(j.GetSideLaneCreepDrag(bot,{foe},nil), 'a displaced wounded core can drag toward safety if retaliation is small')
threat = 90
assert(not j.GetSideLaneCreepDrag(bot,{foe},nil), 'a healthy retreat route alone cannot justify dangerous initial exposure')
bot.WasRecentlyDamagedByAnyHero = no
local home = {x=-400}
local isBuilding, getTower = j.IsValidBuilding, env.GetTower
env.TOWER_BOT_1 = 22
j.IsValidBuilding = function(unit) return unit == home or isBuilding(unit) end
env.GetTower = function(team, id)
    if team == 2 and id == 22 then return home end
    return getTower(team, id)
end
bot.hp, threat = 0.9, 0
assert(not j.GetSideLaneCreepDrag(bot,{foe},nil), 'keep a stable wave outside the allied tower')
j.IsValidBuilding, env.GetTower = isBuilding, getTower
extract('function J.GetTeamFightLocation','function J.CanJoinObservedFightByTeleport')
env.GetTeam = function() return 2 end
env.GetTeamPlayers = function() return {1,2} end
env.GetTeamMember = function(i) return i == 1 and bot or core end
bot.IsAlive, core.IsAlive = yes, yes
j.IsInTeamFight, j.GetEnemyCount = yes, function() return 2 end
j.GetSpecialModeAllies = function(member) return member == bot and {} or {core} end
j.GetCenterOfUnits = function(group) assert(#group > 0); return group[1].x end
assert(j.GetTeamFightLocation(bot) == core.x, 'skip the empty first group and keep scanning for a real fight')
j.GetSpecialModeAllies = none
assert(j.GetTeamFightLocation(bot) == nil, 'no zero-vector fight')
print('PASS: support counterfight, observed combat teleport, held mid wave and two-stage melee creep drag')

do
    local f = assert(io.open('bots/item_purchase_generic.lua','rb'))
    local buySource=f:read('*a'); f:close()
    local first=assert(buySource:find('local adaptiveCounters =',1,true))
    local last=assert(buySource:find('local function ',assert(buySource:find('local function PreferVisibleCounter',1,true))+40,true))
    local buyer={WasRecentlyDamagedByAnyHero=yes,IsSilenced=yes,GetLocation=function() return 0 end}
    local owned=false
    local j={GetPosition=function() return 5 end, GetHP=function() return 0.32 end,
        IsModeTurbo=no, GetEnemiesNearLoc=function() return {{}} end, GetUserHeroConfig=function() end}
    local env=setmetatable({J=j, bot=buyer, botName='npc_dota_hero_shadow_shaman', currentTime=1120,
        GAMEMODE_ARDM=22, GetGameMode=function() return 0 end, GetItemCost=function()return 2700 end,
        Role={IsPvNMode=no,IsAllShadow=no},
        Item={HasBuyBoots=yes,GetMissingPurchaseComponents=function(_, name)
            return {}, false, owned and name=='item_glimmer_cape'
        end},
        AdvancedItemStrategy={GetVisibleCounterItems=function() return {'item_pipe'} end}}, {__index=_G})
    local observe, prefer = setfenv(assert(loadstring(buySource:sub(first,last-1)
        .. '\n return ObserveCounterPressure, PreferVisibleCounter')),env)()
    local q={'item_pipe','item_glimmer_cape'}
    assert(not prefer(q) and q[2]=='item_glimmer_cape','do not let pipe displace the first save')
    observe()
    assert(not prefer({'item_guardian_greaves'}),'no automatic Disk for a single observation')
    env.currentTime=1135; observe()
    assert(not prefer({'item_guardian_greaves'}),'do not add Disk before an actual ally save is owned')
    owned=true
    local q={'item_guardian_greaves'}
    assert(prefer(q) and q[2]=='item_aeon_disk','make Disk situational after two observed burst-control events')
    assert(not prefer(q),'no duplicate Disk')
    print('PASS: first ally save is protected and Disk requires repeated observed burst control')
end
