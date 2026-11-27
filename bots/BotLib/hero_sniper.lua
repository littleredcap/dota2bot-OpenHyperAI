----------------------------------------------------------------------------------------------------
--- The Creation Come From: BOT EXPERIMENT Credit:FURIOUSPUPPY
--- BOT EXPERIMENT Author: Arizona Fauzie 2018.11.21
--- Link:http://steamcommunity.com/sharedfiles/filedetails/?id=837040016
--- Refactor: 决明子 Email: dota2jmz@163.com 微博@Dota2_决明子
--- Link:http://steamcommunity.com/sharedfiles/filedetails/?id=1573671599
--- Link:http://steamcommunity.com/sharedfiles/filedetails/?id=1627071163
----------------------------------------------------------------------------------------------------
local X = {}
local bDebugMode = ( 1 == 10 )
local bot = GetBot()

local J = require( GetScriptDirectory()..'/FunLib/jmz_func' )
local Minion = dofile( GetScriptDirectory()..'/FunLib/aba_minion' )
local sTalentList = J.Skill.GetTalentList( bot )
local sAbilityList = J.Skill.GetAbilityList( bot )
local sRole = J.Item.GetRoleItemsBuyList( bot )

local tTalentTreeList = {
						['t25'] = {0, 10},
						['t20'] = {0, 10},
						['t15'] = {0, 10},
						['t10'] = {10, 0},
}

local tAllAbilityBuildList = {
						{2,1,3,2,1,6,1,1,2,2,3,6,3,3,6},
}
if sRole == 'pos_2' then
	tAllAbilityBuildList = {{2,3,2,1,2,6,2,1,1,1,3,6,3,3,6}}
end

local nAbilityBuildList = J.Skill.GetRandomBuild( tAllAbilityBuildList )

local nTalentBuildList = J.Skill.GetTalentBuild( tTalentTreeList )

local sRoleItemsBuyList = {}

sRoleItemsBuyList['pos_1'] = {
	"item_ranged_carry_outfit",
	"item_dragon_lance",
	"item_maelstrom",
	"item_hurricane_pike",--
	"item_mask_of_madness",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_travel_boots",
	"item_monkey_king_bar",--
	"item_mjollnir",--
	"item_broken_satanic",--
	"item_moon_shard",
	"item_hydras_breath",--
	"item_skadi",--
	"item_travel_boots_2",--
	"item_ultimate_scepter_2",
}

sRoleItemsBuyList['pos_2'] = {
	"item_mid_outfit",
	"item_dragon_lance",
	"item_maelstrom",
	"item_hurricane_pike",--
	"item_mask_of_madness",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_travel_boots",
	"item_monkey_king_bar",--
	"item_mjollnir",--
	"item_broken_satanic",--
	"item_moon_shard",
	"item_hydras_breath",--
	"item_skadi",--
	"item_travel_boots_2",--
	"item_ultimate_scepter_2",
}

sRoleItemsBuyList['pos_4'] = sRoleItemsBuyList['pos_1']

sRoleItemsBuyList['pos_5'] = sRoleItemsBuyList['pos_1']

sRoleItemsBuyList['pos_3'] = sRoleItemsBuyList['pos_1']

X['sBuyList'] = sRoleItemsBuyList[sRole]

X['sSellList'] = {
	"item_mjollnir",
	"item_magic_wand",

	"item_greater_crit", 
	"item_hand_of_midas",
}

if J.Role.IsPvNMode() or J.Role.IsAllShadow() then X['sBuyList'], X['sSellList'] = { 'PvN_mid' }, {} end

nAbilityBuildList, nTalentBuildList, X['sBuyList'], X['sSellList'] = J.SetUserHeroInit( nAbilityBuildList, nTalentBuildList, X['sBuyList'], X['sSellList'] )

X['sSkillList'] = J.Skill.GetSkillList( sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList )

X['bDeafaultAbility'] = false
X['bDeafaultItem'] = false

function X.MinionThink(hMinionUnit)

	if Minion.IsValidUnit( hMinionUnit )
	then
		Minion.IllusionThink( hMinionUnit )
	end

end

