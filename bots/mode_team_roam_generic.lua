local bot = GetBot()
if bot == nil then return end
local botName = bot:GetUnitName()
if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

local Utils = require(GetScriptDirectory()..'/FunLib/utils')
local EnemyRoles = require(GetScriptDirectory()..'/FunLib/enemy_role_estimation')
local Localization = require(GetScriptDirectory()..'/FunLib/localization')
local Customize = require(GetScriptDirectory()..'/Customize/general')
Customize.ThinkLess = Customize.Enable and Customize.ThinkLess or 1
local J = require(GetScriptDirectory()..'/FunLib/jmz_func')
local Item = require(GetScriptDirectory()..'/FunLib/aba_item')
local Roles = require(GetScriptDirectory()..'/FunLib/aba_role')
local AttackSpecialUnit = dofile(GetScriptDirectory()..'/FunLib/aba_special_units')

local X = {}
local team = GetTeam()

-- ==============================
-- Runtime state
-- ==============================
local targetUnit = nil
local towerCreepMode, towerCreep = false, nil
local towerTime, towerCreepTime = 0, 0
local nTpSolt = 15

local beInitDone, IsSupport, IsHeroCore, bePvNMode = false, false, false, false
local ShouldAttackSpecialUnit = false
local lastIdleStateCheck = -1
local rescueAlly, rescueEnemy, issuedRescueTarget
local nearbyAllies, nearbyEnemies
local focusEnemy, issuedFocusTarget

-- Pickup / swap timers
local PickedItem = nil
local minPickItemCost = 200
local pickupAttempts = setmetatable({}, {__mode = 'k'})
local ConsiderDroppedTime = -90
local SwappedCheeseTime   = -90
local SwappedClarityTime  = -90
local SwappedFlaskTime    = -90
local SwappedSmokeTime    = -90
local SwappedRefresherShardTime = -90
local SwappedMoonshardTime = -90
local lastCheckBotToDropTime = 0

local IsAvoidingAbilityZone = false

local hTargetCreep = nil

local function CanSupportCommitToTarget(target)
    return not J.IsInLaningPhase(bot) or not J.IsValidHero(target) or J.HasLaneFightFollowUp(bot, target)
end

local function CancelRescueOrder()
    if issuedRescueTarget == nil then return end
    if not J.CanNotUseAction(bot) then bot:Action_ClearActions(true) end
    if bot:GetTarget() == issuedRescueTarget then bot:SetTarget(nil) end
    issuedRescueTarget = nil
end

local function CapForLanePush(desire)
    -- keep "team roam" from overpowering laning/pushing micro
    if J.IsInLaningPhase() or J.IsPushing(bot) then
        if desire > 0.9 then return 0.72 end  -- soft ceiling
    end
    return desire
end

function GetDesire()
    -- local cacheKey = 'GetTeamRoamDesire'..tostring(bot:GetPlayerID())
    -- local cachedVar = J.Utils.GetCachedVars(cacheKey, 0.2 * (1 + Customize.ThinkLess))
    -- if DotaTime() > 30 and cachedVar ~= nil then return cachedVar end

    local res = GetDesireHelper()
    if rescueEnemy == nil then res = CapForLanePush(res) end

    -- J.Utils.SetCachedVars(cacheKey, res)
    return res
end
function GetDesireHelper()
    rescueAlly, rescueEnemy = nil, nil
    focusEnemy = nil
    hTargetCreep, ShouldAttackSpecialUnit = nil, false
    if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then
        return BOT_MODE_DESIRE_NONE
    end

    if J.ShouldRetreatFromEnemyReinforcements(bot) then return BOT_MODE_DESIRE_NONE end
    if (bot.ohaOuterTowerHoldUntil or 0) > math.max(0, DotaTime()) then
        IsAvoidingAbilityZone = HasModifierThatNeedToAvoidEffects() or bot:HasModifier('modifier_warlock_upheaval')
        return IsAvoidingAbilityZone and BOT_ACTION_DESIRE_VERYHIGH + 0.1 or BOT_MODE_DESIRE_NONE
    end

    Utils.SetFrameProcessTime(bot)
    EnemyRoles.UpdateEnemyHeroPositions()

    IsAvoidingAbilityZone = false

    bot.laneToPush   = bot.ohaPostFightPushLane or J.GetMostPushLaneDesire()
    bot.laneToDefend = J.GetMostDefendLaneDesire()

    if DotaTime() - lastIdleStateCheck >= 1 then
        J.CheckBotIdleState()
        lastIdleStateCheck = DotaTime()
    end

    if not beInitDone then
        beInitDone = true
        bePvNMode = J.Role.IsPvNMode()
        IsHeroCore = J.IsCore(bot)
        IsSupport  = not IsHeroCore
    end

    local itemDesire, isBattleHorn = ItemOpsDesire()

    rescueEnemy, rescueAlly = X.ConsiderHelpWhenCoreIsTargeted()
    if rescueEnemy ~= nil then
        targetUnit = nil
        return RemapValClamped(J.GetHP(bot), 0, 0.5, BOT_MODE_DESIRE_NONE, 0.98)
    end

    nearbyAllies = J.GetAlliesNearLoc(bot:GetLocation(), 2200)
    nearbyEnemies = J.GetEnemiesNearLoc(bot:GetLocation(), 2000)

    rescueEnemy, rescueAlly = ConsiderHelpAlly()
    if rescueEnemy ~= nil then
        targetUnit = nil
        return RemapValClamped(J.GetHP(bot), 0, 0.6, BOT_MODE_DESIRE_NONE, 0.98)
    end

    -- The lane mode times shots and holds position while a mid wave is contested.
    local midWave = J.IsInLaningPhase() and J.IsCore(bot) and bot:GetAssignedLane() == LANE_MID
        and GetUnitToLocationDistance(bot, GetLaneFrontLocation(team, LANE_MID, 0)) <= 1400
        and #bot:GetNearbyLaneCreeps(1200, true) > 0
    if not midWave then
        hTargetCreep = X.GetLastHitCreep()
        if J.IsValid(hTargetCreep) and J.CanBeAttacked(hTargetCreep) then
            return 1.5
        end
    end

    if not bot:IsAlive() or bot:GetCurrentActionType() == BOT_ACTION_TYPE_DELAY then
        return BOT_MODE_DESIRE_NONE
    end

    local nDesire = AttackSpecialUnit.GetDesire(bot)
    if nDesire > 0 then
        ShouldAttackSpecialUnit = true
        return RemapValClamped(J.GetHP(bot), 0.1, 0.8, BOT_MODE_DESIRE_NONE, nDesire)
    end

    if J.IsInLaningPhase() and bot:HasModifier('modifier_warlock_upheaval') then
        IsAvoidingAbilityZone = true
        return BOT_ACTION_DESIRE_VERYHIGH + 0.1
    end

    if HasModifierThatNeedToAvoidEffects() then
        IsAvoidingAbilityZone = true
        return RemapValClamped(J.GetHP(bot), 0.3, 1, BOT_ACTION_DESIRE_VERYHIGH, BOT_ACTION_DESIRE_NONE)
    end

    if isBattleHorn then return itemDesire end

    focusEnemy = J.GetSupportedFightTarget(bot, nearbyEnemies, nearbyAllies)
    if IsSupport and not CanSupportCommitToTarget(focusEnemy) then focusEnemy = nil end
    if focusEnemy ~= nil then return 0.86 end

    if not J.IsFarming(bot) and not J.IsPushing(bot) and not J.IsDefending(bot)
    and not J.IsDoingRoshan(bot) and not J.IsDoingTormentor(bot)
    and bot:GetActiveMode() ~= BOT_MODE_RUNE
    and bot:GetActiveMode() ~= BOT_MODE_SECRET_SHOP
    and bot:GetActiveMode() ~= BOT_MODE_OUTPOST
    and bot:GetActiveMode() ~= BOT_MODE_WARD
    and bot:GetActiveMode() ~= BOT_MODE_ATTACK
    and bot:GetActiveMode() ~= BOT_MODE_DEFEND_ALLY
    and bot:GetActiveMode() ~= BOT_MODE_ROAM then
        return BOT_ACTION_DESIRE_NONE
    elseif #nearbyAllies >= #nearbyEnemies then
        if IsHeroCore and not midWave then
            local botTarget, targetDesire = X.CarryFindTarget()
            if botTarget ~= nil then
                targetUnit = botTarget
                bot:SetTarget(botTarget)
                return RemapValClamped(J.GetHP(bot), 0, 0.4, BOT_MODE_DESIRE_NONE, targetDesire)
            end
        end
        if IsSupport then
            local botTarget, targetDesire = X.SupportFindTarget()
            if botTarget ~= nil and CanSupportCommitToTarget(botTarget) then
                targetUnit = botTarget
                bot:SetTarget(botTarget)
                return RemapValClamped(J.GetHP(bot), 0, 0.4, BOT_MODE_DESIRE_NONE, targetDesire)
            end
        end

        if bot:IsAlive() and bot:DistanceFromFountain() > 4600 then
            if towerTime ~= 0 and X.IsValid(towerCreep) and DotaTime() < towerTime + towerCreepTime then
                return RemapValClamped(J.GetHP(bot), 0, 0.4, BOT_MODE_DESIRE_NONE, 0.9)
            else
                towerTime, towerCreepMode = 0, false
            end

            towerCreepTime, towerCreep = X.ShouldAttackTowerCreep(bot)
            if towerCreepTime ~= 0 and towerCreep ~= nil then
                if towerTime == 0 then
                    towerTime = DotaTime()
                    towerCreepMode = true
                end
                bot:SetTarget(towerCreep)
                return RemapValClamped(J.GetHP(bot), 0, 0.4, BOT_MODE_DESIRE_NONE, 0.9)
            end
        end
    end

    return 0.0
