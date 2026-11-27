local function yes() return true end
local function no() return false end
local function v(x, y, z) return {x=x, y=y, z=z or 0} end
local function dist(a,b) return math.sqrt((a.x-b.x)^2+(a.y-b.y)^2) end
local file = assert(io.open('bots/FunLib/jmz_func.lua', 'rb'))
local source = file:read('*a')
file:close()
local first = assert(source:find('function J.IsHighGroundResponseThreat(', 1, true))
local last = assert(source:find('-- Explicit, conservative roster knowledge.', first, true))
local bot = {GetLocation=function() return v(0,0) end, GetCurrentMovementSpeed=function() return 300 end,
    WasRecentlyDamagedByAnyHero=no}
local function enemy(x, y)
    return {GetLocation=function() return v(x,y) end, GetPlayerID=function() return 3 end,
        GetAttackRange=function() return 550 end}
end
local function tower(x, y) return {GetLocation=function() return v(x,y) end} end
local seen, lastSeen, blocked = {}, {}, false
local j = {GetEnemiesNearLoc=function() return seen end, GetLastSeenEnemiesNearLoc=function() return lastSeen end,
    IsValidHero=yes, IsSuspiciousIllusion=no, GetLocationToLocationDistance=dist, GetHP=function() return 0.9 end,
    IsValidBuilding=yes, AdjustLocationWithOffsetTowardsFountain=function(p) return v(p.x+240,p.y) end,
    CanCommitToLaneTeleport=function(_, p) return p.y ~= 350 end}
local env = setmetatable({J=j, Vector=v, IsLocationPassable=function(p) return not blocked or p.x ~= 1200 end,
    GetHeroLastSeenInfo=function() return {{location=v(1800,600)}} end,
    GetUnitToLocationDistance=function(unit, point) return dist(unit:GetLocation(),point) end}, {__index=_G})
setfenv(assert(loadstring(source:sub(first,last-1))),env)()
assert(j.IsHighGroundResponseThreat({count=3,waveSize=3,eta=8}), 'react before first hit')
assert(j.IsHighGroundResponseThreat({count=3,waveSize=1,siegeAttacking=true}), 'already attacking summons count')
assert(not j.IsHighGroundResponseThreat({count=1,waveSize=6,eta=1}), 'do not mass recall for one hero and creeps')
assert(not j.IsHighGroundResponseThreat({count=3,waveSize=0,eta=0}), 'do not mass recall for an unescorted sighting')
local stage = v(4800, 0)
local direct = j.GetHighGroundWalkPoint(bot, stage)
assert(direct == stage, 'do not detour around an empty corridor')
blocked = true
assert(j.GetHighGroundWalkPoint(bot, stage) ~= stage, 'blocked intermediate terrain is not a clear line')
blocked = false
seen = {enemy(2200, 0)}
local turn = j.GetHighGroundWalkPoint(bot, stage)
assert(turn and turn.y ~= 0, 'do not route 29-minute return straight through a seen enemy')
seen, lastSeen = {}, {4}
turn = j.GetHighGroundWalkPoint(bot, stage)
assert(turn and turn.y <= 0 and turn ~= stage, 'recent sighting forces a different corridor')
seen, lastSeen = {enemy(300,0)}, {}
assert(j.GetHighGroundWalkPoint(bot, stage) == nil, 'hold unsafe walk when the hero starts under threat')
seen = {}
local tp = j.GetHighGroundResponseTeleport(bot, stage, {tower(4460,350), tower(4100,0)})
assert(tp and tp.x == 4340, 'safe TP can beat a 4800-unit walk; reject contested closer landing')
assert(j.GetHighGroundResponseTeleport(bot, v(1000,0), {tower(760,0)}) == nil, 'do not TP when walking is faster')
bot.WasRecentlyDamagedByAnyHero = yes
assert(j.GetHighGroundResponseTeleport(bot, stage, {tower(4100,0)}) == nil, 'do not channel in danger')
print('PASS: early high-ground response reacts to real escorts, avoids unsafe routes, and compares TP arrival')
