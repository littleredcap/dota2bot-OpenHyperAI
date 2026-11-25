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
						{1,2,3,3,3,6,3,1,1,1,2,6,2,2,6},--pos1
}

local nAbilityBuildList = J.Skill.GetRandomBuild( tAllAbilityBuildList )

local nTalentBuildList = J.Skill.GetTalentBuild( tTalentTreeList )

local sRoleItemsBuyList = {}

sRoleItemsBuyList['pos_1'] = {
    "item_tango",
    "item_double_branches",
    "item_quelling_blade",

    "item_wraith_band",
    "item_power_treads",
    "item_magic_wand",
    "item_mask_of_madness",
    "item_mjollnir",--
    "item_black_king_bar",--
    "item_skadi",--
    "item_aghanims_shard",
	"item_butterfly",--
    "item_moon_shard",
    "item_refresher",--
    "item_travel_boots",
    "item_travel_boots_2",--
    "item_ultimate_scepter_2",
}

sRoleItemsBuyList['pos_2'] = sRoleItemsBuyList['pos_1']

sRoleItemsBuyList['pos_3'] = sRoleItemsBuyList['pos_1']

sRoleItemsBuyList['pos_4'] = sRoleItemsBuyList['pos_1']

sRoleItemsBuyList['pos_5'] = sRoleItemsBuyList['pos_1']


X['sBuyList'] = sRoleItemsBuyList[sRole]


X['sSellList'] = {

	"item_black_king_bar",
	"item_quelling_blade",
}

if J.Role.IsPvNMode() or J.Role.IsAllShadow() then X['sBuyList'], X['sSellList'] = { 'PvN_antimage' }, {} end

nAbilityBuildList, nTalentBuildList, X['sBuyList'], X['sSellList'] = J.SetUserHeroInit( nAbilityBuildList, nTalentBuildList, X['sBuyList'], X['sSellList'] )

X['sSkillList'] = J.Skill.GetSkillList( sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList )

X['bDeafaultAbility'] = false
X['bDeafaultItem'] = false

function X.MinionThink(hMinionUnit)
	Minion.MinionThink(hMinionUnit)
end

local TimeWalk 			= bot:GetAbilityByName('faceless_void_time_walk')
local TimeDilation 		= bot:GetAbilityByName('faceless_void_time_dilation')
local Chronosphere 		= bot:GetAbilityByName('faceless_void_chronosphere')
local TimeWalkReverse 	= bot:GetAbilityByName('faceless_void_time_walk_reverse')

local TimeWalkDesire, TimeWalkLocation
local TimeDilationDesire
local ChronosphereDesire, ChronosphereLocation
local TimeWalkReverseDesire

local TimeWalkPrevLocation

local announceCount, lastAnnouncedTime = 0, GameTime()

local botTarget

