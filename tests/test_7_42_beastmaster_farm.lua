-- Run from the repository root with Lua 5.1. Load the real generated module.
local DOMINATOR = 'item_helm_of_the_dominator'
local BKB = 'item_black_king_bar'
local inventory, checked, netWorth
local bot = {
    GetNetWorth = function() return netWorth end,
}
local types = {BotModeDesire = {}, UnitType = {}, BotMode = {}, Team = {}, Tower = {}, Rune = {}, Shop = {}}
local chunk = assert(loadfile('bots/FunLib/aba_site.lua'))
setfenv(chunk, setmetatable({
    GetScriptDirectory = function() return 'bots' end,
    Vector = function() return {} end,
    GetUnitList = function() return {} end,
    GetBot = function() return bot end,
    require = function(module)
        if module == 'bots/ts_libs/dota/index' then return types end
        assert(module == 'bots/FunLib/utils', 'unexpected module: ' .. module)
        return {HasItem = function(unit, item)
            assert(unit == bot)
            checked[#checked + 1] = item
            return inventory[item] == true
        end}
    end,
}, {__index = _G}))
local site = chunk()
local farmForItems = site.ConsiderIsTimeToFarm.npc_dota_hero_beastmaster

local cases = {
    {'both 7.42 items end the hero-specific farm request', 13000, true, true, false},
    {'no helm before the helm threshold', 13999, false, true, true},
    {'the helm threshold is exclusive', 14000, false, true, false},
    {'owned helm does not bypass the BKB requirement', 13999, true, false, true},
    {'BKB gate still applies above the helm threshold', 17999, false, false, true},
    {'the BKB threshold is exclusive', 18000, false, false, false},
}

for _, case in ipairs(cases) do
    netWorth = case[2]
    inventory = {[DOMINATOR] = case[3], [BKB] = case[4]}
    checked = {}
    local actual = farmForItems()
    assert(actual == case[5], case[1] .. ': expected ' .. tostring(case[5]) .. ', got ' .. tostring(actual))
    assert(checked[1] == DOMINATOR, case[1] .. ': must check the 7.42 build item')
    if #checked > 1 then assert(#checked == 2 and checked[2] == BKB, case[1] .. ': BKB gate changed') end
end
print('PASS: ' .. #cases .. ' Beastmaster item-based farm cases')
