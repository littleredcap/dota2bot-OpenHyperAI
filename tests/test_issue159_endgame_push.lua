-- Issue #159: tests the actual generated Lua closing-window predicate.
-- Run at repository root with: lua5.1 tests/test_issue159_endgame_push.lua
local function read(path)
    local f = assert(io.open(path, "rb"), "Missing " .. path)
    local s = assert(f:read("*a"))
    f:close()
    return s
end
local lua = read("bots/FunLib/aba_push.lua")
local ts = read("typescript/bots/FunLib/aba_push.ts")
local startMarker = "    local decisivePushWindow = "
local startPos = assert(lua:find(startMarker, 1, true), "No generated closing-window predicate")
local endPos = assert(lua:find("\n    local team = gameState.team", startPos, true), "Predicate end marker missing")
local expr = lua:sub(startPos + #startMarker, endPos - 1)
local predicate = assert(loadstring([[
return function(state, hp, enemies)
    local gameState, bot, enemiesHere = state, {}, enemies or {}
    local StartToPushTime = 16 * 60
    local jmz = {
        GetHP = function() return hp end,
        IsDefending = function() return state.defending == true end
    }
    local function IsOurBaseUnderCreepAttack() return state.baseUnderCreepAttack == true end
    local nModeDesire = state.activeModeDesire or 0
    return ]] .. expr .. [[

end
]], "production-closing-window"))()

local function state(overrides)
    local s = {currentTime=30*60, aliveEnemyCount=2, aliveAllyCount=4, aliveAllyCoreCount=2}
    for k, v in pairs(overrides or {}) do s[k] = v end
    return s
end
local tests = {}
local function test(name, fn) tests[#tests+1]={name,fn} end
local function expect(got,want)
    assert(got == want,"expected "..tostring(want).." got "..tostring(got))
end
test("4v2 late-game advantage supports pushing while regrouping",function()
    expect(predicate(state(),0.85,{}),true)
end)
test("3v1 is also a closing window",function()
    expect(predicate(state({aliveEnemyCount=1,aliveAllyCount=3}),0.85,{}),true)
end)
test("team wipe 3v0 is safe to advance",function()
    expect(predicate(state({aliveEnemyCount=0,aliveAllyCount=3}),0.85,{}),true)
end)
test("2v0 is insufficient for high-ground commitment",function()
    expect(predicate(state({aliveEnemyCount=0,aliveAllyCount=2}),0.85,{}),false)
end)
test("3v2 is not a decisive advantage",function()
    expect(predicate(state({aliveEnemyCount=2,aliveAllyCount=3}),0.85,{}),false)
end)
test("3 or more enemies alive prevents override",function()
    expect(predicate(state({aliveEnemyCount=3,aliveAllyCount=5}),0.85,{}),false)
end)
test("without a surviving core the override stays off",function()
    expect(predicate(state({aliveAllyCoreCount=0}),0.85,{}),false)
end)
test("low HP bot should not make a high-ground commitment",function()
    expect(predicate(state(),0.4,{}),false)
end)
test("nearby enemy heroes preserve local combat safety gates",function()
    expect(predicate(state(),0.9,{{}}),false)
end)
test("before the push timer, do not force an endgame push",function()
    expect(predicate(state({currentTime=300}),0.9,{}),false)
end)
test("base creep attacks cancel the optimistic closing window",function()
    expect(predicate(state({baseUnderCreepAttack=true}),0.85,{}),false)
end)
test("active high-priority defense is not overruled by numbers",function()
    expect(predicate(state({defending=true,activeModeDesire=0.9}),0.85,{}),false)
    expect(predicate(state({defending=true,activeModeDesire=0.3}),0.85,{}),true)
end)
test("solo base dive requires nearby allies or an actual creep wave",function()
    local a=assert(lua:find("    local safeClosingWindow = ",1,true))
    local b=assert(lua:find("\n    if GetLocationToLocationDistance",a,true))
    local start="    local safeClosingWindow = "
    local expression=lua:sub(a+#start,b-1)
    local fn=assert(loadstring([[
return function(closeToBase,allies,wave)
    local decisivePushWindow=true
    local nearEnemyBase=closeToBase
    local alliesHere=allies
    local nearbyAlliedWave=wave
    return ]]..expression..[[
end
]]))()
    expect(fn(false,{},{}),true)
    expect(fn(true,{},{}),false)
    expect(fn(true,{1,2},{}),true)
    expect(fn(true,{}, {1,2}),true)
end)
test("generated Lua bypasses ONLY the isolated-deep-push cap",function()
    assert(lua:find("not safeClosingWindow and #alliesHere < 3",1,true))
    assert(lua:find("if #alliesHere <= 1 and gameState.aliveEnemyCount >= 3",1,true))
    assert(lua:find("if enemiesAtAncient >= 1 then",1,true))
    assert(lua:find("if jmz.GetHP(bot) < 0.5 then",1,true))
end)
test("only selected lane gets closing-window priority",function()
    assert(lua:find("if decisivePushWindow and not isCurrentLanePushLane then",1,true))
    assert(lua:find("return safeClosingWindow and math.max(pushDesire, 0.88) or pushDesire",1,true))
    assert(ts:find("if (decisivePushWindow && !isCurrentLanePushLane)",1,true))
    assert(ts:find("(!safeClosingWindow && alliesHere.length < 3)",1,true))
    assert(ts:find("!IsOurBaseUnderCreepAttack(gameState.ourAncient)",1,true))
end)
local failed = 0
for _, t in ipairs(tests) do
    local ok, err = pcall(t[2])
    if ok then io.write("PASS: ",t[1],"\n")
    else failed=failed+1;io.stderr:write("FAIL: ",t[1]," :: ",tostring(err),"\n") end
end
if failed > 0 then
    io.stderr:write(string.format("%d tests, %d failed\n",#tests,failed))
    os.exit(1)
end
io.write(string.format("%d tests, all passed\n",#tests))