function X.SkillsComplement()
    if J.CanNotUseAbility(bot) then return end
    if not Chronosphere or Chronosphere:IsHidden() then Chronosphere = bot:GetAbilityByName('faceless_void_time_zone') end

	botTarget = J.GetProperTarget(bot)

	TimeWalkReverseDesire = X.ConsiderTimeWalkReverse()
	if TimeWalkReverseDesire > 0
	then
		bot:Action_UseAbility(TimeWalkReverse)
		return
	end

	TimeWalkDesire, TimeWalkLocation = X.ConsiderTimeWalk()
    if TimeWalkDesire > 0
	and IsAllowedToCast(TimeWalk:GetManaCost())
	then
        J.SetQueuePtToINT(bot, false)

		bot:Action_UseAbilityOnLocation(TimeWalk, TimeWalkLocation)
		TimeWalkPrevLocation = TimeWalkLocation
		return
	end

	TimeDilationDesire = X.ConsiderTimeDilation()
	if TimeDilationDesire > 0
	and IsAllowedToCast(TimeDilation:GetManaCost())
	then
        J.SetQueuePtToINT(bot, false)

		bot:Action_UseAbility(TimeDilation)
		return
	end

	-- Chronosphere = bot:GetAbilityByName('faceless_void_chronosphere')
	if Chronosphere and not Chronosphere:IsNull() and not Chronosphere:IsHidden() then
		if bot.needRefreshAbilitiesFor737 then
			Chronosphere = bot:GetAbilityByName('faceless_void_chronosphere')
			sAbilityList = J.Skill.GetAbilityList( bot )
			X['sSkillList'] = J.Skill.GetSkillList( sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList )
			bot:ActionImmediate_Chat( "I now have my Chronosphere back. Thanks!", true )
			bot.needRefreshAbilitiesFor737 = false
		end

		ChronosphereDesire, ChronosphereLocation = X.ConsiderChronosphere()
		if ChronosphereDesire > 0
		then
			bot:Action_UseAbilityOnLocation(Chronosphere, ChronosphereLocation)
			return
		end
	else
		bot.needRefreshAbilitiesFor737 = true
		if announceCount <= 2 and GameTime() - lastAnnouncedTime > 15 + bot:GetPlayerID() then
			lastAnnouncedTime = GameTime()
			announceCount = announceCount + 1
			bot:ActionImmediate_Chat( "Due to Valve bug in 7.37. I lost Chronosphere. Please enable Fretbots mode in this script to fix this problem. Check Workshop page if you need help.", true )
		end
	end
end

function X.CanUseRefresherShard()
	local nCastRange = 1000
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = '刷新技能'
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	if #nInRangeEnmyList > 0
		and ( J.IsGoingOnSomeone( bot ) or J.IsInTeamFight( bot ) )
		and J.CanUseRefresherShard( bot )
		and not bot:HasModifier("modifier_faceless_void_chronosphere_speed")
	then
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return false
end

