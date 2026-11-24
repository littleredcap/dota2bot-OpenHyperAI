-- Run production spell decisions against only the current game-data keys.
local NONE, HIGH = 0, 0.8
local MAGICAL = 2
local function yes() return true end
local function no() return false end
local function empty() return {} end
local function properRange(_, _, range) return range end

local location = {}
local enemy = {
    HasModifier = no, GetLocation = function() return location end,
    GetExtrapolatedLocation = function() return location end,
}

local function ability(values)
    local function special(_, key)
        assert(values[key] ~= nil, 'unknown 7.42 ability value: ' .. key)
        return values[key]
    end
    return {
        IsFullyCastable = yes, IsTrained = yes, IsHidden = no, IsActivated = yes, IsNull = no,
        GetSpecialValueInt = special, GetSpecialValueFloat = special,
        GetCastPoint = function() return 0.3 end,
        GetCastRange = function() return 800 end,
        GetChannelTime = function() return 1.75 end,
    }
end

local function loadHero(name, spells, bot, common)
    bot.GetAbilityByName = function(_, spell) return spells[spell] end
    bot.GetAbilityInSlot = function() end
    common.Skill = {
        GetTalentList = empty, GetAbilityList = empty, GetRandomBuild = empty,
        GetTalentBuild = empty, GetSkillList = empty,
    }
    common.Item = {GetRoleItemsBuyList = function() return 'pos_2' end}
    common.Role = {IsPvNMode = no, IsAllShadow = no}
    common.SetUserHeroInit = function(...) return ... end
    local env = setmetatable({
        GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
        require = function() return common end, dofile = empty,
        RandomInt = function(first) return first end, TEAM_NEUTRAL = 4,
        GetUnitToUnitDistance = function() return 400 end,
        DotaTime = function() return bot.clock or 100 end, ABILITY_BEHAVIOR_UNIT_TARGET = 8,
        ABILITY_BEHAVIOR_POINT = 16,
        BOT_ACTION_DESIRE_NONE = NONE, BOT_ACTION_DESIRE_HIGH = HIGH, DAMAGE_TYPE_MAGICAL = MAGICAL,
    }, {__index = _G})
    return setfenv(assert(loadfile('bots/BotLib/hero_' .. name .. '.lua')), env)()
end

local function expectDamage(target, damage, damageType)
    assert(target == enemy and damageType == MAGICAL)
    assert(damage == enemy.expectedDamage, 'wrong damage: ' .. damage)
    return true
end

local j = {
    GetProperCastRange = properRange, IsValidHero = yes, IsInRange = yes,
    CanCastOnNonMagicImmune = yes, IsSuspiciousIllusion = no, CanKillTarget = expectDamage,
    GetNearbyHeroes = function(_, _, isEnemy) return isEnemy and {enemy} or {} end,
    IsInTeamFight = no,
}
local bot = {GetLocation = empty}
local arc = loadHero('arc_warden', {
    arc_warden_spark_wraith = ability({radius = 375, spark_damage_base = 170, base_activation_delay = 1.5}),
    arc_warden_magnetic_field = ability({radius = 300}),
}, bot, j)
enemy.expectedDamage = 170
enemy.GetExtrapolatedLocation = function(_, delay)
    assert(math.abs(delay - 1.8) < 0.0001, 'Spark Wraith lost its fractional activation delay')
    return location
end
assert(arc.ConsiderSparkWraith() == HIGH)

bot.HasModifier = no
bot.GetNearbyLaneCreeps, bot.GetNearbyTowers = empty, empty
bot.GetNearbyBarracks, bot.GetNearbyFillers = function() return {{}} end, empty
j.IsGoingOnSomeone, j.IsDefending, j.IsPushing, j.IsAttacking = no, no, yes, yes
j.CanCastAbility = yes
assert(arc.ConsiderMagneticField() == HIGH, 'Arc ignored barracks without a tower')
bot.GetNearbyBarracks, bot.GetNearbyFillers = empty, bot.GetNearbyBarracks
assert(arc.ConsiderMagneticField() == HIGH, 'Arc ignored base fillers')
print('PASS: Arc Warden respects Spark Wraith damage and delay and sees base targets')

enemy.GetExtrapolatedLocation = function() return location end
local gyro = loadHero('gyrocopter', {
    gyrocopter_call_down = ability({radius = 400, damage = 180}),
}, bot, j)
enemy.expectedDamage = 180
assert(gyro.ConsiderCallDown() == HIGH)

