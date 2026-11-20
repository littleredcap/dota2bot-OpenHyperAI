-- Run the actual timer and settings with mocked engine dependencies.
local function fixture(radiant, dire)
    local settings = dofile('bots/FretBots/SettingsDefault.lua')
    local caps = settings.neutralItems.maxPerTier
    assert(#caps == 4)
    local bots, awards, closed = {[2] = {}, [3] = {}}, {}, {}
    local removedTimer
    local now = 3600
    for team = 2, 3 do
        for i = 1, team == 2 and radiant or dire do
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
            GetAbsoluteTime = function() return now end,
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
                -- Model the real cap closure for bots passed over by a quota.
                for _, bot in ipairs(bots[team]) do
                    if bot.stats.neutralsFound < tier then
                        bot.stats.neutralsFound = tier
                        bot.stats.neutralTiming = settings.neutralItems.timings[tier + 1] or -1
                    end
                end
            end,
        },
    }, {__index = _G})
    setfenv(assert(loadfile('bots/FretBots/BonusTimers.lua')), env)()
    local timers = env.BonusTimers
    return timers, caps, awards, closed, env,
        function(time) now = time end,
        function() return removedTimer end
end

local timers, caps, awards, closed, env, _, getRemovedTimer = fixture(5, 5)

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
assert(getRemovedTimer() == 'NeutralItemFindTimer')
assert(#awards == 40 and #closed == 8)
for team = 2, 3 do
    for _, bot in ipairs(env.AllBots[team]) do
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

local function finish(timers)
    assert(timers:IsFindingDone())
    assert(timers:NeutralItemFindTimer() == nil)
end

-- An exhausted short team does not manufacture a fifth award or cap closure.
do
    local partial, _, given, closures, state, _, removed = fixture(4, 5)
    for _ = 1, 20 do assert(partial:NeutralItemFindTimer() == 1) end
    assert(#given == 36 and #closures == 4)
    for _, closure in ipairs(closures) do assert(closure.team == 3) end
    for team = 2, 3 do
        for _, bot in ipairs(state.AllBots[team]) do
            assert(bot.stats.neutralsFound == 4 and bot.stats.neutralTiming == -1)
        end
    end
    finish(partial)
    assert(removed() == 'NeutralItemFindTimer')
end

-- Empty but initialized rosters are done; missing roster or stats aren't.
do
    local empty, _, given, _, state, _, removed = fixture(0, 0)
    state.AllBots[2] = nil
    assert(not empty:IsFindingDone() and empty:NeutralItemFindTimer() == 1)
    state.AllBots[2] = {{stats = {neutralsFound = 0}}}
    assert(not empty:IsFindingDone() and empty:NeutralItemFindTimer() == 1)
    state.AllBots[2] = {{}}
    assert(not empty:IsFindingDone() and empty:NeutralItemFindTimer() == 1)
    assert(removed() == nil and #given == 0)
    state.AllBots[2] = {}
    finish(empty)
    assert(removed() == 'NeutralItemFindTimer')
end

-- The lowest valid tier still blocks the next tier while a bot's time is pending.
do
    local delayed, _, given, _, state, setTime = fixture(1, 1)
    state.AllBots[3][1].stats.neutralTiming = 3601
    assert(delayed:NeutralItemFindTimer() == 1 and #given == 1)
    assert(not delayed:IsFindingDone())
    assert(delayed:NeutralItemFindTimer() == 1 and #given == 1)
    setTime(3601)
    assert(delayed:NeutralItemFindTimer() == 1 and #given == 2 and given[2].tier == 1)
end

-- A deliberately disabled bot does not block a ready bot or final shutdown.
do
    local disabled, _, given, _, state = fixture(1, 1)
    state.AllBots[3][1].stats.neutralTiming = -1
    for _ = 1, 4 do assert(disabled:NeutralItemFindTimer() == 1) end
    assert(#given == 4 and state.AllBots[3][1].stats.neutralsFound == 0)
    finish(disabled)
end

-- Preserve lower quotas and cap closure; don't replace a cap with roster size.
do
    local limited, customCaps, given, closures, state = fixture(2, 2)
    for tier = 1, 4 do customCaps[tier] = 1 end
    for _ = 1, 4 do assert(limited:NeutralItemFindTimer() == 1) end
    assert(#given == 8 and #closures == 8)
    for team = 2, 3 do
        assert(state.AllBots[team][2].stats.neutralTiming == -1)
    end
    finish(limited)
end

print('FretBots 4v5, empty/uninitialized rosters, pending/disabled bots, and custom quotas passed')
