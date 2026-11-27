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
foe.target=tower
bot._defend={waveClearLane=2,waveClearTower=tower}
bot.ohaOuterTowerHoldUntil=1001
local now, enemiesAlive, reinforcement, wave = 1000, 2, 24, {waveSize=0,eta=0}
local j={
    IsValidHero=function(u) return u and u~=tower end, GetHP=function(u) return u.hp end,
    IsSuspiciousIllusion=no, CanBeAttacked=yes, IsDefending=yes, IsDisabled=no, IsRetreating=no,
    IsValidBuilding=function(u) return objective and u==tower end,
    GetAvailableFightAllies=function() return cover and 1 or 0 end,
    GetEnemiesNearLoc=function(point, radius) return point==0 and attack and {foe} or (danger and {foe,foe} or {}) end,
    IsInRange=function(a,b,n) return math.abs(a.x-b.x)<=n end,
    GetAlliesNearLoc=function() return {bot,ally} end, GetOuterTowerThreat=function() return wave end,
    GetNumOfAliveHeroes=function(enemy) return enemy and enemiesAlive or 4 end,
    AdjustLocationWithOffsetTowardsFountain=function(point, offset) return point-offset end,
    CanCommitToLaneTeleport=yes, GetPosition=function() return 2 end,
    GetEnemyReinforcementWindow=function() return reinforcement end,
    GetLocationToLocationDistance=function(a,b) return math.abs(a-b) end,
    VectorTowards=function(a,b,d) return a + (b >= a and d or -d) end,
    GetItem2=function() end, CanCastAbility=no,
    Utils={GetCachedVars=function() end, SetCachedVars=no},
}
local env=setmetatable({J=j, LANE_MID=2, TOWER_MID_3=31, BARRACKS_MID_MELEE=10,
    DotaTime=function() return now end, GetUnitToLocationDistance=function(a,x) return math.abs(a.x-x) end,
    GetTower=function() end, GetBarracks=function() return tower end, GetAncient=function() end,
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
extract('function J.GetPostFightCoverage','local function GetOuterTowerHoldPoint',env)
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
