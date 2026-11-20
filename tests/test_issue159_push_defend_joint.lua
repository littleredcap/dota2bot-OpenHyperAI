-- Run the real generated mode entry points. Engine state plus unrelated
-- lane ranking and cooldown search are deterministic mocks.
local function fixture(opts)
    local function no() return false end
    local function yes() return true end
    local function empty() return {} end
    local function loc(x) return {x=x,y=0} end
    local function building(x,hp)
        return {x=x, IsAlive=yes, IsBuilding=yes, HasModifier=no,
            GetLocation=function() return loc(x) end, GetHealth=function() return hp end,
            GetMaxHealth=function() return 1000 end}
    end
    local Lan = {Top=1, Mid=2, Bot=3}
    local want = {None=0, ExtraLow=0.02, VeryLow=0.12}
    local ancient, enemy = building(0, opts.ancientHP or 1000), building(9900, 1000)
    local t4 = building(120, 1000)
    local orders, members, creeps = {}, {}, {}
    local now = opts.time or 1800
    for i=1,4 do
        local x = (opts.x or 5000) + (i-1) * 200
        members[i] = {
            x=x, IsBot=yes, IsHero=yes, IsAlive=yes, IsIllusion=no, IsInvulnerable=no,
            GetPlayerID=function() return i end, GetCurrentMovementSpeed=function() return 300 end,
            GetUnitName=function() return 'npc_dota_hero_mock' end, GetLevel=function() return 20 end,
            GetActiveMode=function() return 0 end, GetActiveModeDesire=function() return opts.defending and 0.95 or 0 end,
            GetAssignedLane=function() return Lan.Mid end, GetLocation=function() return loc(x) end,
            GetAttackTarget=function() return nil end, WasRecentlyDamagedByAnyHero=no,
            GetNearbyLaneCreeps=function() return opts.wave and {{},{}} or {} end,
            Action_AttackUnit=function() orders[#orders+1]='attack' end,
            SetTarget=function() orders[#orders+1]='target' end,
            Action_MoveToLocation=function() orders[#orders+1]='move' end,
            Action_AttackMove=function() orders[#orders+1]='attack move' end,
        }
    end
    for i=1,(opts.attackers or 0) do
        local x = opts.creepX or i*100
        creeps[i] = {x=x, IsCreep=yes, IsAncientCreep=no, visible=opts.visible ~= false,
            GetAttackTarget=function() return opts.t4 and t4 or ancient end}
    end
    local state = {
        currentTime=now, team=2, enemyTeam=3, ourAncient=ancient,
        enemyAncient=opts.direct and enemy or nil, aliveAllyCount=4, aliveEnemyCount=2,
        aliveAllyCoreCount=2, aliveEnemyCoreCount=1, teamNetworth=60000,
        enemyNetworth=40000, averageLevel=25, isLaningPhase=false,
    }
    local jmz = {
        IsValid=function(u) return u ~= nil and u.visible ~= false end,
        IsValidHero=function(u) return u.IsHero and u:IsHero() end,
        CanBeAttacked=yes, IsValidBuilding=no, IsCore=yes, IsLateGame=yes,
        IsDoingRoshan=no, IsDoingTormentor=no, CanNotUseAction=no,
        GetHP=function() return opts.hp or 1 end,
        GetHumanPing=function()
            if opts.ping then return {}, {time=now,normal_ping=false} end
        end,
        IsPingCloseToValidTower=function() return true,Lan.Mid end,
        IsDefending=function() return opts.defending end,
        GetAlliesNearLoc=function() return opts.baseAlly and {members[1]} or {} end,
        GetEnemiesAroundLoc=function() return opts.outer and 1 or 0 end,
        GetAverageLevel=function() return 20 end,
        GetNumOfAliveHeroes=function() return 4 end,
        IsInLaningPhase=no, IsEarlyGame=no, IsMidGame=no,
        GetTeamFountain=function() return loc(0) end,
        AdjustLocationWithOffsetTowardsFountain=function(point) return point end,
        Utils={
            GetTeamFountainTpPoint=function() return loc(0) end,
            CountEnemyHeroesNear=function(_, radius) return radius == 2200 and opts.heroPanic and 1 or 0 end,
            GetAllyIdsInTpToLocation=empty, NumHumanBotPlayersInTeam=function() return 0 end,
            IsBotThinkingMeaningfulAction=no, GameStates={defendPings={pingedTime=0}},
        },
    }
    local distance=function(u,v) return math.abs(u.x-v.x) end
    local modules = {
        ['bots/FunLib/jmz_func']=jmz,
        ['bots/ts_libs/dota/index']={Lane=Lan, BotModeDesire=want, BotMode={}, Barracks={},
            UnitType={Enemies=1, AlliedHeroes=2, AlliedCreeps=3, EnemyBuildings=4},
            Tower={Base1=1,Base2=2}, Team={Radiant=2,Dire=3}},
        ['bots/FunLib/global_cache']={
            getGlobalGameState=function() return state end, getGlobalLocationState=empty,
            getCachedAlliesNearLoc=function() return opts.localAllies and {members[1],members[2],members[3]} or {members[1]} end,
            getCachedEnemiesNearLoc=empty, autoCleanupCache=function() end,
        },
        ['bots/ts_libs/utils/native-operators']={},
        ['bots/FunLib/utils']={GetLocationToLocationDistance=distance,
            DireFountainTpPoint=loc(10000), RadiantFountainTpPoint=loc(0)},
        ['bots/Customize/general']={Enable=false},
        ['bots/FunLib/localization']={},
    }
    local env = setmetatable({
        GetScriptDirectory=function() return 'bots' end, GetTeam=function() return 2 end,
        GetOpposingTeam=function() return 3 end, GetGameMode=function() return 0 end,
        GameTime=function() return now end, DotaTime=function() return now end,
        GetAncient=function(team) return team == 2 and ancient or enemy end,
        GetTower=function(_, tower) return tower == 1 and t4 or nil end,
        GetBarracks=function() return nil end,
        GetTeamPlayers=function() return {1,2,3,4} end, GetTeamMember=function(i) return members[i] end,
        GetUnitList=function(kind) return kind == 1 and creeps or {} end,
        GetUnitToLocationDistance=distance, GetUnitToUnitDistance=distance,
        GetLaneFrontLocation=function() return loc(8000) end,
        RemapValClamped=function(value, lo, hi, first, last)
            return first + (last-first) * math.max(0, math.min(1, (value-lo)/(hi-lo)))
        end,
        require=function(name) return assert(modules[name],name) end,
    }, {__index=_G})
    local defend = setfenv(assert(loadfile('bots/FunLib/aba_defend.lua')), env)()
    modules['bots/FunLib/aba_defend']=defend
    local push = setfenv(assert(loadfile('bots/FunLib/aba_push.lua')), env)()
    push.WhichLaneToPush=function() return Lan.Mid end
    push.ShouldWaitForImportantItemsSpells=no
    return push,defend,members,orders,Lan
end

local function same(actual, expected, label)
    assert(math.abs(actual-expected)<0.00001, label .. ': expected ' .. expected .. ', got ' .. actual)
end
local function check(opts, id, expected, label)
    local push,_,members,orders,lane=fixture(opts)
    same(push.GetPushDesire(members[id],lane.Mid),expected,label)
    assert(#orders==0,label .. ' emitted an order')
end

check({}, 1, 0.88, '4v2 approach outranks optional farm')
check({x=7500}, 1, 0.08, 'isolated on high ground')
check({x=7500,wave=true}, 1, 0.88, 'allied wave supports high ground')
check({outer=true}, 1, 0.08, 'wider defense cap cannot raise isolation cap')
check({outer=true,localAllies=true}, 1, 0.65, 'wider defense cap cannot receive uplift')
check({attackers=4,localAllies=true}, 4, 0.82, 'critical wave cancels new uplift')
check({attackers=1,ancientHP=450,localAllies=true}, 4, 0.82, 'damaged Ancient under attack cancels uplift')
check({attackers=0,ancientHP=450}, 4, 0.88, 'low health but no attack is not a creep emergency')
check({attackers=4,creepX=2601}, 1, 0.88, 'out-of-radius units excluded by shared scanner')
check({attackers=4,visible=false}, 1, 0.88, 'unseen units excluded by shared scanner')
check({attackers=1,t4=true}, 4, 0.88, 'one T4 attacker does not call everyone off push')
check({attackers=4,ping=true,localAllies=true}, 4, 0.82, 'critical threat supersedes push ping')
check({attackers=1,ping=true}, 4, 0.9, 'single creep does not supersede push ping for nonresponders')
check({heroPanic=true}, 1, 0.02, 'enemy heroes threatening Ancient suppress push')
check({time=959}, 1, 0.08, 'before opening timer')
check({defending=true}, 1, 0.08, 'active defense cannot raise isolation cap')
check({x=9500,direct=true,localAllies=true}, 1, 0.98, 'direct finish only scored, not executed in desire')
check({x=9500,direct=true,localAllies=true,defending=true}, 1, 0.75, 'active defense prevents direct finish shortcut')
check({x=9500,direct=true,localAllies=true,outer=true}, 1, 0.65, 'wider defense prevents direct finish shortcut')

do
    local push,_,members,orders,lane=fixture({x=9500,direct=true,localAllies=true})
    same(push.GetPushDesire(members[1],lane.Top),0.12,'unselected top gets no finish boost')
    same(push.GetPushDesire(members[1],lane.Bot),0.12,'unselected bot gets no finish boost')
    assert(#orders==0)
end

do
    local push,defend,members,orders,lane=fixture({x=9500,direct=true,localAllies=true,attackers=1,ping=true})
    assert(members[1]._ohaCreepDefenseUntil==nil)
    for _, ln in pairs(lane) do
        same(push.GetPushDesire(members[1],ln),0,'responder skips urgency/ping before defense desire')
        push.PushThink(members[1],ln)
    end
    same(defend.GetDefendDesire(members[1],lane.Mid),0.97,'same scanner nominates actual defender')
    assert(#orders==0)
end

do
    local push,_,members,orders,lane=fixture({heroPanic=true})
    push.PushThink(members[1],lane.Mid)
    assert(#orders==0)
end
print('PASS: 22 joint #159/#176 generated push and defense scenarios')
