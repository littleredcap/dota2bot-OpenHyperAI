local f = assert(io.open('bots/FunLib/jmz_func.lua','rb'))
local src=f:read('*a');f:close()
local a=assert(src:find('function J.GetSideLaneReturnPoint',1,true))
local b=assert(src:find('function J.GetLaningManaShortfall',a,true))
local noop=function() return false end
local function empty() return {} end
local function toward(a,b,d) return a + (b>=a and d or -d) end
local function entity(x,name)
    return {x=x, GetLocation=function(self) return self.x end,
        GetUnitName=function() return name or 'npc_dota_creep_test_melee' end,
        CanBeSeen=function(self) return not self.hidden end}
end
local bot=entity(200)
local ally=entity(1700)
local tower=entity(0)
local wave=entity(2250)
local cover=entity(2000)
local attacker={}
local state={hp=0.9}
local function distance(a,b) return math.abs(a-b) end
local function hostile(x,r) return state.enemy and distance(x,state.enemy)<r and {attacker} or {} end
bot.DistanceFromFountain=function() return 4500 end
bot.WasRecentlyDamagedByAnyHero=function() return state.hit end
bot.HasModifier,ally.HasModifier=noop,noop
bot.GetTeam=function() return 2 end
bot.GetAttackRange=function() return 150 end
local j={IsInLaningPhase=function() return true end,IsCore=function() return true end,
    GetHP=function(unit) return unit==bot and state.hp or 0.9 end,
    IsDisabled=noop, IsValidBuilding=function(x) return x==tower end, IsValid=function(x) return x~=nil end,
    IsValidHero=function(x) return x==ally end, GetLanePartner=function() return ally end,
    IsRetreating=noop, GetLocationTowardDistanceLocation=toward,VectorTowards=toward,
    GetLocationToLocationDistance=distance,GetEnemiesNearLoc=hostile,
    GetLastSeenEnemiesNearLoc=hostile}
local env=setmetatable({J=j,LANE_TOP=1,LANE_BOT=2,TOWER_TOP_1=1,TOWER_BOT_1=2,
    UNIT_LIST_ENEMY_CREEPS=1,UNIT_LIST_ALLIED_CREEPS=2,DotaTime=function() return 300 end,
    GetUnitList=function(k) return k==1 and {wave} or {cover} end,
    GetTower=function(team) return team==2 and tower or nil end,GetOpposingTeam=function() return 3 end,
    GetLaneFrontLocation=function() return wave.x end,GetAmountAlongLane=function() return {distance=0} end,
    GetUnitToUnitDistance=function(a,b) return distance(a.x,b.x) end,
    GetUnitToLocationDistance=function(a,b) return distance(a.x,b) end,
    IsLocationPassable=function() return true end,IsLocationVisible=function() return not state.fog end},
    {__index=_G})
setfenv(assert(loadstring(src:sub(a,b-1))),env)()
assert(j.GetSideLaneReturnPoint(bot,1)==1750,'walk back to a screened wave before the last-hit scan can see it')
state.enemy=1750
local fallback=j.GetSideLaneReturnPoint(bot,1)
assert(fallback and fallback<=1125 or fallback==nil,'threat makes the move smaller or aborts it')
state.enemy=nil;state.hit=true
assert(not j.GetSideLaneReturnPoint(bot,1),'cannot override a live retreat')
state.hit=false;wave.hidden=true
assert(not j.GetSideLaneReturnPoint(bot,1),'do not use hidden wave coordinates')
wave.hidden=false;state.fog=true
assert(not j.GetSideLaneReturnPoint(bot,1),'no commitment into a blind endpoint')
print('PASS: side core reconnects to a visible wave, but not through live threat or fog.')
