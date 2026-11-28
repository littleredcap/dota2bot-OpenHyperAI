--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayFilter(self, callbackfn, thisArg)
    local result = {}
    local len = 0
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            len = len + 1
            result[len] = self[i]
        end
    end
    return result
end

local function __TS__StringIncludes(self, searchString, position)
    if not position then
        position = 1
    else
        position = position + 1
    end
    local index = string.find(self, searchString, position, true)
    return index ~= nil
end
-- End of Lua Library inline imports
local ____exports = {}
local updateGameStateCache, updateLocationStateCache, updateUnitStateCache, presence_adjust, pingTimeDelta, StartToPushTime, BOT_MODE_DESIRE_EXTRA_LOW, hEnemyAncient, PUSH_CACHE_TTL, gameStateCache, locationStateCache, unitStateCache, BASE_ANC_RADIUS
local jmz = require(GetScriptDirectory().."/FunLib/jmz_func")
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Barracks = ____dota.Barracks
local BotMode = ____dota.BotMode
local BotModeDesire = ____dota.BotModeDesire
local DamageType = ____dota.DamageType
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local ____utils = require(GetScriptDirectory().."/FunLib/utils")
local IsValidUnit = ____utils.IsValidUnit
local GetLocationToLocationDistance = ____utils.GetLocationToLocationDistance
local RadiantFountainTpPoint = ____utils.RadiantFountainTpPoint
local DireFountainTpPoint = ____utils.DireFountainTpPoint
local ____global_cache = require(GetScriptDirectory().."/FunLib/global_cache")
local getGlobalGameState = ____global_cache.getGlobalGameState
local getGlobalLocationState = ____global_cache.getGlobalLocationState
local getCachedAlliesNearLoc = ____global_cache.getCachedAlliesNearLoc
local getCachedEnemiesNearLoc = ____global_cache.getCachedEnemiesNearLoc
local autoCleanupCache = ____global_cache.autoCleanupCache
local getCachedData = ____global_cache.getCachedData
local ____aba_defend = require(GetScriptDirectory().."/FunLib/aba_defend")
local GetBaseCreepResponse = ____aba_defend.GetBaseCreepResponse
function updateGameStateCache()
    local now = DotaTime()
    if gameStateCache and now - gameStateCache.lastUpdate < PUSH_CACHE_TTL then
        return gameStateCache
    end
    local team = GetTeam()
    local enemyTeam = GetOpposingTeam()
    local currentTime = DotaTime()
    local gameMode = GetGameMode()
    local adjustedTime = gameMode == 23 and currentTime * 2 or currentTime
    gameStateCache = {
        lastUpdate = now,
        currentTime = adjustedTime,
        gameMode = gameMode,
        team = team,
        enemyTeam = enemyTeam,
        ourAncient = GetAncient(team),
        enemyAncient = GetAncient(enemyTeam),
        aliveAllyCount = jmz.GetNumOfAliveHeroes(false),
        aliveEnemyCount = jmz.GetNumOfAliveHeroes(true),
        aliveAllyCoreCount = jmz.GetAliveCoreCount(false),
        aliveEnemyCoreCount = jmz.GetAliveCoreCount(true),
        teamNetworth = (jmz.GetInventoryNetworth()),
        enemyNetworth = select(
            2,
            jmz.GetInventoryNetworth()
        ),
        averageLevel = jmz.GetAverageLevel(false),
        hasAegis = jmz.DoesTeamHaveAegis(),
        isEarlyGame = jmz.IsEarlyGame(),
        isMidGame = jmz.IsMidGame(),
        isLateGame = jmz.IsLateGame(),
        isLaningPhase = jmz.IsInLaningPhase()
    }
    return gameStateCache
end
function updateLocationStateCache()
    local now = DotaTime()
    if locationStateCache and now - locationStateCache.lastUpdate < PUSH_CACHE_TTL then
        return locationStateCache
    end
    local team = GetTeam()
    locationStateCache = {
        lastUpdate = now,
        laneFronts = {
            [Lane.Top] = GetLaneFrontLocation(team, Lane.Top, 0),
            [Lane.Mid] = GetLaneFrontLocation(team, Lane.Mid, 0),
            [Lane.Bot] = GetLaneFrontLocation(team, Lane.Bot, 0)
        },
        teamFountain = jmz.GetTeamFountain(),
        enemyFountain = jmz.GetTeamFountain(),
        roshanLocation = jmz.GetCurrentRoshanLocation(),
        tormentorLocation = jmz.GetTormentorLocation(team),
        tormentorWaitingLocation = jmz.GetTormentorWaitingLocation(team)
    }
    return locationStateCache
end
function updateUnitStateCache()
    local now = DotaTime()
    if unitStateCache and now - unitStateCache.lastUpdate < PUSH_CACHE_TTL then
        return unitStateCache
    end
    unitStateCache = {
        lastUpdate = now,
        enemyBuildings = GetUnitList(UnitType.EnemyBuildings),
        alliedHeroes = GetUnitList(UnitType.AlliedHeroes),
        enemyHeroes = __TS__ArrayFilter(
            GetUnitList(UnitType.Enemies),
            function(____, u) return jmz.IsValidHero(u) end
        ),
        alliedCreeps = GetUnitList(UnitType.AlliedCreeps),
        enemyCreeps = __TS__ArrayFilter(
            GetUnitList(UnitType.Enemies),
            function(____, u) return u:IsCreep() or u:IsAncientCreep() end
        )
    }
    return unitStateCache
