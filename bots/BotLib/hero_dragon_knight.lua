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
						{--pos2
							['t25'] = {10, 0},
							['t20'] = {0, 10},
							['t15'] = {10, 0},
							['t10'] = {0, 10},
						},
						{--pos3
							['t25'] = {10, 0},
							['t20'] = {0, 10},
							['t15'] = {10, 0},
							['t10'] = {0, 10},
						},
}

local tAllAbilityBuildList = {
	{1,2,1,3,3,6,3,3,1,1,6,2,2,2,6},--pos2
	{1,2,3,1,1,6,1,3,3,3,6,2,2,2,6},--pos3
}

local nAbilityBuildList
local nTalentBuildList

if sRole == "pos_2"
then
    nAbilityBuildList   = tAllAbilityBuildList[1]
    nTalentBuildList    = J.Skill.GetTalentBuild(tTalentTreeList[1])
else
    nAbilityBuildList   = tAllAbilityBuildList[2]
    nTalentBuildList    = J.Skill.GetTalentBuild(tTalentTreeList[2])
end

local sRoleItemsBuyList = {}

sRoleItemsBuyList['pos_2'] = {
	"item_tango",
	"item_double_branches",
	"item_quelling_blade",
	"item_circlet",
	"item_gauntlets",

	"item_bottle",
	"item_magic_wand",
	"item_bracer",
	"item_power_treads",
	"item_maelstrom",
	"item_dragon_lance",
	"item_black_king_bar",--
	"item_mjollnir",--
	"item_aghanims_shard",
	"item_greater_crit",--
	"item_hurricane_pike",--
	"item_assault",--
	"item_ultimate_scepter_2",
	"item_moon_shard",
	"item_travel_boots_2",--
}

sRoleItemsBuyList['pos_1'] = {
	"item_tango",
	"item_double_branches",
	"item_quelling_blade",
	"item_circlet",
	"item_gauntlets",

	"item_magic_wand",
	"item_bracer",
	"item_power_treads",
	"item_armlet",
	"item_yasha",
	"item_black_king_bar",--
	"item_sange_and_yasha",--
	"item_greater_crit",--
	"item_aghanims_shard",
	"item_satanic",--
	"item_ultimate_scepter_2",
	"item_bloodthorn",--
	"item_moon_shard",
	"item_travel_boots_2",--
}

sRoleItemsBuyList['pos_4'] = sRoleItemsBuyList['pos_2']

sRoleItemsBuyList['pos_5'] = sRoleItemsBuyList['pos_2']

sRoleItemsBuyList['pos_3'] = {
	"item_tango",
	"item_double_branches",
	"item_quelling_blade",
	"item_circlet",
	"item_gauntlets",

	"item_magic_wand",
	"item_bracer",
	"item_power_treads",
	"item_blink",
	"item_black_king_bar",--
	"item_crimson_guard",--
	"item_heavens_halberd",--
	"item_orchid",
	"item_aghanims_shard",
	"item_overwhelming_blink",--
	"item_bloodthorn",--
	"item_ultimate_scepter_2",
	"item_moon_shard",
	"item_travel_boots_2",--
}

X['sBuyList'] = sRoleItemsBuyList[sRole]
X['sSellList'] = {

	"item_power_treads", "item_quelling_blade",

	"item_crimson_guard", "item_quelling_blade",
	"item_black_king_bar", "item_magic_wand",
	"item_heavens_halberd", "item_bracer",
}

if J.Role.IsPvNMode() or J.Role.IsAllShadow() then X['sBuyList'], X['sSellList'] = { 'PvN_tank' }, {"item_power_treads", 'item_quelling_blade'} end

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

npc_dota_hero_dragon_knight

"Ability1"		"dragon_knight_breathe_fire"
"Ability2"		"dragon_knight_dragon_tail"
"Ability3"		"dragon_knight_dragon_blood"
"Ability4"		"generic_hidden"
"Ability5"		"generic_hidden"
"Ability6"		"dragon_knight_elder_dragon_form"
"Ability10"		"special_bonus_mp_regen_3"
"Ability11"		"special_bonus_unique_dragon_knight_3"
"Ability12"		"special_bonus_attack_damage_30"
"Ability13"		"special_bonus_hp_350"
"Ability14"		"special_bonus_gold_income_30"
"Ability15"		"special_bonus_strength_25"
"Ability16"		"special_bonus_unique_dragon_knight"
"Ability17"		"special_bonus_unique_dragon_knight_2"

