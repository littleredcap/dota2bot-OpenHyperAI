local J = require(GetScriptDirectory() .. '/FunLib/jmz_func')
local Item = J.Item
local Supply = {}

local healthItems = {item_flask=true, item_tango=true, item_tango_single=true}
local manaItems = {item_clarity=true, item_enchanted_mango=true}
local both = {item_bottle=true, item_famango=true, item_great_famango=true, item_greater_famango=true}

local function findRegen(bot, unit, first, last, health)
    if not unit or unit:IsNull() then return nil end
    for i = first, last do
        local item = unit:GetItemInSlot(i)
        if item and not item:IsNull() then
            local name, charges = item:GetName(), item:GetCurrentCharges()
            if charges > 0 and ((health and healthItems or manaItems)[name] or both[name]
                or ((name == 'item_magic_stick' or name == 'item_magic_wand') and J.CanRecoverWithLaneStick(bot, item, health))) then
                return name, i
            end
        end
    end
end

local function usableSlot(bot)
    local branch
    for i = 0, 5 do
        local item = bot:GetItemInSlot(i)
        if not item then return i end
        if item:GetName() == 'item_branches' or string.find(item:GetName(), '^item_recipe_') then branch = i end
    end
    return branch
end

local function almostOutOfTangos(bot, held)
    if held and held ~= 'item_tango' and held ~= 'item_tango_single' then return false end
    local charges = 0
    for slot = 0, 8 do
        local item = bot:GetItemInSlot(slot)
        if item and not item:IsNull() then
            local name = item:GetName()
            if name == 'item_tango' then charges = charges + item:GetCurrentCharges() end
            if item:GetCurrentCharges() > 0 and (both[name] or name == 'item_flask' or name == 'item_tango_single'
                or (name == 'item_magic_stick' or name == 'item_magic_wand') and J.CanRecoverWithLaneStick(bot, item, true)) then
                return false
            end
        end
    end
    return charges == 1 or charges == 0 and bot:HasModifier('modifier_tango_heal')
end

local function isNearCourierLeg(point, start, finish, length, reach)
    if J.GetLocationToLocationDistance(point, start) <= reach
        or J.GetLocationToLocationDistance(point, finish) <= reach then return true end
    if length <= 1 then return false end
    local projection = PointToLineDistance(start, finish, point)
    return projection and projection.within and projection.distance <= reach
end

local function safeCourierLeg(start, finish)
    local length = J.GetLocationToLocationDistance(start, finish)
    for _, enemy in ipairs(J.GetEnemiesNearLoc(start, length + 2050)) do
        local reach = math.max(850, enemy:GetAttackRange() + enemy:GetCurrentMovementSpeed() * 1.5 + 115)
        if isNearCourierLeg(enemy:GetLocation(), start, finish, length, reach) then return false end
    end
    for _, player in ipairs(GetTeamPlayers(GetOpposingTeam())) do
        if IsHeroAlive(player) then
            local info = GetHeroLastSeenInfo(player)
            local seen = info and info[1]
            if seen and seen.time_since_seen < 5
                and isNearCourierLeg(seen.location, start, finish, length, 850) then return false end
        end
    end
    return true
end

function Supply.IsCourierExposed(courier)
    local origin = courier:GetLocation()
    return not safeCourierLeg(origin, courier:GetExtrapolatedLocation(0.9))
end

function Supply.CanDeliverCourier(bot, courier, collectStash)
    local start, destination = courier:GetLocation(), bot:GetLocation()
    if collectStash then
        local fountain = J.GetTeamFountain()
        if courier:DistanceFromFountain() > 800 and not safeCourierLeg(start, fountain) then return false end
        start = fountain
    end
    return safeCourierLeg(start, destination)
end

