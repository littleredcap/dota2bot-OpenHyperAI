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
						['t25'] = {10, 0},
						['t20'] = {0, 10},
						['t15'] = {10, 0},
						['t10'] = {10, 0},
}

local tAllAbilityBuildList = {
						{1,3,1,2,1,6,1,3,3,2,6,3,2,2,6},
}

local nAbilityBuildList = J.Skill.GetRandomBuild( tAllAbilityBuildList )

local nTalentBuildList = J.Skill.GetTalentBuild( tTalentTreeList )

local sRoleItemsBuyList = {}

sRoleItemsBuyList['pos_4'] = {
	"item_tango",
	"item_double_branches",
	"item_faerie_fire",
	"item_blood_grenade",

	"item_magic_wand",
	"item_arcane_boots",
	"item_glimmer_cape",--
	"item_force_staff",
	"item_blink",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_guardian_greaves",--
	"item_aether_lens",--
	"item_octarine_core",--
	"item_black_king_bar",--
	"item_refresher",--
	"item_ultimate_scepter_2",
	"item_moon_shard",
}

sRoleItemsBuyList['pos_5'] = {
	"item_tango",
	"item_double_branches",
	"item_faerie_fire",
	"item_blood_grenade",

	"item_magic_wand",
	"item_tranquil_boots",
	"item_glimmer_cape",--
	"item_force_staff",
	"item_blink",
	"item_aghanims_shard",
	"item_pipe",--
	"item_ultimate_scepter",
	"item_boots_of_bearing",--
	"item_aether_lens",--
	"item_octarine_core",--
	-- "item_black_king_bar",--
	"item_refresher",--
	"item_ultimate_scepter_2",
	"item_moon_shard",
}

sRoleItemsBuyList['pos_1'] = {
	
	"item_crystal_maiden_outfit",
	"item_aghanims_shard",
	"item_ultimate_scepter",
	"item_glimmer_cape",
	"item_force_staff",
	"item_cyclone",
	"item_sheepstick",
	"item_wind_waker",
	"item_moon_shard",
	"item_ultimate_scepter_2",
	"item_refresher",
}

sRoleItemsBuyList['pos_2'] = sRoleItemsBuyList['pos_1']

sRoleItemsBuyList['pos_3'] = sRoleItemsBuyList['pos_1']

X['sBuyList'] = sRoleItemsBuyList[sRole]

X['sSellList'] = {
	"item_cyclone",
	"item_magic_wand",

	"item_ultimate_scepter",
	"item_magic_wand",
}


if J.Role.IsPvNMode() or J.Role.IsAllShadow() then X['sBuyList'], X['sSellList'] = { 'PvN_mage' }, {} end

nAbilityBuildList, nTalentBuildList, X['sBuyList'], X['sSellList'] = J.SetUserHeroInit( nAbilityBuildList, nTalentBuildList, X['sBuyList'], X['sSellList'] )

X['sSkillList'] = J.Skill.GetSkillList( sAbilityList, nAbilityBuildList, sTalentList, nTalentBuildList )

X['bDeafaultAbility'] = false
X['bDeafaultItem'] = true

function X.MinionThink(hMinionUnit)
    Minion.MinionThink(hMinionUnit)
end

--[[

npc_dota_hero_shadow_shaman

"Ability1"		"shadow_shaman_ether_shock"
"Ability2"		"shadow_shaman_voodoo"
"Ability3"		"shadow_shaman_shackles"
"Ability4"		"generic_hidden"
"Ability5"		"generic_hidden"
"Ability6"		"shadow_shaman_mass_serpent_ward"
"Ability10"		"special_bonus_hp_200"
"Ability11"		"special_bonus_exp_boost_20"
"Ability12"		"special_bonus_cast_range_125"
"Ability13"		"special_bonus_unique_shadow_shaman_5"
"Ability14"		"special_bonus_unique_shadow_shaman_2"
"Ability15"		"special_bonus_unique_shadow_shaman_1"
"Ability16"		"special_bonus_unique_shadow_shaman_3"
"Ability17"		"special_bonus_unique_shadow_shaman_4"

modifier_shadow_shaman_ethershock
modifier_shadow_shaman_voodoo
modifier_shadow_shaman_shackles
modifier_shadow_shaman_serpent_ward

--]]

local abilityQ = bot:GetAbilityByName( sAbilityList[1] )
local abilityW = bot:GetAbilityByName( sAbilityList[2] )
local abilityE = bot:GetAbilityByName( sAbilityList[3] )
local abilityR = bot:GetAbilityByName( sAbilityList[6] )
local talent3 = bot:GetAbilityByName( sTalentList[3] )
local talent7 = bot:GetAbilityByName( sTalentList[7] )

