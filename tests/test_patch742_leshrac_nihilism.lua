-- 7.42 Leshrac Nihilism: production functions with small Lua 5.1 engine mocks.
-- Run from repository root: lua5.1 tests/test_patch742_leshrac_nihilism.lua
local function read(path)
    local f = assert(io.open(path, "rb"), "Cannot read " .. path)
    local code = assert(f:read("*a"))
    f:close()
    return code
end

local function extract(path, firstMarker, nextMarker)
    local source = read(path)
    local first = assert(source:find(firstMarker, 1, true), "Missing marker " .. firstMarker)
    local last = assert(source:find(nextMarker, first + #firstMarker, true), "Missing marker " .. nextMarker)
    return source:sub(first, last-1)
end

local path = "bots/BotLib/hero_leshrac.lua"
local skills = extract(path, "function X.SkillsComplement()", "\nfunction X.ConsiderSplitEarth()")
local consider = extract(path, "function X.ConsiderNihilism()", "\nreturn X")

local newLeshrac = assert(loadstring([[
return function(opts)
    local ability = opts.ability
    local actions = {}
    local bot = {
        edictPushing = false,
        GetAbilityByName = function(_, name)
            if name ~= 'leshrac_greater_lightning_storm' then
                error("Unexpected ability query: " .. tostring(name))
            end
            return ability
        end,
        GetLocation = function() return {x=0,y=0} end,
        HasModifier = function() return false end,
        WasRecentlyDamagedByAnyHero = function() return opts.damaged == true end,
        Action_UseAbility = function(_, a)
            actions[#actions+1] = a
        end,
    }
    local J = {
        CanNotUseAbility = function() return false end,
        GetProperTarget = function() return nil end,
        IsRetreating = function() return opts.retreat == true end,
        GetEnemiesNearLoc = function(_, range)
            local valid = {}
            for _, e in ipairs(opts.enemies or {}) do
                if e.distance <= range then valid[#valid+1] = e end
            end
            return valid
        end,
        IsValidHero = function(e) return e.valid ~= false end,
        CanCastOnNonMagicImmune = function(e)
            return e.visible ~= false and e.immune ~= true
        end,
        IsDisabled = function(e) return e.disabled == true end,
        -- This removed 7.41 self-ethereal branch must never be called:
        GetAttackProjectileDamageByRange = function()
            error("7.42 Nihilism cannot avoid incoming projectiles via self-ethereal")
        end,
    }
    local BOT_ACTION_DESIRE_NONE = 0
    local BOT_ACTION_DESIRE_HIGH = 0.9
    local Nihilism, botTarget, NihilismDesire
    local PulseNovaDesire, LightningStormDesire, SplitEarthDesire, DiabolicEdictDesire
    local LightningStormTarget, SplitEarthLocation
    local PulseNova, LightningStorm, SplitEarth, DiabolicEdict
    local X = {}
    function X.ConsiderPulseNova() return 0 end
    function X.ConsiderLightningStorm() return 0 end
    function X.ConsiderSplitEarth() return 0 end
    function X.ConsiderDiabolicEdict() return 0 end
]] .. skills .. "\n" .. consider .. [[
    return {
        tick = function() X.SkillsComplement() end,
        setAbility = function(a) ability = a end,
        actions = actions,
        desire = function() return X.ConsiderNihilism() end
    }
end
]], "leshrac-nihilism"))()

local function spell(trained, castable, radius)
    return {
        IsTrained = function() return trained end,
        IsFullyCastable = function() return castable end,
        GetSpecialValueInt = function(_, name)
            assert(name == 'radius', 'Expected 7.42 radius')
            return radius or 550
        end,
    }
end

local function enemy(options)
    options = options or {}
    options.distance = options.distance or 200
    return options
end

local tests = {}
local function test(name, fn)
    tests[#tests+1] = {name=name, fn=fn}
end

local function eq(actual, expected, desc)
    if actual ~= expected then error(desc .. " expected=" .. tostring(expected)
        .. " actual=" .. tostring(actual), 2) end
end

test("without Scepter-granted ability no nil method error occurs", function()
    local b = newLeshrac({retreat=true, damaged=true, enemies={enemy({})}})
    b.tick()
    eq(#b.actions, 0, "No cast with missing ability")
end)

test("ability refreshed after Scepter appears later", function()
    local b = newLeshrac({retreat=true, damaged=true, enemies={enemy({})}})
    b.tick()
    local a = spell(true, true, 550)
    b.setAbility(a)
    b.tick()
    eq(#b.actions, 1, "New ability can be used after acquisition")
    eq(b.actions[1], a, "Correct handle")
end)

test("untrained and cooldown ability never cast", function()
    for _, a in ipairs({spell(false, true), spell(true, false)}) do
        local b = newLeshrac({ability=a, retreat=true, damaged=true,
            enemies={enemy({})}})
        b.tick()
        eq(#b.actions, 0, "Ability readiness")
    end
end)

test("fatal incoming projectile alone no longer triggers Nihilism", function()
    local b = newLeshrac({ability=spell(true,true), retreat=false,
        damaged=false, enemies={}})
    b.tick()
    eq(#b.actions, 0, "No old self-ethereal behavior")
end)

test("retreating under hero pressure casts disarm on visible valid target", function()
    local a = spell(true,true)
    local b = newLeshrac({ability=a, retreat=true, damaged=true,
        enemies={enemy({distance=350})}})
    b.tick()
    eq(#b.actions, 1, "Useful disarm")
    eq(b.actions[1], a, "Correct no-target spell")
end)

test("not damaged or no retreat means no defensive cast", function()
    for _, opts in ipairs({
        {retreat=false, damaged=true},
        {retreat=true, damaged=false}
    }) do
        opts.ability=spell(true,true)
        opts.enemies={enemy({distance=400})}
        local b = newLeshrac(opts)
        b.tick()
        eq(#b.actions, 0, "Avoid unnecessary disarm")
    end
end)

test("outside radius, immune, hidden, disabled targets are not cast on", function()
    for _, e in ipairs({
        enemy({distance=560}),
        enemy({immune=true}),
        enemy({visible=false}),
        enemy({disabled=true}),
        enemy({valid=false}),
    }) do
        local b = newLeshrac({ability=spell(true,true), retreat=true,
            damaged=true, enemies={e}})
        b.tick()
        eq(#b.actions,0,"No valid affected enemy")
    end
end)

test("skip disabled enemy but permit another viable nearby target", function()
    local a = spell(true,true)
    local b = newLeshrac({ability=a, retreat=true, damaged=true,
        enemies={enemy({distance=200,disabled=true}), enemy({distance=250})}})
    b.tick()
    eq(#b.actions,1,"One nearby enemy can still justify cast")
end)

test("invalid ability radius never triggers", function()
    local b = newLeshrac({ability=spell(true,true,0), retreat=true,
        damaged=true, enemies={enemy({distance=20})}})
    b.tick()
    eq(#b.actions,0,"Invalid radius")
end)

local fail = 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        io.write("PASS: ", t.name, "\n")
    else
        fail = fail + 1
        io.stderr:write("FAIL: ", t.name, " -- ", tostring(err), "\n")
    end
end
if #tests == 0 or fail > 0 then
    io.stderr:write(string.format("%d tests, %d failed\n", #tests, fail))
    os.exit(1)
end
io.write(string.format("%d tests, all passed\n", #tests))
