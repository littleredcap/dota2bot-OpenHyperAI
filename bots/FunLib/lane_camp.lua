local J = require(GetScriptDirectory() .. '/FunLib/jmz_func')

local Camp = {}
local Customize = require(GetScriptDirectory() .. '/Customize/general')

local function TracePull(bot, plan, stage, detail)
    if not Customize.TraceLanePull or plan.kind ~= 'pull' then return end
    print(string.format('[OHA lane-pull] t=%.2f player=%d lane=%d stage=%s %s',
        DotaTime(), bot:GetPlayerID(), plan.lane, stage, detail or ''))
end

local function PullIntercept(bot, target, point)
    local speed = math.max(150, math.min(bot:GetCurrentMovementSpeed(), target:GetCurrentMovementSpeed()))
    local impact = J.GetAttackProDelayTime(bot, target) or 0.5
    return impact, J.GetLocationToLocationDistance(target:GetLocation(), point) / speed
end

local function NearCamp(bot, location)
    local creeps = {}
    for _, unit in ipairs(bot:GetNearbyNeutralCreeps(1550)) do
        if J.IsValid(unit) and unit:GetTeam() == TEAM_NEUTRAL
            and GetUnitToLocationDistance(unit, location) <= 520 then
            creeps[#creeps + 1] = unit
        end
    end
    return creeps
end

local function IsSafe(point)
    return IsLocationPassable(point) and #J.GetEnemiesNearLoc(point, 1050) == 0
        and #J.GetLastSeenEnemiesNearLoc(point, 1050) == 0
end

local function CanWorkCamp(bot)
    return J.GetPosition(bot) >= 4 and bot:IsAlive() and J.GetHP(bot) >= 0.68
        and not J.IsRetreating(bot) and not J.IsGoingOnSomeone(bot)
        and not bot:WasRecentlyDamagedByAnyHero(3)
        and (bot.ohaOuterTowerHoldUntil or 0) <= DotaTime()
        and (bot.ohaLaneGank == nil or bot.ohaLaneGank.expires <= DotaTime())
end

local function CampTaken(bot, location)
    for slot = 1, #GetTeamPlayers(bot:GetTeam()) do
        local ally = GetTeamMember(slot)
        if ally ~= nil and ally ~= bot and ally:IsAlive() then
            local work = ally.ohaLaneCamp
            local farm = ally.ohaFarmCampClaim
            if (work and work.expires > DotaTime() and J.GetLocationToLocationDistance(work.camp.location, location) < 120)
                or (farm and farm.expires > DotaTime() and J.GetLocationToLocationDistance(farm.location, location) < 120) then
                return true
            end
        end
    end
    return false
end

local farmingAbilities = {
    npc_dota_hero_sven = 'sven_great_cleave', npc_dota_hero_luna = 'luna_moon_glaive',
    npc_dota_hero_kunkka = 'kunkka_tidebringer', npc_dota_hero_medusa = 'medusa_split_shot',
    npc_dota_hero_gyrocopter = 'gyrocopter_flak_cannon',
}

local function StackFarmer(location)
    local selected, bestDistance
    for _, ally in ipairs(J.GetAlliesNearLoc(location, 3500)) do
        local name = farmingAbilities[ally:GetUnitName()]
        local ability = name ~= nil and ally:GetAbilityByName(name) or nil
        if ally:IsBot() and J.IsCore(ally) and J.GetHP(ally) >= 0.55 and not J.IsRetreating(ally)
            and ((ability ~= nil and not ability:IsNull() and ability:GetLevel() >= 2)
                or J.HasItem(ally, 'item_bfury') or J.HasItem(ally, 'item_maelstrom')
                or J.HasItem(ally, 'item_radiance') or J.HasItem(ally, 'item_mjollnir')) then
            local seconds = ally:GetSecondsPerAttack()
            local distance = GetUnitToLocationDistance(ally, location)
            if seconds > 0 and ally:GetAttackDamage() / seconds >= 105
                and (bestDistance == nil or distance < bestDistance) then
                selected, bestDistance = ally, distance
            end
        end
    end
    return selected
end

local function PullWaveETA(bot, lane, location)
    local track = GetAmountAlongLane(lane, location)
    local direction = bot:GetTeam() == TEAM_RADIANT and 1 or -1
    local eta
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(1600, false)) do
        if J.IsValid(creep) and not J.IsKeyWordUnit('siege', creep) then
            local unitTrack = GetAmountAlongLane(lane, creep:GetLocation())
            local distance = GetUnitToLocationDistance(creep, location)
            if distance >= 260 and distance <= 1500 and unitTrack.distance < 250
                and (track.amount - unitTrack.amount) * direction > 0 and creep:GetAttackTarget() == nil then
                local time = distance / math.max(250, creep:GetCurrentMovementSpeed())
                if eta == nil or time < eta then eta = time end
            end
        end
    end
    return eta