function X.ConsiderTimeWalk()
	if not TimeWalk:IsFullyCastable()
	or bot:HasModifier("modifier_faceless_void_chronosphere_speed")
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = TimeWalk:GetSpecialValueInt('range')
	local nCastPoint = TimeWalk:GetCastPoint()
	local nSpeed = TimeWalk:GetSpecialValueInt('speed')
	local nDamageWindow = TimeWalk:GetSpecialValueInt('backtrack_duration')
	local nEnemyHeroes = J.GetNearbyHeroes(bot,1600, true, BOT_MODE_NONE)

	if J.IsStuck(bot)
	then
		return BOT_ACTION_DESIRE_HIGH, J.Site.GetXUnitsTowardsLocation(bot, J.GetEscapeLoc(), nCastRange)
	end

	if J.IsStunProjectileIncoming(bot, 600)
	or J.IsUnitTargetProjectileIncoming(bot, 400)
    then
        return BOT_ACTION_DESIRE_HIGH, J.Site.GetXUnitsTowardsLocation(bot, J.GetEscapeLoc(), nCastRange)
    end

	if not bot:HasModifier('modifier_sniper_assassinate')
	and not bot:IsMagicImmune()
	then
		if J.IsWillBeCastUnitTargetSpell(bot, 400)
		then
			return BOT_ACTION_DESIRE_HIGH, J.Site.GetXUnitsTowardsLocation(bot, J.GetEscapeLoc(), nCastRange)
		end
	end

	if J.IsGoingOnSomeone(bot)
	then
		if J.IsValidTarget(botTarget)
		and J.CanCastOnNonMagicImmune(botTarget)
		and not J.IsSuspiciousIllusion(botTarget)
		and not J.IsDisabled(botTarget)
		and not botTarget:IsAttackImmune()
		and not botTarget:HasModifier('modifier_necrolyte_reapers_scythe')
		then
			local nInRangeAlly = J.GetNearbyHeroes(botTarget, 1200, true, BOT_MODE_NONE)
			local nInRangeEnemy = J.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)
			local eta = (GetUnitToUnitDistance(bot, botTarget) / nSpeed) + nCastPoint
			local loc = J.Site.GetXUnitsTowardsLocation(bot, botTarget:GetExtrapolatedLocation(eta), nCastRange)

			if nInRangeAlly ~= nil and nInRangeEnemy ~= nil
			and #nInRangeAlly >= #nInRangeEnemy
			and IsLocationPassable(loc)
			and not J.IsLocationInArena(loc, 600)
			then
				if GetUnitToLocationDistance(bot, loc) > bot:GetAttackRange() * 2
				then
					if J.IsInLaningPhase()
					then
						local nEnemyTowers = botTarget:GetNearbyTowers(700, false)
						if nEnemyTowers ~= nil and #nEnemyTowers == 0
						then
							return BOT_ACTION_DESIRE_HIGH, loc
						end
					else
						return BOT_ACTION_DESIRE_HIGH, loc
					end
				end
			end
		end
	end

	if J.IsRetreating(bot)
	then
        local nInRangeEnemy = J.GetNearbyHeroes(bot,1200, true, BOT_MODE_NONE)
		for _, enemyHero in pairs(nInRangeEnemy)
        do
			if J.IsValidHero(enemyHero)
			and J.IsInRange(bot, enemyHero, nCastRange)
			and not J.IsSuspiciousIllusion(enemyHero)
			and not J.IsDisabled(enemyHero)
			and not J.IsRealInvisible(bot)
			then
				local nInRangeAlly = J.GetNearbyHeroes(enemyHero, 1200, true, BOT_MODE_NONE)
				local nTargetInRangeAlly = J.GetNearbyHeroes(enemyHero, 1200, false, BOT_MODE_NONE)

				if nInRangeAlly ~= nil and nTargetInRangeAlly ~= nil
				and ((#nTargetInRangeAlly > #nInRangeAlly)
					or bot:WasRecentlyDamagedByHero(enemyHero, nDamageWindow))
				then
					return BOT_ACTION_DESIRE_HIGH, J.Site.GetXUnitsTowardsLocation(bot, J.GetEscapeLoc(), nCastRange)
				end
			end
        end
	end

	if J.IsPushing(bot)
	then
		local nEnemyLaneCreeps = bot:GetNearbyLaneCreeps(nCastRange, true)

		if nEnemyLaneCreeps ~= nil and #nEnemyLaneCreeps >= 3
		and GetUnitToLocationDistance(bot, J.GetCenterOfUnits(nEnemyLaneCreeps)) > 500
		then
			return BOT_ACTION_DESIRE_HIGH, J.GetCenterOfUnits(nEnemyLaneCreeps)
		end
	end

	if J.IsFarming(bot)
	then
		if J.IsValid(botTarget)
		and GetUnitToUnitDistance(bot, botTarget) > 500
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end

	if J.IsLaning(bot)
	then
		local nEnemyLaneCreeps = bot:GetNearbyLaneCreeps(nCastRange, true)

		-- for _, creep in pairs(nEnemyLaneCreeps)
		-- do
		-- 	if J.IsValid(creep)
		-- 	and J.CanBeAttacked(creep)
		-- 	and (J.IsKeyWordUnit('ranged', creep) or J.IsKeyWordUnit('siege', creep) or J.IsKeyWordUnit('flagbearer', creep))
		-- 	and GetUnitToUnitDistance(creep, bot) > 500
		-- 	then
		-- 		local nCreepInRangeHero = creep:GetNearbyHeroes(creep:GetCurrentVisionRange(), false, BOT_MODE_NONE)
		-- 		local nCreepInRangeTower = creep:GetNearbyTowers(700, false)
		-- 		local nTime = (GetUnitToUnitDistance(bot, creep) / nSpeed) + nCastPoint
		-- 		local nDamage = bot:GetAttackDamage()

		-- 		if J.WillKillTarget(creep, nDamage, DAMAGE_TYPE_PHYSICAL, nTime)
		-- 		and nCreepInRangeHero ~= nil and #nCreepInRangeHero == 0
		-- 		and nCreepInRangeTower ~= nil and #nCreepInRangeTower == 0
		-- 		then
		-- 			bot:SetTarget(creep)
		-- 			return BOT_ACTION_DESIRE_HIGH, creep:GetLocation()
		-- 		end
		-- 	end
		-- end

		if ((bot:GetMana() - TimeWalk:GetManaCost()) / bot:GetMaxMana()) > 0.85
		and bot:DistanceFromFountain() > 100
		and bot:DistanceFromFountain() < 6000
		and J.IsInLaningPhase()
		and #nEnemyHeroes == 0
		then
			local nLane = bot:GetAssignedLane()
			local nLaneFrontLocation = GetLaneFrontLocation(GetTeam(), nLane, 0)
			local nDistFromLane = GetUnitToLocationDistance(bot, nLaneFrontLocation)

			if nDistFromLane > nCastRange
			then
				local nLocation = J.Site.GetXUnitsTowardsLocation(bot, nLaneFrontLocation, nCastRange)
				if IsLocationPassable(nLocation)
				then
					return BOT_ACTION_DESIRE_HIGH, nLocation
				end
			end
		end
	end

	if J.IsDoingRoshan(bot)
    then
		local roshLoc = J.GetCurrentRoshanLocation()
        if GetUnitToLocationDistance(bot, roshLoc) > nCastRange
        then
			local targetLoc = J.Site.GetXUnitsTowardsLocation(bot, roshLoc, nCastRange)
			local nInRangeEnemy = J.GetEnemiesNearLoc(roshLoc, 1600)

			if nInRangeEnemy ~= nil and #nInRangeEnemy == 0
			and IsLocationPassable(targetLoc)
			then
				return BOT_ACTION_DESIRE_HIGH, targetLoc
			end
        end
    end

    if J.IsDoingTormentor(bot)
    then
		local tormentorLoc = J.GetTormentorLocation(GetTeam())
        if GetUnitToLocationDistance(bot, tormentorLoc) > nCastRange
        then
			local targetLoc = J.Site.GetXUnitsTowardsLocation(bot, tormentorLoc, nCastRange)
			local nInRangeEnemy = J.GetEnemiesNearLoc(targetLoc, 1600)

			if nInRangeEnemy ~= nil and #nInRangeEnemy == 0
			and IsLocationPassable(targetLoc)
			then
				return BOT_ACTION_DESIRE_HIGH, targetLoc
			end

        end
    end

	return BOT_ACTION_DESIRE_NONE, 0
end

function X.ConsiderTimeDilation()
	if not TimeDilation:IsFullyCastable()
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local nRadius = TimeDilation:GetSpecialValueInt('radius')

	if J.IsInTeamFight(bot, 1200)
	then
		local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), nRadius)
		if nInRangeEnemy ~= nil and #nInRangeEnemy >= 2
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end

	if J.IsGoingOnSomeone(bot)
	then
		if J.IsValidTarget(botTarget)
		and J.CanCastOnNonMagicImmune(botTarget)
		and J.IsInRange(bot, botTarget, nRadius)
		and not J.IsSuspiciousIllusion(botTarget)
		and not J.IsDisabled(botTarget)
		and not botTarget:HasModifier('modifier_necrolyte_reapers_scythe')
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end

	if J.IsRetreating(bot)
	then
		local nInRangeEnemy = J.GetNearbyHeroes(bot,nRadius, true, BOT_MODE_NONE)
		for _, enemyHero in pairs(nInRangeEnemy)
		do
			if J.IsValidHero(enemyHero)
			and J.CanCastOnNonMagicImmune(enemyHero)
			and not J.IsSuspiciousIllusion(enemyHero)
			and not J.IsDisabled(enemyHero)
			then
				local nInRangeAlly = J.GetNearbyHeroes(enemyHero, 1200, true, BOT_MODE_NONE)
				local nTargetInRangeAlly = J.GetNearbyHeroes(enemyHero, 1200, false, BOT_MODE_NONE)

				if nInRangeAlly ~= nil and nTargetInRangeAlly ~= nil
				and (#nInRangeAlly >= #nTargetInRangeAlly
					or bot:WasRecentlyDamagedByHero(enemyHero, 2.5))
				then
					return BOT_ACTION_DESIRE_HIGH
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