local troll = loadHero('troll_warlord', {
    troll_warlord_whirling_axes_melee = ability({max_range = 450, damage = 120}),
    troll_warlord_whirling_axes_ranged = ability({axe_range = 950, axe_damage = 80}),
}, bot, j)
enemy.expectedDamage = 120
j.GetNearbyHeroes = function(_, range)
    assert(range == 450, 'melee axes used the wrong range')
    return {enemy}
end
assert(troll.ConsiderWhirlingAxesMelee() == HIGH)
print('PASS: Gyrocopter and Troll use the current spell damage')

local spring = loadHero('monkey_king', {
    monkey_king_primal_spring = ability({impact_radius = 375}),
}, bot, j)
bot.FindAoELocation = function(_, _, _, _, range, radius)
    assert(range == 800 and radius == 375, 'wrong Primal Spring search area')
    return {count = 2, targetloc = location}
end
j.IsInTeamFight = yes
j.GetEnemiesNearLoc = function(center)
    assert(center == location, 'Primal Spring searched around the caster')
    return {enemy, {}}
end
local desire, landing = spring.ConsiderPrimalSpring()
assert(desire == HIGH and landing == location)
print('PASS: Monkey King uses actual cast range and checks enemies at the landing point')

local canDevourAncients = false
local devour = ability({creep_level = 6})
devour.GetSpecialValueInt = function(_, key)
    if key == 'creep_level' then return 6 end
    assert(key == 'can_target_ancient')
    return canDevourAncients and 1 or 0
end
local function creep(health, level, isAncient)
    return {
        GetHealth = function() return health end, GetLevel = function() return level end,
        GetTeam = function() return 4 end, IsAncientCreep = function() return isAncient end,
    }
end
local ancient, normal = creep(1000, 6, true), creep(600, 4, false)
local overLevel = creep(1600, 8, false)
bot.GetNearbyCreeps = function() return {ancient, overLevel, normal} end
bot.GetNearbyTowers = empty
j.IsRetreating, j.IsInLaningPhase, j.IsRoshan, j.IsTormentor = no, no, no, no
j.IsValid, j.CanBeAttacked = yes, yes
local doom = loadHero('doom_bringer', {doom_bringer_devour = devour}, bot, j)
doom.GetRangedOrSiegeCreep = function() end
local _, target = doom.ConsiderDevour()
assert(target == normal, 'Doom selected an illegal creep')
canDevourAncients = true
_, target = doom.ConsiderDevour()
assert(target == ancient, 'Doom did not use upgraded Devour on a valid Ancient')
print('PASS: Doom selects only eligible creeps with and without Ancient Devour')

local antimage = loadHero('antimage', {}, {HasScepter = yes}, {
    CanCastAbility = function(handle) return handle ~= nil end,
})
assert(antimage.ConsiderCounterSpellAlly() == NONE and antimage.ConsiderBlinkFragment() == NONE)
print('PASS: Anti-Mage tolerates absent upgrade abilities')

local pocket = ability({})
local spirit = {HasModifier = no}
local healthy = {GetLocation = empty, WasRecentlyDamagedByAnyHero = yes}
local injured = {GetLocation = empty, WasRecentlyDamagedByAnyHero = yes}
local allies = {healthy, injured}
local casterHP, pocketReady, visibleThreat, casts = 0.8, true, true, 0
spirit.Action_UseAbilityOnEntity = function(_, spell, ally)
    assert(spell == pocket and ally == injured, 'Planar Pocket sent an invalid ally or spell')
    casts = casts + 1
end
local breaker = loadHero('spirit_breaker', {
    spirit_breaker_charge_of_darkness = {IsInAbilityPhase = no},
    spirit_breaker_planar_pocket = pocket,
}, spirit, {
    CanNotUseAbility = no, CanCastAbility = function(handle) return handle == pocket and pocketReady end,
    GetHP = function(unit)
        if unit == spirit then return casterHP end
        return unit == injured and 0.35 or 0.7
    end,
    GetNearbyHeroes = function(_, _, isEnemy) return isEnemy and {enemy} or allies end,
    IsValidHero = yes, IsSuspiciousIllusion = no, IsInRange = yes, GetProperCastRange = properRange,
    GetEnemiesNearLoc = function() return visibleThreat and {enemy} or {} end,
    GetHeroesTargetingUnit = function(enemies, ally) return ally == injured and enemies or {} end,
})
for _, name in ipairs({'ChargeOfDarkness', 'Bulldoze', 'NetherStrike'}) do
    breaker['Consider' .. name] = function() return NONE end