modifier_dragonknight_breathefire_reduction
modifier_dragon_knight_dragon_blood_aura
modifier_dragon_knight_dragon_blood
modifier_dragon_knight_dragon_form
modifier_dragon_knight_corrosive_breath
modifier_dragon_knight_corrosive_breath_dot
modifier_dragon_knight_splash_attack
modifier_dragon_knight_frost_breath
modifier_dragon_knight_frost_breath_slow

--]]
local BreatheFire = bot:GetAbilityByName('dragon_knight_breathe_fire')
local DragonTail = bot:GetAbilityByName('dragon_knight_dragon_tail')
-- local WrymsWrath = bot:GetAbilityByName('dragon_knight_dragon_blood')
local Fireball = bot:GetAbilityByName('dragon_knight_fireball')
local ElderDragonForm = bot:GetAbilityByName('dragon_knight_elder_dragon_form')

local BreatheFireDesire, BreatheFireLocation
local DragonTailDesire, DragonTailTarget
local FireballDesire, FireballLocation
local ElderDragonFormDesire

local bInDragonForm = false
local bAttacking = false
local botTarget, botHP
local nAllyHeroes, nEnemyHeroes

function X.SkillsComplement()
	bot = GetBot()

	if J.CanNotUseAbility(bot) then return end

	BreatheFire = bot:GetAbilityByName('dragon_knight_breathe_fire')
	DragonTail = bot:GetAbilityByName('dragon_knight_dragon_tail')
	Fireball = bot:GetAbilityByName('dragon_knight_fireball')
	ElderDragonForm = bot:GetAbilityByName('dragon_knight_elder_dragon_form')

	bInDragonForm = bot:HasModifier('modifier_dragon_knight_dragon_form')
	bAttacking = J.IsAttacking(bot)
    botHP = J.GetHP(bot)
    botTarget = J.GetProperTarget(bot)
    nAllyHeroes = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
    nEnemyHeroes = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)

	if bot._defend and J.CanCastAbility(DragonTail) then
		local range = J.GetProperCastRange(false, bot, DragonTail:GetCastRange())
		local peel = J.GetTowerPeelTarget(bot, nEnemyHeroes, range)
		if peel ~= nil then
			J.SetQueuePtToINT(bot, false)
			bot:ActionQueue_UseAbilityOnEntity(DragonTail, peel)
			return
		end
	end
	local holdingTower = J.IsDefending(bot) and J.GetAssignedOuterTower(bot) ~= nil
	if holdingTower then BreatheFireDesire, BreatheFireLocation = X.ConsiderBreatheFire() end
	if not holdingTower or BreatheFireDesire <= 0 then
		ElderDragonFormDesire = X.ConsiderElderDragonForm()
		if ElderDragonFormDesire > 0 then
			J.SetQueuePtToINT(bot, false)
			bot:ActionQueue_UseAbility(ElderDragonForm)
			return
		end
	end

	if not holdingTower then BreatheFireDesire, BreatheFireLocation = X.ConsiderBreatheFire() end
	if BreatheFireDesire > 0 then
		J.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnLocation(BreatheFire, BreatheFireLocation)
		return
	end

	DragonTailDesire, DragonTailTarget = X.ConsiderDragonTail()
	if DragonTailDesire > 0 then
		J.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnEntity(DragonTail, DragonTailTarget)
		return
	end

	FireballDesire, FireballLocation = X.ConsiderFireball()
	if FireballDesire > 0 then
		J.SetQueuePtToINT(bot, false)
		bot:ActionQueue_UseAbilityOnLocation(Fireball, FireballLocation)
		return
	end
end

