local Utils = require( GetScriptDirectory()..'/FunLib/utils')
local J = require( GetScriptDirectory()..'/FunLib/jmz_func')
local LaneCamp = require(GetScriptDirectory() .. '/FunLib/lane_camp')
local OpeningRune = require(GetScriptDirectory() .. '/FunLib/opening_rune')

local Version      = require(GetScriptDirectory()..'/FunLib/version')
local Localization = require(GetScriptDirectory()..'/FunLib/localization')


local bot = GetBot()
if bot == nil then return end
local botName = bot:GetUnitName()
local function IsInvulnerableOutsideFountain()
	return bot:IsInvulnerable() and DotaTime() >= 0 and not bot:HasModifier('modifier_fountain_invulnerability')
end
if not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion()
	or IsInvulnerableOutsideFountain() then return end

local local_mode_laning_generic = nil
local nAllyCreeps = nil
local nEnemyCreeps = nil
local nFurthestEnemyAttackRange = 0
local nInRangeEnemy = nil
local botAssignedLane = nil
local botAttackRange = bot:GetAttackRange()
local GetFurthestEnemyAttackRange
local nH, enemyBots = J.Utils.NumHumanBotPlayersInTeam(GetOpposingTeam())
local teamHumans, teamBots = J.Utils.NumHumanBotPlayersInTeam(GetTeam())
local firstWaveReached = false
local campPlan
local laneShot
local nextLaneTrace = {}
local function TraceLaneDecision(kind, target)
	if not J.Customize or not J.Customize.TraceLaneDecisions then return end
	local now = DotaTime()
	if now > 900 or now < (nextLaneTrace[kind] or -math.huge) then return end
	nextLaneTrace[kind] = now + 4
	print('[OHA lane]', now, bot:GetPlayerID(), bot:GetAssignedLane(), kind, bot:GetActiveMode(),
		target and target:GetUnitName() or '-', target and math.floor(GetUnitToUnitDistance(bot, target)) or -1,
		math.floor(J.GetHP(bot) * 100))
end
local laneTierOne = {[LANE_TOP] = TOWER_TOP_1, [LANE_MID] = TOWER_MID_1, [LANE_BOT] = TOWER_BOT_1}

local function IssueLaneTradeShot(target, clash, reason, fromTower)
	if target ~= bot:GetAttackTarget() or not J.IsFinishingLaningAttack(bot, target) then
		TraceLaneDecision(reason, target)
		laneShot = {target = target, previous = bot:GetLastAttackTime(), clash = clash, fromTower = fromTower}
		bot:Action_AttackUnit(target, true)
	end
	return true
end

local function ShootAtLaneClash(enemies, enemyTower, nearbyTower)
	local target, clash
	if nearbyTower then
		target, clash = J.GetTowerLaneHarassTarget(bot, enemies, enemyTower, bot:GetAttackRange())
	else
		target, clash = J.GetCoveredRangedLaneShot(bot, enemies, enemyTower)
	end
	if not target then return false end
	return IssueLaneTradeShot(target, clash, nearbyTower and 'tower-lane-trade' or 'ranged-lane-trade', nearbyTower ~= nil)
end

-- Announcer state
local hasPickedOneAnnouncer      = false
local lastAnnouncePrintedTime    = 0
local numberAnnouncePrinted      = 1
local announcementGapSeconds     = 6
local isChangePosMessageDone     = false

if Utils.BuggyHeroesDueToValveTooLazy[botName] then local_mode_laning_generic = dofile( GetScriptDirectory().."/FunLib/override_generic/mode_laning_generic" ) end
local assignedLane = bot:GetAssignedLane()
local engineMid = local_mode_laning_generic == nil and botAttackRange >= 400
	and (assignedLane == LANE_MID or ((assignedLane == LANE_NONE or assignedLane == nil) and J.GetPosition(bot) == 2))
bot.ohaEngineMid = engineMid
local engineSideCore = false
if local_mode_laning_generic == nil and J.Customize and J.Customize.TestNativeSideLaneCores
	and (assignedLane == LANE_TOP or assignedLane == LANE_BOT or assignedLane == LANE_NONE or assignedLane == nil) then
	local role = J.GetPosition(bot)
	engineSideCore = role == 1 or role == 3
	if engineSideCore and J.Customize.TraceLaneDecisions then
		print('[OHA lane controller]', bot:GetPlayerID(), botName, 'native-side-core')
	end
end

