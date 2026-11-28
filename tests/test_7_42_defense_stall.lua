local f = assert(io.open('bots/FunLib/jmz_func.lua','rb'))
local source = f:read('*a'); f:close()
local a = assert(source:find('function J.RunOuterTowerHold',1,true))
local b = assert(source:find('function J.GetTowerDefenseTarget',a,true))
local function yes() return true end
local function no() return false end
local function empty() return {} end
local function gap(a,b) return math.abs(a-b) end
local bot = {x=-800, order=nil}
local creep = {x=-75, CanBeSeen=yes, GetUnitName=function() return 'npc_dota_creep_badguys_ranged' end}
local busy, teleport, unsafe, hostileAtHold = false,false,false,false
creep.GetLocation = function() return creep.x end
bot.GetLocation = function() return bot.x end
bot.GetAttackRange = function() return 700 end
bot.GetNearbyCreeps = empty
bot.GetNearbyLaneCreeps = function(_, range) return gap(bot.x,creep.x)<=range and {creep} or {} end
bot.HasModifier = function(_,name) return teleport and name=='modifier_teleporting' end
bot.WasRecentlyDamagedByAnyHero = no
bot.IsUsingAbility = function() return busy end
bot.IsCastingAbility, bot.IsChanneling, bot.IsRooted, bot.IsDisarmed = no,no,no,no
bot.GetAttackTarget = function() end
bot.Action_AttackUnit = function(_,target) assert(target==creep); bot.order='attack' end
bot.Action_MoveToLocation = function(_,point) bot.order=point end
local foe1,foe2={},{}
local j = {IsValid=function(u) return u==creep end, IsValidHero=no, CanBeAttacked=yes, GetHP=function() return 0.9 end,
    IsInRange=function(a,b,r) return gap(a.x,b.x)<=r end, GetLastSeenEnemiesNearLoc=empty, GetAlliesNearLoc=empty,
    GetEnemiesNearLoc=function() return hostileAtHold and {foe1,foe2} or {} end,
    AdjustLocationWithOffsetTowardsFountain=function(x,d) return x-d end,
    GetLocationToLocationDistance=gap, GetMidDefensePokeTarget=no,
    VectorTowards=function(a,b,d) return b>a and a+d or a-d end,
    CanCommitToLaneTeleport=function() return not unsafe end}
local e=setmetatable({J=j, GetOuterTowerHoldPoint=function() return -800 end,
    IsLocationPassable=yes, IsLocationVisible=yes,
    GetUnitToLocationDistance=function(a,x) return gap(a.x,x) end,
    GetUnitToUnitDistance=function(a,b) return gap(a.x,b.x) end},{__index=_G})
setfenv(assert(loadstring(source:sub(a,b-1))),e)()
assert(j.RunOuterTowerHold(bot,0,1200,false,-800) and bot.order==-745,'only take the small step to enable the attack')
bot.x,bot.order=bot.order,nil
assert(j.RunOuterTowerHold(bot,0,1200,false,-800) and bot.order=='attack','next tick attacks instead of ordering a return to the hold point')
bot.x,bot.order,unsafe=-800,nil,true
assert(not j.RunOuterTowerHold(bot,0,1200,false,-800) and not bot.order,'do not step into danger')
unsafe=false
assert(not j.RunOuterTowerHold(bot,0,1200,true,-800) and not bot.order,'backup does not leave position for farm')
busy=true
assert(not j.RunOuterTowerHold(bot,0,1200,false,-800) and not bot.order,'the creep is not a reason to interrupt a cast')
busy,teleport,hostileAtHold=false,true,true
assert(not j.RunOuterTowerHold(bot,0,1200,false,-800) and not bot.order,'do not interrupt a teleport')
teleport=false
assert(j.RunOuterTowerHold(bot,0,1200,false,-800) and bot.order==-1000,'once free, an unsafe hold still yields a retreat order')
bot.x, bot.order=-1450,nil
assert(j.RunOuterTowerHold(bot,0,1200,false,-1450) and bot.order==-2050,
    'retreat farther behind a deep stage, not back toward the tower')
hostileAtHold,bot.order,bot.x=false,nil,-800
creep.CanBeSeen=no
assert(not j.RunOuterTowerHold(bot,0,1200,false,-800) and not bot.order,'do not move toward a creep in fog')
print('PASS: staged defender takes a bounded, safe step and shoots without dropping a cast or TP')

