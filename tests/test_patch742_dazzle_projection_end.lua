-- 7.42 Dazzle: validate the cached PHYSICAL BODY before reading its state.
-- Execute the actual production Consider and actual J.IsValid body under Lua 5.1.
local function read(path)
    local f = assert(io.open(path, "rb"), "missing " .. path)
    local source = assert(f:read("*a"))
    f:close()
    return source
end

local function extract(source, first, last)
    local a = assert(source:find(first, 1, true), "missing production function: " .. first)
    local b = assert(source:find(last, a + #first, true), "missing next function: " .. last)
    return source:sub(a, b - 1)
end

local dazzle = read("bots/BotLib/hero_dazzle.lua")
local funcs = extract(dazzle, "function X.ConsiderNothlProjectionEnd()", "\nfunction X.ConsiderR()")
local rememberBody = extract(dazzle, "local function RememberPhysicalBody()", "\nlocal tTalentTreeList")
local skillsEntry = extract(dazzle, "function X.SkillsComplement()", "\n\t-- Re-fetch ability handles")
local jmz = read("bots/FunLib/jmz_func.lua")
local isValid = extract(jmz, "function J.IsValid( nTarget )", "\nfunction J.IsValidTarget(")

local prefix = [[
return function(options)
    local X, J, bot = {}, {Utils={GameStates={}}}, {}
    local BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_HIGH = 0, 0.8
    local NothlProjectionEnd = { name = "end_projection" }
    local hEnemyList = options.enemies == false and {} or {"enemy"}
    local state = J.Utils.GameStates
    if options.cacheMissing then
        state.dazzleNothl = nil
    elseif options.playerStateMissing then
        state.dazzleNothl = {}
    else
        state.dazzleNothl = {[7] = {body = options.selfIsCached and bot or options.body}}
    end
    function bot:GetPlayerID() return 7 end
    function J.CanCastAbility(ability)
        return ability == NothlProjectionEnd and options.castable ~= false
    end
    function J.IsRetreating(unit)
        if unit == nil then error("attempted IsRetreating(nil)") end
        if unit:IsNull() then error("attempted IsRetreating(stale handle)") end
        return options.retreating == true
    end
    function J.GetHP(unit)
        if unit == nil or unit:IsNull() then error("invalid HP lookup") end
        return options.hp or 0.5
    end
]]

local suffix = [[
    function bot:HasModifier(modifier)
        assert(modifier == 'modifier_dazzle_nothl_projection_physical_body_debuff')
        return options.physical == true
    end
    function bot:IsInvisible() return false end
    function J.CanNotUseAbility() return true end
    if options.tick then
        X.SkillsComplement()
        local playerState = state.dazzleNothl and state.dazzleNothl[7]
        return playerState ~= nil and playerState.body == bot
    end
    return X.ConsiderNothlProjectionEnd()
end
]]

local factory, err = loadstring(prefix .. "\n" .. isValid .. "\n" .. rememberBody .. "\n" .. skillsEntry .. "\nend\n" .. funcs .. suffix, "Dazzle production")
assert(factory, err)
local run = factory()

local function body(values)
    values = values or {}
    return {
        IsNull = function() return values.stale == true end,
        CanBeSeen = function() return values.visible ~= false end,
        IsAlive = function() return values.alive ~= false end,
        IsBuilding = function() return values.building == true end
    }
end

local passed = 0
local function check(title, options, expected)
    local ok, actual = pcall(run, options)
    assert(ok, title .. " failed with runtime error: " .. tostring(actual))
    assert(actual == expected,
           title .. " expected " .. tostring(expected) .. " but got " .. tostring(actual))
    passed = passed + 1
    print("PASS " .. title)
end

check("no nearby enemies retains original End behavior", {
    enemies=false, cacheMissing=true
}, 0.8)

check("End ability unavailable remains blocked", {
    castable=false, body=body(), retreating=true
}, 0)

check("missing entire Dazzle cache is safe", {
    cacheMissing=true, retreating=true
}, 0)

check("missing player cache is safe", {
    playerStateMissing=true, retreating=true
}, 0)

check("nil cached body is safe", {
    body=nil, retreating=true
}, 0)

check("stale physical body is not dereferenced", {
    body=body({stale=true}), retreating=true
}, 0)

check("unseen physical body still respects J.IsValid", {
    body=body({visible=false}), retreating=true
}, 0)

check("dead physical body still respects J.IsValid", {
    body=body({alive=false}), retreating=true
}, 0)

check("building impostor is not treated as a physical body", {
    body=body({building=true}), retreating=true
}, 0)

check("valid retreating low HP body triggers existing End", {
    body=body(), retreating=true, hp=0.55
}, 0.8)

check("healthy retreating physical body keeps projection", {
    body=body(), retreating=true, hp=0.8
}, 0)

check("non-retreating physical body keeps projection", {
    body=body(), retreating=false, hp=0.3
}, 0)

check("current projection handle is not accepted as the cached body", {
    selfIsCached=true, retreating=true
}, 0)

check("physical body recovers a missing table", {
    tick=true, physical=true, cacheMissing=true
}, true)

check("physical body recovers a missing player entry", {
    tick=true, physical=true, playerStateMissing=true
}, true)

check("spirit tick does not seed a missing body cache", {
    tick=true, cacheMissing=true
}, false)

assert(not funcs:find("if J.IsValid(bot) then", 1, true),
       "the old mistaken validity guard must not remain")
assert(funcs:find("J.IsValid(hBody)", 1, true),
       "actual cached physical body must be validated")
passed = passed + 1
print("PASS validates cached body instead of current spirit")
print(string.format("%d production-body Dazzle regressions passed", passed))
