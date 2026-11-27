local Utils = require( GetScriptDirectory()..'/FunLib/utils')
local J = require( GetScriptDirectory()..'/FunLib/jmz_func')
local LaneCamp = require(GetScriptDirectory() .. '/FunLib/lane_camp')

local Version      = require(GetScriptDirectory()..'/FunLib/version')
local Localization = require(GetScriptDirectory()..'/FunLib/localization')


local bot = GetBot()
if bot == nil then return end
local botName = bot:GetUnitName()
if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

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
local nextLaneTrace, lastLaneTrace = -math.huge, nil
local function TraceLaneDecision(kind, target)
	if not J.Customize or not J.Customize.TraceLaneDecisions then return end
	local now=DotaTime()
	if now>600 or kind==lastLaneTrace and now<nextLaneTrace then return end
	lastLaneTrace,nextLaneTrace=kind,now+4
	print('[OHA lane]',now,bot:GetPlayerID(),bot:GetAssignedLane(),kind,
		target and target:GetUnitName() or '-',math.floor(J.GetHP(bot)*100))
end
local laneTierOne = {[LANE_TOP] = TOWER_TOP_1, [LANE_MID] = TOWER_MID_1, [LANE_BOT] = TOWER_BOT_1}

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

local function GetOpeningLaneDestination(lane, enemies)
	local now = DotaTime()
	if firstWaveReached or now < -5 or now > 100
		or GetGameMode() == GAMEMODE_MO or GetGameMode() == GAMEMODE_1V1MID then return nil end
	local towerId = laneTierOne[lane]
	local tower = towerId ~= nil and GetTower(GetTeam(), towerId) or nil
	if not J.IsValidBuilding(tower) then return nil end
	if J.IsInRange(bot, tower, 850) then
		firstWaveReached = true
		return nil
	end
	if J.IsLaningUnderPressure(bot, enemies, nil) then return nil end
	return tower:GetLocation()
end

