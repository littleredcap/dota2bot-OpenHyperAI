-- Run the actual timer and settings with mocked engine dependencies.
local settings = dofile('bots/FretBots/SettingsDefault.lua')
local caps = settings.neutralItems.maxPerTier
assert(#caps == 4)
local bots, awards, closed = {[2] = {}, [3] = {}}, {}, {}
local removedTimer
for team = 2, 3 do
    for i = 1, caps[1] do
        bots[team][i] = {team = team, stats = {
            name = team .. ':' .. i, neutralsFound = 0, neutralTiming = 0,
        }}
    end
end

local function noop() end
local env = setmetatable({
    require = noop,
    dofile = function() return {} end,
    Debug = {IsDebug = function() return false end, Print = noop},
    Settings = settings,
    AllBots = bots,
    Utilities = {
        GetAbsoluteTime = function() return 3600 end,
        GetIntegerVariance = function() return 0 end,
        Print = noop,
        AnnounceNeutral = noop,
    },
    Timers = {RemoveTimer = function(_, name) removedTimer = name end},
    NeutralItems = {
        GetTokenTableForTier = function(_, tier)
            assert(tier >= 1 and tier <= 4, 'asked for an unsupported tier')
            return {{tier = tier, realName = 'mock neutral'}}
        end,
        GetBotDesireForItem = function() return 1 end,
        GiveToUnit = function(_, bot, item)
            awards[#awards + 1] = {team = bot.team, tier = item.tier}
        end,
        GetTimingDifficultyScaleShift = function() return 0 end,
        CloseBotFindTier = function(_, tier, team)
            closed[#closed + 1] = {team = team, tier = tier}
        end,
    },
}, {__index = _G})
setfenv(assert(loadfile('bots/FretBots/BonusTimers.lua')), env)()
local timers = env.BonusTimers

assert(not timers:IsFindingDone())
for tier = 1, 4 do
    for i = 1, caps[tier] do
        local before = #awards
        assert(timers:NeutralItemFindTimer() == 1)
        assert(#awards == before + 2, 'expected one award per team per tick')
        assert(awards[before + 1].team == 2 and awards[before + 1].tier == tier)
        assert(awards[before + 2].team == 3 and awards[before + 2].tier == tier)
    end
end
assert(timers:IsFindingDone(), 'configured caps should finish the timer')
assert(timers:NeutralItemFindTimer() == nil)
assert(removedTimer == 'NeutralItemFindTimer')
assert(#awards == 40 and #closed == 8)
for team = 2, 3 do
    for _, bot in ipairs(bots[team]) do
        assert(bot.stats.neutralsFound == 4 and bot.stats.neutralTiming == -1)
    end
    assert(#env.NeutralStash[team] == 4)
    assert(timers:GetNextItemToDole(team) == nil)
    local low, high = {tier = 1}, {tier = 4}
    env.NeutralStash[team][1][1] = low
    env.NeutralStash[team][4][1] = high
    assert(timers:GetNextItemToDole(team) == high)
    timers:RemoveItemFromStash(high, team)
    assert(timers:GetNextItemToDole(team) == low)
end
print('FretBots neutral timer: four tier caps, completion, and stash traversal passed')