end

local function WaveTravelTime(creep, lane, point, direction)
    local position = creep:GetLocation()
    local track = GetAmountAlongLane(lane, position)
    if track.distance >= 250 then return nil end
    local along = (GetAmountAlongLane(lane, point).amount - track.amount) * direction
    return GetUnitToLocationDistance(creep, point) / math.max(250, creep:GetCurrentMovementSpeed())
        * (along > 0 and 1 or -1)
end

local function PullWaveTail(bot, lane, point)
    local direction = bot:GetTeam() == TEAM_RADIANT and 1 or -1
    local wave = {}
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(1600, false)) do
        if J.IsValid(creep) and creep:GetAttackTarget() == nil then
            local eta = WaveTravelTime(creep, lane, point, direction)
            if eta and eta > 0 and eta <= 6 then wave[#wave + 1] = {unit=creep, eta=eta} end
        end
    end
    if #wave < 4 then return nil, false end
    if #wave ~= 4 then return nil, true end -- do not drag a weak camp into a double wave
    table.sort(wave, function(a, b) return a.eta < b.eta end)
    if wave[3].eta - wave[2].eta < 0.55 or wave[4].eta - wave[3].eta > 0.70
        or not (J.IsKeyWordUnit('_ranged', wave[3].unit) or J.IsKeyWordUnit('_ranged', wave[4].unit)) then
        return nil, true
    end
    return wave, true
end

local function TailStillReachable(bot, plan, intercept)
    local direction = bot:GetTeam() == TEAM_RADIANT and 1 or -1
    for i, row in ipairs(plan.half) do
        local creep = row.unit
        if J.IsValid(creep) then
            local eta = WaveTravelTime(creep, plan.lane, plan.goal, direction)
            if i <= 2 then
                if eta and eta > intercept - 0.45 then return false end
            elseif not eta or creep:GetAttackTarget() ~= nil or eta < intercept - 0.35 or eta > intercept + 0.9 then
                return false
            end
        elseif i >= 3 then return false end
    end
    return true
end

local function CanPullLane(bot, lane, tower, point)
    if not J.IsValidBuilding(tower) or #J.GetEnemiesNearLoc(tower:GetLocation(), 1250) >= 2
        or #J.GetLastSeenEnemiesNearLoc(tower:GetLocation(), 1250) >= 2 then return false end
    local ally = J.GetLanePartner(bot)
    if not J.IsValidHero(ally) or not J.IsCore(ally) or ally:GetAssignedLane() ~= lane
        or J.GetHP(ally) < 0.62 or J.IsRetreating(ally) or ally:WasRecentlyDamagedByAnyHero(3)
        or GetUnitToLocationDistance(ally, point) > 3200 then return false end
    local nearTower = 0
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(1600, true)) do
        if J.IsValid(creep) and J.IsInRange(creep, tower, 1250) then nearTower = nearTower + 1 end
    end
    if nearTower >= 3 then return false end
    if J.CanLeaveLane(bot) then return true end
    -- A short pull is not a long roam. When the pushed-out front is occupied,
    -- leave only if the core has no visible or recently seen enemy on top of it.
    local anchor = ally:GetLocation()
    return J.IsInRange(ally, tower, 2300)
        and #J.GetEnemiesNearLoc(anchor, 1150) == 0
        and #J.GetLastSeenEnemiesNearLoc(anchor, 1150) == 0
