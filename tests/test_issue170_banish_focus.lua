-- Issue #170: isolated Lua 5.1 tests for offensive banish anti-synergy.
-- Test actual production helper, while scripted OD/SD/Eul call sites are verified.
local Banish = assert(dofile("bots/FunLib/oha_banish.lua"))

local function actor(id, team, opts)
    opts=opts or {}
    return {
        hero = opts.hero ~= false,
        id=id, team=team, x=opts.x or 50,
        GetUnitName=function() return "npc_dota_hero_test" end,
        GetAttackRange=function() return opts.attackRange or 200 end,
        IsDisarmed=function() return opts.disarmed == true end,
        GetPlayerID=function(self) return self.id end,
        GetTeam=function(self) return self.team end,
        GetLocation=function() return {x=50,y=50} end,
        CanBeSeen=function() return opts.visible ~= false end,
        IsChanneling=function() return opts.channeling == true end,
        IsIllusion=function() return opts.illusion == true end,
        GetAttackTarget=function() return opts.attackTarget end
    }
end

local function scenario(o)
    o=o or {}
    local bot=actor(1,2)
    local enemy=actor(9,3,{visible=o.visible,channeling=o.channeling})
    local mates={}
    for i, member in ipairs(o.mates or {}) do
        mates[#mates+1]=actor(10+i,2,{attackTarget=member.focus and enemy or nil,illusion=member.illusion,x=member.chasing and 850 or 80,disarmed=member.disarmed})
    end
    if o.addSelf then mates[#mates+1]=bot end
    local J={
        IsValidHero=function(x) return x ~= nil and x.hero end,
        IsCastingUltimateAbility=function() return o.ultimate == true end,
        GetAlliesNearLoc=function(_, r)
            assert(r==900,"Guard must use short nearby allies range")
            return mates
        end,
        GetHP=function() return o.enemyHP or 1 end,
        IsDisabled=function() return o.disabled == true end,
        IsInRange=function(a,b,r) return math.abs(a.x-b.x) <= r end
    }
    return bot,enemy,J
end

local function check(o, ctx)
    local bot,enemy,J=scenario(o)
    return Banish.ShouldHoldEnemyBanish(bot,enemy,J,ctx)
end

local tests={}
local function test(name,fn) tests[#tests+1]={name,fn} end
local function eq(actual,want,label)
    if actual~=want then error(label.." expected "..tostring(want)..", got "..tostring(actual),2) end
end

test("one allied attacker about to finish a low-HP enemy prevents banish", function()
    eq(check({mates={{focus=true}},enemyHP=0.31}),true,"Avoid saving low HP target")
end)

test("two teammates currently hitting enemy prevent normal offensive banish", function()
    eq(check({mates={{focus=true},{focus=true}},enemyHP=0.93}),true,"Preserve focus")
end)

test("one teammate attacking already-disabled enemy prevents banish", function()
    eq(check({mates={{focus=true}},disabled=true}),true,"Do not remove existing disable")
end)

test("one attacker against full-HP mobile hero is not enough to forbid banish", function()
    eq(check({mates={{focus=true}},enemyHP=0.97}),false,"No blanket ban")
end)

test("visible allied proximity without actual target focus is not enough", function()
    eq(check({mates={{focus=false},{focus=false},{focus=false}},enemyHP=0.2}),false,"Avoid overly broad guard")
end)

test("interrupt enemy channel/ultimate is allowed despite focus", function()
    eq(check({mates={{focus=true},{focus=true}},channeling=true}),false,"Channel interrupt")
    eq(check({mates={{focus=true},{focus=true}},ultimate=true}),false,"Ultimate interrupt")
end)

test("never prevent friendly save even if allies are attacking someone", function()
    local bot,enemy,J=scenario({mates={{focus=true},{focus=true}}})
    eq(Banish.ShouldHoldEnemyBanish(bot,bot,J),false,"Ally save")
    eq(Banish.ShouldHoldEnemyBanish(bot,nil,J),false,"Nil target")
end)

test("no cheating on unseen enemy", function()
    eq(check({mates={{focus=true},{focus=true}},visible=false}),false,"Unseen target")
end)

test("ignore illusory attackers and caster itself", function()
    eq(check({mates={{focus=true,illusion=true},{focus=true,illusion=true}}}),false,"Illusions ignored")
    eq(check({addSelf=true,mates={{focus=true}},enemyHP=0.98}),false,"Caster not counted")
end)

test("chasing outside attack range must not count as actual DPS", function()
    eq(check({mates={{focus=true,chasing=true},{focus=true,chasing=true}},enemyHP=0.2},
        {intent="STOP_ESCAPE"}),false,"Do not abandon catch due to pursuers")
end)

test("one active attacker still prevents saving low HP fleeing enemy", function()
    eq(check({mates={{focus=true}},enemyHP=0.2},{intent="STOP_ESCAPE"}),true,"Preserve real DPS")
end)

test("defensive peel can protect a fleeing ally despite friendly focus", function()
    eq(check({mates={{focus=true},{focus=true}}},{intent="PEEL"}),false,"Emergency peel")
end)

test("Invoker combo remains protected from allied focus", function()
    eq(check({mates={{focus=true},{focus=true}}},{intent="SETUP_COMBO"}),true,"Prevent cancelling kill")
end)

test("bogus INTERRUPT label is not a bypass", function()
    eq(check({mates={{focus=true},{focus=true}}},{intent="INTERRUPT"}),true,"Require real channel")
end)

test("disarmed attackers do not suppress catch", function()
    eq(check({mates={{focus=true,disarmed=true},{focus=true,disarmed=true}},enemyHP=0.2},{intent="STOP_ESCAPE"}),false,"Cannot damage")
end)

test("cast sites wire OD, SD and Eul chase to the common guard", function()
    local function read(path)
        local f=assert(io.open(path,"rb"),"Missing "..path)
        local s=assert(f:read("*a"));f:close();return s
    end
    for _,p in ipairs({
        "bots/BotLib/hero_obsidian_destroyer.lua",
        "bots/BotLib/hero_shadow_demon.lua",
        "bots/ability_item_usage_generic.lua"
    }) do
        local code=read(p)
        assert(code:find("FunLib/oha_banish",1,true),"Not importing guard: "..p)
        assert(code:find("Banish.ShouldHoldEnemyBanish(",1,true),"No cast guard: "..p)
    end
    local item=read("bots/ability_item_usage_generic.lua")
    assert(item:find('intent = "STOP_ESCAPE", action = "eul_escape"',1,true),
        "Eul chase branch must provide explicit intent")
    assert(item:find('intent = "SETUP_COMBO", action = "eul_combo"',1,true),
        "Invoker combo must avoid accidental denial")
    assert(item:find('Trace.Observe(bot)',1,true),
        "Ability and item status must be observed when no cast was proposed")
    local od = read("bots/BotLib/hero_obsidian_destroyer.lua")
    local sd = read("bots/BotLib/hero_shadow_demon.lua")
    assert(od:find('"STOP_ESCAPE"',1,true) and od:find('"PEEL"',1,true))
    assert(sd:find('"PEEL"',1,true))
end)

local failed=0
for _,t in ipairs(tests) do
    local ok,err=pcall(t[2])
    if ok then io.write("PASS: ",t[1],"\n")
    else failed=failed+1;io.stderr:write("FAIL: ",t[1]," :: ",tostring(err),"\n") end
end
if #tests==0 or failed>0 then
    io.stderr:write(string.format("%d tests, %d failed\n",#tests,failed))
    os.exit(1)
end
io.write(string.format("%d tests, all passed\n",#tests))