local castQDesire, castQTarget
local castWDesire, castWTarget
local castEDesire, castETarget
local castRDesire, castRLocation


local nKeepMana, nMP, nHP, nLV, hEnemyList, hAllyList, botTarget, sMotive
local aetherRange = 0
local talent7Damage = 0

local function HasAttackFollowUp(target)
	if not J.IsValidHero(target) then return false end
	if J.IsInLaningPhase(bot) then return J.HasLaneFightFollowUp(bot, target) end
	return not J.HasCommittedStunFollowUp or J.HasCommittedStunFollowUp(bot, target, 0)
end

local function CanLandDisable(target, castPoint)
	return not J.GetFightDisableDelay or J.GetFightDisableDelay(bot, target) <= castPoint + 0.12
end



function X.SkillsComplement()

	if J.CanNotUseAbility( bot ) or bot:IsInvisible() then return end

	nKeepMana = 400
	aetherRange = 0
	talent7Damage = 0
	nLV = bot:GetLevel()
	nMP = bot:GetMana()/bot:GetMaxMana()
	nHP = bot:GetHealth()/bot:GetMaxHealth()
	local gank = bot.ohaLaneGank
	botTarget = gank and gank.ready and gank.target or J.GetProperTarget(bot)
	hEnemyList = J.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )
	hAllyList = J.GetAlliesNearLoc( bot:GetLocation(), 1600 )


	local aether = J.IsItemAvailable( "item_aether_lens" )
	if aether then aetherRange = aether:GetSpecialValueInt('cast_range_bonus') end
--	if talent3:IsTrained() then aetherRange = aetherRange + talent3:GetSpecialValueInt( "value" ) end
	if talent7 ~= nil and talent7:IsTrained() then talent7Damage = talent7:GetSpecialValueInt( "value" ) end


	local counterfight = J.GetSupportCounterfightPoint and abilityR:IsFullyCastable()
		and J.GetSupportCounterfightPoint(bot, hEnemyList or {}, abilityR:GetCastRange() + aetherRange, 150, 0.40)
	if counterfight then
		bot.ohaSerpentWardSiegeTarget = nil
		bot:Action_UseAbilityOnLocation(abilityR, counterfight)
		return
	end

	castWDesire, castWTarget, sMotive = X.ConsiderW()
	if ( castWDesire > 0 )
	then
		J.SetReportMotive( bDebugMode, sMotive )

		J.SetQueuePtToINT( bot, true )

		if J.NoteFightDisable then J.NoteFightDisable(bot, castWTarget, abilityW:GetCastPoint(), abilityW) end
		bot:ActionQueue_UseAbilityOnEntity( abilityW, castWTarget )
		return
	end


	local siegeTarget
	castRDesire, castRLocation, sMotive, siegeTarget = X.ConsiderR()
	if ( castRDesire > 0 )
	then
		J.SetReportMotive( bDebugMode, sMotive )

		J.SetQueuePtToINT( bot, true )

		bot.ohaSerpentWardSiegeTarget = siegeTarget
		bot:ActionQueue_UseAbilityOnLocation( abilityR, castRLocation )
		return

	end


	castETarget = X.GetLaneShacklesTarget()
	if castETarget ~= nil then
		castEDesire, sMotive = BOT_ACTION_DESIRE_HIGH, 'E-LaneCover'
	else
		local laneStep
		castQDesire, castQTarget, sMotive, laneStep = X.ConsiderQ()
		if castQDesire > 0 then
			J.SetReportMotive(bDebugMode, sMotive)
			if laneStep then bot:Action_MoveToLocation(laneStep); return end
			J.SetQueuePtToINT(bot, true)
			bot:ActionQueue_UseAbilityOnEntity(abilityQ, castQTarget)
			return
		end
		castEDesire, castETarget, sMotive = X.ConsiderE()
	end
	if ( castEDesire > 0 )
	then
		J.SetReportMotive( bDebugMode, sMotive )

		J.SetQueuePtToINT( bot, true )

		bot.ohaFightControlTarget = castETarget
		if J.NoteFightDisable then J.NoteFightDisable(bot, castETarget, abilityE:GetCastPoint(), abilityE) end
		bot:ActionQueue_UseAbilityOnEntity( abilityE, castETarget )
		return
	end


end

