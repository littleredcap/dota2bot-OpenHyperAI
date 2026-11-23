-- Run the real ability-slot resolver, hero build and customization loader.
local heroName = 'obsidian_destroyer'
local orb = heroName .. '_arcane_orb'
local astral = heroName .. '_astral_imprisonment'
local objurgation = heroName .. '_objurgation'
local eclipse = heroName .. '_sanity_eclipse'
local notLearnable = 64

local function ability(name, behavior, hidden, ultimate, talent)
    return {
        GetName = function() return name end,
        GetBehavior = function() return behavior or 0 end,
        IsHidden = function() return hidden end,
        IsUltimate = function() return ultimate end,
        IsTalent = function() return talent end,
    }
end

local slots = {
    [0] = ability(orb),
    [1] = ability(astral),
    [2] = ability(objurgation),
    [3] = ability('generic_hidden'),
    [4] = ability(heroName .. '_equilibrium', notLearnable, true),
    [5] = ability(eclipse, nil, nil, true),
    [6] = ability(heroName .. '_essence_aura', notLearnable, true),
}
for i = 1, 8 do
    slots[i + 8] = ability('special_bonus_test_' .. i, nil, nil, nil, true)
end

local bot = {
    GetUnitName = function() return 'npc_dota_hero_' .. heroName end,
    GetAbilityInSlot = function(_, slot) return slots[slot] end,
    GetAbilityByName = function(_, name)
        for _, handle in pairs(slots) do
            if handle:GetName() == name then return handle end
        end
    end,
}

local function loadHero(config)
    local modules = {
        ['bots/FunLib/utils'] = { AbilityBehaviorHasFlag = function(behavior, flag) return behavior == flag end },
        ['bots/FunLib/aba_item'] = { GetRoleItemsBuyList = function() return 'pos_2' end },
        ['bots/FunLib/aba_role'] = { IsPvNMode = function() return false end, IsAllShadow = function() return false end },
        ['game/Customize/hero/' .. heroName] = config,
    }
    local env = setmetatable({
        GetBot = function() return bot end,
        GetScriptDirectory = function() return 'bots' end,
        GetTeam = function() return 2 end,
        GetTeamPlayers = function() return {} end,
        Vector = function() return {} end,
        RandomInt = function(first) return first end,
        dofile = function() return {} end,
        print = function() end,
        require = function(name) return modules[name] or {} end,
    }, { __index = _G })
    modules['bots/FunLib/aba_skill'] = setfenv(assert(loadfile('bots/FunLib/aba_skill.lua')), env)()
    modules['bots/FunLib/jmz_func'] = setfenv(assert(loadfile('bots/FunLib/jmz_func.lua')), env)()
    return setfenv(assert(loadfile('bots/BotLib/hero_obsidian_destroyer.lua')), env)()
end

local default = loadHero().sSkillList
local expected = {astral, orb, objurgation, astral, astral, eclipse, astral, orb, orb,
    'special_bonus_test_2', orb, eclipse, objurgation, objurgation, 'special_bonus_test_4', objurgation, eclipse}
for i, name in ipairs(expected) do
    assert(default[i] == name, 'default skill ' .. i .. ': expected ' .. name .. ', got ' .. tostring(default[i]))
end

local config = {
    Enable = true,
    AbilityUpgrade = {1, 3, 2, 3, 3, 6, 3, 1, 1, 1, 6, 2, 2, 2, 6},
    Talent = {'r', 'l', 'r', 'l'},
    PurchaseList = {'item_boots'},
    SellList = {'item_tango'},
}
local custom = loadHero(config)
assert(custom.sSkillList[1] == orb and custom.sSkillList[2] == objurgation and custom.sSkillList[3] == astral)
assert(custom.sSkillList[10] == 'special_bonus_test_1', 'custom talent order was ignored')
assert(custom.sBuyList == config.PurchaseList and custom.sSellList == config.SellList, 'custom items were ignored')
print('PASS: OD default Objurgation build and enabled custom build')