--[[

npc_dota_hero_sniper

"Ability1"		"sniper_shrapnel"
"Ability2"		"sniper_headshot"
"Ability3"		"sniper_take_aim"
"Ability4"		"generic_hidden"
"Ability5"		"generic_hidden"
"Ability6"		"sniper_assassinate"
"Ability10"		"special_bonus_cooldown_reduction_25"
"Ability11"		"special_bonus_attack_damage_20"
"Ability12"		"special_bonus_attack_speed_40"
"Ability13"		"special_bonus_unique_sniper_5"
"Ability14"		"special_bonus_unique_sniper_3"
"Ability15"		"special_bonus_unique_sniper_4"
"Ability16"		"special_bonus_attack_range_125"
"Ability17"		"special_bonus_unique_sniper_2"

modifier_sniper_shrapnel_charge_counter
modifier_sniper_shrapnel_thinker
modifier_sniper_shrapnel_slow
modifier_sniper_headshot
modifier_sniper_headshot_slow
modifier_sniper_take_aim
modifier_sniper_take_aim_bonus
modifier_sniper_assassinate_caster
modifier_sniper_assassinate

--]]

local abilityQ = bot:GetAbilityByName( sAbilityList[1] )
local abilityE = bot:GetAbilityByName( sAbilityList[3] )
local abilityAS = bot:GetAbilityByName( sAbilityList[4] )
local abilityR = bot:GetAbilityByName( sAbilityList[6] )


local castQDesire, castQLocation 
local castEDesire 
local castRDesire, castRTarget 
local castASDesire, castASTarget


local nKeepMana, nMP, nHP, nLV, hEnemyHeroList
local lastAbilityQTime = -90
local shrapnelZones = {}
local pendingShrapnel
local shrapnelSpent = 0
local nextShrapnelCharge
local botTarget

local function GetShrapnelCharges()
	-- The bot API exposes item charges, but does not expose Shrapnel's charge count.
	local maximum = abilityQ:GetSpecialValueInt('AbilityCharges')
	return (maximum > 0 and maximum or 3) - shrapnelSpent
end


local function UpdateShrapnel(now)
	if nextShrapnelCharge == nil and pendingShrapnel == nil then return end
	local recharge = abilityQ:GetSpecialValueFloat('AbilityChargeRestoreTime')
	if recharge <= 0 then recharge = 35 end
	while nextShrapnelCharge ~= nil and now >= nextShrapnelCharge do
		shrapnelSpent = shrapnelSpent - 1
		nextShrapnelCharge = shrapnelSpent > 0 and nextShrapnelCharge + recharge or nil
	end
	if pendingShrapnel == nil then return end
	local manaCost = abilityQ:GetManaCost()
	local expectedMana = pendingShrapnel.mana * bot:GetMaxMana() / pendingShrapnel.maxMana
	if abilityQ:IsInAbilityPhase() then
		pendingShrapnel.mana, pendingShrapnel.maxMana = bot:GetMana(), bot:GetMaxMana()
	elseif expectedMana - bot:GetMana() >= manaCost - 5 then
		shrapnelSpent = shrapnelSpent + 1
		nextShrapnelCharge = nextShrapnelCharge or now + recharge
		shrapnelZones[#shrapnelZones + 1] = {
			location = pendingShrapnel.location,
			expires = now + abilityQ:GetSpecialValueFloat('damage_delay') + abilityQ:GetSpecialValueFloat('duration'),
		}
		pendingShrapnel = nil
	elseif now - lastAbilityQTime >= 1.5 then
		pendingShrapnel = nil
	end
end

function X.SkillsComplement()

	UpdateShrapnel(DotaTime())
	if pendingShrapnel ~= nil then return end

	X.ConsiderTarget()
	J.ConsiderForMkbDisassembleMask( bot )

	if J.CanNotUseAbility( bot ) or bot:IsInvisible() then return end

	botTarget = J.GetProperTarget(bot)

	nKeepMana = 280
	nMP = bot:GetMana()/bot:GetMaxMana()
	nHP = bot:GetHealth()/bot:GetMaxHealth()
	nLV = bot:GetLevel()
	hEnemyHeroList = J.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )

	local holdingTower = (J.IsDefending(bot) and J.GetAssignedOuterTower(bot) ~= nil)
		or (DotaTime() >= 240 and DotaTime() <= 780 and J.GetEarlyMidSiegeDefense(bot) ~= nil)
	if holdingTower then castQDesire, castQLocation = X.ConsiderQ() end
	if not holdingTower or castQDesire <= 0 then
		castRDesire, castRTarget = X.ConsiderR()
		if castRDesire > 0 then
			J.SetQueuePtToINT(bot, true)
			bot:ActionQueue_UseAbilityOnEntity(abilityR, castRTarget)
			return
		end

		castEDesire = X.ConsiderE()
		if castEDesire > 0 then
			bot:Action_ClearActions(false)
			bot:ActionQueue_UseAbility(abilityE)
			return
		end
	end

	if not holdingTower then castQDesire, castQLocation = X.ConsiderQ() end
	if castQDesire > 0 and GetUnitToLocationDistance(bot, castQLocation) <= abilityQ:GetCastRange()
	then

		J.SetQueuePtToINT( bot, false )

		lastAbilityQTime = DotaTime()
		pendingShrapnel = {
			location = castQLocation,
			mana = bot:GetMana(),
			maxMana = bot:GetMaxMana(),
		}
		bot:ActionQueue_UseAbilityOnLocation( abilityQ, castQLocation )
		return
	end
	
	castASDesire, castASTarget = X.ConsiderAS()
	if ( castASDesire > 0 )
	then
		
		J.SetQueuePtToINT( bot, true )

		bot:ActionQueue_UseAbilityOnLocation( abilityAS, castASTarget )
		return

	end