end
breaker.SkillsComplement()
assert(casts == 1, 'did not issue a targeted Planar Pocket')
casterHP = 0.4
breaker.SkillsComplement()
casterHP, visibleThreat = 0.8, false
breaker.SkillsComplement()
pocketReady, visibleThreat = false, true
breaker.SkillsComplement()
assert(casts == 1, 'used Planar Pocket outside the defensive conditions')
print('PASS: Spirit Breaker redirects pressure from an eligible ally using a unit-target cast')

local immune = false
local abaddon = loadHero('abaddon', {
    abaddon_death_coil = ability({damage_heal = 170}),
}, {}, {
    IsGoingOnSomeone = no, IsRetreating = no, IsDoingRoshan = no, IsDoingTormentor = no,
    GetProperTarget = function() end, GetMP = function() return 0 end,
    IsValidHero = yes, IsInRange = yes, IsSuspiciousIllusion = no,
    GetNearbyHeroes = function(_, _, isEnemy) return isEnemy and {enemy} or {} end,
    CanCastOnNonMagicImmune = function() return not immune end, CanKillTarget = expectDamage,
})
enemy.expectedDamage = 170
assert(abaddon.ConsiderMistCoil() == HIGH)
immune = true
assert(abaddon.ConsiderMistCoil() == NONE, 'Abaddon tried to damage an immune enemy with Mist Coil')

local phoenix = loadHero('phoenix', {
    phoenix_fire_spirits = ability({radius = 200, spirit_speed = 1000, duration = 4, damage_per_second = 40}),
    phoenix_launch_fire_spirit = ability({}),
}, {
    HasModifier = no, FindAoELocation = function() return {count = 0} end,
    GetNearbyHeroes = function(_, _, isEnemy) return isEnemy and {enemy} or {} end,
}, {
    CanCastAbility = yes, IsValidHero = yes, IsInRange = yes, CanCastOnNonMagicImmune = yes,
    CanKillTarget = expectDamage, GetProperTarget = function() end,
    GetCorrectLoc = function() return location end,
})
enemy.expectedDamage = 160
assert(phoenix.ConsiderFireSpiritsLaunch() == HIGH)
print('PASS: Abaddon and Phoenix use current damage values against legal enemies')

