-- Load the complete production hero under minimal engine mocks.
local function run(opts)
    local function yes() return true end
    local function no() return false end
    local creep = {}
    local ally = {IsIllusion = no, IsAttackImmune = no, IsInvulnerable = no, HasModifier = no}
    local actions, lookedUp = {}, {}
    local abilities = {
        chen_penitence = {IsFullyCastable = no},
        chen_holy_persuasion = {
            IsFullyCastable = yes,
            GetCastRange = function() return 600 end,
            GetSpecialValueInt = function(_, key)
                assert(key == 'max_units' or key == 'level_req')
                return key == 'max_units' and 2 or 4
            end,
        },
        chen_divine_favor = {IsFullyCastable = no},
        chen_hand_of_god = {IsFullyCastable = function() return opts.heal == true end},
        chen_zealot = {IsFullyCastable = yes},
    }
    if opts.legacy then abilities.chen_summon_convert = {IsFullyCastable = yes} end
    local bot = {}
    function bot:GetAbilityByName(name)
        lookedUp[name] = true
        return abilities[name]
    end
    function bot:GetNearbyNeutralCreeps(range)
        assert(range == 600)
        return opts.neutral and {creep} or {}
    end
    function bot:Action_UseAbility(ability)
        actions[#actions + 1] = {kind = 'no_target', ability = ability}
    end
    function bot:Action_UseAbilityOnEntity(ability, target)
        actions[#actions + 1] = {kind = 'entity', ability = ability, target = target}
    end
    local function empty() return {} end
    local J = {
        Skill = {
            GetTalentList = empty, GetAbilityList = empty,
            GetTalentBuild = empty, GetSkillList = empty,
        },
        Item = {GetRoleItemsBuyList = function() return 'pos_4' end},
        Role = {IsPvNMode = no, IsAllShadow = no},
        SetUserHeroInit = function(...) return ... end,
        CanNotUseAbility = function() return opts.blocked == true end,
        GetProperTarget = function() return nil end,
        IsGoingOnSomeone = no, IsFarming = yes, IsAttacking = yes,
        IsValid = function(unit) return unit == creep end,
        IsValidHero = function(unit) return unit == ally end,
        IsCore = function(unit) return unit == ally end,
        GetHP = function(unit) assert(unit == ally); return 0.30 end,
        GetTeamFightLocation = function() return opts.heal and {} or nil end,
        GetAlliesNearLoc = function() return {ally} end,
    }
    local env = setmetatable({
        GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
        require = function() return J end, dofile = empty, GetUnitList = empty,
        UNIT_LIST_ALLIES = 1, UNIT_LIST_ALLIED_HEROES = 2,
        BOT_ACTION_DESIRE_NONE = 0, BOT_ACTION_DESIRE_HIGH = 0.8,
    }, {__index = _G})
    local hero = setfenv(assert(loadfile('bots/BotLib/hero_chen.lua')), env)()
    hero.SkillsComplement()
    return actions, lookedUp, abilities, creep
end

local function assertPersuasion(opts)
    local actions, _, abilities, creep = run(opts)
    assert(#actions == 1 and actions[1].kind == 'entity')
    assert(actions[1].ability == abilities.chen_holy_persuasion and actions[1].target == creep,
        'Holy Persuasion must still target the neutral creep, not Chen')
end

assertPersuasion({neutral = true})

do
    local actions, _, abilities = run({neutral = true, heal = true})
    assert(#actions == 1 and actions[1].kind == 'no_target')
    assert(actions[1].ability == abilities.chen_hand_of_god,
        'Hand of God retains priority over conversion')
end

-- The legacy ready handle used to steal priority from ordinary creep conversion.
assertPersuasion({neutral = true, legacy = true})
local actions, lookedUp = run({legacy = true})
assert(#actions == 0, 'obsolete summon and new Zealot must not inherit the old farming trigger')
assert(not lookedUp.chen_summon_convert and not lookedUp.chen_zealot,
    'removed summon and unimplemented Zealot must not be requested')
assert(#run({neutral = true, heal = true, blocked = true}) == 0,
    'inability to cast must still prevent actions')
print('PASS: 5 Chen production dispatch scenarios')