local function GetOpeningLaneDestination(lane, enemies)
	local now = DotaTime()
	if firstWaveReached or now < -90 or now > 100
		or GetGameMode() == GAMEMODE_MO or GetGameMode() == GAMEMODE_1V1MID then return nil end
	if now < 0 then
		local spot, location = OpeningRune.Target(bot)
		if spot ~= nil then return location, spot end
	end
	local towerId = laneTierOne[lane]
	local tower = towerId ~= nil and GetTower(GetTeam(), towerId) or nil
	if not J.IsValidBuilding(tower) then return nil end
	if J.IsInRange(bot, tower, 850) then
		if now >= 0 and now < 30 and (lane == LANE_TOP or lane == LANE_BOT)
			and #enemies == 0 and #bot:GetNearbyLaneCreeps(800, true) == 0 then
			local anchor = tower:GetLocation()
			local front = GetLaneFrontLocation(GetTeam(), lane, 0)
			for _, ally in ipairs(bot:GetNearbyLaneCreeps(850, false)) do
				if J.IsValid(ally) and GetUnitToLocationDistance(ally, front) < J.GetLocationToLocationDistance(anchor, front)
					and GetUnitToLocationDistance(ally, anchor) > 320 then
					local point = J.VectorTowards(anchor, ally:GetLocation(), 320)
					if GetUnitToLocationDistance(bot, point) > 95 and IsLocationPassable(point)
						and #J.GetLastSeenEnemiesNearLoc(point, 950) == 0 then return point end
					break
				end
			end
		elseif now >= 30 or #bot:GetNearbyLaneCreeps(800, true) > 0 then
			firstWaveReached = true
		end
		return nil
	end
	if J.IsLaningUnderPressure(bot, enemies, nil) then return nil end
	return tower:GetLocation()
end