end

function X.ConsiderTarget()
	if not J.IsRunning( bot )
		or bot:HasModifier( "modifier_item_hurricane_pike_range" )
	then return  end

	local nAttackRange = bot:GetAttackRange() + 60
	if nAttackRange > 1600 then nAttackRange = 1600 end
	local nInAttackRangeWeakestEnemyHero = J.GetAttackableWeakestUnit( bot, nAttackRange, true, true )

	local nTargetUint = nil

	if J.IsValidHero( botTarget )
		and GetUnitToUnitDistance( botTarget, bot ) >  nAttackRange
		and J.IsValidHero( nInAttackRangeWeakestEnemyHero )
	then
		nTargetUint = nInAttackRangeWeakestEnemyHero
		bot:SetTarget( nTargetUint )
		return
	end

end

function X.HasLaningCreepShot(creeps, enemies, tower)
	local lastHit, approach, reserve = J.GetLaningLastHitTarget(bot, creeps, tower, J.GetLaningAttackDamage(bot), enemies)
	if reserve or (lastHit ~= nil and not approach) then return true end
	local deny, reserveDeny = J.GetLaningDenyTarget(bot, bot:GetNearbyLaneCreeps(1200, false), tower, enemies)
	return deny ~= nil or reserveDeny
end

function X.ConsiderQ()

	if not abilityQ:IsFullyCastable()
		or DotaTime() - lastAbilityQTime < 1.5
	then return 0 end

	local nCastRange = abilityQ:GetCastRange()
	local nSkillLV = abilityQ:GetLevel()
	local nRadius = math.max(abilityQ:GetAOERadius() or 0, abilityQ:GetSpecialValueInt('radius'))
	local nCastPoint = abilityQ:GetCastPoint()
	local impactDelay = nCastPoint + abilityQ:GetSpecialValueFloat('damage_delay')
	local botLocation = bot:GetLocation()

	local nEnemysLaneCreepsInSkillRange = bot:GetNearbyLaneCreeps( 1600, true )
	local nEnemysHeroesInSkillRange = J.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )

	local nCanHurtCreepsLocationAoE = bot:FindAoELocation(true, false, botLocation, nCastRange, nRadius, impactDelay, 0)
	local waveLocation = nCanHurtCreepsLocationAoE and nCanHurtCreepsLocationAoE.targetloc
	local nCanHurtCreepCount = waveLocation and J.GetInLocLaneCreepCount(bot, 1600, nRadius, waveLocation) or 0
	local nCanHurtHeroLocationAoE = bot:FindAoELocation(true, true, botLocation, nCastRange, nRadius - 30, impactDelay, 0)
	local holdTower = J.IsDefending(bot) and J.GetAssignedOuterTower(bot) or nil
	if not holdTower and DotaTime() >= 240 and DotaTime() <= 780 then holdTower = J.GetEarlyMidSiegeDefense(bot) end
	if holdTower ~= nil then
		if waveLocation ~= nil and nCanHurtCreepCount >= 2
			and GetUnitToLocationDistance(holdTower, waveLocation) <= 1050
			and not X.IsAbiltyQCastedHere(waveLocation, nRadius) then
			return BOT_ACTION_DESIRE_HIGH, waveLocation
		end
		-- FindAoELocation can pick a larger cluster elsewhere. Look at the
		-- visible lane creeps approaching our assigned tower independently.
		local aim, count, distance = nil, 1, math.huge
		for _, creep in ipairs(nEnemysLaneCreepsInSkillRange) do
			if J.IsValid(creep) then
				local point = J.GetCorrectLoc(creep, impactDelay)
				local fromTower = GetUnitToLocationDistance(holdTower, point)
				if fromTower <= 1250 and GetUnitToLocationDistance(bot, point) <= nCastRange then
					local hits = J.GetInLocLaneCreepCount(bot, 1600, nRadius - 25, point)
					local siegeNow = J.IsKeyWordUnit and J.IsKeyWordUnit('_siege', creep)
						and (creep:GetAttackTarget() == holdTower or fromTower <= 900)
					local priority = hits + (siegeNow and 2 or 0)
					if (hits >= 2 or siegeNow) and (priority > count or priority == count and fromTower < distance)
						and not X.IsAbiltyQCastedHere(point, nRadius) then
						aim, count, distance = point, priority, fromTower
					end
				end
			end
		end
		if aim ~= nil then return BOT_ACTION_DESIRE_HIGH, aim end
	end

	if J.IsInLaningPhase() and (J.IsLaning(bot) or J.IsGoingOnSomeone(bot) or J.IsRetreating(bot)) then
		local attackRange = bot:GetAttackRange()
		local now = DotaTime()
		-- Escort a live catapult by clearing its blockers, not by blindly
		-- shoving every wave or consuming the last defensive charge.
		if now >= 240 and now <= 780 and bot:GetAssignedLane() == LANE_MID and J.IsLaning(bot)
			and not J.IsRetreating(bot) and not J.IsAttacking(bot) and #nEnemysHeroesInSkillRange <= 1
			and not bot:WasRecentlyDamagedByAnyHero(2) and nHP >= 0.62
			and GetShrapnelCharges() >= 2 and bot:GetMana() >= abilityQ:GetManaCost() * 2
			and waveLocation and nCanHurtCreepCount >= 3
			and GetUnitToLocationDistance(bot, waveLocation) <= nCastRange
			and GetAmountAlongLane(LANE_MID, waveLocation).distance < 600
			and not X.IsAbiltyQCastedHere(waveLocation, nRadius)
			and not X.HasLaningCreepShot(nEnemysLaneCreepsInSkillRange, nEnemysHeroesInSkillRange, bot:GetNearbyTowers(1200, true)[1])
		then
			for _, unit in ipairs(bot:GetNearbyLaneCreeps(1400, false)) do
				if J.IsValid(unit) and J.IsKeyWordUnit('_siege', unit)
					and GetUnitToLocationDistance(unit, waveLocation) <= 900
					and GetAmountAlongLane(LANE_MID, unit:GetLocation()).distance < 550
				then return BOT_ACTION_DESIRE_HIGH, waveLocation end
			end
		end
		if not J.IsRetreating(bot) and (J.IsAttacking(bot) or X.HasLaningCreepShot(nEnemysLaneCreepsInSkillRange,
			nEnemysHeroesInSkillRange, bot:GetNearbyTowers(1200, true)[1])) then return BOT_ACTION_DESIRE_NONE end
		local manaReserve = abilityR:IsTrained() and abilityR:GetManaCost() or abilityQ:GetManaCost()
		if GetShrapnelCharges() >= 2 and bot:GetMana() - abilityQ:GetManaCost() >= manaReserve then
			for _, enemy in ipairs(nEnemysHeroesInSkillRange) do
				if J.IsValidHero(enemy) and J.CanCastOnNonMagicImmune(enemy) and not J.IsSuspiciousIllusion(enemy)
					and (not J.IsRetreating(bot) or J.IsInRange(bot, enemy, attackRange + 150))
					and not enemy:HasModifier('modifier_sniper_shrapnel_slow') then
					local enemyLocation = J.GetCorrectLoc(enemy, impactDelay)
					local location = enemyLocation
					if J.GetInLocLaneCreepCount(bot, 1600, nRadius, enemyLocation) == 0 then
						local closest = nRadius * 1.6
						location = nil
						for _, creep in ipairs(nEnemysLaneCreepsInSkillRange) do
							if J.IsValid(creep) then
								local creepLocation = J.GetCorrectLoc(creep, impactDelay)
								local gap = J.GetLocationToLocationDistance(enemyLocation, creepLocation)
								if gap < closest then
									location, closest = (enemyLocation + creepLocation) / 2, gap
								end
							end
						end
					end
					if location ~= nil and GetUnitToLocationDistance(bot, location) <= nCastRange
						and not X.IsAbiltyQCastedHere(location, nRadius)
					then return BOT_ACTION_DESIRE_HIGH, location end
				end
			end
			if waveLocation ~= nil and #nEnemysHeroesInSkillRange > 0 and nCanHurtCreepCount >= 3
				and GetUnitToLocationDistance(bot, waveLocation) <= nCastRange
				and (J.IsRetreating(bot) or GetUnitToLocationDistance(bot, waveLocation) > attackRange)
				and not X.IsAbiltyQCastedHere(waveLocation, nRadius)
			then return BOT_ACTION_DESIRE_HIGH, waveLocation end
		end
		if not J.IsRetreating(bot) then return BOT_ACTION_DESIRE_NONE end
	end

	if J.IsDefending(bot) and waveLocation ~= nil and nCanHurtCreepCount >= 3
		and not X.IsAbiltyQCastedHere(waveLocation, nRadius)
	then
		return BOT_ACTION_DESIRE_HIGH, waveLocation
	end

	--对多个敌方英雄使用
	if #nEnemysHeroesInSkillRange >= 2
		and nCanHurtHeroLocationAoE ~= nil and (nCanHurtHeroLocationAoE.count or 0) >= 2
		and nCanHurtHeroLocationAoE.targetloc ~= nil
		and bot:GetActiveMode() ~= BOT_MODE_LANING
		and ( bot:GetActiveMode() ~= BOT_MODE_RETREAT or ( bot:GetActiveMode() == BOT_MODE_RETREAT and bot:GetActiveModeDesire() < 0.6 ) )
		and not X.IsAbiltyQCastedHere( nCanHurtHeroLocationAoE.targetloc, nRadius )
	then
		return BOT_ACTION_DESIRE_HIGH, nCanHurtHeroLocationAoE.targetloc
	end

	--对当前目标英雄使用
	if J.IsValidHero( botTarget )
		and not botTarget:HasModifier( "modifier_sniper_shrapnel_slow" )
		and J.CanCastOnNonMagicImmune( botTarget )
		and J.IsInRange( botTarget, bot, nCastRange )
		and ( nSkillLV >= 3 or bot:GetMana() >= nKeepMana )
		and not X.IsAbiltyQCastedHere( botTarget:GetLocation(), nRadius )
	then

		if botTarget:IsFacingLocation( J.GetEnemyFountain(), 30 )
			and J.GetHP( botTarget ) < 0.4
			and J.IsRunning( botTarget )
		then
			--追击减速当前目标
			for i=0, 800, 200
			do
				local nCastLocation = J.GetLocationTowardDistanceLocation( botTarget, J.GetEnemyFountain(), nRadius + 800 - i )
				if GetUnitToLocationDistance( bot, nCastLocation ) <= nCastRange
				then
					return BOT_ACTION_DESIRE_HIGH, nCastLocation
				end
			end
		end

		--对当前目标使用技能
		local npcTargetLocInFuture = J.GetCorrectLoc(botTarget, impactDelay)
		if J.GetLocationToLocationDistance( botTarget:GetLocation(), npcTargetLocInFuture ) > 300
			and botTarget:GetMovementDirectionStability() > 0.4
			and GetUnitToLocationDistance(bot, npcTargetLocInFuture) <= nCastRange
		then
			return BOT_ACTION_DESIRE_HIGH, npcTargetLocInFuture
		end

		--近处预测将到近处来的目标
		local castDistance = GetUnitToUnitDistance( bot, botTarget )
		if botTarget:IsFacingLocation( botLocation, 30 ) and J.IsMoving( botTarget )
		then
			if castDistance > 400
			then
				castDistance = castDistance - 200
			end
			return BOT_ACTION_DESIRE_HIGH, J.GetUnitTowardDistanceLocation( bot, botTarget, castDistance )
		end

		--远处预测将到远处去的目标
		if bot:IsFacingLocation( botTarget:GetLocation(), 30 )
		then
			castDistance = math.min(castDistance + 400, nCastRange)
			return BOT_ACTION_DESIRE_HIGH, J.GetUnitTowardDistanceLocation( bot, botTarget, castDistance )
		end

		--目标位置无规律
		local location = J.GetLocationTowardDistanceLocation(botTarget, J.GetEnemyFountain(), nRadius / 2)
		if GetUnitToLocationDistance(bot, location) > nCastRange then location = botTarget:GetLocation() end
		return BOT_ACTION_DESIRE_HIGH, location

	end

	--撤退时减速
	if J.IsRetreating( bot )
		and not bot:IsInvisible()
	then
		local nCanHurtHeroLocationAoENearby = bot:FindAoELocation( true, true, botLocation, nCastRange - 400, nRadius, 1.5, 0 )
		if nCanHurtHeroLocationAoENearby and nCanHurtHeroLocationAoENearby.targetloc
			and (nCanHurtHeroLocationAoENearby.count or 0) >= 2
			and not X.IsAbiltyQCastedHere( nCanHurtHeroLocationAoENearby.targetloc, nRadius )
		then
			return BOT_ACTION_DESIRE_HIGH, nCanHurtHeroLocationAoENearby.targetloc
		end

		if bot:GetActiveModeDesire() > 0.8
		then
			local nEnemyNearby = J.GetNearbyHeroes(bot, 800, true, BOT_MODE_NONE )
			for _, npcEnemy in pairs( nEnemyNearby )
			do
				if J.IsValid( npcEnemy )
					and bot:WasRecentlyDamagedByHero( npcEnemy, 2.0 )
					and J.CanCastOnNonMagicImmune( npcEnemy )
				then
					local nCastLocation = ( botLocation + npcEnemy:GetLocation() )/2
					if not X.IsAbiltyQCastedHere( nCastLocation, nRadius )
					then
						--对特定位置使用技能
						return BOT_ACTION_DESIRE_HIGH, nCastLocation
					end
				end
			end
		end
	end

	if #hEnemyHeroList == 0
		and nSkillLV >= 3
		and bot:GetActiveMode() ~= BOT_MODE_ATTACK
		and bot:GetActiveMode() ~= BOT_MODE_LANING
		and bot:GetMana() >= nKeepMana
		and #nEnemysLaneCreepsInSkillRange >= 2
		and nCanHurtCreepCount >= 5
		and ( nLV < 25 or nCanHurtCreepCount >= 7 )
		and ( nLV < 20 or GetUnitToLocationDistance( bot, nCanHurtCreepsLocationAoE.targetloc ) >= 1100 )
		and not X.IsAbiltyQCastedHere( nCanHurtCreepsLocationAoE.targetloc, nRadius )
	then
		return BOT_ACTION_DESIRE_HIGH, nCanHurtCreepsLocationAoE.targetloc
	end

	if J.IsFarming( bot ) and bot:GetMana() >= nKeepMana
	then
		local nNeutralCreeps = bot:GetNearbyNeutralCreeps( 800 )
		if #nNeutralCreeps >= 4
			and J.IsValid( botTarget )
			and not J.CanKillTarget( botTarget, bot:GetAttackDamage() * 3.88 , DAMAGE_TYPE_PHYSICAL )
		then
			local nAoE = bot:FindAoELocation( true, false, botLocation, nCastRange, nRadius, 0.8, 0 )
			if nAoE and nAoE.targetloc and (nAoE.count or 0) >= 5
				and not X.IsAbiltyQCastedHere(nAoE.targetloc, nRadius)
			then
				return BOT_ACTION_DESIRE_HIGH, nAoE.targetloc
			end
		end
	end

	if J.IsDoingRoshan( bot )
	then
		local nAttackTarget = bot:GetAttackTarget()
		if J.IsValid( nAttackTarget )
			and J.IsRoshan( nAttackTarget )
			and J.IsInRange( nAttackTarget, bot, nCastRange )
			and J.GetManaAfter( abilityQ:GetManaCost() ) > 0.4
			and not nAttackTarget:HasModifier( "modifier_sniper_shrapnel_slow" )
			and not X.IsAbiltyQCastedHere( nAttackTarget:GetLocation(), nRadius )
		then
			return BOT_ACTION_DESIRE_HIGH, nAttackTarget:GetLocation()
		end
	end

	if J.IsDoingTormentor(bot)
	then
		if J.IsTormentor(botTarget)
        and J.IsInRange( botTarget, bot, nRadius )
        and J.IsAttacking(bot)
		and not botTarget:HasModifier( "modifier_sniper_shrapnel_slow" )
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end

	--farming: shrapnel neutral creep camps with 3+ creeps (conserve charges, higher mana threshold)
	if J.IsFarming( bot )
		and #hEnemyHeroList == 0
		and J.GetManaAfter( abilityQ:GetManaCost() ) > 0.4
		and GetShrapnelCharges() >= 2
	then
		local nNeutralCreeps = bot:GetNearbyNeutralCreeps( nCastRange )
		if #nNeutralCreeps >= 3
		then
			local nFarmAoE = bot:FindAoELocation( true, false, botLocation, nCastRange, nRadius, 0.8, 0 )
			if nFarmAoE and nFarmAoE.targetloc and (nFarmAoE.count or 0) >= 3
				and not X.IsAbiltyQCastedHere( nFarmAoE.targetloc, nRadius )
			then
				return BOT_ACTION_DESIRE_HIGH, nFarmAoE.targetloc
			end
		end
	end

	return 0
