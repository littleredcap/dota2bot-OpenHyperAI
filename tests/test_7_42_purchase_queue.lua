local function no() return false end
local function yes() return true end
local function empty() return {} end
local SUCCESS, FAILED, OUT_OF_STOCK = 1, 2, 3

local function item(name, charges)
    return {GetName = function() return name end, GetCurrentCharges = function() return charges or 0 end, IsNull = no}
end

local function fixture(plan, opts)
    opts = opts or {}
    local now, orders = 800, {}
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
        item_magic_wand = 450, item_tpscroll = 100, item_dust = 80}
    local secret = {item_ultimate_orb = true}
    local bot, courier = {}, {}
    local function buy(from, name)
        orders[#orders + 1] = {from, name}
        if opts.failure then return opts.failure end
        local inventory = from == 'courier' and courierSlots or slots
        for i = 0, 14 do
            if inventory[i] == nil then inventory[i] = item(name); break end
        end
        return SUCCESS
    end

    bot.GetUnitName = function() return 'npc_dota_hero_test' end
    bot.IsInvulnerable, bot.IsHero, bot.IsAlive, bot.IsIllusion, bot.HasModifier = no, yes, yes, no, no
    bot.WasRecentlyDamagedByAnyHero = no
    bot.GetLevel = function() return 10 end
    bot.GetGold = function() return opts.gold or 3000 end
    bot.GetNetWorth = function() return 10000 end
    bot.GetActiveMode, bot.GetStashValue = function() return 0 end, function() return 0 end
    bot.GetCourierValue = function() return next(courierSlots) and 500 or 0 end
    bot.DistanceFromFountain = function() return 1000 end
    bot.DistanceFromSecretShop = function() return opts.heroAtSecret and 0 or 1000 end
    bot.SetNextItemPurchaseValue = function(_, value) bot.nextCost = value end
    bot.GetItemInSlot = function(_, slot) return slots[slot] end
    bot.FindItemSlot = function(_, name)
        for i, handle in pairs(slots) do if handle:GetName() == name then return i end end
        return -1
    end
    bot.ActionImmediate_PurchaseItem = function(_, name) return buy('hero', name) end
    courier.IsNull = no
    courier.DistanceFromSecretShop = function() return opts.courierAtSecret and 0 or 1000 end
    courier.GetItemInSlot = function(_, slot) return courierSlots[slot] end
    courier.ActionImmediate_PurchaseItem = function(_, name) return buy('courier', name) end
    bot.theCourier = courier

    local role = {supportExist = true, IsPvNMode = no, IsAllShadow = no}
    local j = {IsStaleARDMHero = function() return false, bot, bot:GetUnitName() end,
        GetUserHeroConfig = function() return opts.custom end, IsMeepoClone = no, IsInLaningPhase = no,
        GetPosition = function() return 1 end, GetHP = function() return 1 end, GetMP = function() return 1 end,
        GetNearbyHeroes = empty,
        IsCore = yes}
    local enemy = {IsNull = no, CanBeSeen = function() return opts.visible end,
        IsAlive = yes, IsHero = yes, IsIllusion = no, GetUnitName = function() return 'TestNuker' end}
    local modules = {
        ['bots/FunLib/aba_role'] = role, ['bots/FunLib/jmz_func'] = j, ['bots/FunLib/aba_global_overrides'] = {},
        ['bots/FunLib/utils'] = {GetLoneDruid = empty, IsBear = no, CountBackpackEmptySpace = function() return 3 end},
        ['bots/BotLib/hero_test'] = {sBuyList = opts.custom and opts.custom.PurchaseList or plan, sSellList = {}},
        ['bots/ts_libs/dota/index'] = {UnitType = {EnemyHeroes = 1}},
        ['bots/ts_libs/dota/heroes'] = {HeroName = setmetatable({}, {__index = function(_, name) return name end})},
        ['bots/FunLib/aba_hero_roles_map'] = {HeroRolesMap = {TestNuker = {nuker = 3}}, IsRanged = no},
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
    modules['bots/FunLib/advanced_item_strategy'] = setfenv(assert(loadfile('bots/FunLib/advanced_item_strategy.lua')), env)()
    setfenv(assert(loadfile('bots/item_purchase_generic.lua')), env)()
    local function tick()
        if bot.lastItemPurchaseFrameProcessTime == nil then bot.lastItemPurchaseFrameProcessTime = now - 1 end
        now = now + 1.1
        env.ItemPurchaseThink()
    end
    return tick, orders, slots, courierSlots, bot
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
    local opts = {visible = true, custom = {PurchaseList = {'item_manta', 'item_black_king_bar'}}}
    local tick, orders, _, _, bot = fixture({}, opts)
    bot.needPurchaseRebuild = true
    tick()
    assert(orders[1][2] == 'item_blade_of_alacrity', 'custom order survives visible threats and a position rebuild')
end

do
    local tick, orders = fixture({'item_manta'}, {turbo = true, failure = FAILED})
    tick()
    assert(#orders == 1, 'Turbo logs a failed purchase without making another attempt')
end
print('PASS: purchase callback honors components, courier ownership, visible threats, and custom ordering')
