-- Run the actual hero dispatchers and item Consider functions. Only hero
-- candidate proposals and engine state are mocked; the common guard is real.
local function read(path)
    local f = assert(io.open(path, 'rb'))
    local result = assert(f:read('*a'))
    f:close()
    return result
end

local function section(path, first, last)
    local code = read(path)
    local start = assert(code:find(first, 1, true))
    local stop = assert(code:find(last, start + #first, true))
    return code:sub(start, stop - 1)
end

local function no() return false end
local function yes() return true end
local function empty() return {} end
local itemCode = section('bots/ability_item_usage_generic.lua',
    'X.ConsiderItemDesire["item_cyclone"] =', 'X.ConsiderItemDesire["item_dagon"] =')
local guardPath = 'bots/FunLib/oha_banish.lua'
local guardFile = io.open(guardPath, 'rb')
local Banish
if guardFile then
    guardFile:close()
    Banish = dofile(guardPath)
end

local function environment(opts)
    local bot, enemy, friend = {}, {}, {}
    local actions = {}
    local function setup(unit, team, id)
        function unit:GetTeam() return team end
        function unit:GetPlayerID() return id end
        function unit:GetLocation() return {} end
        unit.HasModifier, unit.IsDisarmed, unit.IsIllusion = no, no, no
        unit.CanBeSeen = yes
        unit.IsChanneling = function() return unit == enemy and opts.channel == true end
    end
    setup(bot, 2, 1); setup(enemy, 3, 3); setup(friend, 2, 2)
    function enemy:GetCurrentMovementSpeed() return opts.running and 480 or 300 end
    friend.GetAttackTarget = function() return enemy end
    friend.GetAttackRange = function() return 200 end
    bot.WasRecentlyDamagedByAnyHero = yes
    function bot:Action_UseAbilityOnEntity(ability, target)
        actions[#actions + 1] = {ability, target}
    end
    local J = {
        CanNotUseAbility = no, IsValid = function(u) return u ~= nil end,
        IsValidHero = function(u) return u ~= nil end,
        GetNearbyHeroes = empty, GetAlliesNearLoc = function() return opts.focus and {friend} or {} end,
        GetHP = function(u) return u == bot and (opts.self and 0.1 or 1) or 0.4 end,
        IsDisabled = no, IsInRange = yes, CanCastOnNonMagicImmune = yes,
        IsCastingUltimateAbility = no, IsSuspiciousIllusion = no,
        IsGoingOnSomeone = function() return opts.combo == true end,
        IsRunning = function() return opts.running == true end,
        GetMP = function() return 1 end, Chat = {GetNormName = function() return 'unit' end},
    }
    return setmetatable({
        X = {ConsiderItemDesire = {}, IsWithoutSpellShield = yes},
        J = J, bot = bot, Banish = Banish, enemy = enemy, friend = friend,
        botName = opts.combo and 'npc_dota_hero_invoker' or 'npc_dota_hero_test',
        botTarget = enemy, aetherRange = 0, hNearbyEnemyHeroList = opts.self and {enemy} or {},
        BOT_ACTION_DESIRE_NONE = 0, BOT_ACTION_DESIRE_HIGH = 0.8,
    }, {__index = _G}), actions
end

local function dispatchHero(name, opts)
    local od = name == 'obsidian_destroyer'
    local code = section('bots/BotLib/hero_' .. name .. '.lua',
        'function X.SkillsComplement()', od and 'function X.ConsiderArcaneOrb()' or 'function X.ConsiderDisruption()')
    local env, actions = environment(opts)
    local candidate = opts.save and env.friend or env.enemy
    local main = od and 'AstralImprisonment' or 'Disruption'
    local fallback = od and 'ArcaneOrb' or 'DemonicCleanse'
    env[main] = main
    env[fallback] = od and {IsTrained = no} or fallback
    env.X['Consider' .. main] = function() return 0.8, candidate, opts.intent end
    env.X['Consider' .. fallback] = function() return 0.6, env.friend end
    for _, spell in ipairs({'Objurgation','SanitysEclipse','DemonicPurge','Disseminate','ShadowPoison','ShadowPoisonRelease'}) do
        env.X['Consider' .. spell] = function() return 0 end
    end
    setfenv(assert(loadstring(code)), env)()
    env.X.SkillsComplement()
    assert(#actions == 1)
    return actions[1][1], actions[1][2], env, main, env[fallback]
end

for _, hero in ipairs({'obsidian_destroyer','shadow_demon'}) do
    local actual, target, env, main, fallback = dispatchHero(hero, {focus = true})
    assert(actual == fallback and target == env.friend, hero .. ': block offensive candidate, continue dispatch')
    actual, target, env, main = dispatchHero(hero, {focus = true, save = true})
    assert(actual == main and target == env.friend, hero .. ': retain ally save')
    actual, target, env, main = dispatchHero(hero, {focus = true, channel = true})
    assert(actual == main and target == env.enemy, hero .. ': retain channel interrupt')
    actual, target, env, main = dispatchHero(hero, {focus = true, intent = 'PEEL'})
    assert(actual == main and target == env.enemy, hero .. ': retain proposed defensive peel')
    actual, target, env, main = dispatchHero(hero, {intent = 'STOP_ESCAPE'})
    assert(actual == main and target == env.enemy, hero .. ': retain unopposed catch')
end

local function item(name, opts)
    local env = environment(opts)
    setfenv(assert(loadstring(itemCode)), env)()
    local desire, target, castType = env.X.ConsiderItemDesire[name]({})
    if desire > 0 then assert(castType == 'unit') end
    return desire, target, env
end

for _, name in ipairs({'item_cyclone', 'item_wind_waker'}) do
    assert(item(name, {focus = true, running = true}) == 0, name .. ': hold escape cast against focus')
    assert(item(name, {focus = true, combo = true}) == 0, name .. ': hold Invoker setup against focus')
    local desire, target, env = item(name, {running = true})
    assert(desire > 0 and target == env.enemy, name .. ': retain chase')
    desire, target, env = item(name, {combo = true})
    assert(desire > 0 and target == env.enemy, name .. ': retain setup')
    desire, target, env = item(name, {focus = true, channel = true, running = true})
    assert(desire > 0 and target == env.enemy, name .. ': retain channel interrupt')
    desire, target, env = item(name, {focus = true, running = true, self = true})
    assert(desire > 0 and target == env.bot, name .. ': retain self save after offensive candidate is held')
end
print('PASS: 22 OD, SD, Eul and Wind Waker production dispatch scenarios')
