if GetBot():IsInvulnerable() or not GetBot():IsHero() or not string.find(GetBot():GetUnitName(), "hero") or GetBot():IsIllusion() then
	return;
end

local Utils = require( GetScriptDirectory()..'/FunLib/utils' )
local Version = require(GetScriptDirectory()..'/FunLib/version')
local Localization = require( GetScriptDirectory()..'/FunLib/localization' )
local Customize = require( GetScriptDirectory()..'/Customize/general' )
local Defend = require( GetScriptDirectory()..'/FunLib/aba_defend' )

local bot = GetBot();
local X = {}
local J = require( GetScriptDirectory()..'/FunLib/jmz_func')
local LaneResourceWindow = require(GetScriptDirectory() .. '/FunLib/lane_resource_window')
local RB = Vector(-7174.000000, -6671.00000, 0.000000)
local DB = Vector(7023.000000, 6450.000000, 0.000000)

local botName = bot:GetUnitName();
local lastCampRefreshMinute = 0
local preferedCamp = nil;
local farmLaneLocation = nil
local idleRally, collectingWave
local sideWaveTask, sideWaveDesire, sideWaveCandidate
local sideWaveScanAt = -math.huge
local waveScanAt, visibleWaves = -math.huge, {}
local recoveringLane = false
local tradingTowerLocation = nil
local nextCampSearch = 0
local lastWaveLocation, lastWaveSeenAt = nil, -math.huge
local lastWaveCreeps = {}
local postWaveCampDistance = nil
local postWaveOrigin, postWaveLane, postWaveUntil = nil, nil, 0
local issuedFarmOrder = false
local hLaneCreepList = {};
local farmState = 0;
local FARM_STATE_NONE = 0;
local FARM_STATE_FARM = 1;
local teamPlayers = nil;
local nLaneList = {LANE_TOP, LANE_MID, LANE_BOT};
local laneTierOne = {[LANE_TOP] = TOWER_TOP_1, [LANE_MID] = TOWER_MID_1, [LANE_BOT] = TOWER_BOT_1}
local assembleTime = 0;
local teamTime = 0;

local countTime = 0;
local countCD = 5.0;
local allyKills = 0;
local enemyKills = 0;

local nLostCount = RandomInt(35,45);
local nWinCount = RandomInt(24,34);

local bInitDone = false;
local beNormalFarmer = false;
local beHighFarmer = false;
local team = GetTeam()
local isChangePosMessageDone = false
local nH, nB = J.Utils.NumHumanBotPlayersInTeam(GetOpposingTeam())
local lastAnnouncePrintedTime = 0
local numberAnnouncePrinted = 1
local announcementGap = 6
local hasPickedOneAnnouncer = false
local CleanupCachedVarsTime = -100

local runTime = 0;
local shouldRunTime = 0
local runMode = false;


if bot.farmLocation == nil then bot.farmLocation = bot:GetLocation() end

local function ShouldYieldForBaseDefense()
	if J.IsDefending(bot) and bot:GetActiveModeDesire() >= 0.75 then return true end
	local ancient = GetAncient(team)
	if ancient == nil then return false end
	if #J.GetLastSeenEnemiesNearLoc(ancient:GetLocation(), 3000) > 0 then return true end
	local assigned = Defend.GetBaseCreepResponse(bot, ancient)
	return assigned
end