local delays = {}
local techies = loadHero('techies', {
    techies_suicide = ability({damage = 300, duration = 0.75}),
    techies_land_mines = ability({damage = 200}),
    techies_reactive_tazer = {GetBehavior = function() return 8 end},
}, {
    Action_ClearActions = function() end,
    ActionQueue_UseAbilityOnEntity = function() end,
    ActionQueue_UseAbilityOnLocation = function() end,
    ActionQueue_Delay = function(_, seconds) table.insert(delays, seconds) end,
}, {
    CanNotUseAbility = no, GetProperTarget = function() end, CheckBitfieldFlag = yes,
})
techies.ConsiderCombo = function() return HIGH, location, 1 end
techies.SkillsComplement()
assert(#delays == 2 and math.abs(delays[2] - 1.05) < 0.0001, 'Techies did not wait for Blast Off to land')
print('PASS: Techies waits for Blast Off cast and travel time')

local tpTime, wisps = 1.25, 0
local channeling = {
    GetLocation = function() return location end,
    HasModifier = function(_, name) return name == 'modifier_teleporting' end,
}
local wisp = ability({radius = 725, off_duration_initial = 1})
local keeper = loadHero('keeper_of_the_light', {
    keeper_of_the_light_will_o_wisp = wisp,
}, {
    GetNearbyHeroes = function(_, _, isEnemy) return isEnemy and {channeling} or {} end,
    Action_UseAbilityOnLocation = function(_, spell, target)
        assert(spell == wisp and target == location)
        wisps = wisps + 1
    end,
}, {
    CanCastAbility = function(handle) return handle == wisp end, CanNotUseAbility = no,
    GetHP = function() return 1 end, GetProperTarget = function() end,
    GetProperCastRange = properRange, IsInTeamFight = no, IsValidHero = yes, IsInRange = yes,
    CanCastOnNonMagicImmune = yes, GetModifierTime = function() return tpTime end,
})
for _, name in ipairs({'SpiritForm', 'SolarBind', 'BlindingLight', 'IlluminateEnd', 'Illuminate', 'ChakraMagic', 'Recall'}) do
    keeper['Consider' .. name] = function() return NONE end
end
keeper.SkillsComplement()
assert(wisps == 0, 'Will-O-Wisp would pulse too late')
tpTime = 1.5
keeper.SkillsComplement()
assert(wisps == 1, 'Will-O-Wisp has time to interrupt the teleport')
print('PASS: Keeper of the Light accounts for the first Will-O-Wisp pulse')

local willowBot = {clock = 3.1}
local willow = loadHero('dark_willow', {
    dark_willow_bedlam = ability({attack_radius = 300}),
    dark_willow_terrorize = ability({destination_status_duration = 3.2}),
}, willowBot, {
    CanCastAbility = yes, IsInTeamFight = yes, GetProperTarget = function() return enemy end,
    GetNearbyHeroes = function(_, range)
        assert(range == 300, 'Bedlam searched using its no-target cast range')
        return {enemy}
    end,
})
assert(willow.ConsiderBedlam() == NONE, 'Bedlam did not wait through Terrorize fear')
willowBot.clock = 3.3
assert(willow.ConsiderBedlam() == HIGH)
print('PASS: Dark Willow uses Bedlam attack radius and the actual Terrorize duration')

local unitTarget = false
local ward = ability({})
ward.GetBehavior = function() return unitTarget and 8 or 16 end
local farmer = {IsIllusion = no}
local veno = loadHero('venomancer', {venomancer_plague_ward = ward}, {
    GetNearbyHeroes = function(_, _, isEnemy) return isEnemy and {} or {farmer} end,
}, {
    CanCastAbility = yes, GetProperCastRange = properRange,
    CheckBitfieldFlag = function(behavior, flag) return behavior == flag end,
    IsGoingOnSomeone = no, IsRetreating = no, IsFarming = no, IsDefending = no,
    IsPushing = function(unit) return unit == farmer end,
    IsValidHero = yes, IsInRange = yes, GetModifierCount = function() return 0 end,
})
assert(veno.ConsiderPlagueWard() == NONE, 'a point-only ward selected an ally')
unitTarget = true
local wardDesire, wardTarget, attach = veno.ConsiderPlagueWard()
assert(wardDesire == HIGH and wardTarget == farmer and attach)
print('PASS: Venomancer only chooses Plague Ward attachments when the ability supports them')

enemy.IsChanneling = no
local enigma = loadHero('enigma', {
    enigma_malefice = ability({stun_instances = 7, damage = 70}),
}, {}, {
    GetProperCastRange = properRange, GetNearbyHeroes = function() return {enemy} end,
    IsValidHero = yes, CanCastOnNonMagicImmune = yes, CanCastOnTargetAdvanced = yes,
    IsSuspiciousIllusion = no, IsCastingUltimateAbility = no, CanKillTarget = expectDamage,
})
enemy.expectedDamage = 490
assert(enigma.ConsiderMalefice() == HIGH)

local transformed, health = true, 800
local demonZeal = loadHero('terrorblade', {
    terrorblade_demon_zeal = ability({health_cost_pct = 20}),
}, {
    HasModifier = function() return transformed end,
    GetHealth = function() return health end, GetMaxHealth = function() return 1000 end,
    GetAttackRange = function() return 150 end,
}, {
    CanCastAbility = yes, IsInTeamFight = yes, GetNearbyHeroes = function() return {enemy, {}} end,
    GetProperTarget = function() end,
})
assert(demonZeal.ConsiderDemonZeal() == NONE, 'Demon Zeal is illegal during Metamorphosis')
transformed = false
assert(demonZeal.ConsiderDemonZeal() == HIGH)
health = 600
assert(demonZeal.ConsiderDemonZeal() == NONE, 'Demon Zeal ignored health spent on cast')
print('PASS: Enigma respects extra Malefice ticks and Terrorblade uses Demon Zeal outside Metamorphosis')

local active, hp, mp = false, 0.4, 1
local feast = ability({})
feast.GetCastRange = function() return 125 end
feast.GetBehavior = function() return active and 8 or 2 end
local night = loadHero('night_stalker', {night_stalker_midnight_feast = feast}, {
    GetNearbyNeutralCreeps = function(_, range)
        assert(range == 125)
        return {ancient, normal}
    end,
}, {
    IsFarming = yes, GetHP = function() return hp end, GetMP = function() return mp end,
    GetProperCastRange = properRange, IsValid = yes, IsInRange = yes, IsRoshan = no, IsTormentor = no,
    CheckBitfieldFlag = function(behavior, flag) return behavior == flag end,
})
assert(night.ConsiderMidnightFeast() == NONE, 'ordered Midnight Feast while passive')
active = true
local feastDesire, meal = night.ConsiderMidnightFeast()
assert(feastDesire == HIGH and meal == normal, 'Midnight Feast must select a non-Ancient neutral')
hp = 0.9
assert(night.ConsiderMidnightFeast() == NONE, 'spent Midnight Feast with health and mana full enough')
print('PASS: Night Stalker uses Midnight Feast only when its active is available and useful')

local void = ability({damage = 100, duration_day = 1, duration_night = 2.5})
local targeted = false
local nightWithScepter = loadHero('night_stalker', {night_stalker_void = void}, {
    HasScepter = yes,
    Action_UseAbilityOnEntity = function(_, spell, target)
        assert(spell == void and target == enemy)
        targeted = true
    end,
}, {
    CanNotUseAbility = no, GetProperTarget = function() return enemy end,
    IsValidHero = yes, IsSuspiciousIllusion = no, CanCastOnNonMagicImmune = yes,
    GetNearbyHeroes = function() return {enemy} end, CheckTimeOfDay = function() return 'night' end,
    IsCastingUltimateAbility = no, CanKillTarget = yes,
})
nightWithScepter.ConsiderDarkAscension = function() return NONE end
nightWithScepter.ConsiderCripplingFear = function() return NONE end
nightWithScepter.SkillsComplement()
assert(targeted, 'Night Stalker ordered a ground cast on Void with Scepter')

local objective = {}
local seed = ability({})
local treant = loadHero('treant', {treant_leech_seed = seed}, {}, {
    GetProperTarget = function() return objective end, GetProperCastRange = properRange,
    IsGoingOnSomeone = no, IsRetreating = no, IsDoingRoshan = yes,
    IsRoshan = function(unit) return unit == objective end,
    IsInRange = yes, CanCastOnNonMagicImmune = yes, IsAttacking = yes,
})
local seedDesire, seedTarget = treant.ConsiderLeechSeed()
assert(seedDesire == HIGH and seedTarget == objective, 'Leech Seed did not target the objective')
print('PASS: Night Stalker and Treant keep current unit-target spell orders')

local retreating, shieldRaised, shieldOrder = false, false, nil
local facingPoint = {}
local bulwark = ability({})
bulwark.GetToggleState = no
bulwark.GetBehavior = function() return 16 end
local mars = loadHero('mars', {mars_bulwark = bulwark}, {
    HasScepter = yes,
    HasModifier = function(_, name) return shieldRaised and name == 'modifier_mars_bulwark_active' end,
    GetNearbyHeroes = function(_, _, isEnemy) return isEnemy and {enemy, enemy} or {{}} end,
    IsFacingLocation = yes,
    Action_UseAbilityOnLocation = function(_, spell, point)
        assert(spell == bulwark)
        shieldOrder = point
    end,
}, {
    CanNotUseAbility = no, CanCastAbility = yes, GetProperTarget = function() return enemy end,
    IsRetreating = function() return retreating end, IsRealInvisible = no,
    IsValidHero = yes, CanCastOnMagicImmune = yes, IsSuspiciousIllusion = no, IsDisabled = no,
    IsGoingOnSomeone = yes, IsInRange = yes,
    GetFaceTowardDistanceLocation = function() return facingPoint end,
    CheckBitfieldFlag = function(behavior, flag) return behavior == flag end,
})
mars.ConsiderSpearToAlly, mars.ConsiderArenaOfBlood = function() return NONE end, function() return NONE end
mars.ConsiderGodsRebuke, mars.ConsiderSpearOfMars = function() return NONE end, function() return NONE end
mars.SkillsComplement()
assert(shieldOrder == nil, 'Mars raised Bulwark for the old Scepter upgrade')
retreating = true
mars.SkillsComplement()
assert(shieldOrder == location, 'Mars should aim Bulwark at an enemy when covering an ally')
shieldRaised, retreating = true, false
mars.SkillsComplement()
assert(shieldOrder == facingPoint, 'Mars should lower the shield once the threat has passed')
print('PASS: Mars aims Bulwark and skips its obsolete Scepter behavior')