local function IsChronosphereTarget(enemy)
	return J.IsValidHero(enemy)
		and not J.IsSuspiciousIllusion(enemy)
		and not enemy:IsAttackImmune()
		and not enemy:HasModifier('modifier_abaddon_borrowed_time')
		and not enemy:HasModifier('modifier_dazzle_shallow_grave')
		and not enemy:HasModifier('modifier_necrolyte_reapers_scythe')
		and not enemy:HasModifier('modifier_oracle_false_promise_timer')
		and not enemy:HasModifier('modifier_templar_assassin_refraction_absorb')
end

local function GetChronosphereAllyCost(location, radius, allies)
	local cost = 0
	for _, ally in ipairs(allies) do
		if J.Site.GetDistance(location, ally.current) <= radius
			or J.Site.GetDistance(location, ally.predicted) <= radius
		then
			cost = cost + ally.cost
		end
	end
	return cost
end

local function FindTeamfightChronosphere(castRange, radius, castPoint, allies, suggestedLocation)
	local origin = bot:GetLocation()
	local hitRadius = radius / 1.2
	local enemies = {}
	for _, enemy in ipairs(J.GetEnemiesNearLoc(origin, castRange + radius + 200)) do
		if IsChronosphereTarget(enemy) then
			table.insert(enemies, {hero = enemy, location = J.GetCorrectLoc(enemy, castPoint)})
		end
	end
	if #enemies < 2 then return nil, nil end

	local bestLocation, bestTarget
	local bestAllyCost, bestEnemyCount = math.huge, 0
	local function ConsiderLocation(location)
		if location == nil then return end
		if J.Site.GetDistance(origin, location) > castRange then
			location = J.Site.GetXUnitsTowardsLocation(bot, location, castRange)
		end

		local enemyCount = 0
		local target, targetHealth = nil, math.huge
		for _, enemy in ipairs(enemies) do
			if J.Site.GetDistance(location, enemy.location) <= hitRadius then
				enemyCount = enemyCount + 1
				local health = enemy.hero:GetHealth()
				if health < targetHealth then
					target, targetHealth = enemy.hero, health
				end
			end
		end
		if enemyCount < 2 then return end

		local allyCost = GetChronosphereAllyCost(location, radius, allies)
		if enemyCount - allyCost >= 2
			and (allyCost < bestAllyCost or (allyCost == bestAllyCost and enemyCount > bestEnemyCount))
		then
			bestLocation, bestTarget = location, target
			bestAllyCost, bestEnemyCount = allyCost, enemyCount
		end
	end

	ConsiderLocation(suggestedLocation)
	for i, enemy in ipairs(enemies) do
		ConsiderLocation(enemy.location)
		for j = i + 1, #enemies do
			local other = enemies[j].location
			local delta = other - enemy.location
			local distance = J.Site.GetDistance(enemy.location, other)
			if distance > 0 and distance < hitRadius * 2 then
				local center = (enemy.location + other) * 0.5
				-- Check both sides of the pair for a cast that catches both enemies while avoiding allies.
				local offset = math.sqrt(hitRadius * hitRadius - distance * distance * 0.25) * 0.95
				local side = Vector(-delta.y, delta.x, 0) * (offset / distance)
				ConsiderLocation(center)
				ConsiderLocation(center + side)
				ConsiderLocation(center - side)
			end
		end
	end
	return bestLocation, bestTarget
