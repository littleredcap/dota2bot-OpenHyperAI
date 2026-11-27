local function yes() return true end
local function no() return false end
local f=assert(io.open('bots/FunLib/jmz_func.lua','rb'))
local src=f:read('*a'); f:close()
local function extract(a,b,env)
    local start=assert(src:find(a,1,true)); local stop=assert(src:find(b,start+1,true))
    return setfenv(assert(loadstring(src:sub(start,stop-1))),env)()
end
local function unit(x,hp,id)
    return {x=x,hp=hp,id=id, GetLocation=function(self) return self.x end,
        GetPlayerID=function(self) return self.id end, GetCurrentMovementSpeed=function() return 300 end,
        GetTeam=function() return 2 end, IsBot=yes, IsIllusion=no, IsInvulnerable=no, IsChanneling=no,
        HasModifier=no, WasRecentlyDamagedByAnyHero=no, GetAttackTarget=function(self) return self.target end,
        GetAttackRange=function(self) return self.range or 150 end}
end
local bot, ally, tower, foe = unit(-700,.86,1),unit(-840,.85,2),unit(0,1,8),unit(0,.72,11)
local danger, cover, attack, objective, incoming = false,true,true,true,{}
local towers, secondWave = {}, nil
foe.target=tower
bot._defend={waveClearLane=2,waveClearTower=tower}
bot.ohaOuterTowerHoldUntil=1001
local now, enemiesAlive, reinforcement, wave = 1000, 2, 24, {waveSize=0,eta=0}
local j={
    IsValidHero=function(u) return u and u~=tower end, GetHP=function(u) return u.hp end,
    IsSuspiciousIllusion=no, CanBeAttacked=yes, IsDefending=yes, IsDisabled=no, IsRetreating=no,
    IsValidBuilding=function(u) return objective and (u==tower or u and u.structure) end,
    GetAvailableFightAllies=function() return cover and 1 or 0 end,
    GetEnemiesNearLoc=function(point, radius) return point==0 and attack and {foe} or (danger and {foe,foe} or {}) end,
    IsInRange=function(a,b,n) return math.abs(a.x-b.x)<=n end,
    GetAlliesNearLoc=function() return {bot,ally} end, GetOuterTowerThreat=function(b) return b==tower and wave or secondWave end,
    GetNumOfAliveHeroes=function(enemy) return enemy and enemiesAlive or 4 end,
    AdjustLocationWithOffsetTowardsFountain=function(point, offset) return point-offset end,
    CanCommitToLaneTeleport=yes, GetPosition=function() return 2 end,
    GetEnemyReinforcementWindow=function() return reinforcement end,
    GetLocationToLocationDistance=function(a,b) return math.abs(a-b) end,
    VectorTowards=function(a,b,d) return a + (b >= a and d or -d) end,
    GetItem2=function() end, CanCastAbility=no,
    Utils={GetCachedVars=function() end, SetCachedVars=no},
}
local env=setmetatable({J=j, LANE_MID=2, TOWER_MID_3=23, BARRACKS_MID_MELEE=10,
    DotaTime=function() return now end, GetUnitToLocationDistance=function(a,x) return math.abs(a.x-x) end,
    GetTower=function(_,id) return towers[id] end, GetBarracks=function(_,id) return id==10 and tower or nil end,
    GetAncient=function() end, LANE_TOP=1, LANE_BOT=3,
    TOWER_TOP_1=11,TOWER_TOP_2=12,TOWER_TOP_3=13,TOWER_MID_1=21,TOWER_MID_2=22,
    TOWER_BOT_1=31,TOWER_BOT_2=32,TOWER_BOT_3=33,BARRACKS_MID_RANGED=20,
    BARRACKS_TOP_MELEE=30,BARRACKS_TOP_RANGED=34,BARRACKS_BOT_MELEE=35,BARRACKS_BOT_RANGED=36,
    GetIncomingTeleports=function() return incoming end, TOWER_BASE_1=40, TOWER_BASE_2=41,
    GetWaveClearScore=function(u) return u==bot and 400 or 220,1000,250 end}, {__index=_G})