function X.ConsiderBreatheFire()
	if not J.CanCastAbility(BreatheFire) then
		return BOT_ACTION_DESIRE_NONE, 0
	end

	local nCastRange = J.GetProperCastRange(false, bot, BreatheFire:GetCastRange())
	local nCastPoint = BreatheFire:GetCastPoint()
	local nRadius = BreatheFire:GetSpecialValueInt('end_radius')
	local nDamage = BreatheFire:GetSpecialValueInt('damage')
	local nSpeed = BreatheFire:GetSpecialValueInt('speed')
	local nManaCost = BreatheFire:GetManaCost()
	local fManaAfter = J.GetManaAfter(nManaCost)
	local fManaThreshold1 = J.GetManaThreshold(bot, nManaCost, {BreatheFire, DragonTail, Fireball, ElderDragonForm})
	local fManaThreshold2 = J.GetManaThreshold(bot, nManaCost, {DragonTail, ElderDragonForm})
	local holdTower = J.IsDefending(bot) and J.GetAssignedOuterTower(bot) or nil
	if holdTower ~= nil and fManaAfter > fManaThreshold2 then
		local wave = bot:FindAoELocation(true, false, bot:GetLocation(), nCastRange, nRadius, nCastPoint, 0)
		if wave and wave.targetloc and (wave.count or 0) >= 2
			and GetUnitToLocationDistance(holdTower, wave.targetloc) <= 1050
			and J.GetInLocLaneCreepCount(bot, 1600, nRadius, wave.targetloc) >= 2 then
			return BOT_ACTION_DESIRE_HIGH, wave.targetloc
		end
		for _, creep in ipairs(bot:GetNearbyLaneCreeps(nCastRange, true)) do
			if J.IsValid(creep) and J.IsKeyWordUnit('_siege', creep) and creep:GetAttackTarget() == holdTower
				and not creep:HasModifier('modifier_fountain_glyph') then
				return BOT_ACTION_DESIRE_HIGH, creep:GetLocation()
			end
		end
		local poke = J.GetMidDefensePokeTarget and J.GetMidDefensePokeTarget(bot, nCastRange - 35)
		if poke and J.CanCastOnNonMagicImmune(poke) then
			return BOT_ACTION_DESIRE_HIGH, poke:GetLocation()
		end
	end

	for _, enemyHero in pairs(nEnemyHeroes) do
		if J.IsValidHero(enemyHero)
		and J.CanBeAttacked(enemyHero)
        and J.IsInRange(bot, enemyHero, nCastRange + 150)
        and J.CanCastOnNonMagicImmune(enemyHero)
        and not enemyHero:HasModifier('modifier_abaddon_borrowed_time')
        and not enemyHero:HasModifier('modifier_dazzle_shallow_grave')
		and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
        and not enemyHero:HasModifier('modifier_oracle_false_promise_timer')
		then
			local eta = (GetUnitToUnitDistance(bot, enemyHero) / nSpeed) + nCastPoint
			if J.WillKillTarget(enemyHero, nDamage, DAMAGE_TYPE_MAGICAL, eta) then
				return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation()
			end
		end
	end

	if J.IsInTeamFight(bot, 1200) then
		local hTarget = nil
		local hTargetDamage = 0
		for _, enemyHero in pairs(nEnemyHeroes) do
			if J.IsValidHero(enemyHero)
			and J.CanBeAttacked(enemyHero)
            and J.IsInRange(bot, enemyHero, nCastRange - 150)
            and J.CanCastOnNonMagicImmune(enemyHero)
            and not enemyHero:HasModifier('modifier_abaddon_borrowed_time')
            and not enemyHero:HasModifier('modifier_dazzle_shallow_grave')
			and not enemyHero:HasModifier('modifier_dragonknight_breathefire_reduction')
            and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
            and not enemyHero:HasModifier('modifier_oracle_false_promise_timer')
			then
				local enemyHeroDamage = enemyHero:GetEstimatedDamageToTarget(false, bot, 3.0, DAMAGE_TYPE_PHYSICAL)
				if enemyHeroDamage > hTargetDamage then
					hTarget = enemyHero
					hTargetDamage = enemyHeroDamage
				end
			end
		end

		if hTarget ~= nil then
			return BOT_ACTION_DESIRE_HIGH, J.GetCorrectLoc(hTarget, nCastPoint)
		end

		local nLocationAoE = bot:FindAoELocation(true, true, bot:GetLocation(), nCastRange, nRadius - 30, 0, 0)
		if nLocationAoE.count >= 2 and fManaAfter > fManaThreshold2 then
			return BOT_ACTION_DESIRE_HIGH, nLocationAoE.targetloc
		end
	end

	if J.IsGoingOnSomeone(bot) then
		if J.IsValidHero(botTarget)
		and J.CanBeAttacked(botTarget)
        and J.CanCastOnNonMagicImmune(botTarget)
        and J.IsInRange(bot, botTarget, nCastRange - 150)
        and not botTarget:HasModifier('modifier_abaddon_borrowed_time')
        and not botTarget:HasModifier('modifier_dazzle_shallow_grave')
		and not botTarget:HasModifier('modifier_dragonknight_breathefire_reduction')
		and not botTarget:HasModifier('modifier_necrolyte_reapers_scythe')
        and not botTarget:HasModifier('modifier_oracle_false_promise_timer')
		then
			if J.CanCastAbility(ElderDragonForm) then
				if fManaAfter > fManaThreshold2 then
					return BOT_ACTION_DESIRE_HIGH, J.GetCorrectLoc(botTarget, nCastPoint)
				end
			else
				return BOT_ACTION_DESIRE_HIGH, J.GetCorrectLoc(botTarget, nCastPoint)
			end
		end
	end

	if J.IsRetreating(bot) and not J.IsRealInvisible(bot) and bot:WasRecentlyDamagedByAnyHero(4.0) then
		for _, enemyHero in pairs(nEnemyHeroes) do
            if  J.IsValidHero(enemyHero)
            and J.CanBeAttacked(enemyHero)
            and J.IsInRange(bot, enemyHero, nCastRange)
            and J.CanCastOnNonMagicImmune(enemyHero)
            and not enemyHero:IsDisarmed()
			and not enemyHero:HasModifier('modifier_dragonknight_breathefire_reduction')
            then
                if J.IsChasingTarget(enemyHero, bot) or (#nEnemyHeroes > #nAllyHeroes and enemyHero:GetAttackTarget() == bot) then
                    return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation()
                end
            end
        end

		local nLocationAoE = bot:FindAoELocation(true, true, bot:GetLocation(), nCastRange - 100, nRadius, 0, 0)
		local nInRangeEnemy = J.GetEnemiesNearLoc(nLocationAoE.targetloc, nRadius)
		if #nInRangeEnemy >= 2 then
			return BOT_ACTION_DESIRE_HIGH, nLocationAoE.targetloc
		end
	end

	local nEnemyCreeps = bot:GetNearbyCreeps(Min(nCastRange + 300, 1600), true)

	if J.IsPushing(bot) and bAttacking and #nAllyHeroes <= 2 and fManaAfter > fManaThreshold1 and not bInDragonForm then
		for _, creep in pairs(nEnemyCreeps) do
            if J.IsValid(creep) and J.CanBeAttacked(creep) and not J.IsRunning(creep) then
                local nLocationAoE = bot:FindAoELocation(true, false, creep:GetLocation(), 0, nRadius, 0, 0)
                if (nLocationAoE.count >= 4) then
                    return BOT_ACTION_DESIRE_HIGH, nLocationAoE.targetloc
                end
            end
        end
	end

	if J.IsDefending(bot) and fManaAfter > fManaThreshold2
		and (#nEnemyHeroes == 0 or (bot.ohaOuterTowerHoldUntil or 0) > DotaTime()) then
		local area = bot:FindAoELocation(true, false, bot:GetLocation(), nCastRange, nRadius, nCastPoint, 0)
		if area and area.targetloc and (area.count or 0) >= 3
			and J.GetInLocLaneCreepCount(bot, 1600, nRadius, area.targetloc) >= 3 then
			return BOT_ACTION_DESIRE_HIGH, area.targetloc
		end
	end

	if J.IsFarming(bot) and bAttacking and fManaAfter > fManaThreshold2 then
		for _, creep in pairs(nEnemyCreeps) do
            if J.IsValid(creep) and J.CanBeAttacked(creep) and not J.IsRunning(creep) then
                local nLocationAoE = bot:FindAoELocation(true, false, creep:GetLocation(), 0, nRadius, 0, 0)
                if (nLocationAoE.count >= 3 and not bInDragonForm)
				or (nLocationAoE.count >= 2 and creep:IsAncientCreep())
				or (nLocationAoE.count >= 2 and fManaAfter > fManaThreshold1)
				then
                    return BOT_ACTION_DESIRE_HIGH, nLocationAoE.targetloc
                end
            end
        end
	end

	if J.IsLaning(bot) and fManaAfter > fManaThreshold2 then
		for _, creep in ipairs(nEnemyCreeps) do
			if  J.IsValid(creep)
			and J.CanBeAttacked(creep)
			and (string.find(creep:GetUnitName(), 'range') or string.find(creep:GetUnitName(), 'flagbearer') or string.find(creep:GetUnitName(), 'siege'))
			then
				local eta = (GetUnitToUnitDistance(bot, creep) / nSpeed) + nCastPoint
				if J.WillKillTarget(creep, nDamage, DAMAGE_TYPE_MAGICAL, eta) then
					if not J.IsInRange(bot, creep, bot:GetAttackRange())
					or (J.IsValidHero(nEnemyHeroes[1]) and J.IsInRange(nEnemyHeroes[1], creep, nRadius) and not J.IsSuspiciousIllusion(nEnemyHeroes[1]))
					or J.IsUnitTargetedByTower(creep, false)
					then
						return BOT_ACTION_DESIRE_HIGH, creep:GetLocation()
					end
				end
			end
		end

		local nLocationAoE = bot:FindAoELocation(true, false, bot:GetLocation(), nCastRange, nRadius, 0, nDamage)
		if not J.IsInLaningPhase() and nLocationAoE.count >= 2 then
			return BOT_ACTION_DESIRE_HIGH, nLocationAoE.targetloc
		end
	end

	if J.IsDoingRoshan(bot) then
		if J.IsRoshan(botTarget)
		and J.CanBeAttacked(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange)
		and J.CanCastOnNonMagicImmune(botTarget)
		and not botTarget:HasModifier('modifier_dragonknight_breathefire_reduction')
        and bAttacking
		and fManaAfter > fManaThreshold1
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end

	if J.IsDoingTormentor(bot) then
		if J.IsTormentor(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange)
		and not botTarget:HasModifier('modifier_dragonknight_breathefire_reduction')
        and bAttacking
		and fManaAfter > fManaThreshold1
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end

	if fManaAfter > fManaThreshold2 and not J.IsLateGame() and bAttacking and not bInDragonForm then
		for _, creep in ipairs(nEnemyCreeps) do
			if J.IsValid(creep)
			and J.CanBeAttacked(creep)
			and not J.IsRunning(creep)
			then
				local nLocationAoE = bot:FindAoELocation(true, false, creep:GetLocation(), 0, nRadius, 0, nDamage)
				if (nLocationAoE.count >= 3) then
					return BOT_ACTION_DESIRE_HIGH, nLocationAoE.targetloc
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end

function X.ConsiderDragonTail()
	if not J.CanCastAbility(DragonTail) then
		return BOT_ACTION_DESIRE_NONE, nil
	end

	local nCastRange = J.GetProperCastRange(false, bot, DragonTail:GetCastRange())
	local nDamage = DragonTail:GetSpecialValueInt('damage')
	local nSpeed = DragonTail:GetSpecialValueInt('projectile_speed')
	local nManaCost = DragonTail:GetManaCost()
	local fManaAfter = J.GetManaAfter(nManaCost)
	local fManaThreshold1 = J.GetManaThreshold(bot, nManaCost, {ElderDragonForm})

	for _, enemyHero in pairs(nEnemyHeroes) do
		if J.IsValidHero(enemyHero)
		and J.CanBeAttacked(enemyHero)
        and J.IsInRange(bot, enemyHero, nCastRange + 300)
        and J.CanCastOnNonMagicImmune(enemyHero)
        and J.CanCastOnTargetAdvanced(enemyHero)
		and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
		then
			if enemyHero:HasModifier('modifier_teleporting') then
				local fModifierTime = J.GetModifierTime(enemyHero, 'modifier_teleporting')
				if not bInDragonForm then
					local eta = GetUnitToUnitDistance(bot, enemyHero) / bot:GetCurrentMovementSpeed()
					if eta < fModifierTime then
						return BOT_ACTION_DESIRE_HIGH, enemyHero
					end
				else
					local eta = GetUnitToUnitDistance(bot, enemyHero) / nSpeed
					if eta < fModifierTime then
						return BOT_ACTION_DESIRE_HIGH, enemyHero
					end
				end
			elseif enemyHero:IsChanneling() then
				if fManaAfter > fManaThreshold1 then
					return BOT_ACTION_DESIRE_HIGH, enemyHero
				end
			end

			local eta = GetUnitToUnitDistance(bot, enemyHero) / bot:GetCurrentMovementSpeed()
			if bInDragonForm then
				eta = GetUnitToUnitDistance(bot, enemyHero) / nSpeed
			end

			if not J.CanCastAbility(BreatheFire) then
				if J.WillKillTarget(enemyHero, nDamage, DAMAGE_TYPE_MAGICAL, eta)
				and not enemyHero:HasModifier('modifier_abaddon_borrowed_time')
				and not enemyHero:HasModifier('modifier_dazzle_shallow_grave')
				and not enemyHero:HasModifier('modifier_oracle_false_promise_timer')
				and not enemyHero:HasModifier('modifier_templar_assassin_refraction_absorb')
				then
					return BOT_ACTION_DESIRE_HIGH, enemyHero
				end
			end
		end
	end

	-- Convert the support's covered lane trade into a short, in-range stun.
	-- Do not give up our own last hit or the next Breathe Fire to do it.
	if J.IsLaning(bot) and not J.IsRetreating(bot) and not J.HasPendingLaningLastHit(bot)
		and BreatheFire and bot:GetMana() >= nManaCost + BreatheFire:GetManaCost() then
		local support = J.GetLanePartner(bot)
		if J.IsValidHero(support) and J.IsInRange(bot, support, 800) then
			local target = J.GetSideLanePressureTarget(support, nEnemyHeroes, bot:GetNearbyTowers(1500, true)[1], support:GetAttackRange())
			if target and J.IsInRange(bot, target, nCastRange) and support:GetAttackTarget() == target
				and J.CanCastOnNonMagicImmune(target) and J.CanCastOnTargetAdvanced(target)
				and not J.IsDisabled(target) and not target:HasModifier('modifier_necrolyte_reapers_scythe') then
				return BOT_ACTION_DESIRE_HIGH, target
			end
		end
	end

	if J.IsInTeamFight(bot, 1200) then
		-- fire dragon
		if bInDragonForm and true then
			for _, enemyHero in pairs(nEnemyHeroes) do
				if J.IsValidHero(enemyHero)
				and J.CanBeAttacked(enemyHero)
				and J.IsInRange(bot, enemyHero, nCastRange + 300)
				and J.CanCastOnNonMagicImmune(enemyHero)
				and J.CanCastOnTargetAdvanced(enemyHero)
				and not enemyHero:IsDisarmed()
				and not enemyHero:HasModifier('modifier_faceless_void_chronosphere_freeze')
				and not enemyHero:HasModifier('modifier_enigma_black_hole_pull')
				and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
				then
					local nInRangeEnemy = J.GetEnemiesNearLoc(enemyHero:GetLocation(), 100)
					if #nInRangeEnemy >= 2 then
						return BOT_ACTION_DESIRE_HIGH, enemyHero
					end
				end
			end
		end

		local hTarget = nil
		local hTargetDamage = 0
		for _, enemyHero in pairs(nEnemyHeroes) do
			if J.IsValidHero(enemyHero)
			and J.CanBeAttacked(enemyHero)
            and J.IsInRange(bot, enemyHero, nCastRange + 300)
            and J.CanCastOnNonMagicImmune(enemyHero)
            and J.CanCastOnTargetAdvanced(enemyHero)
            and not J.IsDisabled(enemyHero)
            and not enemyHero:IsDisarmed()
			and not enemyHero:HasModifier('modifier_dragonknight_breathefire_reduction')
			and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
			and not enemyHero:HasModifier('modifier_oracle_false_promise_timer')
			then
				local enemyHeroDamage = enemyHero:GetEstimatedDamageToTarget(false, bot, 3.0, DAMAGE_TYPE_ALL)
				if enemyHeroDamage > hTargetDamage then
					hTarget = enemyHero
					hTargetDamage = enemyHeroDamage
				end
			end
		end

		if hTarget ~= nil then
			return BOT_ACTION_DESIRE_HIGH, hTarget
		end
	end

	if J.IsGoingOnSomeone(bot) then
		if J.IsValidHero(botTarget)
		and J.CanBeAttacked(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange + 300)
		and J.CanCastOnNonMagicImmune(botTarget)
		and J.CanCastOnTargetAdvanced(botTarget)
		and not J.IsDisabled(botTarget)
		and not botTarget:IsDisarmed()
		and not botTarget:HasModifier('modifier_faceless_void_chronosphere_freeze')
		and not botTarget:HasModifier('modifier_enigma_black_hole_pull')
		and not botTarget:HasModifier('modifier_necrolyte_reapers_scythe')
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget
		end
	end


	if J.IsRetreating(bot) and not J.IsRealInvisible(bot) and bot:WasRecentlyDamagedByAnyHero(3.0) then
		for _, enemyHero in pairs(nEnemyHeroes) do
			if J.IsValidHero(enemyHero)
            and J.IsInRange(bot, enemyHero, nCastRange + 300)
            and J.CanCastOnNonMagicImmune(enemyHero)
            and J.CanCastOnTargetAdvanced(enemyHero)
			and not J.IsDisabled(enemyHero)
            and not enemyHero:IsDisarmed()
			and not enemyHero:HasModifier('modifier_dragonknight_breathefire_reduction')
			then
				if J.IsChasingTarget(enemyHero, bot)
				or #nEnemyHeroes > #nAllyHeroes and enemyHero:GetAttackTarget() == bot
				or botHP < 0.5
				then
					return BOT_ACTION_DESIRE_HIGH, enemyHero
				end
			end
		end
	end

	if J.IsDoingRoshan(bot) then
		if J.IsRoshan(botTarget)
		and J.CanBeAttacked(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange)
		and J.CanCastOnTargetAdvanced(botTarget)
		and not botTarget:HasModifier('modifier_dragonknight_breathefire_reduction')
        and bAttacking
		and fManaAfter > 0.4
		and fManaAfter > fManaThreshold1
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget
		end
	end

	if J.IsDoingTormentor(bot) then
		if J.IsTormentor(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange)
		and not botTarget:HasModifier('modifier_dragonknight_breathefire_reduction')
        and bAttacking
		and fManaAfter > 0.4
		and fManaAfter > fManaThreshold1
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget
		end
	end

	return BOT_ACTION_DESIRE_NONE, nil
end

function X.ConsiderFireball()
	if not J.CanCastAbility(Fireball) then
        return BOT_ACTION_DESIRE_NONE, 0
    end

    local nCastRange = J.GetProperCastRange(false, bot, Fireball:GetCastRange())
    local nRadius = Fireball:GetSpecialValueInt('radius')
	local nManaCost = Fireball:GetManaCost()
	local fManaAfter = J.GetManaAfter(nManaCost)
	local fManaThreshold1 = J.GetManaThreshold(bot, nManaCost, {ElderDragonForm})

    if J.IsInTeamFight(bot, 1200) then
        local vLocation = J.GetAoeEnemyHeroLocation(bot, nCastRange, nRadius, 2)
        if vLocation ~= nil and fManaAfter > fManaThreshold1 then
            return BOT_ACTION_DESIRE_HIGH, vLocation
        end
    end

    if J.IsGoingOnSomeone(bot) then
        if J.IsValidHero(botTarget)
		and J.CanBeAttacked(botTarget)
        and J.IsInRange(bot, botTarget, nCastRange)
        and J.CanCastOnNonMagicImmune(botTarget)
		and J.GetHP(botTarget) > 0.15
		and not J.IsChasingTarget(bot, botTarget)
		and not botTarget:HasModifier('modifier_abaddon_borrowed_time')
		and not botTarget:HasModifier('modifier_necrolyte_reapers_scythe')
		and fManaAfter > fManaThreshold1
        then
            return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
        end
    end

	if J.IsRetreating(bot) and not J.IsRealInvisible(bot) and bot:WasRecentlyDamagedByAnyHero(3.0) then
		for _, enemyHero in pairs(nEnemyHeroes) do
			if J.IsValidHero(enemyHero)
			and J.CanBeAttacked(enemyHero)
            and J.IsInRange(bot, enemyHero, nCastRange - 100)
            and J.CanCastOnNonMagicImmune(enemyHero)
			and J.GetHP(enemyHero) < 0.5
			and not J.IsDisabled(enemyHero)
            and not enemyHero:IsDisarmed()
			and not enemyHero:HasModifier('modifier_dragonknight_breathefire_reduction')
			then
				if (J.IsChasingTarget(enemyHero, bot) and #nEnemyHeroes >= 2) then
					return BOT_ACTION_DESIRE_HIGH, bot:GetLocation()
				end

				if (#nEnemyHeroes > #nAllyHeroes and enemyHero:GetAttackTarget() == bot)
				then
					return BOT_ACTION_DESIRE_HIGH, (bot:GetLocation() + enemyHero:GetLocation()) / 2
				end
			end
		end
	end

	if J.IsDoingRoshan(bot) then
		if J.IsRoshan(botTarget)
		and J.CanBeAttacked(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange)
		and J.GetHP(botTarget) > 0.4
		and not J.IsDisabled(botTarget)
		and not botTarget:HasModifier('modifier_dragonknight_breathefire_reduction')
        and bAttacking
		and fManaAfter > 0.5
		and fManaAfter > fManaThreshold1
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end

	if J.IsDoingTormentor(bot) then
		if J.IsTormentor(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange)
		and not botTarget:HasModifier('modifier_dragonknight_breathefire_reduction')
        and bAttacking
		and fManaAfter > 0.5
		and fManaAfter > fManaThreshold1
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget:GetLocation()
		end
	end

    return BOT_ACTION_DESIRE_NONE, 0
end

function X.ConsiderElderDragonForm()
	if not J.CanCastAbility(ElderDragonForm) or botHP < 0.25 then
		return BOT_ACTION_DESIRE_NONE
	end

	if J.IsGoingOnSomeone(bot) then
		if J.IsValidHero(botTarget)
        and J.IsInRange(bot, botTarget, 800)
		and J.CanBeAttacked(botTarget)
		and not J.IsSuspiciousIllusion(botTarget)
		then
			local nInRangeAlly = J.GetAlliesNearLoc(bot:GetLocation(), 1200)
			local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1200)
			if not (#nInRangeAlly >= #nInRangeEnemy + 2) then
				if #nInRangeEnemy >= 2 then
					return BOT_ACTION_DESIRE_HIGH
				else
					if not botTarget:HasModifier('modifier_necrolyte_reapers_scythe') then
						return BOT_ACTION_DESIRE_HIGH
					end
				end
			end
		end
	end

	local pushing = J.IsPushing(bot)
	local defending = J.IsDefending(bot)
	if pushing or (botHP >= 0.6 and #nEnemyHeroes == 0 and not defending and not J.IsRetreating(bot)) then
		local building = bot:GetAttackTarget()
		if not J.IsValidBuilding(building) then building = bot:GetNearbyTowers(1000, true)[1] end
		if J.IsValidBuilding(building) and building:GetTeam() == GetOpposingTeam() and J.CanBeAttacked(building) and J.GetHP(building) > 0.2
			and J.IsInRange(bot, building, 850) and not building:HasModifier('modifier_fountain_glyph')
			and not building:HasModifier('modifier_backdoor_protection_active')
			and (#nEnemyHeroes == 0 or J.GetAvailableFightAllies(bot, building:GetLocation(), 1200) >= #nEnemyHeroes)
		then
			local wave = 0
			for _, creep in ipairs(bot:GetNearbyLaneCreeps(1200, false)) do
				if J.IsValid(creep) and J.IsInRange(creep, building, 850) then wave = wave + 1 end
			end
			if (pushing and wave >= 2) or (wave >= 3 and J.GetAvailableFightAllies(bot, building:GetLocation(), 1200) > 0) then
				return BOT_ACTION_DESIRE_HIGH
			end
		end
	end

	if defending then
		local waveSize = #bot:GetNearbyLaneCreeps(800, true)
		local defenseTower = J.GetAssignedOuterTower(bot)
		if defenseTower and waveSize < 4 then
			waveSize = 0
			for _, creep in ipairs(bot:GetNearbyLaneCreeps(1400, true)) do
				if J.IsValid(creep) and J.IsInRange(creep, defenseTower, 950) then waveSize = waveSize + 1 end
			end
		end
		local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1200)
		if waveSize >= 4 and (#nInRangeEnemy == 0
			or (not J.ShouldRetreatFromEnemyReinforcements(bot)
				and J.GetAvailableFightAllies(bot, bot:GetLocation(), 1200) >= #nInRangeEnemy - 1)) then
			return BOT_ACTION_DESIRE_HIGH
		end
	end

	if J.IsDoingRoshan(bot) and bot:GetNetWorth() < 20000 then
		if J.IsRoshan(botTarget)
		and J.CanBeAttacked(botTarget)
		and J.IsInRange(bot, botTarget, 600)
		and J.GetHP(botTarget) > 0.4
        and bAttacking
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end

	if J.IsDoingTormentor(bot) and bot:GetNetWorth() < 15000 then
		if J.IsTormentor(botTarget)
		and J.IsInRange(bot, botTarget, 600)
        and bAttacking
		then
			return BOT_ACTION_DESIRE_HIGH
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

return X
