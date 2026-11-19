-- Offline Lua 5.1 regressions for the 7.42 Meepo Shard pickup/Fling.
-- Run from repo root: lua5.1 tests/test_patch742_meepo_shard.lua
-- Tests execute production function bodies with minimal Dota API mocks.

local function readFile(path)
    local f = assert(io.open(path, "rb"), "Cannot read " .. path)
    local value = assert(f:read("*a"))
    f:close()
    return value
end

local function extract(path, beginMarker, endMarker)
    local source = readFile(path)
    local first = assert(source:find(beginMarker, 1, true), "Missing " .. beginMarker)
    local last = assert(source:find(endMarker, first + #beginMarker, true), "Missing " .. endMarker)
    return source:sub(first, last - 1)
end

local function eq(actual, expected, label)
    if actual ~= expected then
        error(label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local path = "bots/BotLib/hero_meepo.lua"
local productionFile = readFile(path)
local skills = extract(path, "function X.SkillsComplement()", "\nfunction X.ConsiderEarthBind()")
local dig = extract(path, "function X.ConsiderDig()", "\n-- 7.42 Shard:")
local pickup = extract(path, "function X.ConsiderShardPickup()", "\n-- 7.42 Shard secondary action:")
local fling = extract(path, "function X.ConsiderShardFling()", "\nreturn X")

local makeBot = assert(loadstring([[
return function(config)
    local issued = {}
    local state = {
        carrying = config.carrying or false,
        shard = config.shard or false,
        retreat = config.retreat or false,
        going = config.going ~= false,
    }
    local enemies = config.enemies or {}
    local creeps = config.creeps or {}

    local pickupAbility = {
        IsTrained = function() return true end,
        IsFullyCastable = function() return config.pickupCastable ~= false end,
        GetCastRange = function() return config.pickupRange or 250 end
    }
    local flingAbility = {
        IsHidden = function() return not state.carrying end,
        IsFullyCastable = function() return state.carrying end,
        GetSpecialValueInt = function(_, name)
            assert(name == "range", "Incorrect Fling special value name")
            return config.flingRange or 700
        end
    }

    local abilities = {
        meepo_divided_we_stand = pickupAbility,
        meepo_fling_release = flingAbility
    }
    if config.withoutPickup then abilities.meepo_divided_we_stand = nil end
    if config.withoutFling then abilities.meepo_fling_release = nil end

    local bot = {
        HasShard = function() return state.shard end,
        GetAbilityByName = function(_, name) return abilities[name] end,
        HasModifier = function() return false end,
        GetTeam = function() return 2 end,
        GetNearbyCreeps = function() return creeps end,
        WasRecentlyDamagedByAnyHero = function() return false end,
        ActionQueue_UseAbilityOnEntity = function(_, ability, target)
            issued[#issued + 1] = {kind = "pickup", ability = ability, target = target}
            if ability == pickupAbility then state.carrying = true end
        end,
        Action_UseAbilityOnEntity = function(_, ability, target)
            issued[#issued + 1] = {kind = "fling", ability = ability, target = target}
            if ability == flingAbility then state.carrying = false end
        end,
        ActionQueue_UseAbility = function() error("Unexpected Dig") end,
        ActionQueue_UseAbilityOnLocation = function() error("Unexpected Earthbind") end
    }
    local J = {
        CanNotUseAbility = function() return false end,
        GetMeepos = function() return {} end,
        GetProperTarget = function() return nil end,
        GetHP = function() return 0.9 end,
        GetNearbyHeroes = function(_, _, isEnemy)
            return isEnemy and enemies or {}
        end,
        IsAttacking = function() return false end,
        SetQueuePtToINT = function() end,
        IsRetreating = function() return state.retreat end,
        IsGoingOnSomeone = function() return state.going end,
        IsValidHero = function(target)
            return target ~= nil and target.hero and target.visible ~= false
        end,
        IsValid = function(target)
            return target ~= nil and target.valid ~= false
        end,
        CanCastOnNonMagicImmune = function() return true end,
        IsSuspiciousIllusion = function(target)
            return target.illusion == true
        end,
        IsInRange = function(_, target, range)
            return target.distance <= range
        end
    }
    local ENABLE_EXPERIMENTAL_SHARD_AI = config.experimental ~= false
    local BOT_MODE_NONE = 0
    local BOT_ACTION_DESIRE_NONE = 0
    local BOT_ACTION_DESIRE_HIGH = 0.9
    local X = {}
    local EarthBind, Poof, Dig, ShardPickup, ShardFling
    local Meepos, botTarget, botHP, nAllyHeroes, nEnemyHeroes, bAttacking
    local PoofDesire, PoofTarget, DigDesire, EarthBindDesire, EarthBindLocation
    local ShardFlingDesire, ShardFlingTarget, ShardPickupDesire, ShardPickupTarget
    function X.ConsiderPoof() return 0 end
    function X.ConsiderEarthBind() return 0 end
]] .. skills .. "\n" .. dig .. "\n" .. pickup .. "\n" .. fling .. [[
    return {
        tick = function() X.SkillsComplement() end,
        actions = function() return issued end,
        state = state,
        pickup = pickupAbility,
        fling = flingAbility,
    }
end
]], "test-7.42-meepo-shard"))()

local function enemy(distance, opts)
    opts = opts or {}
    return {hero = true, distance = distance, visible = opts.visible,
            illusion = opts.illusion}
end

local function creep(distance, opts)
    opts = opts or {}
    return {
        distance = distance,
        valid = opts.valid ~= false,
        GetTeam = function() return opts.team or 2 end,
        GetUnitName = function() return opts.name or "npc_dota_creep_goodguys_melee" end
    }
end

local tests = {}
local function test(name, fn)
    tests[#tests + 1] = {name=name, fn=fn}
end

test("production leaves unverified Shard AI disabled", function()
    assert(productionFile:find("local ENABLE_EXPERIMENTAL_SHARD_AI = false", 1, true),
        "Experimental Shard AI must not be enabled in the real bot before client validation")
end)

test("experimental gate disables both pickup and Fling", function()
    local noPickup = makeBot({
        shard = true,
        experimental = false,
        enemies = {enemy(350)},
        creeps = {creep(150)}
    })
    noPickup.tick()
    eq(#noPickup.actions(), 0, "Disabled Shard pickup")
    local noFling = makeBot({
        shard = true,
        experimental = false,
        carrying = true,
        enemies = {enemy(350)}
    })
    noFling.tick()
    eq(#noFling.actions(), 0, "Disabled Shard fling")
end)

test("no Shard means no pickup", function()
    local b = makeBot({enemies = {enemy(500)}, creeps = {creep(100)}})
    b.tick()
    eq(#b.actions(), 0, "No Shard")
end)

test("no target or no allied creep means no pickup", function()
    local b = makeBot({shard = true, creeps = {creep(100)}})
    b.tick()
    eq(#b.actions(), 0, "No enemies")
    local c = makeBot({shard = true, enemies = {enemy(300)}})
    c.tick()
    eq(#c.actions(), 0, "No allied creeps")
end)

test("unavailable abilities and invalid targets are not submitted", function()
    for _, bad in ipairs({
        {withoutPickup = true}, {withoutFling = true}, {pickupCastable = false},
        {retreat = true}, {going = false}
    }) do
        local cfg = {shard = true, enemies = {enemy(350)}, creeps = {creep(120)}}
        for k, v in pairs(bad) do cfg[k] = v end
        local b = makeBot(cfg)
        b.tick()
        eq(#b.actions(), 0, "Invalid pickup environment")
    end
    local b = makeBot({shard = true,
        enemies = {enemy(350, {visible = false}), enemy(450, {illusion = true})},
        creeps = {creep(100)}})
    b.tick()
    eq(#b.actions(), 0, "Cannot target unseen enemies or suspicious illusions")
end)

test("prefers allied ordinary creep, not enemy creep or other unit", function()
    local b = makeBot({shard = true, enemies = {enemy(450)},
        creeps = {creep(100, {team = 3}),
                  creep(120, {name = "npc_dota_neutral_kobold"}),
                  creep(140)}})
    b.tick()
    eq(#b.actions(), 1, "One pickup")
    eq(b.actions()[1].kind, "pickup", "Must pick up")
    eq(b.actions()[1].target.distance, 140, "Must select allied lane creep")
end)

test("pickup then fling uses new 7.42 ability handles in order", function()
    local target, ammo = enemy(480), creep(180)
    local b = makeBot({shard = true, enemies = {target}, creeps = {ammo}})
    b.tick()
    eq(#b.actions(), 1, "First command")
    eq(b.actions()[1].ability, b.pickup, "Use Divided We Stand to pick up")
    eq(b.actions()[1].target, ammo, "Pick friendly creep")
    b.tick()
    eq(#b.actions(), 2, "Second command")
    eq(b.actions()[2].kind, "fling", "Fling should be highest priority while carrying")
    eq(b.actions()[2].ability, b.fling, "Use meepo_fling_release")
    eq(b.actions()[2].target, target, "Fling at visible enemy")
end)

test("Fling respects its level-dependent range and visibility", function()
    local b = makeBot({carrying = true, shard = true, flingRange = 600,
        enemies = {enemy(650)}})
    b.tick()
    eq(#b.actions(), 0, "Outside cast range")
    local c = makeBot({carrying = true, shard = true, flingRange = 600,
        enemies = {enemy(540, {visible = false})}})
    c.tick()
    eq(#c.actions(), 0, "Unseen target")
    local d = makeBot({carrying = true, shard = true, flingRange = 600,
        enemies = {enemy(540)}})
    d.tick()
    eq(d.actions()[1].kind, "fling", "Visible in-range target")
end)

test("pickup range is bounded by engine cast range and 250", function()
    local short = makeBot({shard = true, enemies = {enemy(480)},
        creeps = {creep(180)}, pickupRange = 150})
    short.tick()
    eq(#short.actions(), 0, "Out of shorter engine range")
    local bounded = makeBot({shard = true, enemies = {enemy(480)},
        creeps = {creep(260)}, pickupRange = 400})
    bounded.tick()
    eq(#bounded.actions(), 0, "Do not extend beyond 250")
end)

local fails = 0
for _, spec in ipairs(tests) do
    local ok, err = pcall(spec.fn)
    if ok then
        io.write("PASS: ", spec.name, "\n")
    else
        io.stderr:write("FAIL: ", spec.name, " :: ", tostring(err), "\n")
        fails = fails + 1
    end
end
if #tests == 0 or fails > 0 then
    io.stderr:write(string.format("%d tests, %d failures\n", #tests, fails))
    os.exit(1)
end
io.write(string.format("%d tests, all passed\n", #tests))
