-- 7.42 Weaver Time Lapse (Ally): test ACTUAL production skill and Consider
-- functions with Lua 5.1 mocks; never claim this replaces client validation.
local function read(path)
    local f=assert(io.open(path,"rb"));local s=assert(f:read("*a"));f:close();return s
end
local s=read("bots/BotLib/hero_weaver.lua")
local function slice(first,last)
    local a=assert(s:find(first,1,true),"missing: "..first)
    local b=assert(s:find(last,a+#first, true),"missing: "..last)
    return s:sub(a,b-1)
end
local think=slice("function X.SkillsComplement()","\nfunction X.ConsiderTheSwarm()")
local consider=slice("function X.ConsiderTimeLapse()","\nreturn X")
local initialize = [[
return function(opts)
    local bot, X, J, ally, enemy = {}, {}, {}, {}, {}
    local BOT_MODE_NONE, BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_HIGH = 0, 0, 0.8
    local TheSwarm, Shukuchi = {name="weaver_the_swarm"}, {name="weaver_shukuchi"}
    local TimeLapse = {name="weaver_time_lapse"}
    local TimeLapseAlly
    local botTarget, TheSwarmDesire, ShukuchiDesire, TimeLapseDesire, Target
    local actions={}
    function bot:GetAbilityByName(name)
        if name=="weaver_time_lapse_ally" and opts.scepter and opts.allyAvailable~=false then
            return {name="weaver_time_lapse_ally",
                IsFullyCastable=function()return opts.allyReady~=false end,
                IsHidden=function()return opts.allyHidden==true end,
                GetCastRange=function()return opts.castRange or 500 end}
        end
        return nil
    end
    function bot:HasScepter() return opts.scepter==true end
    function bot:HasModifier() return false end
    function bot:WasRecentlyDamagedByHero()return opts.selfDamaged==true end
    function bot:Action_UseAbility(ab)actions[#actions+1]={"self",ab.name}end
    function bot:Action_UseAbilityOnEntity(ab,t)actions[#actions+1]={"ally",ab.name,t}end
    function bot:Action_UseAbilityOnLocation(ab,t)actions[#actions+1]={"location",ab.name,t}end
    function J.CanNotUseAbility()return opts.cannotUse==true end
    function J.GetProperTarget()return nil end
    function J.IsRetreating(unit)
        if unit==bot then return opts.selfRetreat==true end
        return unit==ally and opts.allyRetreat==true
    end
    function J.GetHP(unit)
        if unit==bot then return opts.botHP or 1 end
        if unit==ally then return opts.allyHP or 0.2 end
        return 1
    end
    function J.IsValidHero(unit)return unit==ally or unit==enemy end
    function J.IsCore(unit)return unit==ally and opts.core~=false end
    function J.IsSuspiciousIllusion()return false end
    function J.IsDisabled()return false end
    function J.IsChasingTarget(u,t)
        return u==enemy and t==ally and opts.enemyChasing==true
    end
    function J.SetQueuePtToINT() end
    function J.GetProperCastRange(_,unit,range) assert(unit==bot);return range end
    function J.GetNearbyHeroes(unit,range,isEnemy)
        if unit==bot and isEnemy and range==1600 and opts.selfRetreat then
            return {enemy}
        elseif unit==bot and not isEnemy and range==(opts.castRange or 500)
           and opts.allyClose then
            return {ally}
        elseif unit==ally and isEnemy and range==1200
           and opts.enemyChasing then
            return {enemy}
        end
        return {}
    end
    function TimeLapse:IsFullyCastable()return opts.selfReady~=false end
    function Shukuchi:IsTrained()return true end
    function Shukuchi:GetCooldownTimeRemaining()return 1 end
    function ally:HasModifier()return false end
    function ally:WasRecentlyDamagedByAnyHero()return opts.allyDamaged==true end
    function X.ConsiderShukuchi()return opts.shukuchi and 0.8 or 0 end
    function X.ConsiderTheSwarm()return 0,nil end
]]
local ending=[[
    return {think=X.SkillsComplement,consider=X.ConsiderTimeLapse,actions=actions,
            ally=ally,enemy=enemy,bot=bot}
end
]]
local chunk,err=loadstring(initialize..think.."\n"..consider..ending, "weaver-actual-production")
assert(chunk,err)
local make=chunk()

local tests={}
local function test(label,fn)
    local ok,reason=pcall(fn)
    if not ok then io.stderr:write("FAIL "..label..": "..tostring(reason).."\n");os.exit(1) end
    tests[#tests+1]=label
    print("PASS "..label)
end
local function allyOptions()
    return {scepter=true,allyClose=true,allyRetreat=true,allyDamaged=true,
            enemyChasing=true,botHP=0.95,allyHP=0.2}
end

test("self Time Lapse works without Scepter",function()
    local x=make({selfRetreat=true,selfDamaged=true,botHP=0.2})
    x.think()
    assert(#x.actions==1 and x.actions[1][1]=="self")
    assert(x.actions[1][2]=="weaver_time_lapse")
end)
test("rescues core ally with separate 7.42 Time Lapse (Ally)",function()
    local x=make(allyOptions());x.think()
    local desire,target=x.consider()
    assert(desire>0 and target==x.ally)
    assert(#x.actions==1)
    assert(x.actions[1][1]=="ally" and x.actions[1][2]=="weaver_time_lapse_ally")
    assert(x.actions[1][3]==x.ally)
end)
test("missing ally ability does not block Shukuchi fallback",function()
    local opt=allyOptions();opt.allyAvailable=false;opt.shukuchi=true
    local x=make(opt);x.think()
    assert(#x.actions==1 and x.actions[1][2]=="weaver_shukuchi")
end)
test("no Scepter cannot submit ally action",function()
    local opt=allyOptions();opt.scepter=false
    local x=make(opt);x.think();assert(#x.actions==0)
end)
test("unavailable ally ability cannot submit ally action",function()
    local opt=allyOptions();opt.allyReady=false;opt.shukuchi=true
    local x=make(opt);x.think()
    assert(#x.actions==1 and x.actions[1][2]=="weaver_shukuchi")
end)
test("out of cast range ally remains untouched",function()
    local opt=allyOptions();opt.allyClose=false
    local x=make(opt);x.think();assert(#x.actions==0)
end)
test("unthreatened ally does not trigger rescue",function()
    local opt=allyOptions();opt.enemyChasing=false
    local x=make(opt);x.think();assert(#x.actions==0)
end)
test("non-core low-HP ally retains original filter",function()
    local opt=allyOptions();opt.core=false
    local x=make(opt);x.think();assert(#x.actions==0)
end)
test("self Time Lapse cooldown prevents requests",function()
    local opt=allyOptions();opt.selfReady=false
    local x=make(opt);x.think();assert(#x.actions==0)
end)
test("acquiring Scepter midgame refreshes ally ability",function()
    local opt=allyOptions();opt.scepter=false
    local x=make(opt);x.think();assert(#x.actions==0)
    opt.scepter=true;x.think()
    assert(#x.actions==1 and x.actions[1][2]=="weaver_time_lapse_ally")
end)
test("cannot act blocks both abilities",function()
    local opt=allyOptions();opt.cannotUse=true
    local x=make(opt);x.think();assert(#x.actions==0)
end)
test("old incorrect target cast not present in production",function()
    assert(not s:find("Action_UseAbilityOnEntity(TimeLapse, Target)",1,true))
    assert(s:find("Action_UseAbilityOnEntity(TimeLapseAlly, Target)",1,true))
    assert(s:find("bot:GetAbilityByName('weaver_time_lapse_ally')",1,true))
end)
test("hidden ally ability preserves Shukuchi fallback",function()
    local opt=allyOptions();opt.allyHidden=true;opt.shukuchi=true
    local x=make(opt);x.think()
    assert(#x.actions==1 and x.actions[1][2]=="weaver_shukuchi")
end)
test("uses actual ally ability cast range",function()
    local opt=allyOptions();opt.castRange=650
    local x=make(opt);x.think()
    assert(#x.actions==1 and x.actions[1][2]=="weaver_time_lapse_ally")
end)
test("losing Scepter stops ally actions",function()
    local opt=allyOptions();local x=make(opt);x.think()
    assert(#x.actions==1);opt.scepter=false;x.think()
    assert(#x.actions==1)
end)
print(string.format("%d Weaver production-function regressions passed",#tests))
