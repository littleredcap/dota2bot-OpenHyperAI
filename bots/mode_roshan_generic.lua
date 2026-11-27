local bot = GetBot()
if bot == nil then return end
local botName = bot:GetUnitName()
if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

local J = require( GetScriptDirectory()..'/FunLib/jmz_func' )

local sinceRoshAliveTime = 0
local roshTimeFlag = false

local Roshan

function GetDesire()
	local res = GetDesireHelper()
	if res > 0.6 then J.ModeAnnounce(bot, 'say_roshan', 30) end
	return res
end
function GetDesireHelper()
	if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return BOT_MODE_DESIRE_NONE end
    if not J.IsRoshan(Roshan) then
        Roshan = nil
        local nCreeps = bot:GetNearbyNeutralCreeps(700)
        for _, creepOrRoshan in pairs(nCreeps)
        do
            if J.IsRoshan(creepOrRoshan)
            then
                Roshan = creepOrRoshan
                break
            end
        end
    end

	-- 如果在打高地 就别撤退去干别的
	if J.Utils.IsTeamPushingSecondTierOrHighGround(bot) then
		return BOT_MODE_DESIRE_NONE
	end

	if J.GetEnemiesAroundAncient(bot, 3200) > 0 or J.GetHP(GetAncient(bot:GetTeam())) < 0.8 then
		return BOT_MODE_DESIRE_NONE
	end

    local pit = Roshan and Roshan:GetLocation() or J.GetCurrentRoshanLocation()
    if (bot.ohaOuterTowerHoldUntil or 0) > DotaTime() or GetUnitToLocationDistance(bot, pit) > 2400 then
        return BOT_MODE_DESIRE_NONE
    end
    local nTeamFightLocation = J.GetTeamFightLocation(bot)
    if nTeamFightLocation ~= nil and GetUnitToLocationDistance(bot, pit) < 1600
    and GetUnitToLocationDistance(bot, nTeamFightLocation) < 2000 then
        return BOT_MODE_DESIRE_NONE
    end

    local nearbyRecent = J.GetLastSeenEnemiesNearLoc(bot:GetLocation(), 1200)
    local pitRecent = J.GetLastSeenEnemiesNearLoc(pit, 1200)
    if #nearbyRecent >= 2 or #pitRecent >= 2
    or #J.GetEnemiesNearLoc(bot:GetLocation(), 1300) > 0 or #J.GetEnemiesNearLoc(pit, 1300) > 0 then
        return BOT_MODE_DESIRE_NONE
    end

    local aliveAlly = J.GetNumOfAliveHeroes(false)
    local aliveEnemy = J.GetNumOfAliveHeroes(true)
    if aliveAlly < aliveEnemy then
        return BOT_MODE_DESIRE_NONE
    end

    local nCoreWithNoEmptySlot = 0
    local aliveHeroesList = {}
    for _, h in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES)) do
        if J.IsValidHero(h) and not h:IsIllusion() and not J.IsMeepoClone(h)
            and not h:HasModifier('modifier_arc_warden_tempest_double')
            and J.GetHP(h) > 0.5 and not J.IsRetreating(h)
            and (h.ohaOuterTowerHoldUntil or 0) <= DotaTime()
            and GetUnitToLocationDistance(h, pit) <= 2000
        then
            if J.Utils.CountBackpackEmptySpace(h) <= 0 and J.IsCore(h) then
                nCoreWithNoEmptySlot = nCoreWithNoEmptySlot + 1
            end

            -- do not take rosh if the cores do not have any empty slot, it may get dropped on ground.
            if nCoreWithNoEmptySlot >= 2 then
                return BOT_MODE_DESIRE_NONE
            end
            table.insert(aliveHeroesList, h)
        end
    end

    local shouldKillRoshan = Roshan ~= nil or J.IsRoshanAlive()
    local ready = shouldKillRoshan and J.GetHP(bot) > 0.5 and J.HasEnoughDPSForRoshan(aliveHeroesList, Roshan)
    if ready and Roshan ~= nil and GetUnitToLocationDistance(bot, pit) < 1600 and #nearbyRecent == 0 and #pitRecent == 0 then
        local roshHP = J.GetHP(Roshan)
        if roshHP < 0.5 then
            return RemapValClamped(roshHP, 0.5, 0, BOT_MODE_DESIRE_MODERATE, BOT_MODE_DESIRE_ABSOLUTE)
        end
    end

    if shouldKillRoshan
    and not roshTimeFlag
    then
        sinceRoshAliveTime = DotaTime()
        roshTimeFlag = true
    else
        if not shouldKillRoshan
        then
            sinceRoshAliveTime = 0
            roshTimeFlag = false
        end
    end

    if J.IsRoshanCloseToChangingSides()
    then
        local botTarget = J.GetProperTarget(bot)
        if ready and J.IsRoshan(botTarget) then
            return RemapValClamped(J.GetHP(botTarget), 1, 0, BOT_MODE_DESIRE_NONE, BOT_MODE_DESIRE_VERYHIGH)
        end
        return BOT_MODE_DESIRE_NONE
    end

    if ready
    then
        local human, humanPing = J.GetHumanPing()
        if human ~= nil and DotaTime() > 5.0 then
            if humanPing ~= nil
            and humanPing.normal_ping
            and GetUnitToLocationDistance(human, pit) < 4500
            and J.GetDistance(humanPing.location, pit) < 600
            and DotaTime() < humanPing.time + 5.0
            then
                return 0.95
            end
        end

        local desire = GetRoshanDesire()
        if Roshan == nil then
            return math.min(desire, BOT_MODE_DESIRE_MODERATE)
        end
        local mul = RemapValClamped(DotaTime(), sinceRoshAliveTime, sinceRoshAliveTime + (2.5 * 60), 1, 2)
        return Clamp(desire * mul, 0, 0.95)
    end

    return BOT_MODE_DESIRE_NONE
end
