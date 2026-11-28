local J = require(GetScriptDirectory() .. '/FunLib/jmz_func')
local Opening = {}

local function Spot(member)
    local lane = member:GetAssignedLane()
    local radiant = member:GetTeam() == TEAM_RADIANT
    local safeLane = radiant and LANE_BOT or LANE_TOP
    if lane == LANE_NONE or lane == nil then
        local position = J.GetPosition(member)
        if position == 1 or position == 5 then lane = safeLane end
    end
    if radiant then return lane == safeLane and RUNE_BOUNTY_2 or RUNE_POWERUP_1 end
    return lane == safeLane and RUNE_BOUNTY_1 or RUNE_POWERUP_2
end

function Opening.Target(bot)
    local now, mode = DotaTime(), GetGameMode()
    if now > 6 or not bot:IsAlive() or (GAMEMODE_1V1MID ~= nil and mode == GAMEMODE_1V1MID)
        or (GAMEMODE_MO ~= nil and mode == GAMEMODE_MO)
        or (now >= 0 and J.IsRetreating(bot))
        or (J.GetHP(bot) < 0.70 and bot:WasRecentlyDamagedByAnyHero(2)) then return end
    local spot = Spot(bot)
    if type(spot) ~= 'number' then return end
    local location = GetRuneSpawnLocation(spot)
    if not location or not IsLocationPassable(location) then return end
    local distance = GetUnitToLocationDistance(bot, location)
    if now >= 0 and (distance > 700 or GetRuneStatus(spot) ~= RUNE_STATUS_AVAILABLE) then return end
    local allies, enemies = 0, #J.GetEnemiesNearLoc(location, 850)
    for slot = 1, #GetTeamPlayers(bot:GetTeam()) do
        local member = GetTeamMember(slot)
        if J.IsValidHero(member) then
            local gap = GetUnitToLocationDistance(member, location)
            if gap <= 900 then allies = allies + 1 end
            if not member:IsBot() then
                local ping = member:GetMostRecentPing()
                if gap < 2000 or ping and ping.location and ping.time and J.GetDistance(ping.location, location) < 800
                    and GameTime() - ping.time < (ping.normal_ping and 5 or 30) then return end
            elseif now >= 0 and member ~= bot and not J.IsRetreating(member) and Spot(member) == spot
                and (gap < distance or gap == distance and member:GetPlayerID() < bot:GetPlayerID()) then
                return
            end
        end
    end
    if enemies >= 2 and enemies > allies then return end
    return spot, location
end

-- Ability ticks also run during setup. Keep a shared order so they can start
-- the walk even while the engine has yet to select rune mode.
function Opening.Walk(bot, spot, location)
    local now = DotaTime()
    if now >= 0 or not location or GetUnitToLocationDistance(bot, location) <= 110
        or J.CanNotUseAction(bot, true) then return false end
    if spot ~= bot.ohaOpeningRuneSpot or now >= (bot.ohaOpeningRuneStepAt or -math.huge) then
        if spot ~= bot.ohaOpeningRuneSpot and J.Customize and J.Customize.TraceLaneDecisions then
            print('[OHA opening rune]', now, bot:GetPlayerID(), spot, GetUnitToLocationDistance(bot, location), bot:GetActiveMode())
        end
        bot.ohaOpeningRuneSpot, bot.ohaOpeningRuneStepAt = spot, now + 0.60
        bot:Action_MoveToLocation(location)
    end
    return true
end

return Opening
