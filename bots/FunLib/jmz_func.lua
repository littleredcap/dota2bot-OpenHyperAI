local J = {}
local LaneTeleportPolicy = require(GetScriptDirectory() .. '/FunLib/lane_teleport_policy')
local VisibleThreat = require(GetScriptDirectory() .. '/FunLib/visible_threat')

local bDebugMode = ( 1 == 10 )
local tAllyIDList = GetTeamPlayers( GetTeam() )
local tAllyHeroList = {}
local tAllyHumanList = {}

local RadiantFountain = Vector( -6619, -6336, 384 )
local DireFountain = Vector( 6928, 6372, 392 )
local RadiantTormentorLoc = Vector(7499, -7847, 256)
local DireTormentorLoc = Vector(-7229, 7933, 256)

local fKeepManaPercent = 0.39

for i, id in pairs( tAllyIDList )
do

	local bHuman = not IsPlayerBot( id )
	local hHero = GetTeamMember( i )

	if hHero ~= nil
	then
		if bHuman then table.insert( tAllyHumanList, hHero ) end
		table.insert( tAllyHeroList, hHero )
	end

end

J.Site = require( GetScriptDirectory()..'/FunLib/aba_site' )
J.Item = require( GetScriptDirectory()..'/FunLib/aba_item' )
J.Buff = require( GetScriptDirectory()..'/FunLib/aba_buff' )
J.Role = require( GetScriptDirectory()..'/FunLib/aba_role' )
J.Skill = require( GetScriptDirectory()..'/FunLib/aba_skill' )
J.Chat = require( GetScriptDirectory()..'/FunLib/aba_chat' )
J.Utils = require( GetScriptDirectory()..'/FunLib/utils' )
J.Customize = require(GetScriptDirectory()..'/FunLib/custom_loader')


function J.GetUserHeroConfig(bot)
	local name = string.gsub(bot:GetUnitName(), 'npc_dota_hero_', '')
	local ok, config = pcall(require, 'game/Customize/hero/' .. name)
	if not ok or type(config) ~= 'table' then
		ok, config = pcall(require, GetScriptDirectory() .. '/Customize/hero/' .. name)
	end
	if ok and type(config) == 'table' and config.Enable then return config end
end

function J.SetUserHeroInit( nAbilityBuildList, nTalentBuildList, sBuyList, sSellList )
	local config = J.GetUserHeroConfig(GetBot())
	if config ~= nil then
		nAbilityBuildList = config.AbilityUpgrade or nAbilityBuildList
		if config.Talent ~= nil then nTalentBuildList = J.GetTalentBuildList(config.Talent) end
		sBuyList = config.PurchaseList or sBuyList
		sSellList = config.SellList or sSellList
	end
	return nAbilityBuildList, nTalentBuildList, sBuyList, sSellList
end

function J.GetTalentBuildList( nLocalList )
	local sTargetList = {}
	for i = 1, #nLocalList
    do
		local rawTalent = nLocalList[i] == 'l' and 10 or 0
		if rawTalent == 10
		then
			sTargetList[#sTargetList + 1] = i * 2
		else
			sTargetList[#sTargetList + 1] = i * 2 - 1
		end
	end
	for i = 1, #nLocalList
    do
		local rawTalent = nLocalList[i] == 'r' and 10 or 0
		if rawTalent ~= 10
		then
			sTargetList[#sTargetList + 1] = i * 2
		else
			sTargetList[#sTargetList + 1] = i * 2 - 1
		end
	end
	return sTargetList
end

function J.HasQueuedAction( bot )
	if bot ~= GetBot()
	then
		return false
	end
	return bot:NumQueuedActions() > 0
end

function J.IsTryingtoUseAbility(bot)
	return bot:IsCastingAbility()
	or bot:IsUsingAbility()
	or bot:IsChanneling()
end

function J.CanNotUseAction( bot, allowInvulnerable, ignoreQueue )
	return not bot:IsAlive()
			or (not ignoreQueue and J.HasQueuedAction(bot))
			or (not allowInvulnerable and bot:IsInvulnerable() and not bot:HasModifier('modifier_fountain_invulnerability') and not bot:HasModifier('modifier_dazzle_nothl_projection_soul_debuff'))
			or bot:IsCastingAbility()
			or bot:IsUsingAbility()
			or bot:IsChanneling()
			or (bot:IsStunned() and not bot:HasModifier('modifier_dazzle_nothl_projection_soul_debuff'))
			or bot:IsNightmared()
			or bot:HasModifier( 'modifier_ringmaster_the_box_buff' )
			or bot:HasModifier( 'modifier_item_forcestaff_active' )
			or bot:HasModifier( 'modifier_phantom_lancer_phantom_edge_boost' )
			or bot:HasModifier( 'modifier_tinker_rearm' )

end

function J.CanNotUseAbility( bot )
	return not bot:IsAlive()
			or J.HasQueuedAction( bot )
			or (bot:IsInvulnerable() and not bot:HasModifier('modifier_fountain_invulnerability') and not bot:HasModifier('modifier_dazzle_nothl_projection_soul_debuff'))
			or bot:IsCastingAbility()
			or bot:IsUsingAbility()
			or bot:IsChanneling()
			or bot:IsSilenced()
			or (bot:IsStunned() and not bot:HasModifier('modifier_dazzle_nothl_projection_soul_debuff'))
			or bot:IsHexed()
			or bot:IsNightmared()
			or bot:HasModifier( 'modifier_ringmaster_the_box_buff' )
			or bot:HasModifier( "modifier_doom_bringer_doom" )
			or bot:HasModifier( 'modifier_item_forcestaff_active' )

end


local TempMovableModifierNames = {
    'modifier_abaddon_borrowed_time',
    'modifier_dazzle_shallow_grave',
    'modifier_wind_waker', -- movability depends on whether who uses the item.
    'modifier_item_wind_waker',
    'modifier_oracle_false_promise_timer',
    'modifier_item_aeon_disk_buff'
}
local MovableUndyingModifierRemain = 0

-- check if the target will still have at least one movable undying modifier after nDelay seconds.
function J.HasMovableUndyingModifier(botTarget, nDelay)
    for _, mName in pairs(TempMovableModifierNames)
    do
        if botTarget:HasModifier(mName) then
            MovableUndyingModifierRemain = J.GetModifierTime(botTarget, mName)
            -- print(DotaTime().." - Target has undying modifier "..mName..", the remaining time: " .. tostring(MovableUndyingModifierRemain) .. " seconds, check delay: "..tostring(nDelay))
            if MovableUndyingModifierRemain > 0 then
				if MovableUndyingModifierRemain > nDelay then
					return true
				end
				return false
            end
        end
    end
    return false
end

--友军生物数量
function J.GetUnitAllyCountAroundEnemyTarget( target, nRadius )

	local targetLoc = target:GetLocation()
	local heroCount = J.GetNearbyAroundLocationUnitCount( false, true, nRadius, targetLoc )
	local creepCount = J.GetNearbyAroundLocationUnitCount( false, false, nRadius, targetLoc )

	return heroCount + creepCount

end


--敌军生物数量
function J.GetAroundTargetEnemyUnitCount( target, nRadius )
	local targetLoc = target:GetLocation()
	return J.GetAroundTargetLocEnemyUnitCount( targetLoc, nRadius )
end

function J.GetAroundTargetLocEnemyUnitCount( targetLoc, nRadius )
	local heroCount = J.GetNearbyAroundLocationUnitCount( true, true, nRadius, targetLoc )
	local creepCount = J.GetNearbyAroundLocationUnitCount( true, false, nRadius, targetLoc )
	return heroCount + creepCount
end

--敌军英雄数量
function J.GetAroundTargetEnemyHeroCount( target, nRadius )

	return J.GetNearbyAroundLocationUnitCount( true, true, nRadius, target:GetLocation() )

end


--通用数量
function J.GetNearbyAroundLocationUnitCount( bEnemy, bHero, nRadius, vLoc )
	-- local cacheKey = 'GetNearbyAroundLocationUnitCount'..tostring(nRadius) ..'-'..tostring(bEnemy)..'-'..tostring(bHero)..'-'..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	local nCount = 0

	if bHero
	then
		if bEnemy then
			nCount = #J.GetEnemiesNearLoc(vLoc, nRadius)
		else
			nCount = #J.GetAlliesNearLoc( vLoc, nRadius )
		end
	else
		if bEnemy then
			for _, unit in pairs(GetUnitList(UNIT_LIST_ENEMIES))
			do
				if J.IsValid(unit)
				and GetUnitToLocationDistance(unit, vLoc) <= nRadius
				then
					nCount = nCount + 1
				end
			end
		else
			for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIES))
			do
				if J.IsValid(unit)
				and GetUnitToLocationDistance(unit, vLoc) <= nRadius
				then
					nCount = nCount + 1
				end
			end
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, nCount)
	return nCount

end


function J.GetAttackEnemysAllyCreepCount( target, nRadius )

	local bot = GetBot()
	local nAllyCreeps = bot:GetNearbyCreeps( nRadius, false )
	local nAttackEnemyCount = 0
	for _, creep in pairs( nAllyCreeps )
	do
		if creep:IsAlive()
			and creep:CanBeSeen()
			and creep:GetAttackTarget() == target
		then
			nAttackEnemyCount = nAttackEnemyCount + 1
		end
	end

	return nAttackEnemyCount

end

function J.GetVulnerableWeakestUnit( bot, bHero, bEnemy, nRadius )
	local unitList = {}
	if bHero
	then
		unitList = J.GetNearbyHeroes(bot, nRadius, bEnemy, BOT_MODE_NONE )
	else
		unitList = bot:GetNearbyLaneCreeps( nRadius, bEnemy )
	end
    return J.GetAttackableWeakestUnitFromList( bot, unitList )
end


function J.GetVulnerableUnitNearLoc( bot, bHero, bEnemy, nCastRange, nRadius, vLoc )

	local unitList = {}
	local weakest = nil
	local weakestHP = 10000

	if bHero
	then
		unitList = J.GetNearbyHeroes(bot, nCastRange, bEnemy, BOT_MODE_NONE )
	else
		unitList = bot:GetNearbyLaneCreeps( nCastRange, bEnemy )
	end

	for _, u in pairs( unitList )
	do
		if GetUnitToLocationDistance( u, vLoc ) < nRadius
			and u:GetHealth() < weakestHP
			and J.CanCastOnNonMagicImmune( u )
		then
			weakest = u
			weakestHP = u:GetHealth()
		end
	end

	return weakest

end


function J.GetAoeEnemyHeroLocation( bot, nCastRange, nRadius, nCount )
	-- local cacheKey = 'GetAoeEnemyHeroLocation'..tostring(bot:GetPlayerID())..'-'..tostring(nCastRange) --..'-'..tostring(nRadius)..'-'..tostring(nCount)
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.2)
	-- if cache ~= nil then return cache end

	local nAoe = bot:FindAoELocation( true, true, bot:GetLocation(), nCastRange, nRadius, 0, 0 )

	if nAoe.count >= nCount
	then
		local nEnemyHeroList = J.GetEnemyList( bot, 1600 )
		local nTrueCount = 0
		for _, enemy in pairs( nEnemyHeroList )
		do
			if GetUnitToLocationDistance( enemy, nAoe.targetloc ) <= nRadius
				and not enemy:IsMagicImmune()
			then
				nTrueCount = nTrueCount + 1
			end
		end

		if nTrueCount >= nCount
		then
			-- J.Utils.SetCachedVars(cacheKey, nAoe.targetloc)
			return nAoe.targetloc
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, nil)
	return nil

end


function J.IsWithoutTarget( bot )

	return bot:CanBeSeen()
			and bot:GetAttackTarget() == nil
			and ( bot:GetTeam() == GetBot():GetTeam() and bot:GetTarget() == nil ) 
end


function J.GetProperTarget( bot )

	local target = bot._defend and J.GetTowerDefenseTarget(bot)
	
	if target == nil and ( bot:GetTeam() == GetBot():GetTeam() )
	then
		target = bot:GetTarget()
	end

	if target == nil and bot:CanBeSeen()
	then
		target = bot:GetAttackTarget()
	end

	if target == nil or target:IsNull() or not target:CanBeSeen() then return nil end
	if target:GetTeam() == bot:GetTeam() and (target:IsHero() or target:IsBuilding()) then
		return nil
	end

	return target

end


function J.IsAllyCanKill( target )
	-- local cacheKey = 'IsAllyCanKill'..tostring(target:GetPlayerID())
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	if target:GetHealth() / target:GetMaxHealth() > 0.38
	then
		-- J.Utils.SetCachedVars(cacheKey, false)
		return false
	end

	local nTotalDamage = 0
	local nDamageType = DAMAGE_TYPE_PHYSICAL
	local nTeamMember = GetTeamPlayers( GetTeam() )
	for i = 1, #nTeamMember
	do
		local ally = GetTeamMember( i )
		if ally ~= nil and ally:IsAlive() and ally:CanBeSeen()
			and ( ally:GetAttackTarget() == target )
			and GetUnitToUnitDistance( ally, target ) <= ally:GetAttackRange() + 50
		then
			nTotalDamage = nTotalDamage + ally:GetAttackDamage()
		end
	end

	nTotalDamage = nTotalDamage * 2.44 + J.GetAttackProjectileDamageByRange( target, 1200 )

	if J.CanKillTarget( target, nTotalDamage, nDamageType )
	then
		-- J.Utils.SetCachedVars(cacheKey, true)
		return true
	end

	-- J.Utils.SetCachedVars(cacheKey, false)
	return false

end


function J.IsOtherAllyCanKillTarget( bot, target )
	-- local cacheKey = 'IsOtherAllyCanKillTarget'..tostring(target:GetPlayerID())
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	if not J.IsValid(target) then
		-- J.Utils.SetCachedVars(cacheKey, false)
		return false
	end

	if target:GetHealth() / target:GetMaxHealth() > 0.38
	then
		-- J.Utils.SetCachedVars(cacheKey, false)
		return false
	end

	local nTotalDamage = 0
	local nDamageType = DAMAGE_TYPE_PHYSICAL
	local nTeamMember = GetTeamPlayers( GetTeam() )

	for i = 1, #nTeamMember
	do
		local ally = GetTeamMember( i )
		if J.IsValidTarget(ally)
			and ally ~= bot
			and not J.IsDisabled( ally )
			and ally:GetHealth() / ally:GetMaxHealth() > 0.15
			and ally:IsFacingLocation( target:GetLocation(), 20 )
			and GetUnitToUnitDistance( ally, target ) <= ally:GetAttackRange() + 50
		then
			local allyTarget = J.GetProperTarget( ally )
			if allyTarget == nil or allyTarget == target or J.IsHumanPlayer( ally )
			then
				local allyDamageTime = J.IsHumanPlayer( ally ) and 6.0 or 2.0
				nTotalDamage = nTotalDamage + ally:GetEstimatedDamageToTarget( true, target, allyDamageTime, DAMAGE_TYPE_PHYSICAL )
			end
		end
	end

	if nTotalDamage > target:GetHealth()
	then
		-- J.Utils.SetCachedVars(cacheKey, true)
		return true
	end

	-- J.Utils.SetCachedVars(cacheKey, false)
	return false
end


function J.GetRetreatingAlliesNearLoc( vLoc, nRadius )
	-- local cacheKey = 'GetRetreatingAlliesNearLoc'..tostring(nRadius) ..tostring(J.ToNearest500(vLoc.x))..tostring(J.ToNearest500(vLoc.y))
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	local allies = {}
	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember( i )
		if member ~= nil
			and member:IsAlive()
			and GetUnitToLocationDistance( member, vLoc ) <= nRadius
			and J.IsRetreating( member )
		then
			table.insert( allies, member )
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, allies)

	return allies

end

function J.GetAlliesNearLoc( vLoc, nRadius )
	local allies = {}
	-- local cacheKey = 'GetAlliesNearLoc'..tostring(nRadius) ..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember( i )
		if member ~= nil
			and member:IsAlive()
			and GetUnitToLocationDistance( member, vLoc ) <= nRadius
		then
			table.insert( allies, member )
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, allies)

	return allies

end

function J.GetEnemiesNearLoc(vLoc, nRadius)
	-- local cacheKey = 'GetEnemiesNearLoc'..tostring(nRadius) ..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	local enemies = {}
	for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if J.IsValidHero(enemyHero)
		and GetUnitToLocationDistance(enemyHero, vLoc) <= nRadius
		and not J.IsSuspiciousIllusion(enemyHero)
		and not J.IsMeepoClone(enemyHero)
		and not enemyHero:HasModifier('modifier_arc_warden_tempest_double')
		then
			table.insert(enemies, enemyHero)
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, enemies)

	return enemies
end

function J.GetAnyEnemiesNearLoc(vLoc, nRadius)
	-- local cacheKey = 'GetAnyEnemiesNearLoc'..tostring(nRadius) ..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	local enemies = {}
	for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if J.IsValidHero(enemyHero)
		and GetUnitToLocationDistance(enemyHero, vLoc) <= nRadius
		then
			table.insert(enemies, enemyHero)
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, enemies)

	return enemies
end

function J.GetIllusionsNearLoc(vLoc, nRadius)
	-- local cacheKey = 'GetIllusionsNearLoc'..tostring(nRadius) ..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	local illusions = {}
	for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if J.IsValidHero(enemyHero)
		and GetUnitToLocationDistance(enemyHero, vLoc) <= nRadius
		and J.IsSuspiciousIllusion(enemyHero)
		and not J.IsMeepoClone(enemyHero)
		then
			table.insert(illusions, enemyHero)
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, illusions)

	return illusions
end


function J.IsAllyHeroBetweenAllyAndEnemy( hAlly, hEnemy, vLoc, nRadius )

	local vStart = hAlly:GetLocation()
	local vEnd = vLoc
	local heroList = J.GetNearbyHeroes( hAlly, 1600, false, BOT_MODE_NONE )
	for i, hero in pairs( heroList )
	do
		if hero ~= hAlly
		then
			local tResult = PointToLineDistance( vStart, vEnd, hero:GetLocation() )
			if tResult ~= nil
				and tResult.within
				and tResult.distance <= nRadius + 50
			then
				return true
			end
		end
	end

	heroList = J.GetNearbyHeroes( hEnemy, 1600, true, BOT_MODE_NONE )
	for i, hero in pairs( heroList )
	do
		if hero ~= hAlly
		then
			local tResult = PointToLineDistance( vStart, vEnd, hero:GetLocation() )
			if tResult ~= nil
				and tResult.within
				and tResult.distance <= nRadius + 50
			then
				return true
			end
		end
	end

	return false

end

function J.IsUnderLongDurationStun(enemyHero)
    return enemyHero:HasModifier('modifier_bane_fiends_grip')
    or enemyHero:HasModifier('modifier_legion_commander_duel')
    or enemyHero:HasModifier('modifier_enigma_black_hole_pull')
    or enemyHero:HasModifier('modifier_faceless_void_chronosphere_freeze')
    or enemyHero:HasModifier('modifier_magnataur_reverse_polarity')
    or enemyHero:HasModifier('modifier_tidehunter_ravage')
	or enemyHero:HasModifier('modifier_winter_wyvern_winters_curse_aura')
end

function J.GetUltimateAbility( bot )

	return bot:GetAbilityInSlot( 5 )

end


-- 7.41: Refresher Orb/Shard only refreshes ABILITIES, not items.
-- This function checks if ult is on cooldown and we have enough mana for a double-cast.
function J.CanUseRefresherShard( bot )

	local ult = J.GetUltimateAbility( bot )

	if ult ~= nil
		and ult:IsPassive() == false
	then
		local ultCD = ult:GetCooldown()
		local manaCost = ult:GetManaCost()
		local ultInCooldownAtLeast = 2 -- don't directly use refresh if the ult was just use.

		if bot:GetMana() >= manaCost * 2
			and ult:GetCooldownTimeRemaining() >= ultCD / 2
			and ultCD - ult:GetCooldownTimeRemaining() >= ultInCooldownAtLeast
		then
			return true
		end
	end

	return false

end


function J.GetMostUltimateCDUnit()

	local unit = nil
	local maxCD = 0
	for i, id in pairs( GetTeamPlayers( GetTeam() ) )
	do
		if IsHeroAlive( id )
		then
			local member = GetTeamMember( i )
			if member ~= nil and member:IsAlive()
				and member:GetUnitName() ~= "npc_dota_hero_nevermore"
				and member:GetUnitName() ~= "npc_dota_hero_arc_warden"
			then
				if member:GetUnitName() == "npc_dota_hero_silencer" or member:GetUnitName() == "npc_dota_hero_warlock"
				then
					return member
				end
				local ult = J.GetUltimateAbility( member )
				if ult ~= nil
					and ult:IsPassive() == false
					and ult:GetCooldown() >= maxCD
				then
					unit = member
					maxCD = ult:GetCooldown()
				end
			end
		end
	end

	return unit

end


function J.GetPickUltimateScepterUnit()

	local unit = nil
	local maxNetWorth = 0
	for i, id in pairs( GetTeamPlayers( GetTeam() ) )
	do
		if IsHeroAlive( id )
		then
			local member = GetTeamMember( i )
			if member ~= nil and member:IsAlive()
				and not member:HasScepter()
				and ( member:GetPrimaryAttribute() == ATTRIBUTE_INTELLECT
					 or not member:IsBot() )
			then
				if not member:IsBot()
				then
					return member
				end

				if member:GetUnitName() ~= "npc_dota_hero_warlock"
					and member:GetUnitName() ~= "npc_dota_hero_zuus"
					and ( member:GetItemInSlot( 8 ) == nil or member:GetItemInSlot( 7 ) == nil )
				then
					local mNetWorth = member:GetNetWorth()
					if mNetWorth >= maxNetWorth
					then
						unit = member
						maxNetWorth = mNetWorth
					end
				end
			end
		end
	end

	return unit

end


function J.CanUseRefresherOrb( bot )

	local ult = J.GetUltimateAbility( bot )

	if ult ~= nil
		and ult:IsPassive() == false
	then
		local ultCD = ult:GetCooldown()
		local manaCost = ult:GetManaCost()
		if bot:GetMana() >= manaCost + 375
			and ult:GetCooldownTimeRemaining() >= ultCD / 2
		then
			return true
		end
	end

	return false
end


function J.IsNoItemIllution(bot)
	-- local cacheKey = 'IsNoItemIllution'
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	if (bot:IsIllusion() or J.IsMeepoClone(bot))
	and not bot:HasModifier("modifier_arc_warden_tempest_double")
	and bot:GetUnitName() ~= 'npc_dota_hero_vengefulspirit'
	then
		-- J.Utils.SetCachedVars(cacheKey, true)
		return true
	end
	-- J.Utils.SetCachedVars(cacheKey, false)
	return false
end

function J.IsNoAbilityIllution(bot)
	-- local cacheKey = 'IsNoAbilityIllution'
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	if bot:IsIllusion()
	and not bot:HasModifier("modifier_arc_warden_tempest_double")
	and bot:GetUnitName() ~= 'npc_dota_hero_vengefulspirit'
	and not J.IsMeepoClone(bot)
	then
		-- J.Utils.SetCachedVars(cacheKey, true)
		return true
	end
	-- J.Utils.SetCachedVars(cacheKey, false)
	return false
end


function J.IsSuspiciousIllusion( npcTarget )
	if npcTarget == nil or npcTarget:IsNull() then return false end
	if npcTarget.is_suspicious_illusion ~= nil then
		return npcTarget.is_suspicious_illusion
	end
	if not npcTarget:CanBeSeen() then
		npcTarget.is_suspicious_illusion = false
		return false
	end

	if npcTarget:CanBeSeen() and (
		not npcTarget:IsHero()
		or npcTarget:IsCastingAbility()
		or npcTarget:IsUsingAbility()
		or npcTarget:IsChanneling()
	)
		-- or npcTarget:HasModifier( "modifier_item_satanic_unholy" )
		-- or npcTarget:HasModifier( "modifier_item_mask_of_madness_berserk" )
		-- or npcTarget:HasModifier( "modifier_black_king_bar_immune" )
		-- or npcTarget:HasModifier( "modifier_rune_doubledamage" )
		-- or npcTarget:HasModifier( "modifier_rune_regen" )
		-- or npcTarget:HasModifier( "modifier_rune_haste" )
		-- or npcTarget:HasModifier( "modifier_rune_arcane" )
		-- or npcTarget:HasModifier( "modifier_item_phase_boots_active" )
	then
		npcTarget.is_suspicious_illusion = false
		return false
	end

	local bot = GetBot()

	if npcTarget:GetTeam() == bot:GetTeam()
	then
		npcTarget.is_suspicious_illusion = npcTarget:IsIllusion() or npcTarget:HasModifier( "modifier_arc_warden_tempest_double" )
		return npcTarget.is_suspicious_illusion
	elseif npcTarget:GetTeam() == GetOpposingTeam()
	then

		if npcTarget:HasModifier( 'modifier_illusion' )
		or npcTarget:HasModifier( 'modifier_darkseer_wallofreplica_illusion' )
		or npcTarget:HasModifier( 'modifier_phantom_lancer_doppelwalk_illusion' )
		or npcTarget:HasModifier( 'modifier_phantom_lancer_juxtapose_illusion' )
		or npcTarget:HasModifier( 'modifier_skeleton_king_reincarnation_scepter_active' )
		or npcTarget:HasModifier( 'modifier_item_helm_of_the_undying_active' )
		or npcTarget:HasModifier( 'modifier_terrorblade_conjureimage' )
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end

		local tID = npcTarget:GetPlayerID()

		if not IsHeroAlive( tID )
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end

		if GetHeroLevel( tID ) > npcTarget:GetLevel()
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end
		--[[
		if GetSelectedHeroName( tID ) ~= "npc_dota_hero_morphling"
			and GetSelectedHeroName( tID ) ~= npcTarget:GetUnitName()
		then
			npcTarget.is_suspicious_illusion = true
			return true
		end
		--]]
	end

	npcTarget.is_suspicious_illusion = false
	return false

end


function J.CanCastAbilityOnTarget( npcTarget, bIgnoreMagicImmune )

	return npcTarget:CanBeSeen()
			and ( bIgnoreMagicImmune or not npcTarget:IsMagicImmune() )
			and not npcTarget:IsInvulnerable()
			and not J.IsSuspiciousIllusion( npcTarget )
			and not J.HasForbiddenModifier( npcTarget )
			-- and not J.IsAllyCanKill( npcTarget )

end

function J.CanCastAbility(ability)
	if ability == nil
	or ability:IsNull()
	or ability:IsPassive()
	or ability:IsHidden()
	or not ability:IsTrained()
	or not ability:IsFullyCastable()
	or not ability:IsActivated()
	then
		return false
	end

	return true
end

function J.IsTier1(tower)
	local nTower = {
		TOWER_TOP_1,
		TOWER_MID_1,
		TOWER_BOT_1,
	}

	for i = 1, #nTower do if GetTower( GetTeam(), nTower[i] ) == tower then return true end end

	return false
end

function J.IsTier2(tower)
	local nTower = {
		TOWER_TOP_2,
		TOWER_MID_2,
		TOWER_BOT_2,
	}

	for i = 1, #nTower do if GetTower( GetTeam(), nTower[i] ) == tower then return true end end

	return false
end

function J.IsTier3p(tower)
	local nTower = {
		TOWER_TOP_3,
		TOWER_MID_3,
		TOWER_BOT_3,
		TOWER_BASE_1,
		TOWER_BASE_2,
	}

	for i = 1, #nTower do if GetTower( GetTeam(), nTower[i] ) == tower then return true end end

	return false
end

function J.CanBlinkDagger(bot)
    local blink = nil

    for i = 0, 5
    do
		local item = bot:GetItemInSlot(i)

		if item ~= nil
        and (item:GetName() == "item_blink" or item:GetName() == "item_overwhelming_blink" or item:GetName() == "item_arcane_blink" or item:GetName() == "item_swift_blink")
        then
			blink = item
			break
		end
	end

    if blink ~= nil and blink:IsFullyCastable()
	then
        bot.Blink = blink
        return true
	end

    return false
end

function J.CanBlackKingBar(bot)
    local bkb = nil

    for i = 0, 5
    do
		local item = bot:GetItemInSlot(i)

		if item ~= nil and item:GetName() == "item_black_king_bar"
        then
			bkb = item
			break
		end
	end

    if bkb ~= nil and bkb:IsFullyCastable()
	then
        bot.BlackKingBar = bkb
        return true
	end

    return false
end

function J.CanCastOnMagicImmune( npcTarget )
	return npcTarget:CanBeSeen()
			and not npcTarget:IsInvulnerable()
			and not J.IsSuspiciousIllusion( npcTarget )
			and not J.HasForbiddenModifier( npcTarget )
			-- and not J.IsAllyCanKill( npcTarget )

end

function J.IsNotImmune(botTarget)
	return J.IsValidTarget(botTarget)
	and botTarget:CanBeSeen()
	and not botTarget:IsInvulnerable()
	and not botTarget:IsMagicImmune()
end

function J.FilterEnemiesForStun(enemies)
	local filteredenemies = {}
	for v, enemy in pairs(enemies) do
		if not J.IsSuspiciousIllusion(enemy) and not enemy:IsRooted() and not enemy:IsStunned() and not enemy:IsHexed() and not enemy:IsNightmared() and not J.IsTaunted(enemy) then
			table.insert(filteredenemies, enemy)
		end
	end
	return filteredenemies
end


function J.CanCastOnNonMagicImmune( npcTarget )

	return npcTarget:CanBeSeen()
			and not npcTarget:IsMagicImmune()
			and not npcTarget:IsInvulnerable()
			and not J.IsSuspiciousIllusion( npcTarget )
			and not J.HasForbiddenModifier( npcTarget )

end

function J.IsInEtherealForm( npcTarget )
	return npcTarget:HasModifier( "modifier_ghost_state" )
    or npcTarget:HasModifier( "modifier_item_ethereal_blade_ethereal" )
    or npcTarget:HasModifier( "modifier_necrolyte_death_seeker" )
    or npcTarget:HasModifier( "modifier_necrolyte_sadist_active" )
    or npcTarget:HasModifier( "modifier_pugna_decrepify" )
end

function J.CanCastOnTargetAdvanced( npcTarget )
	if J.IsSuspiciousIllusion(npcTarget) then return false end
	if npcTarget:GetUnitName() == 'npc_dota_hero_antimage' --and npcTarget:IsBot()
	then

		if npcTarget:HasModifier( "modifier_antimage_spell_shield" )
			and J.GetModifierTime( npcTarget, "modifier_antimage_spell_shield" ) > 0.27
		then
			return false
		end

		if npcTarget:IsSilenced()
			or npcTarget:IsStunned()
			or npcTarget:IsHexed()
			or npcTarget:IsNightmared()
			or npcTarget:IsChanneling()
			or J.IsTaunted( npcTarget )
			or npcTarget:GetMana() < 45
			or ( npcTarget:HasModifier( "modifier_antimage_spell_shield" )
				and J.GetModifierTime( npcTarget, "modifier_antimage_spell_shield" ) < 0.27 )
		then
			if not npcTarget:HasModifier( "modifier_item_sphere_target" )
				and not npcTarget:HasModifier( "modifier_item_lotus_orb_active" )
				and not npcTarget:HasModifier( "modifier_item_aeon_disk_buff" )
				and ( not npcTarget:HasModifier( "modifier_dazzle_shallow_grave" ) or npcTarget:GetHealth() > 300 )
			then
				return true
			end
		end

		return false
	end

	return not npcTarget:HasModifier( "modifier_item_sphere_target" )
			and not npcTarget:HasModifier( "modifier_antimage_spell_shield" )
			and not npcTarget:HasModifier( "modifier_brewmaster_earth_spell_immunity" )
			and not npcTarget:HasModifier( "modifier_item_lotus_orb_active" )
			and not npcTarget:HasModifier( "modifier_item_aeon_disk_buff" )
			and not npcTarget:HasModifier( "modifier_roshan_spell_block" )
			and ( not npcTarget:HasModifier( "modifier_dazzle_shallow_grave" ) or npcTarget:GetHealth() > 300 )

end

--加入时间后的进阶函数
function J.CanCastUnitSpellOnTarget( npcTarget, nDelay )

	for _, modifier in pairs( J.Buff["hero_has_spell_shield"] )
	do
		if npcTarget:HasModifier( modifier )
			and J.GetModifierTime( npcTarget, modifier ) >= nDelay
		then
			return false
		end
	end

	return true

end


function J.CanKillTarget( npcTarget, dmg, dmgType )
	if dmgType == DAMAGE_TYPE_PURE then
		return dmg >= npcTarget:GetHealth()
	end

	return npcTarget:GetActualIncomingDamage( dmg, dmgType ) >= npcTarget:GetHealth()

end


--未计算技能增强
function J.WillKillTarget( npcTarget, dmg, dmgType, nDelay )

	local targetHealth = npcTarget:GetHealth() + npcTarget:GetHealthRegen() * nDelay + 0.8

	local nRealBonus = J.GetTotalAttackWillRealDamage( npcTarget, nDelay )

	local nTotalDamage = npcTarget:GetActualIncomingDamage( dmg, dmgType ) + nRealBonus

	return nTotalDamage > targetHealth and nRealBonus < targetHealth - 1

end


--未计算技能增强
function J.WillMixedDamageKillTarget( npcTarget, nPhysicalDamge, nMagicalDamage, nPureDamage, nDelay )

	local targetHealth = npcTarget:GetHealth() + npcTarget:GetHealthRegen() * nDelay + 0.8

	local nRealBonus = J.GetTotalAttackWillRealDamage( npcTarget, nDelay )

	local nRealPhysicalDamge = npcTarget:GetActualIncomingDamage( nPhysicalDamge, DAMAGE_TYPE_PHYSICAL )

	local nRealMagicalDamge = npcTarget:GetActualIncomingDamage( nMagicalDamage, DAMAGE_TYPE_MAGICAL )

	local nRealPureDamge = npcTarget:GetActualIncomingDamage( nPureDamage, DAMAGE_TYPE_PURE )

	local nTotalDamage = nRealPhysicalDamge + nRealMagicalDamge + nRealPureDamge + nRealBonus

	return nTotalDamage > targetHealth and nRealBonus < targetHealth - 1

end

--计算了技能增强
function J.WillMagicKillTarget( bot, npcTarget, dmg, nDelay )

	local nDamageType = DAMAGE_TYPE_MAGICAL

	local MagicResistReduce = 1 - npcTarget:GetMagicResist()

	if MagicResistReduce < 0.05 then MagicResistReduce = 0.05 end

	local HealthBack = npcTarget:GetHealthRegen() * nDelay

	local EstDamage = dmg * ( 1 + bot:GetSpellAmp() ) - HealthBack / MagicResistReduce

	if npcTarget:HasModifier( "modifier_medusa_mana_shield" )
	then
		local EstDamageMaxReduce = EstDamage * 0.98
		if npcTarget:GetMana() * 2.8 >= EstDamageMaxReduce
		then
			EstDamage = EstDamage * 0.04
		else
			EstDamage = EstDamage * 0.02 + EstDamageMaxReduce - npcTarget:GetMana() * 2.8
		end
	end

	if npcTarget:GetUnitName() == "npc_dota_hero_bristleback"
		and not npcTarget:IsFacingLocation( bot:GetLocation(), 120 )
	then
		EstDamage = EstDamage * 0.7
	end

	if npcTarget:HasModifier( "modifier_kunkka_ghost_ship_damage_delay" )
	then
		local buffTime = J.GetModifierTime( npcTarget, "modifier_kunkka_ghost_ship_damage_delay" )
		if buffTime >= nDelay then EstDamage = EstDamage * 0.55 end
	end

	if npcTarget:HasModifier( "modifier_templar_assassin_refraction_absorb" )
	then
		local buffTime = J.GetModifierTime( npcTarget, "modifier_templar_assassin_refraction_absorb" )
		if buffTime >= nDelay then EstDamage = 0 end
	end

	local nRealDamage = npcTarget:GetActualIncomingDamage( EstDamage, nDamageType )

	return nRealDamage >= npcTarget:GetHealth() --, nRealDamage

end


function J.HasForbiddenModifier( npcTarget )

	for _, mod in pairs( J.Buff['enemy_is_immune'] )
	do
		if npcTarget:HasModifier( mod )
		then
			return true
		end
	end

	if npcTarget:IsHero()
	then
		local enemies = J.GetNearbyHeroes(npcTarget, 800, false, BOT_MODE_NONE )
		if enemies ~= nil and #enemies >= 2
		then
			for _, mod in pairs( J.Buff['enemy_is_undead'] )
			do
				if npcTarget:HasModifier( mod )
				then
					return true
				end
			end
		end
		
		-- 有的玩家太菜了，特地加一个判断让这个玩家舒服一点
		if not npcTarget:IsBot()
		then
			local nID = npcTarget:GetPlayerID()
			local nKillCount = GetHeroKills( nID )
			local nDeathCount = GetHeroDeaths( nID )
			if nDeathCount >= 6
				and nKillCount <= 6
				and nKillCount / nDeathCount <= 0.3
			then
				return true
			end
		end
		
	else
		if npcTarget:HasModifier( "modifier_crystal_maiden_frostbite" )
			or npcTarget:HasModifier( "modifier_fountain_glyph" )
		then
			return true
		end
	end
	
	return false
end


function J.GetHeroesTargetingUnit(tUnits, hUnit)
    local tAttackingUnits = {}
    for _, enemyHero in pairs(tUnits) do
        if J.IsValidHero(enemyHero)
		and not J.IsSuspiciousIllusion(enemyHero)
        and (enemyHero:GetAttackTarget() == hUnit or J.IsChasingTarget(enemyHero, hUnit))
        then
            table.insert(tAttackingUnits, enemyHero)
        end
    end

    return tAttackingUnits
end

function J.GetVisibleThreatAt(bot, enemies, point, seconds, checkInterrupt)
    return VisibleThreat.Evaluate(J, bot, enemies, point, seconds, checkInterrupt)
end

local function GetNonHeroDamageAt(bot, units, point, seconds, seen, landing, retreating)
    local damage = 0
    for _, unit in ipairs(units) do
        if not seen[unit] and unit:CanBeSeen() and unit:IsAlive() and not unit:IsDisarmed() then
            local range = unit:GetAttackRange()
            local distance = GetUnitToLocationDistance(unit, point)
            local focused = unit:GetAttackTarget() == bot
            local name = unit.GetUnitName and unit:GetUnitName() or ''
            local summon = (landing or retreating) and distance <= 850 and J.IsSiegeSummon(name)
            local laneCreep = distance <= range + 160 and (name:find('npc_dota_creep_', 1, true) or name:find('_siege', 1, true))
            local closing = retreating and summon and (distance <= range + 90 or unit.GetExtrapolatedLocation
                and J.GetLocationToLocationDistance(unit:GetExtrapolatedLocation(0.65), point) + 60 < distance)
            if focused or closing or landing and (summon or laneCreep) then
                seen[unit] = true
                local speed = unit.GetCurrentMovementSpeed and unit:GetCurrentMovementSpeed() or 0
                if unit.IsRooted and unit:IsRooted() then speed = 0 end
                local gap = math.max(0, distance - range - 60)
                local close = gap == 0 and 0 or (speed > 0 and gap / speed or math.huge)
                local period = math.max(0.25, unit:GetSecondsPerAttack())
                local windup = unit.GetAttackPoint and unit:GetAttackPoint() or 0
                local wait = math.max(close + windup, period - (GameTime() - unit:GetLastAttackTime()))
                local projectile = unit:GetAttackProjectileSpeed()
                if projectile > 0 then wait = wait + math.min(distance, range + 60) / projectile end
                if wait < seconds then
                    damage = damage + (1 + math.floor((seconds - wait) / period))
                        * bot:GetActualIncomingDamage(unit:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
                end
            end
        end
    end
    return damage
end

function J.CanLandByTeleport(bot, point)
    if not IsLocationVisible(point) then return true end
    local damage = GetNonHeroDamageAt(bot, GetUnitList(UNIT_LIST_ENEMY_CREEPS), point, 4, {}, true)
    return damage < (bot:GetHealth() + 4 * bot:GetHealthRegen()) * 0.60
end

function J.CanStartTeleportHere(bot)
    -- Include a small margin for the next order to reach the engine, and use
    -- team vision for long-range interrupts rather than the nearby-hero cap.
    local channel = 3.2
    local wraith = 'modifier_skeleton_king_reincarnation_scepter_active'
    if bot:HasModifier(wraith) and J.GetModifierTime(bot, wraith) <= channel then return false end
    local location = bot:GetLocation()
    local immune = bot:IsMagicImmune()
    local projectile = J.IsStunProjectileIncoming(bot, 3400, immune)
        or not immune and bot:HasModifier('modifier_sniper_assassinate')
    local enemies = J.GetEnemiesNearLoc(location, 3400)
    local inFlight = J.GetCreepAttackProjectileWillRealDamage(bot, channel, true)
    local seen = {}
    local focused = GetNonHeroDamageAt(bot, bot:GetNearbyCreeps(1250, true), location, channel, seen)
        + GetNonHeroDamageAt(bot, bot:GetNearbyTowers(1250, true), location, channel, seen)
    if bot.GetNearbyNeutralCreeps then
        focused = focused + GetNonHeroDamageAt(bot, bot:GetNearbyNeutralCreeps(850), location, channel, seen)
    end
    if J.GetHP(bot) <= 0.40 and bot:WasRecentlyDamagedByAnyHero(3) then
        focused = focused + GetNonHeroDamageAt(bot, GetUnitList(UNIT_LIST_ENEMY_CREEPS), location, channel, seen, false, true)
    end
    if not immune and bot:HasModifier('modifier_item_urn_damage') then
        local duration = math.min(channel, J.GetModifierTime(bot, 'modifier_item_urn_damage'))
        if duration > 0 then
            focused = focused + bot:GetActualIncomingDamage(25 * math.ceil(duration), DAMAGE_TYPE_MAGICAL)
        end
    end
    local now = DotaTime()
    local denied = bot.ohaUnsafeChannel
    if #enemies == 0 and denied and now < denied.expires
        and J.GetLocationToLocationDistance(location, denied.point) <= 475 then return false end
    if #enemies == 0 and not projectile and inFlight == 0 and focused == 0 then return true end
    local damage, interrupt, contacts = J.GetVisibleThreatAt(bot, enemies, location, channel, true)
    damage = damage + inFlight + focused
    local health = bot:GetHealth() + channel * bot:GetHealthRegen()
    -- Keep a margin for attack variance and damage already ticking in a contested lane.
    if bot:HasModifier('modifier_warlock_fatal_bonds') and bot:WasRecentlyDamagedByAnyHero(2) then
        health = health * 0.80
    elseif contacts >= 2 and J.GetHP(bot) <= 0.30 then
        health = health * 0.85
    elseif focused > 0 or contacts >= 2 and bot:WasRecentlyDamagedByAnyHero(2) then
        health = health * 0.90
    end
    if not projectile and not interrupt and damage < health then return true end
    if contacts > 0 and (interrupt or damage >= health) then
        bot.ohaUnsafeChannel = {point=location, expires=now + 1.8}
    end
    if J.Customize and J.Customize.TraceLaneDecisions and (bot.ohaTpDeniedLog or -100) + 2 <= DotaTime() then
        bot.ohaTpDeniedLog = DotaTime()
        local sources = {}
        for _, enemy in ipairs(enemies) do
            if enemy:CanBeSeen() then
                sources[#sources + 1] = string.format('%s@%.0f/mp%.0f', enemy:GetUnitName(),
                    GetUnitToUnitDistance(bot, enemy), enemy:GetMana())
            end
        end
        print(string.format('[OHA tp] %.2f hero=%s denied=%s hp=%.0f incoming=%.0f enemies=%s',
            DotaTime(), bot:GetUnitName(), projectile and 'projectile' or interrupt and 'control' or 'damage',
            bot:GetHealth(), damage, table.concat(sources, ',')))
    end
    return false
end

function J.IsLethalChaseStep(bot, target)
    if not J.IsValidHero(target) or target:GetTeam() == bot:GetTeam() or not target:CanBeSeen()
        or not J.IsGoingOnSomeone(bot) or not J.IsChasingTarget(bot, target) then return false end
    local gap = GetUnitToUnitDistance(bot, target) - bot:GetAttackRange()
    if gap <= 100 then return false end
    local point = J.VectorTowards(bot:GetLocation(), target:GetLocation(), math.min(500, gap))
    local opponents = J.GetEnemiesNearLoc(point, 1400)
    if #opponents < 2 then return false end
    local damage = J.GetVisibleThreatAt(bot, opponents, point, 3)
    return damage >= bot:GetHealth() + 3 * bot:GetHealthRegen()
end

function J.IsLaningUnderPressure(bot, enemies, tower)
    if J.IsValidBuilding(tower) and tower:GetAttackTarget() == bot then return true end

    local hp = J.GetHP(bot)
    if hp < 0.55 then
        local damage = #enemies > 0 and J.GetVisibleThreatAt(bot, enemies, bot:GetLocation(), 3) or 0
        if bot.GetIncomingTrackingProjectiles then damage = damage + J.GetCreepAttackProjectileWillRealDamage(bot, 3, true) end
        if damage >= bot:GetHealth() then return true end
    end
    local recentlyHit = bot:WasRecentlyDamagedByAnyHero(2)
    local attackers = 0
    for _, enemy in ipairs(J.GetHeroesTargetingUnit(enemies, bot)) do
        if J.IsInRange(bot, enemy, math.max(425, enemy:GetAttackRange() + 140)) then
            attackers = attackers + 1
        end
    end
    if attackers >= 2 or (attackers == 1 and hp <= 0.65 and recentlyHit) then return true end
    if hp <= 0.35 or (hp <= 0.62 and recentlyHit) then
        local nearby = 0
        for _, enemy in ipairs(enemies) do
            if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy)
                and J.IsInRange(bot, enemy, math.max(725, enemy:GetAttackRange() + 180))
            then
                nearby = nearby + 1
                if hp <= 0.5 or nearby >= 2 then return true end
            end
        end
    end
    return false
end

local function SafeLaneTower(bot, tower, enemies, hp, partner, sheltered)
    local hold = J.AdjustLocationWithOffsetTowardsFountain(tower:GetLocation(), 300)
    if hp < 0.48 and not sheltered and (#enemies > 0 or bot:WasRecentlyDamagedByAnyHero(3) or not J.IsInRange(bot, tower, 1000)
        or #J.GetLastSeenEnemiesNearLoc(hold, 1400) > 0) then return nil end
    if #J.GetLastSeenEnemiesNearLoc(hold, 850) >= 2 or bot:WasRecentlyDamagedByTower(2) then return nil end
    local pursuers = J.GetHeroesTargetingUnit(enemies, bot)
    local covered = partner ~= nil and J.GetHP(partner) >= 0.58 and not J.IsDisabled(partner)
        and J.IsInRange(bot, tower, 750) and J.IsInRange(bot, partner, 650)
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) then
            local reach = math.max(420, enemy:GetAttackRange() + 160)
            if GetUnitToLocationDistance(enemy, hold) < reach
                or (#pursuers > 0 and J.IsInRange(bot, enemy, reach) and ((hp < 0.58 and not covered) or #pursuers >= 2)) then return nil end
            local path = PointToLineDistance(bot:GetLocation(), hold, enemy:GetLocation())
            if path and path.within and path.distance < reach and GetUnitToUnitDistance(bot, enemy) > reach then return nil end
        end
    end
    return tower
end

function J.GetTowerCoveredLaneCreeps(bot, tower, creeps, enemies)
    local covered = #enemies == 0 and J.GetHP(bot) >= 0.55 and #bot:GetNearbyLaneCreeps(900, false) > 0
    local safe = {}
    for _, creep in ipairs(creeps) do
        if J.IsValid(creep) then
            local limit = covered and 1400 or 1050
            if J.IsInRange(creep, tower, 780) then
                safe[#safe + 1] = creep
            elseif (covered or J.GetHP(bot) >= 0.65 and J.IsInRange(bot, creep, bot:GetAttackRange())
                and #J.GetEnemiesNearLoc(creep:GetLocation(), 750) == 0)
                and J.IsInRange(creep, tower, limit) and #J.GetLastSeenEnemiesNearLoc(creep:GetLocation(), 1100) == 0 then
                safe[#safe + 1] = creep
            end
        end
    end
    return safe, covered
end

-- When one side laner needs to reset, the healthier partner can give ground to the T1.
-- Only take this assignment if both the retreat path and the area behind the tower are usable.
function J.GetSideLaneHoldTower(bot)
    local lane = bot:GetAssignedLane()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or DotaTime() < 40 or not J.IsInLaningPhase(bot) then return nil end
    local hp = J.GetHP(bot)
    if hp < 0.35 then return nil end
    local partner = J.GetLanePartner(bot, true)
    if partner == nil then return nil end
    local team = bot:GetTeam()
    local tower = GetTower(team, lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
    if not J.IsValidBuilding(tower) or GetUnitToUnitDistance(bot, tower) > 3300 then return nil end

    local absent = not partner:IsAlive() or partner:DistanceFromFountain() < 1200
        or (not J.IsInRange(bot, partner, 2000) and not J.IsInRange(partner, tower, 2000))
    if not absent then
        local partnerHP = J.GetHP(partner)
        local teleporting = partner:HasModifier('modifier_teleporting')
        local departing = teleporting or J.IsRetreating(partner)
        local needsReset = partnerHP < 0.34 or (partnerHP < 0.45 and partner:WasRecentlyDamagedByAnyHero(3))
        -- A partner continuing to play the wave still needs a lanemate after an ordinary trade.
        if not departing and not needsReset then
            if J.IsCore(bot) and hp >= 0.45 and J.IsInRange(bot, tower, 1300) then
                local enemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
                if J.IsLaningUnderPressure(bot, enemies, bot:GetNearbyTowers(1200, true)[1]) then
                    return SafeLaneTower(bot, tower, enemies, hp, partner)
                end
            end
            return nil
        end
        if not teleporting and (not departing or J.IsRetreating(bot)) then
            local readiness = hp + (J.IsCore(bot) and 0.06 or 0)
            local otherReadiness = partnerHP + (J.IsCore(partner) and 0.06 or 0)
            if readiness < otherReadiness or (readiness == otherReadiness and bot:GetPlayerID() > partner:GetPlayerID()) then return nil end
        end
    end

    local enemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
    if J.IsCore(bot) and not absent and hp >= 0.45 and J.IsInRange(bot, tower, 1050)
        and J.GetHP(partner) >= 0.58 and J.IsInRange(bot, partner, 650)
        and J.IsLaningUnderPressure(bot, enemies, nil) then
        local covered = SafeLaneTower(bot, tower, enemies, hp, partner)
        if covered then return covered end
    end
    if #enemies == 0 and not bot:WasRecentlyDamagedByAnyHero(5) and not J.IsRetreating(bot)
        and GetUnitToLocationDistance(tower, GetLaneFrontLocation(bot:GetTeam(), lane, 0)) > 1000 then
        local wave = bot:GetNearbyLaneCreeps(1000, true)
        if #wave == 0 or not J.IsInRange(wave[1], tower, 1400) then return nil end
    end
    if SafeLaneTower(bot, tower, enemies, hp) then return tower end
    if absent and hp >= 0.45 then
        local fallback = GetTower(team, lane == LANE_TOP and TOWER_TOP_2 or TOWER_BOT_2)
        if J.IsValidBuilding(fallback) and J.IsInRange(bot, fallback, 4200) then
            return SafeLaneTower(bot, fallback, enemies, hp)
        end
    end
end

local function GetPressuredMidLaneTower(bot)
    if bot:GetAssignedLane() ~= LANE_MID or not J.IsCore(bot) or bot:GetAttackRange() < 400
        or not J.IsInLaningPhase(bot) or J.GetHP(bot) < 0.48 then return nil end
    local tower = GetTower(bot:GetTeam(), TOWER_MID_1)
    if not J.IsValidBuilding(tower) or not J.IsInRange(bot, tower, 1100) then return nil end

    local enemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
    if not J.IsLaningUnderPressure(bot, enemies, bot:GetNearbyTowers(1200, true)[1]) then return nil end
    return SafeLaneTower(bot, tower, enemies, J.GetHP(bot))
end

function J.GetSafeLaneSupplyTower(bot)
    if not bot:IsAlive() or not J.IsInLaningPhase(bot) or bot:DistanceFromFountain() < 2300
        or bot:HasModifier('modifier_teleporting') or bot:HasModifier('modifier_ice_blast')
        or bot:HasModifier('modifier_bloodseeker_rupture') or bot:HasModifier('modifier_doom_bringer_doom')
        or J.GetHP(bot) < 0.30 then return nil end
    local lane = bot:GetAssignedLane()
    if lane ~= LANE_TOP and lane ~= LANE_MID and lane ~= LANE_BOT then return nil end
    local tower = GetTower(bot:GetTeam(), lane == LANE_TOP and TOWER_TOP_1 or (lane == LANE_MID and TOWER_MID_1 or TOWER_BOT_1))
    if not J.IsValidBuilding(tower) or not J.IsInRange(bot, tower, 2300) then return nil end
    if J.IsDoingRoshan(bot) or J.IsDoingTormentor(bot) or J.IsInTeamFight(bot, 1200)
        or (bot:GetActiveMode() == BOT_MODE_ATTACK and J.IsValidHero(bot:GetAttackTarget())) then return nil end
    local enemies = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
    if J.IsLaningUnderPressure(bot, enemies, bot:GetNearbyTowers(1200, true)[1]) then return nil end
    local hp = J.GetHP(bot)
    local partner = hp < 0.48 and lane ~= LANE_MID and J.IsCore(bot) and J.GetLanePartner(bot) or nil
    local hold = J.AdjustLocationWithOffsetTowardsFountain(tower:GetLocation(), 300)
    local sheltered = partner ~= nil and J.IsValidHero(partner) and J.GetHP(partner) >= 0.62
        and not J.IsRetreating(partner) and not J.IsDisabled(partner) and not partner:HasModifier('modifier_teleporting')
        and J.IsInRange(bot, tower, 650) and J.IsInRange(bot, partner, 650)
        and GetUnitToLocationDistance(bot, hold) <= 300 and IsLocationPassable(hold)
        and not bot:WasRecentlyDamagedByAnyHero(2)
        and #J.GetEnemiesNearLoc(hold, 1000) == 0 and #J.GetLastSeenEnemiesNearLoc(hold, 1000) == 0
        and #J.GetHeroesTargetingUnit(enemies, bot) == 0
    return SafeLaneTower(bot, tower, enemies, hp, sheltered and partner or nil, sheltered)
end

function J.GetLaningPeelTarget(bot, ally, enemies, castRange, anticipate)
    if not J.IsValidHero(ally) or not J.IsInLaningPhase(bot) then return nil end
    local hit = ally:WasRecentlyDamagedByAnyHero(2)
    if not hit and not anticipate then return nil end
    local hp = J.GetHP(ally)
    if hp >= 0.70 and not J.IsRetreating(ally) then return nil end
    local best, bestScore = nil, -math.huge
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and J.IsInRange(bot, enemy, castRange)
            and J.IsInRange(ally, enemy, math.max(425, enemy:GetAttackRange() + 180))
            and ((enemy:GetAttackTarget() == ally and (hit or (anticipate and J.IsAttacking(enemy))))
                or (hit and ally:WasRecentlyDamagedByHero(enemy, 1.4) and J.IsChasingTarget(enemy, ally)))
            and not J.IsDisabled(enemy) and not enemy:IsDisarmed()
            and J.CanCastOnNonMagicImmune(enemy) and J.CanCastOnTargetAdvanced(enemy) then
            local score = enemy:GetAttackDamage() / math.max(0.2, enemy:GetSecondsPerAttack())
                - GetUnitToUnitDistance(ally, enemy) / 15
            if score > bestScore then best, bestScore = enemy, score end
        end
    end
    return best
end

-- A visible early siege wave can reach mid without an escort: do not wait for
-- the team-defense assignment before the ranged mid starts clearing it.
function J.GetEarlyMidSiegeDefense(bot)
    local now = DotaTime()
    if now < 4 * 60 or now > 16 * 60 or bot:GetAssignedLane() ~= LANE_MID then return nil end
    local tower = GetTower(bot:GetTeam(), TOWER_MID_1)
    if not J.IsValidBuilding(tower) or not J.IsInRange(bot, tower, 2200) then return nil end
    local threat = J.GetOuterTowerThreat(tower, LANE_MID)
    if threat.siegeAttacking or (threat.siege and threat.waveSize >= 1 and threat.eta <= 7) then
        return tower
    end
    if threat.middleGroup and J.GetHP(bot) >= 0.55 and not J.IsRetreating(bot) then
        local fountain = J.GetTeamFountain()
        if GetUnitToLocationDistance(bot, fountain) <= GetUnitToLocationDistance(tower, fountain) + 250 then
            return tower
        end
    end
end

function J.GetLaningHoldTower(bot)
    local delivery = bot.ohaLaneSupply
    if delivery and not delivery.proactive and delivery.waitUntil > DotaTime() and (bot.ohaCourierUnsafeUntil or 0) <= DotaTime()
        and (delivery.item ~= 'item_clarity' or J.GetHP(bot) < 0.68)
        and bot.theCourier and not bot.theCourier:IsNull() and bot.theCourier:IsAlive() then
        local tower = J.GetSafeLaneSupplyTower(bot)
        if tower then return tower end
    end
    return J.GetSideLaneHoldTower(bot) or GetPressuredMidLaneTower(bot)
end

-- A side laner can recover contact without waiting for the wave to enter the
-- local last-hit scan. This is a walk to experience range, not a commit.
function J.GetSideLaneReturnPoint(bot, lane)
    local now = DotaTime()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or now < 40 or not J.IsInLaningPhase(bot) then return nil end
    local core = J.IsCore(bot)
    if J.GetHP(bot) < (core and 0.58 or 0.65)
        or not core and bot:GetAttackRange() < 310
        or not bot.DistanceFromFountain or bot:WasRecentlyDamagedByAnyHero(2)
        or bot:HasModifier('modifier_teleporting') or J.IsDisabled(bot)
        or (bot.ohaOuterTowerHoldUntil or 0) > now or not GetUnitList then return nil end
    local fountainDistance = bot:DistanceFromFountain()
    local recovered = fountainDistance < 1300 and J.GetHP(bot) > 0.90 and J.GetMP(bot) > 0.80
    if fountainDistance < 1000 and not recovered then return nil end
    local supply = bot.ohaLaneSupply
    if supply and supply.waitUntil > now and (bot.ohaCourierUnsafeUntil or 0) <= now
        and (supply.item ~= 'item_clarity' or J.GetHP(bot) < 0.68) then return nil end
    local origin, team = bot:GetLocation(), bot:GetTeam()
    local tower = GetTower(team, lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
    if not J.IsValidBuilding(tower) then return nil end
    -- After the initial lane phase, reconnect only to a nearby wave.
    local early = now < (J.IsModeTurbo() and 480 or 600)
    if not early and not J.IsInRange(bot, tower, 2800) then return nil end
    local returning = early and (recovered or (bot.ohaSideLaneReturnUntil or 0) > now)
    local partner = J.GetLanePartner(bot, true)
    local partnerReady = J.IsValidHero(partner) and J.GetHP(partner) >= 0.60
        and not J.IsDisabled(partner) and not J.IsRetreating(partner) and not partner:HasModifier('modifier_teleporting')
    if not core and not returning and (not J.IsValidHero(partner) or not J.IsCore(partner)) then return nil end
    local hub, wave, distance = tower:GetLocation(), nil, (core or returning) and 20000 or 4800
    local front = GetLaneFrontLocation(team, lane, 0)
    -- Don't turn a distant recovery route into a chase into enemy territory.
    for _, creep in ipairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS)) do
        if J.IsValid(creep) and creep:CanBeSeen() and string.find(creep:GetUnitName(), 'npc_dota_creep_', 1, true)
            and GetAmountAlongLane(lane, creep:GetLocation()).distance <= 525
            and GetUnitToUnitDistance(creep, tower) <= 3200
            and GetUnitToLocationDistance(creep, front) <= 1600 then
            local d = GetUnitToUnitDistance(bot, creep)
            if d < distance then wave, distance = creep, d end
        end
    end
    if not wave then
        if not returning then return nil end
        distance = GetUnitToUnitDistance(bot, tower)
    end
    if distance <= math.max(600, bot:GetAttackRange() + 370) then return nil end
    local point = wave and wave:GetLocation() or hub
    local covered = J.IsValidHero(partner) and J.GetHP(partner) >= 0.50 and not J.IsDisabled(partner)
        and not partner:HasModifier('modifier_teleporting') and not J.IsRetreating(partner)
        and GetUnitToLocationDistance(partner, point) <= 1050
    local distanceToTower = J.GetLocationToLocationDistance(point, hub)
    -- A healthy support can return to a defending partner even if neither
    -- can safely advance into the enemy wave yet.
    local towerOnly = not wave or not core and (not partnerReady or not covered or distance > 2200)
    if towerOnly and (J.GetHP(bot) < 0.75 or J.IsInRange(bot, tower, 650)
        or not returning and (distanceToTower > 1750 or not J.IsInRange(partner, tower, 800))) then return nil end
    local hasLaneCover = false
    for _, creep in ipairs(GetUnitList(UNIT_LIST_ALLIED_CREEPS)) do
        if J.IsValid(creep) and string.find(creep:GetUnitName(), 'npc_dota_creep_', 1, true)
            and GetUnitToLocationDistance(creep, point) <= 700 then hasLaneCover = true; break end
    end
    local sheltered = not towerOnly and (covered or hasLaneCover)
    local threatRadius = covered and 775 or 950
    local enemyTower = GetTower(GetOpposingTeam(), lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
    local function IsSafeReturnStep(step, radius)
        local travel = GetUnitToLocationDistance(bot, step)
        if travel <= 225 then return false end
        local mid = J.VectorTowards(origin, step, travel * 0.5)
        return IsLocationPassable(step) and IsLocationPassable(mid) and IsLocationVisible(step)
            and (not J.IsValidBuilding(enemyTower) or GetUnitToLocationDistance(enemyTower, step) > 1050)
            and #J.GetEnemiesNearLoc(origin, radius) == 0
            and #J.GetEnemiesNearLoc(mid, radius) == 0
            and #J.GetLastSeenEnemiesNearLoc(mid, radius) == 0
            and #J.GetEnemiesNearLoc(step, radius) == 0
            and #J.GetLastSeenEnemiesNearLoc(step, radius) == 0
    end
    -- If the wave is contested, return to the tower instead of abandoning
    -- the lane or walking all the way into the contested wave.
    local offsets = towerOnly and {math.max(distanceToTower, 825)}
        or sheltered and {math.max(500, bot:GetAttackRange() + 120), 825, 1125, 1325}
        or {distanceToTower > 1050 and distanceToTower or 825, 1325}
    for _, offset in ipairs(offsets) do
        local step = distanceToTower > offset + 70 and J.VectorTowards(point, hub, offset) or hub
        if J.GetLocationToLocationDistance(step, point) + 90 < distance and IsSafeReturnStep(step, threatRadius) then
            return step, recovered and early
        end
    end
    -- Rejoin from the rear while the wave or the T1 approach is contested.
    -- Each stop still has to advance toward the lane from the bot's current location.
    if returning and not J.IsInRange(bot, tower, 2400) then
        local rear = J.AdjustLocationWithOffsetTowardsFountain(hub, 850)
        if IsSafeReturnStep(rear, 950) then return rear, recovered, tower end
        local towerDistance = GetUnitToUnitDistance(bot, tower)
        local rearTowers = lane == LANE_TOP and {TOWER_TOP_2, TOWER_TOP_3} or {TOWER_BOT_2, TOWER_BOT_3}
        for _, id in ipairs(rearTowers) do
            local anchor = GetTower(team, id)
            if J.IsValidBuilding(anchor) and GetUnitToUnitDistance(anchor, tower) + 225 < towerDistance
                and IsSafeReturnStep(anchor:GetLocation(), 950) then
                return anchor:GetLocation(), recovered, anchor
            end
        end
    end
end

-- Yield just enough ground to leave active attack/disable reach. The
-- ordinary retreat remains in charge if the contact cannot be broken safely.
function J.GetSideLaneYieldPoint(bot, enemies, enemyTower, underPressure)
    local lane = bot:GetAssignedLane()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or not J.IsInLaningPhase(bot)
        or not bot.DistanceFromFountain or not bot.GetCurrentMovementSpeed or J.GetHP(bot) < 0.46
        or not J.IsCore(bot) or J.IsDisabled(bot) or bot:IsRooted()
        or #enemies == 0 or #enemies > 2 or bot:WasRecentlyDamagedByTower(2)
        or J.IsValidBuilding(enemyTower) and enemyTower:GetAttackTarget() == bot then return nil end
    local own = GetTower(bot:GetTeam(), lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
    if not J.IsValidBuilding(own) then return nil end
    local origin, front, rear = bot:GetLocation(), GetLaneFrontLocation(bot:GetTeam(), lane, 0), own:GetLocation()
    local early = underPressure == false
    if early then
        local linked = bot:HasModifier('modifier_warlock_fatal_bonds')
        if bot:GetAttackRange() >= 310 or not (linked or bot:WasRecentlyDamagedByAnyHero(2)) then return nil end
        local focused = false
        for _, enemy in ipairs(J.GetHeroesTargetingUnit(enemies, bot)) do
            if J.IsInRange(bot, enemy, enemy:GetAttackRange() + 150) then focused = true; break end
        end
        if not focused and not linked then return nil end
        local limit = linked and 0.10 or 0.11
        if not linked and bot.ohaLaningAttackTarget and J.HasPendingLaningLastHit(bot) then limit = 0.24 end
        if J.GetVisibleThreatAt(bot, enemies, origin, 2.2) < bot:GetHealth() * limit then return nil end
    end
    local partner = J.GetLanePartner(bot, true)
    local cover = J.IsValidHero(partner) and J.GetHP(partner) >= 0.55 and not J.IsRetreating(partner)
        and not J.IsDisabled(partner) and not partner:HasModifier('modifier_teleporting')
    if #enemies == 2 and not cover and not early then return nil end
    if J.GetLocationToLocationDistance(origin, rear) < 250 then rear = J.GetTeamFountain() end
    local pathLength = J.GetLocationToLocationDistance(origin, rear)
    if pathLength < 225 then return nil end
    for _, offset in ipairs({360, 540, 720}) do
        local step = math.min(offset, pathLength)
        local point = J.VectorTowards(origin, rear, step)
        local mid = J.VectorTowards(origin, point, step / 2)
        local safe = IsLocationPassable(point) and IsLocationPassable(mid) and IsLocationVisible(point)
            and J.GetLocationToLocationDistance(point, front) <= 1350
            and (not cover or GetUnitToLocationDistance(partner, point) <= 1250)
        if safe then
            for _, foe in ipairs(enemies) do
                if J.IsValidHero(foe) and not J.IsSuspiciousIllusion(foe) then
                    local reach = math.max(500, foe:GetAttackRange() + 150)
                    if GetUnitToLocationDistance(foe, point) <= reach
                        or GetUnitToLocationDistance(foe, mid) + 30 < GetUnitToUnitDistance(foe, bot) then
                        safe = false; break
                    end
                end
            end
        end
        if safe and #J.GetLastSeenEnemiesNearLoc(point, 520) == 0 then
            local escapeTime = math.min(3, step / math.max(1, bot:GetCurrentMovementSpeed()) + 0.6)
            local damage, control = J.GetVisibleThreatAt(bot, enemies, point, escapeTime, true)
            -- The retreat mode must keep control when a short step still
            -- leaves an injured core in reach of a disable or follow-up.
            if damage < bot:GetHealth() * (control and 0.20 or 0.35)
                and (not control or J.GetHP(bot) > 0.62) then return point end
        end
    end
end

-- Give support a useful job during the return, but never ask it to lead
-- a solo dive or leave an already exposed core undefended.
function J.GetSideLaneReturnScreen(bot)
    local lane = bot:GetAssignedLane()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or not J.IsInLaningPhase(bot)
        or not bot.DistanceFromFountain or not J.IsValidHero(bot)
        or J.IsCore(bot) or J.GetHP(bot) < 0.63 or J.IsDisabled(bot)
        or bot:WasRecentlyDamagedByAnyHero(2) or #bot:GetNearbyHeroes(1000, true, BOT_MODE_NONE) > 0 then return nil end
    local partner = J.GetLanePartner(bot, true)
    if not J.IsValidHero(partner) or not J.IsCore(partner) or not partner.GetLocation then return nil end
    local point = J.GetSideLaneReturnPoint(partner, lane)
    if not point or not J.IsInRange(bot, partner, 1400) then return nil end
    local travel = GetUnitToLocationDistance(bot, point)
    if travel < 330 or travel > 1100 then return nil end
    local mid = J.VectorTowards(bot:GetLocation(), point, travel * 0.5)
    if IsLocationPassable(mid) and #J.GetLastSeenEnemiesNearLoc(mid, 800) == 0 then return point end
end

function J.GetLaningManaShortfall(bot, seconds)
    if bot:GetMaxMana() <= 0 or J.GetMP(bot) >= 0.40 or bot:HasModifier('modifier_clarity_potion') then return nil end
    local projected = bot:GetMana() + bot:GetManaRegen() * seconds
    local shortfall
    for slot = 0, 5 do
        local ability = bot:GetAbilityInSlot(slot)
        if ability and not ability:IsNull() and ability:IsTrained() and ability:IsActivated() and not ability:IsHidden()
            and not ability:IsPassive() and ability:GetCooldownTimeRemaining() <= seconds + 5 then
            local cost = ability:GetManaCost()
            if cost > projected and cost <= bot:GetMaxMana()
                and (not ability:IsUltimate() or #bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE) > 0) then
                shortfall = math.min(shortfall or math.huge, cost - projected)
            end
        end
    end
    return shortfall
end

function J.CanRecoverWithLaneStick(bot, item, health)
    if item:GetCurrentCharges() < 6 then return false end
    local gain = item:GetCurrentCharges() * item:GetSpecialValueInt('restore_per_charge')
    if health then
        return J.GetHP(bot) < 0.48 and bot:OriginalGetHealth() + gain >= bot:OriginalGetMaxHealth() * 0.5
    end
    local shortfall = J.GetLaningManaShortfall(bot, 5)
    return shortfall ~= nil and gain >= shortfall
end

function J.GetLaningAttackDamage(bot)
    local damage = bot:GetAttackDamage()
    if bot:GetItemSlotType(bot:FindItemSlot('item_quelling_blade')) == ITEM_SLOT_TYPE_MAIN then
        damage = damage + ((bot:GetAttackRange() > 310 or bot:GetUnitName() == 'npc_dota_hero_templar_assassin') and 4 or 8)
    end
    if bot:GetUnitName() == 'npc_dota_hero_skeleton_king' then
        local strike = bot:GetAbilityByName('skeleton_king_mortal_strike')
        if strike ~= nil and strike:IsTrained() and strike:IsActivated() and strike:IsCooldownReady() then
            local multiplier = strike:GetSpecialValueInt('crit_mult') / 100
            damage = damage + bot:GetAttackDamage() * math.max(0, multiplier - 1)
        end
    end
    return damage
end

local function LaneAttackDamage(attacker, target, damage)
    -- Some bot runtimes do not expose the documented attack-type multiplier.
    local multiplier = 1
    if type(attacker.GetAttackCombatProficiency) == 'function' then
        local proficiency = attacker:GetAttackCombatProficiency(target)
        if type(proficiency) == 'number' and proficiency > 0 then multiplier = proficiency end
    end
    return target:GetActualIncomingDamage(damage * multiplier, DAMAGE_TYPE_PHYSICAL)
end

function J.IsFinishingLaningAttack(bot, target)
    if not J.IsValid(target) or not J.IsAttacking(bot) or not J.IsInRange(bot, target, bot:GetAttackRange()) then
        return false
    end
    if not target:IsCreep() or (target == bot.ohaLaningAttackTarget
        and bot:GetLastAttackTime() == bot.ohaLaningAttackPreviousShot) then return true end
    return target:GetHealth() <= LaneAttackDamage(bot, target, J.GetLaningAttackDamage(bot))
end

function J.IssueLaningAttack(bot, target)
    bot.ohaLaningAttackTarget = target
    bot.ohaLaningAttackPreviousShot = bot:GetLastAttackTime()
    local now = GameTime()
    local _, release = J.GetAttackProDelayTime(bot, target)
    bot.ohaLaningAttackOrderedAt = now
    bot.ohaLaningAttackUntil = now + (release or 0.3) + 0.13
    bot:Action_AttackUnit(target, true)
end

function J.HasPendingLaningLastHit(bot)
    local target = bot.ohaLaningAttackTarget
    local now = GameTime()
    return J.IsValid(target) and target:IsCreep()
        and (bot.ohaLaningAttackUntil or 0) > now
        and bot:GetLastAttackTime() == bot.ohaLaningAttackPreviousShot
        and J.IsInRange(bot, target, bot:GetAttackRange() + 50)
        and (bot:GetAttackTarget() == target or now - (bot.ohaLaningAttackOrderedAt or 0) <= 0.12)
end

function J.HoldLaningAttack(bot, target)
    bot.ohaLaningAttackTarget = nil
    if J.IsValid(target) then bot:Action_ClearActions(true) end
end

local function GetLaneAttackers(bot, tower, enemies, allies)
    local attackers = {}
    if J.IsValidBuilding(tower) then attackers[1] = tower end
    for _, heroes in ipairs({enemies, allies}) do
        for _, hero in ipairs(heroes) do
            if hero ~= bot and J.IsValidHero(hero) and not J.IsSuspiciousIllusion(hero) then
                attackers[#attackers + 1] = hero
            end
        end
    end
    return attackers
end

local function GetLaneCreepHealthAt(creep, delay, attackers, exclude)
    local remaining = creep:GetHealth() + creep:GetHealthRegen() * delay - J.GetTotalAttackWillRealDamage(creep, delay, true)
    for _, attacker in ipairs(attackers) do
        local windingUp = attacker:GetAttackTarget() == creep and J.IsAttacking(attacker)
        local ordered = attacker.ohaLaningAttackTarget == creep and J.HasPendingLaningLastHit(attacker)
        if attacker ~= exclude and (windingUp or ordered) then
            local impact, release = J.GetAttackProDelayTime(attacker, creep, windingUp)
            if release > 0 and impact < delay - 0.033 then
                remaining = remaining - LaneAttackDamage(attacker, creep, attacker:GetAttackDamage())
            end
        end
    end
    return remaining
end

local function CanReserveLaneCreepShot(creep, damage, impact, nextImpact, attackers, exclude)
    local health = GetLaneCreepHealthAt(creep, nextImpact, attackers, exclude)
    if health > 0 then return health <= damage end

    -- Separate hits may leave a short last-hit window before the creep dies.
    for _ = 1, 4 do
        local time = (impact + nextImpact) / 2
        health = GetLaneCreepHealthAt(creep, time, attackers, exclude)
        if health <= 0 then
            nextImpact = time
        elseif health <= damage then
            return true
        else
            impact = time
        end
    end
    return false
end

local function GetSupportLastHitStep(bot, creep, distance, tower, enemies)
    local range, lane = bot:GetAttackRange(), bot:GetAssignedLane()
    if range < 310 or (lane ~= LANE_TOP and lane ~= LANE_BOT) or not J.IsInLaningPhase(bot)
        or J.GetHP(bot) < 0.65 or J.IsRetreating(bot)
        or bot:WasRecentlyDamagedByAnyHero(2) or bot:WasRecentlyDamagedByCreep(1.5) then return nil end
    local origin = bot:GetLocation()
    local point = J.VectorTowards(origin, creep:GetLocation(), distance - range + 20)
    if not IsLocationPassable(point) or GetHeightLevel(point) ~= GetHeightLevel(origin)
        or (J.IsValidBuilding(tower) and GetUnitToLocationDistance(tower, point) <= 850)
        or #J.GetLastSeenEnemiesNearLoc(point, 650) > 0 then return nil end
    for _, enemy in ipairs(enemies or {}) do
        if J.IsValidHero(enemy) and GetUnitToLocationDistance(enemy, point) <= math.max(650, enemy:GetAttackRange() + 150) then
            return nil
        end
    end
    for _, ally in ipairs(bot:GetNearbyLaneCreeps(1000, false)) do
        if J.IsValid(ally) and J.IsInRange(ally, creep, 500) then return point end
    end
end

function J.GetLaneCreepGoldValue(bot, creep)
    local name = creep:GetUnitName()
    local flagbearer = name:find('_flagbearer', 1, true) ~= nil
    local ranged = name:find('_ranged', 1, true) ~= nil
    local siege = name:find('_siege', 1, true) ~= nil
    local bounty = siege and 64 or ranged and 47 or 37
    if creep.GetBountyGoldMin and creep.GetBountyGoldMax then
        local minimum, maximum = creep:GetBountyGoldMin(), creep:GetBountyGoldMax()
        if minimum and minimum > 0 and maximum and maximum >= minimum then
            bounty = (minimum + maximum) * 0.5
        end
    end
    if flagbearer then
        local bonus = bounty
        for _, ally in ipairs(J.GetAlliesNearLoc(creep:GetLocation(), 1500)) do
            if ally ~= bot and J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally) then
                bonus = bonus + bounty
            end
        end
        bounty = bounty + bonus
    end
    return bounty, flagbearer or ranged or siege
end

function J.GetLaningLastHitTarget(bot, creeps, tower, attackDamage, enemies, coveringLane, occupiedTime)
    if #creeps == 0 then return nil, false, false end
    local range = bot:GetAttackRange()
    local core = J.IsCore(bot)
    local attackers = GetLaneAttackers(bot, bot:GetNearbyTowers(1600, false)[1], enemies or {},
        bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE))
    local attackInterval = bot:GetSecondsPerAttack()
    local holdsAttack, supportStep = false, nil
    local best, bestScore, approach, approachScore, urgentApproach = nil, -math.huge, nil, -math.huge, false
    local bestValue, bestExpires, reserveValue = 0, false, 0
    for _, creep in ipairs(creeps) do
        if J.IsValid(creep) and J.CanBeAttacked(creep) and J.CanSupportTakeLaneLastHit(bot, creep) then
            local distance = GetUnitToUnitDistance(bot, creep)
            local inRange = distance <= range
            local value, valuable = J.GetLaneCreepGoldValue(bot, creep)
            local approachRange = (core or coveringLane) and 425 or (valuable and 240 or 120)
            if inRange or (distance <= range + approachRange
                and not (J.IsValidBuilding(tower) and J.IsInRange(creep, tower, 825))) then
                local delay, _, wait = J.GetAttackProDelayTime(bot, creep)
                -- Includes approach, attack recovery, turn allowance and flight once.
                local remaining = GetLaneCreepHealthAt(creep, delay, attackers)
                local damage = LaneAttackDamage(bot, creep, attackDamage)
                if remaining > 0 then
                    local score = (damage - remaining) / math.max(1, damage) - distance / 2000
                    if inRange and remaining <= damage then
                        if (wait or 0) <= 0.17 then
                            -- Use the next swing on an expiring window first when both can be collected.
                            local later = GetLaneCreepHealthAt(creep, delay + attackInterval, attackers)
                            local expires = later <= 0 or later > damage
                            if best == nil or expires and not bestExpires or expires == bestExpires
                                and (value > bestValue or value == bestValue and score > bestScore) then
                                best, bestScore, bestValue, bestExpires = creep, score, value, expires
                            end
                        elseif wait <= math.max(0.48, occupiedTime or 0) then
                            holdsAttack = true
                        end
                    elseif (inRange or occupiedTime and core) and (not holdsAttack or inRange and valuable and value > reserveValue)
                        and (not occupiedTime or (wait or 0) < math.max(0.65, occupiedTime))
                        and remaining > damage and remaining <= damage * 2.5 then
                        local soon = delay + math.max(occupiedTime or 0, math.min(0.55, attackInterval * 0.5))
                        if CanReserveLaneCreepShot(creep, damage, delay, soon, attackers) then
                            holdsAttack = true
                            if inRange and valuable and GetLaneCreepHealthAt(creep, delay + attackInterval, attackers) <= 0 then
                                reserveValue = math.max(reserveValue, value)
                            end
                        end
                    end
                    local lethalOnArrival = remaining <= damage
                    local approachPriority = value / 35 + score
                    if not inRange and remaining <= damage * 1.45
                        and (approach == nil or lethalOnArrival and not urgentApproach
                            or lethalOnArrival == urgentApproach and approachPriority > approachScore) then
                        local step
                        if not core and not coveringLane and (lethalOnArrival or valuable) then
                            step = GetSupportLastHitStep(bot, creep, distance, tower, enemies)
                        end
                        if core or coveringLane or step then
                            approach, approachScore, supportStep = creep, approachPriority, step
                            urgentApproach = lethalOnArrival
                        end
                    end
                end
            end
        end
    end
    if reserveValue > bestValue then return nil, false, true end
    if best ~= nil then return best, false end
    return approach, approach ~= nil, holdsAttack, urgentApproach, supportStep
end

function J.TrySecureNativeMidLastHit(bot)
    if not bot.ohaEngineMid or DotaTime() < 60 or not J.IsLaning(bot) or not J.IsInLaningPhase(bot)
        or GameTime() - bot:GetLastAttackTime() < math.max(2.7, bot:GetSecondsPerAttack() * 1.5)
        or J.CanNotUseAction(bot) or bot:IsDisarmed() or J.HasPendingLaningLastHit(bot) then return false end
    local current = bot:GetAttackTarget()
    if J.IsValid(current) and J.IsAttacking(bot) then return false end
    local creeps = bot:GetNearbyLaneCreeps(math.min(1600, bot:GetAttackRange()), true)
    if #creeps == 0 then return false end
    local enemies = J.GetNearbyHeroes(bot, 1250, true, BOT_MODE_NONE)
    local tower = bot:GetNearbyTowers(1200, true)[1]
    if J.IsLaningUnderPressure(bot, enemies, tower) then return false end
    local target, approach = J.GetLaningLastHitTarget(bot, creeps, tower, J.GetLaningAttackDamage(bot), enemies)
    if target == nil or approach then return false end
    J.IssueLaningAttack(bot, target)
    if J.Customize and J.Customize.TraceLaneDecisions then
        print('[OHA lane native-mid]', DotaTime(), bot:GetPlayerID(), target:GetUnitName())
    end
    return true
end

-- The tower is about to take a creep neither laner can finish alone.
function J.GetLaningTowerJointHit(bot, tower, enemies)
    if not J.IsValidBuilding(tower) or not J.IsInLaningPhase(bot) then return nil end
    local creep = tower:GetAttackTarget()
    if not creep or not J.IsValid(creep) or not creep:IsCreep() or creep:GetTeam() == bot:GetTeam()
        or not J.CanBeAttacked(creep) or not J.IsInRange(bot, creep, bot:GetAttackRange()) then return nil end
    local partner = J.GetLanePartner(bot)
    if not J.IsValidHero(partner) or not partner:IsBot() or J.IsDisabled(partner) or partner:IsDisarmed()
        or partner:IsChanneling() or partner:HasModifier('modifier_teleporting') or J.GetHP(partner) < 0.55
        or J.IsRetreating(partner) or not J.IsInRange(partner, creep, partner:GetAttackRange())
        or J.HasPendingLaningLastHit(partner) and partner.ohaLaningAttackTarget ~= creep then return nil end
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and J.IsInRange(enemy, creep, math.max(800, enemy:GetAttackRange() + 180)) then return nil end
    end

    local hp = creep:GetHealth()
    local own = LaneAttackDamage(bot, creep, J.GetLaningAttackDamage(bot))
    local other = LaneAttackDamage(partner, creep, J.GetLaningAttackDamage(partner))
    if hp <= math.max(own, other) or hp > own + other
        or hp > LaneAttackDamage(tower, creep, tower:GetAttackDamage()) then return nil end

    local deadline, release = J.GetAttackProDelayTime(tower, creep, true)
    if release <= 0 then deadline = math.huge end
    for _, shot in ipairs(creep:GetIncomingTrackingProjectiles()) do
        if shot.is_attack and shot.caster == tower then
            deadline = math.min(deadline, GetUnitToLocationDistance(creep, shot.location)
                / math.max(1, tower:GetAttackProjectileSpeed()))
        end
    end
    if deadline == math.huge then return nil end
    local first, _, wait = J.GetAttackProDelayTime(bot, creep)
    local second, _, partnerWait = J.GetAttackProDelayTime(partner, creep)
    if wait <= 0.20 and partnerWait <= 0.20 and math.max(first, second) + 0.05 < deadline then return creep end
end

-- Optional lane spells contend for the same time as the next farm order.
-- Kill, peel, heal and recovery decisions use their own urgency checks.
function J.CanSpendLaneTradeTime(bot, tower, enemies, seconds)
    if J.HasPendingLaningLastHit(bot) then return false end
    local reach = math.min(1600, bot:GetAttackRange() + (J.IsCore(bot) and 425 or 120))
    local hit, approach, reserve, urgent = J.GetLaningLastHitTarget(bot,
        bot:GetNearbyLaneCreeps(reach, true), tower, J.GetLaningAttackDamage(bot), enemies, false, seconds + 0.12)
    if reserve or hit and (not approach or urgent) then return false end
    local valuable = {}
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(bot:GetAttackRange() + 50, false)) do
        if J.IsValid(creep) and (J.IsKeyWordUnit('_ranged', creep) or J.IsKeyWordUnit('_siege', creep)
            or J.IsKeyWordUnit('_flagbearer', creep)) then
            valuable[#valuable + 1] = creep
        end
    end
    if #valuable == 0 then return true end
    local deny, soon = J.GetLaningDenyTarget(bot, valuable, tower, enemies)
    return deny == nil and not soon
end

-- Use visible, usable inventory only. The values weight the next exchange,
-- with a discount for healing that takes time or is interrupted by damage.
local function GetLaneRecoveryBudget(unit)
    if not unit.CanBeSeen or not unit:CanBeSeen() then return 0, false end
    local breakable = unit:HasModifier('modifier_flask_healing') or unit:HasModifier('modifier_bottle_regeneration')
    local budget = unit:HasModifier('modifier_tango_heal') and 35 or 0
    for slot = 0, 5 do
        local item = unit:GetItemInSlot(slot)
        if item and not item:IsNull() and item:IsFullyCastable() then
            local name, charges = item:GetName(), item:GetCurrentCharges()
            if name == 'item_magic_stick' or name == 'item_magic_wand' then
                budget = budget + charges * item:GetSpecialValueInt('restore_per_charge')
            elseif name == 'item_faerie_fire' then
                budget = budget + 65
            elseif (name == 'item_tango' or name == 'item_tango_single') and charges > 0 then
                budget = budget + math.min(2, charges) * 40
            elseif (name == 'item_flask' or name == 'item_bottle') and charges > 0 then
                budget = budget + 45
            end
        end
    end
    return math.min(180, budget), breakable
end

local function LaneHarassSupplyScore(bot, enemy)
    local ours = GetLaneRecoveryBudget(bot)
    local theirs, breakable = GetLaneRecoveryBudget(enemy)
    return (ours - theirs) / 300 + (breakable and 0.9 or 0), breakable
end

function J.GetVisibleLaneClash(bot, tower)
    local allies = bot:GetNearbyLaneCreeps(1100, false)
    local clash, closest = nil, math.huge
    for _, enemy in ipairs(bot:GetNearbyLaneCreeps(1100, true)) do
        if J.IsValid(enemy) and (not tower or J.IsInRange(enemy, tower, 1100)) then
            local distance = GetUnitToUnitDistance(bot, enemy)
            if distance < closest then
                for _, ally in ipairs(allies) do
                    if J.IsValid(ally) and J.IsInRange(ally, enemy, 425) then
                        clash, closest = enemy:GetLocation(), distance
                        break
                    end
                end
            end
        end
    end
    return clash
end

-- A real clash near a living tower offers a short trade and a short way out.
function J.GetTowerCoveredLaneClash(bot)
    local lane = bot:GetAssignedLane()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or not J.IsInLaningPhase(bot) then return nil end
    local team = bot:GetTeam()
    local tower = GetTower(team, lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
    if not J.IsValidBuilding(tower) then
        tower = GetTower(team, lane == LANE_TOP and TOWER_TOP_2 or TOWER_BOT_2)
    end
    if not J.IsValidBuilding(tower) or not J.IsInRange(bot, tower, 1050) then return nil end
    return tower, J.GetVisibleLaneClash(bot, tower)
end

local function LaneTradeCreepHarm(bot, seconds, drawsCreeps, point)
    local harm = J.GetCreepAttackProjectileWillRealDamage(bot, seconds, true)
    local radius = point and 850 or 650
    point = point or bot:GetLocation()
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(radius, true)) do
        if J.IsValid(creep) then
            local range = J.IsKeyWordUnit('_ranged', creep) and 600 or 500
            if creep:GetAttackTarget() == bot or drawsCreeps and GetUnitToLocationDistance(creep, point) <= range then
                harm = harm + LaneAttackDamage(creep, bot, creep:GetAttackDamage())
            end
        end
    end
    return harm
end

function J.CanTradeAtLaneClash(bot, enemies, tower, clash, enemyTower, actionTime, drawsCreeps)
    if J.GetHP(bot) < 0.60 or J.IsRetreating(bot) or #enemies > 2
        or GetUnitToLocationDistance(bot, clash) > 720
        or J.IsValidBuilding(enemyTower) and J.IsInRange(bot, enemyTower, 900)
        or #J.GetLastSeenEnemiesNearLoc(clash, 900) > #enemies then return false end
    local partner = J.GetLanePartner(bot)
    if not tower and (not J.IsValidHero(partner) or not J.IsInRange(bot, partner, 780)
        or J.GetHP(partner) < 0.60 or J.IsRetreating(partner) or J.IsDisabled(partner)) then return false end
    if not tower and J.IsValidHero(partner) and J.IsCore(partner) and J.IsInRange(bot, partner, 850)
        and (J.GetHP(partner) < 0.55 or J.IsRetreating(partner)) then return false end
    local exitTime = tower and math.max(0, GetUnitToUnitDistance(bot, tower) - 500) / math.max(1, bot:GetCurrentMovementSpeed()) or 0.35
    local seconds = math.min(3.0, 0.8 + actionTime + exitTime)
    local harm = J.GetVisibleThreatAt(bot, enemies, bot:GetLocation(), seconds)
        + LaneTradeCreepHarm(bot, seconds, drawsCreeps)
    local recovery = GetLaneRecoveryBudget(bot)
    local reserve = recovery < 40 and J.GetHP(bot) < 0.76 and 0.26 or (tower and 0.35 or 0.29)
    return harm < bot:GetHealth() * reserve
end

function J.GetTowerLaneHarassTarget(bot, enemies, enemyTower, range, castPoint)
    if #enemies == 0 then return nil end
    local tower, clash = J.GetTowerCoveredLaneClash(bot)
    if not clash then return nil end
    local best, score = nil, -math.huge
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and J.CanBeAttacked(enemy) and not J.IsSuspiciousIllusion(enemy)
            and J.IsInRange(bot, enemy, range) and GetUnitToLocationDistance(enemy, clash) <= 650
            and (not J.IsValidBuilding(enemyTower) or not J.IsInRange(enemy, enemyTower, 900))
            and (castPoint or GetHeightLevel(bot:GetLocation()) >= GetHeightLevel(enemy:GetLocation())) then
            local target = enemy:GetAttackTarget()
            local distracted = J.IsValid(target) and target:IsCreep() and J.IsAttacking(enemy)
            local rangeAdvantage = GetUnitToUnitDistance(bot, enemy) > enemy:GetAttackRange() + 65
            local supplies, breakable = LaneHarassSupplyScore(bot, enemy)
            if castPoint or distracted or rangeAdvantage or breakable then
                local priority = (distracted and 1 or 0) + (rangeAdvantage and 0.5 or 0) - J.GetHP(enemy) + supplies
                -- Keep spending mana for a meaningful window. A free right
                -- click can still take HP or force the opponent to use an item.
                if castPoint and supplies < -0.30 and not distracted then priority = -math.huge end
                if priority > score then best, score = enemy, priority end
            end
        end
    end
    if not best then return nil end
    local actionTime = castPoint or select(2, J.GetAttackProDelayTime(bot, best))
    local occupiedTime = castPoint or math.max(actionTime, bot:GetSecondsPerAttack())
    if J.CanTradeAtLaneClash(bot, enemies, tower, clash, enemyTower, actionTime, not castPoint)
        and J.CanSpendLaneTradeTime(bot, enemyTower, enemies, occupiedTime) then return best, clash end
end

-- Ranged supports and ranged cores may take a free shot during an actual
-- clash. Leave movement with the farm planner and reassess after one attack.
function J.GetCoveredRangedLaneShot(bot, enemies, tower)
    local range, lane = bot:GetAttackRange(), bot:GetAssignedLane()
    if range < 350 or lane ~= LANE_TOP and lane ~= LANE_BOT or not J.IsInLaningPhase(bot)
        or #enemies == 0 or #enemies > 2 or J.GetHP(bot) < 0.68 or J.IsRetreating(bot)
        or bot:WasRecentlyDamagedByCreep(1.5) then return nil end
    local clash = J.GetVisibleLaneClash(bot)
    if not clash or GetUnitToLocationDistance(bot, clash) > 650
        or #J.GetLastSeenEnemiesNearLoc(clash, 900) > #enemies then return nil end
    local target = J.GetLaningHarassTarget(bot, enemies, tower, #bot:GetNearbyLaneCreeps(600, true))
    if not target or GetUnitToLocationDistance(target, clash) > 600
        or GetUnitToUnitDistance(bot, target) <= target:GetAttackRange() + 65 then return nil end
    local recovery = GetLaneRecoveryBudget(bot)
    local fraction = recovery < 40 and 0.18 or 0.25
    if J.GetVisibleThreatAt(bot, enemies, bot:GetLocation(), 1.4)
        + LaneTradeCreepHarm(bot, 1.4, true) >= bot:GetHealth() * fraction then return nil end
    if J.CanSpendLaneTradeTime(bot, tower, enemies, bot:GetSecondsPerAttack()) then return target, clash end
end

-- Drag nearby enemy melee creeps backwards with an attack order that never
-- reaches the enemy hero. The normal last-hit planner takes over afterwards.
function J.GetSideLaneCreepDrag(bot, enemies, tower)
    local lane, now = bot:GetAssignedLane(), DotaTime()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or now < 25 or now > 600
        or not J.IsInLaningPhase(bot) or bot:GetAttackRange() >= 280 or not J.IsCore(bot)
        or J.GetHP(bot) < 0.55 or J.IsRetreating(bot)
        or (bot.ohaCreepDragNext or 0) > now then return nil end
    local origin = bot:GetLocation()
    local towerId = lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1
    local homeTower = GetTower(bot:GetTeam(), towerId)
    if not J.IsValidBuilding(tower) then
        tower = GetTower(GetOpposingTeam(), towerId)
    end
    if J.IsValidBuilding(tower) and J.IsInRange(bot, tower, 1120) then return nil end
    local eligible = {}
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(500, true)) do
        if J.IsValid(creep) and string.find(creep:GetUnitName(), '_melee', 1, true)
            and creep:GetAttackTarget() ~= bot
            and not J.IsInRange(bot, creep, bot:GetAttackRange() + 50) then eligible[#eligible + 1] = creep end
    end
    if #eligible < 2 then return nil end

    local point = J.AdjustLocationWithOffsetTowardsFountain(origin, 330)
    if J.IsValidBuilding(homeTower) and J.IsInRange(bot, homeTower, 950)
        and GetUnitToLocationDistance(homeTower, point) <= 650 then return nil end
    if not IsLocationPassable(point) or #J.GetEnemiesNearLoc(point, 660) > 0
        or #J.GetLastSeenEnemiesNearLoc(point, 660) > 0 then return nil end
    local covered = false
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(650, false)) do
        if J.IsValid(creep) and GetUnitToLocationDistance(creep, point) <= 360 then covered = true; break end
    end
    if not covered then return nil end
    local exposed = not J.IsValidBuilding(homeTower) or not J.IsInRange(bot, homeTower, 1050)
    local delicate = J.GetHP(bot) < 0.62 or bot:WasRecentlyDamagedByAnyHero(2)
    if delicate and not exposed then return nil end
    local limit = bot:GetHealth() * (delicate and 0.14 or 0.28)
    if J.GetVisibleThreatAt(bot, enemies, origin, 0.8) >= limit
        or J.GetVisibleThreatAt(bot, enemies, point, 1.4) >= limit then return nil end
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy)
            and J.CanBeAttacked(enemy) and not enemy:IsInvulnerable()
            and not J.IsInRange(bot, enemy, math.max(480, bot:GetAttackRange() + 250))
            and J.IsInRange(bot, enemy, 1250) then return enemy, point, eligible end
    end
end

function J.ObserveSideLaneCreepDrag(bot)
    local drag = bot.ohaLaneDragSample
    if not drag then return end
    local following, now = 0, DotaTime()
    for _, before in ipairs(drag.creeps) do
        local creep = before.unit
        if J.IsValid(creep) and creep:GetAttackTarget() == bot
            and GetUnitToLocationDistance(creep, drag.point) + 70 <= before.distance then following = following + 1 end
    end
    if following == 0 and now < drag.expires then return end
    if J.Customize and J.Customize.TraceLaneDecisions then
        print(string.format('[OHA lane-drag] %.2f player=%d attempt=%.2f following=%d', now, bot:GetPlayerID(), drag.started, following))
    end
    bot.ohaLaneDragSample = nil
end

function J.RunSideLaneCreepDrag(bot, enemies, tower, noStart)
    local now = DotaTime()
    if bot.ohaCreepDrag then
        local point = bot.ohaCreepDrag
        bot.ohaCreepDrag = nil
        if bot.ohaCreepDragExpires and now <= bot.ohaCreepDragExpires
            and IsLocationPassable(point) and #J.GetEnemiesNearLoc(point, 660) == 0
            and #J.GetLastSeenEnemiesNearLoc(point, 660) == 0 then
            bot:Action_MoveToLocation(point)
        else
            bot:Action_ClearActions(true)
        end
        return true
    end
    if noStart then return false end
    local enemy, point, creeps = J.GetSideLaneCreepDrag(bot, enemies, tower)
    if not enemy then return false end
    bot.ohaCreepDrag, bot.ohaCreepDragExpires, bot.ohaCreepDragNext = point, now + 0.35, now + 5
    local sample = {point=point, started=now, expires=now + 1.8, creeps={}}
    for _, creep in ipairs(creeps) do
        sample.creeps[#sample.creeps + 1] = {unit=creep, distance=GetUnitToLocationDistance(creep, point)}
    end
    bot.ohaLaneDragSample = sample
    bot:Action_AttackUnit(enemy, true)
    return true
end

function J.GetLaningDenyTarget(bot, creeps, tower, enemies)
    if #creeps == 0 then return nil, false end
    local range = bot:GetAttackRange()
    local damage = bot:GetAttackDamage()
    -- Account for an allied deny windup as well as the existing projectile pass.
    local attackers = GetLaneAttackers(bot, tower, enemies or {}, bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE))
    local best, score, reserve, urgent = nil, -math.huge, false, false
    for _, creep in ipairs(creeps) do
        if J.IsValid(creep) and J.CanBeAttacked(creep) and J.IsInRange(bot, creep, range) and J.GetHP(creep) < 0.5 then
            local delay, _, wait = J.GetAttackProDelayTime(bot, creep)
            local remaining = GetLaneCreepHealthAt(creep, delay, attackers)
            local actual = LaneAttackDamage(bot, creep, damage)
            local priority = J.IsKeyWordUnit('_flagbearer', creep) and 1.5
                or (J.IsKeyWordUnit('ranged', creep) or J.IsKeyWordUnit('siege', creep)) and 1 or 0
            local candidate = priority - remaining / math.max(1, actual)
            if remaining > 0 and remaining <= actual then
                if (wait or 0) <= 0.17 then
                    local dying = GetLaneCreepHealthAt(creep, delay + 0.18, attackers) <= 0
                    if dying then candidate = candidate + 2 end
                    if candidate > score then best, score, urgent = creep, candidate, dying or priority > 0 end
                elseif wait <= 0.48 then
                    reserve = true
                end
            elseif not reserve and remaining > actual and remaining <= actual * 2 then
                reserve = CanReserveLaneCreepShot(creep, actual, delay,
                    delay + math.min(0.50, bot:GetSecondsPerAttack() * 0.45), attackers)
            end
        end
    end
    return best, reserve, urgent
end

function J.GetLaningDenyStep(bot, creeps, enemyTower, enemies)
    local lane, range = bot:GetAssignedLane(), bot:GetAttackRange()
    local core = J.IsCore(bot)
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or (core and range >= 310)
        or (not core and range < 400) or not J.IsInLaningPhase(bot)
        or J.GetHP(bot) < 0.60 or J.IsRetreating(bot) or bot:IsRooted() or bot:IsDisarmed() then return nil end
    local tower = GetTower(bot:GetTeam(), lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
    if not J.IsValidBuilding(tower) then return nil end
    local origin, retreatDistance = bot:GetLocation(), GetUnitToUnitDistance(bot, tower)
    local attackers
    for _, creep in ipairs(creeps) do
        if J.IsValid(creep) and J.CanBeAttacked(creep) and J.GetHP(creep) < 0.5 then
            local gap = GetUnitToUnitDistance(bot, creep) - range
            if gap > 0 and gap <= (core and 160 or 210) then
                local valuable = J.IsKeyWordUnit('_ranged', creep) or J.IsKeyWordUnit('_siege', creep)
                    or J.IsKeyWordUnit('_flagbearer', creep)
                local contested = false
                for _, enemy in ipairs(enemies) do
                    if J.IsValidHero(enemy) and enemy:GetAttackTarget() == creep and J.IsAttacking(enemy) then
                        contested = true
                        break
                    end
                end
                local point = J.VectorTowards(origin, creep:GetLocation(), gap + 20)
                local nearTower = GetUnitToLocationDistance(tower, point)
                local partner = not core and J.GetLanePartner(bot)
                local supportCovered = not core and valuable and (nearTower <= 1150
                    or J.IsValidHero(partner) and J.GetHP(partner) >= 0.62 and not J.IsRetreating(partner)
                        and GetUnitToLocationDistance(partner, point) <= 650)
                if (core and (contested and nearTower <= 1150 or valuable and nearTower <= retreatDistance + 25)
                    or supportCovered)
                    and IsLocationPassable(point) and IsLocationVisible(point)
                    and (not J.IsValidBuilding(enemyTower) or GetUnitToLocationDistance(enemyTower, point) > 900)
                    and #J.GetLastSeenEnemiesNearLoc(point, 700) <= #enemies then
                    attackers = attackers or GetLaneAttackers(bot, enemyTower, enemies,
                        bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE))
                    local impact, release = J.GetAttackProDelayTime(bot, creep)
                    local health = GetLaneCreepHealthAt(creep, impact, attackers)
                    local damage = LaneAttackDamage(bot, creep, bot:GetAttackDamage())
                    -- The move and deny use the next swing. Keep it available for our own next last hit.
                    local occupied = math.max(release, gap / math.max(1, bot:GetCurrentMovementSpeed()) + bot:GetSecondsPerAttack())
                    if health > 0 and health <= damage
                        and J.GetVisibleThreatAt(bot, enemies, point, release + 0.7) < bot:GetHealth() * 0.20
                        and J.CanSpendLaneTradeTime(bot, enemyTower, enemies, occupied) then
                        return point, creep
                    end
                end
            end
        end
    end
end

local function IsContestForLaneCreep(bot, enemy, enemies)
    local target = enemy:GetAttackTarget()
    if not J.IsValid(target) or not target:IsCreep() or not J.IsAttacking(enemy)
        or not (J.IsKeyWordUnit('npc_dota_creep_', target) or J.IsKeyWordUnit('_siege', target))
        or not J.IsInRange(enemy, target, enemy:GetAttackRange() + 40) then return false end
	local impact, release = J.GetAttackProDelayTime(enemy, target, true)
    if release <= 0 then return false end -- a projectile already in flight cannot be interrupted
    local denying = target:GetTeam() == enemy:GetTeam()
    if denying and J.GetHP(target) >= 0.5 then return false end
    local targetsOurCreep = target:GetTeam() == bot:GetTeam()
    local tower = bot:GetNearbyTowers(1600, targetsOurCreep)[1]
    local allies = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
    local hp = GetLaneCreepHealthAt(target, impact, GetLaneAttackers(bot, tower, enemies, allies), enemy)
    if hp > 0 and hp <= LaneAttackDamage(enemy, target, enemy:GetAttackDamage()) then return release end
    return false
end

-- Keep both lane partners in range of the wave. A health advantage is useful
-- only if it can be spent without standing in the opposing pair's damage.
function J.GetSideLaneDuoTrade(bot, enemies, tower, range, castPoint, spellStep, linkedOnly)
    local lane = bot:GetAssignedLane()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or #enemies == 0 or not J.IsInLaningPhase(bot)
        or J.GetHP(bot) < 0.64 or J.IsRetreating(bot) or J.IsDisabled(bot)
        or (not castPoint and (bot:IsDisarmed() or bot:WasRecentlyDamagedByCreep(1.5))) then return nil end
    local partner = J.GetLanePartner(bot)
    if not J.IsValidHero(partner) or not J.IsInRange(bot, partner, 700) or J.GetHP(partner) < 0.64
        or J.IsRetreating(partner) or J.IsDisabled(partner)
        or partner:HasModifier('modifier_teleporting') then return nil end
    local partnerChannel = partner:IsChanneling()

    if not J.IsValidBuilding(tower) then
        local team = GetOpposingTeam()
        tower = GetTower(team, lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
        if not J.IsValidBuilding(tower) then tower = GetTower(team, lane == LANE_TOP and TOWER_TOP_2 or TOWER_BOT_2) end
    end
    if J.IsLaningUnderPressure(bot, enemies, tower) then return nil end
    local clash = J.GetVisibleLaneClash(bot)
    if not clash or GetUnitToLocationDistance(bot, clash) > 700 then return nil end

    local function WaveCount(creeps)
        local count = 0
        for _, creep in ipairs(creeps) do
            if J.IsValid(creep) and GetUnitToLocationDistance(creep, clash) <= 500 then count = count + 1 end
        end
        return count
    end
    local friends = WaveCount(bot:GetNearbyLaneCreeps(1200, false))
    if friends < math.max(2, WaveCount(bot:GetNearbyLaneCreeps(1200, true)) - 1) then return nil end

    local origin, best, bestPoint, bestScore = bot:GetLocation(), nil, nil, -math.huge
    local maxStep = castPoint and (spellStep or 0) or 215
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and J.CanBeAttacked(enemy)
            and (not linkedOnly or enemy:HasModifier('modifier_warlock_fatal_bonds'))
            and GetUnitToLocationDistance(enemy, clash) <= 585
            and (partnerChannel and partner.ohaFightControlTarget == enemy
                or not partnerChannel and (J.CanFollowLaneFight(partner, enemy) or castPoint and J.IsInRange(partner, enemy, 850)))
            and (not J.IsValidBuilding(tower) or not J.IsInRange(enemy, tower, 900)) then
            local gap = GetUnitToUnitDistance(bot, enemy) - range
            local _, release = J.GetAttackProDelayTime(bot, enemy)
            local controlled = not castPoint and J.GetFightHardControlRemaining(enemy) > (release or 0.5) + 0.20
            local linked = enemy:HasModifier('modifier_warlock_fatal_bonds')
            local nearby = 0
            for _, foe in ipairs(enemies) do
                if J.IsValidHero(foe) and not J.IsSuspiciousIllusion(foe) and J.IsInRange(enemy, foe, 950) then
                    nearby = nearby + 1
                end
            end
            if (not partnerChannel or controlled) and nearby <= ((linked or controlled) and 2 or 1) and gap <= maxStep then
                local step = gap > 0 and J.VectorTowards(origin, enemy:GetLocation(), gap + 20) or nil
                local point = step or origin
                local mid = step and J.VectorTowards(origin, point, (gap + 20) * 0.5) or origin
                if (not step or not bot:IsRooted() and IsLocationPassable(point) and IsLocationVisible(point)
                    and IsLocationPassable(mid) and IsLocationVisible(mid))
                    and GetHeightLevel(point) >= GetHeightLevel(enemy:GetLocation())
                    and J.GetLocationToLocationDistance(point, clash) <= 625
                    and (not J.IsValidBuilding(tower) or GetUnitToLocationDistance(tower, point) > 900
                        and GetUnitToLocationDistance(tower, mid) > 900)
                    and #J.GetLastSeenEnemiesNearLoc(point, 950) <= nearby then
                    local walk = math.max(0, gap + 20) / math.max(1, bot:GetCurrentMovementSpeed())
                    local seconds = (castPoint or bot:GetSecondsPerAttack()) + (step and walk or 0)
                    local exposure = math.min(2.2, seconds + 0.5)
                    local harm = J.GetVisibleThreatAt(bot, enemies, point, exposure)
                        + LaneTradeCreepHarm(bot, exposure, not castPoint, point)
                    local limit = GetLaneRecoveryBudget(bot) < 40 and 0.23 or 0.30
                    local score = (linked and 1 or 0) + (controlled and 1 or 0) - J.GetHP(enemy)
                    if harm < bot:GetHealth() * limit and score > bestScore
                        and J.CanSpendLaneTradeTime(bot, tower, enemies, seconds) then
                        best, bestPoint, bestScore = enemy, step, score
                    end
                end
            end
        end
    end
    return best, bestPoint, clash
end

function J.GetSideLaneSpellTradeTarget(bot, enemies, tower, range, disableCastPoint, projectileSpeed, tradeCastPoint)
    local lane = bot:GetAssignedLane()
    if lane ~= LANE_TOP and lane ~= LANE_BOT or not J.IsInLaningPhase(bot)
        or J.GetHP(bot) < 0.65 or J.IsRetreating(bot) or #enemies > 2
        or J.IsLaningUnderPressure(bot, enemies, tower) then return nil end
    if tradeCastPoint then
        local duoTarget = J.GetSideLaneDuoTrade(bot, enemies, tower, range, tradeCastPoint)
        if duoTarget then return duoTarget end
    end
    local nearTower, clash = J.GetTowerCoveredLaneClash(bot)
    if nearTower and tradeCastPoint then
        if clash then return J.GetTowerLaneHarassTarget(bot, enemies, tower, range, tradeCastPoint) end
        return nil
    end
    if nearTower and disableCastPoint and (not clash or not J.CanTradeAtLaneClash(
        bot, enemies, nearTower, clash, tower, disableCastPoint, false)) then return nil end
    if not J.IsValidBuilding(tower) then
        local enemyTeam = GetOpposingTeam()
        tower = GetTower(enemyTeam, lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
        if not J.IsValidBuilding(tower) then tower = GetTower(enemyTeam, lane == LANE_TOP and TOWER_TOP_2 or TOWER_BOT_2) end
    end
    if J.IsValidBuilding(tower) and J.IsInRange(bot, tower, 900) then return nil end
    local friend = J.GetLanePartner(bot)
    if not J.IsValidHero(friend) or not J.IsInRange(bot, friend, 850) or J.GetHP(friend) < 0.60
        or J.IsRetreating(friend) then return nil end
    local wave = bot:GetNearbyLaneCreeps(750, false)
    if #wave < 2 or #wave + 1 < #bot:GetNearbyLaneCreeps(650, true)
        or bot:WasRecentlyDamagedByCreep(1.5) then return nil end
    local best, score = nil, -math.huge
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and J.CanBeAttacked(enemy)
            and not enemy:IsInvulnerable() and J.IsInRange(bot, enemy, range)
            and (not clash or GetUnitToLocationDistance(enemy, clash) <= 650)
            and (not J.IsValidBuilding(tower) or not J.IsInRange(enemy, tower, 900)) then
            local victim = enemy:GetAttackTarget()
            local hitsCore = (victim == bot and J.IsCore(bot) or victim == friend and J.IsCore(friend))
                and J.IsAttacking(enemy) and J.IsInRange(enemy, victim, enemy:GetAttackRange() + 40)
            local contest = IsContestForLaneCreep(bot, enemy, enemies)
            local worthwhile = hitsCore or contest
            if disableCastPoint then
                local flight = projectileSpeed and projectileSpeed > 0
                    and GetUnitToUnitDistance(bot, enemy) / projectileSpeed or 0
                worthwhile = contest and disableCastPoint + flight + 0.08 < contest and not J.IsDisabled(enemy)
            end
            if worthwhile then
                local valuable = contest and (J.IsKeyWordUnit('_ranged', victim)
                    or J.IsKeyWordUnit('_siege', victim) or J.IsKeyWordUnit('_flagbearer', victim))
                local priority = (hitsCore and 2 or 0) + (valuable and 1 or 0) - J.GetHP(enemy)
                    + LaneHarassSupplyScore(bot, enemy)
                if priority > score then best, score = enemy, priority end
            end
        end
    end
    if best and J.GetVisibleThreatAt(bot, enemies, bot:GetLocation(), 1.5) < bot:GetHealth() * 0.30 then return best end
end

function J.GetSideLaneCoverAttack(bot, enemies, tower)
    local lane = bot:GetAssignedLane()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or #enemies == 0 or J.IsCore(bot) or J.GetHP(bot) < 0.62
        or J.IsRetreating(bot) or J.IsLaningUnderPressure(bot, enemies, tower)
        or bot:WasRecentlyDamagedByCreep(1.5) or #enemies > 2 then return nil end
    local core = J.GetLanePartner(bot)
    if not J.IsValidHero(core) or not J.IsCore(core) or not J.IsInRange(bot, core, 750) then return nil end
    local opposingWave = #bot:GetNearbyLaneCreeps(650, true)
    if opposingWave >= 4 and #bot:GetNearbyLaneCreeps(750, false) < opposingWave - 1 then return nil end
    local target = J.GetLaningPeelTarget(bot, core, enemies, bot:GetAttackRange(), true)
    if target and J.CanBeAttacked(target) and not target:IsInvulnerable()
        and (not J.IsValidBuilding(tower) or not J.IsInRange(bot, tower, 850))
        and GetHeightLevel(bot:GetLocation()) >= GetHeightLevel(target:GetLocation()) then return target end
end

-- One safe shot at the enemy approaching the wave, before they start a last hit.
-- The nearby core can keep farming: don't require it to be in melee range.
local function HasCoveredSideLaneAngle(bot, core, enemy, enemies, wave)
    if J.GetHP(bot) < 0.80 or J.GetHP(core) < 0.72 or not J.IsInRange(bot, core, 550)
        or J.IsRetreating(core) or bot:WasRecentlyDamagedByAnyHero(2)
        or not enemy.IsFacingLocation then return false end
    for _, foe in ipairs(enemies) do
        if foe ~= enemy and J.IsValidHero(foe) and not J.IsSuspiciousIllusion(foe)
            and J.IsInRange(bot, foe, math.max(600, foe:GetAttackRange() + 175)) then return false end
    end
    for _, creep in ipairs(wave) do
        if J.IsValid(creep) and J.IsInRange(creep, enemy, 360)
            and J.IsInRange(bot, creep, 580) and enemy:IsFacingLocation(creep:GetLocation(), 45) then return true end
    end
    return false
end

local function HasLaneTradeSpace(enemy, enemies, point)
    for _, other in ipairs(enemies) do
        if other ~= enemy and J.IsValidHero(other) and not J.IsSuspiciousIllusion(other)
            and GetUnitToLocationDistance(other, point) <= math.max(600, other:GetAttackRange() + 175) then return false end
    end
    return true
end

local function LaneTradeAgainst(bot, enemy, enemies, tower, range, step)
    if not J.IsValidHero(enemy) or J.IsSuspiciousIllusion(enemy) or not J.CanBeAttacked(enemy)
        or enemy:IsInvulnerable() then return nil end
    local core = J.GetLanePartner(bot)
    if enemy:GetAttackRange() < 310 or #enemies > 1 then
        if not J.IsValidHero(core) or not J.IsCore(core) or J.IsRetreating(core)
            or not J.IsInRange(bot, core, 750) then return nil end
    end
    local distance = GetUnitToUnitDistance(bot, enemy)
    if (distance > range) ~= step or distance > range + 200 then return nil end
    local victim = enemy:GetAttackTarget()
    local origin, target = bot:GetLocation(), enemy:GetLocation()
    local point = step and J.VectorTowards(origin, target, distance - range + 20) or origin
    local outsideReach = GetUnitToLocationDistance(enemy, point) > enemy:GetAttackRange() + 65
    if (step and (not IsLocationPassable(point) or not IsLocationVisible(point)))
        or GetHeightLevel(point) < GetHeightLevel(target)
        or (J.IsValidBuilding(tower) and (J.IsInRange(enemy, tower, 900) or GetUnitToLocationDistance(tower, point) <= 900))
        or #J.GetLastSeenEnemiesNearLoc(target, 1000) > #enemies then return nil end
    if not HasLaneTradeSpace(enemy, enemies, point) then return nil end

    local busy = J.IsValid(victim) and J.IsAttacking(enemy) and J.IsInRange(victim, enemy, enemy:GetAttackRange() + 50)
        and J.IsInRange(bot, victim, 800)
    local contestedWindow = busy and (IsContestForLaneCreep(bot, enemy, enemies) or victim == core and J.IsCore(core))
        and outsideReach and (not step or enemy:IsFacingLocation(victim:GetLocation(), 60))
        and #bot:GetNearbyLaneCreeps(650, false) > 0
    if contestedWindow then
        if #enemies > 1 and J.GetVisibleThreatAt(bot, enemies, point, 1.5) >= bot:GetHealth() * 0.30 then return nil end
    else
        -- A safe shot on a real wave does not need an enemy last-hit windup.
        local clash = J.GetVisibleLaneClash(bot)
        if not J.IsValidHero(core) or not J.IsCore(core) or J.GetHP(core) < 0.60 or J.IsRetreating(core)
            or not clash or GetUnitToLocationDistance(core, point) > 720
            or GetUnitToLocationDistance(enemy, clash) > 590 or J.GetLocationToLocationDistance(point, clash) > 650
            or step and (not outsideReach or not enemy.IsFacingLocation or not enemy:IsFacingLocation(clash, 75)) then return nil end
        local sinceShot = GameTime() - enemy:GetLastAttackTime()
        local recovering = sinceShot >= 0 and sinceShot <= 0.45
        if not outsideReach and not recovering and not (busy and victim:IsCreep()) then return nil end
        local exposure = step and 1.5 or 1.25
        local damage = J.GetVisibleThreatAt(bot, enemies, point, exposure) + LaneTradeCreepHarm(bot, exposure, true, point)
        if damage >= bot:GetHealth() * 0.24 then return nil end
    end
    if step then
        local function countNearPoint(creeps)
            local count = 0
            for _, creep in ipairs(creeps) do
                if J.IsValid(creep) and GetUnitToLocationDistance(creep, point) <= 500 then count = count + 1 end
            end
            return count
        end
        if countNearPoint(bot:GetNearbyLaneCreeps(750, false)) < math.max(2, countNearPoint(bot:GetNearbyLaneCreeps(750, true))) then return nil end
    end
    return step and point or enemy
end

local function GetRangedLaneTrade(bot, enemies, tower, range, step)
    if #enemies > 2 or bot:GetAttackRange() < 400 or J.GetHP(bot) < 0.75 or bot:WasRecentlyDamagedByAnyHero(2)
        or bot:WasRecentlyDamagedByCreep(1.5) or J.IsRetreating(bot) then return nil end
    for _, enemy in ipairs(enemies) do
        local trade = LaneTradeAgainst(bot, enemy, enemies, tower, range, step)
        if trade then return trade end
    end
end

-- Reapply safe pressure to an injured melee target or contest a real last hit.
-- Do not chase or sacrifice the lane partner's last hits.
function J.GetSideLanePressureTarget(bot, enemies, tower, range)
    local lane = bot:GetAssignedLane()
    if #enemies == 0 or #enemies > 2 or (lane ~= LANE_TOP and lane ~= LANE_BOT)
        or J.IsCore(bot) or J.GetHP(bot) < 0.65 or J.IsRetreating(bot)
        or not J.IsInLaningPhase(bot) then return nil end
    local now = DotaTime()
    if now < 30 or now > 10 * 60 or GetGameMode() == GAMEMODE_1V1MID or GetGameMode() == GAMEMODE_MO
        or J.IsLaningUnderPressure(bot, enemies, tower) then return nil end

    if not J.IsValidBuilding(tower) then
        local enemyTeam = GetOpposingTeam()
        tower = GetTower(enemyTeam, lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
        if not J.IsValidBuilding(tower) then
            tower = GetTower(enemyTeam, lane == LANE_TOP and TOWER_TOP_2 or TOWER_BOT_2)
        end
    end
    local ally = J.GetLanePartner(bot)
    local allyCreeps = bot:GetNearbyLaneCreeps(1150, false)
    local enemyCreeps = bot:GetNearbyLaneCreeps(850, true)
    if #allyCreeps < math.max(2, #enemyCreeps - 1) or bot:WasRecentlyDamagedByCreep(1.5) then return nil end
    local evenWave = #allyCreeps >= #enemyCreeps
    local trade = evenWave and GetRangedLaneTrade(bot, enemies, tower, range, false)
    if trade then return trade end
    if not J.IsValidHero(ally) or not J.IsCore(ally) or not J.IsInRange(bot, ally, 850) then return nil end
    local best, score = nil, math.huge
    for _, enemy in ipairs(enemies) do
        local contest = J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy)
            and J.IsInRange(bot, enemy, range) and IsContestForLaneCreep(bot, enemy, enemies)
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and J.CanBeAttacked(enemy)
            and not enemy:IsInvulnerable() and enemy:GetAttackRange() < 310
            and J.IsInRange(bot, enemy, range)
            and HasLaneTradeSpace(enemy, enemies, bot:GetLocation())
            and (HasCoveredSideLaneAngle(bot, ally, enemy, enemies, allyCreeps)
                or evenWave and (J.GetHP(enemy) <= 0.72 or (J.GetHP(bot) >= 0.74 and J.GetHP(ally) >= 0.70
                    and contest)) and J.CanFollowLaneFight(ally, enemy))
            and (not J.IsValidBuilding(tower) or not (J.IsInRange(enemy, tower, 900) or J.IsInRange(bot, tower, 850)))
            and GetHeightLevel(bot:GetLocation()) >= GetHeightLevel(enemy:GetLocation()) then
            local onWave = false
            for _, creep in ipairs(allyCreeps) do
                if J.IsValid(creep) and J.IsInRange(creep, enemy, 375) then onWave = true; break end
            end
            if onWave and #J.GetEnemiesNearLoc(enemy:GetLocation(), 900) <= 2 then
                local priority = J.GetHP(enemy) - (contest and 1 or 0) - LaneHarassSupplyScore(bot, enemy)
                if priority < score then best, score = enemy, priority end
            end
        end
    end
    return best
end

-- Occupy a reachable angle on the wave, not the retreat path of a fleeing hero.
function J.GetSideLanePressureStep(bot, enemies, tower)
    local lane, now = bot:GetAssignedLane(), DotaTime()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or now < 30 or now > 600
        or #enemies == 0 or #enemies > 2 or J.IsCore(bot) or bot:GetAttackRange() < 400
        or J.GetHP(bot) < 0.72 or bot:WasRecentlyDamagedByAnyHero(2)
        or J.IsLaningUnderPressure(bot, enemies, tower) then return end
    local wave = bot:GetNearbyLaneCreeps(1150, false)
    if #wave < math.max(2, #bot:GetNearbyLaneCreeps(850, true)) then return end
    if not J.IsValidBuilding(tower) then
        local opponent = GetOpposingTeam()
        tower = GetTower(opponent, lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
        if not J.IsValidBuilding(tower) then tower = GetTower(opponent, lane == LANE_TOP and TOWER_TOP_2 or TOWER_BOT_2) end
    end
    local range = bot:GetAttackRange()
    local rangedStep = GetRangedLaneTrade(bot, enemies, tower, range, true)
    if rangedStep then return rangedStep end
    local core = J.GetLanePartner(bot)
    if not J.IsValidHero(core) or not J.IsCore(core) or J.GetHP(core) < 0.65
        or J.IsRetreating(core) or not J.IsInRange(bot, core, 700) then return end
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and J.CanBeAttacked(enemy) and not J.IsSuspiciousIllusion(enemy)
            and not enemy:IsInvulnerable() and enemy:GetAttackRange() < 310
            and not J.IsInRange(bot, enemy, range) and J.IsInRange(bot, enemy, range + 220)
            and (HasCoveredSideLaneAngle(bot, core, enemy, enemies, wave)
                or (J.GetHP(enemy) <= 0.72 or (J.GetHP(bot) >= 0.74 and J.GetHP(core) >= 0.70
                    and IsContestForLaneCreep(bot, enemy, enemies))) and J.CanFollowLaneFight(core, enemy))
            and (not J.IsValidBuilding(tower) or not J.IsInRange(enemy, tower, 1000)) then
            for _, creep in ipairs(wave) do
                if J.IsValid(creep) and J.IsInRange(creep, enemy, 375) then
                    local origin = bot:GetLocation()
                    local point = J.VectorTowards(origin, enemy:GetLocation(), GetUnitToUnitDistance(bot, enemy) - range + 25)
                    if IsLocationPassable(point) and GetHeightLevel(point) >= GetHeightLevel(enemy:GetLocation())
                        and GetUnitToLocationDistance(core, point) <= 720
                        and (not J.IsValidBuilding(tower) or GetUnitToLocationDistance(tower, point) > 1000)
                        and #J.GetLastSeenEnemiesNearLoc(point, 850) <= #enemies then
                        local safe = true
                        for _, foe in ipairs(enemies) do
                            if foe ~= enemy and J.IsValidHero(foe) and GetUnitToLocationDistance(foe, point)
                                <= math.max(500, foe:GetAttackRange() + 160) then safe = false; break end
                        end
                        if safe then return point end
                    end
                end
            end
        end
    end
end

-- Take a clean finishing hit between last-hit windows, never a chase.
function J.GetSideLaneFinishTarget(bot, enemies, tower)
    local lane = bot:GetAssignedLane()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or #enemies == 0 or #enemies > 2
        or not J.IsInLaningPhase(bot) or J.GetHP(bot) < 0.65 or J.IsRetreating(bot)
        or bot:WasRecentlyDamagedByCreep(1.5) or J.IsLaningUnderPressure(bot, enemies, tower) then return nil end
    if not J.IsValidBuilding(tower) then
        tower = GetTower(GetOpposingTeam(), lane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
    end
    if J.IsValidBuilding(tower) and J.IsInRange(bot, tower, 900) then return nil end
    local hostile = #bot:GetNearbyLaneCreeps(650, true)
    if hostile >= 4 and #bot:GetNearbyLaneCreeps(750, false) < hostile - 1 then return nil end
    local best, lowest = nil, math.huge
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and J.CanBeAttacked(enemy)
            and J.IsInRange(bot, enemy, bot:GetAttackRange())
            and not J.CannotBeKilled(bot, enemy) and not enemy:HasModifier('modifier_item_blade_mail_reflect')
            and not enemy:HasModifier('modifier_templar_assassin_refraction_absorb')
            and not enemy:HasModifier('modifier_medusa_mana_shield')
            and not (GetHeightLevel(bot:GetLocation()) < GetHeightLevel(enemy:GetLocation()))
            and enemy:GetHealth() < lowest and J.CanKillTarget(enemy, bot:GetAttackDamage() * 0.85, DAMAGE_TYPE_PHYSICAL) then
            best, lowest = enemy, enemy:GetHealth()
        end
    end
    return best
end

function J.GetLaningHarassTarget(bot, enemies, tower, enemyCreepCount)
    local range = bot:GetAttackRange()
    local core = J.IsCore(bot)
    local lane = bot:GetAssignedLane()
    local rangedMid = lane == LANE_MID and range >= 400
    local side = lane == LANE_TOP or lane == LANE_BOT
    local hp = J.GetHP(bot)
    if hp < 0.6 or (J.IsValidBuilding(tower) and J.IsInRange(bot, tower, 850))
        or (enemyCreepCount >= 2 and bot:WasRecentlyDamagedByCreep(1.5)) then return nil end

    local location = bot:GetLocation()
    local allies = J.GetAlliesNearLoc(location, 900)
    local alliedHeroes = math.max(1, #allies)
    local alliedCreeps = #bot:GetNearbyLaneCreeps(700, false)
    local nearbyEnemies = 0
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and J.IsInRange(bot, enemy, 900) then
            nearbyEnemies = nearbyEnemies + 1
        end
    end
    if nearbyEnemies > alliedHeroes then return nil end
    if side and nearbyEnemies > 1 and J.GetVisibleThreatAt(bot, enemies, location, 1.5) >= bot:GetHealth() * 0.30 then return nil end

    local best, bestScore = nil, -math.huge
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and J.CanBeAttacked(enemy)
            and J.IsInRange(bot, enemy, range) then
            local enemyTarget = enemy:GetAttackTarget()
            local onCreep = J.IsValid(enemyTarget) and enemyTarget:IsCreep()
                and (J.IsAttacking(enemy) or GameTime() - enemy:GetLastAttackTime() < 0.25)
            local distance = GetUnitToUnitDistance(bot, enemy)
            local reachAdvantage = distance > enemy:GetAttackRange() + 65
            local terrain = GetHeightLevel(location) - GetHeightLevel(enemy:GetLocation())
            local uphill = range >= 400 and terrain < 0
            local covered = alliedCreeps >= math.max(2, enemyCreepCount - 1)
            local strongWave = enemyCreepCount >= 4 and not covered
            local contest = side and onCreep and IsContestForLaneCreep(bot, enemy, enemies)
            local freeTrade = (contest or not side and onCreep) and (covered or enemyCreepCount <= 2)
            local sinceEnemyShot = GameTime() - enemy:GetLastAttackTime()
            local enemyRecovering = rangedMid and covered and sinceEnemyShot >= 0 and sinceEnemyShot < 0.35
                and ((enemyTarget ~= bot and not bot:WasRecentlyDamagedByAnyHero(1)) or hp >= 0.72)
            if not uphill and (not strongWave or (reachAdvantage and distance > 500 and enemyCreepCount <= 4))
                and (not side or core or freeTrade or reachAdvantage and covered)
                and (not core or (rangedMid and (freeTrade or enemyRecovering or reachAdvantage or terrain > 0 or enemyCreepCount <= 1))
                    or (hp >= 0.7 and freeTrade)) then
                local peel = 0
                if not core then
                    for _, ally in ipairs(allies) do
                        if ally ~= bot and J.IsCore(ally) and enemyTarget == ally then
                            peel = 3 + (1 - J.GetHP(ally))
                            break
                        end
                    end
                end
                local score = peel + ((freeTrade or not side and onCreep) and 2 or 0)
                    + (reachAdvantage and 1 or 0) - J.GetHP(enemy)
                    + (side and LaneHarassSupplyScore(bot, enemy) or 0)
                if score > bestScore then best, bestScore = enemy, score end
            end
        end
    end
    return best
end

function J.GetLaningCreepPosition(bot, lane, creeps, tower, enemies, approachingLastHit)
    local range = bot:GetAttackRange()
    local core = J.IsCore(bot)
    local melee = range < 310
    local hp = J.GetHP(bot)
    local sideRanged = not melee and (lane == LANE_TOP or lane == LANE_BOT)
    if not core and not sideRanged then return nil end
    if melee then
        -- Stand close enough to wind up while the creep is still losing health.
        if hp < 0.52 then return nil end
    elseif hp < 0.65 or (lane ~= LANE_MID and not approachingLastHit and not sideRanged) then
        return nil
    end

    local closest, distance = nil, math.huge
    for _, creep in ipairs(creeps) do
        if J.IsValid(creep) and J.CanBeAttacked(creep) then
            local d = GetUnitToUnitDistance(bot, creep)
            if d < distance then closest, distance = creep, d end
        end
    end
    if closest == nil then return nil end
    if sideRanged and not approachingLastHit then
        local partner = J.GetLanePartner(bot)
        if distance > range + 250 or bot:WasRecentlyDamagedByAnyHero(2)
            or bot:WasRecentlyDamagedByCreep(1)
            or J.IsValidBuilding(tower) and GetUnitToLocationDistance(tower, bot:GetLocation()) <= 850
            or #bot:GetNearbyLaneCreeps(750, false) < 2
            or not J.IsValidHero(partner) or not J.IsInRange(bot, partner, 800)
            or J.IsRetreating(partner) or J.GetHP(partner) < 0.50 then return nil end
    end
    if melee then
        if distance > 1200 then return nil end
        if distance > range + 550 then
            if hp < 0.65 or bot:WasRecentlyDamagedByAnyHero(3)
                or #J.GetLastSeenEnemiesNearLoc(closest:GetLocation(), 1050) > 0 then return nil end
            local screen = 0
            for _, allyCreep in ipairs(bot:GetNearbyLaneCreeps(1600, false)) do
                if J.IsValid(allyCreep) and J.IsInRange(allyCreep, closest, 550) then screen = screen + 1 end
            end
            if screen < 2 then return nil end
        elseif #bot:GetNearbyLaneCreeps(750, false) == 0 then return nil end
    end
    local inRange = distance <= range - (melee and 12 or 55)
    if inRange and (not melee or lane == LANE_MID) then return bot:GetLocation() end
    local rear = GetLaneFrontLocation(GetTeam(), lane, -1450)
    if not inRange and GetUnitToLocationDistance(closest, rear) < range then
        if IsLocationPassable(rear) and not (J.IsValidBuilding(tower) and GetUnitToLocationDistance(tower, rear) <= 850)
            and #J.GetEnemiesNearLoc(rear, 800) == 0
            and #J.GetLastSeenEnemiesNearLoc(rear, 850) == 0 then return rear end
        return nil
    end
    local hold = inRange and bot:GetLocation()
        or J.GetLocationTowardDistanceLocation(closest, rear, math.max(50, range - (melee and 35 or 105)))
    if not IsLocationPassable(hold) or (J.IsValidBuilding(tower) and GetUnitToLocationDistance(tower, hold) <= 850) then
        return nil
    end
    local travel = GetUnitToLocationDistance(bot, hold)
    if travel > 160 and #J.GetLastSeenEnemiesNearLoc(hold, 750) > 0 then return nil end
    local threats, safeOffset = 0, 0
    for _, enemy in ipairs(enemies) do
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy)
            and GetUnitToLocationDistance(enemy, hold) < math.max(450, enemy:GetAttackRange() + 100) then
            threats = threats + 1
            safeOffset = math.max(safeOffset, enemy:GetAttackRange() + 240)
        end
    end
    if threats >= 2 or (threats == 1 and (bot:WasRecentlyDamagedByAnyHero(2) or hp < 0.65)) then
        if not melee or approachingLastHit then return nil end
        local safe = J.GetLocationTowardDistanceLocation(closest, rear, math.max(650, safeOffset))
        if not IsLocationPassable(safe) or (J.IsValidBuilding(tower) and GetUnitToLocationDistance(tower, safe) <= 850) then return nil end
        for _, enemy in ipairs(enemies) do
            if J.IsValidHero(enemy) and GetUnitToLocationDistance(enemy, safe) <= math.max(500, enemy:GetAttackRange() + 140) then return nil end
        end
        return safe
    end
    return hold
end

function J.CanSupportTakeLaneLastHit(bot, creep)
    if J.IsCore(bot) or not J.IsInLaningPhase() or creep:GetTeam() == bot:GetTeam() then return true end

    local name = creep:GetUnitName()
    if not string.find(name, "npc_dota_creep_", 1, true) and not string.find(name, "_siege", 1, true)
    then return true end

    local allies = J.GetAlliesNearLoc(creep:GetLocation(), 1200)
    local attackers
    local function laneAttackers()
        attackers = attackers or GetLaneAttackers(bot, bot:GetNearbyTowers(1600, false)[1],
            bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE), allies)
        return attackers
    end
    -- An attack already released retains ownership, even if the core now backs off.
    for _, shot in ipairs(creep:GetIncomingTrackingProjectiles()) do
        local ally = shot.caster
        if shot.is_attack and ally ~= nil and ally ~= bot and J.IsValidHero(ally)
            and ally:GetTeam() == bot:GetTeam() and J.IsCore(ally) then
            local impact = GetUnitToLocationDistance(creep, shot.location) / math.max(1, ally:GetAttackProjectileSpeed())
            local damage = LaneAttackDamage(ally, creep, J.GetLaningAttackDamage(ally))
            local health = GetLaneCreepHealthAt(creep, impact, laneAttackers(), ally)
            if health > 0 and health <= damage then return false end
        end
    end
    for _, ally in ipairs(allies) do
        if ally ~= bot and J.IsValidHero(ally) and J.IsCore(ally)
            and not ally:IsDisarmed() and not J.IsDisabled(ally) and not J.IsRetreating(ally)
            and not ally:HasModifier('modifier_teleporting')
            and not (ally.IsChanneling and ally:IsChanneling())
            and not (ally.IsCastingAbility and ally:IsCastingAbility() and ally:GetAttackTarget() ~= creep)
            and J.IsInRange(ally, creep, ally:GetAttackRange() + 500)
        then
            local displacement = (ally.ohaCarryLaneRecoveryUntil or 0) > DotaTime()
                and not J.IsInRange(ally, creep, ally:GetAttackRange() + 230)
            -- Count approach time only when the core has already targeted this creep.
            local canTake = J.IsInRange(ally, creep, ally:GetAttackRange()) or ally:GetAttackTarget() == creep
            if canTake and not displacement and not (J.GetHP(ally) < 0.48 and ally:WasRecentlyDamagedByAnyHero(4)) then
                laneAttackers()
                local delay = J.GetAttackProDelayTime(ally, creep)
                local damage = LaneAttackDamage(ally, creep, J.GetLaningAttackDamage(ally))
                local health = GetLaneCreepHealthAt(creep, delay, attackers, ally)
                if (health > 0 and health <= damage) or (health > damage
                    and CanReserveLaneCreepShot(creep, damage, delay, delay + math.min(1.3, ally:GetSecondsPerAttack()), attackers, ally)) then
                    return false
                end
            end
        end
    end

    return true
end

function J.CanSecureLaneCreepWithSpell(bot, creep, damage, damageType, impact, enemies)
    if not J.CanSupportTakeLaneLastHit(bot, creep) then return false end
    local attackers = GetLaneAttackers(bot, bot:GetNearbyTowers(1600, false)[1], enemies,
        bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE))
    local remaining = GetLaneCreepHealthAt(creep, impact, attackers)
    return remaining > 0 and remaining <= creep:GetActualIncomingDamage(damage, damageType)
end

function J.GetSameUnitType(hUnit, nRadius, sUnitName, bAttacking)
    local tAttackingUnits = {}
    local unitList = GetUnitList(UNIT_LIST_ALL)
    for _, unit in pairs(unitList) do
        if J.IsValid(unit)
        and unit:GetUnitName() == sUnitName
        and GetUnitToUnitDistance(unit, hUnit) <= nRadius
        then
			if bAttacking then
				if (unit:GetAttackTarget() == hUnit or J.IsChasingTarget(unit, hUnit)) then
					table.insert(tAttackingUnits, unit)
				end
			else
				table.insert(tAttackingUnits, unit)
			end
        end
    end

    return tAttackingUnits
end
function J.GetUnitListTotalAttackDamage(bot, tUnits, fTimeInterval)
    local dmg = 0
	for _, unit in pairs(tUnits) do
		if J.IsValid(unit) then
            local nAttackDamage = unit:GetAttackDamage()
			local sUnitName = unit:GetUnitName()

            if J.IsSuspiciousIllusion(unit) then
                if string.find(sUnitName, 'phantom_lancer') then
                    nAttackDamage = nAttackDamage * 0.19
                elseif string.find(sUnitName, 'naga_siren') then
                    nAttackDamage = nAttackDamage * 0.4
                elseif string.find(sUnitName, 'chaos_knight') then
                    -- full
                elseif string.find(sUnitName, 'terrorblade') then
                    if J.IsUnitNearby(bot, tUnits, 1200, sUnitName, true) then
                        nAttackDamage = nAttackDamage * (0.6 + 0.25)
                    else
                        nAttackDamage = nAttackDamage * (0.6 - 0.50)
                    end
                elseif unit:HasModifier('modifier_darkseer_wallofreplica_illusion') then
                    nAttackDamage = nAttackDamage * 0.9
                elseif unit:HasModifier('modifier_grimstroke_scepter_buff') then
                    nAttackDamage = nAttackDamage * 1.5
                else
					if unit:GetAttackRange() > 300 then
						nAttackDamage = nAttackDamage * 0.28
					else
						nAttackDamage = nAttackDamage * 0.33
					end
                end
            end

            dmg = dmg + nAttackDamage * unit:GetAttackSpeed() * fTimeInterval
		end
	end

	return dmg
end
function J.IsTargetedByEnemyWithModifier(tUnits, sModifierName)
    for _, enemyHero in pairs(tUnits) do
        if J.IsValidHero(enemyHero)
        and enemyHero:HasModifier(sModifierName)
        and (enemyHero:GetAttackTarget() == bot or J.IsChasingTarget(enemyHero, bot))
        then
            return true
        end
    end

    return false
end

function J.ShouldEscape( bot )

	local tableNearbyAttackAllies = J.GetNearbyHeroes(bot, 800, false, BOT_MODE_ATTACK )

	if #tableNearbyAttackAllies > 0 and J.GetHP( bot ) > 0.16 then return false end

	local tableNearbyEnemyHeroes = J.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE )
	if bot:WasRecentlyDamagedByAnyHero( 2.0 )
		or bot:WasRecentlyDamagedByTower( 2.0 )
		or #tableNearbyEnemyHeroes >= 2
	then
		return true
	end
end

function J.GetClosestTeamLane(unit)
	local v_top_lane = GetLocationAlongLane(LANE_TOP, GetLaneFrontAmount(GetTeam(), LANE_TOP, false))
	local v_mid_lane = GetLocationAlongLane(LANE_MID, GetLaneFrontAmount(GetTeam(), LANE_MID, false))
	local v_bot_lane = GetLocationAlongLane(LANE_BOT, GetLaneFrontAmount(GetTeam(), LANE_BOT, false))

	local dist_from_top = GetUnitToLocationDistance(unit, v_top_lane)
	local dist_from_mid = GetUnitToLocationDistance(unit, v_mid_lane)
	local dist_from_bot = GetUnitToLocationDistance(unit, v_bot_lane)

	if dist_from_top < dist_from_mid and dist_from_top < dist_from_bot
	then
		return v_top_lane
	elseif dist_from_mid < dist_from_top and dist_from_mid < dist_from_bot
	then
		return v_mid_lane
	elseif dist_from_bot < dist_from_top and dist_from_bot < dist_from_mid
	then
		return v_bot_lane
	end

	return v_mid_lane
end

function J.GetFirstBotInTeam()
	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local ally = GetTeamMember(i)
		if ally ~= nil
		and ally:IsBot()
		then
			return ally
		end
	end
end

local SpecialUnits = {
	['npc_dota_clinkz_skeleton_archer'] = 0.75,
	['npc_dota_juggernaut_healing_ward'] = 0.9,
	['npc_dota_invoker_forged_spirit'] = 0.9,
	['npc_dota_grimstroke_ink_creature'] = 1,
	['npc_dota_ignis_fatuus'] = 1,
	['npc_dota_lone_druid_bear1'] = 0.9,
	['npc_dota_lone_druid_bear2'] = 0.9,
	['npc_dota_lone_druid_bear3'] = 0.9,
	['npc_dota_lone_druid_bear4'] = 0.9,
	['npc_dota_lycan_wolf_1'] = 0.75,
	['npc_dota_lycan_wolf_2'] = 0.75,
	['npc_dota_lycan_wolf_3'] = 0.75,
	['npc_dota_lycan_wolf_4'] = 0.75,
	['npc_dota_observer_wards'] = 1,
	['npc_dota_phoenix_sun'] = 1,
	['npc_dota_venomancer_plague_ward_1'] = 0.75,
	['npc_dota_venomancer_plague_ward_2'] = 0.75,
	['npc_dota_venomancer_plague_ward_3'] = 0.75,
	['npc_dota_venomancer_plague_ward_4'] = 0.75,
	['npc_dota_rattletrap_cog'] = 0.9,
	['npc_dota_sentry_wards'] = 1,
	['npc_dota_unit_tombstone1'] = 1,
	['npc_dota_unit_tombstone2'] = 1,
	['npc_dota_unit_tombstone3'] = 1,
	['npc_dota_unit_tombstone4'] = 1,
	['npc_dota_warlock_golem_1'] = 0.9,
	['npc_dota_warlock_golem_2'] = 0.9,
	['npc_dota_warlock_golem_3'] = 0.9,
	['npc_dota_warlock_golem_scepter_1'] = 0.9,
	['npc_dota_warlock_golem_scepter_2'] = 0.9,
	['npc_dota_warlock_golem_scepter_3'] = 0.9,
	['npc_dota_weaver_swarm'] = 0.9,
	['npc_dota_zeus_cloud'] = 0.75,
}
function J.GetSpecialUnits()
	return SpecialUnits
end

function J.IsDisabled( npcTarget )

	if npcTarget:GetTeam() ~= GetTeam() and npcTarget:CanBeSeen()
	then
		return npcTarget:IsRooted()
				or npcTarget:IsStunned()
				or npcTarget:IsHexed()
				or npcTarget:IsNightmared()
				or J.IsTaunted( npcTarget )
	else

		if npcTarget:IsStunned() and J.GetRemainStunTime( npcTarget ) > 0.8
		then
			return true
		end

		if npcTarget:IsSilenced()
			and not npcTarget:HasModifier( "modifier_item_mask_of_madness_berserk" )
			and J.IsWithoutTarget( npcTarget )
		then
			return true
		end

		return npcTarget:IsRooted()
				or npcTarget:IsHexed()
				or npcTarget:IsNightmared()
				or J.IsTaunted( npcTarget )

	end

end


function J.IsTaunted( npcTarget )
	if not npcTarget:CanBeSeen() then
		return false
	end

	return npcTarget:HasModifier( "modifier_axe_berserkers_call" )
		or npcTarget:HasModifier( "modifier_legion_commander_duel" )
		or npcTarget:HasModifier( "modifier_winter_wyvern_winters_curse" )
		or npcTarget:HasModifier( "modifier_winter_wyvern_winters_curse_aura" )

end


function J.IsInRange( bot, npcTarget, nRadius )
	if npcTarget == nil or not npcTarget:CanBeSeen() then
		return false
	end

	return GetUnitToUnitDistance( bot, npcTarget ) <= nRadius

end


function J.IsInLocRange( npcTarget, nLoc, nRadius )
	if not npcTarget:CanBeSeen() then
		return false
	end

	return GetUnitToLocationDistance( npcTarget, nLoc ) <= nRadius

end

function J.HasItemInInventory( hItem )
	return GetBot():FindItemSlot(hItem) >= 0
end

function J.IsInTeamFight( bot, nRadius )

	if nRadius == nil or nRadius > 1600 then nRadius = 1600 end
	local towerTarget = bot._defend and J.GetTowerDefenseTarget(bot)
	if towerTarget and J.IsInRange(bot, towerTarget, nRadius) then return true end

	local attackModeAllyList = J.GetNearbyHeroes(bot, nRadius, false, BOT_MODE_ATTACK )

	return #attackModeAllyList >= 2 -- and bot:GetActiveMode() ~= BOT_MODE_RETREAT

end

function J.GetItem(itemName)
	for i = 0, 5
    do
		local item = GetBot():GetItemInSlot(i)

		if  item ~= nil
        and item:GetName() == itemName
        then
			return item
		end
	end

	return nil
end

function J.GetItem2(bot, sItemName)
	for i = 0, 16
	do
		local item = bot:GetItemInSlot(i)
		if item ~= nil
		then
			if string.find(item:GetName(), sItemName)
			then
				return item
			end
		end
	end

	return nil
end

function J.IsRetreating( bot )

	local mode = bot:GetActiveMode()
	local modeDesire = bot:GetActiveModeDesire()
	local bDamagedByAnyHero = bot:WasRecentlyDamagedByAnyHero( 2.0 )

	return ( mode == BOT_MODE_RETREAT and modeDesire > BOT_MODE_DESIRE_MODERATE and bot:DistanceFromFountain() > 0 )
		 or ( mode == BOT_MODE_EVASIVE_MANEUVERS and bDamagedByAnyHero )
		 or ( bot:HasModifier( 'modifier_bloodseeker_rupture' ) and bDamagedByAnyHero )
		 or ( mode == BOT_MODE_FARM and modeDesire > BOT_MODE_DESIRE_ABSOLUTE )
		
end

function J.GetAbility(bot, abilityName)
	for i = 0, 23 do
		local ability = bot:GetAbilityInSlot(i)
		if  ability ~= nil
		and ability:GetName() == abilityName
		then
			return ability
		end
	end

	return nil
end

function J.IsUnitNearby(bot, tUnits, nRadius, sUnitName, bHero)
    for _, unit in pairs(tUnits) do
        if J.IsValid(unit)
        and J.IsInRange(bot, unit, nRadius)
        and unit:GetUnitName() == sUnitName
        then
			if bHero then
				if J.IsValidHero(unit) and not J.IsSuspiciousIllusion(unit) then
					return true
				end
			else
				return true
			end
        end
    end

    return false
end


function J.IsGoingOnSomeone( bot )

	local mode = bot:GetActiveMode()

	return mode == BOT_MODE_ROAM
		or mode == BOT_MODE_TEAM_ROAM
		or mode == BOT_MODE_GANK
		or mode == BOT_MODE_ATTACK
		or mode == BOT_MODE_DEFEND_ALLY
		or (bot._defend ~= nil and J.GetTowerDefenseTarget(bot) ~= nil)

end

local function IsEnemyTerrorbladeNear(unit, nRadius)
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES)) do
		if J.IsValidHero(enemy)
		and J.IsInRange(unit, enemy, nRadius)
		and enemy:GetUnitName() == 'npc_dota_hero_terrorblade'
		and not J.IsSuspiciousIllusion(enemy)
		then
			return true
		end
	end

	return false
end

local function GetUnitAttackDamage(unit, fInterval, bIllusion)
	if J.IsValid(unit) then
		local nAttackDamage = unit:GetAttackDamage()
		local sUnitName = unit:GetUnitName()

		if bIllusion and J.IsSuspiciousIllusion(unit) then
			if string.find(sUnitName, 'phantom_lancer') then
				nAttackDamage = nAttackDamage * 0.19
			elseif string.find(sUnitName, 'naga_siren') then
				nAttackDamage = nAttackDamage * 0.4
			elseif string.find(sUnitName, 'chaos_knight') then
				-- full
			elseif string.find(sUnitName, 'terrorblade') then
				if IsEnemyTerrorbladeNear(unit, 1200) then
					nAttackDamage = nAttackDamage * 0.6 * (1.25)
				else
					nAttackDamage = nAttackDamage * 0.6 * (0.60)
				end
			elseif unit:HasModifier('modifier_darkseer_wallofreplica_illusion') then
				nAttackDamage = nAttackDamage * 0.9
			elseif unit:HasModifier('modifier_grimstroke_scepter_buff') then
				nAttackDamage = nAttackDamage * 1.5
			else
				nAttackDamage = nAttackDamage * 0.33
			end

			return nAttackDamage * unit:GetAttackSpeed() * fInterval
		else
			if not bIllusion then
				return nAttackDamage * unit:GetAttackSpeed() * fInterval
			end
		end
	end


	return nil
end

function J.IsDefending( bot )

	local mode = bot:GetActiveMode()

	return mode == BOT_MODE_DEFEND_TOWER_TOP
		or mode == BOT_MODE_DEFEND_TOWER_MID
		or mode == BOT_MODE_DEFEND_TOWER_BOT

end

function J.IsAnyAllyDefending(bot, lane)
	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if J.IsValidHero(allyHero)
		and J.IsNotSelf(bot, allyHero)
		then
			local mode = allyHero:GetActiveMode()
			if (mode == BOT_MODE_DEFEND_TOWER_TOP and lane == LANE_TOP)
			or (mode == BOT_MODE_DEFEND_TOWER_MID and lane == LANE_MID)
			or (mode == BOT_MODE_DEFEND_TOWER_BOT and lane == LANE_BOT)
			then
				return true
			end
		end
	end
	return false
end

function J.IsPushing( bot )

	local mode = bot:GetActiveMode()

	return mode == BOT_MODE_PUSH_TOWER_TOP
		or mode == BOT_MODE_PUSH_TOWER_MID
		or mode == BOT_MODE_PUSH_TOWER_BOT

end

function J.MultipleAlliesArePushing()
	local pushingAlly = 0
	for i, id in pairs( GetTeamPlayers( GetTeam() ) )
	do
		if IsHeroAlive( id )
		then
			local member = GetTeamMember( i )
			if J.IsValidHero(member) and J.IsPushing( member ) then
				pushingAlly = pushingAlly + 1
			end
		end
	end
	return pushingAlly >= 2
end

function J.IsLaning( bot )
	local mode = bot:GetActiveMode()

	return mode == BOT_MODE_LANING

end

function J.IsDoingRoshan( bot )

	local mode = bot:GetActiveMode()

	return mode == BOT_MODE_ROSHAN

end


function J.IsFarming( bot )

	local mode = bot:GetActiveMode()
	local nTarget = J.GetProperTarget( bot )

	return mode == BOT_MODE_FARM
			or ( nTarget ~= nil
					and nTarget:IsAlive()
					and nTarget:GetTeam() == TEAM_NEUTRAL
					and not J.IsRoshan( nTarget ) )
end


function J.IsShopping( bot )

	local mode = bot:GetActiveMode()

	return mode == BOT_MODE_RUNE
		or mode == BOT_MODE_SECRET_SHOP
		or mode == BOT_MODE_SIDE_SHOP

end


function J.GetTeamFountain()

	local Team = GetTeam()
	if Team == TEAM_DIRE
	then
		return DireFountain
	else
		return RadiantFountain
	end

end


function J.GetEnemyFountain()

	local Team = GetTeam()

	if Team == TEAM_DIRE
	then
		return RadiantFountain
	else
		return DireFountain
	end

end


function J.GetComboItem( bot, sItemName )

	local Slot = bot:FindItemSlot( sItemName )

	if Slot >= 0 and Slot <= 5
	then
		return bot:GetItemInSlot( Slot )
	end

end


function J.HasItem( bot, sItemName )

	local Slot = bot:FindItemSlot( sItemName )

	if Slot >= 0 and Slot <= 5 then	return true end

	return false

end

function J.FindItemSlotNotInNonbackpack( bot, sItemName )
	local Slot = bot:FindItemSlot( sItemName )
	if Slot >= 0 and Slot <= 5 then	return Slot end
	return -1
end

function J.IsItemAvailable( sItemName )

	local bot = GetBot()

	local slot = bot:FindItemSlot( sItemName )

	if slot >= 0 and slot <= 5
	then
		return bot:GetItemInSlot( slot )
	end

end


function J.GetMostHpUnit( unitList )

	local mostHpUnit = nil
	local maxHP = 0
	for _, unit in pairs( unitList )
	do
		local uHp = unit:GetHealth()
		if unit ~= nil
		and not J.IsRoshan(unit)
		and not J.IsTormentor(unit)
		and uHp > maxHP
		then
			mostHpUnit = unit
			maxHP = uHp
		end
	end

	return mostHpUnit

end


function J.GetLeastHpUnit( unitList )

	local leastHpUnit = nil
	local minHP = 999999

	for _, unit in pairs( unitList )
	do
		local uHp = unit:GetHealth()
		if uHp < minHP
		then
			leastHpUnit = unit
			minHP = uHp
		end
	end

	return leastHpUnit

end


function J.IsAllowedToSpam( bot, nManaCost )

	if bot:HasModifier( "modifier_silencer_curse_of_the_silent" ) then return false end

	if bot:HasModifier( "modifier_rune_regen" ) then return true end

	return ( bot:GetMana() - nManaCost ) / bot:GetMaxMana() >= fKeepManaPercent

end


function J.IsAllyUnitSpell( sAbilityName )

	return J.Skill['sAllyUnitAbilityIndex'][sAbilityName] == true

end


function J.IsProjectileUnitSpell( sAbilityName )

	return J.Skill['sProjectileAbilityIndex'][sAbilityName] == true


end


function J.IsOnlyProjectileSpell( sAbilityName )

	return J.Skill['sOnlyProjectileAbilityIndex'][sAbilityName] == true

end


function J.IsStunProjectileSpell( sAbilityName )

	return J.Skill['sStunProjectileAbilityIndex'][sAbilityName] == true

end


function J.IsWillBeCastUnitTargetSpell( bot, nRadius )

	if nRadius > 1600 then nRadius = 1600 end

	local enemyList = J.GetNearbyHeroes(bot, nRadius, true, BOT_MODE_NONE )
	for _, npcEnemy in pairs( enemyList )
	do
		if npcEnemy ~= nil and npcEnemy:IsAlive()
			and ( npcEnemy:IsCastingAbility() or npcEnemy:IsUsingAbility() )
			and npcEnemy:IsFacingLocation( bot:GetLocation(), 20 )
		then
			local nAbility = npcEnemy:GetCurrentActiveAbility()
			if nAbility ~= nil
				and nAbility:GetBehavior() == ABILITY_BEHAVIOR_UNIT_TARGET
			then
				local sAbilityName = nAbility:GetName()
				if not J.IsAllyUnitSpell( sAbilityName )
				then
					if J.IsInRange( npcEnemy, bot, 330 )
						or not J.IsProjectileUnitSpell( sAbilityName )
					then
						if not J.IsHumanPlayer( npcEnemy )
						then
							return true
						else
							local nCycle = npcEnemy:GetAnimCycle()
							local nPoint = nAbility:GetCastPoint()
							if nCycle > 0.1 and nPoint * ( 1 - nCycle ) < 0.27 --极限时机0.26
							then
								return true
							end
						end
					end
				end
			end
		end
	end

	return false

end


function J.IsWillBeCastPointSpell( bot, nRadius )

	local enemyList = J.GetNearbyHeroes(bot, nRadius, true, BOT_MODE_NONE )

	for _, npcEnemy in pairs( enemyList )
	do
		if npcEnemy ~= nil and npcEnemy:IsAlive()
			and ( npcEnemy:IsCastingAbility() or npcEnemy:IsUsingAbility() )
			and npcEnemy:IsFacingLocation( bot:GetLocation(), 50 )
		then
			local nAbility = npcEnemy:GetCurrentActiveAbility()
			if nAbility ~= nil
			then
				if nAbility:GetBehavior() == ABILITY_BEHAVIOR_POINT
					or nAbility:GetBehavior() == ABILITY_BEHAVIOR_NO_TARGET
					or nAbility:GetBehavior() == 48
				then
					return true
				end
			end
		end
	end

	return false

end


--可躲避敌方非攻击弹道
function J.IsProjectileIncoming( bot, range )

	local incProj = bot:GetIncomingTrackingProjectiles()
	for _, p in pairs( incProj )
	do
		if p.is_dodgeable
			and not p.is_attack
			and GetUnitToLocationDistance( bot, p.location ) < range
			and ( p.caster == nil or p.caster:GetTeam() ~= GetTeam() )
			and ( p.ability ~= nil
					and not J.IsOnlyProjectileSpell( p.ability:GetName() )
					and ( p.ability:GetName() ~= "medusa_mystic_snake"
							or p.caster == nil
							or p.caster:GetUnitName() == "npc_dota_hero_medusa" ) )
		then
			return true
		end
	end

	return false

end


--可反弹敌方非攻击弹道
function J.IsUnitTargetProjectileIncoming( bot, range )

	local incProj = bot:GetIncomingTrackingProjectiles()
	for _, p in pairs( incProj )
	do
		if not p.is_attack
			and GetUnitToLocationDistance( bot, p.location ) < range
			and ( p.caster == nil
				 or ( p.caster:GetTeam() ~= bot:GetTeam()
					 and p.caster:IsHero()
					 and p.caster:GetUnitName() ~= "npc_dota_hero_antimage"
					 and p.caster:GetUnitName() ~= "npc_dota_hero_templar_assassin" ) )
			and ( p.ability ~= nil
				 and ( p.ability:GetName() ~= "medusa_mystic_snake"
						or p.caster == nil
						or p.caster:GetUnitName() == "npc_dota_hero_medusa" ) )
			and ( p.ability:GetBehavior() == ABILITY_BEHAVIOR_UNIT_TARGET
				 or not J.IsOnlyProjectileSpell( p.ability:GetName() ) )
		then
			return true
		end
	end

	return false

end


--将被眩晕的弹道
function J.IsStunProjectileIncoming( bot, range, requirePiercing )

	local incProj = bot:GetIncomingTrackingProjectiles()
	for _, p in pairs( incProj )
	do
		if not p.is_attack
			and GetUnitToLocationDistance( bot, p.location ) < range
			and p.ability ~= nil
			and (not requirePiercing or J.Utils.AbilityBehaviorHasFlag(p.ability:GetTargetFlags(), ABILITY_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES or 16))
			and J.IsStunProjectileSpell( p.ability:GetName() )
		then
			return true
		end
	end

	return false

end


--攻击弹道
function J.IsAttackProjectileIncoming( bot, range )

	local incProj = bot:GetIncomingTrackingProjectiles()
	for _, p in pairs( incProj )
	do
		if p.is_attack
			and GetUnitToLocationDistance( bot, p.location ) < range
		then
			return true
		end
	end

	return false

end


--非攻击敌方弹道
function J.IsNotAttackProjectileIncoming( bot, range )

	local incProj = bot:GetIncomingTrackingProjectiles()
	for _, p in pairs( incProj )
	do
		if not p.is_attack
			and GetUnitToLocationDistance( bot, p.location ) < range
			and ( p.caster == nil or p.caster:GetTeam() ~= bot:GetTeam() )
			and ( p.ability ~= nil
					and ( p.ability:GetName() ~= "medusa_mystic_snake"
							or p.caster == nil
							or p.caster:GetUnitName() == "npc_dota_hero_medusa" ) )
		then
			return true
		end
	end

	return false

end


local function GetAttackSpeedMultiplier(unit)
	local speed = unit:GetAttackSpeed()
	if speed > 10 then speed = speed / 100 end
	return math.max(0.1, speed)
end

function J.GetAttackProDelayTime(bot, target, currentAttackOnly)
    if target == nil then return 0, 0, 0 end
	local speed = GetAttackSpeedMultiplier(bot)
	local attackPoint = bot:GetAttackPoint()
	local windup = attackPoint / speed
	local distance = GetUnitToUnitDistance(bot, target)
	local range = bot:GetAttackRange()
	local approach = math.max(0, distance - range) / math.max(1, bot:GetCurrentMovementSpeed())
	if approach > 0 and type(bot.IsFacingLocation) == 'function'
		and not bot:IsFacingLocation(target:GetLocation(), 45) then approach = approach + 0.08 end
	local elapsed = GameTime() - bot:GetLastAttackTime()
	local recovery = math.max(0, bot:GetSecondsPerAttack() - windup - elapsed)
    local wait = math.max(approach, recovery)
    local release = wait + windup

	local windupLeft = approach == 0 and bot:GetAttackTarget() == target and J.IsAttacking(bot)
		and (attackPoint - bot:GetAnimCycle()) / speed or 0
	if windupLeft > 0 then
		release, wait = windupLeft, 0
	elseif currentAttackOnly then
		return 0, 0, 0
    elseif approach == 0 and type(bot.IsFacingLocation) == 'function'
        and not bot:IsFacingLocation(target:GetLocation(), 45) then
        wait = math.max(wait, 0.08)
        release = wait + windup
	end

	local missile = bot:GetAttackProjectileSpeed()
	local flight = missile > 0 and math.max(0, math.min(distance, range) - 35) / missile or 0
    return release + flight, release, wait
end


--当前点 * 攻击间隔 / 1.0 = 当前时
function J.GetCreepAttackActivityWillRealDamage( nUnit, nTime, laneTiming )

	local bot = GetBot()
	local botLV = bot:GetLevel()
	local gameTime = GameTime()
	local nDamage = 0
	local othersBeEnemy = true

	if nUnit:GetTeam() ~= bot:GetTeam() then othersBeEnemy = false end

	local nCreeps = bot:GetNearbyLaneCreeps( 1600, othersBeEnemy )
	for _, creep in pairs( nCreeps )
	do
		if laneTiming then
            if creep:CanBeSeen() and creep:GetAttackTarget() == nUnit and J.IsAttacking(creep) then
                local impact, release = J.GetAttackProDelayTime(creep, nUnit, true)
                if release > 0 and impact < nTime - 0.033 then
                    nDamage = nDamage + LaneAttackDamage(creep, nUnit, creep:GetAttackDamage())
                end
			end
		elseif creep:CanBeSeen()
			and creep:GetAttackTarget() == nUnit
			and creep:GetAnimActivity() == 1503
			and creep:GetLastAttackTime() < gameTime - 0.2
		then
			local attackPoint	= creep:GetAttackPoint()
			local animCycle	 = creep:GetAnimCycle()
			local attackPerTime = creep:GetSecondsPerAttack()

			if J.IsKeyWordUnit( 'melee', creep )
				and animCycle < attackPoint
				and ( attackPoint - animCycle ) * attackPerTime < nTime * ( 0.99 - botLV / 300 )
			then
				nDamage = nDamage + creep:GetAttackDamage() * 1
			end

			if J.IsKeyWordUnit( 'ranged', creep )
				and animCycle < attackPoint
			then
				local nDist = GetUnitToUnitDistance( creep, nUnit ) - 22
				local nProjectSpeed = creep:GetAttackProjectileSpeed()
				local nProjectTime = nDist / ( nProjectSpeed + 1 )
				if ( attackPoint - animCycle ) * attackPerTime + nProjectTime < nTime * ( 0.98 - botLV / 200 )
				then
					nDamage = nDamage + creep:GetAttackDamage() * 1
				end
			end

			if J.IsKeyWordUnit( 'siege', creep )
				and animCycle < 0.292 --0.285
			then
				local nDist = GetUnitToUnitDistance( creep, nUnit ) - 28
				local nProjectSpeed = creep:GetAttackProjectileSpeed()
				local nProjectTime = nDist / ( nProjectSpeed + 1 )
				if ( 0.292 - animCycle ) * 0.699 / 0.292 + nProjectTime < nTime * ( 0.9 - botLV / 150 )
				then
					nDamage = nDamage + creep:GetAttackDamage() * 1
				end
			end

		end
	end

	return laneTiming and nDamage or nUnit:GetActualIncomingDamage(nDamage, DAMAGE_TYPE_PHYSICAL)

end


function J.GetCreepAttackProjectileWillRealDamage( nUnit, nTime, laneTiming )

	local nDamage = 0
	local incProj = nUnit:GetIncomingTrackingProjectiles()
	for _, p in pairs( incProj )
	do
		if p.is_attack
			and p.caster ~= nil
			and (not laneTiming or p.caster:CanBeSeen())
		then
			local nProjectSpeed = p.caster:GetAttackProjectileSpeed()
			local nDistance	 = GetUnitToLocationDistance( nUnit, p.location )
			if laneTiming then
				if nProjectSpeed > 0 and nDistance / nProjectSpeed < nTime - 0.033 then
					nDamage = nDamage + LaneAttackDamage(p.caster, nUnit, p.caster:GetAttackDamage())
				end
			else
				if p.caster:IsTower() then nProjectSpeed = nProjectSpeed * 0.93 end
				if nProjectSpeed * nTime * 0.95 > nDistance * 1.02 then nDamage = nDamage + p.caster:GetAttackDamage() end
			end
		end
	end

	return laneTiming and nDamage or nUnit:GetActualIncomingDamage(nDamage, DAMAGE_TYPE_PHYSICAL)

end


function J.GetTotalAttackWillRealDamage( nUnit, nTime, laneTiming )

	 return J.GetCreepAttackProjectileWillRealDamage(nUnit, nTime, laneTiming)
		+ J.GetCreepAttackActivityWillRealDamage(nUnit, nTime, laneTiming)

end


function J.GetAttackProjectileDamageByRange( nUnit, nRadius )

	local nDamage = 0
	local incProj = nUnit:GetIncomingTrackingProjectiles()
	for _, p in pairs( incProj )
	do
		if p.is_attack and p.caster ~= nil
			and GetUnitToLocationDistance( nUnit, p.location ) < nRadius
		then
			nDamage = nDamage + p.caster:GetAttackDamage() * 1
		end
	end

	return nDamage

end


function J.GetCorrectLoc( npcTarget, fDelay )

	local nStability = npcTarget:GetMovementDirectionStability()

	local vFirst = npcTarget:GetLocation()
	local vFuture = npcTarget:GetExtrapolatedLocation( fDelay )
	local vMidFutrue = ( vFirst + vFuture ) * 0.5
	local vLowFutrue = ( vFirst + vMidFutrue ) * 0.5
	local vHighFutrue = ( vFuture + vMidFutrue ) * 0.5


	if nStability < 0.5
	then
		return vLowFutrue
	elseif nStability < 0.7
	then
		return vMidFutrue
	elseif nStability < 0.9
	then
		return vHighFutrue
	end

	return vFuture
end

function J.GetDistanceFromLaneFront(bot)
	return J.GetDistance(GetLaneFrontLocation(GetTeam(), bot:GetAssignedLane(), 0), bot:GetLocation())
end

function J.GetEscapeLoc()

	local bot = GetBot()
	local team = GetTeam()

	if bot:DistanceFromFountain() > 2500
	then
		return GetAncient( team ):GetLocation()
	else
		if team == TEAM_DIRE
		then
			return DireFountain
		else
			return RadiantFountain
		end
	end

end


function J.IsStuck2( bot )

	if bot.stuckLoc ~= nil and bot.stuckTime ~= nil
	then
		local EAd = GetUnitToUnitDistance( bot, GetAncient( GetOpposingTeam() ) )
		if DotaTime() > bot.stuckTime + 5.0 and GetUnitToLocationDistance( bot, bot.stuckLoc ) < 25
			and bot:GetCurrentActionType() == BOT_ACTION_TYPE_MOVE_TO and EAd > 2200
		then
			print( bot:GetUnitName().." is stuck" )
			--DebugPause()
			return true
		end
	end

	return false

end


function J.IsStuck( bot )

	if bot.stuckLoc ~= nil and bot.stuckTime ~= nil and bot:CanBeSeen()
	then
		local attackTarget = bot:GetAttackTarget()
		local EAd = GetUnitToUnitDistance( bot, GetAncient( GetOpposingTeam() ) )
		local TAd = GetUnitToUnitDistance( bot, GetAncient( GetTeam() ) )
		local Et = bot:GetNearbyTowers( 450, true )
		local At = bot:GetNearbyTowers( 450, false )
		if bot:GetCurrentActionType() == BOT_ACTION_TYPE_MOVE_TO
			and attackTarget == nil and EAd > 2200 and TAd > 2200 and #Et == 0 and #At == 0
			and DotaTime() > bot.stuckTime + 5.0
			and GetUnitToLocationDistance( bot, bot.stuckLoc ) < 25
		then
			print( bot:GetUnitName().." is stuck" )
			return true
		end
	end

	return false

end


function J.IsExistInTable( u, tUnit )

	for _, t in pairs( tUnit )
	do
		if u == t
		then
			return true
		end
	end

	return false

end


function J.CombineTwoTable( tableA, tableB )

	local targetTable = tableA
	local Num = #tableA

	for i, u in pairs( tableB )
	do
		targetTable[Num + i] = u
	end

	return targetTable
end


function J.GetInvUnitInLocCount( bot, nRadius, nFindRadius, vLocation, pierceImmune )

	local nUnits = 0
	if nRadius > 1600 then nRadius = 1600 end
	local unitList = J.GetNearbyHeroes(bot, nRadius, true, BOT_MODE_NONE )
	for _, u in pairs( unitList ) do
		if ( ( pierceImmune and J.CanCastOnMagicImmune( u ) )
			 or ( not pierceImmune and J.CanCastOnNonMagicImmune( u ) ) )
			and GetUnitToLocationDistance( u, vLocation ) <= nFindRadius
		then
			nUnits = nUnits + 1
		end
	end

	return nUnits

end


function J.GetInLocLaneCreepCount( bot, nRadius, nFindRadius, vLocation )

	local nUnits = 0
	if nRadius > 1600 then nRadius = 1600 end
	local unitList = bot:GetNearbyLaneCreeps( nRadius, true )
	for _, u in pairs( unitList ) do
		if GetUnitToLocationDistance( u, vLocation ) <= nFindRadius
		then
			nUnits = nUnits + 1
		end
	end

	return nUnits

end


function J.GetInvUnitCount( pierceImmune, unitList )

	local nUnits = 0
	if unitList ~= nil
	then
		for _, u in pairs( unitList )
		do
			if ( pierceImmune and J.CanCastOnMagicImmune( u ) )
				or ( not pierceImmune and J.CanCastOnNonMagicImmune( u ) )
			then
				nUnits = nUnits + 1
			end
		end
	end

	return nUnits

end

function J.HasHealingItem(bot)
	if bot:HasModifier('modifier_tango_heal') or bot:HasModifier('modifier_flask_healing')
		or bot:HasModifier('modifier_bottle_regeneration') then return true end
	for slot = 0, 5 do
		local item = bot:GetItemInSlot(slot)
		if item then
			local name = item:GetName()
			if (name == 'item_tango' or name == 'item_tango_single' or name == 'item_flask' or name == 'item_bottle')
				and item:GetCurrentCharges() > 0 and item:IsFullyCastable() then return true end
		end
	end
	return false
end

function J.ShouldGoFarmDuringLaning(bot)
	-- laning is too hard for the bot, try go farming somewhere else.
	local lane = bot:GetAssignedLane()
	return J.IsInLaningPhase()
	and GetHeroDeaths(bot:GetPlayerID()) >= 4
	and (GetHeroKills(bot:GetPlayerID()) == 0 or GetHeroKills(bot:GetPlayerID()) / GetHeroDeaths(bot:GetPlayerID()) < 0.5)
	and J.IsCore(bot)
	and bot:GetLevel() >= 4
	and bot:GetLevel() < 10
	and J.GetEnemyCountInLane(lane) >= 1
end

--------------------------------------------------ew functions 2018.12.7

function J.GetDistanceFromEnemyFountain( bot )

	local EnemyFountain = J.GetEnemyFountain()
	local Distance = GetUnitToLocationDistance( bot, EnemyFountain )

	return Distance

end


function J.GetDistanceFromAllyFountain( bot )

	local OurFountain = J.GetTeamFountain()
	local Distance = GetUnitToLocationDistance( bot, OurFountain )

	return Distance

end


function J.GetDistanceFromAncient( bot, bEnemy )

	local targetAncient = GetAncient( GetTeam() )

	if bEnemy then targetAncient = GetAncient( GetOpposingTeam() ) end

	return GetUnitToUnitDistance( bot, targetAncient )

end


function J.GetAroundTargetAllyHeroCount( target, nRadius )

	local heroList = J.GetAlliesNearLoc( target:GetLocation(), nRadius )

	return #heroList

end


function J.GetAroundTargetOtherAllyHeroCount( bot, target, nRadius )

	local heroList = J.GetAlliesNearLoc( target:GetLocation(), nRadius )

	if GetUnitToUnitDistance( bot, target ) <= nRadius
	then
		return #heroList - 1
	end

	return #heroList

end


function J.GetAllyCreepNearLoc( bot, vLoc, nRadius )

	local AllyCreepsAll = bot:GetNearbyCreeps( 1600, false )
	local allyCreepList = { }

	for _, creep in pairs( AllyCreepsAll )
	do
		if creep ~= nil
			and creep:IsAlive()
			and GetUnitToLocationDistance( creep, vLoc ) <= nRadius
		then
			table.insert( allyCreepList, creep )
		end
	end

	return allyCreepList

end


function J.GetAllyUnitCountAroundEnemyTarget( bot, target, nRadius )

	local heroList = J.GetAlliesNearLoc( target:GetLocation(), nRadius )
	local creepList = J.GetAllyCreepNearLoc( bot, target:GetLocation(), nRadius )

	return #heroList + #creepList

end


-- local NearbyHeroMap = {
	-- 'hero_unit_name' = {
	-- 	'enemy' = {
	-- 		'1600' = { 
	-- 			'time' = DotaTime(),
	-- 			'heroes' = {}
	-- 		},
	-- 		'1000' = { },
	-- 	},
	-- 	'ally' = {
	-- 		'1600' = { },
	-- 		'1000' = { },
	-- 	}
	-- }
-- }
-- Cache duration in seconds
local nearByHeroCacheDuration = 0.1 -- 0.xxx = xxx ms. if you have 60 frames per second, it's 1000/60 = 16.7ms per frame. higher fps, smaller ms per frame.
-- Check the current time
local currentTime
local cacheNearbyTable
local printN = 0

-- Method to refresh and cache nearby hero lists for each hero unit
-- Unknown why but it seems to cause dota2 to crash due to changing the caching frequence, or maybe it's due to some nil exceptions.
function J.GetNearbyHeroes(bot, nRadius, bEnemy, bBotMode)
	if not bBotMode then bBotMode = BOT_MODE_NONE end
	-- local nearbyHeroes = bot:GetNearbyHeroes(nRadius, bEnemy, bBotMode)
	-- if printN <= 100000 then
	-- 	printN = printN + 1
	-- 	J.Utils.PrintTable(nearbyHeroes)
	-- end
	local nearby = bot:GetNearbyHeroes(nRadius, bEnemy, bBotMode)
	if not nearby then
		return nearby
	end

	local heroes = {}
	for _, hero in pairs( nearby )
	do
		if J.IsValidHero(hero)
		and not J.IsMeepoClone(hero)
		and not bot:HasModifier('modifier_arc_warden_tempest_double') then
			table.insert(heroes, hero)
		end
	end
	return heroes

    -- Cap the radius to a maximum value
    -- if nRadius > 1600 then nRadius = 1600 end

    -- -- Initialize the bot's cache table if it doesn't exist
    -- bot.nearbyHeroes = bot.nearbyHeroes or { ally = {}, enemy = {} }

    -- -- Select the appropriate cache based on whether we're looking for enemies or allies
    -- cacheNearbyTable = bEnemy and bot.nearbyHeroes.enemy or bot.nearbyHeroes.ally

    -- -- Check the current time
    -- currentTime = DotaTime()

    -- -- Initialize or update the cache for the specific radius
	-- if cacheNearbyTable[nRadius] == nil or
	-- 	currentTime - cacheNearbyTable[nRadius].time >= nearByHeroCacheDuration
	-- then
	-- 	cacheNearbyTable[nRadius] = {
	-- 		time = currentTime,
	-- 		heroes = bot:GetNearbyHeroes(nRadius, bEnemy, BOT_MODE_NONE)
	-- 	}
	-- end

	-- -- J.Utils.PrintTable(cacheNearbyTable[nRadius].heroes)
    -- -- Return the cached nearby heroes
    -- return cacheNearbyTable[nRadius].heroes
end

function J.GetAroundBotUnitList( bot, nRadius, bEnemy )

	if nRadius > 1600 then nRadius = 1600 end

	local heroList = J.GetNearbyHeroes(bot, nRadius, bEnemy, BOT_MODE_NONE )
	local creepList = bot:GetNearbyCreeps( nRadius, bEnemy )
	local unitList = {}

	if #heroList > 0 and #creepList > 0
	then
		unitList = heroList
		for i = 1, #creepList
		do
			table.insert( unitList, creepList[1] )
		end
	elseif #heroList == 0
	then
		unitList = creepList
	elseif #creepList == 0
	then
		unitList = heroList
	end

	return unitList

end

function J.GetLocationToLocationDistance( fLoc, sLoc )

	local x1 = fLoc.x
	local x2 = sLoc.x
	local y1 = fLoc.y
	local y2 = sLoc.y

	return math.sqrt( math.pow( ( y2-y1 ), 2 ) + math.pow( ( x2-x1 ), 2 ) )

end


function J.GetUnitTowardDistanceLocation( bot, towardTarget, nDistance )

	local npcBotLocation = bot:GetLocation()
	local tempVector = ( towardTarget:GetLocation() - npcBotLocation ) / GetUnitToUnitDistance( bot, towardTarget )

	return npcBotLocation + nDistance * tempVector

end


function J.GetLocationTowardDistanceLocation( bot, towardLocation, nDistance )

	local npcBotLocation = bot:GetLocation()
	local tempVector = ( towardLocation - npcBotLocation ) / GetUnitToLocationDistance( bot, towardLocation )

	return npcBotLocation + nDistance * tempVector

end


function J.GetFaceTowardDistanceLocation( bot, nDistance )

	local npcBotLocation = bot:GetLocation()
	local tempRadians = bot:GetFacing() * math.pi / 180
	local tempVector = Vector( math.cos( tempRadians ), math.sin( tempRadians ) )

	return npcBotLocation + nDistance * tempVector

end


function J.SetBotPing( vLoc )

	GetBot():ActionImmediate_Ping( vLoc.x, vLoc.y, false )

end


function J.SetBotPrint( sMessage, vLoc, bReport, bPing )

	local bot = GetBot()

	local nTime = J.GetOne( DotaTime() / 10 )* 10
	local sTime = ( J.GetOne( nTime / 600 )* 10 )..":"..( nTime%60 )
	local sTeam = GetTeam() == TEAM_DIRE and "夜魇" or "天辉"

	if bDebugMode
	then

		print( sTeam..sTime.." "..J.Chat.GetNormName( bot ).." "..sMessage )

		if bReport then bot:ActionImmediate_Chat( sTime.."_"..sMessage, true ) end

		if bPing then bot:ActionImmediate_Ping( vLoc.x, vLoc.y, false ) end

	end

end


function J.SetReportMotive( bDebugFile, sMotive )

	if bDebugMode and bDebugFile and sMotive ~= nil
	then

		local nTime = J.GetOne( DotaTime() / 10 ) * 10
		local sTime = ( J.GetOne( nTime / 600 ) * 10 )..":"..( nTime%60 )
		local sTeam = GetTeam() == TEAM_DIRE and "夜魇 " or "天辉 "

		GetBot():ActionImmediate_Chat( sTime.."_"..sMotive, true )

		print( sTeam..sTime.." "..J.Chat.GetNormName( GetBot() ).." "..sMotive )

	end

end


function J.GetCastLocation( bot, npcTarget, nCastRange, nRadius )

	local nDistance = GetUnitToUnitDistance( bot, npcTarget )

	if nDistance <= nCastRange
	then
		return npcTarget:GetLocation()
	end

	if nDistance <= nCastRange + nRadius - 120
	then
		return J.GetUnitTowardDistanceLocation( bot, npcTarget, nCastRange )
	end

	if nDistance < nCastRange + nRadius - 18
		and ( ( J.IsDisabled( npcTarget ) or npcTarget:GetCurrentMovementSpeed() <= 160 )
				or npcTarget:IsFacingLocation( bot:GetLocation(), 45 )
				or ( bot:IsFacingLocation( npcTarget:GetLocation(), 45 ) and npcTarget:GetCurrentMovementSpeed() <= 220 ) )
	then
		return J.GetUnitTowardDistanceLocation( bot, npcTarget, nCastRange +18 )
	end

	if nDistance < nCastRange + nRadius + 28
		and npcTarget:IsFacingLocation( bot:GetLocation(), 30 )
		and bot:IsFacingLocation( npcTarget:GetLocation(), 30 )
		and npcTarget:GetMovementDirectionStability() > 0.95
		and npcTarget:GetCurrentMovementSpeed() >= 300
	then
		return J.GetUnitTowardDistanceLocation( bot, npcTarget, nCastRange + 18 )
	end

	return nil

end


function J.GetDelayCastLocation( bot, npcTarget, nCastRange, nRadius, nTime )

	local nFutureLoc = J.GetCorrectLoc( npcTarget, nTime )
	local nDistance = GetUnitToLocationDistance( bot, nFutureLoc )

	if nDistance > nCastRange + nRadius - 16
	then
		return nil
	end

	if nDistance > nCastRange - nRadius * 0.38
	then
		return J.GetLocationTowardDistanceLocation( bot, nFutureLoc, nCastRange +8 )
	end

	return nFutureLoc

end


function J.GetOne( number )

	return math.floor( number * 10 ) / 10

end


function J.GetTwo( number )

	return math.floor( number * 100 ) / 100

end


function J.SetQueueToInvisible( bot )

	if bot:IsAlive()
		and not bot:IsInvisible()
		and not bot:HasModifier( "modifier_item_dustofappearance" )
	then
		local enemyTowerList = bot:GetNearbyTowers( 888, true )

		if enemyTowerList[1] ~= nil then return end

		local itemAmulet = J.IsItemAvailable( 'item_shadow_amulet' )
		if itemAmulet ~= nil
			and itemAmulet:IsFullyCastable()
		then
			bot:ActionQueue_UseAbilityOnEntity( itemAmulet, bot )
			return
		end
	
		local itemGlimer = J.IsItemAvailable( 'item_glimmer_cape' )
		if itemGlimer ~= nil and itemGlimer:IsFullyCastable()
		then
			bot:ActionQueue_UseAbilityOnEntity( itemGlimer, bot )
			return
		end

		local itemInvisSword = J.IsItemAvailable( 'item_invis_sword' )
		if itemInvisSword ~= nil and itemInvisSword:IsFullyCastable()
		then
			bot:ActionQueue_UseAbility( itemInvisSword )
			return
		end

		local itemSilverEdge = J.IsItemAvailable( 'item_silver_edge' )
		if itemSilverEdge ~= nil and itemSilverEdge:IsFullyCastable()
		then
			bot:ActionQueue_UseAbility( itemSilverEdge )
			return
		end

	end


end


function J.SetQueueSwitchPtToINT( bot )

	local pt = J.IsItemAvailable( "item_power_treads" )
	if pt ~= nil and pt:IsFullyCastable()
	then
		if pt:GetPowerTreadsStat() == ATTRIBUTE_INTELLECT
		then
			bot:ActionQueue_UseAbility( pt )
			bot:ActionQueue_UseAbility( pt )
			return
		elseif pt:GetPowerTreadsStat() == ATTRIBUTE_STRENGTH
			then
				bot:ActionQueue_UseAbility( pt )
				return
		end
	end

end


function J.SetQueueUseSoulRing( bot )

	local sr = J.IsItemAvailable( "item_soul_ring" )

	if sr ~= nil and sr:IsFullyCastable()
	then
		local nEnemyCount = J.GetEnemyCount( bot, 1600 )
		local botHP = J.GetHP( bot )
		local botMP = J.GetMP( bot )
		if botHP > 0.35 + 0.1 * nEnemyCount
			and botMP < 0.99 - 0.1 * nEnemyCount
			and ( nEnemyCount <= 2 or botHP > botMP * 2.5 )
		then
			bot:ActionQueue_UseAbility( sr )
			return
		end
	end

end


function J.SetQueuePtToINT( bot, bSoulRingUsed )

	bot:Action_ClearActions(false)

	if bSoulRingUsed then J.SetQueueUseSoulRing( bot ) end

	if not J.IsPTReady( bot, ATTRIBUTE_INTELLECT )
	then
		J.SetQueueSwitchPtToINT( bot )
	end

end

-- 动力鞋/假腿状态
function J.IsPTReady( bot, status )

	if not bot:IsAlive()
		or bot:IsMuted()
		or bot:IsChanneling()
		or bot:IsInvisible()
		or bot:GetHealth() / bot:GetMaxHealth() < 0.2
	then
		return true
	end

	if status == ATTRIBUTE_INTELLECT
	then
		status = ATTRIBUTE_AGILITY
	elseif status == ATTRIBUTE_AGILITY
		then
			status = ATTRIBUTE_INTELLECT
	end

	local pt = J.IsItemAvailable( "item_power_treads" )
	if pt ~= nil and pt:IsFullyCastable()
	then
		if pt:GetPowerTreadsStat() ~= status
		then
			return false
		end
	end

	return true

end


function J.ShouldSwitchPTStat( bot, pt )

	local ptStatus = pt:GetPowerTreadsStat()
	local botAttribute = bot:GetPrimaryAttribute()
	
	
	if ptStatus == ATTRIBUTE_INTELLECT
	then
		ptStatus = ATTRIBUTE_AGILITY
	elseif ptStatus == ATTRIBUTE_AGILITY
		then
			ptStatus = ATTRIBUTE_INTELLECT
	end
	
	if botAttribute ~= ATTRIBUTE_INTELLECT
		and botAttribute ~= ATTRIBUTE_STRENGTH
		and botAttribute ~= ATTRIBUTE_AGILITY
	then
		return ptStatus ~= ATTRIBUTE_STRENGTH
	end

	return botAttribute ~= ptStatus

end


function J.IsOtherAllysTarget( unit )

	local bot = GetBot()
	local hAllyList = J.GetNearbyHeroes(bot, 800, false, BOT_MODE_NONE )

	if #hAllyList <= 1 then return false end

	for _, ally in pairs( hAllyList )
	do
		if J.IsValid( ally )
			and ally ~= bot
			and not ally:IsIllusion()
			and ( J.GetProperTarget( ally ) == unit
					or ( not ally:IsBot() and ally:IsFacingLocation( unit:GetLocation(), 20 ) ) )
		then
			return true
		end
	end

	return false

end


function J.IsAllysTarget( unit )

	local bot = GetBot()
	local hAllyList = J.GetNearbyHeroes(bot, 800, false, BOT_MODE_NONE )

	for _, ally in pairs( hAllyList )
	do
		if J.IsValid( ally )
			and not ally:IsIllusion()
			and ( J.GetProperTarget( ally ) == unit
					or ( not ally:IsBot() and ally:IsFacingLocation( unit:GetLocation(), 12 ) ) )
		then
			return true
		end
	end

	return false

end

function J.ToNearest500(num)
    return math.floor(num / 500 + 0.5) * 500
end

--RoundToNearestThousand
function J.ToNearest1000(num)
    return math.floor(num / 1000 + 0.5) * 1000
end

function J.IsKeyWordUnit( keyWord, uUnit )

	if string.find( uUnit:GetUnitName(), keyWord ) ~= nil
	then
		return true
	end

	return false
end


function J.IsHumanPlayer( nUnit )

	return not nUnit:IsBot() -- or IsPlayerBot( nUnit:GetPlayerID() )

end


function J.IsValid( nTarget )
	return nTarget ~= nil
			and not nTarget:IsNull()
			and nTarget:CanBeSeen()
			and nTarget:IsAlive()
			and not nTarget:IsBuilding()
end

function J.IsValidTarget(nTarget)
	-- NOTE: return J.Utils.IsValidUnit(nTarget) -- ideally it should be IsValidUnit, but a lot of legacy usage causing some problems.
	return J.Utils.IsValidHero(nTarget)
end

function J.IsValidHero( nTarget )
	return J.Utils.IsValidHero(nTarget)
end

function J.IsValidBuilding( nTarget )
	return J.Utils.IsValidBuilding(nTarget)
end

function J.IsRoshan( nTarget )

	return nTarget ~= nil
			and not nTarget:IsNull()
			and nTarget:CanBeSeen()
			and nTarget:IsAlive()
			and string.find( nTarget:GetUnitName(), "roshan" ) ~= nil

end


function J.IsMoving( bot )

	if not bot:IsAlive() then return false end

	local vLocation = bot:GetExtrapolatedLocation( 0.6 )
	if GetUnitToLocationDistance( bot, vLocation ) > bot:GetCurrentMovementSpeed() * 0.45
	then
		return true
	end

	return false

end


function J.IsRunning( bot )

	if not bot:IsAlive() then return false end

	return bot:GetAnimActivity() == ACTIVITY_RUN

end


function J.IsAttacking( bot )

	local nAnimActivity = bot:GetAnimActivity()

	if nAnimActivity ~= ACTIVITY_ATTACK
		and nAnimActivity ~= ACTIVITY_ATTACK2
	then
		return false
	end

	if bot:GetAttackPoint() > bot:GetAnimCycle() * 0.99
	then
		return true
	end

	return false
end


function J.IsChasingTarget( bot, nTarget )

	if not J.IsValid(bot) or not J.IsValid(nTarget) then return false end

	if J.IsRunning( bot )
		and J.IsRunning( nTarget )
		and bot:IsFacingLocation( nTarget:GetLocation(), 20 )
		and not nTarget:IsFacingLocation( bot:GetLocation(), 150 )
	then
		return true
	end

	return false

end


function J.IsRealInvisible( bot )

	local enemyTowerList = bot:GetNearbyTowers( 880, true )

	if bot:IsInvisible()
		and not bot:HasModifier( 'modifier_item_dustofappearance' )
		and not bot:HasModifier( 'modifier_bloodseeker_thirst_vision' )
		and not bot:HasModifier( 'modifier_slardar_amplify_damage' )
		and not bot:HasModifier( 'modifier_sniper_assassinate' )
		and not bot:HasModifier( 'modifier_bounty_hunter_track' )
		and not bot:HasModifier( 'modifier_faceless_void_chronosphere_freeze' )
		and #enemyTowerList == 0
	then
		return true
	end


	return false

end


function J.GetModifierTime( bot, sModifierName )

	if not bot:HasModifier( sModifierName ) then return 0 end

	local npcModifier = bot:NumModifiers()
	for i = 0, npcModifier
	do
		if bot:GetModifierName( i ) == sModifierName
		then
			return bot:GetModifierRemainingDuration( i )
		end
	end

	return 0

end


function J.GetModifierCount( bot, sModifierName )

	if not bot:HasModifier( sModifierName ) then return 0 end

	local npcModifier = bot:NumModifiers()
	for i = 0, npcModifier
	do
		if bot:GetModifierName( i ) == sModifierName
		then
			return bot:GetModifierStackCount( i )
		end
	end

	return 0

end


function J.GetUniqueModifierCount( bot, sModifierName )

	if not bot:HasModifier( sModifierName ) then return 0 end

	local count = 0
	local npcModifier = bot:NumModifiers()
	for i = 0, npcModifier
	do
		if bot:GetModifierName( i ) == sModifierName
		then
			count = count + 1
		end
	end

	return count

end



function J.GetRemainStunTime( bot )

	if not bot:HasModifier( "modifier_stunned" ) then return 0 end

	local npcModifier = bot:NumModifiers()
	for i = 0, npcModifier
	do
		if bot:GetModifierName( i ) == "modifier_stunned"
		then
			return bot:GetModifierRemainingDuration( i )
		end
	end

	return 0

end


function J.IsTeamActivityCount( bot, nCount )

	local numPlayer = GetTeamPlayers( GetTeam() )
	for i = 1, #numPlayer
	do
		local member = GetTeamMember( i )
		if member ~= nil and member:IsAlive()
		then
			if J.GetAllyCount( member, 1600 ) >= nCount
			then
				return true
			end
		end
	end

	return false

end


function J.GetSpecialModeAllies( bot, nDistance, nMode )

	local allyList = {}
	local numPlayer = GetTeamPlayers( GetTeam() )
	for i = 1, #numPlayer
	do
		local member = GetTeamMember( i )
		if member ~= nil and member:IsAlive()
		then
			if member:GetActiveMode() == nMode
				and GetUnitToUnitDistance( member, bot ) <= nDistance
			then
				table.insert( allyList, member )
			end
		end
	end

	return allyList

end


function J.GetSpecialModeAlliesCount( nMode )

	local allyList = J.GetSpecialModeAllies( GetBot(), 99999, nMode )

	return #allyList

end


function J.GetTeamFightLocation( bot )

	local team = GetTeam()

	-- local res = J.Utils.GetCachedVars('GetTeamFightLocation'..tostring(team), 0.5)
	-- if res ~= nil then return res end

	local targetLocation = nil
	local numPlayer = GetTeamPlayers( team )

	for i = 1, #numPlayer
	do
		local member = GetTeamMember( i )
		if member ~= nil and member:IsAlive()
			and J.IsInTeamFight( member, 1500 )
			and J.GetEnemyCount( member, 1400 ) >= 2
		then
			local allyList = J.GetSpecialModeAllies( member, 1400, BOT_MODE_ATTACK )
			if #allyList > 0 then
				targetLocation = J.GetCenterOfUnits( allyList )
				break
			end
		end
	end

	-- J.Utils.SetCachedVars('GetTeamFightLocation', targetLocation)
	return targetLocation

end


-- Unlike a broad mode label, verify that the group at the destination is
-- actually still exchanging attacks and has somebody who can survive until TP.
function J.CanJoinObservedFightByTeleport(bot, location)
    local foes = J.GetEnemiesNearLoc(location, 1150)
    if #foes < 2 then return false end
    for _, ally in ipairs(J.GetAlliesNearLoc(location, 1050)) do
        if ally ~= bot and J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally)
            and J.GetHP(ally) >= 0.45 and not J.IsRetreating(ally) and not J.IsDisabled(ally)
            and not ally:HasModifier('modifier_teleporting') then
            for _, foe in ipairs(foes) do
                if (ally:GetAttackTarget() == foe or foe:GetAttackTarget() == ally
                    and ally:WasRecentlyDamagedByHero(foe, 2))
                    and J.IsInRange(ally, foe, math.max(750, ally:GetAttackRange() + 200)) then return true end
            end
        end
    end
    return false
end

function J.GetTeamFightAlliesCount( bot )

	local numPlayer = GetTeamPlayers( GetTeam() )
	local nCount = 0
	for i = 1, #numPlayer
	do
		local member = GetTeamMember( i )
		if member ~= nil and member:IsAlive()
			and J.IsInTeamFight( member, 1200 )
			and J.GetEnemyCount( member, 1400 ) >= 2
		then
			nCount = J.GetSpecialModeAlliesCount( BOT_MODE_ATTACK )
			break
		end
	end

	return nCount

end


function J.GetCenterOfUnits( nUnits )

	if #nUnits == 0
	then
		return Vector( 0.0, 0.0 )
	end

	local sum = Vector( 0.0, 0.0 )
	local num = 0

	for _, unit in pairs( nUnits )
	do
		if J.IsValid(unit)
		then
			sum = sum + unit:GetLocation()
			num = num + 1
		end
	end

	if num == 0 then return Vector( 0.0, 0.0 ) end

	return sum / num

end

function J.GetMostFarmLaneDesire(bot)

	local nTopDesire = GetFarmLaneDesire( LANE_TOP )
	local nMidDesire = GetFarmLaneDesire( LANE_MID )
	local nBotDesire = GetFarmLaneDesire( LANE_BOT )

	if nTopDesire > nMidDesire and nTopDesire > nBotDesire
	then
		return LANE_TOP, nTopDesire
	end

	if nBotDesire > nMidDesire and nBotDesire > nTopDesire
	then
		return LANE_BOT, nBotDesire
	end

	if DotaTime() < 8 * 60 then
		return bot:GetAssignedLane(), 0.667
	end

	return LANE_MID, nMidDesire

end


function J.GetMostDefendLaneDesire()

	local nTopDesire = J.GetDefendLaneDesire( LANE_TOP )
	local nMidDesire = J.GetDefendLaneDesire( LANE_MID )
	local nBotDesire = J.GetDefendLaneDesire( LANE_BOT )

	if nMidDesire > nTopDesire and nMidDesire > nBotDesire then
		return LANE_MID, nMidDesire
	end

	if nTopDesire > nMidDesire and nTopDesire > nBotDesire
	then
		return LANE_TOP, nTopDesire
	end

	if nBotDesire > nMidDesire and nBotDesire > nTopDesire
	then
		return LANE_BOT, nBotDesire
	end

	return LANE_MID, nMidDesire

end

function J.GetDefendLaneDesire(lane)
	local defaultDefDesire, newDefDesire = GetDefendLaneDesire(lane), GetBot().DefendLaneDesire
	if newDefDesire ~= nil and newDefDesire[lane] > defaultDefDesire
	then
		return newDefDesire[lane]
	end
	return defaultDefDesire
end

function J.IsT3TowerDown(team, lane)
	local t3 = {
		[LANE_TOP] = TOWER_TOP_3,
		[LANE_MID] = TOWER_MID_3,
		[LANE_BOT] = TOWER_BOT_3,
	}

	return GetTower(team, t3[lane]) == nil
end

function J.IsPingCloseToValidTower(nTeam, ping, nRadius, fInterval)
	if ping and ping.location then
		local unitList = UNIT_LIST_ALLIED_BUILDINGS
		if nTeam == GetOpposingTeam() then
			unitList = UNIT_LIST_ENEMY_BUILDINGS
		end
		for _, unit in pairs(GetUnitList(unitList)) do
			if unit ~= nil
			and unit:IsAlive()
			and unit:CanBeSeen()
			and not unit:IsInvulnerable()
			and not unit:HasModifier('modifier_backdoor_protection')
			and not unit:HasModifier('modifier_backdoor_protection_in_base')
			and not unit:HasModifier('modifier_backdoor_protection_active')
			and not string.find(unit:GetUnitName(), 'fillers')
			then
				local sUnitName = unit:GetUnitName()
				if J.GetDistance(unit:GetLocation(), ping.location) <= nRadius and GameTime() < ping.time + fInterval then
					local nLane = LANE_MID
					if string.find(sUnitName, '_fort') then
						nLane = LANE_MID
					elseif string.find(sUnitName, '_top') then
						nLane = LANE_TOP
					elseif string.find(sUnitName, '_mid') then
						nLane = LANE_MID
					elseif string.find(sUnitName, '_bot') then
						nLane = LANE_BOT
					end
					return true, nLane
				end
			end
		end
	end

	return false, -1
end


function J.IsRoshanCloseToChangingSides()
    return DotaTime() % 300 >= 300 - 30
end

function J.GetMostPushLaneDesire()

	local nTopDesire = GetPushLaneDesire( LANE_TOP )
	local nMidDesire = GetPushLaneDesire( LANE_MID )
	local nBotDesire = GetPushLaneDesire( LANE_BOT )

	if nTopDesire > nMidDesire and nTopDesire > nBotDesire
	then
		return LANE_TOP, nTopDesire
	end

	if nBotDesire > nMidDesire and nBotDesire > nTopDesire
	then
		return LANE_BOT, nBotDesire
	end

	return LANE_MID, nMidDesire

end

function J.GetClosestAlly(bot, nRadius, coreOnly)
	local closest, closestDistance = nil, nRadius
	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember(i)

		if J.IsValidHero(member)
		and member ~= bot
		and (not coreOnly or J.IsCore(member))
		and not J.IsSuspiciousIllusion(member)
		then
			local distance = GetUnitToUnitDistance(bot, member)
			if distance <= closestDistance then
				closest, closestDistance = member, distance
			end
		end
	end

	return closest
end

function J.GetNearestLaneFrontLocation( nUnitLoc, bEnemy, fDeltaFromFront )

	local nTeam = GetTeam()
	if bEnemy then nTeam = GetOpposingTeam() end

	local nTopLoc = GetLaneFrontLocation( nTeam, LANE_TOP, fDeltaFromFront )
	local nMidLoc = GetLaneFrontLocation( nTeam, LANE_MID, fDeltaFromFront )
	local nBotLoc = GetLaneFrontLocation( nTeam, LANE_BOT, fDeltaFromFront )

	local nTopDist = J.GetLocationToLocationDistance( nUnitLoc, nTopLoc )
	local nMidDist = J.GetLocationToLocationDistance( nUnitLoc, nMidLoc )
	local nBotDist = J.GetLocationToLocationDistance( nUnitLoc, nBotLoc )

	if nTopDist < nMidDist and nTopDist < nBotDist
	then
		return nTopLoc
	end

	if nBotDist < nMidDist and nBotDist < nTopDist
	then
		return nBotLoc
	end

	return nMidLoc

end

function J.GetAttackableWeakestUnit( bot, nRadius, bHero, bEnemy )
    local unitList = {}
	if nRadius > 1600 then nRadius = 1600 end
    if bHero then
        unitList = J.GetNearbyHeroes(bot, nRadius, bEnemy, BOT_MODE_NONE )
    else
        unitList = bot:GetNearbyLaneCreeps( nRadius, bEnemy )
    end
    return J.GetAttackableWeakestUnitFromList( bot, unitList )
end

-- The arg `bot` here can be nil
function J.GetAttackableWeakestUnitFromList( bot, unitList )
	if bot == nil then bot = GetBot() end

    local weakest = nil
    local bestScore = math.huge
	local attackRange = bot:GetAttackRange()

    for _, unit in pairs( unitList ) do
		if J.IsValidTarget(unit) then
			local hp = unit:GetHealth()
			local offensivePower = 0
			local distance = GetUnitToUnitDistance(bot, unit)
			if J.IsValidHero(unit) then
				offensivePower = unit:GetRawOffensivePower()
			end
			if J.IsValid( unit )
				and not unit:IsAttackImmune()
				and not unit:IsInvulnerable()
				and not J.HasForbiddenModifier( unit )
				and not J.IsSuspiciousIllusion( unit )
				--and not J.IsAllyCanKill( unit )
				and not J.CannotBeKilled(bot, unit)
			then
				-- Calculate score: lower score is better
				-- Can adjust the weight factors for hp and offensive power to tune the behavior
				local hpWeight = 0.7
				local powerWeight = 0.3
				local score = (hp * hpWeight) - (offensivePower * powerWeight) -- - math.min(1, attackRange / distance) * 100
	
				-- If the new score is lower, choose this unit as the weakest
				if score < bestScore then
					bestScore = score
					weakest = unit
				end
			end
		end
    end

    return weakest
end

function J.CannotBeKilled(bot, botTarget)
	return J.IsValidHero( botTarget )
	and (
		(J.GetModifierTime(botTarget, 'modifier_dazzle_shallow_grave') > 0.6 and J.GetHP(botTarget) < 0.15 and (bot == nil or bot:GetUnitName() ~= "npc_dota_hero_axe"))
		or J.GetModifierTime(botTarget, 'modifier_oracle_false_promise_timer') > 0.6
		or botTarget:HasModifier('modifier_skeleton_king_reincarnation_scepter_active')
		or botTarget:HasModifier('modifier_item_helm_of_the_undying_active')
		or botTarget:HasModifier('modifier_item_aeon_disk_buff')
		or botTarget:HasModifier('modifier_abaddon_borrowed_time')
	)
end

function J.CanIgnoreLowHp(bot)
	return J.GetModifierTime(bot, 'modifier_dazzle_shallow_grave') > 0.6
	or J.GetModifierTime(bot, 'modifier_oracle_false_promise_timer') > 0.6
end

-- Per-bot chase fatigue tracking.
-- NOTE: Each bot runs in its own Lua sandbox, so module-level state is per-bot only.
-- Cross-bot coordination uses Valve API (GetAttackTarget, GetActiveMode) not shared Lua state.

-- Score an enemy for target prioritization. Higher score = better target.
-- Uses Valve API for cross-bot coordination (ally:GetAttackTarget()).
-- Per-bot state (chase fatigue) stored on bot handle to survive across ticks.
function J.ScoreEnemyTarget(bot, enemy, alliesNearby)
	if not J.IsValidHero(enemy) or not J.CanBeAttacked(enemy) or J.IsSuspiciousIllusion(enemy) then
		return -1
	end
	if J.CannotBeKilled(bot, enemy) then return -1 end
	if J.HasForbiddenModifier(enemy) then return -1 end

	-- Skip enemies in dangerous defensive states
	if enemy:HasModifier('modifier_abaddon_borrowed_time')
	or enemy:HasModifier('modifier_item_aeon_disk_buff')
	or enemy:HasModifier('modifier_ursa_enrage')
	or enemy:HasModifier('modifier_troll_warlord_battle_trance')
	or enemy:HasModifier('modifier_winter_wyvern_cold_embrace')
	then
		return -1
	end

	local score = 0
	local dist = GetUnitToUnitDistance(bot, enemy)
	local enemyHP = J.GetHP(enemy)

	-- 1. Killability: low HP enemies are highest priority
	score = score + (1 - enemyHP) * 50

	-- 2. Offensive threat: dangerous enemies should be dealt with
	local offPower = enemy:GetRawOffensivePower()
	score = score + math.min(offPower / 100, 20)

	-- 3. Distance penalty: prefer closer targets
	score = score - (dist / 200)

	-- 4. Ally focus bonus: query Valve API for what allies are attacking (works cross-sandbox)
	local allyAttackingCount = 0
	if alliesNearby then
		for _, ally in pairs(alliesNearby) do
			if J.IsValidHero(ally) and ally ~= bot then
				local allyTarget = ally:GetAttackTarget()
				if allyTarget == enemy then
					allyAttackingCount = allyAttackingCount + 1
				end
			end
		end
	end
	score = score + allyAttackingCount * 12

	-- 5. Core/support priority: prefer killing supports (squishier, high-value disables)
	--    but also weight high-threat cores that are low HP
	if J.IsCore(enemy) then
		score = score + 5  -- slight bonus for removing core damage
	else
		score = score + 8  -- supports are easier kills, remove their disables
	end

	-- 6. Chase fatigue: per-bot tracking stored on bot handle
	if bot._chaseFatigue == nil then bot._chaseFatigue = {} end
	local enemyID = enemy:GetPlayerID()
	if enemyID and bot._chaseFatigue[enemyID] then
		local fatigue = bot._chaseFatigue[enemyID]
		local chaseDuration = DotaTime() - fatigue.startTime
		-- If chasing for over 4 seconds and enemy HP hasn't dropped much, apply penalty
		if chaseDuration > 4 and enemyHP > 0.5 then
			score = score - chaseDuration * 2
		end
		-- If enemy is moving away (distance increasing), more penalty
		if fatigue.lastDist and dist > fatigue.lastDist + 50 then
			score = score - 8
		end
	end

	-- 7. Bonus if enemy is dealing damage to us — don't ignore threats hitting us
	if bot:WasRecentlyDamagedByHero(enemy, 2.0) then
		score = score + 18
	end

	-- 8. Blade mail penalty
	if J.GetModifierTime(enemy, "modifier_item_blade_mail_reflect") > 0.2 then
		score = score - 30
	end

	return score
end

-- Pick the best target for coordinated focus. Returns the best enemy to attack, or nil.
-- Cross-bot coordination happens naturally: all bots running the same scoring algorithm
-- with the same Valve API inputs (ally:GetAttackTarget()) will converge on the same target.
function J.GetBestTeamTarget(bot, enemyHeroes, allyHeroes)
	if not enemyHeroes or #enemyHeroes == 0 then return nil end

	local bestTarget = nil
	local bestScore = -999

	for _, enemy in pairs(enemyHeroes) do
		local score = J.ScoreEnemyTarget(bot, enemy, allyHeroes)
		if score > bestScore then
			bestScore = score
			bestTarget = enemy
		end
	end

	-- Update per-bot chase fatigue tracking
	if bot._chaseFatigue == nil then bot._chaseFatigue = {} end
	if bestTarget then
		local targetID = bestTarget:GetPlayerID()
		if targetID then
			local dist = GetUnitToUnitDistance(bot, bestTarget)
			if not bot._chaseFatigue[targetID] then
				bot._chaseFatigue[targetID] = { startTime = DotaTime(), lastDist = dist }
			else
				bot._chaseFatigue[targetID].lastDist = dist
			end
		end
	end

	-- Clean up stale fatigue entries
	for id, fatigue in pairs(bot._chaseFatigue) do
		if DotaTime() - fatigue.startTime > 10 then
			bot._chaseFatigue[id] = nil
		end
	end

	return bestTarget
end

function J.CanBeAttacked( unit )
	return  unit ~= nil
			and not J.HasForbiddenModifier( unit )
			and unit:IsAlive()
			and unit:CanBeSeen()
			and not unit:IsNull()
			and not unit:IsAttackImmune()
			and not unit:IsInvulnerable()
			and not unit:HasModifier("modifier_fountain_glyph")
			and not unit:HasModifier("modifier_omninight_guardian_angel")
			and not unit:HasModifier("modifier_winter_wyvern_cold_embrace")
			and not unit:HasModifier("modifier_dark_willow_shadow_realm_buff")
			and not unit:HasModifier("modifier_ringmaster_the_box_buff")
			and not unit:HasModifier("modifier_dazzle_nothl_projection_soul_debuff")
			and (unit:GetTeam() == GetTeam() 
					or not unit:HasModifier("modifier_crystal_maiden_frostbite") )
			and (unit:GetTeam() ~= GetTeam() 
			     or ( unit:GetUnitName() ~= "npc_dota_wraith_king_skeleton_warrior" 
					  and unit:GetHealth()/unit:GetMaxHealth() < 0.5 ) )
end


function J.GetHP( unit )
	local nCurHealth = unit:GetHealth()
    local nMaxHealth = unit:GetMaxHealth()
	if GetTeam() == unit:GetTeam() then
		nCurHealth = unit:OriginalGetHealth()
		nMaxHealth = unit:OriginalGetMaxHealth()
	end
	if nCurHealth <= 0 then return 0 end
	return nCurHealth / nMaxHealth
end

function J.GetEffectiveHP( bot )
	if not J.IsValid(bot) then return 0 end

	local nCurHealth = bot:GetHealth()
	if nCurHealth <= 0 then return 0 end

	if bot:GetUnitName() == 'npc_dota_hero_medusa'
    then
		local mana = bot:GetMana()
		-- Assuming max level Mana Shield (95% absorption and 2.5 damage absorbed per point of mana)
		local manaAbsorptionRate = 0.95
		local damagePerMana = 2.6
		-- Calculate how much damage her current mana can absorb
		local manaEffectiveHP = mana * damagePerMana * manaAbsorptionRate
		-- Effective HP is her base HP plus the effective HP from her mana shield
		nCurHealth = nCurHealth + manaEffectiveHP
    end

	return nCurHealth
end


function J.GetMP( bot )
	if bot:GetUnitName() == 'npc_dota_hero_huskar' then
		return bot:GetHealth() / bot:GetMaxHealth()
	end
	return bot:GetMana() / bot:GetMaxMana()
end


function J.GetAllyList( bot, nRadius )

	if nRadius > 1600 then nRadius = 1600 end

	local nRealAllyList = {}
	local nCandidate = J.GetNearbyHeroes(bot, nRadius, false, BOT_MODE_NONE )
	if #nCandidate <= 1 then return nCandidate end

	for _, ally in pairs( nCandidate )
	do
		if ally ~= nil and ally:IsAlive()
			and not ally:IsIllusion()
		then
			table.insert( nRealAllyList, ally )
		end
	end

	return nRealAllyList

end


function J.GetAllyCount( bot, nRadius )

	local nRealAllyList = J.GetAllyList( bot, nRadius )

	return #nRealAllyList

end


function J.GetAroundEnemyHeroList( nRadius )

	if nRadius > 1600 then nRadius = 1600 end

	return J.GetNearbyHeroes(GetBot(), nRadius, true, BOT_MODE_NONE )

end


function J.GetAroundCreepList( nRadius, bEnemy, bNeutral, bLaneCreep )

	local bot = GetBot()
	if nRadius > 1600 then nRadius = 1600 end
	local creepList = {}

	if bNeutral
	then
		creepList = bot:GetNearbyNeutralCreeps( nRadius )
	elseif bLaneCreep
	then
		creepList = bot:GetNearbyLaneCreeps( nRadius, bEnemy )
	else
		creepList = bot:GetNearbyCreeps( nRadius, bEnemy )
	end

	return creepList

end


function J.GetAroundBuildingList( nRadius, bEnemy, bTower, bShrine, bFiller, bBarrack, bAcient )

	local bot = GetBot()
	if nRadius > 1600 then nRadius = 1600 end
	local buildingList = {}

	-- GetNearbyBarracks( nRadius, bEnemies )
	-- GetNearbyTowers( nRadius, bEnemies )
	-- GetNearbyShrines( nRadius, bEnemies )
	-- GetNearbyFillers( nRadius, bEnemies )
	-- GetAncient( nTeam )

	return buildingList

end


function J.GetEnemyList( bot, nRadius )

	if nRadius > 1600 then nRadius = 1600 end
	local nRealEnemyList = {}
	local nCandidate = J.GetNearbyHeroes(bot, nRadius, true, BOT_MODE_NONE )
	if nCandidate[1] == nil then return nCandidate end

	for _, enemy in pairs( nCandidate )
	do
		if enemy ~= nil and type(enemy) == "table" and enemy:IsAlive()
			and not J.IsSuspiciousIllusion( enemy )
		then
			table.insert( nRealEnemyList, enemy )
		end
	end

	return nRealEnemyList

end


function J.GetEnemyCount( bot, nRadius )

	local nRealEnemyList = J.GetEnemyList( bot, nRadius )

	return #nRealEnemyList

end

function J.ConsiderTarget()

	local bot = GetBot()

	if not J.IsRunning( bot )
		or bot:HasModifier( "modifier_item_hurricane_pike_range" )
	then return end

	local npcTarget = J.GetProperTarget( bot )
	if not J.IsValidHero( npcTarget ) then return end

	local nAttackRange = bot:GetAttackRange() + 69
	if nAttackRange > 1600 then nAttackRange = 1600 end
	if nAttackRange < 300 then nAttackRange = 350 end

	local nInAttackRangeWeakestEnemyHero = J.GetAttackableWeakestUnit( bot, nAttackRange, true, true )

	if J.IsValidHero( nInAttackRangeWeakestEnemyHero )
		and ( GetUnitToUnitDistance( npcTarget, bot ) > nAttackRange or J.HasForbiddenModifier( npcTarget ) )
	then
		bot:SetTarget( nInAttackRangeWeakestEnemyHero )
		return
	end

end


function J.IsHaveAegis( bot )
	return bot:FindItemSlot( "item_aegis" ) >= 0
end

function J.DoesTeamHaveAegis()
	-- local cacheKey = tostring(GetTeam())
	-- local res = J.Utils.GetCachedVars('DoesTeamHaveAegis'..cacheKey, 1)
	-- if res ~= nil then return res end

	local numPlayer = GetTeamPlayers( GetTeam() )
	for i = 1, #numPlayer
	do
		local member = GetTeamMember(i)
		if J.IsValidHero(member)
		and J.IsHaveAegis(member)
		then
			-- J.Utils.SetCachedVars('DoesTeamHaveAegis'..cacheKey, true)
			return true
		end
	end

	-- J.Utils.SetCachedVars('DoesTeamHaveAegis'..cacheKey, false)
	return false
end


function J.GetCoresAverageNetworth()
	-- local cacheKey = 'GetCoresAverageNetworth'..tostring(GetTeam())
	-- local cache = J.Utils.GetCachedVars(cacheKey, 2)
	-- if cache ~= nil then return cache end

	local totalNetWorth = 0
	local coreCount = 0
	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember(i)
		if J.IsValidHero(member)
		and J.IsCore(member)
		then
			totalNetWorth = totalNetWorth + member:GetNetWorth()
			coreCount = coreCount + 1
		end
	end

	local res = totalNetWorth / coreCount
	-- J.Utils.SetCachedVars(cacheKey, res)
	return res
end

function J.GetCoresMaxNetworth()
	local cacheKey = 'GetCoresMaxNetworth'..tostring(GetTeam())
	-- local cache = J.Utils.GetCachedVars(cacheKey, 2)
	if cache ~= nil then return cache end

	local maxNetWorth = 0
	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember(i)
		if J.IsValidHero(member)
		and J.IsCore(member) then
			local networth = member:GetNetWorth()
			if networth > maxNetWorth
			then
				maxNetWorth = networth
			end
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, maxNetWorth)
	return maxNetWorth
end

function J.IsLocHaveTower( nRadius, bEnemy, nLoc )

	local nTeam = GetTeam()
	if bEnemy then nTeam = GetOpposingTeam() end

	if ( not bEnemy and J.GetLocationToLocationDistance( nLoc, J.GetTeamFountain() ) < 2500 )
		or ( bEnemy and J.GetLocationToLocationDistance( nLoc, J.GetEnemyFountain() ) < 2500 )
	then
		return true
	end

	for i = 0, 10
	do
		local tower = GetTower( nTeam, i )
		if tower ~= nil and GetUnitToLocationDistance( tower, nLoc ) <= nRadius
		then
			 return true
		end
	end

	return false

end


function J.GetNearbyLocationToTp( nLoc )

	local nTeam = GetTeam()
	local nFountain = J.GetTeamFountain()

	if J.GetLocationToLocationDistance( nLoc, nFountain ) <= 2500
	then
		return nLoc
	end

	local targetTower = nil
	local minDist = 99999
	for i=0, 10, 1 do
		local tower = GetTower( nTeam, i )
		if tower ~= nil
			and GetUnitToLocationDistance( tower, nLoc ) < minDist
		then
			 targetTower = tower
			 minDist = GetUnitToLocationDistance( tower, nLoc )
		end
	end

	local watchTowerList = J.Site.GetAllWatchTower()
	for _, watchTower in pairs( watchTowerList )
	do
		if watchTower ~= nil
			and watchTower:GetTeam() == nTeam
			and GetUnitToLocationDistance( watchTower, nLoc ) < minDist - 1300
			and ( not J.IsEnemyHeroAroundLocation( watchTower:GetLocation(), 600 )
					or J.IsAllyHeroAroundLocation( watchTower:GetLocation(), 600 ) )
		then
			 targetTower = watchTower
			 minDist = GetUnitToLocationDistance( watchTower, nLoc ) + 1300
		end
	end

	if targetTower ~= nil
	then
		return J.GetLocationTowardDistanceLocation( targetTower, nLoc, 575 )
	end

	return nFountain

end


function J.IsEnemyFacingUnit( bot, nRadius, nDegrees )

	local nLoc = bot:GetLocation()

	if nRadius > 1600 then nRadius = 1600 end
	local nEnemyHeroes = J.GetNearbyHeroes(bot, nRadius, true, BOT_MODE_NONE )
	for _, enemy in pairs( nEnemyHeroes )
	do
		if J.IsValid( enemy )
			and enemy:IsFacingLocation( nLoc, nDegrees )
		then
			return true
		end
	end

	return false

end


function J.IsAllyFacingUnit( bot, nRadius, nDegrees )

	local nLoc = bot:GetLocation()
	local numPlayer = GetTeamPlayers( GetTeam() )
	for i = 1, #numPlayer
	do
		local member = GetTeamMember( i )
		if member ~= nil
			and member ~= bot
			and GetUnitToUnitDistance( member, bot ) <= nRadius
			and member:IsFacingLocation( nLoc, nDegrees )
		then
			return true
		end
	end

	return false

end


function J.IsEnemyTargetUnit( nUnit, nRadius )

	if nRadius > 1600 then nRadius = 1600 end
	local nEnemyHeroes = J.GetNearbyHeroes(GetBot(), nRadius, true, BOT_MODE_NONE )
	for _, enemy in pairs( nEnemyHeroes )
	do
		if J.IsValid( enemy )
			and J.GetProperTarget( enemy ) == nUnit
		then
			return true
		end
	end

	return false

end


function J.IsCastingUltimateAbility( bot )

	if bot:CanBeSeen() and (bot:IsCastingAbility() or bot:IsUsingAbility())
	then
		local nAbility = bot:GetCurrentActiveAbility()
		if nAbility ~= nil
			and nAbility:IsUltimate()
		then
			return true
		end
	end

	return false

end


function J.IsInAllyArea( bot )

	local hAllyAcient = GetAncient( GetTeam() )
	local hEnemyAcient = GetAncient( GetOpposingTeam() )
	
	if GetUnitToUnitDistance( bot, hAllyAcient ) + 768 < GetUnitToUnitDistance( bot, hEnemyAcient )
	then
		return true
	end
	
	return false

end


function J.IsInEnemyArea( bot )

	local hAllyAcient = GetAncient( GetTeam() )
	local hEnemyAcient = GetAncient( GetOpposingTeam() )
	
	if GetUnitToUnitDistance( bot, hEnemyAcient ) + 1280 < GetUnitToUnitDistance( bot, hAllyAcient )
	then
		return true
	end
	
	return false

end


function J.IsAnyAllyHeroSurroundedByManyAllies()

	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local npcAlly = GetTeamMember( i )
		if npcAlly ~= nil
			and npcAlly:IsAlive()
			and #J.GetNearbyHeroes(npcAlly, 1600, false, BOT_MODE_NONE) >= 3
		then
			return true
		end
	end

	return false

end

function J.IsAllyHeroAroundLocation( vLoc, nRadius )

	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local npcAlly = GetTeamMember( i )
		if npcAlly ~= nil
			and npcAlly:IsAlive()
			and GetUnitToLocationDistance( npcAlly, vLoc ) <= nRadius
		then
			return true
		end
	end

	return false

end


function J.IsEnemyHeroAroundLocation( vLoc, nRadius )
	-- local cacheKey = 'IsEnemyHeroAroundLocation'..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))..'-'..tostring(nRadius)
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	for i, id in pairs( GetTeamPlayers( GetOpposingTeam() ) )
	do
		if IsHeroAlive( id ) then
			local info = GetHeroLastSeenInfo( id )
			if info ~= nil then
				local dInfo = info[1]
				if dInfo ~= nil
					and J.GetLocationToLocationDistance( vLoc, dInfo.location ) <= nRadius
					and dInfo.time_since_seen < 2.0
				then
					-- J.Utils.SetCachedVars(cacheKey, true)
					return true
				end
			end
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, false)
	return false

end

function J.GetLastSeenEnemiesNearLoc(vLoc, nRadius)
	-- local cacheKey = 'GetLastSeenEnemiesNearLoc'..tostring(nRadius) ..'-'..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	local enemies = {}

	for i, id in pairs( GetTeamPlayers( GetOpposingTeam() ) )
	do
		if IsHeroAlive( id ) then
			local info = GetHeroLastSeenInfo( id )
			if info ~= nil then
				local dInfo = info[1]
				if dInfo ~= nil
					and J.GetLocationToLocationDistance( vLoc, dInfo.location ) <= nRadius
					and dInfo.time_since_seen < 5.0
				then
					table.insert(enemies, id)
				end
			end
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, enemies)
	return enemies
end

function J.GetNumOfAliveHeroes( bEnemy )
	local count = 0
	local nTeam = GetTeam()
	if bEnemy then nTeam = GetOpposingTeam() end

	-- local cacheKey = 'GetNumOfAliveHeroes'..tostring(nTeam)
	-- local cache = J.Utils.GetCachedVars(cacheKey, 1)
	-- if cache ~= nil then return cache end

	for i, id in pairs( GetTeamPlayers( nTeam ) )
	do
		if IsHeroAlive( id )
		then
			count = count + 1
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, count)
	return count

end

function J.GetNumOfHeroesNearLocation( bEnemy, location, distance )
	local count = 0
	local heroList = bEnemy and GetUnitList( UNIT_LIST_ENEMY_HEROES ) or GetUnitList( UNIT_LIST_ALLIED_HEROES )
	for _, hero in pairs( heroList )
	do
		if hero ~= nil and hero:IsAlive() and hero:CanBeSeen() and GetUnitToLocationDistance(hero, location) <= distance then
			count = count + 1
		end
	end
	return count
end

function J.GetHeroesNearLocation( bEnemy, location, distance )
	local heroes = { }
	local heroList = bEnemy and GetUnitList( UNIT_LIST_ENEMY_HEROES ) or GetUnitList( UNIT_LIST_ALLIED_HEROES )
	for _, hero in pairs( heroList )
	do
		if hero ~= nil and hero:IsAlive() and hero:CanBeSeen() and GetUnitToLocationDistance(hero, location) <= distance then
			table.insert(heroes, hero)
		end
	end
	return heroes

end

function J.GetAverageLevel( bEnemy )
	local count = 0
	local sum = 0
	local nTeam = GetTeam()
	if bEnemy then nTeam = GetOpposingTeam() end

	-- local cacheKey = 'GetAverageLevel'..tostring(nTeam)
	-- local cache = J.Utils.GetCachedVars(cacheKey, 1)
	-- if cache ~= nil then return cache end

	for i, id in pairs( GetTeamPlayers( nTeam ) )
	do
		sum = sum + GetHeroLevel( id )
		count = count + 1
	end

	local res = sum / count

	-- J.Utils.SetCachedVars(cacheKey, res)
	return res

end

function J.GetNumOfTeamTotalKills( bEnemy )

	local count = 0
	local nTeam = GetOpposingTeam()
	if bEnemy then nTeam = GetTeam() end

	-- local cacheKey = 'GetNumOfTeamTotalKills'..tostring(nTeam)
	-- local cache = J.Utils.GetCachedVars(cacheKey, 1)
	-- if cache ~= nil then return cache end

	for i, id in pairs( GetTeamPlayers( nTeam ) )
	do
		count = count + GetHeroDeaths( id )
	end

	-- J.Utils.SetCachedVars(cacheKey, count)
	return count

end

function J.IsEarlyGame()
	if DotaTime() < (J.IsModeTurbo() and 8 * 60 or 15 * 60) then
		return true
	end
	return false
end

function J.IsMidGame()
	if DotaTime() > (J.IsModeTurbo() and 8 * 60 or 15 * 60) and DotaTime() < (J.IsModeTurbo() and 18 * 60 or 30 * 60) then
		return true
	end
	return false
end

function J.IsLateGame()
	if DotaTime() > (J.IsModeTurbo() and 18 * 60 or 30 * 60) then
		return true
	end
	return false
end

function J.DotProduct(A, B)
	return A.x * B.x + A.y * B.y + A.z * B.z
end

function J.ConsiderForMkbDisassembleMask( bot )

	if bot.maskDismantleDone == nil then bot.maskDismantleDone = false end
	if bot.staffUnlockDone == nil then bot.staffUnlockDone = false end
	if bot.lifestealUnlockDone == nil then bot.lifestealUnlockDone = false end
	if bot.dismantleCheckTime == nil then bot.dismantleCheckTime = 600 end

	if bot.staffUnlockDone then return end

	if bot.dismantleCheckTime < DotaTime() + 1.0
	then
		bot.dismantleCheckTime = DotaTime()

		local mask	 = bot:FindItemSlot( "item_mask_of_madness" )
		local claymore = bot:FindItemSlot( "item_claymore" )
		local reaver	= bot:FindItemSlot( "item_reaver" )

		if not bot.maskDismantleDone
			and ( bot:GetItemInSlot( 6 ) == nil or bot:GetItemInSlot( 7 ) == nil or bot:GetItemInSlot( 8 ) == nil )
		then

			if mask >= 0 and mask <= 8
				and ( ( reaver >= 0 and reaver <= 8 ) or ( claymore >= 0 and claymore <= 8 ) )
				and ( bot:GetGold() >= 1400 or bot:GetStashValue() >= 1400 or bot:GetCourierValue() >= 1400 )
			then
				if bDebugMode then print( bot:GetUnitName().." mask Dismantle1" ) end
				bot.maskDismantleDone = true
				bot:ActionImmediate_DisassembleItem( bot:GetItemInSlot( mask ) )
				return
			end

			if mask >= 0 and mask <= 8
				and claymore >= 0 and reaver >= 0
			then
				if bDebugMode then print( bot:GetUnitName().." mask Dismantle2" ) end
				bot.maskDismantleDone = true
				bot:ActionImmediate_DisassembleItem( bot:GetItemInSlot( mask ) )
				return
			end
		end

		if not bot.maskDismantleDone then return end

		local lifesteal = bot:FindItemSlot( "item_lifesteal" )
		local staff = bot:FindItemSlot( "item_quarterstaff" )

		if lifesteal >= 0
			and not bot.lifestealUnlockDone
		then
			if bDebugMode then print( bot:GetUnitName().." lifestealUnlockDone" ) end
			bot.lifestealUnlockDone = true
			bot:ActionImmediate_SetItemCombineLock( bot:GetItemInSlot( lifesteal ), false )
			return
		end

		local satanic = bot:FindItemSlot( "item_satanic" )

		if satanic >= 0 and staff >= 0 and not bot.staffUnlockDone
		then
			if bDebugMode then print( bot:GetUnitName().." staffUnlockDone" ) end
			bot.staffUnlockDone = true
			bot:ActionImmediate_SetItemCombineLock( bot:GetItemInSlot( staff ), false )
			return
		end

	end
end


local LastActionTime = {}
function J.HasNotActionLast( nCD, nNumber )

	if LastActionTime[nNumber] == nil then LastActionTime[nNumber] = -90 end

	if DotaTime() > LastActionTime[nNumber] + nCD
	then
		LastActionTime[nNumber] = DotaTime()
		return true
	end

	return false

end


function J.GetCastDelay( bot, unit, nPointTime, nProjectSpeed )

	local nDist = GetUnitToUnitDistance( bot, unit )

	local nDistTime = 0
	if nProjectSpeed ~= 0 then nDistTime = nDist / nProjectSpeed end

	return nPointTime + nDistTime

end


function J.CanBreakTeleport( bot, unit, nPointTime, nProjectSpeed )

	if unit:HasModifier( "modifier_teleporting" )
	then
		return J.GetCastPoint( bot, unit, nPointTime, nProjectSpeed ) < J.GetModifierTime( unit, "modifier_teleporting" )
	end

	return true

end

-- NEWLY ADDED FUNCTIONS FOR NEW HEROES AND BEHAVIOUR

function J.CanBeCast(ability)
	return ability:IsTrained() and ability:IsFullyCastable() and ability:IsHidden() == false;
end

function J.CanSpamSpell(bot, manaCost)
	local initialRatio = 1.0;
	if manaCost < 100 then
		initialRatio = 0.6;
	end
	return ( bot:GetMana() - manaCost ) / bot:GetMaxMana() >= ( initialRatio - bot:GetLevel()/(3*30) );
end

local maxAddedRange = 200
local maxGetRange = 1600
function J.GetProperCastRange(bIgnore, hUnit, abilityCR)
	local attackRng = hUnit:GetAttackRange();
	if bIgnore then
		return abilityCR;
	elseif abilityCR <= attackRng then
		return attackRng + maxAddedRange;
	elseif abilityCR + maxAddedRange <= maxGetRange then
		return abilityCR + maxAddedRange;
	elseif abilityCR > maxGetRange then
		return maxGetRange;
	else
		return abilityCR;
	end
end

function J.GetLowestHPUnit(tUnits, bIgnoreImmune)
	local lowestHP   = 100000;
	local lowestUnit = nil; 
	for _,unit in pairs(tUnits)
	do
		local hp = unit:GetHealth()
		if hp < lowestHP and ( bIgnoreImmune or not unit:IsMagicImmune() ) then
			lowestHP   = hp;
			lowestUnit = unit;
		end
	end
	return lowestUnit;
end

local maxLevel = 30
function J.AllowedToSpam(bot, manaCost)
	return ( bot:GetMana() - manaCost ) / bot:GetMaxMana() >= ( 1.0 - bot:GetLevel()/(2*maxLevel) );
end

function J.CountVulnerableUnit(tUnits, locAOE, nRadius, nUnits)
	local count = 0;
	if locAOE.count >= nUnits then
		for _,unit in pairs(tUnits)
		do
			if GetUnitToLocationDistance(unit, locAOE.targetloc) <= nRadius and not unit:IsInvulnerable() then
				count = count + 1;
			end
		end
	end
	return count;
end

function J.GetProperLocation(hUnit, nDelay)
	if hUnit:GetMovementDirectionStability() >= 0.5 then
		return hUnit:GetExtrapolatedLocation(nDelay);
	end
	return hUnit:GetLocation();
end

function J.CountNotStunnedUnits(tUnits, locAOE, nRadius, nUnits)
	local count = 0;
	if locAOE.count >= nUnits then
		for _,unit in pairs(tUnits)
		do
			if GetUnitToLocationDistance(unit, locAOE.targetloc) <= nRadius and not unit:IsInvulnerable() and not J.IsDisabled(unit) then
				count = count + 1;
			end
		end
	end
	return count;
end

function J.CountInvUnits(pierceImmune, units)
	local nUnits = 0;
	if units ~= nil then
		for _,u in pairs(units) do
			if ( pierceImmune and J.CanCastOnMagicImmune(u) ) or ( not pierceImmune and J.CanCastOnNonMagicImmune(u) )  then
				nUnits = nUnits + 1;
			end
		end
	end
	return nUnits;
end

function J.GetMostHPPercent(listUnits, magicImmune)
	local mostPHP = 0;
	local mostPHPUnit = nil;
	for _,unit in pairs(listUnits)
	do
		local uPHP = unit:GetHealth() / unit:GetMaxHealth()
		if ( ( magicImmune and J.CanCastOnMagicImmune(unit) ) or ( not magicImmune and J.CanCastOnNonMagicImmune(unit) ) ) 
			and uPHP > mostPHP  
		then
			mostPHPUnit = unit;
			mostPHP = uPHP;
		end
	end
	return mostPHPUnit;
end

function J.HasAghanimsShard(bot)
	return bot:HasModifier("modifier_item_aghanims_shard")
end

function J.GetCanBeKilledUnit(units, nDamage, nDmgType, magicImmune)
	local target = nil
	for _,unit in pairs(units)
	do
		if ((magicImmune and J.CanCastOnMagicImmune(unit) ) or ( not magicImmune and J.CanCastOnNonMagicImmune(unit)))
			   and J.CanKillTarget(unit, nDamage, nDmgType)
		then
			target = unit
		end
	end
	return target
end

function J.GetClosestUnit(units)
	local target = nil;
	if units ~= nil and #units >= 1 then
		return units[1];
	end
	return target;
end

function J.IsModeTurbo()
	for _, u in pairs(GetUnitList(UNIT_LIST_ALLIES))
	do
		if u ~= nil
		and u:GetUnitName() == 'npc_dota_courier'
		then
			if u:GetCurrentMovementSpeed() == 1100
			then
				return true
			end
		end
	end

    return false
end

function J.IsCore(bot)
	return J.GetPosition(bot) <= 3
end

local PosXHuman = {}
function J.IsPosxHuman(x)
	if PosXHuman[x] ~= nil then return PosXHuman[x] end
	for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if J.IsValidHero(ally) and J.GetPosition(ally) == x and not ally:IsBot()
		then
			PosXHuman[x] = true
			return true
		end
	end
	PosXHuman[x] = false
	return false
end

function J.GetCoresTotalNetworth()
	local totalNetworth = GetTeamMember(1):GetNetWorth()
				  	    + GetTeamMember(2):GetNetWorth()
				  		+ GetTeamMember(3):GetNetWorth()
	return totalNetworth
end

-- returns 1, 2, 3, 4, or 5 as the position of the hero in the team
function J.GetPosition(bot)
	if bot.isBear then
		return J.GetPosition(J.Utils.GetLoneDruid(bot).hero)
	end
	local role = J.Role.GetPosition(bot)
	if role == nil then
		-- print('[ERROR] Failed to get role for bot: '..bot:GetUnitName())
		role = 2
	end
	return role
end

local function GetEffectiveHealthFromArmor(nHealth, fArmor)
    local damageMultiplier = 1 - ((0.06 * fArmor) / (1 + 0.06 * math.abs(fArmor)))
    return nHealth / damageMultiplier
end

local function GetHealthMultiplier(hUnit)
	local mul = 1
	local sUnitName = hUnit:GetUnitName()
	local botHP = J.GetHP(hUnit) + (hUnit:GetHealthRegen() * 5.0 / hUnit:GetMaxHealth())
	local botMP = J.GetMP(hUnit) + (hUnit:GetManaRegen() * 5.0 / hUnit:GetMaxMana())
	if sUnitName == 'npc_dota_hero_huskar' then
		botHP = ((GetEffectiveHealthFromArmor(hUnit:GetHealth(), hUnit:GetArmor())) / hUnit:GetMaxHealth()) + (hUnit:GetHealthRegen() * 5.0 / hUnit:GetMaxHealth())
		mul = RemapValClamped(botHP, 0, 0.5, 0.5, 1)
	elseif sUnitName == 'npc_dota_hero_medusa' then
		local unitHealth = GetEffectiveHealthFromArmor(hUnit:GetHealth() - hUnit:GetMana(), hUnit:GetArmor())
		local unitMaxHealth = hUnit:GetMaxHealth() - hUnit:GetMaxMana()
		local nHealth = RemapValClamped(unitHealth / unitMaxHealth, 0, 1, 0, 1) * 0.2 + RemapValClamped(botMP, 0, 0.75, 0, 1) * 0.8
		mul = RemapValClamped(nHealth, 0.5, 1, 0.5, 1)
	else
		botHP = ((GetEffectiveHealthFromArmor(hUnit:GetHealth(), hUnit:GetArmor())) / hUnit:GetMaxHealth()) + (hUnit:GetHealthRegen() * 5.0 / hUnit:GetMaxHealth())
		local nHealth = RemapValClamped(botHP, 0, 0.75, 0, 1) * 0.8 + RemapValClamped(botMP, 0, 1, 0, 1) * 0.2
		mul = RemapValClamped(nHealth, 0.5, 1, 0.5, 1)
	end

	return mul
end

function J.WeAreStronger(bot, nRadius)
	local cacheKey = 'WeAreStronger'..tostring(bot:GetPlayerID())..'-'..tostring(nRadius)
	local cachedVar = J.Utils.GetCachedVars(cacheKey, 0.5)
	if cachedVar ~= nil then return cachedVar end

	local tAllyHeroes = {}
	local tEnemyHeroes = {}
	local ourPower = 0
	local ourPowerRaw = 0
	local enemyPower = 0
	local botHealthRegen =  bot:GetHealthRegen() * 2.0

	for _, unit in pairs(GetUnitList(UNIT_LIST_ALL)) do
		if J.IsValidHero(unit)
		and GetUnitToUnitDistance(bot, unit) <= nRadius
		and J.GetHP(unit) > 0.1
		and not unit:HasModifier('modifier_necrolyte_reapers_scythe')
		and not unit:HasModifier('modifier_dazzle_nothl_projection_physical_body_debuff')
		and not unit:HasModifier('modifier_skeleton_king_reincarnation_scepter_active')
		and not unit:HasModifier('modifier_item_helm_of_the_undying_active')
		and not unit:HasModifier('modifier_teleporting')
		and unit:GetTeam() ~= TEAM_NEUTRAL
		and unit:GetTeam() ~= TEAM_NONE
		and (unit:GetTeam() == GetTeam() or not unit.CanBeSeen or unit:CanBeSeen())
		then
			local sUnitName = unit:GetUnitName()
			local fMul = GetHealthMultiplier(unit)
			local fMul_Illusion = RemapValClamped(J.GetHP(unit), 0.25, 1, 0, 1)

			if GetTeam() == unit:GetTeam() then
				if not unit:HasModifier('modifier_arc_warden_tempest_double')
				and J.IsSuspiciousIllusion(unit)
				then
					local nDamage = GetUnitAttackDamage(unit, 5.0, true)
					if nDamage then
						ourPower = ourPower + (math.log(1 + unit:GetOffensivePower())) * ((math.sqrt(Max(0, nDamage)))) * fMul_Illusion
						ourPowerRaw = ourPowerRaw + (math.log(1 + unit:GetRawOffensivePower())) * (math.sqrt(Max(0, nDamage))) * fMul_Illusion
					end
				else
					if not J.IsMeepoClone(unit)
					and not string.find(sUnitName, 'lone_druid_bear')
					and not unit:HasModifier('modifier_item_helm_of_the_undying_active')
					then
						table.insert(tAllyHeroes, unit)
					end
					ourPower = ourPower + (math.log(1 + unit:GetOffensivePower())) * (math.sqrt(unit:GetAttackDamage() * unit:GetAttackSpeed() * 5)) * fMul
					ourPowerRaw = ourPowerRaw + (math.log(1 + unit:GetRawOffensivePower())) * (math.sqrt(Max(0, unit:GetAttackDamage() * unit:GetAttackSpeed() * 5))) * fMul
				end
			else
				if not unit:HasModifier('modifier_arc_warden_tempest_double')
				and J.IsSuspiciousIllusion(unit)
				then
					local nDamage = GetUnitAttackDamage(unit, 5.0, true)
					if nDamage then
						enemyPower = enemyPower + (math.log(1 + unit:GetRawOffensivePower())) * (math.sqrt(Max(0, nDamage))) * fMul_Illusion
					end
				else
					if not J.IsMeepoClone(unit)
					and not string.find(sUnitName, 'lone_druid_bear')
					and not unit:HasModifier('modifier_item_helm_of_the_undying_active')
					then
						table.insert(tEnemyHeroes, unit)
					end
					enemyPower = enemyPower + (math.log(1 + unit:GetRawOffensivePower())) * (math.sqrt(Max(0, unit:GetAttackDamage() * unit:GetAttackSpeed() * 5))) * fMul
				end
			end
		end
	end

	local nAllyTowers = bot:GetNearbyTowers(600, false)
	if J.IsValidBuilding(nAllyTowers[1]) then
		if nAllyTowers[1]:HasModifier('modifier_fountain_glyph') then
			local power = #nAllyTowers * (math.sqrt(Max(0, nAllyTowers[1]:GetAttackDamage() * nAllyTowers[1]:GetAttackSpeed() * 5.0 * 2)))
			ourPower = ourPower + power
			ourPowerRaw = ourPowerRaw + power
		else
			local power = #nAllyTowers * (math.sqrt(Max(0, nAllyTowers[1]:GetAttackDamage() * nAllyTowers[1]:GetAttackSpeed() * 5.0)))
			ourPower = ourPower + power
			ourPowerRaw = ourPowerRaw + power
		end
	end

	if not J.IsEarlyGame() and J.IsInTeamFight(bot, 1600) and #tAllyHeroes >= #tEnemyHeroes then
		local vTeamFightLocation = J.GetTeamFightLocation(bot)
		if vTeamFightLocation ~= nil and (J.IsHumanInLoc(vTeamFightLocation, 1200) or #tAllyHeroes > #tEnemyHeroes) then
			ourPower = ourPower * 1.20
			ourPowerRaw = ourPowerRaw * 1.20
		end
	end

	local res = ourPowerRaw > enemyPower
	-- Keep strategic callers on the cheap proxy. Only an actual close
	-- contested fight can override it with the short-window exchange.
	if #tEnemyHeroes > 0 and J.GetLocalFightReadiness and bot.GetAttackPoint
		and (J.IsAttacking(bot) or bot:WasRecentlyDamagedByAnyHero(2)) then
		local verdict = J.GetLocalFightReadiness(bot, tAllyHeroes, tEnemyHeroes)
		if verdict ~= nil then res = verdict end
	end
	J.Utils.SetCachedVars(cacheKey, res)
	return res
end

function J.CanCastAbilitySoon(ability, fTime)
	if ability == nil
	or ability:IsNull()
	or ability:GetName() == ''
	or ability:IsPassive()
	or ability:IsHidden()
	or not ability:IsTrained()
	or not ability:IsActivated()
	then
		return false
	end

	if ability:GetCooldownTimeRemaining() > fTime then
		return false
	end

	return true
end

-- hAbilityList: handle / integer (mana)
function J.GetManaThreshold(bot, nManaCost, hAbilityList)
	local fManaThreshold = 0
	local botManaRegen = bot:GetManaRegen()
	local botMaxMana = bot:GetMaxMana()

	-- tp, bkb
	local itemSlots = {0, 1, 2, 3, 4, 5, 15}
	for i = 1, #itemSlots do
		local hItem = bot:GetItemInSlot(itemSlots[i])
		if hItem then
			local sItemName = hItem:GetName()
			if sItemName == 'item_tpscroll'
			or sItemName == 'item_black_king_bar'
			then
				local nManaCostItem = hItem:GetManaCost()
				if J.CanCastAbilitySoon(hItem, nManaCost / botManaRegen) then
					fManaThreshold = fManaThreshold + (nManaCostItem / botMaxMana)
				end
			end
		end
	end

	for _, hAbility in pairs(hAbilityList) do
		if type(hAbility) == 'number' then
			fManaThreshold = fManaThreshold + hAbility / botMaxMana
		else
			if J.CanCastAbilitySoon(hAbility, nManaCost / botManaRegen) then
				fManaThreshold = fManaThreshold + (hAbility:GetManaCost()) / botMaxMana
			end
		end
	end

	return fManaThreshold
end

function J.CheckLoneDruid()
	local ld = {hero=nil,bear=nil}
	for _, unit in pairs(GetUnitList(UNIT_LIST_ALL)) do
		if J.IsValid(unit) and not J.IsSuspiciousIllusion(unit) then
			local unitName = unit:GetUnitName()
			if unitName == 'npc_dota_hero_lone_druid' then
				ld.hero = unit
			elseif unitName == 'npc_dota_hero_lone_druid_bear' then
				ld.bear = unit
			end
		end
	end
	return ld
end

function J.RandomForwardVector(length)

    local offset = RandomVector(length)

    if GetTeam() == TEAM_RADIANT then
        offset.x = offset.x > 0 and offset.x or -offset.x
        offset.y = offset.y > 0 and offset.y or -offset.y
    end

    if GetTeam() == TEAM_DIRE then
        offset.x = offset.x < 0 and offset.x or -offset.x
        offset.y = offset.y < 0 and offset.y or -offset.y
    end

    return offset
end

function J.GetUnitWithMinDistanceToLoc(hUnit, hUnits, cUnits, fMinDist, vLoc)
	local minUnit = cUnits;
	local minVal = fMinDist;
	
	for i=1, #hUnits do
		if hUnits[i] ~= nil and hUnits[i] ~= hUnit and J.CanCastOnNonMagicImmune(hUnits[i]) 
		then
			local dist = GetUnitToLocationDistance(hUnits[i], vLoc);
			if dist < minVal then
				minVal = dist;
				minUnit = hUnits[i];	
			end
		end	
	end
	
	return minVal, minUnit;
end

function J.GetUnitWithMaxDistanceToLoc(hUnit, hUnits, cUnits, fMinDist, vLoc)
	local maxUnit = cUnits
	local maxVal = fMinDist
	
	for i=1, #hUnits do
		if hUnits[i] ~= nil and hUnits[i] ~= hUnit and J.CanCastOnNonMagicImmune(hUnits[i])
		then
			local dist = GetUnitToLocationDistance(hUnits[i], vLoc)
			if dist > maxVal then
				maxVal = dist
				maxUnit = hUnits[i]
			end
		end	
	end
	
	return maxVal, maxUnit
end

function J.GetFurthestUnitToLocationFrommAll(hUnit, nRange, vLoc)
	local aHeroes = J.GetNearbyHeroes(hUnit,nRange, false, BOT_MODE_NONE)
	local eHeroes = J.GetNearbyHeroes(hUnit,nRange, true, BOT_MODE_NONE)
	local aCreeps = hUnit:GetNearbyLaneCreeps(nRange, false)
	local eCreeps = hUnit:GetNearbyLaneCreeps(nRange, true)

	local botDist = GetUnitToLocationDistance(hUnit, vLoc)
	local furthestUnit = hUnit
	botDist, furthestUnit = J.GetUnitWithMaxDistanceToLoc(hUnit, aHeroes, furthestUnit, botDist, vLoc)
	botDist, furthestUnit = J.GetUnitWithMaxDistanceToLoc(hUnit, eHeroes, furthestUnit, botDist, vLoc)
	botDist, furthestUnit = J.GetUnitWithMaxDistanceToLoc(hUnit, aCreeps, furthestUnit, botDist, vLoc)
	botDist, furthestUnit = J.GetUnitWithMaxDistanceToLoc(hUnit, eCreeps, furthestUnit, botDist, vLoc)

	if furthestUnit ~= hUnit then
		return furthestUnit
	end

	return nil

end

function J.GetClosestUnitToLocationFrommAll(hUnit, nRange, vLoc)
	local aHeroes = J.GetNearbyHeroes(hUnit,nRange, false, BOT_MODE_NONE);
	local eHeroes = J.GetNearbyHeroes(hUnit,nRange, true, BOT_MODE_NONE);
	local aCreeps = hUnit:GetNearbyLaneCreeps(nRange, false);
	local eCreeps = hUnit:GetNearbyLaneCreeps(nRange, true);
		
	local botDist = GetUnitToLocationDistance(hUnit, vLoc);
	local closestUnit = hUnit;
	botDist, closestUnit = J.GetUnitWithMinDistanceToLoc(hUnit, aHeroes, closestUnit, botDist, vLoc);
	botDist, closestUnit = J.GetUnitWithMinDistanceToLoc(hUnit, eHeroes, closestUnit, botDist, vLoc);
	botDist, closestUnit = J.GetUnitWithMinDistanceToLoc(hUnit, aCreeps, closestUnit, botDist, vLoc);
	botDist, closestUnit = J.GetUnitWithMinDistanceToLoc(hUnit, eCreeps, closestUnit, botDist, vLoc);
	
	if closestUnit ~= hUnit then
		return closestUnit;
	end
	
	return nil;
	
end

function J.GetClosestUnitToLocationFrommAll2(hUnit, nRange, vLoc)
	local aHeroes = J.GetNearbyHeroes(hUnit,nRange, false, BOT_MODE_NONE);
	local eHeroes = J.GetNearbyHeroes(hUnit,nRange, true, BOT_MODE_NONE);
	local aCreeps = hUnit:GetNearbyLaneCreeps(nRange, false);
	local eCreeps = hUnit:GetNearbyLaneCreeps(nRange, true);
		
	local botDist = 10000;
	local closestUnit = nil;
	botDist, closestUnit = J.GetUnitWithMinDistanceToLoc(hUnit, aHeroes, closestUnit, botDist, vLoc);
	botDist, closestUnit = J.GetUnitWithMinDistanceToLoc(hUnit, eHeroes, closestUnit, botDist, vLoc);
	botDist, closestUnit = J.GetUnitWithMinDistanceToLoc(hUnit, aCreeps, closestUnit, botDist, vLoc);
	botDist, closestUnit = J.GetUnitWithMinDistanceToLoc(hUnit, eCreeps, closestUnit, botDist, vLoc);
	
	if closestUnit ~= nil then
		return closestUnit;
	end
	
	return nil;
	
end

function J.CheckTimeOfDay()
    local cycle = 600
    local time = DotaTime() % cycle
    local night = 300

    if time < night then return "day", time
    else return "night", time
    end
end

function J.GetArmorReducers(hero)
	local reducedArmor = 0

	-- Items (Passives for now)
	if J.HasItem(hero, "item_desolator")
	and (hero:GetItemInSlot (6) ~= "item_desolator" or hero:GetItemInSlot(7) ~= "item_desolator" or hero:GetItemInSlot(8) ~= "item_desolator")
	then
		reducedArmor = reducedArmor + 6
	end

	if J.HasItem(hero, "item_assault")
	and (hero:GetItemInSlot (6) ~= "item_assault" or hero:GetItemInSlot(7) ~= "item_assault" or hero:GetItemInSlot(8) ~= "item_assault")
	then
		reducedArmor = reducedArmor + 5
	end

	if J.HasItem(hero, "item_blight_stone")
	and (hero:GetItemInSlot (6) ~= "item_blight_stone" or hero:GetItemInSlot(7) ~= "item_blight_stone" or hero:GetItemInSlot(8) ~= "item_blight_stone")
	then
		reducedArmor = reducedArmor + 2
	end

	-- Abilities (Passives for now)
	local NevermoreDarkLord = hero:GetAbilityByName("nevermore_dark_lord")
	if hero:GetUnitName() == "npc_dota_hero_nevermore"
	and NevermoreDarkLord ~= nil
	and NevermoreDarkLord:GetLevel() > 0
	then
		reducedArmor = reducedArmor + NevermoreDarkLord:GetSpecialValueInt("presence_armor_reduction")
	end

	local NagaSirenRiptide = hero:GetAbilityByName("naga_siren_rip_tide")
	if hero:GetUnitName() == "npc_dota_hero_naga_siren"
	and NagaSirenRiptide ~= nil
	and NagaSirenRiptide:GetLevel() > 0 then
		reducedArmor = reducedArmor + NagaSirenRiptide:GetSpecialValueInt("armor_reduction")
	end

	return reducedArmor
end

-- Number of Roshan kills observed by this Lua instance. 7.42 reduces the
-- normal-mode *base* respawn time from 8m by 1m per defeat down to 5m.
-- Keep the documented pre-7.42 0-3m offset as a conservative working
-- assumption (10/9/8m for 1/2/3+ observed kills). This is a planning
-- estimate, not a current sighting or a way to see through fog.
-- If this Lua instance starts late and misses kills, the bound remains
-- conservative rather than claiming an early respawn without evidence.
local lastObservedRoshanKillTime = 0
local observedRoshanKills = 0
function J.IsRoshanAlive()
    local latestKill = GetRoshanKillTime()
    if type(latestKill) ~= "number" or latestKill < 0 then
        return false
    end
    if latestKill == 0 then
        lastObservedRoshanKillTime = 0
        observedRoshanKills = 0
        return true
    end

    local now = DotaTime()
    if latestKill > now then
        return false
    end

    -- Keep the prior Turbo threshold and its strict boundary unchanged
    -- until the new normal-mode rule has been verified in Turbo itself.
    if J.IsModeTurbo() then
        return now - latestKill > 6 * 60
    end

    if latestKill ~= lastObservedRoshanKillTime then
        if latestKill < lastObservedRoshanKillTime then
            -- A new game / time reset must not inherit the prior game's count.
            observedRoshanKills = 0
        end
        observedRoshanKills = observedRoshanKills + 1
        lastObservedRoshanKillTime = latestKill
    end

    local base = math.max(5, 8 - observedRoshanKills)
    return now - latestKill >= (base + 3) * 60
end

function J.HasEnoughDPSForRoshan(heroes, roshan)
    local dps = 0
    local minute = math.max(0, math.floor(DotaTime() / 60))
    local roshanHealth = roshan ~= nil and roshan:GetHealth() or 6000 + 260 * minute
    local roshanArmor = 30 + 0.375 * minute

    for _, hero in ipairs(heroes) do
        local attack = hero:GetAttackDamage()
        local armor = math.max(0, roshanArmor - J.GetArmorReducers(hero))
        local hitDamage = roshan ~= nil and roshan:GetActualIncomingDamage(attack, DAMAGE_TYPE_PHYSICAL)
            or attack * 20 / (armor + 20)
        dps = dps + hitDamage / math.max(0.2, hero:GetSecondsPerAttack())
    end
    return dps >= roshanHealth / 60, dps > 0 and roshanHealth / dps or math.huge
end

function J.IsNotSelf(bot, ally)
	if bot:GetUnitName() ~= ally:GetUnitName()
	then
		return true
	end

	return false
end

function J.IsThereNonSelfCoreNearby(nRadius)
	local selfBot = GetBot()
	-- local cacheKey = 'IsThereNonSelfCoreNearby'..tostring(selfBot:GetPlayerID())
	-- local cache = J.Utils.GetCachedVars(cacheKey, 2)
	-- if cache ~= nil then return cache end

    local nAllyHeroes = J.GetNearbyHeroes(selfBot, nRadius, false, BOT_MODE_NONE)

    for _, ally in pairs(nAllyHeroes) do
        if J.IsCore(ally) and selfBot ~= ally
        then
            -- J.Utils.SetCachedVars(cacheKey, true)
            return true
        end
    end

    -- J.Utils.SetCachedVars(cacheKey, false)
    return false
end

function J.GetAliveAllyCoreCount()
	local count = 0
	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if J.IsValidHero(allyHero)
		and J.IsCore(allyHero)
		and not allyHero:IsIllusion()
		then
			count = count + 1
		end
	end

	return count
end

function J.GetStrongestUnit(nRange, hUnit, bEnemy, bMagicImune, fTime)
	local units = J.GetNearbyHeroes(hUnit,nRange, bEnemy, BOT_MODE_NONE)
	local strongest = nil
	local maxPower = 0

	for i = 1, #units do
		if J.IsValidTarget(units[i])
		and J.IsValidTarget(hUnit)
		and ((bMagicImune == true and J.CanCastOnMagicImmune(units[i]) == true) or (bMagicImune == false and J.CanCastOnNonMagicImmune(units[i]) == true))
		then
			local power = units[i]:GetEstimatedDamageToTarget(true, hUnit, fTime, DAMAGE_TYPE_ALL)

			if power > maxPower
			then
				maxPower = power
				strongest = units[i]
			end
		end
	end
	return strongest
end

function J.GetStrongestEnemyHero(enemies)
	local strongestenemy = nil
	local highesthealth = 0

	for v, enemy in pairs(enemies) do
		if J.IsValidTarget(enemy) and J.IsNotImmune(enemy) and not J.IsSuspiciousIllusion(enemy) then
			if enemy:GetHealth() > highesthealth then
				strongestenemy = enemy
				highesthealth = enemy:GetHealth()
			end
		end
	end
	return strongestenemy
end

function J.GetDistance(s, t)
    return math.sqrt((s[1] - t[1]) * (s[1]-t[1]) + (s[2] - t[2]) * (s[2] - t[2]))
end

function J.IsHeroBetweenMeAndLocation(hSource, vLoc, nRadius)
	local vStart = hSource:GetLocation()
	local vEnd = vLoc
	local bot = GetBot()

	local nAllyHeroes = J.GetNearbyHeroes(bot,1600, false, BOT_MODE_NONE)
	for _, allyHero in pairs(nAllyHeroes)
    do
		if allyHero ~= hSource
		then
			local tResult = PointToLineDistance(vStart, vEnd, allyHero:GetLocation())
			if tResult ~= nil and tResult.within and tResult.distance < nRadius then return true end
		end
	end

	local nEnemyHeroes = J.GetNearbyHeroes(bot,1600, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(nEnemyHeroes)
    do
		if enemyHero ~= hSource
		and not J.IsSuspiciousIllusion(enemyHero)
		then
			local tResult = PointToLineDistance(vStart, vEnd, enemyHero:GetLocation())
			if tResult ~= nil and tResult.within and tResult.distance < nRadius then return true end
		end
	end

	return false
end

function J.IsEnemyBetweenMeAndLocation(hSource, vLoc, nRadius)
	local vStart = hSource:GetLocation()
	local vEnd = vLoc
	local bot = GetBot()

	local nEnemyHeroes = J.GetNearbyHeroes(bot,1600, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(nEnemyHeroes)
    do
		if enemyHero ~= hSource
		and not J.IsSuspiciousIllusion(enemyHero)
		then
			local tResult = PointToLineDistance(vStart, vEnd, enemyHero:GetLocation())
			if tResult ~= nil and tResult.within and tResult.distance < nRadius then return true end
		end
	end

	return false
end

function J.IsHeroBetweenMeAndTarget(hSource, hTarget, vLoc, nRadius)
	local vStart = hSource:GetLocation()
	local vEnd = vLoc

	local nAllyHeroes = J.GetNearbyHeroes(hSource,1600, false, BOT_MODE_NONE)
	for _, allyHero in pairs(nAllyHeroes)
    do
		if allyHero ~= hTarget and allyHero ~= hSource
		then
			local tResult = PointToLineDistance(vStart, vEnd, allyHero:GetLocation())
			if tResult ~= nil and tResult.within == true and tResult.distance < nRadius then return true end
		end
	end

	local nEnemyHeroes = J.GetNearbyHeroes(hSource,1600, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(nEnemyHeroes)
    do
		if enemyHero ~= hTarget and enemyHero ~= hSource
		then
			local tResult = PointToLineDistance(vStart, vEnd, enemyHero:GetLocation())
			if tResult ~= nil and tResult.within and tResult.distance < nRadius then return true end
		end
	end

	return false
end

function J.IsCreepBetweenMeAndLocation(hSource, vLoc, nRadius)
	local vStart = hSource:GetLocation()
	local vEnd = vLoc
	local bot = GetBot()

	local nAllyLaneCreeps = bot:GetNearbyLaneCreeps(1600, true)
	for _, creep in pairs(nAllyLaneCreeps)
    do
		local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation())
		if tResult ~= nil and tResult.within and tResult.distance < nRadius then return true end
	end

	local nEnemyLaneCreeps = bot:GetNearbyLaneCreeps(1600, false)
	for _, creep in pairs(nEnemyLaneCreeps)
    do
		local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation())

		if tResult ~= nil and tResult.within and tResult.distance < nRadius then return true end
	end

	return false
end

function J.IsUnitBetweenMeAndLocation(hSource, hTarget, vTargetLoc, nRadius)
	local vStart = hSource:GetLocation()
	local vEnd = vTargetLoc

	for _, unit in pairs(GetUnitList(UNIT_LIST_ALL))
	do
		if J.IsValid(unit)
		and GetUnitToUnitDistance(GetBot(), unit) <= 1600
		and not unit:IsBuilding()
		and not string.find(unit:GetUnitName(), 'ward')
		and hSource ~= unit
		and hTarget ~= unit
		then
			local nRadius__ = nRadius + unit:GetBoundingRadius()
			local tResult = PointToLineDistance(vStart, vEnd, unit:GetLocation())
			if tResult ~= nil and tResult.within and tResult.distance <= nRadius__ then return true end end
	end

	return false
end

function J.IsNonSiegeCreepBetweenMeAndLocation(hSource, vLoc, nRadius)
	local vStart = hSource:GetLocation()
	local vEnd = vLoc

	local nAllyLaneCreeps = hSource:GetNearbyLaneCreeps(1600, true)
	for _, creep in pairs(nAllyLaneCreeps)
    do
		if J.IsValid(creep)
		and not J.IsKeyWordUnit('siege', creep)
		then
			local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation())
			if tResult ~= nil and tResult.within and tResult.distance < nRadius then return true end
		end
	end

	local nEnemyLaneCreeps = hSource:GetNearbyLaneCreeps(1600, false)
	for _, creep in pairs(nEnemyLaneCreeps)
    do
		if J.IsValid(creep)
		and not J.IsKeyWordUnit('siege', creep)
		then
			local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation())
			if tResult ~= nil and tResult.within and tResult.distance < nRadius then return true end
		end
	end

	return false
end

function J.IsThereCoreNearby(nRadius)
	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local allyHero = GetTeamMember(i)
		if allyHero ~= nil
		and allyHero ~= GetBot()
		and J.IsCore(allyHero)
		and J.IsInRange(GetBot(), allyHero, nRadius)
		then
			return true
		end
	end

    return false
end

function J.GetClosestCore(bot, nRadius)
	return J.GetClosestAlly(bot, nRadius, true)
end

-- Retreat ultimates are for a fight a teammate can still turn, not simply a
-- low-HP caster. A nearby ally using TP or already disengaging is not follow-up.
function J.GetSupportCounterfightPoint(bot, enemies, castRange, radius, minimumHP)
    if J.GetHP(bot) >= minimumHP and not J.IsRetreating(bot) then return nil end
    local point, best = nil, 0
    for _, target in ipairs(enemies) do
        if J.IsValidHero(target) and not J.IsSuspiciousIllusion(target)
            and not target:IsInvulnerable() and J.CanCastOnMagicImmune(target)
            and not J.IsDisabled(target) and J.IsInRange(bot, target, castRange) then
            local loc = target:GetLocation()
            local score = 0
            for _, ally in ipairs(J.GetAlliesNearLoc(loc, 950)) do
                if ally ~= bot and J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally)
                    and J.GetHP(ally) > 0.38 and not J.IsRetreating(ally) and not J.IsDisabled(ally)
                    and not ally:IsChanneling() and not ally:HasModifier('modifier_teleporting') then
                    local attacker = ally:GetAttackTarget()
                    if (attacker == target and J.IsInRange(ally, target, math.max(650, ally:GetAttackRange() + 200)))
                        or (target:GetAttackTarget() == ally
                        and ally:WasRecentlyDamagedByHero(target, 2)
                        and J.IsInRange(target, ally, target:GetAttackRange() + 200)) then
                        score = score + (J.IsCore(ally) and 3 or 1)
                    end
                end
            end
            if score > 0 and IsLocationPassable(loc) then
                for _, other in ipairs(enemies) do
                    if other ~= target and J.IsValidHero(other) and not J.IsSuspiciousIllusion(other)
                        and not other:IsInvulnerable() and J.IsInRange(target, other, radius) then score = score + 0.5 end
                end
                if score > best then point, best = loc, score end
            end
        end
    end
    return point
end

function J.GetAvailableFightAllies(bot, location, radius)
	local count = 0
	for _, ally in ipairs(J.GetAlliesNearLoc(location, radius)) do
		if ally ~= bot and J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally)
		and not J.IsRetreating(ally) and not ally:HasModifier('modifier_teleporting')
		and not ally:IsChanneling() and not ally:IsStunned() and not ally:IsHexed() and not ally:IsNightmared()
		and J.GetHP(ally) > 0.3 then
			count = count + 1
		end
	end
	return count
end

function J.HasSiegeDamageInRange(bot, location, lane)
	local strongest, ready = 0, 0
	local ranged, readyRanged = 0, 0
	for i = 1, #GetTeamPlayers(bot:GetTeam()) do
		local member = GetTeamMember(i)
		if member ~= nil and not member:IsNull() and member:IsAlive() and J.IsCore(member) then
			local damage = member:GetAttackDamage() / math.max(0.2, member:GetSecondsPerAttack())
			local range = member:GetAttackRange()
			strongest = math.max(strongest, damage)
			if range >= 500 then ranged = math.max(ranged, damage) end
			if J.GetHP(member) >= 0.45 and not J.IsRetreating(member)
				and not member:IsStunned() and not member:IsHexed() and not member:IsNightmared()
				and not member:IsDisarmed() and not member:IsChanneling()
				and not member:HasModifier('modifier_teleporting') then
				local distance = GetUnitToLocationDistance(member, location) - range
				local committed = member == bot or (lane ~= nil and J.IsPushing(member) and member.laneToPush == lane)
				local attackRange = lane == nil and 200 or 0
				if (distance <= (member:IsRooted() and 0 or attackRange) and (committed or not J.IsFarming(member)))
					or (committed and not member:IsRooted() and distance <= member:GetCurrentMovementSpeed() * 1.4) then
					ready = math.max(ready, damage)
					if range >= 500 then readyRanged = math.max(readyRanged, damage) end
				end
			end
		end
	end
	return strongest > 0 and ready >= strongest * 0.85 and (ranged < strongest * 0.65 or readyRanged >= ranged * 0.85)
end

function J.GetLaneWaveAtBuilding(building, lane)
	local location = building:GetLocation()
	local key = 'WaveAtBuilding:' .. lane .. ':' .. location.x .. ':' .. location.y
	local cached = J.Utils.GetCachedVars(key, 0.18)
	if cached ~= nil then return cached.count, cached.eta, cached.thirdETA, cached.siegeETA, cached.attacking end
	local track = GetAmountAlongLane(lane, location)
	local direction = GetTeam() == TEAM_RADIANT and 1 or -1
	local count, first, second, third = 0, math.huge, math.huge, math.huge
	local siegeETA, attacking = math.huge, 0
	for _, creep in ipairs(GetUnitList(UNIT_LIST_ALLIED_CREEPS)) do
		if J.IsValid(creep) and (J.IsKeyWordUnit('npc_dota_creep_', creep) or J.IsKeyWordUnit('_siege', creep)) then
			local distance = GetUnitToLocationDistance(creep, location)
			if distance <= 2900 then
				local path = GetAmountAlongLane(lane, creep:GetLocation())
				if path.distance <= 400 and (track.amount - path.amount) * direction >= -0.04 then
					local time = math.max(0, distance - 775) / math.max(250, creep:GetCurrentMovementSpeed())
					if J.IsKeyWordUnit('_siege', creep) then siegeETA = math.min(siegeETA, time) end
					if creep:GetAttackTarget() == building then attacking = attacking + 1 end
					if time <= 0 then count = count + 1 end
					if time < first then
						first, second, third = time, first, second
					elseif time < second then
						second, third = time, second
					elseif time < third then
						third = time
					end
				end
			end
		end
	end
	J.Utils.SetCachedVars(key, {count = count, eta = second, thirdETA = third, siegeETA = siegeETA, attacking = attacking})
	return count, second, third, siegeETA, attacking
end

local enemyLastAlive = {}
local lastReinforcementSample = -math.huge
local reinforcementWindow = 0

function J.GetEnemyReinforcementWindow()
	local now = DotaTime()
	if now < lastReinforcementSample then enemyLastAlive, lastReinforcementSample = {}, -math.huge end
	if now - lastReinforcementSample < 0.5 then return reinforcementWindow end
	lastReinforcementSample, reinforcementWindow = now, math.huge
	for _, id in ipairs(GetTeamPlayers(GetOpposingTeam())) do
		local deaths = GetHeroDeaths(id)
		if IsHeroAlive(id) then
			enemyLastAlive[id] = {time = now, deaths = deaths}
		else
			-- Estimate only from public death status and the last observed alive tick.
			local budget = math.min(28, 2 + GetHeroLevel(id) * 1.65) * (J.IsModeTurbo() and 0.55 or 1)
			local last = enemyLastAlive[id]
			local remaining = last ~= nil and deaths > last.deaths and math.max(0, last.time + budget - now) or 4
			reinforcementWindow = math.min(reinforcementWindow, remaining)
		end
	end
	return reinforcementWindow
end

function J.CanFinishOuterTowerInWindow(bot, tower, lane, window)
	local wave, waveETA = J.GetLaneWaveAtBuilding(tower, lane)
	if wave < 2 and waveETA > 7 then return false end
	local location = tower:GetLocation()
	local selfETA = math.max(0, GetUnitToLocationDistance(bot, location) - bot:GetAttackRange())
		/ math.max(1, bot:GetCurrentMovementSpeed())
	local start = math.max(waveETA, selfETA)
	local dps = 0
	for _, ally in ipairs(J.GetAlliesNearLoc(location, 3000)) do
		if J.IsValidHero(ally) and not ally:IsIllusion() and not J.IsRetreating(ally) and J.GetHP(ally) >= 0.55
			and not J.IsDisabled(ally) and not ally:IsDisarmed() then
			local distance = math.max(0, GetUnitToLocationDistance(ally, location) - ally:GetAttackRange())
			local eta = distance / math.max(1, ally:GetCurrentMovementSpeed())
			if eta <= start + 2 and (ally == bot or not J.IsFarming(ally)) then
				dps = dps + tower:GetActualIncomingDamage(ally:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
					/ math.max(0.2, ally:GetSecondsPerAttack())
			end
		end
	end
	return dps > 0 and start + tower:GetHealth() / (0.85 * dps) + 2 <= window
end

function J.CanCommitToLaneTeleport(bot, location, requireClear, radius)
	if location == nil then return false end
	radius = radius or 1500
	local enemies = {}
	for _, id in ipairs(J.GetLastSeenEnemiesNearLoc(location, radius)) do enemies[id] = true end
	for _, enemy in ipairs(J.GetEnemiesNearLoc(location, radius)) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) then enemies[enemy:GetPlayerID()] = true end
	end
	for _, tp in ipairs(GetIncomingTeleports()) do
		if tp.playerid ~= nil and tp.location ~= nil and tp.time_remaining ~= nil
			and tp.time_remaining >= 0 and tp.time_remaining <= 4 and GetTeamForPlayer(tp.playerid) == GetOpposingTeam()
			and IsLocationVisible(tp.location) and J.GetLocationToLocationDistance(tp.location, location) <= radius then
			enemies[tp.playerid] = true
		end
	end
	local threatCount = 0
	for _ in pairs(enemies) do threatCount = threatCount + 1 end
	if requireClear then return threatCount == 0 end
	if threatCount < 2 then return true end
	local backup = J.GetAvailableFightAllies(bot, location, 1150)
	return backup >= threatCount - 1 and J.GetHP(bot) >= 0.55
end

local function LaneTower(teamId, lane, tier)
	local ids = lane == LANE_TOP and {TOWER_TOP_1, TOWER_TOP_2, TOWER_TOP_3}
		or (lane == LANE_MID and {TOWER_MID_1, TOWER_MID_2, TOWER_MID_3}
		or (lane == LANE_BOT and {TOWER_BOT_1, TOWER_BOT_2, TOWER_BOT_3}))
	return ids and GetTower(teamId, ids[tier])
end

function J.GetTeleportHomeLane(bot)
	local lane = bot:GetAssignedLane()
	if lane == LANE_TOP or lane == LANE_MID or lane == LANE_BOT then return lane end
	local role = J.GetPosition(bot)
	if role == 2 then return LANE_MID end
	if role == 1 or role == 5 then return bot:GetTeam() == TEAM_RADIANT and LANE_BOT or LANE_TOP end
	return bot:GetTeam() == TEAM_RADIANT and LANE_TOP or LANE_BOT
end

function J.CanReturnToLaneByTeleport(bot, location, minimum)
	return LaneTeleportPolicy.ReturnToLane({
		started = DotaTime() >= 0, fromBase = bot:DistanceFromFountain() <= 1400,
		healthy = J.GetHP(bot) >= 0.80 and J.GetMP(bot) >= 0.35,
		safeAnchor = IsLocationPassable(location) and J.CanCommitToLaneTeleport(bot, location, true, 1100),
		distance = GetUnitToLocationDistance(bot, location), minimum = minimum,
	})
end

function J.TraceLaneTeleport(bot, motive, location)
	if not J.Customize or not J.Customize.TraceLaneDecisions or location == nil then return end
	print(string.format('[OHA tp] %.2f player=%d hero=%s home=%d reason=%s from=%.0f,%.0f to=%.0f,%.0f',
		DotaTime(), bot:GetPlayerID(), bot:GetUnitName(), J.GetTeleportHomeLane(bot), tostring(motive),
		bot:GetLocation().x, bot:GetLocation().y, location.x, location.y))
end

local function HasSourceLaneOpportunity(bot, lane)
	if not J.IsCore(bot) or J.GetHP(bot) < 0.55 or bot:DistanceFromFountain() < 1400 then return false end
	if J.ShouldKeepLaningWave(bot) or J.ShouldKeepMidOpportunity(bot) then return true end
	local tower = LaneTower(bot:GetTeam(), lane, 1)
	local front = GetLaneFrontLocation(bot:GetTeam(), lane, 0)
	local distance = GetUnitToLocationDistance(bot, front)
	return J.IsValidBuilding(tower) and GetAmountAlongLane(lane, bot:GetLocation()).distance <= 1300
		and distance <= 2200 and #J.GetEnemiesNearLoc(bot:GetLocation(), 1100) < 2
end

-- Both planned and legacy defense must justify spending the scroll. Follow-up
-- claims are written only after the item action is issued.
function J.CanTakeLaneDefenseTeleport(bot, lane, landing, tower, rear, planned, reach, observed)
	if not J.IsInLaningPhase(bot) then
		if not landing or (not observed and not J.IsValidBuilding(tower)) then return false end
		if not planned and tower ~= nil and tower == GetAncient(bot:GetTeam()) then
			return #J.GetLastSeenEnemiesNearLoc(tower:GetLocation(), 3000) > 0
		end
		local sight = observed or J.GetOuterTowerThreat(tower, lane)
		if not sight.underAttack and ((sight.waveSize or 0) == 0
			or sight.score == 0 and not (sight.siege and sight.eta <= 9)) then return false, 'no-live-pressure' end
		local role, plan = J.GetPostFightDuty(bot)
		if role and (plan.lane ~= lane or plan.building ~= (rear or tower)) then return false end
		if not role and J.HasAssignedWaveDefense(plan, lane) then return false, 'already-covered' end
		local inbound, seen, now = 0, {}, DotaTime()
		for _, tp in ipairs(GetIncomingTeleports()) do
			if tp.playerid ~= nil and tp.playerid ~= bot:GetPlayerID() and tp.location and tp.time_remaining
				and tp.time_remaining >= 0 and tp.time_remaining <= 7 and GetTeamForPlayer(tp.playerid) == bot:GetTeam()
				and not seen[tp.playerid] and J.GetLocationToLocationDistance(tp.location, landing) <= 1150 then
				seen[tp.playerid], inbound = true, inbound + 1
			end
		end
		for slot = 1, #GetTeamPlayers(bot:GetTeam()) do
			local ally = GetTeamMember(slot)
			if ally ~= bot and J.IsValidHero(ally) and not seen[ally:GetPlayerID()] then
				local order = ally.ohaLaneDefenseTP
				if order and order.lane == lane and order.landing and now >= order.time and now - order.time <= 9
					and J.GetLocationToLocationDistance(order.landing, landing) <= 1150
					and (now - order.time <= 1.2 or ally:HasModifier('modifier_teleporting')
						or GetUnitToLocationDistance(ally, landing) <= 1150 and not J.IsRetreating(ally)) then
					inbound = inbound + 1
				end
			end
		end
		local slots = (sight.count or 0) >= 2 or role and plan.needsBackup
		if inbound >= (slots and 2 or 1) then return false, 'already-incoming' end
		return true
	end
	if not J.IsValidBuilding(tower) or landing == nil then return false end
	local threat = observed or J.GetOuterTowerThreat(tower, lane)
	local home = J.GetTeleportHomeLane(bot)
	local hub = tower:GetLocation()
	local speed = math.max(bot:GetCurrentMovementSpeed(), 250)
	local ready = math.max(bot:GetAttackRange(), reach or 0, 250)
	local arrival = LaneTeleportPolicy.ActionETA(4.5, J.GetLocationToLocationDistance(landing, hub), ready, speed)
	local timeToFall = threat.damageRate > 0 and tower:GetHealth() / threat.damageRate or math.huge
	local urgent = threat.heroAttacking and (threat.count >= 2 or threat.waveSize >= 2)
		or threat.count >= 2 and threat.waveSize >= 3 and threat.eta <= 6
		or threat.underAttack and threat.towerHP <= 0.30
	local pressure = urgent or threat.underAttack and threat.waveSize >= 3
		or threat.waveSize >= 2 and threat.siege and threat.eta <= 6
	-- Don't spend a core's early scroll on one unescorted siege unit.
	if threat.count == 0 and threat.waveSize < 2 and not urgent then pressure = false end
	if rear ~= nil and rear ~= tower then
		-- A rear rally is not a chance to save the front tower. During lane
		-- phase keep the core home unless the rear tower itself needs help.
		return false
	end
	local incoming, covered = {}, 0
	local limit = planned and threat.count >= 3 and 2 or 1
	if planned and threat.middleGroup and threat.eta <= 8 then pressure, urgent = true, true end
	if not pressure then return false, 'no-live-pressure' end
	for _, tp in ipairs(GetIncomingTeleports()) do
		if tp.playerid ~= nil and tp.playerid ~= bot:GetPlayerID() and tp.location ~= nil
			and tp.time_remaining ~= nil and tp.time_remaining >= 0 and tp.time_remaining <= 5
			and GetTeamForPlayer(tp.playerid) == bot:GetTeam()
			and J.GetLocationToLocationDistance(tp.location, hub) <= 1150 then incoming[tp.playerid] = tp end
	end
	for slot = 1, #GetTeamPlayers(bot:GetTeam()) do
		local ally = GetTeamMember(slot)
		if ally ~= bot and J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally)
			and not J.IsRetreating(ally) and not J.IsDisabled(ally) and J.GetHP(ally) >= 0.55 then
			local tp = incoming[ally:GetPlayerID()]
			local point = tp and tp.location or ally:GetLocation()
			local distance = J.GetLocationToLocationDistance(point, hub)
			local started = ally.ohaLaneDefenseTP
			local reach = math.max(ally:GetAttackRange(), 250)
			if distance <= 1450 and (tp or not ally:IsChanneling() and not ally:HasModifier('modifier_teleporting'))
				and (tp or reach >= 450 or ally:GetAssignedLane() == lane
					or started and started.lane == lane and DotaTime() - started.time < 10) then
				local eta = LaneTeleportPolicy.ActionETA(tp and tp.time_remaining or 0, distance, reach, ally:GetCurrentMovementSpeed())
				if LaneTeleportPolicy.CoversDeadline(eta, timeToFall) then covered = covered + 1 end
			end
		end
	end
	-- A support or core who walks there nearly as soon keeps the scroll
	-- and can react again after the initial pressure. Check the walking path.
	local origin, destination = bot:GetLocation(), landing
	local gap = J.GetLocationToLocationDistance(origin, destination)
	local walking = LaneTeleportPolicy.ActionETA(0, GetUnitToLocationDistance(bot, hub), ready, speed) * 1.15
	if gap <= 2300 and walking <= arrival + 1 and LaneTeleportPolicy.CoversDeadline(walking, timeToFall) then
		local midpoint = gap > 25 and J.VectorTowards(origin, destination, gap * 0.5) or origin
		if IsLocationPassable(midpoint) and #J.GetEnemiesNearLoc(midpoint, 950) == 0
			and #J.GetLastSeenEnemiesNearLoc(midpoint, 950) == 0 then return false, 'walk-comparable' end
	end
	local prior = bot.ohaLaneDefenseTP
	return LaneTeleportPolicy.Defense({
		observed = threat.heroAttacking or threat.waveSize > 0,
		pressure = pressure,
		arrival = arrival,
		timeToFall = timeToFall,
		covered = covered >= limit,
		sourceValuable = home ~= lane and HasSourceLaneOpportunity(bot, home),
		urgent = urgent,
		reversing = prior ~= nil and prior.lane ~= lane and DotaTime() - prior.time < 105,
	})
end

-- Route only on information our team can observe. Sample a corridor rather than
-- treating an empty destination as proof that the way there is clear.
function J.IsHighGroundResponseThreat(threat)
    return threat.count >= 3 and (threat.siegeAttacking or threat.waveSize >= 2
        and (threat.underAttack or threat.eta <= 9))
end

local function GetHighGroundPathThreats(bot, destination)
    local locations, seen = {}, {}
    local start = bot:GetLocation()
    local range = J.GetLocationToLocationDistance(start, destination) + 2300
    for _, enemy in ipairs(J.GetEnemiesNearLoc(start, range)) do
        if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and not seen[enemy:GetPlayerID()] then
            seen[enemy:GetPlayerID()] = true
            locations[#locations + 1] = {point = enemy:GetLocation(), radius = math.max(750, enemy:GetAttackRange() + 260)}
        end
    end
    for _, id in ipairs(J.GetLastSeenEnemiesNearLoc(start, range)) do
        local info = not seen[id] and GetHeroLastSeenInfo(id) or nil
        if info and info[1] then
            seen[id] = true
            locations[#locations + 1] = {point = info[1].location, radius = 850}
        end
    end
    return locations
end

local function HighGroundSegmentClear(a, b, threats)
    local dx, dy = b.x - a.x, b.y - a.y
    local length2 = dx * dx + dy * dy
    for _, threat in ipairs(threats) do
        local px, py = threat.point.x - a.x, threat.point.y - a.y
        local f = length2 > 0 and math.max(0, math.min(1, (px * dx + py * dy) / length2)) or 0
        local x, y = px - f * dx, py - f * dy
        if x * x + y * y < threat.radius * threat.radius then return false end
    end
    -- A single order can otherwise route around a cliff into the enemy.
    local steps = math.max(1, math.ceil(math.sqrt(length2) / 600))
    for i = 1, steps do
        if not IsLocationPassable(Vector(a.x + dx * i / steps, a.y + dy * i / steps, b.z)) then return false end
    end
    return true
end

function J.GetHighGroundWalkPoint(bot, stage, rear)
    local start = bot:GetLocation()
    local foes = GetHighGroundPathThreats(bot, stage)
    if HighGroundSegmentClear(start, stage, foes) then return stage end
    local dx, dy = stage.x - start.x, stage.y - start.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1 then return nil end
    local candidate, best = nil, math.huge
    for _, offset in ipairs({1000, -1000, 1900, -1900}) do
        local point = Vector(start.x + dx * 0.5 - dy / length * offset,
            start.y + dy * 0.5 + dx / length * offset, stage.z)
        if HighGroundSegmentClear(start, point, foes) and HighGroundSegmentClear(point, stage, foes) then
            local route = J.GetLocationToLocationDistance(start, point) + J.GetLocationToLocationDistance(point, stage)
            if route < best then candidate, best = point, route end
        end
    end
    if candidate then return candidate end
    -- A safe rear regroup can still be useful. If starting in danger or no route
    -- is known, don't issue a long order; retreat/hero abilities remain in charge.
    if rear and HighGroundSegmentClear(start, rear, foes) then return rear end
    return nil
end

function J.GetHighGroundResponseTeleport(bot, stage, anchors)
    if J.GetHP(bot) < 0.50 or bot:WasRecentlyDamagedByAnyHero(2)
        or not J.CanCommitToLaneTeleport(bot, bot:GetLocation(), true, 975) then return nil end
    local speed = math.max(1, bot:GetCurrentMovementSpeed())
    local walk = GetUnitToLocationDistance(bot, stage) / speed
    local best, bestTime = nil, walk - 2
    local threats = GetHighGroundPathThreats(bot, stage)
    for _, tower in ipairs(anchors) do
        if J.IsValidBuilding(tower) then
            local point = J.AdjustLocationWithOffsetTowardsFountain(tower:GetLocation(), 240)
            local distance = J.GetLocationToLocationDistance(point, stage)
            local time = 4 + distance / speed
            if time < bestTime and IsLocationPassable(point)
                and J.CanCommitToLaneTeleport(bot, point, true, 1050)
                and HighGroundSegmentClear(point, stage, threats) then
                best, bestTime = point, time
            end
        end
    end
    return best
end

-- Explicit, conservative roster knowledge. Never infer that an unseen ultimate is ready.
-- Values are spacing heuristics, not spell radii: these spells have different shapes.
local fightControlSpacing = {
	warlock = 640, enigma = 570, faceless_void = 650, magnataur = 530,
	earthshaker = 620, tidehunter = 720, sand_king = 620, centaur = 500,
	disruptor = 540, mars = 640, phoenix = 640, dark_seer = 540,
	treant = 650, axe = 460, slardar = 450, elder_titan = 550,
}

local function FightHeroKey(hero)
	return string.gsub(hero:GetUnitName(), '^npc_dota_hero_', '')
end

local function IsFightFocusCandidate(enemy)
	return J.IsValidHero(enemy) and J.CanBeAttacked(enemy) and not J.IsSuspiciousIllusion(enemy)
		and not enemy:HasModifier('modifier_skeleton_king_reincarnation_scepter_active')
		and not (J.CannotBeKilled and J.CannotBeKilled(nil, enemy))
end

local function CanProvideFightContact(ally)
	return J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally) and J.GetHP(ally) >= 0.38
		and not J.IsRetreating(ally) and not ally:HasModifier('modifier_teleporting')
		and not ally:IsChanneling() and not ally:IsStunned() and not ally:IsHexed()
		and not ally:IsNightmared() and not ally:IsDisarmed()
end

local function HasFightContact(unit, enemy, buffer)
	return J.IsInRange(unit, enemy, unit:GetAttackRange() + (unit:IsRooted() and 0 or buffer))
end

-- Control is local and observable. A channel can hold a target without
-- adding a fictitious mobile attacker to the reinforcement calculation.
function J.GetFightHardControlRemaining(enemy)
	if not enemy.NumModifiers or not enemy.GetModifierName or not enemy.GetModifierRemainingDuration then return 0 end
	local longest = 0
	for i = 0, enemy:NumModifiers() - 1 do
		local name = enemy:GetModifierName(i) or ''
		if name == 'modifier_stunned' or string.find(name, 'voodoo', 1, true)
			or string.find(name, 'shackles', 1, true) or string.find(name, 'hex', 1, true)
			or name == 'modifier_skeleton_king_hellfire_blast_stun' then
			longest = math.max(longest, enemy:GetModifierRemainingDuration(i) or 0)
		end
	end
	return longest
end

function J.GetFightDisableDelay(bot, enemy)
	local remaining = J.GetFightHardControlRemaining(enemy)
	local now = DotaTime()
	local pending = enemy.ohaFightDisable
	if pending and pending.caster ~= bot and pending.expiry > now and J.IsValidHero(pending.caster) then
		remaining = math.max(remaining, pending.impact - now + 0.65)
	end
	-- A teammate's projectile is observable even when their queued order isn't.
	if enemy.GetIncomingTrackingProjectiles then
		for _, shot in ipairs(enemy:GetIncomingTrackingProjectiles()) do
			if not shot.is_attack and shot.ability and shot.caster and shot.caster:GetTeam() == bot:GetTeam()
				and shot.caster ~= bot and J.IsStunProjectileSpell(shot.ability:GetName())
				and GetUnitToLocationDistance(enemy, shot.location) <= 500 then
				-- Recheck after impact and chain from the observed modifier duration.
				return math.huge
			end
		end
	end
	return remaining
end

function J.NoteFightDisable(bot, enemy, delay)
	local now = DotaTime()
	enemy.ohaFightDisable = {caster=bot, impact=now+delay, expiry=now+delay+0.22}
end

-- Follow-up for a proactive single-target opening, not a peel or interrupt.
function J.HasCommittedStunFollowUp(bot, target, damage)
	local enemies = J.GetEnemiesNearLoc(target:GetLocation(), 1250)
	local hits = HasFightContact(bot, target, 75) and 1 or 0
	local participants = hits
	for _, ally in ipairs(J.GetAlliesNearLoc(target:GetLocation(), 1600)) do
		if ally ~= bot and CanProvideFightContact(ally) and HasFightContact(ally, target, 100) then
			participants = participants + 1
			hits = hits + 1
			damage = damage + ally:GetEstimatedDamageToTarget(false, target, 1.6, DAMAGE_TYPE_PHYSICAL)
		end
	end
	if damage >= target:GetHealth() * 1.08 and participants >= 1 then return true end
	return hits >= math.max(2, #enemies) and not J.ShouldHoldFightApproach(bot, target)
end

function J.GetSupportedFightTarget(bot, enemies, allies)
	if DotaTime() < 8 * 60 or J.GetHP(bot) < 0.45 or not CanProvideFightContact(bot) then return nil end
	local towers = bot:GetNearbyTowers(1600, true)
	local ready = {}
	local engaged, controlling = false, {}
	for _, ally in ipairs(allies) do
		local t = ally.ohaFightControlTarget
		if t and ally.IsChanneling and ally:IsChanneling() and J.IsValidHero(t)
			and J.GetFightHardControlRemaining(t) > 0 then controlling[t] = true end
		if ally ~= bot and CanProvideFightContact(ally) then
			ready[#ready + 1] = ally
			local target = ally:GetAttackTarget()
			if J.IsValidHero(target) and target:GetTeam() ~= ally:GetTeam() and not J.IsSuspiciousIllusion(target)
				and HasFightContact(ally, target, 250) then engaged = true end
		end
	end
	local best, bestScore = nil, -math.huge
	for _, enemy in ipairs(enemies) do
		if IsFightFocusCandidate(enemy) and HasFightContact(bot, enemy, 450) then
			local safe = true
			for _, tower in ipairs(towers) do
				if J.IsValidBuilding(tower) and J.IsInRange(enemy, tower, 800) then safe = false; break end
			end
			if safe and J.CanTakePostFightTrip and not J.CanTakePostFightTrip(bot,enemy:GetLocation())
				and not HasFightContact(bot,enemy,90) then safe=false end
			if safe then
				local committed, inRange = 0, 0
				local burst = HasFightContact(bot, enemy, 70)
					and bot:GetEstimatedDamageToTarget(false, enemy, 1.6, DAMAGE_TYPE_PHYSICAL) or 0
				for _, ally in ipairs(ready) do
					if HasFightContact(ally, enemy, 250) then
						inRange = inRange + 1
						if ally:GetAttackTarget() == enemy then committed = committed + 1 end
						if HasFightContact(ally, enemy, 70) then
							burst = burst + ally:GetEstimatedDamageToTarget(false, enemy, 1.6, DAMAGE_TYPE_PHYSICAL)
						end
					end
				end
				-- Keep the original hard contact safeguards, but distinguish
				-- a plausible 2s chain from raw DPS/unavailable abilities.
				local interval = J.GetFightContactDamage and J.GetFightContactDamage(bot, enemy, ready)
				local burstReady = burst >= math.max(1, enemy:GetHealth()) * 1.15
					or interval and interval.typical >= enemy:GetHealth() * 1.12
						and interval.low >= enemy:GetHealth() * 0.58
				local name = FightHeroKey(enemy)
				local dangerousChannel = enemy:IsChanneling() and fightControlSpacing[name] ~= nil
					and not enemy:HasModifier('modifier_teleporting')
				local hardDisabled = enemy:IsStunned() or enemy:IsHexed() or enemy:IsNightmared()
				local liveControl = hardDisabled or J.GetFightHardControlRemaining(enemy) > 0
				local localFollow = liveControl and HasFightContact(bot, enemy, 100)
				local selfLethal = localFollow and burst >= enemy:GetHealth() * 1.15
				local canCast = not hardDisabled and not (enemy.IsSilenced and enemy:IsSilenced())
				local recentUltimate = J.HasRecentlySeenFightUltimate and J.HasRecentlySeenFightUltimate(enemy)
				local spellThreat = fightControlSpacing[name] and canCast and (recentUltimate and 0.55 or 1.45) or 0
				local damageThreat = math.min(enemy:GetAttackDamage() / 250, 1.5)
				local location = enemy:GetLocation()
				local attacked=enemy:GetAttackTarget()
				local peel=J.IsValidHero(attacked) and attacked:GetTeam()==bot:GetTeam() and J.IsCore(attacked)
					and J.GetHP(attacked)<0.62 and HasFightContact(enemy,attacked,150)
				local exposed = HasFightContact(bot, enemy, 120) and inRange > 0
					and (J.GetHP(enemy) <= 0.72 or burstReady or dangerousChannel)
				local pickoff = inRange > 0 and J.GetHP(bot) >= 0.65 and J.GetHP(enemy) <= 0.55
					and HasFightContact(bot, enemy, 70) and #J.GetEnemiesNearLoc(location, 1250) == 1
					and (burst >= enemy:GetHealth() * 1.15 or interval and interval.low >= enemy:GetHealth() * 1.05)
				-- Do not drag the team toward a full-health backline just because of its roster role.
				if (inRange > 0 or selfLethal or localFollow and controlling[enemy])
					and (committed > 0 or pickoff or peel and HasFightContact(bot,enemy,100) or localFollow
						or engaged and exposed and (spellThreat > 0 or damageThreat >= 1))
					and J.GetAvailableFightAllies(bot, location, 1250) + 1 >= #J.GetEnemiesNearLoc(location, 1250) then
					local score = math.min(committed, 2) * 0.5 + (1 - J.GetHP(enemy)) * 1.8
						+ damageThreat + spellThreat + (dangerousChannel and 1.15 or 0) + (burstReady and 1.05 or 0)
						+ (HasFightContact(bot, enemy, 75) and 0.25 or 0) + (peel and 2.25 or 0)
						+ (localFollow and 0.55 or 0)
					if bot.ohaFightFocus == enemy and (bot.ohaFightFocusUntil or 0) > DotaTime() then score = score + 0.3 end
					if score > bestScore or (score == bestScore and enemy:GetPlayerID() < best:GetPlayerID()) then
						best, bestScore = enemy, score
					end
				end
			end
		end
	end
	return best
end


local function IsLocalFightStep(bot, point, towers)
	local origin = bot:GetLocation()
	local mid = Vector((origin.x + point.x) / 2, (origin.y + point.y) / 2, origin.z)
	local height = GetHeightLevel(origin)
	if not IsLocationPassable(mid) or not IsLocationPassable(point) or not IsLocationVisible(point)
		or GetHeightLevel(mid) ~= height or GetHeightLevel(point) ~= height then return false end
	for _, tower in ipairs(towers) do
		if J.IsValidBuilding(tower) and GetUnitToLocationDistance(tower, point) < 825
			and GetUnitToUnitDistance(tower, bot) > GetUnitToLocationDistance(tower, point) + 25 then return false end
	end
	return true
end

-- Tower defense has a staging phase, so don't wait for three allies or an
-- active attack target to separate a ranged clearer from the frontliner.
function J.GetTowerHoldFormationPoint(bot, hub, hold, reach, enemies, allies)
	if bot:GetAttackRange() < 420 or bot:IsRooted() or J.GetHP(bot) < 0.5
		or #enemies < 2 then return nil end
	local origin = bot:GetLocation()
	if GetUnitToLocationDistance(bot, hold) > 800 then return nil end
	local radius = 0
	for _, enemy in ipairs(enemies) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy)
			and not (enemy.IsSilenced and enemy:IsSilenced()) then
			radius = math.max(radius, fightControlSpacing[FightHeroKey(enemy)] or 0)
		end
	end
	if radius <= 0 then return nil end

	local dx, dy = hold.x - hub.x, hold.y - hub.y
	local length = math.sqrt(dx * dx + dy * dy)
	if length < 150 then return nil end
	local ux, uy = dx / length, dy / length
	local anchors = {}
	for _, ally in ipairs(allies) do
		if ally ~= bot and J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally)
			and (ally:GetAttackRange() < 420 or ally:GetPlayerID() < bot:GetPlayerID())
			and GetUnitToLocationDistance(ally, hold) < radius + 110 then
			anchors[#anchors + 1] = ally
		end
	end
	if #anchors == 0 then return nil end
	local function crowding(point)
		local penalty = 0
		for _, ally in ipairs(anchors) do
			local d = GetUnitToLocationDistance(ally, point)
			penalty = penalty + math.max(0, radius - d)^2
		end
		return penalty
	end
	local best, score = nil, crowding(hold) - 65^2
	local side = bot:GetPlayerID() % 2 == 0 and 1 or -1
	local towers = bot:GetNearbyTowers(1600, true)
	for _, sign in ipairs({side, -side}) do
		local point = Vector(hold.x + ux * 50 - uy * sign * 490,
			hold.y + uy * 50 + ux * sign * 490, hold.z or origin.z)
		if J.GetLocationToLocationDistance(point, hub) <= math.max(length, reach - 100)
			and IsLocalFightStep(bot, point, towers) and #J.GetEnemiesNearLoc(point, 725) == 0 then
			local ahead = false
			for _, enemy in ipairs(enemies) do
				if J.IsValidHero(enemy) and GetUnitToLocationDistance(enemy, point)
					< GetUnitToLocationDistance(enemy, hold) - 90 then ahead = true; break end
			end
			local penalty = crowding(point)
			if not ahead and penalty < score then best, score = point, penalty end
		end
	end
	return best
end

function J.GetTowerPeelTarget(bot, enemies, castRange)
	local state = bot._defend
	local tower = state and (state.waveClearRearTower or state.waveClearTower)
	if not J.IsValidBuilding(tower) or not J.IsDefending(bot) or (bot.ohaOuterTowerHoldUntil or 0) <= DotaTime()
		or not J.IsInRange(bot, tower, 1200) then return nil end
	local best, score = nil, 0
	for _, enemy in ipairs(enemies) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and not J.IsDisabled(enemy)
			and J.IsInRange(bot, enemy, castRange) and J.CanCastOnNonMagicImmune(enemy)
			and J.CanCastOnTargetAdvanced(enemy) then
			local victim = enemy:GetAttackTarget()
			if J.IsValidHero(victim) and victim:GetTeam() == bot:GetTeam() and J.IsInRange(victim, tower, 1100)
				and victim:WasRecentlyDamagedByHero(enemy, 2.5) then
				local pressure = 1 + (1 - J.GetHP(victim)) + (victim:GetAttackRange() >= 420 and 1 or 0)
					+ (J.IsDisabled(victim) and 0.5 or 0)
				if pressure > score then best, score = enemy, pressure end
			end
		end
	end
	return best
end

function J.GetTeamfightSpreadPoint(bot, target, enemies, allies)
	if DotaTime() < 12 * 60 or #enemies < 2 or bot:GetAttackRange() < 420
		or not IsFightFocusCandidate(target) or not CanProvideFightContact(bot) or bot:IsRooted()
		or (J.IsAttacking and J.IsAttacking(bot)) or J.GetHP(bot) < 0.55
		or (target:IsChanneling() and HasFightContact(bot, target, 35)) then return nil end

	local origin, enemyPoint = bot:GetLocation(), target:GetLocation()
	if not HasFightContact(bot, target, 180) then return nil end
	local radius = 0
	for _, enemy in ipairs(enemies) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and J.IsInRange(bot, enemy, 1450)
			and not (enemy.IsSilenced and enemy:IsSilenced()) then
			radius = math.max(radius, fightControlSpacing[FightHeroKey(enemy)] or 0)
		end
	end
	if radius == 0 then return nil end

	-- Frontliners keep their position; among ranged allies the lowest ID anchors.
	local friends, anchor, cover = {}, false, false
	for _, ally in ipairs(allies) do
		if ally ~= bot and CanProvideFightContact(ally) and J.IsInRange(bot, ally, 1250) then
			friends[#friends + 1] = ally
			local distance = GetUnitToUnitDistance(bot, ally)
			if distance < radius and (ally:GetAttackRange() < 420 or ally:GetPlayerID() < bot:GetPlayerID()) then anchor = true end
			if HasFightContact(ally, target, 250) then cover = true end
		end
	end
	if #friends < 2 or not anchor or not cover then return nil end

	local length = math.sqrt((enemyPoint.x - origin.x)^2 + (enemyPoint.y - origin.y)^2)
	if length < 100 then return nil end
	local ux, uy = (enemyPoint.x - origin.x) / length, (enemyPoint.y - origin.y) / length
	local towers = bot:GetNearbyTowers(1600, true)
	local function congestion(point)
		local score = 0
		for _, ally in ipairs(friends) do
			local d = GetUnitToLocationDistance(ally, point)
			score = score + math.max(0, radius - d)^2
		end
		return score
	end
	local best, bestScore = nil, congestion(origin) - (radius * 0.28)^2
	-- Try short side steps, not long flanks. A small rearward offset preserves the firing line.
	local sign = bot:GetPlayerID() % 2 == 0 and 1 or -1
	for _, side in ipairs({sign, -sign}) do
		local point = Vector(origin.x - ux * 70 - uy * side * 290, origin.y - uy * 70 + ux * side * 290, origin.z)
		local attackRange = bot:GetAttackRange()
		local reach = attackRange + (length <= attackRange and 75 or 180)
		local exposure = false
		if GetUnitToLocationDistance(target, point) <= reach
			and GetUnitToLocationDistance(target, point) <= length + 155 and IsLocalFightStep(bot, point, towers) then
			for _, enemy in ipairs(enemies) do
				if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy)
					and GetUnitToLocationDistance(enemy, point) < GetUnitToUnitDistance(bot, enemy) - 75 then
					exposure = true
					break
				end
			end
			if not exposure then
				local score = congestion(point)
				if score < bestScore then best, bestScore = point, score end
			end
		end
	end
	return best
end

-- Revalidate every tick; throttle starting a new move and let the short sidestep finish.
function J.TryTeamfightSpread(bot, target, enemies, allies)
	local now = DotaTime()
	local point = J.GetTeamfightSpreadPoint(bot, target, enemies, allies)
	if point == nil then return false end
	if (bot.ohaSpreadUntil or 0) > now then
		return bot.ohaSpreadPoint ~= nil and J.GetLocationToLocationDistance(point, bot.ohaSpreadPoint) <= 170
			and IsLocalFightStep(bot, bot.ohaSpreadPoint, bot:GetNearbyTowers(1600, true))
	end
	if (bot.ohaNextSpreadAt or 0) > now then return false end
	bot.ohaSpreadUntil, bot.ohaNextSpreadAt, bot.ohaSpreadPoint = now + 0.60, now + 1.10, point
	bot:Action_MoveToLocation(point)
	return true
end

-- Do not count a walk toward a receding hero as guaranteed contact.
-- Use only visible movement, current attack pressure, and reachable teammates.
function J.ShouldHoldFightApproach(bot, target)
	if DotaTime() < 8 * 60 or not J.IsValidHero(target) or target:GetTeam() == bot:GetTeam() then return false end
	local distance = GetUnitToUnitDistance(bot, target)
	local gap = distance - bot:GetAttackRange() - 75
	if gap <= 0 then return false end
	if bot:IsRooted() or not IsFightFocusCandidate(target) then return true end
	if J.CanTakePostFightTrip and not J.CanTakePostFightTrip(bot,target:GetLocation()) then return true end

	local origin, location = bot:GetLocation(), target:GetLocation()
	local stopMovement = target:IsRooted() or target:IsStunned() or target:IsHexed() or target:IsNightmared()
	local allies = J.GetAlliesNearLoc(location, 1200)
	local pressure, inContact = false, 0
	for _, ally in ipairs(allies) do
		if ally ~= bot and CanProvideFightContact(ally) and HasFightContact(ally, target, 110) then
			inContact = inContact + 1
			if ally:GetAttackTarget() == target then pressure = true end
		end
	end

	for _, tower in ipairs(bot:GetNearbyTowers(1600, true)) do
		if J.IsValidBuilding(tower) and J.IsInRange(target, tower, 800) and not pressure then return true end
	end
	if GetHeightLevel(location) > GetHeightLevel(origin) and not pressure then return true end

	local drift = 0
	if not stopMovement then
		local nextPoint = target:GetExtrapolatedLocation(0.75)
		if nextPoint ~= nil then
			drift = math.max(0, (J.GetLocationToLocationDistance(origin, nextPoint) - distance) / 0.75)
		end
	end
	local selfSpeed = math.max(1, bot:GetCurrentMovementSpeed())
	local firedUpon = bot:WasRecentlyDamagedByAnyHero(1.75) or target:GetAttackTarget() == bot
	local closingTime = gap / math.max(1, selfSpeed - drift)

	if firedUpon and not pressure and closingTime > 1.0 and J.GetHP(bot) <= 0.75 then
		local defenders = 0
		for _, enemy in ipairs(J.GetEnemiesNearLoc(location, 1100)) do
			if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) then defenders = defenders + 1 end
		end
		if defenders >= inContact + 3 then return true end
	end
	if drift >= selfSpeed * 0.58 and closingTime > (pressure and 3.5 or 2.2) then return true end
	if firedUpon and not pressure and not stopMovement and target:GetAttackRange() >= bot:GetAttackRange() + 130
		and distance <= target:GetAttackRange() + 275 and closingTime > 1.2 then return true end
	if gap >= 130 then
		local step = J.VectorTowards(origin, location, math.min(375, gap))
		local opponents = J.GetEnemiesNearLoc(step, 1600)
		if #opponents >= 2 then
			local window = math.min(3.2, closingTime + 1.6)
			local damage, control, contacts = J.GetVisibleThreatAt(bot, opponents, step, window, true)
			local health = bot:GetHealth() + window * bot:GetHealthRegen()
			if contacts >= 2 and damage >= health * (control and contacts > inContact + 1 and 0.78 or 1) then
				return true
			end
		end
	end
	return false
end

function J.TryHoldFightApproach(bot, target)
	if not J.ShouldHoldFightApproach(bot, target) then return false end
	if bot:GetTarget() == target then bot:SetTarget(nil) end
	if bot:IsRooted() or (J.IsAttacking and J.IsAttacking(bot)) then
		if bot:IsRooted() and bot:GetAttackTarget() == target then bot:Action_ClearActions(true) end
		return true
	end

	local origin, enemyPoint = bot:GetLocation(), target:GetLocation()
	local dist = GetUnitToUnitDistance(bot, target)
	local length = math.sqrt((enemyPoint.x - origin.x)^2 + (enemyPoint.y - origin.y)^2)
	if length < 100 then return true end
	local ux, uy = (enemyPoint.x - origin.x) / length, (enemyPoint.y - origin.y) / length
	local towers = bot:GetNearbyTowers(1600, true)
	local enemies = J.GetEnemiesNearLoc(origin, 1450)
	local friends = J.GetAlliesNearLoc(origin, 1250)
	local best, bestScore = nil, math.huge
	local rear = 185
	for _, side in ipairs({0, 1, -1}) do
		local point = Vector(origin.x - ux * rear - uy * side * 230, origin.y - uy * rear + ux * side * 230, origin.z)
		if GetUnitToLocationDistance(target, point) >= dist + 100 and IsLocalFightStep(bot, point, towers) then
			local exposure = false
			for _, enemy in ipairs(enemies) do
				if GetUnitToLocationDistance(enemy, point) < GetUnitToUnitDistance(enemy, bot) - 35 then
					exposure = true; break
				end
			end
			if not exposure then
				local support = math.huge
				for _, ally in ipairs(friends) do
					if ally ~= bot and CanProvideFightContact(ally) then
						local d = GetUnitToLocationDistance(ally, point)
						if d <= 1150 and d <= GetUnitToUnitDistance(ally, bot) + 115 then support = math.min(support, d) end
					end
				end
				local score = support
				if support == math.huge then
					-- Alone, take only the short rear step if it also leads home.
					local home = J.GetTeamFountain()
					if side == 0 and J.GetLocationToLocationDistance(point, home) < J.GetLocationToLocationDistance(origin, home) then score = 1500 end
				end
				if score < bestScore then best, bestScore = point, score end
			end
		end
	end

	local now = DotaTime()
	if best ~= nil then
		local old = bot.ohaFightApproachPoint
		if old ~= nil and bot.ohaFightApproachTarget == target and (bot.ohaFightApproachUntil or 0) > now
			and J.GetLocationToLocationDistance(old, best) <= 140 and IsLocalFightStep(bot, old, towers) then return true end
		bot.ohaFightApproachPoint, bot.ohaFightApproachTarget, bot.ohaFightApproachUntil = best, target, now + 0.5
		bot:Action_MoveToLocation(best)
	elseif bot:GetAttackTarget() == target then
		bot:Action_ClearActions(true)
	end
	return true
end

function J.IsSiegeSummon(name)
	return string.find(name, 'shadow_shaman_ward', 1, true) ~= nil or string.find(name, 'warlock_golem', 1, true) ~= nil
		or string.find(name, 'wraith_king_skeleton_warrior', 1, true) ~= nil
end

function J.GetOuterTowerThreat(tower, lane)
	local hub = tower:GetLocation()
	local key = 'OuterTowerThreat:' .. tostring(lane) .. ':' .. tower:GetUnitName()
	local cached = J.Utils.GetCachedVars(key, 0.3)
	if cached ~= nil then return cached end
	local towerTrack = GetAmountAlongLane(lane, hub)
	local direction = GetTeam() == TEAM_RADIANT and 1 or -1
	local function onApproach(location)
		local track = GetAmountAlongLane(lane, location)
		return track.distance <= 850 and (track.amount - towerTrack.amount) * direction >= -0.025
	end

	local seen = {}
	local near = {}
	local visible = {}
	local activeAttackers = 0
	local advancingEscort = false
	local visibleAdvance = 0
	for _, id in ipairs(J.GetLastSeenEnemiesNearLoc(hub, 1600)) do seen[id], near[id] = true, true end
	local forwardRange = lane == LANE_MID and string.find(tower:GetUnitName(), 'tower1_mid', 1, true) and 3800 or 3200
	for _, enemy in ipairs(J.GetEnemiesNearLoc(hub, forwardRange)) do
		local id = enemy:GetPlayerID()
		local attacking = enemy:GetAttackTarget() == tower
		local advancing = onApproach(enemy:GetLocation()) and enemy:IsFacingLocation(hub, 50)
		if attacking then activeAttackers = activeAttackers + 1 end
		advancingEscort = advancingEscort or attacking or advancing
		if advancing or attacking then visibleAdvance = visibleAdvance + 1 end
		if GetUnitToUnitDistance(enemy, tower) <= 1600 then
			seen[id], near[id] = true, true
			visible[id] = enemy
		elseif attacking or advancing then
			seen[id] = true
			visible[id] = enemy
		end
	end
	for _, tp in ipairs(GetIncomingTeleports()) do
		if tp.playerid ~= nil and tp.location ~= nil and tp.time_remaining ~= nil
			and tp.time_remaining >= 0 and tp.time_remaining <= 4 and GetTeamForPlayer(tp.playerid) == GetOpposingTeam()
			and IsLocationVisible(tp.location) and J.GetLocationToLocationDistance(tp.location, hub) <= 2600
			and onApproach(tp.location) then seen[tp.playerid] = true end
	end

	local enemyCount, nearCount = 0, 0
	for _ in pairs(seen) do enemyCount = enemyCount + 1 end
	for _ in pairs(near) do nearCount = nearCount + 1 end
	local waveSize, waveHP, siege, eta = 0, 0, false, math.huge
	local attackingCreeps, siegeAttacking = 0, false
	local clearAt, mostUrgent = nil, -math.huge
	local now = DotaTime()
	-- Several lanes can share a base tower or the Ancient as their front.
	tower.ohaApproachingCreeps = tower.ohaApproachingCreeps or {}
	local previousWave = tower.ohaApproachingCreeps[lane] or {}
	local currentWave = {}
	-- Creep movement speed is a capability. A distant catapult firing into an
	-- allied wave can stay on the same spot for minutes without approaching.
	local function closingSpeed(creep, distance)
		local speed = math.max(1, creep:GetCurrentMovementSpeed())
		if distance <= 1280 then return speed end
		local sample = previousWave[creep]
		if not sample or now - sample.seen > 2.5 then
			local projected = creep.GetExtrapolatedLocation and creep:GetExtrapolatedLocation(1)
			local advance = projected and distance - J.GetLocationToLocationDistance(projected, hub) or 0
			sample = {distance=distance, time=now, speed=not creep:GetAttackTarget() and math.max(0, advance) or 0}
		elseif now - sample.time >= 0.6 then
			sample.speed = math.max(0, (sample.distance - distance) / (now - sample.time))
			sample.distance, sample.time = distance, now
		end
		sample.seen = now
		currentWave[creep] = sample
		return math.min(speed, sample.speed)
	end
	for _, creep in ipairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS)) do
		if J.IsValid(creep) and (not creep.CanBeSeen or creep:CanBeSeen()) then
			local name = creep:GetUnitName()
			local distance = GetUnitToUnitDistance(creep, tower)
			local attacking = creep:GetAttackTarget() == tower
			local summon = J.IsSiegeSummon(name)
			local catapult = string.find(name, 'siege', 1, true) ~= nil
			local laneUnit = catapult or string.find(name, 'npc_dota_creep_', 1, true)
			local speed = laneUnit and distance <= 3000 and onApproach(creep:GetLocation())
				and closingSpeed(creep, distance) or 0
			if (attacking and (summon and distance <= 1400 or laneUnit and distance <= 3000)) or speed >= 60 then
				local priority = (attacking and 8 or 0) + ((summon or catapult) and 3 or 0) - distance / 1000
				if priority > mostUrgent and (not creep.CanBeSeen or creep:CanBeSeen()) then
					clearAt, mostUrgent = creep:GetLocation(), priority
				end
				waveSize = waveSize + 1
				siege = siege or summon or catapult
				if not catapult and not summon then waveHP = math.max(waveHP, creep:GetHealth()) end
				if attacking then
					attackingCreeps = attackingCreeps + 1
					siegeAttacking = siegeAttacking or summon or catapult
					eta = 0
				else
					eta = math.min(eta, math.max(0, distance - 650) / speed)
				end
			end
		end
	end
	tower.ohaApproachingCreeps[lane] = currentWave
	-- A visible group already rotating with a wave is actionable before the first hit.
	local escortedWave = advancingEscort and ((siege and waveSize >= 2) or waveSize >= 4
		or enemyCount >= 3 and waveSize >= 2) and eta <= 10
	local middleGroup = lane == LANE_MID and visibleAdvance >= 3 and waveSize >= 2 and eta <= 10
	-- A visible lone catapult on the mid approach earns one clearer, not a teamfight.
	local soloMidSiege = lane == LANE_MID and siege and waveSize == 1 and eta <= 8
	local wavePressure = attackingCreeps >= 2 or siegeAttacking or escortedWave or soloMidSiege
		or (siege and waveSize >= 2 and eta <= 8) or (enemyCount == 1 and waveSize >= 3 and eta <= 5)
	local active = activeAttackers > 0 or (enemyCount >= 2 and (waveSize > 0 or nearCount >= 2)) or wavePressure
	local underAttack = activeAttackers > 0 or attackingCreeps > 0
	local health = tower:GetHealth()
	local watch = tower.ohaSiegeWatch
	if not watch or not watch.time then
		watch = {health = health, time = now, damageRate = 0, lastHit = watch and watch.lastHit}
		tower.ohaSiegeWatch = watch
	end
	if health < watch.health and (underAttack or enemyCount > 0 and waveSize > 0) then watch.lastHit = now end
	local elapsed = now - watch.time
	if elapsed >= 0.25 then
		local damage = math.max(0, watch.health - health)
		local weight = math.min(1, elapsed / 2.5)
		watch.damageRate = watch.damageRate * (1 - weight) + damage / elapsed * weight
		watch.health, watch.time = health, now
	end
	local briefHold = not active and watch.lastHit ~= nil and now - watch.lastHit <= 10
	local towerHP = health / math.max(1, tower:GetMaxHealth())
	if underAttack and towerHP <= 0.55 and tower.IsTower and tower:IsTower() and tower:GetTeam() == GetTeam() then
		J.recentlyBesiegedTowers = J.recentlyBesiegedTowers or {}
		J.recentlyBesiegedTowers[tower] = {point=tower:GetLocation(), seen=now}
	end
	local enemies = {}
	for _, enemy in pairs(visible) do enemies[#enemies + 1] = enemy end
	if activeAttackers > 0 then eta = 0 end
	local threat = {tower = tower, lane = lane, count = enemyCount, near = nearCount, waveSize = waveSize, waveHP = waveHP,
		enemies = enemies, underAttack = underAttack, damageRate = watch.damageRate, clearAt = clearAt,
		siegeAttacking = siegeAttacking, heroAttacking = activeAttackers > 0,
		siege = siege, eta = eta < math.huge and eta or 0, towerHP = towerHP, briefHold = briefHold,
		middleGroup = middleGroup,
		score = active and (nearCount * 3 + enemyCount * 2 + math.min(waveSize, 8)
			+ activeAttackers * 2 + (siege and 2 or 0) + (underAttack and 12 or escortedWave and 7 or 0))
			* (towerHP > 0.15 and 1 or 0.25) or (briefHold and 1 or 0)}
	J.Utils.SetCachedVars(key, threat)
	return threat
end

-- Do not convert a free mid wave or an exposed mid T1 into an optional
-- cross-map TP. Genuine defense/active fights are handled by their own callers.
function J.ShouldKeepMidOpportunity(bot, targetLane)
    local now = DotaTime()
    if targetLane == LANE_MID or bot:GetAssignedLane() ~= LANE_MID or not J.IsCore(bot)
        or now < 0 or now > 15 * 60 or J.GetHP(bot) < 0.55 or J.IsRetreating(bot) then return false end
    local enemyTower = GetTower(GetOpposingTeam(), TOWER_MID_1)
    if not J.IsValidBuilding(enemyTower) or GetAmountAlongLane(LANE_MID, bot:GetLocation()).distance > 850 then return false end
    local enemies = J.GetEnemiesNearLoc(bot:GetLocation(), 1200)
    if #enemies >= 2 or J.IsLaningUnderPressure(bot, enemies, enemyTower) then return false end
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(1350, true)) do
        if J.IsValid(creep) and GetAmountAlongLane(LANE_MID, creep:GetLocation()).distance <= 600 then return true end
    end
    if #J.GetLastSeenEnemiesNearLoc(enemyTower:GetLocation(), 1350) > 0
        or #J.GetEnemiesNearLoc(enemyTower:GetLocation(), 1350) > 0
        or not J.IsInRange(bot, enemyTower, 1850) then return false end
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(1400, false)) do
        if J.IsValid(creep) and J.IsInRange(creep, enemyTower, 1300)
            and GetAmountAlongLane(LANE_MID, creep:GetLocation()).distance <= 550 then return true end
    end
    return false
end

function J.ShouldKeepMidOverRoutineDefense(bot, targetLane)
    if not J.ShouldKeepMidOpportunity(bot, targetLane) then return false end
    local team = bot:GetTeam()
    local tower = GetTower(team, targetLane == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
    if not J.IsValidBuilding(tower) then
        tower = GetTower(team, targetLane == LANE_TOP and TOWER_TOP_2 or TOWER_BOT_2)
    end
    if not J.IsValidBuilding(tower) then return true end
    local threat = J.GetOuterTowerThreat(tower, targetLane)
    return not (threat.count >= 2 and threat.underAttack
        or threat.count >= 3 and threat.waveSize >= 2
        or threat.siegeAttacking and threat.towerHP < 0.45)
end

-- Keep the only nearby middle core within response range while the other
-- defenders are covering side lanes. This gates only an elective farming TP.
function J.ShouldSaveMidFarmTeleport(bot, targetLane)
    if targetLane == LANE_MID or bot:GetAssignedLane() ~= LANE_MID or not J.IsCore(bot)
        or DotaTime() < 15 * 60 or J.GetHP(bot) < 0.58 or J.IsRetreating(bot)
        or J.GetNumOfAliveHeroes(true) < 4 then return false end
    local team = bot:GetTeam()
    local tower = GetTower(team, TOWER_MID_1)
    if not J.IsValidBuilding(tower) then tower = GetTower(team, TOWER_MID_2) end
    if not J.IsValidBuilding(tower) or not J.IsInRange(bot, tower, 2600) then return false end
    for _, ally in ipairs(J.GetAlliesNearLoc(tower:GetLocation(), 2350)) do
        if ally ~= bot and J.IsValidHero(ally) and J.IsCore(ally) and J.GetHP(ally) >= 0.58
            and not J.IsRetreating(ally) and not J.IsDisabled(ally) and not ally:IsChanneling()
            and not ally:HasModifier('modifier_teleporting')
            and (ally.ohaOuterTowerHoldUntil or 0) <= DotaTime() then return false end
    end
    return true
end

function J.ShouldKeepLaningWave(bot, targetLane, threat)
	local lane = bot:GetAssignedLane()
	local now = DotaTime()
	local openingSideWave = targetLane ~= nil and (lane == LANE_TOP or lane == LANE_BOT)
		and now >= 0 and now < 45
	if lane == targetLane or (lane ~= LANE_MID and lane ~= LANE_TOP and lane ~= LANE_BOT)
		or (not J.IsCore(bot) and not openingSideWave)
		or not J.IsInLaningPhase(bot) or J.GetHP(bot) < 0.55 then return false end
	if targetLane ~= nil and not threat then
		local tower = GetTower(bot:GetTeam(), targetLane == LANE_TOP and TOWER_TOP_1 or (targetLane == LANE_MID and TOWER_MID_1 or TOWER_BOT_1))
		if not J.IsValidBuilding(tower) then
			tower = GetTower(bot:GetTeam(), targetLane == LANE_TOP and TOWER_TOP_2 or (targetLane == LANE_MID and TOWER_MID_2 or TOWER_BOT_2))
		end
		if J.IsValidBuilding(tower) then threat = J.GetOuterTowerThreat(tower, targetLane) end
	end
	if threat and (threat.count >= 3 or threat.siegeAttacking or threat.towerHP < 0.45
		or (threat.count >= 2 and threat.heroAttacking and (threat.waveSize or 0) >= 2)) then return false end
	if GetAmountAlongLane(lane, bot:GetLocation()).distance > 900 then return false end
	local enemies = J.GetEnemiesNearLoc(bot:GetLocation(), 1100)
	if #enemies >= 2 and J.IsLaningUnderPressure(bot, enemies, nil) then return false end
	-- The side-lane wave may not have reached vision yet. Its absence in a
	-- nearby creep scan is not an invitation to leave for a routine rotation.
	if openingSideWave then return true end
	for _, creep in ipairs(bot:GetNearbyLaneCreeps(1250, true)) do
		if J.IsValid(creep) and GetAmountAlongLane(lane, creep:GetLocation()).distance <= 550 then return true end
	end
	return false
end

local function GetWaveClearScore(hero, travelTime)
	local best, bestReach, bestDamage, bestImpact, bestCastRange = 0, 0, 0, math.huge, 0
	for slot = 0, 8 do
		local ability = hero:GetAbilityInSlot(slot)
		if J.CanCastAbilitySoon(ability, travelTime + 3) and not ability:IsUltimate()
			and hero:GetMana() >= ability:GetManaCost() then
			local radius = math.max(ability:GetAOERadius() or 0, ability:GetSpecialValueInt('radius'),
				ability:GetSpecialValueInt('damage_radius'), ability:GetSpecialValueInt('width'),
				ability:GetSpecialValueInt('start_radius'), ability:GetSpecialValueInt('end_radius'))
			local shrapnel = ability:GetSpecialValueInt('shrapnel_damage')
			local damage = math.max(ability:GetAbilityDamage() or 0, ability:GetSpecialValueInt('damage'),
				ability:GetSpecialValueInt('base_damage'),
				shrapnel * math.max(1, math.min(3, ability:GetSpecialValueInt('duration'))))
			local behavior = ability:GetBehavior()
			local needsTarget = J.Utils.AbilityBehaviorHasFlag(behavior, ABILITY_BEHAVIOR_UNIT_TARGET)
				and not J.Utils.AbilityBehaviorHasFlag(behavior, ABILITY_BEHAVIOR_POINT)
			local castRange = ability:GetCastRange()
			local reach = castRange + (needsTarget and 0 or radius)
			if radius >= 100 and damage >= 60 and reach >= 600 and (shrapnel == 0 or ability:IsFullyCastable()) then
				local score = math.sqrt(damage * radius) + math.min(reach, 1400) * 0.25
					- 12 * math.max(0, ability:GetCooldownTimeRemaining() - travelTime)
				local lead = math.max(0, ability:GetCooldownTimeRemaining() - travelTime)
				local cast = ability.GetCastPoint and ability:GetCastPoint() or 0.25
				local impact = lead + cast + (shrapnel ~= 0 and 1.5 or 0.25)
				score = score - impact * 18
				if score > best then
					best, bestReach, bestDamage, bestImpact = score, reach, damage * math.min(1, radius / 250), impact
					bestCastRange = castRange
				end
			end
		end
	end
	return best, bestReach, bestDamage, bestImpact, bestCastRange
end

-- A rear rally is a safe place to assemble. Once the visible wave hits a
-- building, use a reachable firing position on our side of that wave.
function J.GetSiegeFiringPosition(bot, tower, threat, stage)
    local wave = threat and threat.clearAt
    if not wave or not (threat.underAttack or (threat.waveSize or 0) >= 2 and (threat.eta or 99) <= 5)
        or not IsLocationVisible(wave)
        or J.GetHP(bot) < 0.55 or bot:WasRecentlyDamagedByAnyHero(2) then return nil end
    local _, spellReach, damage = GetWaveClearScore(bot, 0)
    local reach = math.max(bot:GetAttackRange(), damage > 0 and spellReach - 90 or 0)
    if reach < 350 or J.GetLocationToLocationDistance(stage, wave) <= reach then return nil end
    local origin = bot:GetLocation()
    if GetUnitToLocationDistance(bot, wave) <= reach and GetUnitToLocationDistance(tower, origin) <= 1400
        and J.CanCommitToLaneTeleport(bot, origin, true, 650) then return origin end
    local point = J.AdjustLocationWithOffsetTowardsFountain(wave, math.max(250, reach - 45))
    if not threat.underAttack and J.GetLocationToLocationDistance(point, J.GetTeamFountain()) >
        GetUnitToLocationDistance(tower, J.GetTeamFountain()) then return nil end
    if GetUnitToLocationDistance(tower, point) > 1600 or not IsLocationVisible(point)
        or not IsLocationPassable(point) or not J.CanCommitToLaneTeleport(bot, point, true, 650)
        or J.GetLocationToLocationDistance(point, wave) > reach then return nil end
    if J.GetHighGroundWalkPoint(bot, point) then return point end
end

-- Keep a reserve within reach of a teammate already defending the wave.
-- Validate each side of the lane independently so the group can spread out.
function J.GetSiegeSupportPosition(bot, tower, threat, stage)
    if not threat.clearAt or not IsLocationVisible(threat.clearAt)
        or not (threat.underAttack or (threat.waveSize or 0) >= 2 and (threat.eta or 99) <= 5)
        or J.GetHP(bot) < 0.65 or bot:WasRecentlyDamagedByAnyHero(2) then return nil end
    local hub = tower:GetLocation()
    if J.GetAvailableFightAllies(bot, hub, 950) == 0 then return nil end
    local _, spellReach, damage = GetWaveClearScore(bot, 0)
    local reach = math.max(bot:GetAttackRange(), damage > 0 and spellReach - 90 or 0)
    if J.GetLocationToLocationDistance(stage, threat.clearAt) <= reach then return nil end
    local depth = bot:GetAttackRange() < 350 and 390 or 600
    local center = J.AdjustLocationWithOffsetTowardsFountain(hub, depth)
    local dx, dy = center.x - hub.x, center.y - hub.y
    local length = math.max(1, math.sqrt(dx*dx + dy*dy))
    local side = bot:GetPlayerID() % 2 == 0 and 1 or -1
    for _, offset in ipairs({side*260, -side*260}) do
        local point = Vector(center.x - dy/length*offset, center.y + dx/length*offset, center.z)
        if IsLocationVisible(point) and IsLocationPassable(point) and GetHeightLevel(point) >= GetHeightLevel(hub)
            and J.GetAvailableFightAllies(bot, point, 850) > 0
            and J.CanCommitToLaneTeleport(bot, point, true, 750) and J.GetHighGroundWalkPoint(bot, point) then
            return point
        end
    end
end

-- Shared coverage for an open lane. Estimates use only live visible / previously
-- sighted threats and the bounded public death-status estimate, never replay data.
local function BuildDefenseLanePlan(team, demand, claimed, now)
	local building, lane, sight = demand.building, demand.lane, demand.sight
	local hub = building:GetLocation()
	local hold = J.AdjustLocationWithOffsetTowardsFountain(hub, demand.open and 750 or 550)
	local enemies = J.GetNumOfAliveHeroes(true)
	local reinforcement = J.GetEnemyReinforcementWindow()
	-- When we cannot see the next wave, do not assume a long reset window.
	local deadline = math.max(5, math.min(18, reinforcement + (enemies >= 2 and 5 or 8)))
	if enemies >= 4 then deadline = math.min(deadline, 13) end
	if sight.underAttack then
		-- Once the wave arrives, ETA is zero. The remaining time to protect
		-- this tower is set by its health and observed rate of damage.
		local life = sight.damageRate and sight.damageRate > 0 and building:GetHealth() / sight.damageRate or 8
		deadline = math.min(deadline, math.max(2, math.min(8, life)))
	else
		if (sight.waveSize or 0) > 0 then deadline = math.min(deadline, math.max(2, sight.eta + 2)) end
		if (sight.count or 0) >= 2 then
			deadline = math.min(deadline, math.max(6, math.min(12, (sight.eta or 0) + 2)))
		end
	end
	if demand.rear then deadline = math.min(12, deadline + 4) end
	local waveSize = sight.waveSize or 0
	local needsBackup = (sight.count or 0) >= 2 or deadline <= 10 and
		(waveSize >= 3 or waveSize >= 2 and sight.siege
			or waveSize == 0 and enemies >= 2 and reinforcement <= 5)
	local plan = {building=building, lane=lane, hold=hold, deadline=deadline, needsBackup=not demand.watch and needsBackup == true,
		waveDefense=not demand.open and waveSize > 0 and (sight.count or 0) <= 1}
	local unsafe = #J.GetEnemiesNearLoc(hold, 800) >= 2
	local rows, incumbent = {}, nil
	local anchors = {}
	for _, towerId in ipairs({TOWER_BASE_1, TOWER_BASE_2}) do
		local tower = GetTower(team, towerId)
		if J.IsValidBuilding(tower) then anchors[#anchors+1] = tower end
	end
	if not demand.open then anchors[#anchors+1] = building end
	local incoming = {}
	for _, tp in ipairs(GetIncomingTeleports()) do
		if tp.playerid ~= nil and tp.location and tp.time_remaining and tp.time_remaining >= 0
			and tp.time_remaining <= 6 and J.GetLocationToLocationDistance(tp.location, hold) <= 1350 then
			incoming[tp.playerid] = tp
		end
	end
	for _, ally in ipairs(J.GetAlliesNearLoc(hold, demand.watch and 750 or unsafe and 2000 or 24000)) do
		if J.IsValidHero(ally) and ally:IsBot() and not ally:IsIllusion() and not claimed[ally:GetPlayerID()]
			and J.GetHP(ally) >= 0.50 and not J.IsRetreating(ally) and not J.IsDisabled(ally) then
			local tp = ally:HasModifier('modifier_teleporting') and incoming[ally:GetPlayerID()]
			if tp or not ally:IsChanneling() and not ally:HasModifier('modifier_teleporting') then
				local point = ally:GetLocation()
				local gap = GetUnitToLocationDistance(ally, hold)
				local speed = math.max(250, ally:GetCurrentMovementSpeed())
				local walk = math.max(0, gap - 550) / speed * 1.25 + 0.6
				local midpoint = J.VectorTowards(point, hold, gap / 2)
				local safe = not unsafe and J.CanCommitToLaneTeleport(ally, hold, true, 700)
					and (gap <= 1200 or J.CanCommitToLaneTeleport(ally, midpoint, true, 850))
				local arrival, teleport = safe and walk or math.huge, nil
				local fireHere = false
				if not tp and not demand.rear and sight.underAttack and sight.clearAt and gap <= 1800
					and not ally:WasRecentlyDamagedByAnyHero(2) and J.CanCommitToLaneTeleport(ally, point, true, 650)
					and #J.GetEnemiesNearLoc(point, 650) == 0 then
					local _, range, damage, impact = GetWaveClearScore(ally, 0)
					fireHere = damage > 0 and (impact or 0.35) <= deadline and GetUnitToLocationDistance(ally, sight.clearAt) <= range
				end
				if fireHere then
					arrival = 0
				elseif tp and not unsafe then
					arrival = tp.time_remaining + math.max(0, J.GetLocationToLocationDistance(tp.location, hold) - 550) / speed * 1.25
				elseif not demand.watch and not unsafe and arrival > deadline
					and J.CanCastAbility(J.GetItem2(ally, 'item_tpscroll'))
					and #J.GetLastSeenEnemiesNearLoc(point, 1600) == 0
					and not J.ShouldKeepLaningWave(ally, lane, sight) then
					local landing = J.GetHighGroundResponseTeleport(ally, hold, anchors)
					if landing then
						local tpETA = 4 + math.max(0, J.GetLocationToLocationDistance(landing, hold) - 550) / speed * 1.25
						if tpETA < arrival and tpETA < deadline and (not J.IsInLaningPhase(ally)
							or J.CanTakeLaneDefenseTeleport(ally, lane, landing, building, nil, true, nil, sight)) then
							arrival, teleport = tpETA, landing
						end
					end
				end
				if arrival < 24 and (not demand.watch or safe and not tp and gap <= 750
					and GetUnitToLocationDistance(ally, hub) <= 1000 and not ally:WasRecentlyDamagedByAnyHero(2)) then
					local score, reach, damage, castLead = GetWaveClearScore(ally, math.min(arrival, deadline))
					if damage == 0 and (demand.watch and ally:GetAttackRange() >= 350 or (sight.count or 0) == 0
						and (sight.waveSize or 0) > 0 and (sight.waveSize or 0) <= 2) then
						reach, damage, castLead = ally:GetAttackRange(), 1, 0.35
					end
					local onSite = fireHere or not tp and gap <= 750 and J.GetHP(ally) >= 0.55
					castLead = castLead or 0.35
					local clearStage = fireHere and point or hold
					local actionablePoint = not demand.rear and not demand.watch and sight.clearAt or nil
					if actionablePoint and J.GetLocationToLocationDistance(actionablePoint, hub) > 1280 then
						-- An approaching wave will move; don't require a defender to chase its present position.
						actionablePoint = hub
					end
					local impact = damage > 0 and arrival + castLead or math.huge
					if damage > 0 and actionablePoint then
						local shortfall = math.max(0, J.GetLocationToLocationDistance(clearStage, actionablePoint) - reach)
						if shortfall > 0 then
							local step = J.VectorTowards(hold, actionablePoint, math.min(500, shortfall))
							local mayStep = shortfall <= 500 and J.CanCommitToLaneTeleport(ally, step, true, 650)
							if mayStep then clearStage = step end
							impact = mayStep and impact + shortfall / speed * 1.25 or math.huge
						end
						-- Use the projected intercept for travel, but only count coverage
						-- as ready once the real, visible target is within reach.
						onSite = onSite and GetUnitToLocationDistance(ally, sight.clearAt) <= reach
					end
					local row = {hero=ally, id=ally:GetPlayerID(), walk=not tp and safe and walk or math.huge,
						arrival=impact, coverArrival=fireHere and (safe and walk or math.huge) or arrival, teleport=teleport, reach=reach, canClear=damage > 0,
						staging=clearStage ~= hold and clearStage or nil,
						onStation=onSite and castLead <= 2 and impact <= deadline,
						score=score - math.min(24, impact) * 34 - (J.GetPosition(ally) == 1 and 100 or 0)}
					rows[#rows+1] = row
					if building.ohaCoverOwner == row.id then incumbent = row end
				end
			end
		end
	end
	table.sort(rows, function(a,b)
		if a.onStation ~= b.onStation then return a.onStation end
		if a.canClear ~= b.canClear then return a.canClear end
		if (a.arrival <= deadline) ~= (b.arrival <= deadline) then return a.arrival <= deadline end
		if a.score == b.score then return a.id < b.id end
		return a.score > b.score
	end)
	local first = LaneTeleportPolicy.TimelyClearer(rows, deadline)
	if first then
		plan.candidates=rows
		-- Do not replace a usable incumbent with someone who has only promised to arrive.
		if incumbent and incumbent.canClear and incumbent.arrival <= deadline and not first.onStation then first=incumbent end
		if incumbent and incumbent.onStation and incumbent.arrival <= deadline then first=incumbent end
		plan.primary=first
		building.ohaCoverOwner=first.id
	else
		building.ohaCoverOwner=nil
	end
	return plan
end

function J.GetPostFightCoverage(team)
	local now = DotaTime()
	if now < 0 then return nil end
	local key = 'SharedDefenseCoverage:' .. tostring(team)
	local cached = J.Utils.GetCachedVars(key, 0.25)
	if cached ~= nil then return cached or nil end
	local demands = {}
	local watch
	for _, ids in ipairs({
		{LANE_MID,TOWER_MID_1,TOWER_MID_2,TOWER_MID_3,BARRACKS_MID_MELEE,BARRACKS_MID_RANGED},
		{LANE_TOP,TOWER_TOP_1,TOWER_TOP_2,TOWER_TOP_3,BARRACKS_TOP_MELEE,BARRACKS_TOP_RANGED},
		{LANE_BOT,TOWER_BOT_1,TOWER_BOT_2,TOWER_BOT_3,BARRACKS_BOT_MELEE,BARRACKS_BOT_RANGED},
	}) do
		local lane = ids[1]
		local building
		for i=2,4 do
			local tower = GetTower(team, ids[i])
			if J.IsValidBuilding(tower) then building=tower; break end
		end
		local open = not building
		if open then
			building = GetBarracks(team, ids[5])
			if not J.IsValidBuilding(building) then building = GetBarracks(team, ids[6]) end
		end
		if open and not J.IsValidBuilding(building) and lane == LANE_MID then building=GetAncient(team) end
		if J.IsValidBuilding(building) then
			local sight = J.GetOuterTowerThreat(building,lane)
			local wave, count = sight.waveSize or 0, sight.count or 0
			local approach = wave >= 2 and (sight.eta or 99) <= 12
				and (sight.middleGroup or count >= 2)
			local immediate = sight.underAttack or approach or wave > 0 and (sight.eta or 99) <= 9
				and (sight.siege or count >= 1)
			local unattendedMid = not open and lane == LANE_MID and wave >= 3 and (sight.eta or 99) <= 7
				and #J.GetAlliesNearLoc(building:GetLocation(),1600)==0
			-- After a favorable fight, leave a real response for a visible
			-- return wave before the push mode sends every healthy core away.
			local enemiesAlive = J.GetNumOfAliveHeroes(true)
			local nextMid = lane == LANE_MID and now >= 12 * 60 and enemiesAlive >= 2 and enemiesAlive <= 3
				and wave >= 2 and (sight.eta or 99) <= 14
			local baseWave = wave >= 3 and (sight.eta or 99) <= 12 and (open
				or ids[4] and GetTower(team, ids[4]) == building)
			if immediate or unattendedMid or nextMid or baseWave or open and lane == LANE_MID then
				local life = sight.damageRate and sight.damageRate > 0 and building:GetHealth() / sight.damageRate or math.huge
				local rear = false
				if not open and sight.underAttack and life < 3.5 and not building:HasModifier('modifier_fountain_glyph') then
					for i=3,4 do
						local nextTower = GetTower(team, ids[i])
						if nextTower ~= building and J.IsValidBuilding(nextTower)
							and GetUnitToLocationDistance(nextTower,building:GetLocation()) < 3300 then
							building,rear=nextTower,true; break
						end
					end
				end
				local value=(immediate and 40 or 0)+(open and 24 or 0)+(sight.underAttack and 20 or 0)
					+math.min(count,5)*5-math.min(sight.eta or 12,12)
				demands[#demands+1]={lane=lane,building=building,sight=sight,open=open,rear=rear,value=value}
			elseif not open and wave == 0 and count <= 1 and (sight.towerHP or 1) <= 0.35
				and GetTower(team, ids[4]) == building then
				local hit = building.ohaSiegeWatch and building.ohaSiegeWatch.lastHit
				if hit and now >= hit and now - hit <= 20 and (not watch or hit > watch.hit) then
					watch = {lane=lane, building=building, sight=sight, watch=true, hit=hit}
				end
			end
		end
	end
	table.sort(demands,function(a,b)
		if a.value == b.value then return a.lane < b.lane end
		return a.value > b.value
	end)
	if #demands == 0 then
		-- Between two waves at a damaged T3, retain one nearby, ready clearer.
		-- An empty wave never spends a TP or reserves the rest of the team.
		local plan = watch and BuildDefenseLanePlan(team, watch, {}, now)
		if plan and plan.primary and plan.primary.onStation then
			plan.candidates = nil
			J.Utils.SetCachedVars(key, plan)
			return plan
		end
		J.Utils.SetCachedVars(key,false)
		return nil
	end
	local lanes, claimed = {}, {}
	-- Reserve distinct clearers before optional cover on any lower-value front.
	for i=1,math.min(3,#demands) do
		local plan=BuildDefenseLanePlan(team,demands[i],claimed,now)
		lanes[#lanes+1]=plan
		if plan.primary then claimed[plan.primary.id]=true end
	end
	for _,plan in ipairs(lanes) do
		plan.backup=nil
		if plan.needsBackup and plan.primary then
			for _,row in ipairs(plan.candidates or {}) do
				-- A screen need not be able to clear the wave itself. Still
				-- require a safe, timely walking or confirmed TP route.
				if not claimed[row.id] and row.coverArrival <= plan.deadline and (not plan.backup
					or row.coverArrival < plan.backup.coverArrival
					or row.coverArrival == plan.backup.coverArrival and row.id < plan.backup.id) then
					plan.backup=row
				end
			end
			if plan.backup then claimed[plan.backup.id]=true end
		end
		plan.candidates=nil
		if J.Customize and J.Customize.TracePostFightCoverage then
			local tower,deadline=plan.building,plan.deadline
			local stamp=(plan.primary and plan.primary.id or -1)..':'..(plan.backup and plan.backup.id or -1)
				..':'..(plan.primary and plan.primary.onStation and 'ready' or 'pending')..':'..math.floor(deadline/4)
			if tower.ohaCoverLog~=stamp then
				tower.ohaCoverLog=stamp
				print('[OHA cover]',now,team,plan.lane,tower:GetUnitName(),stamp,deadline)
			end
		end
	end
	local plan=lanes[1]
	plan.lanes=lanes
	J.Utils.SetCachedVars(key,plan)
	return plan
end

-- Compatibility for consumers that only need the primary wave-clear role.
function J.GetExposedMidCover(team)
	local plan = J.GetPostFightCoverage(team)
	if plan and plan.primary then return plan.primary.hero, plan.building, plan.primary.reach end
end

function J.GetPostFightDuty(bot)
	local plan = J.GetPostFightCoverage(bot:GetTeam())
	if not plan then return end
	for _,lanePlan in ipairs(plan.lanes or {plan}) do
		if lanePlan.primary and lanePlan.primary.hero == bot then return 'clear', lanePlan end
		if lanePlan.backup and lanePlan.backup.hero == bot then return 'cover', lanePlan end
	end
	return nil, plan
end

-- When the shared plan has filled the roles for a small wave, another
-- defense entry point must not recruit a third clearer or spend their TP.
function J.HasAssignedWaveDefense(plan, lane)
	for _, front in ipairs(plan and (plan.lanes or {plan}) or {}) do
		if front.lane == lane and front.waveDefense and front.primary and (not front.needsBackup or front.backup) then
			return true
		end
	end
	return false
end

function J.CanTakePostFightTrip(bot, point, spendTeleport, localResource)
	local role, plan = J.GetPostFightDuty(bot)
	if not plan then return true end
	local covered, nearestDeadline = true, plan
	for _, other in ipairs(plan.lanes or {plan}) do
		local primary, backup = other.primary, other.backup
		local ready = primary and primary.onStation
			and (not other.needsBackup or backup and backup.walk <= other.deadline)
		if not ready then
			if covered or other.deadline < nearestDeadline.deadline then nearestDeadline = other end
			covered = false
		end
	end
	if not point then return role == nil and covered == true end
	if role == nil and covered then return true end
	local speed = math.max(250, bot:GetCurrentMovementSpeed())
	local currentPlan = role and plan or nearestDeadline
	local reach = J.GetLocationToLocationDistance(point, currentPlan.hold)
	-- Even a short diversion costs time. Never spend the held TP on a
	-- nearby side trip just because the point happens to be near our anchor.
	local outbound = spendTeleport and 4 or GetUnitToLocationDistance(bot, point) / speed * 1.25
	local action = spendTeleport and 3.5 or 2.0
	local returnTime = math.max(0, reach - 550) / speed * 1.25
	if role == 'clear' then
		return not spendTeleport and reach <= 850 and outbound + returnTime <= currentPlan.deadline
	end
	if role == nil and not spendTeleport and localResource then
		-- An unassigned bot cannot be treated as the backup for a tower
		-- it can't reach in time. Only reopen short, safe collection; a
		-- long rotation or TP still needs the normal coverage budget.
		local origin = bot:GetLocation()
		local gap = GetUnitToLocationDistance(bot, point)
		local canStillHelp = false
		for _, other in ipairs(plan.lanes or {plan}) do
			if GetUnitToLocationDistance(bot, other.hold) <= 550 + speed * other.deadline / 1.25 then
				local primary, backup = other.primary, other.backup
				if not primary or not primary.onStation or other.needsBackup and (not backup or backup.walk > other.deadline) then
					canStillHelp = true
					break
				end
			end
		end
		if not canStillHelp and gap <= 650 and not bot:WasRecentlyDamagedByAnyHero(2)
			and IsLocationVisible(point) and IsLocationPassable(point)
			and J.CanCommitToLaneTeleport(bot, point, true, 1200)
			and J.CanCommitToLaneTeleport(bot, origin, true, 1000) then
			local mid = gap > 25 and J.VectorTowards(origin, point, gap * 0.5) or origin
			if IsLocationPassable(mid) and J.CanCommitToLaneTeleport(bot, mid, true, 1050) then return true end
		end
	end
	if reach <= 850 and not spendTeleport then return outbound + returnTime < currentPlan.deadline end
	return outbound + action + returnTime + 1 < currentPlan.deadline
end

-- Safe home waves have a unique owner; unused teammates retain normal camp choices.
function J.GetScheduledFarmWaveOwner(bot, location)
	if J.IsInLaningPhase(bot) then return nil end
	local team=bot:GetTeam()
	local key='ScheduledWaves:'..tostring(team)
	local scheduled=J.Utils.GetCachedVars(key,0.65)
	if not scheduled then
		scheduled={}
		local waves={}
		for _,creep in ipairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS)) do
			if J.IsValid(creep) and creep:CanBeSeen() and J.IsInAllyArea(creep)
				and string.find(creep:GetUnitName(),'npc_dota_creep_',1,true) then
				local point=creep:GetLocation()
				local wave
				for _,candidate in ipairs(waves) do
					if J.GetLocationToLocationDistance(candidate.point,point)<=650 then wave=candidate; break end
				end
				if not wave then wave={point=point,count=0}; waves[#waves+1]=wave end
				wave.count=wave.count+1
			end
		end
		table.sort(waves,function(a,b)
			if a.count~=b.count then return a.count>b.count end
			if a.point.x~=b.point.x then return a.point.x<b.point.x end
			return a.point.y<b.point.y
		end)
		local roster, used, wealth = J.GetAlliesNearLoc(location,24000),{},0
		for _,ally in ipairs(roster) do
			if J.IsValidHero(ally) and J.IsCore(ally) then wealth=math.max(wealth,ally:GetNetWorth()) end
		end
		for _,wave in ipairs(waves) do
			if wave.count>=2 and #J.GetEnemiesNearLoc(wave.point,1500)==0 and #J.GetLastSeenEnemiesNearLoc(wave.point,1400)==0 then
				local best,cost= nil,math.huge
				for _,ally in ipairs(roster) do
					local id=ally:GetPlayerID()
					if not used[id] and J.IsValidHero(ally) and ally:IsBot() and not ally:IsIllusion()
						and J.GetHP(ally)>=0.48 and not J.IsRetreating(ally) and not J.IsDisabled(ally)
						and not ally:IsChanneling() and not ally:HasModifier('modifier_teleporting')
						and not J.IsGoingOnSomeone(ally) and not J.IsDoingRoshan(ally) and not J.IsDoingTormentor(ally)
						and not J.GetPostFightDuty(ally) and J.CanTakePostFightTrip(ally,wave.point,false,true) then
						local distance=GetUnitToLocationDistance(ally,wave.point)
						local eta=distance/math.max(250,ally:GetCurrentMovementSpeed())
						local recovery=J.IsCore(ally) and math.min(2.5,math.max(0,wealth-ally:GetNetWorth())/2600) or -2.5
						local score=eta-recovery
						local halfway=J.VectorTowards(ally:GetLocation(),wave.point,distance/2)
						if eta<=10 and (distance<=850 or J.CanCommitToLaneTeleport(ally,halfway,true,950))
							and (score<cost or score==cost and id<best:GetPlayerID()) then best,cost=ally,score end
					end
				end
				if best then
					local id=best:GetPlayerID()
					used[id]=true; scheduled[#scheduled+1]={point=wave.point,id=id}
				end
			end
		end
		J.Utils.SetCachedVars(key,scheduled)
	end
	for _,wave in ipairs(scheduled) do
		if J.GetLocationToLocationDistance(location,wave.point)<=680 then return wave.id end
	end
end

local function GetOuterTowerHoldPoint(hub, reach, cover)
	local offset = cover and 650 or math.max(250, math.min(reach >= 1100 and 800 or 600, reach - 400))
	local hold = J.AdjustLocationWithOffsetTowardsFountain(hub, offset)
	return IsLocationPassable(hold) and hold or J.AdjustLocationWithOffsetTowardsFountain(hub, 220)
end

local function CanJoinTowerFight(hero)
	return J.IsValidHero(hero) and not hero:IsIllusion() and J.GetHP(hero) >= 0.5
		and not J.IsRetreating(hero) and not J.IsDisabled(hero)
end

local ShortFightWindow
local function GetShortFightWindow()
    if not ShortFightWindow then
        ShortFightWindow = require(GetScriptDirectory() .. '/FunLib/short_fight_window')
    end
    return ShortFightWindow
end

local observedSpell = {}
local function ObserveFightSpell(enemy)
    if not enemy:CanBeSeen() or not enemy.GetCurrentActiveAbility
        or not enemy:IsUsingAbility() or enemy:IsCastingAbility() and not enemy:IsChanneling() then return end
    local ability = enemy:GetCurrentActiveAbility()
    if not ability or ability:IsNull() or ability:IsPassive() then return end
    local id = enemy:GetPlayerID()
    local old, now, name = observedSpell[id], DotaTime(), ability:GetName()
    if not old or old.name ~= name or now - old.time > 1 then
        -- A confirmed recent cast narrows only a short heuristic window.
        -- Never query the opponent's real cooldown or assume all spells spent.
        observedSpell[id] = {name = name, time = now, ultimate = ability:IsUltimate()}
    end
end

local function ShortDamageProfile(attacker, target, horizon, eta, friendly)
    local distance = GetUnitToUnitDistance(attacker, target)
    local range = attacker:GetAttackRange()
    local speed = math.max(220, attacker:GetCurrentMovementSpeed())
    local contact = math.max(0, eta or 0, (distance - range) / speed)
    if attacker:IsRooted() and distance > range then contact = horizon + 1 end
    local attack = attacker:IsDisarmed() and 0
        or target:GetActualIncomingDamage(attacker:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
    local spells = {}
    if friendly and not attacker:IsSilenced() then
        for slot = 0, 8 do
            local spell = attacker:GetAbilityInSlot(slot)
            if J.CanCastAbilitySoon(spell, horizon) and spell:GetCastRange() >= 200
                and attacker:GetMana() >= spell:GetManaCost() then
                -- Unknown, delayed and special effects are not guaranteed hits.
                local kind = spell.GetDamageType and spell:GetDamageType() or DAMAGE_TYPE_MAGICAL
                local raw = spell:GetAbilityDamage() or 0
                local cast = math.max(0.15, spell:GetCastPoint())
                local rangeToSpell = math.max(0, distance - spell:GetCastRange())
                local ready = math.max(eta or 0, rangeToSpell / speed, spell:GetCooldownTimeRemaining())
                if raw >= 50 and ready + cast <= horizon and (not attacker:IsRooted() or rangeToSpell == 0)
                    and not target:IsMagicImmune()
                    and (kind == DAMAGE_TYPE_PHYSICAL or kind == DAMAGE_TYPE_MAGICAL or kind == DAMAGE_TYPE_PURE)
                    and J.Utils.AbilityBehaviorHasFlag(spell:GetBehavior(), ABILITY_BEHAVIOR_UNIT_TARGET) then
                    local damage = target:GetActualIncomingDamage(raw, kind)
                    spells[#spells+1] = {eta = ready, damage = damage, cast = cast, cost = spell:GetManaCost()}
                end
            end
        end
    end
    table.sort(spells, function(a,b) return a.eta < b.eta or a.eta == b.eta and a.damage > b.damage end)
    local unknown
    if not friendly and distance <= 1100 and attacker:GetMana() >= 65 and not attacker:IsSilenced() then
        local cast = observedSpell[attacker:GetPlayerID()]
        local recentUlt = cast and cast.ultimate and DotaTime() >= cast.time and DotaTime() - cast.time <= 4.5
        local spellRisk = math.max(120, attack * 1.8) * (recentUlt and 0.72 or 1)
        unknown = target:GetActualIncomingDamage(spellRisk, DAMAGE_TYPE_MAGICAL)
    end
    return GetShortFightWindow().Profile({
        horizon = horizon, contact = contact, attack = attack, period = attacker:GetSecondsPerAttack(),
        windup = attacker.GetAttackPoint and attacker:GetAttackPoint() or 0.35,
        spells = friendly and spells or nil, mana = friendly and attacker:GetMana() or nil, unknownSpell = unknown,
    })
end

function J.HasRecentlySeenFightUltimate(enemy)
    if not enemy.CanBeSeen or not enemy:CanBeSeen() then return false end
    ObserveFightSpell(enemy)
    local record = observedSpell[enemy:GetPlayerID()]
    local now = DotaTime()
    return record ~= nil and record.ultimate and now >= record.time and now - record.time <= 4.5
end

function J.GetFightContactDamage(bot, target, allies)
    if not bot.GetAttackPoint or not bot.GetAbilityInSlot or not target.CanBeSeen or not target:CanBeSeen() then return nil end
    local sum = {low = 0, typical = 0, high = 0}
    local function add(ally)
        if GetUnitToUnitDistance(ally, target) <= math.max(500, ally:GetAttackRange() + 100) then
            local p = ShortDamageProfile(ally, target, 2.1, 0, true)
            for _, key in ipairs({'low','typical','high'}) do sum[key] = sum[key] + p[key] end
        end
    end
    add(bot)
    for _, ally in ipairs(allies) do
        if ally ~= bot and CanProvideFightContact(ally) and ally:GetAttackTarget() == target then add(ally) end
    end
    return sum
end

function J.GetLocalFightReadiness(bot, allies, enemies)
    local horizon, close, focus = 3.25, {}, nil
    for _, enemy in ipairs(enemies) do
        if IsFightFocusCandidate(enemy) and enemy.CanBeSeen and enemy:CanBeSeen()
            and GetUnitToUnitDistance(bot, enemy) < 1250 then
            ObserveFightSpell(enemy)
            close[#close+1] = enemy
            if enemy == bot:GetAttackTarget() or not focus then focus = enemy end
        end
    end
    if not focus or not bot.GetAbilityInSlot or not bot.GetSecondsPerAttack then return nil end
    local incomingLow, incomingHigh, attackers = 0, 0, 0
    for _, enemy in ipairs(close) do
        if not J.IsDisabled(enemy) then
            local p = ShortDamageProfile(enemy, bot, horizon, 0, false)
            if enemy:GetAttackTarget() == bot then
                incomingLow = incomingLow + p.low
                incomingHigh = incomingHigh + p.high
            else
                incomingHigh = incomingHigh + p.high * 0.55
            end
        end
    end
    local outgoingLow, outgoingMid = 0, 0
    for _, ally in ipairs(allies) do
        if CanProvideFightContact(ally) and GetUnitToUnitDistance(ally,focus) <= 1050
            and (ally == bot or ally:GetAttackTarget() == focus) then
            local p = ShortDamageProfile(ally, focus, horizon, 0, true)
            outgoingLow, outgoingMid = outgoingLow + p.low, outgoingMid + p.typical
            if p.typical > 0 then attackers = attackers + 1 end
        end
    end
    local hp, targetHP = bot:GetHealth(), focus:GetHealth() + focus:GetHealthRegen() * horizon
    if incomingLow >= hp * 0.92 and outgoingLow < targetHP then return false end
    if attackers >= 2 and outgoingMid >= targetHP and outgoingLow >= targetHP * 0.70
        and incomingHigh < hp * 0.72 and #close <= attackers + 1 then return true end
    -- Indeterminate overlaps are not certainty of either outcome.
    return nil
end

local function ShortTowerTrade(bot, tower, threat, allies)
    if #allies < 2 or not tower.GetAttackTarget or tower:GetHealth() < tower:GetMaxHealth() * 0.20 then return nil end
    local target = tower:GetAttackTarget()
    if not J.IsValidHero(target) or not target:CanBeSeen() or target:IsInvulnerable()
        or J.IsSuspiciousIllusion(target) or not J.CanBeAttacked(target)
        or GetUnitToUnitDistance(bot, target) > bot:GetAttackRange()
        or GetUnitToUnitDistance(tower, target) > tower:GetAttackRange() then return nil end
    local window, mid = 2.7, GetShortFightWindow()
    local damage = mid.TowerDamage(true, target:GetActualIncomingDamage(tower:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL),
        tower:GetSecondsPerAttack(), window)
    local attackers, incoming, coreHP, coreThreat = 0, 0, nil, 0
    for _, row in ipairs(allies) do
        local ally = row.hero
        if GetUnitToUnitDistance(ally, target) <= math.max(ally:GetAttackRange() + 75, 525) then
            local v = ShortDamageProfile(ally, target, window, 0, true)
            if v.typical > 0 then
                attackers = attackers + 1
                for _, key in ipairs({'low', 'typical', 'high'}) do damage[key] = damage[key] + v[key] end
                if J.IsCore(ally) then
                    local estimate = 0
                    for _, enemy in ipairs(threat.enemies) do
                        if J.IsValidHero(enemy) and enemy:CanBeSeen() then estimate = estimate + ShortDamageProfile(enemy, ally, window, 0, false).high end
                    end
                    if not coreHP or estimate / ally:GetHealth() > coreThreat / coreHP then
                        coreHP, coreThreat = ally:GetHealth(), estimate
                    end
                end
            end
        end
    end
    for _, enemy in ipairs(threat.enemies) do
        if J.IsValidHero(enemy) and enemy:CanBeSeen() then incoming = incoming + ShortDamageProfile(enemy, bot, window, 0, false).high end
    end
    -- Keep the core-risk test separate from the acting support's risk.
    if coreHP and coreThreat >= coreHP * 0.80 then return nil end
    if mid.CanTrade({locked = true, attackers = attackers, unseen = math.max(0, threat.count - #threat.enemies),
        enemyHealth = target:GetHealth() + target:GetHealthRegen() * window, damage = damage,
        incomingHigh = incoming, selfHealth = bot:GetHealth(), canRiskSupport = not J.IsCore(bot),
        targetWorthwhile = target:GetAttackTarget() == tower
            and (target:GetLevel() >= bot:GetLevel() + 2
                or J.GetVisibleFightInventoryValue and J.GetVisibleFightInventoryValue(target)
                    >= J.GetVisibleFightInventoryValue(bot) * 1.45 + 1200)}) then
        return target
    end
end

local function TowerFightPower(hero)
	local dps = hero:GetAttackDamage() / math.max(0.25, hero:GetSecondsPerAttack())
	return (0.6 + 0.045 * hero:GetLevel() + 0.004 * math.min(300, dps))
		* math.sqrt(J.GetHP(hero)) * (hero:IsDisarmed() and 0.75 or 1)
end

local function CanTakeTowerFight(threat, allies)
	if threat.count < 2 or #allies < threat.count or #threat.enemies < math.ceil(threat.count * 0.6) then return false end
	local allyPower, enemyPower = 0, 0
	for _, candidate in ipairs(allies) do
		local power = TowerFightPower(candidate.hero)
		if J.Utils.HasCriticalSpellWithCooldown(candidate.hero, candidate.eta + 1) then power = power * 0.8 end
		allyPower = allyPower + power
	end
	for _, enemy in ipairs(threat.enemies) do
		if J.IsValidHero(enemy) then enemyPower = enemyPower + TowerFightPower(enemy) end
	end
	-- A recently seen hero or incoming enemy TP still counts, without reading unseen stats.
	enemyPower = enemyPower + (threat.count - #threat.enemies) * math.max(1.6, enemyPower / #threat.enemies)
	local towerCover = threat.towerHP >= 0.25 and (threat.siege and 0.2 or 0.55) or 0
	return allyPower + towerCover >= enemyPower
end

local function GetOuterTowerFightPlan(location, threat, fallback)
	if not threat.tower or threat.count < 3 or threat.briefHold or threat.towerHP < 0.25
		or #threat.enemies < math.ceil(threat.count * 0.6)
		or not (threat.underAttack or threat.waveSize >= 2 and threat.eta <= 9) then return nil end
	local gather = J.AdjustLocationWithOffsetTowardsFountain(location, 575)
	if not IsLocationPassable(gather) then return nil end
	local gatherExposed = #J.GetEnemiesNearLoc(gather, 800) >= 2
	local window = math.max(8, threat.eta + 7)
	if threat.underAttack and threat.damageRate > 0 and not threat.tower:HasModifier('modifier_fountain_glyph') then
		window = math.min(window, threat.tower:GetHealth() / threat.damageRate - 1)
	end
	local budget = window
	-- Only extend the plan if the all-Bot team can actually use Glyph.
	if GetGlyphCooldown() <= 0 and window >= 2 then
		local allBots = true
		for i = 1, 5 do
			local ally = GetTeamMember(i)
			if not ally or not ally:IsBot() then allBots = false; break end
		end
		if allBots then budget = math.max(budget, math.min(8.5, budget + 5)) end
	end
	local incoming, teleportCount = {}, 0
	for _, tp in ipairs(GetIncomingTeleports()) do
		if tp.playerid ~= nil and GetTeamForPlayer(tp.playerid) == GetTeam() and tp.location and tp.time_remaining and tp.time_remaining >= 0 then
			incoming[tp.playerid] = tp
			if J.GetLocationToLocationDistance(tp.location, gather) <= 350
				or fallback and J.GetLocationToLocationDistance(tp.location, fallback) <= 350 then teleportCount = teleportCount + 1 end
		end
	end
	local allies = {}
	local fountain = J.GetTeamFountain()
	local homeSide = J.GetLocationToLocationDistance(location, fountain)
	for _, ally in ipairs(J.GetAlliesNearLoc(location, 24000)) do
		if CanJoinTowerFight(ally) then
			local distance = GetUnitToLocationDistance(ally, gather)
			local speed = math.max(250, ally:GetCurrentMovementSpeed())
			local eta, landing = math.huge, nil
			local id = ally:GetPlayerID()
			local tp = incoming[id]
			if tp and ally:HasModifier('modifier_teleporting') then
				if J.GetLocationToLocationDistance(tp.location, gather) <= 3600
					and J.GetLocationToLocationDistance(tp.location, fountain) <= homeSide
					and J.CanCommitToLaneTeleport(ally, tp.location, true, 1250) then
					eta = tp.time_remaining + math.max(0, J.GetLocationToLocationDistance(tp.location, gather) - 250) / speed
					landing = tp.location
				end
			elseif not ally:IsChanneling() then
				if distance <= 1050 then
					eta = math.max(0, distance - 250) / speed
				elseif ally:IsBot() and GetUnitToLocationDistance(ally, fountain) <= homeSide + 250 then
					local midpoint = J.VectorTowards(ally:GetLocation(), gather, distance / 2)
					if J.CanCommitToLaneTeleport(ally, midpoint, true, 950) then
						eta = math.max(0, distance - 250) / speed
					end
				end
				if ally:IsBot() and distance > 2050 and eta > 4 and not ally:IsRooted()
					and not ally:WasRecentlyDamagedByAnyHero(2) and #J.GetEnemiesNearLoc(ally:GetLocation(), 1600) == 0
					and J.CanCastAbility(J.GetItem2(ally, 'item_tpscroll')) then
					local destination = J.CanCommitToLaneTeleport(ally, gather, true, 1250) and gather or fallback
					if destination and IsLocationPassable(destination) and GetUnitToLocationDistance(ally, destination) > 1800
						and J.CanCommitToLaneTeleport(ally, destination, true, 1250) then
						local tpETA = 4.5 + math.min(2.5, teleportCount)
							+ math.max(0, J.GetLocationToLocationDistance(destination, gather) - 250) / speed
						if tpETA < eta and tpETA <= budget then
							eta, landing, teleportCount = tpETA, destination, teleportCount + 1
						end
					end
				end
			end
			if eta <= budget and (not gatherExposed or distance <= 1050 and eta <= 2) then
				allies[#allies + 1] = {hero = ally, eta = eta, teleport = landing}
			end
		end
	end
	if not CanTakeTowerFight(threat, allies) then
		-- Separate buying time from taking a fight. A long-range clearer and
		-- nearby cover can defend mid without claiming that three can beat five.
		if threat.lane ~= LANE_MID or threat.waveSize < 2 or #J.GetEnemiesNearLoc(gather, 550) >= 2 then return nil end
		local ranked = {}
		for _, candidate in ipairs(allies) do
			local ally = candidate.hero
			if ally:IsBot() and candidate.eta <= window then
				local score, reach, damage = GetWaveClearScore(ally, candidate.eta)
				local save = J.CanCastAbility(J.GetItem2(ally, 'item_force_staff'))
					or J.CanCastAbility(J.GetItem2(ally, 'item_glimmer_cape'))
				local hold = GetOuterTowerHoldPoint(location, reach, false)
				if J.CanCommitToLaneTeleport(ally, hold, true, 650) then
					ranked[#ranked + 1] = {hero = ally, eta = candidate.eta, teleport = candidate.teleport,
						reach = reach, damage = damage, score = score - candidate.eta * 25,
						cover = (save and 120 or 0) - candidate.eta * 35}
				end
			end
		end
		table.sort(ranked, function(a, b) return a.score > b.score or a.score == b.score and a.hero:GetPlayerID() < b.hero:GetPlayerID() end)
		local plans, count = {}, 0
		for _, row in ipairs(ranked) do
			if row.reach >= 1050 and row.damage > 0 then
				count = count + 1
				plans[row.hero:GetPlayerID()] = {reach = row.reach, cover = false, gather = gather, teleport = row.teleport, screen = true}
				if count == 2 then break end
			end
		end
		if count == 0 then
			-- With the primary clearer dead/off lane, allow a medium-range
			-- caster already under cover to act, not a short solo overextension.
			for _, row in ipairs(ranked) do
				if row.reach >= 825 and row.damage > 0 and row.eta <= 3 and not row.teleport then
					for _, backup in ipairs(ranked) do
						if backup.hero ~= row.hero and backup.eta <= 3 and not backup.teleport then
							plans[row.hero:GetPlayerID()] = {reach = row.reach, cover = false, gather = gather, screen = true}
							count = 1
							break
						end
					end
					if count > 0 then break end
				end
			end
			if count == 0 then return nil end
		end
		local helper
		for _, row in ipairs(ranked) do
			if not plans[row.hero:GetPlayerID()] and row.eta <= 4 and not row.teleport
				and (not helper or row.cover > helper.cover) then helper = row end
		end
		if helper then
			local ally = helper.hero
			plans[ally:GetPlayerID()] = {reach = ally:GetAttackRange(), cover = true, gather = gather, screen = true}
		end
		return plans
	end
	local assignments = {}
	for _, candidate in ipairs(allies) do
		local ally = candidate.hero
		if ally:IsBot() then
			local _, reach = GetWaveClearScore(ally, candidate.eta)
			assignments[ally:GetPlayerID()] = {reach = math.max(reach, ally:GetAttackRange()), cover = false,
				gather = gather, teleport = candidate.teleport, needsGlyph = candidate.eta > window}
		end
	end
	return assignments
end

function J.GetOuterTowerResponse(location, threat, fallback, highGround)
	local contest = not highGround and GetOuterTowerFightPlan(location, threat, fallback)
	if contest then return true, contest end
	local ready = {}
	local closeCount, closest, closestDistance = 0, nil, math.huge
	local approaching = not highGround and not threat.briefHold and (threat.eta >= 2 or threat.count == 0 and (threat.waveSize >= 2 or threat.lane == LANE_MID and threat.siege)
		or threat.underAttack and threat.towerHP >= 0.35 and (threat.count >= 2 or threat.heroAttacking and threat.waveSize >= 2))
	local function SafeLanding(point)
		return point ~= nil and IsLocationPassable(point) and #J.GetLastSeenEnemiesNearLoc(point, 1650) == 0
			and #J.GetEnemiesNearLoc(point, 1650) == 0
	end
	local tpPoint = approaching and J.AdjustLocationWithOffsetTowardsFountain(location, threat.count >= 3 and 775 or 475) or nil
	if not SafeLanding(tpPoint) then
		tpPoint = not highGround and not threat.briefHold and SafeLanding(fallback) and fallback or nil
	end
	-- When a group can take the front tower, clear the following wave from
	-- the safety of the next one. Other heroes can still trade a side lane.
	local function defendNextTower()
		local assigned = {}
		local advancingWave = threat.waveSize >= 2 and (threat.siege or threat.heroAttacking)
		if highGround or (threat.count < 3 and not advancingWave) or not SafeLanding(fallback) then return true, assigned end
		local budget = threat.eta + J.GetLocationToLocationDistance(location, fallback) / 375 + 5
		local candidates = {}
		for _, ally in ipairs(J.GetAlliesNearLoc(fallback, 24000)) do
			local teleporting = ally:HasModifier('modifier_teleporting')
			local destination = ally._defend and ally._defend.waveClearTeleport
			local landingHere = destination and J.GetLocationToLocationDistance(destination, fallback) < 350
			if ally:IsBot() and J.IsValidHero(ally) and not ally:IsIllusion() and J.GetHP(ally) >= 0.5
				and (not teleporting or landingHere)
				and not J.IsRetreating(ally) and not ally:WasRecentlyDamagedByAnyHero(2) then
				local travel = GetUnitToLocationDistance(ally, fallback) / math.max(250, ally:GetCurrentMovementSpeed())
				local tp
				if travel > 6 and (teleporting or J.CanCastAbility(J.GetItem2(ally, 'item_tpscroll')))
					and #J.GetEnemiesNearLoc(ally:GetLocation(), 1200) == 0 and J.CanCommitToLaneTeleport(ally, fallback, true) then
					travel, tp = 4.5, fallback
				end
				if travel <= budget then
					local score, reach, damage, impact = GetWaveClearScore(ally, travel)
					if damage > 0 and travel + (impact or 0) <= budget then
						candidates[#candidates + 1] = {id = ally:GetPlayerID(), score = score - travel * 25,
						reach = reach, damage = damage, cover = false, teleport = tp, rally = fallback} end
				end
			end
		end
		table.sort(candidates, function(a, b) if a.score == b.score then return a.id < b.id end; return a.score > b.score end)
		local damage = 0
		for i = 1, math.min(2, #candidates) do
			local candidate = candidates[i]
			assigned[candidate.id] = candidate
			damage = damage + candidate.damage
			if damage >= math.max(180, threat.waveHP * 0.8) then break end
		end
		return true, assigned
	end
	-- Do not converge on a tower that will fall before even the first cast.
	local timeToFall = threat.tower and threat.underAttack and threat.damageRate > 0
		and not threat.tower:HasModifier('modifier_fountain_glyph') and threat.tower:GetHealth() / threat.damageRate
		or math.huge
	if not highGround and (threat.towerHP <= 0.15 or timeToFall < 2.5) then return defendNextTower() end
	for _, ally in ipairs(J.GetAlliesNearLoc(location, threat.briefHold and 1600 or (tpPoint ~= nil and 24000 or 4000))) do
		local tp = ally._defend and ally._defend.waveClearTeleport
		local teleportingHere = tpPoint ~= nil and tp ~= nil and J.GetLocationToLocationDistance(tpPoint, tp) < 350
		if J.IsValidHero(ally) and not ally:IsIllusion() and not J.IsRetreating(ally)
			and (not ally:HasModifier('modifier_teleporting') or teleportingHere) and J.GetHP(ally) >= 0.45 then
			local distance = GetUnitToLocationDistance(ally, location)
			if distance <= 2200 then
				closeCount = closeCount + 1
				if distance < closestDistance then closest, closestDistance = ally, distance end
			end
			ready[#ready + 1] = ally
		end
	end
	local groupSiege = not highGround and threat.tower and threat.count >= 3
		and (threat.underAttack or threat.waveSize >= 2 and threat.eta <= 9)
	if not groupSiege and threat.near >= 2 and closeCount >= threat.count and J.WeAreStronger(closest, 2200)
		and not J.Utils.HasTeamMemberWithCriticalItemInCooldown(location)
		and not J.Utils.HasTeamMemberWithCriticalSpellInCooldown(location) then
		return false, {}
	end

	local fountain = J.GetTeamFountain()
	local towerFromFountain = J.GetLocationToLocationDistance(location, fountain)
	local arrivalWindow = math.max(highGround and 10 or 6, threat.eta + 4)
	if not highGround and threat.count <= 1 and threat.towerHP >= 0.4 then
		arrivalWindow = math.max(arrivalWindow, 11)
	end
	local candidates = {}
	for _, ally in ipairs(ready) do
		local pressured = ally:WasRecentlyDamagedByAnyHero(2)
		if ally:IsBot() and (not pressured or J.GetHP(ally) >= 0.65) then
			local distance = GetUnitToLocationDistance(ally, location)
			local speed = math.max(ally:GetCurrentMovementSpeed(), 250)
			local travelTime = GetUnitToLocationDistance(ally, fountain) <= towerFromFountain + 350
				and distance / speed or math.huge
			-- A ranged clearer only needs to reach the protected casting point, not the tower.
			local _, walkingReach = GetWaveClearScore(ally, math.min(travelTime, arrivalWindow))
			if not highGround and walkingReach >= 1100 and travelTime < math.huge then
				local hold = GetOuterTowerHoldPoint(location, walkingReach, false)
				if J.CanCommitToLaneTeleport(ally, hold, true, 950) then
					travelTime = GetUnitToLocationDistance(ally, hold) / speed
				end
			end
			local landing = nil
			if tpPoint ~= nil and distance > 2100 and travelTime > 5 and not pressured
				and (highGround or not J.ShouldKeepLaningWave(ally, threat.lane, threat))
				and (ally:HasModifier('modifier_teleporting') or J.CanCastAbility(J.GetItem2(ally, 'item_tpscroll')))
				and #J.GetEnemiesNearLoc(ally:GetLocation(), 1200) == 0 and J.CanCommitToLaneTeleport(ally, tpPoint, true)
				and (highGround or J.CanTakeLaneDefenseTeleport(ally, threat.lane, tpPoint, threat.tower, nil, true, walkingReach, threat)) then
				local fromLanding = math.max(0, J.GetLocationToLocationDistance(tpPoint, location) - 575)
				travelTime, landing = 4.5 + fromLanding / math.max(ally:GetCurrentMovementSpeed(), 250), tpPoint
			end
			if travelTime <= arrivalWindow and travelTime + 1.25 < timeToFall then
				local score, reach, damage, impact = GetWaveClearScore(ally, travelTime)
				if damage > 0 and travelTime + (impact or 0) >= timeToFall then damage = 0 end
				if damage == 0 and (threat.count == 0 or threat.count == 1 and travelTime <= 5 and landing == nil) then
					-- An uncontested catapult can be cleared with ordinary attacks, including after a safe TP.
					reach, damage = ally:GetAttackRange(), 1
				end
				local canSave = J.CanCastAbility(J.GetItem2(ally, 'item_force_staff'))
					or J.CanCastAbility(J.GetItem2(ally, 'item_glimmer_cape'))
				local cost = 24 * travelTime + (J.GetPosition(ally) == 1 and 95 or 0)
				candidates[#candidates + 1] = {hero = ally, reach = reach, damage = damage, score = score - cost, teleport = landing,
					cover = (canSave and 180 or 0) - cost}
			end
		end
	end
	table.sort(candidates, function(a, b)
		if (a.damage > 0) ~= (b.damage > 0) then return a.damage > 0 end
		if a.score == b.score then return a.hero:GetPlayerID() < b.hero:GetPlayerID() end
		return a.score > b.score
	end)
	local primary = candidates[1]
	if primary == nil or primary.damage <= 0 then return defendNextTower() end

	local requiredDamage = math.max(180, threat.waveHP * 0.8)
	local heavy = threat.siege or threat.waveSize >= 6
	local needsSecond = primary.damage < requiredDamage or (heavy and primary.reach < 900)
	local exposed = threat.count >= 3 and (threat.near >= 2 or threat.eta <= 3)
	local assignments = {[primary.hero:GetPlayerID()] = {reach = primary.reach, cover = false, teleport = primary.teleport}}
	if threat.briefHold then return true, assignments end
	local chipPoint = threat.tower and not highGround and threat.count >= 2 and threat.waveSize >= 2 and threat.towerHP >= 0.3
		and primary.reach >= 1100 and (threat.damageRate == 0 or threat.tower:GetHealth() / threat.damageRate > 4)
		and GetOuterTowerHoldPoint(location, primary.reach, false)
	local canChip = chipPoint and J.GetLocationToLocationDistance(location, chipPoint) >= 650
		and J.CanCommitToLaneTeleport(primary.hero, chipPoint, true, 950)
	local secondary = candidates[2]
	local shortSecondary = false
	if needsSecond and threat.count >= 2 then
		local enough = secondary and secondary.damage > 0 and primary.damage + secondary.damage >= requiredDamage
		if not enough and not canChip then return defendNextTower() end
		if enough or canChip and secondary and secondary.damage > 1 and secondary.reach >= 1100 then
			assignments[secondary.hero:GetPlayerID()] = {reach = secondary.reach, cover = false, teleport = secondary.teleport}
			shortSecondary = secondary.reach < 900
		end
	elseif needsSecond and secondary ~= nil and secondary.damage > 1 then
		assignments[secondary.hero:GetPlayerID()] = {reach = secondary.reach, cover = false, teleport = secondary.teleport}
	end
	-- Even if long-range chip can start alone, try to reserve one nearby cover
	-- hero. Never make a short-range clearer walk up unsupported.
	if exposed and (canChip or primary.reach < 900 or shortSecondary or not highGround and not needsSecond) then
		local cover = nil
		for _, candidate in ipairs(candidates) do
			if assignments[candidate.hero:GetPlayerID()] == nil and (cover == nil or candidate.cover > cover.cover) then cover = candidate end
		end
		if cover == nil then
			if not canChip or shortSecondary then return defendNextTower() end
		else
			assignments[cover.hero:GetPlayerID()] = {reach = cover.hero:GetAttackRange(), cover = true, teleport = cover.teleport}
		end
	end
	return true, assignments
end

local function GetCoveredMidPokeTarget(bot, tower, range)
	local hub = tower:GetLocation()
	if J.GetHP(bot) < 0.60 or bot:WasRecentlyDamagedByAnyHero(2)
		or J.GetAvailableFightAllies(bot, bot:GetLocation(), 1000) == 0 then return nil end
	local target, best
	for _, enemy in ipairs(J.GetEnemiesNearLoc(hub, 1200)) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and J.CanBeAttacked(enemy)
			and not enemy:IsInvulnerable() and J.IsInRange(bot, enemy, range)
			and (J.IsDisabled(enemy) or not J.IsInRange(bot, enemy, enemy:GetAttackRange() + 110)) then
			local victim = enemy:GetAttackTarget()
			if victim == tower or J.IsDisabled(enemy)
				or (victim ~= bot and J.IsValidHero(victim) and victim:GetTeam() == bot:GetTeam()) then
				local score = 1 - J.GetHP(enemy) + (J.IsDisabled(enemy) and 1 or 0)
				if not best or score > best then target, best = enemy, score end
			end
		end
	end
	return target
end

function J.GetMidDefensePokeTarget(bot, range, hold)
	if not J.IsDefending(bot) then return nil end
	local now = DotaTime()
	local guard = bot.ohaMidCover
	local state = bot._defend
	local tower
	if guard and now < guard.expires then
		tower = guard.tower
	elseif bot.ohaHighGroundResponse and now < bot.ohaHighGroundResponse.expires then
		tower = bot.ohaHighGroundResponse.tower
	elseif state and state.waveClearLane and not state.waveClearRearTower and (bot.ohaOuterTowerHoldUntil or 0) > now then
		tower = state.waveClearTower
	end
	if not J.IsValidBuilding(tower) then return nil end
	local hub = tower:GetLocation()
	if GetUnitToLocationDistance(bot, hub) > 1350 or #J.GetEnemiesNearLoc(bot:GetLocation(), 700) >= 2 then return nil end
	local target = GetCoveredMidPokeTarget(bot, tower, range)
	if target or not hold or bot:IsRooted() or bot:IsDisarmed() then return target end
	target = GetCoveredMidPokeTarget(bot, tower, range + 150)
	if not target or target:GetAttackTarget() ~= tower or J.GetHP(tower) < 0.25 then return nil end
	local step = GetUnitToUnitDistance(bot, target) - range + 20
	local origin = bot:GetLocation()
	local point = J.VectorTowards(origin, target:GetLocation(), step)
	local halfway = J.VectorTowards(origin, point, step * 0.5)
	if J.GetLocationToLocationDistance(hold, point) > 220 or not IsLocationVisible(point)
		or not IsLocationPassable(point) or not IsLocationPassable(halfway)
		or GetUnitToLocationDistance(target, point) <= target:GetAttackRange() + 110
		or GetUnitToLocationDistance(tower, J.GetTeamFountain()) < J.GetLocationToLocationDistance(point, J.GetTeamFountain()) then return nil end
	local enemies = J.GetEnemiesNearLoc(point, 1500)
	if J.GetAvailableFightAllies(bot, point, 900) == 0 or not J.CanCommitToLaneTeleport(bot, point, false, 850)
		or J.GetVisibleThreatAt(bot, enemies, point, 1.5) >= bot:GetHealth() * 0.25 then return nil end
	return nil, point
end

function J.RunOuterTowerHold(bot, hub, reach, cover, stage, assignment)
	if bot:HasModifier('modifier_teleporting') then return false end
	local hold = stage or GetOuterTowerHoldPoint(hub, reach, cover)
	local formation = stage
	if not formation and J.GetTowerHoldFormationPoint and reach >= 900 then
		formation = J.GetTowerHoldFormationPoint(bot, hub, hold, reach,
			J.GetEnemiesNearLoc(hub, 2250), J.GetAlliesNearLoc(hold, 1400))
		hold = formation or hold
	end
	local hostile = J.GetEnemiesNearLoc(hold, 700)
	if #hostile >= 2 or bot:WasRecentlyDamagedByAnyHero(2) and #J.GetEnemiesNearLoc(bot:GetLocation(), 750) >= 2
		or (#hostile == 1 and bot:WasRecentlyDamagedByAnyHero(2)
		and (#J.GetAlliesNearLoc(hold, 850) <= 1 or J.GetHP(bot) < 0.45)) then
		-- A deep high-ground stage is already behind the usual exit point.
		-- Do not send a compromised rear-line bot forward to that point.
		local deepStage = stage and J.GetLocationToLocationDistance(stage, hub) > 950
		bot:Action_MoveToLocation(J.AdjustLocationWithOffsetTowardsFountain(deepStage and stage or hub, deepStage and 600 or 1000))
		return true
	end
	-- Ordinary recovery must not cancel a cast; the hard danger exit above
	-- still takes priority, as it did before the short-step fallback.
	if bot:IsUsingAbility() or bot:IsCastingAbility() or bot:IsChanneling() then return false end
	if assignment and not cover then
		local tower = assignment.tower
		local threat = J.GetOuterTowerThreat(tower, assignment.lane or LANE_MID)
		if J.TryStageTowerWaveCast(bot, tower, threat) then return true end
	end
	local awayFromHold = GetUnitToLocationDistance(bot, hold) > 220
	local canStepUp = not cover and formation == nil and #J.GetLastSeenEnemiesNearLoc(hub, 1150) == 0
		and #J.GetEnemiesNearLoc(hub, 1150) == 0
	if awayFromHold and (not canStepUp or GetUnitToLocationDistance(bot, hub) > 700) then
		-- A defender who has just landed may already have a safe shot. Do not
		-- walk back to the rally before firing at a unit on the standing tower.
		local range = bot:GetAttackRange()
		if range >= 350 and not bot:IsDisarmed() and J.GetHP(bot) >= 0.60
			and not bot:WasRecentlyDamagedByAnyHero(2) and GetUnitToLocationDistance(bot, hub) <= 1050 then
			local tower = J.GetAssignedOuterTower(bot)
			if tower and GetUnitToLocationDistance(tower, hub) <= 120 then
				local enemies = J.GetEnemiesNearLoc(bot:GetLocation(), 1400)
				if J.GetAvailableFightAllies(bot, bot:GetLocation(), 1000) > 0
					and J.GetVisibleThreatAt(bot, enemies, bot:GetLocation(), 1.5) < bot:GetHealth() * 0.25 then
					local target = J.GetMidDefensePokeTarget(bot, range - 25)
					if not target then
						for _, creep in ipairs(bot:GetNearbyLaneCreeps(range - 15, true)) do
							if J.IsValid(creep) and J.CanBeAttacked(creep) and creep:GetAttackTarget() == tower then
								target = creep
								break
							end
						end
					end
					if target then
						return J.IssueTowerDefenseAttack(bot, target)
					end
				end
			end
		end
		bot:Action_MoveToLocation(hold)
		return true
	end
	if cover then
		for _, enemy in ipairs(hostile) do
			if J.IsInRange(bot, enemy, bot:GetAttackRange()) and J.CanBeAttacked(enemy) then
				return J.IssueTowerDefenseAttack(bot, enemy)
			end
		end
	end
	local target, priority = nil, 0
	for _, unit in ipairs(bot:GetNearbyCreeps(bot:GetAttackRange(), true)) do
		if J.IsValid(unit) and J.CanBeAttacked(unit) and IsSiegeSummon(unit:GetUnitName()) then
			target, priority = unit, 3
			break
		end
	end
	local range = bot:GetAttackRange()
	local microStep = not cover and range >= 350 and not awayFromHold
		and (not bot.IsRooted or not bot:IsRooted()) and J.GetHP(bot) >= 0.55
		and not bot:WasRecentlyDamagedByAnyHero(2)
	local nextPoint, nextPriority = nil, 0
	local shortStep = formation and 180 or 210
	local scan = canStepUp and math.min(1600, range + 650) or microStep and math.min(1600, range + shortStep) or range
	for _, creep in ipairs(bot:GetNearbyLaneCreeps(scan, true)) do
		if J.IsValid(creep) and J.CanBeAttacked(creep) then
			local siege = string.find(creep:GetUnitName(), 'siege', 1, true) ~= nil
			local closeToHub = GetUnitToLocationDistance(creep, hub) <= 650
			-- A catapult can fire from beyond the ordinary lane-creep leash.
			-- Only follow it in an uncontested area, on a short, safe route.
			local siegeStep = false
			if siege and canStepUp and not closeToHub and GetUnitToLocationDistance(creep, hub) <= 1150 then
				local point = creep:GetLocation()
				local staging = J.VectorTowards(bot:GetLocation(), point,
					math.max(0, GetUnitToUnitDistance(bot, creep) - range + 20))
				siegeStep = IsLocationPassable(staging) and IsLocationVisible(staging)
					and J.CanCommitToLaneTeleport(bot, staging, true, 950)
			end
			if J.IsInRange(bot, creep, range) or canStepUp and (closeToHub or siegeStep) then
				local weight = siege and 2 or 1
				if weight > priority then target, priority = creep, weight end
			elseif microStep and (closeToHub or siege and GetUnitToLocationDistance(creep, hub) <= 1150)
				and (not creep.CanBeSeen or creep:CanBeSeen()) then
				local gap = GetUnitToUnitDistance(bot, creep) - range
				local weight = siege and 2 or 1
				if gap > 0 and gap <= shortStep and weight > nextPriority then
					local origin = bot:GetLocation()
					local point = J.VectorTowards(origin, creep:GetLocation(), gap + 30)
					local mid = J.VectorTowards(origin, point, (gap + 30) * 0.5)
					if J.GetLocationToLocationDistance(point, hold) <= 235
						and IsLocationPassable(point) and IsLocationVisible(point) and IsLocationPassable(mid)
						and J.CanCommitToLaneTeleport(bot, point, true, 950)
						and J.CanCommitToLaneTeleport(bot, mid, true, 950) then
						nextPoint, nextPriority = point, weight
					end
				end
			end
		end
	end
	if target ~= nil then
		return J.IssueTowerDefenseAttack(bot, target)
	end
	if nextPoint then
		bot:Action_MoveToLocation(nextPoint)
		return true
	end
	if range >= 425 and not bot:IsDisarmed() then
		local poke, point = J.GetMidDefensePokeTarget(bot, range - 25, hold)
		if poke then return J.IssueTowerDefenseAttack(bot, poke) end
		if point then bot:Action_MoveToLocation(point); return true end
	end
	if awayFromHold then
		bot:Action_MoveToLocation(hold)
		return true
	elseif J.IsValidHero(bot:GetAttackTarget()) then
		bot:Action_ClearActions(true)
	end
	return false
end

-- A target handle can survive a completed or interrupted once-only attack.
-- Reissue when the order is stale without resetting a fresh windup.
function J.IssueTowerDefenseAttack(bot, target)
	local now = DotaTime()
	local last = bot.ohaTowerAttack
	local attackTime = math.max(0.26, bot:GetSecondsPerAttack())
	if bot:GetAttackTarget() == target then
		if last and last.target == target and now - last.issued < attackTime then return true end
		if (bot.ohaIdleReplanUntil or 0) <= now and J.IsAttacking(bot) then return true end
	end
	bot.ohaTowerAttack = {target=target, issued=now}
	bot:Action_AttackUnit(target, true)
	return true
end

function J.GetTowerDefenseTarget(bot)
	local state = bot._defend
	if state and state.waveClearGather and (state.waveClearTargetUntil or 0) > DotaTime()
		and (bot.ohaOuterTowerHoldUntil or 0) > DotaTime() and J.IsDefending(bot)
		and J.GetHP(bot) >= 0.5 and J.IsValidBuilding(state.waveClearTower) and J.IsValidHero(state.waveClearTarget)
		and J.IsInRange(state.waveClearTower, state.waveClearTarget, 950) then return state.waveClearTarget end
end

local function GetOuterTowerSpellStep(bot, tower, threat)
	local wave = threat.clearAt
	if not threat.underAttack or not wave or (threat.waveSize or 0) < 2
		or not IsLocationVisible(wave) or J.GetHP(bot) < 0.60 or bot:IsSilenced()
		or J.IsDisabled(bot) or bot:IsRooted() or bot:WasRecentlyDamagedByAnyHero(2) then return nil end
	local _, _, damage, impact, castRange = GetWaveClearScore(bot, 0)
	if damage == 0 or castRange < 425 or impact > 1.25 then return nil end
	-- The spell's effect radius helps the assignment score, but the cast
	-- still needs a target point within the actual cast range.
	local distance = GetUnitToLocationDistance(bot, wave) - castRange
	if distance <= 0 or distance > 245 then return nil end
	local origin = bot:GetLocation()
	local point = J.VectorTowards(origin, wave, distance + 25)
	local mid = J.VectorTowards(origin, point, (distance + 25) * 0.5)
	local fountain = J.GetTeamFountain()
	if GetUnitToLocationDistance(tower, point) > 850
		or J.GetLocationToLocationDistance(point, fountain) > GetUnitToLocationDistance(tower, fountain) + 100
		or not IsLocationVisible(point) or not IsLocationPassable(point) or not IsLocationPassable(mid)
		or J.GetAvailableFightAllies(bot, point, 900) == 0
		or not J.CanCommitToLaneTeleport(bot, point, true, 700)
		or not J.CanCommitToLaneTeleport(bot, mid, true, 700)
		or J.GetVisibleThreatAt(bot, threat.enemies, point, 1.6) >= bot:GetHealth() * 0.22 then return nil end
	return point
end

function J.TryStageTowerWaveCast(bot, tower, threat)
	local point = GetOuterTowerSpellStep(bot, tower, threat)
	if not point then return false end
	local now = DotaTime()
	local previous = bot.ohaTowerWaveCast
	if J.Customize and J.Customize.TraceLaneDecisions
		and (not previous or previous.tower ~= tower or previous.expires <= now) then
		print('[OHA tower-wave-cast]', now, bot:GetPlayerID(), tower:GetUnitName(),
			math.floor(GetUnitToLocationDistance(bot, threat.clearAt)))
	end
	bot.ohaTowerWaveCast = {tower = tower, expires = now + 1.4}
	bot:Action_MoveToLocation(point)
	return true
end

function J.RunOuterTowerContest(bot, tower, threat, state)
	state.waveClearTarget = nil
	if bot:IsUsingAbility() or bot:IsCastingAbility() or bot:IsChanneling() then return false end
	local hub = tower:GetLocation()
	local gather = state.waveClearGather
	local allies = {}
	for _, ally in ipairs(J.GetAlliesNearLoc(hub, 1350)) do
		if CanJoinTowerFight(ally) and not ally:HasModifier('modifier_teleporting') and not ally:IsChanneling()
			and GetUnitToLocationDistance(ally, gather) <= 1250 then
			allies[#allies + 1] = {hero = ally, eta = 0}
		end
	end
	if threat.towerHP >= 0.20 and CanJoinTowerFight(bot) and GetUnitToLocationDistance(bot, gather) <= 1250
		and CanTakeTowerFight(threat, allies) then
		local target, best = nil, -math.huge
		for _, enemy in ipairs(threat.enemies) do
			if J.IsValidHero(enemy) and J.CanBeAttacked(enemy) and GetUnitToUnitDistance(enemy, tower) <= 900 then
				local contact = 0
				for _, ally in ipairs(allies) do
					local hero = ally.hero
					if not hero:IsDisarmed() and J.IsInRange(hero, enemy, hero:GetAttackRange() + 125) then
						contact = contact + 1
					elseif threat.lane == LANE_MID and not hero:IsSilenced() and not hero:IsUsingAbility() then
						local _, reach, damage = GetWaveClearScore(hero, 0)
						if damage > 0 and J.IsInRange(hero, enemy, math.min(880, reach - 200)) then contact = contact + 1 end
					end
				end
				-- All defenders choose the same reachable target. Heroes outside
				-- spell range stay in cover instead of picking a different fight.
				local score = contact + 1 - J.GetHP(enemy) + (enemy:GetAttackTarget() == tower and 0.3 or 0)
				if contact >= 2 and (score > best or score == best and enemy:GetPlayerID() < target:GetPlayerID()) then
					target, best = enemy, score
				end
			end
		end
		if target and J.IsInRange(bot, target, math.max(650, bot:GetAttackRange() + 125)) then
			state.waveClearTarget, state.waveClearTargetUntil = target, DotaTime() + 0.8
			if J.IsInRange(bot, target, bot:GetAttackRange() + 100) then
				bot:Action_AttackUnit(target, true)
				return true
			end
		end
	end
	-- If a straight fight fails, this branch permits only one in-range hit
	-- at a time; the check is rerun when aggro, control or positions change.
	if state.waveClearScreen and not bot:IsDisarmed() and J.GetHP(bot) >= 0.48 then
		local target = ShortTowerTrade(bot, tower, threat, allies)
		if target and #J.GetEnemiesNearLoc(bot:GetLocation(), 550) < 2 then
			if J.Customize and J.Customize.TraceLaneDecisions and (bot.ohaShortTradeTrace or 0) < DotaTime() then
				bot.ohaShortTradeTrace = DotaTime() + 3
				print('[OHA tower trade]', DotaTime(), bot:GetPlayerID(), target:GetPlayerID())
			end
			bot:Action_AttackUnit(target, true)
			return true
		end
	end
	if #J.GetEnemiesNearLoc(gather, state.waveClearScreen and 550 or 800) >= 2 or bot:WasRecentlyDamagedByAnyHero(2)
		and (#J.GetEnemiesNearLoc(bot:GetLocation(), 800) >= 2 or J.GetHP(bot) < 0.5) then
		bot:Action_MoveToLocation(J.AdjustLocationWithOffsetTowardsFountain(hub, 1200))
		return true
	end
	if not state.waveClearCover and J.TryStageTowerWaveCast(bot, tower, threat) then return true end
	local hold = gather
	if state.waveClearScreen and not state.waveClearCover then
		hold = GetOuterTowerHoldPoint(hub, state.waveClearReach or bot:GetAttackRange(), false)
	end
	local stage = J.GetTowerHoldFormationPoint and J.GetTowerHoldFormationPoint(bot, hub, hold,
		state.waveClearReach or bot:GetAttackRange(), threat.enemies, J.GetAlliesNearLoc(gather, 1400)) or hold
	if GetUnitToLocationDistance(bot, stage) > 275 then
		bot:Action_MoveToLocation(stage)
		return true
	end
	-- Do not let a shorter-range hero walk ahead of the rally point while the others arrive.
	return J.RunOuterTowerHold(bot, hub, math.max(975, state.waveClearReach or bot:GetAttackRange()),
		state.waveClearScreen and state.waveClearCover or false, (state.waveClearScreen or stage ~= gather) and stage or nil)
end

function J.GetAssignedOuterTower(bot)
	local response = bot.ohaHighGroundResponse
	if response and DotaTime() < response.expires and J.IsValidBuilding(response.tower)
		and GetUnitToLocationDistance(bot, response.stage) <= 500 then return response.tower end
	local guard = bot.ohaMidCover
	if guard and DotaTime() < guard.expires and J.IsValidBuilding(guard.tower) then
		if not guard.cover or (GetUnitToUnitDistance(bot, guard.tower) <= 1000
			and J.GetOuterTowerThreat(guard.tower, guard.lane or LANE_MID).underAttack) then return guard.tower end
	end
	local state = bot._defend
	if state and (bot.ohaOuterTowerHoldUntil or 0) > DotaTime() then
		local tower = state.waveClearRearTower or state.waveClearTower
		if J.IsValidBuilding(tower) and (not state.waveClearCover or state.waveClearLane
			and GetUnitToUnitDistance(bot, tower) <= 1000 and J.GetOuterTowerThreat(tower, state.waveClearLane).underAttack) then return tower end
	end
end

-- A numerical advantage does not protect the particular hero being focused.
-- Require separate visible attackers with a current target and real contact.
local function CanFireDuringFocus(hero)
	return not hero:IsStunned() and not hero:IsHexed() and not hero:IsNightmared() and not hero:IsDisarmed()
end

function J.GetCoreFocusPressure(bot, enemies)
	if not J.IsCore(bot) then return 0, 0 end
	local counted, count, damage = {}, 0, 0
	for _, enemy in ipairs(enemies) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) and CanFireDuringFocus(enemy) and enemy:GetAttackTarget() == bot
			and J.IsInRange(enemy, bot, enemy:GetAttackRange() + 160) then
			local id = enemy:GetPlayerID()
			if not counted[id] then
				counted[id], count = true, count + 1
				damage = damage + enemy:GetEstimatedDamageToTarget(false, bot, 1.6, DAMAGE_TYPE_PHYSICAL)
			end
		end
	end
	return count, damage
end

function J.GetCoreFocusPeelTarget(bot, allies, enemies, castRange)
	if DotaTime() < 8 * 60 or #enemies == 0 or J.GetHP(bot) < 0.42 then return nil end
	local best, bestScore = nil, 0
	for _, ally in ipairs(allies) do
		if ally ~= bot and J.IsValidHero(ally) and J.IsCore(ally) and J.GetHP(ally) <= 0.78
			and J.IsInRange(bot, ally, 1300) then
			local count, damage = J.GetCoreFocusPressure(ally, enemies)
			if count >= 2 and damage >= ally:GetHealth() * 0.42
				or count == 1 and J.GetHP(ally) <= 0.40 and damage >= ally:GetHealth() * 0.62 then
				for _, enemy in ipairs(enemies) do
					if IsFightFocusCandidate(enemy) and enemy:GetAttackTarget() == ally and CanFireDuringFocus(enemy) and J.IsInRange(enemy, ally, enemy:GetAttackRange() + 160)
						and J.IsInRange(bot, enemy, castRange) and J.CanCastOnNonMagicImmune(enemy)
						and J.CanCastOnTargetAdvanced(enemy) then
						local score = enemy:GetEstimatedDamageToTarget(false, ally, 1.6, DAMAGE_TYPE_PHYSICAL)
							/ math.max(1, ally:GetHealth())
						if score > bestScore then best, bestScore = enemy, score end
					end
				end
			end
		end
	end
	return best
end

local function CanFinishValuableFightTrade(bot)
	-- Preserve only an already committed melee hit while rooted. Do not chase
	-- an expensive target, and never bypass an independent emergency retreat.
	if not bot:IsRooted() or bot:GetAttackRange() >= 310 or J.GetHP(bot) > 0.30
		or not CanFireDuringFocus(bot) or not J.IsAttacking(bot) then return false end
	local target = bot:GetAttackTarget()
	if not IsFightFocusCandidate(target) or target:GetTeam() == bot:GetTeam() or not J.IsCore(target)
		or target:GetUnitName() == 'npc_dota_hero_skeleton_king' or target:FindItemSlot('item_aegis') >= 0
		or target:HasModifier('modifier_item_blade_mail_reflect') or target:HasModifier('modifier_templar_assassin_refraction_absorb')
		or target:GetUnitName() == 'npc_dota_hero_medusa'
		or not J.IsInRange(bot, target, bot:GetAttackRange()) then return false end
	local remaining = bot:GetAttackPoint() - bot:GetAnimCycle()
	if remaining < 0 or remaining > 0.28
		or not J.CanKillTarget(target, bot:GetAttackDamage() * 0.85, DAMAGE_TYPE_PHYSICAL) then return false end
	local ours, theirs = J.GetVisibleFightInventoryValue(bot), J.GetVisibleFightInventoryValue(target)
	return ours > 0 and theirs >= math.max(ours + 2200, ours * 1.30)
end

function J.ShouldPreserveCoreFightTrade(bot, enemies)
	if DotaTime() < 8 * 60 or #enemies < 2 or not J.IsCore(bot) or not bot:IsRooted() then return false end
	local count, damage = J.GetCoreFocusPressure(bot, enemies)
	return count >= 2 and damage >= bot:GetHealth() * 0.42 and CanFinishValuableFightTrade(bot)
end

function J.ShouldDisengageAtLostTower(bot, now)
	for tower, front in pairs(J.recentlyBesiegedTowers or {}) do
		if now - front.seen > 8 or now < front.seen then
			J.recentlyBesiegedTowers[tower] = nil
		elseif (tower:IsNull() or not tower:IsAlive()) and GetUnitToLocationDistance(bot, front.point) <= 1800 then
			local enemies = J.GetEnemiesNearLoc(front.point, 1250)
			if #enemies >= 2 then
				local nearest, gap = nil, math.huge
				for _, enemy in ipairs(enemies) do
					local distance = GetUnitToUnitDistance(bot, enemy)
					if distance < gap then nearest, gap = enemy, distance end
				end
				if nearest and gap <= 1400 and (gap <= nearest:GetAttackRange() + 180
					or bot:IsFacingLocation(nearest:GetLocation(), 50) and J.IsMoving(bot)) then
					local point = J.VectorTowards(bot:GetLocation(), nearest:GetLocation(),
						math.min(350, math.max(0, gap - bot:GetAttackRange())))
					local allies = J.GetAlliesNearLoc(point, 1000)
					local ready = J.GetLocalFightReadiness(bot, allies, enemies)
					local incoming = J.GetVisibleThreatAt(bot, enemies, point, 2.5)
					if ready ~= true and incoming >= bot:GetHealth() * 0.50
						and (ready == false or J.GetAvailableFightAllies(bot, point, 850) < #enemies) then return true end
				end
			end
		end
	end
	return false
end

local function HasImmediateFightCover(bot, location, enemies)
	for _, ally in ipairs(J.GetAlliesNearLoc(location, 1400)) do
		if ally ~= bot and CanProvideFightContact(ally) then
			for _, enemy in ipairs(enemies) do
				if HasFightContact(ally, enemy, 120) then return true end
			end
		end
	end
	return false
end

function J.ShouldRetreatFromEnemyReinforcements(bot)
	local now = DotaTime()
	if now < 0 or not bot:IsAlive() or bot:HasModifier('modifier_fountain_invulnerability') then return false end
	if J.recentlyBesiegedTowers and J.ShouldDisengageAtLostTower(bot, now) then
		bot.ohaReinforcementRetreatAt = now
		return true
	end

	local enemyTeam = GetOpposingTeam()
	if now >= 8 * 60 then
		local target = bot:GetAttackTarget() or bot:GetTarget()
		if J.IsValidHero(target) and target:GetTeam() == enemyTeam
			and GetUnitToUnitDistance(bot, target) > bot:GetAttackRange() + 100 then
			local ancient = GetAncient(enemyTeam)
			if ancient ~= nil then
				local fromBase, targetFromBase = GetUnitToUnitDistance(bot, ancient), GetUnitToUnitDistance(target, ancient)
				if fromBase < 3800 and targetFromBase < 2450 and targetFromBase + 250 < fromBase
					and (targetFromBase < 1600 or GetHeightLevel(target:GetLocation()) > GetHeightLevel(bot:GetLocation()))
					and not J.HasSiegeDamageInRange(bot, target:GetLocation()) then
					bot.ohaReinforcementRetreatAt = now
					return true
				end
			end
		end
	end
	local threats = {}
	local incoming = 0
	for _, tp in ipairs(GetIncomingTeleports()) do
		if tp.playerid ~= nil and tp.location ~= nil and tp.time_remaining ~= nil
			and tp.time_remaining >= 0 and tp.time_remaining <= 4
			and GetTeamForPlayer(tp.playerid) == enemyTeam
			and GetUnitToLocationDistance(bot, tp.location) <= 1250 and IsLocationVisible(tp.location)
			and not threats[tp.playerid]
		then
			threats[tp.playerid] = true
			incoming = incoming + 1
		end
	end

	local location = bot:GetLocation()
	local total, close = incoming, 0
	local closePlayers = {}
	local underFire, empoweredAttacker = false, nil
	local enemies = J.GetEnemiesNearLoc(location, 1400)
	for _, enemy in ipairs(enemies) do
		local id = enemy:GetPlayerID()
		local distance = GetUnitToUnitDistance(bot, enemy)
		local inFiringRange = enemy:GetAttackTarget() == bot and distance <= enemy:GetAttackRange() + 250
		underFire = underFire or inFiringRange
		if inFiringRange and enemy:HasModifier('modifier_rune_doubledamage') then empoweredAttacker = enemy end
		if not closePlayers[id] and (distance <= 1000 or inFiringRange) then
			closePlayers[id] = true
			close = close + 1
		end
		if not threats[id] then
			threats[id] = true
			total = total + 1
		end
	end
	local backup = total > 0 and J.GetAvailableFightAllies(bot, location, 1400) or 0
	local damaged = bot:WasRecentlyDamagedByAnyHero(2)
	if close > 0 and (J.GetHP(bot) <= 0.75 or underFire and close >= 2) then
		for _, tower in ipairs(bot:GetNearbyTowers(950, true)) do
			if J.IsValidBuilding(tower) and tower:GetAttackTarget() == bot then
				bot.ohaReinforcementRetreatAt = now
				return true
			end
		end
	end
	local losingDuel = empoweredAttacker ~= nil and backup == 0 and J.GetHP(bot) <= 0.8
		and (J.GetHP(bot) < 0.5 or J.GetHP(empoweredAttacker) > 0.35)
	-- A ranged opponent can win an isolated duel without a damage rune.
	if not losingDuel and now >= 4 * 60 and #enemies == 1 and backup == 0 and damaged then
		local enemy, hp = enemies[1], J.GetHP(bot)
		local distance = GetUnitToUnitDistance(bot, enemy)
		if enemy:GetAttackRange() >= 450 and distance <= 1200 and hp <= 0.75
			and (underFire or bot:WasRecentlyDamagedByHero(enemy, 2))
			and (hp <= 0.40 or J.GetHP(enemy) >= hp + 0.18) then
			local window = 3.5
			local damage = J.GetVisibleThreatAt(bot, enemies, location, window)
			local health = bot:GetHealth() + window * bot:GetHealthRegen()
			losingDuel = damage >= health * (distance > bot:GetAttackRange() + 50 and 0.63 or 0.80)
			if losingDuel and J.Customize and J.Customize.TraceLaneDecisions
				and now - (bot.ohaReinforcementRetreatAt or -math.huge) > 1.25 then
				print('[OHA retreat-exposure]', now, bot:GetPlayerID(), 'solo-ranged', math.floor(health), math.floor(damage))
			end
		end
	end
	local isolatedLaner = false
	if now >= 40 and now < 14 * 60 and #enemies >= 2 and backup == 0 and J.IsInLaningPhase(bot)
		and (bot:GetAttackRange() >= 400 or J.GetHP(bot) <= 0.74) then
		local lane = bot:GetAssignedLane()
		isolatedLaner = lane == LANE_TOP or lane == LANE_BOT
	end
	local exposedRangedHero = now >= 6 * 60 and #enemies >= 2 and bot:GetAttackRange() >= 400
		and (backup == 0 or now >= 8 * 60 and J.IsCore(bot)
			and not J.IsValidBuilding(bot:GetNearbyTowers(850, false)[1])
			and not HasImmediateFightCover(bot, location, enemies))
	local closing = 0
	if close > 0 and (isolatedLaner or exposedRangedHero or now >= 8 * 60 and backup == 0 and total >= 3 and close < 3) then
		for _, enemy in ipairs(enemies) do
			local distance = GetUnitToUnitDistance(bot, enemy)
			if J.GetLocationToLocationDistance(enemy:GetExtrapolatedLocation(0.8), location) < distance - 90 then
				closing = closing + 1
			end
		end
	end
	local losingGank, keepLeaving = false, false
	local advancing = closing > 0 or underFire
	local exposureUntil = bot.ohaExposureRetreatUntil or 0
	if (isolatedLaner or exposedRangedHero) and (advancing or exposureUntil > now) then
		local window = isolatedLaner and 5.0 or 4.5
		local damage, control, contacts = J.GetVisibleThreatAt(bot, enemies, location, window, true)
		local health = bot:GetHealth() + window * bot:GetHealthRegen()
		-- Leave a margin for follow-up attacks while a reachable disable prevents escape.
		losingGank = advancing and contacts >= 2 and (exposedRangedHero or control)
			and damage >= health * (control and 0.80 or 1)
		keepLeaving = exposureUntil > now and backup == 0 and control and contacts >= 2 and damage >= health * 0.60
		if losingGank then bot.ohaExposureRetreatUntil = now + 4.0 end
		if losingGank and J.Customize and J.Customize.TraceLaneDecisions
			and now - (bot.ohaReinforcementRetreatAt or -math.huge) > 1.25 then
			print(string.format('[OHA retreat-exposure] %.2f player=%d health=%.0f damage=%.0f control=%s allies=%d',
				now, bot:GetPlayerID(), health, damage, tostring(control), backup))
		end
	end
	local isolated = now >= 8 * 60 and close >= 2 and total >= backup + 2
		and (backup == 0 or J.GetHP(bot) < 0.7)
		and (close >= 3 or damaged)
	local losingExchange = now >= 8 * 60 and damaged and J.GetHP(bot) <= 0.58
		and (close >= 2 or (underFire and backup == 0)) and total >= backup + 1
		and not J.WeAreStronger(bot, 1400)
	if losingDuel or losingGank or (total >= 3 and closing >= 2) or isolated or losingExchange
		or (total >= 4 and (incoming >= 2 or close >= 3) and total >= backup + 3) then
		bot.ohaReinforcementRetreatAt = now
		return true
	end

	if now >= 8 * 60 and #enemies >= 2 and J.IsCore(bot) and J.GetHP(bot) <= 0.78 then
		local count, damage = J.GetCoreFocusPressure(bot, enemies)
		local health = bot:GetHealth()
		if count >= 2 and (damage >= health * 0.42 or (count >= 3 and damaged and damage >= health * 0.24))
			and not CanFinishValuableFightTrade(bot) then
			bot.ohaReinforcementRetreatAt = now
			return true
		end
	end
	-- Finish disengaging if arrivals drop out of the TP list or briefly leave vision.
	local started = bot.ohaReinforcementRetreatAt
	-- The hard danger checks above still win. A healthy bot already in
	-- contact may re-engage when the arrival is no longer an overload.
	if incoming == 0 and not underFire and backup > 0 and total <= backup + 1
		and J.GetHP(bot) >= 0.60 then return false end
	return keepLeaving or started ~= nil and now >= started and now - started < 1.25
end

function J.IsCreepBetweenMeAndTarget(hSource, hTarget, vLoc, nRadius)
	local vStart = hSource:GetLocation()
	local vEnd = vLoc
	local creeps = hSource:GetNearbyCreeps(1600, false)
	for i,creep in pairs(creeps) do
		local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation());
		if tResult ~= nil and tResult.within and tResult.distance <= nRadius then
			return true
		end
	end
	
	if hTarget:IsHero() then
		creeps = hTarget:GetNearbyCreeps(1600, true)
		for i,creep in pairs(creeps) do
			local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation());
			if tResult ~= nil and tResult.within and tResult.distance <= nRadius then
				return true
			end
		end
	end
	
	creeps = hSource:GetNearbyCreeps(1600, true)
	for i,creep in pairs(creeps) do
		local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation());
		if tResult ~= nil and tResult.within and tResult.distance <= nRadius then
			return true
		end
	end
	
	if hTarget:IsHero() then
		creeps = hTarget:GetNearbyCreeps(1600, false)
		for i,creep in pairs(creeps) do
			local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation());
			if tResult ~= nil and tResult.within and tResult.distance <= nRadius then
				return true
			end
		end
	end
	
	return false
end

-- function J.IsEnemyCreepBetweenMeAndTarget(hSource, hTarget, vLoc, nRadius)
-- 	local vStart = hSource:GetLocation()
-- 	local vEnd = vLoc

-- 	local nAllyLaneCreeps = hTarget:GetNearbyLaneCreeps(1600, false)
-- 	for _, creep in pairs(nAllyLaneCreeps)
-- 	do
-- 		local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation())
-- 		if tResult ~= nil and tResult.within and tResult.distance < nRadius then return true end
-- 	end

-- 	local nEnemyLaneCreeps = hSource:GetNearbyLaneCreeps(1600, true)
-- 	for _, creep in pairs(nEnemyLaneCreeps)
-- 	do
-- 		local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation())
-- 		if tResult ~= nil and tResult.within and tResult.distance < nRadius then return true end
-- 	end

-- 	return false
-- end

-- function J.IsAllyCreepBetweenMeAndTarget(hSource, hTarget, vLoc, nRadius)
-- 	local vStart = hSource:GetLocation()
-- 	local vEnd = vLoc

-- 	local nAllyLaneCreeps = hSource:GetNearbyLaneCreeps(1600, false)
-- 	for _, creep in pairs(nAllyLaneCreeps)
-- 	do
-- 		local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation())
-- 		if tResult ~= nil and tResult.within and tResult.distance < nRadius then
-- 			return true
-- 		end
-- 	end

-- 	local nEnemyLaneCreeps = hTarget:GetNearbyLaneCreeps(1600, true)
-- 	for _, creep in pairs(nEnemyLaneCreeps)
-- 	do
-- 		local tResult = PointToLineDistance(vStart, vEnd, creep:GetLocation())
-- 		if tResult ~= nil and tResult.within and tResult.distance < nRadius then
-- 			return true
-- 		end
-- 	end

-- 	return false
-- end

function J.IsAllyHeroBetweenMeAndTarget(hSource, hTarget, vLoc, nRadius)
	local vStart = hSource:GetLocation()
	local vEnd = vLoc

	local nAllyHeroes = J.GetNearbyHeroes(hSource, 1600, false, BOT_MODE_NONE)
	for _, allyHero in pairs(nAllyHeroes)
	do
		if allyHero ~= hSource
		then
			local tResult = PointToLineDistance(vStart, vEnd, allyHero:GetLocation())
			if tResult ~= nil and tResult.within and tResult.distance <= nRadius + 50 then return true end
		end
	end

	local nEnemyHeroes = J.GetNearbyHeroes(hTarget, 1600, true, BOT_MODE_NONE)
	for _, enemyHero in pairs(nEnemyHeroes)
	do
		if enemyHero ~= hSource
		and not J.IsSuspiciousIllusion(enemyHero)
		then
			local tResult = PointToLineDistance(vStart, vEnd, enemyHero:GetLocation())
			if tResult ~= nil and tResult.within and tResult.distance <= nRadius + 50 then return true end
		end
	end

	return false
end

local sIgnoreAbilityIndex = {
	["antimage_blink"] = true,
	["arc_warden_magnetic_field"] = true,
	["arc_warden_spark_wraith"] = true,
	["arc_warden_tempest_double"] = true,
	["chaos_knight_phantasm"] = true,
	["clinkz_burning_army"] = true,
	["death_prophet_exorcism"] = true,
	["dragon_knight_elder_dragon_form"] = true,
	["juggernaut_healing_ward"] = true,
	["necrolyte_death_pulse"] = true,
	["necrolyte_sadist"] = true,
	["omniknight_guardian_angel"] = true,
	["phantom_assassin_blur"] = true,
	["pugna_nether_ward"] = true,
	["skeleton_king_mortal_strike"] = true,
	["sven_warcry"] = true,
	["sven_gods_strength"] = true,
	["templar_assassin_refraction"] = true,
	["templar_assassin_psionic_trap"] = true,
	["windrunner_windrun"] = true,
	["witch_doctor_voodoo_restoration"] = true,
}
function J.DidEnemyCastAbility()
	local bot = GetBot()
	local nEnemyHeroes = J.GetNearbyHeroes(bot,1200, true, BOT_MODE_NONE)

	for _, npcEnemy in pairs(nEnemyHeroes)
	do
		if npcEnemy ~= nil and npcEnemy:IsAlive()
		and npcEnemy:IsFacingLocation(bot:GetLocation(), 30)
		and (npcEnemy:IsCastingAbility() or npcEnemy:IsUsingAbility())
		then
			local nAbility = npcEnemy:GetCurrentActiveAbility()
			if nAbility ~= nil
			then
				local nAbilityBehavior = nAbility:GetBehavior()
				local sAbilityName = nAbility:GetName()

				if nAbilityBehavior ~= ABILITY_BEHAVIOR_UNIT_TARGET
				and (npcEnemy:IsBot() or npcEnemy:GetLevel() >= 5)
				and not sIgnoreAbilityIndex[sAbilityName]
				then
					return true
				end

				if nAbilityBehavior == ABILITY_BEHAVIOR_UNIT_TARGET
				and npcEnemy:GetLevel() >= 6
				and not npcEnemy:IsBot()
				and not J.IsAllyUnitSpell(sAbilityName)
				and (not J.IsProjectileUnitSpell(sAbilityName) or J.IsInRange(bot, npcEnemy, 400))
				then
					return true
				end
			end
		end
	end

	return false
end

function J.GetWeakestUnit(nEnemyUnits)
	return J.GetAttackableWeakestUnitFromList( nil, nEnemyUnits )
end

function J.HasInvisibilityOrItem( npcEnemy )

	if npcEnemy:HasInvisibility( false )
		or J.HasItem( npcEnemy, "item_shadow_amulet" )
		or J.HasItem( npcEnemy, "item_glimmer_cape" )
		or J.HasItem( npcEnemy, "item_invis_sword" )
		or J.HasItem( npcEnemy, "item_silver_edge" )
	then
		return true
	end

	return false

end

function J.HasEnemyIceSpireNearby(bot, nRange)
	-- local cacheKey = 'HasEnemyIceSpireNearby'..tostring(bot:GetPlayerID())
	-- local cache = J.Utils.GetCachedVars(cacheKey, 1)
	-- if cache ~= nil then return cache end

	-- should also consider neutral creeps etc. tba.
	for _, enemy in pairs(GetUnitList(UNIT_LIST_ENEMIES)) do
        if J.IsValid(enemy)
		and enemy:GetUnitName() == "npc_dota_lich_ice_spire"
		and J.IsInRange(bot, enemy, nRange) then
			-- J.Utils.SetCachedVars(cacheKey, true)
			return enemy
		end
	end
	-- J.Utils.SetCachedVars(cacheKey, false)
	return false
end

function J.AnyAllyAffectedByChainFrost(bot, nRange)
	-- local cacheKey = 'AnyAllyAffectedByChainFrost'..tostring(bot:GetPlayerID())
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.15)
	-- if cache ~= nil then return cache end

	-- ally heroes, creeps, units.
	for _, ally in pairs(GetUnitList(UNIT_LIST_ALLIES))
	do
        if J.IsValid(ally)
        and J.IsInRange(bot, ally, nRange)
		and ally ~= bot
        and ally:HasModifier('modifier_lich_chainfrost_slow') then
			-- J.Utils.SetCachedVars(cacheKey, true)
            return true
        end
    end
	-- J.Utils.SetCachedVars(cacheKey, false)
	return false
end

function J.AdjustLocationWithOffset(vLoc, offset, target)
	local targetLoc = vLoc

	local facingDir = target:GetFacing()
	local offsetX = offset * math.cos(facingDir)
	local offsetY = offset * math.sin(facingDir)

	targetLoc = targetLoc + Vector(offsetX, offsetY)

	return targetLoc
end

function J.AdjustLocationWithOffsetTowardsFountain(loc, distance)
	return J.Utils.GetOffsetLocationTowardsTargetLocation(loc, J.GetTeamFountain(), distance)
end

function J.IsInLaningPhase(unit)
	local nTime = DotaTime()
	local bTurbo = J.IsModeTurbo()

	-- Hard time floor: always laning phase before 8min (turbo) / 10min (normal)
	if bTurbo and nTime < 8 * 60 then return true end
	if not bTurbo and nTime < 10 * 60 then return true end

	-- Soft extension: still laning up to 10min (turbo) / 14min (normal) if networth is low
	if bTurbo and nTime < 10 * 60 and (unit or GetBot()):GetNetWorth() < 8000 then return true end
	if not bTurbo and nTime < 14 * 60 and (unit or GetBot()):GetNetWorth() < 8000 then return true end

	return false
end

function J.IsTormentor(nTarget)
	return nTarget ~= nil
			and not nTarget:IsNull()
			and nTarget:CanBeSeen()
			and nTarget:IsAlive()
			and string.find(nTarget:GetUnitName(), 'miniboss') ~= nil
end

function J.IsDoingTormentor(bot)
	return bot:GetActiveMode() == BOT_MODE_SIDE_SHOP
end

local function GetChronosphereStandOff(bot, location, radius)
	local distance = GetUnitToLocationDistance(bot, location)
	if distance > radius + 320 then return nil end

	local projectedDistance = J.GetLocationToLocationDistance(bot:GetExtrapolatedLocation(0.45), location)
	local entering = projectedDistance < distance - 10 and projectedDistance <= radius + 45
	if not entering and not J.IsRetreating(bot) and distance <= radius + 130 then
		local target = bot:GetAttackTarget()
		entering = J.IsValid(target) and not J.IsInRange(bot, target, bot:GetAttackRange())
			and GetUnitToLocationDistance(target, location) <= radius
	end
	if not entering and distance > radius then return nil end

	local origin = bot:GetLocation()
	if distance < 1 then return J.AdjustLocationWithOffsetTowardsFountain(origin, radius + 130) end
	local safe = J.VectorAway(origin, location, math.max(70, radius + 130 - distance))
	if IsLocationPassable(safe) then return safe end
	return origin
end

function J.GetShrapnelEscapeLocation(bot)
	if bot:IsMagicImmune() or bot:IsRooted() then
		bot.ohaShrapnelExit = nil
		return nil
	end
	local now = DotaTime()
	if not bot:HasModifier('modifier_sniper_shrapnel_slow') then
		local exit = bot.ohaShrapnelExit
		if exit and now < exit.untilTime and GetUnitToLocationDistance(bot, exit.origin) < 650
			and IsLocationPassable(exit.point) then return exit.point end
		bot.ohaShrapnelExit = nil
		return nil
	end
	local origin = bot:GetLocation()
	local fountain = J.GetTeamFountain()
	local fallback = J.AdjustLocationWithOffsetTowardsFountain(origin, 525)
	-- Stay beyond the edge for two damage ticks after the last observed slow.
	-- A lane order on the first clear tick otherwise walks straight back in.
	local function remember(point)
		bot.ohaShrapnelExit = {origin = origin, point = point, untilTime = now + 2}
		return point
	end
	local tower = bot:GetNearbyTowers(1550, true)[1]
	local function isSafe(point)
		return IsLocationPassable(point) and (not J.IsValidBuilding(tower)
			or GetUnitToLocationDistance(tower, point) > 850
			or GetUnitToLocationDistance(tower, point) > GetUnitToLocationDistance(tower, origin))
	end
	if type(GetAvoidanceZones) == 'function' then
		local best, bestDistance = nil, math.huge
		for _, zone in pairs(GetAvoidanceZones() or {}) do
			local center, radius = zone.location, zone.radius
			if center ~= nil and type(radius) == 'number' and radius > 0
				and zone.ability ~= nil and not zone.ability:IsNull() and zone.ability:GetName() == 'sniper_shrapnel'
				and zone.caster ~= nil and not zone.caster:IsNull() and zone.caster:GetTeam() ~= bot:GetTeam()
				and IsLocationVisible(center) then
				local distance = J.GetLocationToLocationDistance(origin, center)
				if distance > 1 and distance < radius + 30 then
					local step = radius + 200 - distance
					local point = J.VectorAway(origin, center, step)
					if step < bestDistance and isSafe(point)
						and J.GetLocationToLocationDistance(point, fountain) <= J.GetLocationToLocationDistance(origin, fountain) + 120 then
						best, bestDistance = point, step
					end
				end
			end
		end
		if best ~= nil then return remember(best) end
	end
	if isSafe(fallback) then return remember(fallback) end
	local shortStep = J.AdjustLocationWithOffsetTowardsFountain(origin, 260)
	if isSafe(shortStep) then return remember(shortStep) end
end

function J.GetChronosphereAvoidanceLocation(bot)
	-- Team handles also cover allied casts omitted by the engine zone list.
	local now = GameTime()
	for i = 1, #GetTeamPlayers(bot:GetTeam()) do
		local ally = GetTeamMember(i)
		local sphere = ally ~= nil and ally ~= bot and ally.ohaChronosphere
		if sphere and now < sphere.expires then
			local safe = GetChronosphereStandOff(bot, sphere.location, sphere.radius)
			if safe ~= nil then return safe end
		end
	end
	if GetAvoidanceZones == nil then return nil end
	for _, zone in pairs(GetAvoidanceZones()) do
		if zone.caster ~= nil and zone.caster ~= bot and not zone.caster:IsNull() and zone.caster:GetTeam() == bot:GetTeam()
			and zone.ability ~= nil and not zone.ability:IsNull() and zone.ability:GetName() == 'faceless_void_chronosphere'
			and zone.location ~= nil and zone.radius ~= nil and zone.radius > 0 then
			local safe = GetChronosphereStandOff(bot, zone.location, zone.radius)
			if safe ~= nil then return safe end
		end
	end
	return nil
end

function J.IsLocationInChrono(loc)
	for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if J.IsValidHero(enemyHero)
		and not J.IsSuspiciousIllusion(enemyHero)
		and GetUnitToLocationDistance(enemyHero, loc) < 300
		and enemyHero:HasModifier('modifier_faceless_void_chronosphere_freeze')
		then
			return true
		end
	end

	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if J.IsValidHero(allyHero)
		and not allyHero:IsIllusion()
		and GetUnitToLocationDistance(allyHero, loc) < 300
		and (allyHero:HasModifier('modifier_faceless_void_chronosphere_freeze'))
		then
			return true
		end
	end

	return false
end

function J.IsLocationInBlackHole(loc)
	for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if J.IsValidHero(enemyHero)
		and not J.IsSuspiciousIllusion(enemyHero)
		and GetUnitToLocationDistance(enemyHero, loc) < 300
		and (enemyHero:HasModifier('modifier_enigma_black_hole_pull')
			or enemyHero:HasModifier('modifier_enigma_black_hole_pull_scepter'))
		then
			return true
		end
	end

	return false
end

function J.IsEnemyChronosphereInLocation(loc)
	local nRadius = 500

	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIES))
	do
		if J.IsValid(unit)
		and GetUnitToLocationDistance(unit, loc) <= nRadius
		and unit:HasModifier('modifier_faceless_void_chronosphere_freeze')
		then
			return true
		end
	end

	return false
end

function J.IsEnemyBlackHoleInLocation(loc)
	local nRadius = 500

	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIES))
	do
		if J.IsValid(unit)
		and GetUnitToLocationDistance(unit, loc) <= nRadius
		and (unit:HasModifier('modifier_enigma_black_hole_pull') or unit:HasModifier('modifier_enigma_black_hole_pull_scepter'))
		then
			return true
		end
	end

	return false
end


function J.IsLocationInArena(loc, radius)
	for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
	do
		if J.IsValidHero(enemyHero)
		and not J.IsSuspiciousIllusion(enemyHero)
		and GetUnitToLocationDistance(enemyHero, loc) < radius
		and (enemyHero:HasModifier('modifier_mars_arena_of_blood_leash')
			or enemyHero:HasModifier('modifier_mars_arena_of_blood_animation'))
		then
			return true
		end
	end

	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if J.IsValidHero(allyHero)
		and not allyHero:IsIllusion()
		and GetUnitToLocationDistance(allyHero, loc) < radius
		and (allyHero:HasModifier('modifier_mars_arena_of_blood_animation'))
		then
			return true
		end
	end

	return false
end

function J.GetMeepos()
	local Meepos = {}

	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if J.IsValidHero(allyHero)
		and allyHero:GetUnitName() == 'npc_dota_hero_meepo'
		and not J.IsSuspiciousIllusion(allyHero)
		then
			table.insert(Meepos, allyHero)
		end
	end

	return Meepos
end

function J.IsMeepoClone(hero)
	if J.IsValidHero(hero)
	and hero:GetUnitName() == 'npc_dota_hero_meepo'
	then
		for i = 0, 5
		do
			local hItem = hero:GetItemInSlot(i)

			if hItem ~= nil
			and not (hItem:GetName() == 'item_boots'
					or hItem:GetName() == 'item_tranquil_boots'
					or hItem:GetName() == 'item_arcane_boots'
					or hItem:GetName() == 'item_power_treads'
					or hItem:GetName() == 'item_phase_boots'
					or hItem:GetName() == 'item_travel_boots'
					or hItem:GetName() == 'item_boots_of_bearing'
					or hItem:GetName() == 'item_guardian_greaves'
					or hItem:GetName() == 'item_travel_boots_2'
				)  
			then
				return false
			end
		end

		return true
    end
end

function J.DoesSomeoneHaveModifier(nUnitList, modifierName)
	for _, unit in pairs(nUnitList)
	do
		if J.IsValid(unit)
		and unit:HasModifier(modifierName)
		then
			return true
		end
	end

	return false
end

-- count the number of human vs bot players in the team. returns: #humen, #bots
function J.NumHumanBotPlayersInTeam()
	local nHuman, nBot = 0, 0
	for _, member in pairs(GetTeamPlayers(GetTeam()))
	do
		if not IsPlayerBot(member)
		then
			nHuman = nHuman + 1
		else
			nBot = nBot + 1
		end
	end

	return nHuman, nBot
end

function J.GetEnemiesAroundAncient(bot, nRadius)
	if bot == nil then bot = GetBot() end
	return J.GetEnemiesAroundLoc(GetAncient(bot:GetTeam()):GetLocation(), nRadius)
end
function J.DoesUnitHaveTemporaryBuff(hUnit)
	local sUnitName = hUnit:GetUnitName()
	if sUnitName == 'npc_dota_hero_huskar' and J.GetHP(hUnit) < 0.6 then
		return true
	end

	for i = 0, hUnit:NumModifiers() do
		local sDuration = hUnit:GetModifierRemainingDuration(i)
		if (sDuration > 0.5)
		or (sDuration > -1 and sDuration < 0.5)
		then
			return true
		end
	end

	return false
end

function J.GetEnemiesAroundLoc(vLoc, nRadius)
	if not nRadius then nRadius = 2000 end
	-- local cacheKey = 'GetEnemiesAroundLoc'..tostring(nRadius) ..'-'..tostring(J.ToNearest500(vLoc.x))..'-'..tostring(J.ToNearest500(vLoc.y))
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	local nUnitCount = 0
	local ancientLoc = GetAncient(GetBot():GetTeam()):GetLocation()

	-- Check Heroes. 
	for _, id in pairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(id) then
			local info = GetHeroLastSeenInfo(id)
			if info ~= nil then
				local dInfo = info[1]
				if dInfo ~= nil
				and J.GetLocationToLocationDistance(vLoc, dInfo.location) <= nRadius
				and dInfo.time_since_seen < 5.0
				then
					nUnitCount = nUnitCount + GetHeroLevel(id) / 3
					if J.GetLocationToLocationDistance(ancientLoc, vLoc) < 1600 then
						nUnitCount = nUnitCount + 2 -- Increase weight for critical defense.
					end
				end
			end
		end
	end

	for _, unit in pairs(GetUnitList(UNIT_LIST_ENEMIES))
	do
		if J.IsValid(unit)
		and GetUnitToLocationDistance(unit, vLoc) <= nRadius
		then
			local unitName = unit:GetUnitName()
			if unit:IsCreep() then
				nUnitCount = nUnitCount + 1
				if unit:IsAncientCreep()
				or unit:HasModifier('modifier_chen_holy_persuasion')
				or unit:HasModifier('modifier_dominated') then
					nUnitCount = nUnitCount + 1
				end
			elseif string.find(unit:GetUnitName(), 'spiderling') then nUnitCount = nUnitCount + 0.1
			elseif string.find(unit:GetUnitName(), 'eidolon') then nUnitCount = nUnitCount + 0.3
			elseif string.find(unitName, 'siege') and not string.find(unitName, 'upgraded') then
				nUnitCount = nUnitCount + 0.6
			elseif string.find(unitName, 'upgraded') then nUnitCount = nUnitCount + 1
			elseif string.find(unitName, 'warlock_golem') then
				if DotaTime() < 10 * 60 then nUnitCount = nUnitCount + 3
				elseif DotaTime() < 20 * 60 then nUnitCount = nUnitCount + 2.5
				elseif DotaTime() < 30 * 60 then nUnitCount = nUnitCount + 2
				else nUnitCount = nUnitCount + 1.5 end
			elseif string.find(unitName, 'lone_druid_bear') then nUnitCount = nUnitCount + 3
			elseif string.find(unitName, 'shadow_shaman_ward') then nUnitCount = nUnitCount + 2
			elseif string.find(unit:GetUnitName(), "tombstone") then nUnitCount = nUnitCount + 2
			elseif J.IsSuspiciousIllusion(unit) then
				if unit:HasModifier('modifier_arc_warden_tempest_double')
					or string.find(unit:GetUnitName(), 'chaos_knight')
					or string.find(unit:GetUnitName(), 'naga_siren') then nUnitCount = nUnitCount + 2 end
			elseif not (string.find(unitName, 'observer_wards') or string.find(unitName, 'sentry_wards')) then nUnitCount = nUnitCount + 1 end
			if J.GetLocationToLocationDistance(ancientLoc, vLoc) < 1600 then nUnitCount = nUnitCount + 2 end
		end
	end

	-- J.Utils.SetCachedVars('GetEnemiesAroundLoc'..cacheKey, nUnitCount)
	return nUnitCount
end

local inventorySeen = {}
local inventorySampleTime = -math.huge
local alliedInventory, enemyInventory = 0, 0

local function GetInventoryValue(hero)
	local value = 0
	for slot = 0, 8 do
		local item = hero:GetItemInSlot(slot)
		if item ~= nil then value = value + GetItemCost(item:GetName()) end
	end
	return value
end

-- Only the current inventory of a visible real hero, never fog net worth.
function J.GetVisibleFightInventoryValue(hero)
	if not J.IsValidHero(hero) or J.IsSuspiciousIllusion(hero) then return 0 end
	return GetInventoryValue(hero)
end

function J.GetInventoryNetworth()
	local now = DotaTime()
	if now < inventorySampleTime then inventorySeen, inventorySampleTime = {}, -math.huge end
	if now - inventorySampleTime < 2 then return alliedInventory, enemyInventory end
	inventorySampleTime, alliedInventory, enemyInventory = now, 0, 0
	local allies = GetTeamPlayers(GetTeam())
	local opponents = GetTeamPlayers(GetOpposingTeam())
	for slot = 1, #allies do
		local hero = GetTeamMember(slot)
		if hero ~= nil then alliedInventory = alliedInventory + GetInventoryValue(hero) end
	end
	for _, enemy in ipairs(GetUnitList(UNIT_LIST_ENEMY_HEROES)) do
		if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy)
			and not enemy:HasModifier('modifier_arc_warden_tempest_double')
			and not string.find(enemy:GetUnitName(), 'lone_druid_bear') and not J.IsMeepoClone(enemy) then
			inventorySeen[enemy:GetPlayerID()] = {time = now, value = GetInventoryValue(enemy)}
		end
	end
	local samples = 0
	for _, id in ipairs(opponents) do
		local entry = inventorySeen[id]
		if entry ~= nil and now - entry.time <= 100 then
			samples = samples + 1
			enemyInventory = enemyInventory + entry.value
		end
	end
	-- Incomplete scouting can rule out a lead, but cannot establish one.
	if samples < #opponents or samples == 0 then
		enemyInventory = math.max(enemyInventory, alliedInventory)
	end
	return alliedInventory, enemyInventory
end

function J.FindEnemyUnit(name)
	for _, unit in pairs(GetUnitList(UNIT_LIST_ENEMIES))
	do
		if J.IsValid(unit)
		then
			if string.find(unit:GetUnitName(), name) then
				return unit
			end
		end
	end
	return nil
end

function J.GetHumanPing()
	local ping = nil

	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember(i)
		if  member ~= nil
		and not member:IsBot()
		then
			return member, member:GetMostRecentPing()
		end
	end

	return nil, ping
end

-- Chat a random message from a localization key, once per cooldown per bot
-- ARDM stale hero detection. Call from any Think function to check if the
-- script's cached bot handle is outdated.
-- Returns: isStale (bool), freshBot (handle), freshName (string)
--   isStale=true  → this script is for a dead hero from a past ARDM life, do nothing
--   isStale=false → safe to proceed; freshBot/freshName are the current hero
-- Uses two signals: name comparison (definitive) and IsHeroAlive (covers edge cases
-- where GetBot() hasn't updated yet but the player already has a new alive hero).
function J.IsStaleARDMHero(cachedBot, cachedName)
	if GetGameMode() ~= GAMEMODE_ARDM then
		return false, cachedBot, cachedName
	end

	local freshBot = GetBot()
	local freshName = freshBot:GetUnitName()
	local nPlayerID = cachedBot:GetPlayerID()

	-- Check 1: name differs AND handle differs → definitely stale
	if freshName ~= cachedName and freshBot ~= cachedBot then
		return true, freshBot, freshName
	end

	-- Check 2: this bot is dead but the player's current hero is alive
	-- (covers case where GetBot() hasn't switched yet but the player has a new hero)
	if nPlayerID >= 0 and IsHeroAlive(nPlayerID) and not cachedBot:IsAlive() then
		-- Only stale if the names also differ (if same name, might just be respawning)
		if freshName ~= cachedName then
			return true, freshBot, freshName
		end
	end

	return false, freshBot, freshName
end

-- Push safety and defend priority logic moved to TS sources:
-- aba_push.ts (GetPushDesireHelper) and aba_defend.ts (GetDefendDesireHelper)

function J.ModeAnnounce(bot, locKey, cooldown)
	local Localization = require( GetScriptDirectory()..'/FunLib/localization' )
	if bot.lastModeChatTime == nil then bot.lastModeChatTime = {} end
	local lastTime = bot.lastModeChatTime[locKey] or -999
	if GameTime() - lastTime < (cooldown or 30) then return end
	bot.lastModeChatTime[locKey] = GameTime()
	local msgs = Localization.Get(locKey)
	if msgs ~= nil and #msgs > 0 then
		bot:ActionImmediate_Chat(msgs[RandomInt(1, #msgs)], false)
	end
end

function J.HasAbility(bot, abilityName)
	for i = 0, 23
	do
		local ability = bot:GetAbilityInSlot(i)
		if  ability ~= nil
		and ability:GetName() == abilityName
		then
			return true, ability
		end
	end

	return false, nil
end

function J.IsHumanInLoc(vLoc, nRadius)
	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember(i)

		if  member ~= nil and member:IsAlive() and not member:IsBot() and not member:IsIllusion()
		and not member:HasModifier("modifier_arc_warden_tempest_double")
		and not J.IsMeepoClone(member)
		and GetUnitToLocationDistance(member, vLoc) <= nRadius
		then
			return true
		end
	end

	return false
end

function J.GetCurrentRoshanLocation()
	-- 7.41: Roshan's pit preference switched (day/night swap)
	if J.CheckTimeOfDay() == 'day'
	then
		return J.Utils.DireRoshanLoc
	else
		return J.Utils.RadiantRoshanLoc
	end
end

function J.GetTormentorLocation(team)
	-- 7.41: Tormentor's spawn preference switched (day/night swap)
	if J.CheckTimeOfDay() == 'day'
	then
		return RadiantTormentorLoc
	else
		return DireTormentorLoc
	end
end

function J.GetTormentorWaitingLocation(team)
	-- 7.41: Tormentor's spawn preference switched (day/night swap)
	local timeOfday = J.CheckTimeOfDay()
	if timeOfday == 'day' then
		return Vector(6792, -6815, 256)
	else
		return Vector(-7041, 6796, 256)
	end
end

local function HasTeamDetectionArea(field, location, margin, time)
    for teamSlot in ipairs(GetTeamPlayers(GetTeam())) do
        local member = GetTeamMember(teamSlot)
        local area = member and member[field]
        if area and time < area.untilTime and J.GetDistance(area.location, location) + margin <= area.radius then
            return true
        end
    end
    return false
end

function J.HasDustCoverage(location, margin, minRemaining)
    return HasTeamDetectionArea('ohaDustCoverage', location, margin or 0, DotaTime() + (minRemaining or 0))
end

function J.HasSentryCoverage(location, margin)
    return J.Site.IsLocationHaveTrueSight(location, margin)
        or HasTeamDetectionArea('ohaSentryOrder', location, margin or 0, DotaTime())
end

function J.RecordSentryOrder(bot, location)
    -- Cover the interval between issuing a placement and seeing a live ward.
    bot.ohaSentryOrder = {location = location, radius = J.Site.SentryTrueSightRange, untilTime = DotaTime() + 0.65}
end

function J.HasLocalTrueSight(location, margin)
    if J.HasSentryCoverage(location, margin) then return true end
    for _, ally in ipairs(J.GetAlliesNearLoc(location, 1300)) do
        local slot = ally:FindItemSlot('item_gem')
        if slot >= 0 and slot <= 5 and not ally:IsIllusion() then
            local gem = ally:GetItemInSlot(slot)
            if gem and not gem:IsNull() and GetUnitToLocationDistance(ally, location) + (margin or 0) <= gem:GetSpecialValueInt('radius') then
                return true
            end
        end
    end
    return false
end

function J.IsClosestToDustLocation(bot, loc)
    local closest = nil
    local closestDist = 100000
    for teamSlot in ipairs(GetTeamPlayers(GetTeam())) do
        local member = GetTeamMember(teamSlot)
        if J.IsValidHero(member) and not J.IsSuspiciousIllusion(member) then
            local dustSlot = member:FindItemSlot('item_dust')
            if dustSlot >= 0 and member:GetItemSlotType(dustSlot) == ITEM_SLOT_TYPE_MAIN then
                local dust = member:GetItemInSlot(dustSlot)
                local distance = GetUnitToLocationDistance(member, loc)
                if dust ~= nil and dust:IsFullyCastable() and distance < closestDist then
                    closest = member
                    closestDist = distance
                end
            end
        end
    end
    if closest ~= nil then return closest == bot end
end


function J.GetXUnitsTowardsLocation2(iLoc, tLoc, nUnits)
    local dir = (tLoc - iLoc):Normalized()
    return iLoc + dir * nUnits
end

function J.HasItemConcealment(unit)
	return unit:HasModifier('modifier_item_invisibility_edge_windwalk')
		or unit:HasModifier('modifier_item_silver_edge_windwalk')
		or unit:HasModifier('modifier_item_glimmer_cape_fade')
		or unit:HasModifier('modifier_item_shadow_amulet_fade')
		or unit:HasModifier('modifier_item_trickster_cloak_invis')
end

function J.IsUnitWillGoInvisible(unit, ignoreSandStorm)
	return (not ignoreSandStorm and unit:HasModifier('modifier_sandking_sand_storm'))
		or unit:HasModifier('modifier_bounty_hunter_wind_walk')
		or unit:HasModifier('modifier_clinkz_wind_walk')
		or unit:HasModifier('modifier_weaver_shukuchi')
		or (unit:HasModifier('modifier_oracle_false_promise') and unit:HasModifier('modifier_oracle_false_promise_invis'))
		or (unit:HasModifier('modifier_windrunner_windrun') and unit:HasModifier('modifier_windrunner_windrun_invis'))
		or J.HasItemConcealment(unit)
end

function J.HasInvisCounterBuff(unit)
	if unit:HasModifier('modifier_item_dustofappearance')
	or unit:HasModifier('modifier_bounty_hunter_track')
	or unit:HasModifier('modifier_bloodseeker_thirst_vision')
	or unit:HasModifier('modifier_slardar_amplify_damage')
	or unit:HasModifier('modifier_sniper_assassinate')
	or unit:HasModifier( 'modifier_faceless_void_chronosphere_freeze' )
	then
		return true
	end

	return false
end

function J.GetUnderlordPortal()
	local portal = {}

	for _, u in pairs(GetUnitList(UNIT_LIST_ALLIES))
	do
		if u:GetUnitName() == 'npc_dota_unit_underlord_portal'
		then
			if #portal == 1
			and portal[1] ~= u
			then
				table.insert(portal, u)
			end

			if #portal == 2
			then
				break
			end

			table.insert(portal, u)
		end
	end

	if #portal == 2
	then
		return portal
	end

	return nil
end

function J.GetTotalEstimatedDamageToTarget(nUnits, target)
	local dmg = 0

	for _, unit in pairs(nUnits)
	do
		if J.IsValid(unit)
		and J.IsValid(target)
		and not J.IsSuspiciousIllusion(unit)
		then
			dmg = dmg + unit:GetEstimatedDamageToTarget(true, target, 5, DAMAGE_TYPE_ALL)
		end
	end

	return dmg
end

function J.GetAliveCoreCount(nEnemy)
	-- local cacheKey = 'GetAliveCoreCount'..tostring(GetTeam())
	-- local cache = J.Utils.GetCachedVars(cacheKey, 0.5)
	-- if cache ~= nil then return cache end

	local count = 0
	if nEnemy then
		for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ENEMY_HEROES))
		do
			if J.IsValidHero(enemyHero) and not J.IsSuspiciousIllusion(enemyHero) and J.IsCore(enemyHero) then
				count = count + 1
			end
		end
	else
		for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
		do
			if J.IsValidHero(allyHero) and not allyHero:IsIllusion() and J.IsCore(allyHero) then
				count = count + 1
			end
		end
	end

	-- J.Utils.SetCachedVars(cacheKey, count)
	return count
end

function J.GetEnemyCountInLane(lane)
	local count = 0
	local laneFront = GetLaneFrontLocation(GetTeam(), lane, 0)
	for _, id in pairs( GetTeamPlayers( GetOpposingTeam()))
	do
		if IsHeroAlive(id)
		then
			local info = GetHeroLastSeenInfo(id)

			if info ~= nil
			then
				local dInfo = info[1]

				if dInfo ~= nil
				and J.GetDistance(laneFront, dInfo.location) < 1600
				and dInfo.time_since_seen < 6
				then
					count = count + 1
				end
			end
		end
	end

	return count
end

function J.GetAllyCountInLane(lane, nRadius) -- not including self.
	local count = 0
	local laneFront = GetLaneFrontLocation(GetTeam(), lane, 0)
	for i, id in pairs(GetTeamPlayers(GetTeam()))
	do
		local member = GetTeamMember(i)
		if member:IsAlive()
		and member ~= GetBot()
		and not member:IsIllusion()
		and GetUnitToLocationDistance(member, laneFront) <= nRadius
		then
			count = count + 1
		end
	end
	return count
end

function J.GetManaAfter(manaCost)
	local bot = GetBot()
	return (bot:GetMana() - manaCost) / bot:GetMaxMana()
end
function J.GetHealthAfter(hpCost)
	local bot = GetBot()
	return (bot:GetHealth() - hpCost) / bot:GetMaxHealth()
end

function J.GetCreepListAroundTargetCanKill(target, nRadius, damage, bEnemy, bNeutral, bLaneCreep)
	if nRadius > 1600 then nRadius = 1600 end
	local creepList = {}

	if target ~= nil
	then
		if bNeutral
		then
			for _, creep in pairs(GetUnitList(UNIT_LIST_NEUTRAL_CREEPS))
			do
				if J.IsValid(creep)
				and target ~= creep
				and GetUnitToUnitDistance(target, creep) <= nRadius
				and creep:GetHealth() <= damage
				then
					table.insert(creepList, creep)
				end
			end
		elseif bLaneCreep
		then
			local unitList = GetUnitList(UNIT_LIST_ALLIED_CREEPS)
			if bEnemy
			then
				unitList = GetUnitList(UNIT_LIST_ENEMY_CREEPS)
			end

			for _, creep in pairs(unitList)
			do
				if J.IsValid(creep)
				and target ~= creep
				and GetUnitToUnitDistance(target, creep) <= nRadius
				and creep:GetHealth() <= damage
				then
					table.insert(creepList, creep)
				end
			end
		else
			local unitList = GetUnitList(UNIT_LIST_ALLIED_CREEPS)
			if bEnemy
			then
				unitList = GetUnitList(UNIT_LIST_ENEMY_CREEPS)
			end

			for _, creep in pairs(unitList)
			do
				if J.IsValid(creep)
				and target ~= creep
				and GetUnitToUnitDistance(target, creep) <= nRadius
				and creep:GetHealth() <= damage
				then
					table.insert(creepList, creep)
				end
			end

			unitList = GetUnitList(UNIT_LIST_NEUTRAL_CREEPS)
			for _, creep in pairs(unitList)
			do
				if J.IsValid(creep)
				and target ~= creep
				and GetUnitToUnitDistance(target, creep) <= nRadius
				and creep:GetHealth() <= damage
				then
					table.insert(creepList, creep)
				end
			end			
		end
	end

	return creepList
end

function J.GetPushTPLocation(nLane)
	local laneFront = GetLaneFrontLocation(GetTeam(), nLane, 0)
	local bestTpLoc = J.GetNearbyLocationToTp(laneFront)
	if J.GetLocationToLocationDistance(laneFront, bestTpLoc) < 1600
	then
		return bestTpLoc
	end
end

function J.GetDefendTPLocation(nLane)
	return GetLaneFrontLocation(GetTeam(), nLane, -950)
end

function J.GetRandomLocationWithinDist(sLoc, minDist, maxDist)
	local randomAngle = math.random() * 2 * math.pi
	local randomDist = math.random(minDist, maxDist)
	local newX = sLoc.x + randomDist * math.cos(randomAngle)
	local newY = sLoc.y + randomDist * math.sin(randomAngle)
	return Vector(newX, newY, sLoc.z)
end

function J.GetHeroCountAttackingTarget(nUnits, target)
	local count = 0
	for _, hero in pairs(nUnits)
	do
		if J.IsValidHero(hero)
		and J.IsInRange(hero, target, 1600)
		and J.IsGoingOnSomeone(hero)
		and hero:CanBeSeen()
		and (hero:GetAttackTarget() == target or hero:GetTarget() == target)
		and not J.IsSuspiciousIllusion(hero)
		then
			count = count + 1
		end
	end

	return count
end

function J.GetHighestRightClickDamageHero(nUnits)
	local target = nil
	local dmg = 0
	for _, hero in pairs(nUnits)
	do
		if J.IsValidHero(hero)
		and not J.IsMeepoClone(hero)
		and not J.IsSuspiciousIllusion(hero)
		then
			if dmg < hero:GetAttackDamage()
			then
				dmg = hero:GetAttackDamage()
				target = hero
			end
		end
	end

	return target
end

function J.IsBigCamp(nUnits)
	for _, creep in pairs(nUnits)
	do
		if J.IsValid(creep)
		then
			if creep:GetUnitName() == 'npc_dota_neutral_satyr_hellcaller'
			or creep:GetUnitName() == 'npc_dota_neutral_polar_furbolg_ursa_warrior'
			or creep:GetUnitName() == 'npc_dota_neutral_dark_troll_warlord'
			or creep:GetUnitName() == 'npc_dota_neutral_centaur_khan'
			or creep:GetUnitName() == 'npc_dota_neutral_enraged_wildkin'
			or creep:GetUnitName() == 'npc_dota_neutral_warpine_raider'
			then
				return true
			end
		end
	end
end

function J.GetETAWithAcceleration(dist, speed, accel)
	return (math.sqrt(2 * accel * dist + speed * speed) - speed) / accel
end

function J.GetTechiesMines()
	local nMinesList = {}

	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIES))
    do
		if unit ~= nil
        and unit:GetUnitName() == 'npc_dota_techies_land_mine'
        then
			table.insert(nMinesList, unit)
		end
	end

	return nMinesList
end

function J.GetTechiesMinesInLoc(loc, nRadius)
	local nMinesList = {}

	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIES))
    do
		if unit ~= nil
        and unit:GetUnitName() == 'npc_dota_techies_land_mine'
		and GetUnitToLocationDistance(unit, loc) <= nRadius
        then
			table.insert(nMinesList, unit)
		end
	end

	return nMinesList
end

function J.CheckBitfieldFlag(bitfield, flag)
    return ((bitfield / flag) % 2) >= 1
end

function J.GetPowerCogsCountInLoc(loc, nRadius)
	local count = 0
	for _, unit in pairs(GetUnitList(UNIT_LIST_ALL))
	do
		if J.IsValid(unit)
		and string.find(unit:GetUnitName(), 'rattletrap_cog')
		and GetUnitToLocationDistance(unit, loc) <= nRadius
		then
			count = count + 1
		end
	end

	return count
end

function J.HasPowerTreads(bot)
	if J.HasItem(bot, 'item_power_treads')
	or J.HasItem(bot, 'item_power_treads_agi')
	or J.HasItem(bot, 'item_power_treads_int')
	or J.HasItem(bot, 'item_power_treads_str')
	then
		return true
	end

	return false
end

function J.GetLanePartner(bot, includeDead)
	if bot:GetAssignedLane() == LANE_MID
	then
		return nil
	end

	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember(i)

		if member ~= nil
		and (includeDead or member:IsAlive())
		and member ~= bot
		and member:GetAssignedLane() == bot:GetAssignedLane()
		then
			return member
		end
	end

	return nil
end

function J.CanLeaveLane(bot)
	if not J.IsInLaningPhase(bot) then return true end
	local lane, team = bot:GetAssignedLane(), bot:GetTeam()
	if lane ~= LANE_TOP and lane ~= LANE_MID and lane ~= LANE_BOT then return false end
	if J.GetLaningHoldTower(bot) ~= nil then return false end
	local towerId = lane == LANE_TOP and TOWER_TOP_1 or (lane == LANE_MID and TOWER_MID_1 or TOWER_BOT_1)
	local tower = GetTower(team, towerId)
	if not J.IsValidBuilding(tower) then return false end
	local front = GetLaneFrontLocation(team, lane, 0)
	if #J.GetLastSeenEnemiesNearLoc(tower:GetLocation(), 1300) >= 2 then return false end
	for slot = 1, #GetTeamPlayers(team) do
		local ally = GetTeamMember(slot)
		if ally ~= nil and ally ~= bot and ally:IsAlive() and J.IsCore(ally) and ally:GetAssignedLane() == lane then
			if J.GetHP(ally) < 0.58 or J.IsRetreating(ally) or ally:WasRecentlyDamagedByAnyHero(3) then return false end
			local exposed = #J.GetLastSeenEnemiesNearLoc(front, 1500) > 0
				or #J.GetEnemiesNearLoc(ally:GetLocation(), 1100) > 0
			if exposed and not J.IsInRange(ally, tower, 1050) then return false end
		end
	end
	return true
end

function J.CanFollowLaneFight(ally, target)
	return J.IsValidHero(target) and J.IsValidHero(ally) and not ally:IsIllusion()
		and J.GetHP(ally) >= 0.55 and not J.IsRetreating(ally) and not J.IsDisabled(ally)
		and not ally:IsDisarmed() and not ally:IsChanneling() and not ally:HasModifier('modifier_teleporting')
		and J.IsInRange(ally, target, ally:GetAttackRange() + math.min(160, ally:GetCurrentMovementSpeed() * 0.5))
end

function J.HasLaneFightFollowUp(bot, target)
	if not J.IsValidHero(target) then return false end
	for _, ally in ipairs(J.GetAlliesNearLoc(target:GetLocation(), 1500)) do
		if ally ~= bot and J.CanFollowLaneFight(ally, target) then return true end
	end
	return false
end

function J.IsEnemyHero(hero)
	if hero ~= nil
	and hero:GetTeam() ~= GetBot():GetTeam()
	then
		return true
	else
		return false
	end
end

-- Adds an avoidance zone for use with GeneratePath(). Takes a Vector with x and y as a 2D location, and z as as radius. Returns a handle to the avoidance zone.
-- location as Vector(-7174.0, -6671.0, 10.0)
function J.AddAvoidanceZone(locationR, durationSec)
	local zone = AddAvoidanceZone(locationR, durationSec)
	-- J.Utils.StartCoroutine(function()
	-- 	local endTime = DotaTime() + durationSec
	-- 	while endTime >= DotaTime() do
	-- 		print('AddAvoidanceZone...'..' endtime='..endTime..', time='..DotaTime())
	-- 		coroutine.yield()
	-- 	end
	-- 	return RemoveAvoidanceZone(zone)
	-- end)
	return zone
end

function J.GetClosestAllyHero(bot)
	local closestHeroDistance = 999999
	local closestHero = nil
	for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if J.IsValidHero(allyHero)
		and J.IsNotSelf(bot, allyHero)
		then
			local diffDistance = J.GetLocationToLocationDistance(allyHero:GetLocation(), bot:GetLocation())
			if diffDistance < closestHeroDistance then
				closestHero = allyHero
				closestHeroDistance = diffDistance
			end
		end
	end
	return closestHero, closestHeroDistance
end

-- check if a table contains a value
function J.hasValue(tab, val)
    for index, value in ipairs(tab) do
        if value == val then
            return true
        end
    end

    return false
end

-- Sample net movement across decisions. A hero can keep receiving move orders
-- and still be walking back and forth at the edge of the same objective.
function J.CheckBotIdleState()
	local bot = GetBot()
	local now = DotaTime()
	if now < 40 or not bot:IsAlive()
		or bot:DistanceFromFountain() < 850 and (J.GetHP(bot) < 0.88 or J.GetMP(bot) < 0.65)
		or J.CanNotUseAction(bot, false, true) or bot:IsRooted() or J.IsTryingtoUseAbility(bot)
		or bot:HasModifier('modifier_teleporting') then
		bot.ohaMoveSample, bot.ohaIdleRecoveryUntil, bot.ohaIdleReplanUntil = nil, nil, nil
		bot.ohaWatcherRecoveryUntil = nil
		return false
	end
	local mode = bot:GetActiveMode()
	-- DOTA_BOT_MODE_WATCHER in the client protocol. Older Lua bindings omit it.
	local watching = mode == (BOT_MODE_WATCHER or 28)
	local sample = bot.ohaMoveSample
	local elapsed = sample and now - sample.sampled
	if elapsed and elapsed >= 0 and elapsed < 0.50 then
		return (bot.ohaIdleRecoveryUntil or 0) > now
	end
	local attack = bot:GetLastAttackTime()
	local location = bot:GetLocation()
	local reset = sample == nil or elapsed < 0 or elapsed > 2 or sample.attack ~= attack
		or watching and sample.mode ~= mode
	if reset or GetUnitToLocationDistance(bot, sample.location) > 180 then
		if reset then bot.ohaIdleRecoveryUntil, bot.ohaWatcherRecoveryUntil = nil, nil end
		bot.ohaMoveSample = {location=location, time=now, sampled=now, attack=attack, mode=mode}
		bot.ohaIdleReplanUntil = nil
		return (bot.ohaIdleRecoveryUntil or 0) > now
	end
	sample.sampled = now
	if now - sample.time < (watching and 4 or 6) then return false end
	-- Let the current mode replace a stale queue even on defense or near enemies.
	-- Only a quiet, unassigned hero may switch to local farm or a rally point.
	bot.ohaIdleReplanUntil = now + 1.25
	if now - sample.time < (watching and 4 or 9) or (bot.ohaIdleRecoveryUntil or 0) > now then
		return (bot.ohaIdleRecoveryUntil or 0) > now
	end
	if J.IsDefending(bot) or J.IsDoingRoshan(bot) or J.IsDoingTormentor(bot)
		or (bot.ohaOuterTowerHoldUntil or 0) > now or bot:WasRecentlyDamagedByAnyHero(3)
		or J.IsRetreating(bot) and (J.GetHP(bot) < 0.80 or J.GetMP(bot) < 0.40)
		or #J.GetEnemiesNearLoc(location, 1400) > 0 or #J.GetLastSeenEnemiesNearLoc(location, 1200) > 0 then return false end
	if J.HasQueuedAction(bot) and not bot:GetAttackTarget() then bot:Action_ClearActions(false) end
	bot.ohaIdleRecoveryUntil = now + 15
	if watching then bot.ohaWatcherRecoveryUntil = now + 8 end
	bot.ohaIdleRecoveryOrigin = location
	if J.Customize and J.Customize.TraceLaneDecisions then
		local name = watching and 'BOT_MODE_WATCHER' or nil
		for key, value in pairs(_G) do
			if type(key) == 'string' and key:find('^BOT_MODE_') and not key:find('^BOT_MODE_DESIRE_') and value == mode then
				name = key
				break
			end
		end
		print('[OHA idle]', now, bot:GetUnitName(), 'mode', name or mode, 'action', bot:GetCurrentActionType(),
			'stationary', now - sample.time, 'desire', bot:GetActiveModeDesire(), 'lastAttack', attack)
	end
	return true
end

function J.GetStalledWatcherExit(bot, destination)
	local now = DotaTime()
	if (bot.ohaWatcherRecoveryUntil or 0) <= now or J.CanNotUseAction(bot, false, true)
		or bot:IsRooted() or J.IsTryingtoUseAbility(bot) or bot:HasModifier('modifier_teleporting')
		or bot:WasRecentlyDamagedByAnyHero(3) or (bot.ohaOuterTowerHoldUntil or 0) > now then return nil end
	if not destination and bot:GetActiveMode() ~= (BOT_MODE_WATCHER or 28) then return nil end
	local origin = bot:GetLocation()
	if #J.GetEnemiesNearLoc(origin, 1400) > 0 or #J.GetLastSeenEnemiesNearLoc(origin, 1300) > 0 then return nil end
	local function SafeExit(point)
		local distance = J.GetLocationToLocationDistance(origin, point)
		if distance < 120 or distance > 850 then return false end
		local middle = J.VectorTowards(origin, point, distance * 0.5)
		return IsLocationVisible(point) and IsLocationVisible(middle) and IsLocationPassable(point) and IsLocationPassable(middle)
			and #J.GetEnemiesNearLoc(point, 1300) == 0 and #J.GetLastSeenEnemiesNearLoc(point, 1250) == 0
			and J.CanTakePostFightTrip(bot, point, false, true)
	end
	if destination then return SafeExit(destination) and destination or nil end

	local ally = J.GetClosestAlly(bot, 3000, true)
	local anchor = ally and J.GetHP(bot) >= 0.55 and GetUnitToUnitDistance(bot, ally) > 700 and ally:GetActiveMode() ~= (BOT_MODE_WATCHER or 28)
		and ally:GetLocation() or J.GetTeamFountain()
	local distance = J.GetLocationToLocationDistance(origin, anchor)
	if distance < 450 then return nil end
	local ahead = J.VectorTowards(origin, anchor, math.min(distance, 700))
	local dx, dy = ahead.x - origin.x, ahead.y - origin.y
	for _, side in ipairs({0, 1, -1}) do
		local point = side == 0 and ahead or Vector(origin.x + dx * 0.82 - dy * side * 0.58,
			origin.y + dy * 0.82 + dx * side * 0.58, origin.z)
		if SafeExit(point) then return point end
	end
end

function J.AreTreesBetween(bot, loc, r)
	local nTrees = bot:GetNearbyTrees(GetUnitToLocationDistance(bot, loc))

	for _, tree in pairs(nTrees)
	do
		local x = GetTreeLocation(tree)
		local y = bot:GetLocation()
		local z = loc

		if x ~= y
		then
			local a = 1
			local b = 1
			local c = 0

			if x.x - y.x == 0
			then
				b = 0
				c = -x.x
			else
				a = -(x.y - y.y) / (x.x - y.x)
				c = -(x.y + x.x * a)
			end

			local d = math.abs((a*z.x+b*z.y+c)/math.sqrt(a*a+b*b))

			if d <= r
			and GetUnitToLocationDistance(bot,loc) > J.GetDistance(x, loc) + 50
			then
				return true
			end
		end
	end

	return false
end

function J.VectorTowards(vStart, vTowards, nDistance)
	local vDirection = (vTowards - vStart):Normalized()
	return vStart + (vDirection * nDistance)
end

function J.VectorAway(vStart, vTowards, nDistance)
	local vDirection = (vStart - vTowards):Normalized()
	return vStart + (vDirection * nDistance)
end

function J.GetAngleFromDotProduct(dot)
	return math.deg(math.acos(dot))
end

function J.IsUnitTargetedByTower(hUnit, bTeam)
	local nUnitType = (bTeam and UNIT_LIST_ALLIED_BUILDINGS) or UNIT_LIST_ENEMY_BUILDINGS
	local nUnitList = GetUnitList(nUnitType)

	for _, building in pairs(nUnitList) do
		if J.IsValidBuilding(building) and building:GetAttackTarget() == hUnit then
			return true
		end
	end

	return false
end

function J.GetBestRetreatTree(bot, nCastRange)
	local nTrees = bot:GetNearbyTrees(nCastRange)
	local dest = J.VectorTowards(bot:GetLocation(), J.GetTeamFountain(), 1000)

	local bestRetreatTree = nil
	local maxDist = 0

	for _, tree in pairs(nTrees)
	do
		local nTreeLoc = GetTreeLocation(tree)

		if not J.AreTreesBetween(bot, nTreeLoc, 100)
		and GetUnitToLocationDistance(bot, nTreeLoc) > maxDist
		and GetUnitToLocationDistance(bot, nTreeLoc) < nCastRange
		and J.GetDistance(nTreeLoc, dest) < 880
		then
			maxDist = GetUnitToLocationDistance(bot, nTreeLoc)
			bestRetreatTree = loc
		end
	end

	if bestRetreatTree ~= nil
	and maxDist > bot:GetAttackRange()
	then
		return bestRetreatTree
	end

	return bestRetreatTree
end

function J.GetBestTree(bot, enemyLoc, enemy, nCastRange, hitRadios)
	local bestTree = nil
	local nTrees = bot:GetNearbyTrees(nCastRange)
	local dist = 10000

	for _, tree in pairs(nTrees)
	do
		local x = GetTreeLocation(tree)
		local y = bot:GetLocation()
		local z = enemyLoc

		if x ~= y
		then
			local a = 1
			local b = 1
			local c = 0

			if x.x - y.x == 0
			then
				b = 0
				c = -x.x
			else
				a=-(x.y-y.y)/(x.x-y.x);
				c=-(x.y + x.x*a);
			end

			local d = math.abs((a * z.x + b * z.y + c) / math.sqrt(a * a + b * b))
			if d <= hitRadios
			and dist > GetUnitToLocationDistance(enemy, x)
			and (GetUnitToLocationDistance(enemy, x) <= GetUnitToLocationDistance(bot, x))
			then
				bestTree = tree
				dist = GetUnitToLocationDistance(enemy, x)
			end
		end
	end

	return bestTree
end

function J.GetUltLoc(bot, target, nManaCost, nCastRange, s)
	local v = target:GetVelocity()
	local sv = J.GetDistance(Vector(0,0), v)
	if sv > 800
	then
		v = (v / sv) * target:GetCurrentMovementSpeed()
	end

	local x= bot:GetLocation()
	local y= target:GetLocation()

	local a = v.x * v.x + v.y * v.y - s * s
	local b = -2 * (v.x * (x.x - y.x) + v.y * (x.y - y.y))
	local c = (x.x - y.x) * (x.x - y.x) + (x.y - y.y) * (x.y - y.y)

	local t = math.max((-b + math.sqrt(b * b - 4 * a * c)) / (2 * a), (-b - math.sqrt(b * b - 4 * a * c)) / (2 * a))
	local dest = (t + 0.35) * v + y

	if GetUnitToLocationDistance(bot, dest) > nCastRange
	or bot:GetMana() < 100 + nManaCost
	then
		return nil
	end

	if target:GetMovementDirectionStability() < 0.4
	or not bot:IsFacingLocation(target:GetLocation(), 60)
	then
		dest = J.VectorTowards(y, J.GetEnemyFountain(), 180)
	end

	if J.IsDisabled(target)
	then
		dest = target:GetLocation()
	end

	return dest
end


return J