local function HasSafeShacklesPosition(enemy)
	for _, other in ipairs(hEnemyList) do
		if other ~= enemy and J.IsValidHero(other) and not J.IsSuspiciousIllusion(other) and not J.IsDisabled(other)
			and J.IsInRange(bot, other, math.max(550, other:GetAttackRange() + 200)) then return false end
	end
	return true
end

function X.GetLaneShacklesTarget()
	if not J.IsInLaningPhase(bot) or not abilityE or not J.CanCastAbility(abilityE) or nHP < 0.55
		or bot:WasRecentlyDamagedByAnyHero(1.5) then return nil end
	local partner = J.GetLanePartner(bot)
	local enemy = J.GetLaningPeelTarget(bot, partner, hEnemyList, abilityE:GetCastRange() + aetherRange, true)
	if enemy and HasSafeShacklesPosition(enemy) then return enemy end
end

function X.ConsiderQ()


	if not abilityQ:IsFullyCastable() then return 0 end

	local nSkillLV = abilityQ:GetLevel()
	local nCastRange = abilityQ:GetCastRange()
	local nCastPoint = abilityQ:GetCastPoint()
	local nManaCost = abilityQ:GetManaCost()
	local nDamage = abilityQ:GetSpecialValueInt( "damage" ) + talent7Damage
	local nDamageType = DAMAGE_TYPE_MAGICAL
	local nInRangeEnemyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )
	local nInBonusEnemyList = J.GetNearbyHeroes(bot, nCastRange + 220, true, BOT_MODE_NONE )


	for _, npcEnemy in pairs( nInBonusEnemyList )
	do
		if J.IsValid( npcEnemy )
			and J.CanCastOnNonMagicImmune( npcEnemy )
			and J.CanCastOnTargetAdvanced( npcEnemy )
			and J.WillMagicKillTarget( bot, npcEnemy, nDamage, nCastPoint )
		then
			return BOT_ACTION_DESIRE_HIGH, npcEnemy, 'Q-kill'..J.Chat.GetNormName( npcEnemy )
		end
	end


	local holdTower = J.IsDefending(bot) and J.GetAssignedOuterTower(bot) or nil
	if holdTower ~= nil then
		local radius = abilityQ:GetSpecialValueInt('start_radius')
		for _, creep in ipairs(bot:GetNearbyLaneCreeps(math.min(1600, nCastRange + aetherRange), true)) do
			if J.IsValid(creep) and not creep:HasModifier('modifier_fountain_glyph')
				and GetUnitToUnitDistance(holdTower, creep) <= 1050
				and (J.GetInLocLaneCreepCount(bot, 1600, radius, creep:GetLocation()) >= 2
					or J.IsKeyWordUnit('_siege', creep) and creep:GetAttackTarget() == holdTower
						and bot:GetMana() >= 2 * nManaCost) then
				return BOT_ACTION_DESIRE_HIGH, creep, 'Q-DefendWave'
			end
		end
		local poke = J.GetMidDefensePokeTarget and J.GetMidDefensePokeTarget(bot, nCastRange + aetherRange - 25)
		if poke and J.CanCastOnNonMagicImmune(poke) and J.CanCastOnTargetAdvanced(poke)
			and bot:GetMana() >= abilityQ:GetManaCost() * 2 then
			return BOT_ACTION_DESIRE_HIGH, poke, 'Q-DefendPoke'
		end
	end

	if J.IsInTeamFight( bot, 1200 ) and nLV >= 5
	then
		local nWeakestEnemy = nil
		local nWeakestEnemyHealth = 9999

		for _, npcEnemy in pairs( nInRangeEnemyList )
		do
			if J.IsValid( npcEnemy )
				and J.CanCastOnNonMagicImmune( npcEnemy )
				and J.CanCastOnTargetAdvanced( npcEnemy )
			then
				local npcEnemyHealth = npcEnemy:GetHealth()
				if ( npcEnemyHealth < nWeakestEnemyHealth )
				then
					nWeakestEnemyHealth = npcEnemyHealth
					nWeakestEnemy = npcEnemy
				end
			end
		end

		if ( nWeakestEnemy ~= nil )
		then
			return BOT_ACTION_DESIRE_HIGH, nWeakestEnemy, "Q-Battle-Weakest:"..J.Chat.GetNormName( nWeakestEnemy )
		end
	end


	if J.IsGoingOnSomeone(bot) and HasAttackFollowUp(botTarget)
	then
		if J.IsValidHero( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
			and J.CanCastOnNonMagicImmune( botTarget )
			and J.CanCastOnTargetAdvanced( botTarget )
		then
			if nSkillLV >= 2 or nMP > 0.7 or J.GetHP( botTarget ) < 0.5 or nHP < 0.4
			then
				return BOT_ACTION_DESIRE_HIGH, botTarget, 'Q-attack:'..J.Chat.GetNormName( botTarget )
			end
		end
	end


	if J.IsRetreating( bot )
	then
		for _, npcEnemy in pairs( nInRangeEnemyList )
		do
			if J.IsValidHero( npcEnemy )
				and ( bot:WasRecentlyDamagedByHero( npcEnemy, 4.0 )
						or nMP > 0.68
						or GetUnitToUnitDistance( bot, npcEnemy ) <= 400 )
				and J.CanCastOnNonMagicImmune( npcEnemy )
				and J.CanCastOnTargetAdvanced( npcEnemy )
				and bot:IsFacingLocation( npcEnemy:GetLocation(), 30 )
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy, "Q-Retreat:"..J.Chat.GetNormName( npcEnemy )
			end
		end
	end


	if J.IsLaning( bot )
	then
		local tower = bot:GetNearbyTowers(1500, true)[1]
		local reserve = abilityE and abilityE:IsTrained() and abilityE:GetManaCost() or nManaCost
		if nMP > 0.5
		then
			local peel = J.GetLaningPeelTarget(bot, J.GetLanePartner(bot), nInRangeEnemyList, nCastRange + aetherRange, true)
			if peel ~= nil then return BOT_ACTION_DESIRE_HIGH, peel, 'Q-LaneCover' end
		end

		-- Collect a valuable creep that no core can finish. Do not walk up to cast.
		local spellReach = math.min(1600, nCastRange + aetherRange)
		local canSecure = not J.HasPendingLaningLastHit(bot) and not J.IsLaningUnderPressure(bot, nInBonusEnemyList, tower)
			and bot:GetMana() - nManaCost >= reserve
		if canSecure then
			for _, creep in ipairs(bot:GetNearbyLaneCreeps(spellReach, true)) do
				if J.IsValid(creep) and J.CanBeAttacked(creep) and not creep:HasModifier('modifier_fountain_glyph')
					and (J.IsKeyWordUnit('_ranged', creep) or J.IsKeyWordUnit('_siege', creep))
					and J.IsInRange(bot, creep, spellReach)
					and J.GetAttackProDelayTime(bot, creep) > nCastPoint + 0.12
					and J.CanSecureLaneCreepWithSpell(bot, creep, nDamage, nDamageType, nCastPoint, nInBonusEnemyList) then
					return BOT_ACTION_DESIRE_HIGH, creep, 'Q-LaneSecure'
				end
			end
		end

		if nMP > 0.5 and bot:GetMana() - nManaCost >= reserve then
			local visibleEnemies = hEnemyList or nInBonusEnemyList
			local pressure, step = J.GetSideLaneDuoTrade(bot, visibleEnemies, tower, spellReach, nCastPoint, 145)
			if pressure and J.CanCastOnNonMagicImmune(pressure) and J.CanCastOnTargetAdvanced(pressure) then
				return BOT_ACTION_DESIRE_HIGH, pressure, 'Q-LaneDuoTrade', step
			end
			pressure = J.GetSideLaneSpellTradeTarget(bot, visibleEnemies, tower, spellReach, nil, nil, nCastPoint)
			if pressure and J.CanCastOnNonMagicImmune(pressure) and J.CanCastOnTargetAdvanced(pressure)
				and J.CanSpendLaneTradeTime(bot, tower, visibleEnemies, nCastPoint) then
				return BOT_ACTION_DESIRE_HIGH, pressure, 'Q-LanePressure'
			end
		end

		if canSecure and #nInRangeEnemyList == 0 then
			for _, creep in ipairs(bot:GetNearbyLaneCreeps(spellReach, true)) do
				if J.IsValid(creep) and J.CanBeAttacked(creep) and not creep:HasModifier('modifier_fountain_glyph')
					and (J.IsKeyWordUnit('_melee', creep) or J.IsKeyWordUnit('_flagbearer', creep))
					and J.IsInRange(bot, creep, spellReach) and J.GetAttackProDelayTime(bot, creep) > nCastPoint + 0.12
					and J.GetAroundTargetEnemyUnitCount(creep, 280) >= 2
					and J.CanSecureLaneCreepWithSpell(bot, creep, nDamage, nDamageType, nCastPoint, nInBonusEnemyList) then
					return BOT_ACTION_DESIRE_HIGH, creep, 'Q-LaneMelee'
				end
			end
		end
	end


	if ( J.IsPushing( bot ) or J.IsDefending( bot ) or J.IsFarming( bot ) )
		and J.IsAllowedToSpam( bot, 30 )
		and nSkillLV >= 3
		and #hEnemyList == 0
		and #hAllyList <= 3
	then
		local nEnemyCreeps = bot:GetNearbyLaneCreeps( 999, true )
		local nAllyCreeps = bot:GetNearbyLaneCreeps( 888, false )

		for _, creep in pairs( nEnemyCreeps )
		do
			if J.IsValid( creep )
				and not creep:HasModifier( "modifier_fountain_glyph" )
				and J.IsInRange( creep, bot, nCastRange + 300 )
			then

				if #nAllyCreeps == 0
					and J.GetAroundTargetEnemyUnitCount( creep, 380 ) >= 2
					and #nEnemyCreeps >= 4
				then
					return BOT_ACTION_DESIRE_HIGH, creep, "Q-PushAoe"
				end

				if J.IsKeyWordUnit( 'ranged', creep )
					and J.WillKillTarget( creep, nDamage, nDamageType, nCastPoint )
				then
					return BOT_ACTION_DESIRE_HIGH, creep, "Q-PushRanged"
				end

				if J.IsKeyWordUnit( 'melee', creep )
					and J.WillKillTarget( creep, nDamage, nDamageType, nCastPoint )
					and ( J.GetAroundTargetEnemyUnitCount( creep, 380 ) >= 2 or nMP > 0.8 )
				then
					return BOT_ACTION_DESIRE_HIGH, creep, "Q-PushMelee"
				end

			end
		end

	end


	if J.IsFarming( bot ) and nSkillLV >= 3
		and J.IsAllowedToSpam( bot, nManaCost )
		and #hEnemyList == 0
		and #hAllyList <= 2
		and not ( J.IsPushing( bot ) or J.IsDefending( bot ) )
	then
		local nNeutralCreeps = bot:GetNearbyNeutralCreeps( nCastRange + 200 )
		if #nNeutralCreeps >= 2 or nMP >= 0.5
		then
			local targetCreep = nNeutralCreeps[1]
			if J.IsValid( targetCreep )
				and bot:IsFacingLocation( targetCreep:GetLocation(), 30 )
				and targetCreep:GetHealth() >= 500
				and targetCreep:GetMagicResist() < 0.3
				and J.GetAroundTargetEnemyUnitCount( targetCreep, 300 ) >= 2
			then
				return BOT_ACTION_DESIRE_HIGH, targetCreep, "Q-Farm:"..( #nNeutralCreeps )
			end
		end
	end

	if J.IsDoingRoshan(bot) then
		if J.IsRoshan( botTarget )
		and J.IsInRange(bot, botTarget, nCastRange)
		and J.CanBeAttacked(botTarget)
		and J.IsAttacking(bot)
		and not botTarget:HasModifier('modifier_roshan_spell_block')
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget, ''
		end
	end

    if J.IsDoingTormentor(bot) then
		if J.IsTormentor(botTarget)
        and J.IsInRange(bot, botTarget, nCastRange)
        and J.IsAttacking(bot)
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget, ''
		end
	end

	return BOT_ACTION_DESIRE_NONE


end

function X.ConsiderW()


	if not abilityW:IsFullyCastable() then return 0 end

	local nSkillLV = abilityW:GetLevel()
	local nCastRange = abilityW:GetCastRange() + aetherRange
	local nCastPoint = abilityW:GetCastPoint()
	local nManaCost = abilityW:GetManaCost()
	local nDamage = abilityW:GetAbilityDamage()
	local nDamageType = DAMAGE_TYPE_MAGICAL
	local nInRangeEnemyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )
	local nInBonusEnemyList = J.GetNearbyHeroes(bot, nCastRange + 240, true, BOT_MODE_NONE )



	for _, npcEnemy in pairs( nInBonusEnemyList )
	do
		if J.IsValidHero( npcEnemy )
			and J.CanCastOnTargetAdvanced( npcEnemy )
			and J.CanCastOnNonMagicImmune( npcEnemy )
		then
			if npcEnemy:IsChanneling()
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy, 'W-Check1:'..J.Chat.GetNormName( npcEnemy )
			end

			if npcEnemy:IsCastingAbility()
				and J.IsInRange( bot, npcEnemy, nCastRange + 50 )
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy, 'W-Check2:'..J.Chat.GetNormName( npcEnemy )
			end
		end
	end

	if J.IsInLaningPhase(bot) then
		local peel = J.GetLaningPeelTarget(bot, J.GetLanePartner(bot), nInRangeEnemyList, nCastRange, true)
		if peel ~= nil then return BOT_ACTION_DESIRE_HIGH, peel, 'W-LaneCover' end
	end
	local focusPeel = J.GetCoreFocusPeelTarget(bot, hAllyList, hEnemyList, nCastRange)
	if focusPeel ~= nil then return BOT_ACTION_DESIRE_HIGH, focusPeel, 'W-CoreFocusCover' end
	local towerPeel = bot._defend and J.GetTowerPeelTarget(bot, nInRangeEnemyList, nCastRange)
	if towerPeel then return BOT_ACTION_DESIRE_HIGH, towerPeel, 'W-TowerCover' end

	if J.IsInTeamFight( bot, 1200 )
		and ( #nInBonusEnemyList >= 2 or #hAllyList >= 3 )
	then
		local npcMostDangerousEnemy = nil
		local nMostDangerousDamage = 0

		for _, npcEnemy in pairs( nInBonusEnemyList )
		do
			if J.IsValid( npcEnemy )
				and J.CanCastOnNonMagicImmune( npcEnemy )
				and J.CanCastOnTargetAdvanced( npcEnemy )
				and not J.IsDisabled( npcEnemy )
				and not J.IsTaunted( npcEnemy )
				and not npcEnemy:IsDisarmed()
			then
				local npcEnemyDamage = npcEnemy:GetEstimatedDamageToTarget( false, bot, 3.0, DAMAGE_TYPE_PHYSICAL )
				if ( npcEnemyDamage > nMostDangerousDamage )
				then
					nMostDangerousDamage = npcEnemyDamage
					npcMostDangerousEnemy = npcEnemy
				end
			end
		end

		if npcMostDangerousEnemy ~= nil
			and J.IsInRange( bot, npcMostDangerousEnemy, nCastRange )
			and HasAttackFollowUp(npcMostDangerousEnemy)
			and CanLandDisable(npcMostDangerousEnemy, nCastPoint)
		then
			return BOT_ACTION_DESIRE_HIGH, npcMostDangerousEnemy, 'W-Battle:'..J.Chat.GetNormName( npcMostDangerousEnemy )
		end

	end



	if J.IsGoingOnSomeone(bot) and HasAttackFollowUp(botTarget)
	then
		if J.IsValidHero( botTarget )
			and J.CanCastOnNonMagicImmune( botTarget )
			and J.CanCastOnTargetAdvanced( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange + 32 )
			and not J.IsDisabled( botTarget )
			and not J.IsTaunted( botTarget )
			and not botTarget:IsDisarmed()
			and CanLandDisable(botTarget, nCastPoint)
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget, 'W-Attack:'..J.Chat.GetNormName( botTarget )
		end
	end



	if bot:WasRecentlyDamagedByAnyHero( 3.0 ) and nLV >= 10
		and bot:GetActiveMode() ~= BOT_MODE_RETREAT
		and #nInRangeEnemyList >= 1
	then
		for _, npcEnemy in pairs( nInRangeEnemyList )
		do
			if J.IsValid( npcEnemy )
				and J.CanCastOnNonMagicImmune( npcEnemy )
				and J.CanCastOnTargetAdvanced( npcEnemy )
				and not J.IsDisabled( npcEnemy )
				and not J.IsTaunted( npcEnemy )
				and not npcEnemy:IsDisarmed()
				and (bot:WasRecentlyDamagedByHero(npcEnemy, 3) or npcEnemy:GetAttackTarget() == bot)
				and CanLandDisable(npcEnemy, nCastPoint)
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy, 'W-protect'
			end
		end
	end



	if J.IsRetreating( bot )
	then
		for _, npcEnemy in pairs( nInRangeEnemyList )
		do
			if J.IsValidHero( npcEnemy )
				and ( bot:WasRecentlyDamagedByHero( npcEnemy, 4.0 )
						or GetUnitToUnitDistance( bot, npcEnemy ) <= 500 )
				and J.CanCastOnNonMagicImmune( npcEnemy )
				and J.CanCastOnTargetAdvanced( npcEnemy )
				and not J.IsDisabled( npcEnemy )
				and not J.IsTaunted( npcEnemy )
				and not npcEnemy:IsDisarmed()
				and CanLandDisable(npcEnemy, nCastPoint)
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy, "W-Retreat:"..J.Chat.GetNormName( npcEnemy )
			end
		end
	end


	if J.IsDoingRoshan( bot ) and nMP > 0.6
	then
		if J.IsRoshan( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
			and not J.IsDisabled( botTarget )
			and not botTarget:IsDisarmed()
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget, "W-Roshan"
		end
	end

	if J.IsDoingTormentor(bot) then
		if J.IsTormentor(botTarget)
        and J.IsInRange(bot, botTarget, nCastRange)
        and J.IsAttacking(bot)
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget, ''
		end
	end

	return BOT_ACTION_DESIRE_NONE


end

function X.ConsiderE()


	if not abilityE:IsFullyCastable() then return 0 end

	local nSkillLV = abilityE:GetLevel()
	local nCastRange = abilityE:GetCastRange() + aetherRange
	local nCastPoint = abilityE:GetCastPoint()
	local nManaCost = abilityE:GetManaCost()
	local nDamage = nSkillLV * 100 - 40 + bot:GetAttackDamage() * 2
	local nDamageType = DAMAGE_TYPE_MAGICAL
	local nInRangeEnemyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )
	local nInBonusEnemyList = J.GetNearbyHeroes(bot, nCastRange + 240, true, BOT_MODE_NONE )


	for _, npcEnemy in pairs( nInBonusEnemyList )
	do
		if J.IsValidHero( npcEnemy )
			and J.CanCastOnTargetAdvanced( npcEnemy )
			and J.CanCastOnNonMagicImmune( npcEnemy )
		then
			if npcEnemy:IsChanneling()
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy, 'E-Check1:'..J.Chat.GetNormName( npcEnemy )
			end

			if #hAllyList >= 2
				and npcEnemy:IsCastingAbility()
				and J.IsInRange( bot, npcEnemy, nCastRange + 30 )
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy, 'E-Check2:'..J.Chat.GetNormName( npcEnemy )
			end
		end
	end


	if J.IsInTeamFight( bot, 1200 ) and nLV >= 5
	then
		local npcMostDangerousEnemy = nil
		local nMostDangerousDamage = 0

		for _, npcEnemy in pairs( nInBonusEnemyList )
		do
			if J.IsValid( npcEnemy )
				and J.CanCastOnNonMagicImmune( npcEnemy )
				and not J.IsDisabled( npcEnemy )
				and not J.IsTaunted( npcEnemy )
				and not npcEnemy:IsDisarmed()
			then
				local npcEnemyDamage = npcEnemy:GetEstimatedDamageToTarget( false, bot, 3.0, DAMAGE_TYPE_PHYSICAL )
				if ( npcEnemyDamage > nMostDangerousDamage )
				then
					nMostDangerousDamage = npcEnemyDamage
					npcMostDangerousEnemy = npcEnemy
				end
			end
		end

		if npcMostDangerousEnemy ~= nil
			and J.IsInRange( bot, npcMostDangerousEnemy, nCastRange )
			and HasAttackFollowUp(npcMostDangerousEnemy)
			and CanLandDisable(npcMostDangerousEnemy, nCastPoint)
			and HasSafeShacklesPosition(npcMostDangerousEnemy)
		then
			return BOT_ACTION_DESIRE_HIGH, npcMostDangerousEnemy, 'E-Battle:'..J.Chat.GetNormName( npcMostDangerousEnemy )
		end
	end


	if J.IsGoingOnSomeone(bot) and HasAttackFollowUp(botTarget)
	then
		if J.IsValidHero( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange + 30 )
			and J.CanCastOnNonMagicImmune( botTarget )
			and J.CanCastOnTargetAdvanced( botTarget )
			and not J.IsDisabled( botTarget )
			and not J.IsTaunted( botTarget )
			and not botTarget:IsDisarmed()
			and CanLandDisable(botTarget, nCastPoint)
			and HasSafeShacklesPosition(botTarget)
		then
			if nSkillLV >= 2 or nMP > 0.68 or J.GetHP( botTarget ) < 0.35 or nHP < 0.28
			then
				return BOT_ACTION_DESIRE_HIGH, botTarget, "E-Attack:"..J.Chat.GetNormName( botTarget )
			end
		end
	end


	if J.IsRetreating( bot )
		and nSkillLV >= 3
		and #hEnemyList == 1
	then
		for _, npcEnemy in pairs( nInRangeEnemyList )
		do
			if J.IsValidHero( npcEnemy )
				and J.CanCastOnNonMagicImmune( npcEnemy )
				and J.CanCastOnTargetAdvanced( npcEnemy )
				and not J.IsDisabled( npcEnemy )
				and not J.IsTaunted( npcEnemy )
				and not npcEnemy:IsDisarmed()
				and CanLandDisable(npcEnemy, nCastPoint)
			then
				return BOT_ACTION_DESIRE_HIGH, npcEnemy, "E-Retreat:"..J.Chat.GetNormName( npcEnemy )
			end
		end
	end


	if bot:GetActiveMode() == BOT_MODE_ROSHAN
		and bot:GetMana() >= 800
	then
		if J.IsRoshan( botTarget )
			and J.GetHP( botTarget ) > 0.2
			and J.IsInRange( bot, botTarget, nCastRange + 100 )
			and not J.IsDisabled( botTarget )
			and not botTarget:IsDisarmed()
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget
		end
	end


	return BOT_ACTION_DESIRE_NONE


end

function X.ConsiderR()


	if not abilityR:IsFullyCastable() or (nHP or 1) < 0.40 or (J.IsRetreating and J.IsRetreating(bot)) then return 0 end

	local nSkillLV = abilityR:GetLevel()
	local nCastRange = abilityR:GetCastRange() + aetherRange
	local nRadius	 = 150
	local nCastPoint = abilityR:GetCastPoint()
	local nManaCost = abilityR:GetManaCost()
	local nDamage = abilityR:GetAbilityDamage()
	local nDamageType = DAMAGE_TYPE_MAGICAL
	local nInRangeEnemyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )
	local targetLocation = nil
	local building, location = X.GetSiegeWardTarget(nCastRange)
	if building ~= nil then
		return BOT_ACTION_DESIRE_HIGH, location, 'R-Pushing', building
	end

	if J.IsGoingOnSomeone(bot) and HasAttackFollowUp(botTarget)
	then
		local nAoeLoc = J.GetAoeEnemyHeroLocation( bot, nCastRange + 100, nRadius, 2 )
		if nAoeLoc ~= nil
		then
			targetLocation = nAoeLoc
			return BOT_ACTION_DESIRE_HIGH, targetLocation, 'R-Aoe'
		end

		if J.IsValidHero( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
			and J.CanCastOnMagicImmune( botTarget )
			and botTarget:GetHealth() > bot:GetAttackDamage() * 3
			and J.GetAvailableFightAllies(bot, botTarget:GetLocation(), 900) >= 1
			and (J.IsDisabled(botTarget) or botTarget:IsRooted())
		then
			targetLocation = botTarget:GetExtrapolatedLocation( nCastPoint )
			return BOT_ACTION_DESIRE_HIGH, targetLocation, "R-Attack:"..J.Chat.GetNormName( botTarget )
		end
	end


	return BOT_ACTION_DESIRE_NONE


end

function X.GetSiegeWardTarget(castRange)
	if J.IsRetreating(bot) or bot:WasRecentlyDamagedByAnyHero(2) then return end
	local attackTarget = bot:GetAttackTarget()
	local enemyTeam = GetOpposingTeam()
	local attackingBuilding = J.IsValidBuilding(attackTarget) and attackTarget:GetTeam() == enemyTeam
	local committed = J.IsPushing(bot) or attackingBuilding
	local buildings = bot:GetNearbyTowers(1300, true)
	if attackingBuilding then table.insert(buildings, 1, attackTarget) end
	for _, barracks in ipairs(bot:GetNearbyBarracks(1300, true)) do buildings[#buildings + 1] = barracks end
	buildings[#buildings + 1] = GetAncient(enemyTeam)
	local wave = bot:GetNearbyLaneCreeps(1300, false)
	for _, building in ipairs(buildings) do
		if J.IsValidBuilding(building) and building:GetTeam() == enemyTeam and J.CanBeAttacked(building)
			and not building:HasModifier('modifier_fountain_glyph')
			and not building:HasModifier('modifier_backdoor_protection_active') then
			local location = J.GetUnitTowardDistanceLocation(building, bot, 240)
			if GetUnitToLocationDistance(bot, location) <= castRange and IsLocationPassable(location) then
				local defenders = #J.GetEnemiesNearLoc(building:GetLocation(), 1100)
				local allies = J.GetAvailableFightAllies(bot, location, 1200)
				if (committed and (defenders == 0 or allies > defenders)) or (defenders == 0 and allies > 0) then
					local creeps = 0
					for _, creep in ipairs(wave) do
						if J.IsValid(creep) and J.IsInRange(creep, building, 800) then
							creeps = creeps + 1
							if creeps >= (committed and 1 or 2) then return building, location end
						end
					end
				end
			end
		end
	end
end


return X
-- dota2jmz@163.com QQ:2462331592..
