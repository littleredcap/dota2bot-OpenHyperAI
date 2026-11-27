--------------------------------------------------------------------
-- mode_laning_generic.lua (override for weak/buggy heroes)
--------------------------------------------------------------------
local J = require( GetScriptDirectory()..'/FunLib/jmz_func')

BotsInit = require( "game/botsinit" )
local X = BotsInit.CreateGeneric()

local bot = GetBot()

function X.OnStart() end
function X.OnEnd() end

local assignedLane
local tangoDesire, tangoTarget, tangoSlot

function X.GetDesire()
	tangoDesire, tangoTarget = ConsiderTango()
	if tangoDesire > 0 then
		return BOT_MODE_DESIRE_ABSOLUTE
	end

	if not assignedLane then assignedLane = X.GetBotTargetLane() end

	if GetGameMode() == GAMEMODE_1V1MID or GetGameMode() == GAMEMODE_MO then return 1 end

	local currentTime = DotaTime()
	local botLV = bot:GetLevel()

	if GetGameMode() == 23 then currentTime = currentTime * 1.65 end
	if currentTime <= 10 then return 0.268 end
	if currentTime <= 9 * 60 and botLV <= 7 then return 0.446 end
	if currentTime <= 12 * 60 and botLV <= 11 then return 0.369 end
	if botLV <= 15 and J.GetCoresAverageNetworth() < 12000 then return 0.228 end

	return BOT_MODE_DESIRE_VERYLOW
end

function X.GetBotTargetLane()
	if assignedLane then return assignedLane end

	if GetTeam() == TEAM_RADIANT then
		if J.GetPosition(bot) == 2 then assignedLane = LANE_MID
		elseif J.GetPosition(bot) == 1 or J.GetPosition(bot) == 5 then assignedLane = LANE_BOT
		elseif J.GetPosition(bot) == 3 or J.GetPosition(bot) == 4 then assignedLane = LANE_TOP
		end
	else
		if J.GetPosition(bot) == 2 then assignedLane = LANE_MID
		elseif J.GetPosition(bot) == 1 or J.GetPosition(bot) == 5 then assignedLane = LANE_TOP
		elseif J.GetPosition(bot) == 3 or J.GetPosition(bot) == 4 then assignedLane = LANE_BOT
		end
	end
	return assignedLane
end

