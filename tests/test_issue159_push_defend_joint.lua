-- Run the real generated mode entry points. Engine state plus unrelated
-- lane ranking and cooldown search are deterministic mocks.
local function fixture(opts)
    local function no() return false end
    local function yes() return true end
    local function empty() return {} end
    local function loc(x) return {x=x,y=0} end
    local function building(x,hp)
        return {x=x, IsAlive=yes, IsBuilding=yes, CanBeSeen=no, HasModifier=no, GetAttackTarget = function() return opts.towerTarget end,
            GetLocation=function() return loc(x) end, GetHealth=function() return hp end,
            GetUnitName=function() return 'npc_dota_tower_' .. x end,
            GetMaxHealth=function() return 1000 end, GetActualIncomingDamage=function(_, dmg) return dmg * 0.65 end}
    end
    local Lan = {Top=1, Mid=2, Bot=3}
    local want = {None=0, ExtraLow=0.02, VeryLow=0.12, High=0.7}
    local ancient, enemy = building(0, opts.ancientHP or 1000), building(9900, 1000)
    enemy.HasModifier = function(_, name) return opts.ancientProtected and name == 'modifier_backdoor_protection_active' end
    enemy.GetHealth = function() return opts.enemyAncientHP or 1000 end
    local t4 = building(120, 1000)
    local highTower = building(opts.highTowerX or 8200, 1000)
    local outerTower = building(6000, 1000)
    local rearTower = building(3500, 1000)
    local topTower, counterTower = building(6800, 1000), building(9100, 1000)
    local fightTower = building(7200, 1000)
    fightTower.HasModifier = function(_, name) return opts.postFightProtected and name == 'modifier_backdoor_protection_active' end
    outerTower.GetUnitName = function() return 'npc_dota_goodguys_tower1_mid' end
    topTower.GetUnitName = function() return 'npc_dota_goodguys_tower1_top' end
    counterTower.GetUnitName = function() return 'npc_dota_badguys_tower1_top' end
    local melee, ranged = building(8650, 1000), building(8690, 1000)
    melee.GetUnitName = function() return 'npc_dota_badguys_melee_rax_mid' end
    ranged.GetUnitName = function() return 'npc_dota_badguys_range_rax_mid' end
    melee.IsAlive = function() return not opts.meleeDestroyed end
    melee.HasModifier = function(_, name)
        return name == 'modifier_backdoor_protection_in_base'
            or (opts.meleeProtected and name == 'modifier_backdoor_protection_active')
    end
    ranged.IsAlive = function() return not opts.rangedDestroyed end
    local orders, members, creeps = {}, {}, {}
    local conversionCreep = {x=opts.conversionX or 5450, GetUnitName=function() return "npc_dota_creep_badguys_ranged" end,
        GetLocation=function(self) return {x=self.x, lane=Lan.Mid} end}
    local now = opts.time or 1800
    local function advanceTime(seconds) now = now + seconds end
    for i=1,(opts.allyCount or 4) do
        local x = (opts.x or 5000) + (i-1) * 200
        members[i] = {
            x=x, IsBot=yes, IsHero=yes, IsAlive=yes, IsIllusion=no, IsInvulnerable=no, IsNull=no,
            IsChanneling=no, IsUsingAbility=no, IsDisarmed=no, IsStunned=no, IsHexed=no, IsNightmared=no, IsRooted=no, HasModifier=no,
            GetTeam=function() return 2 end, GetSecondsPerAttack=function() return 1 end,
            GetAttackDamage=function(self) return self.damage or 100 end,
            GetPlayerID=function() return i end, GetCurrentMovementSpeed=function() return 300 end,
            GetUnitName=function() return 'npc_dota_hero_mock' end, GetLevel=function() return 20 end,
            GetActiveMode=function() return 0 end, GetActiveModeDesire=function() return opts.defending and 0.95 or 0 end,
            GetAssignedLane=function() return Lan.Mid end, GetLocation=function(self) return loc(self.x) end,
            GetAttackTarget=function() return nil end, WasRecentlyDamagedByAnyHero=no, WasRecentlyDamagedByTower=no,
            GetAttackRange=function() return 650 end, GetNearbyTowers=empty, GetNearbyCreeps=empty,
            GetNearbyLaneCreeps=function(_, _, enemies)
                if enemies then return {} end
                return opts.counterPush and {{x=9000},{x=9050},{x=9100}}
                    or opts.wave and {{x=x},{x=x}} or {}
            end,
            Action_AttackUnit=function(_, unit, once) opts.lastAttackOnce=once; orders[#orders+1]=opts.captureTargets and unit or 'attack' end,
            Action_ClearActions=function() orders[#orders+1]='cancel' end,
            SetTarget=function() orders[#orders+1]='target' end,
            Action_MoveToLocation=function(_, point) orders[#orders+1]=opts.captureTargets and point or 'move' end,
            Action_AttackMove=function() orders[#orders+1]='attack move' end,
        }
    end
    for i=1,(opts.attackers or 0) do
        local x = opts.creepX or i*100
        creeps[i] = {x=x, IsCreep=yes, IsAncientCreep=no, visible=opts.visible ~= false,
            GetUnitName=function() return opts.mega and 'npc_dota_creep_badguys_melee_upgraded_mega'
                or opts.super and 'npc_dota_creep_badguys_melee_upgraded' or 'npc_dota_creep_badguys_melee' end,
            IsFacingLocation=function() return not opts.movingAway end,
            GetAttackTarget=function() if not opts.mega and not opts.super then return opts.t4 and t4 or ancient end end}
    end
    for i=1,(opts.towerCreeps or 0) do
        creeps[i] = {x=outerTower.x, IsCreep=yes, IsAncientCreep=no,
            GetLocation=function() return loc(outerTower.x) end, GetHealth=function() return 200 end,
            GetCurrentMovementSpeed=function() return 300 end,
            GetUnitName=function() return 'npc_dota_creep_badguys_melee' end,
            GetAttackTarget=function() return opts.waveAttacking and outerTower or nil end}
    end
    if opts.approach or opts.bigWave then
        for i=1,(opts.bigWave and 6 or 4) do
            local x = opts.approach and 7900 + i * 15 or 6450 + i * 15
            creeps[#creeps+1] = {x=x, IsCreep=yes, IsAncientCreep=no,
                GetLocation=function() return loc(x) end, GetAttackTarget=function() end,
                GetHealth=function() return opts.bigWave and 400 or 200 end,
                GetCurrentMovementSpeed=function() return 300 end,
                GetUnitName=function() return opts.bigWave and i == 6 and 'npc_dota_badguys_siege'
                    or 'npc_dota_creep_badguys_melee' end}
        end
    end
    local state = {
        currentTime=now, team=2, enemyTeam=3, ourAncient=ancient,
        enemyAncient=opts.direct and enemy or nil, aliveAllyCount=#members, aliveEnemyCount=opts.enemyAliveAtStart or 2,
        aliveAllyCoreCount=2, aliveEnemyCoreCount=1, teamNetworth=60000,
        enemyNetworth=40000, averageLevel=25, isLaningPhase=false, reinforcementWindow=opts.reinforcementWindow or 26,
    }
    local function stagedWave()
        local function laneCreep(x, lane, siege)
            return {x=x, GetUnitName=function() return siege and 'npc_dota_goodguys_siege' or 'npc_dota_creep_goodguys_melee' end,
                GetLocation=function() return {x=x, lane=lane} end, GetCurrentMovementSpeed=function() return 300 end,
                GetAttackTarget=function() return opts.alliedWaveHitting and counterTower or nil end}
        end
        if opts.counterPush then
            local wave, offset = {}, opts.waveOffset or 0
            for i = 1, (opts.waveCount or 3) do wave[i] = laneCreep(8950 + i * 50 - offset, Lan.Top, opts.alliedCatapult and i == 1) end
            return wave
        end
        if opts.postFight then
            local wave = {}
            for lane, front in pairs(opts.fightWaves or {}) do
                for i=1,3 do
                    local point = opts.fightCreepOffsets and opts.fightCreepOffsets[i] or i * 30
                    wave[#wave+1] = laneCreep(front + point, lane, false)
                end
            end
            return wave
        end
        if opts.stagedWave then return {laneCreep(5000, Lan.Mid), laneCreep(5100, Lan.Mid)} end
        if opts.wave then return {laneCreep(opts.x, Lan.Mid), laneCreep(opts.x + 30, Lan.Mid)} end
        return {}
    end
    local jmz = {
        IsValid=function(u) return u ~= nil and u.visible ~= false end,
        IsValidHero=function(u) return u and u.IsHero and u:IsHero() end,
        CanBeAttacked=yes, IsValidBuilding=function(u) return opts.direct and u ~= nil and u.IsBuilding ~= nil and u:IsAlive() end,
        IsCore=function(unit) return not opts.conversionCore or unit:GetPlayerID() == opts.conversionCore end, IsLateGame=yes, IsTormentor=no, IsRoshan=no,
        IsDoingRoshan=no, IsDoingTormentor=no, CanNotUseAction=no,
        ShouldRetreatFromEnemyReinforcements=function() return opts.retreatNow end,
        GetHP=function(u) return u == enemy and enemy:GetHealth() / 1000 or (u and u.hp) or opts.hp or 1 end,
        GetMP=function() return 1 end,
        IsInRange=function(u, v, radius) return math.abs(u.x-v.x) <= radius end,
        VectorTowards=function(point, _, offset) return loc(point.x-offset) end,
        GetRandomLocationWithinDist=function(point) return point end,
        GetHumanPing=function()
            if opts.ping then return {}, {time=now,normal_ping=false} end
        end,
        IsPingCloseToValidTower=function() return true,Lan.Mid end,
        IsDefending=function() return opts.defending end,
        GetAlliesNearLoc=function(point)
            if opts.localAllies and point.x == outerTower.x then return members end
            return opts.baseAlly and {members[1]} or {}
        end,
        GetEnemiesAroundLoc=function() return opts.outer and 1 or 0 end,
        GetAverageLevel=function() return 20 end,
        GetAliveCoreCount=function(enemies) return enemies and 1 or 2 end,
        GetInventoryNetworth=function() return 60000,40000 end,
        DoesTeamHaveAegis=no, GetCurrentRoshanLocation=empty, GetTormentorLocation=empty,
        GetTormentorWaitingLocation=empty, IsSuspiciousIllusion=no, IsMeepoClone=no,
        GetNumOfAliveHeroes=function(enemies) return enemies and (opts.aliveEnemies or 2) or 4 end,
        GetAvailableFightAllies=function()
            return opts.backupLost and 0 or (opts.localAllies and 2 or 0)
        end,
        GetEnemiesNearLoc=function(point)
            if opts.counterPush and point.x == 5000 then return {{}, {}, {}, {}} end
            local nearby = {}
            local count = point.x == enemy.x and opts.defendersAtAncient or opts.visibleDefenders or 0
            for _=1,count do nearby[#nearby+1] = {} end
            return nearby
        end,
        GetLastSeenEnemiesNearLoc=empty,
        CanCommitToLaneTeleport=function(_, point, clear)
            if clear and opts.unsafeConversion and point.x == conversionCreep.x then return false end
            return not opts.unsafeLanding and (not clear or point.x ~= outerTower.x
                or (opts.safeSiege and (opts.visibleDefenders or 0) == 0))
        end,
        IsInLaningPhase=no, IsEarlyGame=no, IsMidGame=no,
        GetPosition=function(unit) return unit:GetPlayerID() + 1 end,
        GetNearbyHeroes=empty, WeAreStronger=no, GetTeamFountain=function() return loc(0) end,
        IsRetreating=no, IsPushing=no, IsFarming=no, IsDisabled=no, IsKeyWordUnit=function(word, unit)
            return unit:GetUnitName():find(word, 1, true) ~= nil
        end,
        AdjustLocationWithOffsetTowardsFountain=function(point) return point end,
        Utils={
            GetTeamFountainTpPoint=function() return loc(0) end,
            CountEnemyHeroesNear=function(_, radius) return radius == 2200 and opts.heroPanic and 1 or 0 end,
            GetAllyIdsInTpToLocation=empty, NumHumanBotPlayersInTeam=function() return 0 end,
            CountEnemyHeroesOnHighGround=function() return 0 end, GetCachedVars=function() end,
            SetCachedVars=function() end, GetLocationToLocationDistance=function(a, b) return math.abs(a.x - b.x) end,
            AbilityBehaviorHasFlag=function(behavior, flag) return math.floor(behavior / flag) % 2 == 1 end,
            IsBotThinkingMeaningfulAction=no, GameStates={defendPings={pingedTime=0}}, IsAnyBarracksOnLaneAlive=yes,
        },
    }
    local distance=function(u,v) return math.abs(u.x-v.x) end
    jmz.GetLocationToLocationDistance = distance
    local modules = {
        ['bots/FunLib/jmz_func']=jmz,
        ['bots/ts_libs/dota/index']={Lane=Lan, BotModeDesire=want, BotMode={}, Barracks={TopMelee=1, MidMelee=2, MidRanged=3},
            UnitType={Enemies=1, AlliedHeroes=2, AlliedCreeps=3, EnemyBuildings=4, EnemyCreeps=9},
            Tower={Base1=1,Base2=2,Mid1=11,Top1=10,Top2=20,Mid2=21,Mid3=31}, Team={Radiant=2,Dire=3}},
        ['bots/FunLib/global_cache']={
            getGlobalGameState=function()
                state.aliveEnemyCount = opts.postFightEnemyAlive or state.aliveEnemyCount
                return state
            end,
            getGlobalLocationState=function() return {teamFountain=loc(0)} end,
            getCachedAlliesNearLoc=function() return opts.localAllies and {members[1],members[2],members[3]} or {members[1]} end,
            getCachedEnemiesNearLoc=empty, autoCleanupCache=function() end,
            getCachedData=function(_, _, read) return read() end,
        },
        ['bots/ts_libs/utils/native-operators']={},
        ['bots/FunLib/utils']={GetLocationToLocationDistance=distance,
            DireFountainTpPoint=loc(10000), RadiantFountainTpPoint=loc(0),
            CachedVarsCleanTime=60, CleanupCachedVars=function() end},
        ['bots/FunLib/version']={},
        ['bots/Customize/general']={Enable=false},
        ['bots/FunLib/localization']={},
    }
    local env = setmetatable({
        GetScriptDirectory=function() return 'bots' end, GetTeam=function() return 2 end,
        GetOpposingTeam=function() return 3 end, GetGameMode=function() return 0 end,
        GameTime=function() return now end, DotaTime=function() return now end,
        GetAncient=function(team) return team == 2 and ancient or enemy end,
        GetTower=function(team, tower)
            if opts.rearTower and team == 2 and tower == 21 then return rearTower end
            if opts.postFight and team == 3 then
                if tower == 21 and not opts.postFightHighGround then return fightTower end
                if tower == 31 and opts.postFightHighGround then return fightTower end
                if tower == 20 then return counterTower end
            end
            if team == 3 and opts.highTowerX and tower == 31 then return highTower end
            if opts.counterPush and team == 3 and tower == 10 then return counterTower end
            if (opts.rotatePressure or opts.friendlyTower) and team == 2 and tower == 10 then return topTower end
            return tower == 1 and t4 or (opts.outerSiege and tower == (opts.highDefend and 31 or 11) and outerTower or nil)
        end,
        GetBarracks=function(team, barrack)
            if team == 3 and opts.rotate and barrack == 1 then return melee end
            if team == 3 and opts.objectives then
                if barrack == 2 and melee:IsAlive() then return melee end
                if barrack == 3 and ranged:IsAlive() then return ranged end
            end
        end,
        GetTeamPlayers=function() return opts.allyCount == 5 and {1,2,3,4,5} or {1,2,3,4} end,
        GetTeamMember=function(i) return members[i] end,
        GetUnitList=function(kind)
            if kind == 1 then return creeps end
            if kind == 3 then return stagedWave() end
            if kind == 9 and opts.conversion then
                conversionCreep.visible = not opts.conversionFog
                return {conversionCreep}
            end
            if kind == 4 and opts.objectives then return {melee,ranged} end
            return {}
        end,
        GetUnitToLocationDistance=distance, GetUnitToUnitDistance=distance,
        Vector=function(x,y,z) return {x=x,y=y,z=z} end,
        GetHeightLevel=function(point) return opts.uphillStaging and point.x == 6300 and 2 or 1 end,
        IsHeroAlive=function() return opts.enemySightings ~= nil end,
        GetHeroLastSeenInfo=function(id) return opts.enemySightings and opts.enemySightings[id] end,
        GetIncomingTeleports=function() return opts.incoming or {} end, RandomFloat=function(first) return first end,
        GetTeamForPlayer=function(id) return id <= #members and 2 or 3 end,
        GetGlyphCooldown=function() return opts.glyphCooldown or 180 end,
        IsLocationPassable=yes, TEAM_RADIANT=2, LANE_TOP=1, LANE_MID=2, LANE_BOT=3, UNIT_LIST_ENEMY_CREEPS=1, UNIT_LIST_ALLIED_CREEPS=3,
        ABILITY_BEHAVIOR_UNIT_TARGET=8, ABILITY_BEHAVIOR_POINT=16,
        GetAmountAlongLane=function(lane, point)
            return {amount=point.x / 10000, distance=point.lane and point.lane ~= lane and 650 or point.y or 0}
        end,
        GetLocationAlongLane=function(lane, amount) return {x=amount*10000, y=0, lane=lane} end,
        PointToLineDistance=function() return opts.badFarmPath and {within=true, distance=100} or nil end,
        GetLaneFrontLocation=function(_, lane)
            return loc(opts.postFight and opts.fightWaves and opts.fightWaves[lane] or 8000)
        end,
        RemapValClamped=function(value, lo, hi, first, last)
            return first + (last-first) * math.max(0, math.min(1, (value-lo)/(hi-lo)))
        end,
        require=function(name) return assert(modules[name],name) end,
    }, {__index=_G})
    local file = assert(io.open('bots/FunLib/jmz_func.lua', 'rb'))
    local source = file:read('*a')
    file:close()
    local first = assert(source:find('function J.HasSiegeDamageInRange(', 1, true))
    local last = assert(source:find('function J.CanCommitToLaneTeleport(', first, true))
    env.J = jmz
    setfenv(assert(loadstring(source:sub(first, last - 1))), env)()
    if not opts.outerSiege then jmz.GetOuterTowerThreat = function() return {score=0} end end
    if opts.outerSiege then
        local spell = {IsUltimate=no, GetManaCost=function() return 100 end,
            GetBehavior=function() return opts.unitTargetClear and 8 or 16 end,
            GetAOERadius=function() return 270 end, GetSpecialValueInt=function() return 0 end,
            GetAbilityDamage=function() return opts.spellDamage or 180 end, GetCastRange=function() return opts.spellRange or 750 end,
            GetCooldownTimeRemaining=function() return opts.spellCooldown or 0 end}
        for _, member in ipairs(members) do
            member.HasModifier = no
            member.WasRecentlyDamagedByTower = no
            member.IsChanneling, member.IsCastingAbility, member.IsUsingAbility = no, no, no
            member.GetMana = function() return 200 end
            member.GetAbilityInSlot = function(self, slot)
                return (self == members[3] or opts.twoClearers and self == members[2]) and slot == 1 and spell or nil
            end
        end
        jmz.WeAreStronger = function() return opts.localAdvantage == true end
        jmz.GetLastSeenEnemiesNearLoc = function(point)
            if point.x == topTower.x and opts.rotatePressure then return {5, 6, 7, 8, 9} end
            if point.x == outerTower.x and not opts.safeSiege and not opts.rotatePressure and not opts.approach then
                if opts.singleAttacker then return {5} end
                return opts.twoAttackers and {5, 6} or {5, 6, 7, 8}
            end
            return {}
        end
        local enemyScan = jmz.GetEnemiesNearLoc
        jmz.GetEnemiesNearLoc = function(point, radius)
            if opts.approach and point.x == outerTower.x and radius >= 3200 then
                local function approachingEnemy(id, x)
                    return {x=x, GetPlayerID=function() return id end, GetLocation=function() return loc(x) end,
                        IsFacingLocation=function() return not opts.movingAway end, GetAttackTarget=function() end}
                end
                return {approachingEnemy(5, 8000), approachingEnemy(6, 8150)}
            end
            if opts.holdDanger and point.x == outerTower.x - 600 then return {{}, {}} end
            return enemyScan(point, radius)
        end
        jmz.AdjustLocationWithOffsetTowardsFountain = function(point, shift) return loc(point.x - shift) end
        jmz.GetAlliesNearLoc = function(point, radius)
            if not opts.contest then return members end
            local nearby = {}
            for _, ally in ipairs(members) do
                if ally:IsAlive() and distance(ally, point) <= radius then nearby[#nearby+1] = ally end
            end
            return nearby
        end
        if opts.contest then
            jmz.IsDefending = yes
            jmz.CanCommitToLaneTeleport = function(_, point, _, radius)
                return not opts.unsafeLanding and #jmz.GetEnemiesNearLoc(point, radius or 1500) == 0
            end
            jmz.GetEnemiesNearLoc = function(point, radius)
                local nearby = {}
                for _, foe in ipairs(opts.contest) do
                    if distance(point, foe) <= radius and not foe.hidden then nearby[#nearby+1] = foe end
                end
                return nearby
            end
        end
        local scroll = {}
        jmz.GetItem2 = function(ally, name)
            if name == 'item_tpscroll' and (opts.safeTP and ally == members[3] or opts.contest and ally.scroll) then return scroll end
        end
        jmz.CanCastAbility = function(item) return item == scroll end
        jmz.Utils.HasTeamMemberWithCriticalItemInCooldown = function() return opts.criticalCooldown end
        jmz.Utils.HasTeamMemberWithCriticalSpellInCooldown = no
        jmz.Utils.HasCriticalSpellWithCooldown = function(ally, eta) return (ally.cooldown or 0) > eta end
        jmz.CanCastAbilitySoon = function(ability, seconds) return ability ~= nil and ability:GetCooldownTimeRemaining() <= seconds end
        local first = assert(source:find('local function IsSiegeSummon(', 1, true))
        local last = assert(source:find('function J.ShouldRetreatFromEnemyReinforcements(', first, true))
        setfenv(assert(loadstring(source:sub(first, last - 1))), env)()
    end
    local defend = setfenv(assert(loadfile('bots/FunLib/aba_defend.lua')), env)()
    modules['bots/FunLib/aba_defend']=defend
    local push = setfenv(assert(loadfile('bots/FunLib/aba_push.lua')), env)()
    if not opts.rotate then push.WhichLaneToPush=function() return Lan.Mid end end
    push.ShouldWaitForImportantItemsSpells=no
    local farm
    if opts.farmBot then
        local bot = members[opts.farmBot]
        local laneCreepPoint = loc(bot.x + 100)
        local laneCreep = {x = laneCreepPoint.x, GetTeam = function() return 3 end,
            IsNull = no, CanBeSeen = yes, IsAlive = function() return opts.farmWave or opts.waveMoved end,
            IsCreep = yes, IsAncientCreep = no, GetAttackTarget = function() end,
            GetCurrentMovementSpeed = function() return 300 end,
            GetUnitName = function() return 'npc_dota_creep_badguys_melee' end,
            GetLocation = function() return laneCreepPoint end}
        local distantCreeps = {}
        if opts.distantWave then
            for i = 1, 3 do
                local point = loc(bot.x + 1800 + 40 * i)
                distantCreeps[i] = setmetatable({x=point.x, GetLocation=function() return point end}, {__index=laneCreep})
            end
        end
        local lanes = {[Lan.Top] = loc(bot.x + 800), [Lan.Mid] = loc(bot.x + 1200), [Lan.Bot] = loc(bot.x + 1600)}
        local closeCamp = {cattr = {location = loc(bot.x - (opts.closeCampDistance or 680))}}
        local farCamp = {cattr = {location = loc(bot.x - 1500)}}
        local neutral = {x = closeCamp.cattr.location.x, IsAncientCreep = no, GetTeam = function() return 4 end,
            GetHealth = function() return opts.neutralHP or 300 end}
        local midas = {}
        bot.GetNearbyLaneCreeps = function()
            if opts.supportWave then return {laneCreep, laneCreep, laneCreep} end
            return (not opts.route or opts.farmWave) and {laneCreep} or {}
        end
        bot.HasModifier, bot.IsChanneling = no, no
        bot.GetAssignedLane = function() return opts.farmAssignedLane or Lan.Mid end
        bot.WasRecentlyDamagedByAnyHero = function(_, seconds) return opts.carryHarass and seconds >= 5 end
        bot.WasRecentlyDamagedByCreep = no
        bot.GetNearbyTowers, bot.GetNearbyBarracks, bot.GetNearbyNeutralCreeps = empty, empty, empty
        bot.DistanceFromFountain = function() return 1000 end
        if opts.resetMode then
            bot.GetActiveMode, bot.GetActiveModeDesire = function() return 7 end, function() return 0.9 end
        end
        bot.GetAttackRange = function() return 600 end
        bot.GetHealth = function() return 1500 end
        bot.GetNetWorth = function() return opts.farmNetWorth or 10000 end
        if opts.farmLevel then bot.GetLevel = function() return opts.farmLevel end end
        bot.GetTeam = function() return 2 end
        bot.GetAbilityByName = function() end
        bot.Action_MoveToLocation = function(_, point) orders[#orders + 1] = point end
        bot.Action_ClearActions = function() orders[#orders + 1] = 'cancel' end
        bot.GetNearbyNeutralCreeps = function()
            local creeps = {}
            for _ = 1, (opts.neutralCount or (opts.occupied and 1 or 0)) do
                creeps[#creeps + 1] = neutral
            end
            return creeps
        end
        local ally = members[2]
        ally.GetAttackTarget = function() return opts.occupied and neutral or nil end
        jmz.Role = {IsCampRefreshDone = yes, NotSayRate = no, IsPvNMode = no,
            availableCampTable = opts.route and {closeCamp, farCamp} or {}}
        jmz.Site = {
            RefreshCamp = function()
                opts.campRefreshes = (opts.campRefreshes or 0) + 1
                return opts.route and {closeCamp, farCamp} or {}, opts.route and 2 or 0
            end,
            GetClosestNeutralSpwan = function(_, camps) return camps[1] end,
            GetFarmLaneTarget = function() return laneCreep end,
            FindFarmNeutralTarget = function(units) return units[1] end,
            IsTimeToFarm = yes, IsModeSuitableToFarm = yes, IsEnemyCamp = no, IsSmallCamp = yes, IsMediumCamp = no,
            UpdateAvailableCamp = function()
                opts.removedCamp = true
                return {farCamp}, nil
            end,
        }
        jmz.GetPosition = function(unit) return unit == bot and (opts.farmPosition or 1) or 1 end
        jmz.GetMP = function() return opts.mana or 1 end
        jmz.IsCore = function(unit) return jmz.GetPosition(unit) <= 3 end
        jmz.GetProperTarget = function() end
        jmz.CheckLoneDruid, jmz.GetEnemyList, jmz.GetAllyList = empty, empty, empty
        jmz.GetDistanceFromEnemyFountain = function() return 6000 end
        jmz.IsMeepoClone, jmz.DoesTeamHaveAegis = no, no
        jmz.WeAreStronger = yes
        jmz.GetTormentorLocation, jmz.GetCurrentRoshanLocation = empty, empty
        jmz.GetInventoryNetworth = function() return 20000, 20000 end
        jmz.IsRoshanAlive, jmz.IsGoingOnSomeone, jmz.IsRetreating, jmz.IsInRange = no, no, no, no
        jmz.IsInTeamFight = function() return opts.teamfight == true end
        jmz.IsPushing = no
        jmz.GetLocationTowardDistanceLocation = function(unit, point, step)
            return loc(unit.x + (point.x > unit.x and step or -step))
        end
        jmz.GetLocationToLocationDistance = distance
        jmz.IsRoshan = no
        jmz.GetLaningAttackDamage = bot.GetAttackDamage
        jmz.GetTeamFightLocation = function() end
        jmz.GetAllyCount, jmz.GetNumOfTeamTotalKills = function() return 1 end, function() return 0 end
        jmz.GetLastSeenEnemiesNearLoc = function(point)
            if point.x == bot.x - 750 and opts.unsafeCampPath then return {7} end
            if point.x == ancient.x and opts.baseEnemyId then return {opts.baseEnemyId} end
            if point.x > bot.x and opts.laneThreat then return {7, 8} end
            return {}
        end
        jmz.IsInLaningPhase = function() return opts.laning == true end
        jmz.IsItemAvailable = function() return not opts.route and midas or nil end
        jmz.IsInAllyArea = yes
        jmz.CanCastAbility = function(item) return item == midas end
        jmz.GetAliveCoreCount = function() return 2 end
        jmz.IsModeTurbo, jmz.IsFarming, jmz.IsLaning = no, no, no
        jmz.IsLateGame = function() return now > 30 * 60 end
        jmz.GetCenterOfUnits = function() return laneCreepPoint end
        jmz.GetAlliesNearLoc = function(point)
            if point == laneCreepPoint and opts.waveOwner then return {ally} end
            if point == lanes[Lan.Top] and opts.waveClaimed then return {ally} end
            return point == closeCamp.cattr.location and opts.occupied and {ally} or {}
        end
        local farmEnv = setmetatable({
            GetBot = function() return bot end, Vector = loc, RandomInt = function(low) return low end,
            GetUnitList = function(kind)
                if kind == 8 then return opts.visibleCampUnit and {neutral} or {} end
                if opts.distantWave and kind == env.UNIT_LIST_ENEMY_CREEPS then return distantCreeps end
                if opts.tradeWaves and kind == env.UNIT_LIST_ENEMY_CREEPS then
                    local visible = {}
                    for _, lane in ipairs(opts.tradeWaves) do
                        local point = lanes[lane]
                        point.lane = lane
                        for i=1,3 do
                            visible[#visible+1] = setmetatable({x=point.x+i, GetLocation=function() return point end}, {__index=laneCreep})
                        end
                    end
                    return visible
                end
                if opts.returnWave and kind == env.UNIT_LIST_ENEMY_CREEPS then return {laneCreep} end
                return env.GetUnitList(kind)
            end,
            GetRoshanDesire = function() return 0 end,
            DotaTime = function() return now end,
            GetLaneFrontLocation = function(_, lane) return lanes[lane] end,
            GetTower = function(team, id)
                if opts.laning and id == 11 and opts.laneTower then return building(lanes[Lan.Mid].x, 1000) end
                if opts.laning and id == 12 and opts.laneTower and opts.farmAssignedLane == Lan.Bot then
                    return building(lanes[Lan.Bot].x, 1000)
                end
                return env.GetTower(team, id)
            end,
            GetHeroDeaths = function() return 0 end,
            IsLocationVisible = function(point)
                return not opts.campHidden or (point ~= closeCamp.cattr.location and point ~= farCamp.cattr.location)
            end,
            LANE_TOP = Lan.Top, LANE_MID = Lan.Mid, LANE_BOT = Lan.Bot,
            TOWER_TOP_1 = 10, TOWER_MID_1 = 11, TOWER_BOT_1 = 12,
            TEAM_NEUTRAL = 4, GAMEMODE_MO = 99, Min = math.min,
            BOT_MODE_DESIRE_NONE = 0, BOT_MODE_DESIRE_MODERATE = 0.5, BOT_MODE_DESIRE_VERYHIGH = 0.9,
            BOT_MODE_DESIRE_ABSOLUTE = 1, BOT_MODE_DESIRE_HIGH = 0.7, BOT_MODE_DESIRE_LOW = 0.2, BOT_MODE_ITEM = 15,
            UNIT_LIST_NEUTRAL_CREEPS = 8, BOT_MODE_RETREAT = 7,
            GAMEMODE_1V1MID = 98,
        }, {__index = env})
        jmz.GetEnemiesNearLoc = function(point)
            return (opts.dangerInLanes and point.x > bot.x or opts.dangerAtFarCamp and point == farCamp.cattr.location) and {{}} or {}
        end
        setfenv(assert(loadfile('bots/mode_farm_generic.lua')), farmEnv)()
        farm = {GetDesire = farmEnv.GetDesire, Think = farmEnv.Think, OnEnd = farmEnv.OnEnd}
        function farm.SetThreatVisible(visible) creeps[1].visible = visible end
        farm.AdvanceTime = advanceTime
        farm.lanes, farm.camps = lanes, {closeCamp, farCamp}
    end
    return push,defend,members,orders,Lan,farm,
        {ancient=enemy, ourAncient=ancient, melee=melee, ranged=ranged, outerTower=outerTower, counterTower=counterTower, fightTower=fightTower}, jmz, advanceTime
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
check({x=9500,direct=true,localAllies=true,wave=true}, 1, 0.98, 'direct finish only scored, not executed in desire')
check({x=9500,direct=true,localAllies=true,wave=true,defending=true}, 1, 0.75, 'active defense prevents direct finish shortcut')
check({x=9500,direct=true,localAllies=true,wave=true,outer=true}, 1, 0.65, 'wider defense prevents direct finish shortcut')

do
    local push,_,members,orders,lane=fixture({x=9500,direct=true,localAllies=true,wave=true})
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
do
    local opts = {x=1200, attackers=1, super=true, creepX=1500}
    local _, defend, members, _, _, _, buildings = fixture(opts)
    local anchor = members[1]
    assert(defend.GetBaseCreepResponse(anchor, buildings.ourAncient), 'approaching super creep needs one responder')
    anchor.IsChanneling = function() return true end
    assert(not defend.GetBaseCreepResponse(anchor, buildings.ourAncient), 'do not rely on a channeling responder')
    assert(defend.GetBaseCreepResponse(members[2], buildings.ourAncient), 'next available hero takes over')
    opts.movingAway = true
    assert(not defend.GetBaseCreepResponse(members[2], buildings.ourAncient), 'no recall for super creep moving away')
end
print('PASS: joint push and defense, including super creep response')

do
    local opts = {x=9500,direct=true,localAllies=true,wave=true,captureTargets=true}
    local push,_,members,orders,lane,_,buildings = fixture(opts)
    local bot = members[1]
    push.PushThink(bot, lane.Mid)
    assert(orders[1] == buildings.ancient, 'finish the exposed Ancient with the wave and available allies')
    opts.wave = false
    same(push.GetPushDesire(bot, lane.Mid), 0.12, 'drop the finish desire after the wave is cleared')
    push.PushThink(bot, lane.Mid)
    assert(orders[2] == 'cancel' and orders[3].x < bot.x, 'cancel the attack and move toward safety')
    opts.wave = true
    push.PushThink(bot, lane.Mid)
    assert(orders[4] == buildings.ancient)
    opts.visibleDefenders = 3
    push.PushThink(bot, lane.Mid)
    assert(orders[5] == 'cancel' and orders[6].x < bot.x, 'enemy reinforcements cancel the finish despite cached advantage')
    opts.visibleDefenders, opts.wave, opts.aliveEnemies, opts.enemyAncientHP = 0, false, 1, 300
    push.PushThink(bot, lane.Mid)
    assert(orders[7] == buildings.ancient, 'healthy allies can close a low-health Ancient when the defense is gone')
    opts.hp = 0.2
    same(push.GetPushDesire(bot, lane.Mid), 0.12, 'yield the finish when low on health')
    push.PushThink(bot, lane.Mid)
    assert(orders[8] == 'cancel' and orders[9].x < bot.x, 'back off for recovery instead of trading into the base')
end

do
    local opts = {x=8300,direct=true,localAllies=true,wave=true,objectives=true,captureTargets=true}
    local push,_,members,orders,lane,_,buildings = fixture(opts)
    push.PushThink(members[1],lane.Mid)
    assert(orders[1] == buildings.melee, 'the passive backdoor modifier alone does not block a supported attack')
    opts.meleeProtected = true
    push.PushThink(members[1],lane.Mid)
    assert(orders[2] == buildings.ranged, 'protection cancels the objective lock before it expires')
    opts.defendersAtAncient = 3
    push.PushThink(members[1],lane.Mid)
    assert(orders[3] == 'cancel' and orders[4].x < members[1].x, 'defenders visible at the Ancient stop an approach early')
    opts.defendersAtAncient = 0
    push.PushThink(members[1],lane.Mid)
    assert(orders[5] == buildings.ranged)
    opts.rangedDestroyed = true
    push.PushThink(members[1],lane.Mid)
    assert(orders[6] == 'cancel' and orders[7].x ~= nil, 'the destroyed last objective should fall back to a hold position')
end

do
    local push,_,members,_,lane=fixture({rotate=true})
    assert(push.WhichLaneToPush(members[1],lane.Mid) == lane.Top, 'rotate away from a cleared lane when barracks remain elsewhere')
end
print('PASS: high-ground cover, live aborts, protected targets and rotation off cleared lanes')

do
    local opts = {postFight=true, fightWaves={[1]=3900,[2]=5880}, allyCount=5, enemyAliveAtStart=3,
        attackers=1, captureTargets=true}
    local push, defend, members, orders, lane, _, buildings, jmz = fixture(opts)
    jmz.IsValidBuilding = function(unit) return unit == buildings.fightTower and not opts.fog end
    opts.fog = true
    same(defend.GetDefendDesire(members[1], lane.Mid), 0.97, 'keep a defender for the exposed Ancient')
    same(push.GetPushDesire(members[1], lane.Mid), 0, 'the assigned defender stays')
    for i=2,5 do
        same(push.GetPushDesire(members[i], lane.Top), 0.12, 'the more distant side lane waits')
        same(push.GetPushDesire(members[i], lane.Mid), 0.88, 'five versus three rally on the wave to the known mid tower')
    end
    push.PushThink(members[2], lane.Mid)
    assert(orders[1].lane == lane.Mid and orders[1].x < 5970, 'advance behind the live wave even while the tower is outside vision')
    opts.fog, opts.postFightProtected, opts.fightWaves[lane.Mid] = false, true, 6910
    push.PushThink(members[3], lane.Mid)
    assert(orders[2] ~= buildings.fightTower, 'wait for actual backdoor protection to drop')
    opts.postFightProtected = false
    members[2].x = 6540
    push.PushThink(members[2], lane.Mid)
    assert(orders[3] == buildings.fightTower, 'execute the attack after the lane wave reaches the tower')
    opts.postFightEnemyAlive = 4
    push.PushThink(members[2], lane.Mid)
    assert(orders[4] == 'cancel', 'an enemy returning cancels the expired push order')
end

do
    local opts = {postFight=true, direct=true, postFightHighGround=true, fightWaves={[2]=6910},
        x=5100, captureTargets=true, localAllies=true}
    local push, _, members, orders, lane, _, buildings, jmz = fixture(opts)
    jmz.HasSiegeDamageInRange = function() return opts.siegeArrived == true end
    same(push.GetPushDesire(members[1], lane.Mid), 0.88, 'rally below high ground while the tower is reachable')
    push.PushThink(members[1], lane.Mid)
    assert(orders[1].lane == lane.Mid and orders[1].x < 6910, 'wait behind the wave while damage is unavailable')
    members[1].x = 6450
    same(push.GetPushDesire(members[1], lane.Mid), 0.76, 'retain the safe rally while the distant damage catches up')
    opts.uphillStaging = true
    same(push.GetPushDesire(members[1], lane.Mid), 0.12, 'give up the rally if reaching it requires going uphill without damage')
    opts.uphillStaging = false
    opts.siegeArrived = true
    push.PushThink(members[1], lane.Mid)
    assert(orders[2] == buildings.fightTower, 'attack when the main siege damage arrives')
    opts.heroPanic = true
    push.PushThink(members[1], lane.Mid)
    assert(orders[3] == 'cancel', 'new pressure on our Ancient interrupts the push')
end

do
    local opts = {postFight=true, fightWaves={[2]=5880}, allyCount=5, enemyAliveAtStart=3, reinforcementWindow=8}
    local push, _, members, _, lane = fixture(opts)
    members[5].x = -1000
    same(push.GetPushDesire(members[2], lane.Mid), 0.88, 'nearby available heroes can escort the wave before reinforcements')
    assert(push.GetPushDesire(members[5], lane.Mid) ~= 0.88 and members[5].ohaPostFightPushLane == nil,
        'a distant ally keeps local work if they cannot get to the wave in time')
    opts.reinforcementWindow = 2
    local expired, _, nearby, _, expiredLane = fixture(opts)
    assert(expired.GetPushDesire(nearby[2], expiredLane.Mid) ~= 0.88, 'skip a rally that exceeds the remaining enemy downtime')
end
do
    local opts = {postFight=true, fightWaves={[2]=6830}, allyCount=5, enemyAliveAtStart=3,
        reinforcementWindow=5, x=6450, fightCreepOffsets={0,-1500,-1570}}
    local push, _, members, _, lane = fixture(opts)
    assert(push.GetPushDesire(members[1], lane.Mid) ~= 0.88,
        'only the lead creep reaches the tower before respawn')
    opts.fightCreepOffsets = {0,-150,-250}
    same(push.GetPushDesire(members[1], lane.Mid), 0.88, 'send the team when two creeps reach attack cover')
    for i=2,5 do members[i].IsDisarmed = function() return true end end
    assert(push.GetPushDesire(members[1], lane.Mid) ~= 0.88, 'disarmed bodies do not form an attack pair')
    members[2].IsDisarmed = function() return false end
    members[2].x = 6250
    members[2].IsRooted = function() return true end
    assert(push.GetPushDesire(members[1], lane.Mid) ~= 0.88, 'rooted ally cannot travel into attack range')
    members[2].x = 6550
    same(push.GetPushDesire(members[1], lane.Mid), 0.88, 'rooted ally already in attack range can contribute')
end
print('PASS: coordinated post-fight lane, second creep ETA, attack-ready allies and base defense')

do
    local opts = {farmBot = 1, attackers = 1, visible = false}
    local _, defend, members, orders, lane, farm = fixture(opts)
    assert(farm.GetDesire() > 0, 'farm is available in a quiet lane with a ready Midas')
    farm.Think()
    assert(orders[1] == 'attack', 'farm can issue a normal lane attack')
    farm.SetThreatVisible(true)
    farm.Think()
    assert(#orders == 2 and orders[2] == 'cancel', 'a new base defense assignment cancels a stale farm order')
    same(farm.GetDesire(), 0, 'assigned creep responder yields even with Midas ready')
    same(defend.GetDefendDesire(members[1], lane.Mid), 0.97, 'assigned farmer has an active defense mode')
    farm.SetThreatVisible(false)
    farm.AdvanceTime(4)
    assert(farm.GetDesire() > 0, 'farming becomes available after the defense window ends')
    opts.baseEnemyId = 9
    same(farm.GetDesire(), 0, 'last-seen enemy support at the Ancient also blocks farming')
end

do
    local _, _, _, _, _, farm = fixture({farmBot = 4, attackers = 1})
    assert(farm.GetDesire() > 0, 'a single creep does not pull unassigned farmers off the map')
end

do
    local _, _, _, _, _, farm = fixture({farmBot = 1, defending = true})
    same(farm.GetDesire(), 0, 'high-priority active defense outranks a ready Midas')
end
print('PASS: farm yields to an assigned or high-priority defense and resumes after the threat')

do
    local opts = {farmBot = 1, route = true, time = 1200}
    local _, _, _, orders, lane, farm = fixture(opts)
    assert(farm.GetDesire() > 0)
    farm.Think()
    assert(orders[1] == farm.camps[1].cattr.location, 'fill downtime with a known camp instead of going to a lane with no wave')
    opts.dangerInLanes = true
    farm.Think()
    assert(orders[2] == farm.camps[1].cattr.location, 'switch to a camp when a visible enemy threatens the lane')
    opts.occupied = true
    farm.Think()
    assert(orders[3] == farm.camps[2].cattr.location, 'leave a camp that an ally is attacking and do not attack its neutrals')
    opts.dangerAtFarCamp = true
    farm.Think()
    assert(#orders == 4 and orders[4] == 'cancel', 'cancel the last farm order when every destination is blocked')
    opts.dangerInLanes, opts.farmWave = false, true
    assert(farm.GetDesire() > 0)
    farm.Think()
    assert(orders[5] == 'attack', 'take a safe wave once its creeps arrive')
end
print('PASS: farm follows safe lane routes and replans around enemy threats and occupied camps')

do
    local opts = {farmBot = 1, route = true, time = 35 * 60, farmNetWorth = 9800}
    local _, _, members, orders, _, farm, _, jmz = fixture(opts)
    jmz.IsTeamActivityCount = function() return true end
    same(farm.GetDesire(), 0.55, 'a remote team group does not block a nearby late-game camp')
    farm.Think()
    assert(orders[1] == farm.camps[1].cattr.location)
    members[1].ohaOuterTowerHoldUntil = opts.time + 2
    same(farm.GetDesire(), 0, 'an assigned defender yields its camp immediately')
    farm.Think()
    assert(orders[2] == 'cancel', 'cancel a farm move when a tower assignment becomes active')
end

do
    local opts = {farmBot = 1, route = true, time = 600, laning = true, direct = true,
        farmLevel = 5, farmNetWorth = 2100, laneTower = true}
    local _, _, _, orders, lane, farm = fixture(opts)
    same(farm.GetDesire(), 0, 'safe assigned lane still uses laning')
    opts.laneThreat = true
    same(farm.GetDesire(), 0.5, 'an outnumbered carry can farm before the tower falls')
    farm.Think()
    assert(orders[1] == farm.camps[1].cattr.location, 'avoid last-seen threats at a farming destination')
    opts.laneThreat, opts.laneTower = false, false
    same(farm.GetDesire(), 0.5, 'the carry can recover while the match is still in the laning phase')
    farm.Think()
    assert(orders[2] == farm.camps[1].cattr.location, 'skip a visible lane front with no actual wave')
    opts.tradeWaves = {lane.Top}
    farm.AdvanceTime(1.2)
    assert(farm.GetDesire() > 0)
    farm.Think()
    assert(orders[3] == farm.lanes[lane.Top], 'collect a real, safe lane wave ahead of the camp')
    opts.defending = true
    same(farm.GetDesire(), 0, 'urgent defense still overrides early recovery')
end
do
    local opts = {farmBot = 1, route = true, time = 330, laning = true, direct = true,
        farmLevel = 4, farmNetWorth = 1500, laneTower = true, farmAssignedLane = 3, tradeWaves = {3}}
    local _, _, members, orders, lane, farm = fixture(opts)
    local bot = members[1]
    bot.GetLocation = function(self) return {x = self.x, y = 1100} end
    same(farm.GetDesire(), 0.71, 'a recovered, displaced carry prioritizes its visible safe tower wave')
    farm.Think()
    assert(orders[1] == farm.lanes[lane.Bot], 'catch the assigned wave rather than the nearby neutral camp')
    opts.laneThreat = true
    assert(farm.GetDesire() ~= 0.71, 'an unsafe assigned wave must not be reclaimed')
end
print('PASS: an underfarmed carry can recover from a lost lane during laning')

do
    local opts = {farmBot=1,route=true,time=240,laning=true,direct=true,farmLevel=4,farmNetWorth=1800}
    local _, _, members, _, _, farm, _, jmz = fixture(opts)
    local creep = {IsHero=function() return false end}
    members[1].WasRecentlyDamagedByCreep = function() return true end
    jmz.GetHP = function(unit) return unit == members[1] and 0.60 or 0.70 end
    jmz.GetProperTarget = function() return creep end
    assert(farm.GetDesire() < 1, 'creep damage while the laner is last-hitting does not force a retreat')
    local hero = {IsHero=function() return true end,GetTeam=function() return 3 end}
    jmz.GetProperTarget = function() return hero end
    same(farm.GetDesire(),1.1,'still retreat from creep aggro when pursuing a healthy enemy hero')
end

do
    local opts = {farmBot = 1, route = true, time = 515, laning = true, direct = true, hp = 0.5,
        carryHarass = true, farmLevel = 4, farmNetWorth = 1500, laneTower = true, laneThreat = true}
    local _, _, members, orders, lane, farm = fixture(opts)
    opts.farmAssignedLane = lane.Bot
    same(farm.GetDesire(), 0.67, 'surviving a two-hero lane forces a shorter safe recovery route')
    opts.hp, opts.carryHarass, opts.laneThreat = 1, false, false
    opts.tradeWaves = {lane.Top}
    farm.AdvanceTime(20)
    same(farm.GetDesire(), 0.67, 'healing does not erase the recent forced reset')
    farm.Think()
    assert(orders[1] == farm.lanes[lane.Top], 'an open wave can replace the contested lane')
    assert(members[1].ohaCarryLaneRecoveryUntil > opts.time)
    farm.AdvanceTime(35)
    same(farm.GetDesire(), 0, 'a past bad trade no longer keeps the carry off a clear lane')
end

do
    local opts = {farmBot = 1, route = true, time = 300, laning = true, direct = true,
        farmLevel = 3, farmNetWorth = 1250, laneTower = true}
    local _, _, _, orders, _, farm = fixture(opts)
    same(farm.GetDesire(), 0, 'a safe five-minute lane should still take priority')
    opts.laneThreat = true
    same(farm.GetDesire(), 0.5, 'a level-three carry may recover when two enemies deny access to the lane')
    farm.Think()
    assert(orders[1] == farm.camps[1].cattr.location, 'the early recovery route avoids the contested lane')
end

do
    local opts = {time=12 * 60,x=5500,direct=true,outerSiege=true,localAllies=true,wave=true,safeSiege=true}
    opts.captureTargets = true
    local push, _, members, orders, lane, _, buildings = fixture(opts)
    members[4].GetLevel = function() return 5 end
    same(push.GetPushDesire(members[1], lane.Mid), 0.8, 'a supported wave converts a numbers advantage into outer-tower pressure')
    push.PushThink(members[1], lane.Mid)
    assert(orders[1] == buildings.outerTower, 'attack the tower selected by the post-fight decision')
    opts.wave = false
    same(push.GetPushDesire(members[1], lane.Mid), 0, 'do not bypass ordinary push limits without a wave')
    push.PushThink(members[1], lane.Mid)
    assert(orders[2] == 'cancel' and not members[1].ohaOuterTowerPush, 'cancel the existing tower order when the wave dies')
    opts.wave, opts.visibleDefenders = true, 1
    same(push.GetPushDesire(members[1], lane.Mid), 0, 'do not commit the tower window into a visible defender')
    opts.visibleDefenders, opts.safeSiege = 0, false
    same(push.GetPushDesire(members[1], lane.Mid), 0, 'do not commit into recently seen defenders')
end

do
    local opts = {time=6 * 60, x=5500, direct=true, outerSiege=true, localAllies=true,
        wave=true, safeSiege=true, captureTargets=true, enemyAliveAtStart=4}
    local push, _, members, orders, lane, _, buildings = fixture(opts)
    local bot, tower = members[1], buildings.outerTower
    local tank = {IsCreep=function() return true end, GetTeam=function() return 2 end}
    members[4].GetLevel = function() return 5 end
    opts.towerTarget = tank
    same(push.GetPushDesire(bot, lane.Mid), 0.8, 'take a covered outer tower opening with all opponents alive')
    push.PushThink(bot, lane.Mid)
    assert(orders[1] == tower, 'use the opening to attack the tower')
    opts.towerTarget = bot
    push.PushThink(bot, lane.Mid)
    assert(orders[2] == 'cancel' and orders[3].x < bot.x and not bot.ohaOuterTowerPush,
        'drop the order and step out when the tower changes targets')
    opts.towerTarget, opts.backupLost = tank, true
    same(push.GetPushDesire(bot, lane.Mid), 0.8, 'a healthy ranged hero can still hit while the wave tanks after its ally leaves')
    opts.towerTarget = nil
    same(push.GetPushDesire(bot, lane.Mid), 0, 'yield when neither the allied tank nor a wave attacking the tower is confirmed')
end

do
    local opts = {time=360, x=5500, direct=true, outerSiege=true, localAllies=true,
        wave=true, safeSiege=true, captureTargets=true}
    local push, _, members, orders, lane, _, buildings, jmz = fixture(opts)
    local bot, tower = members[1], buildings.outerTower
    local hp = 300
    local tank = {x=tower.x, GetTeam=function() return 2 end, GetHealth=function() return hp end}
    local tank2 = {x=tower.x+50}
    tower.CanBeSeen = function() return true end
    tower.GetAttackDamage = function() return 105 end
    bot.GetAttackRange = function() return 650 end
    bot.GetNearbyLaneCreeps = function() return {tank, tank2} end
    jmz.IsKeyWordUnit = function(key, unit) return key == 'npc_dota_creep_' and unit == tank end
    opts.towerTarget = tank
    same(push.GetPushDesire(bot, lane.Mid), 0.8, 'ranged mid can take one covered early shot')
    assert(bot.ohaOuterTowerPush and bot.ohaOuterTowerPush.earlyMidChip)
    push.PushThink(bot, lane.Mid)
    assert(orders[#orders] == tower)
    hp = 40
    push.PushThink(bot, lane.Mid)
    assert(not bot.ohaOuterTowerPush and orders[#orders] == 'cancel', 'cancel the actual attack when creep cover is about to die')
end

do
    local opts = {time=20 * 60,x=3600,direct=true,outerSiege=true,localAllies=true,safeSiege=true,stagedWave=true,captureTargets=true}
    local push, _, members, orders, lane, _, buildings = fixture(opts)
    local bot = members[1]
    same(push.GetPushDesire(bot, lane.Mid), 0.76, 'advance with backup towards a supported wave outside attack range')
    push.PushThink(bot, lane.Mid)
    same(orders[1].x, buildings.outerTower.x - 950, 'stage behind the wave instead of walking straight under the tower')
    opts.unsafeLanding = true
    push.PushThink(bot, lane.Mid)
    assert(orders[2] == 'cancel', 'newly visible defenders or arrivals cancel the advance')
end

do
    local opts = {farmBot = 1, farmPosition = 5, time = 600, route = true, laning = true, supportWave = true}
    local _, _, members, orders, _, farm = fixture(opts)
    same(farm.GetDesire(), 0.49, 'support can collect an unclaimed safe wave')
    opts.waveOwner = true
    same(farm.GetDesire(), 0, 'yield the wave to a nearby core')
    members[2].IsChanneling = function() return true end
    same(farm.GetDesire(), 0.49, 'a channeling core cannot reserve the wave')
    members[2].IsChanneling = function() return false end
    members[2].ohaOuterTowerHoldUntil = 610
    same(farm.GetDesire(), 0.49, 'a core assigned to defend elsewhere cannot reserve a support wave')
    farm.Think()
    assert(orders[1] == 'attack', 'the support follows through and attacks the released wave')
    members[2].ohaOuterTowerHoldUntil = nil
    farm.Think()
    assert(orders[2] == 'cancel' and not members[1].ohaWaveClaim, 'give the wave back when the carry is available again')
    opts.waveOwner, opts.laneThreat = false, true
    same(farm.GetDesire(), 0, 'do not collect a wave into recent enemies')
    opts.laneThreat = false
    same(farm.GetDesire(), 0.49, 'reserve a new safe wave once the danger is gone')
    farm.Think()
    assert(members[1].ohaWaveClaim and orders[3] == 'attack', 'a live wave remains claimable')
    opts.supportWave = false
    farm.Think()
    assert(orders[4] == 'cancel' and not members[1].ohaWaveClaim, 'a vanished wave releases its claim at the destination')
    opts.farmPosition = 3
    members[1].ohaIdleRecoveryUntil = 605
    same(farm.GetDesire(), 0.65, 'idle core can rejoin safe income')
end

do
    local opts = {farmBot=1, farmPosition=5, time=900, route=true, laning=true, distantWave=true}
    local _, _, members, orders, _, farm = fixture(opts)
    local bot = members[1]
    bot.ohaIdleRecoveryUntil = 914
    same(farm.GetDesire(), 0.72, 'a stalled support can reach a visible unclaimed wave beyond the local creep scan')
    farm.Think()
    assert(orders[1].x == bot.x + 1840 and bot.ohaWaveClaim.location == orders[1])
    opts.laneThreat = true
    farm.Think()
    assert(#orders == 2 and orders[2] == 'cancel' and not bot.ohaWaveClaim, 'cancel the route and release the claim when enemies appear')
end

do
    local opts = {farmBot = 1, farmPosition = 2, route = true, time = 617,
        laning = true, direct = true, farmLevel = 7, farmNetWorth = 2800, waveClaimed = true}
    local _, _, members, orders, lane, farm = fixture(opts)
    opts.tradeWaves = {lane.Top, lane.Mid}
    farm.lanes[lane.Top].x = members[1].x + 450
    same(farm.GetDesire(), 0.5, 'a mid core can recover before the global laning phase ends')
    farm.Think()
    assert(orders[1] == farm.lanes[lane.Mid], 'recover on an open wave instead of contesting the carry')
    same(opts.campRefreshes, 1, 'initialize camps even when the first eligible tick is late in the minute')
    opts.dangerInLanes = true
    same(farm.GetDesire(), 0.5, 'fall back to a safe camp when there is no safe wave')
    farm.Think()
    assert(orders[2] == farm.camps[1].cattr.location and opts.campRefreshes == 1)
end

do
    local opts = {farmBot = 1, route = true, time = 15 * 60, farmLevel = 7,
        farmNetWorth = 2300, dangerInLanes = true}
    local _, _, _, orders, _, farm = fixture(opts)
    same(farm.GetDesire(), 0.5, 'a level-seven carry may take a safe camp after laning ends')
    farm.Think()
    assert(orders[1] == farm.camps[1].cattr.location)
end

do
    local opts = {direct = true, outerSiege = true, captureTargets = true, x = 4700}
    local _, defend, members, orders, lane, _, buildings, jmz = fixture(opts)
    local tower = buildings.outerTower
    local threat = jmz.GetOuterTowerThreat(tower, lane.Mid)
    local delay, assigned = jmz.GetOuterTowerResponse(tower:GetLocation(), threat)
    assert(delay and assigned[3].reach == 1020 and assigned[4].cover, 'assign the clearer and protect it against a dive')
    same(defend.GetDefendDesire(members[3], lane.Mid), 0.7, 'the assigned bot delays at the tower')
    same(defend.GetDefendDesire(members[1], lane.Mid), 0.12, 'the other core is free to play another lane')
    assert(members[1].ohaOuterTowerTrade.lane == lane.Mid and members[3].ohaOuterTowerHoldUntil > 1800)
    defend.DefendThink(members[3], lane.Mid)
    same(orders[1].x, tower.x - 600, 'a long-range spell can clear from deeper behind the tower')
    members[3].IsChanneling = function() return true end
    defend.DefendThink(members[3], lane.Mid)
    same(#orders, 1, 'normal repositioning must not overwrite a committed spell')
    opts.holdDanger = true
    defend.DefendThink(members[3], lane.Mid)
    same(orders[2].x, tower.x - 1000, 'retreat if the current hold point is compromised')
    opts.holdDanger = false
    opts.spellCooldown = 15
    same(defend.GetDefendDesire(members[3], lane.Mid), 0.12, 'yield if nobody can clear the wave soon')
    opts.localAdvantage = true
    delay = jmz.GetOuterTowerResponse(tower:GetLocation(), threat)
    assert(not delay, 'an evenly staffed favorable fight remains available')
    opts.criticalCooldown = true
    delay = jmz.GetOuterTowerResponse(tower:GetLocation(), threat)
    assert(delay, 'numerical parity alone cannot force a fight with key cooldowns missing')
end

do
    local opts = {direct = true, outerSiege = true, captureTargets = true, x = 4800, approach = true}
    local _, defend, members, orders, lane, _, buildings, jmz = fixture(opts)
    local threat = jmz.GetOuterTowerThreat(buildings.outerTower, lane.Mid)
    assert(threat.near == 0 and threat.count == 2 and threat.eta > 3, 'notice visible heroes escorting a wave before they arrive')
    same(defend.GetDefendDesire(members[3], lane.Mid), 0.7, 'pre-position before the wave reaches the tower')
    members[3].x, opts.safeTP = 2800, true
    same(defend.GetDefendDesire(members[3], lane.Mid), 0.84, 'a distant clearer can reposition to an uncontested tower')
    same(members[3]._defend.waveClearTeleport.x, buildings.outerTower.x - 475, 'choose the tower side facing the base')
    opts.unsafeLanding = true
    same(defend.GetDefendDesire(members[3], lane.Mid), 0.12, 'do not teleport the only clearer into danger')
    opts.unsafeLanding, members[3].x = false, 5200
    same(defend.GetDefendDesire(members[3], lane.Mid), 0.7, 'resume the safe hold')
    opts.movingAway = true
    assert(jmz.GetOuterTowerThreat(buildings.outerTower, lane.Mid).score == 0, 'ignore distant heroes facing away')
    opts.movingAway, opts.rotatePressure = false, true
    defend.DefendThink(members[3], lane.Mid)
    same(#orders, 0, 'cancel the old hold when a higher-pressure lane appears')
end

do
    local opts = {direct = true, outerSiege = true, captureTargets = true, x = 4500, towerCreeps = 4,
        waveAttacking = true, spellRange = 1050, spellDamage = 100}
    local _, defend, members, orders, lane, _, buildings, jmz = fixture(opts)
    local tower = buildings.outerTower
    local threat = jmz.GetOuterTowerThreat(tower, lane.Mid)
    local _, assigned = jmz.GetOuterTowerResponse(tower:GetLocation(), threat, nil, false)
    assert(assigned[3] and not assigned[3].cover and assigned[4] and assigned[4].cover, 'use the safe long-range clearer and a separate nearby escort against a group')
    same(defend.GetDefendDesire(members[3], lane.Mid), 0.7, 'stay in reach to delay the tower siege')
    defend.DefendThink(members[3], lane.Mid)
    assert(orders[1].x == tower.x - 800, 'use the long spell range to hold further behind the tower')
    opts.unsafeLanding = true
    _, assigned = jmz.GetOuterTowerResponse(tower:GetLocation(), threat, nil, false)
    assert(not assigned[3], 'partial damage does not justify holding a threatened position')
end

do
    local defenders = {contest = {}, direct = true, outerSiege = true, captureTargets = true, safeSiege = true,
        towerCreeps = 4, waveAttacking = true, time = 14 * 60}
    local _, defend, members, orders, lane, _, buildings, jmz = fixture(defenders)
    local tower, bot = buildings.outerTower, members[3]
    for i = 1, 3 do
        defenders.contest[i] = {x = 6800 + i * 30, IsHero = function() return true end, IsFacingLocation = function() return true end,
            GetPlayerID = function() return i + 5 end, GetLocation = function(self) return {x = self.x} end,
            GetAttackTarget = function() return tower end, GetLevel = function() return 20 end,
            GetSecondsPerAttack = function() return 1 end, GetAttackDamage = function(self) return self.damage or 100 end,
            IsDisarmed = function() return false end}
    end
    members[1].x, members[2].x, bot.x, members[4].x = 2200, 2500, 5000, 5500
    members[1].scroll, members[2].scroll = true, true
    local threat = jmz.GetOuterTowerThreat(tower, lane.Mid)
    local _, plans = jmz.GetOuterTowerResponse(tower:GetLocation(), threat, nil, false)
    assert(plans[1].teleport.x == 5425 and plans[2].teleport.x == 5425 and plans[3].gather and plans[4].gather,
        'call healthy allies that can safely walk or teleport before the tower falls')
    defenders.unsafeLanding = true
    local _, unsafe = jmz.GetOuterTowerResponse(tower:GetLocation(), threat, nil, false)
    assert(not unsafe[3] or not unsafe[3].gather, 'disallow the fight when the required teleports are unsafe')
    defenders.unsafeLanding = false
    same(defend.GetDefendDesire(bot, lane.Mid), 0.89, 'a credible siege gets a coordinated response')
    defend.DefendThink(bot, lane.Mid)
    assert(orders[1].x == 5425, 'walk to the rear of the tower instead of charging the wave alone')
    bot.x = 5660
    for i, foe in ipairs(defenders.contest) do foe.x = 6280 + i * 15 end
    members[1].HasModifier = function(_, name) return name == 'modifier_teleporting' end
    defenders.incoming = {{playerid = 1, location = plans[1].teleport, time_remaining = 2}}
    defend.DefendThink(bot, lane.Mid)
    assert(orders[2].x == 5400 and not jmz.GetTowerDefenseTarget(bot), 'a teleport in progress never counts as an arrived fighter')
    members[1].x, members[2].x, members[1].HasModifier = 5450, 5500, function() return false end
    defenders.incoming = nil
    members[4].x = 5500
    defend.DefendThink(bot, lane.Mid)
    assert(orders[3].x == 5400 and not jmz.GetTowerDefenseTarget(bot),
        'even an assembled team holds when only one defender can hit the target')
    members[2].x = 5600
    defend.DefendThink(bot, lane.Mid)
    assert(orders[4] == defenders.contest[1] and jmz.GetTowerDefenseTarget(bot) == orders[4],
        'concentrate attacks once support reaches the same target')
    for i, foe in ipairs(defenders.contest) do foe.x, foe.damage = 5430 + i * 15, 320 end
    members[1].hp, members[2].hp = 0.3, 0.3
    defend.DefendThink(bot, lane.Mid)
    assert(orders[5].x == 4800 and not jmz.GetTowerDefenseTarget(bot), 'retreat when the attackers reach the hold point and local strength drops')
    local delay, weaker = jmz.GetOuterTowerResponse(tower:GetLocation(), jmz.GetOuterTowerThreat(tower, lane.Mid), nil, false)
    assert(delay and (not weaker[3] or not weaker[3].gather), 'a lost fight falls back to clearers and releases other heroes')
    local dying = jmz.GetOuterTowerThreat(tower, lane.Mid)
    dying.damageRate, dying.underAttack = tower:GetHealth(), true
    local _, doomed = jmz.GetOuterTowerResponse(tower:GetLocation(), dying, nil, false)
    assert(next(doomed) == nil, 'do not call a clearer to a front tower whose remaining life is under 2.5 seconds')
end

do
    local opts = {direct = true, outerSiege = true, singleAttacker = true, waveAttacking = true,
        towerCreeps = 4, captureTargets = true, x = 4800, spellCooldown = 30}
    local _, defend, members, orders, lane, _, buildings, jmz = fixture(opts)
    local tower = buildings.outerTower
    local threat = jmz.GetOuterTowerThreat(tower, lane.Mid)
    assert(threat.score > 0 and threat.count == 1 and threat.eta == 0, 'one hero and a wave attacking the tower matter')
    same(defend.GetDefendDesire(members[4], lane.Mid), 0.7, 'assign a nearby hero even with no ready wave-clear spell')
    same(defend.GetDefendDesire(members[1], lane.Mid), 0.12, 'do not pull the whole team for one hero')
    opts.safeSiege = true
    assert(jmz.GetOuterTowerThreat(tower, lane.Mid).score > 0, 'the wave still threatens after the escort leaves')
    opts.waveAttacking = false
    assert(jmz.GetOuterTowerThreat(tower, lane.Mid).score == 0, 'a normal unattended approaching wave is not an emergency')
end

do
    local opts = {direct=true, outerSiege=true, approach=true, movingAway=true, bigWave=true, safeTP=true, x=-7000}
    local _, defend, members, _, lane, _, buildings, jmz = fixture(opts)
    local tower = buildings.outerTower
    jmz.GetAlliesNearLoc = function(point, range)
        local result = {}
        for _, ally in ipairs(members) do
            if math.abs(ally.x - point.x) <= range then result[#result+1] = ally end
        end
        return result
    end
    local threat = jmz.GetOuterTowerThreat(tower, lane.Mid)
    assert(threat.count == 0 and threat.siege and threat.score > 0 and threat.eta > 0)
    same(defend.GetDefendDesire(members[3], lane.Mid), 0.84, 'a remote clearer gets a safe TP before an unescorted catapult arrives')
    assert(members[3]._defend.waveClearTeleport.x == tower.x - 475)
end

do
    local opts = {direct=true, outerSiege=true, twoClearers=true, safeSiege=true, x=3650}
    local _, _, members, _, _, _, buildings, jmz = fixture(opts)
    local fallback = {x=3500,y=0}
    local threat = {count=5, near=5, eta=0, towerHP=0.1, waveHP=400, waveSize=5, siege=true}
    local _, assignments = jmz.GetOuterTowerResponse(buildings.outerTower:GetLocation(), threat, fallback)
    assert(assignments[2].rally == fallback and assignments[3].rally == fallback and not assignments[1] and not assignments[4],
        'stage two clearers at the next safe tower when the front tower will fall')
    members[3].HasModifier = function(_, name) return name == 'modifier_teleporting' end
    _, assignments = jmz.GetOuterTowerResponse(buildings.outerTower:GetLocation(), threat, fallback)
    assert(not assignments[3], 'a defender already teleporting elsewhere cannot be reassigned in flight')
end

do
    local opts = {direct=true, outerSiege=true, safeTP=true, x=-7000}
    local _, _, members, _, lane, _, buildings, j = fixture(opts)
    local threat = {lane=lane.Mid, count=2, near=2, eta=6, towerHP=0.8, waveHP=170, waveSize=4, siege=true}
    local location = buildings.outerTower:GetLocation()
    local _, orders = j.GetOuterTowerResponse(location, threat, nil, false)
    local clearer = members[3]:GetPlayerID()
    assert(orders[clearer] and orders[clearer].teleport.x == location.x - 475,
        'an approaching wave with two enemies still permits a safe preemptive teleport behind this tower')
    j.GetEnemiesNearLoc = function() return {{}} end
    _, orders = j.GetOuterTowerResponse(location, threat, nil, false)
    assert(not orders[clearer], 'cancel the teleport when the destination is threatened')
end

do
    local opts = {direct=true, outerSiege=true, twoClearers=true, rearTower=true, x=3650, bigWave=true, captureTargets=true}
    local _, defend, members, orders, lane, _, buildings, jmz = fixture(opts)
    buildings.outerTower.GetHealth = function() return 90 end
    local bot = members[3]
    same(defend.GetDefendDesire(bot, lane.Mid), 0.84, 'stage an assigned clearer at the next tower')
    local spellAnchor = jmz.GetAssignedOuterTower(bot)
    assert(spellAnchor and spellAnchor.x == 3500, 'the hero spell can target the actual rear-tower wave')
    defend.DefendThink(bot, lane.Mid)
    assert(orders[1].x == 3500-600, 'the walking point uses a single offset from the defended tower')
    buildings.outerTower.IsAlive = function() return false end
    opts.safeSiege, opts.bigWave = true, false
    same(defend.GetDefendDesire(bot, lane.Mid), 0.84, 'keep the rear tower covered while the attack marches from the destroyed T1')
    defend.DefendThink(bot, lane.Mid)
    assert(orders[#orders].x == 3500-600, 'use the rear tower through the gap between sightings')
end

do
    local _, _, members, _, lane, _, _, j = fixture({outerSiege=true, direct=true})
    local bot = members[1]
    j.IsInLaningPhase = function() return true end
    bot.GetNearbyLaneCreeps = function() return {{GetLocation=function() return {x=bot.x, lane=lane.Mid} end}} end
    local watch = {count=0, towerHP=0.9}
    assert(j.ShouldKeepLaningWave(bot, lane.Top, watch), 'a healthy mid keeps a free wave instead of teleporting for routine coverage')
    assert(j.ShouldKeepLaningWave(bot), 'a reachable free wave can postpone a trip for items')
    watch.count, watch.near, watch.waveSize = 2, 2, 0
    assert(j.ShouldKeepLaningWave(bot, lane.Top, watch), 'two heroes walking near a healthy side tower do not cost the middle wave')
    watch.heroAttacking, watch.waveSize = true, 3
    assert(not j.ShouldKeepLaningWave(bot, lane.Top, watch), 'a real escorted wave at the tower justifies rotating')
    watch.heroAttacking, watch.count, watch.waveSize = false, 0, 0
    watch.siegeAttacking = true
    assert(not j.ShouldKeepLaningWave(bot, lane.Top, watch), 'an attacking catapult can justify rotating')
    watch.siegeAttacking, watch.count = false, 3
    assert(not j.ShouldKeepLaningWave(bot, lane.Top, watch), 'a confirmed group push can still call the mid')
end

do
    local opts = {direct=true,outerSiege=true,twoClearers=true,twoAttackers=true,rearTower=true, x=3650,
        bigWave=true, waveAttacking=true,towerCreeps=2}
    local _, _, _, _, lane, _, buildings, jmz = fixture(opts)
    local watch = {lane=lane.Mid,count=2,near=2,towerHP=0.08,waveSize=4,waveHP=200,
        eta=0,siege=true,siegeAttacking=true,heroAttacking=true}
    local fallback = {x=3500,y=0}
    local _, orders = jmz.GetOuterTowerResponse(buildings.outerTower:GetLocation(),watch,fallback,false)
    local assignedToRear = false
    for _, order in pairs(orders) do
        if order.rally == fallback then assignedToRear = true end
    end
    assert(assignedToRear, 'two pushers with siege still require a clearer at the next tower')
end

do
    local opts = {direct=true, outerSiege=true, x=5200, singleAttacker=true, waveAttacking=true, towerCreeps=3}
    local _, _, _, _, lane, _, buildings, jmz, advanceTime = fixture(opts)
    local tower = buildings.outerTower
    jmz.GetOuterTowerThreat(tower, lane.Mid)
    tower.GetHealth = function() return 710 end
    jmz.GetOuterTowerThreat(tower, lane.Mid)
    opts.safeSiege, opts.waveAttacking = true, false
    local threat = jmz.GetOuterTowerThreat(tower, lane.Mid)
    assert(threat.briefHold and threat.score > 0, 'keep an observed tower hit across a gap between waves')
    local _, assignments = jmz.GetOuterTowerResponse(tower:GetLocation(), threat)
    local held = 0
    for _, assignment in pairs(assignments) do
        held = held + 1
        assert(not assignment.teleport)
    end
    assert(held == 1, 'reserve just one local clearer during a brief lull')
    advanceTime(11)
    assert(jmz.GetOuterTowerThreat(tower, lane.Mid).score == 0, 'release the lane when the attackers stay away')
end

do
    local opts = {direct=true, x=1200, attackers=4, creepX=1300, mega=true, heroPanic=true}
    local _, defend, members, _, lane = fixture(opts)
    same(defend.GetDefendDesire(members[1], lane.Mid), 0.97, 'reserve a defender for approaching megas with enemy heroes present')
    assert(members[1]._ohaCreepDefenseUntil > 1800)
end

do
    local opts = {direct = true, outerSiege = true, singleAttacker = true, x = 2500, safeTP = true}
    local _, _, members, _, lane, _, buildings, jmz = fixture(opts)
    local tower = buildings.outerTower
    local scout = {x=tower.x + 850, GetPlayerID=function() return 5 end,
        GetLocation=function(self) return {x=self.x,y=0} end, IsFacingLocation=function() return true end,
        GetAttackTarget=function() return tower end}
    jmz.GetEnemiesNearLoc = function(point, radius)
        return point.x == tower.x and radius >= 3200 and {scout} or {}
    end
    local threat = jmz.GetOuterTowerThreat(tower, lane.Mid)
    assert(threat.score > 0 and threat.waveSize == 0, 'respond when a visible enemy is already hitting an outer tower')
    local fallback = {x=tower.x - 2200,y=0}
    local delay, assignments = jmz.GetOuterTowerResponse(tower:GetLocation(), threat, fallback)
    assert(delay and assignments[members[3]:GetPlayerID()].teleport == fallback,
        'allow a ranged clearer to land at the rear tower while the front tower still has time')
    threat.towerHP = 0.2
    delay, assignments = jmz.GetOuterTowerResponse(tower:GetLocation(), threat, fallback)
    assert(delay and next(assignments) == nil, 'skip an arrival that would be too late to defend')
end

do
    local opts = {direct = true, outerSiege = true, x = 4750, bigWave = true, twoClearers = true}
    local _, defend, members, _, lane, _, buildings, jmz = fixture(opts)
    local threat = jmz.GetOuterTowerThreat(buildings.outerTower, lane.Mid)
    local delay, assignments = jmz.GetOuterTowerResponse(buildings.outerTower:GetLocation(), threat)
    assert(threat.waveSize == 6 and threat.siege and delay and assignments[2] and assignments[3],
        'reinforce a siege wave when one spell cannot clear it in time')
    same(defend.GetDefendDesire(members[2], lane.Mid), 0.7, 'second clearer is assigned through production defense mode')
    opts.twoClearers = false
    delay, assignments = jmz.GetOuterTowerResponse(buildings.outerTower:GetLocation(), threat)
    assert(delay and next(assignments) == nil, 'yield instead of feeding an unsupported clearer')
    opts.spellDamage, opts.twoAttackers = 650, true
    threat = jmz.GetOuterTowerThreat(buildings.outerTower, lane.Mid)
    delay, assignments = jmz.GetOuterTowerResponse(buildings.outerTower:GetLocation(), threat)
    assert(delay and assignments[3] and not assignments[2], 'one safe high-damage clearer may handle a siege wave')
    opts.unitTargetClear = true
    _, assignments = jmz.GetOuterTowerResponse(buildings.outerTower:GetLocation(), threat)
    assert(not assignments[3], 'a lone short-range clearer cannot stand off the same siege')
    threat.count, threat.near = 1, 1
    _, assignments = jmz.GetOuterTowerResponse(buildings.outerTower:GetLocation(), threat)
    assert(assignments[3].reach == 750, 'a unit-target wave spell needs an enemy in cast range')
end

do
    local opts = {direct=true, outerSiege=true, highDefend=true, x=4750, bigWave=true, twoClearers=true}
    local _, defend, members, _, lane, _, buildings = fixture(opts)
    same(defend.GetDefendDesire(members[3], lane.Mid), 0.96, 'high ground assigns the available ranged clearer')
    assert(members[3]._defend.waveClearTower == buildings.outerTower)
end

do
    local opts = {time=435, direct=true, outerSiege=true, counterPush=true, safeSiege=true, captureTargets=true,
        x=8528, enemyAliveAtStart=5, alliedWaveHitting=true}
    local push, _, members, orders, lane, _, buildings = fixture(opts)
    local bot = members[1]
    bot.GetAttackRange = function() return 150 end
    same(push.GetPushDesire(bot, lane.Top), 0.8, 'a lone melee core can join three allied creeps already hitting an open tower')
    push.PushThink(bot, lane.Top)
    assert(orders[1] == buildings.counterTower and opts.lastAttackOnce == false, 'attack the actual tower until the wave or safety changes')
    bot.GetAttackTarget = function() return buildings.counterTower end
    push.PushThink(bot, lane.Top)
    assert(#orders == 1, 'do not restart a tower attack already in progress')
    opts.visibleDefenders = 2
    push.PushThink(bot, lane.Top)
    assert(orders[2] == 'cancel' and not bot.ohaOuterTowerPush, 'release the standing attack when defenders appear')
end

do
    local opts = {time=970, direct=true, outerSiege=true, counterPush=true, safeSiege=true, captureTargets=true,
        x=4900, enemyAliveAtStart=5, alliedCatapult=true, enemySightings={}}
    local push, _, members, orders, lane, _, buildings = fixture(opts)
    local bot = members[1]
    for i=2,4 do members[i].x = -1000 end
    for i=1,4 do opts.enemySightings[i] = {{time_since_seen=1, location={x=0,y=0}}} end
    opts.enemySightings[4][1].time_since_seen = 10
    same(push.GetPushDesire(bot, lane.Top), 0, 'old information cannot justify a long rotation for a siege wave')
    opts.enemySightings[4][1].time_since_seen = 1
    same(push.GetPushDesire(bot, lane.Top), 0.76, 'start escorting an ordinary siege wave even without a tower-defense trade')
    push.PushThink(bot, lane.Top)
    same(orders[1].x, buildings.counterTower.x - 950, 'approach behind the siege wave')
    members[2].x = 6500
    push.PushThink(bot, lane.Top)
    assert(orders[2] == 'cancel', 'leave the long rotation to the closer available teammate')
    members[2].x, opts.alliedCatapult = -1000, false
    same(push.GetPushDesire(bot, lane.Top), 0, 'a small ordinary wave will disappear before this distant hero arrives')
end

do
    local opts = {direct = true, counterPush = true, captureTargets = true, x = 8400, aliveEnemies = 5}
    local push, _, members, orders, lane, _, buildings = fixture(opts)
    members[1].ohaOuterTowerTrade = {lane = lane.Mid, location = {x = 5000}, expires = 1803}
    same(push.GetPushDesire(members[1], lane.Top), 0.82, 'exploit a safe outer-tower window even with the enemy alive')
    push.PushThink(members[1], lane.Top)
    assert(orders[1] == buildings.counterTower)
    opts.unsafeLanding = true
    push.PushThink(members[1], lane.Top)
    assert(orders[2] == 'cancel', 'stop trading the tower when enemy reinforcements can contest it')
end

do
    local opts = {direct=true, outerSiege=true, counterPush=true, safeSiege=true, captureTargets=true,
        x=6500, aliveEnemies=5, enemyAliveAtStart=5, waveOffset=1750, enemySightings={}}
    local push, _, members, orders, lane, _, buildings, jmz = fixture(opts)
    local support, tower = members[1], buildings.counterTower
    jmz.IsCore = function(unit) return unit ~= support end
    for i=2,4 do members[i].x = -1000 end
    for i=1,4 do opts.enemySightings[i] = {{time_since_seen=1, location={x=0,y=0}}} end
    support.ohaOuterTowerTrade = {lane=lane.Mid, location={x=5000}, expires=1803}
    same(push.GetPushDesire(support, lane.Top), 0.82, 'a nearby unassigned support can escort when four opponents show elsewhere')
    push.PushThink(support, lane.Top)
    assert(orders[1].lane == lane.Top and orders[1].x < tower.x-950, 'approach along the side lane behind the wave')
    local alliedCreep = {GetAttackTarget=function() end}
    local blocker = {x=6800, GetAttackTarget=function() return alliedCreep end}
    support.GetNearbyLaneCreeps = function(_, _, enemy) return enemy and {blocker} or {alliedCreep} end
    push.PushThink(support, lane.Top)
    assert(orders[2] == blocker, 'clear the enemy creep holding up the escorted wave')
    members[2].x = 7600
    push.PushThink(support, lane.Top)
    assert(orders[3] == 'cancel', 'release the long escort when a ready teammate is closer')
    members[2].x = -1000
    opts.enemySightings[4][1].time_since_seen = 12
    same(push.GetPushDesire(support, lane.Top), 0, 'a long support rotation requires fresh information about four opponents')
    opts.enemySightings[4][1].time_since_seen = 1
    support.x, opts.waveOffset = 8350, 0
    support.GetNearbyLaneCreeps = function() return {} end
    tower.HasModifier = function(_, name) return name == 'modifier_backdoor_protection_active' end
    same(push.GetPushDesire(support, lane.Top), 0.82, 'the protected tower can still have an approaching escort')
    push.PushThink(support, lane.Top)
    assert(orders[4].lane == lane.Top, 'stay behind the creeps while the building is protected')
    tower.HasModifier = function() return false end
    push.PushThink(support, lane.Top)
    assert(orders[5] == tower, 'attack only after protection drops')
    support.ohaOuterTowerHoldUntil = 1803
    push.PushThink(support, lane.Top)
    assert(orders[6] == 'cancel', 'the designated defender drops the side-lane order')
end

do
    local opts = {direct=true, counterPush=true, captureTargets=true, x=7200, aliveEnemies=5}
    local push, _, members, orders, lane, _, buildings, jmz = fixture(opts)
    members[1].ohaOuterTowerTrade = {lane=lane.Mid, location={x=5000}, expires=1803}
    jmz.AdjustLocationWithOffsetTowardsFountain = function(point, offset) return {x=point.x-offset} end
    same(push.GetPushDesire(members[1], lane.Top), 0.82, 'join the side wave when four enemies are visible across the map')
    push.PushThink(members[1], lane.Top)
    same(orders[1].x, buildings.counterTower.x-950, 'stage behind the wave before entering tower range')
    opts.unsafeLanding = true
    push.PushThink(members[1], lane.Top)
    assert(orders[2] == 'cancel', 'abandon the approach when the route becomes contested')
end

do
    local opts = {direct=true, counterPush=true, captureTargets=true, x=8400, aliveEnemies=5, waveOffset=1400}
    local push, _, members, orders, lane, _, buildings, jmz = fixture(opts)
    members[1].ohaOuterTowerTrade = {lane=lane.Mid, location={x=5000}, expires=1803}
    jmz.AdjustLocationWithOffsetTowardsFountain = function(point, offset) return {x=point.x-offset} end
    same(push.GetPushDesire(members[1], lane.Top), 0.82, 'leave early enough to accompany a wave arriving in under six seconds')
    push.PushThink(members[1], lane.Top)
    assert(orders[1].x < 9000 - opts.waveOffset, 'stay behind the approaching creeps while the tower has no targets')
    opts.waveCount = 2
    push.PushThink(members[1], lane.Top)
    assert(orders[2] == 'cancel', 'drop the siege order when too little cover remains')
    opts.waveCount, opts.waveOffset = 3, 0
    same(push.GetPushDesire(members[1], lane.Top), 0.82, 'resume the trade behind a full wave')
    push.PushThink(members[1], lane.Top)
    assert(orders[3] == buildings.counterTower, 'hit the tower once the creeps arrive')
end

do
    local opts = {direct = true, counterPush = true, captureTargets = true, x = 5750, enemyAliveAtStart = 5, waveOffset = 3400}
    local push, _, members, orders, lane, _, buildings = fixture(opts)
    local bot = members[1]
    bot.ohaOuterTowerTrade = {lane = lane.Mid, location = {x = 5000}, expires = 1806}
    same(push.GetPushDesire(bot, lane.Top), 0.82, 'start the counterpush several thousand units before the side wave reaches the enemy tower')
    local blocker = {x = 5850, GetLocation = function(self) return {x = self.x, lane = lane.Top} end}
    bot.GetNearbyLaneCreeps = function(_, _, enemy) return enemy and {blocker} or {} end
    push.PushThink(bot, lane.Top)
    assert(orders[1] == blocker, 'clear a real blocking wave even before the creeps attack each other')
    bot.GetNearbyLaneCreeps = function() return {} end
    push.PushThink(bot, lane.Top)
    assert(orders[2].lane == lane.Top and orders[2].x < blocker.x, 'escort the side wave once the blocking creep is gone')
    opts.waveOffset, bot.x = 0, 8450
    push.PushThink(bot, lane.Top)
    assert(orders[3] == buildings.counterTower, 'turn the side-lane wave into tower damage')
    opts.unsafeLanding = true
    push.PushThink(bot, lane.Top)
    assert(orders[4] == 'cancel', 'release the pressure immediately when the enemy can arrive')
end

do
    local opts = {direct = true, counterPush = true, captureTargets = true, x = 5400, enemyAliveAtStart = 5,
        waveOffset = 3000, enemySightings = {}}
    local push, _, members, orders, lane = fixture(opts)
    for i = 2, 4 do members[i].x = -1000 end
    for i = 1, 4 do opts.enemySightings[i] = {{time_since_seen = 1, location = {x = 0, y = 0}}} end
    same(push.GetPushDesire(members[1], lane.Top), 0.76, 'turn a safe distant wave into a proactive attack at five versus five')
    push.PushThink(members[1], lane.Top)
    assert(orders[1].lane == lane.Top and orders[1].x > members[1].x, 'advance with the observed wave without waiting for a battle')
    opts.enemySightings[4][1].time_since_seen = 10
    push.PushThink(members[1], lane.Top)
    assert(orders[2] == 'cancel', 'stale information does not justify continuing the proactive rotation')
    opts.friendlyTower, opts.localAllies = true, true
    same(push.GetPushDesire(members[1], lane.Top), 0.76, 'start a wave on the protected side with local backup even if opponents have not revealed')
    opts.backupLost = true
    push.PushThink(members[1], lane.Top)
    assert(#orders == 2 and not members[1].ohaOuterTowerPush, 'release the approach when backup leaves and no distant safety is known')
end

do
    local opts = {farmBot = 1, route = true, time = 1200, laning = true, direct = true}
    local _, _, members, orders, lane, farm = fixture(opts)
    local bot = members[1]
    bot.ohaOuterTowerTrade = {lane = lane.Top, location = {x = bot.x - 850}, expires = 1203}
    same(farm.GetDesire(), 0, 'a visible but empty lane front is not a tower trade')
    opts.tradeWaves = {lane.Top, lane.Mid, lane.Bot}
    farm.lanes[lane.Top].x = bot.x - 1100
    farm.lanes[lane.Bot].x = farm.lanes[lane.Mid].x + 1300
    farm.AdvanceTime(1)
    same(farm.GetDesire(), 0.6, 'use the outer tower window to farm elsewhere')
    farm.Think()
    assert(orders[1] == farm.lanes[lane.Mid], 'follow the nearest safe side wave away from the siege')
    members[2].ohaOuterFarmClaim = {location = farm.lanes[lane.Mid], expires = 1203}
    same(farm.GetDesire(), 0.6, 'a separate safe route is still available')
    farm.Think()
    assert(orders[2] == farm.lanes[lane.Bot], 'do not send two cores to the same wave')
    bot.ohaOuterTowerHoldUntil = 1202
    same(farm.GetDesire(), 0, 'the assigned wave clearer keeps the tower assignment')
    bot.ohaOuterTowerHoldUntil, opts.teamfight = nil, true
    same(farm.GetDesire(), 0, 'do not leave an active teamfight to farm')
    opts.teamfight = false
    farm.AdvanceTime(4)
    same(farm.GetDesire(), 0, 'retire an expired tower-trade assignment')
end

do
    local _, defend, members, _, _, _, buildings = fixture({outerSiege = true, towerCreeps = 2})
    assert(not defend.ShouldDefend(members[2], buildings.outerTower, 1600), 'two ordinary creeps do not request a response')
    _, defend, members, _, _, _, buildings = fixture({outerSiege = true, towerCreeps = 5})
    assert(defend.ShouldDefend(members[4], buildings.outerTower, 1600), 'pick the closer position five')
    assert(not defend.ShouldDefend(members[3], buildings.outerTower, 1600), 'the first support slot is not skipped or preferred')
    members[3].x = buildings.outerTower.x
    assert(defend.ShouldDefend(members[3], buildings.outerTower, 1600), 'pick position four when it becomes closer')
end
print('PASS: anticipate sieges, group clearers and cover, abandon losing holds, and trade map resources safely')

do
    local opts = {farmBot = 1, route = true, time = 1200, dangerInLanes = true,
        closeCampDistance = 400, neutralCount = 3}
    local _, _, members, orders, _, farm = fixture(opts)
    assert(farm.GetDesire() > 0)
    farm.Think()
    assert(orders[2] == 'attack')
    members[1].x = farm.camps[1].cattr.location.x
    opts.neutralCount = 1
    farm.Think()
    assert(orders[4] == 'attack' and not opts.removedCamp, 'finish the last neutral before removing the camp')
    opts.neutralCount = 0
    farm.Think()
    assert(opts.removedCamp, 'clear the camp only after no eligible neutrals remain')
end
print('PASS: farm keeps a camp available through the final neutral creep')

do
    local opts = {farmBot=1, route=true, farmWave=true, time=1800, campHidden=true}
    local _, _, members, orders, _, farm = fixture(opts)
    local bot, ally = members[1], members[2]
    farm.GetDesire()
    farm.Think()
    assert(orders[#orders] == 'attack')
    opts.farmWave, opts.waveMoved = false, true
    assert(farm.GetDesire() ~= 0.62, 'a visible living wave that moved away was not cleared')
    opts.waveMoved = false
    same(farm.GetDesire(), 0.62, 'use the gap after a visible wave')
    farm.Think()
    local near, far = farm.camps[1].cattr.location, farm.camps[2].cattr.location
    assert(orders[#orders] == near and bot.ohaFarmCampClaim.location == near)
    ally.ohaFarmCampClaim = {location=near, expires=1803}
    same(farm.GetDesire(), 0.62, 'look for a different camp when a teammate commits')
    farm.Think()
    assert(orders[#orders] == far and bot.ohaFarmCampClaim.location == far)
    opts.unsafeCampPath = true
    farm.Think()
    assert(orders[#orders] == 'cancel' and not bot.ohaFarmCampClaim, 'a newly unsafe crossing cancels the route')
    farm.AdvanceTime(4)
    same(farm.GetDesire(), 0.62, 'an abandoned claim expires')
    farm.Think()
    assert(orders[#orders] == near)
    opts.farmWave, opts.neutralCount = true, 2
    farm.Think()
    assert(orders[#orders] == 'attack' and bot.ohaFarmCampClaim == nil, 'resume the safe lane on the next wave')
    farm.OnEnd()
    assert(bot.ohaFarmCampClaim == nil)
end

do
    local opts = {farmBot=1, route=true, farmWave=true, time=1800, closeCampDistance=1550, campHidden=true}
    local _, _, members, orders, _, farm = fixture(opts)
    local bot = members[1]
    farm.GetDesire()
    opts.farmWave = false
    same(farm.GetDesire(), 0.62, 'start a nearby camp after clearing')
    farm.Think()
    local nextWaveX = bot.x + 100
    bot.x = farm.camps[1].cattr.location.x
    farm.AdvanceTime(16)
    opts.returnWave = true
    same(farm.GetDesire(), 0.62, 'see the next wave from the camp using allied vision')
    farm.Think()
    assert(orders[#orders].x == nextWaveX and not bot.ohaFarmCampClaim, 'return to the lane from outside local creep range')
end

do
    local opts = {farmBot=1, route=true, farmWave=true, time=1800,
        closeCampDistance=1350, dangerAtFarCamp=true, neutralHP=100}
    local _, _, _, _, _, farm = fixture(opts)
    farm.GetDesire()
    opts.farmWave = false
    assert(farm.GetDesire() ~= 0.62, 'a visible empty camp outside the local scan is not a between-wave detour')
    opts.visibleCampUnit = true
    farm.AdvanceTime(1.2)
    same(farm.GetDesire(), 0.62, 'a visible occupied camp at the same distance can be cleared before the next wave')
end

do
    local opts = {farmBot=1, route=true, resetMode=true, time=480, laning=true, direct=true, farmLevel=5,
        farmNetWorth=2300, mana=0.4, hp=1}
    local _, _, _, orders, _, farm = fixture(opts)
    same(farm.GetDesire(), 0, 'finish the fountain reset while mana is still low')
    opts.mana = 0.9
    same(farm.GetDesire(), 0.5, 'a fully recovered carry can find income before the old retreat mode clears')
    farm.Think()
    assert(orders[1] == farm.camps[1].cattr.location, 'leave the fountain for a real recovery route')
end

do
    local opts = {farmBot=1, farmPosition=2, route=true, direct=true, farmNetWorth=3200, laneTower=true,
        farmWave=true, laning=true, time=720, campHidden=true, neutralCount=3, neutralHP=1100, dangerAtFarCamp=true}
    local _, _, _, _, _, farm = fixture(opts)
    farm.GetDesire()
    opts.farmWave = false
    same(farm.GetDesire(), 0, 'reject a camp the underfarmed core cannot finish before the wave')
    opts.neutralHP = 100
    farm.AdvanceTime(1.2)
    same(farm.GetDesire(), 0.62, 'even during the extended laning phase a nearby quick camp is valid')
end

do
    local function distance(a, b) return math.abs(a.x - b.x) end
    local rawCamps = {
        {team=3, type='small', location={x=10}}, {team=2, type='ancient', location={x=20}},
        {team=2, type='large', location={x=260}}, {team=2, type='small', location={x=360}},
    }
    local enums = {Tower={}, Rune={}, Shop={}, UnitType={}, Lane={}, Team={}}
    local env = setmetatable({GetScriptDirectory=function() return 'bots' end,
        require=function(name) return name:find('utils', 1, true) and {GetLocationToLocationDistance=distance} or enums end,
        Vector=function(x) return {x=x} end, GetTeam=function() return 2 end,
        GetNeutralSpawners=function() return rawCamps end, GetUnitList=function() return {} end,
        GetUnitToLocationDistance=distance}, {__index=_G})
    local site = setfenv(assert(loadfile('bots/FunLib/aba_site.lua')), env)()
    local bot = {x=0, level=4, GetLevel=function(self) return self.level end}
    local camps, count = site.RefreshCamp(bot)
    assert(count == 4)
    local function best() return site.GetClosestNeutralSpwan(bot, camps) end
    assert(best().cattr == rawCamps[4], 'a low-level hero can select an own-side small camp')
    bot.level = 8
    assert(best().cattr == rawCamps[3], 'large camp is reachable at the appropriate level')
    local cleared = best()
    bot.x = 360
    site.UpdateAvailableCamp(bot, cleared, camps)
    assert(#camps == 3 and best().cattr == rawCamps[4], 'remove the cleared camp even if a neighbor is closer to the hero')
    bot.x, bot.level = 0, 12
    assert(best().cattr == rawCamps[2], 'the shared list retains camps for stronger farmers')
    bot.level = 15
    assert(best().cattr == rawCamps[1], 'a capable farmer can select a nearby enemy-side camp')
end

do
    local opts = {x=8400, direct=true, localAllies=true, wave=true, objectives=true, captureTargets=true}
    local push, _, members, orders, lane, _, buildings, jmz = fixture(opts)
    local front, carry = members[1], members[4]
    front.GetAttackRange = function() return 150 end
    carry.damage, carry.x = 310, -4200
    same(push.GetPushDesire(front, lane.Mid), 0.12, 'three local heroes cannot siege without enough damage')
    push.PushThink(front, lane.Mid)
    assert(orders[#orders].x < front.x, 'hold below high ground when the carry is across the map')
    carry.x = 7800
    same(push.GetPushDesire(front, lane.Mid), 0.12, 'a nearby but uncommitted carry is not ready')
    jmz.IsPushing = function(ally) return ally == carry end
    carry.laneToPush = lane.Mid
    push.PushThink(front, lane.Mid)
    assert(orders[#orders] == buildings.melee, 'commit once the ranged damage can arrive with the front')
    carry.IsDisarmed = function() return true end
    push.PushThink(front, lane.Mid)
    assert(orders[#orders-1] == 'cancel' and orders[#orders].x < front.x, 'cancel an outstanding building attack when the damage drops out')
    front.damage = 305
    same(push.GetPushDesire(front, lane.Mid), 0.12, 'a melee front with similar sheet damage still needs its backline')
    carry.x, members[3].damage = -4200, 280
    push.PushThink(front, lane.Mid)
    assert(orders[#orders] == buildings.melee, 'a different available core with comparable damage can siege')
end

do
    local opts = {x=6600, highTowerX=8200, direct=true, localAllies=true, wave=true, captureTargets=true}
    local push, _, members, orders, lane = fixture(opts)
    members[4].damage, members[4].x = 310, -5000
    same(push.GetPushDesire(members[1], lane.Mid), 0.12, 'wait at the T3 approach before entering the Ancient radius')
    push.PushThink(members[1], lane.Mid)
    assert(orders[#orders].x < members[1].x)
end
print('PASS: rotate from wave to safe camp, share live camp claims, and siege only with timely damage')

do
    -- 46-minute river window: no two allied creeps can reach the tower, but
    -- a core and its nearest partner can clear one verified wave together.
    local opts = {postFight=true, conversion=true, conversionCore=1, x=5040,
        allyCount=5, enemyAliveAtStart=3, captureTargets=true, attackers=1}
    local push, defend, members, orders, lane = fixture(opts)
    members[5].x = 200 -- The sole responder stays at the threatened Ancient.
    members[3].x, members[4].x = 7600, 8000
    same(defend.GetDefendDesire(members[5], lane.Mid), 0.97, 'reserve the home defender')
    same(push.GetPushDesire(members[5], lane.Mid), 0, 'the home defender may not convert')
    same(push.GetPushDesire(members[1], lane.Top), 0.12, 'do not split the pair onto another lane')
    same(push.GetPushDesire(members[1], lane.Mid), 0.84, 'the core takes the shared clear task')
    same(push.GetPushDesire(members[2], lane.Mid), 0.84, 'the partner takes the same task')
    push.PushThink(members[1], lane.Mid)
    push.PushThink(members[2], lane.Mid)
    assert(orders[#orders] == orders[#orders-1] and orders[#orders].x == 5450, 'both issue orders to the same real creep')
    opts.unsafeConversion = true
    push.PushThink(members[1], lane.Mid)
    assert(orders[#orders] == 'cancel', 'a newly unsafe target cancels the action')
    opts.unsafeConversion, opts.conversionFog = false, true
    assert(push.GetPushDesire(members[1], lane.Mid) ~= 0.84, 'no play from a wave that is no longer visible')
    opts.conversionFog = false
    members[2].hp = 0.35
    assert(push.GetPushDesire(members[1], lane.Mid) ~= 0.84, 'no solo commitment when the partner cannot help')
    members[2].hp, opts.postFightEnemyAlive = 1, 4
    assert(push.GetPushDesire(members[1], lane.Mid) ~= 0.84, 'stop when enemies respawn')
end

do
    -- 44-minute defensive fight: keep defending multiple creeps inside the base.
    local opts = {postFight=true, conversion=true, conversionX=1400, conversionCore=1,
        x=350, allyCount=5, enemyAliveAtStart=2, attackers=5}
    local push, defend, members, _, lane = fixture(opts)
    for _, ally in ipairs(members) do
        assert(push.GetPushDesire(ally, lane.Mid) ~= 0.84, 'the critical base stops the counter-advance')
    end
    same(defend.GetDefendDesire(members[1], lane.Mid), 0.97, 'critical base assignments still take priority')
end
print('PASS: post-fight allies share a safe wave without abandoning base defense')