extract('local function GetCoveredMidPokeTarget','function J.RunOuterTowerHold',env)
assert(j.GetMidDefensePokeTarget(bot,800)==foe,'a ranged defender at a protected point can hit a visible tower attacker')
assert(not j.GetMidDefensePokeTarget(bot,650),'never issue a poke that requires walking into range')
foe.range=610
assert(not j.GetMidDefensePokeTarget(bot,800),'avoid trading into enemy attack range')
foe.range=150
cover=false
assert(not j.GetMidDefensePokeTarget(bot,800),'do not poke without another available defender')
cover,danger=true,true
assert(not j.GetMidDefensePokeTarget(bot,800),'do not poke into a group already at the defender')
danger=false
env.LaneTeleportPolicy = dofile('bots/FunLib/lane_teleport_policy.lua')
extract('local function BuildDefenseLanePlan','local function GetOuterTowerHoldPoint',env)
local spare=unit(-1000,.90,3)
local guard, building, reach=j.GetExposedMidCover(2)
assert(guard==bot and building==tower and reach==1000, 'retain one nearby clearer when the window is safe')
assert(j.CanTakePostFightTrip(spare,6500,true), 'other heroes are not locked at base')
assert(not j.CanTakePostFightTrip(bot,6500,true), 'the incumbent may not cash out the defensive TP')

enemiesAlive, reinforcement, wave = 4, 1, {waveSize=3,eta=5,count=2}
local plan=j.GetPostFightCoverage(2)
assert(plan.deadline == 6 and plan.needsBackup and plan.backup.hero==ally,'react to the visible counterpush plus imminent reinforcements')
assert(not j.CanTakePostFightTrip(ally,6500,true),'the only backup cannot spend the escape route')
assert(j.CanTakePostFightTrip(spare,6500,true),'the remaining offense is allowed while both duties are covered')
ally.x=-4000
assert(not j.CanTakePostFightTrip(spare,6500,true),'do not leave when the backup could not return')
assert(j.CanTakePostFightTrip(spare,-1300,false),'nearby activity is permitted despite the narrow window')
ally.HasModifier=function(_,name) return name=='modifier_teleporting' end
incoming={{playerid=ally.id,location=-750,time_remaining=2.5}}
assert(j.GetPostFightCoverage(2).backup.hero==ally,'an actual inbound backup keeps its assignment')
assert(not j.CanTakePostFightTrip(spare,6500,true),'an inbound backup is not already at the line')
incoming={}
ally.HasModifier=no

reinforcement, enemiesAlive, wave = 24, 2, {waveSize=0,eta=0}
bot.x, ally.x = -1700, -3600
assert(not j.CanTakePostFightTrip(spare,6500,true),'ticket to arrive is not actual coverage')
ally.x=-760
assert(j.GetExposedMidCover(2)==ally,'handoff occurs after another clearer actually reaches the line')
assert(j.CanTakePostFightTrip(spare,6500,true),'reopen conversion after confirmed handoff')
wave={waveSize=1,eta=0,underAttack=true,count=0}
assert(j.GetPostFightCoverage(2).backup==nil,'a single unescorted creep does not recall the backup')
danger=true
assert(not j.GetExposedMidCover(2),'no assignment into an already overrun hold point')
danger=false
objective=false
assert(not j.GetExposedMidCover(2) and j.CanTakePostFightTrip(spare,6500,true),'release if no vulnerable objective remains')
print('PASS: shared post-fight cover protects the return budget, validates handoff, and preserves safe conversion')

