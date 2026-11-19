-- Cross-issue decision contract: uses actual production helpers from both TS-generated Lua files.
-- This is a deterministic mock of mode desires, NOT evidence of a complete Dota match.
local function read(path)
    local f=assert(io.open(path,"rb"),"Missing "..path)
    local s=assert(f:read("*a"));f:close();return s
end
local defendLua=read("bots/FunLib/aba_defend.lua")
local pushLua=read("bots/FunLib/aba_push.lua")
local a=assert(defendLua:find("function GetBaseCreepAttacker(ancient)",1,true))
local b=assert(defendLua:find("\nfunction GetThreatenedLane()",a,true))
local defenderFns=defendLua:sub(a,b-1)
local p=assert(pushLua:find("function IsCriticalBaseCreepAttack(ancient)",1,true))
local q=assert(pushLua:find("\nfunction ____exports.GetPushDesireHelper",p,true))
local criticalFn=pushLua:sub(p,q-1)
local x=assert(pushLua:find("    local decisivePushWindow = ",1,true))
local y=assert(pushLua:find("\n    local team = gameState.team",x,true))
local expr=pushLua:sub(x + #"    local decisivePushWindow = ",y-1)

local create=assert(loadstring([[
return function(world)
    local ancient={
        x=0,
        GetLocation=function(self) return {x=self.x} end,
        IsAlive=function() return true end,
        IsBuilding=function() return true end,
        GetHealth=function() return world.ancientHP or 1000 end,
        GetMaxHealth=function() return 1000 end,
    }
    local t4a,t4b={x=80},{x=-80}
    local nTeam=2
    local Lane={Top=1,Mid=2,Bot=3}
    local Tower={Base1=1,Base2=2}
    local BASE_THREAT_RADIUS=2600
    local members={}
    for i=1,(world.members or 4) do
        local b={x=i*250,hero=true,alive=true,id=i}
        function b:IsBot() return true end
        function b:IsIllusion() return false end
        function b:GetPlayerID() return self.id end
        function b:GetCurrentMovementSpeed() return 300 end
        members[#members+1]=b
    end
    local creeps={}
    for i=1,(world.creeps or 0) do
        local c={x=i*70,visible=world.visible ~= false,alive=true}
        c.GetAttackTarget=function()
            if world.attacking == false then return nil end
            return world.attackT4 and t4a or ancient
        end
        creeps[#creeps+1]=c
    end
    local jmz={
        IsValid=function(u) return u and u.visible ~= false and u.alive ~= false end,
        IsValidHero=function(u) return u and u.hero == true and u.alive ~= false end,
        IsSuspiciousIllusion=function(u) return false end,
        IsCore=function(u) return true end,
        IsDefending=function() return world.defending == true end,
        GetHP=function() return world.botHP or 0.9 end,
        Utils={CountEnemyHeroesNear=function() return world.enemiesAtAncient or 0 end},
    }
    local function IsValidBuildingTarget(unit) return unit and unit:IsAlive() and unit:IsBuilding() end
    local function GetTeam() return 2 end
    local function GetTower(_,which) return which==Tower.Base1 and t4a or t4b end
    local function GetUnitToLocationDistance(u,loc) return math.abs(u.x-loc.x) end
    local function GetTeamPlayers() return members end
    local function GetTeamMember(i) return members[i] end
    local function updateDefendUnitStateCache() return {enemyHeroes={},enemyCreeps=creeps} end
    local function updateUnitStateCache() return {enemyCreeps=creeps} end
]]..defenderFns..criticalFn..[[
    local function pushOpportunity(bot)
        local gameState={
            ourAncient=ancient,
            currentTime=world.time or 1800,
            aliveEnemyCount=world.enemiesAlive or 0,
            aliveAllyCount=world.members or 4,
            aliveAllyCoreCount=world.coresAlive or 2,
        }
        local nModeDesire=world.defendModeDesire or 0
        local StartToPushTime=960
        local enemiesHere={}
        return ]]..expr..[[
    end
    return {
        members=members, mid=Lane.Mid, top=Lane.Top,
        defend=function(bot,lane) return GetCreepBaseDefenseDesire(bot,lane or Lane.Mid,ancient) end,
        critical=function() return IsCriticalBaseCreepAttack(ancient) end,
        push=function(bot) return pushOpportunity(bot) end,
    }
end
]],"combined-production-contracts"))()

local tests={}
local function test(name,fn) tests[#tests+1]={name,fn} end
local function eq(actual,want)
    assert(actual==want,"expected "..tostring(want).." got "..tostring(actual))
end
test("one Ancient attacker selects exactly one responder and others may push",function()
    local g=create({creeps=1})
    eq(g.defend(g.members[1]),0.97)
    eq(g.defend(g.members[2]),nil)
    eq(g.defend(g.members[2],g.top),nil)
    eq(g.critical(),false)
    eq(g.push(g.members[2]),true)
end)
test("five active attackers reserve two defenders and suspend closing push",function()
    local g=create({creeps=5})
    eq(g.defend(g.members[1]),0.97)
    eq(g.defend(g.members[2]),0.97)
    eq(g.defend(g.members[3]),nil)
    eq(g.critical(),true)
    eq(g.push(g.members[3]),false)
end)
test("low Ancient HP recruits three defenders despite one attacker",function()
    local g=create({creeps=1,ancientHP=180})
    for i=1,3 do eq(g.defend(g.members[i]),0.97) end
    eq(g.defend(g.members[4]),nil)
    eq(g.critical(),true)
    eq(g.push(g.members[4]),false)
end)
test("passing waves do not falsely force backdoor recall",function()
    local g=create({creeps=8,attacking=false})
    eq(g.defend(g.members[1]),nil)
    eq(g.critical(),false)
    eq(g.push(g.members[2]),true)
end)
test("invisible creep data cannot start a critical warning",function()
    local g=create({creeps=8,visible=false})
    eq(g.defend(g.members[1]),nil)
    eq(g.critical(),false)
end)
test("active hero threat follows original combat defense instead",function()
    local g=create({creeps=1,enemiesAtAncient=2})
    eq(g.defend(g.members[1]),nil)
    assert(pushLua:find("if enemiesAtAncient >= 1 then",1,true))
end)
test("high-priority defense means no optimistic closing window",function()
    local g=create({creeps=0,defending=true,defendModeDesire=0.92})
    eq(g.push(g.members[1]),false)
end)
test("production banish helper remains independent of mode scoring",function()
    local Banish=assert(dofile("bots/FunLib/oha_banish.lua"))
    local hero=function(id,team)
        return {
            GetPlayerID=function()return id end,
            GetTeam=function()return team end,
            GetLocation=function() return {x=0} end,
            CanBeSeen=function()return true end,
            IsChanneling=function()return false end,
            IsIllusion=function()return false end,
            GetAttackTarget=function()return nil end,
        }
    end
    local bot,enemy=hero(1,2),hero(9,3)
    local J={
        IsValidHero=function(x) return x~=nil end,
        IsCastingUltimateAbility=function() return false end,
        GetAlliesNearLoc=function()return {} end,
        IsDisabled=function()return false end,
        GetHP=function()return 0.6 end,
    }
    eq(Banish.ShouldHoldEnemyBanish(bot,enemy,J,{intent="STOP_ESCAPE"}),false)
end)
local failed=0
for _,t in ipairs(tests) do
    local ok,err=pcall(t[2])
    if ok then io.write("PASS: ",t[1],"\n")
    else failed=failed+1;io.stderr:write("FAIL: ",t[1]," :: ",tostring(err),"\n") end
end
if failed>0 then
    io.stderr:write(string.format("%d joint tests, %d failed\n",#tests,failed))
    os.exit(1)
end
io.write(string.format("%d joint tests, all passed\n",#tests))
