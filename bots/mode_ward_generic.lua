if GetBot():IsInvulnerable() or not GetBot():IsHero() or not string.find(GetBot():GetUnitName(), "hero") or  GetBot():IsIllusion() then
	return
end

local X = {}

local bot = GetBot()
local J = require(GetScriptDirectory()..'/FunLib/jmz_func')
local W = require(GetScriptDirectory() ..'/FunLib/aba_ward_utility')
local Customize = require(GetScriptDirectory()..'/Customize/general')
Customize.ThinkLess = Customize.Enable and Customize.ThinkLess or 1

local nObserverWardCastRange = 500
local nSentryWardCastRange = 500

local ObserverWard = nil
local SentryWard = nil

local hTargetSpot = nil
local plantingSentry = false
local fLastWardPlantTime = -math.huge

function GetDesire()
	if (bot.ohaIdleRecoveryUntil or 0) > math.max(0, DotaTime())
		or (bot.ohaOuterTowerHoldUntil or 0) > math.max(0, DotaTime()) then return BOT_MODE_DESIRE_NONE end
	if J.GetPosition(bot) <= 3 then return false end
	-- local cacheKey = 'GetWardDesire'..tostring(bot:GetPlayerID())
	-- local cachedVar = J.Utils.GetCachedVars(cacheKey, 0.6 * (1 + Customize.ThinkLess))
	-- if DotaTime() > 30 and cachedVar ~= nil then return cachedVar end
	local res = GetDesireHelper()
	-- J.Utils.SetCachedVars(cacheKey, res)
	return RemapValClamped(J.GetHP(bot) * res, 0, 1, BOT_MODE_DESIRE_NONE, res)
end
function GetDesireHelper()
    hTargetSpot, plantingSentry = nil, false
    if not X.IsSuitableToWard() then
        return BOT_MODE_DESIRE_NONE
    end

	-- 如果在打高地 就别撤退去干别的
	if J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		return BOT_MODE_DESIRE_NONE
	end
	local enemiesAtAncient = J.Utils.CountEnemyHeroesNear(GetAncient(GetTeam()):GetLocation(), 3200)
    if enemiesAtAncient >= 1 then
        return BOT_MODE_DESIRE_NONE
    end

    local now = DotaTime()
    local stayInLane = now >= -5 and J.IsInLaningPhase(bot) and (now <= 90 or not J.CanLeaveLane(bot))
    ObserverWard = nil
    for i = 0, 5 do
        local hItem = bot:GetItemInSlot(i)
        if hItem then
            local sItemName = hItem:GetName()
            if sItemName == 'item_ward_observer' or sItemName == 'item_ward_dispenser' then
                ObserverWard = hItem
				break
            end
        end
    end

    -- Observer
    if J.CanCastAbility(ObserverWard) then
        local hAvailabeObserverWardSpots = W.GetAvailabeObserverWardSpots(bot)
        hTargetSpot = W.GetClosestObserverWardSpot(bot, hAvailabeObserverWardSpots)
		if hTargetSpot and (not stayInLane or GetUnitToLocationDistance(bot, hTargetSpot.location) <= nObserverWardCastRange)
			and (not X.IsEnemyCloserToWardLocation(hTargetSpot.location) or J.IsRealInvisible(bot)) then
			if DotaTime() < 0 and DotaTime() > (J.IsModeTurbo() and -45 or -60) then
				return BOT_MODE_DESIRE_ABSOLUTE
			end

			if DotaTime() > fLastWardPlantTime + 1.0 then
				if GetUnitToLocationDistance(bot, hTargetSpot.location) <= 3200 then
					return BOT_MODE_DESIRE_VERYHIGH
				end
			end
		end
    end

	SentryWard = nil
	for i = 0, 5 do
        local hItem = bot:GetItemInSlot(i)
        if hItem then
            local sItemName = hItem:GetName()
            if (sItemName == 'item_ward_sentry' or sItemName == 'item_ward_dispenser')
                and J.Item.GetSentryCharges(hItem) > 0 then
                SentryWard = hItem
				break
            end
        end
    end

    -- Sentry
    if J.CanCastAbility(SentryWard) then
        local hPossibleSentryWardSpots = W.GetPossibleSentryWardSpots(bot)
        hTargetSpot = W.GetClosestSentryWardSpot(bot, hPossibleSentryWardSpots)
		if hTargetSpot and (not stayInLane or GetUnitToLocationDistance(bot, hTargetSpot.location) <= nSentryWardCastRange)
			and not J.HasSentryCoverage(hTargetSpot.location)
			and (not X.IsEnemyCloserToWardLocation(hTargetSpot.location) or J.IsRealInvisible(bot)) then
			if DotaTime() > fLastWardPlantTime + 1.0 then
				if GetUnitToLocationDistance(bot, hTargetSpot.location) <= 3200 then
					plantingSentry = true
					return BOT_MODE_DESIRE_VERYHIGH
				end
			end
		end
    end

	hTargetSpot = nil
	return BOT_MODE_DESIRE_NONE