do
    local tower={x=0}
    j.GetAssignedOuterTower=function() return tower end
    j.GetAvailableFightAllies=function() return 1 end
    j.GetVisibleThreatAt=function() return 80 end
    bot.GetHealth=function() return 1000 end
    creep.GetAttackTarget=function() return tower end
    creep.CanBeSeen=yes
    bot.x,bot.order=-450,nil
    assert(j.RunOuterTowerHold(bot,0,1200,false,-1000) and bot.order=='attack',
        'on landing, hit the creep already attacking this tower before walking back to the rally')
    j.GetVisibleThreatAt=function() return 450 end
    bot.order=nil
    assert(j.RunOuterTowerHold(bot,0,1200,false,-1000) and bot.order==-1000,
        'fall back when standing still for the attack is unsafe')
end

do
    local hero = {x=0, GetActiveMode=function() return 0 end, IsAlive=yes, HasModifier=no,
        GetUnitName=function() return 'npc_dota_hero_test' end, GetTeam=function() return 2 end,
        GetHealth=function() return 500 end, GetHealthRegen=function() return 0 end,
        GetManaRegen=function() return 0 end, GetLevel=function() return 12 end,
        GetLocation=function() return 0 end, GetNearbyLaneCreeps=empty,
        GetActualIncomingDamage=function(_, damage) return damage end}
    local function attacker(name, damage)
        return {visible=true, target=hero, x=300, GetUnitName=function() return name end,
            GetAttackTarget=function(self) return self.target end, IsDisarmed=no, HasModifier=no,
            GetTeam=function() return 3 end, GetAttackRange=function() return 700 end,
            GetAttackDamage=function() return damage end, GetSecondsPerAttack=function() return 1 end,
            CanBeSeen=function(self) return self.visible end}
    end
    local ward, tower = attacker('npc_dota_shadow_shaman_ward_1', 60), attacker('enemy_tower', 50)
    hero.GetNearbyTowers=function(_, _, enemy) return enemy and {tower} or {} end
    local j={ShouldRetreatFromEnemyReinforcements=no, GetModifierTime=function() return 0 end,
        GetHP=function() return 0.65 end, GetMP=function() return 1 end, GetProperTarget=no,
        IsValid=function(u) return u==ward and u.visible end, IsValidHero=no, IsValidBuilding=function(u) return u==tower end,
        IsInRange=function(u,v,r) return math.abs(u.x-v.x)<=r end, GetSideLaneYieldPoint=nil,
        ShouldPreserveCoreFightTrade=yes}
    local env=setmetatable({GetBot=function() return hero end, GetTeam=hero.GetTeam,
        GetOpposingTeam=function() return 3 end, GetAncient=no, GetDroppedItemList=empty,
        GetUnitList=function() return {ward,tower} end, GetScriptDirectory=function() return 'bots' end,
        require=function(name) return name:find('jmz_func') and j or {} end,
        BOT_MODE_DESIRE_ABSOLUTE=1, BOT_MODE_DESIRE_VERYHIGH=0.9, BOT_MODE_DESIRE_NONE=0}, {__index=_G})
    setfenv(assert(loadfile('bots/mode_retreat_generic.lua')),env)()
    assert(env.GetDesire()==1, 'focused ward and tower damage overrides the 0.96 high-ground hold')
    tower.target=ward
    assert(env.GetDesire()==0, 'a tower shooting another unit does not add damage')
    tower.target, ward.visible = hero, false
    assert(env.GetDesire()==0, 'a ward in fog does not add damage')
end

do
    local f=assert(io.open('bots/ability_item_usage_generic.lua','rb'))
    local src=f:read('*a'); f:close()
    local first=assert(src:find('function X.TraceDefenseMovement',1,true))
    local last=assert(src:find('function AbilityUsageThink()',first,true))
    local state={mode=1, attack=0, x=0}
    local logs={}
    local unit={GetLocation=function() return state.x end, GetLastAttackTime=function() return state.attack end,
        GetActiveMode=function() return state.mode end, GetCurrentActionType=function() return 0 end,
        GetAttackTarget=function() end, GetNearbyLaneCreeps=empty, IsChanneling=no}
    local env=setmetatable({bot=unit, botName='test', X={}, J={IsDefending=yes, GetLocationToLocationDistance=gap},
        print=function(line) logs[#logs+1]=line end}, {__index=_G})
    setfenv(assert(loadstring(src:sub(first,last-1))),env)()
    for t=0,20 do
        state.x=t%2*100
        if t==7 then state.mode=2 end
        env.X.TraceDefenseMovement(t)
    end
    assert(#logs==2 and logs[2]:find('since=0.00',1,true) and logs[2]:find('travel=2000 net=0',1,true))
    state.attack=21
    env.X.TraceDefenseMovement(21)
    assert(#logs==3 and logs[3]:find('auto-resumed',1,true))
end
