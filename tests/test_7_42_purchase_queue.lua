local function no() return false end
local function yes() return true end
local function empty() return {} end
local SUCCESS, FAILED, OUT_OF_STOCK = 1, 2, 3

local function item(name, charges)
    return {GetName = function() return name end, GetCurrentCharges = function() return charges or 0 end,
        IsFullyCastable = function() return charges ~= 0 end, IsNull = no,
        GetSpecialValueInt = function(_, key) assert(key == 'restore_per_charge'); return 15 end}
end

local function fixture(plan, opts)
    opts = opts or {}
    local now, orders = opts.time or 800, {}
    local slots = {[15] = item('item_tpscroll', 2)}
    local courierSlots = {}
    local recipes = {
        item_manta = {{'item_yasha', 'item_ultimate_orb', 'item_recipe_manta'}},
        item_yasha = {{'item_blade_of_alacrity', 'item_boots_of_elves', 'item_recipe_yasha'}},
        item_magic_wand = {{'item_magic_stick', 'item_branches', 'item_branches', 'item_recipe_magic_wand'}},
        item_black_king_bar = {{'item_ogre_axe', 'item_mithril_hammer', 'item_recipe_black_king_bar'}},
    }
    local costs = {item_manta = 4600, item_black_king_bar = 4000, item_ultimate_orb = 2800,
        item_yasha = 2000, item_recipe_manta = 900, item_ogre_axe = 1000, item_blade_of_alacrity = 1000,
        item_magic_wand = 450, item_tpscroll = 100, item_dust = 80, item_flask = 110, item_tango = 90,
        item_clarity = 50, item_boots = 500, item_ward_sentry = 50, item_gem = 900,
        item_mithril_hammer = 1600, item_recipe_black_king_bar = 1400}
    local secret = {item_ultimate_orb = true}
    local bot, courier = {}, {}
    local function buy(from, name)
        orders[#orders + 1] = {from, name}
        if opts.failure then return opts.failure end
        local inventory = from == 'courier' and courierSlots or slots
        if opts.lane or opts.detection then opts.gold = opts.gold - costs[name] end
        for i = (opts.lane or opts.stashPurchases) and from == 'hero' and 9 or 0, 14 do
            if inventory[i] == nil then
                inventory[i] = item(name, (opts.lane or opts.detection) and (name == 'item_tango' and 3 or 1) or nil)
                break
            end
        end
        return SUCCESS
    end

    bot.GetUnitName = function() return 'npc_dota_hero_test' end
    bot.IsInvulnerable, bot.IsHero, bot.IsAlive, bot.IsIllusion, bot.HasModifier = no, yes, yes, no, no
    bot.WasRecentlyDamagedByAnyHero = function() return opts.controlHit end
    bot.IsSilenced = function() return opts.silenced end
    bot.GetLevel = function() return 10 end
    bot.GetGold = function() return opts.gold or 3000 end
    bot.GetNetWorth = function() return opts.worth or 10000 end
    bot.GetActiveMode, bot.GetStashValue = function() return 0 end, function() return 0 end
    bot.GetCourierValue = function() return next(courierSlots) and 500 or 0 end
    bot.GetLocation = function() return opts.distance or 1000 end
    bot.DistanceFromFountain = bot.GetLocation
    bot.GetAttackTarget, bot.GetTarget = function() return nil end, function() return nil end
    bot.DistanceFromSecretShop = function() return opts.heroAtSecret and 0 or 1000 end
    bot.SetNextItemPurchaseValue = function(_, value) bot.nextCost = value end
    bot.GetItemInSlot = function(_, slot) return slots[slot] end
    bot.FindItemSlot = function(_, name)
        for i, handle in pairs(slots) do if handle:GetName() == name then return i end end
        return -1
    end
    bot.ActionImmediate_PurchaseItem = function(_, name) return buy('hero', name) end
    courier.IsNull, courier.IsAlive = no, function() return not opts.dead end
    courier.DistanceFromSecretShop = function() return opts.courierAtSecret and 0 or 1000 end
    courier.GetItemInSlot = function(_, slot) return courierSlots[slot] end
    courier.ActionImmediate_PurchaseItem = function(_, name) return buy('courier', name) end
    bot.theCourier = courier

    local role = {supportExist = true, IsPvNMode = no, IsAllShadow = no}
    local j = {IsStaleARDMHero = function() return false, bot, bot:GetUnitName() end,
        GetUserHeroConfig = function() return opts.custom end, IsMeepoClone = no, IsInLaningPhase = no, IsModeTurbo = no,
        GetPosition = function() return 1 end, GetHP = function() return 1 end, GetMP = function() return 1 end,
        GetNearbyHeroes = empty, GetEnemiesNearLoc = empty, IsGoingOnSomeone = no, IsDefending = no, IsRetreating = no,
        IsCore = yes, IsDisabled = no, HasInvisCounterBuff = no, IsUnitWillGoInvisible = no, HasInvisibilityOrItem = no}
    local enemy = {IsNull = no, CanBeSeen = function() return opts.visible end,
        IsAlive = yes, IsHero = yes, IsInvisible = no, GetUnitName = function() return 'TestNuker' end}
    j.IsValidHero = function(unit) return unit ~= nil and unit:CanBeSeen() end
    j.IsSuspiciousIllusion = no
    j.GetEnemiesNearLoc = function() return opts.controlHit and opts.visible and {enemy} or {} end
    local modules = {
        ['bots/FunLib/aba_role'] = role, ['bots/FunLib/jmz_func'] = j, ['bots/FunLib/aba_global_overrides'] = {},
        ['bots/FunLib/utils'] = {GetLoneDruid = empty, IsBear = no, CountBackpackEmptySpace = function() return 3 end},
        ['bots/BotLib/hero_test'] = {sBuyList = opts.custom and opts.custom.PurchaseList or plan, sSellList = {}},
        ['bots/ts_libs/dota/index'] = {UnitType = {EnemyHeroes = 1}},
        ['bots/ts_libs/dota/heroes'] = {HeroName = setmetatable({}, {__index = function(_, name) return name end})},
        ['bots/FunLib/aba_hero_roles_map'] = {HeroRolesMap = {TestNuker = {nuker = 3}}, IsRanged = no},
        ['bots/Customize/general'] = {},
        ['bots/FunLib/aba_ward_utility'] = {GetPossibleSentryWardSpots = empty,
            GetAvailabeObserverWardSpots = empty, GetClosestObserverWardSpot = function() end, IsOtherWardClose = no,
            GetClosestSentryWardSpot = function() return opts.deward and {location = bot:GetLocation() + 250} or nil end},
    }
    local env = setmetatable({
        GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
        require = function(name) return assert(modules[name], name) end,
        dofile = function() return {sBuyList = opts.newPlan or plan, sSellList = {}} end,
        GetItemComponents = function(name) return recipes[name] or {} end,
        GetItemCost = function(name) return costs[name] or 200 end,
        GetGameMode = function() return opts.turbo and 23 or 1 end,
        GetUnitList = function(kind) assert(kind == 1); return {enemy} end,
        DotaTime = function() return now end, print = function() end,
        GetGameState = function() return 2 end, GAME_STATE_PRE_GAME = 1, GAME_STATE_GAME_IN_PROGRESS = 2,
        GetDroppedItemList = empty, IsItemPurchasedFromSecretShop = function(name) return secret[name] end,
        GetItemStockCount = function() return 10 end, PURCHASE_ITEM_SUCCESS = SUCCESS,
        PURCHASE_ITEM_OUT_OF_STOCK = OUT_OF_STOCK,
    }, {__index = _G})
    modules['bots/FunLib/aba_item'] = setfenv(assert(loadfile('bots/FunLib/aba_item.lua')), env)()
    j.Item = modules['bots/FunLib/aba_item']
    modules['bots/FunLib/lane_supply'] = setfenv(assert(loadfile('bots/FunLib/lane_supply.lua')), env)()
    modules['bots/FunLib/detection_purchase'] = setfenv(assert(loadfile('bots/FunLib/detection_purchase.lua')), env)()
    modules['bots/FunLib/advanced_item_strategy'] = setfenv(assert(loadfile('bots/FunLib/advanced_item_strategy.lua')), env)()
    setfenv(assert(loadfile('bots/item_purchase_generic.lua')), env)()
    local function tick()
        if bot.lastItemPurchaseFrameProcessTime == nil then bot.lastItemPurchaseFrameProcessTime = now - 1 end
        now = now + 1.1
        env.ItemPurchaseThink()
    end
    return tick, orders, slots, courierSlots, bot, env, j, function(seconds) now = now + seconds end
end

do
    local tick, orders, slots = fixture({'item_magic_wand'})
    slots[0], slots[1] = item('item_magic_stick'), item('item_branches')
    tick()
    assert(#orders == 1 and orders[1][2] == 'item_branches', 'one owned branch satisfies only one component')
    tick()
    assert(orders[2][2] == 'item_recipe_magic_wand', 'do not buy the second branch again')
    slots[0], slots[1], slots[2], slots[3] = item('item_magic_wand'), nil, nil, nil
    tick()
    assert(#orders == 2, 'the assembled item completes the queue')
end

do
    local opts = {courierAtSecret = true}
    local tick, orders, slots, carried, bot = fixture({'item_manta'}, opts)
    slots[9] = item('item_yasha')
    tick()
    assert(bot.SecretShop and #orders == 0 and bot.nextCost == 2800, 'the missing secret-shop part controls routing and cost')
    tick()
    assert(orders[1][1] == 'courier' and orders[1][2] == 'item_ultimate_orb')
    tick()
    assert(orders[2][1] == 'hero' and orders[2][2] == 'item_recipe_manta' and bot.nextCost == 900)
    assert(not bot.SecretShop and carried[0]:GetName() == 'item_ultimate_orb')
    tick()
    assert(#orders == 2, 'split inventory, stash and courier parts must not be repurchased')
end

do
    local opts = {visible = false, failure = FAILED}
    local tick, orders = fixture({'item_manta', 'item_black_king_bar'}, opts)
    tick()
    assert(#orders == 1 and orders[1][2] == 'item_blade_of_alacrity', 'an unseen threat cannot reorder or duplicate purchases')
    opts.visible = true
    tick()
    assert(#orders == 2 and orders[2][2] == 'item_blade_of_alacrity', 'do not interrupt an active target')
end

do
    local tick, orders = fixture({'item_manta', 'item_black_king_bar'}, {visible = true})
    tick()
    assert(orders[1][2] == 'item_ogre_axe', 'promote an already-planned adjacent counter against a visible threat')
    local tickPartial, partialOrders, slots = fixture({'item_manta', 'item_black_king_bar'}, {visible = true})
    slots[0] = item('item_yasha')
    slots[1] = item('item_ultimate_orb')
    tickPartial()
    assert(partialOrders[1][2] == 'item_recipe_manta', 'finish the partly assembled item before the counter')
end

do
    local tick, orders, _, _, _, env = fixture({'item_blink', 'item_black_king_bar'}, {visible = true})
    local baseCost = env.GetItemCost
    env.GetItemCost = function(name) return name == 'item_blink' and 2250 or baseCost(name) end
    tick()
    assert(orders[1][2] == 'item_blink', 'ordinary counter pressure should preserve the planned initiation item')
end

do
    local tick, orders, _, _, _, _, _, advance = fixture({'item_double_gauntlets'})
    tick()
    advance(1.1)
    tick()
    assert(#orders == 2 and orders[1][2] == 'item_gauntlets' and orders[2][2] == 'item_gauntlets',
        'the starting bundle buys the two planned Gauntlets')
end

do
    local opts = {visible = true, custom = {PurchaseList = {'item_manta', 'item_black_king_bar'}}}
    local tick, orders, _, _, bot = fixture({}, opts)
    bot.needPurchaseRebuild = true
    tick()
    assert(orders[1][2] == 'item_blade_of_alacrity', 'custom order survives visible threats and a position rebuild')
end

do
    local tick, orders = fixture({'item_manta', 'item_magic_wand', 'item_black_king_bar'}, {visible = true})
    tick()
    assert(orders[1][2] == 'item_ogre_axe', 'promote a planned counter across more than one queue position')
end

do
    local opts = {visible = true, silenced = true, controlHit = true, gold = 400}
    local tick, orders, slots, _, bot, _, _, advance = fixture({'item_manta'}, opts)
    slots[0] = item('item_boots')
    tick()
    assert(#orders == 0 and bot.currBuyingItemInPurchaseList == 'item_manta')
    advance(13)
    opts.gold = 3000
    tick()
    assert(orders[1][2] == 'item_ogre_axe' and bot.currBuyingItemInPurchaseList == 'item_black_king_bar',
        'repeated visible disables can add BKB while the unfinished target has no components')
end

do
    local tick, orders = fixture({'item_manta'}, {turbo = true, failure = FAILED})
    tick()
    assert(#orders == 1, 'Turbo logs a failed purchase without making another attempt')
end
print('PASS: purchase callback honors components, courier ownership, visible threats, and custom ordering')

local function sourceSection(path, first, after)
    local file = assert(io.open(path, 'r'))
    local source = file:read('*a')
    file:close()
    local start = assert(source:find(first, 1, true))
    local stop = assert(source:find(after, start + #first, true))
    return source:sub(start, stop - 1)
end

local strategy = 'bots/FunLib/jmz_func.lua'
local behavior = 'bots/ability_item_usage_generic.lua'
local sharedSafety = sourceSection(strategy, 'local function SafeLaneTower(', 'function J.GetLaningAttackDamage(')
    .. sourceSection(strategy, 'function J.HasHealingItem(', 'function J.ShouldGoFarmDuringLaning(')
local courierBehavior = sourceSection(behavior, 'local nCourierLastActionTime =', 'function X.GetNumStashItem(')
    .. sourceSection(behavior, 'function CourierUsageThink()', 'function AbilityLevelUpThink()')
local salveBehavior = sourceSection(behavior, 'X.ConsiderItemDesire["item_flask"] =', '-- Healing Lotus helper')
local tangoBehavior = sourceSection(behavior, 'X.ConsiderItemDesire["item_tango"] =', 'X.ConsiderItemDesire["item_tome_of_knowledge"]')
local detectionCoverage = sourceSection(strategy, 'local function HasTeamDetectionArea(', 'function J.IsClosestToDustLocation(')
local stickBehavior = sourceSection(behavior, 'local function ShouldSpendLaneStick(', 'X.ConsiderItemDesire["item_manta"] =')

local function laneFixture(o, plan)
    o.gold, o.time, o.lane = o.gold or 350, o.time or 160, true
    local tick, orders, slots, carried, bot, env, j, advance = fixture(plan or {}, o)
    local courier, commands = bot.theCourier, {}
    local tower = {GetLocation = function() return 6000 end}
    local creep = {GetLocation = function() return o.waveAt or 6000 end,
        GetBountyGoldMin = function() return 40 end}
    slots[15] = o.scrolls and item('item_tpscroll', o.scrolls) or nil
    if slots[15] and o.tpCooling then slots[15].IsFullyCastable = no end
    env.LANE_TOP, env.LANE_MID, env.LANE_BOT = 1, 2, 3
    env.TOWER_TOP_1, env.TOWER_MID_1, env.TOWER_BOT_1 = 1, 2, 3
    env.BOT_MODE_NONE, env.BOT_ACTION_DESIRE_NONE, env.BOT_ACTION_DESIRE_HIGH = 0, 0, 0.75
    env.COURIER_STATE_AT_BASE, env.COURIER_STATE_IDLE, env.COURIER_STATE_DELIVERING_ITEMS = 1, 2, 3
    env.COURIER_STATE_RETURNING_TO_BASE, env.COURIER_STATE_MOVING, env.COURIER_STATE_DEAD = 4, 5, 6
    env.COURIER_ACTION_TAKE_STASH_ITEMS, env.COURIER_ACTION_TRANSFER_ITEMS, env.COURIER_ACTION_RETURN_STASH_ITEMS = 7, 8, 9
    env.GetTower = function() return tower end
    env.GetCourierState = function() return o.state or env.COURIER_STATE_AT_BASE end
    env.GetItemStockCount = function(name) return name == o.soldOut and 0 or 10 end
    env.GetLaneFrontLocation = creep.GetLocation
    env.GetUnitToLocationDistance = function(unit, x) return math.abs(unit:GetLocation() - x) end
    env.GetUnitToUnitDistance = function(a, b) return math.abs(a:GetLocation() - b:GetLocation()) end
    j.IsInRange = function(a, b, radius) return env.GetUnitToUnitDistance(a, b) <= radius end
    j.IsRetreating, j.GetAlliesNearLoc, j.GetHeroesTargetingUnit = no, empty, empty
    j.IsCore = function(unit) return unit ~= bot or not o.support end
    j.GetPosition = function() return o.support and 4 or 1 end
    j.IsLaningUnderPressure = function() return o.dived end
    j.IsDoingRoshan, j.IsDoingTormentor = no, no
    j.IsInTeamFight = function() return o.fight end
    j.IsInLaningPhase = function() return not o.afterLane end
    j.IsValid = function(unit) return unit ~= nil end
    j.IsValidBuilding = function() return not o.lostTower end
    j.GetTeamFountain = function() return 0 end
    j.AdjustLocationWithOffsetTowardsFountain = function(x, distance) return x - distance end
    j.GetEnemiesNearLoc = empty
    j.GetLastSeenEnemiesNearLoc = function(x)
        return (o.routeThreat or o.routeThreatAt)
            and math.abs(x - (o.routeThreatAt or 3000)) < 200 and {true} or {}
    end
    j.GetHP = function(unit) return unit:GetHealth() / unit:GetMaxHealth() end
    j.GetMP = function(unit) return unit:GetMana() / unit:GetMaxMana() end
    j.GetLanePartner = function() return o.partner end
    j.Role = {fLastGiveTangoTime = -90}
    bot.GetAssignedLane = function() return o.partner and env.LANE_BOT or env.LANE_MID end
    bot.GetTeam, bot.GetPlayerID, courier.GetPlayerID = function() return 2 end, function() return 4 end, function() return 4 end
    bot.IsNull, bot.GetNearbyTowers, bot.GetNearbyHeroes = no, empty, empty
    bot.GetLocation = function() return o.distance or 6000 end
    bot.DistanceFromFountain = bot.GetLocation
    bot.GetCurrentMovementSpeed = function() return 300 end
    bot.GetAttackRange = function() return 550 end
    bot.GetHealth = function() return (o.hp or 0.42) * 800 end
    bot.GetMaxHealth, bot.GetHealthRegen = function() return 800 end, function() return o.hpRegen or 1 end
    bot.OriginalGetMaxHealth, bot.OriginalGetHealth = bot.GetMaxHealth, bot.GetHealth
    bot.GetMana, bot.GetManaRegen = function() return o.mana or 300 end, function() return o.mpRegen or 1 end
    bot.GetMaxMana = function() return 400 end
    bot.GetAbilityInSlot = function(_, index)
        if index == 0 and o.spell then
            return {IsNull = no, IsTrained = yes, IsActivated = function() return not o.inactive end,
                IsHidden = no, IsPassive = no, IsUltimate = function() return o.ultimate end,
                GetCooldownTimeRemaining = function() return o.cooldown or 0 end, GetManaCost = function() return 120 end}
        end
    end
    bot.GetLastHits = function() return o.lastHits or 16 end
    bot.GetNearbyLaneCreeps = function(_, radius, enemy)
        local wave = {}
        local count = enemy and (o.creeps or 4) or (o.alliedCreeps or 0)
        if j.IsInRange(bot, creep, radius) then for i = 1, count do wave[i] = creep end end
        return wave
    end
    bot.GetNearbyTrees = function() return o.noTrees and {} or {1} end
    bot.WasRecentlyDamagedByAnyHero = function(_, seconds) return o.hitAgo ~= nil and o.hitAgo < seconds end
    bot.WasRecentlyDamagedByTower = function() return o.towerHit end
    bot.HasModifier = function(_, modifier) return modifier == o.modifier end
    bot.ActionImmediate_SwapItems = function(_, a, b) slots[a], slots[b] = slots[b], slots[a] end
    bot.ActionImmediate_Courier = function(_, target, command)
        assert(target == courier, 'only the personal courier receives an order')
        commands[#commands + 1] = command
    end
    courier.GetHealth, courier.GetMaxHealth = function() return 100 end, function() return 100 end
    courier.IsAlive = function() return not o.dead end
    courier.GetLocation = function() return o.courierAt or 0 end
    courier.DistanceFromFountain = courier.GetLocation
    courier.GetCurrentMovementSpeed = function() return o.speed or 300 end
    courier.FindItemSlot = function(_, name)
        for slot, handle in pairs(carried) do if handle:GetName() == name then return slot end end
        return -1
    end
    courier.GetAbilityByName = function() return nil end
    env.GetNumCouriers = function() return 3 end
    env.GetCourier = function(index) if index == 2 then return courier end end
    env.bot, env.J, env.RefreshBotHandle, j.SetReportMotive = bot, j, no, no
    env.X = {ConsiderItemDesire = {}, IsInvFull = no, IsEnemyHeroAroundSecretShop = no,
        IsCourierTargetedByUnit = function() return o.courierTargeted end, GetNumStashItem = function()
            local count = 0
            for i = 9, 14 do if slots[i] then count = count + 1 end end
            return count
        end}
    env.hNearbyEnemyHeroList = {}
    setfenv(assert(loadstring(sharedSafety .. courierBehavior .. salveBehavior .. stickBehavior)), env)()
    bot.lastCourierFrameProcessTime = 0
    return {tick = tick, orders = orders, slots = slots, carried = carried, bot = bot, env = env, j = j,
        tower = tower, commands = commands, advance = advance}
end

do
    local o = {routeThreat = true, afterLane = true}
    local s = laneFixture(o)
    o.state = s.env.COURIER_STATE_DELIVERING_ITEMS
    s.env.CourierUsageThink()
    assert(s.commands[1] == s.env.COURIER_ACTION_RETURN_STASH_ITEMS,
        'recall ordinary cargo before it reaches a newly exposed midpoint')
    o.routeThreat = false
    s.advance(6)
    s.env.CourierUsageThink()
    assert(#s.commands == 1, 'leave an ordinary delivery going once the route is clear')
end

-- Drive the normal purchase, courier and item-use callbacks through one lane reset decision.
do
    local o = {}
    local s = laneFixture(o)
    s.bot.theCourier = nil
    s.env.CourierUsageThink()
    s.tick()
    assert(#s.orders == 1 and s.orders[1][2] == 'item_flask' and o.gold == 240)
    assert(s.j.GetLaningHoldTower(s.bot) == nil, 'an unconfirmed receipt cannot suppress a reset')
    s.tick()
    assert(s.j.GetLaningHoldTower(s.bot) == s.tower, 'wait under the safe T1 after confirming the stash')
    s.bot.currBuyingBasicItemList, s.bot.currBuyingBasicItem = {'item_boots'}, 'item_boots'
    s.slots[10] = item('item_blade_of_alacrity')
    s.env.CourierUsageThink()
    assert(s.commands[1] == s.env.COURIER_ACTION_TAKE_STASH_ITEMS)
    s.carried[0], s.slots[9] = s.slots[9], nil
    s.advance(2.5)
    s.tick()
    s.env.CourierUsageThink()
    assert(s.commands[2] == s.env.COURIER_ACTION_TRANSFER_ITEMS, 'deliver even with another component still in the stash')
    o.state = s.env.COURIER_STATE_DELIVERING_ITEMS
    s.advance(2.5)
    s.tick()
    s.env.CourierUsageThink()
    assert(#s.commands == 2 and #s.orders == 1, 'an ongoing delivery is not reissued or repurchased')
    s.slots[6], s.carried[0] = s.carried[0], nil
    s.tick()
    assert(s.slots[0] and s.slots[0]:GetName() == 'item_flask' and s.j.HasHealingItem(s.bot))
    local desire, target = s.env.X.ConsiderItemDesire.item_flask(s.slots[0])
    assert(desire == s.env.BOT_ACTION_DESIRE_HIGH and target == s.bot, 'use the delivered salve with less than 500 HP missing')
    o.towerHit = true
    assert(s.env.X.ConsiderItemDesire.item_flask(s.slots[0]) == 0, 'do not break a salve on tower damage')
    s.slots[0], o.towerHit = nil, false
    s.tick()
    assert(#s.orders == 1 and s.j.GetLaningHoldTower(s.bot) == nil, 'consuming one salve cannot immediately trigger another order')
end

local function expectPurchase(options, expected, reason, plan)
    local s = laneFixture(options, plan)
    s.tick()
    local first = s.orders[1]
    assert((first and first[2]) == expected, reason)
    if not expected then assert(s.bot.ohaLaneSupply == nil, reason .. ' (no pending delivery)') end
    return s
end

expectPurchase({creeps = 1}, nil, 'one creep cannot pay for an extra salve')
expectPurchase({time = 600, lastHits = 12, scrolls = 2, tpCooling = true}, nil,
    'a core with 12 last hits at ten minutes cannot budget the full value of this wave')
expectPurchase({time = 600, lastHits = 40, scrolls = 2, tpCooling = true}, 'item_tango',
    'with forty last hits at the same time, the same wave covers tangos but not a salve')
expectPurchase({creeps = 0, alliedCreeps = 4}, 'item_flask', 'a visible allied wave at the lane front can signal the next wave')
expectPurchase({creeps = 0, alliedCreeps = 4, waveAt = 7400}, nil, 'an inaccessible wave is not income')
expectPurchase({speed = 95}, nil, 'walking to the fountain and back is faster')
expectPurchase({scrolls = 2}, nil, 'an available spare TP makes the fountain round trip cheaper')
expectPurchase({scrolls = 1}, 'item_flask', 'using the last ready TP also has a replacement cost')
expectPurchase({gold = 485}, nil, 'preserve gold for imminent boots', {'item_boots'})
expectPurchase({gold = 510}, 'item_boots', 'buy the ready equipment first', {'item_boots'})
expectPurchase({gold = 650}, 'item_flask', 'surplus gold can cover both', {'item_boots'})
expectPurchase({gold = 450}, 'item_tango', 'respect the already planned consumable', {'item_tango'})
expectPurchase({dead = true}, nil, 'no courier is available')
expectPurchase({routeThreat = true}, nil, 'avoid a threatened courier route')
expectPurchase({routeThreatAt = 4500}, nil, 'avoid an enemy near the last quarter of the delivery')
expectPurchase({courierAt = 3600, routeThreatAt = 900}, nil, 'also check the courier leg to collect the stash')
expectPurchase({dived = true}, nil, 'the hero has to retreat')
expectPurchase({fight = true}, nil, 'waiting for a parcel must not displace a teamfight')
expectPurchase({hp = 0.28}, nil, 'a critically injured hero cannot wait')
expectPurchase({hp = 0.42, hpRegen = 12}, nil, 'natural healing will cover the deficit before arrival')
expectPurchase({hp = 0.60}, nil, 'a quiet lane and moderate damage are insufficient')
expectPurchase({hp = 0.60, hitAgo = 5}, 'item_tango', 'recover from a recent lane trade')
expectPurchase({hp = 0.60, hitAgo = 1, modifier = 'modifier_warlock_shadow_word'}, 'item_tango',
    'the shared Shadow Word modifier does not establish that the hero is already being healed')
expectPurchase({hp = 0.42, hitAgo = 1, modifier = 'modifier_warlock_shadow_word'}, nil,
    'an unsafe wounded hero still should not wait for a delivery')
expectPurchase({hp = 0.60, hitAgo = 5, noTrees = true}, nil, 'do not buy unusable tangos')
expectPurchase({soldOut = 'item_flask'}, 'item_tango', 'use available stock')
expectPurchase({hp = 0.80, mana = 40}, nil, 'low mana alone does not justify buying clarity')
expectPurchase({hp = 0.80, mana = 40, spell = true, ultimate = true}, nil, 'saving up for a quiet-lane ultimate is insufficient')
expectPurchase({hp = 0.80, mana = 40, spell = true}, 'item_clarity', 'an imminent cast is still unaffordable at delivery')
expectPurchase({hp = 0.60, mana = 40, spell = true}, 'item_clarity', 'in a quiet lane, a small health deficit does not hide a real mana deficit')
expectPurchase({hp = 0.80, mana = 40, spell = true, cooldown = 17}, 'item_clarity', 'budget for a spell coming off cooldown during delivery')
expectPurchase({hp = 0.80, mana = 40, spell = true, inactive = true}, nil, 'an inactive spell cannot justify spending')
expectPurchase({hp = 0.80, mana = 40, spell = true, hitAgo = 2}, nil, 'recent enemy damage would interrupt clarity')
expectPurchase({hp = 0.80, mana = 40, spell = true, mpRegen = 4}, nil, 'natural mana regeneration funds the next cast')
expectPurchase({mana = 25, spell = true}, nil, 'buying a salve alone would still require a reset')

do
    local opts = {hp = 0.67, hitAgo = 5}
    local s = laneFixture(opts)
    s.slots[0] = item('item_tango', 1)
    s.tick()
    assert(#s.orders == 1 and s.orders[1][2] == 'item_tango' and s.bot.ohaLaneSupply.proactive,
        'one remaining Tango in an active lane can justify one affordable pack')
    s.slots[9] = item('item_tango', 3)
    s.tick()
    assert(s.j.GetLaningHoldTower(s.bot) == nil, 'the courier can come without forcing the hero off the wave')
    s.env.CourierUsageThink()
    assert(s.commands[1] == s.env.COURIER_ACTION_TAKE_STASH_ITEMS,
        'identify stash Tango even when an item with the same name is still in the active inventory')
    opts.hitAgo = 15
    s.advance(6)
    s.tick()
    assert(#s.orders == 1 and s.bot.ohaLaneSupply.proactive,
        'finish safe replenishment after the last attack ages out without buying another pack')
    s.slots[9], s.slots[0] = nil, item('item_tango', 4)
    s.tick()
    assert(s.bot.ohaLaneSupply == nil and #s.orders == 1, 'clear the order after replenishment merges into the old stack')
    for _, options in ipairs({{hp=0.67, hitAgo=5, creeps=1}, {hp=0.67}, {hp=0.67, hitAgo=5, gold=485}}) do
        local blocked = laneFixture(options, options.gold and {'item_boots'} or nil)
        blocked.slots[0] = item('item_tango', 1)
        blocked.tick()
        assert(#blocked.orders == 0, 'wait when the wave cannot cover cost, pressure is quiet, or boots are imminent')
    end
end

do
    local s = laneFixture({hp = 0.78, hitAgo = 1})
    local env, j = s.env, s.j
    env.aetherRange, env.nMode, env.BOT_MODE_LANING = 0, 1, 1
    env.GetTreeLocation = function() return 6100 end
    env.IsLocationVisible, env.IsLocationPassable = yes, yes
    j.IsWithoutTarget, j.HasPendingLaningLastHit, j.IsFinishingLaningAttack = no, no, no
    j.IsValidBuilding = function(unit) return unit ~= nil end
    j.GetNearbyHeroes = empty
    setfenv(assert(loadstring(tangoBehavior)), env)()
    local tango = s.env.X.ConsiderItemDesire.item_tango_single
    local charges = item('item_tango', 3)
    local desire, tree = tango(charges)
    assert(desire > 0 and tree == 1, 'begin healing from a reachable tree while the lane target is still set')
    j.HasPendingLaningLastHit = yes
    assert(tango(charges) == 0, 'do not interrupt a last hit to eat the tree')
    j.HasPendingLaningLastHit = no
    local threat = {GetLocation = function() return 6360 end, GetAttackRange = function() return 490 end}
    j.IsValidHero = function(unit) return unit == threat end
    j.GetNearbyHeroes = function() return {threat} end
    assert(tango(charges) == 0, 'do not move closer to a visible threat for a tree')
end

do
    local o = {hp = 0.60, hitAgo = 5}
    local s = laneFixture(o)
    o.partner = {IsBot = yes, IsAlive = yes, IsNull = no, GetLocation = function() return 6100 end,
        GetHealth = function() return 790 end, GetMaxHealth = function() return 800 end,
        GetItemInSlot = function(_, slot) return ({[0] = item('item_bottle', 1), [1] = item('item_tango', 2)})[slot] end,
        WasRecentlyDamagedByAnyHero = no, GetNearbyHeroes = empty, HasModifier = no,
        DistanceFromFountain = function() return 6100 end}
    o.support = true
    s.tick()
    s.advance(6)
    s.tick()
    assert(#s.orders == 0, 'a support does not value the healthy farming core’s last hits as its own')
    o.support = false
    -- Reverse the roles, with the tango still in the slot after a non-shareable bottle.
    s.j.IsCore = function(unit) return unit == s.bot end
    s.bot.ohaLaneShareSince = nil
    s.tick()
    assert(#s.orders == 0, 'give the healthy partner time to share')
    s.slots[0] = item('item_tango_single', 1)
    s.advance(7)
    s.tick()
    assert(#s.orders == 0, 'a shared tango avoids a purchase')
end

for _, name in ipairs({'item_magic_stick', 'item_magic_wand'}) do
    local s = laneFixture({})
    s.slots[0] = item(name, 6)
    s.tick()
    assert(#s.orders == 0 and s.env.X.ConsiderItemDesire[name](s.slots[0]) == s.env.BOT_ACTION_DESIRE_HIGH,
        'use existing charges to recover safely instead of paying for a salve')
    local saving = laneFixture({hp = 0.34})
    saving.slots[0] = item(name, 6)
    saving.tick()
    assert(saving.orders[1][2] == 'item_flask', 'six charges cannot cover a much larger deficit')
end

do
    local o = {gold = 10, creeps = 0}
    local s = laneFixture(o)
    s.slots[9] = item('item_flask', 1)
    s.tick()
    assert(#s.orders == 0 and s.j.GetLaningHoldTower(s.bot) == s.tower, 'send prepaid supplies even when a new sale would not pay')
    o.dead = true
    assert(s.j.GetLaningHoldTower(s.bot) == nil, 'a courier death immediately releases the hold')
    o.dead, o.dived = false, true
    assert(s.j.GetLaningHoldTower(s.bot) == nil, 'diving enemies immediately release the hold')
    o.dived, o.state, o.routeThreat = false, s.env.COURIER_STATE_DELIVERING_ITEMS, true
    s.carried[0], s.slots[9] = s.slots[9], nil
    s.env.CourierUsageThink()
    assert(s.commands[1] == s.env.COURIER_ACTION_RETURN_STASH_ITEMS and s.j.GetLaningHoldTower(s.bot) == nil)
    o.routeThreat = false
    s.advance(50)
    s.tick()
    assert(s.j.GetLaningHoldTower(s.bot) == nil, 'an overdue parcel cannot keep a hero in lane indefinitely')
end

do
    local o = {failure = FAILED}
    local s = laneFixture(o)
    s.slots[0] = item('item_bottle', 0)
    assert(not s.j.HasHealingItem(s.bot), 'an empty bottle cannot heal the hero')
    s.tick()
    assert(#s.orders == 1 and s.bot.ohaLaneSupply == nil and s.j.GetLaningHoldTower(s.bot) == nil)
    s.tick()
    assert(#s.orders == 1, 'rate-limit failed purchases')
    o.failure = nil
    s.advance(4)
    s.tick()
    assert(#s.orders == 2 and s.bot.ohaLaneSupply.item == 'item_flask', 'retry a real purchase failure')
end
print('PASS: safe lane supply purchases, delivery, use, and fountain decisions')

local function detectionFixture(options, plan)
    local o = options
    o.detection, o.gold, o.time = true, o.gold or 700, o.time or 150
    local tick, orders, slots, cargo, bot, env, j, advance = fixture(plan or {}, o)
    local allyItems = {}
    local ally = {
        IsIllusion = no, IsBot = yes, IsAlive = yes, GetTeam = function() return 2 end,
        GetLocation = function() return bot:GetLocation() + 40 end,
        GetItemInSlot = function(_, slot) return allyItems[slot] end,
        GetGold = function() return o.allyGold or 0 end, GetNetWorth = function() return 2400 end,
        purchaseListInReverseOrder = {}, DistanceFromFountain = function() return 400 end,
    }
    local enemy = {
        CanBeSeen = function() return not o.hidden end, IsInvisible = function() return o.concealed end,
        GetLocation = function() return bot:GetLocation() + 430 end, GetAttackRange = function() return 450 end,
        GetAttackTarget = function()
            if o.threatensAlly then return ally end
            if o.attacking then return bot end
        end,
    }
    env.GetUnitToLocationDistance = function(unit, location) return math.abs(unit:GetLocation() - location) end
    env.GetItemStockCount = function(name) return name == 'item_ward_sentry' and (o.stock or 2) or 0 end
    j.GetDistance = function(a, b) return math.abs(a - b) end
    j.IsInRange = function(a, b, radius) return j.GetDistance(a:GetLocation(), b:GetLocation()) <= radius end
    j.IsValidHero = function(unit) return unit ~= nil end
    j.GetPosition = function(unit) return unit == ally and (o.allyPosition or 1) or (o.position or 4) end
    j.IsCore = function(unit) return j.GetPosition(unit) <= 3 end
    j.GetHP = function(unit) return unit == bot and (o.hp or 1) or 1 end
    j.IsDefending = function() return o.holding end
    j.IsGoingOnSomeone = function() return o.pursuing end
    j.GetEnemiesNearLoc = function() return o.threat and {enemy} or {} end
    j.GetAlliesNearLoc = function() return o.withAlly and {bot, ally} or {bot} end
    j.GetHeroesTargetingUnit = function() return o.teamFocus and {ally} or {} end
    j.HasInvisibilityOrItem = function() return o.threat end
    j.IsUnitWillGoInvisible = function() return o.fading end
    j.HasInvisCounterBuff = function() return o.marked end
    j.Site = {IsLocationHaveTrueSight = function() return o.warded end, SentryTrueSightRange = 1050}
    ally.FindItemSlot = function(_, name)
        for slot, handle in pairs(allyItems) do
            if handle:GetName() == name then return slot end
        end
        return -1
    end
    bot.GetTeam = ally.GetTeam
    bot.GetAttackTarget = function() return o.focusing and enemy or nil end
    bot.WasRecentlyDamagedByHero = function() return o.recentlyHit end
    bot.WasRecentlyDamagedByAnyHero = bot.WasRecentlyDamagedByHero
    bot.ActionImmediate_SwapItems = function(_, a, b) slots[a], slots[b] = slots[b], slots[a] end
    env.J, env.GetTeam = j, bot.GetTeam
    env.GetTeamPlayers = function(team) return team == 2 and {1, 2} or {} end
    env.GetTeamMember = function(slot) return slot == 1 and bot or ally end
    setfenv(assert(loadstring(detectionCoverage)), env)()
    return {tick = tick, orders = orders, slots = slots, cargo = cargo, bot = bot, advance = advance,
        ally = ally, allyItems = allyItems, enemy = enemy, env = env, j = j}
end

local function expectDetection(options, expected, reason, plan)
    local s = detectionFixture(options, plan)
    s.tick()
    local first = s.orders[1]
    assert((first and first[2]) == expected, reason)
    return s
end

expectDetection({time = 800}, nil, 'an idle support does not buy detection by the clock')
expectDetection({threat = true, hidden = true, fading = true, attacking = true}, nil,
    'hidden inventory or buffs cannot trigger spending')
expectDetection({threat = true, pursuing = true, focusing = true, fading = true}, 'item_dust',
    'an early Glimmer fade on the team’s target justifies one counter')
expectDetection({threat = true, holding = true}, 'item_ward_sentry', 'protect the threatened fixed position')
expectDetection({threat = true, holding = true, warded = true}, nil, 'existing true sight covers the threatened point')
expectDetection({threat = true, holding = true, stock = 0}, nil, 'an unavailable sentry does not waste purchase attempts')
expectDetection({threat = true, holding = true, hp = 0.05, recentlyHit = true}, nil, 'a dying support does not spend on detection')
expectDetection({threat = true, concealed = true, attacking = true, dead = true}, nil,
    'do not buy optional dust away from base when delivery is unavailable')
expectDetection({threat = true, concealed = true, attacking = true, gold = 480}, nil,
    'save when boots are within 60 gold', {'item_boots'})
expectDetection({threat = true, concealed = true, attacking = true, gold = 510}, 'item_boots',
    'finish affordable boots before purchasing even high-priority dust', {'item_boots'})
expectDetection({threat = true, concealed = true, attacking = true, gold = 4040}, 'item_ogre_axe',
    'protect the cost of all remaining BKB components', {'item_black_king_bar'})
expectDetection({threat = true, concealed = true, attacking = true, gold = 4100}, 'item_dust',
    'true surplus gold can fund both dust and all remaining BKB components', {'item_black_king_bar'})
expectDetection({threat = true, concealed = true, attacking = true, gold = 950}, 'item_gem',
    'respect an explicitly configured gem and leave its gold available', {'item_gem'})
expectDetection({position = 1, threat = true, pursuing = true}, nil, 'a core does not buy for possession alone')
expectDetection({position = 1, threat = true, concealed = true, withAlly = true, threatensAlly = true}, 'item_dust',
    'a core may cover a nearby teammate from a confirmed threat')
expectDetection({position = 1, threat = true, recentlyHit = true}, 'item_dust',
    'a visible attacker can remain a priority after the ambush removes invisibility')
expectDetection({position = 1, threat = true, fading = true, teamFocus = true}, 'item_dust',
    'an ally’s focus target can be more important than the bot’s own target')
expectDetection({position = 1, threat = true, concealed = true, attacking = true, withAlly = true,
    allyPosition = 5, allyGold = 100}, nil, 'an eligible nearby support buys instead of the core')
expectDetection({position = 1, threat = true, concealed = true, attacking = true, withAlly = true,
    allyPosition = 5, allyGold = 60}, 'item_dust', 'a nearby support without the budget does not prevent the fallback')

do
    local o = {position = 4, threat = true, pursuing = true, worth = 5000}
    local s = expectDetection(o, 'item_dust', 'a known local threat can justify one initial dust')
    s.slots[0] = nil
    s.advance(15)
    o.concealed, o.attacking = true, true
    s.tick()
    assert(#s.orders == 1, 'even a critical target has a minimum restock interval')
    o.concealed, o.attacking = false, false
    s.advance(27)
    s.tick()
    assert(#s.orders == 1, 'inventory evidence alone does not justify replenishment after forty seconds')
    o.concealed, o.attacking = true, true
    s.advance(2)
    s.tick()
    assert(#s.orders == 2 and s.orders[2][2] == 'item_dust', 'a confirmed attack and concealment get the shorter interval')
    s.slots[0] = nil
    s.advance(100)
    s.tick()
    assert(#s.orders == 2, 'even recurring priority threats respect the spending ceiling')
end

do
    local o = {worth = 1100, threat = true, concealed = true, attacking = true}
    local s = expectDetection(o, 'item_dust', 'a poor support with spare gold can still buy one useful counter')
    s.slots[0] = nil
    o.holding, o.concealed, o.attacking = true, false, false
    s.advance(100)
    s.tick()
    assert(#s.orders == 1, 'the same budget covers both sentries and dust, including when changing type')
    s.advance(82)
    s.tick()
    assert(#s.orders == 2 and s.orders[2][2] == 'item_ward_sentry', 'previous spending expires after three minutes')
end

do
    local s = detectionFixture({threat = true, fading = true, attacking = true, withAlly = true})
    s.allyItems[0] = item('item_dust', 1)
    s.tick()
    assert(#s.orders == 0, 'a nearby ally with usable dust covers the engagement')
    s.allyItems[0], s.allyItems[10] = nil, item('item_dust', 1)
    s.ally.theCourier = {IsNull = no, IsAlive = yes}
    s.advance(3)
    s.tick()
    assert(#s.orders == 0, 'inbound detection already funded by a nearby ally is enough')
    s.allyItems[10], s.ally.theCourier = nil, nil
    local gem = item('item_gem')
    gem.GetSpecialValueInt = function(_, key) assert(key == 'radius'); return 900 end
    s.allyItems[0] = gem
    s.advance(3)
    s.tick()
    assert(#s.orders == 0, 'a gem carrier provides local true sight without purchasing a consumable')
    s.allyItems[0] = nil
    s.cargo[0] = item('item_dust', 1)
    s.advance(3)
    s.tick()
    assert(#s.orders == 0, 'avoid duplicating a personal courier’s dust')
    s.cargo[0] = gem
    s.advance(3)
    s.tick()
    assert(#s.orders == 0, 'avoid buying another counter while a gem is being delivered')
end

do
    local s = detectionFixture({deward = true, position = 5})
    local combined = item('item_ward_dispenser', 1)
    combined.GetSecondaryCharges = function() return 1 end
    s.slots[6] = combined
    s.tick()
    assert(#s.orders == 0 and s.slots[0] == combined, 'use an already owned sentry in the combined ward')
    combined.GetSecondaryCharges = function() return 0 end
    s.advance(3)
    s.tick()
    assert(#s.orders == 1 and s.orders[1][2] == 'item_ward_sentry', 'a useful deward still justifies a sentry')
end

do
    local o = {threat = true, holding = true, stashPurchases = true}
    local s = expectDetection(o, 'item_ward_sentry', 'buy the defensive sentry into the stash')
    s.advance(90)
    s.tick()
    assert(#s.orders == 1 and s.slots[9] ~= nil, 'do not replace a sentry that has yet to be delivered')

    local sentryUse = sourceSection(behavior, 'local function ConsiderCombatSentry(', '--GG树')
    s.env.bot, s.env.J, s.env.X, s.env.aetherRange = s.bot, s.j, {ConsiderItemDesire = {}}, 0
    s.env.BOT_ACTION_DESIRE_NONE, s.env.BOT_ACTION_DESIRE_HIGH = 0, 0.8
    s.j.GetUnitTowardDistanceLocation = function(_, target) return target:GetLocation() end
    setfenv(assert(loadstring(sentryUse)), s.env)()
    local combined = item('item_ward_dispenser', 1)
    combined.GetSecondaryCharges = function() return 1 end
    combined.GetToggleState = function() return not o.sentrySelected end
    local consider = s.env.X.ConsiderItemDesire.item_ward_dispenser
    local desire, target, kind = consider(combined)
    assert(desire == 0.8 and target == s.bot and kind == 'unit', 'select the sentry charge on defense')
    o.sentrySelected = true
    desire, target, kind = consider(combined)
    assert(desire == 0.8 and target == s.enemy:GetLocation() and kind == 'ground', 'place that sentry on defense')
    o.warded = true
    assert(consider(combined) == 0, 'avoid duplicating an existing ward at the fight')
end

do
    local s = detectionFixture({deward = true, position = 5})
    local env, j, orders = s.env, s.j, {}
    local ward = item('item_ward_dispenser', 1)
    local observer = true
    ward.GetSecondaryCharges = function() return 1 end
    ward.GetToggleState = function() return observer end
    s.slots[0] = ward
    j.Utils = {IsTeamPushingSecondTierOrHighGround = no, CountEnemyHeroesNear = function() return 0 end,
        IsBotThinkingMeaningfulAction = no}
    j.CanNotUseAction = no
    j.CanCastAbility = function(ability) return ability and ability:IsFullyCastable() end
    env.GetTeam = s.bot.GetTeam
    env.GetOpposingTeam = function() return 3 end
    env.GetAncient = function() return {GetLocation = function() return 0 end} end
    env.RandomVector = function() return 0 end
    env.RemapValClamped = function(_, _, _, _, result) return result end
    env.BOT_MODE_NONE, env.BOT_MODE_DESIRE_NONE, env.BOT_MODE_DESIRE_VERYHIGH = 0, 0, 0.8
    env.BOT_MODE_RUNE, env.BOT_MODE_DEFEND_ALLY = 1, 2
    s.bot.GetActiveModeDesire = function() return 0 end
    s.bot.GetNearbyHeroes = empty
    s.bot.Action_UseAbilityOnEntity = function(_, _, target)
        assert(target == s.bot)
        observer = false
        orders[#orders + 1] = 'switch'
    end
    s.bot.Action_UseAbilityOnLocation = function(_, _, loc)
        assert(not observer and loc == s.bot:GetLocation() + 250)
        orders[#orders + 1] = 'sentry'
    end
    setfenv(assert(loadfile('bots/mode_ward_generic.lua')), env)()
    assert(env.GetDesire() == 0.8)
    env.Think()
    assert(orders[1] == 'switch', 'a deward assignment switches the combined item to sentry')
    assert(env.GetDesire() == 0.8)
    s.j.RecordSentryOrder(s.ally, s.bot:GetLocation() + 250)
    env.Think()
    assert(#orders == 1, 'another bot placed a sentry after the warding desire was computed')
    s.advance(0.7)
    -- Even a fresh dust zone does not reveal wards for dewarding.
    s.ally.ohaDustCoverage = {location = s.bot:GetLocation() + 250, radius = 1050, untilTime = env.DotaTime() + 12}
    assert(env.GetDesire() == 0.8, 'retry after an unconfirmed placement expires')
    env.Think()
    assert(orders[2] == 'sentry', 'the normal ward callback spends the correct charge')
    assert(env.GetDesire() == 0, 'the accepted ward placement prevents an immediate repeat')
end
print('PASS: detection purchases account for real threats, local coverage, equipment, and the spending budget')
