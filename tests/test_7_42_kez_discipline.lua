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
local parryCancel = 'kez_shodo_sai_parry_cancel'
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
addAbility(parryCancel)
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
enemy.GetMaxHealth = function() return 1000 end
enemy.GetLocation = empty
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
    GetLevel = one, GetLocation = empty, GetNearbyTowers = empty, GetNearbyHeroes = empty,
    GetAttackDamage = function() return 200 end, IsFacingLocation = yes,
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
    CanCastAbility = function(ability)
        return ability == abilities[switch] or ability == abilities.kez_ravens_veil
            or (ability == abilities[parryCancel] and not ability:IsHidden())
    end,
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
    DAMAGE_TYPE_PHYSICAL = 1,
    require = function(name) return name == 'bots/FunLib/jmz_func' and J or {} end,
    dofile = function(name) return name == 'bots/BotLib/hero_kez' and hero or {} end,
}, {__index = _G})

local function loadModule(path)
    return setfenv(assert(loadfile(path)), env)()
end

J.Skill = loadModule('bots/FunLib/aba_skill.lua')
J.Skill.GetTalentList, J.Skill.GetAbilityList = empty, empty
hero = loadModule('bots/BotLib/hero_kez.lua')
local considerParryCancel = hero.ConsiderShodoSaiCancel
local considerEchoSlash, considerRaptorDance = hero.ConsiderEchoSlash, hero.ConsiderRaptorDance
local considerKazuraiKatana = hero.ConsiderKazuraiKatana
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

expose(2)
points = 1 -- Hold the regular weapon switch so the existing retreat cancel can run.
J.GetAlliesNearLoc = function() return {{}} end
hero.ConsiderShodoSaiCancel = considerParryCancel
unavailable[parryCancel] = 'missing'
usage.AbilityUsageThink()
assert(#casts == 4, 'issued a missing parry cancel')
unavailable[parryCancel] = nil
usage.AbilityUsageThink()
assert(#casts == 4, 'issued a hidden parry cancel')
visible[parryCancel] = true
usage.AbilityUsageThink()
assert(#casts == 5 and casts[5] == parryCancel, 'did not issue the visible parry cancel')

print('PASS: Kez paired leveling and live discipline in both callbacks')
print('PASS: Kez resolves the parry cancel handle when it is exposed')

local function setValues(name, values)
    local handle = abilities[name]
    handle.GetSpecialValueInt = function(_, key) return assert(values[key], name .. ': unexpected ' .. key) end
    handle.GetSpecialValueFloat = handle.GetSpecialValueInt
end

local echo = 'kez_echo_slash'
local raptor = 'kez_raptor_dance'
setValues(echo, {katana_distance = 800, katana_radius = 225, katana_echo_damage = 30, echo_base_damage = 40, katana_strikes = 2})
setValues(raptor, {radius = 425, base_damage = 50, strikes = 4, max_health_damage_pct = 2.75})
expose(1)
visible[parryCancel] = false
retreating, chasing = false, false
J.GetProperTarget = function() return nil end
J.GetNearbyHeroes = function(_, _, isEnemy) return isEnemy and {enemy} or {} end
J.IsInRange = function(_, target) return target == enemy end
J.IsSuspiciousIllusion = no
J.Chat = {GetNormName = function() return 'test enemy' end}

local function expectPhysicalCast(name, expectedDamage)
    J.CanCastAbility = function(handle) return handle == abilities[name] end
    J.CanKillTarget = function(target, damage, damageType)
        assert(target == enemy and damageType == env.DAMAGE_TYPE_PHYSICAL, 'wrong damage target or type')
        assert(damage == expectedDamage, name .. ': expected ' .. expectedDamage .. ', got ' .. damage)
        return true
    end
    queue = {}
    usage.AbilityUsageThink()
    assert(#queue == 1 and queue[1] == name, 'missing ' .. name .. ' kill cast')
end

hero.ConsiderEchoSlash = considerEchoSlash
expectPhysicalCast(echo, 200)
hero.ConsiderRaptorDance = considerRaptorDance
expectPhysicalCast(raptor, 310)
print('PASS: Kez Echo Slash and Raptor Dance use current 7.42 damage')

local katana = 'kez_kazurai_katana'
setValues(katana, {bleed_as_rupture_pct = 50, max_stacks = 500})
abilities[katana].GetCastRange = function() return 200 end
hero.ConsiderKazuraiKatana = considerKazuraiKatana
J.CanCastAbility = function(handle) return handle == abilities[katana] end
J.GetProperCastRange = function(_, _, range) return range end
J.CanCastOnTargetAdvanced = yes
local distance, stacks, katanaCasts = 200, 900, 0
J.IsInRange = function(_, target, range) return target == enemy and distance <= range end
J.GetModifierCount = function(target, modifier)
    assert(target == enemy and modifier == 'modifier_kez_katana_bleed')
    return stacks
end
J.CanKillTarget = function(target, damage, damageType)
    assert(target == enemy and damage == 250 and damageType == env.DAMAGE_TYPE_PHYSICAL)
    return true
end
bot.Action_UseAbilityOnEntity = function(_, ability, target)
    assert(ability == abilities[katana] and target == enemy)
    katanaCasts = katanaCasts + 1
end
usage.AbilityUsageThink()
assert(katanaCasts == 1)
distance = 201
usage.AbilityUsageThink()
distance, stacks = 200, 0
usage.AbilityUsageThink()
assert(katanaCasts == 1, 'issued an out-of-range or zero-bleed Katana')
print('PASS: Kez Kazurai Katana checks cast range and caps the target’s bleed burst')
