-- Offline 7.42 Roshan timer regressions, no game client.
-- Execute from repository root: lua5.1 tests/test_patch742_roshan_respawn.lua
local function read(path)
    local f = assert(io.open(path, "rb"))
    local txt = assert(f:read("*a"))
    f:close()
    return txt
end

local src = read("bots/FunLib/jmz_func.lua")
local a = assert(src:find("local lastObservedRoshanKillTime = 0", 1, true) or src:find("local killTime = 0.0", 1, true))
local b = assert(src:find("\nfunction J.HasEnoughDPSForRoshan(", a, true))
local production = src:sub(a, b - 1)

local makeRoshan = assert(loadstring([[
return function()
    local state = {clock = 0, killTime = 0, turbo = false}
    local J = {IsModeTurbo = function() return state.turbo end}
    local function DotaTime() return state.clock end
    local function GetRoshanKillTime() return state.killTime end
]] .. production .. [[
    return {
        state = state,
        alive = function() return J.IsRoshanAlive() end,
        kill = function(time) state.killTime = time; state.clock = time end,
        tick = function(time) state.clock = time; return J.IsRoshanAlive() end,
    }
end
]], "test-patch742-roshan"))()

local function equal(actual, expected, message)
    if actual ~= expected then
        error(message .. " (expected " .. tostring(expected) .. ", got " .. tostring(actual) .. ")", 2)
    end
end

local tests = {}
local function test(name, fn) tests[#tests + 1] = {name, fn} end

test("Roshan is alive before the first observed kill", function()
    local g = makeRoshan()
    equal(g.alive(), true, "No kill")
end)

test("after first kill the normal-mode conservative upper bound is 10m", function()
    local g = makeRoshan()
    g.kill(100)
    equal(g.alive(), false, "Immediately after death")
    equal(g.tick(100 + 10 * 60 - 1), false, "Just before upper bound")
    equal(g.tick(100 + 10 * 60), true, "At 10m latest possible respawn")
end)

test("after second and third observed kills the bounds are 9m and 8m", function()
    local g = makeRoshan()
    g.kill(100)
    equal(g.alive(), false, "First kill")
    g.kill(1000)
    equal(g.tick(1000 + 9 * 60 - 1), false, "Before second kill upper bound")
    equal(g.tick(1000 + 9 * 60), true, "Second kill 9m")
    g.kill(2000)
    equal(g.tick(2000 + 8 * 60 - 1), false, "Before third kill upper bound")
    equal(g.tick(2000 + 8 * 60), true, "Third kill 8m")
end)

test("further kills do not shorten the bound below 8m", function()
    local g = makeRoshan()
    for _, t in ipairs({100, 1000, 2000, 3000, 4000, 5000}) do
        g.kill(t)
        g.alive()
    end
    equal(g.tick(5000 + 8 * 60 - 1), false, "Before floor")
    equal(g.tick(5000 + 8 * 60), true, "At 5+3 minute latest-bound floor")
end)

test("same death timestamp is not counted multiple times", function()
    local g = makeRoshan()
    g.kill(100)
    for i = 1, 100 do g.tick(101 + i) end
    equal(g.tick(100 + 9 * 60), false, "Should remain first-kill bound")
end)

test("late-loaded instance counts only last observed kill, staying conservative", function()
    local g = makeRoshan()
    g.state.clock = 2000
    g.state.killTime = 1800
    equal(g.alive(), false, "Recent but unknown prior history")
    equal(g.tick(1800 + 10 * 60), true, "Upper bound after first observed kill")
end)

test("reset to pregame clears observed kills", function()
    local g = makeRoshan()
    g.kill(100)
    g.alive()
    g.kill(1500)
    g.alive()
    g.state.killTime = 0
    g.state.clock = 0
    equal(g.alive(), true, "New game no kill")
    g.kill(100)
    equal(g.tick(100 + 9 * 60), false, "Count reset: first kill bound still 10m")
end)

test("Turbo retains previous conservative 6m upper bound pending verification", function()
    local g = makeRoshan()
    g.state.turbo = true
    g.kill(100)
    equal(g.tick(100 + 6 * 60 - 1), false, "Turbo early")
    equal(g.tick(100 + 6 * 60), false, "Turbo original strict boundary")
    equal(g.tick(100 + 6 * 60 + 1), true, "Turbo after original threshold")
    g.kill(1000)
    equal(g.tick(1000 + 5 * 60), false, "Turbo bound unchanged")
end)

test("unknown engine kill time does not assert Roshan is alive", function()
    local g = makeRoshan()
    g.state.killTime = nil
    equal(g.alive(), false, "Unknown kill time")
end)

test("an invalid timestamp does not increase observed kills", function()
    local g = makeRoshan()
    g.kill(100)
    g.alive()
    g.state.killTime = -1
    equal(g.tick(500), false, "Negative timestamp")
    g.state.killTime = 2000
    equal(g.tick(500), false, "Future timestamp")
    g.state.killTime = 100
    equal(g.tick(100 + 9 * 60), false, "Counter unchanged")
end)

test("a decreasing valid timestamp discards the previous match history", function()
    local g = makeRoshan()
    for _, t in ipairs({1000, 2000, 3000}) do g.kill(t); g.alive() end
    g.kill(200)
    equal(g.tick(200 + 9 * 60), false, "After reset only one kill is known")
    equal(g.tick(200 + 10 * 60), true, "First observed-kill threshold")
end)

local failed = 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t[2])
    if ok then
        io.write("PASS: ", t[1], "\n")
    else
        failed = failed + 1
        io.stderr:write("FAIL: ", t[1], " - ", tostring(err), "\n")
    end
end
if #tests == 0 or failed > 0 then
    io.stderr:write(string.format("%d tests, %d failed\n", #tests, failed))
    os.exit(1)
end
io.write(string.format("%d tests, all passed\n", #tests))
