-- Run from the repository root: lua5.1 tests/test_7_42_leshrac_nihilism.lua
-- Load the production hero script; only the engine and common helpers are mocked.
local cases = 0
local NONE, HIGH = 0, 0.8

local function run(name, opts, expected)
    local applied, queried = 0, false
    local ability = {
        IsHidden = function() return opts.hidden == true end,
        IsTrained = function() return opts.untrained ~= true end,
        IsFullyCastable = function() return opts.unready ~= true end,
        GetSpecialValueInt = function(_, key)
            assert(key == 'radius')
            return opts.radius or 550
        end,
    }
    local bot = {
        edictPushing = false,
        GetAbilityByName = function(_, id)
            if id == 'leshrac_greater_lightning_storm' and not opts.missing then return ability end
        end,
        HasModifier = function() return false end,
        WasRecentlyDamagedByAnyHero = function(_, duration)
            assert(duration == 2)
            return opts.recent == true
        end,
        GetLocation = function() return {} end,
        GetHealth = function() return 100 end,
        Action_UseAbility = function(_, handle)
            assert(handle == ability, 'wrong cast handle')
            applied = applied + 1
        end,
    }
    local empty = function() return {} end
    local disabled = function() return false end
    local J = {
        Skill = { GetTalentList = empty, GetAbilityList = empty, GetTalentBuild = empty, GetSkillList = empty },
        Item = { GetRoleItemsBuyList = function() return 'pos_2' end },
        Role = { IsPvNMode = disabled, IsAllShadow = disabled },
        SetUserHeroInit = function(...) return ... end,
        CanNotUseAbility = disabled,
        GetProperTarget = function() return nil end,
        IsRetreating = function() return opts.retreat == true end,
        IsWithoutTarget = function() return true end,
        GetAttackProjectileDamageByRange = function() return 1000 end,
        GetEnemiesNearLoc = function(_, radius)
            assert(radius == 550)
            queried = true
            return opts.enemies
        end,
        IsValidHero = function(enemy) return not enemy.invalid end,
        CanCastOnNonMagicImmune = function(enemy) return not enemy.ineligible end,
        IsDisabled = function(enemy) return enemy.disabled == true end,
    }
    local chunk = assert(loadfile('bots/BotLib/hero_leshrac.lua'))
    setfenv(chunk, setmetatable({
        GetBot = function() return bot end,
        GetScriptDirectory = function() return 'bots' end,
        require = function() return J end,
        dofile = empty,
        RandomInt = function(first) return first end,
        BOT_ACTION_DESIRE_NONE = NONE,
        BOT_ACTION_DESIRE_HIGH = HIGH,
    }, { __index = _G }))
    local hero = chunk()
    -- Prevent the unrelated spells from consuming the decision first.
    for _, spell in ipairs({'PulseNova', 'LightningStorm', 'SplitEarth', 'DiabolicEdict'}) do
        hero['Consider' .. spell] = function() return NONE end
    end
    hero.SkillsComplement()
    assert(applied == expected, name .. ': expected ' .. expected .. ' cast(s), got ' .. applied)
    if opts.noQuery then assert(not queried, name .. ': unexpected enemy query') end
    cases = cases + 1
end

run('lethal incoming projectile alone does not trigger the removed ethereal save', {noQuery = true}, 0)
for _, unavailable in ipairs({'missing', 'hidden', 'untrained', 'unready'}) do
    run(unavailable, {[unavailable] = true, retreat = true, recent = true, enemies = {{}}, noQuery = true}, 0)
end
run('invalid radius', {radius = 0, retreat = true, recent = true, noQuery = true}, 0)
run('retreat without recent damage', {retreat = true, enemies = {{}}, noQuery = true}, 0)
run('nil enemy query', {retreat = true, recent = true}, 0)
run('ineligible or disabled heroes only', {
    retreat = true, recent = true, enemies = {{invalid = true}, {ineligible = true}, {disabled = true}},
}, 0)
run('eligible retreat threat uses the untargeted action once', {
    retreat = true, recent = true, enemies = {{ineligible = true}, {}},
}, 1)
print('PASS: ' .. cases .. ' Leshrac Nihilism production-script mock cases')