end
local HasHighGroundCover, CanFinishAncient, GetOuterTowerOpportunity, GetCounterPushTarget, GetPreferredCounterPushLane, GetPostFightPushPlan
function ____exports.GetPushDesireHelper(bot, lane)
    local gameState = getGlobalGameState()
    local ourAncient = gameState.ourAncient
    if not ourAncient then
        return BotModeDesire.None
    end
    local baseResponder, criticalBaseCreeps = GetBaseCreepResponse(bot, ourAncient)
    if baseResponder then
        return BotModeDesire.None
    end
    if bot.laneToPush == nil then
        bot.laneToPush = lane
    end
    autoCleanupCache()
    local locationState = getGlobalLocationState()
    local nMaxDesire = 0.82
    local botActiveMode = bot:GetActiveMode()
    local nModeDesire = bot:GetActiveModeDesire()
    local bMyLane = bot:GetAssignedLane() == lane
    local isMidOrEarlyGame = gameState.isEarlyGame or gameState.isMidGame
    hEnemyAncient = gameState.enemyAncient
    local alliesHere = getCachedAlliesNearLoc(
        bot:GetLocation(),
        1600
    )
    local enemiesHere = getCachedEnemiesNearLoc(
        bot:GetLocation(),
        1600
    )
    local team = gameState.team
    local teamAncientLoc = ourAncient:GetLocation()
    local enemiesAtAncient = jmz.Utils.CountEnemyHeroesNear(teamAncientLoc, BASE_ANC_RADIUS)
    if enemiesAtAncient >= 1 then
        return BotModeDesire.ExtraLow
    end
    if (bot.ohaOuterTowerHoldUntil or 0) > DotaTime()
        or (jmz.GetPostFightDuty and jmz.GetPostFightDuty(bot))
        or (jmz.CanTakePostFightTrip and not jmz.CanTakePostFightTrip(bot, GetLaneFrontLocation(team, lane, 0))) then
        return BotModeDesire.None
    end
    if bot.ohaPostFightPushLane and gameState.aliveEnemyCount > (bot.ohaPostFightPushEnemyCount or 5) then
        if not bot._ohaIssuedPushOrder then bot.ohaPostFightPushLane, bot.ohaPostFightPushEnemyCount = nil, nil end
        return BotModeDesire.None
    end
    local tradeLane = not criticalBaseCreeps and GetPreferredCounterPushLane(bot, gameState.enemyTeam)
    if tradeLane then
        if tradeLane ~= lane then return BotModeDesire.VeryLow end
        bot.ohaPostFightPushLane, bot.ohaPostFightPushEnemyCount = nil, nil
        bot.ohaOuterTowerPush = nil
        bot.ohaCounterPushLane = lane
        bot.laneToPush = lane
        return 0.82
    end
    local nEffAlliesNearAncient = #jmz.GetAlliesNearLoc(teamAncientLoc, 4500) + #jmz.Utils.GetAllyIdsInTpToLocation(teamAncientLoc, 4500)
    local baseDefenseLimited = jmz.GetEnemiesAroundLoc(teamAncientLoc, 4500) > 0 and nEffAlliesNearAncient < 1
    local activeDefense = jmz.IsDefending(bot) and nModeDesire >= 0.8
    local currentTime = gameState.currentTime
    local nH = jmz.Utils.NumHumanBotPlayersInTeam(GetOpposingTeam())
    local outsideCoreLane = not bMyLane and jmz.IsCore(bot) and gameState.isLaningPhase
    jmz.Utils.GameStates = jmz.Utils.GameStates or ({})
    jmz.Utils.GameStates.defendPings = jmz.Utils.GameStates.defendPings or ({pingedTime = GameTime()})
    local recentDefendPing = GameTime() - jmz.Utils.GameStates.defendPings.pingedTime <= 5
    if not outsideCoreLane and not recentDefendPing and not criticalBaseCreeps and not baseDefenseLimited
        and not (hEnemyAncient and CanFinishAncient(bot, hEnemyAncient)) then
        local plan = GetPostFightPushPlan(gameState)
        if plan and plan.ready[bot:GetPlayerID()] then
            if plan.lane ~= lane then return BotModeDesire.VeryLow end
            local waitingForDamage = plan.highGround and hEnemyAncient and not HasHighGroundCover(bot, hEnemyAncient, lane)
            if waitingForDamage then
                local point = bot:GetLocation()
                local direction = team == Team.Radiant and 1 or -1
                local advanced = (GetAmountAlongLane(lane, point).amount - GetAmountAlongLane(lane, plan.staging).amount) * direction
                if advanced > 0.025 or GetHeightLevel(plan.staging) > GetHeightLevel(point) then return BotModeDesire.VeryLow end
            end
            bot.ohaPostFightPushLane = lane
            bot.ohaPostFightPushEnemyCount = gameState.aliveEnemyCount
            bot.ohaCounterPushLane = nil
            bot.ohaOuterTowerPush = nil
            bot.laneToPush = lane
            if plan.waveTarget then return 0.84 end
            if waitingForDamage then return 0.76 end
            return 0.88
        end
    end
    local earlyMidChip = lane == Lane.Mid and currentTime >= 240 and currentTime <= 780
        and bot:GetAssignedLane() == Lane.Mid and bot:GetAttackRange() >= 550
    if (earlyMidChip or nH == 0 or currentTime > StartToPushTime) and not outsideCoreLane and not recentDefendPing
        and not criticalBaseCreeps and not baseDefenseLimited and not activeDefense then
        local opportunity = GetOuterTowerOpportunity(bot, lane, gameState)
        if opportunity ~= nil and (opportunity.earlyMidChip or nH == 0 or currentTime > StartToPushTime) then
            local tower = opportunity.tower
            bot.ohaOuterTowerPush = {lane = lane, tower = tower, earlyMidChip = opportunity.earlyMidChip}
            bot.laneToPush = lane
            return GetUnitToUnitDistance(bot, tower) <= 1600 and 0.8 or 0.76
        end
    end
    if hEnemyAncient and not HasHighGroundCover(bot, hEnemyAncient, lane) then return BotModeDesire.VeryLow end
    local decisivePushWindow = gameState.currentTime >= StartToPushTime and gameState.aliveEnemyCount <= 2 and gameState.aliveAllyCount >= 3 and gameState.aliveAllyCoreCount >= 1 and gameState.aliveAllyCount >= gameState.aliveEnemyCount + 2 and jmz.GetHP(bot) >= 0.6 and #enemiesHere == 0 and not activeDefense and not baseDefenseLimited and not criticalBaseCreeps
    if #alliesHere <= 1 and gameState.aliveEnemyCount >= 3 then
        return BotModeDesire.None
    end
    if gameState.aliveAllyCount <= gameState.aliveEnemyCount - 2 then
        return BotModeDesire.None
    end
    local enemyFountain = gameState.team == Team.Radiant and DireFountainTpPoint or RadiantFountainTpPoint
    local laneFront = GetLaneFrontLocation(gameState.team, lane, 0)
    local safeClosingWindow = decisivePushWindow and (GetUnitToLocationDistance(bot, enemyFountain) >= 3200 or #alliesHere >= 2 or #bot:GetNearbyLaneCreeps(1100, false) >= 2)
    if safeClosingWindow then
        nMaxDesire = 0.88
    end
    if GetLocationToLocationDistance(laneFront, enemyFountain) < 5000 then
        if not safeClosingWindow and #alliesHere < 3 or gameState.aliveAllyCount < gameState.aliveEnemyCount then
            nMaxDesire = math.min(nMaxDesire, 0.08)
        end
    end
    if jmz.GetHP(bot) < 0.5 then
        nMaxDesire = math.min(nMaxDesire, 0.25)
    end
    if gameState.aliveEnemyCount >= 5 and gameState.aliveAllyCount <= gameState.aliveEnemyCount then
        nMaxDesire = math.min(nMaxDesire, 0.41)
    end
    local closeEnemies = getCachedEnemiesNearLoc(
        bot:GetLocation(),
        900
    )
    if #closeEnemies > 0 and #alliesHere >= #closeEnemies then
        nMaxDesire = math.min(nMaxDesire, 0.3)
    end
    if botActiveMode == BotMode.PushTowerTop then
        bot.laneToPush = Lane.Top
    elseif botActiveMode == BotMode.PushTowerMid then
        bot.laneToPush = Lane.Mid
    elseif botActiveMode == BotMode.PushTowerBot then
        bot.laneToPush = Lane.Bot
    end
    if recentDefendPing then
        return BotModeDesire.None
    end
    if outsideCoreLane
        or jmz.IsDoingRoshan(bot) or jmz.IsDoingTormentor(bot) then
        return BOT_MODE_DESIRE_EXTRA_LOW
    end
    do
        local i = 1
        while i <= #GetTeamPlayers(team) do
            local member = GetTeamMember(i)
            if member ~= nil and member:GetLevel() < 6 then
                return BotModeDesire.None
            end
            i = i + 1
        end
    end
    if nH > 0 and currentTime <= StartToPushTime then
        return BOT_MODE_DESIRE_EXTRA_LOW
    end
    if activeDefense then
        nMaxDesire = math.min(nMaxDesire, 0.75)
    end
    local human, humanPing = jmz.GetHumanPing()
    if not criticalBaseCreeps and human ~= nil and humanPing ~= nil and not humanPing.normal_ping and DotaTime() > 0 then
        local isPinged, pingedLane = jmz.IsPingCloseToValidTower(
            GetOpposingTeam(),
            humanPing,
            700,
            5
        )
        if isPinged and lane == pingedLane and GameTime() < humanPing.time + pingTimeDelta then
            return 0.9
        end
    end
    if hEnemyAncient and hEnemyAncient ~= nil then
        if jmz.IsDoingTormentor(bot) and GetUnitToUnitDistance(bot, hEnemyAncient) > 4000 then
            return BOT_MODE_DESIRE_EXTRA_LOW
        end
    end
    local aAliveCount = gameState.aliveAllyCount
    local eAliveCount = gameState.aliveEnemyCount
    local aAliveCoreCount = gameState.aliveAllyCoreCount
    local eAliveCoreCount = gameState.aliveEnemyCoreCount
    local nPushDesire = 0.5
    if baseDefenseLimited then
        nMaxDesire = math.min(nMaxDesire, 0.65)
    end
    local networthAdvantage = gameState.teamNetworth - gameState.enemyNetworth
    local enemyAverageLevel = jmz.GetAverageLevel(true)
    local levelAdvantage = gameState.averageLevel - enemyAverageLevel
    local hasSignificantAdvantage = networthAdvantage > 15000 or levelAdvantage > 2
    if #alliesHere < #enemiesHere and #alliesHere <= eAliveCount - 1 and aAliveCount < eAliveCount then
        if hasSignificantAdvantage and #alliesHere >= #enemiesHere - 1 then
            nMaxDesire = math.min(nMaxDesire, 0.6)
        else
            return BotModeDesire.VeryLow
        end
    end
    local vEnemyLaneFrontLocation = GetLaneFrontLocation(gameState.enemyTeam, lane, 0)
    local waitForSpells = ____exports.ShouldWaitForImportantItemsSpells(vEnemyLaneFrontLocation)
    if waitForSpells and eAliveCount >= aAliveCount and eAliveCoreCount >= aAliveCoreCount then
        nMaxDesire = math.min(nMaxDesire, 0.5)
    end
    local botTarget = bot:GetAttackTarget()
    if jmz.IsValidBuilding(botTarget) and not __TS__StringIncludes(
        botTarget:GetUnitName(),
        "tower1"
    ) and not __TS__StringIncludes(
        botTarget:GetUnitName(),
        "tower2"
    ) then
        if ____exports.HasBackdoorProtect(botTarget) then
            return BOT_MODE_DESIRE_EXTRA_LOW
        end
    end
    local pushLane = ____exports.WhichLaneToPush(bot, lane)
    local isCurrentLanePushLane = pushLane == lane
    if decisivePushWindow and not isCurrentLanePushLane then
        return BotModeDesire.VeryLow
    end
    if not criticalBaseCreeps and not baseDefenseLimited and not activeDefense and (not decisivePushWindow or safeClosingWindow)
    and hEnemyAncient and CanFinishAncient(bot, hEnemyAncient) and not bot:WasRecentlyDamagedByAnyHero(1) and jmz.GetHP(bot) > 0.5 then
        return RemapValClamped(
            jmz.GetHP(bot),
            0,
            0.5,
            BotModeDesire.None,
            0.98
        )
    end
    if not jmz.IsCore(bot) and isCurrentLanePushLane or jmz.IsCore(bot) and (jmz.IsLateGame() and isCurrentLanePushLane or isMidOrEarlyGame) then
        local allowNumbers = eAliveCount == 0 or aAliveCoreCount >= eAliveCoreCount or aAliveCoreCount >= 1 and aAliveCount >= eAliveCount + 2 or networthAdvantage > 8000 and aAliveCount >= eAliveCount - 1 or levelAdvantage > 2 and aAliveCount >= eAliveCount - 1
        if allowNumbers then
            if gameState.hasAegis then
                nPushDesire = nPushDesire + 0.3
            end
            if aAliveCount >= eAliveCount - 1 then
                local networthBonus = RemapValClamped(
                    networthAdvantage,
                    3000,
                    20000,
                    0,
                    1.5
                )
                nPushDesire = nPushDesire + networthBonus
            end
            if levelAdvantage > 0 then
                local levelBonus = RemapValClamped(
                    levelAdvantage,
                    0,
                    8,
                    0,
                    0.8
                )
                nPushDesire = nPushDesire + levelBonus
            end
            if aAliveCount > eAliveCount then
                local groupBonus = RemapValClamped(
                    aAliveCount - eAliveCount,
                    1,
                    3,
                    0.1,
                    0.4
                )
                nPushDesire = nPushDesire + groupBonus
            end
            local desire = RemapValClamped(
                nPushDesire * jmz.GetHP(bot),
                0,
                1,
                0,
                nMaxDesire
            )
            return safeClosingWindow and math.min(
                nMaxDesire,
                math.max(desire, 0.88)
            ) or desire
        end
    end
    return lane == Lane.Mid and BotModeDesire.VeryLow or BOT_MODE_DESIRE_EXTRA_LOW
end
function presence_adjust(score, loc)
    local allies = #jmz.GetAlliesNearLoc(loc, 1600)
    return score / (1 + 0.25 * allies)
end
function ____exports.WhichLaneToPush(_bot, _lane)
    local locationState = updateLocationStateCache()
    local gameState = updateGameStateCache()
    local topLaneScore = 0
    local midLaneScore = 0
    local botLaneScore = 0
    local vTop = locationState.laneFronts[Lane.Top]
    local vMid = locationState.laneFronts[Lane.Mid]
    local vBot = locationState.laneFronts[Lane.Bot]
    local teamMembers = GetUnitList(UnitType.AlliedHeroes)
    for ____, member in ipairs(teamMembers) do
        if jmz.IsValidHero(member) then
            local topDist = GetUnitToLocationDistance(member, vTop)
            local midDist = GetUnitToLocationDistance(member, vMid)
            local botDist = GetUnitToLocationDistance(member, vBot)
            if jmz.IsCore(member) and member and not member:IsBot() then
                topDist = topDist * 0.2
                midDist = midDist * 0.2
                botDist = botDist * 0.2
            elseif not jmz.IsCore(member) then
                topDist = topDist * 1.5
                midDist = midDist * 1.5
                botDist = botDist * 1.5
            end
            topLaneScore = topLaneScore + topDist
            midLaneScore = midLaneScore + midDist
            botLaneScore = botLaneScore + botDist
        end
    end
    local countTop = 0
    local countMid = 0
    local countBot = 0
    for ____, id in ipairs(GetTeamPlayers(gameState.enemyTeam)) do
        if IsHeroAlive(id) then
            local info = GetHeroLastSeenInfo(id)
            if info and info ~= nil then
                local dInfo = info[1]
                if dInfo and dInfo.time_since_seen < 5 then
                    if jmz.GetLocationToLocationDistance(vTop, dInfo.location) <= 1600 then
                        countTop = countTop + 1
                    elseif jmz.GetLocationToLocationDistance(vMid, dInfo.location) <= 1600 then
                        countMid = countMid + 1
                    elseif jmz.GetLocationToLocationDistance(vBot, dInfo.location) <= 1600 then
                        countBot = countBot + 1
                    end
                end
            end
        end
    end
    local hTeleports = GetIncomingTeleports()
    for ____, tp in ipairs(hTeleports) do
        if tp and tp.location and IsLocationVisible(tp.location) and ____exports.IsEnemyTP(tp.playerid) then
            if jmz.GetLocationToLocationDistance(vTop, tp.location) <= 1600 then
                countTop = countTop + 1
            elseif jmz.GetLocationToLocationDistance(vMid, tp.location) <= 1600 then
                countMid = countMid + 1
            elseif jmz.GetLocationToLocationDistance(vBot, tp.location) <= 1600 then
                countBot = countBot + 1
            end
        end
    end
    topLaneScore = topLaneScore * (0.05 * countTop + 1)
    midLaneScore = midLaneScore * (0.05 * countMid + 1)
    botLaneScore = botLaneScore * (0.05 * countBot + 1)
    local topTier = ____exports.GetLaneBuildingTier(Lane.Top)
    local midTier = ____exports.GetLaneBuildingTier(Lane.Mid)
    local botTier = ____exports.GetLaneBuildingTier(Lane.Bot)
    if math.min(topTier, midTier, botTier) < 4 then
        if topTier == 4 then topLaneScore = math.huge end
        if midTier == 4 then midLaneScore = math.huge end
        if botTier == 4 then botLaneScore = math.huge end
    end
    if midTier < topTier and midTier < botTier then
        midLaneScore = midLaneScore * 0.5
        if not jmz.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Mid) then
            midLaneScore = midLaneScore * 0.5
        end
    elseif topTier < midTier and topTier < botTier then
        topLaneScore = topLaneScore * 0.5
        if not jmz.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Top) then
            topLaneScore = topLaneScore * 0.5
        end
    elseif botTier < topTier and botTier < midTier then
        botLaneScore = botLaneScore * 0.5
        if not jmz.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Bot) then
            botLaneScore = botLaneScore * 0.5
        end
    end
    topLaneScore = presence_adjust(topLaneScore, vTop)
    midLaneScore = presence_adjust(midLaneScore, vMid)
    botLaneScore = presence_adjust(botLaneScore, vBot)
    if topLaneScore < midLaneScore and topLaneScore < botLaneScore then
        return Lane.Top
    end
    if midLaneScore < topLaneScore and midLaneScore < botLaneScore then
        return Lane.Mid
    end
    if botLaneScore < topLaneScore and botLaneScore < midLaneScore then
        return Lane.Bot
    end
    if midLaneScore <= topLaneScore and midLaneScore <= botLaneScore then return Lane.Mid end
    return topLaneScore <= botLaneScore and Lane.Top or Lane.Bot
