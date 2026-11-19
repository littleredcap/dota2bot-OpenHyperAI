-- Issue #176: isolated Lua 5.1 regression of generated production helpers.
-- Execute from repo root: lua5.1 tests/test_issue176_base_creeps.lua
-- No Dota client is used. Do not mistake mock assertions for game validation.
local function read(path)
    local f = assert(io.open(path, "rb"), "Missing " .. path)
    local code = assert(f:read("*a"))
    f:close()
    return code
end

local path = "bots/FunLib/aba_defend.lua"
local code = read(path)
local first = assert(code:find("function WeightedEnemiesAroundLocation(vLoc, nRadius)", 1, true),
    "Missing generated production threat helper: npm run build required")
local last = assert(code:find("\nfunction GetThreatenedLane()", first, true),
    "Missing production end marker")
local production = code:sub(first, last - 1)

local create = assert(loadstring([[
return function(options)
    options = options or {}
    local creeps = options.creeps or {}
    local heroes = options.heroes or {}
    local members = options.members or {}
    local ancient = {
        x=0,
        IsAlive=function() return true end,
        IsBuilding=function() return true end,
        GetLocation=function(self) return {x=self.x} end,
    }
    local t4a = {x=80}
    local t4b = {x=-80}
    local nTeam = 2
    local Tower = {Base1=1, Base2=2}
    local Lane = {Top=1, Mid=2, Bot=3}
    local BotModeDesire = {VeryLow=0.12}
    local BASE_THREAT_RADIUS = 2600
    local CACHE_ENEMY_AROUND_LOC_HZ = 0.35
    local _cacheEnemyAroundLoc = {}
    local currentTime = 100
    -- TSTL's inline standard library is outside the extracted helper body;
    -- provide its string-includes primitive in this isolated mock only.
    local function __TS__StringIncludes(s, search)
        return string.find(s, search, 1, true) ~= nil
    end
    local function DotaTime() return currentTime end
    local function _keyLoc(loc, rad) return tostring(loc.x) .. "|" .. tostring(rad) end
    local function updateDefendUnitStateCache()
        return {enemyHeroes=heroes, enemyCreeps=creeps}
    end
    local function IsValidBuildingTarget(unit)
        return unit ~= nil and unit:IsAlive() and unit:IsBuilding()
    end
    local jmz = {
        IsValid=function(u) return u ~= nil and u.visible ~= false and u.alive ~= false end,
        IsValidHero=function(u) return u ~= nil and u.hero == true and u.alive ~= false end,
        IsSuspiciousIllusion=function(u) return u.illusion == true end,
        IsCore=function(u) return u.core == true end,
        Utils = {CountEnemyHeroesNear=function() return options.enemyHeroesAtBase or 0 end},
    }
    local function GetUnitToLocationDistance(unit, loc) return math.abs(unit.x-loc.x) end
    local function GetTeamPlayers() return members end
    local function GetTeamMember(i) return members[i] end
    local function GetTower(_, which)
        if which == Tower.Base1 then return t4a end
        if which == Tower.Base2 then return t4b end
        return nil
    end
]] .. production .. [[
    return {
        ancient=ancient,
        t4a=t4a,
        t4b=t4b,
        weighted=function() return WeightedEnemiesAroundLocation(ancient:GetLocation(), 2200) end,
        attacker=function() return GetBaseCreepAttacker(ancient) end,
        desire=function(bot, lane) return GetCreepBaseDefenseDesire(bot, lane or Lane.Mid, ancient) end,
        mid=Lane.Mid,
        top=Lane.Top,
        veryLow=BotModeDesire.VeryLow,
    }
end
]], "issue176-production-helpers"))()

local function creep(x, target, opts)
    opts=opts or {}
    local c = {
        x=x, hero=false, visible=opts.visible ~= false, alive=true,
        GetUnitName=function() return opts.name or "npc_dota_creep_badguys_melee" end,
        GetAttackTarget=function() return target end,
    }
    return c
end

local function bot(id, x, opts)
    opts=opts or {}
    return {
        hero=true, core=opts.core or false, x=x, alive=opts.alive ~= false,
        IsBot=function() return opts.human ~= true end,
        IsIllusion=function() return opts.illusion == true end,
        GetPlayerID=function() return id end,
    }
end