function GetDesire()
	campPlan = nil
	J.ObserveSideLaneCreepDrag(bot)
	PickOneAnnouncer()
	AnnounceMessages()

	if not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion()
		or IsInvulnerableOutsideFountain() then return BOT_MODE_DESIRE_NONE end
	local botLV = bot:GetLevel()
	local currentTime = DotaTime()

	botAttackRange = bot:GetAttackRange()
	nAllyCreeps = bot:GetNearbyLaneCreeps(1200, false)
	nEnemyCreeps = bot:GetNearbyLaneCreeps(botAttackRange < 310 and 1200 or math.min(1600, math.max(800, botAttackRange + 300)), true)
	nInRangeEnemy = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	nFurthestEnemyAttackRange = GetFurthestEnemyAttackRange(nInRangeEnemy)
	if local_mode_laning_generic then
		botAssignedLane = local_mode_laning_generic.GetBotTargetLane()
	else
		botAssignedLane = bot:GetAssignedLane()
	end
	local opening, openingRune = GetOpeningLaneDestination(botAssignedLane, nInRangeEnemy)
	if opening ~= nil then return openingRune ~= nil and 0.93 or 0.72 end
	if GetGameMode() == 23 then currentTime = currentTime * 1.65 end
	if currentTime < 0 then return BOT_ACTION_DESIRE_NONE end
	local enemyTower = bot:GetNearbyTowers(1200, true)[1]
	local underPressure = J.IsLaningUnderPressure(bot, nInRangeEnemy, enemyTower)

	-- if DotaTime() > 20 and DotaTime() - skipLaningState.lastCheckTime < skipLaningState.checkGap then
	-- 	if skipLaningState.count > 6 then
	-- 		print('[WARN] Bot ' ..botName.. ' switching modes too often, now stop it for laning to avoid conflicts.')
	-- 		return 0
	-- 	end
	-- else
	-- 	skipLaningState.lastCheckTime = DotaTime()
	-- 	skipLaningState.count = 0
	-- end

	if J.GetEnemiesAroundAncient(bot, 3200) > 0 then
		return BOT_MODE_DESIRE_NONE
	end
	if bot.ohaCreepDrag ~= nil then return 0.82 end
	if not local_mode_laning_generic and J.GetSideLaneYieldPoint
		and J.GetSideLaneYieldPoint(bot, nInRangeEnemy, enemyTower, underPressure) then return 0.88 end
	-- A safe side-lane return also helps ranged supports rejoin their core.
	if not local_mode_laning_generic and J.GetSideLaneReturnPoint
		and J.GetSideLaneReturnPoint(bot, botAssignedLane) ~= nil then return J.IsCore(bot) and 0.84 or 0.68 end
	if not local_mode_laning_generic and not underPressure and J.GetSideLaneReturnScreen
		and J.GetSideLaneReturnScreen(bot) then return 0.79 end
	if J.GetLaningHoldTower(bot) ~= nil then return 0.82 end

	-- if J.GetDistanceFromAncient( bot, true ) < 6900 then
	-- 	return BOT_MODE_DESIRE_NONE
	-- end

	if underPressure and bot:WasRecentlyDamagedByAnyHero(5)
	and #J.Utils.GetLastSeenEnemyIdsNearLocation(bot:GetLocation(), 800) > 0 then
		local nLaneFrontLocation = GetLaneFrontLocation(GetTeam(), bot:GetAssignedLane(), 0)
		local nDistFromLane = GetUnitToLocationDistance(bot, nLaneFrontLocation)
		if not J.WeAreStronger(bot, 1200) or (nDistFromLane > 700 and J.GetHP(bot) < 0.7) then
			return BOT_MODE_DESIRE_NONE
		end
	end

	-- 如果在打高地 就别撤退去干别的
	if J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		return BOT_MODE_DESIRE_NONE
	end
	-- if J.ShouldGoFarmDuringLaning(bot) then
	-- 	return 0.2
	-- end

	if J.IsInLaningPhase() and not underPressure then
		if engineMid and botAssignedLane == LANE_MID and #nEnemyCreeps > 0
			and GetUnitToLocationDistance(bot, GetLaneFrontLocation(GetTeam(), LANE_MID, 0)) < 1500 then
			return 0.74
		end
		if J.HasPendingLaningLastHit(bot) then return J.IsCore(bot) and 0.9 or 0.55 end
		local hitCreep, moveToCreep, reserve, urgentApproach, approachStep = J.GetLaningLastHitTarget(bot, nEnemyCreeps, enemyTower,
			J.GetLaningAttackDamage(bot), nInRangeEnemy)
		if J.IsValid(hitCreep) and not moveToCreep and J.IsInRange(bot, hitCreep, botAttackRange + 100) then
			if J.GetPosition(bot) <= 3 then return 0.9 end
			if GetUnitToUnitDistance(bot, hitCreep) <= botAttackRange then return 0.55 end
		end
		if not engineMid and not local_mode_laning_generic and J.GetLaningTowerJointHit(bot,
			bot:GetNearbyTowers(1050, false)[1], nInRangeEnemy) then return J.IsCore(bot) and 0.88 or 0.75 end
		if approachStep then return J.IsCore(bot) and 0.72 or 0.55 end
		if reserve and botAssignedLane ~= LANE_MID then return J.IsCore(bot) and 0.78 or 0.55 end
		if urgentApproach and J.IsCore(bot)
			and J.GetLaningCreepPosition(bot, botAssignedLane, {hitCreep}, enemyTower, nInRangeEnemy, true) ~= nil then return 0.74 end
		local deny, reserveDeny, urgentDeny = J.GetLaningDenyTarget(bot, nAllyCreeps, enemyTower, nInRangeEnemy)
		if urgentDeny and not local_mode_laning_generic then return 0.76 end
		if not local_mode_laning_generic and not deny and not reserveDeny
			and J.GetLaningDenyStep(bot, nAllyCreeps, enemyTower, nInRangeEnemy) then return 0.69 end
		local nearbyTower = J.GetTowerCoveredLaneClash(bot)
		if not local_mode_laning_generic and hitCreep == nil and not reserve
			and J.GetSideLaneCreepDrag(bot, nInRangeEnemy, enemyTower) then return 0.73 end
		if not local_mode_laning_generic
			and J.GetSideLaneCoverAttack(bot, nInRangeEnemy, enemyTower) ~= nil then return 0.75 end
		if not local_mode_laning_generic
			and J.GetSideLaneFinishTarget(bot, nInRangeEnemy, enemyTower) ~= nil then return 0.75 end
		campPlan = LaneCamp.Plan(bot, botAssignedLane)
		if campPlan and campPlan.kind == 'pull' then return bot.ohaLaneCamp and 0.74 or 0.68 end
		if campPlan and campPlan.kind == 'probe' then return bot.ohaLaneCamp and 0.72 or 0.68 end
		if not local_mode_laning_generic then
			local target, step = J.GetSideLaneDuoTrade(bot, nInRangeEnemy, enemyTower, botAttackRange)
			if target then return step and 0.68 or 0.71 end
			if J.GetSideLanePressureTarget(bot, nInRangeEnemy, enemyTower, botAttackRange) ~= nil then return 0.71 end
			if J.GetSideLanePressureStep(bot, nInRangeEnemy, enemyTower) ~= nil then return 0.68 end
		end
		if not local_mode_laning_generic and nearbyTower then
			if not deny and not reserveDeny and J.GetTowerLaneHarassTarget(bot, nInRangeEnemy, enemyTower, botAttackRange) then
				return 0.71
			end
		elseif not local_mode_laning_generic then
			if not deny and not reserveDeny and J.GetCoveredRangedLaneShot(bot, nInRangeEnemy, enemyTower) then return 0.66 end
		end
		if deny ~= nil or reserveDeny then return 0.7 end
		if botAssignedLane == LANE_MID and J.IsCore(bot) and (reserve or moveToCreep) then
			return 0.7
		end
		if J.IsCore(bot) and (reserve or moveToCreep
			or J.GetLaningCreepPosition(bot, botAssignedLane, nEnemyCreeps, enemyTower, nInRangeEnemy) ~= nil) then
			return 0.57
		end
		if campPlan ~= nil then return 0.63 end
		if not local_mode_laning_generic and not J.IsCore(bot)
			and J.GetLaningCreepPosition(bot, botAssignedLane, nEnemyCreeps, enemyTower, nInRangeEnemy) ~= nil then
			return 0.59
		end
	end
	if local_mode_laning_generic and local_mode_laning_generic.GetDesire ~= nil then return local_mode_laning_generic.GetDesire() end

	if GetGameMode() == GAMEMODE_1V1MID or GetGameMode() == GAMEMODE_MO then
		return 1
	end

	if currentTime <= 10 then return 0.268 end
	if currentTime <= 9 * 60 and botLV <= 7 then return 0.446 end
	if currentTime <= 12 * 60 and botLV <= 11 then return 0.369 end
	if botLV <= 14 and J.GetCoresAverageNetworth() < 7000 then return 0.2 end

	J.Utils.GameStates.passiveLaningTime = true
	return 0.01
