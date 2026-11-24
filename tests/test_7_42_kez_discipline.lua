-- Exercise both production callbacks with weapon visibility controlled by the engine mock.
local function no() return false end
local function yes() return true end
local function empty() return {} end
local function one() return 1 end

local pairsBySlot = {
    {'kez_echo_slash', 'kez_falcon_rush'},
    {'kez_grappling_claw', 'kez_talon_toss'},
    {'kez_kazurai_katana', 'kez_shodo_sai'},
    {'kez_raptor_dance', 'kez_ravens_veil'},
}
local switch = 'kez_switch_weapons'
local talent = 'special_bonus_test'
local visible, unavailable, abilities = {}, {}, {}

local function addAbility(name)
    abilities[name] = {
        GetName = function() return name end,
        IsNull = function() return unavailable[name] == 'null' end,
        IsHidden = function() return not visible[name] end,
        GetHeroLevelRequiredToUpgrade = one,
        CanAbilityBeUpgraded = yes,
        GetLevel = one,
        GetMaxLevel = function() return 4 end,
        GetManaCost = one,
    }
end
for _, pair in ipairs(pairsBySlot) do
    addAbility(pair[1])
    addAbility(pair[2])
end
addAbility(switch)
addAbility(talent)

local function expose(side)
    for _, pair in ipairs(pairsBySlot) do
        visible[pair[1]] = side == 1
        visible[pair[2]] = side == 2
    end
    visible[talent] = true
end

local casts, queue, leveled = {}, {}, {}
local points, chasing, retreating, scepter = 0, false, false, false
local enemy = {HasModifier = no, GetAttackDamage = one, GetAttackSpeed = one, GetEstimatedDamageToTarget = one}
enemy.GetNearbyHeroes = function() return {enemy} end
local bot = {
    kez_mode = 'katana',
    GetUnitName = function() return 'npc_dota_hero_kez' end,
    GetAbilityByName = function(_, name)
        if unavailable[name] ~= 'missing' then return abilities[name] end
    end,
    GetAbilityInSlot = function(_, slot)
        local pair = pairsBySlot[slot + 1]
        if pair then return visible[pair[1]] and abilities[pair[1]] or abilities[pair[2]] end
    end,
    IsAlive = yes, IsHero = yes, IsInvulnerable = no, IsIllusion = no, IsRooted = no,
    HasModifier = no, HasScepter = function() return scepter end,
    GetAbilityPoints = function() return points end,
    GetLevel = one, GetLocation = empty, GetNearbyTowers = empty,
    GetHealth = one, GetMaxHealth = one, GetMana = one, GetMaxMana = one,
    Action_UseAbility = function(_, ability) table.insert(casts, ability:GetName()) end,
    ActionImmediate_LevelAbility = function(_, name) table.insert(leveled, name) end,
    Action_ClearActions = function() queue = {} end,
    ActionQueue_Delay = function() table.insert(queue, 'delay') end,
    ActionQueue_UseAbility = function(_, ability) table.insert(queue, ability:GetName()) end,
    ActionQueue_UseAbilityOnEntity = function(_, ability) table.insert(queue, ability:GetName()) end,
}

local J = {
    GetProperTarget = function() return enemy end,
    GetNearbyHeroes = empty, GetAlliesNearLoc = empty,
    CanNotUseAbility = no, IsTryingtoUseAbility = no, IsNoAbilityIllution = no,
    GetPosition = one, IsInLaningPhase = no,
    IsGoingOnSomeone = function() return chasing end,
    IsRetreating = function() return retreating end,
    IsRealInvisible = no, IsFarming = no, IsDoingRoshan = no, IsDoingTormentor = no,
    IsValidHero = function(target) return target == enemy end,
    IsInRange = yes, CanBeAttacked = yes, CanCastOnTargetAdvanced = yes,
    GetHP = function() return 0.5 end,
    GetManaAfter = one,
    GetEnemiesNearLoc = function() return {enemy} end,
    CanCastAbility = function(ability) return ability == abilities[switch] or ability == abilities.kez_ravens_veil end,
    IsStaleARDMHero = function() return false, bot, bot:GetUnitName() end,
    Item = {GetRoleItemsBuyList = function() return 'pos_1' end},
    Role = {IsPvNMode = no, IsAllShadow = no},
    SetUserHeroInit = function(...) return ... end,
    SetReportMotive = function() end, SetQueuePtToINT = function() end,
}

