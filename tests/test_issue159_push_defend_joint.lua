-- Run the real generated mode entry points. Engine state plus unrelated
-- lane ranking and cooldown search are deterministic mocks.
local function fixture(opts)
    local function no() return false end
    local function yes() return true end
    local function empty() return {} end
    local function loc(x) return {x=x,y=0} end
    local function building(x,hp)
        return {x=x, IsAlive=yes, IsBuilding=yes, HasModifier=no, GetAttackTarget = function() return opts.towerTarget end,
            GetLocation=function() return loc(x) end, GetHealth=function() return hp end,
            GetMaxHealth=function() return 1000 end}
    end
    local Lan = {Top=1, Mid=2, Bot=3}
    local want = {None=0, ExtraLow=0.02, VeryLow=0.12, High=0.7}
    local ancient, enemy = building(0, opts.ancientHP or 1000), building(9900, 1000)
    enemy.HasModifier = function(_, name) return opts.ancientProtected and name == 'modifier_backdoor_protection_active' end
    enemy.GetHealth = function() return opts.enemyAncientHP or 1000 end
    local t4 = building(120, 1000)
    local highTower = building(opts.highTowerX or 8200, 1000)
    local outerTower = building(6000, 1000)
    local topTower, counterTower = building(6800, 1000), building(9100, 1000)
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
    local now = opts.time or 1800
    for i=1,4 do
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
            GetNearbyLaneCreeps=function()
                return opts.counterPush and {{x=9000},{x=9050},{x=9100}}
                    or opts.wave and {{x=x},{x=x}} or {}
            end,
            Action_AttackUnit=function(_, unit) orders[#orders+1]=opts.captureTargets and unit or 'attack' end,
            Action_ClearActions=function() orders[#orders+1]='cancel' end,
            SetTarget=function() orders[#orders+1]='target' end,
            Action_MoveToLocation=function(_, point) orders[#orders+1]=opts.captureTargets and point or 'move' end,
            Action_AttackMove=function() orders[#orders+1]='attack move' end,
        }
    end
    for i=1,(opts.attackers or 0) do
        local x = opts.creepX or i*100
        creeps[i] = {x=x, IsCreep=yes, IsAncientCreep=no, visible=opts.visible ~= false,
            GetAttackTarget=function() return opts.t4 and t4 or ancient end}
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
        enemyAncient=opts.direct and enemy or nil, aliveAllyCount=4, aliveEnemyCount=2,
        aliveAllyCoreCount=2, aliveEnemyCoreCount=1, teamNetworth=60000,
        enemyNetworth=40000, averageLevel=25, isLaningPhase=false,
    }
    local function stagedWave()
        if not opts.stagedWave then return {} end
        local function laneCreep(x)
            return {x=x, GetUnitName=function() return 'npc_dota_creep_goodguys_melee' end}
        end
        return {laneCreep(5500), laneCreep(5600)}
    end
    local jmz = {
        IsValid=function(u) return u ~= nil and u.visible ~= false end,
        IsValidHero=function(u) return u and u.IsHero and u:IsHero() end,
        CanBeAttacked=yes, IsValidBuilding=function(u) return opts.direct and u ~= nil and u.IsBuilding ~= nil and u:IsAlive() end,
        IsCore=yes, IsLateGame=yes, IsTormentor=no, IsRoshan=no,
        IsDoingRoshan=no, IsDoingTormentor=no, CanNotUseAction=no,
        ShouldRetreatFromEnemyReinforcements=function() return opts.retreatNow end,
        GetHP=function(u) return u == enemy and enemy:GetHealth() / 1000 or opts.hp or 1 end,
        GetMP=function() return 1 end,
        IsInRange=function(u, v, radius) return math.abs(u.x-v.x) <= radius end,
        VectorTowards=function(point, _, offset) return loc(point.x-offset) end,
        GetRandomLocationWithinDist=function(point) return point end,
        GetHumanPing=function()
            if opts.ping then return {}, {time=now,normal_ping=false} end
        end,
        IsPingCloseToValidTower=function() return true,Lan.Mid end,
        IsDefending=function() return opts.defending end,
        GetAlliesNearLoc=function() return opts.baseAlly and {members[1]} or {} end,
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
            return not opts.unsafeLanding and (not clear or point.x ~= outerTower.x
                or (opts.safeSiege and (opts.visibleDefenders or 0) == 0))
        end,
        IsInLaningPhase=no, IsEarlyGame=no, IsMidGame=no,
        GetPosition=function(unit) return unit:GetPlayerID() + 1 end,
        GetNearbyHeroes=empty, WeAreStronger=no, GetTeamFountain=function() return loc(0) end,
        IsRetreating=no,
        AdjustLocationWithOffsetTowardsFountain=function(point) return point end,
        Utils={
            GetTeamFountainTpPoint=function() return loc(0) end,
            CountEnemyHeroesNear=function(_, radius) return radius == 2200 and opts.heroPanic and 1 or 0 end,
            GetAllyIdsInTpToLocation=empty, NumHumanBotPlayersInTeam=function() return 0 end,
            CountEnemyHeroesOnHighGround=function() return 0 end, GetCachedVars=function() end,
            SetCachedVars=function() end, GetLocationToLocationDistance=function(a, b) return math.abs(a.x - b.x) end,
            IsBotThinkingMeaningfulAction=no, GameStates={defendPings={pingedTime=0}}, IsAnyBarracksOnLaneAlive=yes,
        },
    }
    local distance=function(u,v) return math.abs(u.x-v.x) end
    local modules = {
        ['bots/FunLib/jmz_func']=jmz,
        ['bots/ts_libs/dota/index']={Lane=Lan, BotModeDesire=want, BotMode={}, Barracks={TopMelee=1, MidMelee=2, MidRanged=3},
            UnitType={Enemies=1, AlliedHeroes=2, AlliedCreeps=3, EnemyBuildings=4},
            Tower={Base1=1,Base2=2,Mid1=11,Top1=10,Mid2=21,Mid3=31}, Team={Radiant=2,Dire=3}},
        ['bots/FunLib/global_cache']={
            getGlobalGameState=function() return state end, getGlobalLocationState=function() return {teamFountain=loc(0)} end,
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
            if team == 3 and opts.highTowerX and tower == 31 then return highTower end
            if opts.counterPush and team == 3 and tower == 10 then return counterTower end
            if opts.rotatePressure and team == 2 and tower == 10 then return topTower end
            return tower == 1 and t4 or (opts.outerSiege and tower == 11 and outerTower or nil)
        end,
        GetBarracks=function(team, barrack)
            if team == 3 and opts.rotate and barrack == 1 then return melee end
            if team == 3 and opts.objectives then
                if barrack == 2 and melee:IsAlive() then return melee end
                if barrack == 3 and ranged:IsAlive() then return ranged end
            end
        end,
        GetTeamPlayers=function() return {1,2,3,4} end, GetTeamMember=function(i) return members[i] end,
        GetUnitList=function(kind)
            if kind == 1 then return creeps end
            if kind == 3 then return stagedWave() end
            if kind == 4 and opts.objectives then return {melee,ranged} end
            return {}
        end,
        GetUnitToLocationDistance=distance, GetUnitToUnitDistance=distance,
        IsHeroAlive=no, GetIncomingTeleports=empty, RandomFloat=function(first) return first end,
        IsLocationPassable=yes, TEAM_RADIANT=2, UNIT_LIST_ENEMY_CREEPS=1,
        GetAmountAlongLane=function(_, point) return {amount=point.x / 10000, distance=point.y or 0} end,
        PointToLineDistance=function() return opts.badFarmPath and {within=true, distance=100} or nil end,
        GetLaneFrontLocation=function() return loc(8000) end,
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
    if opts.outerSiege then
        local spell = {IsUltimate=no, GetManaCost=function() return 100 end,
            GetAOERadius=function() return 270 end, GetSpecialValueInt=function() return 0 end,
            GetAbilityDamage=function() return opts.spellDamage or 180 end, GetCastRange=function() return 750 end,
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
        jmz.GetAlliesNearLoc = function() return members end
        jmz.GetLocationToLocationDistance = distance
        local scroll = {}
        jmz.GetItem2 = function(ally, name)
            if opts.safeTP and ally == members[3] and name == 'item_tpscroll' then return scroll end
        end
        jmz.CanCastAbility = function(item) return item == scroll end
        jmz.Utils.HasTeamMemberWithCriticalItemInCooldown = function() return opts.criticalCooldown end
        jmz.Utils.HasTeamMemberWithCriticalSpellInCooldown = no
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
            GetUnitName = function() return 'npc_dota_creep_badguys_melee' end,
            GetLocation = function() return laneCreepPoint end}
        local lanes = {[Lan.Top] = loc(bot.x + 800), [Lan.Mid] = loc(bot.x + 1200), [Lan.Bot] = loc(bot.x + 1600)}
        local closeCamp = {cattr = {location = loc(bot.x - (opts.closeCampDistance or 680))}}
        local farCamp = {cattr = {location = loc(bot.x - 1500)}}
        local neutral = {x = closeCamp.cattr.location.x, IsAncientCreep = no, GetTeam = function() return 4 end}
        local midas = {}
        bot.GetNearbyLaneCreeps = function()
            if opts.supportWave then return {laneCreep, laneCreep, laneCreep} end
            return (not opts.route or opts.farmWave) and {laneCreep} or {}
        end
        bot.HasModifier, bot.IsChanneling = no, no
        bot.WasRecentlyDamagedByCreep = no
        bot.GetNearbyTowers, bot.GetNearbyBarracks, bot.GetNearbyNeutralCreeps = empty, empty, empty
        bot.DistanceFromFountain = function() return 1000 end
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
            IsTimeToFarm = yes, IsModeSuitableToFarm = yes, IsEnemyCamp = no,
            UpdateAvailableCamp = function()
                opts.removedCamp = true
                return {farCamp}, nil
            end,
        }
        jmz.GetPosition = function(unit) return unit == bot and (opts.farmPosition or 1) or 1 end
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
                if opts.returnWave and kind == env.UNIT_LIST_ENEMY_CREEPS then return {laneCreep} end
                return env.GetUnitList(kind)
            end,
            GetRoshanDesire = function() return 0 end,
            DotaTime = function() return now end,
            GetLaneFrontLocation = function(_, lane) return lanes[lane] end,
            GetTower = function(team, id)
                if opts.laning and id == 11 and opts.laneTower then return building(lanes[Lan.Mid].x, 1000) end
                return env.GetTower(team, id)
            end,
            GetHeroDeaths = function() return 0 end,
            IsLocationVisible = yes, LANE_TOP = Lan.Top, LANE_MID = Lan.Mid, LANE_BOT = Lan.Bot,
            TOWER_TOP_1 = 10, TOWER_MID_1 = 11, TOWER_BOT_1 = 12,
            TEAM_NEUTRAL = 4, GAMEMODE_MO = 99, Min = math.min,
            BOT_MODE_DESIRE_NONE = 0, BOT_MODE_DESIRE_MODERATE = 0.5, BOT_MODE_DESIRE_VERYHIGH = 0.9,
            BOT_MODE_DESIRE_ABSOLUTE = 1, BOT_MODE_DESIRE_HIGH = 0.7, BOT_MODE_DESIRE_LOW = 0.2, BOT_MODE_ITEM = 15,
            GAMEMODE_1V1MID = 98,
        }, {__index = env})
        jmz.GetEnemiesNearLoc = function(point)
            return (opts.dangerInLanes and point.x > bot.x or opts.dangerAtFarCamp and point == farCamp.cattr.location) and {{}} or {}
        end
        setfenv(assert(loadfile('bots/mode_farm_generic.lua')), farmEnv)()
        farm = {GetDesire = farmEnv.GetDesire, Think = farmEnv.Think, OnEnd = farmEnv.OnEnd}
        function farm.SetThreatVisible(visible) creeps[1].visible = visible end
        function farm.AdvanceTime(seconds) now = now + seconds end
        farm.lanes, farm.camps = lanes, {closeCamp, farCamp}
    end
    return push,defend,members,orders,Lan,farm,
        {ancient=enemy, melee=melee, ranged=ranged, outerTower=outerTower, counterTower=counterTower}, jmz
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
print('PASS: 22 joint #159/#176 generated push and defense scenarios')

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
    assert(orders[2] == farm.lanes[lane.Top], 'an open nearby lane is preferred to a neutral camp')
    opts.defending = true
    same(farm.GetDesire(), 0, 'urgent defense still overrides early recovery')
end
print('PASS: an underfarmed carry can recover from a lost lane during laning')

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
    assert(orders[2] == 'cancel' and not members[1].ohaPostFightTower, 'cancel the existing tower order when the wave dies')
    opts.wave, opts.visibleDefenders = true, 1
    same(push.GetPushDesire(members[1], lane.Mid), 0, 'do not commit the tower window into a visible defender')
    opts.visibleDefenders, opts.safeSiege = 0, false
    same(push.GetPushDesire(members[1], lane.Mid), 0, 'do not commit into recently seen defenders')
end

do
    local opts = {time=20 * 60,x=3600,direct=true,outerSiege=true,localAllies=true,safeSiege=true,stagedWave=true,captureTargets=true}
    local push, _, members, orders, lane, _, buildings = fixture(opts)
    local bot = members[1]
    same(push.GetPushDesire(bot, lane.Mid), 0.76, 'advance with backup towards a supported wave outside attack range')
    push.PushThink(bot, lane.Mid)
    assert(orders[1].x == buildings.outerTower.x - 900, 'stage behind the wave instead of walking straight under the tower')
    opts.unsafeLanding = true
    push.PushThink(bot, lane.Mid)
    assert(orders[2] == 'cancel', 'newly visible defenders or arrivals cancel the advance')
end

do
    local opts = {farmBot = 1, farmPosition = 5, time = 600, route = true, laning = true, supportWave = true}
    local _, _, members, _, _, farm = fixture(opts)
    same(farm.GetDesire(), 0.49, 'support can collect an unclaimed safe wave')
    opts.waveOwner = true
    same(farm.GetDesire(), 0, 'yield the wave to a nearby core')
    opts.waveOwner, opts.laneThreat = false, true
    same(farm.GetDesire(), 0, 'do not collect a wave into recent enemies')
    opts.laneThreat, opts.farmPosition, opts.supportWave = false, 3, false
    members[1].ohaIdleRecoveryUntil = 605
    same(farm.GetDesire(), 0.65, 'idle core can rejoin safe income')
end

do
    local opts = {farmBot = 1, farmPosition = 2, route = true, time = 617,
        laning = true, direct = true, farmLevel = 7, farmNetWorth = 2800, waveClaimed = true}
    local _, _, _, orders, lane, farm = fixture(opts)
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
    same(defend.GetDefendDesire(members[3], lane.Mid), 0.7, 'a distant clearer can reposition to an uncontested tower')
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
end

do
    local opts = {direct = true, counterPush = true, captureTargets = true, x = 8400, aliveEnemies = 5}
    local push, _, members, orders, lane, _, buildings = fixture(opts)
    members[1].ohaOuterTowerTrade = {lane = lane.Mid, location = {x = 5000}, expires = 1803}
    same(push.GetPushDesire(members[1], lane.Top), 0.67, 'exploit a safe outer-tower window even with the enemy alive')
    push.PushThink(members[1], lane.Top)
    assert(orders[1] == buildings.counterTower)
    opts.unsafeLanding = true
    push.PushThink(members[1], lane.Top)
    assert(orders[2] == 'cancel', 'stop trading the tower when enemy reinforcements can contest it')
end

do
    local opts = {farmBot = 1, route = true, time = 1200, laning = true}
    local _, _, members, orders, lane, farm = fixture(opts)
    local bot = members[1]
    bot.ohaOuterTowerTrade = {lane = lane.Top, location = {x = bot.x - 850}, expires = 1203}
    same(farm.GetDesire(), 0.6, 'use the outer tower window to farm elsewhere')
    farm.Think()
    assert(orders[1] == farm.lanes[lane.Mid], 'follow the nearest safe side wave away from the siege')
    members[2].ohaOuterFarmClaim = {location = farm.lanes[lane.Mid], expires = 1203}
    farm.lanes[lane.Bot].x = farm.lanes[lane.Mid].x + 1300
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
    local opts = {farmBot=1, route=true, farmWave=true, time=1800}
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
    local opts = {farmBot=1, route=true, farmWave=true, time=1800, closeCampDistance=1550}
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
    local push, _, members, orders, lane, _, buildings = fixture(opts)
    local front, carry = members[1], members[4]
    front.GetAttackRange = function() return 150 end
    carry.damage, carry.x = 310, -4200
    same(push.GetPushDesire(front, lane.Mid), 0.12, 'three local heroes cannot siege without enough damage')
    push.PushThink(front, lane.Mid)
    assert(orders[#orders].x < front.x, 'hold below high ground when the carry is across the map')
    carry.x = 7800
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