end
function ____exports.IsEnemyTP(nID)
    local gameState = updateGameStateCache()
    for ____, id in ipairs(GetTeamPlayers(gameState.enemyTeam)) do
        if id == nID then
            return true
        end
    end
    return false
end
--- Include micro-summons & dominated units into "nearby creeps" for push thinning
function ____exports.GetSpecialUnitsNearby(bot, hUnitList, nRadius)
    local unitState = updateUnitStateCache()
    local hCreepList = {unpack(hUnitList)}
    for ____, unit in ipairs(unitState.enemyHeroes) do
        if IsValidUnit(unit) and jmz.IsInRange(bot, unit, nRadius) then
            local s = unit:GetUnitName()
            if __TS__StringIncludes(s, "invoker_forge_spirit") or __TS__StringIncludes(s, "lycan_wolf") or __TS__StringIncludes(s, "eidolon") or __TS__StringIncludes(s, "beastmaster_boar") or __TS__StringIncludes(s, "beastmaster_greater_boar") or __TS__StringIncludes(s, "furion_treant") or __TS__StringIncludes(s, "broodmother_spiderling") or __TS__StringIncludes(s, "skeleton_warrior") or __TS__StringIncludes(s, "warlock_golem") or unit:HasModifier("modifier_dominated") or unit:HasModifier("modifier_chen_holy_persuasion") then
                hCreepList[#hCreepList + 1] = unit
            end
        end
    end
    return hCreepList
end
function ____exports.GetAllyHeroesAttackingUnit(hUnit)
    local unitState = updateUnitStateCache()
    local out = {}
    for ____, ally in ipairs(unitState.alliedHeroes) do
        if jmz.IsValidHero(ally) and not jmz.IsSuspiciousIllusion(ally) and not jmz.IsMeepoClone(ally) and ally:GetAttackTarget() == hUnit then
            out[#out + 1] = ally
        end
    end
    return out
end
function ____exports.GetAllyCreepsAttackingUnit(hUnit)
    local unitState = updateUnitStateCache()
    local out = {}
    for ____, creep in ipairs(unitState.alliedCreeps) do
        if jmz.IsValid(creep) and creep:GetAttackTarget() == hUnit then
            out[#out + 1] = creep
        end
    end
    return out
end
--- Returns 1..4 for the highest structure on that lane that is still alive on the enemy team
function ____exports.GetLaneBuildingTier(nLane)
    local gameState = updateGameStateCache()
    local enemyTeam = gameState.enemyTeam
    if nLane == Lane.Top then
        if GetTower(enemyTeam, Tower.Top1) ~= nil then
            return 1
        elseif GetTower(enemyTeam, Tower.Top2) ~= nil then
            return 2
        elseif GetTower(enemyTeam, Tower.Top3) ~= nil or GetBarracks(enemyTeam, Barracks.TopMelee) ~= nil or GetBarracks(enemyTeam, Barracks.TopRanged) ~= nil then
            return 3
        else
            return 4
        end
    elseif nLane == Lane.Mid then
        if GetTower(enemyTeam, Tower.Mid1) ~= nil then
            return 1
        elseif GetTower(enemyTeam, Tower.Mid2) ~= nil then
            return 2
        elseif GetTower(enemyTeam, Tower.Mid3) ~= nil or GetBarracks(enemyTeam, Barracks.MidMelee) ~= nil or GetBarracks(enemyTeam, Barracks.MidRanged) ~= nil then
            return 3
        else
            return 4
        end
    elseif nLane == Lane.Bot then
        if GetTower(enemyTeam, Tower.Bot1) ~= nil then
            return 1
        elseif GetTower(enemyTeam, Tower.Bot2) ~= nil then
            return 2
        elseif GetTower(enemyTeam, Tower.Bot3) ~= nil or GetBarracks(enemyTeam, Barracks.BotMelee) ~= nil or GetBarracks(enemyTeam, Barracks.BotRanged) ~= nil then
            return 3
        else
            return 4
        end
    end
    return 1
end
function ____exports.ShouldWaitForImportantItemsSpells(vLocation)
    local gameState = updateGameStateCache()
    if gameState.isMidGame or gameState.isLateGame then
        if jmz.Utils.HasTeamMemberWithCriticalItemInCooldown(vLocation) then
            return true
        end
        if jmz.Utils.HasTeamMemberWithCriticalSpellInCooldown(vLocation) then
            return true
        end
    end
    return false
end
function ____exports.HasBackdoorProtect(target)
    return target:HasModifier("modifier_fountain_glyph") or target:HasModifier("modifier_backdoor_protection_active")
end
--- Returns true if the *nearest* intended target around the enemy lane-front
-- is currently backdoored/glyphed.
function ____exports.IsAnyTargetBackdooredAt(_bot, lane)
    local locationState = updateLocationStateCache()
    local unitState = updateUnitStateCache()
    local lf = locationState.laneFronts[lane]
    local nearest = nil
    local best = math.huge
    for ____, b in ipairs(unitState.enemyBuildings) do
        if jmz.IsValidBuilding(b) then
            local d = GetUnitToLocationDistance(b, lf)
            if d < best then
                nearest = b
                best = d
            end
        end
    end
    return not not (nearest and ____exports.HasBackdoorProtect(nearest))
end
local Customize = require(GetScriptDirectory().."/Customize/general")
local ____Customize_1 = Customize
local ____Customize_Enable_0
if Customize.Enable then
    ____Customize_Enable_0 = Customize.ThinkLess
else
    ____Customize_Enable_0 = 1
end
____Customize_1.ThinkLess = ____Customize_Enable_0
pingTimeDelta = 5
StartToPushTime = 16 * 60
BOT_MODE_DESIRE_EXTRA_LOW = 0.02
hEnemyAncient = nil
PUSH_CACHE_TTL = 0.5
local BOT_CACHE_TTL = 0.2
gameStateCache = nil
locationStateCache = nil
unitStateCache = nil
local botStateCache = {}
--- Update bot state cache if needed
local function updateBotStateCache(bot, targetLoc)
    local now = DotaTime()
    local botId = bot:GetPlayerID()
    local cached = botStateCache[botId]
    if cached and now - cached.lastUpdate < BOT_CACHE_TTL then
        return cached
    end
    local location = bot:GetLocation()
    local attackRange = bot:GetAttackRange()
    local gameState = updateGameStateCache()
    botStateCache[botId] = {
        lastUpdate = now,
        botId = botId,
        attackRange = attackRange,
        location = location,
        hp = jmz.GetHP(bot),
        mp = jmz.GetMP(bot),
        nearbyTowers = bot:GetNearbyTowers(1200, true),
        nearbyLaneCreeps = bot:GetNearbyLaneCreeps(1200, false),
        nearbyCreeps = bot:GetNearbyCreeps(1600, true),
        attackTarget = bot:GetAttackTarget(),
        distanceToAncient = gameState.enemyAncient and GetUnitToUnitDistance(bot, gameState.enemyAncient) or math.huge,
        distanceToTargetLoc = targetLoc and GetUnitToLocationDistance(bot, targetLoc) or 0
    }
    return botStateCache[botId]
end
--- === Objective selection stability (anti-thrash) ===
-- (kept from Lua; comments preserved)
local OBJECTIVE_STICKY_TIME = 1.2
local SWITCH_SCORE_MARGIN = 0.25
local OBJECTIVE_LEASH_RANGE = 2600
local SCORE_BARRACKS_MELEE = 0
local SCORE_BARRACKS_RANGED = 0.1
local SCORE_T3 = 0.5
local SCORE_T4 = 1.8
BASE_ANC_RADIUS = 2200
local ObjectiveState = {}
function ____exports.GetPushDesire(bot, lane)
    if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not __TS__StringIncludes(
        bot:GetUnitName(),
        "hero"
    ) or bot:IsIllusion() then
        return BotModeDesire.None
    end
    if bot:GetLevel() < 3 then
        return BotModeDesire.None
    end
    local res = ____exports.GetPushDesireHelper(bot, lane)
    bot.pushDesire = res
    return res
end
local function UnitIsValidObjective(u)
    return not not u and jmz.IsValidBuilding(u) and jmz.CanBeAttacked(u) and not ____exports.HasBackdoorProtect(u)
end
local function GetFirstOuterTower(lane, enemyTeam, isAvailable)
    local tierOne = lane == Lane.Top and Tower.Top1 or (lane == Lane.Mid and Tower.Mid1 or Tower.Bot1)
    local tierTwo = lane == Lane.Top and Tower.Top2 or (lane == Lane.Mid and Tower.Mid2 or Tower.Bot2)
    local tower = GetTower(enemyTeam, tierOne)
    if not isAvailable(tower) then tower = GetTower(enemyTeam, tierTwo) end
    return isAvailable(tower) and tower or nil
end
local function GetOuterTowerTarget(bot, lane, enemyTeam, maxDistance)
    local tower = GetFirstOuterTower(lane, enemyTeam, jmz.IsValidBuilding)
    if not tower or not jmz.CanBeAttacked(tower) then return nil end
    local distance = GetUnitToUnitDistance(bot, tower)
    if distance > maxDistance then return nil end

    local location = tower:GetLocation()
    if not jmz.CanCommitToLaneTeleport(bot, location, true) then return nil end
    return tower
end

local function GetLaneStaging(location, lane, offset)
    local amount = GetAmountAlongLane(lane, location).amount
    local behind = math.max(0, math.min(1, amount + (GetTeam() == Team.Radiant and -0.05 or 0.05)))
    local span = GetLocationToLocationDistance(GetLocationAlongLane(lane, amount), GetLocationAlongLane(lane, behind))
    if span < 1 then return nil end
    return GetLocationAlongLane(lane, math.max(0, math.min(1, amount + (behind - amount) * offset / span)))
end

local function GetOuterWaveStaging(tower, lane)
    local location = tower:GetLocation()
    return getCachedData('outerWaveStaging:' .. lane .. ':' .. location.x .. ':' .. location.y, 0.3, function()
        local track = GetAmountAlongLane(lane, location).amount
        local direction = GetTeam() == Team.Radiant and 1 or -1
        local wave = {}
        for _, creep in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
            if jmz.IsValid(creep) and (jmz.IsKeyWordUnit('npc_dota_creep_', creep) or jmz.IsKeyWordUnit('_siege', creep)) then
                local point = creep:GetLocation()
                local path = GetAmountAlongLane(lane, point)
                local distance = GetUnitToLocationDistance(creep, location)
                if distance <= 5200 and path.distance <= 440 and (track - path.amount) * direction >= 0 then
                    wave[#wave + 1] = {point = point, distance = distance}
                end
            end
        end
        table.sort(wave, function(a, b) return a.distance < b.distance end)
        for i = 1, #wave - 2 do
            local front = wave[i]
            if wave[i + 2].distance - front.distance <= 800 then
                local staging = GetLaneStaging(front.point, lane, 325)
                if staging and GetUnitToLocationDistance(tower, staging) < 900 then
                    staging = GetLaneStaging(location, lane, 950)
                end
                if staging and IsLocationPassable(staging) then return {tower = tower, staging = staging, waveFront = front.point, lane = lane} end
            end
        end
    end)
end

local function CanEscortOuterWave(bot, tower, lane, travel)
    local point = tower:GetLocation()
    local distance = GetUnitToUnitDistance(bot, tower)
    local remoteSupport = distance > 2200 and not jmz.IsCore(bot)
    if remoteSupport and travel > 8 then return false end
    local accounted = 0
    for _, id in ipairs(GetTeamPlayers(GetOpposingTeam())) do
        if not IsHeroAlive(id) then
            accounted = accounted + 1
        else
            local info = GetHeroLastSeenInfo(id)
            local seen = info and info[1]
            if seen and seen.time_since_seen < 5 and jmz.GetLocationToLocationDistance(seen.location, point) > 3200 + travel * 160 then
                accounted = accounted + 1
            end
        end
    end
    if accounted < ((distance > 3000 or remoteSupport) and 4 or 2) then return false end
    if not jmz.CanCommitToLaneTeleport(bot, jmz.VectorTowards(bot:GetLocation(), point, distance / 2), true) then return false end
    -- Only one hero needs to rotate. Allies already on the wave can still hit the tower.
    for _, ally in ipairs(jmz.GetAlliesNearLoc(point, distance + 500)) do
        if ally ~= bot and jmz.IsValidHero(ally) and not ally:IsIllusion() and jmz.GetHP(ally) >= 0.6
            and not jmz.IsRetreating(ally) and not ally:HasModifier('modifier_teleporting') and not ally:IsChanneling()
            and not ally:IsDisarmed() and not ally:WasRecentlyDamagedByAnyHero(2) and not ally:WasRecentlyDamagedByTower(2)
            and not jmz.IsDoingRoshan(ally) and not jmz.IsDoingTormentor(ally) and (ally.ohaOuterTowerHoldUntil or 0) <= DotaTime()
            and not (jmz.IsInLaningPhase(ally) and jmz.IsCore(ally) and ally:GetAssignedLane() ~= lane) then
            local gap = GetUnitToUnitDistance(ally, tower)
            local eta = math.max(0, gap - ally:GetAttackRange()) / math.max(1, ally:GetCurrentMovementSpeed())
            if (gap <= 2200 or jmz.IsCore(ally) or accounted >= 4 and eta <= 8) and (eta < travel or eta == travel and ally:GetPlayerID() < bot:GetPlayerID())
                and #jmz.GetEnemiesNearLoc(ally:GetLocation(), 1400) == 0
                and jmz.CanCommitToLaneTeleport(ally, jmz.VectorTowards(ally:GetLocation(), point, gap / 2), true) then return false end
        end
    end
    return true
end

-- A brief mid T1 attack behind a living wave is not a general push.
local function GetEarlyMidTowerChip(bot, lane, gameState)
    local now = gameState.currentTime
    if lane ~= Lane.Mid or now < 240 or now > 960
        or bot:GetAssignedLane() ~= Lane.Mid or bot:GetAttackRange() < 550
        or not jmz.IsCore(bot) or jmz.GetHP(bot) < 0.65 or bot:IsDisarmed()
        or jmz.IsRetreating(bot) or bot:WasRecentlyDamagedByAnyHero(2)
        or bot:WasRecentlyDamagedByTower(2) then return end
    local tower = GetTower(gameState.enemyTeam, Tower.Mid1)
    if not jmz.IsValidBuilding(tower) or not tower:CanBeSeen()
        or tower:HasModifier('modifier_fountain_glyph') or ____exports.HasBackdoorProtect(tower)
        or (bot.ohaLaningAttackTarget ~= nil and jmz.HasPendingLaningLastHit(bot)) then return end
    local gap = GetUnitToUnitDistance(bot, tower) - bot:GetAttackRange()
    if gap > 260 or (now > 780 and gap > 0) then return end
    local tank = tower:GetAttackTarget()
    if not jmz.IsValid(tank) or tank:GetTeam() ~= bot:GetTeam()
        or not jmz.IsKeyWordUnit('npc_dota_creep_', tank)
        or tank:GetHealth() <= math.max(100, tower:GetAttackDamage()) then return end
    local count, siege = 0, false
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(1400, false)) do
        if jmz.IsValid(creep) and jmz.IsInRange(creep, tower, 850) then
            count = count + 1
            siege = siege or jmz.IsKeyWordUnit('_siege', creep)
        end
    end
    if count < 2 or #jmz.GetLastSeenEnemiesNearLoc(tower:GetLocation(), 1200) > 1 then return end
    for _, enemy in ipairs(jmz.GetEnemiesNearLoc(tower:GetLocation(), 1650)) do
        if jmz.IsInRange(bot, enemy, math.max(725, enemy:GetAttackRange() + 150)) then return end
    end
    if gap > 0 then
        -- Only step into range while a real catapult has company and plenty
        -- of tank health; give up the step if another wave needs last hits.
        if not siege or tank:GetHealth() <= 2 * math.max(100, tower:GetAttackDamage())
            or #bot:GetNearbyLaneCreeps(1000, true) > 0 then return end
        local origin = bot:GetLocation()
        local staging = jmz.VectorTowards(origin, tower:GetLocation(), gap + 25)
        local halfway = jmz.VectorTowards(origin, tower:GetLocation(), (gap + 25) / 2)
        if not IsLocationPassable(staging) or not IsLocationVisible(staging)
            or not jmz.CanCommitToLaneTeleport(bot, tower:GetLocation(), true, 1650)
            or not jmz.CanCommitToLaneTeleport(bot, staging, true, 1400)
            or not jmz.CanCommitToLaneTeleport(bot, halfway, true, 1200) then return end
        return {tower = tower, staging = staging, earlyMidChip = true}
    end
    return {tower = tower, earlyMidChip = true}
end

function GetOuterTowerOpportunity(bot, lane, gameState)
    local chip = GetEarlyMidTowerChip(bot, lane, gameState)
    if chip then return chip end
    if jmz.GetHP(bot) < 0.6 or jmz.IsRetreating(bot) or jmz.IsDoingTormentor(bot) or jmz.IsDoingRoshan(bot)
        or bot:IsDisarmed() or bot:WasRecentlyDamagedByTower(2) or bot:WasRecentlyDamagedByAnyHero(2)
        or #jmz.GetEnemiesNearLoc(bot:GetLocation(), 1400) > 0 then return nil end
    local tower = GetOuterTowerTarget(bot, lane, gameState.enemyTeam, 6500)
    if not tower or tower:GetAttackTarget() == bot or #jmz.GetLastSeenEnemiesNearLoc(tower:GetLocation(), 1700) > 0 then return nil end
    local wave, eta, thirdETA, siegeETA, attacking = jmz.GetLaneWaveAtBuilding(tower, lane)
    local tank = tower:GetAttackTarget()
    local distance = GetUnitToUnitDistance(bot, tower)
    local travel = math.max(0, distance - bot:GetAttackRange()) / math.max(1, bot:GetCurrentMovementSpeed())
    if wave < 2 and eta > 7 then
        if DotaTime() < 12 * 60 then return nil end
        local preparation = GetOuterWaveStaging(tower, lane)
        if not preparation or GetUnitToLocationDistance(bot, preparation.staging) > 2200
            or not jmz.CanCommitToLaneTeleport(bot, preparation.staging, true) then return nil end
        -- Open the lane from our side while an ally can cover the shoving hero.
        local friendly = GetFirstOuterTower(lane, bot:GetTeam(), jmz.IsValidBuilding)
        if friendly and GetUnitToLocationDistance(friendly, preparation.staging) <= 1500
            and jmz.GetAvailableFightAllies(bot, preparation.staging, 1450) >= 1 then return preparation end
        if distance <= 4500 and CanEscortOuterWave(bot, tower, lane, travel) then return preparation end
        return nil
    end
    local covered = tank and jmz.IsValid(tank) and tank:IsCreep() and tank:GetTeam() == bot:GetTeam()
        or tank == nil and attacking >= 2
    local protected = ____exports.HasBackdoorProtect(tower)
    if not protected and covered and wave >= 2 and travel <= (wave >= 3 and 3.5 or 1.8) then return {tower = tower} end
    local postFight = DotaTime() >= 8 * 60 and gameState.aliveAllyCount > gameState.aliveEnemyCount and gameState.aliveAllyCoreCount >= 1
    local canApproach = gameState.aliveAllyCount >= 3 and gameState.aliveEnemyCount <= 2
    if postFight and distance <= (canApproach and 3000 or 1600)
        and (jmz.GetAvailableFightAllies(bot, tower:GetLocation(), 1600) >= 1
            or distance > 1600 and jmz.GetAvailableFightAllies(bot, bot:GetLocation(), 1600) >= 1)
        and (jmz.CanFinishOuterTowerInWindow(bot, tower, lane, gameState.reinforcementWindow)
            or (gameState.reinforcementWindow >= 5 and wave >= 2 and distance <= bot:GetAttackRange() + 150)) then
        if not protected and wave >= 2 and distance <= 1600 then return {tower = tower} end
        local staging = GetLaneStaging(tower:GetLocation(), lane, 950)
        if staging and IsLocationPassable(staging) and jmz.CanCommitToLaneTeleport(bot, staging, true) then return {tower = tower, staging = staging} end
    end
    if thirdETA > 7 or travel > thirdETA + ((siegeETA <= 7 or wave >= 5) and 16 or 7)
        or not CanEscortOuterWave(bot, tower, lane, travel) then return nil end
    local staging = GetLaneStaging(tower:GetLocation(), lane, 950 + thirdETA * 325)
    if staging and IsLocationPassable(staging) and jmz.CanCommitToLaneTeleport(bot, staging, true) then return {tower = tower, staging = staging} end
end
function GetCounterPushTarget(bot, lane, enemyTeam)
    local trade = bot.ohaOuterTowerTrade
    if trade == nil or trade.lane == lane or trade.expires <= DotaTime()
        or DotaTime() < 8 * 60 or jmz.GetHP(bot) < 0.6
        or jmz.IsRetreating(bot) or bot:WasRecentlyDamagedByAnyHero(2)
        or bot:WasRecentlyDamagedByTower(2) or bot:IsDisarmed() or bot:IsChanneling()
        or jmz.IsDoingRoshan(bot) or jmz.IsDoingTormentor(bot) then return nil end
    local visiblePushers = #jmz.GetEnemiesNearLoc(trade.location, 2250)
    local support = not jmz.IsCore(bot)
    if visiblePushers < (support and 4 or 3) then return nil end
    local tower = GetOuterTowerTarget(bot, lane, enemyTeam, visiblePushers >= 4 and 6100 or 3600)
    if not tower or tower:GetAttackTarget() == bot or GetUnitToLocationDistance(tower, trade.location) < 3200 then return nil end
    local wave, _, thirdETA = jmz.GetLaneWaveAtBuilding(tower, lane)
    local distance = GetUnitToUnitDistance(bot, tower)
    if #jmz.GetEnemiesNearLoc(bot:GetLocation(), 1500) > 0 then return nil end
    local travel = math.max(0, distance - bot:GetAttackRange()) / math.max(1, bot:GetCurrentMovementSpeed())
    if support and distance > 1600 and not CanEscortOuterWave(bot, tower, lane, travel) then return nil end
    if wave < 3 and (visiblePushers < 4 or thirdETA > 6) then
        local preparation = GetOuterWaveStaging(tower, lane)
        if not preparation or GetUnitToLocationDistance(bot, preparation.staging) > (support and 1700 or 2500)
            or not jmz.CanCommitToLaneTeleport(bot, preparation.staging, true) then return nil end
        local halfway = jmz.VectorTowards(bot:GetLocation(), preparation.staging, GetUnitToLocationDistance(bot, preparation.staging) / 2)
        if not jmz.CanCommitToLaneTeleport(bot, halfway, true) then return nil end
        return preparation
    end
    if distance > 1600 or wave < 3 or ____exports.HasBackdoorProtect(tower) then
        local staging = GetLaneStaging(tower:GetLocation(), lane, 950 + thirdETA * 325)
        if not staging or not IsLocationPassable(staging)
            or not jmz.CanCommitToLaneTeleport(bot, staging, true) then return nil end
        return {tower = tower, staging = staging}
    end
    return {tower = tower}
end

function GetPreferredCounterPushLane(bot, enemyTeam)
    local trade = bot.ohaOuterTowerTrade
    if not trade or trade.expires <= DotaTime() then return nil end
    local best, bestScore = nil, math.huge
    for _, lane in ipairs({Lane.Mid, Lane.Top, Lane.Bot}) do
        local plan = GetCounterPushTarget(bot, lane, enemyTeam)
        if plan then
            local toWave = plan.staging and GetUnitToLocationDistance(bot, plan.staging) or 0
            local score = toWave + GetUnitToUnitDistance(bot, plan.tower) * 0.5
            if score < bestScore then best, bestScore = lane, score end
        end
    end
    return best
end
local function IsStandingBuilding(building)
    return building ~= nil and building:IsAlive()
end

local function GetHighGroundObjective(lane, enemyTeam)
    local tower = GetTower(enemyTeam, lane == Lane.Top and Tower.Top3 or (lane == Lane.Mid and Tower.Mid3 or Tower.Bot3))
    local objective = tower and tower:IsAlive() and tower or GetBarracks(enemyTeam,
        lane == Lane.Top and Barracks.TopMelee or (lane == Lane.Mid and Barracks.MidMelee or Barracks.BotMelee))
    if not objective or not objective:IsAlive() then
        objective = GetBarracks(enemyTeam, lane == Lane.Top and Barracks.TopRanged or (lane == Lane.Mid and Barracks.MidRanged or Barracks.BotRanged))
    end
    return objective and objective:IsAlive() and objective or nil
end

-- A lost siege window is not a reason to split up. Pair a core and a second
-- ready bot for one visible wave, outside enemy tower range, without drafting
-- the base responder. Never substitute a blind move or an uphill approach.
local function GetPostFightWavePlan(gameState, ready, availableTime)
    if availableTime < 6 then return false end
    local free = {}
    for _, ally in pairs(ready) do
        if not jmz.IsValidHero(ally:GetAttackTarget())
            and #jmz.GetEnemiesNearLoc(ally:GetLocation(), 950) == 0 then free[#free + 1] = ally end
    end
    if #free < 2 then return false end
    local best, bestScore = false, math.huge
    local direction = gameState.team == Team.Radiant and 1 or -1
    local enemies = GetUnitList(UnitType.EnemyCreeps)
    for _, lane in ipairs({Lane.Mid, Lane.Top, Lane.Bot}) do
        local tower = GetFirstOuterTower(lane, gameState.enemyTeam, IsStandingBuilding)
        if not tower then tower = GetHighGroundObjective(lane, gameState.enemyTeam) end
        for _, creep in ipairs(enemies) do
            if jmz.IsValid(creep) and jmz.CanBeAttacked(creep)
                and (string.find(creep:GetUnitName(), "npc_dota_creep_", 1, true)
                    or string.find(creep:GetUnitName(), "_siege", 1, true)) then
                local point = creep:GetLocation()
                local track = GetAmountAlongLane(lane, point)
                local staging = GetLaneStaging(point, lane, 360)
                local beforeTower = not tower or ((GetAmountAlongLane(lane, tower:GetLocation()).amount - track.amount) * direction > 0
                    and GetUnitToLocationDistance(tower, point) > 1250)
                if track.distance <= 460 and beforeTower
                    and (not gameState.enemyAncient or GetUnitToLocationDistance(gameState.enemyAncient, point) > 3400)
                    and staging and IsLocationPassable(staging) then
                    local candidates = {}
                    for _, ally in ipairs(free) do
                        local distance = GetUnitToLocationDistance(ally, staging)
                        local eta = distance / math.max(1, ally:GetCurrentMovementSpeed())
                        if eta <= math.min(8, availableTime - 4) and not ally:IsRooted()
                            and not ally:WasRecentlyDamagedByAnyHero(2)
                            and GetHeightLevel(point) <= GetHeightLevel(ally:GetLocation())
                            and jmz.CanCommitToLaneTeleport(ally, point, true, 1200)
                            and jmz.CanCommitToLaneTeleport(ally, staging, true, 1000)
                            and (distance <= 850 or jmz.CanCommitToLaneTeleport(ally,
                                jmz.VectorTowards(ally:GetLocation(), staging, distance / 2), true, 1000))
                            and (not jmz.CanTakePostFightTrip or jmz.CanTakePostFightTrip(ally, point)) then
                            candidates[#candidates + 1] = {ally = ally, eta = eta}
                        end
                    end
                    for i = 1, #candidates do
                        for j = i + 1, #candidates do
                            local a, b = candidates[i], candidates[j]
                            local aId, bId = a.ally:GetPlayerID(), b.ally:GetPlayerID()
                            local score = math.max(a.eta, b.eta) + (a.eta + b.eta) * 0.15
                                + (aId + bId) * 0.0001 + math.min(aId, bId) * 0.000001
                            if score < bestScore and (jmz.IsCore(a.ally) or jmz.IsCore(b.ally)) then
                                bestScore = score
                                best = {lane = lane, staging = staging, waveTarget = creep, ready = {[aId] = a.ally, [bId] = b.ally}}
                            end
                        end
                    end
                end
            end
        end
    end
    return best
end

function GetPostFightPushPlan(gameState)
    local singlePick = gameState.aliveEnemyCount == 4 and gameState.aliveAllyCount == 5
    if gameState.currentTime < (singlePick and 8 * 60 or StartToPushTime)
        or (gameState.aliveEnemyCount > 3 and not singlePick)
        or (singlePick and gameState.reinforcementWindow < 6)
        or gameState.aliveAllyCount <= gameState.aliveEnemyCount or gameState.aliveAllyCoreCount == 0 then return nil end
    return getCachedData("postFightPushPlan", 0.35, function()
        local ready, count = {}, 0
        local reserve = jmz.GetExposedMidCover and jmz.GetExposedMidCover(gameState.team)
        for slot = 1, #GetTeamPlayers(gameState.team) do
            local ally = GetTeamMember(slot)
            if reserve ~= ally and jmz.IsValidHero(ally) and (not jmz.GetPostFightDuty or not jmz.GetPostFightDuty(ally)) and ally:IsBot() and not ally:IsIllusion()
                and jmz.GetHP(ally) >= (singlePick and 0.65 or 0.55)
                and (not singlePick or not jmz.IsValidHero(ally:GetAttackTarget()) and not ally:WasRecentlyDamagedByAnyHero(2))
                and not jmz.IsRetreating(ally) and not ally:IsChanneling() and not ally:HasModifier("modifier_teleporting")
                and not ally:IsStunned() and not ally:IsHexed() and not ally:IsNightmared() and not ally:IsDisarmed()
                and not jmz.IsDoingRoshan(ally) and not jmz.IsDoingTormentor(ally)
                and (ally.ohaOuterTowerHoldUntil or 0) <= DotaTime()
                and not (jmz.IsDefending(ally) and ally:GetActiveModeDesire() >= 0.8)
                and not GetBaseCreepResponse(ally, gameState.ourAncient) then
                ready[ally:GetPlayerID()], count = ally, count + 1
            end
        end
        if count < 2 then return false end

        local availableTime = math.max(0, gameState.reinforcementWindow - 1.5)
        if not singlePick and gameState.aliveAllyCount == gameState.aliveEnemyCount + 1 then
            return GetPostFightWavePlan(gameState, ready, availableTime)
        end
        local creeps = GetUnitList(UnitType.AlliedCreeps)
        local direction = gameState.team == Team.Radiant and 1 or -1
        local best, bestTime = false, math.huge
        for _, lane in ipairs({Lane.Mid, Lane.Top, Lane.Bot}) do
            local tower = GetFirstOuterTower(lane, gameState.enemyTeam, IsStandingBuilding)
            local highGround = tower == nil
            if highGround and not singlePick then tower = GetHighGroundObjective(lane, gameState.enemyTeam) end
            if IsStandingBuilding(tower) and (not singlePick or (jmz.IsValidBuilding(tower)
                and IsLocationVisible(tower:GetLocation())
                and #jmz.GetLastSeenEnemiesNearLoc(tower:GetLocation(), 2000) == 0
                and #jmz.GetEnemiesNearLoc(tower:GetLocation(), 2000) == 0)) then
                local location = tower:GetLocation()
                local front = GetLaneFrontLocation(gameState.team, lane, 0)
                local targetProgress = GetAmountAlongLane(lane, location).amount * direction
                local wave, waveProgress = nil, -math.huge
                local firstCreepETA, secondCreepETA = math.huge, math.huge
                for _, creep in ipairs(creeps) do
                    if jmz.IsValid(creep) and GetUnitToLocationDistance(creep, front) <= 1600 then
                        local name, point = creep:GetUnitName(), creep:GetLocation()
                        local track = GetAmountAlongLane(lane, point)
                        local progress = track.amount * direction
                        if track.distance <= 550 and progress <= targetProgress + 0.04
                            and (string.find(name, "npc_dota_creep_", 1, true) or string.find(name, "_siege", 1, true)) then
                            local eta = math.max(0, GetUnitToLocationDistance(creep, location) - 775)
                                / math.max(1, creep:GetCurrentMovementSpeed())
                            if eta < firstCreepETA then firstCreepETA, secondCreepETA = eta, firstCreepETA
                            elseif eta < secondCreepETA then secondCreepETA = eta end
                            if progress > waveProgress then wave, waveProgress = point, progress end
                        end
                    end
                end
                -- A respawn estimate can be exhausted while the hero is
                -- still publicly dead. Allow only immediately actionable
                -- outer-tower chip in that case, never a march or high ground.
                local immediateChip = not highGround and secondCreepETA == 0
                    and #jmz.GetLastSeenEnemiesNearLoc(location, 1800) == 0
                    and #jmz.GetEnemiesNearLoc(location, 2000) == 0
                local budget = not singlePick and immediateChip and math.max(availableTime, 4) or availableTime
                local arrivalBudget = singlePick and math.min(3, budget) or budget
                if wave and secondCreepETA <= arrivalBudget then
                    local waveDistance = GetLocationToLocationDistance(wave, location)
                    local staging = waveDistance <= 1200 and GetLaneStaging(location, lane, 900)
                        or GetLaneStaging(wave, lane, 280)
                    if staging and IsLocationPassable(staging) then
                        local first, second, core = math.huge, math.huge, math.huge
                        local arriving = {}
                        for _, ally in pairs(ready) do
                            local reach = math.max(0, GetUnitToUnitDistance(ally, tower) - ally:GetAttackRange())
                            if (not ally:IsRooted() or reach == 0)
                                and (not jmz.CanTakePostFightTrip or jmz.CanTakePostFightTrip(ally, location)) then
                                local distance = reach == 0 and 0 or math.max(reach, GetUnitToLocationDistance(ally, staging))
                                local eta = distance / math.max(1, ally:GetCurrentMovementSpeed())
                                if eta <= arrivalBudget then
                                    if budget == availableTime or eta <= 0.7 then arriving[ally:GetPlayerID()] = ally end
                                    if eta < first then first, second = eta, first
                                    elseif eta < second then second = eta end
                                    if jmz.IsCore(ally) then core = math.min(core, eta) end
                                end
                            end
                        end
                        -- First creep or arrival at the staging point alone cannot start the siege.
                        local arrival = math.max(second, core, secondCreepETA)
                        local time = arrival + (highGround and 6 or 0)
                            + #jmz.GetLastSeenEnemiesNearLoc(location, 1600) * 6
                        local dps = 0
                        for _, ally in pairs(arriving) do
                            if ally.GetAttackDamage and ally.GetSecondsPerAttack and tower.GetActualIncomingDamage then
                                local eta = math.max(0, GetUnitToUnitDistance(ally, tower) - ally:GetAttackRange())
                                    / math.max(1, ally:GetCurrentMovementSpeed())
                                if eta <= arrival + 1 then
                                    dps = dps + tower:GetActualIncomingDamage(ally:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
                                        / math.max(0.25, ally:GetSecondsPerAttack())
                                end
                            end
                        end
                        -- If a kill won't fit, a safe outer tower chip can
                        -- still be worth it. Keep an exit buffer either way.
                        local hp = tower.GetHealth and tower:GetHealth() or 0
                        local work = dps > 0 and hp / (dps * 0.8) or math.huge
                        local finish = time + work + 2
                        local usable = budget - time - 1.5
                        local chip = not highGround and dps > 0 and usable >= 1
                            and (budget == availableTime or arrival <= 0.7)
                            and dps * 0.8 * usable >= math.min(hp, math.max(70, hp * 0.075))
                        local rank = finish <= availableTime and finish or chip and (budget + 2 + time) or math.huge
                        if rank < bestTime then
                            bestTime = rank
                            best = {lane = lane, tower = tower, staging = staging, highGround = highGround, ready = arriving, waveFront = wave}
                        end
                    end
                end
            end
        end
        return best or (not singlePick and GetPostFightWavePlan(gameState, ready, availableTime))
    end)
end

function HasHighGroundCover(bot, ancient, lane)
    local enemyTeam = GetOpposingTeam()
    local objective = not CanFinishAncient(bot, ancient) and GetHighGroundObjective(lane, enemyTeam) or ancient
    if GetUnitToUnitDistance(bot, ancient) >= 3000 then
        if GetUnitToUnitDistance(bot, objective) > 1900 then return true end
        local outer = GetTower(enemyTeam, lane == Lane.Top and Tower.Top2 or (lane == Lane.Mid and Tower.Mid2 or Tower.Bot2))
        if outer and outer:IsAlive() then return true end
    end
    local location = bot:GetLocation()
    local allies = jmz.GetAvailableFightAllies(bot, location, 1600)
    local enemies = math.max(#jmz.GetEnemiesNearLoc(location, 1600), #jmz.GetEnemiesNearLoc(ancient:GetLocation(), 1600),
        #jmz.GetEnemiesNearLoc(objective:GetLocation(), 1600))
    if allies < 1 or jmz.GetHP(bot) < 0.35 or enemies >= allies + 1
        or (enemies > 0 and not jmz.WeAreStronger(bot, 1800)) then return false end
    if enemies == 0 and allies >= 2 and jmz.GetNumOfAliveHeroes(true) <= 1
        and CanFinishAncient(bot, ancient) and jmz.GetHP(ancient) <= 0.35 then return true end
    local wave = jmz.GetLaneWaveAtBuilding(objective, lane)
    return wave >= 2 and jmz.HasSiegeDamageInRange(bot, objective:GetLocation(), lane)
end
function CanFinishAncient(bot, ancient)
    return GetUnitToUnitDistance(bot, ancient) < 1000 and UnitIsValidObjective(ancient)
        and (#____exports.GetAllyHeroesAttackingUnit(ancient) >= 2 or #____exports.GetAllyCreepsAttackingUnit(ancient) >= 2
            or jmz.GetAvailableFightAllies(bot, ancient:GetLocation(), 1600) >= 2 or jmz.GetHP(ancient) <= 0.35)
end
local function UnitIsBarracks(u)
    local n = u ~= nil and u:GetUnitName() or ""
    return __TS__StringIncludes(n, "rax")
end
local function UnitIsMeleeBarracks(u)
    return UnitIsBarracks(u) and not not u and __TS__StringIncludes(
        u:GetUnitName(),
        "melee"
    )
end
local function UnitIsRangedBarracks(u)
    return UnitIsBarracks(u) and not not u and __TS__StringIncludes(
        u:GetUnitName(),
        "ranged"
    )
end
local function UnitIsT3(u)
    return u == GetTower(
        GetOpposingTeam(),
        Tower.Top3
    ) or u == GetTower(
        GetOpposingTeam(),
        Tower.Mid3
    ) or u == GetTower(
        GetOpposingTeam(),
        Tower.Bot3
    )
end
local function UnitIsT4(u)
    return u == GetTower(
        GetOpposingTeam(),
        Tower.Base1
    ) or u == GetTower(
        GetOpposingTeam(),
        Tower.Base2
    ) or GetUnitToUnitDistance(
        u,
        GetAncient(GetOpposingTeam())
    ) < 500
end
--- Compute a score for an objective; lower is better.
-- Base priority + mild distance terms; prefer closer to the bot and to approach targetLoc.
local function ObjectiveScore(bot, u, targetLoc)
    if not UnitIsValidObjective(u) then
        return math.huge
    end
    local base = UnitIsMeleeBarracks(u) and SCORE_BARRACKS_MELEE or UnitIsRangedBarracks(u) and SCORE_BARRACKS_RANGED or UnitIsT3(u) and SCORE_T3 or UnitIsT4(u) and SCORE_T4 or 2
    local dBot = GetUnitToUnitDistance(bot, u)
    if dBot > OBJECTIVE_LEASH_RANGE then
        return math.huge
    end
    local d1 = dBot / 2000
    local d2 = targetLoc and GetUnitToLocationDistance(u, targetLoc) / 2500 or 0
    return base + 0.35 * d1 + 0.2 * d2
end
--- Decide whether to keep current target or switch to a better one
local function SelectOrStickHGTarget(bot, lane, targetLoc)
    local pid = bot:GetPlayerID()
    ObjectiveState[pid] = ObjectiveState[pid] or ({})
    ObjectiveState[pid][lane] = ObjectiveState[pid][lane] or ({})
    local state = ObjectiveState[pid][lane]
    local now = GameTime()
    local current = state.target or nil
    local currentScore = current and ObjectiveScore(bot, current, targetLoc) or math.huge
    if current and currentScore < math.huge and now < (state.lockUntil or 0) then
        return current
    end
    local unitState = updateUnitStateCache()
    local best = nil
    local bestScore = math.huge
    for ____, b in ipairs(unitState.enemyBuildings) do
        local sc = ObjectiveScore(bot, b, targetLoc)
        if sc < bestScore then
            best = b
            bestScore = sc
        end
    end
    if current and currentScore < math.huge then
        if best and bestScore + SWITCH_SCORE_MARGIN < currentScore then
            state.target = best
            state.lockUntil = now + OBJECTIVE_STICKY_TIME
            return best
        else
            state.lockUntil = now + 0.6
            return current
        end
    end
    if best then
        state.target = best
        state.lockUntil = now + OBJECTIVE_STICKY_TIME
        return best
    end
    state.target = nil
    state.lockUntil = nil
    return nil
end
local fNextMovementTime = 0
function ____exports.CancelPushOrder(bot, lane)
    if lane ~= nil and bot.ohaOuterTowerPush and bot.ohaOuterTowerPush.lane == lane then bot.ohaOuterTowerPush = nil end
    if lane ~= nil and bot.ohaPostFightPushLane == lane then
        bot.ohaPostFightPushLane, bot.ohaPostFightPushEnemyCount = nil, nil
    end
    if lane ~= nil and bot.ohaCounterPushLane == lane then bot.ohaCounterPushLane = nil end
    if not bot._ohaIssuedPushOrder then return end
    if not jmz.CanNotUseAction(bot) then bot:Action_ClearActions(true) end
    bot._ohaIssuedPushOrder = false
end
local function RunOuterTowerPlan(bot, plan)
    if plan.staging then
        if plan.waveFront then
            local range = math.min(1500, math.max(550, bot:GetAttackRange() + 120))
            for _, creep in ipairs(bot:GetNearbyLaneCreeps(range, true)) do
                if jmz.IsValid(creep) and jmz.CanBeAttacked(creep) and jmz.IsInRange(bot, creep, range)
                    and GetUnitToLocationDistance(creep, plan.waveFront) <= 700 and GetUnitToUnitDistance(creep, plan.tower) > 950
                    and GetAmountAlongLane(plan.lane, creep:GetLocation()).distance <= 460 then
                    bot._ohaIssuedPushOrder = true
                    if bot:GetAttackTarget() ~= creep then bot:Action_AttackUnit(creep, false) end
                    return
                end
            end
        end
        local blockers = bot:GetNearbyLaneCreeps(math.min(1600, bot:GetAttackRange() + 100), true)
        for _, creep in ipairs(blockers) do
            if jmz.IsValid(creep) and jmz.CanBeAttacked(creep) and GetUnitToUnitDistance(creep, plan.tower) > 850
                and GetUnitToLocationDistance(creep, plan.staging) <= 1100 then
                for _, ally in ipairs(bot:GetNearbyLaneCreeps(1600, false)) do
                    if creep:GetAttackTarget() == ally or ally:GetAttackTarget() == creep then
                        bot._ohaIssuedPushOrder = true
                        if bot:GetAttackTarget() ~= creep then bot:Action_AttackUnit(creep, false) end
                        return
                    end
                end
            end
        end
        if GetUnitToLocationDistance(bot, plan.staging) <= 120 then
            ____exports.CancelPushOrder(bot)
            return
        end
        bot._ohaIssuedPushOrder = true
        bot:Action_MoveToLocation(plan.staging)
    elseif bot:GetAttackTarget() ~= plan.tower then
        bot._ohaIssuedPushOrder = true
        bot:Action_AttackUnit(plan.tower, false)
    end
end
function ____exports.PushThink(bot, lane)
    local now = DotaTime()
    if jmz.CanNotUseAction(bot) then
        return
    end
    if jmz.Utils.IsBotThinkingMeaningfulAction(bot, Customize.ThinkLess, "push") then
        return
    end
    local ourAncient = GetAncient(GetTeam())
    local baseResponder, criticalBaseCreeps = GetBaseCreepResponse(bot, ourAncient)
    if baseResponder or ourAncient and jmz.Utils.CountEnemyHeroesNear(
        ourAncient:GetLocation(),
        BASE_ANC_RADIUS
    ) > 0 or jmz.ShouldRetreatFromEnemyReinforcements(bot)
        or (jmz.GetPostFightDuty and jmz.GetPostFightDuty(bot))
        or (jmz.CanTakePostFightTrip and not jmz.CanTakePostFightTrip(bot, GetLaneFrontLocation(GetTeam(), lane, 0))) then
        ____exports.CancelPushOrder(bot, lane)
        return
    end
    if bot.ohaCounterPushLane == lane then
        local plan = not criticalBaseCreeps and (bot.ohaOuterTowerHoldUntil or 0) <= now
            and GetCounterPushTarget(bot, lane, GetOpposingTeam()) or nil
        if plan == nil then
            bot.ohaCounterPushLane = nil
            ____exports.CancelPushOrder(bot)
            if bot:WasRecentlyDamagedByTower(2) then
                bot:Action_MoveToLocation(jmz.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 350))
            end
            return
        end
        RunOuterTowerPlan(bot, plan)
        return
    end
    autoCleanupCache()
    local gameState = getGlobalGameState()
    local locationState = getGlobalLocationState()
    if bot.ohaPostFightPushLane == lane and gameState.enemyAncient and CanFinishAncient(bot, gameState.enemyAncient) then
        bot.ohaPostFightPushLane, bot.ohaPostFightPushEnemyCount = nil, nil
    end
    if bot.ohaPostFightPushLane == lane then
        if gameState.aliveEnemyCount > (bot.ohaPostFightPushEnemyCount or 5) then
            ____exports.CancelPushOrder(bot, lane)
            return
        end
        local advance = not criticalBaseCreeps and (bot.ohaOuterTowerHoldUntil or 0) <= now and GetPostFightPushPlan(gameState)
        if not advance or advance.lane ~= lane or not advance.ready[bot:GetPlayerID()] or jmz.GetHP(bot) < 0.55
            or not jmz.CanCommitToLaneTeleport(bot, advance.staging) then
            ____exports.CancelPushOrder(bot, lane)
            return
        end
        if advance.waveTarget then
            local target, paired = advance.waveTarget, false
            if not jmz.IsValid(target) or not jmz.CanBeAttacked(target) or bot:WasRecentlyDamagedByTower(2)
                or not jmz.CanCommitToLaneTeleport(bot, target:GetLocation(), true, 1200) then
                ____exports.CancelPushOrder(bot, lane)
                return
            end
            for id, ally in pairs(advance.ready) do
                if id ~= bot:GetPlayerID() and jmz.IsValidHero(ally) and jmz.GetHP(ally) >= 0.55
                    and not jmz.IsRetreating(ally) and not ally:IsStunned() and not ally:HasModifier("modifier_teleporting")
                    and GetUnitToUnitDistance(ally, target) <= 1100 and GetUnitToUnitDistance(ally, bot) <= 1400 then
                    paired = true
                end
            end
            if paired and GetUnitToUnitDistance(bot, target) <= math.max(550, bot:GetAttackRange() + 100) then
                bot._ohaIssuedPushOrder = true
                if bot:GetAttackTarget() ~= target then bot:Action_AttackUnit(target, false) end
            elseif GetUnitToLocationDistance(bot, advance.staging) > 120 then
                bot._ohaIssuedPushOrder = true
                bot:Action_MoveToLocation(advance.staging)
            else
                ____exports.CancelPushOrder(bot)
            end
            return
        end
        local tower = advance.tower
        if not IsStandingBuilding(tower) then ____exports.CancelPushOrder(bot, lane); return end
        if bot:WasRecentlyDamagedByTower(2) or (jmz.IsValidBuilding(tower) and tower:GetAttackTarget() == bot) then
            ____exports.CancelPushOrder(bot, lane)
            bot:Action_MoveToLocation(jmz.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 350))
            return
        end
        local wave = jmz.GetLaneWaveAtBuilding(tower, lane)
        local canAttack = wave >= 2 and GetUnitToUnitDistance(bot, tower) <= 1600 and UnitIsValidObjective(tower)
            and jmz.CanCommitToLaneTeleport(bot, tower:GetLocation())
            and (not advance.highGround or gameState.enemyAncient and HasHighGroundCover(bot, gameState.enemyAncient, lane))
        if advance.highGround and not canAttack and GetHeightLevel(advance.staging) > GetHeightLevel(bot:GetLocation()) then
            ____exports.CancelPushOrder(bot, lane)
            return
        end
        RunOuterTowerPlan(bot, {tower = tower, lane = lane, waveFront = advance.waveFront, staging = not canAttack and advance.staging or nil})
        return
    end
    local plan = bot.ohaOuterTowerPush
    if plan and plan.lane == lane then
        if jmz.IsValidBuilding(plan.tower)
            and (plan.tower:GetAttackTarget() == bot or bot:WasRecentlyDamagedByTower(2)) then
            ____exports.CancelPushOrder(bot, lane)
            bot:Action_MoveToLocation(jmz.AdjustLocationWithOffsetTowardsFountain(bot:GetLocation(), 350))
            return
        end
        local opportunity = not criticalBaseCreeps and (bot.ohaOuterTowerHoldUntil or 0) <= now
            and GetOuterTowerOpportunity(bot, lane, gameState) or nil
        if not opportunity or opportunity.tower ~= plan.tower or (plan.earlyMidChip and not opportunity.earlyMidChip) then
            ____exports.CancelPushOrder(bot, lane)
            return
        end
        if opportunity.earlyMidChip then
            bot._ohaIssuedPushOrder = true
            if opportunity.staging then bot:Action_MoveToLocation(opportunity.staging)
            elseif bot:GetAttackTarget() ~= opportunity.tower then bot:Action_AttackUnit(opportunity.tower, true) end
            return
        end
        RunOuterTowerPlan(bot, opportunity)
        return
    end
    hEnemyAncient = gameState.enemyAncient
    if hEnemyAncient and not HasHighGroundCover(bot, hEnemyAncient, lane) then
        ____exports.CancelPushOrder(bot)
        bot:Action_MoveToLocation(jmz.VectorTowards(bot:GetLocation(), locationState.teamFountain, 850))
        return
    end
    local botState = updateBotStateCache(bot)
    local botLocation = botState.location
    local alliesHere = getCachedAlliesNearLoc(botLocation, 1600)
    local enemiesHere = getCachedEnemiesNearLoc(botLocation, 1600)
    local botAttackRange = botState.attackRange
    local botHp = botState.hp
    local fDeltaFromFront = math.min(botHp, 0.7) * 800 - 500 + RemapValClamped(
        botAttackRange,
        300,
        700,
        0,
        -300
    )
    fDeltaFromFront = math.max(
        math.min(fDeltaFromFront, 250),
        -200
    )
    local nEnemyTowers = botState.nearbyTowers
    local nAllyCreeps = botState.nearbyLaneCreeps
    local protectedObjective = ____exports.IsAnyTargetBackdooredAt(bot, lane)
    if #alliesHere < #enemiesHere or protectedObjective then
        local longestRange = 0
        for ____, enemyHero in ipairs(enemiesHere) do
            if jmz.IsValidHero(enemyHero) and not jmz.IsSuspiciousIllusion(enemyHero) then
                local r = enemyHero:GetAttackRange()
                if r > longestRange then
                    longestRange = r
                end
            end
        end
        local gameState = getGlobalGameState()
        local networthAdvantage = gameState.teamNetworth - gameState.enemyNetworth
        local enemyAverageLevel = jmz.GetAverageLevel(true)
        local levelAdvantage = gameState.averageLevel - enemyAverageLevel
        local hasTeamAdvantage = networthAdvantage > 5000 or levelAdvantage > 1
        if #enemiesHere >= #alliesHere + 1 or botHp < 0.3 then
            if hasTeamAdvantage and botHp > 0.4 then
                fDeltaFromFront = math.max(-200, -80 - 0.25 * longestRange)
            else
                fDeltaFromFront = math.max(-300, -120 - 0.35 * longestRange)
            end
        else
            if hasTeamAdvantage and botHp > 0.5 then
                fDeltaFromFront = math.max(-50, -20 - 0.1 * longestRange)
            else
                fDeltaFromFront = math.max(-100, -50 - 0.2 * longestRange)
            end
        end
    end
    local targetLoc = GetLaneFrontLocation(gameState.team, lane, fDeltaFromFront)
    if not botState.distanceToTargetLoc or math.abs(botState.distanceToTargetLoc - GetUnitToLocationDistance(bot, targetLoc)) > 50 then
        updateBotStateCache(bot, targetLoc)
    end
    if jmz.IsValidBuilding(nEnemyTowers[1]) and (nEnemyTowers[1]:GetAttackTarget() == bot or nEnemyTowers[1]:GetAttackTarget() ~= bot and bot:WasRecentlyDamagedByTower(#nAllyCreeps <= 2 and 4 or 2)) then
        local nDamage = nEnemyTowers[1]:GetAttackDamage() * nEnemyTowers[1]:GetAttackSpeed() * 5 - bot:GetHealthRegen() * 5
        if bot:GetActualIncomingDamage(nDamage, DamageType.Physical) / bot:GetHealth() > 0.15 or #nAllyCreeps > 2 then
            local retreat = math.min(fDeltaFromFront - 200, -300)
            local retreatLoc = GetLaneFrontLocation(gameState.team, lane, retreat)
            bot._ohaIssuedPushOrder = false
            bot:Action_MoveToLocation(retreatLoc)
            return
        end
    end
    if not criticalBaseCreeps and hEnemyAncient and CanFinishAncient(bot, hEnemyAncient) then
        bot._ohaIssuedPushOrder = true
        bot:Action_AttackUnit(hEnemyAncient, true)
        return
    end
    local nRange = math.min(700 + botAttackRange, 1600)
    if hEnemyAncient and botState.distanceToAncient < 2600 then
        nRange = 1600
    end
    local nCreeps = botState.nearbyCreeps
    local creepCacheKey = (("specialCreeps_" .. tostring(bot:GetPlayerID())) .. "_") .. tostring(math.floor(now * 5))
    nCreeps = getCachedData(
        creepCacheKey,
        0.2,
        function() return ____exports.GetSpecialUnitsNearby(bot, nCreeps, nRange) end
    )
    local vTeamFountain = locationState.teamFountain
    local bTowerNearby = jmz.IsValidBuilding(nEnemyTowers[1])
    local towerDistanceToFountain = bTowerNearby and GetUnitToLocationDistance(nEnemyTowers[1], vTeamFountain) or 0
    for ____, creep in ipairs(nCreeps) do
        do
            local __continue125
            repeat
                if not jmz.IsValid(creep) or not jmz.CanBeAttacked(creep) then
                    __continue125 = true
                    break
                end
                if jmz.IsTormentor(creep) or jmz.IsRoshan(creep) then
                    __continue125 = true
                    break
                end
                if bTowerNearby and GetUnitToLocationDistance(creep, vTeamFountain) >= towerDistanceToFountain then
                    __continue125 = true
                    break
                end
                bot._ohaIssuedPushOrder = true
                bot:Action_AttackUnit(creep, true)
                return
            until true
            if not __continue125 then
                break
            end
        end
    end
    local hgTarget = SelectOrStickHGTarget(bot, lane, targetLoc)
    if hgTarget then
        bot._ohaIssuedPushOrder = true
        if jmz.IsInRange(bot, hgTarget, botAttackRange + 150) then
            bot:Action_AttackUnit(hgTarget, true)
        else
            bot:Action_MoveToLocation(hgTarget:GetLocation())
        end
        return
    end
    if protectedObjective then
        ____exports.CancelPushOrder(bot)
        bot:Action_MoveToLocation(targetLoc)
        return
    end
    if botState.distanceToTargetLoc > 500 then
        bot._ohaIssuedPushOrder = true
        bot:Action_MoveToLocation(targetLoc)
        return
    else
        if DotaTime() >= fNextMovementTime then
            local attackMoveLoc = jmz.GetRandomLocationWithinDist(targetLoc, 0, 400)
            bot._ohaIssuedPushOrder = true
            bot:Action_AttackMove(attackMoveLoc)
            fNextMovementTime = DotaTime() + RandomFloat(0.05, 0.3)
            return
        end
    end
end
function ____exports.TryClearingOtherLaneHighGround(_bot, vLocation)
    local gameState = updateGameStateCache()
    local unitState = updateUnitStateCache()
    local unitList = unitState.enemyBuildings
    local function IsValid(building)
        return jmz.IsValidBuilding(building) and jmz.CanBeAttacked(building) and not ____exports.HasBackdoorProtect(building)
    end
    local hBarrackTarget = nil
    local best = math.huge
    for ____, barrack in ipairs(unitList) do
        if IsValid(barrack) and (barrack == GetBarracks(gameState.enemyTeam, Barracks.TopMelee) or barrack == GetBarracks(gameState.enemyTeam, Barracks.TopRanged) or barrack == GetBarracks(gameState.enemyTeam, Barracks.MidMelee) or barrack == GetBarracks(gameState.enemyTeam, Barracks.MidRanged) or barrack == GetBarracks(gameState.enemyTeam, Barracks.BotMelee) or barrack == GetBarracks(gameState.enemyTeam, Barracks.BotRanged)) then
            local d = GetUnitToLocationDistance(barrack, vLocation)
            if d < best then
                hBarrackTarget = barrack
                best = d
            end
        end
    end
    if hBarrackTarget then
        return hBarrackTarget
    end
    local hTowerTarget = nil
    best = math.huge
    for ____, tower in ipairs(unitList) do
        if IsValid(tower) and (tower == GetTower(gameState.enemyTeam, Tower.Top3) or tower == GetTower(gameState.enemyTeam, Tower.Mid3) or tower == GetTower(gameState.enemyTeam, Tower.Bot3)) then
            local d = GetUnitToLocationDistance(tower, vLocation)
            if d < best then
                hTowerTarget = tower
                best = d
            end
        end
    end
    if hTowerTarget then
        return hTowerTarget
    end
    return nil
end
function ____exports.CanBeAttacked(building)
    return not not building and building:CanBeSeen() and not building:IsInvulnerable()
end
--- Estimate if staying in a tower's zone is too dangerous over fDuration seconds
function ____exports.IsInDangerWithinTower(hUnit, fThreshold, fDuration)
    local unitState = updateUnitStateCache()
    local totalDamage = 0
    for ____, enemy in ipairs(unitState.enemyHeroes) do
        if jmz.IsValid(enemy) and jmz.IsInRange(hUnit, enemy, 1600) and (enemy:GetAttackTarget() == hUnit or jmz.IsChasingTarget(enemy, hUnit)) then
            totalDamage = totalDamage + hUnit:GetActualIncomingDamage(
                enemy:GetAttackDamage() * enemy:GetAttackSpeed() * fDuration,
                DamageType.Physical
            )
        end
    end
    return totalDamage / hUnit:GetHealth() * 1.2 > fThreshold
end
function ____exports.IsHealthyInsideFountain(hUnit)
    return hUnit:HasModifier("modifier_fountain_aura_buff") and jmz.GetHP(hUnit) > 0.9 and jmz.GetMP(hUnit) > 0.85
end
--- Picks best high-ground objective with strict priority:
--   1) Barracks: melee > ranged (closest of each class)
--   2) Tier-3 towers (closest)
--   3) Fillers/others (closest)
-- Radius is the max distance from the bot; tie-breaker favors closer to targetLoc.
function ____exports.FindBestHGTarget(bot, radius, targetLoc)
    local gameState = updateGameStateCache()
    local unitState = updateUnitStateCache()
    local function isBarracks(u)
        return __TS__StringIncludes(
            u:GetUnitName(),
            "rax"
        )
    end
    local function isMeleeBarracks(u)
        return __TS__StringIncludes(
            u:GetUnitName(),
            "melee"
        )
    end
    local function isRangedBarracks(u)
        return __TS__StringIncludes(
            u:GetUnitName(),
            "ranged"
        )
    end
    local function isT3Tower(u)
        return u == GetTower(gameState.enemyTeam, Tower.Top3) or u == GetTower(gameState.enemyTeam, Tower.Mid3) or u == GetTower(gameState.enemyTeam, Tower.Bot3)
    end
    local function isT4Tower(u)
        return u == GetTower(gameState.enemyTeam, Tower.Base1) or u == GetTower(gameState.enemyTeam, Tower.Base2)
    end
    local bestMelee = nil
    local bestMeleeD = math.huge
    local bestRanged = nil
    local bestRangedD = math.huge
    local bestT3 = nil
    local bestT3D = math.huge
    local bestT4 = nil
    local bestT4D = math.huge
    local bestOther = nil
    local bestOtherD = math.huge
    for ____, b in ipairs(unitState.enemyBuildings) do
        if jmz.IsValidBuilding(b) and jmz.CanBeAttacked(b) and not ____exports.HasBackdoorProtect(b) then
            local dBot = GetUnitToUnitDistance(bot, b)
            if dBot <= radius then
                local dLoc = targetLoc and GetUnitToLocationDistance(b, targetLoc) or 0
                if isBarracks(b) then
                    if isMeleeBarracks(b) then
                        if dBot < bestMeleeD or dBot == bestMeleeD and dLoc < (bestMelee and GetUnitToLocationDistance(bestMelee, targetLoc) or dLoc) then
                            bestMelee = b
                            bestMeleeD = dBot
                        end
                    elseif isRangedBarracks(b) then
                        if dBot < bestRangedD or dBot == bestRangedD and dLoc < (bestRanged and GetUnitToLocationDistance(bestRanged, targetLoc) or dLoc) then
                            bestRanged = b
                            bestRangedD = dBot
                        end
                    end
                elseif isT3Tower(b) then
                    if dBot < bestT3D or dBot == bestT3D and dLoc < (bestT3 and GetUnitToLocationDistance(bestT3, targetLoc) or dLoc) then
                        bestT3 = b
                        bestT3D = dBot
                    end
                elseif isT4Tower(b) then
                    if dBot < bestT4D or dBot == bestT4D and dLoc < (bestT4 and GetUnitToLocationDistance(bestT4, targetLoc) or dLoc) then
                        bestT4 = b
                        bestT4D = dBot
                    end
                else
                    if dBot < bestOtherD or dBot == bestOtherD and dLoc < (bestOther and GetUnitToLocationDistance(bestOther, targetLoc) or dLoc) then
                        bestOther = b
                        bestOtherD = dBot
                    end
                end
            end
        end
    end
    return bestMelee or bestRanged or bestT3 or bestOther
end
return ____exports
