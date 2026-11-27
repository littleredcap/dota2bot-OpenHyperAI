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
bot.IsCastingAbility, bot.IsChanneling, bot.IsRooted = no,no,no
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