local tests={}
local function test(name, fn) tests[#tests+1]={name,fn} end
local function eq(actual, expected, msg)
    if actual ~= expected then error(msg..": expected "..tostring(expected).." got "..tostring(actual),2) end
end

test("no enemy creeps never starts emergency mode", function()
    local a=bot(1,500)
    local g=create({members={a}})
    eq(g.attacker(),nil,"No attacker")
    eq(g.desire(a),nil,"No emergency")
end)

test("passing creep is not treated as attacking Ancient", function()
    local a=bot(1,500)
    local wave=creep(250,nil)
    local g=create({creeps={wave},members={a}})
    eq(g.attacker(),nil,"Passing wave")
    eq(g.desire(a),nil,"No default all-team recall")
end)

test("visible creep attacking Ancient triggers one defender", function()
    local a=bot(1,400)
    local b=bot(2,1300)
    local g=create({members={a,b}})
    local unit=creep(180,g.ancient)
    -- pass in a stable shared target handle
    local h=create({creeps={unit},members={a,b}})
    -- h has a different Ancient handle: reconstruct inside same environment
    unit.GetAttackTarget=function() return h.ancient end
    eq(h.attacker(),unit,"Actual Ancient attacker")
    eq(h.desire(a,h.mid),0.97,"Nearest bot must urgently defend")
    eq(h.desire(a,h.top),h.veryLow,"Do not activate three lanes")
    eq(h.desire(b,h.mid),h.veryLow,"Other hero should not abandon current plan")
end)

test("visible T4 attacker also triggers without enemy hero", function()
    local a=bot(1,400)
    local unit=creep(160,nil)
    local g=create({members={a},creeps={unit}})
    unit.GetAttackTarget=function() return g.t4a end
    eq(g.attacker(),unit,"T4 attacked")
    eq(g.desire(a),0.97,"Defend T4")
end)

test("invisible creep cannot provide cheating information", function()
    local a=bot(1,400)
    local unit=creep(120,nil,{visible=false})
    local g=create({members={a},creeps={unit}})
    unit.GetAttackTarget=function() return g.ancient end
    eq(g.attacker(),nil,"Hidden creep ignored")
    eq(g.desire(a),nil,"No fog-based recall")
end)

test("out of base-threat radius is ignored", function()
    local a=bot(1,400)
    local unit=creep(2900,nil)
    local g=create({members={a},creeps={unit}})
    unit.GetAttackTarget=function() return g.ancient end
    eq(g.attacker(),nil,"Out of radius")
end)

test("closest available bot is selected, not a dead or human hero", function()
    local dead=bot(1,80,{alive=false})
    local human=bot(2,120,{human=true})
    local close=bot(3,350)
    local far=bot(4,900)
    local unit=creep(100,nil)
    local g=create({members={dead,human,close,far},creeps={unit}})
    unit.GetAttackTarget=function() return g.ancient end
    eq(g.desire(close),0.97,"Nearest eligible bot")
    eq(g.desire(far),g.veryLow,"Other bots not recalled")
end)

test("enemy heroes at base use existing teamfight logic instead", function()
    local a=bot(1,400)
    local unit=creep(100,nil)
    local g=create({members={a},creeps={unit},enemyHeroesAtBase=2})
    unit.GetAttackTarget=function() return g.ancient end
    eq(g.desire(a),nil,"Do not override hero-driven defense")
end)

test("weighted threat includes real creep collection, not only heroes", function()
    local wave={}
    for i=1,6 do wave[#wave+1]=creep(i*80,nil) end
    local g=create({creeps=wave})
    eq(g.weighted(),1,"Six ordinary creeps contribute to base pressure")
end)

test("generated mode checks emergency before team-pushing and hero-only early exits", function()
    local ts=read("typescript/bots/FunLib/aba_defend.ts")
    local x=assert(ts:find("const creepBaseDesire = GetCreepBaseDefenseDesire(bot, lane, ancient);",1,true))
    local y=assert(ts:find("if (teamIsPushing)",x,true))
    assert(x<y,"Creep-only Ancient emergency must bypass normal pushing heuristic")
    assert(ts:find("bot.Action_AttackUnit(baseCreep, true);",1,true),
        "DefendThink must target the actual threatening creep")
end)

local bad=0
for _,t in ipairs(tests) do
    local ok,err=pcall(t[2])
    if ok then io.write("PASS: ",t[1],"\n")
    else bad=bad+1;io.stderr:write("FAIL: ",t[1]," :: ",tostring(err),"\n") end
end
if #tests==0 or bad>0 then
    io.stderr:write(string.format("%d tests, %d failed\n",#tests,bad))
    os.exit(1)
end
io.write(string.format("%d tests, all passed\n",#tests))