local hero
local env = setmetatable({
    GetScriptDirectory = function() return 'bots' end,
    GetBot = function() return bot end,
    GetTeam = one, Vector = empty, RandomInt = function(first) return first end,
    GAME_STATE_PRE_GAME = 1, GetGameState = one, GetGameMode = function() return 0 end,
    DotaTime = function() return 20 end, GetUnitToUnitDistance = one,
    BOT_ACTION_DESIRE_NONE = 0, BOT_ACTION_DESIRE_HIGH = 0.8,
    require = function(name) return name == 'bots/FunLib/jmz_func' and J or {} end,
    dofile = function(name) return name == 'bots/BotLib/hero_kez' and hero or {} end,
}, {__index = _G})

local function loadModule(path)
    return setfenv(assert(loadfile(path)), env)()
end

J.Skill = loadModule('bots/FunLib/aba_skill.lua')
J.Skill.GetTalentList, J.Skill.GetAbilityList = empty, empty
hero = loadModule('bots/BotLib/hero_kez.lua')
for _, spell in ipairs({'EchoSlash', 'GrapplingClaw', 'RaptorDance', 'FalconRush', 'RavensVeil',
    'KazuraiKatana', 'TalonToss', 'ShodoSaiCancel', 'ShodoSai'}) do
    hero['Consider' .. spell] = function() return 0 end
end
local usage = loadModule('bots/ability_item_usage_generic.lua')

local function tryLevel(name)
    local build = {name}
    leveled = {}
    usage.SetAbilityItemList(false, false, build)
    usage.AbilityLevelUpThink()
    return build
end

points = 1
for _, side in ipairs({2, 1}) do
    expose(side)
    for _, pair in ipairs(pairsBySlot) do
        local build = tryLevel(pair[3 - side])
        assert(#leveled == 1 and leveled[1] == pair[side] and #build == 0, 'wrong discipline for ' .. pair[side])
    end
end

expose(0)
unavailable.kez_echo_slash, unavailable.kez_falcon_rush = 'missing', 'null'
local pending = tryLevel('kez_echo_slash')
assert(#leveled == 0 and pending[1] == 'kez_echo_slash', 'missing or null handles consumed the build entry')
unavailable.kez_echo_slash, unavailable.kez_falcon_rush = nil, nil
visible.kez_echo_slash, visible.kez_falcon_rush = true, true
usage.AbilityLevelUpThink()
assert(#leveled == 0 and pending[1] == 'kez_echo_slash', 'ambiguous visibility consumed the build entry')
expose(2)
usage.AbilityLevelUpThink()
assert(#leveled == 1 and leveled[1] == 'kez_falcon_rush' and #pending == 0, 'did not retry after the stance settled')
expose(0)
tryLevel(talent)
assert(#leveled == 1 and leveled[1] == talent, 'ordinary talent leveling depends on stance')

points, chasing = 0, true
usage.AbilityUsageThink()
assert(#casts == 0, 'attempted to switch with no observed stance')
expose(1)
usage.AbilityUsageThink()
usage.AbilityUsageThink() -- The previous order did not change the engine state.
assert(#casts == 2 and casts[1] == switch and casts[2] == switch, 'treated a switch request as a completed switch')
expose(2)
usage.AbilityUsageThink()
assert(#casts == 2, 'continued the katana switch after the engine exposed sai')
retreating, chasing = true, false
usage.AbilityUsageThink()
assert(#casts == 3 and casts[3] == switch, 'retreat did not recognize sai')

-- The Scepter combo queues a switch and should leave the rest of the think alone.
retreating, chasing, scepter = true, true, true
hero.ConsiderEchoSlash = function() error('continued casting after queuing the combo') end
usage.AbilityUsageThink()
assert(table.concat(queue, ',') == 'kez_ravens_veil,delay,kez_switch_weapons,kez_grappling_claw,delay,kez_echo_slash')
assert(#casts == 3, 'replaced the queued switch with an immediate cast')
hero.ConsiderEchoSlash = function() return 0 end
scepter = false
expose(1) -- The queued switch has now actually completed.
usage.AbilityUsageThink()
assert(#casts == 4 and casts[4] == switch, 'did not observe katana after the queued switch')

print('PASS: Kez paired leveling and live discipline in both callbacks')
