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
        IsAttackImmune = no,
        HasModifier = no,
        location = vector(x, y),
    }
end

local aim = vector(500, 0)
local enemies, allies, orders = {}, {}, {}
local attackTarget, target
local teamfight, chasing = true, false
local spell = {
    GetName = function(self) return self.name end,
    IsFullyCastable = yes,
    IsHidden = no,
    IsNull = no,
    GetCastRange = function() return 800 end,
    GetCastPoint = function() return 0.35 end,
    GetAOERadius = function(self) return self.aoeRadius or 0 end,
    GetSpecialValueInt = function(_, name) return name == 'radius' and 400 or 4 end,
    name = 'faceless_void_chronosphere',
}

local bot = heroAt(0, 0, 1000)
bot.GetAbilityByName = function() return spell end
bot.GetAttackDamage = one
bot.GetAttackSpeed = one
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
    IsCore = function(unit) return unit.core == true end,
    IsInTeamFight = function() return teamfight end,
    IsGoingOnSomeone = function() return chasing end,
    IsRetreating = no,
    IsInRange = yes,
    CanCastOnMagicImmune = yes,
    CanKillTarget = yes,
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
    GameTime = one,
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

local sniper, tiny = heroAt(365, 0, 400), heroAt(635, 0, 800)
local mars, dazzle = heroAt(365, 0, 1100), heroAt(635, 0, 500)
enemies, allies = {sniper, tiny}, {bot, mars, dazzle}
assert(decide() == nil, 'hold a two-target Chronosphere when it would also freeze Mars and Dazzle')

allies = {bot}
assert(decide() == aim and target == sniper, 'use the clean default location and target the weaker enemy')

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

print('PASS: Faceless Void avoids freezing allies, can shift the sphere, and preserves clean casts')