local function IsFarmLocationSafe(location)
	if J.CanTakePostFightTrip and not J.CanTakePostFightTrip(bot, location, false, true) then return false end
	if #J.GetEnemiesNearLoc(location, 1400) > 0
		or (recoveringLane and #J.GetLastSeenEnemiesNearLoc(location, 1400) > 0) then return false end
	if tradingTowerLocation == nil then return true end
	if J.GetLocationToLocationDistance(location, tradingTowerLocation) <= 1800 then return false end
	local path = PointToLineDistance(bot:GetLocation(), location, tradingTowerLocation)
	if path ~= nil and path.within and path.distance < 1200
		and GetUnitToLocationDistance(bot, tradingTowerLocation) > 1400 then return false end
	for i = 1, #GetTeamPlayers(team) do
		local ally = GetTeamMember(i)
		local claim = ally ~= nil and ally ~= bot and ally.ohaOuterFarmClaim
		if claim and ally:IsAlive() and claim.expires > DotaTime()
			and J.GetLocationToLocationDistance(location, claim.location) < 900 then return false end
	end
	return true
end

local function CanReserveWave(ally)
	return ally ~= bot and J.IsValidHero(ally) and not ally:IsIllusion() and J.GetHP(ally) >= 0.40
		and not J.IsRetreating(ally) and not ally:IsChanneling() and not J.IsDisabled(ally)
		and (ally.ohaOuterTowerHoldUntil or 0) <= DotaTime() and not ally:HasModifier('modifier_teleporting')
		and not (J.IsDefending(ally) and ally:GetActiveModeDesire() >= 0.75)
		and not J.IsGoingOnSomeone(ally) and not J.IsDoingRoshan(ally) and not J.IsDoingTormentor(ally)
end

local function IsReleasedFarmLane(location)
	local trade = bot.ohaOuterTowerTrade
	return trade and trade.expires > DotaTime() and GetAmountAlongLane(trade.lane, location).distance <= 550
end

local function IsFarmWaveAvailable(location)
	if IsReleasedFarmLane(location) or not IsFarmLocationSafe(location) then return false end
	local owner=J.GetScheduledFarmWaveOwner and J.GetScheduledFarmWaveOwner(bot,location)
	if owner~=nil then return owner==bot:GetPlayerID() end
	if not recoveringLane then return true end
	for _, ally in ipairs(J.GetAlliesNearLoc(location, 1000)) do
		if CanReserveWave(ally) and J.IsCore(ally)
			and (J.IsLaning(ally) or J.IsFarming(ally) or J.GetPosition(ally) == 1)
		then return false end
	end
	return true
end

local function CancelFarmOrder()
	if not issuedFarmOrder then return end
	bot:Action_ClearActions(true)
	issuedFarmOrder = false
end

local function MoveToFarm(location)
	if J.CanTakePostFightTrip and not J.CanTakePostFightTrip(bot, location, false, true) then CancelFarmOrder(); return end
	bot:Action_MoveToLocation(location)
	issuedFarmOrder = true
end

local function AttackFarmTarget(target)
	if J.CanTakePostFightTrip and target.GetLocation and not J.CanTakePostFightTrip(bot, target:GetLocation(), false, true) then
		CancelFarmOrder()
		return
	end
	bot:Action_AttackUnit(target, true)
	issuedFarmOrder = true
end

local function IsFarmPathSafe(location)
	local distance = GetUnitToLocationDistance(bot, location)
	if distance > 850 then
		local halfway = J.GetLocationTowardDistanceLocation(bot, location, distance / 2)
		if #J.GetLastSeenEnemiesNearLoc(halfway, 850) > 0 or #J.GetEnemiesNearLoc(halfway, 850) > 0 then return false end
	end
	return true
end

local function CanFarmCamp(camp)
	local location = camp.cattr.location
	-- Do not spend the last of a low-health hero's escape budget on
	-- neutrals, especially if it just lost a fight near its exit path.
	if J.GetHP(bot) < 0.27 or J.GetHP(bot) < 0.42
		and (bot:WasRecentlyDamagedByAnyHero(5) or not J.Site.IsSmallCamp(camp.cattr)) then return false end
	if (recoveringLane or postWaveCampDistance) and (J.Site.IsEnemyCamp(camp.cattr)
		or GetUnitToLocationDistance(bot, location) > (postWaveCampDistance or 2600)) then return false end
	if postWaveCampDistance and postWaveOrigin and J.GetLocationToLocationDistance(location, postWaveOrigin) > postWaveCampDistance then return false end
	if not IsFarmLocationSafe(location) or not IsFarmPathSafe(location) then return false end
	-- After the map contracts, don't routinely walk across the river to
	-- a speculative camp. Reserve exposed resources for visible team pushes.
	if DotaTime() >= 25 * 60 and J.Site.IsEnemyCamp(camp.cattr)
		and (not IsLocationVisible(location) or #J.GetAlliesNearLoc(location, 1050) == 0) then return false end
	if postWaveCampDistance then
		local walk = GetUnitToLocationDistance(bot, location)
		local health = 0
		local visibleCamp = IsLocationVisible(location)
		local nearby = walk > 1100 and visibleCamp and GetUnitList(UNIT_LIST_NEUTRAL_CREEPS)
			or bot:GetNearbyNeutralCreeps(math.min(1600, walk + 500))
		for _, creep in ipairs(nearby) do
			if J.IsValid(creep) and not J.IsRoshan(creep) and GetUnitToLocationDistance(creep, location) <= 500 then
				health = health + creep:GetHealth()
			end
		end
		if health == 0 then
			if visibleCamp then return false end
			health = J.Site.IsSmallCamp(camp.cattr) and 790 or (J.Site.IsMediumCamp(camp.cattr) and 1350 or 2200)
		end
		local speed = math.max(1, bot:GetCurrentMovementSpeed())
		local damagePerSecond = math.max(1, J.GetLaningAttackDamage(bot) * 0.85 / math.max(0.2, bot:GetSecondsPerAttack()))
		local clear = health / damagePerSecond
		local returnWalk = J.GetLocationToLocationDistance(location, postWaveOrigin)
		if DotaTime() + (walk + returnWalk) / speed + clear + 1.5 > postWaveUntil then return false end
	end
	for i = 1, #GetTeamPlayers(team) do
		local ally = GetTeamMember(i)
		local claim = ally and ally ~= bot and ally.ohaFarmCampClaim
		if claim and ally:IsAlive() and claim.expires > DotaTime()
			and J.GetLocationToLocationDistance(claim.location, location) < 100 then return false end
		local campWork = ally and ally.ohaLaneCamp
		if campWork and ally:IsAlive() and campWork.expires > DotaTime()
			and J.GetLocationToLocationDistance(campWork.camp.location, location) < 100 then return false end
		local stack = ally and ally.ohaStackedCamp
		if stack and stack.owner ~= bot:GetPlayerID() and stack.expires > DotaTime()
			and J.GetLocationToLocationDistance(stack.location, location) < 100 then return false end
	end
	for _, ally in ipairs(J.GetAlliesNearLoc(location, 800)) do
		if ally ~= bot and J.IsValidHero(ally) and not ally:IsIllusion() then
			local target = ally:GetAttackTarget()
			if (J.IsFarming(ally) and GetUnitToLocationDistance(ally, location) <= 450)
			or (J.IsValid(target) and target:GetTeam() == TEAM_NEUTRAL
				and GetUnitToLocationDistance(target, location) <= 600) then
				return false
			end
		end
	end
	return true
end

local function FindFarmCamp()
	if preferedCamp ~= nil then
		if CanFarmCamp(preferedCamp) then return preferedCamp end
		preferedCamp, farmState = nil, FARM_STATE_NONE
		nextCampSearch = 0
	end
	if GameTime() < nextCampSearch then return nil end
	nextCampSearch = GameTime() + 1
	local camps = J.Role.availableCampTable or {}
	for _, ally in ipairs(J.GetAlliesNearLoc(bot:GetLocation(), 2400)) do
		local stack = ally.ohaStackedCamp
		if stack ~= nil and stack.owner == bot:GetPlayerID() and stack.expires > DotaTime()
			and GetUnitToLocationDistance(bot, stack.location) <= 2000 then
			for _, camp in ipairs(camps) do
				if J.GetLocationToLocationDistance(stack.location, camp.cattr.location) < 100 and CanFarmCamp(camp) then
					preferedCamp = camp
					return camp
				end
			end
		end
	end
	preferedCamp = J.Site.GetClosestNeutralSpwan(bot, camps)
	if preferedCamp ~= nil and not CanFarmCamp(preferedCamp) then
		local alternatives = {}
		for _, camp in ipairs(camps) do
			if camp ~= preferedCamp and CanFarmCamp(camp) then
				alternatives[#alternatives + 1] = camp
			end
		end
		preferedCamp = J.Site.GetClosestNeutralSpwan(bot, alternatives)
	end
	return preferedCamp
end

local function RefreshFarmCamps()
	local minute = math.floor((DotaTime() - 1) / 60)
	if minute > lastCampRefreshMinute then
		J.Role.availableCampTable, J.Role.campCount = J.Site.RefreshCamp(bot)
		lastCampRefreshMinute = minute
		nextCampSearch = 0
	end
end

local function HasJustClearedWave()
	local now = DotaTime()
	local wave = bot:GetNearbyLaneCreeps(900, true)
	if #wave > 0 then
		lastWaveLocation, lastWaveSeenAt, lastWaveCreeps = J.GetCenterOfUnits(wave), now, wave
		return false
	end
	if now - lastWaveSeenAt > 14 or lastWaveLocation == nil or GetUnitToLocationDistance(bot, lastWaveLocation) > 1100
		or not IsLocationVisible(lastWaveLocation) then return false end
	for _, creep in ipairs(lastWaveCreeps) do
		if not creep:IsNull() and creep:CanBeSeen() and creep:IsAlive() then return false end
	end
	return true
end

local function GetReturningWave()
	if postWaveOrigin == nil then return nil end
	local origin = GetAmountAlongLane(postWaveLane, postWaveOrigin)
	local direction = team == TEAM_RADIANT and 1 or -1
	local wave, earliest = nil, math.huge
	for _, creep in ipairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS)) do
		if J.IsValid(creep) and creep:GetTeam() == GetOpposingTeam() and GetUnitToLocationDistance(creep, postWaveOrigin) < 4500 then
			local name = creep:GetUnitName()
			if string.find(name, 'npc_dota_creep_', 1, true) or string.find(name, '_siege', 1, true) then
				local point = creep:GetLocation()
				local track = GetAmountAlongLane(postWaveLane, point)
				if track.distance <= 475 and (track.amount - origin.amount) * direction >= -0.035 then
					local eta = math.max(0, GetUnitToLocationDistance(creep, postWaveOrigin) - 650)
						/ math.max(280, creep:GetCurrentMovementSpeed())
					if eta < earliest then wave, earliest = point, eta end
				end
			end
		end
	end
	if wave ~= nil then
		postWaveUntil = math.min(postWaveUntil, DotaTime() + earliest)
		if earliest <= 1 and IsFarmWaveAvailable(wave) and IsFarmPathSafe(wave) then return wave end
	end
	local returnTime = GetUnitToLocationDistance(bot, postWaveOrigin) / math.max(1, bot:GetCurrentMovementSpeed())
	if DotaTime() + returnTime + 1 >= postWaveUntil and IsFarmWaveAvailable(postWaveOrigin)
		and IsFarmPathSafe(postWaveOrigin) then return postWaveOrigin end
end

local function GetVisibleHomeWaves()
	if DotaTime() - waveScanAt < 1 then return visibleWaves end
	waveScanAt, visibleWaves = DotaTime(), {}
	for _, creep in ipairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS)) do
		if J.IsValid(creep) and J.IsInAllyArea(creep) and GetUnitToUnitDistance(bot, creep) <= 3800 then
			local name = creep:GetUnitName()
			if string.find(name, 'npc_dota_creep_', 1, true) or string.find(name, '_siege', 1, true) then
				local pack
				for _, wave in ipairs(visibleWaves) do
					if GetUnitToLocationDistance(creep, wave.location) <= 650 then pack = wave; break end
				end
				if pack then pack.count = pack.count + 1
				else visibleWaves[#visibleWaves + 1] = {location = creep:GetLocation(), count = 1} end
			end
		end
	end
	return visibleWaves
end

local function FindRecoveryRoute(maxLaneDistance, desire, excludedLane)
	recoveringLane = true
	local nearbyWave = bot:GetNearbyLaneCreeps(1600, true)
	if #nearbyWave > 0 then
		local location = J.GetCenterOfUnits(nearbyWave)
		if IsFarmWaveAvailable(location) and IsFarmPathSafe(location) then farmLaneLocation = location end
	end
	if farmLaneLocation == nil and maxLaneDistance ~= nil then
		for _, wave in ipairs(GetVisibleHomeWaves()) do
			local distance = GetUnitToLocationDistance(bot, wave.location)
			if wave.count >= 2 and distance < maxLaneDistance
				and (excludedLane == nil or GetAmountAlongLane(excludedLane, wave.location).distance > 550)
				and IsFarmWaveAvailable(wave.location) and IsFarmPathSafe(wave.location) then
				farmLaneLocation, maxLaneDistance = wave.location, distance
			end
		end
	end
	local camp = farmLaneLocation == nil and FindFarmCamp() or nil
	local location = farmLaneLocation or (camp and camp.cattr.location)
	if location ~= nil then
		bot.farmLocation = location
		return desire
	end
	recoveringLane = false
	tradingTowerLocation = nil
	return BOT_MODE_DESIRE_NONE
end

local function GetOuterTowerRecoveryDesire()
	local trade = bot.ohaOuterTowerTrade
	local now = DotaTime()
	if trade == nil or trade.expires <= now or (bot.ohaOuterTowerHoldUntil or 0) > now
		or not J.IsCore(bot) or J.GetHP(bot) < 0.55 or bot:WasRecentlyDamagedByAnyHero(2)
		or J.IsInTeamFight(bot, 1200)
	then
		bot.ohaOuterFarmClaim = nil
		return BOT_MODE_DESIRE_NONE
	end

	tradingTowerLocation = trade.location
	local desire = FindRecoveryRoute(3800, 0.6, trade.lane)
	if desire > BOT_MODE_DESIRE_NONE then
		bot.ohaOuterFarmClaim = {location = bot.farmLocation, expires = now + 3}
	else
		bot.ohaOuterFarmClaim = nil
	end
	return desire
end

local function UpdateCarryLaneRecovery()
	local now = DotaTime()
	if now < (J.IsModeTurbo() and 150 or 180) or not J.IsInLaningPhase(bot) or not bot:IsAlive()
		or J.GetPosition(bot) ~= 1 or J.GetHP(bot) >= 0.66 or not bot:WasRecentlyDamagedByAnyHero(5) then return end
	local lane = bot:GetAssignedLane()
	if lane ~= LANE_TOP and lane ~= LANE_BOT then return end
	local front = GetLaneFrontLocation(team, lane, 0)
	local tower = GetTower(team, laneTierOne[lane])
	local underFireAtTower = J.IsValidBuilding(tower) and J.IsInRange(bot, tower, 1600)
	local attackers = math.max(#J.GetLastSeenEnemiesNearLoc(front, 1700), #J.GetEnemiesNearLoc(bot:GetLocation(), 1250))
	if (GetUnitToLocationDistance(bot, front) <= 2600 or underFireAtTower)
		and (attackers >= 2 or attackers == 1 and J.GetHP(bot) <= 0.46 and underFireAtTower) then
		-- Several of the replay's return walks outlasted the old 50s marker.
		-- Budget one real walk back plus healing, not a permanent farm override.
		local walkBack = bot:DistanceFromFountain() / math.max(1, bot:GetCurrentMovementSpeed())
		bot.ohaCarryLaneRecoveryUntil = now + math.min(85, math.max(50, walkBack * 1.4 + 25))
	end
end

local function GetLaningRecoveryDesire()
	local position = J.GetPosition(bot)
	local turbo = J.IsModeTurbo()
	local time = DotaTime()
	local recoveryStart = turbo and 5 * 60 or 7 * 60
	local displaced = position == 1 and (bot.ohaCarryLaneRecoveryUntil or 0) > time
	local carryStart = displaced and (turbo and 150 or 180) or (turbo and 210 or 270)
	if time < (position <= 2 and carryStart or recoveryStart) or time >= (turbo and 14 * 60 or 20 * 60)
		or position > 3 or bot:GetLevel() < (position == 1 and 3 or 4) or bot:GetNetWorth() >= 8000
		or J.GetHP(bot) < 0.45 or (bot:WasRecentlyDamagedByAnyHero(2) and not J.WeAreStronger(bot, 1200))
		or GetGameMode() == GAMEMODE_MO or GetGameMode() == GAMEMODE_1V1MID
	then return BOT_MODE_DESIRE_NONE end

	local lane = bot:GetAssignedLane()
	local towerId = laneTierOne[lane]
	if towerId == nil then return BOT_MODE_DESIRE_NONE end
	local tower = GetTower(team, towerId)
	-- A recovering core should pick up a visible, reachable wave on its own
	-- side before going to a nearby camp. Leave normal on-lane timing alone.
	if time < (turbo and 8 * 60 or 10 * 60) and J.IsValidBuilding(tower)
		and J.GetHP(bot) >= 0.55 and (displaced or GetAmountAlongLane(lane, bot:GetLocation()).distance > 950) then
		local bestDistance = 3800
		local towerTrack = GetAmountAlongLane(lane, tower:GetLocation())
		local direction = team == TEAM_RADIANT and 1 or -1
		for _, wave in ipairs(GetVisibleHomeWaves()) do
			local track = GetAmountAlongLane(lane, wave.location)
			local distance = GetUnitToLocationDistance(bot, wave.location)
			if (wave.count >= 2 or (displaced and wave.count >= 1 and distance <= 1600))
				and track.distance <= 475
				and (track.amount - towerTrack.amount) * direction <= 0.07
				and distance < bestDistance and IsFarmWaveAvailable(wave.location) and IsFarmPathSafe(wave.location) then
				farmLaneLocation, bestDistance = wave.location, distance
			end
		end
		if farmLaneLocation ~= nil then
			recoveringLane, bot.farmLocation = true, farmLaneLocation
			return 0.71
		end
	end
	if J.IsValidBuilding(tower) and not displaced then
		-- Before ten minutes, only a displaced carry should leave an intact lane to farm.
		if position ~= 1 and time < (turbo and 8 * 60 or 10 * 60) then return BOT_MODE_DESIRE_NONE end
		local laneFront = GetLaneFrontLocation(team, lane, 0)
		local enemies = J.GetLastSeenEnemiesNearLoc(laneFront, 1600)
		local outmatched = not J.WeAreStronger(bot, 1600)
		local harassed = bot:WasRecentlyDamagedByAnyHero(6)
		local outnumbered = #enemies >= 2 and #enemies > #J.GetAlliesNearLoc(laneFront, 1600)
		if time < recoveryStart and not outnumbered and not (harassed and outmatched) then return BOT_MODE_DESIRE_NONE end
		if #enemies == 0 or (#enemies == 1 and not (harassed and outmatched))
			or (#enemies >= 2 and not outnumbered and not harassed and not outmatched) then
			return BOT_MODE_DESIRE_NONE
		end
	end

	return FindRecoveryRoute(2900, displaced and 0.67 or BOT_MODE_DESIRE_MODERATE)
end

local shelterFarmSince, shelterFarmTask, shelterFarmScanAt = nil, nil, 0
local shelterFarmActive = false
local function GetShelterCampCreeps(camp, neutrals)
	local loc, creeps = camp.cattr.location, {}
	local health = 0
	for _, creep in ipairs(neutrals) do
		if J.IsValid(creep) and creep:CanBeSeen() and not J.IsRoshan(creep) and not creep:IsAncientCreep()
			and GetUnitToLocationDistance(creep, loc) <= 520 then
			creeps[#creeps + 1] = creep
			health = health + creep:GetHealth()
		end
	end
	if health > 1750 then return {} end
	return creeps
end

local function CanUseShelteredResource(tower, lane, started, camp)
	if not J.IsValidBuilding(tower) or J.GetHP(bot) < 0.64 or J.IsRetreating(bot)
		or bot:WasRecentlyDamagedByAnyHero(3) or J.IsGoingOnSomeone(bot) or J.IsInTeamFight(bot, 1250)
		or (bot.ohaLaneSupply and bot.ohaLaneSupply.waitUntil > DotaTime())
		or #J.GetEnemiesNearLoc(bot:GetLocation(), 1000) > 0 then return false end
	if J.HasPendingLaningLastHit(bot) then return false end
	local towerPoint = tower:GetLocation()
	if not J.IsInRange(bot, tower, 2300) then return false end
	local window = J.GetOuterTowerThreat(tower, lane)
	local waveReady = window.underAttack
	for _, creep in ipairs(bot:GetNearbyLaneCreeps(1450, true)) do
		if J.IsValid(creep) and J.IsInRange(creep, tower, 1100) then waveReady = true; break end
	end
	local distance = camp and J.GetLocationToLocationDistance(camp.cattr.location, towerPoint) or 0
	local returnETA = distance / math.max(250, bot:GetCurrentMovementSpeed()) * 1.15
	return LaneResourceWindow.ShouldUse({
		ready = true, coveredWave = waveReady,
		towerUnderAttack = window.underAttack or window.briefHold or (window.count or 0) >= 2 and (window.waveSize or 0) >= 2,
		hasNextWave = (window.waveSize or 0) > 0, waveETA = window.eta or 0, returnETA = returnETA,
		waited = DotaTime() - started, safe = true, campConfirmed = true,
	})
end

local function GetShelteredResourceDesire()
	local now = DotaTime()
	if now < 5 * 60 or not J.IsCore(bot) or not J.IsInLaningPhase(bot)
		or not J.GetLaningHoldTower or GetGameMode() == GAMEMODE_MO or GetGameMode() == GAMEMODE_1V1MID then
		shelterFarmSince, shelterFarmTask = nil, nil
		return BOT_MODE_DESIRE_NONE
	end
	local lane = bot:GetAssignedLane()
	local task = shelterFarmTask
	if task and (task.expires <= now or task.lane ~= lane) then
		shelterFarmSince, shelterFarmTask = nil, nil
		task = nil
	end
	local tower = task and task.tower or J.GetLaningHoldTower(bot)
	if not J.IsValidBuilding(tower) then
		shelterFarmSince, shelterFarmTask = nil, nil
		return BOT_MODE_DESIRE_NONE
	end
	if shelterFarmSince == nil then shelterFarmSince = now end
	-- Check safety without starting the ten-second timer during an active siege.
	if not CanUseShelteredResource(tower, lane, now - 10, task and task.camp) then
		shelterFarmSince, shelterFarmTask = nil, nil
		return BOT_MODE_DESIRE_NONE
	end
	if now - shelterFarmSince < 10 then return BOT_MODE_DESIRE_NONE end
	recoveringLane = true
	if task then
		if CanFarmCamp(task.camp) and #GetShelterCampCreeps(task.camp, bot:GetNearbyNeutralCreeps(1600)) > 0 then
			bot.farmLocation = task.camp.cattr.location
			shelterFarmActive = true
			return 0.84
		end
		shelterFarmSince, shelterFarmTask = nil, nil
		recoveringLane = false
		return BOT_MODE_DESIRE_NONE
	end
	if now < shelterFarmScanAt then recoveringLane = false; return BOT_MODE_DESIRE_NONE end
	shelterFarmScanAt = now + 1
	local nearest, nearestDistance = nil, 1450
	local neutrals = bot:GetNearbyNeutralCreeps(1600)
	for _, camp in ipairs(J.Role.availableCampTable or {}) do
		local point = camp.cattr.location
		local distance = GetUnitToLocationDistance(bot, point)
		if distance < nearestDistance and J.GetLocationToLocationDistance(point, tower:GetLocation()) <= 1650
			and #GetShelterCampCreeps(camp, neutrals) > 0 and CanFarmCamp(camp)
			and CanUseShelteredResource(tower, lane, shelterFarmSince, camp) then
			nearest, nearestDistance = camp, distance
		end
	end
	if nearest == nil then recoveringLane = false; return BOT_MODE_DESIRE_NONE end
	shelterFarmTask = {camp=nearest, tower=tower, lane=lane, expires=now + 18}
	bot.farmLocation = nearest.cattr.location
	shelterFarmActive = true
	if Customize.TraceLaneDecisions then print('[OHA lane] sheltered-camp', now, bot:GetPlayerID(), lane) end
	return 0.84
end

local function ThinkShelteredResource(task)
	recoveringLane = true
	if DotaTime() >= task.expires or not CanUseShelteredResource(task.tower, task.lane, shelterFarmSince, task.camp)
		or not CanFarmCamp(task.camp) then
		shelterFarmTask, shelterFarmSince, bot.ohaFarmCampClaim = nil, nil, nil
		CancelFarmOrder()
		return
	end
	local target = J.Site.FindFarmNeutralTarget(GetShelterCampCreeps(task.camp, bot:GetNearbyNeutralCreeps(1600)))
	if J.IsValid(target) then
		bot.ohaFarmCampClaim = {location=task.camp.cattr.location, expires=DotaTime()+3}
		if J.IsInRange(bot, target, bot:GetAttackRange() + 100) then AttackFarmTarget(target)
		else MoveToFarm(target:GetLocation()) end
	else
		shelterFarmTask, shelterFarmSince, bot.ohaFarmCampClaim = nil, nil, nil
		CancelFarmOrder()
	end
end

local function GetBetweenWaveFarmDesire(bNotClone)
	local now = DotaTime()
	if not bNotClone or not J.IsCore(bot) or now < (J.IsModeTurbo() and 210 or 270) then return BOT_MODE_DESIRE_NONE end
	local cleared = postWaveOrigin == nil and HasJustClearedWave()
	if not cleared and postWaveOrigin == nil then return BOT_MODE_DESIRE_NONE end
	if J.GetHP(bot) < 0.55 or #J.GetEnemiesNearLoc(bot:GetLocation(), 1600) > 0
		or bot:WasRecentlyDamagedByAnyHero(3) or J.IsInTeamFight(bot, 1800)
		or (J.IsPushing(bot) and J.IsValidBuilding(bot:GetNearbyTowers(1600, true)[1]))
		or J.IsGoingOnSomeone(bot) or GetGameMode() == GAMEMODE_MO or GetGameMode() == GAMEMODE_1V1MID then
		postWaveOrigin = nil
		return BOT_MODE_DESIRE_NONE
	end
	if cleared then
		local closestDistance = math.huge
		for _, lane in ipairs(nLaneList) do
			local track = GetAmountAlongLane(lane, lastWaveLocation)
			if track.distance < closestDistance then closestDistance, postWaveLane = track.distance, lane end
		end
		if closestDistance > 550 then return BOT_MODE_DESIRE_NONE end
		postWaveOrigin, postWaveUntil = lastWaveLocation, lastWaveSeenAt + 23
	end

	recoveringLane = true
	postWaveCampDistance = math.min(2400, bot:GetCurrentMovementSpeed() * 6)
	local returning = GetReturningWave()
	if returning ~= nil then
		if returning == postWaveOrigin and GetUnitToLocationDistance(bot, returning) <= 650 then
			postWaveOrigin, postWaveCampDistance, recoveringLane = nil, nil, false
			lastWaveLocation = nil
			return BOT_MODE_DESIRE_NONE
		end
		farmLaneLocation, bot.farmLocation = returning, returning
		return 0.62
	end
	local desire = FindRecoveryRoute(nil, 0.62)
	if desire <= BOT_MODE_DESIRE_NONE then
		postWaveOrigin, postWaveCampDistance = nil, nil
	end
	return desire
end

local function CanCollectWave(location, distance)
	if IsReleasedFarmLane(location) or not IsFarmLocationSafe(location) or not IsFarmPathSafe(location)
		or #J.GetLastSeenEnemiesNearLoc(location, 1400) > 0 then return false end
	local owner=J.GetScheduledFarmWaveOwner and J.GetScheduledFarmWaveOwner(bot,location)
	if owner~=nil then return owner==bot:GetPlayerID() end
	for _, ally in ipairs(J.GetAlliesNearLoc(location, math.max(1250, distance + 400))) do
		if CanReserveWave(ally) then
			local claim = ally.ohaWaveClaim
			if claim and claim.expires > DotaTime() and J.GetLocationToLocationDistance(location, claim.location) < 700 then return false end
			local other = GetUnitToLocationDistance(ally, location)
			local coreOwnsWave = J.IsCore(ally) and (other <= 1250 or J.IsFarming(ally) and other <= distance + 300)
			local closerCollector = other + 150 < distance and J.IsFarming(ally)
			if coreOwnsWave or closerCollector then return false end
		end
	end
	return true
end

-- Prepare one unattended side wave before a shared push. Do not send a
-- hero who is already part of the push or turn this into a split-push mode.
local function SideWaveUnit(unit)
	if not J.IsValid(unit) or not unit:CanBeSeen() then return false end
	local name = unit:GetUnitName()
	return string.find(name, 'npc_dota_creep_', 1, true) ~= nil
		or name == 'npc_dota_goodguys_siege' or name == 'npc_dota_badguys_siege'
end

local function SideWaveMidpoint(a, b)
	return Vector((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2)
end

local function SideWavePathSafe(a, b, radius)
	local mid = SideWaveMidpoint(a, b)
	return IsLocationPassable(b) and IsLocationPassable(mid)
		and J.CanCommitToLaneTeleport(bot, b, true, radius)
		and J.CanCommitToLaneTeleport(bot, mid, true, radius)
end

local function SideWaveHeroReady(hero)
	return J.IsValidHero(hero) and not hero:IsIllusion() and not J.IsMeepoClone(hero)
		and not hero:HasModifier('modifier_arc_warden_tempest_double')
		and not J.IsRetreating(hero) and not J.IsDisabled(hero) and not hero:IsChanneling()
		and not hero:HasModifier('modifier_teleporting')
end

local function GetSideWaveRally(members)
	local pushModes = {[LANE_TOP] = BOT_MODE_PUSH_TOWER_TOP, [LANE_MID] = BOT_MODE_PUSH_TOWER_MID, [LANE_BOT] = BOT_MODE_PUSH_TOWER_BOT}
	local best, bestCount = nil, 2
	for _, lane in ipairs(nLaneList) do
		local mode = pushModes[lane]
		if mode ~= nil then
			for _, lead in ipairs(members) do
				if SideWaveHeroReady(lead) and lead:GetActiveMode() == mode and lead:GetActiveModeDesire() >= 0.64
					and GetAmountAlongLane(lane, lead:GetLocation()).distance <= 800 then
					local n, core = 0, false
					for _, ally in ipairs(members) do
						if SideWaveHeroReady(ally) and ally:GetActiveMode() == mode and ally:GetActiveModeDesire() >= 0.64
							and GetUnitToUnitDistance(ally, lead) <= 1250 then
							n = n + 1
							core = core or J.GetPosition(ally) <= 2
						end
					end
					if core and n > bestCount and not lead:WasRecentlyDamagedByAnyHero(2) then
						best, bestCount = {lane = lane, anchor = lead, location = lead:GetLocation()}, n
					end
				end
			end
		end
	end
	if not best or not J.CanCommitToLaneTeleport(bot, best.location, true, 1800) then return nil end
	for _, ally in ipairs(members) do
		if J.IsValidHero(ally) and GetUnitToUnitDistance(ally, best.anchor) <= 1550
			and (ally:WasRecentlyDamagedByAnyHero(2) or ally:GetActiveMode() == BOT_MODE_ATTACK) then return nil end
	end
	return best
end

local function GetSideWaveNudge(lane, point, pack, friendly)
	local tierOne = laneTierOne[lane]
	if not tierOne then return nil end
	local home, away = GetTower(team, tierOne), GetTower(GetOpposingTeam(), tierOne)
	if not home or home:IsNull() or not home:IsAlive() or not away or away:IsNull() or not away:IsAlive() then return nil end
	if GetUnitToLocationDistance(home, point) < 1300 or GetUnitToLocationDistance(away, point) < 1300 then return nil end
	local homeTrack = GetAmountAlongLane(lane, home:GetLocation()).amount
	local awayTrack = GetAmountAlongLane(lane, away:GetLocation()).amount
	local span = awayTrack - homeTrack
	if math.abs(span) < 0.06 then return nil end
	local progress = (GetAmountAlongLane(lane, point).amount - homeTrack) / span
	if progress < 0.34 or progress > 0.66 then return nil end

	local function sample(units, hostile)
		local info = {melee = 0, meleeHP = 0, ranged = 0, siege = 0}
		for _, unit in ipairs(units) do
			-- Count the wave already fighting, not the approaching reinforcements.
			if GetUnitToLocationDistance(unit, point) <= 730 then
				local name = unit:GetUnitName()
				if name:find('_upgraded', 1, true) then return nil end
				if name:find('_siege', 1, true) then
					info.siege = info.siege + 1
					local target = unit:GetAttackTarget()
					if hostile and J.IsValidBuilding(target) and target:GetTeam() == team then return nil end
				elseif name:find('_ranged', 1, true) then
					info.ranged = info.ranged + 1
					info.rangedUnit = unit
				elseif name:find('_melee', 1, true) or name:find('_flagbearer', 1, true) then
					info.melee = info.melee + 1
					info.meleeHP = info.meleeHP + unit:GetHealth()
				else
					return nil
				end
			end
		end
		return info
	end

	local theirs, ours = sample(pack, true), sample(friendly, false)
	if theirs and ours and ours.melee >= 2 and ours.melee == theirs.melee
		and ours.siege == theirs.siege and ours.siege <= 1 and ours.ranged == 1 and theirs.ranged == 1
		and ours.meleeHP >= theirs.meleeHP * 0.80 and ours.meleeHP <= theirs.meleeHP * 1.25
		and ours.rangedUnit:GetHealth() >= ours.rangedUnit:GetMaxHealth() * 0.45
		and GetUnitToUnitDistance(theirs.rangedUnit, away) > 950 then
		return theirs.rangedUnit
	end
end

local function GetRallySideWavePlan(onlyLane)
	local now = DotaTime()
	if now < 14 * 60 or J.GetHP(bot) < 0.55 or J.IsInTeamFight(bot, 1200)
		or bot:WasRecentlyDamagedByAnyHero(2) then return nil end
	local members = {}
	for i = 1, #GetTeamPlayers(team) do
		local ally = GetTeamMember(i)
		if J.IsValidHero(ally) then
			local claim = ally.ohaRallySideWave
			if ally ~= bot and claim and claim.expires > now then return nil end
			members[#members + 1] = ally
		end
	end
	local rally = GetSideWaveRally(members)
	if not rally then return nil end
	local candidate
	local direction = team == TEAM_RADIANT and 1 or -1
	for _, lane in ipairs({LANE_TOP, LANE_BOT}) do
		if lane ~= rally.lane and (onlyLane == nil or onlyLane == lane) then
			local point = GetLaneFrontLocation(team, lane, 0)
			local own, opposing = GetAncient(team), GetAncient(GetOpposingTeam())
			local onHomeSide = own and opposing and GetUnitToLocationDistance(own, point) + 550 < GetUnitToLocationDistance(opposing, point)
			if own and opposing and IsLocationVisible(point) and SideWavePathSafe(point, rally.location, 1250)
				and J.CanCommitToLaneTeleport(bot, point, true, 1350) then
				local pack, friendly, health, support = {}, {}, 0, 0
				local front = GetAmountAlongLane(lane, point).amount * direction
				for _, creep in ipairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS)) do
					if SideWaveUnit(creep) and GetUnitToLocationDistance(creep, point) <= 730
						and GetAmountAlongLane(lane, creep:GetLocation()).distance <= 420 then
						pack[#pack + 1] = creep
						health = health + creep:GetHealth()
					end
				end
				for _, creep in ipairs(GetUnitList(UNIT_LIST_ALLIED_CREEPS)) do
					if SideWaveUnit(creep) and GetUnitToLocationDistance(creep, point) <= 1050 then
						local track = GetAmountAlongLane(lane, creep:GetLocation())
						local ahead = track.amount * direction - front
						if track.distance <= 420 and ahead < 0.043 and ahead > -0.060 then
							support = support + 1
							friendly[#friendly + 1] = creep
						end
					end
				end
				local ranged = #pack >= 3 and support >= 3 and GetSideWaveNudge(lane, point, pack, friendly) or nil
				if #pack >= 2 and support >= 2 and (ranged or onHomeSide) then
					for _, hero in ipairs(members) do
						local active = hero:GetActiveMode()
						if hero:IsBot() and SideWaveHeroReady(hero) and J.GetPosition(hero) >= 3 and J.GetHP(hero) >= 0.62
							and not hero:IsDisarmed() and not hero:IsRooted()
							and active ~= BOT_MODE_ATTACK and active ~= BOT_MODE_TEAM_ROAM and active ~= BOT_MODE_WARD
							and active ~= BOT_MODE_RUNE and active ~= BOT_MODE_SECRET_SHOP and active ~= BOT_MODE_OUTPOST
							and not J.IsDefending(hero) and not J.IsPushing(hero) and not J.IsDoingRoshan(hero) and not J.IsDoingTormentor(hero)
							and not J.IsGoingOnSomeone(hero) and not hero:WasRecentlyDamagedByAnyHero(2)
							and ((hero.ohaNextRallySideWaveAt or 0) <= now
								or (hero.ohaRallySideWave and hero.ohaRallySideWave.expires > now))
							and (hero.ohaOuterTowerHoldUntil or 0) <= now and GetUnitToUnitDistance(hero, rally.anchor) >= 1150 then
							local speed = math.max(1, hero:GetCurrentMovementSpeed())
							local toWave = GetUnitToLocationDistance(hero, point)
							local toRally = J.GetLocationToLocationDistance(point, rally.location)
							local damage = math.max(1, hero:GetAttackDamage() / math.max(0.3, hero:GetSecondsPerAttack()))
							local clear = health / (damage * 0.82 + support * 24)
							local targetNear = true
							if ranged then
								-- No credit for hoped-for ally hits or a walk behind the wave.
								local perHit = ranged:GetActualIncomingDamage(hero:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
								clear = math.ceil(ranged:GetHealth() / math.max(1, perHit)) * math.max(0.3, hero:GetSecondsPerAttack())
								targetNear = GetUnitToUnitDistance(hero, ranged) <= hero:GetAttackRange() + 225 and clear <= 2.5
							end
							local returnETA = 1.2 * math.max(0, toRally - 550) / speed
							local total = toWave * 1.17 / speed + clear + returnETA
							if targetNear and toWave <= 900 and clear <= 8 and returnETA <= 8 and total <= 15
								and SideWavePathSafe(hero:GetLocation(), point, 1050)
								and (not candidate or total < candidate.cost or total == candidate.cost and hero:GetPlayerID() < candidate.hero:GetPlayerID()) then
								candidate = {hero = hero, lane = lane, mainLane = rally.lane, location = point,
									rally = rally.anchor, targetPack = pack, ranged = ranged, cost = total}
							end
						end
					end
				end
			end
		end
	end
	if candidate and candidate.hero == bot then return candidate end
end

local function GetSideWaveReturnPoint(task)
	local anchor = task.rally
	if not J.IsValidHero(anchor) or J.GetHP(bot) < 0.55 or bot:WasRecentlyDamagedByAnyHero(2)
		or GetUnitToUnitDistance(bot, anchor) <= 900 or #J.GetAlliesNearLoc(anchor:GetLocation(), 1350) < 2
		or #J.GetEnemiesNearLoc(bot:GetLocation(), 900) > 0 then return nil end
	local point = J.AdjustLocationWithOffsetTowardsFountain(anchor:GetLocation(), 525)
	if SideWavePathSafe(bot:GetLocation(), point, 850) then return point end
end

local function AttackSideWave(plan)
	if plan.ranged then
		if not SideWaveUnit(plan.ranged) or GetUnitToUnitDistance(bot, plan.ranged) > bot:GetAttackRange() + 225 then return false end
		if bot:GetAttackTarget() ~= plan.ranged or not (J.IsAttacking and J.IsAttacking(bot)) then AttackFarmTarget(plan.ranged) end
		return true
	end
	local best, bestScore = nil, -math.huge
	for _, creep in ipairs(plan.targetPack) do
		if SideWaveUnit(creep) and GetUnitToLocationDistance(creep, plan.location) <= 730 then
			local name = creep:GetUnitName()
			local priority = string.find(name, '_siege', 1, true) and 900
				or string.find(name, '_ranged', 1, true) and 650 or 0
			local score = priority - creep:GetHealth() * 0.6 - GetUnitToUnitDistance(bot, creep) * 0.15
			if score > bestScore then best, bestScore = creep, score end
		end
	end
	if not best then return false end
	if GetUnitToUnitDistance(bot, best) > bot:GetAttackRange() + 275 then
		if GetUnitToLocationDistance(bot, plan.location) > 300 then MoveToFarm(plan.location); return true end
		return false
	end
	if bot:GetAttackTarget() == best and J.IsAttacking and J.IsAttacking(bot) then return true end
	AttackFarmTarget(best)
	return true
end

local function GetUnclaimedWaveDesire()
	if DotaTime() < 8 * 60 or J.IsCore(bot) and J.IsInLaningPhase(bot) or J.GetHP(bot) < 0.55
		or J.IsInTeamFight(bot, 1200) or J.IsGoingOnSomeone(bot) or bot:WasRecentlyDamagedByAnyHero(2)
		or J.IsPushing(bot) and J.IsValidBuilding(bot:GetNearbyTowers(1600, true)[1]) then return BOT_MODE_DESIRE_NONE end
	local nearby = bot:GetNearbyLaneCreeps(1000, true)
	local best, bestDistance = nil, 2801
	if #nearby >= 3 and J.IsInAllyArea(nearby[1]) then
		local point = J.GetCenterOfUnits(nearby)
		if CanCollectWave(point, GetUnitToLocationDistance(bot, point)) then best = point end
	end
	if best == nil then
		for _, wave in ipairs(GetVisibleHomeWaves()) do
			local distance = GetUnitToLocationDistance(bot, wave.location)
			if wave.count >= (distance < 1700 and 2 or 3) and distance < bestDistance
				and CanCollectWave(wave.location, distance) then best, bestDistance = wave.location, distance end
		end
	end
	if best == nil then return BOT_MODE_DESIRE_NONE end
	collectingWave, recoveringLane = true, true
	farmLaneLocation, bot.farmLocation = best, best
	if (bot.ohaIdleRecoveryUntil or 0) > DotaTime() then return 0.72 end
	return J.IsCore(bot) and 0.62 or 0.49
end

function GetDesire()
	-- local cacheKey = 'GetFarmDesire'..tostring(bot:GetPlayerID())
	-- local cachedVar = J.Utils.GetCachedVars(cacheKey, 0.4)
	-- if DotaTime() > 30 and cachedVar ~= nil then return cachedVar end
	local res = GetDesireHelper()
	-- J.Utils.SetCachedVars(cacheKey, res)
	return res
end

function GetDesireHelper()
	shelterFarmActive = false
	idleRally, collectingWave = nil, false
	sideWaveDesire = nil
	farmLaneLocation = nil
	recoveringLane = false
	tradingTowerLocation = nil
	postWaveCampDistance = nil
	-- Utils.PrintPings(0.15)

	if DotaTime() - CleanupCachedVarsTime > Utils.CachedVarsCleanTime then
		Utils.CleanupCachedVars()
		CleanupCachedVarsTime = DotaTime()
	end

    J.Utils['GameStates'] = J.Utils['GameStates'] or {}
    J.Utils['GameStates']['defendPings'] = J.Utils['GameStates']['defendPings'] or { pingedTime = GameTime() }
    if GameTime() - J.Utils['GameStates']['defendPings'].pingedTime <= 5.0 then
		return BOT_MODE_DESIRE_NONE
	end

	if bot:IsAlive()
	then
		if runTime ~= 0
			and DotaTime() < runTime + shouldRunTime
		then
			return BOT_MODE_DESIRE_ABSOLUTE * 1.1;
		else
			runTime = 0;
			runMode = false;
		end
		
		UpdateCarryLaneRecovery()
		shouldRunTime = X.ShouldRun(bot);
		if shouldRunTime ~= 0
		then
			if runTime == 0 then 
				runTime = DotaTime(); 
				runMode = true;
				preferedCamp = nil;
				bot:Action_ClearActions(true);
				issuedFarmOrder = false
			end
			return BOT_MODE_DESIRE_ABSOLUTE * 1.1;
		end
	end

	if not bInitDone
	then
		bInitDone = true
		beNormalFarmer = J.GetPosition(bot) == 3
		beHighFarmer = J.GetPosition(bot) == 2
	end

	local LoneDruid = J.CheckLoneDruid()
    local botActiveMode = bot:GetActiveMode()
	local botActiveModeDesire = bot:GetActiveModeDesire()
    local bAlive = bot:IsAlive()
	local bNotClone = not bot:HasModifier('modifier_arc_warden_tempest_double') and not J.IsMeepoClone(bot)
	local retreating = botActiveMode == BOT_MODE_RETREAT and botActiveModeDesire > 0
	local readyAtBase = retreating and bot:DistanceFromFountain() < 1250 and J.GetHP(bot) >= 0.88 and J.GetMP(bot) >= 0.65
		and #J.GetEnemiesNearLoc(bot:GetLocation(), 1800) == 0 and #J.GetLastSeenEnemiesNearLoc(bot:GetLocation(), 1800) == 0

	-- Early exits first (cheap checks before expensive queries)
    if not bAlive
	or (J.IsDoingRoshan(bot) and bNotClone)
	or (J.IsDoingTormentor(bot) and bNotClone)
    or DotaTime() < 50
    or (botActiveModeDesire > 0 and botActiveMode == BOT_MODE_SECRET_SHOP)
    or (retreating and not readyAtBase)
    or (botActiveModeDesire > 0 and (bot.ohaIdleRecoveryUntil or 0) <= DotaTime()
		and (botActiveMode == BOT_MODE_RUNE or botActiveMode == BOT_MODE_WARD or botActiveMode == BOT_MODE_OUTPOST))
    then
        return BOT_MODE_DESIRE_NONE
    end
	if ShouldYieldForBaseDefense() then
		teamTime = DotaTime()
		return BOT_MODE_DESIRE_NONE
	end
	if (bot.ohaOuterTowerHoldUntil or 0) > DotaTime()
		or (J.GetPostFightDuty and J.GetPostFightDuty(bot)) then return BOT_MODE_DESIRE_NONE end
	RefreshFarmCamps()
	local tradeDesire = GetOuterTowerRecoveryDesire()
	if tradeDesire > BOT_MODE_DESIRE_NONE then return tradeDesire end
	local now = DotaTime()
	if sideWaveTask then
		sideWaveDesire = sideWaveTask
		return 0.73
	end
	if (bot.ohaNextRallySideWaveAt or 0) <= now then
		if now < sideWaveScanAt or now - sideWaveScanAt >= 0.45 then
			sideWaveScanAt, sideWaveCandidate = now, GetRallySideWavePlan()
		end
		sideWaveDesire = sideWaveCandidate
		if sideWaveDesire then return 0.73 end
	end
	local unclaimedWave = GetUnclaimedWaveDesire()
	if unclaimedWave > BOT_MODE_DESIRE_NONE then return unclaimedWave end
	if (bot.ohaIdleRecoveryUntil or 0) > DotaTime() and J.GetHP(bot) >= 0.55
		and not J.IsInTeamFight(bot, 1200) and not J.IsGoingOnSomeone(bot) then
		if J.IsCore(bot) then
			local idleDesire = FindRecoveryRoute(3800, 0.65)
			if idleDesire > BOT_MODE_DESIRE_NONE then return idleDesire end
		end
		if bot.ohaIdleRecoveryOrigin and GetUnitToLocationDistance(bot, bot.ohaIdleRecoveryOrigin) < 700 then
			local ally = J.GetClosestAlly(bot, 3500, true)
			local rally = ally and GetUnitToUnitDistance(bot, ally) > 650 and ally:GetLocation() or J.GetTeamFountain()
			if IsFarmPathSafe(rally) and IsFarmLocationSafe(rally) then idleRally = rally; return 0.72 end
		end
	end
	local shelteredDesire = GetShelteredResourceDesire()
	if shelteredDesire > BOT_MODE_DESIRE_NONE then return shelteredDesire end
	local recoveryDesire = GetLaningRecoveryDesire()
	if recoveryDesire > BOT_MODE_DESIRE_NONE then return recoveryDesire end
	local rotationDesire = GetBetweenWaveFarmDesire(bNotClone)
	if rotationDesire > BOT_MODE_DESIRE_NONE or J.IsInLaningPhase() then return rotationDesire end

	-- Expensive queries (only after early exits)
    local botLevel = bot:GetLevel()
	local bCore = J.IsCore(bot)
	local bWeAreStronger = J.WeAreStronger(bot, 1600)
    local bRoshanAlive = J.IsRoshanAlive()
    local teamNetworth, enemyNetworth = J.GetInventoryNetworth()
    local networthAdvantage = teamNetworth - enemyNetworth
    local nAliveEnemyCount = J.GetNumOfAliveHeroes(true)
	local nAliveAllyCount  = J.GetNumOfAliveHeroes(false)

	if (nAliveEnemyCount <= 1 and nAliveAllyCount >= 2)
    or (J.DoesTeamHaveAegis() and J.IsLateGame() and nAliveAllyCount >= 4)
    then
        return BOT_MODE_DESIRE_NONE
    end
	
	if teamPlayers == nil then teamPlayers = GetTeamPlayers(GetTeam()) end

	if DotaTime() < 50 or botActiveMode == BOT_MODE_RUNE then
		return 0.0
	end
	
    local nEnemyHeroes = J.GetEnemiesNearLoc(bot:GetLocation(), 1600)
    if #nEnemyHeroes > 0 then
		if not bWeAreStronger then
			return BOT_MODE_DESIRE_NONE
		end

		for _, enemy in ipairs(nEnemyHeroes) do
			if J.IsValidHero(enemy) and enemy:GetAttackTarget() == bot then
				return BOT_MODE_DESIRE_NONE
			end
		end
    end

    local nAllyHeroes_attacking = {}
	for i = 1, #GetTeamPlayers( GetTeam() ) do
		local member = GetTeamMember(i)
		if bot ~= member and J.IsValidHero(member) and J.IsInRange(bot, member, 1600) then
            local hTarget = member:GetAttackTarget()
			if J.IsGoingOnSomeone(member)
            or (J.IsValidHero(hTarget) and J.IsChasingTarget(member, hTarget) and J.IsInRange(member, hTarget, 1000))
			then
				table.insert(nAllyHeroes_attacking, member)
			end
		end
	end

    if #nAllyHeroes_attacking > 0 then
        local nInRangeEnemy = J.GetEnemiesNearLoc(J.GetCenterOfUnits(nAllyHeroes_attacking), 1200)
        if #nInRangeEnemy > 0 and #nAllyHeroes_attacking + 1 >= #nInRangeEnemy then
            return BOT_MODE_DESIRE_NONE
        end
    end

	-- Retreating allies
    for i = 1, #GetTeamPlayers( GetTeam() ) do
		local member = GetTeamMember(i)
		if bot ~= member and J.IsValidHero(member) and J.IsInRange(bot, member, 2000) and J.IsRetreating(member) then
            local nInRangeEnemy = J.GetEnemiesNearLoc(member:GetLocation(), 1200)
            for _, enemy in pairs(nInRangeEnemy) do
                if J.IsValidHero(enemy)
                and (J.IsChasingTarget(enemy, bot) or enemy:GetAttackTarget() == member and J.GetHP(member) < 0.4)
                then
                    return BOT_MODE_DESIRE_NONE
                end
            end
		end
	end

    local vTeamFightLocation = J.GetTeamFightLocation(bot)
    if vTeamFightLocation ~= nil and GetUnitToLocationDistance(bot, vTeamFightLocation) < 2500 then
        if bot:GetLevel() >= 18 or not J.IsCore(bot) then
            return BOT_MODE_DESIRE_NONE
        end
    end

    if bAlive and bot:HasModifier('modifier_arc_warden_tempest_double') then
        if bRoshanAlive then
            for _, ally in pairs(nInRangeAlly_roshan) do
                if ally ~= bot
                and J.IsValidHero(ally)
                and ally:GetUnitName() == 'npc_dota_hero_arc_warden'
				and J.IsDoingRoshan(ally)
                then
                    local hTarget = ally:GetAttackTarget()
                    if (J.IsRoshan(hTarget) and J.GetHP(hTarget) < 0.4)
                    or (botActiveMode == BOT_MODE_ITEM)
                    then
						FindFarmCamp()
                        return RemapValClamped(J.GetHP(bot), 0.2, 0.7, BOT_MODE_DESIRE_MODERATE, BOT_MODE_DESIRE_VERYHIGH)
					end
                end
            end
        end
    end

    if bAlive and J.IsMeepoClone(bot) then
        if bRoshanAlive then
            for _, ally in pairs(nInRangeAlly_roshan) do
                if ally ~= bot
                and J.IsValidHero(ally)
				and not J.IsMeepoClone(ally)
                and ally:GetUnitName() == 'npc_dota_hero_meepo'
                and J.IsDoingRoshan(ally)
                then
                    local hTarget = ally:GetAttackTarget()
                    if (J.IsRoshan(hTarget) and J.GetHP(hTarget) < 0.25)
                    or (botActiveMode == BOT_MODE_ITEM)
                    then
						FindFarmCamp()
                        return RemapValClamped(J.GetHP(bot), 0.2, 0.7, BOT_MODE_DESIRE_MODERATE, BOT_MODE_DESIRE_VERYHIGH)
                    end
                end
            end
        end
    end
	
	if J.DoesTeamHaveAegis() and nAliveAllyCount >= 4 then
		return BOT_MODE_DESIRE_NONE;
	end

	-- A visible wave just died. Use the gap for a short round trip to a friendly camp.
		
	if DotaTime() > countTime + countCD
	then
		countTime  = DotaTime();
		allyKills  = J.GetNumOfTeamTotalKills(false);
		enemyKills = J.GetNumOfTeamTotalKills(true);

		
		if enemyKills > allyKills + nLostCount and J.Role.NotSayRate() 
		then
			J.Role['sayRate'] = true;
			if RandomInt(1,6) < 3 
			then
				bot:ActionImmediate_Chat(Localization.Get('say_will_lose'),true);
			else
				bot:ActionImmediate_Chat(Localization.Get('say_will_lose_2'),true);
			end
		end
		if allyKills > enemyKills + nWinCount and J.Role.NotSayRate() 
		then
		    J.Role['sayRate'] = true;
			if RandomInt(1,6) < 3 
			then
				bot:ActionImmediate_Chat(Localization.Get('say_will_win'),true);
			else
				bot:ActionImmediate_Chat(Localization.Get('say_will_win_2'),true);
			end
		end
	
	end
	if allyKills > enemyKills + 20 and nAliveAllyCount >= 4
	then return BOT_MODE_DESIRE_NONE; end

    local hItem = J.IsItemAvailable('item_hand_of_midas')
    if J.IsInAllyArea(bot) and J.CanCastAbility(hItem) then
        FindFarmCamp()
        return RemapValClamped(J.GetHP(bot), 0.2, 0.7, BOT_MODE_DESIRE_MODERATE, BOT_MODE_DESIRE_VERYHIGH)
    end

	if teamTime > DotaTime() - 3.0 then return BOT_MODE_DESIRE_NONE end

	local aAliveCount = J.GetNumOfAliveHeroes(false)
    local eAliveCount = J.GetNumOfAliveHeroes(true)
    local aAliveCoreCount = J.GetAliveCoreCount(false)
    local eAliveCoreCount = J.GetAliveCoreCount(true)
	if eAliveCount == 0
	or aAliveCoreCount >= eAliveCoreCount
	or (aAliveCoreCount >= 1 and aAliveCount >= eAliveCount + 2)
	or J.IsLateGame()
	then
		if (beHighFarmer or (beNormalFarmer and J.IsMidGame()) or J.IsLateGame() or bot:GetNetWorth() >= 15000) then
			if bot:GetActiveMode() == BOT_MODE_ASSEMBLE then assembleTime = DotaTime() end
			if DotaTime() - assembleTime < 15.0 then return BOT_MODE_DESIRE_NONE end
		end
	end

	-- Gradual farm desire cap: ramps from 0.3 during laning to 0.6 by 20min (turbo: 14min)
	-- Keeps jungle farming as a secondary priority — never dominant over teamfight/push/defend
	local nFarmRampStart = J.IsModeTurbo() and 8 * 60 or 10 * 60
	local nFarmRampEnd   = J.IsModeTurbo() and 14 * 60 or 20 * 60
	local nFarmCap = RemapValClamped(DotaTime(), nFarmRampStart, nFarmRampEnd, 0.3, 0.6)
	if bCore and bNotClone and GetGameMode() ~= GAMEMODE_MO and GetGameMode() ~= GAMEMODE_1V1MID
		and J.GetHP(bot) >= 0.55 and #nEnemyHeroes == 0 and not bot:WasRecentlyDamagedByAnyHero(3)
		and not J.IsInTeamFight(bot, 1800)
		and (botActiveModeDesire < BOT_MODE_DESIRE_HIGH or (not J.IsPushing(bot) and not J.IsDefending(bot)))
	then
		-- Use nearby income between fights, including after the late-game cutoff.
		local desire = FindRecoveryRoute(nil, Min(nFarmCap, 0.55))
		if desire > BOT_MODE_DESIRE_NONE then return desire end
	end

	if GetGameMode() ~= GAMEMODE_MO
	and J.Site.IsTimeToFarm(bot)
	and not J.IsDefending(bot)
	and (bot:GetUnitName() ~= 'npc_dota_hero_lone_druid_bear' or (bot:HasScepter() and not J.IsValid(LoneDruid.hero)))
	and (DotaTime() > 8 * 60 or bot:GetLevel() >= 8 or ( bot:GetAttackRange() < 220 and bot:GetLevel() >= 6 ))
	and networthAdvantage < 6000
	and not J.IsLateGame()
	then
		hLaneCreepList = {}
		if J.GetDistanceFromEnemyFountain(bot) > 4000
		then
			hLaneCreepList = bot:GetNearbyLaneCreeps(1600, true);
		end;

		local laneCenter = #hLaneCreepList > 0 and J.GetCenterOfUnits(hLaneCreepList) or nil
		if laneCenter ~= nil and IsFarmLocationSafe(laneCenter)
		then
			farmLaneLocation = laneCenter
			bot.farmLocation = farmLaneLocation
			return Min(RemapValClamped(J.GetHP(bot), 0.2, 0.7, 0.4, BOT_MODE_DESIRE_HIGH), nFarmCap)
		else
			-- Early game: prefer lane farming over jungle
			-- Lane creeps give more gold/XP per minute than jungle camps,
			-- especially before the bot has farming items.
			local bEarlyGame = (J.IsModeTurbo() and DotaTime() < 18 * 60 or DotaTime() < 25 * 60)
				and bot:GetNetWorth() < 15000
			local nDeaths = GetHeroDeaths(bot:GetPlayerID())

			if bEarlyGame and nDeaths < 5 then
				-- Find the closest safe lane front to farm
				local bestLane = nil
				local bestDist = 99999
				for _, lane in pairs({LANE_TOP, LANE_MID, LANE_BOT}) do
					local laneFront = GetLaneFrontLocation(GetTeam(), lane, 0)
					local dist = GetUnitToLocationDistance(bot, laneFront)
					if dist < bestDist and IsLocationVisible(laneFront) and IsFarmLocationSafe(laneFront) then
						bestDist = dist
						bestLane = lane
					end
				end

				if bestLane then
					local laneFront = GetLaneFrontLocation(GetTeam(), bestLane, 0)
					farmLaneLocation = laneFront
					bot.farmLocation = farmLaneLocation
					return Min(RemapValClamped(J.GetHP(bot), 0.2, 0.7, 0.35, BOT_MODE_DESIRE_HIGH), nFarmCap)
				end
			end

			-- Late game or dangerous lanes: farm jungle camps
			if FindFarmCamp() ~= nil then
				if not J.Site.IsModeSuitableToFarm(bot)
				then
					return BOT_MODE_DESIRE_NONE;
				elseif bot:GetHealth() <= 200
					then
						teamTime = DotaTime();
						return BOT_MODE_DESIRE_VERYLOW;
				elseif farmState == FARM_STATE_FARM
					then
						return nFarmCap;
				else
					bot.farmLocation = preferedCamp.cattr.location
					return Min(RemapValClamped(J.GetHP(bot), 0.2, 0.7, 0.4, BOT_MODE_DESIRE_VERYHIGH), nFarmCap);
				end
			end
		end
	end

	if not J.IsInLaningPhase() and (bCore or J.IsLateGame() or bot:GetLevel() >= 18) then
		hLaneCreepList = bot:GetNearbyLaneCreeps(1600, true)
		local laneCenter = #hLaneCreepList > 0 and J.GetCenterOfUnits(hLaneCreepList) or nil
		if laneCenter ~= nil and IsFarmLocationSafe(laneCenter) then
			farmLaneLocation = laneCenter
			bot.farmLocation = farmLaneLocation
			return Min(BOT_MODE_DESIRE_LOW, nFarmCap)
		end
		if FindFarmCamp() ~= nil then return Min(BOT_MODE_DESIRE_LOW, nFarmCap) end
	end

	return BOT_MODE_DESIRE_NONE
end


function OnStart()

end

function OnEnd()
	sideWaveTask, sideWaveDesire, bot.ohaRallySideWave = nil, nil, nil
	bot.ohaWaveClaim = nil
	if issuedFarmOrder and not bot:IsUsingAbility() and not bot:IsChanneling() then CancelFarmOrder() end
	issuedFarmOrder = false
	bot.ohaFarmCampClaim = nil
	postWaveCampDistance = nil
	postWaveOrigin = nil
	preferedCamp = nil;
	farmLaneLocation = nil
	recoveringLane = false
	tradingTowerLocation = nil
	nextCampSearch = 0
	farmState = FARM_STATE_NONE;
	hLaneCreepList  = {};
	runMode = false;
	runTime = 0;
	bot:SetTarget(nil);
end

local function RefreshSideWaveAction(request, task)
	if task and (task.returning or task.clearUntil <= DotaTime()) then return nil end
	local plan = GetRallySideWavePlan(request.lane)
	if plan and plan.mainLane == request.mainLane and plan.ranged == request.ranged then return plan end
	-- Never upgrade a one-unit nudge to a clear after death, deny, or loss of vision.
end

function Think()
	if J.CanNotUseAction(bot) then return end
	if J.Utils.IsBotThinkingMeaningfulAction(bot, Customize.ThinkLess, "farm") then return end
	if runMode
	then
		if not bot:IsInvisible() and bot:GetLevel() >= 15
			and not bot:HasModifier('modifier_medusa_stone_gaze_facing')
		then
			local botAttackRange = bot:GetAttackRange();
			if botAttackRange > 1400 then botAttackRange = 1400 end;
			local runModeAllies = bot:GetNearbyHeroes(900,false,BOT_MODE_NONE);
			local runModeEnemyHeroes = bot:GetNearbyHeroes(botAttackRange +50,true,BOT_MODE_NONE);
			if J.IsValid(runModeEnemyHeroes[1])
				and #runModeAllies >= 2
				and not runModeEnemyHeroes[1]:IsAttackImmune()
				and botName ~= "npc_dota_hero_bristleback"
				and J.GetDistanceFromEnemyFountain(bot) > 2200
			then
				bot:Action_AttackUnit(runModeEnemyHeroes[1], true);
				return;
			end
			local runModeBarracks  = bot:GetNearbyBarracks(botAttackRange +150,true);
			if J.IsValid(runModeBarracks[1])
				and not bot:WasRecentlyDamagedByAnyHero(1.0)
				and not runModeBarracks[1]:IsAttackImmune()
				and not runModeBarracks[1]:IsInvulnerable()
				and not runModeBarracks[1]:HasModifier("modifier_fountain_glyph")
				and not runModeBarracks[1]:HasModifier("modifier_invulnerable")
				and not runModeBarracks[1]:HasModifier("modifier_backdoor_protection_active")
			then
				bot:Action_AttackUnit(runModeBarracks[1], true);
				return;
			end
		end
		if J.IsInAllyArea(bot) or J.GetDistanceFromEnemyFountain(bot) < 2600
		then
			if bot:GetTeam() == TEAM_RADIANT
			then
				bot:Action_MoveToLocation(RB);
				return;
			else
				bot:Action_MoveToLocation(DB);
				return;
			end
		else
			if bot:GetTeam() == TEAM_RADIANT
			then
			    local mLoc = J.GetLocationTowardDistanceLocation(bot,DB,-700);
				bot:Action_MoveToLocation(mLoc);
				return;
			else
			    local mLoc = J.GetLocationTowardDistanceLocation(bot,RB,-700);
				bot:Action_MoveToLocation(mLoc);
				return;
			end
		end
	end

	if ShouldYieldForBaseDefense() or (bot.ohaOuterTowerHoldUntil or 0) > DotaTime()
		or (J.GetPostFightDuty and J.GetPostFightDuty(bot)) then
		sideWaveTask, sideWaveDesire, bot.ohaRallySideWave = nil, nil, nil
		shelterFarmTask, shelterFarmSince = nil, nil
		bot.ohaOuterFarmClaim = nil
		bot.ohaFarmCampClaim = nil
		CancelFarmOrder()
		return
	end
	if shelterFarmActive and shelterFarmTask then
		ThinkShelteredResource(shelterFarmTask)
		return
	end
	if sideWaveDesire then
		local now = DotaTime()
		local plan = RefreshSideWaveAction(sideWaveDesire, sideWaveTask)
		if plan then
			if not sideWaveTask then
				sideWaveTask = {lane = plan.lane, mainLane = plan.mainLane, rally = plan.rally, ranged = plan.ranged,
					clearUntil = now + (plan.ranged and 3.5 or 8), expires = now + 15}
				bot.ohaRallySideWave = sideWaveTask
				bot.ohaNextRallySideWaveAt = now + 26
				if Customize.TraceRallySideWave then
					print('[OHA side wave] start', now, bot:GetPlayerID(), plan.lane, plan.mainLane, plan.ranged and 'ranged-only' or 'clear')
				end
			end
			sideWaveTask.rally = plan.rally
			if AttackSideWave(plan) then return end
		end
		if sideWaveTask and sideWaveTask.expires > now then
			if not sideWaveTask.returning and Customize.TraceRallySideWave then
				print('[OHA side wave] return', now, bot:GetPlayerID(), sideWaveTask.lane)
			end
			sideWaveTask.returning = true
			local point = GetSideWaveReturnPoint(sideWaveTask)
			if point then MoveToFarm(point); return end
		end
		sideWaveTask, sideWaveDesire, bot.ohaRallySideWave = nil, nil, nil
		CancelFarmOrder()
		return
	end
	if idleRally ~= nil then
		MoveToFarm(idleRally)
		return
	end
	if collectingWave and farmLaneLocation ~= nil then
		if not CanCollectWave(farmLaneLocation, GetUnitToLocationDistance(bot, farmLaneLocation)) then
			bot.ohaWaveClaim = nil
			CancelFarmOrder()
			return
		end
		bot.ohaWaveClaim = {location = farmLaneLocation, expires = DotaTime() + 2}
	end
	if postWaveCampDistance and (#J.GetEnemiesNearLoc(bot:GetLocation(), 1600) > 0 or bot:WasRecentlyDamagedByAnyHero(3)) then
		bot.ohaFarmCampClaim = nil
		CancelFarmOrder()
		return
	end
	local returning = postWaveCampDistance and GetReturningWave()
	if returning and GetUnitToLocationDistance(bot, returning) > 650 then
		bot.ohaFarmCampClaim = nil
		MoveToFarm(returning)
		return
	end

	-- Ability-specific farm range detection
	local nEffectiveRange = bot:GetAttackRange()
	local StaticRemnant = bot:GetAbilityByName('storm_spirit_static_remnant')
	local Firefly = bot:GetAbilityByName('batrider_firefly')
	local ShadowWave = bot:GetAbilityByName('dazzle_shadow_wave')
	local InnerFire = bot:GetAbilityByName('huskar_inner_fire')
	if J.CanCastAbility(StaticRemnant) then
		nEffectiveRange = StaticRemnant:GetSpecialValueInt('static_remnant_radius')
	elseif J.CanCastAbility(Firefly) or bot:HasModifier('modifier_batrider_firefly') then
		nEffectiveRange = Firefly:GetSpecialValueInt('radius')
	elseif J.CanCastAbility(ShadowWave) then
		nEffectiveRange = ShadowWave:GetSpecialValueInt('damage_radius')
	elseif J.CanCastAbility(InnerFire) then
		nEffectiveRange = InnerFire:GetSpecialValueInt('radius')
	end

	hLaneCreepList = bot:GetNearbyLaneCreeps(900, true) -- always refresh to avoid stale data
	if collectingWave and farmLaneLocation ~= nil then
		local claimedWave = {}
		for _, creep in ipairs(hLaneCreepList or {}) do
			if J.IsValid(creep) and GetUnitToLocationDistance(creep, farmLaneLocation) <= 700 then
				claimedWave[#claimedWave + 1] = creep
			end
		end
		hLaneCreepList = claimedWave
		if #claimedWave == 0 and GetUnitToLocationDistance(bot, farmLaneLocation) <= 650 then
			bot.ohaWaveClaim = nil
			farmLaneLocation = nil
			collectingWave = false
			CancelFarmOrder()
			return
		end
	end
	if hLaneCreepList ~= nil and #hLaneCreepList > 0 and J.IsValid(hLaneCreepList[1]) then
		local farmTarget = J.Site.GetFarmLaneTarget(hLaneCreepList);
		local nSearchRange = bot:GetAttackRange() + 180
		if nSearchRange > 1600 then nSearchRange = 1600 end
		local nNeutrals = bot:GetNearbyNeutralCreeps(nSearchRange);
		if J.IsValid(farmTarget) and IsFarmWaveAvailable(farmTarget:GetLocation())
		and (not recoveringLane or IsFarmPathSafe(farmTarget:GetLocation()))
		and (#nNeutrals == 0 or farmLaneLocation ~= nil or postWaveCampDistance ~= nil) then
			bot.ohaFarmCampClaim = nil
			postWaveOrigin = nil
			if farmTarget:GetTeam() ~= bot:GetTeam() then
				local nEnemyTowers = bot:GetNearbyTowers(1600, true)
				if J.IsValidBuilding(nEnemyTowers[1]) then
					if nEnemyTowers[1]:GetAttackTarget() == bot or bot:WasRecentlyDamagedByTower(5.0) then
						bot:Action_MoveToLocation(J.VectorAway(bot:GetLocation(), nEnemyTowers[1]:GetLocation(), 1600))
						issuedFarmOrder = false
						return
					end
				end

				local nFarmRange = math.max(nEffectiveRange, bot:GetAttackRange())
				if GetUnitToUnitDistance(bot, farmTarget) > nFarmRange then
					MoveToFarm(farmTarget:GetLocation())
					return
				else
					AttackFarmTarget(farmTarget)
					return
				end
			end
		end
	end

	if farmLaneLocation ~= nil and IsFarmWaveAvailable(farmLaneLocation) then
		bot.ohaFarmCampClaim = nil
		MoveToFarm(farmLaneLocation)
		return
	end
	farmLaneLocation = nil

	if FindFarmCamp() ~= nil then
		local targetFarmLoc = preferedCamp.cattr.location;
		bot.ohaFarmCampClaim = {location = targetFarmLoc, expires = DotaTime() + 3}
		local cDist = GetUnitToLocationDistance(bot, targetFarmLoc);
		local nNeutrals = {}
		for _, creep in ipairs(bot:GetNearbyNeutralCreeps(1000)) do
			if J.IsValid(creep) and not J.IsRoshan(creep) and GetUnitToLocationDistance(creep, targetFarmLoc) <= 600 then
				nNeutrals[#nNeutrals + 1] = creep
			end
		end

		if #nNeutrals >= 3 and cDist <= 600 and cDist > 240
		   and ( bot:GetLevel() >= 10 or not nNeutrals[1]:IsAncientCreep())
		then farmState = FARM_STATE_FARM end;

		if farmState == FARM_STATE_NONE
		   and ( J.IsValid(nNeutrals[1]) or #nNeutrals > 1)
		   and not J.IsRoshan(nNeutrals[1])
		   and ( bot:GetLevel() >= 10 or not nNeutrals[1]:IsAncientCreep())
		then

			-- Use ability-specific range for neutral farming too
			local farmTarget = J.Site.FindFarmNeutralTarget(nNeutrals)
			if J.IsValid(farmTarget)
			then
				bot:SetTarget(farmTarget);
				AttackFarmTarget(farmTarget)
				return;
			elseif J.IsValid(nNeutrals[1]) then
				bot:SetTarget(nNeutrals[1]);
				AttackFarmTarget(nNeutrals[1])
				return;
			end
			
		elseif  farmState == FARM_STATE_NONE
				and (#nNeutrals == 0 and GetUnitToLocationDistance(bot, targetFarmLoc) < 600)
		        and cDist > 240
		        and ( not X.IsLocCanBeSeen(targetFarmLoc) or cDist > 600 )
			then
				if X.CouldBlink(bot,targetFarmLoc) then return end;
				
				if X.CouldBlade(bot,targetFarmLoc) then return end;
							
				MoveToFarm(targetFarmLoc)
				return;
		else
			local neutralCreeps = nNeutrals
			
			if #neutralCreeps >= 2 then

				farmState = FARM_STATE_FARM;
				
				local farmTarget = J.Site.FindFarmNeutralTarget(neutralCreeps)
				if J.IsValid(farmTarget)
				then
					bot:SetTarget(farmTarget);
					AttackFarmTarget(farmTarget)
					return;
				end
				
			elseif #neutralCreeps == 0 and (cDist <= 240 or (cDist <= 600 and X.IsLocCanBeSeen(targetFarmLoc)))
				then
					
					farmState = FARM_STATE_NONE;
					J.Role['availableCampTable'], preferedCamp = J.Site.UpdateAvailableCamp(bot, preferedCamp, J.Role['availableCampTable']);
					nextCampSearch = 0
					bot.ohaFarmCampClaim = nil
			else
			
				local farmTarget = J.Site.FindFarmNeutralTarget(neutralCreeps)
				if J.IsValid(farmTarget)
				then
					bot:SetTarget(farmTarget);
					AttackFarmTarget(farmTarget)
					return;
				end
				
				if cDist > 200 then MoveToFarm(targetFarmLoc) return end
			end
		end			
	end
	bot.ohaFarmCampClaim = nil
	CancelFarmOrder()
	
end

function X.CouldBlade(bot,nLocation) 
	local blade = J.IsItemAvailable("item_quelling_blade");
	if blade == nil then blade = J.IsItemAvailable("item_bfury"); end
	
	if blade ~= nil 
	   and blade:IsFullyCastable() 
	then
		local trees = bot:GetNearbyTrees(380);
		local dist = GetUnitToLocationDistance(bot,nLocation);
		local vStart = J.Site.GetXUnitsTowardsLocation(bot, nLocation, 32 );
		local vEnd  = J.Site.GetXUnitsTowardsLocation(bot, nLocation, dist - 32 );
		for _,t in pairs(trees)
		do
			if t ~= nil
			then
				local treeLoc = GetTreeLocation(t);
				local tResult = PointToLineDistance(vStart, vEnd, treeLoc);
				if tResult ~= nil 
				   and tResult.within 
				   and tResult.distance <= 96
				   and J.GetLocationToLocationDistance(treeLoc,nLocation) < dist
				then
					bot:Action_UseAbilityOnTree(blade, t);
					return true;
				end
			end			
		end
	end
	
	return false;
end


function X.CouldBlink(bot,nLocation)
	
	
	local maxBlinkDist = 1199;
	local blink = J.IsItemAvailable("item_blink");
	
	if botName == "npc_dota_hero_antimage"
	then
		blink = bot:GetAbilityByName( "antimage_blink" );
		maxBlinkDist = blink:GetSpecialValueInt('AbilityCastRange')
	end
	
	if botName == "npc_dota_hero_queenofpain"
	then
		blink = bot:GetAbilityByName( "queenofpain_blink" );
		maxBlinkDist = J.GetProperCastRange(false, bot, blink:GetCastRange())
	end
	
	if blink ~= nil 
	   and blink:IsFullyCastable() 
       and J.IsRunning(bot)
	then
		local bDist = GetUnitToLocationDistance(bot,nLocation);
		local maxBlinkLoc = J.Site.GetXUnitsTowardsLocation(bot, nLocation, maxBlinkDist );
		if bDist <= 600  -- recommend by oyster 2019/4/16
		then
			return false;
		elseif bDist < maxBlinkDist +1
			then
				if botName == "npc_dota_hero_antimage"
				then
					bot:Action_ClearActions(true);
		
					if not J.IsPTReady(bot,ATTRIBUTE_INTELLECT) 
					then
						J.SetQueueSwitchPtToINT(bot);
					end
							
					bot:ActionQueue_UseAbilityOnLocation(blink, nLocation);
									
					return true;
				end
			
				bot:Action_UseAbilityOnLocation(blink, nLocation);
				return true;
		elseif IsLocationPassable(maxBlinkLoc)
			then
				
				if botName == "npc_dota_hero_antimage"
				then
					bot:Action_ClearActions(true);
		
					if not J.IsPTReady(bot,ATTRIBUTE_INTELLECT) 
					then
						J.SetQueueSwitchPtToINT(bot);
					end
							
					bot:ActionQueue_UseAbilityOnLocation(blink, maxBlinkLoc);
									
					return true;
				end
				
				bot:Action_UseAbilityOnLocation(blink, maxBlinkLoc);
				return true;
		end
	end

	return false;
end


function X.IsLocCanBeSeen(vLoc)

	if GetUnitToLocationDistance(GetBot(),vLoc) < 180 then return true end
	
	local tempLocUp    = vLoc + Vector(5  ,0  );
	local tempLocDown  = vLoc + Vector(0  ,10 );
	local tempLocLeft  = vLoc + Vector(-15,0  );
	local tempLocRight = vLoc + Vector(0  ,-20);
	
	return IsLocationVisible(tempLocRight) 
		   and IsLocationVisible(tempLocLeft) 
	       and IsLocationVisible(tempLocUp) 
		   and IsLocationVisible(tempLocDown)
		   and IsRadiusVisible(vLoc,10)

end

function PickOneAnnouncer()
	if not hasPickedOneAnnouncer then
		for i, id in pairs(GetTeamPlayers(GetTeam())) do
			local hero = GetTeamMember(i)
			if hero ~= nil and hero.isAnnouncer then return end
		end
		bot.isAnnouncer = true
		hasPickedOneAnnouncer = true
		return
	end
end

function AnnounceMessages()
	if DotaTime() > 60 then return end

	local welcome_msgs = Localization.Get('welcome_msgs')
	if ((J.IsModeTurbo() and DotaTime() > -50 + team * 2) or (not J.IsModeTurbo() and DotaTime() > -75 + team * 2))
	and numberAnnouncePrinted < #welcome_msgs + 1
	and bot.isAnnouncer
	and DotaTime() < 0
	then
		if GameTime() - lastAnnouncePrintedTime >= announcementGap then
			local msg = welcome_msgs[numberAnnouncePrinted]
			local isFirstLine = numberAnnouncePrinted == 1
			if msg then
				bot:ActionImmediate_Chat(isFirstLine and msg .. Version.number or msg, nB == 0 or isFirstLine)
			end
			numberAnnouncePrinted = numberAnnouncePrinted + 1
			lastAnnouncePrintedTime = GameTime()
		end
	end

	if GetGameMode() ~= GAMEMODE_1V1MID and GetGameState() == GAME_STATE_PRE_GAME and bot.isBear == nil
	and (bot.announcedRole == nil or bot.announcedRole ~= J.GetPosition(bot)) then
		bot.announcedRole = J.GetPosition(bot)
		-- if GetTeam() == TEAM_DIRE then
		-- 	-- broken for 7.38 for now.
		-- 	return
		-- end
		bot:ActionImmediate_Chat(Localization.Get('say_play_pos')..J.GetPosition(bot), false)
	end
	if GetGameMode() ~= GAMEMODE_1V1MID
	and not isChangePosMessageDone
	and bot.isAnnouncer
	then
		local nH, nB = J.NumHumanBotPlayersInTeam()
		if DotaTime() >= 0 and nH > 0 and nB > 0
		then
			bot:ActionImmediate_Chat(Localization.Get('pos_select_closed'), true)
			isChangePosMessageDone = true
		end
	end
end


local enemyPids = nil;
function X.ShouldRun(bot)
	if bot:HasModifier('modifier_medusa_stone_gaze_facing') 
	then
		AttackTarget=bot:GetAttackTarget()
		if AttackTarget~=nil and AttackTarget:GetUnitName() == "npc_dota_hero_medusa"  
		and J.IsOtherAllyCanKillTarget( bot, AttackTarget )
		then
			
		else  
			return 3.33
		end
	end

		
	if bot:IsChanneling() 
	   or not bot:IsAlive()
	then
		return 0
	end	   
	
	local botLevel    = bot:GetLevel();
	local botMode     = bot:GetActiveMode();
	local botTarget   = J.GetProperTarget(bot);
	local hEnemyHeroList = J.GetEnemyList(bot,1600);
	local hAllyHeroList  = J.GetAllyList(bot,1600);
	local enemyFountainDistance = J.GetDistanceFromEnemyFountain(bot);
	local enemyAncient = GetAncient(GetOpposingTeam());
	local enemyAncientDistance = GetUnitToUnitDistance(bot,enemyAncient);
	local aliveEnemyCount = J.GetNumOfAliveHeroes(true)
	local rushEnemyTowerDistance = 250;

	if enemyFountainDistance < 1000
	then
		return 2;
	end

	if bot:DistanceFromFountain() < 200
		and botMode ~= BOT_MODE_RETREAT
		and ( J.GetHP(bot) + J.GetMP(bot) < 1.7 )
	then
		return 3;
	end

	if botLevel < 6
		and DotaTime() > 30
		and DotaTime() < 8 * 60
		and enemyFountainDistance < 8111
	then
		if botTarget ~= nil and botTarget:IsHero()
		   and J.GetHP(botTarget) > 0.35
		   and (  not J.IsInRange(bot,botTarget,bot:GetAttackRange() + 150) 
				  or not J.CanKillTarget(botTarget, bot:GetAttackDamage() * 2.33, DAMAGE_TYPE_PHYSICAL) )
		then
			return 2.88;
		end
	end

	if not X.IsThereT3Detroyed() 
	   and aliveEnemyCount >= 3 
	   and #hAllyHeroList < aliveEnemyCount + 2
	   and not J.Role.IsPvNMode()
	   and ( DotaTime() % 600 > 285 or DotaTime() < 18 * 60 )--处于夜间或小于18分钟
	then
		local allyLevel = J.GetAverageLevel(false);
		local enemyLevel = J.GetAverageLevel(true);
		if enemyFountainDistance < 4765
		then
			local nAllyLaneCreeps = bot:GetNearbyLaneCreeps(550,false);
			if( allyLevel - 4 < enemyLevel and allyLevel < 24 )
			   and not ( allyLevel - 2 > enemyLevel and aliveEnemyCount == 3)
			   and #nAllyLaneCreeps <= 4
			then
				return 1.33;
			end
		end
				
	end
	
	-- 前期线上别顶着小兵打太凶
	if botLevel < 5
	and bot:WasRecentlyDamagedByCreep(1)
	and J.GetHP(bot) < 0.7
	and J.IsValidHero(botTarget) and botTarget:GetTeam() ~= bot:GetTeam()
	and J.GetHP(botTarget) > J.GetHP(bot) - 0.15 then
		return 2;
	end

	local nEnemyTowers = bot:GetNearbyTowers(898, true);
	local nEnemyBrracks = bot:GetNearbyBarracks(800,true);
	
	if #nEnemyBrracks >= 1 and aliveEnemyCount >= 2 and #hEnemyHeroList >= #hAllyHeroList
	then
		if #nEnemyTowers >= 2
		   or enemyAncientDistance <= 1314
		   or enemyFountainDistance <= 2828
		then
			return 2;
		end
	end
	

	if nEnemyTowers[1] ~= nil and botLevel < 16
	then
		if nEnemyTowers[1]:HasModifier("modifier_invulnerable") and aliveEnemyCount > 1
		then
			return 2.5;
		end
		
		if  enemyAncientDistance > 2100
			and enemyAncientDistance < GetUnitToUnitDistance(nEnemyTowers[1],enemyAncient) - rushEnemyTowerDistance
		then
			local nTarget = J.GetProperTarget(bot);
			if nTarget == nil
			then
				return 3.9;
			end
			
			if J.IsValidHero(nTarget) and aliveEnemyCount > 2
			then
				
				local assistAlly = false;
				
				for _,ally in pairs(hAllyHeroList)
				do
					if GetUnitToUnitDistance(ally,nTarget) <= ally:GetAttackRange() + 100
						and (ally:GetAttackTarget() == nTarget or ally:GetTarget() == nTarget)
					then
						assistAlly = true;
						break;
					end
				end
				
				if not assistAlly 
				then
					return 2.5;
				end
				
			end
		end
	end
	

	-- 前期谨慎冲塔
	if botLevel <= 10 and DotaTime() > 0
		and (#hEnemyHeroList > 0 or bot:GetHealth() < 700)
	then
		local nLongEnemyTowers = bot:GetNearbyTowers(1200, true);
		if bot:GetAssignedLane() == LANE_MID
		then
			 nLongEnemyTowers = bot:GetNearbyTowers(1100, true);
			 nEnemyTowers     = bot:GetNearbyTowers(980, true);
		end
		if ( botLevel <= 2 or DotaTime() < 2 * 60 )
			and nLongEnemyTowers[1] ~= nil
		then
			return 2;
		end
		if ( botLevel <= 4 or DotaTime() < 3 * 60 )
			and nEnemyTowers[1] ~= nil
		then
			return 2;
		end
		if botLevel <= 9
			and nEnemyTowers[1] ~= nil
			and nEnemyTowers[1]:CanBeSeen()
			and nEnemyTowers[1]:GetAttackTarget() == bot
			and #hAllyHeroList <= 1
		then
			return 2;
		end
	end

	if  botLevel <= 10
		and (#hEnemyHeroList > 0 or bot:GetHealth() < 700)
	then
		local nLongEnemyTowers = bot:GetNearbyTowers(999, true);
		if bot:GetAssignedLane() == LANE_MID 
		then 
			 nLongEnemyTowers = bot:GetNearbyTowers(988, true); 
			 nEnemyTowers     = bot:GetNearbyTowers(966, true); 
		end
		if ( botLevel <= 2 or DotaTime() < 2 * 60 )
			and nLongEnemyTowers[1] ~= nil
		then
			return 1;
		end	
		if ( botLevel <= 4 or DotaTime() < 3 * 60 )
			and nEnemyTowers[1] ~= nil
		then
			return 1;
		end	
		if botLevel <= 9
			and nEnemyTowers[1] ~= nil
			and nEnemyTowers[1]:CanBeSeen()
			and nEnemyTowers[1]:GetAttackTarget() == bot
			and #hAllyHeroList <= 1
		then
			return 1;
		end
	end

	if #hAllyHeroList <= 1 
	   and botMode ~= BOT_MODE_TEAM_ROAM
	   and botMode ~= BOT_MODE_LANING
	   and botMode ~= BOT_MODE_RETREAT
	   and ( botLevel <= 1 or botLevel > 5 ) 
	   and bot:DistanceFromFountain() > 1400
	then
		if enemyPids == nil then
			enemyPids = GetTeamPlayers(GetOpposingTeam())
		end	
		local enemyCount = 0
		for i = 1, #enemyPids do
			local info = GetHeroLastSeenInfo(enemyPids[i])
			if info ~= nil then
				local dInfo = info[1]; 
				if dInfo ~= nil and dInfo.time_since_seen < 2.0  
					and GetUnitToLocationDistance(bot,dInfo.location) < 1000 
				then
					enemyCount = enemyCount +1;
				end
			end	
		end
		if (enemyCount >= 4 or #hEnemyHeroList >= 4) 
			and botMode ~= BOT_MODE_ATTACK
			and botMode ~= BOT_MODE_TEAM_ROAM
			and bot:GetCurrentMovementSpeed() > 300
		then
			local nNearByHeroes = bot:GetNearbyHeroes(700,true,BOT_MODE_NONE);
			if #nNearByHeroes < 2
	        then
				return 4;
			end
		end	
		if  botLevel >= 9 and botLevel <= 17  
			and (enemyCount >= 3 or #hEnemyHeroList >= 3) 
			and botMode ~= BOT_MODE_LANING
			and bot:GetCurrentMovementSpeed() > 300
		then
			local nNearByHeroes = bot:GetNearbyHeroes(700,true,BOT_MODE_NONE);
			if #nNearByHeroes < 2
	        then
				return 3;
			end
		end
		local nEnemy = bot:GetNearbyHeroes(800,true,BOT_MODE_NONE);
		for _,enemy in pairs(nEnemy)
		do
			if J.IsValid(enemy)
				and enemy:GetUnitName() == "npc_dota_hero_necrolyte"
				and enemy:GetMana() >= 200
				and J.GetHP(bot) < 0.45
				and enemy:IsFacingLocation(bot:GetLocation(),20)
			then
				return 3;
			end
		end
	end
	return 0
end

function X.IsThereT3Detroyed()
	
	local T3s = {
		TOWER_TOP_3,
		TOWER_MID_3,
		TOWER_BOT_3
	}
	
	for _,t in pairs(T3s) do
		local tower = GetTower(GetOpposingTeam(), t);
		if tower == nil or not tower:IsAlive() then
			return true;
		end
	end	
	return false;
end
