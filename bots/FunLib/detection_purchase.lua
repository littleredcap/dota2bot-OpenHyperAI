local J = require(GetScriptDirectory() .. '/FunLib/jmz_func')
local Item = J.Item
local Detection = {}

local dust = 'item_dust'
local sentry = 'item_ward_sentry'
local gem = 'item_gem'
local budgetWindow = 180

local function courierAvailable(hero, now)
    local courier = hero.theCourier
    return courier and not courier:IsNull() and courier:IsAlive()
        and not hero.SecretShop and not hero.SShopUser and (hero.ohaCourierUnsafeUntil or 0) <= now
end

local function findSupply(unit, first, last, name, ready)
    for slot = first, last do
        local item = unit:GetItemInSlot(slot)
        if item and not item:IsNull() then
            local kind = item:GetName()
            local matches = name == sentry and Item.GetSentryCharges(item) > 0
                or name ~= sentry and kind == name and (name == gem or item:GetCurrentCharges() > 0)
            if matches and (not ready or name == gem or item:IsFullyCastable()) then return item end
        end
    end
end

local function hasDelivery(hero, name, now)
    return courierAvailable(hero, now) and (findSupply(hero, 9, 14, name)
        or findSupply(hero.theCourier, 0, 5, name))
end

local function visibleDemand(bot, stationary, pursuing)
    local origin = bot:GetLocation()
    local best, priority, bestDistance = nil, 0, math.huge
    local focus = bot:GetAttackTarget() or bot:GetTarget()
    for _, enemy in ipairs(J.GetEnemiesNearLoc(origin, 1600)) do
        if enemy:CanBeSeen() and not J.HasInvisCounterBuff(enemy) then
            local concealing = enemy:IsInvisible() or J.IsUnitWillGoInvisible(enemy, true)
            if concealing or J.HasInvisibilityOrItem(enemy) then
                local point = enemy:GetLocation()
                local victim = enemy:GetAttackTarget()
                local threateningCore = J.IsValidHero(victim) and victim:GetTeam() == bot:GetTeam()
                    and (victim == bot or J.IsCore(victim))
                    and J.IsInRange(enemy, victim, enemy:GetAttackRange() + 250)
                local recentAmbush = bot:WasRecentlyDamagedByHero(enemy, 4)
                local teamFocus = concealing and ((pursuing and focus == enemy)
                    or #J.GetHeroesTargetingUnit(J.GetAlliesNearLoc(point, 1100), enemy) > 0)
                -- An attacker remains dangerous after the attack breaks its invisibility.
                local important = threateningCore or recentAmbush or teamFocus
                local urgency = important and 2 or ((concealing or stationary or pursuing) and 1 or 0)
                local distance = GetUnitToLocationDistance(bot, point)
                if urgency > 0 and (urgency > priority or (urgency == priority and distance < bestDistance))
                    and not J.HasSentryCoverage(point) then
                    best, priority, bestDistance = point, urgency, distance
                end
            end
        end
    end
    return best, priority == 2
end

local function canRestock(hero, name, now, urgent)
    if name == sentry and GetItemStockCount(sentry) <= 0 then return false end
    if Item.GetEmptyNonBackpackInventoryAmount(hero) == 0 then return false end
    if hero:DistanceFromFountain() > 600 and not courierAvailable(hero, now) then return false end
    local orders = hero.ohaDetectionPurchases or {}
    local previous = orders[#orders]
    if previous and now - previous.time < (urgent and 30 or 75) then return false end

    local dustCost, sentryCost = GetItemCost(dust), GetItemCost(sentry)
    -- Allow one basic counter even on a low net worth, and cap recurring spending.
    local budget = math.min(dustCost + 2 * sentryCost, math.max(dustCost, hero:GetNetWorth() * 0.04))
    for _, order in ipairs(orders) do
        if now - order.time < budgetWindow then budget = budget - order.cost end
    end
    if budget < GetItemCost(name) then return false end
    local component, remaining = Item.GetPendingPurchase(hero)
    if component == dust or component == sentry or component == gem then
        if hero:GetGold() + 60 >= GetItemCost(component) then return false end
    end
    return Item.CanBuyOptionalConsumable(hero, name, component, remaining)
end

local function canCover(ally, name, target, now)
    local carrier = findSupply(ally, 0, 5, gem)
    if carrier and GetUnitToLocationDistance(ally, target) <= carrier:GetSpecialValueInt('radius') then return true end
    if findSupply(ally, 0, 5, name, true) or hasDelivery(ally, name, now) or hasDelivery(ally, gem, now) then return true end
    local previous = ally.ohaDetectionPurchases and ally.ohaDetectionPurchases[#ally.ohaDetectionPurchases]
    return previous and previous.item == name and now - previous.time < 3
end

function Detection.Update(bot)
    local now = DotaTime()
    if now < 25 or now < (bot.ohaNextDetectionCheck or 0) or not bot:IsAlive() or J.GetHP(bot) < 0.30 then return end
    bot.ohaNextDetectionCheck = now + 2

    local support = J.GetPosition(bot) >= 4
    local pursuing = J.IsGoingOnSomeone(bot)
    local stationary = not pursuing and (J.IsInLaningPhase(bot) or J.IsDefending(bot))
    local target, urgent = visibleDemand(bot, stationary, pursuing)
    if not support and not urgent then return end
    local deward = target == nil
    local name = (deward or (support and stationary and not urgent)) and sentry or dust
    if findSupply(bot, 0, 14, name) or findSupply(bot, 0, 5, gem) or hasDelivery(bot, name, now) or hasDelivery(bot, gem, now)
        or not canRestock(bot, name, now, urgent) then return end

    if deward then
        if pursuing or J.IsDefending(bot) or J.IsRetreating(bot) or bot:WasRecentlyDamagedByAnyHero(4) then return end
        local Ward = require(GetScriptDirectory() .. '/FunLib/aba_ward_utility')
        local spot = Ward.GetClosestSentryWardSpot(bot, Ward.GetPossibleSentryWardSpots(bot))
        if not spot or GetUnitToLocationDistance(bot, spot.location) > 1600
            or #J.GetEnemiesNearLoc(spot.location, 1000) > 0 then return end
        target = spot.location
    end
    if J.HasSentryCoverage(target) or (not deward and J.HasDustCoverage(target)) then return end

    for _, ally in ipairs(J.GetAlliesNearLoc(target, 1100)) do
        if ally ~= bot and J.IsValidHero(ally) and not ally:IsIllusion() and J.GetHP(ally) >= 0.35 and not J.IsRetreating(ally) then
            if canCover(ally, name, target, now) then return end
            if not support and ally:IsBot() and ally.purchaseListInReverseOrder and J.GetPosition(ally) >= 4
                and canRestock(ally, name, now, true) then return end
        end
    end

    bot.ohaNextDetectionCheck = now + 4
    if bot:ActionImmediate_PurchaseItem(name) ~= PURCHASE_ITEM_SUCCESS then return end
    local recent = {}
    for _, order in ipairs(bot.ohaDetectionPurchases or {}) do
        if now - order.time < budgetWindow then recent[#recent + 1] = order end
    end
    recent[#recent + 1] = {time = now, cost = GetItemCost(name), item = name}
    bot.ohaDetectionPurchases = recent
    return true
end

return Detection