end

-- 7.41: Take Aim now has passive attack range (160/240/320/400)
-- plus an active component that grants bonus range (75/150/225/300) for a duration.
function X.ConsiderE()

	if not abilityE:IsFullyCastable()
		or bot:IsDisarmed()
		or J.IsAttacking(bot)
	then return 0 end

	local nAttackRange = bot:GetAttackRange()
	local npcTarget = bot:GetAttackTarget()
	if J.IsInLaningPhase() and J.IsLaning(bot) then
		local tower = bot:GetNearbyTowers(1200, true)[1]
		local creeps = bot:GetNearbyLaneCreeps(math.min(1600, nAttackRange + 120), true)
		if J.GetLaningHarassTarget(bot, hEnemyHeroList, tower, #bot:GetNearbyLaneCreeps(600, true)) ~= npcTarget
			or not J.IsValidHero(npcTarget) then return BOT_ACTION_DESIRE_NONE end
		if X.HasLaningCreepShot(creeps, hEnemyHeroList, tower) then return BOT_ACTION_DESIRE_NONE end
		local _, release = J.GetAttackProDelayTime(bot, npcTarget)
		if release > 0.55 then return BOT_ACTION_DESIRE_NONE end
	end
	
	if J.IsValidHero( npcTarget )
		and not npcTarget:IsAttackImmune()
		and J.IsInRange( bot, npcTarget, nAttackRange )
		and not J.IsRetreating(bot)
	then
		--低地打高地
		if GetHeightLevel( bot:GetLocation() ) < GetHeightLevel( npcTarget:GetLocation() )
		then
			return BOT_ACTION_DESIRE_HIGH
		end
		
		--增加爆头几率
		if J.IsInRange( bot, npcTarget, nAttackRange - 75 )
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

function X.ConsiderR()

	if not abilityR:IsFullyCastable() then return 0 end

	local nCastRange = abilityR:GetCastRange()
	local nCastPoint = abilityR:GetCastPoint()
	local nAttackRange = bot:GetAttackRange()
	if nAttackRange > 1550 then nAttackRange = 1550 end
	local nDamage	 = abilityR:GetAbilityDamage()
	local nDamageType = DAMAGE_TYPE_MAGICAL

	local nEnemysHerosCanSeen = GetUnitList( UNIT_LIST_ENEMY_HEROES )
	local nEnemysHerosInAttackRange = J.GetNearbyHeroes(bot, math.min(nAttackRange + 50, 1600), true, BOT_MODE_NONE )

	local nTempTarget = nEnemysHerosInAttackRange[1]
	if J.IsValidHero( botTarget )
		and J.IsInRange( bot, botTarget, nAttackRange + 50 )
	then nTempTarget = botTarget end

	local nWeakestEnemyHeroInCastRange = X.GetWeakestUnitInRangeExRadius( nEnemysHerosCanSeen, nCastRange, nAttackRange -300, bot )
	local nChannelingEnemyHeroInCastRange = X.GetChannelingUnitInRange( nEnemysHerosCanSeen, nCastRange, bot )
	local castRTarget = nil

	if J.IsValid( nWeakestEnemyHeroInCastRange )
		and ( J.WillMagicKillTarget( bot, nWeakestEnemyHeroInCastRange, nDamage, nCastPoint )
			or ( X.ShouldUseR( nTempTarget, nWeakestEnemyHeroInCastRange, nDamage ) and ( bot:GetMana() > nKeepMana * 1.28 or bot:HasScepter() ) ) )
	then
		castRTarget = nWeakestEnemyHeroInCastRange
		return BOT_ACTION_DESIRE_HIGH, castRTarget
	end

	if J.IsValid( nChannelingEnemyHeroInCastRange )
		and not bot:IsInvisible()
		and not J.IsRetreating( bot )
	then
		castRTarget = nChannelingEnemyHeroInCastRange
		return BOT_ACTION_DESIRE_HIGH, castRTarget
	end

	return 0
end

function X.GetWeakestUnitInRangeExRadius( nUnits, nRange, nRadius, bot )
	if nUnits[1] == nil then return nil end

	local nAttackRange = bot:GetAttackRange()
	local nAttackDamage = bot:GetAttackDamage()
	local weakestUnit = nil
	local weakestHealth = 9999
	for _, unit in pairs( nUnits )
	do
		if J.IsInRange( unit, bot, nRange )
			and not J.IsInRange( unit, bot, nRadius )
			and J.CanCastOnNonMagicImmune( unit )
			and not J.IsOtherAllyCanKillTarget( bot, unit )
			and unit:GetHealth() < weakestHealth
			and not unit:HasModifier( "modifier_teleporting" )
			and not ( J.IsInRange( unit, bot, nAttackRange )
					  and J.CanKillTarget( unit, nAttackDamage, DAMAGE_TYPE_PHYSICAL ) )
		then
			weakestUnit = unit
			weakestHealth = unit:GetHealth()
		end
	end

	return weakestUnit
end

function X.GetChannelingUnitInRange( nUnits, nRange, bot )

	if nUnits[1] == nil then return nil end

	local channelingUnit = nil
	for _, unit in pairs( nUnits )
	do
		if J.IsInRange( unit, bot, nRange )
			and not unit:IsMagicImmune()
			and unit:IsChanneling()
			and not ( unit:HasModifier( "modifier_teleporting" )
					  and X.GetCastPoint( bot, unit ) > J.GetModifierTime( unit, "modifier_teleporting" ) )
		then
			channelingUnit = unit
			break
		end
	end

	return channelingUnit
end

function X.GetCastPoint( bot, unit )

		local nCastTime = abilityR:GetCastPoint()

		local nDist = GetUnitToUnitDistance( bot, unit )
		local nDistTime = nDist/2500

		return nCastTime + nDistTime

end

function X.IsAbiltyQCastedHere( nLoc, nRadius )
	local covered = false
	for i = #shrapnelZones, 1, -1 do
		local zone = shrapnelZones[i]
		if DotaTime() >= zone.expires then
			table.remove(shrapnelZones, i)
		elseif J.GetLocationToLocationDistance(zone.location, nLoc) <= nRadius * 1.14 then
			covered = true
		end
	end
	return covered
end

--判定是否在不能击杀目标的情况下对目标使用大招
--1, 该目标为队友准备攻击的目标且自己没有攻击范围内的攻击目标
--2, 能与宙斯合力击杀目标

function X.ShouldUseR( nAttackTarget, nEnemy, nDamage )
	if J.IsRetreating( bot )
		or ( J.IsValidHero( nAttackTarget ) and J.CanBeAttacked( nAttackTarget )
			and ( GetUnitToUnitDistance( bot, nAttackTarget ) <= bot:GetAttackRange() -300
					or J.CanKillTarget( nAttackTarget, bot:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL ) ) )
	then
		return false
	end

	if J.IsValid( nEnemy )
	then
		local numPlayer =  GetTeamPlayers( GetTeam() )
		for i = 1, #numPlayer
		do
			local member =  GetTeamMember( i )
			if J.IsValid( member )
				and member ~= bot
				and GetUnitToUnitDistance( member, nEnemy ) <= 600
				and ( member:IsFacingLocation( nEnemy:GetLocation(), 20 )
						or not ( J.IsValidHero( nAttackTarget ) and GetUnitToUnitDistance( bot, nAttackTarget ) <= bot:GetAttackRange() ) )
			then
				return true
			end

			if J.IsValid( member )
				and member:GetUnitName() == "npc_dota_hero_zuus"
				and not J.CanNotUseAbility( member )
			then
				local zAbility = member:GetAbilityByName( "zuus_thundergods_wrath" )
				if zAbility:IsFullyCastable()
				then
					local zAbilityDamage = zAbility:GetAbilityDamage()
					if nEnemy:GetHealth() + 66 < nEnemy:GetActualIncomingDamage( zAbilityDamage + nDamage, DAMAGE_TYPE_MAGICAL )
					then
						return true
					end
				end
			end
		end
	end

	return false
end


function X.ConsiderAS()

	if not abilityAS:IsTrained()
		or not abilityAS:IsFullyCastable() 
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nRadius = 375
	local nCastRange = abilityAS:GetCastRange()
	local nCastPoint = abilityAS:GetCastPoint()
	local nManaCost = abilityAS:GetManaCost()


	if J.IsRetreating( bot )
	then
		local enemyHeroList = J.GetNearbyHeroes(bot, nRadius, true, BOT_MODE_NONE )
		local targetHero = enemyHeroList[1]
		if J.IsValidHero( targetHero )
			and J.CanCastOnNonMagicImmune( targetHero )
			and not targetHero:IsDisarmed()
		then
			return BOT_ACTION_DESIRE_HIGH, bot:GetLocation()
		end		
	end
	

	if J.IsInTeamFight( bot, 1400 )
	then
		local nAoeLoc = J.GetAoeEnemyHeroLocation( bot, nCastRange, nRadius, 2 )
		if nAoeLoc ~= nil
		then
			return BOT_ACTION_DESIRE_HIGH, nAoeLoc
		end		
	end
	

	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
			and J.CanCastOnNonMagicImmune( botTarget )
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0

end


return X
-- dota2jmz@163.com QQ:2462331592..