end

function X.GetLastHitCreep()
	if J.IsRetreating(bot)
	or (not J.IsCore(bot) and not J.IsInLaningPhase() and J.IsThereCoreNearby(800))
	or J.IsInTeamFight(bot, 1200)
	then
		return nil
	end

	local nEnemyTowers = bot:GetNearbyTowers(1000, true)
	local nEnemyCreeps = bot:GetNearbyCreeps(1200, true)
	for _, creep in pairs(nEnemyCreeps) do
		if J.IsValid(creep)
		and J.CanBeAttacked(creep)
		and J.IsInRange(bot, creep, bot:GetAttackRange() + 300)
		and not J.IsRoshan(creep)
		and not J.IsTormentor(creep)
		and J.CanSupportTakeLaneLastHit(bot, creep)
		and (J.IsCore(bot) or creep:GetTeam() ~= TEAM_NEUTRAL or not J.IsThereCoreNearby(800))
		then
			local nDelay = J.GetAttackProDelayTime(bot, creep)
			if J.WillKillTarget(creep, bot:GetAttackDamage()-1, DAMAGE_TYPE_PHYSICAL, nDelay)
			and (#nEnemyTowers == 0 or (J.IsValidBuilding(nEnemyTowers[1]) and not J.IsInRange(creep, nEnemyTowers[1], 750)))
			then
				local nInRangeAlly = J.GetAlliesNearLoc(creep:GetLocation(), 1000)
				local nInRangeEnemy = J.GetEnemiesNearLoc(creep:GetLocation(), 1000)
				if #nInRangeAlly >= #nInRangeEnemy then
					return creep
				end
			end
		end
	end

	return nil
end

-- ==============================
-- Avoid zones
-- ==============================
function HasModifierThatNeedToAvoidEffects()
    return bot:HasModifier('modifier_jakiro_macropyre_burn')
        or bot:HasModifier('modifier_dark_seer_wall_slow')
        or ((bot:HasModifier('modifier_sandking_sand_storm_slow') or bot:HasModifier('modifier_sand_king_epicenter_slow'))
            and (not bot:HasModifier("modifier_black_king_bar_immune")
                or not bot:HasModifier("modifier_magic_immune")
                or not bot:HasModifier("modifier_omniknight_repel")))
end

-- ==============================
-- Desire Helpers
-- ==============================
local function CanRescueAlly(ally)
    return J.IsValidHero(ally) and J.GetHP(bot) >= 0.3
        and (not J.IsCore(bot) or bot.isBear or not J.IsInLaningPhase() or J.IsInRange(bot, ally, 1600))
        and not J.IsGoingOnSomeone(bot)
        and not (J.IsRetreating(bot) and bot:GetActiveModeDesire() > 0.8)
end

local function CanPeelEnemy(ally, enemy)
    return J.IsValidHero(enemy) and X.CanBeAttacked(enemy)
        and J.IsInRange(bot, enemy, 1800) and J.IsInRange(ally, enemy, 1600)
        and (enemy:GetAttackTarget() == ally or J.IsChasingTarget(enemy, ally))
end

local function FindRescueEnemy(ally, expectedEnemy)
    if not CanRescueAlly(ally) then return nil end
    local location = ally:GetLocation()
    local enemies = J.GetEnemiesNearLoc(location, 1600)
    if #enemies > 1 + J.GetAvailableFightAllies(bot, location, 1200) then return nil end
    for _, enemy in ipairs(enemies) do
        if (expectedEnemy == nil or enemy == expectedEnemy) and CanPeelEnemy(ally, enemy) then return enemy end
    end
end

function ConsiderHelpAlly()
    local ally = J.GetClosestAlly(bot, 1800)
    if J.IsValidHero(ally) and J.GetHP(bot) >= J.GetHP(ally) then
        return FindRescueEnemy(ally), ally
    end
end

-- ==============================
-- Lifecycle
-- ==============================
function OnStart() end

local function CancelFocusOrder()
    if issuedFocusTarget == nil then return end
    if bot:GetTarget() == issuedFocusTarget then
        bot:SetTarget(nil)
        if not J.CanNotUseAction(bot) then bot:Action_ClearActions(true) end
    end
    if bot.ohaFightFocus == issuedFocusTarget then
        bot.ohaFightFocus, bot.ohaFightFocusUntil = nil, nil
    end
    issuedFocusTarget = nil
end

function OnEnd()
    CancelRescueOrder()
    CancelFocusOrder()
    rescueAlly, rescueEnemy = nil, nil
    towerTime = 0
    towerCreepMode = false
    PickedItem = nil
end

-- ==============================
-- Think
-- ==============================
function Think()
    if J.CanNotUseAction(bot) then return end
    if J.ShouldRetreatFromEnemyReinforcements(bot) then
        CancelRescueOrder()
        CancelFocusOrder()
        return
    end
	-- diabled think less to avoid failing to last hit
    -- if J.Utils.IsBotThinkingMeaningfulAction(bot, Customize.ThinkLess, "team_roam") then return end

    if focusEnemy ~= nil then
        local location = bot:GetLocation()
        local liveEnemies, liveAllies = J.GetEnemiesNearLoc(location, 1600), J.GetAlliesNearLoc(location, 1600)
        if (not IsSupport or CanSupportCommitToTarget(focusEnemy))
            and J.GetSupportedFightTarget(bot, liveEnemies, liveAllies) == focusEnemy then
            if J.TryHoldFightApproach(bot, focusEnemy) then
                CancelFocusOrder()
                return
            end
            if bot.ohaFightFocus ~= focusEnemy then
                bot.ohaFightFocus, bot.ohaFightFocusUntil = focusEnemy, DotaTime() + 1.25
            end
            bot:SetTarget(focusEnemy)
            if bot:GetAttackTarget() ~= focusEnemy
                and not J.TryTeamfightSpread(bot, focusEnemy, liveEnemies, liveAllies) then
                -- Keep a continuous local attack, but never issue an
                -- indefinite chase when still outside attack reach.
                local contact = J.IsInRange(bot, focusEnemy, bot:GetAttackRange() + 75)
                bot:Action_AttackUnit(focusEnemy, not contact)
            end
            issuedFocusTarget = focusEnemy
        else
            CancelFocusOrder()
        end
        return
    end
    CancelFocusOrder()

    if rescueEnemy ~= nil then
        if FindRescueEnemy(rescueAlly, rescueEnemy) ~= nil then
            bot:SetTarget(rescueEnemy)
            bot:Action_AttackUnit(rescueEnemy, true)
            issuedRescueTarget = rescueEnemy
        else
            CancelRescueOrder()
            rescueEnemy, rescueAlly = nil, nil
        end
        return
    end
    CancelRescueOrder()

	if J.IsValid(hTargetCreep) and J.CanSupportTakeLaneLastHit(bot, hTargetCreep) then
		bot:Action_AttackUnit(hTargetCreep, true)
		return
	end

	-- Leash & validity guard to prevent pacing back and forth
	if IsSupport and J.IsValidHero(targetUnit) and not CanSupportCommitToTarget(targetUnit) then
		if bot:GetAttackTarget() == targetUnit then bot:Action_ClearActions(true) end
		if bot:GetTarget() == targetUnit then bot:SetTarget(nil) end
		targetUnit = nil
	end
	if targetUnit ~= nil then
		if (not J.Utils.IsValidUnit(targetUnit))
		or (not X.CanBeAttacked(targetUnit))
		or not J.CanSupportTakeLaneLastHit(bot, targetUnit)
		or (GetUnitToUnitDistance(bot, targetUnit) > 1800)  -- too far = drop it
		or (bot:GetActiveMode() == BOT_MODE_LANING and GetUnitToUnitDistance(bot, targetUnit) > bot:GetAttackRange() + 250)
		then
			targetUnit = nil
		end
	end

    if IsAvoidingAbilityZone then
        bot:Action_MoveToLocation(Utils.GetOffsetLocationTowardsTargetLocation(bot:GetLocation(), J.GetTeamFountain(), 600) + RandomVector(200))
        return
    end

    if ShouldAttackSpecialUnit then
        AttackSpecialUnit.Think()
    end

    if towerCreepMode then
        bot:Action_AttackUnit(towerCreep, false)
        return
    end

    if not ShouldAttackSpecialUnit and ItemOpsThink() then return end

    if (IsHeroCore or IsSupport) and J.Utils.IsValidUnit(targetUnit) then
        if J.IsValidHero(targetUnit) then
            if J.TryHoldFightApproach(bot, targetUnit) then return end
            local location = bot:GetLocation()
            if J.TryTeamfightSpread(bot, targetUnit, J.GetEnemiesNearLoc(location, 1600), J.GetAlliesNearLoc(location, 1600)) then return end
        end
        bot:Action_AttackUnit(targetUnit, false)
        return
    end
end

-- ==============================
-- Support / Carry target selection
-- (guarded by emergency retreat)
-- ==============================
function X.SupportFindTarget()
    if X.CanNotUseAttack(bot) or DotaTime() < 0 then return nil, 0 end

    local IsModeSuitHit = X.IsModeSuitToHitCreep(bot)
    local nAttackRange = math.min(bot:GetAttackRange() + 50, 1200)

    local nTarget = J.GetProperTarget(bot)
    local botMode = bot:GetActiveMode()
    local botLV   = bot:GetLevel()
    local botAD   = bot:GetAttackDamage()
    local botBAD  = X.GetAttackDamageToCreep(bot) - 1

    if X.CanBeAttacked(nTarget) and nTarget == targetUnit and GetUnitToUnitDistance(bot, nTarget) <= 1600
        and J.CanSupportTakeLaneLastHit(bot, nTarget) then
        if nTarget:GetTeam() == bot:GetTeam() then
            if nTarget:GetHealth() > X.GetLastHitHealth(bot, nTarget) then
                return nTarget, BOT_MODE_DESIRE_VERYHIGH * 1.08
            end
            return nTarget, BOT_MODE_DESIRE_VERYHIGH * 1.04
        end
        if nTarget:IsCourier()
        and GetUnitToUnitDistance(bot, nTarget) <= nAttackRange + 300
        and J.GetHP(bot) > 0.3 and not J.IsRetreating(bot) then
            return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 1.5
        end
        if nTarget:IsHero() and (bot:GetCurrentMovementSpeed() < 300 or botLV >= 25) then
            return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 1.2
        end
        if J.IsPushing(bot) and not nTarget:IsHero() then return nil, 0 end
        if not nTarget:IsHero() and GetUnitToUnitDistance(bot, nTarget) < nAttackRange + 50 then
            return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 0.98
        end
        if not nTarget:IsHero() and GetUnitToUnitDistance(bot, nTarget) > nAttackRange + 300 then
            return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 0.7
        end
        return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 0.96
    end

	-- Avoid derailing laning/pushing for courier hunts
	if not J.IsInLaningPhase() and not J.IsPushing(bot) then
		local enemyCourier = X.GetEnemyCourier(bot, nAttackRange + botLV * 2 + 20)  -- or +30 in carry version
		if enemyCourier ~= nil and not enemyCourier:IsAttackImmune() and not enemyCourier:IsInvulnerable()
		and J.GetHP(bot) > 0.3 and not J.IsRetreating(bot) then
			return enemyCourier, BOT_MODE_DESIRE_ABSOLUTE * 1.2
		end
	end

    if botMode == BOT_MODE_RETREAT and botLV > 9 and not X.CanBeInVisible(bot) and X.ShouldNotRetreat(bot) then
        nTarget = J.GetAttackableWeakestUnit(bot, nAttackRange + 50, true, true)
        if nTarget ~= nil then return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 1.09 end
    end

    local attackDamage = botBAD - 1
    if IsModeSuitHit and not X.HasHumanAlly(bot) and (J.GetHP(bot) > 0.5 or not bot:WasRecentlyDamagedByAnyHero(2.0)) then
        local nBonusRange = botLV > 20 and 200 or (botLV > 12 and 300 or 400)
        nTarget = X.GetNearbyLastHitCreep(false, true, attackDamage, nAttackRange + nBonusRange, bot)
        if nTarget ~= nil then return nTarget, BOT_MODE_DESIRE_ABSOLUTE end

        local nEnemyTowers = bot:GetNearbyTowers(nAttackRange + 150, true)
        if X.CanBeAttacked(nEnemyTowers[1]) and J.IsWithoutTarget(bot) and X.IsLastHitCreep(nEnemyTowers[1], botAD * 2) then
            return nEnemyTowers[1], BOT_MODE_DESIRE_ABSOLUTE
        end

        local nNeutrals = bot:GetNearbyNeutralCreeps(nAttackRange + 150)
        local nAllies = J.GetNearbyHeroes(bot, 1300, false, BOT_MODE_NONE)
        if J.IsWithoutTarget(bot) and botMode ~= BOT_MODE_FARM and #nNeutrals > 0 and #nAllies <= 1 then
            for i = 1, #nNeutrals do
                if X.CanBeAttacked(nNeutrals[i]) and not X.IsAllysTarget(nNeutrals[i])
                and not J.IsTormentor(nNeutrals[i]) and not J.IsRoshan(nNeutrals[i])
                and X.IsLastHitCreep(nNeutrals[i], attackDamage) then
                    return nNeutrals[i], BOT_MODE_DESIRE_ABSOLUTE
                end
            end
        end
    end

    local denyDamage = botAD + 3
    local nNearbyEnemyHeroes = J.GetNearbyHeroes(bot, 750, true, BOT_MODE_NONE)
    if IsModeSuitHit and bot:GetLevel() <= 8
    and bot:GetNetWorth() < 13998
    and (J.GetHP(bot) > 0.38 or not bot:WasRecentlyDamagedByAnyHero(3.0))
    and (nNearbyEnemyHeroes[1] == nil or nNearbyEnemyHeroes[1]:GetLevel() < 10)
    and bot:DistanceFromFountain() > 3800
    and J.GetDistanceFromEnemyFountain(bot) > 5000 then

        local nWillAttackCreeps = X.GetExceptRangeLastHitCreep(true, attackDamage * 1.1, 0, nAttackRange + 60, bot)
        if nWillAttackCreeps == nil or denyDamage > 130 or not X.IsOthersTarget(nWillAttackCreeps) or not X.IsMostAttackDamage(bot) then
            nTarget = X.GetNearbyLastHitCreep(false, false, denyDamage, nAttackRange + 300, bot)
            if nTarget ~= nil then return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 0.97 end
        end

        local nAllyTowers = bot:GetNearbyTowers(nAttackRange + 300, false)
        if J.IsWithoutTarget(bot) and #nAllyTowers > 0 then
            if X.CanBeAttacked(nAllyTowers[1]) and J.GetHP(nAllyTowers[1]) < 0.08 and X.IsLastHitCreep(nAllyTowers[1], denyDamage * 3) then
                return nAllyTowers[1], BOT_MODE_DESIRE_ABSOLUTE
            end
        end
    end

    return nil, 0
end

function X.CarryFindTarget()
    if X.CanNotUseAttack(bot) or DotaTime() < 0 then return nil, 0 end

    local IsModeSuitHit = X.IsModeSuitToHitCreep(bot)
    local nAttackRange = math.min(bot:GetAttackRange() + 50, 1170)
    if botName == "npc_dota_hero_templar_assassin" then nAttackRange = nAttackRange + 100 end

	local nTarget = J.GetProperTarget(bot);	
	local botHP   = bot:GetHealth()/bot:GetMaxHealth();
	local botMode = bot:GetActiveMode();
	local botLV   = bot:GetLevel();
    local botAD   = bot:GetAttackDamage() - 0.8
    local botBAD  = X.GetAttackDamageToCreep(bot) - 1.2

    if X.CanBeAttacked(nTarget) and nTarget == targetUnit and GetUnitToUnitDistance(bot, nTarget) <= 1600 then
        if nTarget:GetTeam() == bot:GetTeam() then
            if nTarget:GetHealth() > X.GetLastHitHealth(bot, nTarget) then
                return nTarget, BOT_MODE_DESIRE_VERYHIGH * 1.08
            end
            return nTarget, BOT_MODE_DESIRE_VERYHIGH * 1.04
        end
        if nTarget:IsCourier()
        and GetUnitToUnitDistance(bot, nTarget) <= nAttackRange + 300
        and J.GetHP(bot) > 0.3 and not J.IsRetreating(bot) then
            return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 1.5
        end
        if nTarget:IsHero() and (bot:GetCurrentMovementSpeed() < 300 or botLV >= 25) then
            if botName == "npc_dota_hero_antimage" then
                local bAbility = bot:GetAbilityByName("antimage_blink")
                if bAbility ~= nil and bAbility:IsFullyCastable() then return nil, BOT_MODE_DESIRE_NONE end
            end
            return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 1.2
        end
        if J.IsPushing(bot) and not nTarget:IsHero() then return nil, 0 end
        if not nTarget:IsHero() and GetUnitToUnitDistance(bot, nTarget) < nAttackRange + 50 then
            return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 0.98
        end
        if not nTarget:IsHero() and GetUnitToUnitDistance(bot, nTarget) > nAttackRange + 300 then
            return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 0.7
        end
        return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 0.96
    end

    if bot:HasModifier('modifier_phantom_lancer_phantom_edge_boost') then
        return nil, 0
    end

	-- Avoid derailing laning/pushing for courier hunts
	if not J.IsInLaningPhase() and not J.IsPushing(bot) then
		local enemyCourier = X.GetEnemyCourier(bot, nAttackRange + botLV * 2 + 20)  -- or +30 in carry version
		if enemyCourier ~= nil and not enemyCourier:IsAttackImmune() and not enemyCourier:IsInvulnerable()
		and J.GetHP(bot) > 0.3 and not J.IsRetreating(bot) then
			return enemyCourier, BOT_MODE_DESIRE_ABSOLUTE * 1.2
		end
	end

    if botMode == BOT_MODE_RETREAT
    and botName ~= "npc_dota_hero_bristleback"
    and botLV > 9
    and not X.CanBeInVisible(bot)
    and X.ShouldNotRetreat(bot) then
        nTarget = J.GetAttackableWeakestUnit(bot, nAttackRange + 50, true, true)
        if nTarget ~= nil then return nTarget, BOT_MODE_DESIRE_ABSOLUTE * 1.09 end
    end

    local cItem = J.IsItemAvailable("item_echo_sabre")
    if  cItem ~= nil and (cItem:IsFullyCastable() or cItem:GetCooldownTimeRemaining() < bot:GetAttackPoint() +0.8)
		and IsModeSuitHit
		and (botHP > 0.35 or not bot:WasRecentlyDamagedByAnyHero(1.0))
	then
		local echoDamage = botBAD *2;
		if (cItem:IsFullyCastable() or cItem:GetCooldownTimeRemaining() <  bot:GetAttackPoint())
		then
			nTarget = X.GetNearbyLastHitCreep(true, true, echoDamage, 350, bot);
			if nTarget ~= nil then return nTarget,BOT_MODE_DESIRE_ABSOLUTE *0.98; end
		end
		local nEnemyTowers = bot:GetNearbyTowers(1000,true);			
		if (cItem:IsFullyCastable() or cItem:GetCooldownTimeRemaining() <  bot:GetAttackPoint() +0.8)
			and #nEnemyTowers == 0
		then
			for i=400, 580, 60 do
				nTarget = X.GetExceptRangeLastHitCreep(true, echoDamage, 350, i, bot);
				if nTarget ~= nil 
				   then return nTarget,BOT_MODE_DESIRE_HIGH; end
			end
		end
	end

	local attackDamage = botBAD;
	if  IsModeSuitHit
		and not X.HasHumanAlly( bot )
		and ( botHP > 0.5 or not bot:WasRecentlyDamagedByAnyHero(2.0))
	then
		local nBonusRange = 430;
		if botLV > 12 then nBonusRange = 380; end
		if botLV > 20 then nBonusRange = 330; end

		nTarget = X.GetNearbyLastHitCreep(true, true, attackDamage, nAttackRange + nBonusRange, bot);
		if nTarget ~= nil
		then
			return nTarget,BOT_MODE_DESIRE_ABSOLUTE;
		end
	end

	local denyDamage = botAD + 3
	local nNearbyEnemyHeroes = bot:GetNearbyHeroes(650,true,BOT_MODE_NONE);
	if  IsModeSuitHit 
		and ( botHP > 0.38 or not bot:WasRecentlyDamagedByAnyHero(3.0))
		and (nNearbyEnemyHeroes[1] == nil or nNearbyEnemyHeroes[1]:GetLevel() < 12)
		and bot:DistanceFromFountain() > 3800
		and J.GetDistanceFromEnemyFountain(bot) > 5000
	then
		if bot:GetLevel() <= 8
		then
			local nWillAttackCreeps = X.GetExceptRangeLastHitCreep(true, attackDamage *1.5, 0, nAttackRange +60, bot);
			if nWillAttackCreeps == nil
				or denyDamage > 130
				or not X.IsOthersTarget(nWillAttackCreeps)
				or not X.IsMostAttackDamage(bot)
			then
				nTarget = X.GetNearbyLastHitCreep(false, false, denyDamage, nAttackRange +300, bot);
				if nTarget ~= nil then
					return nTarget,BOT_MODE_DESIRE_ABSOLUTE *0.97;
				end
			end
		end

		local nAllyTowers = bot:GetNearbyTowers(nAttackRange + 300, false);
		if J.IsWithoutTarget(bot)
		   and #nAllyTowers > 0
		then
			if X.CanBeAttacked(nAllyTowers[1])
			   and J.GetHP(nAllyTowers[1]) < 0.05
			   and X.IsLastHitCreep(nAllyTowers[1],denyDamage * 3)
			then
				return nAllyTowers[1],BOT_MODE_DESIRE_ABSOLUTE;
			end
		end
	end

	if  IsModeSuitHit
		and bot:GetLevel() <= 8
		and X.CanAttackTogether(bot)
		and (nNearbyEnemyHeroes[1] == nil or nNearbyEnemyHeroes[1]:GetLevel() < 12)
		and bot:DistanceFromFountain() > 3800
		and J.GetDistanceFromEnemyFountain(bot) > 5000
	 then
	     local nAllies = bot:GetNearbyHeroes(1200,false,BOT_MODE_NONE);
		 local nNum = X.GetCanTogetherCount(nAllies)
		 local centerAlly = X.GetMostDamageUnit(nAllies);
		 if centerAlly ~= nil and nNum >= 2
		 then
			local nTowerCreeps = centerAlly:GetNearbyLaneCreeps(1600,true);
			local nAllyTower = bot:GetNearbyTowers(1400,false);
			if(nAllyTower[1] ~= nil and nAllyTower[1]:GetAttackTarget() ~= nil)
			then
				local nTowerDamage = nAllyTower[1]:GetAttackDamage();
				local nTowerTarget = nAllyTower[1]:GetAttackTarget();
				for _,creep in pairs(nTowerCreeps)
				do
					if  nTowerTarget == creep
						and X.CanBeAttacked(creep)
						and creep:GetHealth() < X.GetLastHitHealth(nAllyTower[1],creep)
						and creep:GetHealth() > X.GetLastHitHealth(bot,creep)
					then
						local togetherDamage = 0;
						local togetherCount = 0;
						for _,ally in pairs(nAllies)
						do
							if X.CanAttackTogether(ally)
								and GetUnitToUnitDistance(ally,creep) <= ally:GetAttackRange() +50
							then
								togetherDamage = ally:GetAttackDamage() + togetherDamage;
								togetherCount =  togetherCount +1;
							end
						end
						if X.IsLastHitCreep(creep,togetherDamage)
						   and togetherCount >= 2
						   and GetUnitToUnitDistance(bot,creep) <= bot:GetAttackRange() +50
						then
							return creep,BOT_MODE_DESIRE_ABSOLUTE;
						end
					end
				end
		    end

			local nWillAttackCreeps = X.GetExceptRangeLastHitCreep(true, centerAlly:GetAttackDamage() *1.2, 0, 800, centerAlly);
			if nWillAttackCreeps == nil 
				or not X.IsOthersTarget(nWillAttackCreeps)
			then
				local nDenyCreeps = centerAlly:GetNearbyCreeps(1600,false);
				for _,creep in pairs(nDenyCreeps)
				do
					if X.CanBeAttacked(creep)
					and creep:GetHealth()/creep:GetMaxHealth() < 0.5
					and not X.IsLastHitCreep(creep,denyDamage)
					and not J.IsTormentor(creep)
					and not J.IsRoshan(creep)
					then
						local togetherDamage = 0;
						local togetherCount = 0;
						for _,ally in pairs(nAllies)
						do
							if X.CanAttackTogether(ally)
								and GetUnitToUnitDistance(ally,creep) <= ally:GetAttackRange() + 150 
							then
								togetherDamage = ally:GetAttackDamage() + togetherDamage;
								togetherCount = togetherCount +1;
							end
						end
						if X.IsLastHitCreep(creep,togetherDamage)
						   and togetherCount >= 2
						   and GetUnitToUnitDistance(bot,creep) <= bot:GetAttackRange() + 150
						then
							return creep,BOT_MODE_DESIRE_HIGH;
						end
					end
				end
			end
		end

	end

	local nNearbyEnemyHeroes = bot:GetNearbyHeroes(1600,true,BOT_MODE_NONE);
	local nEnemyLaneCreep = bot:GetNearbyLaneCreeps(1200, true);
	local nWillAttackCreeps = X.GetExceptRangeLastHitCreep(true, attackDamage *1.2, 0, nAttackRange + 120, bot);
	if  IsModeSuitHit
		and botLV >= 8
		and nNearbyEnemyHeroes[1] == nil
		and ( attackDamage > 118 or bot:GetSecondsPerAttack() < 0.7 )
		and ( nWillAttackCreeps == nil or not X.IsMostAttackDamage(bot) or not X.IsOthersTarget(nWillAttackCreeps))
	then
		local nEnemyTowers = bot:GetNearbyTowers(900,true);
		if botName ~= "npc_dota_hero_templar_assassin"
		then
			local nTwoHitCreeps = bot:GetNearbyLaneCreeps(nAttackRange +150, true);
			for _,creep in pairs(nTwoHitCreeps)
			do
				if X.CanBeAttacked(creep)
				   and not X.IsLastHitCreep(creep,attackDamage *1.2)
				   and not X.IsOthersTarget(creep)
				then
					local nAllyLaneCreep = bot:GetNearbyLaneCreeps(600, false);
					if X.IsLastHitCreep(creep,attackDamage *2)
					then
						return creep,BOT_MODE_DESIRE_ABSOLUTE;
					elseif X.IsLastHitCreep(creep,attackDamage *3 - 5) 
							and #nAllyLaneCreep == 0 and botLV >= 3						
						then
							return creep,BOT_MODE_DESIRE_ABSOLUTE *0.9;
					end
				end
			end
		end

		if  bot:DistanceFromFountain() > 3800 
			and not bePvNMode and bot:GetLevel() <= 6
			and J.GetDistanceFromEnemyFountain(bot) > 5000
			and nEnemyTowers[1] == nil
			and bot:GetNetWorth() < 19800
			and denyDamage > 110
		then
			local nTwoHitDenyCreeps = bot:GetNearbyCreeps(nAttackRange +120, false);
			for _,creep in pairs(nTwoHitDenyCreeps)
			do
				if X.CanBeAttacked(creep)
				and creep:GetHealth()/creep:GetMaxHealth() < 0.5
				and X.IsLastHitCreep(creep,denyDamage *2)
				and ( not X.IsLastHitCreep(creep,denyDamage *1.2) or #nEnemyLaneCreep == 0 )
				and not X.IsOthersTarget(creep)
				and not J.IsTormentor(creep)
				and not J.IsRoshan(creep)
				then
					return creep,BOT_MODE_DESIRE_ABSOLUTE;
				end
			end
		end

		local nEnemysCreeps = bot:GetNearbyCreeps(1600,true)
		local nAttackAlly = J.GetSpecialModeAllies(bot, 2500, BOT_MODE_ATTACK);
		local nTeamFightLocation = J.GetTeamFightLocation(bot);
		local nDefendLane,nDefendDesire = J.GetMostDefendLaneDesire();
		if  X.CanBeAttacked(nEnemysCreeps[1])
		and bot:GetHealth() > 300
		and not X.IsAllysTarget(nEnemysCreeps[1])
		and not J.IsRoshan(nEnemysCreeps[1])
		and (nEnemysCreeps[1]:GetTeam() == TEAM_NEUTRAL or attackDamage > 110)
		and ( not nEnemysCreeps[1]:IsAncientCreep() or attackDamage > 150 )
		and ( not J.IsKeyWordUnit("warlock", nEnemysCreeps[1]) or J.GetHP(bot) > 0.58 )		
		and ( nTeamFightLocation == nil or GetUnitToLocationDistance(bot,nTeamFightLocation) >= 3000 )
		and ( nDefendDesire <= 0.8 )
		and botMode ~= BOT_MODE_FARM
		and botMode ~= BOT_MODE_RUNE
		and botMode ~= BOT_MODE_LANING
		and botMode ~= BOT_MODE_ASSEMBLE
		and botMode ~= BOT_MODE_SECRET_SHOP
		and botMode ~= BOT_MODE_SIDE_SHOP
		and botMode ~= BOT_MODE_WARD
		and GetRoshanDesire() < BOT_MODE_DESIRE_HIGH	
		and not bot:WasRecentlyDamagedByAnyHero(2.0)
		and bot:GetAttackTarget() == nil
		and botLV >= 10
		and #nAttackAlly == 0
		and #nEnemyTowers == 0
		and not J.IsTormentor(nEnemysCreeps[1])
		and not J.IsRoshan(nEnemysCreeps[1])
		then
			return nEnemysCreeps[1],BOT_MODE_DESIRE_ABSOLUTE;
		end

		if bot:GetHealth() > 160 
		   and J.IsWithoutTarget(bot)
		then
			local nNeutrals = bot:GetNearbyNeutralCreeps(nAttackRange + 150);
			if #nNeutrals > 0
			   and botMode ~= BOT_MODE_FARM
			then
				for i = 1,#nNeutrals
				do
					if X.CanBeAttacked(nNeutrals[i])
						and not X.IsAllysTarget(nNeutrals[i])
						and not J.IsTormentor(nNeutrals[i])
						and not J.IsRoshan(nNeutrals[i])
						and X.IsLastHitCreep(nNeutrals[i],attackDamage * 2)
					then
						return nNeutrals[i],BOT_MODE_DESIRE_ABSOLUTE; 
					end
				end
			end
		end
	end
    return nil,0;
end

local bHumanAlly = nil
function X.HasHumanAlly( bot )
	if bHumanAlly == false then return false end
	if bHumanAlly == nil
	then
		local teamPlayerIDList = GetTeamPlayers( GetTeam() )
		for i = 1, #teamPlayerIDList
		do
			if not IsPlayerBot( teamPlayerIDList[i] )
			then
				bHumanAlly = true
				break
			end
		end	
		if bHumanAlly ~= true then bHumanAlly = false end
	end
	local allyHeroList = bot:GetNearbyHeroes( 900, false, BOT_MODE_NONE )
	for _, npcAlly in pairs( allyHeroList )
	do
		if not npcAlly:IsBot()
		then
			return true
		end
	end
	return false
end

function X.IsCreepTarget(nUnit)
	local bot = GetBot();
	local nCreeps = bot:GetNearbyCreeps(1200,true);
	for _,creep in pairs(nCreeps)
	do
		if  X.IsValid(creep)
		and creep:GetAttackTarget() == nUnit
		and not J.IsTormentor(creep)
		and not J.IsRoshan(creep)
		then
			return true;
		end
	end
	
	local nCreeps = bot:GetNearbyCreeps(1200,false);
	for _,creep in pairs(nCreeps)
	do
		if X.IsValid(creep)
		and creep:GetAttackTarget() == nUnit
		and not J.IsTormentor(creep)
		and not J.IsRoshan(creep)
		then
			return true;
		end
	end

	return false;
end

-- ==============================
-- Generic utils (many of yours kept)
-- ==============================
function X.IsValid(u) return u ~= nil and not u:IsNull() and u:IsAlive() and u:CanBeSeen() end

function X.GetAttackDamageToCreep( bot )
	if bot:GetItemSlotType(bot:FindItemSlot("item_quelling_blade")) == ITEM_SLOT_TYPE_MAIN
	then
		if bot:GetAttackRange() > 310 or bot:GetUnitName() == "npc_dota_hero_templar_assassin"
		then
			return bot:GetAttackDamage() + 4;
		else
			return bot:GetAttackDamage() + 8;
		end
	end
	if bot:FindItemSlot("item_bfury") >= 0
	then
		return bot:GetAttackDamage() + 15;
	end
	return bot:GetAttackDamage();
end

function X.CanNotUseAttack(b)
    return not b:IsAlive() or J.HasQueuedAction(b) or b:IsInvulnerable() or b:IsCastingAbility()
        or b:IsUsingAbility() or b:IsChanneling() or b:IsStunned() or b:IsDisarmed()
        or b:IsHexed() or b:IsRooted() or X.WillBreakInvisible(b)
end

function X.WillBreakInvisible(b)
    local invis = {
        ["npc_dota_hero_riki"] = true,
        ["npc_dota_hero_phantom_assassin"] = true,
        ["npc_dota_hero_templar_assassin"] = true,
        ["npc_dota_hero_bounty_hunter"] = true,
    }
    if b:IsInvisible() and not invis[b:GetUnitName()] then return true end
    return false
end

function X.CanBeAttacked(unit)
    return unit ~= nil and unit:IsAlive() and unit:CanBeSeen() and not unit:IsNull()
        and not unit:IsAttackImmune() and not unit:IsInvulnerable()
        and not unit:HasModifier("modifier_fountain_glyph")
        and (unit:GetTeam() == team or not unit:HasModifier("modifier_crystal_maiden_frostbite"))
        and (unit:GetTeam() ~= team or (unit:GetUnitName() ~= "npc_dota_wraith_king_skeleton_warrior"
            and unit:GetHealth()/unit:GetMaxHealth() < 0.5))
end

-- Courier scan (unchanged)
local courierFindCD, lastFindTime = 0.1, -90
function X.GetEnemyCourier(b, nRadius)
    if GetGameMode() == 23 then return nil end
    if J.GetDistanceFromEnemyFountain(b) < 1400 then return nil end
    if DotaTime() > lastFindTime + courierFindCD then
        lastFindTime = DotaTime()
        for _,u in pairs(GetUnitList(UNIT_LIST_ENEMIES)) do
            if u and u:IsCourier() and u:IsAlive()
            and GetUnitToUnitDistance(b, u) <= nRadius
            and not u:IsInvulnerable() and not u:IsAttackImmune()
            and not u:HasModifier('modifier_fountain_aura') then
                return u
            end
        end
    end
    return nil
end

function X.WeakestUnitExceptRangeCanBeAttacked(bHero, bEnemy, nRange, nRadius, bot)
	local units = {};
	local weakest = nil;
	local weakestHP = 4999;
	local realHP = 0;
	if nRadius > 1600 then nRadius = 1600 end;
	
	if bHero then
		units = bot:GetNearbyHeroes(nRadius, bEnemy, BOT_MODE_NONE);
	else	
		units = bot:GetNearbyLaneCreeps(nRadius, bEnemy);
	end
	
	for _,u in pairs(units) do
		if  X.IsValid(u)
		and GetUnitToUnitDistance(bot,u) > nRange 
		and X.CanBeAttacked(u)
		and not u:HasModifier("modifier_crystal_maiden_frostbite")
		then
			realHP = u:GetHealth() / 1;
			
			if realHP < weakestHP
			then
				weakest = u;
				weakestHP = realHP;
			end			
		end
	end
	return weakest;
end

function X.GetNearbyLastHitCreep(ignorAlly, bEnemy, nDamage, nRadius, bot)

	if nRadius > 1600 then nRadius = 1600 end;
	local nNearbyCreeps = bot:GetNearbyLaneCreeps(nRadius, bEnemy);
	local nDamageType = DAMAGE_TYPE_PHYSICAL;
	local botName = bot:GetUnitName();


	if  bEnemy 
		and botName == "npc_dota_hero_templar_assassin" --V bug
		and bot:HasModifier("modifier_templar_assassin_refraction_damage")
	then
		local cAbility = bot:GetAbilityByName( "templar_assassin_refraction" );
		local bonusDamage = cAbility:GetSpecialValueInt( 'bonus_damage' );
		nDamage = nDamage + bonusDamage;
	end

	if  bEnemy
		and botName == "npc_dota_hero_kunkka"
	then
		local cAbility = bot:GetAbilityByName( "kunkka_tidebringer" );
		if cAbility:IsFullyCastable() 
		then
			local bonusDamage = cAbility:GetSpecialValueInt( 'damage_bonus' );
			nDamage = nDamage + bonusDamage;
		end
	end


	for _,nCreep in pairs(nNearbyCreeps)
	do
		if X.CanBeAttacked(nCreep) and nCreep:GetHealth() < ( nDamage + 256 )
		and ( ignorAlly or not X.IsAllysTarget(nCreep) )
		then
		
			local nAttackProDelayTime = J.GetAttackProDelayTime(bot,nCreep) ;
			
			if bEnemy and botName == "npc_dota_hero_antimage"
				and J.IsKeyWordUnit("ranged",nCreep)
			then
				local cAbility = bot:GetAbilityByName( "antimage_mana_break" );
				if cAbility:IsTrained()
				then
					local bonusDamage = 0.5 * cAbility:GetSpecialValueInt( 'mana_per_hit' );
					nDamage = nDamage + bonusDamage;
				end
			end
		
			
			local nRealDamage = nDamage * 1
				
			if J.WillKillTarget(nCreep,nRealDamage,nDamageType,nAttackProDelayTime)
				and (not bEnemy or J.CanSupportTakeLaneLastHit(bot, nCreep))
			then
				return nCreep;
			end
		
		end
	end
	return nil;
end

function X.GetExceptRangeLastHitCreep(bEnemy,nDamage,nRange,nRadius,bot)
	
	local nCreep = X.WeakestUnitExceptRangeCanBeAttacked(false, bEnemy, nRange, nRadius, bot);
	local nDamageType = DAMAGE_TYPE_PHYSICAL;

	if X.IsValid(nCreep)
	then
		if not bEnemy and nCreep:GetHealth()/nCreep:GetMaxHealth() >= 0.5
		then return nil end	
	
		nDamage = nDamage * 1 ;

		local nAttackProDelayTime = J.GetAttackProDelayTime(bot,nCreep);
		
		if J.WillKillTarget(nCreep,nDamage,nDamageType,nAttackProDelayTime)
		then		
			return nCreep;
		end

	end

	return nil;
end

function X.IsLastHitCreep(nCreep,nDamage)
	
	if X.CanBeAttacked(nCreep)
	then
		
		nDamage = nDamage * 1;
		
		if nCreep:GetActualIncomingDamage(nDamage, DAMAGE_TYPE_PHYSICAL) + J.GetCreepAttackProjectileWillRealDamage(nCreep,0.66) > nCreep:GetHealth() +1
		then 
		    return true;
		end
		
	end
	 
	return false;
	
end


function X.GetLastHitHealth(bot,nCreep)
	
	if X.CanBeAttacked(nCreep)
	then
	   
       local nDamage = X.GetAttackDamageToCreep(bot) * 1
		
	   return nCreep:GetActualIncomingDamage(nDamage, DAMAGE_TYPE_PHYSICAL);
	end
	 
	return bot:GetAttackDamage();

end


function X.IsAllysTarget(unit)
	local bot = GetBot();
	local allies = bot:GetNearbyHeroes(1000,false,BOT_MODE_NONE);
	if #allies < 2 then return false end;
	
	for _,ally in pairs(allies) 
	do
		if  ally ~= bot
			and not ally:IsIllusion()
			and ( ally:GetTarget() == unit or ally:GetAttackTarget() == unit )
		then
			return true;
		end
	end
	return false;
end


function X.IsEnemysTarget(unit)
	local bot = GetBot();
	local enemys = bot:GetNearbyHeroes(1600,true,BOT_MODE_NONE);
	for _,enemy in pairs(enemys) 
	do
		if  X.IsValid(enemy) and J.GetProperTarget(enemy) == unit 
		then
			return true;
		end
	end
	return false;
end


function X.CanAttackTogether(bot)
   
   local allies = bot:GetNearbyHeroes(1200,false,BOT_MODE_NONE);
   local nNearbyEnemyHeroes = bot:GetNearbyHeroes(600,true,BOT_MODE_NONE);
   
   return bot ~= nil and bot:IsAlive()
		  and not bot:IsIllusion()
		  and J.GetProperTarget(bot) == nil
	      and #allies >= 2
		  and (nNearbyEnemyHeroes[1] == nil or nNearbyEnemyHeroes[1]:GetLevel() < 10)
   
end


function X.GetMostDamageUnit(nUnits)
	
	local mostAttackDamage = 0;
	local mostUnit = nil;
	for _,unit in pairs(nUnits)
	do
		if unit ~= nil and unit:IsAlive()
			and J.GetProperTarget(unit) == nil
			and unit:GetAttackDamage() > mostAttackDamage
		then
			mostAttackDamage = unit:GetAttackDamage();
			mostUnit = unit;
		end
	end
	
	return mostUnit;

end


function X.GetCanTogetherCount(nAllies)
	
	local nNum = 0;
	for _,ally in pairs(nAllies)
	do
		if X.IsValid(ally) and X.CanAttackTogether(ally)
		then
			nNum = nNum +1;
		end
	end
	
	return nNum;

end

function X.IsOthersTarget(nUnit)
	local bot = GetBot();

	if X.IsValid(nUnit)
	then
		if X.IsAllysTarget(nUnit)
		then
			return true;
		end
		
		if X.IsEnemysTarget(nUnit)
		then
			return true;
		end
		
		if X.IsCreepTarget(nUnit)
		then
			return true
		end
		
		local nTowers = bot:GetNearbyTowers(1600,true);
		for _,tower in pairs(nTowers)
		do
			if J.IsValidBuilding(tower)
			   and tower:GetAttackTarget() == nUnit
			then
				return true;
			end
		end
		
		local nTowers = bot:GetNearbyTowers(1600,false);
		for _,tower in pairs(nTowers)
		do
			if J.IsValidBuilding(tower)
			   and tower:GetAttackTarget() == nUnit
			then
				return true;
			end
		end
	end
	
	return false;

end

function X.CanBeInVisible(bot)

	local nEnemyTowers = bot:GetNearbyTowers(800,true);
	if #nEnemyTowers > 0 
	   or bot:HasModifier("modifier_item_dustofappearance")
	then 
		return false;
	end

	if bot:IsInvisible()
	then
		return true;
	end

	local glimer = J.IsItemAvailable("item_glimmer_cape");
	if glimer ~= nil and glimer:IsFullyCastable() 
	then
		return true;			
	end
	
	local invissword = J.IsItemAvailable("item_invis_sword");
	if invissword ~= nil and invissword:IsFullyCastable() 
	then
		return true;			
	end
	
	local silveredge = J.IsItemAvailable("item_silver_edge");
	if silveredge ~= nil and silveredge:IsFullyCastable() 
	then
		return true;			
	end

	return false;
end

-- ==============================
-- Help when a nearby core is targeted
-- ==============================
function X.ConsiderHelpWhenCoreIsTargeted()
    local core = J.GetClosestCore(bot, 1800)
    if J.IsValidHero(core) and J.GetHP(core) > 0.2 then
        return FindRescueEnemy(core), core
    end
end

function X.IsModeSuitToHitCreep(b)
    local botMode = b:GetActiveMode()
    local nEnemyHeroes = J.GetEnemyList(b, 750)
    if #nEnemyHeroes >= 3 or (nEnemyHeroes[1] ~= nil and nEnemyHeroes[1]:GetLevel() >= 8) then
        return false
    end
    if b:HasModifier("modifier_axe_battle_hunger") then
        if #b:GetNearbyLaneCreeps(b:GetAttackRange() + 180, true) > 0 then return true end
    end
    if b:GetLevel() <= 3 and botMode ~= BOT_MODE_EVASIVE_MANEUVERS
    and (botMode ~= BOT_MODE_RETREAT or (botMode == BOT_MODE_RETREAT and b:GetActiveModeDesire() < 0.78)) then
        return true
    end
    return botMode ~= BOT_MODE_ATTACK
        and botMode ~= BOT_MODE_EVASIVE_MANEUVERS
        and (botMode ~= BOT_MODE_RETREAT or (botMode == BOT_MODE_RETREAT and b:GetActiveModeDesire() < 0.68))
end

function X.IsMostAttackDamage(b)
    for _,ally in pairs(J.GetNearbyHeroes(b, 800, false, BOT_MODE_NONE)) do
        if ally ~= b and not X.CanNotUseAttack(ally) and ally:GetAttackDamage() > b:GetAttackDamage() then
            return false
        end
    end
    return true
end

-- ==============================
-- Retreat logic hardening
-- ==============================
function X.ShouldNotRetreat(b)
    do
        local a = J.GetAlliesNearLoc(b:GetLocation(), 1000)
        local e = J.GetEnemiesNearLoc(b:GetLocation(), 1000)
        local losing = (#a < #e) or not J.WeAreStronger(b, 1000)
        if (b:WasRecentlyDamagedByAnyHero(1.2) or b:WasRecentlyDamagedByTower(1.2)) and losing then
            return false
        end
    end

    if b:HasModifier("modifier_item_satanic_unholy")
       or b:HasModifier("modifier_abaddon_borrowed_time")
       or (b:GetCurrentMovementSpeed() < 240 and not b:HasModifier("modifier_arc_warden_spark_wraith_purge")) then
        return true
    end

    local nAttackAlly = J.GetNearbyHeroes(b, 1000, false, BOT_MODE_ATTACK)
    if (b:HasModifier("modifier_item_mask_of_madness_berserk") or J.CanIgnoreLowHp(b))
    and (#nAttackAlly >= 1 or J.GetHP(b) > 0.6)
    and (b:WasRecentlyDamagedByAnyHero(1) or b:WasRecentlyDamagedByTower(1)) then
        return true
    end

    local nAllies = J.GetAllyList(b, 800)
    if #nAllies <= 1 then return false end

    if (botName == "npc_dota_hero_medusa" or b:FindItemSlot("item_abyssal_blade") >= 0)
       or b:HasModifier('modifier_muerta_pierce_the_veil_buff')
    and (b:WasRecentlyDamagedByAnyHero(1) or J.GetHP(b) > 0.2 or b:WasRecentlyDamagedByTower(1))
    and #nAllies >= 3 and #nAttackAlly >= 1 then
        return true
    end

    if botName == "npc_dota_hero_skeleton_king" and b:GetLevel() >= 6 and #nAttackAlly >= 1 then
        local abilityR = b:GetAbilityByName("skeleton_king_reincarnation")
        if abilityR and abilityR:GetCooldownTimeRemaining() <= 1.0 and b:GetMana() >= 160 then
            return true
        end
    end

    for _,ally in pairs(nAllies) do
        if J.IsValid(ally) then
            if J.GetHP(b) >= 0.3 and (
                (J.GetHP(ally) > 0.88 and ally:GetLevel() >= 12 and ally:GetActiveMode() ~= BOT_MODE_RETREAT)
                or ally:HasModifier("modifier_black_king_bar_immune") or ally:IsMagicImmune()
                or (ally:HasModifier("modifier_item_mask_of_madness_berserk") and ally:GetAttackTarget() ~= nil)
                or ally:HasModifier("modifier_abaddon_borrowed_time")
                or ally:HasModifier("modifier_item_satanic_unholy")
                or J.CanIgnoreLowHp(ally)
            ) then
                return true
            end
        end
    end

    return false
end

-- ==============================
-- Tower creep targeting (guarded)
-- ==============================
local fLastReturnTime = 0
function X.ShouldAttackTowerCreep(b)
    if X.CanNotUseAttack(b) then return 0 end

    if b:GetLevel() > 2
    and b:GetAnimActivity() == 1502
    and b:GetTarget() == nil and b:GetAttackTarget() == nil
    and X.IsModeSuitToHitCreep(b)
    and J.GetHP(b) > 0.38
    and not b:WasRecentlyDamagedByAnyHero(2.0) then
        local nRange = math.min(b:GetAttackRange() + 150, 1250)
        local allyCreeps = b:GetNearbyLaneCreeps(800, false)
        local enemyCreeps = b:GetNearbyLaneCreeps(800, true)
        local attackTime = b:GetSecondsPerAttack() * 0.75
        local attackTarget = nil
        local nEnemyTowers = b:GetNearbyTowers(nRange, true)
        local bMS = b:GetCurrentMovementSpeed()

        if X.CanBeAttacked(nEnemyTowers[1])
        and (nEnemyTowers[1]:GetAttackTarget() ~= b or J.GetHP(b) > 0.8)
        and #allyCreeps > 0
        and fLastReturnTime < DotaTime() - 1.0 then
            attackTarget = nEnemyTowers[1]
            local nDist = GetUnitToUnitDistance(b, attackTarget) - b:GetAttackRange()
            if nDist > 0 then attackTime = attackTime + nDist / bMS end
            fLastReturnTime = DotaTime()
            return attackTime, attackTarget
        end

        local nEnemyBarracks = b:GetNearbyBarracks(nRange, true)
        if X.CanBeAttacked(nEnemyBarracks[1]) and #allyCreeps > 0 then
            attackTarget = nEnemyBarracks[1]
            local nDist = GetUnitToUnitDistance(b, attackTarget) - b:GetAttackRange()
            if nDist > 0 then attackTime = attackTime + nDist / bMS end
            return attackTime, attackTarget
        end

        local nEnemyAncient = GetAncient(GetOpposingTeam())
        if J.IsInRange(b, nEnemyAncient, nRange + 80)
        and X.CanBeAttacked(nEnemyAncient) and #enemyCreeps == 0 then
            attackTarget = nEnemyAncient
            local nDist = GetUnitToUnitDistance(b, attackTarget) - b:GetAttackRange()
            if nDist > 0 then attackTime = attackTime + nDist / bMS end
            return attackTime, attackTarget
        end
    end

    local nTowers = b:GetNearbyTowers(1600, false)
    if nTowers[1] == nil or not X.IsMostAttackDamage(b) or b:GetLevel() > 12 then
        return 0, nil
    end

    if nTowers[1] ~= nil and nTowers[1]:GetAttackTarget() ~= nil then
        local towerTarget = nTowers[1]:GetAttackTarget()
        local hAllyCreepList = b:GetNearbyLaneCreeps(500, false)
        if not towerTarget:IsHero() and X.CanBeAttacked(towerTarget)
        and #hAllyCreepList == 0 and not X.IsCreepTarget(towerTarget)
        and GetUnitToUnitDistance(b, towerTarget) < b:GetAttackRange() + 100 then
            local towerRealDamage = X.GetLastHitHealth(nTowers[1], towerTarget)
            local botRealDamage   = X.GetLastHitHealth(b, towerTarget)
            local attackTime      = b:GetSecondsPerAttack() - 0.3
            local towerTargetHealth = towerTarget:GetHealth()
            if towerRealDamage > botRealDamage
            and towerTargetHealth > towerRealDamage
            and towerTargetHealth % towerRealDamage > botRealDamage then
                return attackTime, towerTarget
            end
        end
    end

    return 0, nil
end

-- ==============================
-- Item pickup and inventory management
-- ==============================
-- Recheck at selection and execution: another mode may deliberately discard
-- the selected item between these callbacks.
local function CanConsiderDroppedItem(drop)
    if drop == nil or drop.item == nil or drop.item:IsNull()
    or drop.location == nil or not IsLocationVisible(drop.location)
    then
        return false
    end
    local attempt = pickupAttempts[drop.item]
    if attempt ~= nil and attempt.count >= 3 then return false end
    return bot.ohaDiscardedItems == nil or not bot.ohaDiscardedItems[drop.item]
end

local battleHorn = 'item_horn_of_battle_greater'

local function CanPickUpBattleHorn(drop)
    if (drop.owner ~= nil and drop.owner ~= bot)
    or bot:FindItemSlot(battleHorn) >= 0
    or J.Item.GetEmptyInventoryAmount(bot) == 0
    or J.IsRetreating(bot)
    or #J.GetEnemiesNearLoc(drop.location, 900) > 0
    then
        return false
    end

    local distance = GetUnitToLocationDistance(bot, drop.location)
    if distance > 1200 then return false end
    for _, ally in ipairs(J.GetAlliesNearLoc(drop.location, 1200)) do
        if ally ~= bot and not J.IsRetreating(ally)
        and J.Item.GetEmptyInventoryAmount(ally) > 0 and ally:FindItemSlot(battleHorn) < 0 then
            local allyDistance = GetUnitToLocationDistance(ally, drop.location)
            if allyDistance < distance
            or (allyDistance == distance and ally:GetPlayerID() < bot:GetPlayerID()) then
                return false
            end
        end
    end
    return true
end

function ItemOpsDesire()
    if DotaTime() >= ConsiderDroppedTime + 2.0 then
        ConsiderDroppedTime = DotaTime()
        PickedItem = nil
        for _, drop in pairs(GetDroppedItemList()) do
            if CanConsiderDroppedItem(drop) and GetUnitToLocationDistance(bot, drop.location) < 2000 then
                local name = drop.item:GetName()
                local shouldPick = false
                if name == battleHorn then
                    shouldPick = CanPickUpBattleHorn(drop)
                elseif not Utils.HasValue(Item['tEarlyConsumableItem'], name) then
                    if (name == 'item_aegis' or name == 'item_cheese')
                    and J.GetPosition(bot) <= 3 and not J.HasItem(bot, 'item_aegis') then
                        shouldPick = true
                    elseif name == 'item_refresher_shard' then
                        shouldPick = J.GetMostUltimateCDUnit() == bot
                    else
                        shouldPick = drop.owner == bot and GetItemCost(name) > minPickItemCost
                            and not string.find(name, 'token')
                    end
                end
                if shouldPick and (PickedItem == nil or name == battleHorn) then
                    PickedItem = drop
                    if name == battleHorn then break end
                end
            end
        end
        if PickedItem ~= nil and PickedItem.item:GetName() == 'item_aegis'
        and J.Item.GetEmptyNonBackpackInventoryAmount(bot) == 0 then
            local lessValItem = J.Item.GetMainInvLessValItemSlot(bot)
            local emptySlot = J.Item.GetEmptyBackpackSlot(bot)
            if lessValItem ~= -1 and emptySlot ~= -1 then
                bot:ActionImmediate_SwapItems(emptySlot, lessValItem)
            end
        end
    end

    if CanConsiderDroppedItem(PickedItem) then
        if PickedItem.item:GetName() == battleHorn then
            if CanPickUpBattleHorn(PickedItem) then return BOT_MODE_DESIRE_MODERATE, true end
        else
            return RemapValClamped(GetUnitToLocationDistance(bot, PickedItem.location),
                5000, 0, BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_VERYHIGH)
        end
    end

    TrySellOrDropItem()
    SwapSmokeSupport()
    TrySwapInvItemForCheese()
    TrySwapInvItemForRefresherShard()
    TrySwapInvItemForClarity()
    TrySwapInvItemForFlask()
    TrySwapInvItemForSmoke()
    TrySwapInvItemForMoonshard()
end

function ItemOpsThink()
    if not CanConsiderDroppedItem(PickedItem) or J.Item.GetEmptyInventoryAmount(bot) == 0 then return false end
    local name = PickedItem.item:GetName()
    if name == battleHorn and not CanPickUpBattleHorn(PickedItem) then return false end
    if (name == 'item_aegis' or name == 'item_cheese')
    and (J.GetPosition(bot) > 3 or J.HasItem(bot, 'item_aegis')) then return false end

    local distance = GetUnitToLocationDistance(bot, PickedItem.location)
    if distance <= 100 then
        local item = PickedItem.item
        local attempt = pickupAttempts[item]
        local now = DotaTime()
        if attempt ~= nil and now < attempt.nextTime then return true end
        pickupAttempts[item] = {count = (attempt and attempt.count or 0) + 1, nextTime = now + 0.5}
        bot:Action_PickUpItem(item)
        return true
    end
    if distance < 2000 then
        bot:Action_MoveToLocation(PickedItem.location)
        return true
    end
    return false
end

-- Swap smoke after killing Roshan
function SwapSmokeSupport()
	if J.IsDoingRoshan(bot)
	then
		local botTarget = bot:GetAttackTarget()

		if J.IsRoshan(botTarget)
		and J.IsAttacking(bot)
		then
			local smokeSlot = bot:FindItemSlot('item_smoke_of_deceit')

			if bot:GetItemSlotType(smokeSlot) == ITEM_SLOT_TYPE_BACKPACK
			then
				local leastCostItem = J.FindLeastExpensiveItemSlot()
	
				if leastCostItem ~= -1
				then
					bot:ActionImmediate_SwapItems(smokeSlot, leastCostItem)
				end
			end
		end
	end
end
-- Swap Items for healing
function TrySwapInvItemForClarity()
	if 	DotaTime() >= SwappedClarityTime + 6.3
	and bot:GetActiveMode() ~= BOT_MODE_WARD
	then
		local cSlot = bot:FindItemSlot('item_clarity')
		if cSlot and bot:GetItemSlotType(cSlot) == ITEM_SLOT_TYPE_BACKPACK
		then
			local lessValItem = J.Item.GetMainInvLessValItemSlot(bot)

			if lessValItem ~= -1
			then
				bot:ActionImmediate_SwapItems(cSlot, lessValItem)
			end
		end

		SwappedClarityTime = DotaTime()
	end
end
function TrySwapInvItemForFlask()
	if 	DotaTime() >= SwappedFlaskTime + 6.2
	and bot:GetActiveMode() ~= BOT_MODE_WARD
	then
		local cSlot = bot:FindItemSlot('item_flask')
		if cSlot and bot:GetItemSlotType(cSlot) == ITEM_SLOT_TYPE_BACKPACK
		then
			local lessValItem = J.Item.GetMainInvLessValItemSlot(bot)

			if lessValItem ~= -1
			then
				bot:ActionImmediate_SwapItems(cSlot, lessValItem)
			end
		end

		SwappedFlaskTime = DotaTime()
	end
end

function TrySwapInvItemForSmoke()
	if 	DotaTime() >= SwappedSmokeTime + 15
	then
		local cSlot = bot:FindItemSlot('item_smoke_of_deceit')
		if cSlot and bot:GetItemSlotType(cSlot) == ITEM_SLOT_TYPE_BACKPACK
		then
			local lessValItem = J.Item.GetMainInvLessValItemSlot(bot)

			if lessValItem ~= -1
			then
				bot:ActionImmediate_SwapItems(cSlot, lessValItem)
			end
		end

		SwappedSmokeTime = DotaTime()
	end
end

-- Swap Items for moonshard
function TrySwapInvItemForMoonshard()
	if DotaTime() >= SwappedMoonshardTime + 10.0
	and bot:GetActiveMode() ~= BOT_MODE_WARD
	then
		local cSlot = bot:FindItemSlot('item_moon_shard')
		if cSlot and bot:GetItemSlotType(cSlot) == ITEM_SLOT_TYPE_BACKPACK
		then
			local lessValItem = J.Item.GetMainInvLessValItemSlot(bot)

			if lessValItem ~= -1
			then
				bot:ActionImmediate_SwapItems(cSlot, lessValItem)
			end
		end
		SwappedMoonshardTime = DotaTime()
	end
end

-- Swap Items for Cheese
function TrySwapInvItemForCheese()
	if 	DotaTime() >= SwappedCheeseTime + 2.3
	and bot:GetActiveMode() ~= BOT_MODE_WARD
	then
		local cSlot = bot:FindItemSlot('item_cheese')

		if bot:GetItemSlotType(cSlot) == ITEM_SLOT_TYPE_BACKPACK
		then
			local lessValItem = J.Item.GetMainInvLessValItemSlot(bot)

			if lessValItem ~= -1
			then
				bot:ActionImmediate_SwapItems(cSlot, lessValItem)
			end
		end

		SwappedCheeseTime = DotaTime()
	end
end

-- Swap Items for Refresher Shard
function TrySwapInvItemForRefresherShard()
	if 	DotaTime() >= SwappedRefresherShardTime + 2.2
	and bot:GetActiveMode() ~= BOT_MODE_WARD
	then
		local rSlot = bot:FindItemSlot('item_refresher_shard')

		if bot:GetItemSlotType(rSlot) == ITEM_SLOT_TYPE_BACKPACK
		then
			local lessValItem = J.Item.GetMainInvLessValItemSlot(bot)

			if lessValItem ~= -1
			then
				bot:ActionImmediate_SwapItems(rSlot, lessValItem)
			end
		end

		SwappedRefresherShardTime = DotaTime()
	end
end

function TrySellOrDropItem()
	if DotaTime() > 0 and DotaTime() - lastCheckBotToDropTime > 3
	then
		lastCheckBotToDropTime = DotaTime()

		-- Issue #155: a deliberately dropped backpack item must not be picked
		-- straight back up by item_purchase_generic's generic owned-item loop.
		if bot:GetLevel() >= 6 and bot:GetNetWorth() >= 14000 and Utils.CountBackpackEmptySpace(bot) <= 1 then
			for i = 1, #Item['tEarlyConsumableItem']
			do
				local itemName = Item['tEarlyConsumableItem'][i]
				local itemSlot = bot:FindItemSlot(itemName)
				if itemSlot >= 6 and itemSlot <= 8
				then
					local item = bot:GetItemInSlot(itemSlot)
					if item ~= nil then
						local distance = bot:DistanceFromFountain()
						if distance <= 300 then
							bot:ActionImmediate_SellItem(item)
							return
						elseif distance >= 3000 then
							bot.ohaDiscardedItems = bot.ohaDiscardedItems or {}
							bot.ohaDiscardedItems[item] = true
							bot:Action_DropItem(item, bot:GetLocation())
							return -- one item operation per tick; avoid overwriting actions
						end
					end
				end
			end
		end
	end
end

function J.FindLeastExpensiveItemSlot()
	local minCost = 100000
	local idx = -1

	for i = 0, 5
	do
		if bot:GetItemInSlot(i) ~= nil
		and bot:GetItemInSlot(i):GetName() ~= 'item_aegis'
		and bot:GetItemInSlot(i):GetName() ~= 'item_rapier'
		then
			local item = bot:GetItemInSlot(i):GetName()

			if GetItemCost(item) < minCost
			and not (item == 'item_ward_observer' or item == 'item_ward_sentry')
			then
				minCost = GetItemCost(item)
				idx = i
			end
		end
	end

	return idx
end

X.GetDesire = GetDesire
X.Think = Think

return X
