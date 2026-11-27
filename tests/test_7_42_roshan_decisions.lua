local function yes() return true end
local function no() return false end
local function empty() return {} end
local function pos(x) return {x = x} end
local function distance(a, b) return math.abs(a.x - b.x) end
local function clamp(n, lo, hi) return math.max(lo, math.min(hi, n)) end
local function remap(n, lo, hi, a, b) return a + (b - a) * clamp((n - lo) / (hi - lo), 0, 1) end

local function fixture()
    local state = {time = 1500, alive = true, enoughDps = true, aliveAlly = 5, aliveEnemy = 3, baseDesire = 0.65}
    local expectedPit = pos(5000)
    local bot = {
        x = 3000, GetUnitName = function() return 'npc_dota_hero_test' end,
        IsInvulnerable = no, IsHero = yes, IsAlive = yes, IsIllusion = no, HasModifier = no, GetTeam = function() return 2 end,
        GetLocation = function(self) return pos(self.x) end,
        GetNearbyNeutralCreeps = function() return state.visibleRoshan and {state.visibleRoshan} or {} end,
    }
    local function enemiesAt(point, radius, enemy)
        return enemy and distance(point, enemy) <= radius and {enemy} or {}
    end
    local j = {
        Utils = {IsTeamPushingSecondTierOrHighGround = no, CountBackpackEmptySpace = function() return 1 end},
        GetEnemiesAroundAncient = function() return state.baseThreat and 1 or 0 end,
        GetHP = function(unit) return unit.hp or 1 end,
        GetCurrentRoshanLocation = function() return expectedPit end,
        GetTeamFightLocation = function() return state.fight end,
        GetLastSeenEnemiesNearLoc = function(point, radius) return enemiesAt(point, radius, state.lastSeen) end,
        GetEnemiesNearLoc = function(point, radius) return enemiesAt(point, radius, state.enemy) end,
        GetNumOfAliveHeroes = function(enemy) return enemy and state.aliveEnemy or state.aliveAlly end,
        IsCore = no,
        IsValidHero = yes, IsMeepoClone = no, IsRetreating = no,
        IsRoshan = function(unit) return unit ~= nil and unit.visible end,
        IsRoshanAlive = function() return state.alive end,
        HasEnoughDPSForRoshan = function(allies) return #allies > 0 and state.enoughDps end,
        IsRoshanCloseToChangingSides = function() return state.changingSides end,
        GetProperTarget = function() return state.target end,
        GetHumanPing = function() end, ModeAnnounce = function() end,
    }
    local env = setmetatable({
        GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
        require = function() return j end, GetUnitList = function() return {bot} end,
        GetAncient = empty, DotaTime = function() return state.time end,
        GetUnitToLocationDistance = distance, Clamp = clamp, RemapValClamped = remap,
        GetRoshanDesire = function() return state.baseDesire end,
        BOT_MODE_DESIRE_NONE = 0, BOT_MODE_DESIRE_MODERATE = 0.5,
        BOT_MODE_DESIRE_VERYHIGH = 0.9, BOT_MODE_DESIRE_ABSOLUTE = 1,
    }, {__index = _G})
    setfenv(assert(loadfile('bots/mode_roshan_generic.lua')), env)()
    return state, bot, env.GetDesire
end

do
    local state, _, desire = fixture()
    state.baseDesire = 0.2
    assert(desire() == 0.2, 'keep the engine approach desire when the pit is unconfirmed')
    state.baseDesire = 0.95
    assert(desire() == 0.5, 'leave an unconfirmed pit at approach priority')
    state.visibleRoshan = {hp = 0.9, visible = true, GetLocation = function() return pos(5000) end}
    state.baseDesire = 0.65
    assert(desire() == 0.65, 'a visible objective with superior numbers and enough output is viable')
    state.enoughDps = false
    assert(desire() == 0, 'old DPS readiness must not survive a drop in current output')
    state.enoughDps, state.aliveAlly = true, 2
    assert(desire() == 0, 'do not commit with fewer alive heroes')
    state.aliveAlly, state.alive = 5, false
    state.visibleRoshan.visible = false
    assert(desire() == 0, 'do not approach outside the available window')
end

do
    local state, bot, desire = fixture()
    local first = {hp = 0.3, visible = true, GetLocation = function() return pos(5000) end}
    state.visibleRoshan = first
    assert(desire() == 0.65, 'a distant hero should not get an urgent finish desire')
    bot.x = 3600
    assert(desire() > 0.5 and desire() < 0.8, 'scale urgency using the fractional health of visible Roshan')
    state.enoughDps = false
    assert(desire() == 0, 'a wounded Roshan still requires current healthy damage')
    state.changingSides, state.target = true, first
    assert(desire() == 0, 'the last chance before Roshan moves does not bypass damage readiness')
    state.enoughDps, state.changingSides, state.target = true, false, nil
    state.enemy = pos(5100)
    assert(desire() == 0, 'a threat at the pit cancels the low-health shortcut even outside local radius')
    state.enemy, state.lastSeen = nil, pos(5100)
    state.baseDesire = 0.2
    assert(desire() == 0.2, 'recent contact at the pit suppresses the low-health shortcut')
    state.baseThreat = true
    assert(desire() == 0, 'base defense takes priority over finishing Roshan')
    state.baseThreat, state.lastSeen, state.aliveAlly = false, nil, 2
    assert(desire() == 0, 'the finish shortcut observes the current team advantage')
    state.aliveAlly = 5
    state.baseThreat, state.lastSeen, first.visible = false, nil, false
    state.visibleRoshan = {hp = 0.9, visible = true, GetLocation = function() return pos(1000) end}
    bot.x, state.fight = 1200, pos(1600)
    assert(desire() == 0, 'reacquire the replacement Roshan and assess the nearby fight against the actual pit')
end

print('PASS: Roshan approach, current team readiness, contested finishes and replacement pit')

do
    local file = assert(io.open('bots/FunLib/jmz_func.lua', 'rb'))
    local source = file:read('*a')
    file:close()
    local first = assert(source:find('function J.HasEnoughDPSForRoshan(', 1, true))
    local last = assert(source:find('function J.IsNotSelf(', first, true))
    local j = {GetArmorReducers = function() return 0 end}
    local env = setmetatable({J=j, DotaTime=function() return 1200 end}, {__index=_G})
    setfenv(assert(loadstring(source:sub(first, last - 1))), env)()
    local attacker = {GetAttackDamage = function() return 315 end, GetSecondsPerAttack = function() return 1 end}
    assert(not j.HasEnoughDPSForRoshan({attacker}))
    assert(j.HasEnoughDPSForRoshan({attacker, attacker}), 'compare combined DPS to the group kill threshold')
end