do
    objective=true
    wave={waveSize=3,eta=5,count=2}
    local outer, rear = unit(5200,1,9), unit(3600,1,10)
    outer.structure,rear.structure=true,true
    outer.GetHealth=function() return 60 end
    rear.GetHealth=function() return 1000 end
    towers[env.TOWER_TOP_1],towers[env.TOWER_TOP_2]=outer,rear
    secondWave={waveSize=4,eta=0,count=3,underAttack=true,damageRate=40}
    bot.x, ally.x=-760,3050
    local plan=j.GetPostFightCoverage(2)
    assert(#plan.lanes==2 and plan.lanes[1].lane==env.LANE_TOP and plan.lanes[1].building==rear,
        'transfer a doomed outer front to the rear tower regardless of lane identity')
    assert(plan.lanes[1].primary.hero==ally and plan.lanes[2].primary.hero==bot,
        'two credible fronts recruit distinct clearers, never assign one hero twice')
end
print('PASS: generic simultaneous top and mid deadlines allocate two defenders and skip a doomed tower')

do
    local outer = unit(3000,0.60,9)
    outer.structure = true
    outer.GetHealth = function() return 600 end
    towers = {[env.TOWER_TOP_1]=outer}
    secondWave={waveSize=4,eta=0,count=3,underAttack=true,damageRate=100}
    wave={waveSize=3,eta=5,count=2}
    local heroes = j.GetAlliesNearLoc
    j.GetAlliesNearLoc = function() return {bot} end
    bot.x = 0
    local plan = j.GetPostFightCoverage(2)
    assert(plan.lanes[1].lane==env.LANE_TOP and not plan.lanes[1].primary
        and plan.lanes[2].primary.hero==bot, 'a missed deadline must not block another reachable lane')
    bot.x = 2400
    plan = j.GetPostFightCoverage(2)
    assert(plan.lanes[1].primary.hero==bot and not plan.lanes[2].primary,
        'the highest-priority lane still takes the only clearer if on time')
    j.GetAlliesNearLoc = heroes
end
print('PASS: an impossible first response does not steal a timely second-lane defender')

do
    local function v(x) return {x=x,y=0} end
    local function u(x,id,wealth)
        local hero=unit(x,.9,id)
        hero.GetLocation=function(self) return v(self.x) end
        hero.GetNetWorth=function() return wealth end
        return hero
    end
    local strong, recovering, injured=u(1300,1,10500),u(1450,2,4500),u(4650,3,9500)
    injured.hp=.35
    local function c(x)
        return {CanBeSeen=yes,GetLocation=function() return v(x) end,
            GetUnitName=function() return 'npc_dota_creep_enemy_ranged' end}
    end
    local roster={strong,recovering,injured}
    j.IsInLaningPhase, j.IsGoingOnSomeone, j.IsDoingRoshan, j.IsDoingTormentor=no,no,no,no
    j.IsInAllyArea,j.IsCore,j.IsValid=yes,yes,yes
    j.GetAlliesNearLoc=function() return roster end
    j.GetEnemiesNearLoc,j.GetLastSeenEnemiesNearLoc=function() return {} end,function() return {} end
    j.GetPostFightDuty=function() return nil end
    j.CanTakePostFightTrip=yes
    j.GetLocationToLocationDistance=function(a,b) return math.abs(a.x-b.x) end
    j.VectorTowards=function(a,b,d) return v(a.x+(b.x>=a.x and d or -d)) end
    env.GetUnitToLocationDistance=function(a,p) return math.abs(a.x-p.x) end
    env.GetUnitList=function() return {c(1700),c(1730),c(1760),c(3900),c(3925)} end
    assert(j.GetScheduledFarmWaveOwner(strong,v(1700))==recovering.id,'prefer the recovering but still timely core')
    assert(j.GetScheduledFarmWaveOwner(recovering,v(3900))==strong.id,'assign the other wave to a distinct healthy core')
    j.GetPostFightDuty=function(hero) return hero==recovering and 'clear' or nil end
    assert(j.GetScheduledFarmWaveOwner(strong,v(1700))==strong.id,'defensive coverage outranks a farm grant')
end
print('PASS: opponent-neutral resource assignments prefer timely recovering cores without double claims')