end

function Think()
	if J.CanNotUseAction(bot) then return end
	if J.Utils.IsBotThinkingMeaningfulAction(bot, Customize.ThinkLess, "ward") then return end
	if hTargetSpot then
		if not plantingSentry and ObserverWard and J.CanCastAbility(ObserverWard) then
			if GetUnitToLocationDistance(bot, hTargetSpot.location) <= nObserverWardCastRange then
				if ObserverWard:GetName() == 'item_ward_observer' then
					bot:Action_UseAbilityOnLocation(ObserverWard, hTargetSpot.location)
				else
					if ObserverWard:GetToggleState() == false then
						bot:Action_UseAbilityOnEntity(ObserverWard, bot)
						return
					else
						bot:Action_UseAbilityOnLocation(ObserverWard, hTargetSpot.location)
					end
				end

				hTargetSpot.plant_time_obs = DotaTime()
				return
			else
				bot:Action_MoveToLocation(hTargetSpot.location)
				return
			end
		end

		if plantingSentry and SentryWard and J.CanCastAbility(SentryWard) then
			if J.HasSentryCoverage(hTargetSpot.location) then
				hTargetSpot = nil
				return
			end
			if GetUnitToLocationDistance(bot, hTargetSpot.location) <= nSentryWardCastRange then
				local fLength = 0
				if W.IsOtherWardClose(hTargetSpot.location, 'npc_dota_observer_wards', 300, true, false) then
					fLength = 30
				end

				if SentryWard:GetName() == 'item_ward_dispenser' and SentryWard:GetToggleState() then
					bot:Action_UseAbilityOnEntity(SentryWard, bot)
					return
				end

				local location = hTargetSpot.location + RandomVector(fLength)
				bot:Action_UseAbilityOnLocation(SentryWard, location)
				J.RecordSentryOrder(bot, location)
				hTargetSpot.plant_time_sentry = DotaTime()
				return
			else
				bot:Action_MoveToLocation(hTargetSpot.location)
				return
			end
		end
	end
end

function X.IsSuitableToWard()
	local nEnemyHeroes = bot:GetNearbyHeroes(1200, true, BOT_MODE_NONE)

	local botActiveMode = bot:GetActiveMode()
    local botActiveModeDesire = bot:GetActiveModeDesire()

	if (J.IsRetreating(bot) and botActiveModeDesire > 0.75)
	or (botActiveMode == BOT_MODE_RUNE and DotaTime() > 0)
	or (botActiveMode == BOT_MODE_DEFEND_ALLY)
	or (nEnemyHeroes ~= nil and #nEnemyHeroes >= 1 and X.IsIBecameTheTarget(nEnemyHeroes))
    or J.IsDefending(bot)
	or J.IsGoingOnSomeone(bot)
	or bot:WasRecentlyDamagedByAnyHero(5.0)
	then
		return false
	end

	return true
end

function X.IsIBecameTheTarget(unitList)
	for _, unit in pairs(unitList) do
		if J.IsValid(unit)
        and not J.IsSuspiciousIllusion(unit)
		and unit:GetAttackTarget() == bot
		then
			return true
		end
	end

	return false
end

function X.IsEnemyCloserToWardLocation(vLocation)
	for _, id in pairs(GetTeamPlayers(GetOpposingTeam())) do
		if IsHeroAlive(id) then
			local info = GetHeroLastSeenInfo(id)
			if info ~= nil then
				local dInfo = info[1]
				if  dInfo ~= nil
				and dInfo.time_since_seen < 3.0
				and J.GetDistance(dInfo.location, vLocation) < GetUnitToLocationDistance(bot, vLocation)
				then
					local nAllyHeroes = J.GetAlliesNearLoc(vLocation, 1200)
					local nEnemyHeroes = J.GetEnemiesNearLoc(vLocation, 1200)
					if #nEnemyHeroes > #nAllyHeroes then
						return true
					end
				end
			end
		end
	end

	return false
end