local function deliveryTime(bot, courier, aboard, tower)
    if not courier or courier:IsNull() or not courier:IsAlive() or J.GetHP(courier) < 0.9
        or (bot.ohaCourierUnsafeUntil or 0) > DotaTime() or bot.SShopUser then return nil end
    local state = GetCourierState(courier)
    if state == COURIER_STATE_DEAD or state == COURIER_STATE_MOVING
        or (not aboard and (state == COURIER_STATE_DELIVERING_ITEMS or bot.SecretShop or Item.GetEmptyNonBackpackInventoryAmount(courier) == 0)) then return nil end
    local destination = bot:GetLocation()
    local distance = GetUnitToUnitDistance(courier, bot)
    local start = courier:GetLocation()
    if not aboard then
        distance = courier:DistanceFromFountain() + bot:DistanceFromFountain()
        local fountain = J.GetTeamFountain()
        if courier:DistanceFromFountain() > 800 and not safeCourierLeg(start, fountain) then return nil end
        start = fountain
    end
    if not safeCourierLeg(start, destination) then return nil end
    local enemies = J.GetEnemiesNearLoc(destination, 900)
    if #enemies > 0 and (not J.IsInRange(bot, tower, 1050) or #J.GetHeroesTargetingUnit(enemies, bot) > 0) then return nil end
    return 2 + 1.15 * distance / math.max(1, courier:GetCurrentMovementSpeed())
end

local function fountainTime(bot)
    local walk = 1.15 * bot:DistanceFromFountain() / math.max(1, bot:GetCurrentMovementSpeed())
    local scroll = bot:GetItemInSlot(15)
    local back = scroll and scroll:IsFullyCastable() and math.min(walk, 4) or walk
    -- Discount the replacement cost of spending the last ready scroll; walking is always an alternative.
    local scrollValue = 0
    if back < walk and scroll:GetCurrentCharges() == 1 and not Item.HasItem(bot, 'item_travel_boots')
        and not Item.HasItem(bot, 'item_travel_boots_2') then scrollValue = GetItemCost('item_tpscroll') * 0.5 end
    return walk + back + 8, 2 * walk + 8, scrollValue
end

local function needsHealth(bot)
    return J.GetHP(bot) < 0.68 and bot:OriginalGetMaxHealth() - bot:OriginalGetHealth() >= 160
        and not (bot:HasModifier('modifier_tango_heal') or bot:HasModifier('modifier_flask_healing')
        or bot:HasModifier('modifier_bottle_regeneration')
        or bot:HasModifier('modifier_juggernaut_healing_ward_heal') or bot:HasModifier('modifier_fountain_aura_buff')
        or bot:HasModifier('modifier_filler_heal') or bot:HasModifier('modifier_elixer_healing'))
end

