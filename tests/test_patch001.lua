-- OHA-Next Patch 001: offline regression tests for live production Lua functions.
-- Execute from repo root: lua5.1 tests/test_patch001.lua
-- No Dota 2 client is needed; this isolates the exact function bodies.

local function readFile(path)
    local file = assert(io.open(path, "rb"), "Cannot open " .. path)
    local data = assert(file:read("*a"))
    file:close()
    return data
end

local function extractFunction(path, firstMarker, nextMarker)
    local source = readFile(path)
    local first = assert(source:find(firstMarker, 1, true), "Missing function marker: " .. firstMarker)
    local last = assert(source:find(nextMarker, first + #firstMarker, true), "Missing end marker: " .. nextMarker)
    assert(last > first, "Invalid function bounds: " .. firstMarker)
    return source:sub(first, last - 1)
end

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. " (expected=" .. tostring(expected) .. ", actual=" .. tostring(actual) .. ")", 2)
    end
end

local tests = {}
local function test(name, fn)
    tests[#tests + 1] = {name=name, fn=fn}
end

local stickySource = extractFunction(
    "bots/mode_team_roam_generic.lua",
    "local function SetStickyTarget(t)",
    "\nlocal function CapForLanePush(desire)"
)

local makeSticky = assert(loadstring([[
return function()
    local time = 0
    local targetUnit = nil
    local targetLockUntil = -90
    local targetSetCalls = 0
    local bot = {
        SetTarget = function(_, target)
            targetSetCalls = targetSetCalls + 1
        end
    }
    local J = { Utils = { IsValidUnit = function(t)
        return t ~= nil and t.valid ~= false
    end } }
    local X = { CanBeAttacked = function(t)
        return t ~= nil and t.attackable ~= false
    end }
    local function DotaTime() return time end
]] .. stickySource .. [[
    return {
        setTime = function(t) time = t end,
        choose = function(t) SetStickyTarget(t) end,
        target = function() return targetUnit end,
        deadline = function() return targetLockUntil end,
        calls = function() return targetSetCalls end
    }
end
]], "patch001-sticky"))()

test("sticky target keeps current valid target during lock", function()
    local s = makeSticky()
    local a = {valid=true, attackable=true}
    local b = {valid=true, attackable=true}
    s.setTime(0)
    s.choose(a)
    equal(s.target(), a, "Initial target")
    equal(s.deadline(), 1.2, "Initial lock deadline")
    s.setTime(0.5)
    s.choose(b)
    equal(s.target(), a, "Switch before lock expiry should be rejected")
    equal(s.calls(), 1, "Should not send SetTarget for rejected switch")
end)

test("reconsidering current target does not extend lock indefinitely", function()
    local s = makeSticky()
    local a = {valid=true, attackable=true}
    local b = {valid=true, attackable=true}
    s.setTime(0)
    s.choose(a)
    s.setTime(0.7)
    s.choose(a)
    equal(s.deadline(), 1.2, "Same target should retain initial lock deadline")
    equal(s.calls(), 1, "Same target should not issue a redundant target command")
    s.setTime(1.21)
    s.choose(b)
    equal(s.target(), b, "Switch should succeed after lock expiry")
end)

test("invalid or unattackable locked target can be replaced", function()
    local s = makeSticky()
    local a = {valid=true, attackable=true}
    local b = {valid=true, attackable=true}
    s.setTime(0)
    s.choose(a)
    a.valid = false
    s.setTime(0.2)
    s.choose(b)
    equal(s.target(), b, "Invalid target should not block replacement")

    local c = {valid=true, attackable=true}
    b.attackable = false
    s.setTime(0.3)
    s.choose(c)
    equal(s.target(), c, "Unattackable target should not block replacement")
end)

local roshanSource = extractFunction(
    "bots/FunLib/jmz_func.lua",
    "function J.HasEnoughDPSForRoshan(heroes)",
    "\nfunction J.IsNotSelf(bot, ally)"
)
local estimateRoshan = assert(loadstring([[
local J = { GetArmorReducers = function(_) return 0 end }
local function DotaTime() return 0 end
]] .. roshanSource .. [[
return J.HasEnoughDPSForRoshan
]], "patch001-roshan"))()

local function hero(damage, attackSpeed)
    return {
        GetAttackDamage = function() return damage end,
        GetAttackSpeed = function() return attackSpeed end
    }
end

test("Roshan estimate rejects nil or empty roster", function()
    equal(estimateRoshan(nil), false, "Nil roster")
    equal(estimateRoshan({}), false, "Empty roster")
end)

test("Roshan estimate uses combined rather than average DPS", function()
    -- At time=0, estimated HP=6000 and 60s target => threshold=100 DPS.
    -- Each mock hero: 160 damage x 1 attack/sec x 0.4 armor multiplier = 64 DPS.
    local a, b = hero(160, 1), hero(160, 1)
    equal(estimateRoshan({a}), false, "64 DPS alone is insufficient")
    equal(estimateRoshan({a,b}), true, "128 DPS together must satisfy 100 DPS threshold")
end)

local failures = 0
for _, spec in ipairs(tests) do
    local ok, err = pcall(spec.fn)
    if ok then
        io.write("PASS: ", spec.name, "\n")
    else
        failures = failures + 1
        io.stderr:write("FAIL: ", spec.name, " :: ", tostring(err), "\n")
    end
end

if #tests == 0 or failures > 0 then
    io.stderr:write(string.format("%d tests executed, %d failures\n", #tests, failures))
    os.exit(1)
end
io.write(string.format("%d tests executed, all passed\n", #tests))