end

local function PlanPull(bot, camp, lane, lanePoint, neutral, campCreeps)
    local team = bot:GetTeam()
    local safeLane = team == TEAM_RADIANT and LANE_BOT or LANE_TOP
    local cross = J.GetLocationToLocationDistance(camp.location, lanePoint)
    if lane ~= safeLane or not J.Site.IsSmallCamp(camp) or cross > 850 then return end
    local towerId = lane == LANE_BOT and TOWER_BOT_1 or TOWER_TOP_1
    local tower = GetTower(team, towerId)
    local front = GetLaneFrontLocation(team, lane, 0)
    if not CanPullLane(bot, lane, tower, lanePoint) or GetUnitToLocationDistance(tower, lanePoint) > 1900
        or not IsSafe(J.VectorTowards(camp.location, lanePoint, cross * 0.5)) then return end
    local direction = team == TEAM_RADIANT and 1 or -1
    local home = GetAmountAlongLane(lane, tower:GetLocation()).amount
    local pushed = (GetAmountAlongLane(lane, front).amount - home) * direction
    local enemyTower = GetTower(GetOpposingTeam(), towerId)
    local nearEnemyTower = J.IsValidBuilding(enemyTower)
        and GetUnitToLocationDistance(enemyTower, front) <= 1550
    if pushed <= 0 or not (nearEnemyTower or GetUnitToLocationDistance(tower, front) >= 1200) then return end
    local eta = PullWaveETA(bot, lane, lanePoint)
    local impact, travel = PullIntercept(bot, neutral, lanePoint)
    local intercept = impact + travel
    local half, observed
    if #campCreeps <= 3 then
        half, observed = PullWaveTail(bot, lane, lanePoint)
        if observed and not half then return end
        if half then eta = half[3].eta end
    end
    if eta and eta >= intercept - 0.9 and eta <= intercept + 2.4 then
        local _, release = J.GetAttackProDelayTime(bot, neutral)
        local approach = math.max(0, GetUnitToUnitDistance(bot, neutral) - bot:GetAttackRange())
            / math.max(1, bot:GetCurrentMovementSpeed())
        return {kind = 'pull', camp = camp, goal = lanePoint, lane = lane, tower = tower,
            target = neutral, half = half, expires = DotaTime() + eta + 4,
            impact = math.max(0.25, impact - (release or 0)),
            attackAt = DotaTime() + math.max(0, eta - (impact - approach) - travel - 0.1)}
    end
end

local function PlanStack(bot, camp, lanePoint, distance)
    if J.Site.IsAncientCamp(camp) or distance > 1100 then return end
    local now = DotaTime()
    local minute = math.floor(now / 60) * 60
    local attackAt = minute + J.Site.GetCampStackTime({cattr = camp})
    local approach = math.max(0, distance - bot:GetAttackRange()) / math.max(1, bot:GetCurrentMovementSpeed())
    if now > attackAt + 0.55 or now + approach < attackAt - 1.25 or now + approach > attackAt + 0.8 then return end
    local owner = StackFarmer(camp.location)
    if owner == nil then return end
    local goal = camp.idx ~= nil and J.Site.GetCampMoveToStack(camp.idx) or nil
    local length = goal ~= nil and J.GetLocationToLocationDistance(camp.location, goal) or 0
    if length < 540 or length > 1000 or not IsSafe(goal) then
        goal = J.VectorTowards(camp.location, lanePoint, 760)
    end
    if camp.min and camp.max and goal.x >= camp.min.x and goal.x <= camp.max.x
        and goal.y >= camp.min.y and goal.y <= camp.max.y then return end
    if J.GetLocationToLocationDistance(camp.location, goal) >= 540 and IsSafe(goal) then
        return {kind = 'stack', camp = camp, goal = goal, owner = owner:GetPlayerID(),
            attackAt = attackAt, spawnAt = minute + 60, expires = minute + 63}
    end
