local NONE, HIGH = 0, 0.8
local function no() return false end
local function yes() return true end
local function empty() return {} end
local function one() return 1 end

local vector
local vectorOps = {
    __add = function(a, b) return vector(a.x + b.x, a.y + b.y) end,
    __sub = function(a, b) return vector(a.x - b.x, a.y - b.y) end,
    __mul = function(a, b) return vector(a.x * b, a.y * b) end,
}
vector = function(x, y) return setmetatable({x = x, y = y}, vectorOps) end
local function distance(a, b) return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2) end

local function heroAt(x, y, health)
    return {
        GetLocation = function(self) return self.location end,
        GetExtrapolatedLocation = function(self, delay)
            assert(delay >= 0.55, 'look beyond the bare cast point for allies')
            return self.predicted or self.location
        end,
        GetHealth = function() return health end,
        GetAttackRange = function(self) return self.range or 150 end,
        IsAttackImmune = no,
        IsDisarmed = no,
        HasModifier = no,
        location = vector(x, y),
    }
end

local aim = vector(500, 0)
local enemies, allies, orders = {}, {}, {}
local attackTarget, target
local teamfight, chasing = true, false
local now, cooldown = 1, 0
local spell = {
    GetName = function(self) return self.name end,
    IsFullyCastable = yes,
    IsHidden = no,
    IsNull = no,
    GetCastRange = function() return 800 end,
    GetCastPoint = function() return 0.35 end,
    GetAOERadius = function(self) return self.aoeRadius or 0 end,
    GetSpecialValueInt = function(_, name) return name == 'radius' and 400 or 4 end,
    GetSpecialValueFloat = function() return 4 end,
    GetCooldownTimeRemaining = function() return cooldown end,
    name = 'faceless_void_chronosphere',
}

