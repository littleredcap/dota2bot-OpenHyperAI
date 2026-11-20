-- 7.42: Nature's Prophet Oldgrowth is now a passive, not an active cast.
-- Execute the production handle refresh and SkillsComplement.
local f = assert(io.open("bots/BotLib/hero_furion.lua", "rb"))
local code = assert(f:read("*a")); f:close()
local start = assert(code:find("local Sprout, Teleportation, NaturesCall", 1, true))
local finish = assert(code:find("\nfunction X.ConsiderSprout()", start, true))
local production = code:sub(start, finish-1)

local create = assert(loadstring([[
return function(options)
    options = options or {}
    local actions, lookedUp = {}, {}
    local X, bot, J = {}, {}, {}
    BOT_MODE_NONE = 0
    bot.useProphetTP = options.externalTP
    bot.ProphetTPLocation = options.externalTP and "location" or nil
    local aliases = {
        furion_sprout = "sprout",
        furion_teleportation = "tp",
        furion_force_of_nature = "natures",
        furion_wrath_of_nature = "wrath",
        furion_curse_of_the_forest = "legacy-oldgrowth",
    }
    function bot:GetAbilityByName(name)
        lookedUp[name] = true
        return aliases[name]
    end
    function J.CanCastAbility(handle) return handle ~= nil and handle ~= "legacy-oldgrowth" end
    function J.CanNotUseAbility() return options.cannotUse == true end
    function J.GetProperTarget() return nil end
    function J.GetHP() return 1 end
    function J.IsAttacking() return false end
    function J.SetQueuePtToINT() end
    function bot:GetNearbyHeroes() return {} end
    function bot:ActionQueue_UseAbilityOnEntity(ability, target)
        actions[#actions+1] = ability
    end
    function bot:ActionQueue_UseAbilityOnLocation(ability, target)
        actions[#actions+1] = ability
    end
    function bot:Action_UseAbilityOnLocation(ability)
        actions[#actions+1] = "immediate:" .. ability
    end
    function bot:Action_ClearActions() actions[#actions+1] = "clear" end
    function bot:ActionQueue_Delay() actions[#actions+1] = "delay" end
    function X.ConsiderSproutCall()
        if options.combo then return 1, "target", "place" end
        return 0, nil, nil
    end
    function X.ConsiderTeleportation() return 0, nil end
    function X.ConsiderSprout()
        if options.sprout then return 1, "target" end
        return 0, nil
    end
    function X.ConsiderNaturesCall() return 0, nil end
    function X.ConsiderWrathOfNature()
        if options.wrath then return 1, "target" end
        return 0, nil
    end
    -- The old branch would not cast a real passive; the test instead checks
    -- that the production refresh never asks for an obsolete active handle.
    function X.ConsiderCurseOfTheOldGrowth() return 0 end
]] .. production .. [[
    return {think=X.SkillsComplement, actions=actions, lookedUp=lookedUp}
end
]], "actual-furion-complement"))()

local function run(options, expected)
    local subject = create(options)
    subject.think()
    assert(not subject.lookedUp.furion_curse_of_the_forest, "Looked up the obsolete Oldgrowth active")
    assert(#subject.actions == #expected,
        "Expected "..#expected.." actions, got "..#subject.actions)
    for i=1,#expected do
        assert(subject.actions[i] == expected[i], "Unexpected action at "..i)
    end
end
run({}, {})
run({wrath=true}, {"wrath"})
run({sprout=true, wrath=true}, {"sprout"})
run({cannotUse=true, wrath=true}, {})
run({externalTP=true, wrath=true}, {"immediate:tp"})
run({combo=true, wrath=true}, {"clear", "sprout", "delay", "natures"})
assert(not code:find("CurseOfTheOldGrowth", 1, true), "Obsolete active cast branch remains")
print("6 Furion production-complement tests passed")