function GetDesire()
	campPlan = nil
	PickOneAnnouncer()
	AnnounceMessages()

	if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return BOT_MODE_DESIRE_NONE end
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
	local enemyTower = bot:GetNearbyTowers(1200, true)[1]
	local underPressure = J.IsLaningUnderPressure(bot, nInRangeEnemy, enemyTower)

	if GetOpeningLaneDestination(botAssignedLane, nInRangeEnemy) ~= nil then return 0.72 end
	if GetGameMode() == 23 then currentTime = currentTime * 1.65 end
	if currentTime < 0 then return BOT_ACTION_DESIRE_NONE end

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
		local hitCreep, moveToCreep, reserve, urgentApproach = J.GetLaningLastHitTarget(bot, nEnemyCreeps, enemyTower,
			J.GetLaningAttackDamage(bot), nInRangeEnemy)
		if J.IsValid(hitCreep) and not moveToCreep and J.IsInRange(bot, hitCreep, botAttackRange + 100) then
			if J.GetPosition(bot) <= 3 then return 0.9 end
			if GetUnitToUnitDistance(bot, hitCreep) <= botAttackRange then return 0.55 end
		end
		if urgentApproach and J.IsCore(bot)
			and J.GetLaningCreepPosition(bot, botAssignedLane, {hitCreep}, enemyTower, nInRangeEnemy, true) ~= nil then return 0.74 end
		local deny, reserveDeny, urgentDeny = J.GetLaningDenyTarget(bot, nAllyCreeps, enemyTower, nInRangeEnemy)
		if urgentDeny and not local_mode_laning_generic then return 0.76 end
		if not local_mode_laning_generic and hitCreep == nil and not reserve
			and J.GetSideLaneCreepDrag(bot, nInRangeEnemy, enemyTower) then return 0.73 end
		if not local_mode_laning_generic
			and J.GetSideLaneCoverAttack(bot, nInRangeEnemy, enemyTower) ~= nil then return 0.75 end
		if not local_mode_laning_generic
			and J.GetSideLaneFinishTarget(bot, nInRangeEnemy, enemyTower) ~= nil then return 0.75 end
		if not local_mode_laning_generic then
			if J.GetSideLanePressureTarget(bot, nInRangeEnemy, enemyTower, botAttackRange) ~= nil then return 0.71 end
			if J.GetSideLanePressureStep(bot, nInRangeEnemy, enemyTower) ~= nil then return 0.68 end
		end
		if deny ~= nil or reserveDeny then return 0.7 end
		if botAssignedLane == LANE_MID and J.IsCore(bot) and (reserve or moveToCreep) then
			return 0.7
		end
		if J.IsCore(bot) and (reserve or moveToCreep
			or J.GetLaningCreepPosition(bot, botAssignedLane, nEnemyCreeps, enemyTower, nInRangeEnemy) ~= nil) then
			return 0.57
		end
		campPlan = LaneCamp.Plan(bot, botAssignedLane)
		if campPlan ~= nil then return 0.63 end
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
	if not bot:IsAlive() or J.CanNotUseAction(bot) or bot:IsDisarmed()
		or bot:IsUsingAbility() or bot:IsChanneling() then return end
	nInRangeEnemy = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	if bot.ohaCreepDrag and J.RunSideLaneCreepDrag(bot, nInRangeEnemy, nil, true) then return end
	local opening = GetOpeningLaneDestination(botAssignedLane or bot:GetAssignedLane(), nInRangeEnemy)
	if opening ~= nil then
		bot:Action_MoveToLocation(opening)
		return
	end
	local holdTower = J.GetLaningHoldTower(bot)
	if holdTower ~= nil then
		local wave, covered = J.GetTowerCoveredLaneCreeps(bot, holdTower, bot:GetNearbyLaneCreeps(1000, true), nInRangeEnemy)
		local current = bot:GetAttackTarget()
		local hold = J.AdjustLocationWithOffsetTowardsFountain(holdTower:GetLocation(), 300)
		if #wave > 0 then
			local pending = J.HasPendingLaningLastHit(bot) and bot.ohaLaningAttackTarget or nil
			if pending or J.IsFinishingLaningAttack(bot, current) then
				for _, creep in ipairs(wave) do if (pending or current) == creep then return end end
			end
			local creep, approach = J.GetLaningLastHitTarget(bot, wave, nil, J.GetLaningAttackDamage(bot), nInRangeEnemy, true)
			if creep ~= nil and not approach then J.IssueLaningAttack(bot, creep); return end
			if approach and not J.IsLaningUnderPressure(bot, nInRangeEnemy, nil)
				and #J.GetEnemiesNearLoc(creep:GetLocation(), 750) == 0 then
				bot:Action_MoveToUnit(creep)
				return
			end
			if covered then
				local point = J.AdjustLocationWithOffsetTowardsFountain(wave[1]:GetLocation(), math.max(240, bot:GetAttackRange() - 50))
				if IsLocationPassable(point) and #J.GetLastSeenEnemiesNearLoc(point, 900) == 0 then hold = point end
			end
		end
		if GetUnitToLocationDistance(bot, hold) > 90 then
			bot:Action_MoveToLocation(hold)
		elseif J.IsValid(current) then
			bot:Action_ClearActions(true)
		end
		return
	end
	local enemyTower = bot:GetNearbyTowers(1200, true)[1]
	local attackTarget = bot:GetAttackTarget()
	local underPressure = J.IsLaningUnderPressure(bot, nInRangeEnemy, enemyTower)
	if not underPressure and J.HasPendingLaningLastHit(bot) then return end
	if local_mode_laning_generic then
		if campPlan ~= nil and not underPressure and not J.IsFinishingLaningAttack(bot, attackTarget)
			and LaneCamp.Think(bot, campPlan) then return end
		local_mode_laning_generic.Think()
		return
	end
	if underPressure then
		TraceLaneDecision('yield-pressure')
		bot:Action_MoveToLocation(GetLaneFrontLocation(GetTeam(), botAssignedLane or bot:GetAssignedLane(), -1200))
		return
	end

	if J.IsValid(attackTarget) and attackTarget:IsCreep() and J.IsFinishingLaningAttack(bot, attackTarget) then return end
	nFurthestEnemyAttackRange = GetFurthestEnemyAttackRange(nInRangeEnemy)
	nEnemyCreeps = bot:GetNearbyLaneCreeps(botAttackRange < 310 and 1200 or math.min(1600, math.max(800, botAttackRange + 300)), true)
	nAllyCreeps = bot:GetNearbyLaneCreeps(1200, false)
	botAssignedLane = bot:GetAssignedLane()
	local hitCreep, moveToCreep, reserve, urgentApproach = J.GetLaningLastHitTarget(bot, nEnemyCreeps, enemyTower,
		J.GetLaningAttackDamage(bot), nInRangeEnemy)
	if hitCreep ~= nil and not moveToCreep then
		TraceLaneDecision('last-hit-order', hitCreep)
		if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'last-hit-now') end
		bot:SetTarget(hitCreep)
		J.IssueLaningAttack(bot, hitCreep)
		return
	end
	if reserve then
		J.HoldLaningAttack(bot, attackTarget)
		return
	end

	local firingPosition = moveToCreep
		and J.GetLaningCreepPosition(bot, botAssignedLane, {hitCreep}, enemyTower, nInRangeEnemy, true) or nil
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
	local cover = J.GetSideLaneCoverAttack(bot, nInRangeEnemy, enemyTower)
	if cover and not J.IsFinishingLaningAttack(bot, attackTarget) then
		TraceLaneDecision('cover-core',cover)
		if bot.ohaLaneCamp then LaneCamp.Cancel(bot, 'protect-core-now') end
		bot:Action_AttackUnit(cover, true)
		return
	end
	if campPlan ~= nil and not J.IsFinishingLaningAttack(bot, attackTarget)
		and LaneCamp.Think(bot, campPlan) then return end

	if not J.IsFinishingLaningAttack(bot, attackTarget) then
		local finish = J.GetSideLaneFinishTarget(bot, nInRangeEnemy, enemyTower)
		if finish ~= nil then bot:Action_AttackUnit(finish, true); return end
	end

	-- Real last hits remain first. Pressure the returning offlaner before an
	-- optional support deny, and only move a short distance with lane cover.
	if not J.IsCore(bot) and not J.IsFinishingLaningAttack(bot, attackTarget) then
		local press = J.GetSideLanePressureTarget(bot, nInRangeEnemy, enemyTower, botAttackRange)
		if press ~= nil then bot:Action_AttackUnit(press, true); return end
		local step = J.GetSideLanePressureStep(bot, nInRangeEnemy, enemyTower)
		if step ~= nil then bot:Action_MoveToLocation(step); return end
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
	local harassTarget = J.GetLaningHarassTarget(bot, nInRangeEnemy, enemyTower, #bot:GetNearbyLaneCreeps(600, true))
	if harassTarget ~= nil then
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

-- Omitting this callback lets the engine time the ranged mid's attacks and denies.
-- Heroes that need a script override and the two side lanes keep their lane controller.
if not engineMid then Think = ThinkLane end

function OnEnd()
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
