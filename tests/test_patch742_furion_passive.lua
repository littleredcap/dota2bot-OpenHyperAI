-- 7.42: Nature's Prophet Oldgrowth is now a passive, not an active cast.
-- Test extracted production SkillsComplement, not a copied stub.
local f = assert(io.open("bots/BotLib/hero_furion.lua", "rb"))
local code = assert(f:read("*a")); f:close()
assert(not code:find("CurseOfTheOldGrowth", 1, true),
    "No active Oldgrowth state, consideration or cast should remain")
local start = assert(code:find("function X.SkillsComplement()", 1, true))
local finish = assert(code:find("\nfunction X.ConsiderSprout()", start, true))
local production = code:sub(start, finish-1)

local create = assert(loadstring([[
return function(options)
    options = options or {}
    local actions = {}
    local X, bot, J = {}, {}, {}
    BOT_MODE_NONE = 0
    Sprout, Teleportation, NaturesCall, WrathOfNature = "sprout", "tp", "natures", "wrath"
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
    function bot:Action_ClearActions() actions[#actions+1] = "clear" end
    function bot:ActionQueue_Delay() actions[#actions+1] = "delay" end
    function X.ConsiderSproutCall() return 0, nil, nil end
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
    local function RefreshAbilities() end
]] .. production .. [[
    return {think=X.SkillsComplement, actions=actions}
end
]], "actual-furion-complement"))()

local function run(options, expected)
    local subject = create(options)
    subject.think()
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
print("4 Furion production-complement tests passed")
