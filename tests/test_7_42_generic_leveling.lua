local function yes() return true end
local function no() return false end
local function empty() return {} end

local function fixture(plan, custom)
    local state = {time = 60, points = 1, heroLevel = 6, ranks = {}, orders = {}, available = {}, position = 2}
    local abilities = {}
    for _, name in ipairs({'spell_a', 'spell_b', 'spell_c'}) do
        abilities[name] = {
            GetName = function() return name end,
            IsNull = function() return state.available[name] == 'null' end,
            IsHidden = function() return state.available[name] == 'hidden' end,
            GetLevel = function() return state.ranks[name] or 0 end,
            GetMaxLevel = function() return 4 end,
            GetHeroLevelRequiredToUpgrade = function() return 1 end,
            CanAbilityBeUpgraded = function() return state.available[name] ~= 'blocked' end,
        }
    end
    local function train(name)
        state.ranks[name] = (state.ranks[name] or 0) + 1
        state.points = state.points - 1
    end
    local bot = {
        IsInvulnerable = no, IsHero = yes, IsAlive = yes, IsIllusion = no,
        GetUnitName = function() return 'npc_dota_hero_test' end,
        GetLevel = function() return state.heroLevel end,
        GetLocation = empty, GetAbilityPoints = function() return state.points end,
        GetAbilityByName = function(_, name)
            if state.available[name] ~= 'absent' then return abilities[name] end
        end,
        ActionImmediate_LevelAbility = function(_, name)
            state.orders[#state.orders + 1] = name
            if not state.delay then train(name) end
        end,
    }
    local j = {
        GetUserHeroConfig = function() return custom end,
        IsStaleARDMHero = function() return false, bot, bot:GetUnitName() end,
        CanNotUseAbility = no, IsTryingtoUseAbility = no,
        GetPosition = function() return state.position end,
        Skill = {GetTalentList = empty, GetAbilityList = function() return {'spell_c'} end},
        Utils = {CombineTablesUnique = function(_, spells) return spells end},
    }
    local modules = {['bots/FunLib/jmz_func'] = j, ['bots/FunLib/oha_banish'] = {}, ['bots/FunLib/opening_rune'] = {},
        ['bots/Customize/general'] = {}, ['bots/FunLib/utils'] = {}, ['bots/FunLib/localization'] = {}}
    local env = setmetatable({
        GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
        require = function(path) return assert(modules[path], path) end,
        dofile = function() return {sSkillList = state.rolePlan or plan} end,
        GetTeam = function() return 2 end, Vector = empty, print = function() end,
        RandomInt = function(first) return first end,
        GetGameState = function() return 2 end, GetGameMode = function() return state.ardm and 20 or 1 end,
        GAME_STATE_PRE_GAME = 1, GAME_STATE_GAME_IN_PROGRESS = 2,
        DotaTime = function() return state.time end,
    }, {__index = _G})
    local usage = setfenv(assert(loadfile('bots/ability_item_usage_generic.lua')), env)()
    local function tick()
        if bot.lastLevelUpFrameProcessTime == nil then bot.lastLevelUpFrameProcessTime = state.time - 1 end
        state.time = state.time + 1.1
        usage.AbilityLevelUpThink()
    end
    return state, tick, train
end

do
    local plan = {'generic_hidden', 'spell_a', 'spell_b'}
    local state, tick, train = fixture(plan)
    for _, condition in ipairs({'absent', 'null', 'hidden', 'blocked'}) do
        state.available.spell_a = condition
        tick()
        assert(#state.orders == 0 and state.points == 1, 'hold the configured ability point while the skill is unavailable')
    end
    state.available.spell_a, state.delay = nil, true
    tick()
    tick()
    assert(#state.orders == 2 and state.orders[1] == 'spell_a' and state.orders[2] == 'spell_a', 'retry the unconfirmed rank')
    train('spell_a')
    tick()
    assert(#state.orders == 2 and state.points == 0)
    state.points, state.delay = 1, false
    tick()
    assert(state.orders[3] == 'spell_b' and #plan == 3, 'advance after the rank changes without mutating the build')
end

do
    local state, tick = fixture({'spell_a', [3] = 'spell_b'})
    state.ranks.spell_a = 4
    tick()
    assert(state.orders[1] == 'spell_b', 'skip permanently maxed skills and preserve entries after a sparse slot')
end

do
    local state, tick = fixture({'spell_a', 'spell_c'})
    tick()
    state.points, state.position = 1, 3
    state.rolePlan = {'spell_b', 'spell_a', 'spell_c'}
    tick()
    assert(state.orders[2] == 'spell_b', 'role changes keep the next untrained skill rather than dropping a level-sized prefix')
    state.points = 1
    tick()
    assert(state.orders[3] == 'spell_c', 'skip a skill previously trained under a different role')
end

do
    local state, tick = fixture({'spell_b'}, {AbilityUpgrade = {2}})
    state.heroLevel = 27
    tick()
    state.points = 1
    tick()
    assert(#state.orders == 1 and state.orders[1] == 'spell_b', 'do not replace an exhausted custom plan')
end

do
    local state, tick = fixture({'obsolete_spell'})
    state.ardm = true
    tick()
    tick()
    assert(#state.orders == 1 and state.orders[1] == 'spell_c', 'ARDM fallback chooses a currently legal ability')
end

do
    local state, tick = fixture({'obsolete_spell', 'spell_c'})
    tick()
    assert(#state.orders == 0, 'wait briefly before removing a missing default ability')
    for _ = 1, 7 do tick() end
    assert(state.orders[1] == 'spell_c' and state.points == 0, 'a permanent missing default entry cannot block later skills')
    local custom, customTick = fixture({'obsolete_spell', 'spell_c'}, {AbilityUpgrade = {2, 3}})
    for _ = 1, 8 do customTick() end
    assert(#custom.orders == 0 and custom.points == 1, 'do not substitute a skill into an explicit build')
end
print('PASS: generic leveling waits for availability and confirmation, rebuilds by actual ranks, and respects overrides')
