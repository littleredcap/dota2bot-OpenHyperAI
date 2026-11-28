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

local function loadHero(name, spells, bot, common, abilityOrder, role)
    bot.GetAbilityByName = function(_, spell) return spells[spell] end
    bot.GetAbilityInSlot = function() end
    common.Skill = {
        GetTalentList = empty, GetAbilityList = function() return abilityOrder or {} end,
        GetRandomBuild = function(builds) return builds[1] end,
        GetTalentBuild = empty, GetSkillList = function(_, build) return build or {} end,
    }
    common.Item = {GetRoleItemsBuyList = function() return role or 'pos_2' end}
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

do
    local tower = {GetLocation = function() return location end, GetAttackTarget = function() return enemy end}
    local pushing, nearbyAlly, overlapsChrono = {}, true, false
    local defenders = {{}, {}}
    local arena = loadHero('mars', {mars_arena_of_blood = ability({radius = 550, duration = 5})}, {
        GetLocation = function() return location end,
        GetNearbyTowers = function() return {tower} end,
        FindAoELocation = function() return {targetloc = location} end,
    }, {
        CanCastAbility = yes, GetProperCastRange = properRange, IsInTeamFight = no,
        IsDefending = yes, IsValidBuilding = yes, IsGoingOnSomeone = no, IsRetreating = no,
        GetEnemiesNearLoc = function() return pushing end,
        GetAlliesNearLoc = function() return nearbyAlly and defenders or {} end,
        IsInRange = yes, IsLocationInBlackHole = no, IsLocationInArena = no,
        IsLocationInChrono = function() return overlapsChrono end,
    })
    pushing = {{}, {}}
    assert(arena.ConsiderArenaOfBlood() == HIGH, 'Mars can protect a tower against a visible push')
    assert(table.concat(arena.sBuyList, ' '):find('item_blink item_desolator', 1, true))
    nearbyAlly = false
    assert(arena.ConsiderArenaOfBlood() == NONE, 'A lone tower defender should hold Arena')
    nearbyAlly, overlapsChrono = true, true
    assert(arena.ConsiderArenaOfBlood() == NONE, 'Tower defense still avoids overlapping Chronosphere')
end
print('PASS: Mars prioritizes Blink and uses Arena for a supported defense')

do
    local impale = ability({duration = 1.4, impale_damage = 140})
    impale.GetAOERadius = function() return 125 end
    local tower, mana, invisible = {}, 0.75, false
    local wave = {}
    local nyx = loadHero('nyx_assassin', {nyx_assassin_impale = impale}, {
        HasModifier = function() return invisible end,
        GetLocation = function() return {x = 0} end,
        GetNearbyTowers = function() return {tower} end,
        GetNearbyLaneCreeps = function() return wave end,
    }, {
        GetProperCastRange = properRange, GetProperTarget = function() end, GetNearbyHeroes = empty,
        IsGoingOnSomeone = no, IsRetreating = no, IsDefending = yes, IsValidBuilding = yes,
        IsValid = yes, IsInRange = yes, GetMP = function() return mana end, IsLaning = no,
        IsDoingRoshan = no, IsDoingTormentor = no,
        Site = {GetXUnitsTowardsLocation = function(_, target) return target end},
    })
    getfenv(nyx.ConsiderImpale).PointToLineDistance = function(_, aim, creep)
        return {within = true, distance = aim.y == creep.y and 0 or 200}
    end
    for i = 1, 4 do
        local lanePoint = {x = i * 100, y = i < 4 and 0 or 200}
        wave[i] = {GetExtrapolatedLocation = function() return lanePoint end}
    end
    local desire, aim = nyx.ConsiderImpale()
    assert(desire == HIGH and aim.y == 0, 'Nyx should line up the tower wave')
    mana = 0.4
    assert(nyx.ConsiderImpale() == NONE, 'Nyx should retain mana for hero control')
    mana, invisible = 0.75, true
    assert(nyx.ConsiderImpale() == NONE, 'Nyx should preserve Vendetta when the wave is the only target')
end
print('PASS: Nyx clears a lined-up tower wave while preserving Vendetta and low mana')