local function laneIncome(bot, tower, reset, walking, scrollValue, waiting)
    local wave = bot:GetNearbyLaneCreeps(1500, true)
    if #wave == 0 then
        if GetUnitToLocationDistance(bot, GetLaneFrontLocation(bot:GetTeam(), bot:GetAssignedLane(), 0)) > 1500 then return 0 end
        wave = bot:GetNearbyLaneCreeps(1500, false)
    end
    local bounty = 0
    local safeWave = J.GetTowerCoveredLaneCreeps(bot, tower, wave, bot:GetNearbyHeroes(1600, true, BOT_MODE_NONE))
    for _, creep in ipairs(safeWave) do
        bounty = bounty + creep:GetBountyGoldMin()
    end
    local partner = J.GetLanePartner(bot)
    local share = 0.60
    if partner and J.IsInRange(bot, partner, 1200) and J.IsCore(partner) and not J.IsRetreating(partner) then
        -- A support saves part of the core's wave only when the core needs cover.
        share = (partner:WasRecentlyDamagedByAnyHero(5) or #partner:GetNearbyHeroes(1000, true, BOT_MODE_NONE) > 0) and 0.55 or 0.15
    elseif J.IsCore(bot) then
        -- Smooth the first waves with five last hits from two hypothetical four-creep waves.
        -- Once the lane has a history, a struggling core should not budget for most of a wave.
        local waves = math.max(0, (DotaTime() - 25) / 30)
        share = math.min(0.9, (bot:GetLastHits() + 5) / (waves * 4 + 8))
    end
    local waveGold = bounty * share
    local function lostIncome(seconds)
        return waveGold * math.min(1.5, math.max(0, seconds - waiting) / 30)
    end
    return math.min(lostIncome(reset) + scrollValue, lostIncome(walking))
end

local function lanePartnerCanShare(bot, health)
    local ally = J.GetLanePartner(bot)
    if not ally or not ally:IsBot() or not J.IsInRange(bot, ally, 300) or J.IsRetreating(ally)
        or J.GetHP(ally) < 0.65 then return false end
    for slot = 0, 5 do
        local item = ally:GetItemInSlot(slot)
        if item and item:IsFullyCastable() then
            local name = item:GetName()
            if health and name == 'item_tango' and DotaTime() > J.Role.fLastGiveTangoTime + 40 then return true end
            if health and name == 'item_flask' and not bot:WasRecentlyDamagedByAnyHero(3)
                and #bot:GetNearbyHeroes(900, true, BOT_MODE_NONE) == 0 then return true end
            if not health and name == 'item_clarity' and not bot:WasRecentlyDamagedByAnyHero(4)
                and #bot:GetNearbyHeroes(800, true, BOT_MODE_NONE) == 0 then return true end
        end
    end
    return false
end

-- Called once per purchase tick. A purchase receipt alone never makes a hero wait.
function Supply.Update(bot)
    local now, order = DotaTime(), bot.ohaLaneSupply
    if order then order.waitUntil = 0 end
    if now < 40 or not bot:IsAlive() or not J.IsInLaningPhase(bot) or bot:DistanceFromFountain() < 2300 then
        bot.ohaLaneSupply = nil
        return
    end
    local health = needsHealth(bot)
    local held, slot = findRegen(bot, bot, 0, 8, true)
    local pendingRefill = order and order.proactive and now <= order.deadline
    local proactive = J.GetHP(bot) >= 0.60 and J.GetHP(bot) <= 0.82
        and (pendingRefill or bot:WasRecentlyDamagedByAnyHero(8))
        and almostOutOfTangos(bot, held)
        and not bot:HasModifier('modifier_flask_healing') and not bot:HasModifier('modifier_bottle_regeneration')
    local lowMana = bot:GetMaxMana() > 0 and J.GetMP(bot) < 0.40 and not bot:HasModifier('modifier_clarity_potion')
    if proactive and not health and lowMana and J.GetLaningManaShortfall(bot, 5) then proactive = false end
    health = health or proactive
    local stableHealth = health and J.GetHP(bot) > 0.48 and not bot:WasRecentlyDamagedByAnyHero(10)
        and #bot:GetNearbyHeroes(1400, true, BOT_MODE_NONE) == 0 and not J.IsRetreating(bot)
    if stableHealth and lowMana and J.GetLaningManaShortfall(bot, 5) then health = false end
    if not health and not lowMana then
        bot.ohaLaneSupply, bot.ohaLaneShareSince = nil, nil
        return
    end
    local tower = J.GetSafeLaneSupplyTower(bot)
    if not tower then return end
    if not health then held, slot = findRegen(bot, bot, 0, 8, false) end
    local main = usableSlot(bot)
    if held and not proactive then
        bot.ohaLaneShareSince = nil
        if slot >= 6 and main ~= nil then bot:ActionImmediate_SwapItems(slot, main) end
        if order and not order.proactive and held == order.item and now <= order.deadline and (slot <= 5 or main ~= nil) then
            order.waitUntil = math.min(order.deadline, now + 2.5)
        else
            bot.ohaLaneSupply = nil
        end
        return
    end
    if proactive and held and slot >= 6 and main ~= nil then bot:ActionImmediate_SwapItems(slot, main) end
    if main == nil or Item.GetEmptyInventoryAmount(bot) == 0 then return end
    local courier = bot.theCourier
    local aboard = findRegen(bot, courier, 0, 5, health)
    local cargo = aboard or findRegen(bot, bot, 9, 14, health)
    local eta = deliveryTime(bot, courier, aboard, tower)
    if not eta then return end
    local reset, walking, scrollValue = fountainTime(bot)
    if eta + 4 >= reset then return end
    local projectedHP = (bot:OriginalGetHealth() + bot:GetHealthRegen() * eta) / math.max(1, bot:OriginalGetMaxHealth())
    local projectedLimit = proactive and 0.80 or 0.72
    if (health and projectedHP >= projectedLimit) or (not health and not J.GetLaningManaShortfall(bot, eta)) then return end

    if health and projectedHP < 0.5 and J.GetMP(bot) < 0.2 and J.GetLaningManaShortfall(bot, eta)
        and not findRegen(bot, bot, 0, 14, false) and not findRegen(bot, courier, 0, 5, false) then return end
    if cargo then
        bot.ohaLaneShareSince = nil
        if not order or order.item ~= cargo then
            order = {item=cargo, deadline=now + eta + 10, proactive=proactive}
            bot.ohaLaneSupply = order
        end
        order.proactive = proactive
        order.waitUntil = math.min(order.deadline, now + 2.5)
        return
    end
    bot.ohaLaneSupply = nil
    if now < (bot.ohaNextLaneSupplyBuy or 0) then return end
    if health and (1 - projectedHP) * bot:OriginalGetMaxHealth() < (proactive and 155 or 200) then return end
    if health and stableHealth then return end
    if not health and (bot:WasRecentlyDamagedByAnyHero(4) or #bot:GetNearbyHeroes(800, true, BOT_MODE_NONE) > 0) then return end
    if lanePartnerCanShare(bot, health) then
        bot.ohaLaneShareSince = bot.ohaLaneShareSince or now
        if now - bot.ohaLaneShareSince < 5 then return end
    else
        bot.ohaLaneShareSince = nil
    end
    local waiting = eta * (J.GetHP(bot) < 0.45 and 0.65 or 0.35) + 4
    local income, nextItem = laneIncome(bot, tower, reset, walking, scrollValue, waiting), Item.GetPendingPurchase(bot)
    if nextItem and ((health and healthItems or manaItems)[nextItem] or both[nextItem])
        and GetItemStockCount(nextItem) ~= 0 and bot:GetGold() + 60 >= GetItemCost(nextItem) then return end
    local candidates
    if health then
        local quiet = not bot:WasRecentlyDamagedByAnyHero(3) and #bot:GetNearbyHeroes(900, true, BOT_MODE_NONE) == 0
        candidates = not proactive and projectedHP < 0.53 and quiet and {'item_flask', 'item_tango'} or {'item_tango'}
    else
        candidates = {'item_clarity'}
    end
    for _, name in ipairs(candidates) do
        if (name ~= 'item_tango' or #bot:GetNearbyTrees(800) > 0) and income >= GetItemCost(name)
            and GetItemStockCount(name) ~= 0 and Item.CanBuyOptionalConsumable(bot, name, nextItem) then
            bot.ohaNextLaneSupplyBuy = now + 4
            if bot:ActionImmediate_PurchaseItem(name) == PURCHASE_ITEM_SUCCESS then
                bot.ohaLaneSupply = {item=name, deadline=now + eta + 10, waitUntil=0, proactive=proactive}
                bot.ohaNextLaneSupplyBuy = now + (proactive and 75 or 45)
                return true
            end
            return
        end
    end
end

-- The hero has its own courier. Confirm the cargo at each transition and never
-- redirect an existing delivery for an item still sitting in the stash.
function Supply.CourierAction(bot, courier, state)
    local order, now = bot.ohaLaneSupply, DotaTime()
    if not order or now > order.deadline or not bot:IsAlive() or bot.SShopUser then return nil end
    local aboard = courier:FindItemSlot(order.item) >= 0
    if not aboard then
        if bot.SecretShop or state == COURIER_STATE_DELIVERING_ITEMS then return nil end
        local inStash = false
        for slot = 9, 14 do
            local item = bot:GetItemInSlot(slot)
            if item and not item:IsNull() and item:GetName() == order.item then inStash = true; break end
        end
        if not inStash then return nil end
    end
    if state == COURIER_STATE_MOVING or state == COURIER_STATE_DEAD then return nil end
    local tower = J.GetSafeLaneSupplyTower(bot)
    if not tower or Item.GetEmptyInventoryAmount(bot) == 0 or not deliveryTime(bot, courier, aboard, tower) then
        order.waitUntil = 0
        if aboard and state == COURIER_STATE_DELIVERING_ITEMS then return COURIER_ACTION_RETURN_STASH_ITEMS, true end
        return nil, true
    end
    if order.waitUntil <= now then return nil end
    if aboard then
        if state == COURIER_STATE_DELIVERING_ITEMS then return nil, true end
        return COURIER_ACTION_TRANSFER_ITEMS, true
    end
    if state == COURIER_STATE_AT_BASE or (state == COURIER_STATE_IDLE and courier:DistanceFromFountain() < 800) then
        return COURIER_ACTION_TAKE_STASH_ITEMS, true
    end
    if state == COURIER_STATE_IDLE then return COURIER_ACTION_RETURN_STASH_ITEMS, true end
    return nil, true
end

return Supply
