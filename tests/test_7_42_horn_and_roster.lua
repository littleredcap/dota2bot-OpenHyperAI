local function section(path, first, after)
    local file = assert(io.open(path, 'rb'))
    local code = file:read('*a')
    file:close()
    local start = assert(code:find(first, 1, true))
    local stop = assert(code:find(after, start + #first, true))
    return code:sub(start, stop - 1)
end

local function no() return false end
local function yes() return true end
local function zero() return 0 end
local function empty() return {} end

local roster = {}
local human = {IsBot = no, GetMostRecentPing = function() return 'human ping' end}
local bot = {
    IsBot = yes, GetTeam = function() return 3 end, IsAlive = yes,
    GetHealth = function() return 50 end, GetMaxHealth = function() return 100 end,
    GetNearbyHeroes = function() return {{}, {}} end,
}
roster[2], roster[5] = human, bot
local players = {5, 6, 7, 8, 9}
local utils = {
    GetCachedVars = function() end, SetCachedVars = function() end,
    IsNearEnemySecondTierTower = function(unit) return unit == bot end,
}
local env = setmetatable({
    ____exports = utils, GetTeam = bot.GetTeam, GetTeamPlayers = function() return players end,
    GetTeamMember = function(slot)
        assert(slot >= 1 and slot <= 5, 'used a global player ID as a team slot')
        return roster[slot]
    end,
    GetUnitToUnitDistance = zero, GetAncient = empty, GetOpposingTeam = function() return 2 end,
    IsHeroAlive = function(playerID)
        assert(playerID >= 5 and playerID <= 9, 'used a team slot as a global player ID')
        return playerID == 9
    end,
    BotMode = {None = 0},
}, {__index = _G})
local utilsPath = 'bots/FunLib/utils.lua'
local utilCode = section(utilsPath, 'function ____exports.GetHumanPing()', 'function ____exports.IsPingedByAnyPlayer')
    .. section(utilsPath, 'function ____exports.GetNearbyAllyAverageHpPercent(', 'function ____exports.IsWithoutSpellShield')
    .. section(utilsPath, 'function ____exports.IsTeamPushingSecondTierOrHighGround(', 'function ____exports.GetNumOfAliveHeroes')
setfenv(assert(loadstring(utilCode)), env)()
local member, ping = utils.GetHumanPing()
assert(member == human and ping == 'human ping', 'missed a Dire human teammate')
assert(utils.IsTeamPushingSecondTierOrHighGround(bot), 'missed a Dire push')
roster[2] = nil
assert(utils.GetNearbyAllyAverageHpPercent(bot, 1200) == 0.5)
roster[5] = nil
assert(utils.GetNearbyAllyAverageHpPercent(bot, 1200) == 0, 'empty roster produced a bogus average')
print('PASS: Dire roster lookup uses team slots and handles an empty roster')

local function enemy(name, visible, illusion)
    return {CanBeSeen = function() return visible end, IsNull = no, IsAlive = yes, IsHero = yes,
        IsIllusion = function() return illusion end, GetUnitName = function()
            assert(visible, 'read a hidden hero')
            return name
        end}
end
local enemyCode = section('bots/FunLib/advanced_item_strategy.lua', 'local function getEnemyHeroes()',
    'local function applyHeroSpecificModifications')
env.UnitType = {EnemyHeroes = 700}
env.GetUnitList = function(kind)
    assert(kind == 700)
    return {enemy('seen', true, false), enemy('seen', true, false), enemy('hidden', false, false),
        enemy('illusion', true, true)}
end
local getEnemies = setfenv(assert(loadstring(enemyCode .. '\nreturn getEnemyHeroes')), env)()
local enemies = getEnemies()
assert(#enemies == 1 and enemies[1] == 'seen', 'enemy item strategy counted duplicates or hidden units')
print('PASS: adaptive item planning only uses unique visible enemy heroes')

local usagePath = 'bots/ability_item_usage_generic.lua'
local usageCode = section(usagePath, 'local battleHorn =', 'function X.IsWithoutSpellShield')
    .. section(usagePath, 'X.ConsiderItemDesire[battleHorn] = function()', 'X.ConsiderItemDesire["item_abyssal_blade"]')
    .. '\nreturn ItemUsageComplement'
local slots, casts = {}, {}
local horn = {GetName = function() return 'item_horn_of_battle_greater' end}
local defaultItem = {GetName = function() return 'test_item' end}
local pushing, supported = false, false
local x = {
    SetStashItemTimeUpdate = function() end, WillBreakInvisible = no, IsItemInStash = no,
    ConsiderItemDesire = {test_item = function() return 0.8, nil, 'none' end},
}
local carrier = {
    IsAlive = yes, IsMuted = no, IsHexed = no, IsStunned = no, IsChanneling = no, IsInvulnerable = no,
    IsUsingAbility = no, IsCastingAbility = no, NumQueuedActions = zero, HasModifier = no,
    GetNearbyTowers = empty, GetActiveMode = zero,
    GetItemInSlot = function(_, slot) return slots[slot] end,
    Action_UseAbility = function(_, item) table.insert(casts, {item}) end,
    Action_UseAbilityOnEntity = function(_, item, unit) table.insert(casts, {item, unit}) end,
}
env.bot, env.X = carrier, x
env.BOT_ACTION_DESIRE_NONE, env.BOT_ACTION_DESIRE_HIGH = 0, 0.8
env.J = {
    CanCastAbility = function(item) return item ~= nil end,
    HasItemConcealment = no,
    GetNearbyHeroes = empty, GetProperTarget = function() end, IsItemAvailable = function() end,
    IsPushing = function() return pushing end,
    Utils = {IsTeamPushingSecondTierOrHighGround = function() return supported end},
}
local useItems = setfenv(assert(loadstring(usageCode)), env)()
slots[6], slots[7] = horn, defaultItem
useItems()
pushing = true
useItems()
assert(#casts == 0, 'spent the Horn without support or used another item from the backpack')
supported = true
useItems()
assert(#casts == 1 and casts[1][1] == horn and casts[1][2] == nil, 'could not use the ready Horn from the backpack')
local unit = newproxy()
x.SetUseItem(defaultItem, unit, 'unit')
assert(#casts == 2 and casts[2][2] == unit, 'unit item orders lost userdata handles')
x.SetUseItem(defaultItem, 0, 'unit')
assert(#casts == 2, 'issued an item order to an invalid unit')
print('PASS: supported push uses the Battle Horn from the backpack and item targets accept unit handles')
