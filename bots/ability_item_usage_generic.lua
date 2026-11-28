local X = {}
local bot = GetBot()
if bot == nil then return end
local botName = bot:GetUnitName()
if not bot:IsHero() or not string.find(botName, "hero") or bot:IsIllusion()
	or bot:IsInvulnerable() and DotaTime() >= 0 and not bot:HasModifier('modifier_fountain_invulnerability') then return end
if not bot.frameProcessTime then bot.frameProcessTime = 0.1 end

local team = GetTeam()
local bDebugMode = ( 10 == 10 )

local J = require( GetScriptDirectory()..'/FunLib/jmz_func' )
local OpeningRune = require(GetScriptDirectory() .. '/FunLib/opening_rune')
local Banish = require( GetScriptDirectory()..'/FunLib/oha_banish' )
local Utils = require( GetScriptDirectory()..'/FunLib/utils' )
local BotBuild = dofile( GetScriptDirectory().."/BotLib/"..string.gsub( botName, "npc_dota_", "" ) )
local Localization = require( GetScriptDirectory()..'/FunLib/localization' )
local Customize = require(GetScriptDirectory()..'/Customize/general')
Customize.ThinkLess = Customize.Enable and Customize.ThinkLess or 1
if GAMEMODE_TURBO == nil then GAMEMODE_TURBO = 23 end
if GAMEMODE_ARDM == nil then GAMEMODE_ARDM = 20 end

if BotBuild == nil then return end

local bDeafaultAbilityHero = BotBuild['bDeafaultAbility']
local bDeafaultItemHero = BotBuild['bDeafaultItem']