do
    local aim, enemyCreep, mana, lane, lastHit, waveCount = 100, {}, 250, true, false, 1
    local retreating, enemyInRange, reserve, deny, windingUp = false, true, false, false, false
    local holdTower, earlyTower, catapult = nil, nil, nil
    local casts, creepAim = {}, 700
    local shrapnel = ability({radius = 450, damage_delay = 1.2, duration = 10, AbilityCharges = 3, AbilityChargeRestoreTime = 35})
    shrapnel.GetAOERadius = function() return 450 end
    shrapnel.GetLevel = function() return 1 end
    shrapnel.IsInAbilityPhase = no
    shrapnel.GetManaCost = function() return 75 end
    local sniperBot = {
        clock = 100, IsInvisible = no, GetLevel = function() return 4 end,
        GetHealth = function() return 600 end, GetMaxHealth = function() return 600 end,
        GetMana = function() return mana end, GetMaxMana = function() return 300 end,
        GetAttackRange = function() return 600 end, GetAttackDamage = function() return 60 end,
        GetLocation = function() return 0 end, GetAssignedLane = function() return 2 end,
        WasRecentlyDamagedByAnyHero = no,
        GetNearbyLaneCreeps = function(_, _, enemy) return enemy and {enemyCreep} or (catapult and {catapult} or {}) end,
        GetNearbyTowers = empty,
        FindAoELocation = function() return (not lane or retreating) and {targetloc = aim} or nil end,
        ActionQueue_UseAbilityOnLocation = function(_, spell, point)
            assert(spell == shrapnel)
            casts[#casts + 1] = point
        end,
    }
    local sniper = loadHero('sniper', {sniper_shrapnel = shrapnel, sniper_assassinate = {IsTrained = no}}, sniperBot, {
        IsLaning = function() return lane end, IsInLaningPhase = yes, IsDefending = function() return not lane end,
        GetAssignedOuterTower = function() return holdTower end,
        GetEarlyMidSiegeDefense = function() return earlyTower end,
        IsKeyWordUnit = function(_, unit) return unit == catapult end,
        IsRetreating = function() return retreating end, IsGoingOnSomeone = no,
        GetNearbyHeroes = function() return {enemy} end,
        GetInLocLaneCreepCount = function() return waveCount end,
        IsValid = yes, IsValidHero = yes, CanBeAttacked = yes,
        IsInRange = function(_, target) return target ~= enemy or enemyInRange end,
        GetLaningAttackDamage = function() return 60 end,
        GetLaningLastHitTarget = function() return lastHit and enemyCreep or nil, false, reserve end,
        GetLaningDenyTarget = function() return deny and enemyCreep or nil end,
        IsAttacking = function() return windingUp end,
        CanCastOnNonMagicImmune = yes, IsSuspiciousIllusion = no,
        GetCorrectLoc = function(unit, delay) assert(delay == 1.5); return unit == enemyCreep and creepAim or aim end,
        GetLocationToLocationDistance = function(a, b) return math.abs(a - b) end,
        CanNotUseAbility = no, ConsiderForMkbDisassembleMask = no, GetProperTarget = no, SetQueuePtToINT = no,
    }, {[1] = 'sniper_shrapnel', [6] = 'sniper_assassinate'})
    assert(sniper.sSkillList[2] == 3 and sniper.sSkillList[4] == 1 and sniper.sSkillList[7] == 2)
    local buy = table.concat(sniper.sBuyList, ' ')
    assert(buy:find('item_dragon_lance item_maelstrom item_hurricane_pike item_mask_of_madness item_aghanims_shard', 1, true))
    local env = getfenv(sniper.ConsiderQ)
    env.GetUnitToLocationDistance = function(_, point) return math.abs(point) end
    env.LANE_MID, env.GetAmountAlongLane = 2, function() return {distance = 0} end
    sniper.ConsiderTarget = no
    sniper.ConsiderR, sniper.ConsiderE, sniper.ConsiderAS = function() return NONE end,
        function() return NONE end, function() return NONE end
    lastHit = true
    sniper.SkillsComplement()
    assert(#casts == 0, 'secure a reachable last hit before applying Shrapnel')
    lastHit, reserve = false, true
    sniper.SkillsComplement()
    assert(#casts == 0, 'reserve the next shot when a last hit will open soon')
    reserve, deny = false, true
    sniper.SkillsComplement()
    assert(#casts == 0, 'secure the deny before applying Shrapnel')
    deny, windingUp = false, true
    sniper.SkillsComplement()
    assert(#casts == 0, 'finish the attack windup before applying Shrapnel')
    windingUp = false
    sniper.SkillsComplement()
    assert(casts[1] == 100, 'use a spare Shrapnel charge on the contested lane wave even without an AoE search result')
    sniperBot.clock = 102
    sniper.SkillsComplement()
    assert(#casts == 2 and casts[2] == 100, 'allow a new cast after an order consumes no charge')
    mana, sniperBot.clock = 175, 103
    sniper.SkillsComplement()
    assert(sniper.IsAbiltyQCastedHere(100, 450))
    sniperBot.clock = 104
    sniper.SkillsComplement()
    assert(#casts == 2, 'do not spend a charge on an already covered wave')
    aim = 700
    sniper.SkillsComplement()
    assert(casts[3] == 700, 'a separate wave can be targeted while a zone is active')
    mana, sniperBot.clock = 100, 105
    sniper.SkillsComplement()
    assert(sniper.IsAbiltyQCastedHere(100, 450) and sniper.IsAbiltyQCastedHere(700, 450))
    sniperBot.clock = 115
    assert(not sniper.IsAbiltyQCastedHere(100, 450) and sniper.IsAbiltyQCastedHere(700, 450))
    aim, lane, waveCount = 100, false, 3
    sniper.SkillsComplement()
    assert(casts[4] == 100, 'defend an incoming tower wave after the prior zone expires')
    waveCount, lane, mana, sniperBot.clock = 0, true, 250, 132
    sniper.SkillsComplement()
    assert(#casts == 4, 'keep the last estimated charge while the first charge is replenishing')
    sniperBot.clock = 150
    sniper.SkillsComplement()
    assert(casts[5] == 400, 'cover a retreating enemy and the wave when their centers are too far apart')
    retreating, enemyInRange, aim, waveCount, sniperBot.clock = true, false, 750, 4, 185
    sniper.SkillsComplement()
    assert(casts[6] == 750, 'thin a contested wave without walking back into attack range')
    holdTower, retreating, lane, aim, waveCount, sniperBot.clock = {}, false, false, 100, 2, 201
    sniper.ConsiderR = function() error('clear the assigned wave before picking an ultimate target') end
    sniper.SkillsComplement()
    assert(casts[7] == 100, 'use the last planned wave clear even if there are only two creeps left')
    aim, creepAim, sniperBot.clock = 1500, 400, 225
    sniper.SkillsComplement()
    assert(casts[8] == 400, 'clear the assigned tower wave even when the engine AoE search picks another cluster')
    lane, earlyTower, holdTower, aim, waveCount, sniperBot.clock = true, {}, nil, nil, 2, 300
    sniperBot.FindAoELocation = function() return aim and {targetloc = aim} or nil end
    assert(sniper.ConsiderQ() > 0, 'clear the early siege near own mid before the team defense mode switches')
    earlyTower, aim, waveCount, lastHit, mana = nil, 410, 3, true, 280
    catapult = {GetLocation = function() return 390 end}
    assert(sniper.ConsiderQ() == NONE, 'escort cannot interrupt a secured last hit')
    lastHit = false
    local desire, point = sniper.ConsiderQ()
    assert(desire > 0 and point == 410, 'spare charge clears the wave stopping our siege creep')
end
print('PASS: Sniper balances last hits, lane pressure and distinct Shrapnel zones')

do
    local orders, laning = {}, true
    local enemyWarlock = {GetUnitName=function()return 'npc_dota_hero_warlock' end}
    local enemyWarlockPresent, pressLane = false, false
    local pressureEnemy = {GetTeam = function() return 3 end, HasModifier = no}
    local function ally(hp, core, pressured)
        local unit = {hp = hp, core = core, pressured = pressured, GetTeam = function() return 2 end}
        unit.IsIllusion = no
        unit.IsInvulnerable = function(self) return self.invulnerable == true end
        unit.HasModifier = function(self) return self.healing == true end
        unit.WasRecentlyDamagedByAnyHero = function(self) return self.pressured end
        return unit
    end
    local warlockBot, laneCore = ally(0.9, false, false), ally(0.76, true, true)
    warlockBot.IsInvisible, warlockBot.GetLevel, warlockBot.GetNearbyTowers = no, function() return 5 end, empty
    warlockBot.GetMana, warlockBot.GetMaxMana = function() return 400 end, function() return 500 end
    warlockBot.GetHealth, warlockBot.GetMaxHealth = function() return 540 end, function() return 600 end
    warlockBot.ActionQueue_UseAbilityOnEntity = function(_, spell, target) orders[#orders + 1] = {spell, target} end
    local word, bonds = ability({}), ability({})
    word.GetManaCost = function() return 100 end
    local freeToTrade = true
    local warlock = loadHero('warlock', {warlock_shadow_word = word, warlock_fatal_bonds = bonds}, warlockBot, {
        IsInLaningPhase = function() return laning end, IsInTeamFight = no, IsGoingOnSomeone = no, IsDefending = no,
        GetSideLaneSpellTradeTarget = function() return pressLane and pressureEnemy or nil end,
        CanSpendLaneTradeTime = function() return freeToTrade end,
        CanCastOnNonMagicImmune = yes, CanCastOnTargetAdvanced = yes,
        IsValidHero = yes, GetHP = function(unit) return unit.hp end, IsCore = function(unit) return unit.core end,
        GetNearbyHeroes = function(_, _, hostile)
            if hostile then return enemyWarlockPresent and {enemyWarlock} or {} end
            return {laneCore}
        end,
        IsItemAvailable = no, CanNotUseAbility = no, SetQueuePtToINT = no,
    }, {'warlock_fatal_bonds', 'warlock_shadow_word'})
    assert(warlock.sSkillList[2] == 2 and warlock.sSkillList[5] == 2)
    warlock.WarlockShouldMove = no
    warlock.ConsiderRFR, warlock.ConsiderR = function() return NONE end, function() return NONE end
    warlock.ConsiderQ = function() return HIGH, enemy end
    warlock.SkillsComplement()
    assert(orders[1][1] == word and orders[1][2] == laneCore, 'heal a pressured lane core before casting Bonds')
    laneCore.healing = true
    warlock.SkillsComplement()
    assert(orders[2][1] == bonds, 'do not reapply Shadow Word to a target already healing')
    laneCore.healing, laneCore.invulnerable = false, true
    warlockBot.hp = 0.6
    warlock.SkillsComplement()
    assert(orders[3][1] == word and orders[3][2] == warlockBot, 'heal self when the pressured ally is invulnerable')
    laneCore.invulnerable, warlockBot.hp, laning = false, 0.9, false
    warlock.SkillsComplement()
    assert(orders[4][1] == bonds, 'a lightly wounded core outside laning does not suppress offense')
    laneCore.hp, laneCore.healing, enemyWarlockPresent = 0.4, true, true
    laneCore.WasRecentlyDamagedByHero = function(_, enemy) return enemy == enemyWarlock end
    warlock.SkillsComplement()
    assert(orders[5][1] == word and orders[5][2] == laneCore,
        'a shared modifier name does not prove an active heal on a dying ally recently harmed by a visible enemy Warlock')
    pressLane, laning, laneCore.healing, laneCore.hp = true, true, false, 0.76
    warlock.SkillsComplement()
    assert(orders[6][2] == laneCore, 'defensive heal takes precedence even during a safe pressure window')
    laneCore.hp = 0.95
    warlock.SkillsComplement()
    assert(orders[7][1] == word and orders[7][2] == pressureEnemy,
        'apply Shadow Word to the exposed opponent instead of pushing the wave with Bonds')
    freeToTrade = false
    warlock.ConsiderQ = function() return NONE end
    assert(warlock.ConsiderW() == NONE, 'protect an upcoming last hit from an optional Shadow Word')
    freeToTrade = true
    warlockBot.GetMana = function() return 150 end
    assert(warlock.ConsiderW() == NONE, 'reserve a second Shadow Word to heal the core')
    laneCore.hp = 0.5
    assert(select(2, warlock.ConsiderW()) == laneCore, 'a needed heal keeps priority over resource protection')
end
print('PASS: Warlock learns and prioritizes useful lane healing')

do
    local spell = ability({search_aoe=400})
    spell.GetManaCost = function() return 120 end
    local target, creeps, enemies = nil, {}, {}
    local function unit(x) return {x=x, HasModifier=no} end
    local caster = unit(0)
    caster.IsInvisible, caster.GetLevel = no, function() return 9 end
    caster.GetHealth, caster.GetMaxHealth = function() return 800 end, function() return 900 end
    caster.GetMana, caster.GetMaxMana = function() return 400 end, function() return 600 end
    caster.ActionQueue_UseAbilityOnEntity=function(_, skill, other) assert(skill==spell);target=other end
    local tower
    local offering=ability({})
    offering.GetManaCost=function() return 240 end
    local warlock=loadHero('warlock',{warlock_fatal_bonds=spell,warlock_rain_of_chaos=offering},caster,{
        CanNotUseAbility=no,IsItemAvailable=no,SetQueuePtToINT=no,IsLaning=no,IsDefending=yes,
        GetAssignedOuterTower=function() return tower end,
        IsValidHero=yes,IsSuspiciousIllusion=no,IsValid=yes,CanBeAttacked=yes,
        CanCastOnNonMagicImmune=yes,CanCastOnTargetAdvanced=yes,
        IsInRange=function(a,b,r) return math.abs(a.x-b.x)<=r end,
        GetNearbyHeroes=function() return enemies end,
    },{'warlock_fatal_bonds',[6]='warlock_rain_of_chaos'})
    local env=getfenv(warlock.ConsiderQ)
    env.UNIT_LIST_ENEMY_CREEPS=7
    env.GetUnitList=function(team) assert(team==7);return creeps end
    local function skip() return NONE end
    warlock.WarlockShouldMove,warlock.ConsiderRFR,warlock.ConsiderR,warlock.ConsiderW,warlock.ConsiderE=no,skip,skip,skip,skip
    local isolated,front,follow=unit(-260),unit(620),unit(820)
    enemies={isolated,front,follow}
    warlock.SkillsComplement()
    assert(target==front,'Bonds must choose an in-range hero in the enemy cluster, even if another hero is closer')
    target,enemies=nil,{isolated}
    warlock.SkillsComplement()
    assert(not target,'a single enemy without hostile links cannot justify Bonds')
    creeps={unit(-250),unit(-240)}
    warlock.SkillsComplement()
    assert(target==isolated,'Bonds can link an actual tower attacker to its wave')
    tower,creeps,enemies,target={}, {unit(680)}, {unit(1020)}, nil
    creeps[1].GetAttackTarget=function() return tower end
    caster.WasRecentlyDamagedByAnyHero=no
    caster.GetNearbyLaneCreeps=function() return creeps end
    warlock.SkillsComplement()
    assert(target==creeps[1],'use the in-range tower creep to link the escort beyond direct cast range')
    target=nil
    caster.GetMana=function() return 300 end
    warlock.SkillsComplement()
    assert(not target,'the optional link cannot consume Offering mana')
end

do
    local bonds = ability({search_aoe = 400, count = 4})
    local word = ability({})
    bonds.GetManaCost, word.GetManaCost = function() return 120 end, function() return 100 end
    local function unit(x) return {x = x, HasModifier = no, GetHealth = function() return 300 end} end
    local caster, tower = unit(0), unit(-400)
    local badSeed, bridge, front = unit(530), unit(740), unit(795)
    local first, second = unit(900), unit(1100)
    local foes, creeps, allies, target = {first, second}, {badSeed, bridge, front}, {unit(760), unit(780)}
    local safe, free, covered, doomed, mana = true, true, true, nil, 260
    local function distance(a, b) return math.abs(a.x - b.x) end
    caster.IsInvisible, caster.GetLevel = no, function() return 4 end
    caster.GetHealth, caster.GetMaxHealth = function() return 600 end, function() return 600 end
    caster.GetMana, caster.GetMaxMana = function() return mana end, function() return 400 end
    caster.GetNearbyTowers, caster.GetNearbyLaneCreeps = empty, function(_, _, enemy) return enemy and creeps or allies end
    caster.ActionQueue_UseAbilityOnEntity = function(_, spell, chosen) assert(spell == bonds); target = chosen end
    local warlock = loadHero('warlock', {warlock_fatal_bonds = bonds, warlock_shadow_word = word}, caster, {
        IsLaning = yes, CanNotUseAbility = no, IsItemAvailable = no, SetQueuePtToINT = no,
        CanSpendLaneTradeTime = function() return free end,
        GetTowerCoveredLaneClash = function() if covered then return tower, 795 end end,
        GetVisibleLaneClash = function() return 795 end,
        CanTradeAtLaneClash = function() return safe end,
        GetTotalAttackWillRealDamage = function(creep) return creep == doomed and 350 or 0 end,
        IsValidHero = yes, IsValid = yes, CanBeAttacked = yes, IsSuspiciousIllusion = no,
        CanCastOnNonMagicImmune = yes, CanCastOnTargetAdvanced = yes,
        IsInRange = function(a, b, radius) return distance(a, b) <= radius end,
        GetNearbyHeroes = function() return foes end,
    }, {'warlock_fatal_bonds', 'warlock_shadow_word'})
    local env = getfenv(warlock.ConsiderQ)
    env.GetUnitToUnitDistance = distance
    env.GetUnitToLocationDistance = function(unit, point) return math.abs(unit.x - point) end
    local function skip() return NONE end
    warlock.WarlockShouldMove, warlock.ConsiderRFR, warlock.ConsiderR, warlock.ConsiderW, warlock.ConsiderE =
        no, skip, skip, skip, skip
    warlock.SkillsComplement()
    assert(target == bridge, 'cast from a creep that reaches both enemy heroes within the link limit')
    target, covered = nil, false
    caster.GetTeam, first.GetTeam = function() return 2 end, function() return 3 end
    warlock.ConsiderW = function() return HIGH, first, true end
    warlock.SkillsComplement()
    assert(target == bridge, 'take a multi-hero Bonds window outside tower cover before optional Shadow Word')
    warlock.ConsiderW, covered = skip, true
    doomed, target = bridge, nil
    warlock.SkillsComplement()
    assert(target == badSeed, 'skip a preferred bridge that will already be dead at cast time')
    foes, doomed, target = {first}, nil, nil
    warlock.SkillsComplement()
    assert(target, 'one hero and multiple creeps can justify a covered defensive lane link')
    allies, target = {unit(700), unit(720), unit(740), unit(760)}, nil
    warlock.SkillsComplement()
    assert(not target, 'save single-hero Bonds when it would push an already stronger allied wave')
    foes, safe = {first, second}, false
    assert(warlock.ConsiderQ() == NONE, 'respect the retaliation estimate')
    safe, free = true, false
    assert(warlock.ConsiderQ() == NONE, 'do not cast over a reserved last hit')
    free, mana = true, 210
    assert(warlock.ConsiderQ() == NONE, 'leave enough mana to heal the core')
end
print('PASS: Warlock forecasts visible lane bounces, picks the best seed, and protects mana and lane position')

do
    local near, orders = true, {}
    local spell, bonds = ability({aoe=500}), ability({})
    spell.GetManaCost, bonds.GetManaCost = function() return 250 end, function() return 100 end
    local a, b = {x=110}, {x=310}
    local caster = {GetLocation=function()return 0 end, GetLevel=function()return 9 end, IsInvisible=no,
        GetHealth=function()return 850 end, GetMaxHealth=function()return 900 end,
        GetMana=function()return 500 end, GetMaxMana=function()return 600 end,
        FindAoELocation=function()return {count=3,targetloc=0} end,
        ActionQueue_UseAbilityOnLocation=function(_, ability) orders[#orders+1]=ability end}
    local warlock = loadHero('warlock', {warlock_fatal_bonds=bonds,warlock_rain_of_chaos=spell}, caster,
        {CanNotUseAbility=no, IsItemAvailable=no, SetQueuePtToINT=no, GetNearbyHeroes=empty, IsGoingOnSomeone=no,
            GetEnemyList=function() return near and {a,b} or {a,{x=950}} end},
        {'warlock_fatal_bonds',[6]='warlock_rain_of_chaos'})
    getfenv(warlock.ConsiderR).GetUnitToLocationDistance = function(unit, point) return math.abs(unit.x-point) end
    warlock.WarlockShouldMove, warlock.ConsiderRFR = no, function()return NONE end
    warlock.ConsiderW, warlock.ConsiderQ, warlock.ConsiderE = function()return NONE end, function()return NONE end, function()return NONE end
    warlock.SkillsComplement()
    assert(orders[1] == spell, 'two actual targets can justify Chaotic Offering with Bonds still castable')
    near = false
    warlock.SkillsComplement()
    assert(#orders == 1, 'unit or illusion count in the AoE does not substitute for clustered heroes')
end

do
    local mana, threatened, order = 420, false, nil
    local caster = {GetLocation = empty, GetLevel = function() return 9 end, IsInvisible = no,
        GetMana = function() return mana end, GetMaxMana = function() return 600 end,
        GetHealth = function() return 800 end, GetMaxHealth = function() return 900 end,
        ActionQueue_UseAbilityOnLocation = function(_, spell, point) order = {spell, point} end,
        FindAoELocation = function() return {count = 2, targetloc = location} end}
    local enemyFront = {GetAttackRange = function() return 450 end,
        GetAttackTarget = function() if threatened then return caster end end}
    local slow, golem = ability({aoe = 500}), ability({})
    slow.GetManaCost, golem.GetManaCost = function() return 100 end, function() return 250 end
    local warlock = loadHero('warlock', {warlock_fatal_bonds = ability({}), warlock_shadow_word = ability({}),
        warlock_upheaval = slow, warlock_rain_of_chaos = golem}, caster, {
        CanNotUseAbility = no, IsItemAvailable = no, SetQueuePtToINT = no,
        GetNearbyHeroes = function() return {enemyFront} end, IsInTeamFight = yes, IsValidHero = yes,
        IsRetreating = no, IsDisabled = no, IsInRange = yes, IsChasingTarget = no, IsDefending = no,
    }, {'warlock_fatal_bonds', 'warlock_shadow_word', 'warlock_upheaval', [6] = 'warlock_rain_of_chaos'})
    warlock.WarlockShouldMove = no
    local function noTarget() return NONE end
    warlock.ConsiderRFR, warlock.ConsiderR, warlock.ConsiderW, warlock.ConsiderQ = noTarget, noTarget, noTarget, noTarget
    getfenv(warlock.ConsiderE).BOT_ACTION_DESIRE_LOW = 0.3
    warlock.SkillsComplement()
    assert(order and order[1] == slow and order[2] == location, 'channel on a group when the other ready spells have no target')
    order, threatened = nil, true
    warlock.SkillsComplement()
    assert(order == nil, 'do not start a channel when an enemy in reach is attacking the caster')
    threatened, mana = false, 300
    warlock.SkillsComplement()
    assert(order == nil, 'keep enough mana for a ready golem')
end

do
    local tower = {x = 900, GetLocation = function() return 900 end, GetTeam = function() return 3 end, HasModifier = no}
    local wave, towerGuarded, pushing, allies = true, false, true, 0
    local shamanBot = {GetAttackTarget = function() end, WasRecentlyDamagedByAnyHero = no,
        GetNearbyTowers = function() return {tower} end, GetNearbyBarracks = empty,
        GetNearbyLaneCreeps = function() return wave and {{x = 800}, {x = 825}} or {} end}
    local common = {IsRetreating = no, IsPushing = function() return pushing end,
        IsValidBuilding = function(unit) return unit == tower end, IsValid = yes, CanBeAttacked = yes,
        IsInRange = function(a, b, r) return math.abs(a.x - b.x) <= r end,
        GetUnitTowardDistanceLocation = function(building, _, r) return building.x - r end,
        GetEnemiesNearLoc = function() return towerGuarded and {enemy} or {} end,
        GetAvailableFightAllies = function() return allies end}
    local shaman = loadHero('shadow_shaman', {}, shamanBot, common)
    local env = getfenv(shaman.GetSiegeWardTarget)
    env.GetUnitToLocationDistance = function(_, point) return point end
    env.GetAncient, env.GetOpposingTeam, env.IsLocationPassable = no, function() return 3 end, yes
    local building, location = shaman.GetSiegeWardTarget(700)
    assert(building == tower and location == 660, 'place siege wards within cast range and near the tower')
    tower.HasModifier = function(_, modifier) return modifier == 'modifier_backdoor_protection_in_base' end
    assert(shaman.GetSiegeWardTarget(700) == tower, 'the inactive backdoor marker does not block siege wards')
    tower.HasModifier = function(_, modifier) return modifier == 'modifier_backdoor_protection_active' end
    assert(shaman.GetSiegeWardTarget(700) == nil, 'save wards while backdoor protection is active')
    tower.HasModifier = no
    assert(shaman.GetSiegeWardTarget(650) == nil)
    towerGuarded = true
    assert(shaman.GetSiegeWardTarget(700) == nil, 'avoid unsupported casts into defenders')
    towerGuarded, pushing, allies = false, false, 1
    assert(shaman.GetSiegeWardTarget(700) == tower, 'a safe wave and ally can open the siege before push mode activates')
    allies = 0
    assert(shaman.GetSiegeWardTarget(700) == nil, 'no proactive cast if the support has no cover')
    pushing = true
    towerGuarded, wave = false, false
    assert(shaman.GetSiegeWardTarget(700) == nil, 'wait for allied creeps before committing siege wards')

    local order
    local ward = {x = 515, GetAttackRange = function() return 600 end,
        Action_AttackUnit = function(_, target) order = target end}
    local utility = {GetWeakestHero = function(range) assert(range == 600); return enemy end, IsNotAllowedToAttack = no}
    local wardEnv = setmetatable({GetScriptDirectory = function() return 'bots' end,
        require = function(name) return name:find('jmz_func', 1, true) and common or utility end,
        GetUnitToUnitDistance = function(a, b) return math.abs(a.x - b.x) end}, {__index = _G})
    local wards = setfenv(assert(loadfile('bots/FunLib/minion_lib/attacking_wards.lua')), wardEnv)()
    shamanBot.ohaSerpentWardSiegeTarget = tower
    tower.HasModifier = function(_, modifier) return modifier == 'modifier_backdoor_protection_in_base' end
    wards.Think(shamanBot, ward)
    assert(order == tower, 'siege wards prioritize a reachable tower using the ward attack range')
    tower.HasModifier = function(_, modifier) return modifier == 'modifier_fountain_glyph' end
    wards.Think(shamanBot, ward)
    assert(order == enemy, 'protected structures fall back to a combat target')
end
print('PASS: Shaman plans a safe siege and serpent wards use their own attack range')

do
    local shackle, shock = ability({}), ability({})
    local core, rival, interrupter = {}, {}, {GetAttackRange=function()return 500 end}
    local risky, order = false, nil
    local caster = {GetLevel=function()return 3 end, GetMana=function()return 280 end, GetMaxMana=function()return 300 end,
        GetHealth=function()return 540 end, GetMaxHealth=function()return 640 end, GetLocation=empty,
        IsInvisible=no,WasRecentlyDamagedByAnyHero=no,
        ActionQueue_UseAbilityOnEntity=function(_, spell, target) order={spell,target} end}
    local j = {CanNotUseAbility=no, GetProperTarget=no, GetAlliesNearLoc=empty, IsItemAvailable=no, SetReportMotive=no, SetQueuePtToINT=no,
        IsInLaningPhase=yes, CanCastAbility=yes, GetLanePartner=function()return core end, IsValidHero=yes,
        IsSuspiciousIllusion=no, IsDisabled=no, IsInRange=yes,
        GetNearbyHeroes=function() return risky and {rival,interrupter} or {rival} end,
        GetLaningPeelTarget=function(_, partner) assert(partner==core); return rival end}
    local shaman = loadHero('shadow_shaman',{shadow_shaman_shackles=shackle,shadow_shaman_ether_shock=shock},caster,j,
        {'shadow_shaman_ether_shock',[3]='shadow_shaman_shackles'})
    shaman.ConsiderW, shaman.ConsiderR = function()return NONE end,function()return NONE end
    shaman.ConsiderQ = function()return HIGH, rival end
    shaman.SkillsComplement()
    assert(order[1]==shackle and order[2]==rival, 'safe lane peel takes precedence over damage')
    risky=true
    shaman.SkillsComplement()
    assert(order[1]==shock, 'avoid channeling if another enemy can punish the support')
    shackle.GetLevel, shackle.GetManaCost = function() return 3 end, function() return 100 end
    caster.GetAttackDamage, caster.GetActiveMode = function() return 70 end, function() return 0 end
    rival.IsChanneling, rival.IsDisarmed, interrupter.IsChanneling = no, no, no
    j.IsInLaningPhase, j.IsInTeamFight, j.IsRetreating, j.IsTaunted = no, no, no, no
    j.IsGoingOnSomeone, j.HasCommittedStunFollowUp = yes, yes
    j.CanCastOnNonMagicImmune, j.CanCastOnTargetAdvanced = yes, yes
    j.GetProperTarget, j.Chat = function() return rival end, {GetNormName=function() return 'rival' end}
    shaman.ConsiderQ = function() return NONE end
    order=nil
    shaman.SkillsComplement()
    assert(not order, 'an exposed Shaman does not start a voluntary channel in a later fight')
    risky=false
    shaman.SkillsComplement()
    assert(order and order[1]==shackle, 'shackle when the dangerous second hero has gone')
    order, risky, rival.IsChanneling=nil, true, yes
    shaman.SkillsComplement()
    assert(order and order[1]==shackle, 'a necessary channel interrupt still takes priority')
end

do
    local targetDistance, protected = 580, false
    local creep = {HasModifier = function() return protected end, GetLocation = function() return location end}
    local clearer = {GetNearbyLaneCreeps = function(_, radius)
        return targetDistance <= radius and {creep} or {}
    end}
    local shock = ability({damage = 190, start_radius = 200})
    shock.GetCastRange, shock.GetLevel, shock.GetManaCost = function() return 600 end, function() return 2 end, function() return 105 end
    local shaman = loadHero('shadow_shaman', {shadow_shaman_ether_shock = shock}, clearer, {
        IsValid = yes, GetNearbyHeroes = function() return {enemy} end, CanCastOnNonMagicImmune = no,
        IsDefending = yes, GetAssignedOuterTower = function() return {} end,
        GetInLocLaneCreepCount = function() return 2 end, IsInTeamFight = no, IsGoingOnSomeone = no,
        IsRetreating = no, IsLaning = no, IsFarming = no, IsPushing = no, IsAllowedToSpam = no,
        IsDoingRoshan = no, IsDoingTormentor = no,
    }, {'shadow_shaman_ether_shock'})
    local desire, target = shaman.ConsiderQ()
    assert(desire == HIGH and target == creep, 'clear the assigned wave with a visible enemy on the same lane')
    targetDistance = 730
    assert(shaman.ConsiderQ() == NONE, 'do not walk up to cast a short targeted spell into a siege')
    targetDistance, protected = 580, true
    assert(shaman.ConsiderQ() == NONE, 'save the cast while the wave is protected by glyph')
end

do
    local canClaim, pressure, pending, mana, attackETA = true, false, false, 290, 0.68
    local target = {HasModifier=no}
    local shock, shackle = ability({damage=140}), ability({})
    shock.GetCastRange, shock.GetLevel, shock.GetManaCost = function() return 600 end, function() return 1 end, function() return 100 end
    shackle.GetManaCost = function() return 120 end
    local order
    local caster = {GetLocation=empty, GetNearbyTowers=empty, GetLevel=function() return 3 end, IsInvisible=no,
        GetMana=function() return mana end, GetMaxMana=function() return 300 end,
        GetHealth=function() return 560 end, GetMaxHealth=function() return 700 end,
        GetNearbyLaneCreeps=function() return {target} end,
        ActionQueue_UseAbilityOnEntity=function(_, spell, creep) order={spell,creep} end}
    local j = {
        CanNotUseAbility=no, GetProperTarget=no, GetAlliesNearLoc=function() return {caster,{}} end,
        IsItemAvailable=no, SetReportMotive=no, SetQueuePtToINT=no, GetNearbyHeroes=empty,
        CanCastAbility=no, IsValid=yes, IsValidHero=no, IsDefending=no, IsInLaningPhase=yes,
        IsInTeamFight=no, IsGoingOnSomeone=no, IsRetreating=no, IsLaning=yes,
        GetLaningPeelTarget=function() end, GetLanePartner=no, GetSideLaneSpellTradeTarget=no, GetSideLaneDuoTrade=no,
        HasPendingLaningLastHit=function() return pending end, IsLaningUnderPressure=function() return pressure end,
        CanBeAttacked=yes, IsKeyWordUnit=function(key) return key=='_ranged' end, IsInRange=yes,
        GetAttackProDelayTime=function() return attackETA end,
        CanSecureLaneCreepWithSpell=function(_,creep,damage,kind,delay)
            assert(creep==target and damage==140 and kind==MAGICAL and delay==0.3)
            return canClaim
        end,
        IsCore=no, IsPushing=no, IsFarming=no, IsDoingRoshan=no, IsDoingTormentor=no,
    }
    local shaman = loadHero('shadow_shaman',{shadow_shaman_ether_shock=shock,shadow_shaman_shackles=shackle},
        caster,j,{'shadow_shaman_ether_shock',[3]='shadow_shaman_shackles'},'pos_5')
    shaman.ConsiderW, shaman.ConsiderR, shaman.ConsiderE = function() return NONE end,
        function() return NONE end, function() return NONE end
    shaman.SkillsComplement()
    assert(order and order[1]==shock and order[2]==target,'secure the unclaimed ranged creep even with the lane partner nearby')
    order, canClaim = nil, false
    shaman.SkillsComplement()
    assert(not order,'preserve the core last hit')
    canClaim, pressure = true, true
    shaman.SkillsComplement()
    assert(not order,'skip a threatened creep')
    pressure, pending = false, true
    shaman.SkillsComplement()
    assert(not order,'preserve a launched creep order')
    pending, mana = false, 215
    shaman.SkillsComplement()
    assert(not order,'retain mana for shackles')
    mana, attackETA = 290, 0.39
    shaman.SkillsComplement()
    assert(not order,'prefer a timely normal attack')
end

do
    local knight = loadHero('dragon_knight', {}, {}, {}, nil, 'pos_3')
    assert(knight.sSkillList[4] == 1 and knight.sSkillList[7] == 1, 'offlane build ranks Breathe Fire for wave clear')
    assert(table.concat(knight.sBuyList, ' '):find('item_blink item_black_king_bar item_crimson_guard', 1, true))
    local king = loadHero('skeleton_king', {}, {}, {}, nil, 'pos_1')
    assert(king.sSkillList[2] == 3 and king.sSkillList[7] == 3, 'carry build ranks Mortal Strike for last hits')
    assert(table.concat(king.sBuyList, ' '):find('item_boots item_helm_of_iron_will item_phase_boots item_armlet item_blink item_black_king_bar', 1, true))
end

do
    local shot = {x = 400, GetLocation = function() return 400 end,
        GetUnitName = function() return 'npc_dota_creep_badguys_ranged' end}
    local tower = {x = 700, HasModifier = no, GetTeam = function() return 3 end, GetLocation = function() return 700 end}
    local pushing, defending, alliedWave, incoming, order = false, false, 0, false, nil
    local breath = ability({end_radius = 250, damage = 100, speed = 1000})
    breath.GetManaCost = function() return 100 end
    local form = ability({})
    local dragon = {x = 0, GetAttackRange = function() return 150 end, HasModifier = no,
        GetLocation = function() return 0 end, GetNearbyHeroes = empty, GetNearbyTowers = function() return {tower} end,
        GetNearbyCreeps = function() return {shot} end, FindAoELocation = function() return {count=0} end,
        GetNearbyLaneCreeps = function(_, radius, hostile)
            if hostile then return incoming and radius > 800 and {{x=930}, {x=960}, {x=990}, {x=1020}} or {} end
            local creeps = {}
            for i=1,alliedWave do creeps[i] = {x=660 - 20 * i} end
            return creeps
        end,
        GetAttackTarget = function() return pushing and tower or nil end,
        ActionQueue_UseAbilityOnLocation = function(_, spell, place) order = {spell, place} end,
        Action_MoveToLocation = function(_, place) order = {'move', place} end,
        ActionQueue_UseAbility = function(_, spell) order = {spell} end}
    local common = {CanNotUseAbility = no, CanCastAbility = function(spell) return spell ~= nil end,
        IsAttacking = no, GetHP = function() return 1 end, GetProperTarget = no,
        IsGoingOnSomeone = no, IsRetreating = no, IsInTeamFight = no, IsFarming = no,
        IsPushing = function() return pushing end, IsDefending = function() return defending end,
        GetAssignedOuterTower = function() return defending and tower or nil end,
        GetAvailableFightAllies = function() return 1 end, GetEnemiesNearLoc = empty,
        IsDoingRoshan = no, IsDoingTormentor = no,
        IsLaning = function() return not pushing end, IsInLaningPhase = yes, IsValid = yes, CanBeAttacked = yes,
        GetSideLaneDuoTrade = function() end,
        IsValidBuilding = function(unit) return unit == tower end, IsValidHero = no,
        IsInRange = function(a,b,r) return math.abs(a.x-b.x) <= r end, GetProperCastRange = properRange,
        GetManaAfter = function() return 0.85 end, GetManaThreshold = function() return 0.2 end,
        WillKillTarget = function(unit, damage) return unit == shot and damage == 100 end,
        SetQueuePtToINT = no}
    local dk = loadHero('dragon_knight', {dragon_knight_breathe_fire = breath, dragon_knight_elder_dragon_form = form},
        dragon, common, nil, 'pos_3')
    local env = getfenv(dk.SkillsComplement)
    env.Min, env.GetOpposingTeam = math.min, function() return 3 end
    dk.SkillsComplement()
    assert(order and order[1] == breath and order[2] == 400, 'use Breathe Fire for a ranged last hit during the actual laning phase')
    pushing, alliedWave, order = true, 2, nil
    tower.HasModifier = function(_, modifier) return modifier == 'modifier_backdoor_protection' end
    dk.SkillsComplement()
    assert(order and order[1] == form, 'use Dragon Form once allied creeps reach the tower after its wave is gone')
    tower.HasModifier = function(_, modifier) return modifier == 'modifier_backdoor_protection_active' end
    assert(dk.ConsiderElderDragonForm() == NONE, 'save Dragon Form against active protection')
    pushing, alliedWave, tower.HasModifier = false, 3, no
    assert(dk.ConsiderElderDragonForm() == HIGH, 'start a clean siege with live cover even before push mode')
    defending, alliedWave, incoming = true, 0, true
    assert(dk.ConsiderElderDragonForm() == HIGH, 'prepare to clear the actual incoming wave at the assigned tower')
    incoming = false
    assert(dk.ConsiderElderDragonForm() == NONE, 'an assignment alone does not use Dragon Form')
    defending=false
    local ally={x=200,GetAttackRange=function() return 600 end}
    local foe={x=580,HasModifier=no,GetLocation=function(self) return self.x end}
    common.IsValidHero=function(unit) return unit==ally or unit==foe end
    common.GetLanePartner=function() return ally end
    common.IsCore,common.HasPendingLaningLastHit,common.IsLateGame=no,no,no
    common.GetSideLaneSpellTradeTarget=function(caster,enemies)
        assert(caster==dragon and enemies[1]==foe)
        return foe
    end
    common.CanSpendLaneTradeTime=function() return not common.HasPendingLaningLastHit() end
    common.CanCastOnNonMagicImmune,common.GetCorrectLoc=yes,function(unit) return unit.x end
    dragon.GetNearbyCreeps=empty
    dragon.GetNearbyHeroes=function(_,_,hostile) return hostile and {foe} or {ally} end
    dk.ConsiderElderDragonForm=function() return NONE end
    order=nil
    dk.SkillsComplement()
    assert(order and order[1]==breath and order[2]==580,'Breathe Fire can contest a covered enemy on a wave without a creep kill')
    common.HasPendingLaningLastHit=yes
    assert(dk.ConsiderBreatheFire()==NONE,'the optional trade cannot steal a pending last hit')
    order, common.HasPendingLaningLastHit = nil, no
    common.GetSideLaneDuoTrade=function(caster,enemies,_,_,_,stepBudget,linkedOnly)
        assert(caster == dragon and enemies[1] == foe and linkedOnly and stepBudget == 145)
        return foe, 110
    end
    dk.SkillsComplement()
    assert(order and order[1]=='move' and order[2]==110,'make a bounded approach before following up a link')
    common.GetSideLaneDuoTrade=function() return foe end
    dk.SkillsComplement()
    assert(order and order[1]==breath and order[2]==580,'cast on the linked target once in range')
    defending = true
    common.GetManaAfter = function() return 0.12 end
    common.GetInLocLaneCreepCount = function() return 2 end
    dragon.FindAoELocation = function() return {count=2, targetloc=400} end
    env.GetUnitToLocationDistance = function() return 250 end
    env.DotaTime = function() return 500 end
    dragon.ohaTowerWaveCast = {tower=tower, expires=501}
    local desire, place = dk.ConsiderBreatheFire()
    assert(desire==HIGH and place==400, 'use affordable fire to clear the wave at the safely reached post')
    dragon.ohaTowerWaveCast.expires = 499
    assert(dk.ConsiderBreatheFire()==NONE, 'the brief wave assignment does not relax the reserve after expiry')
end

do
    local spell = ability({damage = 80, blast_speed = 1200})
    spell.GetManaCost = function() return 95 end
    spell.GetLevel = function() return 1 end
    local creep = {x = 400, hp = 75}
    local target, visibleThreat
    local wkBot = {x = 0, IsInvisible = no, GetLevel = function() return 4 end,
        GetMana = function() return 180 end, GetMaxMana = function() return 250 end,
        GetHealth = function() return 500 end, GetMaxHealth = function() return 800 end,
        GetAttackRange = function() return 150 end, GetActiveMode = function() return 7 end,
        GetNearbyLaneCreeps = function() return {creep} end, WasRecentlyDamagedByAnyHero = no,
        ActionQueue_UseAbilityOnEntity = function(_, used, unit) assert(used == spell); target=unit end}
    local wk = loadHero('skeleton_king', {skeleton_king_hellfire_blast = spell}, wkBot, {
        CanNotUseAbility = no, IsDefending = no, IsRetreating = no, IsFarming = no, IsValidHero = no, HasPendingLaningLastHit = yes,
        GetLaningPeelTarget = function() end,
        GetNearbyHeroes = function(_, range, hostile)
            return visibleThreat and range == 1600 and hostile and {enemy} or {}
        end,
        IsGoingOnSomeone = no, IsInTeamFight = no, IsValid = yes, CanBeAttacked = yes, IsKeyWordUnit = yes,
        IsInRange = function(a,b,r) return math.abs(a.x-b.x) <= r end, SetQueuePtToINT = no,
        WillKillTarget = function(unit, damage, _, delay)
            assert(unit == creep and damage == 80 and math.abs(delay - (0.3 + 400 / 1200)) < 0.001)
            return unit.hp <= damage
        end,
    }, nil, 'pos_1')
    local env = getfenv(wk.SkillsComplement)
    env.BOT_MODE_LANING = 7
    assert(wk.sSkillList[1] == 1 and wk.sSkillList[2] == 3 and wk.sSkillList[3] == 2,
        'start the carry with the stun and still learn the other basic abilities by level three')
    wk.SkillsComplement()
    assert(target == creep, 'use the real blast damage to secure a ranged creep WK cannot safely hit')
    target, creep.hp = nil, 95
    wk.SkillsComplement()
    assert(target == nil, 'do not waste mana on a creep above the initial blast damage')
    visibleThreat, creep.hp = true, 75
    wk.SkillsComplement()
    assert(target == nil, 'a visible enemy increases the need to reserve a defensive stun')
    visibleThreat, wkBot.ohaLaningAttackTarget = false, creep
    wk.SkillsComplement()
    assert(target == nil, 'do not interrupt a reserved last-hit windup with an optional stun')
    local common = env.require('bots/FunLib/jmz_func')
    local attacker = {x=500}
    common.IsDefending=yes
    common.GetMidDefensePokeTarget=function(_,reach) assert(reach<spell:GetCastRange()); return attacker end
    common.IsDisabled=no
    common.CanCastOnNonMagicImmune,common.CanCastOnTargetAdvanced=yes,yes
    wkBot.GetMana=function() return 240 end
    local desire, unit=wk.ConsiderQ()
    assert(desire>0 and unit==attacker,'a covered in-range siege attacker can be stunned before a team attack starts')
    common.IsDisabled=yes
    assert(wk.ConsiderQ()==NONE,'do not overlap the existing disable for optional tower poke')
end
do
    local file = assert(io.open('bots/BotLib/hero_dragon_knight.lua','rb'))
    local source = file:read('*a')
    file:close()
    local start = assert(source:find('function X.ConsiderDragonTail()', 1, true))
    local finish = assert(source:find('function X.ConsiderFireball()', start, true))
    local target = {x=195, HasModifier=no, IsChanneling=no}
    local follow, bonded, pending, mana = target, false, false, 240
    local support = {x=160, GetAttackRange=function() return 580 end, GetAttackTarget=function() return follow end}
    local bot = {x=0, GetMana=function() return mana end, GetCurrentMovementSpeed=function() return 300 end,
        GetNearbyTowers=empty, WasRecentlyDamagedByAnyHero=no}
    local tail = {GetCastRange=function() return 200 end, GetCastPoint=function() return 0.3 end,
        GetManaCost=function() return 90 end, GetSpecialValueInt=function() return 0 end}
    local breath = {GetManaCost=function() return 100 end}
    local distance = function(a,b) return math.abs(a.x-b.x) end
    local env = setmetatable({X={}, bot=bot, DragonTail=tail, BreatheFire=breath, nEnemyHeroes={target},
        GetUnitToUnitDistance=distance, BOT_ACTION_DESIRE_NONE=NONE, BOT_ACTION_DESIRE_HIGH=HIGH,
        J={CanCastAbility=yes, GetProperCastRange=function(_,_,range) return range end,
            GetManaAfter=function() return 0.7 end, GetManaThreshold=function() return 0.4 end,
            IsValidHero=yes, CanBeAttacked=yes, IsInRange=function(a,b,r) return distance(a,b) <= r end,
            CanCastOnNonMagicImmune=yes, CanCastOnTargetAdvanced=yes, IsLaning=yes, IsRetreating=no,
            HasPendingLaningLastHit=function() return pending end, GetLanePartner=function() return support end,
            GetSideLanePressureTarget=function(unit) assert(unit == support); return target end,
            GetSideLaneSpellTradeTarget=no, GetSideLaneDuoTrade=function() return bonded and target or nil end,
            CanSpendLaneTradeTime=yes,
            IsDisabled=no, IsInTeamFight=no, IsGoingOnSomeone=no, IsDoingRoshan=no, IsDoingTormentor=no},
    }, {__index=_G})
    setfenv(assert(loadstring(source:sub(start,finish-1))),env)()
    local desire, unit = env.X.ConsiderDragonTail()
    assert(desire == HIGH and unit == target, 'Dragon Tail follows a safe support trade already in range')
    follow = nil
    assert(env.X.ConsiderDragonTail() == NONE, 'do not stun without the support trade')
    bonded = true
    assert(select(2, env.X.ConsiderDragonTail()) == target, 'follow a safe Bonds opening before an allied attack target exists')
    bonded = false
    follow, pending = target, true
    assert(env.X.ConsiderDragonTail() == NONE, 'do not break a protected last-hit windup')
    pending, mana = false, 170
    assert(env.X.ConsiderDragonTail() == NONE, 'keep enough mana to use Breathe Fire')
    mana, target.x = 240, 201
    assert(env.X.ConsiderDragonTail() == NONE, 'do not walk forward to force the optional stun')
end
print('PASS: Dragon Knight and Wraith King secure lane creeps, and Dragon Form converts a clean siege')

do
    local wards, hex = ability({}), ability({})
    wards.GetManaCost, wards.GetAbilityDamage = function() return 200 end, function() return 0 end
    wards.GetLevel = function() return 1 end
    local hp, immediateChase, hexAvailable, casts, teamCanCounter = 700, false, false, 0, false
    local bot = {
        IsInvisible = no, GetLevel = function() return 12 end,
        GetMana = function() return 400 end, GetMaxMana = function() return 800 end,
        GetHealth = function() return hp end, GetMaxHealth = function() return 1000 end,
        GetLocation = empty, WasRecentlyDamagedByHero = yes,
        ActionQueue_UseAbilityOnLocation = function() error('a retreat ultimate should not queue behind movement') end,
        Action_UseAbilityOnLocation = function(_, spell, point)
            assert(spell == wards and point == 420)
            casts = casts + 1
        end,
    }
    local shaman = loadHero('shadow_shaman', {shadow_shaman_mass_serpent_ward = wards, shadow_shaman_voodoo = hex}, bot, {
        CanNotUseAbility = no, IsItemAvailable = no, GetProperTarget = no,
        GetNearbyHeroes = function() return {enemy} end, GetAlliesNearLoc = empty,
        IsRetreating = yes, IsGoingOnSomeone = no, IsValidHero = yes, IsDisabled = no, IsInRange = yes, IsInLaningPhase = no,
        IsChasingTarget = function() return immediateChase end,
        GetSupportCounterfightPoint = function() return teamCanCounter and 420 or nil end,
        CanCastAbility = function(ability) return ability == hex and hexAvailable end,
        CanCastOnMagicImmune = yes, CanCastOnNonMagicImmune = yes, CanCastOnTargetAdvanced = yes,
        Chat = {GetNormName = function() return 'test' end}, SetQueuePtToINT = no, SetReportMotive = no,
    }, {[2] = 'shadow_shaman_voodoo', [6] = 'shadow_shaman_mass_serpent_ward'})
    getfenv(shaman.SkillsComplement).IsLocationPassable = yes
    shaman.ConsiderW, shaman.ConsiderQ, shaman.ConsiderE = function() return NONE end, function() return NONE end, function() return NONE end
    shaman.SkillsComplement()
    assert(casts == 0, 'a healthy retreat keeps wards')
    hp = 320
    shaman.SkillsComplement()
    assert(casts == 0, 'recent damage without an immediate pursuer does not use wards')
    immediateChase, hexAvailable = true, true
    shaman.SkillsComplement()
    assert(casts == 0, 'reserve wards if a short disable is ready')
    hexAvailable = false
    shaman.SkillsComplement()
    assert(casts == 0, 'do not drop wards just for a lone pursuer')
    teamCanCounter = true
    shaman.SkillsComplement()
    assert(casts == 1, 'cast immediately when a teammate can still counterattack')
end

do
    local file = assert(io.open('bots/BotLib/hero_warlock.lua', 'rb'))
    local source = file:read('*a')
    file:close()
    local first = assert(source:find('local sRoleItemsBuyList = {}', 1, true))
    local needle = "X['sBuyList'] = sRoleItemsBuyList[sRole]"
    local last = assert(source:find(needle, first, true)) + #needle
    local function build(role, enabled)
        local env = setmetatable({sRole=role, J={Customize={TestWarlockEarlyMek=enabled}}, X={}}, {__index=_G})
        setfenv(assert(loadstring(source:sub(first,last-1))),env)()
        local items = {}
        for i, item in ipairs(env.X.sBuyList) do items[item] = i end
        return items
    end
    assert(not build('pos_4', false).item_mekansm, 'control build must stay unchanged')
    local trial = build('pos_4', true)
    assert(trial.item_arcane_boots < trial.item_mekansm and trial.item_mekansm < trial.item_glimmer_cape
        and trial.item_glimmer_cape < trial.item_guardian_greaves, 'only advance Mekansm in the trial')
    assert(not build('pos_5', true).item_mekansm, 'do not change other roles')
    print('PASS: Warlock early Mekansm A/B is opt-in and position-specific')
end