end

function X.ConsiderChronosphere()
	if not Chronosphere:IsFullyCastable()
	then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = Chronosphere:GetCastRange()
	local nCastPoint = Chronosphere:GetCastPoint()
	local nRadius = Chronosphere:GetSpecialValueInt('radius')
	local nDuration = Chronosphere:GetSpecialValueInt('duration')
	local nAttackDamage = bot:GetAttackDamage()
	local nAttackSpeed = bot:GetAttackSpeed()
	local bFreezesAllies = Chronosphere:GetName() == 'faceless_void_chronosphere'
	local allies = {}
	if bFreezesAllies then
		for _, ally in ipairs(J.GetAlliesNearLoc(bot:GetLocation(), nCastRange + nRadius + 200)) do
			if ally ~= bot then
				table.insert(allies, {
					current = ally:GetLocation(),
					predicted = J.GetCorrectLoc(ally, nCastPoint),
					cost = J.IsCore(ally) and 2 or 1,
				})
			end
		end
	end

	if J.IsInTeamFight(bot, 1200)
	then
		local nLocationAoE = bot:FindAoELocation(true, true, bot:GetLocation(), nCastRange, nRadius / 1.2, nCastPoint, 0)
		local location = nLocationAoE.targetloc
		local targetHero
		if bFreezesAllies then
			location, targetHero = FindTeamfightChronosphere(nCastRange, nRadius, nCastPoint, allies, location)
		elseif location ~= nil then
			local enemies = J.GetEnemiesNearLoc(location, nRadius / 1.2)
			local targetHealth = math.huge
			if #enemies >= 2 then
				for _, enemy in ipairs(enemies) do
					if IsChronosphereTarget(enemy) and enemy:GetHealth() < targetHealth then
						targetHero, targetHealth = enemy, enemy:GetHealth()
					end
				end
			end
		end
		if targetHero ~= nil then
			bot:SetTarget(targetHero)
			return BOT_ACTION_DESIRE_HIGH, location
		end
	end

	if J.IsGoingOnSomeone(bot)
	then
		if J.IsValidTarget(botTarget)
		and J.CanCastOnMagicImmune(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange + nRadius)
		and not J.IsSuspiciousIllusion(botTarget)
		and not botTarget:IsAttackImmune()
		and not botTarget:HasModifier('modifier_abaddon_borrowed_time')
		and not botTarget:HasModifier('modifier_dazzle_shallow_grave')
		and not botTarget:HasModifier('modifier_necrolyte_reapers_scythe')
		and not botTarget:HasModifier('modifier_oracle_false_promise_timer')
		and not botTarget:HasModifier('modifier_templar_assassin_refraction_absorb')
		then
			local nInRangeAlly = J.GetNearbyHeroes(bot,1200, false, BOT_MODE_NONE)
			local nInRangeEnemy = J.GetNearbyHeroes(bot,1200, true, BOT_MODE_NONE)

			if nInRangeAlly ~= nil and nInRangeEnemy ~= nil
			and #nInRangeAlly >= #nInRangeEnemy
			and #nInRangeAlly <= 1 and #nInRangeEnemy <= 1
			then
				local loc = J.Site.GetXUnitsTowardsLocation(bot, botTarget:GetLocation(), nCastRange)

				if J.CanKillTarget(botTarget, nAttackDamage * nAttackSpeed * nDuration, DAMAGE_TYPE_PHYSICAL)
				and not J.IsLocationInChrono(loc)
				and not J.IsLocationInBlackHole(loc)
				and not J.IsLocationInArena(loc, nRadius)
				and GetChronosphereAllyCost(loc, nRadius, allies) == 0
				then
					bot:SetTarget(botTarget)
					return BOT_ACTION_DESIRE_HIGH, loc
					-- if J.IsCore(botTarget)
					-- then
					-- 	bot:SetTarget(botTarget)
					-- 	return BOT_ACTION_DESIRE_HIGH, loc
					-- end

					-- if not J.IsCore(botTarget)
					-- and nBotDeaths > nBotKills + 4
					-- then
					-- 	bot:SetTarget(botTarget)
					-- 	return BOT_ACTION_DESIRE_HIGH, loc
					-- end
				end
			end
		end
	end

	if J.IsRetreating(bot)
	then
        local nInRangeAlly = J.GetNearbyHeroes(bot,1200, false, BOT_MODE_NONE)
        local nInRangeEnemy = J.GetNearbyHeroes(bot,1200, true, BOT_MODE_NONE)

        for _, enemyHero in pairs(nInRangeEnemy)
        do
			if nInRangeAlly ~= nil and nInRangeEnemy ~= nil
			and J.IsValidHero(enemyHero)
			and J.IsChasingTarget(enemyHero, bot)
			and not J.IsSuspiciousIllusion(enemyHero)
			and not J.IsDisabled(enemyHero)
			and not nInRangeEnemy[1]:HasModifier('modifier_legion_commander_duel')
			and not nInRangeEnemy[1]:HasModifier('modifier_necrolyte_reapers_scythe')
			then
				local nTargetInRangeAlly = J.GetNearbyHeroes(nInRangeEnemy[1], 1200, false, BOT_MODE_NONE)

				if nTargetInRangeAlly ~= nil
				and #nTargetInRangeAlly > #nInRangeAlly + 2
				and #nInRangeAlly <= 1
				then
					local nLocationAoE = bot:FindAoELocation(true, true, bot:GetLocation(), nCastRange, nRadius, nCastPoint, 0)
					local nTargetLocInRangeEnemy = J.GetEnemiesNearLoc(nLocationAoE.targetloc, nRadius)

					if nTargetLocInRangeEnemy ~= nil and #nTargetLocInRangeEnemy >= 1
					and not J.IsLocationInChrono(nLocationAoE.targetloc)
					and not J.IsLocationInBlackHole(nLocationAoE.targetloc)
					and not J.IsLocationInArena(nLocationAoE.targetloc, nRadius)
					and GetChronosphereAllyCost(nLocationAoE.targetloc, nRadius, allies) == 0
					then
						return BOT_ACTION_DESIRE_HIGH, nLocationAoE.targetloc
					end
				end
			end
        end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end