end

function Camp.Cancel(bot, reason)
    if bot.ohaLaneCamp == nil then return end
    if reason ~= 'confirmed' then TracePull(bot, bot.ohaLaneCamp, 'cancel', reason or 'mode-exit') end
    bot.ohaLaneCamp.expires = DotaTime()
    bot.ohaLaneCamp = nil
    bot.ohaNextCampWork = DotaTime() + 5
end

function Camp.Plan(bot, lane)
    local now = DotaTime()
    if (lane ~= LANE_TOP and lane ~= LANE_BOT) or now < 95 or now >= 14 * 60
        or now < (bot.ohaNextCampWork or 0) or not CanWorkCamp(bot) then return end
    local work = bot.ohaLaneCamp
    if work ~= nil and work.expires > now and IsSafe(work.goal)
        and (work.kind == 'pull' and CanPullLane(bot, lane, work.tower, work.goal)
            or work.kind == 'stack' and J.CanLeaveLane(bot)) then return work end
    if work ~= nil then Camp.Cancel(bot); return end
    local best, bestScore
    for _, camp in pairs(GetNeutralSpawners()) do
        local distance = GetUnitToLocationDistance(bot, camp.location)
        if camp.team == bot:GetTeam() and distance <= 1230
            and IsLocationVisible(camp.location) and IsSafe(camp.location) and not CampTaken(bot, camp.location) then
            local track = GetAmountAlongLane(lane, camp.location)
            local point = GetLocationAlongLane(lane, track.amount)
            if track.distance >= 180 and IsSafe(point) then
                local creeps = NearCamp(bot, camp.location)
                local neutral, nearest = nil, math.huge
                for _, creep in ipairs(creeps) do
                    local dist = GetUnitToUnitDistance(bot, creep)
                    if dist < nearest and J.CanBeAttacked(creep) then neutral, nearest = creep, dist end
                end
                if neutral then
                    local plan = PlanPull(bot, camp, lane, point, neutral, creeps)
                    if not plan and J.CanLeaveLane(bot) then plan = PlanStack(bot, camp, point, distance) end
                    local score = distance - (plan and plan.kind == 'pull' and 500 or 0)
                    if plan and (bestScore == nil or score < bestScore) then
                        plan.creeps = creeps
                        best, bestScore = plan, score
                    end
                end
            end
        end
    end
    return best
end