end

function GetFurthestEnemyAttackRange(enemyList)
	local attackRange = 0
	for _, enemy in pairs(enemyList) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) then
			local enemyAttackRange = enemy:GetAttackRange()
			if enemyAttackRange > attackRange then
				attackRange = enemyAttackRange
			end
		end
	end

	return attackRange
end

local function ThinkLane()
	if not bot:IsAlive() or J.CanNotUseAction(bot, DotaTime() < 0) or bot:IsDisarmed()
		or bot:IsUsingAbility() or bot:IsChanneling() then return end
	nInRangeEnemy = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	local nearbyTower, clash = J.GetTowerCoveredLaneClash(bot)
	if laneShot then
		local target = laneShot.target
		local released = bot:GetLastAttackTime() ~= laneShot.previous
		if not laneShot.fromTower then clash = laneShot.clash end
		if released or not clash or not J.IsValidHero(target) or not J.IsInRange(bot, target, bot:GetAttackRange())
			or GetUnitToLocationDistance(target, clash) > 650 or GetUnitToLocationDistance(bot, clash) > 720 then
			laneShot = nil
			if not released and bot:GetAttackTarget() == target then
				bot:Action_ClearActions(true)
				return
			end
		end
	end
	if bot.ohaCreepDrag and J.RunSideLaneCreepDrag(bot, nInRangeEnemy, nil, true) then return end
	local opening, spot = GetOpeningLaneDestination(botAssignedLane or bot:GetAssignedLane(), nInRangeEnemy)
	if opening ~= nil then
		if spot ~= nil then OpeningRune.Walk(bot, spot, opening); return end
		if DotaTime() < 0 and bot.ohaOpeningRuneSpot ~= nil and DotaTime() < (bot.ohaOpeningRuneStepAt or -math.huge) then return end
		bot:Action_MoveToLocation(opening)
		return
	end
	local enemyTower = bot:GetNearbyTowers(1200, true)[1]
	local underPressure = J.IsLaningUnderPressure(bot, nInRangeEnemy, enemyTower)
	if not local_mode_laning_generic and J.GetSideLaneYieldPoint then
		local point = J.GetSideLaneYieldPoint(bot, nInRangeEnemy, enemyTower, underPressure)
		if point then
			local pending = bot.ohaSideLaneYield
			if not pending or pending.expires <= DotaTime() or pending.point ~= point then
				local travel = GetUnitToLocationDistance(bot, point) / math.max(1, bot:GetCurrentMovementSpeed())
				bot.ohaSideLaneYield = {point=point, expires=DotaTime() + math.min(3, travel + 0.6)}
			end
			TraceLaneDecision('short-yield')
			if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'short-yield') end
			bot:Action_MoveToLocation(point)
			return
		end
		bot.ohaSideLaneYield = nil
	end
	if not local_mode_laning_generic and not J.HasPendingLaningLastHit(bot)
		and J.GetSideLaneReturnPoint then
		local point, recovered, anchor = J.GetSideLaneReturnPoint(bot, botAssignedLane or bot:GetAssignedLane())
		if point then
			if recovered then bot.ohaSideLaneReturnUntil = DotaTime() + 50 end
			TraceLaneDecision(anchor and 'side-rear-tower-reentry' or 'side-wave-reentry', anchor)
			if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'side-wave-reentry') end
			bot:Action_MoveToLocation(point)
			return
		end
	end
	local holdTower = J.GetLaningHoldTower(bot)
	if holdTower ~= nil then
		local wave, covered = J.GetTowerCoveredLaneCreeps(bot, holdTower, bot:GetNearbyLaneCreeps(1000, true), nInRangeEnemy)
		local current = bot:GetAttackTarget()
		local hold = J.AdjustLocationWithOffsetTowardsFountain(holdTower:GetLocation(), 300)
		local pending = J.HasPendingLaningLastHit(bot) and bot.ohaLaningAttackTarget or nil
		if pending and not underPressure and pending:GetTeam() == bot:GetTeam()
			and J.IsInRange(pending, holdTower, 875) then return end
		local creep, approach, reserve
		if #wave > 0 then
			if pending or J.IsFinishingLaningAttack(bot, current) then
				for _, creep in ipairs(wave) do if (pending or current) == creep then return end end
			end
			creep, approach, reserve = J.GetLaningLastHitTarget(bot, wave, nil, J.GetLaningAttackDamage(bot), nInRangeEnemy, true)
			if creep ~= nil and not approach then J.IssueLaningAttack(bot, creep); return end
			local together = not underPressure and J.GetLaningTowerJointHit(bot, holdTower, nInRangeEnemy)
			if together then TraceLaneDecision('joint-tower-hit', together); J.IssueLaningAttack(bot, together); return end
		end
		if not underPressure and not pending and not J.IsFinishingLaningAttack(bot, current)
			and J.TryClearTowerSiege(bot, holdTower) then return end
		if #wave > 0 then
			if reserve then J.HoldLaningAttack(bot, current); return end
			if approach and bot:GetAttackRange() < 310 and not J.IsLaningUnderPressure(bot, nInRangeEnemy, nil)
				and #J.GetEnemiesNearLoc(creep:GetLocation(), 750) == 0 then
				bot:Action_MoveToUnit(creep)
				return
			end
			if (approach or not covered) and not underPressure and J.GetHP(bot) >= 0.70 and not bot:WasRecentlyDamagedByAnyHero(2)
				and not J.IsFinishingLaningAttack(bot, current) then
				local front = approach and creep or wave[1]
				local gap = GetUnitToUnitDistance(bot, front) - bot:GetAttackRange()
				if (gap > 90 or approach and gap > 0) and J.IsInRange(front, holdTower, 780) then
					local here = bot:GetLocation()
					local stride = math.min(gap + (approach and 24 or -45), 325)
					local point = J.VectorTowards(here, front:GetLocation(), stride)
					local midpoint = J.VectorTowards(here, point, stride * 0.5)
					if GetUnitToLocationDistance(holdTower, point) <= 700 and IsLocationVisible(point)
						and IsLocationPassable(point) and IsLocationPassable(midpoint)
						and #J.GetLastSeenEnemiesNearLoc(point, 850) == 0
						and #J.GetEnemiesNearLoc(midpoint, 750) == 0
						and J.GetVisibleThreatAt(bot, nInRangeEnemy, point, 1.5) < bot:GetHealth() * 0.20 then
						TraceLaneDecision('tower-wave-step', front)
						bot:Action_MoveToLocation(point)
						return
					end
				end
			end
			if covered then
				local point = J.AdjustLocationWithOffsetTowardsFountain(wave[1]:GetLocation(), math.max(240, bot:GetAttackRange() - 50))
				if IsLocationPassable(point) and #J.GetLastSeenEnemiesNearLoc(point, 900) == 0 then hold = point end
			end
		elseif botAssignedLane ~= LANE_MID and #nInRangeEnemy == 0 and not underPressure and J.GetHP(bot) >= 0.80 then
			local lane = botAssignedLane or bot:GetAssignedLane()
			local front = GetLaneFrontLocation(bot:GetTeam(), lane, 0)
			local anchor = holdTower:GetLocation()
			local direction = bot:GetTeam() == TEAM_RADIANT and 1 or -1
			local ahead = (GetAmountAlongLane(lane, front).amount - GetAmountAlongLane(lane, anchor).amount) * direction
			if ahead > 0.02 then
				local point = J.VectorTowards(anchor, front, 460)
				if IsLocationPassable(point) and IsLocationVisible(point)
					and #J.GetEnemiesNearLoc(point, 1050) == 0 and #J.GetLastSeenEnemiesNearLoc(point, 1050) == 0 then
					hold = point
					if GetUnitToLocationDistance(bot, hold) > 90 then TraceLaneDecision('tower-face-wave', holdTower) end
				end
			end
		end
		-- On a real reset, the laner covering the tower can still deny from safety.
		if not underPressure and J.IsInRange(bot, holdTower, 900) then
			local deny = J.GetLaningDenyTarget(bot, bot:GetNearbyLaneCreeps(bot:GetAttackRange(), false), enemyTower, nInRangeEnemy)
			if deny and J.IsInRange(deny, holdTower, 875) then
				TraceLaneDecision('tower-lane-deny', deny)
				J.IssueLaningAttack(bot, deny)
				return
			end
		end
		local enemyTower = bot:GetNearbyTowers(1500, true)[1]
		local cover = J.GetSideLaneCoverAttack(bot, nInRangeEnemy, enemyTower)
		if cover and not J.IsFinishingLaningAttack(bot, current) then
			TraceLaneDecision('cover-core', cover)
			bot:Action_AttackUnit(cover, true)
			return
		end
		if nearbyTower and ShootAtLaneClash(nInRangeEnemy, enemyTower, nearbyTower) then return end
		local press = not nearbyTower and J.GetSideLanePressureTarget(bot, nInRangeEnemy, enemyTower, botAttackRange)
		if press and J.IsInRange(bot, press, botAttackRange) then
			if bot:GetAttackTarget() ~= press then bot:Action_AttackUnit(press, true) end
			return
		end
		if GetUnitToLocationDistance(bot, hold) > 90 then
			bot:Action_MoveToLocation(hold)
		elseif J.IsValid(current) then
			bot:Action_ClearActions(true)
		end
		return
	end
	local attackTarget = bot:GetAttackTarget()
	if not underPressure and J.HasPendingLaningLastHit(bot) then return end
	if local_mode_laning_generic then
		if campPlan ~= nil and not underPressure and not J.IsFinishingLaningAttack(bot, attackTarget)
			and LaneCamp.Think(bot, campPlan) then return end
		local_mode_laning_generic.Think()
		return
	end
	if underPressure then
		TraceLaneDecision('yield-pressure')
		local lane = botAssignedLane or bot:GetAssignedLane()
		local team = bot:GetTeam()
		local tower = laneTierOne[lane] and GetTower(team, laneTierOne[lane])
		local fallback = J.GetTeamFountain()
		if J.IsValidBuilding(tower) then
			local direction = team == TEAM_RADIANT and 1 or -1
			local here = GetAmountAlongLane(lane, bot:GetLocation()).amount
			local shelter = GetAmountAlongLane(lane, tower:GetLocation()).amount
			if (here - shelter) * direction > 0 and not J.IsInRange(bot, tower, 450) then
				fallback = tower:GetLocation()
			end
		end
		bot:Action_MoveToLocation(fallback)
		return
	end

	if J.IsValid(attackTarget) and attackTarget:IsCreep() and J.IsFinishingLaningAttack(bot, attackTarget) then return end
	nFurthestEnemyAttackRange = GetFurthestEnemyAttackRange(nInRangeEnemy)
	nEnemyCreeps = bot:GetNearbyLaneCreeps(botAttackRange < 310 and 1200 or math.min(1600, math.max(800, botAttackRange + 300)), true)
	nAllyCreeps = bot:GetNearbyLaneCreeps(1200, false)
	botAssignedLane = bot:GetAssignedLane()
	local hitCreep, moveToCreep, reserve, urgentApproach, approachStep = J.GetLaningLastHitTarget(bot, nEnemyCreeps, enemyTower,
		J.GetLaningAttackDamage(bot), nInRangeEnemy)
	-- Trace inputs as decision evidence, not as a claim that a creep was missed.
	if J.IsCore(bot) and #nEnemyCreeps == 0 then TraceLaneDecision('no-near-wave')
	elseif moveToCreep then TraceLaneDecision(approachStep and not urgentApproach and 'stage-last-hit' or 'approach-window', hitCreep)
	elseif reserve then TraceLaneDecision('hold-for-shot')
	elseif hitCreep == nil then TraceLaneDecision('no-lethal-window') end
	if hitCreep ~= nil and not moveToCreep then
		TraceLaneDecision('last-hit-order', hitCreep)
		if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'last-hit-now') end
		bot:SetTarget(hitCreep)
		J.IssueLaningAttack(bot, hitCreep)
		return
	end
	local together = J.GetLaningTowerJointHit(bot, bot:GetNearbyTowers(1050, false)[1], nInRangeEnemy)
	if together then
		TraceLaneDecision('joint-tower-hit', together)
		if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'joint-tower-hit') end
		J.IssueLaningAttack(bot, together)
		return
	end
	if reserve then
		if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'last-hit-window') end
		J.HoldLaningAttack(bot, attackTarget)
		return
	end

	local firingPosition = approachStep or (moveToCreep
		and J.GetLaningCreepPosition(bot, botAssignedLane, {hitCreep}, enemyTower, nInRangeEnemy, true)) or nil
	-- A recovering core should enter last-hit range before an optional deny
	-- can pin it behind the next enemy creep. Never walk without a safe point.
	if firingPosition ~= nil and (urgentApproach or J.IsCore(bot)) then
		if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'safe-core-last-hit') end
		bot:Action_MoveToLocation(firingPosition)
		return
	end

	local denyCreep, reserveDeny, urgentDeny = J.GetLaningDenyTarget(bot, nAllyCreeps, enemyTower, nInRangeEnemy)
	if urgentDeny and J.IsValid(denyCreep) then
		TraceLaneDecision('deny-order',denyCreep)
		if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'deny-now') end
		bot:SetTarget(denyCreep)
		J.IssueLaningAttack(bot, denyCreep)
		return
	end
	if J.GetSideLaneReturnScreen and not J.IsFinishingLaningAttack(bot, attackTarget) then
		local screen = J.GetSideLaneReturnScreen(bot)
		if screen then
			TraceLaneDecision('screen-return')
			if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'screen-return') end
			bot:Action_MoveToLocation(screen)
			return
		end
	end
	local cover = J.GetSideLaneCoverAttack(bot, nInRangeEnemy, enemyTower)
	if cover and not J.IsFinishingLaningAttack(bot, attackTarget) then
		TraceLaneDecision('cover-core',cover)
		if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'protect-core-now') end
		bot:Action_AttackUnit(cover, true)
		return
	end
	if approachStep ~= nil then
		if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'last-hit-approach') end
		bot:Action_MoveToLocation(approachStep)
		return
	end
	local camp = campPlan or bot.ohaLaneCamp
	if camp and (camp.kind == 'pull' or camp.kind == 'probe') and not J.IsFinishingLaningAttack(bot, attackTarget)
		and LaneCamp.Think(bot, camp) then return end
	if not denyCreep and not reserveDeny and not J.IsFinishingLaningAttack(bot, attackTarget) then
		local point, deny = J.GetLaningDenyStep(bot, nAllyCreeps, enemyTower, nInRangeEnemy)
		if point then
			TraceLaneDecision('deny-step', deny)
			if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'valuable-deny') end
			bot:Action_MoveToLocation(point)
			return
		end
	end
	if not J.IsFinishingLaningAttack(bot, attackTarget) then
		local target, step, tradeClash = J.GetSideLaneDuoTrade(bot, nInRangeEnemy, enemyTower, botAttackRange)
		if target then
			if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'side-duo-trade') end
			if step then
				TraceLaneDecision('side-duo-step', target)
				bot:Action_MoveToLocation(step)
			else
				IssueLaneTradeShot(target, tradeClash, 'side-duo-shot')
			end
			return
		end
	end
	if campPlan ~= nil and campPlan.kind == 'stack' and not J.IsFinishingLaningAttack(bot, attackTarget)
		and LaneCamp.Think(bot, campPlan) then return end

	if not J.IsFinishingLaningAttack(bot, attackTarget) then
		local finish = J.GetSideLaneFinishTarget(bot, nInRangeEnemy, enemyTower)
		if finish ~= nil then bot:Action_AttackUnit(finish, true); return end
	end

	-- Real last hits remain first. Pressure the returning offlaner before an
	-- optional support deny, and only move a short distance with lane cover.
	if not J.IsCore(bot) and not J.IsFinishingLaningAttack(bot, attackTarget)
		and J.CanSpendLaneTradeTime(bot, enemyTower, nInRangeEnemy, bot:GetSecondsPerAttack()) then
		local press = J.GetSideLanePressureTarget(bot, nInRangeEnemy, enemyTower, botAttackRange)
		if press ~= nil then
			IssueLaneTradeShot(press, J.GetVisibleLaneClash(bot), 'side-pressure-shot')
			return
		end
		local step = J.GetSideLanePressureStep(bot, nInRangeEnemy, enemyTower)
		if step ~= nil then
			TraceLaneDecision('side-pressure-step')
			bot:Action_MoveToLocation(step)
			return
		end
	end
	if firingPosition == nil and J.RunSideLaneCreepDrag(bot, nInRangeEnemy, enemyTower, false) then return end
	if J.IsValid(denyCreep) then
		bot:SetTarget(denyCreep)
		J.IssueLaningAttack(bot, denyCreep)
		return
	end

	if reserveDeny then
		J.HoldLaningAttack(bot, attackTarget)
		return
	end

	if firingPosition then
		bot:Action_MoveToLocation(firingPosition)
		return
	end

	if J.IsFinishingLaningAttack(bot, attackTarget) then return end
	if ShootAtLaneClash(nInRangeEnemy, enemyTower, nearbyTower) then return end
	local tradeHasTime = botAssignedLane == LANE_MID
		or J.CanSpendLaneTradeTime(bot, enemyTower, nInRangeEnemy, bot:GetSecondsPerAttack())
	local harassTarget = not nearbyTower and tradeHasTime
		and J.GetLaningHarassTarget(bot, nInRangeEnemy, enemyTower, #bot:GetNearbyLaneCreeps(600, true))
	if harassTarget then
		bot:Action_AttackUnit(harassTarget, true)
		return
	end

	local nLongestAttackRange = math.max(botAttackRange, 250, nFurthestEnemyAttackRange)
	if J.IsCore(bot) and #nAllyCreeps > 0 then
		nLongestAttackRange = math.max(botAttackRange, 280)
	end
	local setup = J.GetLaningCreepPosition(bot, botAssignedLane, nEnemyCreeps, enemyTower, nInRangeEnemy)
	local target_loc = setup
		or GetLaneFrontLocation(GetTeam(), botAssignedLane, -nLongestAttackRange)
	if GetUnitToLocationDistance(bot, target_loc) > (setup and 30 or 100) then
		bot:Action_MoveToLocation(target_loc)
	else
		J.HoldLaningAttack(bot, attackTarget)
	end
end

-- Omitting this callback lets the engine time lane attacks and denies.
if not engineMid and not engineSideCore then Think = ThinkLane end

function OnEnd()
	laneShot = nil
	if bot.ohaCreepDrag then
		bot.ohaCreepDrag = nil
		if not bot:IsUsingAbility() and not bot:IsChanneling() then bot:Action_ClearActions(true) end
	end
	campPlan = nil
	LaneCamp.Cancel(bot)
end


function PickOneAnnouncer()
	if not hasPickedOneAnnouncer then
		for i, _ in pairs(GetTeamPlayers(GetTeam())) do
			local member = GetTeamMember(i)
			if member ~= nil and member.isAnnouncer then return end
		end
		bot.isAnnouncer = true
		hasPickedOneAnnouncer = true
	end
end

function AnnounceMessages()
	-- Only pre-game chatter
	if DotaTime() > 60 then return end

	local welcomeMessages = Localization.Get('welcome_msgs')
	local inTurbo         = J.IsModeTurbo()

	-- Staggered lines during negative DotaTime pre-game
	if ((inTurbo and DotaTime() > -50 + GetTeam() * 2) or (not inTurbo and DotaTime() > -75 + GetTeam() * 2))
	   and numberAnnouncePrinted < #welcomeMessages + 1
	   and bot.isAnnouncer
	   and DotaTime() < 0
	then
		if GameTime() - lastAnnouncePrintedTime >= announcementGapSeconds then
			local message      = welcomeMessages[numberAnnouncePrinted]
			local isFirstLine  = (numberAnnouncePrinted == 1)
			if message then
				-- Match original behavior: first line (or if no enemy bots) can be global
				bot:ActionImmediate_Chat(isFirstLine and (message .. Version.number) or message, enemyBots == 0 or isFirstLine)
			end
			numberAnnouncePrinted   = numberAnnouncePrinted + 1
			lastAnnouncePrintedTime = GameTime()
		end
	end

	-- Announce role during pre-game
	if GetGameMode() ~= GAMEMODE_1V1MID
	   and GetGameState() == GAME_STATE_PRE_GAME
	   and (bot.announcedRole == nil or bot.announcedRole ~= J.GetPosition(bot))
	then
		bot.announcedRole = J.GetPosition(bot)
		bot:ActionImmediate_Chat(Localization.Get('say_play_pos') .. J.GetPosition(bot), false)
	end

	-- Close position selection after horn if humans and bots mixed
	if GetGameMode() ~= GAMEMODE_1V1MID and not isChangePosMessageDone then
		if DotaTime() >= 0 and teamHumans > 0 and teamBots > 0 then
			bot:ActionImmediate_Chat(Localization.Get('pos_select_closed'), true)
			isChangePosMessageDone = true
		end
	end
end