function X.ConsiderTimeWalkReverse()
	if not TimeWalkReverse:IsTrained()
	or not TimeWalkReverse:IsFullyCastable()
	or not TimeWalkReverse:IsActivated()
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if J.IsStunProjectileIncoming(bot, 600)
	or J.IsUnitTargetProjectileIncoming(bot, 400)
    then
        return BOT_ACTION_DESIRE_HIGH
    end

	if not bot:HasModifier('modifier_sniper_assassinate')
	and not bot:IsMagicImmune()
	then
		if J.IsWillBeCastUnitTargetSpell(bot, 400)
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end

	if not bot:HasModifier('modifier_faceless_void_chronosphere_speed')
	and J.IsValidTarget(botTarget)
	and J.IsInRange(bot, botTarget, bot:GetCurrentVisionRange())
	and not J.IsSuspiciousIllusion(botTarget)
	then
		local nInRangeAlly = J.GetNearbyHeroes(botTarget, 1200, true, BOT_MODE_NONE)
		local nInRangeEnemy = J.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)

		if nInRangeAlly ~= nil and nInRangeEnemy ~= nil
		then
			if #nInRangeEnemy > #nInRangeAlly
			and GetUnitToLocationDistance(bot, TimeWalkPrevLocation) > GetUnitToLocationDistance(botTarget, TimeWalkPrevLocation)
			and GetUnitToLocationDistance(bot, TimeWalkPrevLocation) > GetUnitToUnitDistance(bot, botTarget)
			then
				return BOT_ACTION_DESIRE_HIGH
			end
		end

		-- if TimeDilation:IsTrained() and TimeDilation:IsFullyCastable()
		-- and J.IsGoingOnSomeone(bot)
		-- then
		-- 	return BOT_ACTION_DESIRE_HIGH
		-- end
	end

	return BOT_ACTION_DESIRE_NONE
end

--Helper Funcs
function IsAllowedToCast(manaCost)
	if Chronosphere ~= nil
	and not Chronosphere:IsNull()
	and Chronosphere:IsTrained()
	and Chronosphere:IsFullyCastable()
	then
		local ultCost = Chronosphere:GetManaCost()
		if bot:GetMana() - manaCost * 2 > ultCost
		then
			return true
		else
			return false
		end
	end

	return true
end

return X