function Camp.Think(bot, plan)
    local now = DotaTime()
    if plan.expires <= now or not CanWorkCamp(bot) or not IsSafe(plan.goal) or not IsSafe(plan.camp.location)
        or (plan.kind == 'pull' and not CanPullLane(bot, plan.lane, plan.tower, plan.goal))
        or (plan.kind == 'stack' and not J.CanLeaveLane(bot))
        or CampTaken(bot, plan.camp.location) then
        Camp.Cancel(bot, plan.expires <= now and 'expired' or 'unsafe-or-claimed')
        return false
    end
    if bot.ohaLaneCamp ~= plan then TracePull(bot, plan, 'plan') end
    bot.ohaLaneCamp = plan
    if plan.drawAt == nil then
        if plan.attackAt ~= nil and now > plan.attackAt + 0.85 then Camp.Cancel(bot); return false end
        local target = plan.kind == 'pull' and plan.target or nil
        if plan.kind ~= 'pull' then
            for _, creep in ipairs(plan.creeps) do
                if J.IsValid(creep) and J.CanBeAttacked(creep) then target = creep; break end
            end
        elseif not J.IsValid(target) or not J.CanBeAttacked(target) then
            target = nil
        end
        if target == nil then Camp.Cancel(bot); return false end
        if not J.IsInRange(bot, target, bot:GetAttackRange() + 35) then
            bot:Action_MoveToLocation(plan.camp.location)
        elseif plan.attackAt == nil or now >= plan.attackAt then
            if plan.kind == 'pull' then
                local impact, travel = PullIntercept(bot, target, plan.goal)
                local intercept = impact + travel
                if plan.half then
                    if not TailStillReachable(bot, plan, intercept) then
                        Camp.Cancel(bot, 'half-pull-window')
                        return false
                    end
                    TracePull(bot, plan, 'attack-order', string.format('half intercept=%.2f', intercept))
                else
                    local eta = PullWaveETA(bot, plan.lane, plan.goal)
                    if not eta or eta < intercept - 0.9 or eta > intercept + 2.4 then
                        Camp.Cancel(bot, 'intercept-window')
                        return false
                    end
                    TracePull(bot, plan, 'attack-order', string.format('eta=%.2f intercept=%.2f', eta, intercept))
                end
            end
            local _, release = J.GetAttackProDelayTime(bot, target)
            plan.attackTime, plan.drawAt = bot:GetLastAttackTime(), now + math.min(1, (release or 0.3) + 0.25)
            plan.target = target
            bot:Action_AttackUnit(target, true)
        else
            bot:Action_ClearActions(true)
        end
        return true
    end
    if not plan.released then
        local aggro = J.IsValid(plan.target) and plan.target:GetAttackTarget() == bot
        if plan.kind == 'pull' and not aggro then
            if now <= plan.drawAt + math.max(0.4, plan.impact or 0.5) then return true end
            Camp.Cancel(bot, 'no-aggro')
            return false
        elseif not aggro and bot:GetLastAttackTime() == plan.attackTime then
            if now < plan.drawAt then return true end
            Camp.Cancel(bot)
            return false
        end
        plan.released = true
        TracePull(bot, plan, 'aggro')
    end
    if plan.kind == 'pull' then
        local count, caughtTail = 0, 0
        for _, laneCreep in ipairs(bot:GetNearbyLaneCreeps(1600, false)) do
            if J.IsValid(laneCreep) and laneCreep:GetTeam() == bot:GetTeam()
                and GetUnitToLocationDistance(laneCreep, plan.goal) <= 650 then
                for _, creep in ipairs(plan.creeps) do
                    if J.IsValid(creep) and (creep:GetAttackTarget() == laneCreep
                        or laneCreep:GetAttackTarget() == creep) then
                        count = count + 1
                        if plan.half and (laneCreep == plan.half[3].unit or laneCreep == plan.half[4].unit) then
                            caughtTail = caughtTail + 1
                        end
                        break
                    end
                end
            end
        end
        if count >= 2 then
            local half = count == 2 and caughtTail == 2
            bot.ohaLastConfirmedPull = {time = now, lane = plan.lane, caught = count, half = half}
            TracePull(bot, plan, 'confirmed', string.format('caught=%d tail=%d', count, caughtTail))
            Camp.Cancel(bot, 'confirmed')
            bot.ohaNextCampWork = now + 25
            return false
        end
    elseif now >= plan.spawnAt + 0.4 then
        local originalStillAlive = false
        for _, before in ipairs(plan.creeps) do
            if J.IsValid(before) then originalStillAlive = true; break end
        end
        if originalStillAlive then
            for _, creep in ipairs(NearCamp(bot, plan.camp.location)) do
                local existed = false
                for _, before in ipairs(plan.creeps) do existed = existed or creep == before end
                if not existed then
                    bot.ohaStackedCamp = {location = plan.camp.location, owner = plan.owner, expires = now + 28}
                    Camp.Cancel(bot)
                    bot.ohaNextCampWork = now + 27
                    return false
                end
            end
        end
    end
    if GetUnitToLocationDistance(bot, plan.goal) > 120 then bot:Action_MoveToLocation(plan.goal) end
    return true
end

return Camp
