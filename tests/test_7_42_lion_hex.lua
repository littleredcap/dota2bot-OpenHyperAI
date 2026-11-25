local function no() return false end
local function yes() return true end
local function empty() return {} end
local NONE, HIGH, POINT, UNIT_TARGET = 0, 0.8, 16, 8

local state = {time = 500, x = 450, remaining = 0, orders = {}}
local enemy = {
    GetLocation = function() return state.x end,
    IsChanneling = function() return state.channeling end,
    IsCastingAbility = no,
}
local ally = {}
local hex = {
    GetCastRange = function() return 600 end, GetCastPoint = function() return 0 end,
    GetBehavior = function() return state.pointCast and POINT or UNIT_TARGET end,
}
local spike = {}
local spells = {lion_impale = spike, lion_voodoo = hex}
local lens = {GetSpecialValueInt = function(_, name) assert(name == 'cast_range_bonus'); return 200 end}
local function order(kind, spell, target)
    state.orders[#state.orders + 1] = {kind, spell, target}
end
local bot = {
    GetAbilityByName = function(_, name) return spells[name] end,
    IsChanneling = no, IsInvisible = no, GetLocation = function() return 0 end,
    GetLevel = function() return 12 end, GetHealth = function() return 900 end,
    GetMaxHealth = function() return 1000 end, GetMana = function() return 600 end,
    GetMaxMana = function() return 1000 end, WasRecentlyDamagedByAnyHero = no,
    ActionQueue_UseAbilityOnEntity = function(_, spell, target) order('unit', spell, target) end,
    ActionQueue_UseAbilityOnLocation = function(_, spell, target) order('point', spell, target) end,
}
local jmz = {
    Skill = {
        GetTalentList = empty, GetRandomBuild = empty, GetTalentBuild = empty, GetSkillList = empty,
        GetAbilityList = function() return {'lion_impale', 'lion_voodoo'} end,
    },
    Item = {GetRoleItemsBuyList = function() return 'pos_5' end},
    Role = {IsPvNMode = no, IsAllShadow = no}, SetUserHeroInit = function(...) return ... end,
    CanNotUseAbility = no, CanCastAbility = function(ability) return ability == hex end,
    IsItemAvailable = function() return state.lens and lens or nil end,
    GetProperTarget = function() return enemy end,
    GetNearbyHeroes = function(_, range) return state.x <= range and {enemy} or {} end,
    GetAlliesNearLoc = function(location) return location == state.x and state.follow and {ally} or {} end,
    IsValidHero = function(target) return target == enemy or target == ally end,
    IsSuspiciousIllusion = no,
    CanCastOnNonMagicImmune = function() return not state.immune end,
    CanCastOnTargetAdvanced = function() return not state.blocked end,
    IsInRange = function(_, target, range) return target == enemy and state.x <= range end,
    IsDisabled = function() return state.remaining > 0 or state.unknownDisable end,
    GetRemainStunTime = function() return state.remaining end,
    GetModifierTime = function() return 0 end,
    IsInTeamFight = no, IsGoingOnSomeone = yes, IsRetreating = no,
    IsChasingTarget = function() return state.chasing end, IsDoingRoshan = no,
    CheckBitfieldFlag = function(behavior, flag) return behavior == flag end,
    SetReportMotive = empty, SetQueuePtToINT = empty,
}
local env = setmetatable({
    GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
    require = function() return jmz end, dofile = empty, DotaTime = function() return state.time end,
    BOT_ACTION_DESIRE_NONE = NONE, BOT_ACTION_DESIRE_HIGH = HIGH,
    ABILITY_BEHAVIOR_POINT = POINT,
}, {__index = _G})
local lion = setfenv(assert(loadfile('bots/BotLib/hero_lion.lua')), env)()
lion.ConsiderE, lion.ConsiderR = function() return NONE end, function() return NONE end
lion.ConsiderQ = function() return state.useSpike and HIGH or NONE, state.x end

local function expect(kind, spell, target)
    state.orders = {}
    lion.SkillsComplement()
    if kind == nil then assert(#state.orders == 0, 'unexpected cast'); return end
    local actual = assert(state.orders[1], 'missing cast')
    assert(#state.orders == 1 and actual[1] == kind and actual[2] == spell and actual[3] == target, 'wrong cast or target')
end

expect(nil)
state.follow = true
expect('unit', hex, enemy)
state.remaining = 1.2
expect(nil)
state.remaining = 0.1
expect('unit', hex, enemy)
state.remaining, state.unknownDisable = 0, true
expect(nil)
state.unknownDisable, state.follow, state.chasing = false, false, true
expect('unit', hex, enemy)
state.x, state.channeling = 820, true
expect(nil)
state.lens, state.x = true, 790
expect('unit', hex, enemy)

state.x, state.channeling, state.useSpike = 450, false, true
expect('point', spike, state.x)
state.time, state.channeling = state.time + 0.1, true
expect('unit', hex, enemy)

state.pointCast, state.blocked = true, true
expect('point', hex, state.x)
state.immune = true
state.useSpike = false
expect(nil)
print('PASS: Lion Hex follow-up, chase, control timing, spell range, urgent interrupt and point dispatch')