local function CopyLevelPlan(plan)
	local copy, indices = {}, {}
	for index, name in pairs(plan or {}) do
		if type(index) == 'number' and type(name) == 'string' then indices[#indices + 1] = index end
	end
	table.sort(indices)
	for _, index in ipairs(indices) do copy[#copy + 1] = plan[index] end
	return copy
end

local sAbilityLevelUpList = CopyLevelPlan(BotBuild['sSkillList'])
local pendingLevelUp
local config = J.GetUserHeroConfig(bot)
local customLevelPlan = config ~= nil and (config.AbilityUpgrade ~= nil or config.Talent ~= nil)

local RadiantFountain = Vector(-6619, -6336, 384)
local DireFountain = Vector(6928, 6372, 392)

local bNeedARDMReload = false
local nLastKnownPosition = nil  -- tracks bot's position for !pos swap detection

local function FindLevelAbility(name)
	local ability, paired
	if botName == 'npc_dota_hero_kez' then
		ability, paired = J.Skill.GetKezLevelUpAbility(bot, name)
	else
		ability = bot:GetAbilityByName(name)
	end
	if ability ~= nil and not ability:IsNull() then return ability, paired end
	return nil, paired
end

local function BuildRemainingLevelPlan(plan)
	local remaining, learned = {}, {}
	for _, name in ipairs(CopyLevelPlan(plan)) do
		if learned[name] == nil then
			local ability = FindLevelAbility(name)
			learned[name] = ability ~= nil and ability:GetLevel() or 0
		end
		if learned[name] > 0 then
			learned[name] = learned[name] - 1
		else
			remaining[#remaining + 1] = name
		end
	end
	return remaining
end

local function IsLegalLevelUp(ability, heroLevel)
	return not ability:IsHidden() and ability:GetLevel() < ability:GetMaxLevel()
		and heroLevel >= ability:GetHeroLevelRequiredToUpgrade() and ability:CanAbilityBeUpgraded()
end

local function GetFallbackLevelPlan(heroLevel)
	local abilities = J.Utils.CombineTablesUnique(J.Skill.GetTalentList(bot), J.Skill.GetAbilityList(bot))
	local legal = {}
	for _, name in ipairs(abilities) do
		local ability = FindLevelAbility(name)
		if ability ~= nil and IsLegalLevelUp(ability, heroLevel) then legal[#legal + 1] = name end
	end
	return legal
end

-- Reload BotBuild for the current hero+role (shared by ARDM swap and !pos swap)
local function ReloadBotBuild(reason)
	local heroFile = string.gsub(botName, "npc_dota_", "")
	print("[Reload] "..reason.." for "..botName..", loading BotLib/"..heroFile)
	local ok, newBuild = pcall(dofile, GetScriptDirectory().."/BotLib/"..heroFile)
	if ok and newBuild ~= nil then
		BotBuild = newBuild
		bDeafaultAbilityHero = BotBuild['bDeafaultAbility']
		bDeafaultItemHero = BotBuild['bDeafaultItem']
		local user = J.GetUserHeroConfig(bot)
		customLevelPlan = user ~= nil and (user.AbilityUpgrade ~= nil or user.Talent ~= nil)
		sAbilityLevelUpList = BuildRemainingLevelPlan(newBuild['sSkillList'])
		pendingLevelUp = nil
	else
		print("[Reload] dofile FAILED for "..heroFile..": "..tostring(newBuild))
	end
end

-- ARDM: Refresh the bot handle and detect stale hero instances.
-- Returns true if this script instance should do NOTHING (stale hero from a past life).
local function RefreshBotHandle()
	local isStale, freshBot, freshName = J.IsStaleARDMHero(bot, botName)
	if isStale then
		print("[ARDM] Stale ability script: this="..botName..", current="..freshName)
		return true
	end

	-- Update handle/name if changed (hero swapped in place)
	if freshName ~= botName then
		print("[ARDM] Hero swap detected: "..botName.." -> "..freshName)
		bot = freshBot
		botName = freshName
		bNeedARDMReload = true
		pendingLevelUp = nil
		local user = J.GetUserHeroConfig(bot)
		customLevelPlan = user ~= nil and (user.AbilityUpgrade ~= nil or user.Talent ~= nil)
	elseif freshBot ~= bot then
		bot = freshBot
	end

	-- Reload BotLib when hero changed and is alive (abilities initialized)
	if bNeedARDMReload and bot:IsAlive() then
		bNeedARDMReload = false
		local heroFile = string.gsub(botName, "npc_dota_", "")
		print("[ARDM] Loading BotLib/"..heroFile..".lua for "..botName)
		local ok, newBuild = pcall(dofile, GetScriptDirectory().."/BotLib/"..heroFile)
		if not ok then
			print("[ARDM] dofile FAILED for "..heroFile..": "..tostring(newBuild))
		end
		if ok and newBuild ~= nil and newBuild['sSkillList'] ~= nil and #newBuild['sSkillList'] > 0 then
			BotBuild = newBuild
			bDeafaultAbilityHero = BotBuild['bDeafaultAbility']
			bDeafaultItemHero = BotBuild['bDeafaultItem']
			sAbilityLevelUpList = BuildRemainingLevelPlan(BotBuild['sSkillList'])
			print("[ARDM] Loaded BotLib for "..botName.." with "..#sAbilityLevelUpList.." skill entries, first: "..tostring(sAbilityLevelUpList[1]))
		else
			local abilityList = J.Skill.GetAbilityList(bot)
			local talentList = J.Skill.GetTalentList(bot)
			print("[ARDM] BotLib load failed or empty for "..botName..", abilities: "..#abilityList..", talents: "..#talentList)
			if #abilityList > 0 then
				BotBuild = nil
				bDeafaultAbilityHero = false
				bDeafaultItemHero = false
				sAbilityLevelUpList = GetFallbackLevelPlan(bot:GetLevel())
				print("[ARDM] Using generic build for "..botName.." with "..#sAbilityLevelUpList.." entries")
			else
				print("[ARDM] Abilities not ready for "..botName..", retrying next frame")
				bNeedARDMReload = true
			end
		end
	elseif bNeedARDMReload and not bot:IsAlive() then
		print("[ARDM] Waiting for "..botName.." to respawn")
	end

	return false
end

local missingLevelSkill, missingLevelSince

local function IsMissingDefaultLevelSkill(name, paired)
	if customLevelPlan or paired then return false end
	if missingLevelSkill ~= name then
		missingLevelSkill, missingLevelSince = name, DotaTime()
	end
	return DotaTime() - missingLevelSince >= 5
end

local function AbilityLevelUpComplement()
	if GetGameState() ~= GAME_STATE_PRE_GAME
		and GetGameState() ~= GAME_STATE_GAME_IN_PROGRESS
	then
		return
	end

	if J.CanNotUseAbility(bot) then
		return
	end

	-- Detect position change from !pos command: reload BotBuild for new role
	local nCurrentPos = J.GetPosition(bot)
	if nLastKnownPosition == nil then
		nLastKnownPosition = nCurrentPos
	elseif nCurrentPos ~= nLastKnownPosition then
		print("[PosSwap] "..botName.." position changed: pos"..nLastKnownPosition.." -> pos"..nCurrentPos)
		nLastKnownPosition = nCurrentPos
		ReloadBotBuild("Position swap to pos"..nCurrentPos)
		-- Signal item purchase to also rebuild
		bot.needPurchaseRebuild = true
	end

	if bot:GetLevel() >= 30
		and botName == "npc_dota_hero_bloodseeker"
	then
		return
	end

	if DotaTime() < 15
	then
		bot.theRole = J.Role.GetCurrentSuitableRole( bot, botName )
	end

	local botLoc = bot:GetLocation()
	if bot:IsAlive()
		and DotaTime() > 90
		and bot:GetCurrentActionType() == BOT_ACTION_TYPE_MOVE_TO
		and not IsLocationPassable( botLoc )
	then
		if bot.stuckLoc == nil
		then
			bot.stuckLoc = botLoc
			bot.stuckTime = DotaTime()
		elseif GetUnitToLocationDistance(bot, bot.stuckLoc) > 25
		then
			bot.stuckLoc = botLoc
			bot.stuckTime = DotaTime()
		end
	else
		bot.stuckTime = nil
		bot.stuckLoc = nil
	end

	if bot.needRefreshAbilitiesFor737 == false and BotBuild ~= nil then
		sAbilityLevelUpList = BuildRemainingLevelPlan(BotBuild['sSkillList'])
		pendingLevelUp = nil
		bot.needRefreshAbilitiesFor737 = nil
	end

	if pendingLevelUp ~= nil then
		local ability, paired = FindLevelAbility(pendingLevelUp.name)
		if ability == nil then
			if not IsMissingDefaultLevelSkill(pendingLevelUp.name, paired) then return end
		elseif ability:GetLevel() > pendingLevelUp.level then
			table.remove(sAbilityLevelUpList, 1)
		elseif DotaTime() - pendingLevelUp.time < 0.4 then
			return
		end
		pendingLevelUp = nil
	end

	if bot:GetAbilityPoints() <= 0 or J.IsTryingtoUseAbility(bot) then return end
	local botLevel = bot:GetLevel()
	local ardm = GetGameMode() == GAMEMODE_ARDM
	if #sAbilityLevelUpList == 0 and not customLevelPlan and (ardm or (botLevel > 25 and botLevel < 30)) then
		sAbilityLevelUpList = GetFallbackLevelPlan(botLevel)
	end

	while #sAbilityLevelUpList > 0 do
		local name = sAbilityLevelUpList[1]
		if name == 'generic_hidden' then
			table.remove(sAbilityLevelUpList, 1)
		else
			local ability, paired = FindLevelAbility(name)
			if ability == nil then
				if ardm and not paired and not customLevelPlan then
					local fallback = GetFallbackLevelPlan(botLevel)
					if #fallback > 0 then sAbilityLevelUpList = fallback end
				end
				if ardm or not IsMissingDefaultLevelSkill(name, paired) then return end
				table.remove(sAbilityLevelUpList, 1)
				if #sAbilityLevelUpList == 0 then
					sAbilityLevelUpList = GetFallbackLevelPlan(botLevel)
				end
			else
				missingLevelSkill, missingLevelSince = nil, nil

				local alternateName = (name == 'phoenix_fire_spirits' and 'phoenix_launch_fire_spirit')
					or (name == 'alchemist_unstable_concoction' and 'alchemist_unstable_concoction_throw')
				if alternateName then
					local alternate = bot:GetAbilityByName(alternateName)
					if alternate ~= nil and not alternate:IsNull() and not alternate:IsHidden() then return end
				end

				local previousLevel = ability:GetLevel()
				if previousLevel >= ability:GetMaxLevel() then
					table.remove(sAbilityLevelUpList, 1)
				elseif IsLegalLevelUp(ability, botLevel) then
					bot:ActionImmediate_LevelAbility(ability:GetName())
					if ability:GetLevel() > previousLevel then
						table.remove(sAbilityLevelUpList, 1)
					else
						pendingLevelUp = {name = name, level = previousLevel, time = DotaTime()}
					end
					return
				else
					return
				end
			end
		end
	end
end

function X.GetNumEnemyNearby( building )

	local nearbynum = 0
	for i, id in pairs( GetTeamPlayers( GetOpposingTeam() ) )
	do
		if IsHeroAlive( id )
		then
			local info = GetHeroLastSeenInfo( id )
			if info ~= nil
			then
				local dInfo = info[1]
				if dInfo ~= nil
					and GetUnitToLocationDistance( building, dInfo.location ) <= 3000
					and dInfo.time_since_seen < 1.0
				then
					nearbynum = nearbynum + 1
				end
			end
		end
	end

	return nearbynum

end

local nJiDiCount = RandomInt( 14, 20 )
local nTalkDelay = RandomInt( 19, 56 )/10
local nDeathReplyTime = -999
local nLastGold = 9999
local nLastKillCount = 999
local nLastDeathCount = 0
local nContinueKillCount = 0
local nReplyHumanCount = 0
local nMaxReplyCount = RandomInt( 5, 9 )
local bInstallChatCallbackDone = false
local nReplyHumanTime = nil
local sHumanString = nil
local bAllChat = false
function X.SetTalkMessage()

	local nBotID = bot:GetPlayerID()
	local nCurrentGold = bot:GetGold()
	local nCurrentKills = GetHeroKills( nBotID )
	local nCurrentDeaths = GetHeroDeaths( nBotID )
	local nRate = GetGameMode() == GAMEMODE_TURBO and 2.0 or 1.0

	--回复玩家的对话
	if nBotID == J.Role.GetReplyMemberID()
		and nReplyHumanCount <= nMaxReplyCount
	then
		if not bInstallChatCallbackDone and GetGameState() == GAME_STATE_GAME_IN_PROGRESS
		then
			bInstallChatCallbackDone = true
			--print(botName)
			InstallChatCallback( function( tChat ) X.SetReplyHumanTime( tChat ) end )
		end

		if sHumanString ~= nil
			and nReplyHumanTime ~= nil
			and DotaTime() > nReplyHumanTime + nTalkDelay
		then
			local chatString = J.Chat.GetReplyString( sHumanString, bAllChat )
			if chatString ~= nil
			then
				if nReplyHumanCount == nMaxReplyCount
				then chatString = J.Chat.GetStopReplyString() end

				bot:ActionImmediate_Chat( chatString, bAllChat )

				nReplyHumanCount = nReplyHumanCount + 1
				nTalkDelay = RandomInt( 6, 30 )/10
				if nTalkDelay > 2.0 then nTalkDelay = RandomInt( 6, 30 )/10 end
			end
			sHumanString = nil
			nReplyHumanTime = nil
		end
	end

	if J.Customize.Allow_Trash_Talk then
		--一血
		if DotaTime() < 600
			and bot:IsAlive()
			and nCurrentKills > nLastKillCount
			and J.GetNumOfTeamTotalKills( false ) == 1
			and J.GetNumOfTeamTotalKills( true ) == 0
			and RandomInt( 1, 9 ) > 4
		then
			local sTauntMark = Localization.Get('got_first_blood')[RandomInt( 1, #Localization.Get('got_first_blood') )]
			bot:ActionImmediate_Chat( sTauntMark, true )
		end

		--发问号
		if bot:IsAlive()
			and nCurrentGold > nLastGold + 300 * nRate
			and nCurrentKills > nLastKillCount
		then
			local sTauntMark = "?"
			if J.Customize.Trash_Talk_Level and J.Customize.Trash_Talk_Level >= 2 then
				if RandomInt( 1, 9 ) > 7 then sTauntMark = Localization.Get('got_a_kill')[RandomInt( 1, #Localization.Get('got_a_kill') )] end
				if nCurrentGold > nLastGold + 800 * nRate and RandomInt( 1, 9 ) > 4 then sTauntMark = Localization.Get('got_big_kill')[RandomInt( 1, #Localization.Get('got_big_kill') )] end
				if nCurrentGold > nLastGold + 1000 * nRate and RandomInt( 1, 9 ) > 3 then sTauntMark = Localization.Get('got_big_kill_2')[RandomInt( 1, #Localization.Get('got_big_kill_2') )] end
				if nCurrentGold > nLastGold + 1500 * nRate then sTauntMark = Localization.Get('got_big_kill_3')[RandomInt( 1, #Localization.Get('got_big_kill_3') )] end
			end
			if RandomInt( 1, 9 ) > 4 then bot:ActionImmediate_Chat( sTauntMark, true ) end
		end

		--发省略号
		if not bot:IsAlive()
		then
			if nContinueKillCount >= 8
				and nDeathReplyTime == -999
			then
				nDeathReplyTime = DotaTime()
				nContinueKillCount = 0
			end

			if nDeathReplyTime ~= -999
				and nDeathReplyTime < DotaTime() - nTalkDelay
			then
				bot:ActionImmediate_Chat( Localization.Get('kill_streak_ended')[RandomInt( 1, #Localization.Get('kill_streak_ended'))], true )
				nDeathReplyTime = -999
				nTalkDelay = RandomInt( 36, 49 )/10
			end
		end

		--发"jidi, xiayiba"
		if nCurrentKills == 0
			and nCurrentDeaths >= nJiDiCount
			and J.Role.NotSayJiDi()
		then
			bot:ActionImmediate_Chat( Localization.Get('say_end')[RandomInt( 1, #Localization.Get('say_end'))], true )
			J.Role['sayJiDi'] = true
		end
	end

	--计算连杀数量
	if nLastDeathCount == nCurrentDeaths
	then
		if nCurrentKills >= nLastKillCount + 1
		then
			nContinueKillCount = nContinueKillCount + 1
		end
	else
		nContinueKillCount = 0
	end

	nLastKillCount = GetHeroKills( nBotID )
	nLastDeathCount = GetHeroDeaths( nBotID )
	nLastGold = bot:GetGold()

end


function X.SetReplyHumanTime( tChat )

	local sChatString = tChat.string
	local nChatID = tChat.player_id

	if string.find(sChatString, "!sp") or string.find(sChatString, "!speak") then
		local action, target = J.Utils.TrimString(sChatString):match("^(%S+)%s+(.*)$")
		print("Set to speak: ".. target)
		J.Customize.Localization = target
		return
	end

	if sChatString ~= "-都来守家" or J.Role.IsAllyMemberID( nChatID )
	then
		J.Role.SetLastChatString( sChatString )
	end
		
	if not IsPlayerBot( nChatID )
		and ( tChat.team_only or J.Role.IsEnemyMemberID( nChatID ) )
	then
		sHumanString = sChatString
		nReplyHumanTime = DotaTime()
		bAllChat = not tChat.team_only
	end


end


local function BuybackUsageComplement()
	if J.IsMeepoClone(bot) then return end

	X.SetTalkMessage()

	if bot:GetLevel() <= 15
		or bot:HasModifier( 'modifier_arc_warden_tempest_double' )
		or not J.Role.ShouldBuyBack()
	then
		return
	end

	if bot:IsAlive() then return end

	if not bot:HasBuyback() then return end


	local ancient = GetAncient( GetTeam() )

	local nRemainingRespawnTime = bot:GetRespawnTime()

	if ancient ~= nil and J.GetHP(ancient) < 0.8 then
		local nEnemyUnitsAroundAncient = J.GetEnemiesAroundLoc(ancient:GetLocation(), 1500)
		local nAllyUnitsAroundAncient = J.GetAlliesNearLoc(ancient:GetLocation(), 1500)
		if nEnemyUnitsAroundAncient > 1 and #nAllyUnitsAroundAncient == 0 and nRemainingRespawnTime > 20 then
			J.Role['lastbbtime'] = DotaTime()
			bot:ActionImmediate_Buyback()
			return
		end
	end

	if bot:GetLevel() > 24
		and nRemainingRespawnTime > 80
	then
		local nTeamFightLocation = J.GetTeamFightLocation( bot )
		if nTeamFightLocation ~= nil
		then
			J.Role['lastbbtime'] = DotaTime()
			bot:ActionImmediate_Buyback()
			return
		end
	end

	if nRemainingRespawnTime < 40
	then
		return
	end

	if ancient ~= nil
	then
		local nEnemyCount = X.GetNumEnemyNearby( ancient )
		local nAllyCount = J.GetNumOfAliveHeroes( false )
		if nEnemyCount > 0 and nEnemyCount >= nAllyCount
		then
			J.Role['lastbbtime'] = DotaTime()
			bot:ActionImmediate_Buyback()
			return
		end
	end

end


local nCourierLastActionTime = -90
local nCourierState = -1
bot.SShopUser = false
local nCourierReturnTime = -90
local nCourierDeliverTime = -90
local function CourierUsageComplement()

	if DotaTime() < -56
		or bot:HasModifier( "modifier_arc_warden_tempest_double" )
		or nCourierReturnTime + 5.0 > DotaTime()
	then
		return
	end

	if bot.theCourier == nil or bot.theCourier:IsNull()
	then
		bot.theCourier = X.GetBotCourier( bot )
		if bot.theCourier == nil then return end
	end

	--------* * * * * * * ----------------* * * * * * * ----------------* * * * * * * --------
	local bDebugCourier = ( 10 == 10 )
	local npcCourier = bot.theCourier
	nCourierState = GetCourierState( npcCourier )
	local courierHP = npcCourier:GetHealth() / npcCourier:GetMaxHealth()
	local currentTime = DotaTime()
	local bAliveBot = bot:IsAlive()
	local botLV = bot:GetLevel()
	local useCourierCD = 2.3
	local protectCourierCD = 5.0
	--------* * * * * * * ----------------* * * * * * * ----------------* * * * * * * --------

	if nCourierState == COURIER_STATE_DEAD then return	end

	if X.IsCourierTargetedByUnit( npcCourier )
	then
		bot.ohaCourierUnsafeUntil = currentTime + protectCourierCD
		if currentTime > nCourierReturnTime + protectCourierCD
		then
			nCourierReturnTime = currentTime

			J.SetReportMotive( bDebugCourier, "信使可能会被攻击" )

			bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_RETURN_STASH_ITEMS )

			local abilityBurst = npcCourier:GetAbilityByName( 'courier_burst' )
			if abilityBurst and abilityBurst:IsFullyCastable()
			then
				bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_BURST )
			end

		end
		return
	end

	if bot.SShopUser
		and ( not bAliveBot or bot:GetActiveMode() == BOT_MODE_SECRET_SHOP or not bot.SecretShop )
	then
		bot.SShopUser = false
		J.SetReportMotive( bDebugCourier, "让信使返回基地避免被卡住" )
		bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_RETURN_STASH_ITEMS )
		return
	end


	if bot.ohaLaneSupply then
		local supply = require(GetScriptDirectory() .. '/FunLib/lane_supply')
		local action, handling = supply.CourierAction(bot, npcCourier, nCourierState)
		if handling then
			if action and currentTime > nCourierLastActionTime + useCourierCD then
				bot:ActionImmediate_Courier(npcCourier, action)
				nCourierLastActionTime = currentTime
			end
			return
		end
	end
	if ( nCourierState == COURIER_STATE_RETURNING_TO_BASE
		or nCourierState == COURIER_STATE_AT_BASE
		or nCourierState == COURIER_STATE_IDLE )
		and currentTime > nCourierReturnTime + protectCourierCD
	then

		if nCourierState == COURIER_STATE_AT_BASE and courierHP < 0.8 
		then return	end

		if nCourierState == COURIER_STATE_IDLE and npcCourier:DistanceFromFountain() > 800
		then
			J.SetReportMotive( bDebugCourier, "让空闲的信使返回" )
			bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_RETURN_STASH_ITEMS )
			return
		end

		if bAliveBot
			and ( not X.IsInvFull( bot )
					or currentTime <= 5 * 60
					or ( bot.currBuyingBasicItemList ~= nil and #bot.currBuyingBasicItemList == 0 and bot.currBuyingItemInPurchaseList ~= 'item_travel_boots' ) )
			and ( nCourierState == COURIER_STATE_AT_BASE
					or ( nCourierState == COURIER_STATE_IDLE and npcCourier:DistanceFromFountain() < 800 ) )
		then
			local nMSlot = X.GetNumStashItem( bot )
			if nMSlot > 0
			-- and Utils.CountBackpackEmptySpace(bot) >= 1
			then
				if ( bot.currBuyingBasicItemList ~= nil and #bot.currBuyingBasicItemList == 0 )
					or ( bot.currBuyingBasicItem ~= nil
							and ( IsItemPurchasedFromSecretShop( bot.currBuyingBasicItem )
									or X.GetNumStashItem( bot ) == 6
									or bot:GetGold() + 80 < GetItemCost( bot.currBuyingBasicItem ) ) )
				then
					J.SetReportMotive( bDebugCourier, "信使取出物品并开始运输" )
					bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_TAKE_STASH_ITEMS )
					nCourierLastActionTime = currentTime

					if currentTime > nCourierDeliverTime + protectCourierCD
					then
						nCourierDeliverTime = currentTime
						local abilityBurst = npcCourier:GetAbilityByName( 'courier_burst' )
						if abilityBurst and abilityBurst:IsFullyCastable()
						then
							J.SetReportMotive( bDebugCourier, "信使加速配送" )
							bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_BURST )
						end
					end
				end
			end
		end

		if bAliveBot and bot.SecretShop
			and npcCourier:DistanceFromFountain() < 7000
			and J.Item.GetEmptyInventoryAmount( npcCourier ) >= 2
			and not X.IsEnemyHeroAroundSecretShop() -- 商店附近没有敌人
			and currentTime > nCourierLastActionTime + useCourierCD
		then
			J.SetReportMotive( bDebugCourier, "信使前往神秘商店购物" )
			bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_SECRET_SHOP )
			bot.SShopUser = true
			nCourierLastActionTime = currentTime
			return
		end

		if bAliveBot
			and bot:GetCourierValue() > 0
			and bot:GetStashValue() < 100
			and ( not X.IsInvFull( bot ) or ( X.GetNumStashItem( bot ) == 0 and bot.currBuyingBasicItemList ~= nil and #bot.currBuyingBasicItemList == 0 ) )
			and ( npcCourier:DistanceFromFountain() < 4000 + botLV * 200 or GetUnitToUnitDistance( bot, npcCourier ) < 1800 )
			and currentTime > nCourierLastActionTime + useCourierCD
			-- and Utils.CountBackpackEmptySpace(bot) >= 1
		then
			J.SetReportMotive( bDebugCourier, "信使运输背包中的东西" )
			bot:ActionImmediate_Courier( npcCourier, COURIER_ACTION_TRANSFER_ITEMS )
			nCourierLastActionTime = currentTime
			return
		end


	end

end


function X.GetBotCourier( bot )

	local nPlayerID = bot:GetPlayerID()

	for nCourierID = 0, GetNumCouriers() - 1
	do
		local courier = GetCourier( nCourierID )
		if courier ~= nil and not courier:IsNull() and courier:GetPlayerID() == nPlayerID
		then
			return courier
		end
	end

end


function X.GetNumStashItem( unit )

	local amount = 0
	for i = 9, 14
	do
		if unit:GetItemInSlot( i ) ~= nil
		then
			amount = amount + 1
		end
	end

	return amount

end

function X.IsThereRecipeInStash( unit )
	local amount = 0

	for i = 9, 14
	do
		local item = unit:GetItemInSlot(i)
		if item ~= nil
		then
			if string.find(item:GetName(), "item_recipe_")
			then
				amount = amount + 1
			end
		end
	end

	return amount > 0
end


function X.IsCourierTargetedByUnit( courier )
	if GetGameMode() == GAMEMODE_TURBO then return false end
	
	local botLV = bot:GetLevel()

	if J.GetHP( courier ) < 0.9
	then
		return true
	end

	if courier:DistanceFromFountain() < 900 then return false end

	for i = 0, 10
	do
		local tower = GetTower( GetOpposingTeam(), i )
		if tower ~= nil and tower:CanBeSeen()
		then
			local towerTarget = tower:GetAttackTarget()

			if towerTarget == courier
			then
				return true
			end

			if towerTarget == nil
				and GetUnitToUnitDistance( courier, tower ) < 999
			then
				return true
			end
		end
	end

	for i, id in pairs( GetTeamPlayers( GetOpposingTeam() ) )
	do
		if IsHeroAlive( id )
		then
			local info = GetHeroLastSeenInfo( id )
			if info ~= nil
			then
				local dInfo = info[1]
				if dInfo ~= nil
					and GetUnitToLocationDistance( courier, dInfo.location ) <= 800
					and dInfo.time_since_seen < 1.8
				then
					return true
				end
			end
		end
	end

	local nEnemysHeroesCanSeen = GetUnitList( UNIT_LIST_ENEMY_HEROES )
	for _, enemy in pairs( nEnemysHeroesCanSeen )
	do
		if GetUnitToUnitDistance( enemy, courier ) <= 700 + botLV * 15
		then
			local nNearCourierAllyList = J.GetAlliesNearLoc( enemy:GetLocation(), 600 )
			if #nNearCourierAllyList == 0
				or enemy:GetAttackTarget() == courier
			then
				return true
			end
		end

		if enemy:GetUnitName() == 'npc_dota_hero_sniper'
			and GetUnitToUnitDistance( enemy, courier ) <= 1100 + botLV * 30
		then
			return true
		end

		if GetUnitToUnitDistance( enemy, courier ) <= enemy:GetAttackRange() + 88
		then
			return true
		end
	end

	local nEnemysHeroes = J.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )
	for _, enemy in pairs( nEnemysHeroes )
	do
		if enemy ~= nil and J.IsValidHero( enemy ) and GetUnitToUnitDistance( enemy, courier ) <= 700 + botLV * 15
		then
			local nNearCourierAllyList = J.GetAlliesNearLoc( enemy:GetLocation(), 800 )
			if #nNearCourierAllyList == 0
				or enemy:GetAttackTarget() == courier
			then
				return true
			end
		end

		if enemy ~= nil and J.IsValidHero( enemy ) and GetUnitToUnitDistance( enemy, courier ) <= enemy:GetAttackRange() + 100
		then
			return true
		end
	end

	local nAllEnemyCreeps = GetUnitList( UNIT_LIST_ENEMY_CREEPS )
	local nNearCourierAllyList = J.GetAlliesNearLoc( courier:GetLocation(), 1500 )
	local nNearCourierAllyCount = #nNearCourierAllyList
	for _, creep in pairs( nAllEnemyCreeps )
	do
		if GetUnitToUnitDistance( courier, creep ) <= 800
			and ( creep:GetAttackTarget() == courier or botLV > 10 )
			and ( nNearCourierAllyCount == 0 or creep:GetAttackTarget() == courier )
		then
			return true
		end
	end

	return false

end


function X.IsInvFull( bot )

	for i = 0, 8
	do
		if bot:GetItemInSlot( i ) == nil
		then
			return false
		end
	end

	return true

end


function X.IsEnemyHeroAroundSecretShop()

	local vRadiantShop = GetShopLocation( team, SHOP_SECRET )
	local vDireShop = GetShopLocation( team, SHOP_SECRET2 )
	local vTeamSecretShop = team == TEAM_DIRE and vDireShop or vRadiantShop

	local vCenterLocation = ( vTeamSecretShop + GetAncient( team ):GetLocation() ) * 0.5

	if J.IsEnemyHeroAroundLocation( vCenterLocation, 2000 )
	then
		return true
	end

	return false

end




local fLastStashItemTimeList = {}
local aetherRange = 0
local lastAmuletTime = 0
local thereBeMonkey = false
local lastSwitchPtTime = -90
local hNearbyEnemyHeroList = {}
local hNearbyEnemyTowerList = {}
local botTarget = nil
local nMode = -1
local battleHorn = 'item_horn_of_battle_greater'
local combatItems = {
	item_black_king_bar = true, item_force_staff = true, item_caduceus = true, item_hurricane_pike = true,
	item_invis_sword = true, item_silver_edge = true, item_trickster_cloak = true,
	item_glimmer_cape = true, item_lotus_orb = true, item_dust = true,
}

local concealmentFade = {
	item_invis_sword = 'windwalk_fade_time', item_silver_edge = 'windwalk_fade_time',
	item_shadow_amulet = 'fade_time', item_glimmer_cape = 'initial_fade_delay',
}

local function HasPendingConcealment(unit, itemName)
	local pending = unit.ohaItemConcealment
	if pending == nil or (itemName ~= nil and pending.itemName ~= itemName) then return false end
	local now = DotaTime()
	return now >= pending.start and now < pending.finish
end

local function HasItemConcealment(unit)
	return HasPendingConcealment(unit) or J.HasItemConcealment(unit)
end

local function ConsiderItemSlot(slot, combat, preserveConcealment, revealed)
	local item = bot:GetItemInSlot(slot)
	if not J.CanCastAbility(item) then return end
	local name = item:GetName()
	if (combatItems[name] == true) ~= combat or (slot >= 6 and slot <= 8 and name ~= battleHorn) then return end
	-- In 7.42 Armlet's toggle preserves invisibility. Other legacy handlers can change state while evaluating.
	if preserveConcealment and not combat and name ~= 'item_armlet' then return end
	local consider = X.ConsiderItemDesire[name]
	if consider ~= nil and not X.IsItemInStash(name) then
		local desire, target, castType, motive, followUp, emergency = consider(item)
		if name == 'item_tpscroll' and desire > 0 and not J.CanStartTeleportHere(bot) then return end
		if desire > 0 and (not preserveConcealment or name == 'item_armlet' or emergency == 'always'
			or (revealed and emergency == 'revealed')) then
			return {item = item, name = name, slot = slot, desire = desire, target = target,
				castType = castType, motive = motive, followUp = followUp}
		end
	end
end

local function UseConsideredItem(choice)
	if bDebugMode and choice.motive ~= nil and J.Item.IsSpecifiedItem(choice.name) then
		J.SetReportMotive(bDebugMode, choice.name .. '→' .. choice.motive)
	end
	X.SetUseItem(choice.item, choice.target, choice.castType)
	if choice.name == 'item_tpscroll' then J.TraceLaneTeleport(bot, choice.motive, choice.target) end
	local fade = concealmentFade[choice.name]
	if fade ~= nil or choice.name == 'item_trickster_cloak' then
		local recipient = choice.castType == 'unit' and choice.target or bot
		local now = DotaTime()
		local delay = fade ~= nil and choice.item:GetSpecialValueFloat(fade) or 0
		recipient.ohaItemConcealment = {itemName = choice.name, start = now, finish = now + delay + 0.15}
	end
	if choice.followUp ~= nil then choice.followUp() end
	return choice.slot + 1
end

local function ItemUsageComplement()

	X.SetStashItemTimeUpdate()

	if not bot:IsAlive()
		or bot:IsMuted()
		or bot:IsHexed()
		or bot:IsStunned()
		or bot:IsChanneling()
		or bot:IsInvulnerable() and not bot:HasModifier('modifier_fountain_invulnerability')
		or bot:IsUsingAbility()
		or bot:IsCastingAbility()
		or bot:NumQueuedActions() > 0
		or bot:HasModifier( 'modifier_teleporting' )
		or bot:HasModifier( 'modifier_doom_bringer_doom' )
		or bot:HasModifier( 'modifier_phantom_lancer_phantom_edge_boost' )
	then return	BOT_ACTION_DESIRE_NONE end

	hNearbyEnemyHeroList = J.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE )
	hNearbyEnemyTowerList = bot:GetNearbyTowers( 888, true )
	botTarget = J.GetProperTarget( bot )
	nMode = bot:GetActiveMode()
	local itemConcealment = HasItemConcealment(bot)
	local preserveConcealment = itemConcealment or X.WillBreakInvisible(bot)
	local revealed = itemConcealment and (J.HasInvisCounterBuff(bot) or #hNearbyEnemyTowerList > 0)

	local aether = J.IsItemAvailable( "item_aether_lens" )
	if aether ~= nil then aetherRange = aether:GetSpecialValueInt('cast_range_bonus') else aetherRange = 0 end

	local nItemSlot = { 5, 4, 3, 2, 1, 0, 15, 16, 8, 7, 6 }

	local bestCombat
	for _, slot in ipairs(nItemSlot) do
		local choice = ConsiderItemSlot(slot, true, preserveConcealment, revealed)
		if choice ~= nil and (bestCombat == nil or choice.desire > bestCombat.desire) then bestCombat = choice end
	end
	if bestCombat ~= nil and bestCombat.desire >= BOT_ACTION_DESIRE_HIGH then return UseConsideredItem(bestCombat) end

	-- Other item handlers can have side effects. Keep their existing first-match order.
	for _, slot in ipairs(nItemSlot) do
		local choice = ConsiderItemSlot(slot, false, preserveConcealment)
		if choice ~= nil then return UseConsideredItem(choice) end
	end
	if bestCombat ~= nil then return UseConsideredItem(bestCombat) end
	return BOT_ACTION_DESIRE_NONE

end

function X.SetUseItem( hItem, hItemTarget, sCastType )

	if sCastType == 'none'
	then
		bot:Action_UseAbility( hItem )
		return
	elseif sCastType == 'unit'
	then
		local targetType = type(hItemTarget)
		if targetType == 'table' or targetType == 'userdata' then
			bot:Action_UseAbilityOnEntity( hItem, hItemTarget )
		end
		return
	elseif sCastType == 'ground' or (hItemTarget and type(hItemTarget) ~= 'number' and type(hItemTarget) ~= 'table' and hItemTarget.x ~= nil) -- in case target is a location
	then
		bot:Action_UseAbilityOnLocation( hItem, hItemTarget )
		return
	elseif sCastType == 'tree'
	then
		bot:Action_UseAbilityOnTree( hItem, hItemTarget )
		return
	elseif sCastType == 'twice'
	then
		bot:Action_UseAbility( hItem )
		bot:ActionQueue_UseAbility( hItem )
		return
	end

end


function X.IsWithoutSpellShield( npcEnemy )

	return not npcEnemy:HasModifier( "modifier_item_sphere_target" )
			and not npcEnemy:HasModifier( "modifier_antimage_spell_shield" )
			and not npcEnemy:HasModifier( "modifier_item_lotus_orb_active" )

end


local lastDeleteTime = -90
function X.SetStashItemTimeUpdate()

	local currentTime = DotaTime()

	for i = 6, 8
	do
		local hItem = bot:GetItemInSlot( i )
		if hItem ~= nil
		then
			fLastStashItemTimeList[hItem:GetName()] = currentTime
		end
	end

	if currentTime > lastDeleteTime + 7.0
	then
		lastDeleteTime = currentTime
		for k, v in pairs( fLastStashItemTimeList )
		do
			if v ~= nil
				and v < currentTime - 7.0
			then
				fLastStashItemTimeList[k] = nil
			end
		end
	end

end


function X.IsItemInStash( sItemName )

	if fLastStashItemTimeList[sItemName] ~= nil
		and DotaTime() < fLastStashItemTimeList[sItemName] + 6.05
	then
		return true
	end

	return false

end


function X.WillBreakInvisible( bot )

	local botName = botName

	if bot:IsInvisible()
	then
		if not bot:HasModifier( "modifier_phantom_assassin_blur_active" )
			and botName ~= "npc_dota_hero_riki"
		then
			return true
		end
	end

	return false

end


X.ConsiderItemDesire = {}

X.ConsiderItemDesire[battleHorn] = function()
	if J.IsPushing(bot) and J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		return BOT_ACTION_DESIRE_HIGH, bot, 'none'
	end
	return BOT_ACTION_DESIRE_NONE
end

--深渊
X.ConsiderItemDesire["item_abyssal_blade"] = function( hItem )

	local nCastRange = 620 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil

	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	for _, npcEnemy in pairs( nInRangeEnmyList )
	do

		if J.IsValid( npcEnemy )
			and J.CanCastOnNonMagicImmune( npcEnemy )
			and X.IsWithoutSpellShield( npcEnemy )
		then
			--打断
			if npcEnemy:IsChanneling() or npcEnemy:IsCastingAbility()
			then
				hEffectTarget = npcEnemy
				sCastMotive = "打断:"..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end

			--撤退
			if 	nMode == BOT_MODE_RETREAT
				and not J.IsDisabled( npcEnemy )
			then
				hEffectTarget = npcEnemy
				sCastMotive = "撤退:"..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end

	end

	--进攻
	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange + 50 )
			and J.CanCastOnNonMagicImmune( botTarget ) --bug
			and X.IsWithoutSpellShield( botTarget )
			and not J.IsDisabled( botTarget )
		then
			hEffectTarget = botTarget
			sCastMotive = "进攻:"..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--战鼓
X.ConsiderItemDesire["item_ancient_janggo"] = function( hItem )

	if ( hItem:GetCurrentCharges() <= 0 and hItem:GetName() == "item_ancient_janggo" )
	then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 680
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	if bot:HasModifier('modifier_nyx_assassin_vendetta')
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and J.CanCastOnMagicImmune( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
		then
			hEffectTarget = botTarget
			sCastMotive = "进攻:"..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--秘法
X.ConsiderItemDesire["item_arcane_boots"] = function( hItem )

	if bot:DistanceFromFountain() < 800 then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 1200
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	local hNearbyAllyList = J.GetAllyList( bot, nCastRange )

	if #hNearbyAllyList >= 2
		and bot:GetHealth() <= 120
		and bot:WasRecentlyDamagedByAnyHero( 3.0 )
	then
		sCastMotive = '死前为队友用'
		return BOT_ACTION_DESIRE_HIGH, hNearbyAllyList[2], sCastType, sCastMotive
	end

	local nNeedMPCount = 0
	for _, npcAlly in pairs( hNearbyAllyList )
	do
		if npcAlly ~= nil and npcAlly:IsAlive()
			and npcAlly:GetMaxMana()- npcAlly:GetMana() > 180
		then
			nNeedMPCount = nNeedMPCount + 1
		end

		if nNeedMPCount >= 2
		then
			sCastMotive = '团队回蓝'
			return BOT_ACTION_DESIRE_HIGH, hNearbyAllyList[2], sCastType, sCastMotive
		end
	end

	if bot:GetMana() / bot:GetMaxMana() < 0.58
	then
		sCastMotive = '自己补蓝'
		return BOT_ACTION_DESIRE_HIGH, bot, sCastType, sCastMotive
	end


	return BOT_ACTION_DESIRE_NONE

end


--臂章
local nLastActiveArmletTime = -90
X.ConsiderItemDesire["item_armlet"] = function( hItem )

	if bDeafaultItemHero then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 1000
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	local bActive = hItem:GetToggleState()

	if ( J.IsValid( botTarget ) or J.IsValidBuilding( botTarget ) )
		and not botTarget:IsAttackImmune()
		and not botTarget:IsInvulnerable()
		and ( not botTarget:IsBuilding() or not J.IsKeyWordUnit( "OutpostName", botTarget ) )
		and not J.HasForbiddenModifier( botTarget )
		and J.IsInRange( bot, botTarget, bot:GetAttackRange() + 180 )
		and not bot:IsDisarmed()
	then
		nLastActiveArmletTime = DotaTime()
		if not bActive
		then
			hEffectTarget = botTarget
			sCastMotive = '激活臂章攻击'..( hEffectTarget:IsHero() and J.Chat.GetNormName( hEffectTarget ) or "非英雄" )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end


	if bot:OriginalGetHealth() <= 600
		and ( bot:WasRecentlyDamagedByAnyHero( 2.0 ) or J.IsAttackProjectileIncoming( bot, 1600 ) )
	then
		nLastActiveArmletTime = DotaTime()
		if not bActive
		then
			hEffectTarget = bot
			sCastMotive = '激活临时血量'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end


	if bActive
		and DotaTime() > nLastActiveArmletTime + 0.9
		and #nInRangeEnmyList == 0
		and not bot:WasRecentlyDamagedByAnyHero(2)
		and not J.IsAttackProjectileIncoming(bot, 1600)
	then
		hEffectTarget = bot
		sCastMotive = '关闭臂章'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType --, '关闭臂章'
	end

	return BOT_ACTION_DESIRE_NONE

end


--狂战
X.ConsiderItemDesire["item_bfury"] = function( hItem )

	return X.ConsiderItemDesire["item_quelling_blade"]( hItem )

end


local dispellableControls = {
    modifier_silencer_global_silence = true,
    modifier_orchid_malevolence_debuff = true,
    modifier_bloodthorn_debuff = true,
    modifier_skywrath_mage_ancient_seal = true,
    modifier_death_prophet_silence = true,
    modifier_rod_of_atos_debuff = true,
    modifier_gungir_debuff = true,
    modifier_crystal_maiden_frostbite = true,
}

local targetedDisables = {
    lion_voodoo = true, shadow_shaman_voodoo = true, shadow_shaman_shackles = true,
    rubick_telekinesis = true, bane_nightmare = true, morphling_adaptive_strike_str = true,
}

local function GetDispellableControlTime(unit)
    if not (unit:IsRooted() or unit:IsSilenced()) then return 0 end
    local remaining = 0
    for name in pairs(dispellableControls) do
        remaining = math.max(remaining, J.GetModifierTime(unit, name))
    end
    return remaining
end

local function GetCombatPursuers(unit, radius)
    return J.GetHeroesTargetingUnit(J.GetEnemiesNearLoc(unit:GetLocation(), radius), unit)
end

local function HasAllyAttackCommitment(target, meleeOnly)
    for _, ally in ipairs(J.GetAlliesNearLoc(target:GetLocation(), 1250)) do
        if ally:GetAttackTarget() == target and (not meleeOnly or ally:GetAttackProjectileSpeed() == 0)
        and J.IsInRange(ally, target, ally:GetAttackRange() + 100) then return true end
    end
    return false
end

local function HasIncomingCombatSpell(unit, radius, kind)
    for _, projectile in ipairs(unit:GetIncomingTrackingProjectiles()) do
        local ability = projectile.ability
        if not projectile.is_attack and ability ~= nil and not ability:IsNull()
        and (projectile.caster == nil or projectile.caster:GetTeam() ~= unit:GetTeam())
        and GetUnitToLocationDistance(unit, projectile.location) <= radius then
            local name = ability:GetName()
            if (kind == 'disable' and J.IsStunProjectileSpell(name))
            or (kind == 'targeted' and J.CheckBitfieldFlag(ability:GetBehavior(), ABILITY_BEHAVIOR_UNIT_TARGET))
            or (kind == 'magic' and (J.IsStunProjectileSpell(name) or
                (ability.GetDamageType ~= nil and ability:GetDamageType() == DAMAGE_TYPE_MAGICAL))) then
                return true
            end
        end
    end
    return false
end

local function HasIncomingTargetedDisable(unit, enemies)
    for _, enemy in ipairs(enemies) do
        if (enemy:IsCastingAbility() or enemy:IsUsingAbility()) and enemy:IsFacingLocation(unit:GetLocation(), 20) then
            local ability = enemy:GetCurrentActiveAbility()
            if ability ~= nil and not ability:IsNull() and targetedDisables[ability:GetName()]
            and J.IsInRange(enemy, unit, ability:GetCastRange() + 50) then
                return true
            end
        end
    end
    return false
end

local function IsSafeCombatLanding(unit, location)
    if not IsLocationPassable(location) or J.IsLocationInChrono(location)
    or J.IsLocationInBlackHole(location) or J.IsLocationInArena(location, 600) then return false end
    for _, tower in ipairs(unit:GetNearbyTowers(1600, true)) do
        if J.IsValidBuilding(tower) and GetUnitToLocationDistance(tower, location) <= tower:GetAttackRange() + 50
        and GetUnitToLocationDistance(tower, location) <= GetUnitToUnitDistance(tower, unit) then
            return false
        end
    end
    return true
end

local function MakesSpaceFromEnemies(unit, location, pursuers)
    if not IsSafeCombatLanding(unit, location) or #J.GetEnemiesNearLoc(location, 350) > 0 then return false end
    if #pursuers == 0 then return true end
    local before, after = math.huge, math.huge
    for _, enemy in ipairs(pursuers) do
        before = math.min(before, GetUnitToUnitDistance(unit, enemy))
        after = math.min(after, GetUnitToLocationDistance(enemy, location))
    end
    return after >= before + 150
end

local function BkbEnablesCast(item, ability)
    return ability ~= nil and not ability:IsNull() and not ability:IsHidden() and ability:IsTrained()
        and ability:IsActivated() and ability:GetCooldownTimeRemaining() <= 0
        and not bot:HasModifier('modifier_item_mask_of_madness_berserk')
        and bot:GetMana() >= item:GetManaCost() + ability:GetManaCost()
end

local bkbEscapeSpells = {
    npc_dota_hero_faceless_void = 'faceless_void_time_walk',
    npc_dota_hero_antimage = 'antimage_blink',
    npc_dota_hero_queenofpain = 'queenofpain_blink',
}

local function FindBkbEscape(item, pursuers)
    local name = bkbEscapeSpells[botName]
    if name == nil then return end
    local ability = bot:GetAbilityByName(name)
    if not BkbEnablesCast(item, ability) then return end
    local range = name == 'faceless_void_time_walk' and ability:GetSpecialValueInt('range') or ability:GetCastRange()
    if range <= 0 then return end

    local goal = J.GetEscapeLoc()
    local distance = math.min(range, GetUnitToLocationDistance(bot, goal))
    if distance < 200 then return end
    local location = J.Site.GetXUnitsTowardsLocation(bot, goal, distance)
    if MakesSpaceFromEnemies(bot, location, pursuers) then
        return function() bot:ActionQueue_UseAbilityOnLocation(ability, location) end
    end
end

local function FindBkbCounterInitiation(item)
    if botName ~= 'npc_dota_hero_faceless_void' then return end
    local ability = bot:GetAbilityByName('faceless_void_chronosphere')
    if not BkbEnablesCast(item, ability) then return end
    local radius = math.max(ability:GetSpecialValueInt('radius'), ability:GetAOERadius() or 0)
    if radius <= 0 then return end
    local area = bot:FindAoELocation(true, true, bot:GetLocation(), ability:GetCastRange(), radius, ability:GetCastPoint(), 0)
    if area.count < 2 or area.targetloc == nil or #J.GetEnemiesNearLoc(area.targetloc, radius) < 2
    or J.GetAvailableFightAllies(bot, area.targetloc, 1200) == 0
    or not BotBuild.IsChronosphereAllySafe(ability, area.targetloc) then return end
    return function() bot:ActionQueue_UseAbilityOnLocation(ability, area.targetloc) end
end

local function EarliestPursuitContact(unit, pursuers)
    local time = math.huge
    for _, enemy in ipairs(pursuers) do
        local reach = math.max(enemy:GetAttackRange(), 300) + 75
        local gap = math.max(0, GetUnitToUnitDistance(unit, enemy) - reach)
        time = math.min(time, gap / math.max(enemy:GetCurrentMovementSpeed(), 1))
    end
    return time
end

local function HasBkbWalkingExit(pursuers)
    local goal = J.GetEscapeLoc()
    local movement = math.min(400, GetUnitToLocationDistance(bot, goal))
    return movement >= 200 and MakesSpaceFromEnemies(bot, J.Site.GetXUnitsTowardsLocation(bot, goal, movement), pursuers)
end

X.ConsiderItemDesire['item_black_king_bar'] = function(item)
    if bot:HasModifier('modifier_dazzle_nothl_projection_soul_debuff')
    or bot:IsMagicImmune() or bot:IsInvulnerable() then return BOT_ACTION_DESIRE_NONE end

    local enemies = J.GetEnemiesNearLoc(bot:GetLocation(), 1300)
    local pursuers = J.GetHeroesTargetingUnit(enemies, bot)
    local retreating = J.IsRetreating(bot) or J.ShouldRetreatFromEnemyReinforcements(bot)
    local fighting = J.IsGoingOnSomeone(bot) and J.IsValidHero(botTarget)
    local alreadyIncoming = HasIncomingCombatSpell(bot, 400, 'disable')
    local imminent = alreadyIncoming or HasIncomingTargetedDisable(bot, enemies)
    local contact = EarliestPursuitContact(bot, pursuers)
    local remaining = GetDispellableControlTime(bot)

    if remaining > 0.3 and contact + 0.2 < remaining then
        if retreating or (#pursuers >= 2 and not fighting) then
            local escape = FindBkbEscape(item, pursuers)
            if escape ~= nil then return 0.98, bot, 'none', '驱散后位移撤离', escape, 'revealed' end
            if bot:IsRooted() and HasBkbWalkingExit(pursuers) then return 0.95, bot, 'none', '驱散缠绕后撤离', nil, 'revealed' end
        end
    end
    if remaining > 0.35 and fighting and bot:IsSilenced() then
        local counter = FindBkbCounterInitiation(item)
        if counter ~= nil then return 0.98, bot, 'none', '驱散后反打', counter end
    end

    local exposed = #pursuers >= 2 and (bot:WasRecentlyDamagedByAnyHero(2) or (alreadyIncoming and contact < 0.5))
    if imminent and (fighting or exposed or (retreating and HasBkbWalkingExit(pursuers))) then
        return 0.99, bot, 'none', '预防即将命中的硬控', nil, alreadyIncoming and 'always' or 'revealed'
    end
    if J.GetHP(bot) < 0.35 and contact < 0.6 and HasIncomingCombatSpell(bot, 500, 'magic') then
        return 0.94, bot, 'none', '减轻即将命中的魔法伤害', nil, 'always'
    end
    return BOT_ACTION_DESIRE_NONE
end


--刃甲
X.ConsiderItemDesire["item_blade_mail"] = function( hItem )

	local nCastRange = 800
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsNotAttackProjectileIncoming( bot, 366 )
		and #nInRangeEnmyList >= 1
	then
		hEffectTarget = bot
		sCastMotive = '反弹弹道'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	for _, npcEnemy in pairs( hNearbyEnemyHeroList )
	do
		if J.IsValidHero( npcEnemy )
			and J.CanCastOnNonMagicImmune( npcEnemy )
			and npcEnemy:GetAttackTarget() == bot
			and ( bot:WasRecentlyDamagedByHero( npcEnemy, 5.0 )
				 or J.IsAttackProjectileIncoming( bot, 1000 ) )
		then
			hEffectTarget = npcEnemy
			sCastMotive = '反弹敌人伤害:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--跳刀
X.ConsiderItemDesire["item_blink"] = function( hItem )
	local nCastRange = 1200
	if hItem:GetName() == 'item_arcane_blink' then
		nCastRange = 1400
	end

	nCastRange = nCastRange + aetherRange

	if J.HasItemInInventory('item_magnifying_monocle') then
		nCastRange = nCastRange + 100
	end

	if J.HasItemInInventory('item_enhancement_keen_eyed') then
		if DotaTime() >= (J.IsModeTurbo() and 7.5*60 or 15*60) then
			nCastRange = nCastRange + 125
		elseif DotaTime() >= (J.IsModeTurbo() and 12.5*60 or 25*60) then
			nCastRange = nCastRange + 135
		end
	end

	if J.HasItemInInventory('item_enhancement_mystical') then
		if DotaTime() >= (J.IsModeTurbo() and 17.5*60 or 35*60) then
			nCastRange = nCastRange + 100
		end
	end

	if J.HasItemInInventory('item_enhancement_boundless') then
		if DotaTime() >= (J.IsModeTurbo() and 30*60 or 60*60) then
			nCastRange = nCastRange + 350
		end
	end

	local botName = bot:GetUnitName()

	if bot:IsRooted()
	or bot:HasModifier('modifier_nyx_assassin_vendetta')
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if J.IsStuck(bot)
	then
		local loc = J.GetLocationTowardDistanceLocation(bot, GetAncient(GetTeam()):GetLocation(), nCastRange)
		return BOT_ACTION_DESIRE_HIGH, loc, 'ground', nil
	end

	local nInRangeAlly = bot:GetNearbyHeroes(800, false, BOT_MODE_ATTACK)

	if  J.IsRetreating(bot)
	and not J.IsRealInvisible(bot)
	and bot:GetActiveModeDesire() > BOT_MODE_DESIRE_MODERATE
	then
		local vLocation = J.GetLocationTowardDistanceLocation(bot, GetAncient(GetTeam()):GetLocation(), nCastRange)
		local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1200)

		if  bot:DistanceFromFountain() > 900
		and IsLocationPassable(vLocation)
		and (#nInRangeAlly <= 1
			or bot:GetActiveModeDesire() > BOT_MODE_DESIRE_VERYHIGH * 0.9)
		and nInRangeEnemy ~= nil and #nInRangeEnemy >= 1
		then
			return BOT_ACTION_DESIRE_HIGH, vLocation, 'ground', nil
		end
	end

	nInRangeAlly = bot:GetNearbyHeroes(1600, false, BOT_MODE_ATTACK)

	if #nInRangeAlly <= 1 and (botTarget == nil or not botTarget:IsHero())
	and J.IsFarming(bot)
	and not bot:WasRecentlyDamagedByAnyHero(3.1)
	and not J.IsPushing(bot)
	and not J.IsDefending(bot)
	then
		local nAOELocation = bot:FindAoELocation(true, false, bot:GetLocation(), nCastRange, 500, 0, 0)
		local nEnemyLaneCreeps = bot:GetNearbyLaneCreeps(1600, true)
		local nInRangeEnemy = J.GetEnemiesNearLoc(nAOELocation.targetloc, 1600)

		if  nEnemyLaneCreeps ~= nil and #nEnemyLaneCreeps >= 4
		and nInRangeEnemy ~= nil and #nInRangeEnemy == 0
		and nAOELocation.count >= 4
		then
			local bCenter = J.GetCenterOfUnits(nEnemyLaneCreeps)
			local bDist = GetUnitToLocationDistance(bot, bCenter)
			local vLocation = J.GetLocationTowardDistanceLocation(bot, bCenter, bDist + 550)
			local bLocation = J.GetLocationTowardDistanceLocation(bot, bCenter, bDist - 300)

			if bDist > nCastRange then bLocation = J.GetLocationTowardDistanceLocation(bot, bCenter, nCastRange) end

			if  IsLocationPassable(bLocation)
			and GetUnitToLocationDistance(bot, bLocation) > 600
			and IsLocationVisible(vLocation)
			and not J.IsLocHaveTower(700, true, bLocation)
			then
				return BOT_ACTION_DESIRE_HIGH, bLocation, 'ground', nil
			end
		end
	end

	if  J.IsProjectileIncoming(bot, 1200)
	and (botTarget == nil
		or not botTarget:IsHero()
		or not J.IsInRange(bot, botTarget, bot:GetAttackRange() + 100))
	then
		local loc = J.GetLocationTowardDistanceLocation(bot, GetAncient(GetTeam()):GetLocation(), 1199)
		return BOT_ACTION_DESIRE_HIGH, loc, 'ground', nil
	end

	if J.IsGoingOnSomeone(bot) then
		-- for their queued spell combos
		if  bot.shouldBlink ~= nil
		and bot.shouldBlink
		and (botName == 'npc_dota_hero_batrider'
			or botName == 'npc_dota_hero_beastmaster'
			or botName == 'npc_dota_hero_dark_seer'
			or botName == 'npc_dota_hero_earthshaker'
			or botName == 'npc_dota_hero_magnataur'
			or botName == 'npc_dota_hero_rubick'
			-- or botName == 'npc_dota_hero_tinker'
			or botName == 'npc_dota_hero_tiny'
			or botName == 'npc_dota_hero_treant')
		then
			return BOT_ACTION_DESIRE_NONE
		end

		if botName == 'npc_dota_hero_nevermore' then
			local RequiemOfSouls = bot:GetAbilityByName('nevermore_requiem')
			if J.CanCastAbility(RequiemOfSouls) then
				return BOT_ACTION_DESIRE_NONE
			end
		end

		if  J.IsValidTarget(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange)
		and J.CanBeAttacked(botTarget)
		and not J.IsInRange(bot, botTarget, 500)
		and not botTarget:HasModifier('modifier_faceless_void_chronosphere_freeze')
		and not botTarget:HasModifier('modifier_enigma_black_hole_pull')
		then
			local reach = botTarget:GetLocation()
			local initiationSpell = botName == 'npc_dota_hero_skeleton_king' and 'skeleton_king_hellfire_blast'
				or botName == 'npc_dota_hero_dragon_knight' and 'dragon_knight_dragon_tail'
				or botName == 'npc_dota_hero_shadow_shaman' and 'shadow_shaman_voodoo'
			if initiationSpell ~= nil then
				local backup = J.GetAvailableFightAllies(bot, reach, 1300)
				local spell = bot:GetAbilityByName(initiationSpell)
				if backup < 1 or not J.CanCastAbility(spell) then return BOT_ACTION_DESIRE_NONE end
				if botName == 'npc_dota_hero_skeleton_king' then
					local reincarnation = bot:GetAbilityByName('skeleton_king_reincarnation')
					local canReincarnate = reincarnation ~= nil and reincarnation:IsTrained()
						and reincarnation:GetCooldownTimeRemaining() <= 0
						and bot:GetMana() >= reincarnation:GetManaCost() + spell:GetManaCost()
					if not canReincarnate and backup < 2 then return BOT_ACTION_DESIRE_NONE end
				end
			end
			local nInRangeAlly = J.GetAlliesNearLoc(botTarget:GetLocation(), 1200)
			local nInRangeEnemy = J.GetEnemiesNearLoc(botTarget:GetLocation(), 1200)
			local bWeAreStronger = J.WeAreStronger(bot, 1200)
			local nNearbyEnemyHeroCount = 0
			for _, id in pairs(GetTeamPlayers(GetOpposingTeam())) do
				if IsHeroAlive(id) then
					local info = GetHeroLastSeenInfo(id)
					if info ~= nil then
						local dInfo = info[1]
						if dInfo ~= nil and dInfo.time_since_seen < 3.0 and GetUnitToLocationDistance(botTarget, dInfo.location) <= 1200 then
							nNearbyEnemyHeroCount = nNearbyEnemyHeroCount + 1
						end
					end
				end
			end

			if (#nInRangeAlly >= nNearbyEnemyHeroCount and bWeAreStronger) then
				local nDistance = Min(nCastRange, GetUnitToUnitDistance(bot, botTarget))
				local vLocation = J.GetUnitTowardDistanceLocation(bot, botTarget, nDistance) + RandomVector(150)
				if (initiationSpell == nil and IsLocationPassable(vLocation))
					or (initiationSpell ~= nil and IsSafeCombatLanding(bot, vLocation)) then
					return BOT_ACTION_DESIRE_HIGH, vLocation, 'ground', nil
				end
			end
		end
	end

	if J.IsDoingTormentor(bot) and not J.IsRealInvisible(bot) then
		local vTormentorLocation = J.GetTormentorLocation(GetTeam())
		if GetUnitToLocationDistance(bot, vTormentorLocation) > 2000 then
			local vLocation = J.VectorTowards(bot:GetLocation(), vTormentorLocation, nCastRange)
			local nInRangeEnemy = J.GetEnemiesNearLoc(vLocation, 1200)
			if IsLocationPassable(vLocation) and #nInRangeEnemy == 0 then
				return BOT_ACTION_DESIRE_HIGH, vLocation, 'ground', nil
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

--盛世闪光
X.ConsiderItemDesire["item_overwhelming_blink"] = function( hItem )

	return X.ConsiderItemDesire["item_blink"]( hItem )

end

--迅疾闪光
X.ConsiderItemDesire["item_swift_blink"] = function( hItem )

	return X.ConsiderItemDesire["item_blink"]( hItem )

end

--秘奥闪光
X.ConsiderItemDesire["item_arcane_blink"] = function( hItem )

	return X.ConsiderItemDesire["item_blink"]( hItem )

end


--奶酪
X.ConsiderItemDesire["item_cheese"] = function( hItem )

	if bot:DistanceFromFountain() < 1200 then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 800
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	local nLostHealth = bot:GetMaxHealth() - bot:GetHealth()
	local botHP = bot:GetHealth() / bot:GetMaxHealth()
	local nLostMana = bot:GetMaxMana() - bot:GetMana()
	local botMP = bot:GetMana() / bot:GetMaxMana()


	if ( nLostHealth > 2500 and nLostMana > 1500 )
		or ( nLostHealth > 2000 and nLostHealth + nLostMana > 3000 )
		or ( botHP < 0.4 and botMP < 0.4 )
		or ( botHP < 0.2 )
		or ( botMP < 0.06 )
	then
		if J.IsGoingOnSomeone( bot )
		then
			if J.IsValidHero( botTarget )
				and J.IsInRange( bot, botTarget, 2000 )
				and J.CanCastOnMagicImmune( botTarget )
			then
				hEffectTarget = bot
				sCastMotive = "进攻"
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end

		if J.IsRetreating( bot )
			and bot:WasRecentlyDamagedByAnyHero( 4.0 )
		then
			hEffectTarget = bot
			sCastMotive = "撤退"
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--血精石
-- 7.41: Bloodstone active (Blood Pact) - increases spell lifesteal to 60% for the duration, self-cast
X.ConsiderItemDesire["item_bloodstone"] = function( hItem )

	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE )

	-- Don't use when silenced or mana too low
	if bot:IsSilenced() or bot:GetMana() < hItem:GetManaCost() then
		return BOT_ACTION_DESIRE_NONE
	end

	-- Don't use when no enemies nearby (wasted)
	if #nInRangeEnmyList == 0 and not J.IsDoingRoshan(bot) and not J.IsDoingTormentor(bot) then
		return BOT_ACTION_DESIRE_NONE
	end

	-- Use in teamfights with enemies nearby
	if J.IsInTeamFight( bot, 1200 ) and #nInRangeEnmyList >= 2
	then
		hEffectTarget = bot
		sCastMotive = 'Bloodstone: teamfight spell lifesteal'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	-- Use when going on someone and enemies within 1200
	if J.IsGoingOnSomeone( bot ) and #nInRangeEnmyList >= 1
	then
		hEffectTarget = bot
		sCastMotive = 'Bloodstone: going on target with spell lifesteal'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	-- Use when doing Roshan/Tormentor for sustain
	if J.IsDoingRoshan(bot) or J.IsDoingTormentor(bot)
	then
		hEffectTarget = bot
		sCastMotive = 'Bloodstone: Roshan/Tormentor sustain'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end


--血棘
X.ConsiderItemDesire["item_bloodthorn"] = function( hItem )

	return X.ConsiderItemDesire["item_orchid"]( hItem )

end

--魔瓶
X.ConsiderItemDesire["item_bottle"] = function( hItem )

	if hItem:GetCurrentCharges() == 0
		or bot:HasModifier( "modifier_bottle_regeneration" )
	then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 400 + aetherRange
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nLostMana = bot:GetMaxMana() - bot:GetMana()
	local nLostHealth = bot:OriginalGetMaxHealth() - bot:OriginalGetHealth()


	--泉水喝
	if bot:HasModifier( "modifier_fountain_aura" )
	then
		hEffectTarget = bot
		sCastMotive = "在泉水里喝"
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	--自己喝
	if not bot:WasRecentlyDamagedByAnyHero( 3.0 )
	then
		if nLostHealth > 150 and nLostMana > 90
		then
			hEffectTarget = bot
			sCastMotive = "补血补篮"
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end

		if nLostHealth > 500 and J.GetHP( bot ) < 0.5
		then
			hEffectTarget = bot
			sCastMotive = "只补血"
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end

		if nLostMana > 280 and J.GetMP( bot ) < 0.4
		then
			hEffectTarget = bot
			sCastMotive = "只补篮"
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end


	return BOT_ACTION_DESIRE_NONE

end


--小净化
X.ConsiderItemDesire["item_clarity"] = function( hItem )

	if bot:DistanceFromFountain() < 2000 then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 800 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.GetMP( bot ) < 0.4
		and not bot:HasModifier( "modifier_clarity_potion" )
		and #nInRangeEnmyList == 0
		and not bot:WasRecentlyDamagedByAnyHero( 4.0 )
		and not bot:WasRecentlyDamagedByTower(3)
	then
		hEffectTarget = bot
		sCastMotive = '净化自己'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if #nInRangeEnmyList == 0 
	then
		local hAllyList = J.GetNearbyHeroes(bot, 600, false, BOT_MODE_NONE )
		local hNeedManaAlly = nil
		local nNeedManaAllyMana = 99999
		for _, npcAlly in pairs( hAllyList )
		do
			if J.IsValid( npcAlly )
				and npcAlly ~= bot
				and not npcAlly:IsIllusion()
				and not npcAlly:IsChanneling()
				and not npcAlly:HasModifier( "modifier_clarity_potion" )
				and not npcAlly:WasRecentlyDamagedByAnyHero( 4.0 )
				and not npcAlly:WasRecentlyDamagedByTower(3)
				and #npcAlly:GetNearbyHeroes(800, true, BOT_MODE_NONE) == 0
				and (npcAlly:GetMaxMana() - npcAlly:GetMana() > 350
					or (J.IsInLaningPhase(npcAlly) and J.GetLaningManaShortfall(npcAlly, 5) ~= nil))
			then
				if( npcAlly:GetMana() < nNeedManaAllyMana )
				then
					hNeedManaAlly = npcAlly
					nNeedManaAllyMana = npcAlly:GetMana()
				end
			end
		end
		if( hNeedManaAlly ~= nil )
		then
			hEffectTarget = hNeedManaAlly
			sCastMotive = '净化队友:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--赤红甲
X.ConsiderItemDesire["item_crimson_guard"] = function( hItem )

	if bot:DistanceFromFountain() < 400 then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 1200
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	local hNearbyAllyList = J.GetAllyList( bot, nCastRange )

	for _, npcAlly in pairs( hNearbyAllyList )
	do
		if J.IsValid( npcAlly )
			and npcAlly:OriginalGetHealth() / npcAlly:OriginalGetMaxHealth() < 0.8
			and npcAlly:WasRecentlyDamagedByAnyHero( 2.0 )
			and not npcAlly:HasModifier( "modifier_item_crimson_guard_nostack" )
			and #hNearbyEnemyHeroList > 0
		then
			hEffectTarget = npcAlly
			sCastMotive = '救救队友:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end


	local nNearbyEnemyHeroes = J.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE )
	local nNearbyEnemyTowers = bot:GetNearbyTowers( 800, true )
	if #hNearbyAllyList >= 2
		and ( #nNearbyEnemyHeroes + #nNearbyEnemyTowers >= 2 or #nNearbyEnemyHeroes >= 2 )
	then
		for _, npcAlly in pairs( hNearbyAllyList )
		do
			if npcAlly:WasRecentlyDamagedByAnyHero( 2.0 )
				and not npcAlly:HasModifier( "modifier_item_crimson_guard_nostack" )
			then
				hEffectTarget = npcAlly
				sCastMotive = '保护队友:'..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end


	return BOT_ACTION_DESIRE_NONE

end


--吹风
X.ConsiderItemDesire["item_cyclone"] = function( hItem )

	local nCastRange = 650 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	if bot:HasModifier('modifier_nyx_assassin_vendetta')
	then
		return BOT_ACTION_DESIRE_NONE
	end

	if J.IsValid( botTarget )
		and J.CanCastOnNonMagicImmune( botTarget )
		and X.IsWithoutSpellShield( botTarget )
		and J.IsInRange( bot, botTarget, nCastRange + 200 )
	then
		---- Invoker combo with item_cyclone ----
		if botName == "npc_dota_hero_invoker" and J.IsGoingOnSomeone(bot) then
			if J.IsValidHero(botTarget)
			and not J.IsSuspiciousIllusion(botTarget)
			and J.GetMP(bot) > 0.5
			and not Banish.ShouldHoldEnemyBanish(bot, botTarget, J, "SETUP_COMBO") then
				-- Should check if the target is already stuned etc.
				hEffectTarget = botTarget
				sCastMotive = '预设连招:'..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end

		-- 别帮电脑减伤害/解状态
		if botTarget:HasModifier( 'modifier_invoker_cold_snap_freeze' ) 
		or botTarget:HasModifier('modifier_invoker_cold_snap') 
		or botTarget:HasModifier('modifier_invoker_chaos_meteor_burn') then
			return BOT_ACTION_DESIRE_NONE
		end

		---- Above for Invoker combo with item_cyclone ----


		if botTarget:HasModifier( 'modifier_teleporting' )
			 or botTarget:HasModifier( 'modifier_abaddon_borrowed_time' )
			 or botTarget:HasModifier( "modifier_ursa_enrage" )
			 or botTarget:HasModifier( "modifier_item_satanic_unholy" )
			 or botTarget:IsChanneling()
		then
			hEffectTarget = botTarget
			sCastMotive = '驱散Buff:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end

		if J.GetHP( botTarget ) > 0.49 and J.IsCastingUltimateAbility( botTarget )
		then
			hEffectTarget = botTarget
			sCastMotive = '打断大招:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end

		if J.IsRunning( botTarget ) and botTarget:GetCurrentMovementSpeed() > 440
		and not Banish.ShouldHoldEnemyBanish(bot, botTarget, J, "STOP_ESCAPE")
		then
			hEffectTarget = botTarget
			sCastMotive = '阻止逃跑:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	if J.CanCastOnNonMagicImmune( bot )
		and #hNearbyEnemyHeroList > 0
	then
		if J.GetHP(bot) < 0.2 and bot:WasRecentlyDamagedByAnyHero( 3.0 )
		then
			hEffectTarget = bot
			sCastMotive = '撤退:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end

		if bot:IsRooted()
			or ( bot:GetPrimaryAttribute() == ATTRIBUTE_INTELLECT and bot:IsSilenced() )
		then
			hEffectTarget = bot
			sCastMotive = '解缠绕:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end

		if J.IsUnitTargetProjectileIncoming( bot, 800 )
		then
			hEffectTarget = bot
			sCastMotive = '防御弹道:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--风之杖
X.ConsiderItemDesire["item_wind_waker"] = function( hItem )

	return X.ConsiderItemDesire["item_cyclone"]( hItem )

end


--大根
-- 7.41: Dagon no longer instakills non-ancient creeps and no longer heals the user.
-- Only target heroes with Dagon.
X.ConsiderItemDesire["item_dagon"] = function( hItem )

	local nCastRange = hItem:GetCastRange() + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange + 100, true, BOT_MODE_NONE )
	local nDamage = hItem:GetSpecialValueInt( "damage" )

	if bot:HasModifier('modifier_nyx_assassin_vendetta')
	then
		return BOT_ACTION_DESIRE_NONE
	end

	--击杀
	for _, npcEnemy in pairs( nInRangeEnmyList )
	do
		if J.IsValidHero( npcEnemy )
			and J.CanCastOnNonMagicImmune( npcEnemy )
			and X.IsWithoutSpellShield( npcEnemy )
			and J.CanKillTarget( npcEnemy, nDamage, DAMAGE_TYPE_MAGICAL )
		then
			hEffectTarget = npcEnemy
			sCastMotive = "击杀:"..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	--攻击
	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and J.CanCastOnNonMagicImmune( botTarget )
			and X.IsWithoutSpellShield( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
		then
			hEffectTarget = botTarget
			sCastMotive = "进攻:"..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

X.ConsiderItemDesire["item_dagon_2"] = function( hItem )

	return X.ConsiderItemDesire["item_dagon"]( hItem )

end

X.ConsiderItemDesire["item_dagon_3"] = function( hItem )

	return X.ConsiderItemDesire["item_dagon"]( hItem )

end

X.ConsiderItemDesire["item_dagon_4"] = function( hItem )

	return X.ConsiderItemDesire["item_dagon"]( hItem )

end

X.ConsiderItemDesire["item_dagon_5"] = function( hItem )

	return X.ConsiderItemDesire["item_dagon"]( hItem )

end

--散失
X.ConsiderItemDesire["item_diffusal_blade"] = function( hItem )

	local nCastRange = 630 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if( nMode == BOT_MODE_RETREAT )
	then
		for _, npcEnemy in pairs( hNearbyEnemyHeroList )
		do
			if J.IsValid( npcEnemy )
				and J.IsMoving( npcEnemy )
				and J.IsInRange( npcEnemy, bot, nCastRange )
				and bot:WasRecentlyDamagedByHero( npcEnemy, 4.0 )
				and npcEnemy:GetCurrentMovementSpeed() > 200
				and J.CanCastOnNonMagicImmune( npcEnemy )
				and X.IsWithoutSpellShield( npcEnemy )
				and not J.IsDisabled( npcEnemy ) 
			then
				hEffectTarget = npcEnemy
				sCastMotive = "撤退:"..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and J.IsMoving( botTarget )
			and botTarget:GetCurrentMovementSpeed() > 200
			and J.IsInRange( botTarget, bot, nCastRange )
			and J.CanCastOnNonMagicImmune( botTarget )
			and X.IsWithoutSpellShield( botTarget )
			and not J.IsDisabled( botTarget ) 
		then
			hEffectTarget = botTarget
			sCastMotive = "进攻:"..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	local npcEnemy = hNearbyEnemyHeroList[1]
	if J.IsValidHero( npcEnemy )
		and J.IsInRange( bot, npcEnemy, nCastRange - 100 )
		and J.CanCastOnNonMagicImmune( npcEnemy )
		and X.IsWithoutSpellShield( npcEnemy )
		and not J.IsDisabled( npcEnemy )
		and J.IsMoving( npcEnemy )
		and J.IsRunning( npcEnemy )
		and npcEnemy:GetCurrentMovementSpeed() > bot:GetCurrentMovementSpeed() * 0.8
	then
		hEffectTarget = npcEnemy
		sCastMotive = '减速:'..J.Chat.GetNormName( hEffectTarget )
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end


--芒果
X.ConsiderItemDesire["item_enchanted_mango"] = function( hItem )

	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil

	if bot:GetMana() < 150
	then
		hEffectTarget = bot
		sCastMotive = '自己吃'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end


--虚灵
X.ConsiderItemDesire["item_ethereal_blade"] = function( hItem )

	local nCastRange = 800 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and J.CanCastOnNonMagicImmune( botTarget )
			and J.CanCastOnTargetAdvanced( botTarget )
			and not J.IsInEtherealForm( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
			and not HasAllyAttackCommitment(botTarget, false)
		then
			hEffectTarget = botTarget
			sCastMotive = "进攻"..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--心火
X.ConsiderItemDesire["item_faerie_fire"] = function( hItem )

	if bot:DistanceFromFountain() < 1800 then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 300 + aetherRange
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if nMode == BOT_MODE_RETREAT
		 and bot:GetActiveModeDesire() >= BOT_MODE_DESIRE_HIGH
		 and bot:WasRecentlyDamagedByAnyHero( 3.0 )
		 and bot:OriginalGetHealth() < 90
	then
		hEffectTarget = bot
		sCastMotive = "撤退"
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	--攻击
	if J.IsGoingOnSomeone( bot )
		and J.GetHP( bot ) < 0.3
		and J.IsValidHero( botTarget )
		and bot:WasRecentlyDamagedByAnyHero( 3.0 )
	then
		hEffectTarget = bot
		sCastMotive = "进攻"
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	--自己吃
	if DotaTime() > 10 * 60
		and hItem:GetName() == "item_faerie_fire"
		and bot:GetItemInSlot( 6 ) ~= nil
		and bot:GetMaxHealth() - bot:OriginalGetHealth() > 200
	then
		hEffectTarget = bot
		sCastMotive = '自己吃'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--大药
X.ConsiderItemDesire["item_flask"] = function( hItem )

	if bot:DistanceFromFountain() < 2300 then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 900
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	local laning = J.IsInLaningPhase(bot)
	local selfMissing = bot:OriginalGetMaxHealth() - bot:OriginalGetHealth()
	if (selfMissing > 500 or (laning and J.GetHP(bot) < 0.65 and selfMissing >= 200))
		and #nInRangeEnmyList == 0
		and not bot:WasRecentlyDamagedByAnyHero( 2.2 )
		and not bot:WasRecentlyDamagedByTower(2.2)
		and not bot:HasModifier( "modifier_filler_heal" )
		and not bot:HasModifier( "modifier_elixer_healing" )
		and not bot:HasModifier( "modifier_flask_healing" )
		and not bot:HasModifier( "modifier_juggernaut_healing_ward_heal" )
	then
		hEffectTarget = bot
		sCastMotive = '自己吃'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	local hAllyList = J.GetAlliesNearLoc( bot:GetLocation(), 700 )
	local hNeedHealAlly = nil
	local nNeedHealAllyHealth = 99999
	for _, npcAlly in pairs( hAllyList )
	do
		if J.IsValid( npcAlly ) and npcAlly ~= bot
			and not npcAlly:HasModifier( "modifier_filler_heal" )
			and not npcAlly:HasModifier( "modifier_elixer_healing" )
			and not npcAlly:HasModifier( "modifier_flask_healing" )
			and not npcAlly:HasModifier( "modifier_juggernaut_healing_ward_heal" )
			and not npcAlly:WasRecentlyDamagedByAnyHero( 3.0 )
			and not npcAlly:IsIllusion()
			and not npcAlly:IsChanneling()
			and (npcAlly:OriginalGetMaxHealth() - npcAlly:OriginalGetHealth() > 550
				or (laning and J.GetHP(npcAlly) < 0.55 and npcAlly:OriginalGetMaxHealth() - npcAlly:OriginalGetHealth() >= 250))
			and not npcAlly:WasRecentlyDamagedByTower(3)
			and #npcAlly:GetNearbyHeroes(800, true, BOT_MODE_NONE) == 0
		then
			if( npcAlly:OriginalGetHealth() < nNeedHealAllyHealth )
			then
				hNeedHealAlly = npcAlly
				nNeedHealAllyHealth = npcAlly:OriginalGetHealth()
			end
		end
	end
	if hNeedHealAlly ~= nil and #hNearbyEnemyHeroList == 0
	then
		hEffectTarget = hNeedHealAlly
		sCastMotive = '给队友贴:'..J.Chat.GetNormName( hEffectTarget )
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

-- Healing Lotus helper (item_famango / item_great_famango / item_greater_famango)
-- All three restore HP+mana and can target allies. Differ by thresholds and priority.
-- Thresholds use REMAINING ratios (0.0-1.0) not absolute missing values, because
-- a hero at 30% HP is critical regardless of their max HP pool.
local function ConsiderHealingLotus(hItem, sLabel, nSelfHPRatio, nSelfMPRatio, nAllyHPRatio, nFountainDist, bCoresDrop, bEmergency, bPrioritizeCores)
	if bot:DistanceFromFountain() < nFountainDist then return BOT_ACTION_DESIRE_NONE end

	local sCastType = 'unit'
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, 900, true, BOT_MODE_NONE)
	local botHP = J.GetHP(bot)
	local botMP = bot:GetMaxMana() > 0 and (bot:GetMana() / bot:GetMaxMana()) or 1

	-- Cores drop normal/great lotus after 30min (not worth the slot late game)
	if bCoresDrop and DotaTime() > 30 * 60 and J.IsCore(bot) then
		return BOT_ACTION_DESIRE_NONE
	end

	-- Emergency self-use in combat (greater lotus only)
	if bEmergency then
		if botHP < 0.35 or (botHP < 0.5 and botMP < 0.3) then
			if J.IsRetreating(bot) or J.IsGoingOnSomeone(bot) or #nInRangeEnmyList >= 1 then
				return BOT_ACTION_DESIRE_HIGH, bot, sCastType, 'Emergency self ('..sLabel..')'
			end
		end
	end

	-- Use on self when safe and HP or mana is below threshold
	if (botHP < nSelfHPRatio or botMP < nSelfMPRatio)
		and #nInRangeEnmyList == 0
		and not bot:WasRecentlyDamagedByAnyHero(2.2)
		and not bot:HasModifier("modifier_flask_healing")
		and not bot:HasModifier("modifier_filler_heal")
	then
		return BOT_ACTION_DESIRE_HIGH, bot, sCastType, 'Self heal ('..sLabel..')'
	end

	-- Use on nearby ally who is low on HP
	local hAllyList = J.GetAlliesNearLoc(bot:GetLocation(), 700)
	local hBestAlly = nil
	local nBestScore = 0
	for _, npcAlly in pairs(hAllyList) do
		if J.IsValid(npcAlly) and npcAlly ~= bot
			and not npcAlly:IsIllusion()
			and not npcAlly:HasModifier("modifier_flask_healing")
			and not npcAlly:HasModifier("modifier_filler_heal")
			and (bEmergency or not npcAlly:WasRecentlyDamagedByAnyHero(3.0))
		then
			local nAllyHP = npcAlly:GetHealth() / npcAlly:GetMaxHealth()
			local nAllyMP = npcAlly:GetMaxMana() > 0 and (npcAlly:GetMana() / npcAlly:GetMaxMana()) or 1
			if nAllyHP < nAllyHPRatio or nAllyMP < nAllyHPRatio then
				-- Score: lower HP = higher priority. Cores get bonus.
				local nScore = (1 - nAllyHP) + (1 - nAllyMP) * 0.5
				if bPrioritizeCores and J.IsCore(npcAlly) then nScore = nScore * 1.5 end
				if nScore > nBestScore then
					hBestAlly = npcAlly
					nBestScore = nScore
				end
			end
		end
	end
	if hBestAlly ~= nil and (bEmergency or #nInRangeEnmyList == 0) then
		return BOT_ACTION_DESIRE_HIGH, hBestAlly, sCastType, 'Heal ally ('..sLabel..'): '..J.Chat.GetNormName(hBestAlly)
	end

	return BOT_ACTION_DESIRE_NONE
end

--[[
  Ally scoring uses (1 - HP%) + (1 - MP%) * 0.5 — a hero at 20% HP and 50% MP scores much higher than one at 80% HP and 10% MP, reflecting that HP is more critical than mana.
  ┌────────────────────────┬───────┬─────────────┬───────────────────────────────┐
  │                        │ Lotus │ Great Lotus │         Greater Lotus         │
  ├────────────────────────┼───────┼─────────────┼───────────────────────────────┤
  │ Self use when HP below │ 70%   │ 60%         │ 50%                           │
  ├────────────────────────┼───────┼─────────────┼───────────────────────────────┤
  │ Self use when MP below │ 50%   │ 40%         │ 30%                           │
  ├────────────────────────┼───────┼─────────────┼───────────────────────────────┤
  │ Ally use when HP below │ 60%   │ 50%         │ 50%                           │
  ├────────────────────────┼───────┼─────────────┼───────────────────────────────┤
  │ Emergency combat use   │ no    │ no          │ yes (HP<35% or HP<50%+MP<30%) │
  ├────────────────────────┼───────┼─────────────┼───────────────────────────────┤
  │ Prioritize cores       │ no    │ no          │ yes (1.5x score)              │
  ├────────────────────────┼───────┼─────────────┼───────────────────────────────┤
  │ Cores drop after 30min │ yes   │ yes         │ no                            │
  └────────────────────────┴───────┴─────────────┴───────────────────────────────┘
]]
X.ConsiderItemDesire["item_famango"]         = function(h) return ConsiderHealingLotus(h, "lotus",         0.7, 0.5, 0.6, 3000, true,  false, false) end
X.ConsiderItemDesire["item_great_famango"]   = function(h) return ConsiderHealingLotus(h, "great lotus",   0.6, 0.4, 0.5, 3000, true,  false, false) end
X.ConsiderItemDesire["item_greater_famango"] = function(h) return ConsiderHealingLotus(h, "greater lotus", 0.5, 0.3, 0.5, 1200, false, true,  true)  end

--推推
local function IsBeingDisplaced(unit)
    local elapsed = unit.ohaItemPushTime ~= nil and DotaTime() - unit.ohaItemPushTime or math.huge
    return unit:HasModifier('modifier_item_forcestaff_active')
        or (elapsed >= 0 and elapsed < 0.5)
end

local function RecordItemPush(unit)
    unit.ohaItemPushTime = DotaTime()
end

local function ConsiderForceItem(item, allyOnly)
    if bot:HasModifier('modifier_nyx_assassin_vendetta') or IsBeingDisplaced(bot) then return BOT_ACTION_DESIRE_NONE end
    local allyRange = item:GetCastRange() + aetherRange
    local pushLength = item:GetSpecialValueInt('push_length')
    if pushLength <= 0 then return BOT_ACTION_DESIRE_NONE end

    local preserveSelf = false
    if allyOnly and J.IsCore(bot) then
        local threats = GetCombatPursuers(bot, 1400)
        preserveSelf = J.ShouldRetreatFromEnemyReinforcements(bot)
            or (#threats > 0 and (J.IsRetreating(bot) or bot:WasRecentlyDamagedByAnyHero(2)
                or EarliestPursuitContact(bot, threats) <= 1.25))
    end
    local bestAlly, bestDesire, bestMotive, emergency = nil, 0, nil, nil
    for _, ally in ipairs(J.GetAlliesNearLoc(bot:GetLocation(), allyRange)) do
        if J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally) and not ally:IsChanneling()
        and (not preserveSelf or ally == bot)
        and not ally:HasModifier('modifier_teleporting') and not ally:HasModifier('modifier_item_nullifier_mute')
        and not IsBeingDisplaced(ally)
        and J.IsInRange(bot, ally, allyRange) then
            local pursuers = GetCombatPursuers(ally, 1200)
            local stuck = J.IsStuck(ally) or ally:HasModifier('modifier_furion_sprout_damage')
            local retreating = (J.IsRetreating(ally) or (ally == bot and preserveSelf)) and #pursuers > 0
            if stuck or retreating then
                local landing = J.GetFaceTowardDistanceLocation(ally, pushLength)
                if MakesSpaceFromEnemies(ally, landing, pursuers)
                and (not retreating or J.GetDistance(landing, J.GetEscapeLoc()) < GetUnitToLocationDistance(ally, J.GetEscapeLoc())) then
                    local desire = 0.85 + 0.14 * (1 - J.GetHP(ally))
                    if desire > bestDesire then
                        bestAlly, bestDesire, bestMotive = ally, desire, retreating and '安全推出追击范围' or '安全脱离地形'
                        emergency = ally == bot and (retreating or #pursuers > 0) and 'revealed' or nil
                    end
                end
            elseif J.IsGoingOnSomeone(ally) and not HasItemConcealment(ally) then
                local target = J.GetProperTarget(ally)
                if J.IsValidHero(target) and J.CanBeAttacked(target) then
                    local landing = J.GetFaceTowardDistanceLocation(ally, pushLength)
                    local distance = GetUnitToUnitDistance(ally, target)
                    if distance > ally:GetAttackRange() + 75 and GetUnitToLocationDistance(target, landing) + 200 < distance
                    and IsSafeCombatLanding(ally, landing) and J.GetAvailableFightAllies(bot, landing, 1000) >= 1
                    and #J.GetEnemiesNearLoc(landing, 800) < 3 and bestDesire < 0.55 then
                        bestAlly, bestDesire, bestMotive, emergency = ally, 0.55, '有队友跟进时协助接战', nil
                    end
                end
            end
        end
    end

    if bestAlly ~= nil then
        return bestDesire, bestAlly, 'unit', bestMotive, function() RecordItemPush(bestAlly) end, emergency
    end
    if allyOnly then return BOT_ACTION_DESIRE_NONE end

    local enemyRange = item:GetSpecialValueInt('enemy_cast_range') + aetherRange
    if enemyRange > aetherRange and J.IsGoingOnSomeone(bot) and J.IsValidHero(botTarget)
    and J.IsInRange(bot, botTarget, enemyRange) and J.CanCastOnNonMagicImmune(botTarget)
    and X.IsWithoutSpellShield(botTarget) and not IsBeingDisplaced(botTarget) then
        local landing = J.GetFaceTowardDistanceLocation(botTarget, pushLength)
        if GetUnitToLocationDistance(bot, landing) + 200 < GetUnitToUnitDistance(bot, botTarget)
        and J.GetAvailableFightAllies(bot, landing, 800) >= 2 then
            local target = botTarget
            return 0.55, target, 'unit', '把目标推向队友', function() RecordItemPush(target) end
        end
    end
    return BOT_ACTION_DESIRE_NONE
end

X.ConsiderItemDesire['item_force_staff'] = ConsiderForceItem
X.ConsiderItemDesire['item_caduceus'] = ConsiderForceItem


--绿杖
local function ConsiderGhostForm()
	if J.IsInEtherealForm(bot) or HasIncomingCombatSpell(bot, 650, 'magic') then return BOT_ACTION_DESIRE_NONE end
	local target = bot:GetAttackTarget()
	if bot:HasModifier('modifier_item_satanic_unholy') and J.IsValidHero(target)
		and J.CanBeAttacked(target) and J.IsInRange(bot, target, bot:GetAttackRange() + 100)
	then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 800
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if bot:GetAttackTarget() == nil
		or bot:GetHealth() < 500
	then
		for _, npcEnemy in pairs( hNearbyEnemyHeroList )
		do
			if J.IsValidHero( npcEnemy )
				and J.CanCastOnMagicImmune( npcEnemy )
				and J.IsInRange( bot, npcEnemy, npcEnemy:GetAttackRange() + 100 )
				and npcEnemy:GetAttackTarget() == bot
				and bot:WasRecentlyDamagedByHero( npcEnemy, 2.0 )
				and npcEnemy:GetAttackDamage() > bot:GetAttackDamage()
			then
				hEffectTarget = npcEnemy
				sCastMotive = "撤退"..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

X.ConsiderItemDesire['item_ghost'] = ConsiderGhostForm
--克雷拉斯权杖 (Crellas's Crozier - self-cast ghost form)
X.ConsiderItemDesire['item_crellas_crozier'] = ConsiderGhostForm

--微光
X.ConsiderItemDesire['item_glimmer_cape'] = function(item)
    local range = item:GetCastRange() + aetherRange
    local best, score, motive, emergency = nil, 0, nil, nil
    for _, ally in ipairs(J.GetAlliesNearLoc(bot:GetLocation(), range)) do
        if J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally) and not ally:IsInvulnerable()
        and J.IsInRange(bot, ally, range) and not ally:HasModifier('modifier_fountain_aura')
        and not ally:HasModifier('modifier_item_glimmer_cape_fade') and not HasPendingConcealment(ally, 'item_glimmer_cape')
        and not ally:HasModifier('modifier_item_nullifier_mute') then
            local hp = J.GetHP(ally)
            local criticalMagic = HasIncomingCombatSpell(ally, 650, 'magic') and (hp < 0.65 or J.IsDisabled(ally))
            local underAttack = #GetCombatPursuers(ally, 1000) > 0
            local canConceal = not ally:IsInvisible() and not HasItemConcealment(ally)
                and not J.HasInvisCounterBuff(ally) and #ally:GetNearbyTowers(850, true) == 0
            local canSave = underAttack and canConceal and hp < 0.65
                and (J.IsRetreating(ally) or J.IsDisabled(ally)
                    or (hp < 0.5 and ally:WasRecentlyDamagedByAnyHero(2)))
            if criticalMagic or canSave then
                local desire = (criticalMagic and 0.83 or 0.71) + 0.14 * (1 - hp)
                if desire > score then
                    best, score = ally, desire
                    motive = criticalMagic and '给即将承受魔法伤害的队友护盾' or '掩护被追击的队友'
                    emergency = criticalMagic and ally == bot and hp < 0.35 and 'always' or nil
                end
            end
        end
    end
    if best ~= nil then return score, best, 'unit', motive, nil, emergency end
    return BOT_ACTION_DESIRE_NONE
end


X.ConsiderItemDesire["item_mekansm"] = function( hItem )
	local nCastRange = 1200
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil


	local hAllyList = J.GetAllyList( bot, nCastRange )
	for _, npcAlly in pairs( hAllyList ) 
	do
		if npcAlly ~= nil and npcAlly:IsAlive()
			and J.GetHP( npcAlly ) < 0.45
			and #hNearbyEnemyHeroList > 0
		then
			hEffectTarget = npcAlly
			sCastMotive = '治疗队友'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	local needHPCount = 0
	for _, npcAlly in pairs( hAllyList )
	do
		if npcAlly ~= nil
			and npcAlly:GetMaxHealth()- npcAlly:GetHealth() > 400
		then
			needHPCount = needHPCount + 1

			if needHPCount >= 2 and npcAlly:GetHealth() / npcAlly:GetMaxHealth() < 0.55
			then
				hEffectTarget = npcAlly
				sCastMotive = '治疗二队友:'..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end

			if needHPCount >= 3
			then
				hEffectTarget = npcAlly
				sCastMotive = '治疗多个队友:'..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	if bot:GetHealth() / bot:GetMaxHealth() < 0.5
		or bot:IsSilenced()
		or bot:IsRooted()
		or bot:HasModifier( "modifier_item_urn_damage" )
		or bot:HasModifier( "modifier_item_spirit_vessel_damage" )
	then
		hEffectTarget = bot
		sCastMotive = '治疗自己:'..J.Chat.GetNormName( hEffectTarget )
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE
end

--大鞋
X.ConsiderItemDesire["item_guardian_greaves"] = function( hItem )

	local nCastRange = 1200
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil


	local hAllyList = J.GetAllyList( bot, nCastRange )
	for _, npcAlly in pairs( hAllyList ) 
	do
		if npcAlly ~= nil and npcAlly:IsAlive()
			and J.GetHP( npcAlly ) < 0.45
			and #hNearbyEnemyHeroList > 0
		then
			hEffectTarget = npcAlly
			sCastMotive = '治疗队友'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	local needHPCount = 0
	for _, npcAlly in pairs( hAllyList )
	do
		if npcAlly ~= nil
			and npcAlly:GetMaxHealth()- npcAlly:GetHealth() > 400
		then
			needHPCount = needHPCount + 1

			if needHPCount >= 2 and npcAlly:GetHealth() / npcAlly:GetMaxHealth() < 0.55
			then
				hEffectTarget = npcAlly
				sCastMotive = '治疗二队友:'..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end

			if needHPCount >= 3
			then
				hEffectTarget = npcAlly
				sCastMotive = '治疗多个队友:'..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	if bot:GetHealth() / bot:GetMaxHealth() < 0.5
		or bot:IsSilenced()
		or bot:IsRooted()
		or bot:HasModifier( "modifier_item_urn_damage" )
		or bot:HasModifier( "modifier_item_spirit_vessel_damage" )
	then
		hEffectTarget = bot
		sCastMotive = '治疗自己:'..J.Chat.GetNormName( hEffectTarget )
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	local nNeedMPCount = 0
	for _, npcAlly in pairs( hAllyList )
	do
		if npcAlly ~= nil
			and npcAlly:GetMaxMana()- npcAlly:GetMana() > 400
		then
			nNeedMPCount = nNeedMPCount + 1
		end

		if nNeedMPCount >= 2 and bot:GetMana() / bot:GetMaxMana() < 0.2
		then
			hEffectTarget = npcAlly
			sCastMotive = '回蓝二队友:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end

		if nNeedMPCount >= 3
		then
			hEffectTarget = npcAlly
			sCastMotive = '回蓝多个队友:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end

	end

	local laneCreepList = bot:GetNearbyLaneCreeps( 1200, false )
	if #laneCreepList >= 9
	then
		local nAOELocation = bot:FindAoELocation( false, false, bot:GetLocation(), 100, 1100 , 0, 200 )
		if nAOELocation.count >= 6
			and GetUnitToLocationDistance( bot, nAOELocation.targetloc ) <= 200
		then
			hEffectTarget = bot
			sCastMotive = '治疗小兵们:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--点金
X.ConsiderItemDesire["item_hand_of_midas"] = function( hItem )

	local nCastRange = 990 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil


	if #hNearbyEnemyHeroList >= 1 then nCastRange = 628 end
	local hNearbyCreepList = bot:GetNearbyCreeps( nCastRange, true )
	local targetCreep = nil
	local targetCreepLV = 0

	for _, creep in pairs( hNearbyCreepList )
	do
		if J.IsValid( creep )
		 and not creep:IsMagicImmune()
		 and not creep:IsAncientCreep()
		then
			if creep:GetLevel() > targetCreepLV
			then
				targetCreepLV = creep:GetLevel()
				targetCreep = creep
			end
		end

	end

	if targetCreep ~= nil
	then
		hEffectTarget = targetCreep
		sCastMotive = '点金小兵:'..hEffectTarget:GetUnitName()
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--天堂
X.ConsiderItemDesire["item_heavens_halberd"] = function( hItem )

	-- 7.42 changed Halberd cast range; read the item's current value.
	local nCastRange = hItem:GetCastRange() + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	local targetHero = nil
	local targetHeroDamage = 0
	for _, npcEnemy in pairs( nInRangeEnmyList )
	do
		if J.IsValidHero( npcEnemy )
			and not npcEnemy:IsDisarmed()
			and not J.IsDisabled( npcEnemy )
			and J.CanCastOnNonMagicImmune( npcEnemy )
			and X.IsWithoutSpellShield( npcEnemy )
			and npcEnemy:GetAttackTarget() ~= nil
			and ( npcEnemy:GetPrimaryAttribute() ~= ATTRIBUTE_INTELLECT or npcEnemy:GetAttackDamage() > 180 )
		then
			local nEnemyDamage = npcEnemy:GetEstimatedDamageToTarget( false, bot, 3.0, DAMAGE_TYPE_PHYSICAL )
			if ( nEnemyDamage > targetHeroDamage )
			then
				targetHeroDamage = nEnemyDamage
				targetHero = npcEnemy
			end
		end
	end
	if targetHero ~= nil
	then
		hEffectTarget = targetHero
		sCastMotive = '缴械敌人:'..J.Chat.GetNormName( hEffectTarget )
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if ( bot:GetActiveMode() == BOT_MODE_ROSHAN )
	then
		local botTarget = bot:GetAttackTarget()
		if J.IsRoshan( botTarget )
			and not J.IsDisabled( botTarget )
			and not botTarget:IsDisarmed()
		then
			hEffectTarget = botTarget
			sCastMotive = '缴械肉山'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--支配
X.ConsiderItemDesire["item_helm_of_the_dominator"] = function( hItem )

	local nCastRange = 1000 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil

	for _, unit in pairs(GetUnitList(UNIT_LIST_ALLIED_CREEPS))
	do
		if J.IsValid(unit)
		and unit:HasModifier('modifier_dominated')
		and unit:IsAncientCreep()
		then
			return BOT_ACTION_DESIRE_NONE, hEffectTarget, 'sCastType', sCastMotive
		end
	end

	local maxHP = 0
	local hCreep = nil
	local hNearbyCreepList = bot:GetNearbyCreeps( nCastRange, true )
	if #hNearbyCreepList >= 2
	then
		for _, creep in pairs( hNearbyCreepList )
		do
			if J.IsValid( creep )
			then
				local nCreepHP = creep:GetHealth()
				if nCreepHP > maxHP
					and ( creep:GetHealth() / creep:GetMaxHealth() ) > 0.75
					and not creep:IsAncientCreep()
					and not J.IsKeyWordUnit( "siege", creep )
				then
					hCreep = creep
					maxHP = nCreepHP
				end
			end
		end
	end
	if hCreep ~= nil
	then
		hEffectTarget = hCreep
		sCastMotive = '支配:'..hEffectTarget:GetUnitName()
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end


-- 7.42: Helm of the Overlord was removed; Dominator remains supported.

--挑战
X.ConsiderItemDesire["item_hood_of_defiance"] = function( hItem )

	if bot:HasModifier( 'modifier_item_pipe_barrier' )
		or J.GetHP( bot ) > 0.88
	then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 1000
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if #nInRangeEnmyList > 0
	then
		hEffectTarget = bot
		sCastMotive = '套盾'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end



--圣洁吊坠
X.ConsiderItemDesire["item_holy_locket"] = function( hItem )

	--给队友

	return X.ConsiderItemDesire["item_magic_wand"]( hItem )

end

--大推推
X.ConsiderItemDesire['item_hurricane_pike'] = function(item)
    if IsBeingDisplaced(bot) or bot:HasModifier('modifier_item_nullifier_mute') then return BOT_ACTION_DESIRE_NONE end

    local range = item:GetSpecialValueInt('cast_range_enemy') + aetherRange
    local push = item:GetSpecialValueInt('enemy_length')
    if (J.IsRetreating(bot) or J.ShouldRetreatFromEnemyReinforcements(bot)) and push > 0 and range > aetherRange then
        local pursuers = GetCombatPursuers(bot, 1200)
        local best
        for _, enemy in ipairs(pursuers) do
            local distance = GetUnitToUnitDistance(bot, enemy)
            if distance > 0 and distance <= range and J.CanCastOnNonMagicImmune(enemy)
            and X.IsWithoutSpellShield(enemy) and not IsBeingDisplaced(enemy) then
                local landing = J.Site.GetXUnitsTowardsLocation(bot, enemy:GetLocation(), -push)
                if MakesSpaceFromEnemies(bot, landing, pursuers)
                and J.GetDistance(landing, J.GetEscapeLoc()) < GetUnitToLocationDistance(bot, J.GetEscapeLoc())
                and (best == nil or distance < GetUnitToUnitDistance(bot, best)) then best = enemy end
            end
        end
        if best ~= nil then
            local desire = EarliestPursuitContact(bot, pursuers) < 0.35 and 0.94 or 0.87
            return desire, best, 'unit', '拉开与追击者的距离', function()
                RecordItemPush(bot)
                RecordItemPush(best)
            end, 'revealed'
        end
    elseif push > 0 and range > aetherRange and J.IsGoingOnSomeone(bot) and J.IsValidHero(botTarget)
    and bot:GetAttackTarget() == botTarget and botTarget:GetAttackTarget() == bot
    and botTarget:GetAttackRange() + 150 < bot:GetAttackRange()
    and not HasAllyAttackCommitment(botTarget, true) and J.CanBeAttacked(botTarget)
    and J.CanCastOnNonMagicImmune(botTarget) and X.IsWithoutSpellShield(botTarget) and not IsBeingDisplaced(botTarget) then
        local target = botTarget
        local distance = GetUnitToUnitDistance(bot, target)
        if distance > 0 and distance <= range
        and MakesSpaceFromEnemies(bot, J.Site.GetXUnitsTowardsLocation(bot, target:GetLocation(), -push),
            GetCombatPursuers(bot, 1200)) then
            return 0.75, target, 'unit', '拉开距离继续远程输出', function()
                RecordItemPush(bot)
                RecordItemPush(target)
            end
        end
    end
    return ConsiderForceItem(item, true)
end

--隐刀
X.ConsiderItemDesire["item_invis_sword"] = function( hItem )

	if bot:IsInvisible()
		or HasItemConcealment(bot)
		or #hNearbyEnemyTowerList > 0
		or J.HasInvisCounterBuff(bot)
	then return BOT_ACTION_DESIRE_NONE end

	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil


	if J.IsRetreating( bot )
		and bot:GetActiveModeDesire() > BOT_MODE_DESIRE_MODERATE
		and (#GetCombatPursuers(bot, 1050) > 0 or J.ShouldRetreatFromEnemyReinforcements(bot))
	then
		hEffectTarget = bot
		sCastMotive = '撤退了'
		return 0.92, hEffectTarget, sCastType, sCastMotive
	end

	if J.GetHP( bot ) < 0.166
		and ( #hNearbyEnemyHeroList > 0 or bot:WasRecentlyDamagedByAnyHero( 5.0 ) )
	then
		hEffectTarget = bot
		sCastMotive = '残血了'
		return 0.9, hEffectTarget, sCastType, sCastMotive
	end

	if J.IsGoingOnSomeone( bot )
	then
		if 	J.IsValidHero( botTarget )
			and J.CanCastOnMagicImmune( botTarget )
			and not J.IsInRange( bot, botTarget, botTarget:GetCurrentVisionRange() )
			and J.IsInRange( bot, botTarget, 2600 )
		then
			local hEnemyCreepList = bot:GetNearbyLaneCreeps( 800, true )
			if #hEnemyCreepList == 0 and #hNearbyEnemyHeroList == 0
			then
				hEffectTarget = botTarget
				sCastMotive = "进攻:"..J.Chat.GetNormName( hEffectTarget )
				return 0.65, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--莲花
X.ConsiderItemDesire['item_lotus_orb'] = function(item)
    local range = item:GetCastRange() + aetherRange
    local best, score, motive = nil, 0, nil
    for _, ally in ipairs(J.GetAlliesNearLoc(bot:GetLocation(), range)) do
        if J.IsValidHero(ally) and not J.IsSuspiciousIllusion(ally) and not ally:IsInvulnerable()
        and J.IsInRange(bot, ally, range) and not ally:HasModifier('modifier_item_lotus_orb_active') then
            local hp = J.GetHP(ally)
            local location = ally:GetLocation()
            local remaining = GetDispellableControlTime(ally)
            local underPressure = #GetCombatPursuers(ally, 1050) > 0
            local fighting = J.IsGoingOnSomeone(ally) and #J.GetEnemiesNearLoc(location, 800) > 0
            local reflect = not ally:HasModifier('modifier_antimage_spell_shield') and not ally:HasModifier('modifier_item_sphere_target')
                and not ally:HasModifier('modifier_black_king_bar_immune')
                and (HasIncomingCombatSpell(ally, 650, 'targeted') or HasIncomingTargetedDisable(ally, J.GetEnemiesNearLoc(location, 1000)))
            if remaining > 0.35 and (underPressure or fighting) then
                local desire = 0.86 + 0.1 * (1 - hp)
                if desire > score then best, score, motive = ally, desire, '驱散影响当前行动的控制' end
            elseif reflect then
                local desire = 0.78 + 0.08 * (1 - hp)
                if desire > score then best, score, motive = ally, desire, '反制即将命中的指向技能' end
            end
        end
    end
    if best ~= nil then return score, best, 'unit', motive end
    return BOT_ACTION_DESIRE_NONE
end

local function ShouldSpendLaneStick(item)
	if item:GetCurrentCharges() < 6 or not J.IsInLaningPhase(bot) then return false end
	return (J.CanRecoverWithLaneStick(bot, item, true) or J.CanRecoverWithLaneStick(bot, item, false))
		and J.GetSafeLaneSupplyTower(bot) ~= nil
end

--魔棒
X.ConsiderItemDesire["item_magic_stick"] = function( hItem )

	local nCastRange = 1000
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	local nEnemyCount = #nInRangeEnmyList
	local nHPrate = bot:GetHealth() / bot:GetMaxHealth()
	local nMPrate = bot:GetMana() / bot:GetMaxMana()
	local nCharges = hItem:GetCurrentCharges()

	if nEnemyCount == 0 and ShouldSpendLaneStick(hItem) then
		return BOT_ACTION_DESIRE_HIGH, bot, sCastType, '用魔棒恢复以继续对线'
	end

	if ( nHPrate < 0.5 or nMPrate < 0.3 ) and nEnemyCount >= 1 and nCharges >= 1
	then
		hEffectTarget = bot
		sCastMotive = '用途1'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if ( nHPrate + nMPrate < 1.1 and nCharges >= 7 and nEnemyCount >= 1 )
	then
		hEffectTarget = bot
		sCastMotive = '用途2'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if ( nCharges >= 9 and bot:GetItemInSlot( 6 ) ~= nil and ( nHPrate <= 0.7 or nMPrate <= 0.6 ) )
	then
		hEffectTarget = bot
		sCastMotive = '用途3'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--魔杖
X.ConsiderItemDesire["item_magic_wand"] = function( hItem )

	if hItem:GetCurrentCharges() <= 0 then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 1000
	local sCastType = 'none'
	if hItem:GetName() == 'item_holy_locket' then sCastType = 'unit' end
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	local nEnemyCount = #nInRangeEnmyList
	local nHPrate = bot:GetHealth() / bot:GetMaxHealth()
	local nMPrate = bot:GetMana() / bot:GetMaxMana()
	local nLostHP = bot:GetMaxHealth() - bot:GetHealth()
	local nLostMP = bot:GetMaxMana() - bot:GetMana()
	local nCharges = hItem:GetCurrentCharges()
	if nEnemyCount == 0 and hItem:GetName() == 'item_magic_wand' and ShouldSpendLaneStick(hItem) then
		return BOT_ACTION_DESIRE_HIGH, bot, sCastType, '用魔杖恢复以继续对线'
	end

	if ( ( nHPrate < 0.4 or nMPrate < 0.3 ) and nEnemyCount >= 1 and nCharges >= 1 )
	then
		hEffectTarget = bot
		sCastMotive = '用途1'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if ( nHPrate < 0.7 and nMPrate < 0.7 and nCharges >= 12 and nEnemyCount >= 1 ) 
	then
		hEffectTarget = bot
		sCastMotive = '用途2'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if ( nCharges >= 19 and bot:GetItemInSlot( 6 ) ~= nil and ( nHPrate <= 0.6 or nMPrate <= 0.5 ) ) 
	then
		hEffectTarget = bot
		sCastMotive = '用途3'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if ( nCharges == 20 and nEnemyCount >= 1 and nLostHP > 350 and nLostMP > 350 ) 
	then
		hEffectTarget = bot
		sCastMotive = '用途4'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--分身
X.ConsiderItemDesire["item_manta"] = function( hItem )

	local nCastRange = 800
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	local nNearbyAttackingAlliedHeroes = J.GetNearbyHeroes(bot, 1000, false, BOT_MODE_ATTACK )
	local nNearbyEnemyHeroes = J.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE )
	local nNearbyEnemyTowers = bot:GetNearbyTowers( 800, true )
	local nNearbyEnemyBarracks = bot:GetNearbyBarracks( 600, true )
	local nNearbyAlliedCreeps = bot:GetNearbyLaneCreeps( 1000, false )
	local nNearbyEnemyCreeps = bot:GetNearbyLaneCreeps( 800, true )

	if J.IsPushing( bot )
	then
		if ( #nNearbyEnemyTowers >= 1 or #nNearbyEnemyBarracks >= 1 )
			and #nNearbyAlliedCreeps >= 1
		then
			hEffectTarget = bot
			sCastMotive = '推进'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	if J.IsGoingOnSomeone( bot )
		and J.IsValidHero( botTarget )
		and J.CanCastOnMagicImmune( botTarget )
		and J.IsInRange( bot, botTarget, bot:GetAttackRange() + 80 )
	then
		hEffectTarget = botTarget
		sCastMotive = '进攻:'..J.Chat.GetNormName( hEffectTarget )
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if bot:IsRooted()
		or ( bot:IsSilenced() and not bot:HasModifier( "modifier_item_mask_of_madness_berserk" ) )
		or bot:HasModifier( 'modifier_item_solar_crest_armor_reduction' )
		or bot:HasModifier( 'modifier_item_medallion_of_courage_armor_reduction' )
		or bot:HasModifier( 'modifier_item_spirit_vessel_damage' )
		or bot:HasModifier( 'modifier_dragonknight_breathefire_reduction' )
		or bot:HasModifier( 'modifier_slardar_amplify_damage' )
		or bot:HasModifier( 'modifier_item_dustofappearance' )
	then
		hEffectTarget = bot
		sCastMotive = '解Buff'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if not bot:IsMagicImmune()
		and not bot:HasModifier( "modifier_antimage_spell_shield" )
		and not bot:HasModifier( "modifier_item_sphere_target" )
		and not bot:HasModifier( "modifier_item_lotus_orb_active" )
		and J.IsNotAttackProjectileIncoming( bot, 70 )
	then
		hEffectTarget = bot
		sCastMotive = '躲弹道'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if J.IsRetreating( bot )
		and nNearbyEnemyHeroes[1] ~= nil
		and bot:DistanceFromFountain() > 600
	then
		hEffectTarget = bot
		sCastMotive = '撤退了'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if #nNearbyEnemyCreeps >= 8
	then
		hEffectTarget = bot
		sCastMotive = '刷小兵'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if bot:WasRecentlyDamagedByAnyHero( 5.0 )
		and bot:GetHealth() / bot:GetMaxHealth() < 0.18
		and bot:DistanceFromFountain() > 800
	then
		hEffectTarget = bot
		sCastMotive = '残血了'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--大电锤
X.ConsiderItemDesire["item_mjollnir"] = function( hItem )

	local nCastRange = 800 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	local nNearbyAllyList = J.GetNearbyHeroes(bot, nCastRange + 100, false, BOT_MODE_NONE);

	--团战中对被攻击频率最高的用
	if J.IsInTeamFight( bot, 900 )
	then
		local targetAlly = nil
		local maxTargetCount = 1
		for _, npcAlly in pairs(nNearbyAllyList)
		do
			if J.IsValid( npcAlly )
				and not npcAlly:IsIllusion()
				and not npcAlly:HasModifier( "modifier_item_mjollnir_static" )
			then
				local nAllyCount = 0 ;
				local nEnemyHeroes = J.GetNearbyHeroes(npcAlly, 1400, true, BOT_MODE_NONE);
				local nEnemyCreeps = npcAlly:GetNearbyCreeps(1000, true);
				for _, unit in pairs(nEnemyHeroes)
				do
					if unit ~= nil and unit:IsAlive()
						and unit:GetAttackTarget() == npcAlly
					then
						nAllyCount = nAllyCount + 1
					end
				end
				for _, unit in pairs(nEnemyCreeps)
				do
					if unit ~= nil and unit:IsAlive()
						and unit:GetAttackTarget() == npcAlly
					then
						nAllyCount = nAllyCount + 1
					end
				end
				if nAllyCount > maxTargetCount
				then
					maxTargetCount = nAllyCount
					targetAlly = npcAlly
				end
			end
		end

		if targetAlly ~= nil
		then
			hEffectTarget = targetAlly
			sCastMotive = '团战中套电锤给队友:'..J.Chat.GetNormName(hEffectTarget)
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	if J.IsValidHero(botTarget)
	then
		local nAllies = J.GetAlliesNearLoc(botTarget:GetLocation(),1400)
		if J.IsValid(nAllies[1])
		then
			local targetAlly = nil
			local targetDis = 9999
			for _, npcAlly in pairs(nAllies)
			do
				if J.IsValid( npcAlly )
					and GetUnitToUnitDistance( bot, npcAlly ) < nCastRange + 200
					and GetUnitToUnitDistance( botTarget, npcAlly ) < targetDis
					and not npcAlly:HasModifier( "modifier_item_mjollnir_static" )
				then
					targetAlly = npcAlly
					targetDis = GetUnitToUnitDistance( botTarget, npcAlly )
				end
			end
			if targetAlly ~= nil
			then
				hEffectTarget = targetAlly
				sCastMotive = '攻击前套电锤给队友:'..J.Chat.GetNormName(hEffectTarget)
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	if hNearbyEnemyHeroList[1] == nil
	then
		local nAllyCreeps = bot:GetNearbyLaneCreeps(1000,false);
		local nEnemyCreeps = bot:GetNearbyLaneCreeps(1000,true);
		if #nAllyCreeps >= 1 and #nEnemyCreeps == 0
		then
			local targetCreep = nil
			local targetDis = 0
			for _, creep in pairs(nAllyCreeps)
			do
				if J.IsValid(creep)
					and J.GetHP(creep) > 0.6
					and creep:DistanceFromFountain() > targetDis
				then
					targetCreep = creep;
					targetDis = creep:DistanceFromFountain();
				end
			end
			if targetCreep ~= nil
			then
				hEffectTarget = targetCreep
				sCastMotive = '给前排小兵套上'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end


	if J.IsValidHero(hNearbyEnemyHeroList[1])
	   and hNearbyEnemyHeroList[1]:GetAttackTarget() == bot
	then
		if not bot:HasModifier("modifier_item_mjollnir_static")
		then
			hEffectTarget = bot
			sCastMotive = '给自己套上'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end



--疯脸
X.ConsiderItemDesire["item_mask_of_madness"] = function( hItem )

	if botName == 'npc_dota_hero_drow_ranger' or J.IsRetreating(bot)
		or J.ShouldRetreatFromEnemyReinforcements(bot) then return BOT_ACTION_DESIRE_NONE end

	local nAttackTarget = bot:GetAttackTarget()
	local nCastRange = bot:GetAttackRange() + 100
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	-- local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if ( J.IsValid( nAttackTarget ) or J.IsValidBuilding( nAttackTarget ) )
		and J.CanBeAttacked( nAttackTarget )
		and J.IsInRange( bot, nAttackTarget, nCastRange )
		and ( not J.CanKillTarget( nAttackTarget, bot:GetAttackDamage() * 2, DAMAGE_TYPE_PHYSICAL )
			 or J.GetAroundTargetEnemyUnitCount( bot, nCastRange ) >= 2 )
	then
		local nEnemyHeroInView = J.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )
		if nAttackTarget:IsHero()
			or ( #nEnemyHeroInView == 0 and not bot:WasRecentlyDamagedByAnyHero( 2.0 ) )
		then
			if #nEnemyHeroInView > 0 and botName == 'npc_dota_hero_sniper' then
				local shrapnel = bot:GetAbilityByName('sniper_shrapnel')
				if J.CanCastAbility(shrapnel)
					and (#nEnemyHeroInView >= 2 or J.GetHP(bot) < 0.65) then return BOT_ACTION_DESIRE_NONE end
			end
			if #nEnemyHeroInView > 0 and botName == "npc_dota_hero_faceless_void" then
				local ultimate = J.GetUltimateAbility(bot)
				if ultimate ~= nil and ultimate:IsTrained() and ultimate:GetCooldownTimeRemaining() <= 0 then
					return BOT_ACTION_DESIRE_NONE
				end
			end

			bot:SetTarget( nAttackTarget )
			hEffectTarget = nAttackTarget
			sCastMotive = '启动'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--勋章
X.ConsiderItemDesire["item_medallion_of_courage"] = function( hItem )

	local nCastRange = 900 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	-- local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and not botTarget:HasModifier( 'modifier_item_solar_crest_armor_reduction' )
			and not botTarget:HasModifier( 'modifier_item_medallion_of_courage_armor_reduction' )
			and J.CanCastOnNonMagicImmune( botTarget )
			and not botTarget:IsAncientCreep()
			and ( J.IsInRange( bot, botTarget, bot:GetAttackRange() + 150 )
				or ( J.IsInRange( bot, botTarget, 1000 )
					and J.GetAroundTargetOtherAllyHeroCount( bot, botTarget, 600 ) >= 1 ) )
		then
			hEffectTarget = botTarget
			sCastMotive = '进攻:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	if #hNearbyEnemyHeroList == 0
	then
		if J.IsValid( botTarget )
			and not botTarget:HasModifier( 'modifier_item_solar_crest_armor_reduction' )
			and not botTarget:HasModifier( 'modifier_item_medallion_of_courage_armor_reduction' )
			and not botTarget:HasModifier( "modifier_fountain_glyph" )
			and not J.CanKillTarget( botTarget, bot:GetAttackDamage() * 2.38, DAMAGE_TYPE_PHYSICAL )
			and J.IsInRange( bot, botTarget, bot:GetAttackRange() + 150 )
		then
			hEffectTarget = botTarget
			sCastMotive = '刷小兵:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	--------
	local hAllyList = J.GetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE )
	for _, npcAlly in pairs( hAllyList )
	do
		if npcAlly ~= bot
			and J.IsValidHero( npcAlly )
			and not npcAlly:IsIllusion()
			and J.CanCastOnNonMagicImmune( npcAlly )
			and not npcAlly:HasModifier( 'modifier_item_solar_crest_armor_addition' )
			and not npcAlly:HasModifier( 'modifier_item_medallion_of_courage_armor_addition' )
			and not npcAlly:HasModifier( "modifier_arc_warden_tempest_double" )
			and ( ( J.IsDisabled( npcAlly ) )
				or ( J.GetHP( npcAlly ) < 0.35 and #hNearbyEnemyHeroList > 0 and npcAlly:WasRecentlyDamagedByAnyHero( 2.0 ) )
				or ( J.IsValidHero( npcAlly:GetAttackTarget() ) and GetUnitToUnitDistance( npcAlly, npcAlly:GetAttackTarget() ) <= npcAlly:GetAttackRange() and #hNearbyEnemyHeroList == 0 ) )
		then
			hEffectTarget = npcAlly
			sCastMotive = '救队友:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--银月
X.ConsiderItemDesire["item_moon_shard"] = function( hItem )
	if bot:GetNetWorth() < 18000 or Utils.CountBackpackEmptySpace(bot) >= 3
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local nCastRange = 2000
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil


	if not bot:HasModifier( "modifier_item_moon_shard_consumed" )
	then
		if bot.moonSharedTime == nil --添加使用延迟避免吃得过快以为没出
		then
			bot.moonSharedTime = DotaTime()
		elseif bot.moonSharedTime < DotaTime() - 2.0
		then
			bot.moonSharedTime = nil
			hEffectTarget = bot
			sCastMotive = "自己吃"
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	local targetMember = nil
	local targetDamage = 0
	for i = 1, #GetTeamPlayers( GetTeam() )
	do
		local member = GetTeamMember( i )
		if member ~= nil and member:IsAlive()
		 and member:GetAttackDamage() > targetDamage
		 and not member:HasModifier( "modifier_item_moon_shard_consumed" )
		then
			targetMember = member
			targetDamage = member:GetAttackDamage()
		end
	end
	if targetMember ~= nil
	then
		if bot.moonSharedTime == nil
		then
			bot.moonSharedTime = DotaTime()
		elseif bot.moonSharedTime < DotaTime() - 3.0
		then
			bot.moonSharedTime = nil
			hEffectTarget = targetMember
			sCastMotive = "给队友"
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end


	return BOT_ACTION_DESIRE_NONE

end

--死灵书
X.ConsiderItemDesire["item_necronomicon"] = function( hItem )

	local nCastRange = 750
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if botTarget ~= nil and botTarget:IsAlive()
		and J.IsInRange( bot, botTarget, 1000 )
	then
		hEffectTarget = botTarget
		sCastMotive = "进攻"
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

X.ConsiderItemDesire["item_necronomicon_2"] = function( hItem )

	return X.ConsiderItemDesire["item_necronomicon"]( hItem )

end

X.ConsiderItemDesire["item_necronomicon_3"] = function( hItem )

	return X.ConsiderItemDesire["item_necronomicon"]( hItem )

end

--否决
X.ConsiderItemDesire["item_nullifier"] = function( hItem )

	local nCastRange = 800 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and J.CanCastOnNonMagicImmune( botTarget )
			and J.CanCastOnTargetAdvanced( botTarget )
			and J.IsInRange( botTarget, bot, nCastRange )
			and not botTarget:HasModifier( "modifier_item_nullifier_mute" )
		then
			hEffectTarget = botTarget
			sCastMotive = '进攻:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--紫苑
X.ConsiderItemDesire["item_orchid"] = function( hItem )

	local nCastRange = 900 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	for _, npcEnemy in pairs( nInRangeEnmyList )
	do
		if J.IsValid( npcEnemy )
			and J.CanCastOnNonMagicImmune( npcEnemy )
			and X.IsWithoutSpellShield( npcEnemy )
		then
			if ( npcEnemy:IsChanneling() or npcEnemy:IsCastingAbility() )
			then
				hEffectTarget = npcEnemy
				sCastMotive = "打断:"..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end

			if J.IsRetreating( bot )
			then
				if not J.IsDisabled( npcEnemy )
				then
					hEffectTarget = npcEnemy
					sCastMotive = "撤退:"..J.Chat.GetNormName( hEffectTarget )
					return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
				end
			end
		end
	end

	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
			and not J.IsDisabled( botTarget )
			and J.CanCastOnNonMagicImmune( botTarget )
			and X.IsWithoutSpellShield( botTarget )
		then
			hEffectTarget = botTarget
			sCastMotive = "进攻:"..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--相位
X.ConsiderItemDesire["item_phase_boots"] = function( hItem )

	local nCastRange = 800
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsRunning( bot )
	then
		hEffectTarget = bot
		sCastMotive = '跑起来'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--笛子
X.ConsiderItemDesire["item_pipe"] = function( hItem )

	local nCastRange = 1000
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )
	local hNearbyAllyList = J.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE )

	for _, npcAlly in pairs( hNearbyAllyList )
	do
		if J.IsValid( npcAlly )
			and not npcAlly:IsIllusion()
			and npcAlly:GetHealth() / npcAlly:GetMaxHealth() < 0.4
			and #hNearbyEnemyHeroList > 0
		then
			hEffectTarget = npcAlly
			sCastMotive = '保护队友:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	local nNearbyAllyHeroes = J.GetNearbyHeroes(bot, 1200, false, BOT_MODE_NONE )
	local nNearbyEnemyHeroes = J.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )
	local nNearbyAllyTowers = bot:GetNearbyTowers( 1200, true )
	if ( #nNearbyAllyHeroes >= 2 and #nNearbyEnemyHeroes >= 2 )
		or ( #nNearbyEnemyHeroes >= 2 and #nNearbyAllyHeroes + #nNearbyAllyTowers >= 2 )
	then
		hEffectTarget = bot
		sCastMotive = '保护团队'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--假腿
X.ConsiderItemDesire["item_power_treads"] = function( hItem )

	if bDeafaultItemHero then return 0 end

	local nCastRange = 1000
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	local nPtStat = hItem:GetPowerTreadsStat()
	if nPtStat == ATTRIBUTE_INTELLECT
	then
		nPtStat = ATTRIBUTE_AGILITY
	elseif nPtStat == ATTRIBUTE_AGILITY
	then
		nPtStat = ATTRIBUTE_INTELLECT
	end

	if ( bot:HasModifier( "modifier_flask_healing" )
		 or bot:HasModifier( "modifier_clarity_potion" )
		 or bot:HasModifier( "modifier_item_urn_heal" )
		 or bot:HasModifier( "modifier_item_spirit_vessel_heal" )
		 or bot:HasModifier( "modifier_bottle_regeneration" ) )
		and nMode ~= BOT_MODE_ATTACK
		and nMode ~= BOT_MODE_RETREAT
	then
		if nPtStat ~= ATTRIBUTE_AGILITY
		then
			--切换敏捷腿回复
			lastSwitchPtTime = DotaTime()
			if nPtStat == ATTRIBUTE_STRENGTH
			then
				sCastMotive = '力量腿切敏捷回复'
				return BOT_ACTION_DESIRE_HIGH, bot, 'twice', sCastMotive
			else
				sCastMotive = '智力腿切敏捷回复'
				return BOT_ACTION_DESIRE_HIGH, bot, sCastType, sCastMotive
			end

		end
	elseif ( nMode == BOT_MODE_RETREAT and bot:GetActiveModeDesire() > BOT_MODE_DESIRE_MODERATE )
			or nMode == BOT_MODE_EVASIVE_MANEUVERS
			or ( J.IsNotAttackProjectileIncoming( bot, 1200 ) )
			or ( bot:HasModifier( "modifier_sniper_assassinate" ) )
			or ( bot:GetHealth() / bot:GetMaxHealth() < 0.2 )
			or ( nPtStat == ATTRIBUTE_STRENGTH and bot:GetHealth() / bot:GetMaxHealth() < 0.3 )
			or ( nMode ~= BOT_MODE_LANING and bot:GetLevel() <= 10 and J.IsEnemyFacingUnit( bot, 800, 20 ) )
		then
			if nPtStat ~= ATTRIBUTE_STRENGTH
			then
				--切换力量腿吃伤害
				lastSwitchPtTime = DotaTime()
				if nPtStat == ATTRIBUTE_AGILITY
				then
					sCastMotive = '敏捷腿切换力量吃伤害'
					return BOT_ACTION_DESIRE_HIGH, bot, sCastType, sCastMotive
				else
					sCastMotive = '智力腿切换力量吃伤害'
					return BOT_ACTION_DESIRE_HIGH, bot, 'twice', sCastMotive
				end

			end
	elseif nMode == BOT_MODE_ATTACK
			or nMode == BOT_MODE_TEAM_ROAM
		then
			if J.ShouldSwitchPTStat( bot, hItem )
				and lastSwitchPtTime < DotaTime() - 0.2
			then
				--切换主属性腿攻击
				sCastMotive = '切换主属性腿攻击'
				return BOT_ACTION_DESIRE_HIGH, bot, sCastType, sCastMotive
			end
	elseif J.ShouldSwitchPTStat( bot, hItem )
			and lastSwitchPtTime < DotaTime() - 0.2
		then
			--默认为主属性腿
			sCastMotive = '默认为主属性腿'
			return BOT_ACTION_DESIRE_HIGH, bot, sCastType, sCastMotive
	end


	return BOT_ACTION_DESIRE_NONE

end

--补刀斧
local lastQuellingBladeUseTime = 0
X.ConsiderItemDesire["item_quelling_blade"] = function( hItem )

	local nCastRange = 450 + aetherRange
	local sCastType = 'tree'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )
	
	-- 解开先知的树框
	if bot:HasModifier('modifier_furion_sprout_damage') then
		local nearbyTrees = bot:GetNearbyTrees( 280 )
		if nearbyTrees ~= nil and #nearbyTrees >= 8
			and IsLocationVisible( GetTreeLocation( nearbyTrees[1] ) )
			and IsLocationPassable( GetTreeLocation( nearbyTrees[1] ) )
		then
			hEffectTarget = nearbyTrees[1]
			sCastMotive = '吃先知的树'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	if DotaTime() < 0 and not thereBeMonkey
	then
		for i, id in pairs( GetTeamPlayers( GetOpposingTeam() ) )
		do
			if GetSelectedHeroName( id ) == 'npc_dota_hero_monkey_king'
			then
				thereBeMonkey = true
			end
		end
	end

	if thereBeMonkey
	then
		local theMonkeyKing = nil
		for _, enemy in pairs( hNearbyEnemyHeroList )
		do
			if enemy:IsAlive()
				and enemy:GetUnitName() == "npc_dota_hero_monkey_king"
			then
				theMonkeyKing = enemy
				break
			end
		end

		if theMonkeyKing ~= nil
			and J.IsInRange( bot, theMonkeyKing, nCastRange )
		then
			local nTrees = bot:GetNearbyTrees( nCastRange )
			for _, tree in pairs( nTrees )
			do
				local treeLoc = GetTreeLocation( tree )
				if GetUnitToLocationDistance( theMonkeyKing, treeLoc ) < 30
				then
					sCastMotive = '砍大圣的树'
					return BOT_ACTION_DESIRE_HIGH, tree, sCastType, sCastMotive
				end
			end
		end
	end

	--开视野
	if DotaTime() > lastQuellingBladeUseTime + 0.8
		and ( J.IsGoingOnSomeone( bot ) or J.IsFarming( bot ) or J.IsRetreating( bot ) )
	then
		lastQuellingBladeUseTime = DotaTime()

		local nBladeRange = 350
		local nTrees = bot:GetNearbyTrees( nBladeRange )
		local nTreeCount = #nTrees
		if nTreeCount >= 1
		then
			for treeID = 1, nTreeCount
			do
				local tree = nTrees[treeID]
				if bot:IsFacingLocation( GetTreeLocation( tree ), 7 )
				then
					sCastMotive = '开视野'
					return BOT_ACTION_DESIRE_HIGH, tree, sCastType, sCastMotive
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--刷新球
-- 7.41: Refresher Orb only refreshes ABILITIES, not items.
-- Do not add logic that chains Refresher with item re-use (e.g. BKB).
X.ConsiderItemDesire["item_refresher"] = function( hItem )

	local nCastRange = 1000
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = '刷新技能'
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	-- if bot has an overrided version of CanUseRefresherShard logic:
	if BotBuild ~= nil and BotBuild.CanUseRefresherShard ~= nil and BotBuild.CanUseRefresherShard() then
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if #nInRangeEnmyList > 0
		and ( J.IsGoingOnSomeone( bot ) or J.IsInTeamFight( bot ) )
		and J.CanUseRefresherShard( bot )
	then
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--刷新碎片
X.ConsiderItemDesire["item_refresher_shard"] = function( hItem )

	return X.ConsiderItemDesire["item_refresher"]( hItem )

end


--肉山A杖
X.ConsiderItemDesire["item_ultimate_scepter_roshan"] = function( hItem )

	local nCastRange = 300
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	if hItem:IsFullyCastable()
	then
		hEffectTarget = bot
		sCastMotive = '吃A杖'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--肉山魔晶
X.ConsiderItemDesire["item_aghanims_shard_roshan"] = function( hItem )

	local nCastRange = 300
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	if hItem:IsFullyCastable()
	then
		hEffectTarget = bot
		sCastMotive = '吃魔晶'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end


--阿托斯
X.ConsiderItemDesire["item_rod_of_atos"] = function( hItem )

	local nCastRange = 1100 + aetherRange
	local sCastType = 'unit'
	if hItem:GetName() == "item_gungir" then sCastType = 'ground' end
	local hEffectTarget = nil
	local sCastMotive = nil
	local nEnemysHerosInCastRange = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	for _, npcEnemy in pairs( nEnemysHerosInCastRange )
	do
		if J.IsValid( npcEnemy )
			and npcEnemy:IsChanneling()
			and npcEnemy:HasModifier( "modifier_teleporting" )
			and J.CanCastOnNonMagicImmune( npcEnemy )
			and J.CanCastOnTargetAdvanced( npcEnemy )
		then
			hEffectTarget = npcEnemy
			sCastMotive = '打断:'..J.Chat.GetNormName( hEffectTarget )
			
			if hItem:GetName() == "item_gungir" then hEffectTarget = hEffectTarget:GetLocation() end
			
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	if nMode == BOT_MODE_RETREAT
		and bot:GetActiveModeDesire() > BOT_MODE_DESIRE_MODERATE
		and	J.IsValid( nEnemysHerosInCastRange[1] )
		and J.CanCastOnNonMagicImmune( nEnemysHerosInCastRange[1] )
		and J.CanCastOnTargetAdvanced( nEnemysHerosInCastRange[1] )
		and not J.IsDisabled( nEnemysHerosInCastRange[1] )
	then
		hEffectTarget = nEnemysHerosInCastRange[1]
		sCastMotive = '撤退了'
		
		if hItem:GetName() == "item_gungir" then hEffectTarget = hEffectTarget:GetLocation() end
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and not J.IsDisabled( botTarget )
			and J.CanCastOnNonMagicImmune( botTarget )
			and J.CanCastOnTargetAdvanced( botTarget )
			and GetUnitToUnitDistance( botTarget, bot ) <= nCastRange
			and J.IsMoving( botTarget )
		then
			hEffectTarget = botTarget
			sCastMotive = '进攻:'..J.Chat.GetNormName( hEffectTarget )
			if hItem:GetName() == "item_gungir" then hEffectTarget = hEffectTarget:GetLocation() end
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--撒旦
X.ConsiderItemDesire["item_satanic"] = function( hItem )

	if J.IsInEtherealForm(bot) or bot:IsDisarmed()
		or bot:OriginalGetHealth() / bot:OriginalGetMaxHealth() >= 0.62
	then return BOT_ACTION_DESIRE_NONE end
	local range = bot:GetAttackRange() + 250
	if J.IsValidHero(botTarget) and J.CanBeAttacked(botTarget) and J.IsInRange(bot, botTarget, range) then
		return BOT_ACTION_DESIRE_HIGH, botTarget, 'none', '普攻吸血'
	end
	for _, enemy in ipairs(J.GetNearbyHeroes(bot, range, true, BOT_MODE_NONE)) do
		if J.IsValidHero(enemy) and J.CanBeAttacked(enemy) then
			return BOT_ACTION_DESIRE_HIGH, enemy, 'none', '普攻吸血'
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--护符
X.ConsiderItemDesire["item_shadow_amulet"] = function( hItem )

	local nCastRange = 600 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if not bot:IsInvisible() and not HasItemConcealment(bot) and not J.HasInvisCounterBuff(bot)
	then
		local nEnemyList = J.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )
		for _, enemy in pairs( nEnemyList )
		do
			if enemy:IsAlive()
				and ( enemy:GetAttackTarget() == bot or enemy:IsFacingLocation( bot:GetLocation(), 16 ) )
			then
				local nNearbyEnemyTowers = bot:GetNearbyTowers( 888, true )
				if #nNearbyEnemyTowers == 0
					and lastAmuletTime < DotaTime() - 1.28
					and not J.IsGoingOnSomeone(bot)
				then
					lastAmuletTime = DotaTime()
					hEffectTarget = bot
					sCastMotive = '自己用'
					return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
				end
			end
		end

		if bot:IsRooted()
			or J.IsStunProjectileIncoming( bot, 1000 )
		then
			local nNearbyEnemyTowers = bot:GetNearbyTowers( 888, true )
			if #nNearbyEnemyTowers == 0
				and lastAmuletTime < DotaTime() - 1.28
			then
				lastAmuletTime = DotaTime()
				hEffectTarget = bot
				sCastMotive = '撤退了'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	local nNearAllyList = J.GetNearbyHeroes(bot, 849, false, BOT_MODE_NONE )
	for _, npcAlly in pairs( nNearAllyList )
	do
		if J.IsValid( npcAlly )
			and npcAlly ~= bot
			and not npcAlly:IsIllusion()
			and not npcAlly:IsMagicImmune()
			and not npcAlly:IsInvisible()
			and not HasItemConcealment(npcAlly)
			and not J.HasInvisCounterBuff(npcAlly)
			and ( npcAlly:IsStunned()
					or npcAlly:IsRooted()
					or J.IsStunProjectileIncoming( npcAlly, 1000 ) )
		then
			local nNearbyAllyEnemyTowers = npcAlly:GetNearbyTowers( 888, true )
			if #nNearbyAllyEnemyTowers == 0
			then
				hEffectTarget = npcAlly
				sCastMotive = '帮助队友隐身'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--羊刀
X.ConsiderItemDesire["item_sheepstick"] = function( hItem )

	local nCastRange = 700 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	for _, npcEnemy in pairs( nInRangeEnmyList )
	do
		if J.IsValid( npcEnemy )
			and J.CanCastOnNonMagicImmune( npcEnemy )
			and X.IsWithoutSpellShield( npcEnemy )
		then
			if ( npcEnemy:IsChanneling() or npcEnemy:IsCastingAbility() )
			then
				hEffectTarget = npcEnemy
				sCastMotive = "打断:"..J.Chat.GetNormName( hEffectTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end

			if J.IsRetreating( bot )
			then
				if not J.IsDisabled( npcEnemy )
					and not npcEnemy:IsDisarmed()
				then
					hEffectTarget = npcEnemy
					sCastMotive = "撤退:"..J.Chat.GetNormName( hEffectTarget )
					return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
				end
			end
		end
	end

	if J.IsGoingOnSomeone( bot )
	then
		if	J.IsValidHero( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
			and not J.IsDisabled( botTarget )
			and J.CanCastOnNonMagicImmune( botTarget )
			and X.IsWithoutSpellShield( botTarget )
		then
			hEffectTarget = botTarget
			sCastMotive = "进攻:"..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--希瓦
X.ConsiderItemDesire["item_shivas_guard"] = function( hItem )

	local nCastRange = 800
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange + 50, true, BOT_MODE_NONE )


	local hNearbyCreepList = bot:GetNearbyCreeps( nCastRange, true )
	if #hNearbyCreepList >= 6
		or #nInRangeEnmyList >= 1
	then
		hEffectTarget = bot
		sCastMotive = '启动希瓦'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--大隐刀
X.ConsiderItemDesire["item_silver_edge"] = function( hItem )

	if bot:IsInvisible() or HasItemConcealment(bot) or J.HasInvisCounterBuff(bot) then return BOT_ACTION_DESIRE_NONE end
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil

	--破被动
	if J.IsGoingOnSomeone( bot ) and not J.IsRetreating(bot)
		and #hNearbyEnemyTowerList == 0
	then
		if J.IsValidHero( botTarget )
			and J.IsInRange( bot, botTarget, 2400 )
			and J.CanCastOnMagicImmune( botTarget )
		then
			local nearTargetTower = botTarget:GetNearbyTowers( 888, false )
			if #nearTargetTower == 0
			then
				hEffectTarget = botTarget
				sCastMotive = '破坏被动:'..J.Chat.GetNormName( botTarget )
				return 0.65, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	return X.ConsiderItemDesire["item_invis_sword"]( hItem )

end

--大勋章
X.ConsiderItemDesire["item_solar_crest"] = function( hItem )

	local nCastRange = 1000
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local hAllyList = J.GetAlliesNearLoc(bot:GetLocation(), 1000)

	for _, npcAlly in pairs(hAllyList)
	do
		if J.IsValidHero( npcAlly )
		and J.IsInRange( bot, npcAlly, nCastRange )
		and not npcAlly:HasModifier( 'modifier_legion_commander_press_the_attack' )
		and not npcAlly:IsMagicImmune()
		and not npcAlly:IsInvulnerable()
		and npcAlly:CanBeSeen()
		then
			if not npcAlly:IsBot()
			and npcAlly:GetAttackTarget() ~= nil
			and npcAlly:GetMaxHealth() - npcAlly:GetHealth() >= 120
			then
				hEffectTarget = npcAlly
				sCastMotive = 'Solar Crest'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end

			if J.IsGoingOnSomeone(npcAlly)
			then
				local allyTarget = J.GetProperTarget(npcAlly)

				if J.IsValidHero(allyTarget)
				and npcAlly:IsFacingLocation( allyTarget:GetLocation(), 20)
				and J.IsInRange(npcAlly, allyTarget, npcAlly:GetAttackRange() + 100)
				then
					hEffectTarget = npcAlly
					sCastMotive = 'Solar Crest'
					return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--林肯
X.ConsiderItemDesire["item_sphere"] = function( hItem )

	local nCastRange = 700 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )
	local nNearAllyList = J.GetNearbyHeroes(bot, nCastRange, false, BOT_MODE_NONE )


	--对可能被作为敌方目标的队友使用
	for _, npcAlly in pairs( nNearAllyList )
	do
		if J.IsValidHero( npcAlly )
			and npcAlly ~= bot
			and not npcAlly:IsMagicImmune()
			and not npcAlly:IsInvulnerable()
			and not npcAlly:IsIllusion()
			and not npcAlly:HasModifier( "modifier_item_sphere_target" )
			and not npcAlly:HasModifier( 'modifier_antimage_spell_shield' )
			and ( J.IsUnitTargetProjectileIncoming( npcAlly, 800 )
				 or J.IsWillBeCastUnitTargetSpell( npcAlly, 1200 )
				 or bot:GetHealth() < 150 )
		then
			hEffectTarget = npcAlly
			sCastMotive = '帮助队友'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end


	if J.IsValidHero( botTarget )
		and J.IsInRange( bot, botTarget, 2400 )
		and not J.IsInRange( bot, botTarget, 800 )
	then
		if #nNearAllyList >= 2
		then
			local targetAlly = nil
			local targetDistance = 9999
			for _, npcAlly in pairs( nNearAllyList )
			do
				if npcAlly ~= bot
					and not npcAlly:IsIllusion()
					and J.IsInRange( npcAlly, botTarget, targetDistance )
					and not npcAlly:HasModifier( "modifier_item_sphere_target" )
					and not npcAlly:HasModifier( 'modifier_antimage_spell_shield' )
				then
					targetAlly = npcAlly
					targetDistance = GetUnitToUnitDistance( botTarget, npcAlly )
					if J.IsHumanPlayer( npcAlly ) then break end
				end
			end
			if targetAlly ~= nil
			then
				hEffectTarget = targetAlly
				sCastMotive = '先给前排套上'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--大骨灰
X.ConsiderItemDesire["item_spirit_vessel"] = function( hItem )

	return X.ConsiderItemDesire["item_urn_of_shadows"]( hItem )

end


--精华蒸馏器
X.ConsiderItemDesire["item_essence_distiller"] = function( hItem )

	if hItem:GetCurrentCharges() == 0 then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 950 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget ) and
			((J.CanCastOnNonMagicImmune( botTarget )
				and J.IsInRange( bot, botTarget, nCastRange )
				and not botTarget:HasModifier( "modifier_item_urn_damage" )
				and not botTarget:HasModifier( "modifier_item_spirit_vessel_damage" )
				and not botTarget:HasModifier( "modifier_item_essence_distiller_damage" )
				and not botTarget:HasModifier( "modifier_arc_warden_tempest_double" )
				and ( J.GetHP( botTarget ) < 0.95 or J.IsInRange( bot, botTarget, 700 ) ))
			or botTarget:HasModifier( "modifier_invoker_cold_snap_freeze" )
		) then
			hEffectTarget = botTarget
			sCastMotive = "进攻:"..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	if bot:GetActiveMode() ~= BOT_MODE_ROSHAN
	then
		local hAllyList = J.GetNearbyHeroes(bot, nCastRange + 80, false, BOT_MODE_NONE )
		local hNeedHealAlly = nil
		local nNeedHealAllyHealth = 99999
		for _, npcAlly in pairs( hAllyList )
		do
			if J.IsValid( npcAlly )
				and not npcAlly:IsIllusion()
				and npcAlly:DistanceFromFountain() > 800
				and J.CanCastOnNonMagicImmune( npcAlly )
				and not npcAlly:WasRecentlyDamagedByAnyHero( 3.1 )
				and not npcAlly:HasModifier( "modifier_item_spirit_vessel_heal" )
				and not npcAlly:HasModifier( "modifier_item_urn_heal" )
				and not npcAlly:HasModifier( "modifier_item_essence_distiller_heal" )
				and not npcAlly:HasModifier( "modifier_fountain_aura" )
				and not npcAlly:HasModifier( "modifier_arc_warden_tempest_double" )
				and npcAlly:OriginalGetMaxHealth() - npcAlly:OriginalGetHealth() > 450
				and #hNearbyEnemyHeroList == 0
			then
				if( npcAlly:OriginalGetHealth() < nNeedHealAllyHealth )
				then
					hNeedHealAlly = npcAlly
					nNeedHealAllyHealth = npcAlly:OriginalGetHealth()
				end
			end
		end

		if( hNeedHealAlly ~= nil )
		then
			hEffectTarget = hNeedHealAlly
			sCastMotive = '治疗:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--吃树
X.ConsiderItemDesire["item_tango"] = function( hItem )

	local nCastRange = 300 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil


	--share tango
	local tCharge = hItem:GetCurrentCharges()
	if	bot:GetLevel() <= 12
			and ( #hNearbyEnemyHeroList == 0 or nMode == BOT_MODE_LANING )
			and tCharge >= 1
			and DotaTime() > 10
			and DotaTime() > J.Role['fLastGiveTangoTime'] + 40.0
		then
			local hAllyList = J.GetNearbyHeroes(bot, nCastRange, false, BOT_MODE_NONE )
			for _, npcAlly in pairs( hAllyList )
			do
				if npcAlly ~= bot
				then
					local tangoSlot = npcAlly:FindItemSlot( 'item_tango' )
					if tangoSlot == -1
						and not npcAlly:IsIllusion()
						and npcAlly:OriginalGetMaxHealth() - npcAlly:OriginalGetHealth() > 200
						and not npcAlly:HasModifier( "modifier_tango_heal" )
						and not npcAlly:HasModifier( "modifier_arc_warden_tempest_double" )
						and not J.IsMeepoClone(bot)
						and not J.IsMeepoClone(npcAlly)
						and J.Item.GetItemCount( npcAlly, "item_tango_single" ) == 0
						and J.Item.GetEmptyInventoryAmount( npcAlly ) >= 1
					then
						J.Role['fLastGiveTangoTime'] = DotaTime()
						hEffectTarget = npcAlly
						sCastMotive = '分享队友吃树'
						return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
					end
				end
			end
	end

	local hTangoSingle = J.IsItemAvailable( 'item_tango_single' )
	if hTangoSingle ~= nil and hTangoSingle:IsFullyCastable() then return 0 end

	return X.ConsiderItemDesire["item_tango_single"]( hItem )

end

X.ConsiderItemDesire["item_tango_single"] = function( hItem )

	if bot:DistanceFromFountain() < 2300 or bot:HasModifier( "modifier_tango_heal" ) then return 0 end

	local nCastRange = 300 + aetherRange
	local sCastType = 'tree'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nUseTangoLostHealth = ( hItem:GetName() == 'item_tango' ) and 200 or 160
	local nLostHealth = bot:OriginalGetMaxHealth() - bot:OriginalGetHealth()

	-- 解开先知的树框。bug: 因为先知的树不是正常的树。GetNearbyTrees 不会返回先知的树，此方式行不通
	if bot:HasModifier('modifier_furion_sprout_damage') then
		local nearbyTrees = bot:GetNearbyTrees( 280 )
		if nearbyTrees ~= nil and #nearbyTrees >= 8
			and IsLocationVisible( GetTreeLocation( nearbyTrees[1] ) )
			and IsLocationPassable( GetTreeLocation( nearbyTrees[1] ) )
		then
			hEffectTarget = nearbyTrees[1]
			sCastMotive = '吃先知的树'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	-- A reachable Tango can be started during lane attrition without walking away from the wave.
	if nMode == BOT_MODE_LANING and J.IsInLaningPhase(bot) and bot:WasRecentlyDamagedByAnyHero(3)
		and nLostHealth >= math.min(160, bot:OriginalGetMaxHealth() * 0.2)
		and not bot:HasModifier('modifier_flask_healing') and not bot:HasModifier('modifier_juggernaut_healing_ward_heal')
		and not J.HasPendingLaningLastHit(bot) and not J.IsFinishingLaningAttack(bot, bot:GetAttackTarget()) then
		local enemies = J.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE)
		local enemyTower = bot:GetNearbyTowers(1200, true)[1]
		for _, tree in ipairs(bot:GetNearbyTrees(140)) do
			local point = GetTreeLocation(tree)
			local safe = IsLocationVisible(point) and IsLocationPassable(point)
				and (not J.IsValidBuilding(enemyTower) or GetUnitToLocationDistance(enemyTower, point) > 850)
			for _, enemy in ipairs(enemies) do
				if J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy)
					and GetUnitToLocationDistance(enemy, point) <= math.max(425, enemy:GetAttackRange() + 150)
					and GetUnitToLocationDistance(enemy, point) + 35 < GetUnitToUnitDistance(bot, enemy) then
					safe = false
					break
				end
			end
			if safe then return BOT_ACTION_DESIRE_HIGH, tree, sCastType, '对线换血吃树' end
		end
	end

	if J.IsWithoutTarget( bot )
		and not bot:HasModifier( "modifier_flask_healing" )
		and not bot:HasModifier( "modifier_juggernaut_healing_ward_heal" )
	then
		local trees = bot:GetNearbyTrees( 800 )
		local targetTree = trees[1]
		local nearEnemyList = J.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE )
		local nearestEnemy = nearEnemyList[1]
		local nearTowerList = bot:GetNearbyTowers( 1400, true )
		local nearestTower = nearTowerList[1]


		--常规吃树
		if targetTree ~= nil
		then
			local targetTreeLoc = GetTreeLocation( targetTree )
			if nLostHealth > nUseTangoLostHealth
				and IsLocationVisible( targetTreeLoc )
				and IsLocationPassable( targetTreeLoc )
				and ( #nearEnemyList == 0 or not J.IsInRange( bot, nearestEnemy, 800 ) )
				and ( #nearEnemyList == 0 or GetUnitToLocationDistance( bot, targetTreeLoc ) * 1.6 < GetUnitToUnitDistance( bot, nearestEnemy ) )
				and ( #nearTowerList == 0 or GetUnitToLocationDistance( nearestTower, targetTreeLoc ) > 920 )
			then
				hEffectTarget = targetTree
				sCastMotive = '800码内的树'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end


		--塔下吃树
		local nAllyTowerList = bot:GetNearbyTowers( 1100, false )
		if #nAllyTowerList >= 1
			and nLostHealth > nUseTangoLostHealth + 20
		then
			local nAllyTower = nAllyTowerList[1]
			if nAllyTower ~= nil
			then
				local nFindTreeDistance = 1100 - GetUnitToUnitDistance( bot, nAllyTower )
				local nearTowerTrees = bot:GetNearbyTrees( nFindTreeDistance )
				local targetTree = nearTowerTrees[1]

				if targetTree ~= nil
				then
					local targetTreeLoc = GetTreeLocation( targetTree )
					if IsLocationVisible( targetTreeLoc )
						and IsLocationPassable( targetTreeLoc )
					then
						hEffectTarget = targetTree
						sCastMotive = '吃塔下的树'
						return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
					end
				end
			end
		end


		--吃近处的树
		local nearbyTrees = bot:GetNearbyTrees( 280 )
		if nearbyTrees[1] ~= nil
			and IsLocationVisible( GetTreeLocation( nearbyTrees[1] ) )
			and IsLocationPassable( GetTreeLocation( nearbyTrees[1] ) )
		then
			if nLostHealth > nUseTangoLostHealth
			then
				hEffectTarget = nearbyTrees[1]
				sCastMotive = '近处的树'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end

			if nLostHealth > nUseTangoLostHealth * 0.38
				and bot:WasRecentlyDamagedByAnyHero( 2.0 )
				and ( bot:GetActiveMode() == BOT_MODE_ATTACK
					 or ( bot:GetActiveMode() == BOT_MODE_RETREAT
						 and bot:GetActiveModeDesire() > BOT_MODE_DESIRE_HIGH ) )
			then
				hEffectTarget = nearbyTrees[1]
				sCastMotive = '提前吃树'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	if DotaTime() > 4 * 60 + 30 and botTarget == nil
		and hItem:GetName() == 'item_tango_single'
		and bot:DistanceFromFountain() > 3000
		and nMode ~= BOT_MODE_RUNE
	then
		local tCount = J.Item.GetItemCount( bot, "item_tango_single" )
		local hNearbyEnemyHeroList = J.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )
		if tCount >= 2
		then
			local trees = bot:GetNearbyTrees( 1200 )
			if trees[1] ~= nil
				and IsLocationVisible( GetTreeLocation( trees[1] ) )
				and IsLocationPassable( GetTreeLocation( trees[1] ) )
				and #hNearbyEnemyHeroList == 0
			then
				hEffectTarget = trees[1]
				sCastMotive = '消耗共享吃树'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end

		if DotaTime() > 7 * 60 + 30
		then
			local trees = bot:GetNearbyTrees( 1200 )
			if trees[1] ~= nil
				and IsLocationVisible( GetTreeLocation( trees[1] ) )
				and IsLocationPassable( GetTreeLocation( trees[1] ) )
				and nLostHealth > 60
				and #hNearbyEnemyHeroList == 0
			then
				hEffectTarget = trees[1]
				sCastMotive = '用掉共享吃树'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end

	end

	return BOT_ACTION_DESIRE_NONE

end

--经验书
X.ConsiderItemDesire["item_tome_of_knowledge"] = function( hItem )

	local nCastRange = 300
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	if hItem:IsFullyCastable()
	then
		hEffectTarget = bot
		sCastMotive = '读书'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end


function X.GetLaningTPLocation( bot, nMinTPDistance, botLocation )

	-- overridding for mid only modes
	if GetGameMode() == GAMEMODE_1V1MID or GetGameMode() == GAMEMODE_MO then
		return nil, false
	end

	local laneToTP = J.GetTeleportHomeLane(bot)
	local tp = false
	if J.IsInLaningPhase(bot) then
		if DotaTime() < 0 or bot:DistanceFromFountain() > 1400 then return nil, false end
		local towers = laneToTP == LANE_TOP and {TOWER_TOP_1, TOWER_TOP_2}
			or (laneToTP == LANE_MID and {TOWER_MID_1, TOWER_MID_2} or {TOWER_BOT_1, TOWER_BOT_2})
		for _, towerId in ipairs(towers) do
			local tower = GetTower(team, towerId)
			if J.IsValidBuilding(tower) then
				local point = J.AdjustLocationWithOffsetTowardsFountain(tower:GetLocation(), 250)
				if J.CanReturnToLaneByTeleport(bot, point, nMinTPDistance - 900) then return point, true end
				if laneToTP == LANE_MID then break end
			end
		end
		return nil, false
	end

	local botAmount = GetAmountAlongLane(laneToTP, botLocation)
	local laneFront = GetLaneFrontAmount(team, laneToTP, false)
	if botAmount.distance > nMinTPDistance
	or botAmount.amount < laneFront / 5
	then
		tp = true
	end
	if tp and laneToTP ~= LANE_MID and bot:DistanceFromFountain() < 1400 then
		local tower = GetTower(team, laneToTP == LANE_TOP and TOWER_TOP_1 or TOWER_BOT_1)
		-- The enemy can own the front without owning our protected landing.
		-- Return behind the tower if a healthy partner can receive us; never TP
		-- to a contested landing merely because health recovered in fountain.
		if (bot.ohaCarryLaneRecoveryUntil or 0) > DotaTime()
			and #J.GetLastSeenEnemiesNearLoc(GetLaneFrontLocation(team, laneToTP, 0), 1700) > 0 then
			local partner = J.GetLanePartner(bot)
			if J.IsValidBuilding(tower) then
				local point = J.AdjustLocationWithOffsetTowardsFountain(tower:GetLocation(), 300)
				local covered = partner ~= nil and J.IsValidHero(partner) and J.GetHP(partner) >= 0.58
					and J.IsInRange(partner, tower, 1100) and not J.IsRetreating(partner)
				local unoccupied = #J.GetLastSeenEnemiesNearLoc(tower:GetLocation(), 1400) == 0
					and #J.GetEnemiesNearLoc(tower:GetLocation(), 1400) == 0
				if (covered or unoccupied) and IsLocationPassable(point)
					and J.CanCommitToLaneTeleport(bot, point, true, 1100) then return point, true end
			end
			return nil, false
		end
		if tower and tower:IsAlive() then return J.AdjustLocationWithOffsetTowardsFountain(tower:GetLocation(), 200), true end
	end
	return GetLaneFrontLocation(team, laneToTP, 100), tp
end

function X.GetDefendTPLocation( nLane )
	local towers = nLane == LANE_TOP and {TOWER_TOP_1, TOWER_TOP_2, TOWER_TOP_3}
		or (nLane == LANE_MID and {TOWER_MID_1, TOWER_MID_2, TOWER_MID_3}
			or {TOWER_BOT_1, TOWER_BOT_2, TOWER_BOT_3})
	for _, id in ipairs(towers) do
		local tower = GetTower(team, id)
		if J.IsValidBuilding(tower) then
			local point = J.AdjustLocationWithOffsetTowardsFountain(tower:GetLocation(), 300)
			if IsLocationPassable(point) and J.CanCommitToLaneTeleport(bot, point, true) then return point, tower end
		end
	end
	local ancient = GetAncient(team)
	if ancient ~= nil and X.GetNumEnemyNearby(ancient) > 0 then
		local fountain = J.GetTeamFountain()
		if J.CanCommitToLaneTeleport(bot, fountain, true) then return fountain, ancient end
	end
end

function X.CanTeleportToFarm(wavePoint, landing)
	if wavePoint == nil or landing == nil or not IsLocationVisible(wavePoint)
		or not J.CanCommitToLaneTeleport(bot, landing, true)
		or not J.CanCommitToLaneTeleport(bot, wavePoint, true) then return false end
	local count = 0
	for _, creep in ipairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS)) do
		if J.IsValid(creep) and GetUnitToLocationDistance(creep, wavePoint) <= 1050
			and (J.IsKeyWordUnit('npc_dota_creep_', creep) or J.IsKeyWordUnit('_siege', creep)) then
			count = count + 1
			if count >= 2 then return true end
		end
	end
	return false
end

function X.GetPushTPLocation( nLane )

	local laneFront = GetLaneFrontLocation( team, nLane, 0 )
	local bestTpLoc = J.GetNearbyLocationToTp( laneFront )
	if J.GetLocationToLocationDistance( laneFront, bestTpLoc ) < 2000
	then
		return bestTpLoc
	end

end


function X.CanJuke()

	local allyTowers = bot:GetNearbyTowers( 350, false )

	if allyTowers[1] ~= nil
		and allyTowers[1]:DistanceFromFountain() > bot:DistanceFromFountain() + 100
		and J.GetEnemyCount( bot, 700 ) == 0
	then return true end

	if J.GetModifierTime(bot, 'modifier_dazzle_shallow_grave') > 3.0
		or J.GetModifierTime(bot, 'modifier_oracle_false_promise_timer') > 3.0
	then return true end

	local enemyPids = GetTeamPlayers( GetOpposingTeam() )

	local heroHG = GetHeightLevel( bot:GetLocation() )
	for i = 1, #enemyPids
	do
		local info = GetHeroLastSeenInfo( enemyPids[i] )
		if info ~= nil then
			local dInfo = info[1]
			if dInfo ~= nil
				and dInfo.time_since_seen < 2.0
			then
				if GetUnitToLocationDistance( bot, dInfo.location ) < 1300
					and GetHeightLevel( dInfo.location ) < heroHG
				then
					return false
				end

				if GetUnitToLocationDistance( bot, dInfo.location ) < 600
				then
					local hNearbyEnemyHeroList = J.GetNearbyHeroes(bot, 600, true, BOT_MODE_NONE )
					if #hNearbyEnemyHeroList == 0
					then
						return false
					end
				end
			end
		end
	end

	local totalDamage = 0
	local nEnemies = J.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE )
	for _, enemy in pairs( nEnemies )
	do
		local enemyDamage = enemy:GetEstimatedDamageToTarget( true, bot, 4.0, DAMAGE_TYPE_ALL )
		totalDamage = totalDamage + enemyDamage
		if bot:OriginalGetHealth() <= totalDamage
		then
			return false
		end
	end

	return true

end


function X.GetNumHeroWithinRange( nRange )

	local enemyPids = GetTeamPlayers( GetOpposingTeam() )

	local cHeroes = 0
	for i = 1, #enemyPids
	do
		local info = GetHeroLastSeenInfo( enemyPids[i] )
		if info ~= nil then
			local dInfo = info[1]
			if dInfo ~= nil and dInfo.time_since_seen < 2.0
				and GetUnitToLocationDistance( bot, dInfo.location ) < nRange
			then
				cHeroes = cHeroes + 1
			end
		end
	end

	return cHeroes

end


function X.IsFarmingAlways( bot )

	local nTarget = bot:GetAttackTarget()
	if J.IsValid( nTarget )
		and nTarget:GetTeam() == TEAM_NEUTRAL
		and not J.IsRoshan( nTarget )
		and not J.IsKeyWordUnit( "warlock", nTarget )
		and X.GetNumEnemyNearby( GetAncient( team ) ) >= 2
	then
		return true
	end

	local nNearAllyList = J.GetNearbyHeroes(bot, 800, false, BOT_MODE_NONE )
	if J.IsValid( nTarget )
		and nTarget:IsAncientCreep()
		and not J.IsRoshan( nTarget )
		and not J.IsKeyWordUnit( "warlock", nTarget )
		and bot:GetPrimaryAttribute() == ATTRIBUTE_INTELLECT
		and botName ~= 'npc_dota_hero_ogre_magi'
		and #nNearAllyList < 2
	then
		return true
	end

	if X.GetNumEnemyNearby( GetAncient( team ) ) >= 4
		and bot:DistanceFromFountain() >= 4800
		and #nNearAllyList < 2
	then
		return true
	end

	return false
end

function X.IsBaseTowerDestroyed()

	for i = 9, 10, 1
	do
		local tower = GetTower( team, i )
		if tower == nil
			or tower:GetHealth() / tower:GetMaxHealth() < 0.99
		then
			return true
		end
	end

	return false

end

--TP
if bot.useProphetTP == nil then bot.useProphetTP = false end
if bot.ProphetTPLocation == nil then bot.ProphetTPLocation = bot:GetLocation() end
X.ConsiderItemDesire["item_tpscroll"] = function( hItem )

	local nMode = bot:GetActiveMode()
	local laning = J.IsInLaningPhase(bot)
	if nMode == BOT_MODE_RUNE
		or ( bot:IsRooted() )
		or ( bot:HasModifier( "modifier_item_armlet_unholy_strength" ) )
		or ( bot:HasModifier( "modifier_kunkka_x_marks_the_spot" ) )
		or ( bot:HasModifier( "modifier_teleporting" ) )
		or ( bot:HasModifier( "modifier_sniper_assassinate" ) )
		or J.GetShrapnelEscapeLocation(bot) ~= nil
		or ( bot:HasModifier( "modifier_viper_nethertoxin" ) )
		or ( bot:HasModifier( "modifier_oracle_false_promise_timer" ) and J.GetModifierTime( bot, "modifier_oracle_false_promise_timer" ) <= 3.2 )
		or ( bot:HasModifier( "modifier_jakiro_macropyre_burn" ) and J.GetModifierTime( bot, "modifier_jakiro_macropyre_burn" ) >= 1.4 )
		or ( bot:HasModifier( "modifier_arc_warden_tempest_double" ) and bot:GetRemainingLifespan() < 3.3 )
		or (J.IsDoingRoshan(bot) and GetUnitToLocationDistance(bot, J.GetCurrentRoshanLocation()) <= 2800)
	then return BOT_ACTION_DESIRE_NONE end

	if bot:GetHealth() < 240
	then
		local nProDamage = J.GetAttackProjectileDamageByRange( bot, 1600 ) * 2
		if bot:GetHealth() < bot:GetActualIncomingDamage( nProDamage, DAMAGE_TYPE_PHYSICAL )
		then return BOT_ACTION_DESIRE_NONE end
	end

	if bot:HasModifier('modifier_spirit_breaker_charge_of_darkness')
	or bot.healInBase
	then
		return BOT_ACTION_DESIRE_NONE
	end

	local nNearbyEnemyTowers = bot:GetNearbyTowers( 888, true )
	if #nNearbyEnemyTowers > 0 then return BOT_ACTION_DESIRE_NONE end

	local sCastType = 'ground'
	local hEffectTarget = nil
	local sCastMotive = nil

	local nMinTPDistance = 5500
	local nModeDesire = bot:GetActiveModeDesire()
	local botLocation = bot:GetLocation()
	local botHP = J.GetHP( bot )
	local botMP = J.GetMP( bot )
	local nEnemyCount = X.GetNumHeroWithinRange( 1600 )
	local nAllyCount = J.GetAllyCount( bot, 1600 )
	local itemFlask = J.IsItemAvailable( "item_flask" )
	local response = bot.ohaHighGroundResponse
	local highGroundResponse = response and response.expires > DotaTime()
	local postFightDuty, postFightPlan
	if J.GetPostFightDuty then postFightDuty, postFightPlan = J.GetPostFightDuty(bot) end
	local midCover = postFightDuty or (bot.ohaMidCover and bot.ohaMidCover.expires > DotaTime())
	local function CanSpendOnTrip(loc)
		return not J.CanTakePostFightTrip or J.CanTakePostFightTrip(bot, loc, true)
	end
	if highGroundResponse then
		local anchors = {}
		for _, id in ipairs({TOWER_BASE_1, TOWER_BASE_2, TOWER_TOP_3, TOWER_MID_3, TOWER_BOT_3}) do
			local tower = GetTower(team, id)
			if J.IsValidBuilding(tower) then anchors[#anchors + 1] = tower end
		end
		local location = J.GetHighGroundResponseTeleport(bot, response.stage, anchors)
		if location then return BOT_ACTION_DESIRE_ABSOLUTE, location, sCastType, 'high-ground-response' end
	end
	local function RememberDefense(lane)
		return function() bot.ohaLaneDefenseTP = { lane = lane, time = DotaTime() } end
	end
	local defense = bot._defend
	local plannedDefense = defense and defense.waveClearLane ~= nil and (bot.ohaOuterTowerHoldUntil or 0) > DotaTime()
		and defense.waveClearTeleport ~= nil and J.IsValidBuilding(defense.waveClearRearTower or defense.waveClearTower)
	if plannedDefense and not postFightDuty and J.IsDefending(bot) and nEnemyCount == 0
		and not J.ShouldKeepLaningWave(bot, defense.waveClearLane)
		and GetUnitToLocationDistance(bot, defense.waveClearTeleport) > 1800
		and J.CanCommitToLaneTeleport(bot, defense.waveClearTeleport, true, defense.waveClearGather and 1250 or nil)
		and J.CanTakeLaneDefenseTeleport(bot, defense.waveClearLane, defense.waveClearTeleport,
			defense.waveClearTower, defense.waveClearRearTower, true, defense.waveClearReach) then
		return BOT_ACTION_DESIRE_ABSOLUTE, defense.waveClearTeleport, sCastType,
			'planned-lane-defense:' .. tostring(defense.waveClearLane), RememberDefense(defense.waveClearLane)
	end

	if postFightDuty and nEnemyCount == 0 then
		local assignment = postFightDuty == 'clear' and postFightPlan.primary or postFightPlan.backup
		if assignment and assignment.teleport and not J.ShouldKeepLaningWave(bot, postFightPlan.lane)
			and J.CanCommitToLaneTeleport(bot, assignment.teleport, true, 1050) then
			return BOT_ACTION_DESIRE_ABSOLUTE, assignment.teleport, sCastType, 'post-fight-cover'
		end
	end

	if bot:GetLevel() > 12 and bot:DistanceFromFountain() < 600 then nMinTPDistance = nMinTPDistance + 600 end

	local recoveringSideCore = (bot.ohaCarryLaneRecoveryUntil or 0) > DotaTime()
		and bot:DistanceFromFountain() < 1400 and botHP >= 0.82 and botMP >= 0.40
		and nEnemyCount == 0 and J.IsInLaningPhase(bot)
	local homeLane, now = bot:GetAssignedLane(), DotaTime()
	local recoveredSideLaner = laning and (homeLane == LANE_TOP or homeLane == LANE_BOT)
		and now >= 40 and now < (J.IsModeTurbo() and 480 or 600) and nEnemyCount == 0
		and botHP > 0.90 and botMP > 0.80 and bot:DistanceFromFountain() < 1300
	if nMode == BOT_MODE_LANING or recoveringSideCore or recoveredSideLaner
		or laning and nMode == BOT_MODE_FARM and nEnemyCount == 0
		and not midCover and bot:DistanceFromFountain() <= 1400
	then
		local shouldTp
		hEffectTarget, shouldTp = X.GetLaningTPLocation(bot, nMinTPDistance, botLocation)
		sCastMotive = '出去发育'
		if shouldTp and J.CanCommitToLaneTeleport(bot, hEffectTarget)
		then
			if botName == 'npc_dota_hero_furion'
			then
				local Teleportation = bot:GetAbilityByName('furion_teleportation')
				if Teleportation:IsTrained()
				and Teleportation:IsFullyCastable()
				then
					bot.useProphetTP = true
					bot.ProphetTPLocation = hEffectTarget
					return BOT_ACTION_DESIRE_NONE
				end
			end

			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	-- Go complete items
	if not laning and not midCover and X.IsInvFull(bot) and X.GetNumStashItem(bot) >= 1
	and (X.IsThereRecipeInStash(bot) or (bot:GetStashValue() >= 1000 and bot:GetGold() > 1100))
	and not J.IsPushing(bot) and not J.IsGoingOnSomeone(bot)
	and not J.IsInTeamFight(bot, 1000)
	and nEnemyCount == 0
	and J.GetLaningHoldTower(bot) == nil
	and not J.ShouldKeepLaningWave(bot)
	and not (J.ShouldKeepMidOpportunity and J.ShouldKeepMidOpportunity(bot))
	then
		hEffectTarget = J.GetTeamFountain()
		sCastMotive = '撤退:1'

		if botName == 'npc_dota_hero_furion'
		then
			local Teleportation = bot:GetAbilityByName('furion_teleportation')
			if Teleportation:IsTrained()
			and Teleportation:IsFullyCastable()
			then
				bot.useProphetTP = true
				bot.ProphetTPLocation = hEffectTarget
				return BOT_ACTION_DESIRE_NONE
			end
		end

		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	-- Roshan
	if not laning and J.IsDoingRoshan(bot)
	and nEnemyCount == 0
	and not J.IsRoshanCloseToChangingSides()
	then
		local roshanLoc = J.GetCurrentRoshanLocation()
		local targetLoc = J.GetNearbyLocationToTp(roshanLoc)

		local tpLocDist = GetUnitToLocationDistance(bot, targetLoc)
		local roshanLocDist = GetUnitToLocationDistance(bot, roshanLoc)

		if tpLocDist > 8000
		and roshanLocDist > 8000
		and roshanLocDist > tpLocDist and CanSpendOnTrip(targetLoc)
		then
			if botName == 'npc_dota_hero_furion'
			then
				local Teleportation = bot:GetAbilityByName('furion_teleportation')
				if Teleportation:IsTrained()
				and Teleportation:IsFullyCastable()
				then
					bot.useProphetTP = true
					bot.ProphetTPLocation = targetLoc
					return BOT_ACTION_DESIRE_NONE
				end
			end

			return BOT_ACTION_DESIRE_HIGH, targetLoc, 'ground', 'tp_roshan'
		end
	end

	--Tormentor
	if not laning and bot:GetActiveMode() == BOT_MODE_SIDE_SHOP
	and nEnemyCount == 0
	and (not J.IsInTeamFight(bot, 1200)
		or not J.IsGoingOnSomeone(bot)
		or not J.IsDefending(bot))
	then
		local torLoc = J.GetTormentorLocation(team)
		if GetUnitToLocationDistance(bot, torLoc) > 8000 then
			hEffectTarget = J.GetNearbyLocationToTp(torLoc)
			sCastMotive = 'tormentor'
			if J.GetLocationToLocationDistance(bot:GetLocation(), hEffectTarget) > 4400 and CanSpendOnTrip(hEffectTarget)
			then
				if botName == 'npc_dota_hero_furion'
				then
					local Teleportation = bot:GetAbilityByName('furion_teleportation')
					if Teleportation:IsTrained()
					and Teleportation:IsFullyCastable()
					then
						bot.useProphetTP = true
						bot.ProphetTPLocation = hEffectTarget
						return BOT_ACTION_DESIRE_NONE
					end
				end
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	--守塔
	if not highGroundResponse and not postFightDuty and J.IsDefending( bot )
		and nModeDesire > BOT_MODE_DESIRE_MODERATE
		and nEnemyCount == 0
	then
		local tpLoc, tower
		local nDefendLane, sLane = LANE_MID, 'tower_mid'
		if nMode == BOT_MODE_DEFEND_TOWER_TOP then nDefendLane, sLane = LANE_TOP, 'tower_top' end
		if nMode == BOT_MODE_DEFEND_TOWER_BOT then nDefendLane, sLane = LANE_BOT, 'tower_bot' end

		local trade = bot.ohaOuterTowerTrade
		local released = trade and trade.lane == nDefendLane and trade.expires > DotaTime()
		if not released and not J.ShouldKeepLaningWave(bot, nDefendLane)
			and not (J.ShouldKeepMidOverRoutineDefense and J.ShouldKeepMidOverRoutineDefense(bot, nDefendLane))
			and (not defense or defense.waveClearLane ~= nDefendLane or (bot.ohaOuterTowerHoldUntil or 0) <= DotaTime()) then
			local botAmount = GetAmountAlongLane(nDefendLane, botLocation)
			local laneFront = GetLaneFrontAmount(team, nDefendLane, false)
			if botAmount.distance > nMinTPDistance or botAmount.amount < laneFront / 5 then
				tpLoc, tower = X.GetDefendTPLocation(nDefendLane)
			end
		end

		if tpLoc ~= nil
			and GetUnitToLocationDistance(bot, tpLoc) > nMinTPDistance - 500
			and J.CanCommitToLaneTeleport(bot, tpLoc)
			and J.CanTakeLaneDefenseTeleport(bot, nDefendLane, tpLoc, tower)
		then
			hEffectTarget = tpLoc
			sCastMotive = '前往守塔:'..sLane

			if botName == 'npc_dota_hero_furion'
			then
				local Teleportation = bot:GetAbilityByName('furion_teleportation')
				if Teleportation:IsTrained()
				and Teleportation:IsFullyCastable()
				then
					bot.useProphetTP = true
					bot.ProphetTPLocation = hEffectTarget
					return BOT_ACTION_DESIRE_NONE
				end
			end

			return BOT_ACTION_DESIRE_ABSOLUTE, hEffectTarget, sCastType, sCastMotive, RememberDefense(nDefendLane)
		end
	end


	--推塔
	if not laning and not highGroundResponse and not midCover and J.IsPushing( bot )
		and nModeDesire >= BOT_MODE_DESIRE_MODERATE
		and nEnemyCount == 0
	then
		local tpLoc
		local nPushLane, sLane = LANE_MID, 'tower_mid'
		if nMode == BOT_MODE_PUSH_TOWER_TOP then nPushLane, sLane = LANE_TOP, 'tower_top' end
		if nMode == BOT_MODE_PUSH_TOWER_BOT then nPushLane, sLane = LANE_BOT, 'tower_bot' end

		if not J.ShouldKeepLaningWave(bot, nPushLane)
			and not (J.ShouldKeepMidOpportunity and J.ShouldKeepMidOpportunity(bot, nPushLane)) then
			local botAmount = GetAmountAlongLane( nPushLane, botLocation )
			local laneFront = GetLaneFrontAmount( team, nPushLane, false )
			if botAmount.distance > nMinTPDistance
				or botAmount.amount < laneFront / 5
			then
				tpLoc = X.GetPushTPLocation( nPushLane )
			end

			if tpLoc ~= nil
				and GetUnitToLocationDistance( bot, tpLoc ) > nMinTPDistance - 600
				and J.CanCommitToLaneTeleport(bot, tpLoc) and CanSpendOnTrip(tpLoc)
			then
				hEffectTarget = tpLoc
				sCastMotive = '前往推塔:'..sLane

				if botName == 'npc_dota_hero_furion'
				then
					local Teleportation = bot:GetAbilityByName('furion_teleportation')
					if Teleportation:IsTrained()
					and Teleportation:IsFullyCastable()
					then
						bot.useProphetTP = true
						bot.ProphetTPLocation = hEffectTarget
						return BOT_ACTION_DESIRE_NONE
					end
				end

				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
		end
	end


	--保人
	if not laning and nMode == BOT_MODE_DEFEND_ALLY
		and nModeDesire >= BOT_MODE_DESIRE_MODERATE
		and J.Role.CanBeSupport( botName )
		and nEnemyCount == 0
	then
		local tpLoc
		local target = bot:GetTarget()
		if target ~= nil
			and target:IsHero()
			and GetUnitToUnitDistance( bot, target ) > nMinTPDistance and CanSpendOnTrip(target:GetLocation())
		then
			local bestTpLoc = J.GetNearbyLocationToTp( target:GetLocation() )
			if bestTpLoc ~= nil
				and GetUnitToLocationDistance( bot, bestTpLoc ) > nMinTPDistance - 800
			then
				tpLoc = bestTpLoc
			end
		end

		if tpLoc ~= nil
		then
			hEffectTarget = tpLoc
			sCastMotive = '支援队友:'..J.Chat.GetNormName( target )

			if botName == 'npc_dota_hero_furion'
			then
				local Teleportation = bot:GetAbilityByName('furion_teleportation')
				if Teleportation:IsTrained()
				and Teleportation:IsFullyCastable()
				then
					bot.useProphetTP = true
					bot.ProphetTPLocation = hEffectTarget
					return BOT_ACTION_DESIRE_NONE
				end
			end

			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end


	--塔下保人



	--撤退
	if nMode == BOT_MODE_RETREAT
		and nModeDesire >= BOT_MODE_DESIRE_MODERATE
		and bot:GetLevel() >= 3
		and not bot:HasModifier( "modifier_arc_warden_tempest_double" )
		and J.GetLaningHoldTower(bot) == nil
	then

		--第一种情况:无敌人无大药回家恢复
		if botHP < 0.19
			and ( bot:WasRecentlyDamagedByAnyHero( 8.0 ) or botHP < 0.12 )
			and botName ~= 'npc_dota_hero_huskar'
			and ( botName ~= 'npc_dota_hero_slark' or bot:GetLevel() <= 5 )
			and nEnemyCount == 0
			and itemFlask == nil
			and not bot:HasModifier( "modifier_tango_heal" )
			and not bot:HasModifier( "modifier_flask_healing" )
			and not bot:HasModifier( "modifier_juggernaut_healing_ward_heal" )
			and not bot:HasModifier( "modifier_item_urn_heal" )
			and not bot:HasModifier( "modifier_item_spirit_vessel_heal" )
			and bot:DistanceFromFountain() > nMinTPDistance
		then
			local tpLoc = J.GetTeamFountain()
			sCastMotive = '撤退:1'

			if botName == 'npc_dota_hero_furion'
			then
				local Teleportation = bot:GetAbilityByName('furion_teleportation')
				if Teleportation:IsTrained()
				and Teleportation:IsFullyCastable()
				then
					bot.useProphetTP = true
					bot.ProphetTPLocation = hEffectTarget
					return BOT_ACTION_DESIRE_NONE
				end
			end

			return BOT_ACTION_DESIRE_HIGH, tpLoc, sCastType, sCastMotive
		end


		--第二种情况:有多个敌人但可以卡视野TP
		local nAttackAllyList = J.GetNearbyHeroes(bot, 1500, false, BOT_MODE_ATTACK )
		if botHP < ( 0.15 + 0.24 * nEnemyCount )
			and #nAttackAllyList == 0
			and bot:WasRecentlyDamagedByAnyHero( 6.0 )
			and X.CanJuke()
			and nEnemyCount <= ( botHP < 0.4 and 2 or 3 )
			and nAllyCount <= 2
			and itemFlask == nil
			and not bot:HasModifier( "modifier_tango_heal" )
			and not bot:HasModifier( "modifier_flask_healing" )
			and not bot:HasModifier( "modifier_item_urn_heal" )
			and not bot:HasModifier( "modifier_item_spirit_vessel_heal" )
			and not bot:HasModifier( "modifier_juggernaut_healing_ward_heal" )
			and bot:DistanceFromFountain() > nMinTPDistance - 600
		then
			local tpLoc = J.GetTeamFountain()
			sCastMotive = '撤退:2'

			if botName == 'npc_dota_hero_furion'
			then
				local Teleportation = bot:GetAbilityByName('furion_teleportation')
				if Teleportation:IsTrained()
				and Teleportation:IsFullyCastable()
				then
					bot.useProphetTP = true
					bot.ProphetTPLocation = hEffectTarget
					return BOT_ACTION_DESIRE_NONE
				end
			end

			return BOT_ACTION_DESIRE_HIGH, tpLoc, sCastType, sCastMotive
		end


		--第三种情况:只有一个敌人直接T回家
		if ( botHP < 0.34 or botHP + botMP < 0.43 )
			and #nAttackAllyList == 0
			and bot:GetLevel() >= 9
			and X.CanJuke()
			and nEnemyCount <= 1
			and nAllyCount <= 2
			and itemFlask == nil
			and bot:GetAttackTarget() == nil
			and botName ~= 'npc_dota_hero_huskar'
			and botName ~= 'npc_dota_hero_slark'
			and not bot:HasModifier( "modifier_flask_healing" )
			and not bot:HasModifier( "modifier_clarity_potion" )
			and not bot:HasModifier( "modifier_filler_heal" )
			and not bot:HasModifier( "modifier_item_urn_heal" )
			and not bot:HasModifier( "modifier_item_spirit_vessel_heal" )
			and not bot:HasModifier( "modifier_juggernaut_healing_ward_heal" )
			and not bot:HasModifier( "modifier_bottle_regeneration" )
			and not bot:HasModifier( "modifier_tango_heal" )
			and bot:DistanceFromFountain() > nMinTPDistance - 600
		then
			local tpLoc = J.GetTeamFountain()
			sCastMotive = '撤退:3'

			if botName == 'npc_dota_hero_furion'
			then
				local Teleportation = bot:GetAbilityByName('furion_teleportation')
				if Teleportation:IsTrained()
				and Teleportation:IsFullyCastable()
				then
					bot.useProphetTP = true
					bot.ProphetTPLocation = hEffectTarget
					return BOT_ACTION_DESIRE_NONE
				end
			end

			return BOT_ACTION_DESIRE_HIGH, tpLoc, sCastType, sCastMotive
		end
	end


	--TP出去发育
	if not laning and nMode == BOT_MODE_FARM
		and bot:DistanceFromFountain() < 800
		and not X.IsBaseTowerDestroyed()
		and botHP > 0.9
		and botMP > 0.8
	then
		local tpLoc
		local mostFarmDesireLane, mostFarmDesire = J.GetMostFarmLaneDesire(bot)

		if mostFarmDesire > 0.1
		then
			local farmTpLoc = GetLaneFrontLocation( team, mostFarmDesireLane, 0 )
			local bestTpLoc = J.GetNearbyLocationToTp( farmTpLoc )
			if bestTpLoc ~= nil and farmTpLoc ~= nil
				and J.IsLocHaveTower( 2000, false, farmTpLoc )
				and GetUnitToLocationDistance( bot, bestTpLoc ) > nMinTPDistance
				and X.CanTeleportToFarm(farmTpLoc, bestTpLoc) and CanSpendOnTrip(farmTpLoc)
			then
				tpLoc = bestTpLoc
			end
		end

		if tpLoc ~= nil
		then
			hEffectTarget = tpLoc
			sCastMotive = '出去发育'

			if botName == 'npc_dota_hero_furion'
			then
				local Teleportation = bot:GetAbilityByName('furion_teleportation')
				if Teleportation:IsTrained()
				and Teleportation:IsFullyCastable()
				then
					bot.useProphetTP = true
					bot.ProphetTPLocation = hEffectTarget
					return BOT_ACTION_DESIRE_NONE
				end
			end

			return BOT_ACTION_DESIRE_ABSOLUTE, hEffectTarget, sCastType, sCastMotive
		end

	end


	--TP发育带线
	if not laning and bot:GetLevel() >= 10
		and nMode ~= BOT_MODE_ROSHAN
		and not X.IsBaseTowerDestroyed()
		and J.GetAllyCount( bot, 1600 ) <= 2
		and J.Role.ShouldTpToFarm()
		and not J.Role.IsAllyHaveAegis()
		and not J.Role.CanBeSupport( botName )
		and not J.IsEnemyHeroAroundLocation( GetAncient( team ):GetLocation(), 3300 )
	then
		local nAttackAllyList = J.GetNearbyHeroes(bot, 1600, false, BOT_MODE_ATTACK )
		local nNearEnemyList = J.GetNearbyHeroes(bot, 1400, true, BOT_MODE_NONE )
		local nCreeps= bot:GetNearbyCreeps( 1600, true )
		local mostFarmDesireLane, mostFarmDesire = J.GetMostFarmLaneDesire(bot)
		
		local tpLoc
		local isTravelBootsAvailable = false
		if J.IsItemAvailable( "item_travel_boots" )
			or J.IsItemAvailable( "item_travel_boots_2" )
		then
			isTravelBootsAvailable = true
		end

		if mostFarmDesire > ( isTravelBootsAvailable and 0.7 or 0.8 )
			and not midCover
			and not (J.ShouldKeepMidOpportunity and J.ShouldKeepMidOpportunity(bot, mostFarmDesireLane))
			and #nNearEnemyList == 0
			and #nCreeps == 0
			and #nAttackAllyList == 0
		then

			if isTravelBootsAvailable
			then
				tpLoc = GetLaneFrontLocation( team, mostFarmDesireLane, - 600 )
				local nNearAllyList = J.GetAlliesNearLoc( tpLoc, 1600 )
				if GetUnitToLocationDistance( bot, tpLoc ) > nMinTPDistance - 1500
					and #nNearAllyList == 0
					and X.CanTeleportToFarm(GetLaneFrontLocation(team, mostFarmDesireLane, 0), tpLoc) and CanSpendOnTrip(tpLoc)
				then
					J.Role['lastFarmTpTime'] = DotaTime()
					sCastMotive = '飞鞋带线'

					if botName == 'npc_dota_hero_furion'
					then
						local Teleportation = bot:GetAbilityByName('furion_teleportation')
						if Teleportation:IsTrained()
						and Teleportation:IsFullyCastable()
						then
							bot.useProphetTP = true
							bot.ProphetTPLocation = tpLoc
							return BOT_ACTION_DESIRE_NONE
						end
					end

					return BOT_ACTION_DESIRE_HIGH, tpLoc, sCastType, sCastMotive
				end
			end

			tpLoc = GetLaneFrontLocation( team, mostFarmDesireLane, 0 )
			local bestTpLoc = J.GetNearbyLocationToTp( tpLoc )
			local nNearAllyList = J.GetAlliesNearLoc( tpLoc, 1600 )
			if bestTpLoc ~= nil
				and J.IsLocHaveTower( 1850, false, tpLoc )
				and GetUnitToLocationDistance( bot, bestTpLoc ) > nMinTPDistance - 800
				and #nNearAllyList == 0
				and X.CanTeleportToFarm(tpLoc, bestTpLoc) and CanSpendOnTrip(tpLoc)
			then
				J.Role['lastFarmTpTime'] = DotaTime()
				sCastMotive = '线上打钱'

				if botName == 'npc_dota_hero_furion'
				then
					local Teleportation = bot:GetAbilityByName('furion_teleportation')
					if Teleportation:IsTrained()
					and Teleportation:IsFullyCastable()
					then
						bot.useProphetTP = true
						bot.ProphetTPLocation = bestTpLoc
						return BOT_ACTION_DESIRE_NONE
					end
				end

				return BOT_ACTION_DESIRE_HIGH, bestTpLoc, sCastType, sCastMotive
			end
		end
	end


	--支援团战和守家
	if bot:GetLevel() > 10
		and nMode ~= BOT_MODE_SECRET_SHOP
		and nMode ~= BOT_MODE_ROSHAN
		and nMode ~= BOT_MODE_ATTACK
		and ( botTarget == nil or not botTarget:IsHero() )
		--and J.GetAllyCount( bot, 1600 ) <= 3 --守护遗迹bug
	then
		local nNearEnemyList = J.GetNearbyHeroes(bot, 1400, true, BOT_MODE_NONE )
		local nTeamFightLocation = J.GetTeamFightLocation( bot )
		local isTravelBootsAvailable = false
		if J.IsItemAvailable( "item_travel_boots" )
			or J.IsItemAvailable( "item_travel_boots_2" )
		then
			isTravelBootsAvailable = true
		end

		if botName == 'npc_dota_hero_spectre'
		then
			local ShadowStep = bot:GetAbilityByName('spectre_shadow_step')
			local Haunt = bot:GetAbilityByName('spectre_haunt')

			if (ShadowStep:IsFullyCastable())
			or (Haunt:IsTrained() and Haunt:IsFullyCastable())
			then
				return BOT_ACTION_DESIRE_NONE
			end
		end
		
		if #nNearEnemyList == 0
			and nTeamFightLocation ~= nil
			and GetUnitToLocationDistance( bot, nTeamFightLocation ) > nMinTPDistance - 1200
			and J.CanJoinObservedFightByTeleport(bot, nTeamFightLocation) and CanSpendOnTrip(nTeamFightLocation)
		then

			if isTravelBootsAvailable and J.CanCommitToLaneTeleport(bot, nTeamFightLocation)
			then
				sCastMotive = '飞鞋支援团战距离:'..GetUnitToLocationDistance( bot, nTeamFightLocation )

				if botName == 'npc_dota_hero_furion'
				then
					local Teleportation = bot:GetAbilityByName('furion_teleportation')
					if Teleportation:IsTrained()
					and Teleportation:IsFullyCastable()
					then
						bot.useProphetTP = true
						bot.ProphetTPLocation = nTeamFightLocation
						return BOT_ACTION_DESIRE_NONE
					end
				end

				return BOT_ACTION_DESIRE_HIGH, nTeamFightLocation, sCastType, sCastMotive
			end

			local bestTpLoc = J.GetNearbyLocationToTp( nTeamFightLocation )
			if bestTpLoc ~= nil
				and J.GetLocationToLocationDistance( bestTpLoc, nTeamFightLocation ) < 1800
				and GetUnitToLocationDistance( bot, bestTpLoc ) > nMinTPDistance - 1200
				and J.CanCommitToLaneTeleport(bot, bestTpLoc)
			then
				sCastMotive = '支援团战:'..GetUnitToLocationDistance( bot, nTeamFightLocation )

				if botName == 'npc_dota_hero_furion'
				then
					local Teleportation = bot:GetAbilityByName('furion_teleportation')
					if Teleportation:IsTrained()
					and Teleportation:IsFullyCastable()
					then
						bot.useProphetTP = true
						bot.ProphetTPLocation = bestTpLoc
						return BOT_ACTION_DESIRE_NONE
					end
				end

				return BOT_ACTION_DESIRE_HIGH, bestTpLoc, sCastType, sCastMotive
			end
		end

		--守护遗迹
		local nAncient = GetAncient( team )
		if bot:GetLevel() >= 15	
			and #nNearEnemyList == 0
			and J.Role.ShouldTpToFarm()
			and bot:DistanceFromFountain() > 2000
			and GetUnitToUnitDistance( bot, nAncient ) > nMinTPDistance - 200
			and J.GetAroundTargetAllyHeroCount( nAncient, 1400 ) == 0
		then
			local nEnemyLaneFront = J.GetNearestLaneFrontLocation( nAncient:GetLocation(), true, 400 )
			if nEnemyLaneFront ~= nil
				and GetUnitToLocationDistance( nAncient, nEnemyLaneFront ) <= 1600
			then

				J.Role['lastFarmTpTime'] = DotaTime()
				sCastMotive = '守护遗迹'

				if botName == 'npc_dota_hero_furion'
				then
					local Teleportation = bot:GetAbilityByName('furion_teleportation')
					if Teleportation:IsTrained()
					and Teleportation:IsFullyCastable()
					then
						bot.useProphetTP = true
						bot.ProphetTPLocation = nAncient:GetLocation()
						return BOT_ACTION_DESIRE_NONE
					end
				end

				return BOT_ACTION_DESIRE_HIGH, nAncient:GetLocation(), sCastType, sCastMotive
			end
			
			local ancientTower1 = GetTower(team, 9)
			local ancientTower2 = GetTower(team, 10)
			if ancientTower1 == nil and ancientTower2 == nil
--				and nAncient:WasRecentlyDamagedByCreep( 5.0 )
			then
				local nAllEnemyCreeps = GetUnitList( UNIT_LIST_ENEMY_CREEPS )
				for _, creep in pairs( nAllEnemyCreeps )
				do
					if J.IsValid(creep)
					and GetUnitToUnitDistance( nAncient, creep ) <= 800
					and ( creep:GetAttackTarget() == nAncient or bot:GetLevel() >= 15 )
					then
						J.Role['lastFarmTpTime'] = DotaTime()
						sCastMotive = '保护遗迹'

						if botName == 'npc_dota_hero_furion'
						then
							local Teleportation = bot:GetAbilityByName('furion_teleportation')
							if Teleportation:IsTrained()
							and Teleportation:IsFullyCastable()
							then
								bot.useProphetTP = true
								bot.ProphetTPLocation = nAncient:GetLocation()
								return BOT_ACTION_DESIRE_NONE
							end
						end

						return BOT_ACTION_DESIRE_HIGH, nAncient:GetLocation(), sCastType, sCastMotive
					end
				end
			end
			
		end

	end

	--回复状态
	if ( botHP + botMP < 0.3 or botHP < 0.2 )
		and bot:GetLevel() >= 6
		and botName ~= 'npc_dota_hero_huskar'
		and botName ~= 'npc_dota_hero_slark'
		and not bot:HasModifier( "modifier_arc_warden_tempest_double" )
	then
		if	X.CanJuke()
			and bot:DistanceFromFountain() > nMinTPDistance + 200
			and nEnemyCount <= 1 and nAllyCount <= 1
			and J.GetProperTarget( bot ) == nil
			and itemFlask == nil
			and bot:GetAttackTarget() == nil
			and not bot:HasModifier( "modifier_flask_healing" )
			and not bot:HasModifier( "modifier_clarity_potion" )
			and not bot:HasModifier( "modifier_filler_heal" )
			and not bot:HasModifier( "modifier_item_urn_heal" )
			and not bot:HasModifier( "modifier_item_spirit_vessel_heal" )
			and not bot:HasModifier( "modifier_juggernaut_healing_ward_heal" )
			and not bot:HasModifier( "modifier_bottle_regeneration" )
			and not bot:HasModifier( "modifier_tango_heal" )
		then
			tpLoc = J.GetTeamFountain()
		end

		if tpLoc ~= nil
		then
			hEffectTarget = tpLoc
			sCastMotive = '回复状态'

			if botName == 'npc_dota_hero_furion'
			then
				local Teleportation = bot:GetAbilityByName('furion_teleportation')
				if Teleportation:IsTrained()
				and Teleportation:IsFullyCastable()
				then
					bot.useProphetTP = true
					bot.ProphetTPLocation = hEffectTarget
					return BOT_ACTION_DESIRE_NONE
				end
			end

			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	--血魔大
	if bot:HasModifier( 'modifier_bloodseeker_rupture' ) and nEnemyCount <= 1
		and J.GetModifierTime( bot, "modifier_bloodseeker_rupture" ) >= 3.1
	then
		local nAllyCount = J.GetNearbyHeroes(bot, 1000, false, BOT_MODE_NONE )
		if #nAllyCount <= 1 and X.CanJuke()
		then
			tpLoc = J.GetTeamFountain()
		end

		if tpLoc ~= nil
		then
			hEffectTarget = tpLoc
			sCastMotive = '躲血魔大'

			if botName == 'npc_dota_hero_furion'
			then
				local Teleportation = bot:GetAbilityByName('furion_teleportation')
				if Teleportation:IsTrained()
				and Teleportation:IsFullyCastable()
				then
					bot.useProphetTP = true
					bot.ProphetTPLocation = hEffectTarget
					return BOT_ACTION_DESIRE_NONE
				end
			end

			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	--处理特殊情况一
	if X.IsFarmingAlways( bot )
	then
		tpLoc = GetAncient( team ):GetLocation()
		sCastMotive = '处理特殊情况一'

		if botName == 'npc_dota_hero_furion'
		then
			local Teleportation = bot:GetAbilityByName('furion_teleportation')
			if Teleportation:IsTrained()
			and Teleportation:IsFullyCastable()
			then
				bot.useProphetTP = true
				bot.ProphetTPLocation = tpLoc
				return BOT_ACTION_DESIRE_NONE
			end
		end

		return BOT_ACTION_DESIRE_HIGH, tpLoc, sCastType, sCastMotive
	end

	--处理特殊情况二
	if J.IsStuck( bot ) --and nEnemyCount == 0
	then
		tpLoc = GetAncient( team ):GetLocation()
		sCastMotive = '处理特殊情况二'

		if botName == 'npc_dota_hero_furion'
		then
			local Teleportation = bot:GetAbilityByName('furion_teleportation')
			if Teleportation:IsTrained()
			and Teleportation:IsFullyCastable()
			then
				bot.useProphetTP = true
				bot.ProphetTPLocation = tpLoc
				return BOT_ACTION_DESIRE_NONE
			end
		end

		return BOT_ACTION_DESIRE_HIGH, tpLoc, sCastType, sCastMotive
	end
	
	if J.Role.ShouldTpToDefend()
	and bot:DistanceFromFountain() > 3800
	then
		tpLoc = GetAncient( team ):GetLocation()
		sCastMotive = '立即TP守家'
		return BOT_ACTION_DESIRE_HIGH, tpLoc, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end


--骨灰
X.ConsiderItemDesire["item_urn_of_shadows"] = function( hItem )

	if hItem:GetCurrentCharges() == 0 then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 950 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget ) and 
			((J.CanCastOnNonMagicImmune( botTarget )
				and J.IsInRange( bot, botTarget, nCastRange )
				and not botTarget:HasModifier( "modifier_item_urn_damage" )
				and not botTarget:HasModifier( "modifier_item_spirit_vessel_damage" )
				and not botTarget:HasModifier( "modifier_arc_warden_tempest_double" )
				and ( J.GetHP( botTarget ) < 0.95 or J.IsInRange( bot, botTarget, 700 ) ))
			or botTarget:HasModifier( "modifier_invoker_cold_snap_freeze" ) -- 配合急速冷却
		) then
			hEffectTarget = botTarget
			sCastMotive = "进攻:"..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	if bot:GetActiveMode() ~= BOT_MODE_ROSHAN
	then
		local hAllyList = J.GetNearbyHeroes(bot, nCastRange + 80, false, BOT_MODE_NONE )
		local hNeedHealAlly = nil
		local nNeedHealAllyHealth = 99999
		for _, npcAlly in pairs( hAllyList )
		do
			if J.IsValid( npcAlly )
				and not npcAlly:IsIllusion()
				and npcAlly:DistanceFromFountain() > 800
				and J.CanCastOnNonMagicImmune( npcAlly )
				and not npcAlly:WasRecentlyDamagedByAnyHero( 3.1 )
				and not npcAlly:HasModifier( "modifier_item_spirit_vessel_heal" )
				and not npcAlly:HasModifier( "modifier_item_urn_heal" )
				and not npcAlly:HasModifier( "modifier_fountain_aura" )
				and not npcAlly:HasModifier( "modifier_arc_warden_tempest_double" )
				and npcAlly:OriginalGetMaxHealth() - npcAlly:OriginalGetHealth() > 450
				and #hNearbyEnemyHeroList == 0 
			then
				if( npcAlly:OriginalGetHealth() < nNeedHealAllyHealth )
				then
					hNeedHealAlly = npcAlly
					nNeedHealAllyHealth = npcAlly:OriginalGetHealth()
				end
			end
		end

		if( hNeedHealAlly ~= nil )
		then
			hEffectTarget = hNeedHealAlly
			sCastMotive = '治疗:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--纷争
X.ConsiderItemDesire["item_veil_of_discord"] = function( hItem )

	local nCastRange = 900
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange + 50, true, BOT_MODE_NONE )

	local hNearbyCreepList = bot:GetNearbyCreeps( nCastRange, true )
	if #hNearbyCreepList >= 6
		or #nInRangeEnmyList >= 1
	then
		hEffectTarget = bot
		sCastMotive = '启动希瓦'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end



--真眼
local function ConsiderCombatSentry(hItem)
	if J.Item.GetSentryCharges(hItem) <= 0
		or not (J.IsGoingOnSomeone(bot) or J.IsDefending(bot) or J.IsInLaningPhase(bot)) then
		return BOT_ACTION_DESIRE_NONE
	end
	for _, enemy in ipairs(J.GetEnemiesNearLoc(bot:GetLocation(), 900)) do
		local point = enemy:GetLocation()
		if (enemy:IsInvisible() or J.IsUnitWillGoInvisible(enemy, true) or J.HasInvisibilityOrItem(enemy))
			and not J.HasInvisCounterBuff(enemy) and not J.HasLocalTrueSight(point)
			and not J.HasDustCoverage(point, 0, 0.65) then
			if hItem:GetName() == 'item_ward_dispenser' and hItem:GetToggleState() then
				return BOT_ACTION_DESIRE_HIGH, bot, 'unit', '切换至真眼'
			end
			local location = J.GetUnitTowardDistanceLocation(bot, enemy, 500 + aetherRange)
			return BOT_ACTION_DESIRE_HIGH, location, 'ground', '在交战位置插真眼', function()
				J.RecordSentryOrder(bot, location)
			end
		end
	end
	return BOT_ACTION_DESIRE_NONE
end

X.ConsiderItemDesire["item_ward_sentry"] = ConsiderCombatSentry
X.ConsiderItemDesire["item_ward_dispenser"] = ConsiderCombatSentry


--GG树
local lastKACount = -1
X.ConsiderItemDesire["item_ironwood_tree"] = function( hItem )

	local nCastRange = 600
	local sCastType = 'ground'
	local hEffectTarget = nil
	local sCastMotive = nil

	if lastKACount == -1 then lastKACount = GetHeroKills( bot:GetPlayerID() ) + GetHeroAssists( bot:GetPlayerID() ) end

	if lastKACount < GetHeroKills( bot:GetPlayerID() ) + GetHeroAssists( bot:GetPlayerID() )
	then
		lastKACount = -1
		hEffectTarget = J.GetFaceTowardDistanceLocation( bot, nCastRange )
		sCastMotive = 'GG'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--精华指环
X.ConsiderItemDesire["item_essence_ring"] = function( hItem )

	if bot:DistanceFromFountain() < 1000 then return 0 end

	local nCastRange = 600
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, 1400, true, BOT_MODE_NONE )

	if bot:GetMaxHealth() - bot:GetHealth() > 600
		and J.IsAllowedToSpam( bot, 200 )
	then
		hEffectTarget = bot
		sCastMotive = '治疗自己'
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return X.ConsiderItemDesire["item_faerie_fire"]( hItem )

end

X.ConsiderItemDesire["item_ash_legion_shield"] = function( hItem )
	local nRadius = hItem:GetSpecialValueInt('block_radius')
	local unitList = GetUnitList(UNIT_LIST_ALLIES)

	local countControlledCreep = 0
	local countControlledHero = 0

	for _, unit in pairs(unitList) do
		if J.IsValid(unit) and J.IsInRange(bot, unit, nRadius) then
			local sUnitName = unit:GetUnitName()

			if unit:IsHero() and (unit:IsIllusion() or string.find(sUnitName, 'bear')) then
				countControlledHero = countControlledHero + 1
			end

			if string.find(sUnitName, 'golem') then
				return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
			end

			if string.find(sUnitName, 'spiderlings')
			or string.find(sUnitName, 'forge_spirit')
			or string.find(sUnitName, 'golem')
			or string.find(sUnitName, 'boar')
			or string.find(sUnitName, 'furion_treant')
			or string.find(sUnitName, 'familiars')
			or unit:IsDominated()
			or unit:HasModifier('modifier_chen_holy_persuasion')
			then
				countControlledCreep = countControlledCreep + 1
			end
		end
	end

	if J.IsGoingOnSomeone(bot) then
		if bot:WasRecentlyDamagedByAnyHero(2.0) and (countControlledCreep >= 2 or countControlledHero >= 2) then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

X.ConsiderItemDesire["item_flayers_bota"] = function( hItem )

	if J.IsGoingOnSomeone(bot) then
		if  J.IsValidHero(botTarget)
		and J.CanBeAttacked(botTarget)
		and not J.IsSuspiciousIllusion(botTarget)
		and bAttacking
		then
			return BOT_ACTION_DESIRE_HIGH, nil, ITEM_TARGET_TYPE_NONE
		end
	end

	if J.IsDoingRoshan(bot) then
		if J.IsRoshan(botTarget)
		and J.CanBeAttacked(botTarget)
		and J.IsInRange(bot, botTarget, botAttackRange + 150)
		and #nEnemyHeroes == 0
		and bAttacking
		then
			return BOT_ACTION_DESIRE_HIGH, nil, ITEM_TARGET_TYPE_NONE
		end
	end

	if J.IsDoingTormentor(bot) then
		if J.IsTormentor(botTarget)
		and J.IsInRange(bot, botTarget, botAttackRange + 150)
		and #nEnemyHeroes == 0
		and bAttacking
		then
			return BOT_ACTION_DESIRE_HIGH, nil, ITEM_TARGET_TYPE_NONE
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

X.ConsiderItemDesire["item_idol_of_screeauk"] = function( hItem )

	if J.IsGoingOnSomeone(bot) then
		if bot:WasRecentlyDamagedByAnyHero(2.0) and J.IsRunning(bot) then
			return BOT_ACTION_DESIRE_HIGH, nil, ITEM_TARGET_TYPE_NONE
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

X.ConsiderItemDesire["item_jidi_pollen_bag"] = function( hItem )

	local nRadius = hItem:GetSpecialValueInt('debuff_radius')

	local nInRangeEnemy = J.GetEnemiesNearLoc(botLocation, nRadius)

	if J.IsInTeamFight(bot, 1200) then
        if #nInRangeEnemy >= 2 then
            local count = 0
            for _, enemyHero in pairs(nInRangeEnemy) do
                if J.IsValidHero(enemyHero)
                and J.CanBeAttacked(enemyHero)
                and J.CanCastOnNonMagicImmune(enemyHero)
				and not enemyHero:HasModifier('modifier_doom_bringer_doom_aura_enemy')
				and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
				and not enemyHero:HasModifier('modifier_ice_blast')
				and not enemyHero:HasModifier('modifier_item_spirit_vessel_damage')
                then
                    count = count + 1
                end
            end

            if count >= 2 then
                return BOT_ACTION_DESIRE_HIGH, nil, ITEM_TARGET_TYPE_NONE
            end
        end
    end

    if J.IsGoingOnSomeone(bot) then
        if  J.IsValidHero(botTarget)
        and J.CanBeAttacked(botTarget)
        and J.IsInRange(bot, botTarget, nRadius)
        and J.CanCastOnNonMagicImmune(botTarget)
        and not botTarget:HasModifier('modifier_doom_bringer_doom_aura_enemy')
		and not botTarget:HasModifier('modifier_necrolyte_reapers_scythe')
		and not botTarget:HasModifier('modifier_ice_blast')
		and not botTarget:HasModifier('modifier_item_spirit_vessel_damage')
        then
			return BOT_ACTION_DESIRE_HIGH, nil, ITEM_TARGET_TYPE_NONE
        end
	end

	return BOT_ACTION_DESIRE_NONE
end

X.ConsiderItemDesire["item_metamorphic_mandible"] = function( hItem )

	local nDuration = hItem:GetSpecialValueInt('duration')

	if J.IsGoingOnSomeone(bot) then
		if bot:WasRecentlyDamagedByAnyHero(2.0) then
			local enemyDamage = 0
			for _, enemyHero in pairs(nEnemyHeroes) do
				if  J.IsValidHero(enemyHero)
				and not J.IsSuspiciousIllusion(enemyHero)
				and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
				and not enemyHero:IsChanneling()
				then
					if enemyHero:GetAttackTarget() == bot
					or J.IsChasingTarget(enemyHero, bot)
					or enemyHero:IsFacingLocation(bot:GetLocation(), 15)
					or bot:WasRecentlyDamagedByHero(enemyHero, 3.0)
					then
						enemyDamage = enemyDamage + (enemyHero:GetAttackDamage() * enemyHero:GetAttackSpeed() * nDuration)
					end
				end
			end

			if bot:GetActualIncomingDamage(enemyDamage * 1.5, DAMAGE_TYPE_PHYSICAL) < bot:GetHealth() then
				return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

X.ConsiderItemDesire["item_riftshadow_prism"] = function( hItem )
	local fHealthCostPct = hItem:GetSpecialValueInt('health_cost')

	if J.IsGoingOnSomeone(bot) then
		if bot:WasRecentlyDamagedByAnyHero(2.0) and J.GetHealthAfter(bot:GetHealth() * fHealthCostPct) > 0.2 then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

--网虫腿
X.ConsiderItemDesire["item_spider_legs"] = function( hItem )

	return X.ConsiderItemDesire["item_phase_boots"]( hItem )

end


--闪灵
X.ConsiderItemDesire["item_flicker"] = function( hItem )

	if bot:DistanceFromFountain() < 600 or bot:IsRooted() then return BOT_ACTION_DESIRE_NONE end

	local nCastRange = 600
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, 800, true, BOT_MODE_NONE )

	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and ( bot:IsSilenced() or bot:IsRooted() )
		then
			hEffectTarget = bot
			sCastMotive = '驱散沉默或缠绕'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end


	if J.IsRetreating( bot )
		and bot:WasRecentlyDamagedByAnyHero( 3.0 )
		and #nInRangeEnmyList >= 1
	then
		hEffectTarget = bot
		sCastMotive = "撤退"
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end


	return BOT_ACTION_DESIRE_NONE

end

--幻术师披风
X.ConsiderItemDesire["item_illusionsts_cape"] = function( hItem )

	local nCastRange = 800
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil

	if J.IsValid( botTarget )
		and J.IsInRange( bot, botTarget, nCastRange )
	then
		hEffectTarget = botTarget
		sCastMotive = "辅助攻击"
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return X.ConsiderItemDesire["item_manta"]( hItem )

end

--灵犀角
-- X.ConsiderItemDesire["item_minotaur_horn"] = function( hItem )

-- 	return X.ConsiderItemDesire["item_black_king_bar"]( hItem )

-- end

--林地神行靴
X.ConsiderItemDesire["item_woodland_striders"] = function( hItem )

	if bot:DistanceFromFountain() < 600 then return 0 end

	local nCastRange = 800
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil

	if J.IsRetreating( bot )
		and bot:WasRecentlyDamagedByAnyHero( 4.0 )
	then
		hEffectTarget = bot
		sCastMotive = "撤退"
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end

--堕天斧
X.ConsiderItemDesire["item_fallen_sky"] = function( hItem )

	local nCastRange = 1600
	local sCastType = 'ground'
	local nRadius = 315
	local nCastDelay = 0.5
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE )


	if J.IsGoingOnSomeone( bot )
	then
		local nAoeLocation = J.GetAoeEnemyHeroLocation( bot, nCastRange, nRadius, 2 )
		if nAoeLocation ~= nil
		then
			hEffectTarget = nAoeLocation
			sCastMotive = 'Aoe'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end

		if J.IsValidHero( botTarget )
			and J.CanCastOnNonMagicImmune( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
		then
			local nCastLocation = J.GetDelayCastLocation( bot, botTarget, nCastRange, nRadius, nCastDelay )
			if nCastLocation ~= nil
			then
				hEffectTarget = nCastLocation
				sCastMotive = "进攻"
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	if J.IsRetreating( bot )
		and bot:WasRecentlyDamagedByAnyHero( 3.0 )
	then
		local bLocation = J.GetLocationTowardDistanceLocation( bot, GetAncient( team ):GetLocation(), 1600 )
		local nAttackAllyList = J.GetNearbyHeroes(bot, 800, false, BOT_MODE_ATTACK )
		if bot:DistanceFromFountain() > 800
			and IsLocationPassable( bLocation )
			and ( #nAttackAllyList == 0 or bot:GetActiveModeDesire() > BOT_MODE_DESIRE_VERYHIGH * 0.9 )
			and #nInRangeEnmyList >= 1
		then
			hEffectTarget = bLocation
			sCastMotive = "撤退"
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--机械之心
X.ConsiderItemDesire["item_ex_machina"] = function( hItem )

	local nCastRange = 800
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
		then
			local nSoltList = { 0, 1, 2, 3, 4, 5 }
			local nRemainTime = 0
			for _, nSlot in pairs( nSoltList )
			do
				local hItem = bot:GetItemInSlot( nSlot )
				if hItem ~= nil and hItem:GetName() ~= 'item_refresher'
				then
					local nCooldownTime = hItem:GetCooldownTimeRemaining()
					nRemainTime = nRemainTime + nCooldownTime
				end
			end

			if nRemainTime >= 30
			then
				hEffectTarget = botTarget
				sCastMotive = "刷新CD"
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--风暴宝器
X.ConsiderItemDesire["item_stormcrafter"] = function( hItem )

	local nCastRange = 300 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )


	if J.CanCastOnNonMagicImmune( bot )
		and #nInRangeEnmyList > 0
	then
		if bot:IsRooted()
			or ( bot:GetPrimaryAttribute() == ATTRIBUTE_INTELLECT and bot:IsSilenced() )
		then
			hEffectTarget = bot
			sCastMotive = '解缠绕:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end

		if J.IsUnitTargetProjectileIncoming( bot, 400 )
		then
			hEffectTarget = bot
			sCastMotive = '防御弹道:'..J.Chat.GetNormName( hEffectTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

--缚灵索
X.ConsiderItemDesire["item_gungir"] = function( hItem )
	local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1000)
	for _, enemyHero in pairs(nInRangeEnemy)
	do
		if J.IsValidTarget(enemyHero)
		and J.IsUnitWillGoInvisible(enemyHero)
		and J.IsClosestToDustLocation(bot, enemyHero:GetLocation())
		and not J.HasInvisCounterBuff(enemyHero)
		and not J.IsSuspiciousIllusion(enemyHero)
		then
			if hItem:GetName() == "item_gungir" then hEffectTarget = enemyHero:GetLocation() end
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, 'unit', 'Stop invis'
		end	
	end	

	return X.ConsiderItemDesire["item_rod_of_atos"]( hItem )

end

--杂技玩具
X.ConsiderItemDesire["item_pogo_stick"] = function( hItem )

	local nCastRange = 1000
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	--追击敌人
	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and J.IsInRange( bot, botTarget, bot:GetAttackRange() + 400 )
			and J.CanCastOnMagicImmune( botTarget )
			and J.IsChasingTarget( bot, botTarget )
		then
			hEffectTarget = botTarget
			sCastMotive = "进攻:"..J.Chat.GetNormName( botTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end
	
	--撤退了推自己
	if ( nMode == BOT_MODE_RETREAT and bot:GetActiveModeDesire() > BOT_MODE_DESIRE_HIGH )
	then
		
		if bot:IsFacingLocation( GetAncient( team ):GetLocation(), 20 )
			and bot:DistanceFromFountain() > 600
			and #nInRangeEnmyList >= 1
		then
			hEffectTarget = bot
			sCastMotive = '撤退了推自己'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--仙灵榴弹
X.ConsiderItemDesire["item_paintball"] = function( hItem )

	local nCastRange = 900 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsValidHero( botTarget )
		and J.CanCastOnNonMagicImmune( botTarget )
		and J.CanCastOnTargetAdvanced( botTarget )
		and J.IsInRange( botTarget, bot, nCastRange )
	then
		hEffectTarget = botTarget
		sCastMotive = '仙灵榴弹:'..J.Chat.GetNormName( hEffectTarget )
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE

end


--行巫之祸
X.ConsiderItemDesire["item_heavy_blade"] = function( hItem )

	local nCastRange = 500
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	--驱散友军
	for i = 1, #GetTeamPlayers( GetTeam() )
	do 
		local npcAlly = GetTeamMember( i )
		if J.IsValidHero( npcAlly )
			and J.IsInRange( bot, npcAlly, nCastRange + 100 )
		then
			if ( J.IsGoingOnSomeone( npcAlly ) or J.IsRetreating( npcAlly ) )
				and npcAlly:WasRecentlyDamagedByAnyHero( 2.0 )
				and J.GetHP( npcAlly ) < 0.85
			then
				local nEnemyList = J.GetNearbyHeroes(npcAlly,  300, true, BOT_MODE_NONE )
				local npcEnemy = nEnemyList[1]
				if J.IsValidHero( npcEnemy )
					and J.CanCastOnMagicImmune( npcEnemy )
				then
					hEffectTarget = npcAlly
					sCastMotive = "行巫之祸驱散友军:"..J.Chat.GetNormName( npcAlly )
					return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
				end
			end
		end	
	end
	
		
	--驱散敌军
	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and J.IsInRange( bot, botTarget, nCastRange )
			and J.CanCastOnNonMagicImmune( botTarget )
		then
			-- if botTarget:HasModifier("")
				-- or botTarget:HasModifier("")
			if botTarget:WasRecentlyDamagedByAnyHero( 3.0 )
				and J.GetHP( botTarget ) < 0.7
			then
				hEffectTarget = botTarget
				sCastMotive = "行巫之祸驱散敌军:"..J.Chat.GetNormName( botTarget )
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end
	

	return BOT_ACTION_DESIRE_NONE

end

-- 7.42: Revenant's Brooch is now a passive Tier 3 neutral artifact.
-- No active-item handler: the old attack-toggle cast must not be attempted.

--怨灵之契
X.ConsiderItemDesire["item_wraith_pact"] = function( hItem )

	local nCastRange = 200 + aetherRange
	local sCastType = 'ground'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
			and botTarget:GetAttackTarget() ~= nil
			and J.IsInRange( bot, botTarget, 900 )
			and J.CanCastOnNonMagicImmune( botTarget )
		then
			hEffectTarget = J.GetFaceTowardDistanceLocation( bot, 200 )
			sCastMotive = "怨灵之契进攻:"..J.Chat.GetNormName( botTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end


--宽容之鞋
X.ConsiderItemDesire["item_boots_of_bearing"] = function( hItem )

	return X.ConsiderItemDesire["item_ancient_janggo"]( hItem )

end


--新物品
X.ConsiderItemDesire["item_new"] = function( hItem )

	local nCastRange = 300 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )


	if J.IsGoingOnSomeone( bot )
	then
		if J.IsValidHero( botTarget )
		then
			hEffectTarget = botTarget
			sCastMotive = "进攻:"..J.Chat.GetNormName( botTarget )
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	return BOT_ACTION_DESIRE_NONE

end

-- ADDED EXISTING ITEMS FUNCTIONALITY

--item_soul_ring
X.ConsiderItemDesire['item_soul_ring'] = function(item)

	local sCastType = 'none'
	local hEffectTarget = bot
	local sCastMotive = nil
	local aMode = bot:GetActiveMode()

	local currMana = bot:GetMana() / bot:GetMaxMana()
	local currHealth = bot:OriginalGetHealth() / bot:OriginalGetMaxHealth()

	if (aMode == BOT_MODE_FARM or aMode == BOT_MODE_LANING)
	and currHealth > 0.5 and currMana < 0.5
	then
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	return BOT_ACTION_DESIRE_NONE
end

-- 7.33 New Items
X.ConsiderItemDesire['item_pavise'] = function(item)
	local nCastRange = 1000 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )
	local nNearAllyList = J.GetNearbyHeroes(bot, nCastRange, false, BOT_MODE_NONE )
	local health = bot:OriginalGetHealth() / bot:OriginalGetMaxHealth()

	--对可能被作为敌方目标的队友使用
	for _, npcAlly in pairs( nNearAllyList )
	do
		if J.IsValidHero( npcAlly )
			and npcAlly ~= bot
			and not npcAlly:IsMagicImmune()
			and not npcAlly:IsInvulnerable()
			and not npcAlly:IsIllusion()
			and not npcAlly:HasModifier( "modifier_item_pavise_shield" )
			and not npcAlly:HasModifier( 'modifier_antimage_spell_shield' )
			and ( J.IsUnitTargetProjectileIncoming( npcAlly, 800 )
				 or J.IsWillBeCastUnitTargetSpell( npcAlly, 1200 )
				 or health < 0.2 )
		then
			hEffectTarget = npcAlly
			sCastMotive = '帮助队友'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end


	if J.IsValidHero( botTarget )
		and J.IsInRange( bot, botTarget, 2400 )
		and not J.IsInRange( bot, botTarget, 800 )
	then
		if #nNearAllyList >= 2
		then
			local targetAlly = nil
			local targetDistance = 9999
			for _, npcAlly in pairs( nNearAllyList )
			do
				if npcAlly ~= bot
					and not npcAlly:IsIllusion()
					and J.IsInRange( npcAlly, botTarget, targetDistance )
					and not npcAlly:HasModifier( "modifier_item_pavise_shield" )
					and not npcAlly:HasModifier( 'modifier_antimage_spell_shield' )
				then
					targetAlly = npcAlly
					targetDistance = GetUnitToUnitDistance( botTarget, npcAlly )
					if J.IsHumanPlayer( npcAlly ) then break end
				end
			end
			if targetAlly ~= nil
			then
				hEffectTarget = targetAlly
				sCastMotive = '先给前排套上'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

X.ConsiderItemDesire['item_harpoon'] = function(item)
	local nCastRange = 700 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil

	local nAttackRange = bot:GetAttackRange()
	local botTarget = J.GetProperTarget(bot)

	if J.IsGoingOnSomeone(bot)
	then
		if J.IsValidTarget(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange + nAttackRange)
		and not J.IsInRange(bot, botTarget, nCastRange / 2)
		and not J.IsSuspiciousIllusion(botTarget)
		then
			hEffectTarget = botTarget
			sCastMotive = 'Harpoon'

			if J.WeAreStronger(bot, nCastRange + nAttackRange)
			then
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			else
				return BOT_ACTION_DESIRE_MODERATE, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

X.ConsiderItemDesire['item_disperser'] = function(item)
	local nCastRange = 600 + aetherRange
	local sCastType = 'unit'
	local hEffectTarget = nil
	local sCastMotive = nil

	local nAttackRange = bot:GetAttackRange()
	local botTarget = J.GetProperTarget(bot)
	local nAllyHeroes = J.GetNearbyHeroes(bot,nCastRange, false, BOT_MODE_NONE)
	local nEnemyHeroes = J.GetNearbyHeroes(bot,nCastRange + nAttackRange, true, BOT_MODE_NONE)

	if J.IsDisabled(bot)
	then
		if nEnemyHeroes ~= nil and #nEnemyHeroes >= 1
		then
			hEffectTarget = bot
			sCastMotive = 'Disperser'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	for _, allyHero in pairs(nAllyHeroes)
	do
		if nEnemyHeroes ~= nil and #nEnemyHeroes >= 1
		and allyHero:WasRecentlyDamagedByAnyHero(2)
		and not J.IsSuspiciousIllusion(allyHero)
		then
			hEffectTarget = allyHero
			sCastMotive = 'Disperser'

			if J.IsDisabled(allyHero)
			then
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end

			if allyHero:GetActiveMode() == BOT_MODE_RETREAT
			and J.GetHP(allyHero) < 0.42
			then
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	if J.IsGoingOnSomeone(bot)
	then
		if J.IsValidTarget(botTarget)
		and J.CanCastOnNonMagicImmune(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange)
		and not J.IsSuspiciousIllusion(botTarget)
		and not J.IsDisabled(botTarget)
		then
			if botTarget:GetCurrentMovementSpeed() > bot:GetCurrentMovementSpeed()
			and bot:IsFacingLocation(botTarget:GetLocation(), 30)
			and not botTarget:IsFacingLocation(bot:GetLocation(), 30)
			then
				hEffectTarget = RandomInt(1, 100) > 20 and botTarget or bot -- 20% ourself, more fun
				sCastMotive = 'Disperser'

				if J.WeAreStronger(bot, nCastRange + nAttackRange)
				then
					return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
				else
					return BOT_ACTION_DESIRE_MODERATE, hEffectTarget, sCastType, sCastMotive
				end
			end
		end
	end

	if J.IsInTeamFight(bot, nCastRange + nAttackRange)
	then
		local nNearbyAllies = J.GetAlliesNearLoc(bot:GetLocation(), nCastRange)

		if nNearbyAllies ~= nil and #nNearbyAllies >= 1
		and nEnemyHeroes ~= nil and #nEnemyHeroes >= 2
		then
			hEffectTarget = bot
			sCastMotive = 'Disperser'
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
	end

	if J.IsRetreating(bot)
	then
		if nEnemyHeroes ~= nil and #nEnemyHeroes >= 1
		then
			if not J.WeAreStronger(bot, nCastRange + nAttackRange)
			or J.GetHP(bot) < 0.33
			then
				hEffectTarget = RandomInt(1, 100) > 10 and bot or botTarget -- 90% ourself, more fun
				sCastMotive = 'Disperser'
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

X.ConsiderItemDesire['item_blood_grenade'] = function(item)
	local nCastRange = 900
	local nRadius = 300
	local nHealth = bot:GetHealth()
	local nHealthCost = 75
	local nImpactDamage = 50
	local nDPS = 15
	local nDuration = 5
	local nEnemyHeroes = J.GetNearbyHeroes(bot,nCastRange, true, BOT_MODE_NONE)
	local totalDmg = nImpactDamage + (nDPS * nDuration)

	for _, enemyHero in pairs(nEnemyHeroes)
	do
		local canKillTarget = J.CanKillTarget(enemyHero, totalDmg, DAMAGE_TYPE_MAGICAL)
		if J.IsInRange(bot, enemyHero, bot:GetAttackRange()) and bot:IsFacingLocation(enemyHero:GetLocation(), 15) then
			canKillTarget = canKillTarget or J.CanKillTarget(enemyHero, totalDmg + 150, DAMAGE_TYPE_MAGICAL)
		end

		if J.IsValidHero(enemyHero)
		and J.CanCastOnNonMagicImmune(enemyHero)
		and canKillTarget
		and not J.IsSuspiciousIllusion(enemyHero)
		and nHealth > nHealthCost * 2
		then
			local nInRangeEnemy = J.GetEnemiesNearLoc(enemyHero:GetLocation(), nRadius)

            if nInRangeEnemy ~= nil and #nInRangeEnemy >= 1
            then
                return BOT_ACTION_DESIRE_HIGH, J.GetCenterOfUnits(nInRangeEnemy), 'ground', 'Blood Grenade'
            end

            return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation(), 'ground', 'Blood Grenade'
		end
	end

	if J.IsGoingOnSomeone(bot)
	then
		for _, enemyHero in pairs(nEnemyHeroes)
		do
			if J.IsValidHero(enemyHero)
			and J.CanCastOnNonMagicImmune(enemyHero)
			and J.IsChasingTarget(bot, enemyHero)
			and not J.IsSuspiciousIllusion(enemyHero)
			and nHealth > nHealthCost * 2
			then
				local nInRangeAlly = J.GetNearbyHeroes(enemyHero, 1200, true, BOT_MODE_NONE)
				local nInRangeEnemy = J.GetNearbyHeroes(enemyHero, 1200, false, BOT_MODE_NONE)
				
				if nInRangeAlly ~= nil and nInRangeEnemy ~= nil
				and #nInRangeAlly >= #nInRangeEnemy
				and #nInRangeAlly >= 1
					and J.IsGoingOnSomeone(nInRangeAlly[1])
					and nInRangeAlly[1]:GetAttackTarget() == enemyHero
					and J.IsChasingTarget(nInRangeAlly[1], enemyHero)
					and not nInRangeAlly[1]:IsIllusion()
				and J.GetTotalEstimatedDamageToTarget(nInRangeAlly, enemyHero) >= enemyHero:GetHealth()
				then
					local nTargetInRangeAlly = J.GetEnemiesNearLoc(enemyHero:GetLocation(), nRadius)

					if nTargetInRangeAlly ~= nil and #nTargetInRangeAlly >= 1
					then
						return BOT_ACTION_DESIRE_HIGH, J.GetCenterOfUnits(nTargetInRangeAlly), 'ground', 'Blood Grenade'
					end
		
					return BOT_ACTION_DESIRE_HIGH, enemyHero:GetLocation(), 'ground', 'Blood Grenade'
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE, 0
end

local function CanSmokeToDefend(defense)
	local now, location, gather = DotaTime(), bot:GetLocation(), defense.waveClearGather
	local distance = GetUnitToLocationDistance(bot, gather)
	if defense.waveClearTeleport or distance < 1200 or distance > 2250
		or GetAmountAlongLane(defense.waveClearLane, location).distance < 550
		or bot:HasModifier('modifier_smoke_of_deceit') or #bot:GetNearbyTowers(1350, true) > 0
		or not J.CanCommitToLaneTeleport(bot, location, true, 1350) then return false end
	local sight = J.GetOuterTowerThreat(defense.waveClearTower, defense.waveClearLane)
	if sight.count < 3 or sight.briefHold then return false end
	local joined = 1
	for _, ally in ipairs(J.GetAlliesNearLoc(location, 850)) do
		local plan = ally._defend
		if ally ~= bot and J.IsValidHero(ally) and J.IsDefending(ally) and J.GetHP(ally) >= 0.5
			and plan and plan.waveClearGather and plan.waveClearTower == defense.waveClearTower and not plan.waveClearTeleport
			and not ally:IsChanneling() and (ally.ohaOuterTowerHoldUntil or 0) > now then
			if ally:HasModifier('modifier_smoke_of_deceit') or #ally:GetNearbyTowers(1150, true) > 0
				or not J.CanCommitToLaneTeleport(ally, ally:GetLocation(), true, 1150) then return false end
			if ally:GetPlayerID() < bot:GetPlayerID()
				and GetAmountAlongLane(plan.waveClearLane, ally:GetLocation()).distance >= 550
				and GetUnitToLocationDistance(ally, gather) >= 1200 and GetUnitToLocationDistance(ally, gather) <= 2250
				and J.CanCastAbility(J.Utils.GetItem(ally, 'item_smoke_of_deceit')) then return false end
			joined = joined + 1
		end
	end
	return joined >= 3
end

local roshDeathTime = 0
X.ConsiderItemDesire['item_smoke_of_deceit'] = function(item)
	local nRadius = 1200
	local sCastType = 'none'
	local hEffectTarget = nil
	local sCastMotive = 'Smoke Of Deceit'
	local defense = bot._defend
	if defense and defense.waveClearLane and defense.waveClearGather and (bot.ohaOuterTowerHoldUntil or 0) > DotaTime()
		and J.IsDefending(bot) and J.IsValidBuilding(defense.waveClearTower) then
		if CanSmokeToDefend(defense) then return BOT_ACTION_DESIRE_HIGH, nil, sCastType, '开雾侧翼回防' end
		return BOT_ACTION_DESIRE_NONE
	end

	local isThereEnemyNearby = false
	local nInRangeAlly = J.GetAllyList(bot, nRadius)
	local nInRangeEnemy = J.GetNearbyHeroes(bot,nRadius, true, BOT_MODE_NONE)
	local nInRangeTower = bot:GetNearbyTowers(nRadius, true)

	if DotaTime() < 0 and DotaTime() > -60
	then
		return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
	end

	if (nInRangeEnemy ~= nil and #nInRangeEnemy == 0)
	or (nInRangeTower ~= nil and #nInRangeTower == 0)
	then
		for _, allyHero in pairs(nInRangeAlly)
		do
			if J.IsValidHero(allyHero)
			then
				local nAllyInRangeEnemy = J.GetNearbyHeroes(allyHero, nRadius, true, BOT_MODE_NONE)
				local nAllyInRangeTower = allyHero:GetNearbyTowers(nRadius, true)

				if (nAllyInRangeEnemy ~= nil and #nAllyInRangeEnemy >= 1)
				or (nAllyInRangeTower ~= nil and #nAllyInRangeTower >= 1)
				then
					isThereEnemyNearby = true
					break
				end
			end
		end
	end

	if not isThereEnemyNearby
	then
		local nMode = bot:GetActiveMode()
		local timeOfDay = J.CheckTimeOfDay()
		hEffectTarget = bot

		if #nInRangeAlly >= 2
		and (nMode == BOT_MODE_ROAM
			or nMode == BOT_MODE_GANK)
		then
			return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
		end
		
		if (timeOfDay == 'day' and GetUnitToLocationDistance(bot, J.Utils.RadiantRoshanLoc) < 600)
		or (timeOfDay == 'night' and GetUnitToLocationDistance(bot, J.Utils.DireRoshanLoc) < 600)
		then
			if GetRoshanKillTime() > roshDeathTime
			then
				roshDeathTime = GetRoshanKillTime()
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end

		if nMode == BOT_MODE_ROSHAN
		and nInRangeAlly ~= nil and #nInRangeAlly >= 2
		then
			if timeOfDay == 'day'
			and GetUnitToLocationDistance(bot, J.Utils.RadiantRoshanLoc) > 3000
			then
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end

			if timeOfDay == 'night'
			and GetUnitToLocationDistance(bot, J.Utils.DireRoshanLoc) > 3000
			then
				return BOT_ACTION_DESIRE_HIGH, hEffectTarget, sCastType, sCastMotive
			end
		end
	end
	
	return BOT_ACTION_DESIRE_NONE
end

-- Dust of Appearance
local dustSightings = {}

local function NeedsDust(location, margin, projectedLocation)
    if J.HasDustCoverage(location, margin) then return false end
    if not J.HasLocalTrueSight(location, margin) then return true end
    return projectedLocation ~= nil and not J.HasLocalTrueSight(projectedLocation)
end

X.ConsiderItemDesire['item_dust'] = function(item)
    local radius = item:GetSpecialValueInt('radius')
    if radius <= 0 then return BOT_ACTION_DESIRE_NONE end
    local now = DotaTime()
    local origin = bot:GetLocation()
    local currentlyVisible = {}
    local selectedLocation
    local fighting = J.IsGoingOnSomeone(bot) or bot:WasRecentlyDamagedByAnyHero(0.65)
    for _, enemy in ipairs(J.GetEnemiesNearLoc(origin, radius + 500)) do
        local id = enemy:GetPlayerID()
        local position = enemy:GetLocation()
        currentlyVisible[id] = true
        if (enemy:IsInvisible() or J.IsUnitWillGoInvisible(enemy, true)) and not J.HasInvisCounterBuff(enemy) then
            local engaged = fighting or enemy == botTarget or enemy:GetAttackTarget() == bot
            dustSightings[id] = {location = position, time = now, speed = enemy:GetCurrentMovementSpeed(), engaged = engaged}
            if engaged and GetUnitToLocationDistance(bot, position) <= radius
            and J.IsClosestToDustLocation(bot, position) and NeedsDust(position, 0, enemy:GetExtrapolatedLocation(0.5)) then
                selectedLocation = position
            end
        else
            dustSightings[id] = nil
        end
    end

    local bestAge = selectedLocation == nil and math.huge or 0
    for id, seen in pairs(dustSightings) do
        local age = now - seen.time
        local drift = age * math.max(200, seen.speed)
        if age > 0.9 or not IsHeroAlive(id) then
            dustSightings[id] = nil
        elseif not currentlyVisible[id] and age > 0 and age < bestAge
        and (seen.engaged or fighting) and IsLocationVisible(seen.location)
        and GetUnitToLocationDistance(bot, seen.location) + drift <= radius
        and J.IsClosestToDustLocation(bot, seen.location) and NeedsDust(seen.location, drift) then
            selectedLocation, bestAge = seen.location, age
        end
    end

    if selectedLocation ~= nil then
        return 0.82, bot, 'none', '根据已观察到的隐身线索显影', function()
            bot.ohaDustCoverage = {location = origin, radius = radius, untilTime = now + item:GetSpecialValueFloat('duration')}
        end
    end
    return BOT_ACTION_DESIRE_NONE
end

----------------
-- Neutral Items
----------------

-- TIER 1

-- Trusty Shovel
X.ConsiderItemDesire["item_trusty_shovel"] = function(hItem)
	if GetTeamMember(1):IsBot() then return BOT_ACTION_DESIRE_NONE end

	local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1000)

	if nInRangeEnemy ~= nil and #nInRangeEnemy == 0
	then
		return BOT_ACTION_DESIRE_HIGH, bot:GetLocation(), 'ground', nil
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Arcane Ring
X.ConsiderItemDesire["item_arcane_ring"] = function(hItem)
	return X.ConsiderItemDesire["item_arcane_boots"](hItem)
end

-- Pig Pole
X.ConsiderItemDesire["item_unstable_wand"] = function(hItem)
	local nCastRange = 1600
	local nInRangeEnemy = J.GetNearbyHeroes(bot,nCastRange, true, BOT_MODE_NONE)

	if nInRangeEnemy ~= nil and #nInRangeEnemy == 0
	and J.GetMP(bot) > 0.5
	and (J.IsRetreating(bot) or J.IsGoingOnSomeone(bot))
	then
		return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Seeds of Serenity
X.ConsiderItemDesire["item_seeds_of_serenity"] = function(hItem)
	local nRadius = 400
	local nInRangeEnemy = J.GetNearbyHeroes(bot,nRadius, true, BOT_MODE_NONE)
	local nInRangeTower = bot:GetNearbyTowers(700, true)

	if J.IsFarming(bot)
	then	
		if J.IsAttacking(bot)
		then
			local nNeutralCreeps = bot:GetNearbyNeutralCreeps(nRadius)
			if nNeutralCreeps ~= nil
			and ((#nNeutralCreeps >= 3)
				or (#nNeutralCreeps >= 2 and nNeutralCreeps[1]:IsAncientCreep()))
			then
				return BOT_ACTION_DESIRE_HIGH, bot:GetLocation()
			end

			local nEnemyLaneCreeps = bot:GetNearbyLaneCreeps(nRadius, true)
			if nEnemyLaneCreeps ~= nil and #nEnemyLaneCreeps >= 3
			then
				return BOT_ACTION_DESIRE_HIGH, bot:GetLocation()
			end
		end
	end

	if J.IsPushing(bot)
	then
		if nInRangeTower ~= nil and #nInRangeTower >= 1
		and J.IsValidBuilding(botTarget)
		and J.IsValidBuilding(nInRangeTower[1])
		and J.IsAttacking(bot)
		and botTarget == nInRangeTower[1]
		then
			return BOT_ACTION_DESIRE_HIGH, bot:GetLocation(), 'ground', nil
		end
	end

	if J.IsDoingRoshan(bot)
    then
        if J.IsRoshan(botTarget)
        and J.IsInRange(bot, botTarget, nRadius)
        and J.IsAttacking(bot)
        then
            return BOT_ACTION_DESIRE_HIGH, bot:GetLocation(), 'ground', nil
        end
    end

    if J.IsDoingTormentor(bot)
    then
        if J.IsTormentor(botTarget)
        and J.IsInRange(bot, botTarget, nRadius)
        and J.IsAttacking(bot)
        then
            return BOT_ACTION_DESIRE_HIGH, bot:GetLocation(), 'ground', nil
        end
    end

	return BOT_ACTION_DESIRE_NONE
end

-- 7.41 Neutral Items

-- Dagger of Ristul: self-cast, consume 100 HP for +25 damage for 8s, 30s CD
X.ConsiderItemDesire["item_dagger_of_ristul"] = function(hItem)
	local sCastType = 'none'

	-- Don't use when low HP (costs 100 HP)
	if J.GetHP(bot) < 0.4 then return BOT_ACTION_DESIRE_NONE end

	-- Use when going on someone and have enough HP
	if J.IsGoingOnSomeone(bot)
	then
		if J.IsValidTarget(botTarget)
		and J.IsInRange(bot, botTarget, 800)
		and J.GetHP(bot) > 0.5
		then
			return BOT_ACTION_DESIRE_HIGH, bot, sCastType, nil
		end
	end

	-- Use when farming neutrals and healthy
	if J.IsFarming(bot) and J.IsAttacking(bot)
	and J.GetHP(bot) > 0.7
	then
		local nNeutralCreeps = bot:GetNearbyNeutralCreeps(600)
		if nNeutralCreeps ~= nil and #nNeutralCreeps >= 2
		then
			return BOT_ACTION_DESIRE_HIGH, bot, sCastType, nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Stonefeather Satchel: toggle between Feathers (MS) and Rocks (armor), 6s CD
X.ConsiderItemDesire["item_stonefeather_satchel"] = function(hItem)
	local sCastType = 'none'
	local nEnemyHeroes = J.GetNearbyHeroes(bot, 1200, true, BOT_MODE_NONE)

	-- Toggle to Rocks (armor) mode when in danger
	if #nEnemyHeroes >= 1
	and (J.IsRetreating(bot) or J.GetHP(bot) < 0.5)
	and not bot:HasModifier('modifier_item_stonefeather_satchel_rocks')
	then
		return BOT_ACTION_DESIRE_HIGH, bot, sCastType, nil
	end

	-- Toggle to Feathers (MS) mode when safe
	if #nEnemyHeroes == 0
	and not bot:HasModifier('modifier_item_stonefeather_satchel_feathers')
	then
		return BOT_ACTION_DESIRE_MODERATE, bot, sCastType, nil
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Royal Jelly
local royalJellyTime = nil
X.ConsiderItemDesire["item_royal_jelly"] = function(hItem)
	if royalJellyTime == nil
	then
		royalJellyTime = DotaTime()
	else
		if royalJellyTime < DotaTime() - 2.0
		then
			local targetAlly = nil

			for i = 1, #GetTeamPlayers( GetTeam() )
			do
				local allyHero = GetTeamMember(i)

				if J.IsValidHero(allyHero)
				and J.IsCore(allyHero)
				and not allyHero:IsIllusion()
				and not allyHero:HasModifier('modifier_royal_jelly')
				then
					targetAlly = allyHero
				end
			end

			if targetAlly ~= nil
			then
				royalJellyTime = nil
				return BOT_ACTION_DESIRE_HIGH, targetAlly, 'unit', nil
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- TIER 2

-- Vambrace
-- X.ConsiderItemDesire["item_vambrace"] = function(hItem)
-- 	return X.ConsiderItemDesire["item_power_treads"](hItem)
-- end

-- Bullwhip
X.ConsiderItemDesire["item_bullwhip"] = function(hItem)
	local nCastRange = 850 + aetherRange

	if J.IsGoingOnSomeone(bot)
	then
		if J.IsValidHero(botTarget)
		and J.CanCastOnNonMagicImmune(botTarget)
		and J.IsChasingTarget(bot, botTarget)
		and not J.IsDisabled(botTarget)
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget, 'unit', nil
		end
	end

	local nInRangeAlly = J.GetAlliesNearLoc(bot:GetLocation(), nCastRange)
	for _, allyHero in pairs(nInRangeAlly)
	do
		if J.IsValidHero(allyHero)
		and J.CanCastOnNonMagicImmune(allyHero)
		then
			local nAllyInRangeEnemy = J.GetNearbyHeroes(allyHero, 1200, true, BOT_MODE_NONE)

			if nAllyInRangeEnemy ~= nil and #nAllyInRangeEnemy >= 1
			and J.IsRetreating(allyHero)
			and allyHero:DistanceFromFountain() > 1200
			and not J.IsRealInvisible(allyHero)
			and not J.IsDisabled(allyHero)
			then
				return BOT_ACTION_DESIRE_HIGH, allyHero, 'unit', nil
			end
		end
	end

	if hItem:IsFullyCastable()
	then
		return BOT_ACTION_DESIRE_HIGH, bot, 'unit', nil
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Light Collector
X.ConsiderItemDesire["item_light_collector"] = function(hItem)
	local nRadius = 325
	local nInRangeTrees = bot:GetNearbyTrees(nRadius)

	if J.IsGoingOnSomeone(bot)
	then
		if nInRangeTrees ~= nil and #nInRangeTrees >= 3
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Iron Talon
X.ConsiderItemDesire["item_iron_talon"] = function(hItem)
	local nCastRange = 350

	-- Only use it for creeps
	if J.IsFarming(bot)
	then
		local nCreep = bot:GetNearbyNeutralCreeps(nCastRange)
		if #nCreep <= 0 then return 0 end

		local creepTarget = J.GetMostHpUnit(nCreep)
		if J.CanBeAttacked(creepTarget)
		and J.GetHP(creepTarget) > 0.5
		then
			return BOT_ACTION_DESIRE_HIGH, creepTarget, 'unit', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- TIER 3

-- Craggy Coat
X.ConsiderItemDesire["item_craggy_coat"] = function(hItem)
	local nRadius = 1200

	if J.IsInTeamFight(bot)
	then
		local realEnemyCount = J.GetEnemiesNearLoc(bot:GetLocation(), nRadius)

        if realEnemyCount ~= nil and #realEnemyCount >= 2
		and bot:WasRecentlyDamagedByAnyHero(1.5)
        then
            return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
        end
	end

    if J.IsGoingOnSomeone(bot)
	then
		local nInRangeAlly = J.GetNearbyHeroes(bot,1200, false, BOT_MODE_NONE)

        if J.IsValidTarget(botTarget)
        and J.IsAttacking(botTarget)
		and bot:WasRecentlyDamagedByAnyHero(1.3)
        and J.IsInRange(bot, botTarget, 600)
        and not J.IsSuspiciousIllusion(botTarget)
        then
            local nTargetInRangeAlly = J.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)

            if nInRangeAlly ~= nil and nTargetInRangeAlly ~= nil
            and #nInRangeAlly >= #nTargetInRangeAlly
            then
                return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
            end
        end
	end

	if J.IsDoingRoshan(bot)
    then
        if J.IsRoshan(botTarget)
        and J.IsInRange(bot, botTarget, 500)
        and J.IsAttacking(bot)
        then
            return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
        end
    end

    if J.IsDoingTormentor(bot)
    then
        if J.IsTormentor(botTarget)
        and J.IsInRange(bot, botTarget, 500)
        and J.IsAttacking(bot)
        then
            return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
        end
    end

	return BOT_ACTION_DESIRE_NONE
end

-- Psychic Headband
X.ConsiderItemDesire["item_psychic_headband"] = function(hItem)
	local nCastRange = 600 + aetherRange
	local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), nCastRange)

	if J.IsRetreating(bot)
	then	
		if J.IsValidHero(nInRangeEnemy[1])
		and J.CanCastOnNonMagicImmune(nInRangeEnemy[1])
		and J.IsRunning(nInRangeEnemy[1])
		and nInRangeEnemy[1]:IsFacingLocation(bot:GetLocation(), 30)
		and not J.IsSuspiciousIllusion(nInRangeEnemy[1])
		and not J.IsDisabled(nInRangeEnemy[1])
		then
			return BOT_ACTION_DESIRE_HIGH, nInRangeEnemy[1], 'unit', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Ogre Seal Totem
X.ConsiderItemDesire["item_ogre_seal_totem"] = function(hItem)
	local nFlopRadius = 275
	local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), nFlopRadius * 2)

	if J.IsGoingOnSomeone(bot)
	then
		local nInRangeAlly = J.GetNearbyHeroes(bot,1000, false, BOT_MODE_NONE)

		if J.IsValidTarget(botTarget)
		and J.CanCastOnNonMagicImmune(botTarget)
		and bot:IsFacingLocation(botTarget:GetLocation(), 5)
		and J.IsInRange(bot, botTarget, nFlopRadius * 2)
		and not J.IsInRange(bot, botTarget, nFlopRadius - 75)
		and not J.IsSuspiciousIllusion(botTarget)
		and not bot:HasModifier('modifier_abaddon_borrowed_time')
		and not bot:HasModifier('modifier_necrolyte_reapers_scythe')
		and not J.IsLocationInChrono(botTarget:GetLocation())
		and not J.IsLocationInBlackHole(botTarget:GetLocation())
		then
			local nTargetInRangeAlly = J.GetNearbyHeroes(botTarget, 1000, false, BOT_MODE_NONE)

			if nInRangeAlly ~= nil and nTargetInRangeAlly ~= nil
			and #nInRangeAlly >= #nTargetInRangeAlly
			then
				return BOT_ACTION_DESIRE_HIGH, bot, 'unit', nil
			end
		end
	end

	if J.IsRetreating(bot)
	then	
		if J.IsValidHero(nInRangeEnemy[1])
		and J.IsRunning(nInRangeEnemy[1])
		and bot:IsFacingLocation(J.GetEscapeLoc(), 15)
		and nInRangeEnemy[1]:IsFacingLocation(bot:GetLocation(), 30)
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Doubloon
local currState = 'health'
X.ConsiderItemDesire["item_doubloon"] = function(hItem)
	local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1000)

	if J.IsGoingOnSomeone(bot)
	then
		local nInRangeAlly = J.GetNearbyHeroes(bot,1000, false, BOT_MODE_NONE)

		if J.IsValidTarget(botTarget)
		and J.IsInRange(bot, botTarget, 1000)
		and J.GetHP(bot) > 0.8
		and J.GetMP(bot) < 0.5
		and currState == 'mana'
		and not J.IsSuspiciousIllusion(botTarget)
		then
			currState = 'health'
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	if J.IsRetreating(bot)
	then	
		if J.IsValidHero(nInRangeEnemy[1])
		and J.IsRunning(nInRangeEnemy[1])
		and nInRangeEnemy[1]:IsFacingLocation(bot:GetLocation(), 30)
		and bot:WasRecentlyDamagedByAnyHero(1.5)
		and J.GetHP(bot) < 0.5
		and J.GetMP(bot) > 0.75
		and currState == 'health'
		then
			currState = 'mana'
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- TIER 4

-- Ninja Gear
X.ConsiderItemDesire["item_ninja_gear"] = function(hItem)
	local nCastRange = 1600

	if J.IsGoingOnSomeone(bot)
	then
		if J.IsValidTarget(botTarget)
		and J.CanCastOnMagicImmune(botTarget)
		and J.IsInRange(bot, botTarget, 2800)
		and not J.IsInRange(bot, botTarget, botTarget:GetCurrentVisionRange() + 200)
		and not J.IsSuspiciousIllusion(botTarget)
		then
			local nEnemyLaneCreeps = bot:GetNearbyLaneCreeps(800, true)
			local nEnemyTowers = bot:GetNearbyTowers(700, true)

			if nEnemyLaneCreeps ~= nil and #nEnemyLaneCreeps == 0
			and nEnemyTowers ~= nil and #nEnemyTowers == 0
			then
				return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
			end
		end
	end

	if J.IsDefending(bot)
	then
		local nMode = bot:GetActiveMode()
		local nLane = LANE_MID

		if nMode == BOT_MODE_PUSH_TOWER_TOP then nLane = LANE_TOP end
		if nMode == BOT_MODE_PUSH_TOWER_BOT then nLane = LANE_BOT end

		local nPushLoc = GetLaneFrontLocation(team, nLane, 0)
		if GetUnitToLocationDistance(bot, nPushLoc) > 3200
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	if J.IsDoingRoshan(bot)
    then
        if J.CheckTimeOfDay() == 'day'
        and GetUnitToLocationDistance(bot, J.Utils.RadiantRoshanLoc) > 3200
        then
            return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end

		if J.CheckTimeOfDay() == 'night'
        and GetUnitToLocationDistance(bot, J.Utils.DireRoshanLoc) > 3200
        then
            return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
        end
    end

	return BOT_ACTION_DESIRE_NONE
end

-- Trickster Cloak
X.ConsiderItemDesire["item_trickster_cloak"] = function(hItem)
	return X.ConsiderItemDesire["item_invis_sword"](hItem)
end

-- Havoc Hammer
X.ConsiderItemDesire["item_havoc_hammer"] = function(hItem)
	local nRadius = 400
	local nDamage = 175 + bot:GetAttributeValue(ATTRIBUTE_STRENGTH) * 1.5

	local nEnemyHeroes = J.GetNearbyHeroes(bot,nRadius, true, BOT_MODE_NONE)
    for _, enemyHero in pairs(nEnemyHeroes)
    do
        if J.IsValidHero(enemyHero)
        and J.CanCastOnNonMagicImmune(enemyHero)
        and J.CanKillTarget(enemyHero, nDamage, DAMAGE_TYPE_MAGICAL)
        and not J.IsSuspiciousIllusion(enemyHero)
        and not enemyHero:HasModifier('modifier_abaddon_borrowed_time')
        and not enemyHero:HasModifier('modifier_dazzle_shallow_grave')
        and not enemyHero:HasModifier('modifier_oracle_false_promise_timer')
        and not enemyHero:HasModifier('modifier_templar_assassin_refraction_absorb')
        then
            return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
        end
    end

	if J.IsInTeamFight(bot, 1200)
	then
		local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1000)

		if nInRangeEnemy ~= nil and #nInRangeEnemy >= 2
        then
            local realEnemyCount = J.GetEnemiesNearLoc(bot:GetLocation(), nRadius)

            if realEnemyCount ~= nil and #realEnemyCount >= 2
            and not J.IsLocationInChrono(nInRangeEnemy[1]:GetLocation())
            and not J.IsLocationInBlackHole(nInRangeEnemy[1]:GetLocation())
            then
                return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
            end
		end
	end

	if J.IsGoingOnSomeone(bot)
	then
		local nInRangeAlly = J.GetNearbyHeroes(bot,1000, false, BOT_MODE_NONE)

		if J.IsValidTarget(botTarget)
		and J.CanCastOnNonMagicImmune(botTarget)
		and J.IsInRange(bot, botTarget, nRadius)
		and J.IsRunning(botTarget)
		and bot:IsFacingLocation(botTarget:GetLocation(), 30)
		and not botTarget:IsFacingLocation(bot:GetLocation(), 90)
		and not J.IsSuspiciousIllusion(botTarget)
		and not J.IsDisabled(botTarget)
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	if J.IsDoingRoshan(bot)
    then
        if J.IsRoshan(botTarget)
        and J.IsInRange(bot, botTarget, nRadius)
        and J.IsAttacking(bot)
        then
            return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
        end
    end

    if J.IsDoingTormentor(bot)
    then
        if J.IsTormentor(botTarget)
        and J.IsInRange(bot, botTarget, nRadius)
        and J.IsAttacking(bot)
        then
            return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
        end
    end

	return BOT_ACTION_DESIRE_NONE
end

-- Martyrdom
X.ConsiderItemDesire["item_martyrs_plate"] = function(hItem)
	local nRadius = 900

	if J.IsInTeamFight(bot)
	then
		local nInRangeAlly = J.GetAlliesNearLoc(bot:GetLocation(), nRadius)
		local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), nRadius)

		if nInRangeEnemy ~= nil and #nInRangeEnemy >= 2
		then
			if J.IsValidHero(nInRangeEnemy[1])
			and J.IsValidHero(nInRangeEnemy[2])
			and J.IsAttacking(nInRangeEnemy[1])
			and J.IsAttacking(nInRangeEnemy[2])
			and J.GetHP(bot) > 0.88
			and bot:GetHealth() >= 3800
			and not bot:WasRecentlyDamagedByAnyHero(0.8)
			then
				return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- TIER 5

-- Force Boots
X.ConsiderItemDesire["item_force_boots"] = function( hItem )
	local nCastRange = 700 + aetherRange
	local nInRangeEnemy = J.GetNearbyHeroes(bot,nCastRange, true, BOT_MODE_NONE)

	if J.IsStuck(bot)
	then
		return BOT_ACTION_DESIRE_HIGH, bot, 'unit', nil
	end

	if J.IsGoingOnSomeone(bot)
	then
		if J.IsValidTarget(botTarget)
		and J.IsInRange(bot, botTarget, 900)
		and X.IsWithoutSpellShield(botTarget)
		and not J.IsSuspiciousIllusion(botTarget)
		and not J.IsLocationInChrono(botTarget:GetLocation())
		and not J.IsLocationInBlackHole(botTarget:GetLocation())
		and not botTarget:HasModifier('modifier_necrolyte_reapers_scythe')
		then
			local nInRangeAlly = J.GetNearbyHeroes(bot,1200, false, BOT_MODE_NONE)
			local nTargetInRangeAlly = J.GetNearbyHeroes(botTarget, 1200, false, BOT_MODE_NONE)

			if nInRangeAlly ~= nil and nTargetInRangeAlly ~= nil
			and #nInRangeAlly >= #nTargetInRangeAlly
			then
				if bot:IsFacingLocation(botTarget:GetLocation(), 15)
				and #nInRangeAlly >= #nTargetInRangeAlly + 1
				then
					return BOT_ACTION_DESIRE_HIGH, bot, 'unit', nil
				end

				local allyCenterLocation = J.GetCenterOfUnits(nInRangeAlly)
				if botTarget:IsFacingLocation(allyCenterLocation, 15)
				and GetUnitToLocationDistance(bot, allyCenterLocation ) >= 750
				then
					return BOT_ACTION_DESIRE_HIGH, botTarget, 'unit', nil
				end	
			end		
		end
	end

	if J.IsRetreating(bot)
	then
		if nInRangeEnemy ~= nil and #nInRangeEnemy >= 1
		and bot:IsFacingLocation(J.GetEscapeLoc(), 30)
		and bot:DistanceFromFountain() > 600
		and not J.IsRealInvisible(bot)
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'unit', nil
		end
	end

	local nInRangeAlly = J.GetAlliesNearLoc(bot:GetLocation(), nCastRange)
	for _, allyHero in pairs(nInRangeAlly)
	do
		if J.IsValidHero(allyHero)
		and J.CanCastOnNonMagicImmune(allyHero)
		then
			local nAllyInRangeEnemy = J.GetNearbyHeroes(allyHero, 1200, true, BOT_MODE_NONE)

			if nAllyInRangeEnemy ~= nil and #nAllyInRangeEnemy >= 1
			and J.IsRetreating(allyHero)
			and allyHero:IsFacingLocation(J.GetEscapeLoc(), 30)
			and allyHero:DistanceFromFountain() > 600
			and allyHero:WasRecentlyDamagedByAnyHero(2.2)
			and not J.IsRealInvisible(allyHero)
			then
				return BOT_ACTION_DESIRE_HIGH, allyHero, 'unit', nil
			end

			if J.IsGoingOnSomeone(allyHero)
			then
				local allyTarget = J.GetProperTarget(allyHero)

				if J.IsValidHero(allyTarget)
				and J.CanCastOnNonMagicImmune(allyTarget)
				and allyHero:IsFacingLocation(allyTarget:GetLocation(), 15 )
				and GetUnitToUnitDistance(allyHero, allyTarget) > allyHero:GetAttackRange() + 50
				and GetUnitToUnitDistance(allyHero, allyTarget) < allyHero:GetAttackRange() + 700
				and J.IsRunning(allyTarget)
				and J.GetEnemyCount(allyHero, 1600) <= 3
				and not allyTarget:IsFacingLocation(allyHero:GetLocation(), 40)
				and not J.IsSuspiciousIllusion(allyTarget)
				then
					return BOT_ACTION_DESIRE_HIGH, allyHero, 'unit', nil
				end
			end

			if J.IsStuck(allyHero)
			then
				return BOT_ACTION_DESIRE_HIGH, allyHero, 'unit', nil
			end
		end

	end

	if bot:DistanceFromFountain() < 2800
	then
		for _, enemyHero in pairs(nInRangeEnemy)
		do
			if J.IsValidHero(enemyHero)
			and J.CanCastOnMagicImmune(enemyHero)
			and enemyHero:IsFacingLocation(GetAncient(team):GetLocation(), 30)
			and GetUnitToLocationDistance(enemyHero, GetAncient(team):GetLocation()) < 1600
			and not J.IsSuspiciousIllusion(enemyHero)
			then
				local nInRangeAlly = J.GetNearbyHeroes(bot,1000, false, BOT_MODE_NONE)
				local nTargetInRangeAlly = J.GetNearbyHeroes(enemyHero, 1000, false, BOT_MODE_NONE)

				if nInRangeAlly ~= nil and nTargetInRangeAlly ~= nil
				and #nInRangeAlly >= #nTargetInRangeAlly
				then
					return BOT_ACTION_DESIRE_HIGH, enemyHero, 'unit', nil
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Seer Stone
X.ConsiderItemDesire["item_seer_stone"] = function(hItem)
	local nRadius = 800

	-- In Fights
	if J.IsGoingOnSomeone(bot)
	then
		local nLocationAoE = bot:FindAoELocation(true, true, bot:GetLocation(), 1600, nRadius, 0, 0)
		local nInRangeEnemy = J.GetEnemiesNearLoc(nLocationAoE.targetloc, nRadius)

		local targetHero = nil
		for _, enemyHero in pairs(nInRangeEnemy)
		do
			if J.IsValidHero(enemyHero)
			and J.IsInRange(bot, enemyHero, nRadius)
			and J.CanCastOnMagicImmune(enemyHero)
			and J.HasInvisibilityOrItem(enemyHero)
			and not enemyHero:HasModifier('modifier_slardar_amplify_damage')
			and not enemyHero:HasModifier('modifier_item_dustofappearance')
			and not J.Site.IsLocationHaveTrueSight(enemyHero:GetLocation())
			then
				return BOT_ACTION_DESIRE_HIGH, nLocationAoE.targetloc, 'ground', nil
			end
		end

	end

	-- For Roshan Scout
	local nInSightEnemy = 0
	for _, enemyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
	do
		if J.IsValidHero(enemyHero)
		and not J.IsSuspiciousIllusion(enemyHero)
		then
			nInSightEnemy = nInSightEnemy + 1
		end
	end

	if J.IsRoshanAlive()
	and nInSightEnemy == 0
	then
		if J.CheckTimeOfDay() == 'day'
		and GetUnitToLocationDistance(bot, J.Utils.RadiantRoshanLoc) > 1600
		then
			return BOT_ACTION_DESIRE_HIGH, J.Utils.RadiantRoshanLoc, 'ground', nil
		end

		if J.CheckTimeOfDay() == 'night'
		and GetUnitToLocationDistance(bot, J.Utils.DireRoshanLoc) > 1600
		then
			return BOT_ACTION_DESIRE_HIGH, J.Utils.DireRoshanLoc, 'ground', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Book of the Dead
X.ConsiderItemDesire["item_demonicon"] = function(hItem)
	local nCastRange = 750
	local nInRangeEnmyList = J.GetNearbyHeroes(bot, nCastRange, true, BOT_MODE_NONE )

	if J.IsPushing(bot)
	then
		local nEnemyTowers = bot:GetNearbyTowers(900, true)
		local nLaneCreeps = bot:GetNearbyLaneCreeps(900, false)

		if nEnemyTowers ~= nil and #nEnemyTowers >= 1
		and nLaneCreeps ~= nil and #nLaneCreeps >= 3
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	if J.IsValidTarget(botTarget)
	and J.IsInRange(bot, botTarget, 1000)
	and not botTarget:HasModifier('modifier_abaddon_borrowed_time')
	then
		local nTargetInRangeAlly = J.GetNearbyHeroes(botTarget, 1000, false, BOT_MODE_NONE)

		if nTargetInRangeAlly ~= nil
		then
			if #nTargetInRangeAlly == 0
			-- and J.IsCore(botTarget)
			then
				return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
			end

			if #nTargetInRangeAlly >= 1
			then
				return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Arcanist's Armor
X.ConsiderItemDesire["item_force_field"] = function(hItem)
	local nRadius = 1200
	local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), nRadius)


	for _, enemyHero in pairs(nInRangeEnemy)
	do
		if J.IsValidHero(enemyHero)
		and enemyHero:GetAttackTarget() == bot
		and (bot:WasRecentlyDamagedByHero(enemyHero, 5)
			or J.IsAttackProjectileIncoming(bot, 500))
		and not J.IsSuspiciousIllusion(enemyHero)
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Pirate Hat
X.ConsiderItemDesire['item_pirate_hat'] = function(hItem)
	return X.ConsiderItemDesire["item_trusty_shovel"](hItem)
end

-- Mana Draught
X.ConsiderItemDesire["item_mana_draught"] = function( hItem )
	local nEnemyHeroes = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)

	if #nEnemyHeroes == 0
	or (J.IsValidHero(nEnemyHeroes[1]) and not J.IsInRange(bot, nEnemyHeroes[1], 800) and not bot:WasRecentlyDamagedByAnyHero(5.0))
	then
		if J.GetMP(bot) < 0.5 then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Pollywog Charm
X.ConsiderItemDesire["item_polliwog_charm"] = function( hItem )
	local nCastRange = 1000

	if bot:GetMana() < 75 + 40 then
		return BOT_ACTION_DESIRE_NONE
	end

	local nAllyHeroes = J.GetAlliesNearLoc(bot:GetLocation(), nCastRange)
	local hNeedHealAlly = nil
	local nNeedHealAllyHealth = 99999
	for _, allyHero in pairs(nAllyHeroes) do
		if J.IsValidHero(allyHero)
		and not allyHero:IsIllusion()
		and not allyHero:HasModifier("modifier_abaddon_borrowed_time")
		and not allyHero:HasModifier("modifier_necrolyte_reapers_scythe")
		and not allyHero:HasModifier("modifier_filler_heal")
		and not allyHero:HasModifier("modifier_elixer_healing")
		and not allyHero:HasModifier("modifier_flask_healing")
		and not allyHero:HasModifier("modifier_juggernaut_healing_ward_heal")
		and not allyHero:HasModifier("modifier_juggernaut_healing_ward_heal")
		and not allyHero:IsChanneling()
		and (allyHero:GetMaxHealth() - allyHero:GetHealth() > 100)
		then
			if allyHero:GetHealth() < nNeedHealAllyHealth then
				hNeedHealAlly = allyHero
				nNeedHealAllyHealth = allyHero:GetHealth()
			end
		end
	end

	if hNeedHealAlly ~= nil then
		return BOT_ACTION_DESIRE_HIGH, hNeedHealAlly, 'unit', nil
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Ripper's Lash
X.ConsiderItemDesire["item_rippers_lash"] = function( hItem )
	local nCastRange = 700
	local nRadius = 200

	local nAllyHeroes = J.GetAlliesNearLoc(bot:GetLocation(), nCastRange)
	for _, allyHero in pairs(nAllyHeroes) do
		if J.IsValidHero(allyHero) and not allyHero:IsIllusion() then
			local hAllyTarget = allyHero:GetAttackTarget()
			if J.IsGoingOnSomeone(allyHero) and J.IsAttacking(allyHero) then
				if J.IsValidHero(hAllyTarget)
				and J.CanBeAttacked(hAllyTarget)
				and J.IsInRange(allyHero, hAllyTarget, allyHero:GetAttackRange() + 50)
				and J.IsInRange(bot, hAllyTarget, nCastRange)
				and not J.IsSuspiciousIllusion(hAllyTarget)
				and not hAllyTarget:HasModifier('modifier_abaddon_borrowed_time')
				and not hAllyTarget:HasModifier('modifier_necrolyte_reapers_scythe')
				and not hAllyTarget:HasModifier('modifier_dazzle_shallow_grave')
				then
					local nLocationAoE = bot:FindAoELocation(true, true, hAllyTarget:GetLocation(), 0, nRadius, 0, 0)
					if nLocationAoE.count >= 2 then
						return BOT_ACTION_DESIRE_HIGH, nLocationAoE.targetloc, 'point', nil
					else
						return BOT_ACTION_DESIRE_HIGH, hAllyTarget:GetLocation(), 'point', nil
					end
				end
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Gale Guard
X.ConsiderItemDesire["item_gale_guard"] = function( hItem )
    local nAllyHeroes = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
    local nEnemyHeroes = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)

	if bot:HasModifier('modifier_abaddon_aphotic_shield') or not J.CanBeAttacked(bot) then
		return BOT_ACTION_DESIRE_NONE
	end

	if bot:IsRooted() and #nEnemyHeroes > 0 then
		return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
	end

	if J.IsGoingOnSomeone(bot) then
		if J.IsValidHero(botTarget)
		and J.IsInRange(bot, botTarget, bot:GetAttackRange() + 300)
		and (J.GetHP(bot) < 0.65 and bot:WasRecentlyDamagedByAnyHero(3.0))
		and not J.IsSuspiciousIllusion(botTarget)
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

	if J.IsRetreating(bot) and not J.IsRealInvisible(bot) then
		for _, enemyHero in pairs(nEnemyHeroes) do
            if J.IsValidHero(enemyHero)
            and J.IsInRange(bot, enemyHero, 800)
            and J.IsChasingTarget(enemyHero, bot)
			and not J.IsSuspiciousIllusion(enemyHero)
            then
                if #nEnemyHeroes > #nAllyHeroes or (J.GetHP(bot) < 0.55 and bot:WasRecentlyDamagedByAnyHero(3.0)) then
                    return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
                end
            end
        end
	end

    if J.IsFarming(bot) then
        local nEnemyCreeps = bot:GetNearbyCreeps(1600, true)
		if nEnemyCreeps then
			if  J.IsValid(nEnemyCreeps[1])
			and J.CanBeAttacked(nEnemyCreeps[1])
			and J.GetHP(bot) < 0.25
			and J.IsAttacking(bot)
			then
				return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
			end
		end
    end

    if J.IsDoingRoshan(bot) then
        if  J.IsRoshan(botTarget)
		and J.CanBeAttacked(botTarget)
        and J.IsInRange(bot, botTarget, 500)
        and J.IsAttacking(bot)
		and J.GetHP(bot) < 0.5
        then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
        end
    end

    if J.IsDoingTormentor(bot) then
        if  J.IsTormentor(botTarget)
        and J.IsInRange(bot, botTarget, 400)
        and J.IsAttacking(bot)
		and J.GetHP(bot) < 0.5
        then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
        end
    end

	return BOT_ACTION_DESIRE_NONE
end

-- Crippling Crossbow
X.ConsiderItemDesire["item_crippling_crossbow"] = function( hItem )
	local nCastRange = J.GetProperCastRange(false, bot, hItem:GetCastRange())
	local nDamage = hItem:GetSpecialValueInt('damage')

	local nAllyHeroes = bot:GetNearbyHeroes(1600, false, BOT_MODE_NONE)
    local nEnemyHeroes = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)

	for _, enemyHero in pairs(nEnemyHeroes) do
        if  J.IsValidHero(enemyHero)
        and J.IsInRange(bot, enemyHero, nCastRange)
		and not J.IsInRange(bot, enemyHero, nCastRange / 2)
        and J.CanCastOnNonMagicImmune(enemyHero)
        and J.CanCastOnTargetAdvanced(enemyHero)
        then
            if  J.CanKillTarget(enemyHero, nDamage, DAMAGE_TYPE_MAGICAL)
            and not enemyHero:HasModifier('modifier_abaddon_borrowed_time')
            and not enemyHero:HasModifier('modifier_dazzle_shallow_grave')
            and not enemyHero:HasModifier('modifier_necrolyte_reapers_scythe')
            and not enemyHero:HasModifier('modifier_oracle_false_promise_timer')
            then
                return BOT_ACTION_DESIRE_HIGH, enemyHero, 'unit', nil
            end
        end
    end

	if J.IsGoingOnSomeone(bot) then
		if J.IsValidHero(botTarget)
		and J.CanBeAttacked(botTarget)
		and J.CanCastOnNonMagicImmune(botTarget)
		and J.CanCastOnTargetAdvanced(botTarget)
		and J.IsInRange(bot, botTarget, nCastRange)
		and not J.IsInRange(bot, botTarget, nCastRange / 2)
		and J.IsChasingTarget(bot, botTarget)
		then
			return BOT_ACTION_DESIRE_HIGH, botTarget, 'unit', nil
		end
	end

	if J.IsRetreating(bot) and not J.IsRealInvisible(bot) then
		for _, enemyHero in pairs(nEnemyHeroes) do
            if  J.IsValidHero(enemyHero)
            and J.IsInRange(bot, enemyHero, nCastRange)
            and J.CanCastOnNonMagicImmune(enemyHero)
            and J.CanCastOnTargetAdvanced(enemyHero)
            and J.IsChasingTarget(enemyHero, bot)
            and not J.IsDisabled(enemyHero)
            then
                if #nEnemyHeroes > #nAllyHeroes or (J.GetHP(bot) < 0.55 and bot:WasRecentlyDamagedByAnyHero(3.0)) then
                    return BOT_ACTION_DESIRE_HIGH, enemyHero, 'unit', nil
                end
            end
        end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Pyrrhic Cloak
X.ConsiderItemDesire["item_pyrrhic_cloak"] = function( hItem )
	local nCastRange = J.GetProperCastRange(false, bot, hItem:GetCastRange())

    local nEnemyHeroes = bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE)

	if J.IsNotAttackProjectileIncoming(bot, 400)
	and J.IsValidHero(nEnemyHeroes[1])
	and J.IsInRange(bot, nEnemyHeroes[1], nCastRange)
	and J.CanCastOnNonMagicImmune(nEnemyHeroes[1])
	and J.CanCastOnTargetAdvanced(nEnemyHeroes[1])
	then
		return BOT_ACTION_DESIRE_HIGH, nEnemyHeroes[1], 'unit', nil
	end

	for _, enemyHero in pairs(nEnemyHeroes)do
		if J.IsValidHero(enemyHero)
		and J.IsInRange(bot, enemyHero, nCastRange)
		and J.CanCastOnNonMagicImmune(enemyHero)
		and J.CanCastOnTargetAdvanced(enemyHero)
		and (enemyHero:GetAttackTarget() == bot)
		and (bot:WasRecentlyDamagedByHero(enemyHero, 3.0) or J.IsAttackProjectileIncoming(bot, 1000))
		then
			return BOT_ACTION_DESIRE_HIGH, enemyHero, 'unit', nil
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

-- Minotaur Horn
X.ConsiderItemDesire["item_minotaur_horn"] = function( hItem )
	if bot:IsMagicImmune()
	or not J.CanBeAttacked(bot)
	or not bot:HasModifier('modifier_item_lotus_orb_active')
    or not bot:HasModifier('modifier_antimage_spell_shield')
	then
        return BOT_ACTION_DESIRE_NONE
    end

    local nEnemyHeroes = J.GetEnemiesNearLoc(bot:GetLocation(), 1200)

	if (J.IsGoingOnSomeone(bot) or (J.IsRetreating(bot) and not J.IsRealInvisible(bot)))
    and #nEnemyHeroes > 0
	then
		if bot:IsRooted() then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end

        nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 600)
		if bot:IsSilenced()
        and #nInRangeEnemy >= 2
        and not bot:HasModifier('modifier_item_mask_of_madness_berserk')
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end

		if J.IsNotAttackProjectileIncoming(bot, 300)
		or J.IsWillBeCastUnitTargetSpell(bot, 300)
		or J.IsWillBeCastPointSpell(bot, 300)
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end

        nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1200)
		if #nInRangeEnemy > #nAllyHeroes
        and J.GetHP(bot) < 0.6
        and J.IsValidHero(nInRangeEnemy[1])
        and (J.IsChasingTarget(nInRangeEnemy[1], bot) or nInRangeEnemy[1]:GetAttackTarget() == bot)
		then
			return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
		end
	end

    if bot:HasModifier('modifier_jakiro_macropyre_burn')
    or bot:HasModifier('modifier_lich_chainfrost_slow')
    or bot:HasModifier('modifier_crystal_maiden_freezing_field_slow')
    or bot:HasModifier('modifier_puck_coiled')
    or bot:HasModifier('modifier_skywrath_mystic_flare_aura_effect')
    or bot:HasModifier('modifier_snapfire_magma_burn_slow')
    or bot:HasModifier('modifier_sand_king_epicenter_slow')
    then
        return BOT_ACTION_DESIRE_HIGH, bot, 'none', nil
    end

	return BOT_ACTION_DESIRE_NONE
end

-- Book of Shadows
X.ConsiderItemDesire["item_book_of_shadows"] = function( hItem )
	local nCastRange = 700 + aetherRange
	local nInRangeAlly = J.GetAlliesNearLoc(bot:GetLocation(), nCastRange)
	local nInRangeEnemy = J.GetEnemiesNearLoc(bot:GetLocation(), 1200)

	for _, allyHero in pairs(nInRangeAlly)
	do
		if J.IsValidHero(allyHero)
		and J.CanCastOnNonMagicImmune(allyHero)
		and allyHero:WasRecentlyDamagedByAnyHero(3)
		then
			local nAllyInRangeEnemy = J.GetNearbyHeroes(allyHero, 1200, true, BOT_MODE_NONE)

			if nAllyInRangeEnemy ~= nil and #nAllyInRangeEnemy >= 1
			and J.IsRetreating(allyHero)
			and not J.IsRealInvisible(allyHero)
			and not J.IsDisabled(allyHero)
			and allyHero:DistanceFromFountain() > 1200
			then
				return BOT_ACTION_DESIRE_HIGH, allyHero, 'unit', nil
			end
		end
	end

	return BOT_ACTION_DESIRE_NONE
end

function X.IsTargetedByEnemy( building )

	local heroList = GetUnitList( UNIT_LIST_ENEMY_HEROES )
	for _, hero in pairs( heroList )
	do
		if J.IsValidHero(hero) then
			if ( GetUnitToUnitDistance( building, hero ) <= hero:GetAttackRange() + 200
				and hero:GetAttackTarget() == building )
			then
				return true
			end
		end
	end

	return false

end

local function HasGlyphPressure(building)
	if X.IsTargetedByEnemy(building) then return true end
	local attackers = 0
	for _, creep in ipairs(GetUnitList(UNIT_LIST_ENEMY_CREEPS)) do
		if J.IsValid(creep) and creep:GetAttackTarget() == building then
			attackers = attackers + (string.find(creep:GetUnitName(), 'siege', 1, true) and 2 or 1)
			if attackers >= 3 then return true end
		end
	end
	return false
end

local function GetGlyphClearerETA(ally, tower, defense)
	local speed = math.max(250, ally:GetCurrentMovementSpeed())
	local rally = defense.waveClearGather or tower:GetLocation()
	local slack = defense.waveClearGather and 250 or 500
	local time = math.max(0, GetUnitToLocationDistance(ally, rally) - slack) / speed
	if defense.waveClearTeleport ~= nil then
		for _, tp in ipairs(GetIncomingTeleports()) do
			if tp.playerid == ally:GetPlayerID() and tp.location ~= nil and tp.time_remaining ~= nil
				and tp.time_remaining >= 0
				and J.GetLocationToLocationDistance(tp.location, defense.waveClearTeleport) <= 350 then
				time = math.min(time, tp.time_remaining
					+ math.max(0, J.GetLocationToLocationDistance(tp.location, rally) - slack) / speed)
			end
		end
	end
	return time
end

local function UseGlyph()

	if GetGlyphCooldown( ) > 0
		or DotaTime() < 60
		or bot ~= GetTeamMember( 1 )
	then
		return
	end

	for i = 2, 5 do
		local teammate = GetTeamMember(i)
		if teammate == nil or not teammate:IsBot() then
			return
		end
	end

	local T1 = {
		TOWER_TOP_1,
		TOWER_MID_1,
		TOWER_BOT_1,
		TOWER_TOP_2,
		TOWER_MID_2,
		TOWER_BOT_2,
		TOWER_TOP_3,
		TOWER_MID_3,
		TOWER_BOT_3,
		TOWER_BASE_1,
		TOWER_BASE_2
	}

	local coverOuter = false
	local coverage = J.GetPostFightCoverage and J.GetPostFightCoverage(team)
	for _, front in ipairs(coverage and (coverage.lanes or {coverage}) or {}) do
		local tower, clear = front.building, front.primary
		if clear and J.IsValidBuilding(tower) and not tower:HasModifier('modifier_fountain_glyph') and HasGlyphPressure(tower) then
			local threat = J.GetOuterTowerThreat(tower, front.lane or LANE_MID)
			if threat.damageRate and threat.damageRate > 0 then
				local life = tower:GetHealth() / threat.damageRate
				local timeToAction = clear.arrival + 1
				if life < timeToAction and timeToAction <= life + 5 and threat.waveSize > 0 then
					coverOuter=true
				end
			end
		end
	end
	for index = #T1, 1, -1
	do
		local tower = GetTower(team, T1[index])
		if tower ~= nil and tower:GetHealth() > 0
			and (index <= 6 or tower:GetHealth() / tower:GetMaxHealth() < 0.40)
			and tower:CanBeSeen()
			and not tower:HasModifier('modifier_fountain_glyph')
			and HasGlyphPressure(tower)
		then
			if index > 6 then
				bot:ActionImmediate_Glyph()
				return
			end
			local fraction = tower:GetHealth() / tower:GetMaxHealth()
			local lanes = {LANE_TOP, LANE_MID, LANE_BOT}
			local threat = J.GetOuterTowerThreat(tower, lanes[(index - 1) % 3 + 1])
			local secondsLeft = threat.damageRate > 0 and tower:GetHealth() / threat.damageRate or math.huge
			-- The fight planner can admit a defender beyond the normal Glyph ETA.
			-- Count that ally only when the tower's remaining life plus protection is enough.
			local gatherETA = math.min(8.5, math.max(5.5, secondsLeft + 4))
			local contestCount, lateETA, needed = 0, 0, false
			for _, ally in ipairs(J.GetAlliesNearLoc(tower:GetLocation(), 24000)) do
				local defense = ally._defend
				if defense and defense.waveClearTower == tower and not defense.waveClearCover
					and defense.waveClearRearTower == nil
					and (ally.ohaOuterTowerHoldUntil or 0) > DotaTime()
				then
					local eta = GetGlyphClearerETA(ally, tower, defense)
					local forFight = defense.waveClearGather and not defense.waveClearScreen
					if eta <= (forFight and gatherETA or 5.5) then
						if forFight then
							contestCount, lateETA = contestCount + 1, math.max(lateETA, eta)
							needed = needed or defense.waveClearNeedsGlyph
						elseif (fraction < 0.50 and secondsLeft <= math.max(12, eta + 4))
							or (index == 2 and threat.count >= 3 and (threat.waveSize or 0) >= 2
								and threat.underAttack and eta <= 4 and fraction <= 0.70 and secondsLeft <= 11)
							or (fraction <= 0.20 and threat.siegeAttacking)
							or (threat.count >= 3 and secondsLeft <= eta + 3) then
							coverOuter = true
						end
					end
				end
			end
			if contestCount >= 3 then
				if contestCount >= threat.count and (needed or fraction < 0.45
					or threat.damageRate > 0 and tower:GetHealth() / threat.damageRate <= lateETA + 2) then coverOuter = true end
			end
		end
	end


	local MeleeBarrack = {
		BARRACKS_TOP_MELEE,
		BARRACKS_MID_MELEE,
		BARRACKS_BOT_MELEE
	}

	for _, b in pairs( MeleeBarrack )
	do
		local barrack = GetBarracks( team, b )
		if barrack ~= nil and barrack:GetHealth() > 0
			and barrack:GetHealth() / barrack:GetMaxHealth() < 0.5
			and HasGlyphPressure(barrack)
		then
			bot:ActionImmediate_Glyph( )
			return
		end
	end

	local Ancient = GetAncient( team )
	if Ancient ~= nil and Ancient:GetHealth() > 0
		and Ancient:GetHealth() / Ancient:GetMaxHealth() < 0.5
		and HasGlyphPressure(Ancient)
	then
		bot:ActionImmediate_Glyph( )
		return
	end

	if coverOuter then bot:ActionImmediate_Glyph() end
end

function ItemUsageThink()
	if RefreshBotHandle() then return end
	if not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion()
		or bot:IsInvulnerable() and not bot:HasModifier('modifier_fountain_invulnerability')
	then return end
	if bot.lastItemFrameProcessTime == nil then bot.lastItemFrameProcessTime = DotaTime() end
	if DotaTime() > 30 and (DotaTime() - bot.lastItemFrameProcessTime < (bot.frameProcessTime * (1 + Customize.ThinkLess))) then return end
	bot.lastItemFrameProcessTime = DotaTime()
	if not J.IsNoItemIllution(bot) then ItemUsageComplement() end
end

function X.TraceDefenseMovement(now)
	if now < 0 then return end
	local position = bot:GetLocation()
	local sample = bot.ohaDefenseMovement
	if sample and now >= sample.sampled and now < sample.sampled + 0.5 then return end
	local lastAttack = bot:GetLastAttackTime()
	local high, guard, outer = bot.ohaHighGroundResponse, bot.ohaMidCover, bot._defend
	if high and high.expires <= now then high = nil end
	if guard and guard.expires <= now then guard = nil end
	if (bot.ohaOuterTowerHoldUntil or 0) <= now then outer = nil end
	local duty = (bot._ohaCreepDefenseUntil or -1) > now and 'base-creeps'
		or (bot.ohaInnerHeroDefenseUntil or -1) > now and 'base-hero'
		or high and ('high-ground-' .. (high.duty or 'reserve')) or guard and (guard.cover and 'cover' or 'clear')
		or outer and 'outer' or 'unassigned'
	local tower = high and high.tower or guard and guard.tower or outer and outer.waveClearTower
	local mode = bot:GetActiveMode()
	if sample and sample.reported and now >= sample.sampled and now - sample.sampled <= 2 and lastAttack ~= sample.attack then
		print(string.format('[OHA auto-resumed] %.2f hero=%s since=%.2f mode=%d', now, botName, sample.started, mode))
	end
	if not sample or now < sample.sampled or now - sample.sampled > 2 or lastAttack ~= sample.attack then
		bot.ohaDefenseMovement = {started=now, sampled=now, origin=position, last=position, travel=0,
			attack=lastAttack, mode=mode, duty=duty, nextReport=now+10}
		return
	end
	sample.travel = sample.travel + J.GetLocationToLocationDistance(sample.last, position)
	sample.last, sample.sampled = position, now
	if now < sample.nextReport then return end
	local displacement = J.GetLocationToLocationDistance(sample.origin, position)
	if duty ~= 'unassigned' or J.IsDefending(bot) or displacement <= 200 then
		local target = bot:GetAttackTarget()
		local creep = bot:GetNearbyLaneCreeps(1500, true)[1]
		local function describe(unit)
			if not unit or unit:IsNull() or not unit:CanBeSeen() then return '-' end
			return string.format('%s@%.0f', unit:GetUnitName(), GetUnitToUnitDistance(bot, unit))
		end
		print(string.format('[OHA no-auto] %.2f hero=%s since=%.2f mode=%d>%d duty=%s>%s tower=%s target=%s laneCreep=%s travel=%.0f net=%.0f action=%d channel=%s',
			now, botName, sample.started, sample.mode, mode, sample.duty, duty, describe(tower), describe(target), describe(creep), sample.travel,
			displacement, bot:GetCurrentActionType(), tostring(bot:IsChanneling())))
		sample.reported = true
	end
	sample.nextReport = now + 10
end

function AbilityUsageThink()
	if RefreshBotHandle() then return end
	if GetGameState() == GAME_STATE_PRE_GAME and DotaTime() < 0 and not bot:IsIllusion()
		and DotaTime() >= (bot.ohaOpeningRuneStepAt or -math.huge) then
		local spot, location = OpeningRune.Target(bot)
		if J.Customize and J.Customize.TraceLaneDecisions and not bot.ohaOpeningRuneTick then
			bot.ohaOpeningRuneTick = true
			print('[OHA pregame]', DotaTime(), bot:GetPlayerID(), bot:GetAssignedLane(), spot, bot:GetActiveMode())
		end
		if OpeningRune.Walk(bot, spot, location) then return end
	end
	if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end
	if bot.lastAbilityFrameProcessTime == nil then bot.lastAbilityFrameProcessTime = DotaTime() end
	if DotaTime() > 30 and (DotaTime() - bot.lastAbilityFrameProcessTime < (bot.frameProcessTime * (1 + Customize.ThinkLess))) and bot.isBear == nil then return end
	bot.lastAbilityFrameProcessTime = DotaTime()
	J.CheckBotIdleState()
	if J.Customize and J.Customize.TraceLaneDecisions then X.TraceDefenseMovement(bot.lastAbilityFrameProcessTime) end
	local protectingShot = bot.ohaLaningAttackTarget ~= nil and J.HasPendingLaningLastHit(bot)
	if not protectingShot and bot.ohaEngineMid and J.IsLaning(bot) and J.IsInLaningPhase(bot) then
		local target = bot:GetAttackTarget()
		protectingShot = J.IsValid(target) and target:IsCreep() and J.IsFinishingLaningAttack(bot, target)
	end
	if protectingShot then
		local enemies = J.GetNearbyHeroes(bot, 1050, true, BOT_MODE_NONE)
		if #enemies == 0 or (J.IsLaning(bot) and J.GetHP(bot) >= 0.5
			and not J.IsLaningUnderPressure(bot, enemies, bot:GetNearbyTowers(1200, true)[1])) then return end
	end
	if BotBuild ~= nil and not J.IsNoAbilityIllution(bot) then BotBuild.SkillsComplement() end
end

function BuybackUsageThink()
	if RefreshBotHandle() then return end
	if bot.lastBuybackFrameProcessTime == nil then bot.lastBuybackFrameProcessTime = DotaTime() end
	if DotaTime() > 30 and (DotaTime() - bot.lastBuybackFrameProcessTime < 2) then return end
	bot.lastBuybackFrameProcessTime = DotaTime()
	if not bot:IsIllusion() then BuybackUsageComplement() end
	if not bot:IsIllusion() then UseGlyph() end
end

function CourierUsageThink()
	if RefreshBotHandle() then return end
	if bot.lastCourierFrameProcessTime == nil then bot.lastCourierFrameProcessTime = DotaTime() end
	if DotaTime() > 30 and (DotaTime() - bot.lastCourierFrameProcessTime < 0.5) then return end
	bot.lastCourierFrameProcessTime = DotaTime()
	if not bot:IsIllusion() then CourierUsageComplement() end
end

function AbilityLevelUpThink()
	if RefreshBotHandle() then return end
	if bot.lastLevelUpFrameProcessTime == nil then bot.lastLevelUpFrameProcessTime = DotaTime() end
	if DotaTime() > 30 and (DotaTime() - bot.lastLevelUpFrameProcessTime < 1) then return end
	bot.lastLevelUpFrameProcessTime = DotaTime()
	if not bot:IsIllusion() then AbilityLevelUpComplement() end
end

function X.SetAbilityItemList(heroAbility, items, abilityLvlup)
	bDeafaultAbilityHero = heroAbility
	bDeafaultItemHero = items
	sAbilityLevelUpList = abilityLvlup
	pendingLevelUp = nil
end

X.AbilityLevelUpThink = AbilityLevelUpThink
X.BuybackUsageThink = BuybackUsageThink
X.AbilityUsageThink = AbilityUsageThink
X.ItemUsageThink = ItemUsageThink

return X