local bot = heroAt(0, 0, 1000)
bot.GetAbilityByName = function() return spell end
bot.GetAttackDamage = function() return 170 end
bot.GetAttackSpeed = one
bot.GetCurrentMovementSpeed = function() return 300 end
bot.FindAoELocation = function() return { targetloc = aim } end
bot.SetTarget = function(_, unit) target = unit end
bot.Action_UseAbilityOnLocation = function(_, ability, location)
    orders[#orders + 1] = {ability, location}
end

local J = {
    Skill = {
        GetTalentList = empty, GetAbilityList = empty, GetRandomBuild = empty,
        GetTalentBuild = empty, GetSkillList = empty,
    },
    Item = {GetRoleItemsBuyList = function() return 'pos_1' end},
    Role = {IsPvNMode = no, IsAllShadow = no},
    Site = {
        GetDistance = distance,
        GetXUnitsTowardsLocation = function(unit, location, range)
            local origin = unit:GetLocation()
            return origin + (location - origin) * (range / distance(origin, location))
        end,
    },
    SetUserHeroInit = function(...) return ... end,
    CanNotUseAbility = no,
    GetProperTarget = function() return attackTarget end,
    GetCorrectLoc = function(unit) return unit.predicted or unit:GetLocation() end,
    IsValidHero = function(unit) return unit ~= nil end,
    IsValidTarget = function(unit) return unit ~= nil end,
    IsSuspiciousIllusion = no,
    IsDisabled = no,
    IsCore = function(unit) return unit.core == true end,
    IsInTeamFight = function() return teamfight end,
    IsGoingOnSomeone = function() return chasing end,
    IsRetreating = no,
    IsInRange = yes,
    CanCastOnMagicImmune = yes,
    CanKillTarget = function(unit, damage) return damage >= unit:GetHealth() end,
    IsLocationInChrono = no,
    IsLocationInBlackHole = no,
    IsLocationInArena = no,
    GetNearbyHeroes = empty,
    GetAlliesNearLoc = function() return allies end,
    GetEnemiesNearLoc = function(location, radius)
        local nearby = {}
        for _, enemy in ipairs(enemies) do
            if distance(location, enemy.location) <= radius then nearby[#nearby + 1] = enemy end
        end
        return nearby
    end,
}

local env = setmetatable({
    GetBot = function() return bot end,
    GetScriptDirectory = function() return 'bots' end,
    require = function() return J end,
    dofile = empty,
    GameTime = function() return now end,
    Vector = vector,
    BOT_ACTION_DESIRE_NONE = NONE,
    BOT_ACTION_DESIRE_HIGH = HIGH,
}, {__index = _G})
local hero = setfenv(assert(loadfile('bots/BotLib/hero_faceless_void.lua')), env)()
hero.ConsiderTimeWalkReverse = function() return NONE end
hero.ConsiderTimeWalk = function() return NONE end
hero.ConsiderTimeDilation = function() return NONE end

local function decide()
    orders, target = {}, nil
    hero.SkillsComplement()
    assert(#orders <= 1)
    return orders[1] and orders[1][2]
end

local sniper, tiny = heroAt(365, 0, 300), heroAt(635, 0, 800)
local mars, dazzle = heroAt(365, 0, 1100), heroAt(635, 0, 500)
enemies, allies = {sniper, tiny}, {bot, mars, dazzle}
assert(decide() == nil, 'hold a two-target Chronosphere when it would also freeze Mars and Dazzle')

allies = {bot}
assert(decide() == aim and target == sniper, 'use the clean default location and target the weaker enemy')

local durable = heroAt(365, 0, 1000)
enemies = {durable, tiny}
assert(decide() == nil, 'hold a multi-hero sphere when Void cannot finish and nobody can attack from outside')
local ranged = heroAt(500, 550, 650)
ranged.range = 650
allies = {bot, ranged}
assert(decide() == aim and target == tiny, 'a ranged ally in reach can follow up from outside')
enemies = {sniper, tiny}

mars.location = vector(500, 330)
allies = {bot, mars}
local location = assert(decide(), 'find an offset with both enemies and no Mars')
assert(location.y < 0 and distance(location, mars.location) > 400)
assert(distance(location, sniper.location) <= 400 and distance(location, tiny.location) <= 400)
assert(distance(location, bot.location) <= 800)

mars.location = vector(700, 450)
mars.predicted = vector(500, 0)
assert(decide() == nil, 'account for a core moving into the sphere during the cast point')

local witchDoctor = heroAt(500, 0, 550)
dazzle.location = vector(500, 0)
enemies, allies = {sniper, tiny, witchDoctor}, {bot, dazzle}
assert(decide() == nil, 'a normal teamfight cast must avoid supports even when it can catch three enemies')

spell.aoeRadius = 500
dazzle.location = vector(960, 0)
assert(not hero.IsChronosphereAllySafe(spell, aim), 'protect allies inside the current effective radius')
spell.aoeRadius = nil
assert(hero.IsChronosphereAllySafe(spell, aim))

spell.name = 'faceless_void_time_zone'
enemies, allies = {sniper, tiny}, {bot, mars, dazzle}
assert(decide() == aim, 'Time Zone does not apply the allied freeze cost')

spell.name = 'faceless_void_chronosphere'
teamfight, chasing, attackTarget = false, true, sniper
allies = {bot, heroAt(800, 0, 500)}
assert(decide() == nil, 'the solo finisher also checks the actual cast location for nearby allies')
allies = {bot}
assert(decide() ~= nil, 'preserve a clean solo finisher')

assert(bot.ohaChronosphere == nil, 'an order alone is no evidence that the sphere appeared')
now = now + 3
assert(decide() ~= nil and bot.ohaChronosphere == nil, 'an expired order may be retried without publishing a zone')
J.CanNotUseAbility = yes
now, cooldown = now + 0.5, 90
hero.SkillsComplement()
local sphere = assert(bot.ohaChronosphere, 'publish the zone after cooldown confirms the cast')

local file = assert(io.open('bots/FunLib/jmz_func.lua', 'rb'))
local source = file:read('*a')
file:close()
local first = assert(source:find('local function GetChronosphereStandOff(', 1, true))
local last = assert(source:find('function J.IsLocationInChrono(', first, true))
env.J, env.GetTeamPlayers = J, function() return {1, 2} end
env.GetTeamMember = function(index) return ({bot, mars})[index] end
env.GetUnitToLocationDistance = function(unit, point) return distance(unit.location, point) end
env.IsLocationPassable = yes
J.GetLocationToLocationDistance = distance
J.VectorAway = function(origin, center, amount) return origin + (origin - center) * (amount / distance(origin, center)) end
J.IsValid = J.IsValidHero
J.IsInRange = function(a, b, range) return distance(a.location, b.location) <= range end
bot.GetTeam, mars.GetTeam = function() return 2 end, function() return 2 end
mars.GetExtrapolatedLocation = function() return mars.predicted or mars.location end
mars.GetAttackRange = function() return mars.range end
mars.GetAttackTarget = function() return sniper end
setfenv(assert(loadstring(source:sub(first, last - 1))), env)()

mars.location = sphere.location + vector(-450, 0)
mars.predicted = sphere.location + vector(-350, 0)
sniper.location = sphere.location
mars.range = 150
assert(distance(assert(J.GetChronosphereAvoidanceLocation(mars)), sphere.location) > sphere.radius)
mars.predicted = nil
assert(J.GetChronosphereAvoidanceLocation(mars) ~= nil, 'stop a melee pursuit into an active sphere')
mars.range = 600
assert(J.GetChronosphereAvoidanceLocation(mars) == nil, 'allow in-range attacks from outside the sphere')
mars.range = 150
now = sphere.expires + 0.1
assert(J.GetChronosphereAvoidanceLocation(mars) == nil, 'release the route once the sphere expires')

print('PASS: Faceless Void preserves clean casts and allies avoid confirmed, active spheres')
