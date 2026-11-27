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
local danger, cover, attack, objective = false,true,true,true
foe.target=tower
bot._defend={waveClearLane=2,waveClearTower=tower}
bot.ohaOuterTowerHoldUntil=1001
local now=1000
local j={
    IsValidHero=function(u) return u and u~=tower end, GetHP=function(u) return u.hp end,
    IsSuspiciousIllusion=no, CanBeAttacked=yes, IsDefending=yes, IsDisabled=no, IsRetreating=no,
    IsValidBuilding=function(u) return objective and u==tower end,
    GetAvailableFightAllies=function() return cover and 1 or 0 end,
    GetEnemiesNearLoc=function(point, radius) return point==0 and attack and {foe} or (danger and {foe,foe} or {}) end,
    IsInRange=function(a,b,n) return math.abs(a.x-b.x)<=n end,
    GetAlliesNearLoc=function() return {bot,ally} end, GetOuterTowerThreat=function() return {waveSize=0,eta=0} end,
    GetNumOfAliveHeroes=function(enemy) return enemy and 2 or 4 end,
    AdjustLocationWithOffsetTowardsFountain=function(point, offset) return point-offset end,
    CanCommitToLaneTeleport=yes, GetPosition=function() return 2 end,
    Utils={GetCachedVars=function() end, SetCachedVars=no},
}
local env=setmetatable({J=j, LANE_MID=2, TOWER_MID_3=31, BARRACKS_MID_MELEE=10,
    DotaTime=function() return now end, GetUnitToLocationDistance=function(a,x) return math.abs(a.x-x) end,
    GetTower=function() end, GetBarracks=function() return tower end,
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
extract('function J.GetExposedMidCover','local function GetOuterTowerHoldPoint',env)
local guard, building, reach=j.GetExposedMidCover(2)
assert(guard==bot and building==tower and reach==1000, 'retain exactly one nearby clearer in the won-fight window')
objective=false
assert(not j.GetExposedMidCover(2),'release after the threatened structure falls')
print('PASS: active safe mid defender poke and exposed-mid post-fight cover')
