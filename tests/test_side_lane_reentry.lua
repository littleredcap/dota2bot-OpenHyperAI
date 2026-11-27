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
bot.DistanceFromFountain=function() return state.fountainDistance or 4500 end
bot.WasRecentlyDamagedByAnyHero=function() return state.hit end
bot.HasModifier,ally.HasModifier=noop,noop
bot.GetTeam=function() return 2 end
bot.GetAttackRange=function() return 150 end
local j={IsInLaningPhase=function() return true end,IsCore=function() return true end,
    GetHP=function(unit) return unit==bot and state.hp or 0.9 end,
    GetMP=function() return state.mp or 1 end,
    IsDisabled=noop, IsValidBuilding=function(x) return x==tower end, IsValid=function(x) return x~=nil end,
    IsValidHero=function(x) return x==ally end, GetLanePartner=function() return ally end,
    IsRetreating=noop, GetLocationTowardDistanceLocation=function(unit,b,d) return toward(unit:GetLocation(),b,d) end,VectorTowards=toward,
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
state.fountainDistance, state.hp, state.mp = 200, 0.99, 0.9
assert(j.GetSideLaneReturnPoint(bot,1)==1750,'a healed side core can start the safe return inside the fountain radius')
state.mp=0.5
assert(not j.GetSideLaneReturnPoint(bot,1),'wait for mana before leaving the fountain')
state.mp, state.hp=0.9,0.75
assert(not j.GetSideLaneReturnPoint(bot,1),'wait for health before leaving the fountain')
state.fountainDistance, state.hp=nil,0.9
state.enemy=1750
local fallback=j.GetSideLaneReturnPoint(bot,1)
assert(fallback and fallback<=1125 or fallback==nil,'threat makes the move smaller or aborts it')
state.enemy=nil;state.hit=true
assert(not j.GetSideLaneReturnPoint(bot,1),'cannot override a live retreat')
state.hit=false;wave.hidden=true
assert(not j.GetSideLaneReturnPoint(bot,1),'do not use hidden wave coordinates')
wave.hidden=false
-- Returning from a large detour can take a different but closer path
-- even when the selected staging point is farther from the bot itself.
bot.x=-7500
assert(j.GetSideLaneReturnPoint(bot,1)==1750,'favor progress toward the wave, not proximity to the bot')
bot.x=-1500
ally.x,cover.x=6000,6000
assert(j.GetSideLaneReturnPoint(bot,1)==0,'without a screen only return to the protected tower')
bot.x=200
ally.x,cover.x=1700,2000
state.fog=true
assert(not j.GetSideLaneReturnPoint(bot,1),'no commitment into a blind endpoint')
print('PASS: side core reconnects to a visible wave, but not through live threat or fog.')

-- Exercise the production choice of a small retreat versus a real retreat.
bot.GetAssignedLane=function() return 1 end
bot.GetCurrentMovementSpeed=function() return 300 end
bot.IsRooted=noop
bot.WasRecentlyDamagedByTower=noop
attacker.x=2100
attacker.GetAttackRange=function() return 300 end
j.IsSuspiciousIllusion=noop
j.IsValidHero=function(x) return x==ally or x==attacker end
state.fog=false
state.hp=0.58
bot.x=1800
assert(j.GetSideLaneYieldPoint(bot,{attacker})==1440,'break attack contact with one small backward step')
state.hp=0.35
assert(not j.GetSideLaneYieldPoint(bot,{attacker}),'a low core still commits to the real escape')
state.hp=0.59
state.fog=true
assert(not j.GetSideLaneYieldPoint(bot,{attacker}),'do not select a short retreat into fog')

do
    local health, enemiesAtWave, availableAllies, recentHit = 178, 2, 0, 13
    local position, waveFront, attackRange, lane = 0, 3082, 150, 3
    local function yes() return true end
    local function none() end
    local function constant(value) return function() return value end end
    local hero = {
        GetTeam=constant(2), GetAssignedLane=function() return lane end, GetActiveMode=constant(5), IsAlive=yes,
        GetUnitName=constant('npc_dota_hero_skeleton_king'), GetLevel=constant(4),
        GetHealth=function() return health end, GetMaxHealth=constant(980), GetHealthRegen=constant(5),
        GetMana=constant(205), GetMaxMana=constant(300), GetManaRegen=constant(1),
        GetLocation=function() return position end, DistanceFromFountain=constant(6000),
        GetNearbyTowers=empty, GetNearbyLaneCreeps=empty, GetNearbyCreeps=empty, GetNearbyBarracks=empty,
        GetAttackRange=function() return attackRange end, GetAttackDamage=constant(80),
        HasModifier=noop, IsChanneling=noop, IsUsingAbility=noop, IsCastingAbility=noop,
        WasRecentlyDamagedByAnyHero=function(_,seconds) return recentHit <= seconds end,
    }
    local j=setmetatable({
        Utils={HasModifierContainsName=noop}, IsCore=yes, IsInLaningPhase=yes,
        GetHP=function() return health/980 end, GetMP=constant(205/300),
        GetModifierTime=constant(0), GetEnemyList=empty, GetAllyList=empty, GetHeroesTargetingUnit=empty,
        GetNumOfAliveHeroes=constant(5), GetDistanceFromEnemyFountain=constant(15000),
        GetLaningHoldTower=none, GetSideLaneReturnPoint=none, GetSideLaneYieldPoint=none,
        GetLastSeenEnemiesNearLoc=function(point)
            assert(point==waveFront)
            local ids={}; for i=1,enemiesAtWave do ids[i]=i end; return ids
        end,
        GetAvailableFightAllies=function(_,point) assert(point==waveFront); return availableAllies end,
    },{__index=function() return noop end})
    local env=setmetatable({ GetBot=constant(hero),GetTeam=constant(2),GetOpposingTeam=constant(3),
        GetAncient=none, GetUnitList=empty, GetTeamPlayers=empty, GetDroppedItemList=empty,
        GetLaneFrontLocation=function(team,ln) assert(team==2 and ln==lane); return waveFront end,
        GetUnitToLocationDistance=function(u,point) return math.abs(u:GetLocation()-point) end,
        GetUnitToUnitDistance=constant(15000), Min=math.min, DotaTime=constant(242),
        GetScriptDirectory=constant('bots'), require=function(name) return name:find('jmz_func') and j or {} end,
        LANE_TOP=1, LANE_MID=2, LANE_BOT=3, BOT_MODE_LANING=5,
        BOT_MODE_DESIRE_NONE=0, BOT_MODE_DESIRE_MODERATE=0.5,BOT_MODE_DESIRE_VERYHIGH=0.9,BOT_MODE_DESIRE_ABSOLUTE=1,
    },{__index=_G})
    setfenv(assert(loadfile('bots/mode_retreat_generic.lua')),env)()
    assert(env.GetDesire()>=0.9,'continue recovery after leaving two opponents at the next wave with only 178/980 health')
    position,health=2600,257
    assert(env.GetDesire()>=0.9,'stay out of the same defended wave at 257/980')
    enemiesAtWave=0
    assert(env.GetDesire()<0.9,'a previously unsafe wave that has cleared does not force a retreat')
    enemiesAtWave,availableAllies=2,2
    assert(env.GetDesire()<0.9,'available allies already screening that wave allow ordinary lane decisions')
    availableAllies,health=0,500
    assert(env.GetDesire()<0.9,'a recovered core can return to normal lane selection')
    health,position=178,-2000
    assert(env.GetDesire()<0.9,'remote pressure in the assigned lane does not dictate movement across the map')
    position,lane=0,2
    assert(env.GetDesire()<0.9,'keep the usual mid-lane retreat decision')
    lane,attackRange=3,600
    assert(env.GetDesire()<0.9,'a ranged hero can use its ordinary spacing')
    attackRange,hero.IsChanneling=150,yes
    assert(env.GetDesire()<0.9,'do not replace an existing channel with the lane recovery decision')
end
