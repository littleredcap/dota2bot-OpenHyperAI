-- Patch 7.42 compatibility regressions. Run from repository root:
-- lua5.1 tests/test_patch742_compat.lua
-- These use production function bodies with mocked Dota APIs; no game client.
local function readFile(path)
    local f = assert(io.open(path, "rb"), "Cannot read " .. path)
    local src = assert(f:read("*a"))
    f:close()
    return src
end

local function extractFunction(path, startMarker, endMarker)
    local src = readFile(path)
    local a = assert(src:find(startMarker, 1, true), "Missing marker " .. startMarker)
    local b = assert(src:find(endMarker, a + #startMarker, true), "Missing marker " .. endMarker)
    return src:sub(a, b - 1)
end

local function equal(actual, expected, desc)
    if actual ~= expected then
        error(desc .. " (expected=" .. tostring(expected) .. ", got=" .. tostring(actual) .. ")", 2)
    end
end

local tests = {}
local function test(name, fn)
    tests[#tests + 1] = {name = name, run = fn}
end

local meepoPath = "bots/BotLib/hero_meepo.lua"
local meepoSource = readFile(meepoPath)

test("removed MegaMeepo and old Fling actions are no longer referenced", function()
    -- The 7.42 Shard pickup/Fling is a new active with different semantics.
    assert(not meepoSource:find("GetAbilityByName('meepo_megameepo')", 1, true))
    assert(not meepoSource:find("GetAbilityByName('meepo_megameepo_fling')", 1, true))
    assert(not meepoSource:find("function X.ConsiderMegaMeepo()", 1, true))
    assert(not meepoSource:find("function X.ConsiderMegaMeepoFling()", 1, true))
end)

test("Meepo default builds do not spend gold on the unvalidated 7.42 Shard", function()
    -- This checks active source references, not comments or user overrides.
    local code = meepoSource:gsub("%-%-[^\r\n]*", "")
    assert(not code:find('"item_aghanims_shard"', 1, true),
        "Meepo default buy lists still purchase unvalidated Shard")
end)

local skillsSource = extractFunction(
    meepoPath,
    "function X.SkillsComplement()",
    "\nfunction X.ConsiderEarthBind()"
)
local digSource = extractFunction(
    meepoPath,
    "function X.ConsiderDig()",
    "\nreturn X"
)

-- Exercise the same production SkillsComplement and ConsiderDig used by Meepo,
-- replacing only unrelated ability considerations and game-engine interfaces.
local makeMeepo = assert(loadstring([[
return function(abilities, health)
    local issued = {}
    local bot = {
        GetAbilityByName = function(_, name) return abilities[name] end,
        HasModifier = function() return false end,
        WasRecentlyDamagedByAnyHero = function() return false end,
        ActionQueue_UseAbility = function(_, ability)
            issued[#issued + 1] = {kind = "cast", ability = ability}
        end,
        ActionQueue_UseAbilityOnEntity = function(_, ability, target)
            issued[#issued + 1] = {kind = "unit", ability = ability, target = target}
        end,
        ActionQueue_UseAbilityOnLocation = function(_, ability, location)
            issued[#issued + 1] = {kind = "point", ability = ability, target = location}
        end
    }
    local J = {
        CanNotUseAbility = function() return false end,
        GetMeepos = function() return {} end,
        GetProperTarget = function() return nil end,
        GetHP = function() return health end,
        GetNearbyHeroes = function() return {} end,
        IsAttacking = function() return false end,
        SetQueuePtToINT = function() end
    }
    local BOT_MODE_NONE = 0
    local BOT_ACTION_DESIRE_NONE = 0
    local BOT_ACTION_DESIRE_HIGH = 0.9
    local X = {}
    local EarthBind, Poof, Dig
    local Meepos, botTarget, botHP, nAllyHeroes, nEnemyHeroes, bAttacking
    local PoofDesire, PoofTarget, DigDesire, EarthBindDesire, EarthBindLocation
    function X.ConsiderPoof() return BOT_ACTION_DESIRE_NONE end
    function X.ConsiderEarthBind() return BOT_ACTION_DESIRE_NONE end
]] .. skillsSource .. "\n" .. digSource .. [[
    return {
        tick = function() X.SkillsComplement() end,
        actions = function() return issued end
    }
end
]], "patch742-meepo-production"))()

local function ability(trained, castable)
    return {
        IsTrained = function() return trained end,
        IsFullyCastable = function() return castable end
    }
end

test("Meepo with missing Dig and deleted MegaMeepo can still think", function()
    local b = makeMeepo({}, 0.25)
    b.tick()
    equal(#b.actions(), 0, "No unavailable abilities should be submitted")
end)

test("Meepo does not cast Dig without learned or castable Scepter ability", function()
    for _, a in ipairs({ability(false, true), ability(true, false)}) do
        local b = makeMeepo({meepo_petrify = a}, 0.2)
        b.tick()
        equal(#b.actions(), 0, "Unusable Dig must not be submitted")
    end
end)

test("Meepo still uses Dig when available and in danger", function()
    local dig = ability(true, true)
    local b = makeMeepo({meepo_petrify = dig}, 0.3)
    b.tick()
    equal(#b.actions(), 1, "One valid Dig")
    equal(b.actions()[1].kind, "cast", "Dig should use no-target action")
    equal(b.actions()[1].ability, dig, "Dig ability handle must be preserved")
end)

test("Meepo retains Dig when needed but avoids spending it at high HP", function()
    local dig = ability(true, true)
    local b = makeMeepo({meepo_petrify = dig}, 0.95)
    b.tick()
    equal(#b.actions(), 0, "Healthy Meepo must not spend Dig in this mock scenario")
end)

local function withoutSingleLineComments(src)
    return (src:gsub("%-%-[^\r\n]*", ""))
end

test("7.42 removed Overlord is absent from active item recipes and hero builds", function()
    for _, path in ipairs({
        "bots/FunLib/aba_item.lua",
        "bots/BotLib/hero_beastmaster.lua",
        "bots/BotLib/hero_lycan.lua"
    }) do
        local active = withoutSingleLineComments(readFile(path))
        assert(not active:find("item_helm_of_the_overlord", 1, true),
            "Still references removed item: " .. path)
        assert(active:find("item_helm_of_the_dominator", 1, true),
            "Dominator item should remain available: " .. path)
    end
end)

local failures = 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.run)
    if ok then
        io.write("PASS: ", t.name, "\n")
    else
        io.stderr:write("FAIL: ", t.name, " :: ", tostring(err), "\n")
        failures = failures + 1
    end
end

if #tests == 0 or failures ~= 0 then
    io.stderr:write(string.format("%d tests, %d failures\n", #tests, failures))
    os.exit(1)
end
io.write(string.format("%d tests, all passed\n", #tests))