--------------------------------------------------------------------
-- Think (reference structure with local additions)
--------------------------------------------------------------------
function X.Think()
	if not bot:IsAlive() or J.CanNotUseAction(bot) or bot:IsUsingAbility() or bot:IsChanneling() or bot:IsDisarmed() then return end

	local botAttackRange = bot:GetAttackRange()
	local botAssignedLane = assignedLane or bot:GetAssignedLane()
	local nAllyCreeps = bot:GetNearbyLaneCreeps(1200, false)
	local nEnemyCreeps = bot:GetNearbyLaneCreeps(1200, true)
	local tEnemyHeroes = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	local tEnemyTowers = bot:GetNearbyTowers(1200, true)

	-- Tango usage (local addition)
	if tangoDesire and tangoDesire > 0 and tangoTarget then
		local hItem = bot:GetItemInSlot(tangoSlot)
		bot:Action_UseAbilityOnTree(hItem, tangoTarget)
		return
	end

	-- Safety: retreat if being targeted by heroes, tower, or heavy creep damage (reference pattern)
	if J.IsLaningUnderPressure(bot, tEnemyHeroes, tEnemyTowers[1])
	or (bot:WasRecentlyDamagedByCreep(2.0) and not (bot:HasModifier('modifier_tower_aura') or bot:HasModifier('modifier_tower_aura_bonus')) and #nAllyCreeps > 0) then
		local safeLoc = GetLaneFrontLocation(GetTeam(), botAssignedLane, -1200)
		bot:Action_MoveToLocation(safeLoc)
		return
	end


	local attackTarget = bot:GetAttackTarget()
	if J.HasPendingLaningLastHit(bot)
		or (J.IsValid(attackTarget) and attackTarget:IsCreep() and J.IsFinishingLaningAttack(bot, attackTarget)) then return end

	-- Drop tower aggro (reference pattern)
	if bot:WasRecentlyDamagedByTower(1.0) and #nEnemyCreeps > 0 then
		local nEnemyTowersClose = bot:GetNearbyTowers(750, true)
		if #nEnemyTowersClose > 0 then
			for _, creep in pairs(nEnemyCreeps) do
				if J.IsValid(creep) and GetUnitToUnitDistance(creep, nEnemyTowersClose[1]) < 700
					and J.CanSupportTakeLaneLastHit(bot, creep) then
					bot:Action_AttackUnit(creep, true)
					return
				end
			end
		end
	end

	-- Stay away from enemy tower if few creeps
	if J.IsValidBuilding(tEnemyTowers[1]) then
		local dist = GetUnitToUnitDistance(bot, tEnemyTowers[1])
		if dist < 800 and #nEnemyCreeps < 3 then
			bot:Action_MoveToLocation(J.VectorAway(bot:GetLocation(), tEnemyTowers[1]:GetLocation(), 800))
			return
		end
	end

	local hitCreep, moveToCreep, reserve, urgentApproach = J.GetLaningLastHitTarget(bot, nEnemyCreeps, tEnemyTowers[1],
		J.GetLaningAttackDamage(bot), tEnemyHeroes)
	if hitCreep ~= nil and not moveToCreep then
		J.IssueLaningAttack(bot, hitCreep)
		return
	end
	if reserve then
		J.HoldLaningAttack(bot, attackTarget)
		return
	end

	local firingPosition = moveToCreep
		and J.GetLaningCreepPosition(bot, botAssignedLane, {hitCreep}, tEnemyTowers[1], tEnemyHeroes, true) or nil
	if urgentApproach and firingPosition ~= nil then
		bot:Action_MoveToLocation(firingPosition)
		return
	end

	-- Deny
	local denyCreep, reserveDeny = J.GetLaningDenyTarget(bot, nAllyCreeps, tEnemyTowers[1], tEnemyHeroes)
	if J.IsValid(denyCreep) then
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
	local harassTarget = J.GetLaningHarassTarget(bot, tEnemyHeroes, tEnemyTowers[1], #bot:GetNearbyLaneCreeps(600, true))
	if harassTarget ~= nil then
		bot:Action_AttackUnit(harassTarget, true)
		return
	end

	-- Positioning
	local nFurthestEnemyAttackRange = GetFurthestEnemyAttackRange(tEnemyHeroes)
	if nFurthestEnemyAttackRange == 0 then
		nFurthestEnemyAttackRange = math.max(botAttackRange, 330)
	end

	if J.IsCore(bot) and #nAllyCreeps > 0 then
		nFurthestEnemyAttackRange = math.max(botAttackRange, 280)
	end
	local setup = J.GetLaningCreepPosition(bot, botAssignedLane, nEnemyCreeps, tEnemyTowers[1], tEnemyHeroes)
	local target_loc = setup
		or GetLaneFrontLocation(GetTeam(), botAssignedLane, -nFurthestEnemyAttackRange)

	if GetUnitToLocationDistance(bot, target_loc) > (setup and 30 or 100) then
		bot:Action_MoveToLocation(target_loc)
	else
		J.HoldLaningAttack(bot, attackTarget)
	end
end

--------------------------------------------------------------------
-- Helper functions
--------------------------------------------------------------------
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

function ConsiderTango()
	if bot:HasModifier('modifier_tango_heal') then return BOT_ACTION_DESIRE_NONE, nil end

	tangoDesire = 0
	tangoSlot = J.FindItemSlotNotInNonbackpack(bot, "item_tango")
	if tangoSlot < 0 then
		tangoSlot = J.FindItemSlotNotInNonbackpack(bot, "item_tango_single")
	end
	if tangoSlot >= 0
	and bot:OriginalGetMaxHealth() - bot:OriginalGetHealth() > 250
	and J.GetHP(bot) > 0.15
	and not J.IsAttacking(bot)
	and not bot:WasRecentlyDamagedByAnyHero(2) then
		local trees = bot:GetNearbyTrees(800)
		local targetTree = trees[1]
		local nearEnemyList = J.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE)
		local nearestEnemy = nearEnemyList[1]
		local nearTowerList = bot:GetNearbyTowers(1400, true)
		local nearestTower = nearTowerList[1]
		if targetTree ~= nil then
			local targetTreeLoc = GetTreeLocation(targetTree)
			if IsLocationVisible(targetTreeLoc)
			and IsLocationPassable(targetTreeLoc)
			and (#nearEnemyList == 0 or GetUnitToLocationDistance(bot, targetTreeLoc) * 1.6 < GetUnitToUnitDistance(bot, nearestEnemy))
			and (#nearTowerList == 0 or GetUnitToLocationDistance(nearestTower, targetTreeLoc) > 920)
			then
				return BOT_ACTION_DESIRE_HIGH, targetTree
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end

return X
