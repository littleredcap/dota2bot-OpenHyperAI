local bot = GetBot()
if bot == nil then return end
local botName = bot:GetUnitName()
if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not string.find(botName, "hero") or bot:IsIllusion() then return end

if GAMEMODE_ARDM == nil then GAMEMODE_ARDM = 20 end
local Item = require( GetScriptDirectory()..'/FunLib/aba_item' )
local Role = require( GetScriptDirectory()..'/FunLib/aba_role' )
local J = require( GetScriptDirectory()..'/FunLib/jmz_func')
local LaneSupply = require(GetScriptDirectory() .. '/FunLib/lane_supply')
local Detection = require(GetScriptDirectory() .. '/FunLib/detection_purchase')
local Utils = require( GetScriptDirectory()..'/FunLib/utils')
local AdvancedItemStrategy = require(GetScriptDirectory()..'/FunLib/advanced_item_strategy').AdvancedItemStrategy

local X = {}

if bot:IsInvulnerable()
	or not bot:IsHero()
	or bot:IsIllusion()
then
	return
end

local BotBuild = require( GetScriptDirectory() .. "/BotLib/" .. string.gsub( botName, "npc_dota_", "" ) )

if BotBuild == nil then return end

bot.purchaseListInReverseOrder = {}
bot.currBuyingItemInPurchaseList = nil
bot.currBuyingBasicItem = nil
bot.currBuyingBasicItemList = {}
bot._lastPurchaseAttempt = { name = nil, t = -999 }

bot.SecretShop = false

local sPurchaseList = BotBuild['sBuyList']
local sItemSellList = BotBuild['sSellList']


if sPurchaseList == nil then
	print("[ERROR] Can't load purchase list for: " .. botName)
	print("Stack Trace:", debug.traceback())
	return
end

for i = 1, #sPurchaseList
 do
	bot.purchaseListInReverseOrder[i] = sPurchaseList[#sPurchaseList - i + 1]
end

bot.sell_time = -90
local check_time = -90

bot.countInvCheck = 0

bot.lastItemToBuy = nil
bot.bPurchaseFromSecret = false
bot.hasBuyShard = true
local itemCost = 0
local t3AlreadyDamaged = false
local t3Check = -90

bot.lastInvCheck = -90
bot.fullInvCheck = -90
bot.switchTime = 0
local buyRD = false

local buyWardTime = -999

local buyBookTime = 0

local initSmoke = false

local currentTime, botLevel, botGold, botWorth, botMode, botHP, botCourierValue, botStashValue, botDistanceFromFountain
local buyingBundle = false
local skippedTarget = false

-- Items that should never be re-bought in ARDM after hero swap
-- (early game consumables / cheap items that waste gold mid-late game)
local tARDMNeverRebuy = {
	item_tango = true, item_double_tango = true, item_clarity = true,
	item_faerie_fire = true, item_enchanted_mango = true, item_flask = true,
	item_blood_grenade = true, item_branches = true, item_double_branches = true,
	item_quelling_blade = true, item_magic_stick = true,
	item_magic_wand = true, item_recipe_magic_wand = true,
	item_infused_raindrop = true, item_orb_of_venom = true,
	item_blight_stone = true, item_orb_of_frost = true,
	item_gauntlets = true, item_slippers = true, item_mantle = true,
	item_circlet = true, item_ring_of_protection = true,
	item_bracer = true, item_wraith_band = true, item_null_talisman = true,
	item_soul_ring = true,
}

local function _antiSpamPurchase(name)
	local t = DotaTime()
	if bot._lastPurchaseAttempt.name == name and t - bot._lastPurchaseAttempt.t < 0.4 then
		return true -- skip this frame
	end
	bot._lastPurchaseAttempt.name, bot._lastPurchaseAttempt.t = name, t
	return false
end

local function HasSufficientTp()
	local tCharges = Item.GetItemCharges( bot, 'item_tpscroll' )
	return tCharges >= 2
		or (tCharges >= 1 and Item.HasItem( bot, 'item_travel_boots' ))
		or (tCharges >= 1 and Item.HasItem( bot, 'item_travel_boots_2' ))
end

local function ClearCurrBuyingBasicItemList(skip)
	if skip and bot.currBuyingBasicItem == bot.currBuyingItemInPurchaseList then skippedTarget = true end
	bot.countInvCheck = 0
	bot.currBuyingBasicItem = nil
	bot.currBuyingBasicItemList[#bot.currBuyingBasicItemList] = nil
end

-- safe pop entire state when finishing/abandoning a composite item
local function _resetCurrentTarget()
	bot.countInvCheck = 0
	bot.currBuyingItemInPurchaseList = nil
	bot.currBuyingBasicItem = nil
	bot.currBuyingBasicItemList = {}
	bot.lastItemToBuy = nil
	bot.SecretShop = false
	buyingBundle, skippedTarget = false, false
end

local function GeneralPurchase()

	if bot.lastItemToBuy ~= bot.currBuyingBasicItem
	then
		bot.lastItemToBuy = bot.currBuyingBasicItem
		bot:SetNextItemPurchaseValue( GetItemCost( bot.currBuyingBasicItem ) )
		bot.bPurchaseFromSecret = IsItemPurchasedFromSecretShop( bot.currBuyingBasicItem )
		if not bot.bPurchaseFromSecret then bot.SecretShop = false end
		itemCost = GetItemCost( bot.currBuyingBasicItem )
	end

	if bot.currBuyingBasicItem == "item_infused_raindrop"
		or bot.currBuyingBasicItem == "item_tome_of_knowledge"
		or bot.currBuyingBasicItem == "item_flask"
	then
		if GetItemStockCount( bot.currBuyingBasicItem ) <= 0
		then
			ClearCurrBuyingBasicItemList(true)
			return
		end
	end

	if _antiSpamPurchase(bot.currBuyingBasicItem) then return end

	local cost = itemCost

	if bot.lastItemToBuy == 'item_boots'
		and bot.currBuyingItemInPurchaseList == 'item_travel_boots'
		and Item.HasBootsInMainSolt( bot )
	then
		cost = GetItemCost( 'item_travel_boots' )
	end

	if bot:GetLevel() >= 18
		and t3AlreadyDamaged == false
		and DotaTime() > t3Check + 1.0
	then

		for i = 2, 8, 3
		do
			local tower = GetTower( GetTeam(), i )
			if tower == nil or tower:GetHealth() / tower:GetMaxHealth() < 0.3
			then
				t3AlreadyDamaged = true
				break
			end
		end


		for i = 1, 7, 3
		do
			local tower = GetTower( GetTeam(), i )
			if tower ~= nil
				and tower:IsAlive()
			then
				t3AlreadyDamaged = false
				break
			end
		end


		for i = 9, 10, 1
		do
			local tower = GetTower( GetTeam(), i )
			if tower == nil
				or tower:GetHealth() / tower:GetMaxHealth() < 0.9
			then
				t3AlreadyDamaged = true
				break
			end
		end


		if DotaTime() >= 54 * 60 then t3AlreadyDamaged = true end

		t3Check = DotaTime()

	elseif t3AlreadyDamaged == true
			and bot:GetBuybackCooldown() <= 10
	then
		cost = itemCost + bot:GetBuybackCost() + bot:GetNetWorth() / 40 - 300
	end

	--如果只剩下一个小配件则不留
	if #bot.currBuyingBasicItemList == 1
		or Role.IsPvNMode()
	then
		cost = itemCost
	end

	--从第12分钟起存钱买魔晶
	if not bot.hasBuyShard
		and DotaTime() > 12 * 60
	then
		local shardCDTime = 15 * 60 - DotaTime()
		if shardCDTime < 0
		then
			cost = cost + 1400
		else
			cost = cost + 1400 * ( 1 - shardCDTime / 300 )
		end
	end

	--开始购买魔晶
	if bot.currBuyingBasicItem == "item_aghanims_shard"
	then
		bot.hasBuyShard = false
		ClearCurrBuyingBasicItemList(true)
		return
	end

	--达到金钱需要时购物
	if bot:GetGold() >= cost
		and bot:GetItemInSlot( 14 ) == nil
	then

		local courier = bot.theCourier

		--当信使购买神秘商店物品后
		if bot.SecretShop
			and courier ~= nil and not courier:IsNull()
			and courier:DistanceFromSecretShop() == 0
		then
			local res = courier:ActionImmediate_PurchaseItem(bot.currBuyingBasicItem)
			if res == PURCHASE_ITEM_SUCCESS then
				ClearCurrBuyingBasicItemList()
				bot.SecretShop = false
				return
			elseif res == PURCHASE_ITEM_OUT_OF_STOCK then
				-- out of stock → don’t block the queue
				ClearCurrBuyingBasicItemList(true)
				bot.SecretShop = false
				return
			end
			return
		end


		--决定是否在神秘购物
		if bot.bPurchaseFromSecret
			and bot:DistanceFromSecretShop() > 0
		then
			bot.SecretShop = true
		else
			if Utils.CountBackpackEmptySpace(bot) > 0 -- has empty slot
			or bot:DistanceFromSecretShop() > 700
			then
				local result = bot:ActionImmediate_PurchaseItem(bot.currBuyingBasicItem)
				if result == PURCHASE_ITEM_SUCCESS
				then
					ClearCurrBuyingBasicItemList()
					bot.SecretShop = false
					return
				else
					if result == PURCHASE_ITEM_OUT_OF_STOCK then
						-- out of stock, skip that item.
						ClearCurrBuyingBasicItemList(true)
						bot.SecretShop = false
					else
						print(botName.." 未能购买物品 "..bot.currBuyingBasicItem.." : "..tostring(result))
					end
				end
			end
		end
	else
		bot.SecretShop = false
	end
end

--加速模式购物逻辑
local function TurboModeGeneralPurchase()

	if _antiSpamPurchase(bot.currBuyingBasicItem) then return end

	if bot.lastItemToBuy ~= bot.currBuyingBasicItem
	then
		bot.lastItemToBuy = bot.currBuyingBasicItem
		bot:SetNextItemPurchaseValue( GetItemCost( bot.currBuyingBasicItem ) )
		itemCost = GetItemCost( bot.currBuyingBasicItem )
		bot.lastItemToBuy = bot.currBuyingBasicItem
	end

	if bot.currBuyingBasicItem == "item_infused_raindrop"
		or bot.currBuyingBasicItem == "item_tome_of_knowledge"
	then
		if GetItemStockCount( bot.currBuyingBasicItem ) <= 0
		then
			ClearCurrBuyingBasicItemList(true)
			return
		end
	end

	local cost = itemCost

	if bot.lastItemToBuy == 'item_boots'
		and bot.currBuyingItemInPurchaseList == 'item_travel_boots'
		and Item.HasBootsInMainSolt( bot )
	then
		cost = GetItemCost( 'item_travel_boots' )
	end
	

	if not bot.hasBuyShard
		and DotaTime() > 8 * 60
	then
		local shardCDTime = 10 * 60 - DotaTime()
		if shardCDTime < 0
		then
			cost = cost + 1400
		else
			cost = cost + 1400 * ( 1 - shardCDTime / 180 )
		end
	end

	if bot.currBuyingBasicItem == "item_aghanims_shard"
	then
		bot.hasBuyShard = false
		ClearCurrBuyingBasicItemList(true)
		return
	end

	if bot:GetGold() >= cost
		and bot:GetItemInSlot( 14 ) == nil
	then
		local result = bot:ActionImmediate_PurchaseItem(bot.currBuyingBasicItem)
		if result == PURCHASE_ITEM_SUCCESS
		then
			ClearCurrBuyingBasicItemList()
			return
		else
			if result == PURCHASE_ITEM_OUT_OF_STOCK then
				-- out of stock, skip that item.
				ClearCurrBuyingBasicItemList(true)
			else
				print(botName.." 未能购买物品 "..bot.currBuyingBasicItem.." : "..tostring(result))
			end
		end
	end
end

-- Issue #155: respect intentional inventory discards while preserving the
-- normal recovery of valuable items accidentally dropped on the ground.
-- The marker is stored on the bot handle so mode_team_roam and purchase logic
-- can agree without accessing each other's script-local variables.
local function ShouldRecoverOwnedDrop(drop, hero)
	if drop == nil or drop.owner ~= hero or drop.item == nil or drop.item:IsNull()
	or drop.location == nil or not IsLocationVisible(drop.location) then
		return false
	end
	if hero.ohaDiscardedItems ~= nil and hero.ohaDiscardedItems[drop.item] then
		return false
	end
	if Item.GetEmptyInventoryAmount(hero) <= 0 then
		return false
	end
	return not string.find(drop.item:GetName(), 'token')
end

local adaptiveCounters = {item_black_king_bar = true, item_monkey_king_bar = true, item_pipe = true}
local recentControl, previousControl = -math.huge, -math.huge
local recentSupportBurst, previousSupportBurst = -math.huge, -math.huge
local nextCounterReview = 0

local function ObserveCounterPressure()
	if currentTime - recentControl >= 12 and bot:WasRecentlyDamagedByAnyHero(1.5)
		and (bot:IsSilenced() or J.IsDisabled(bot)) and #J.GetEnemiesNearLoc(bot:GetLocation(), 1150) > 0 then
		previousControl, recentControl = recentControl, currentTime
		if J.GetPosition(bot) >= 4 and J.GetHP(bot) < 0.45 then
			previousSupportBurst, recentSupportBurst = recentSupportBurst, currentTime
		end
	end
end

local function PreferVisibleCounter(queue)
	local index = #queue
	local current = queue[index]
	if current == nil or adaptiveCounters[current] or currentTime < (J.IsModeTurbo() and 360 or 480)
	or GetGameMode() == GAMEMODE_ARDM or Role.IsPvNMode() or Role.IsAllShadow()
	or GetItemCost(current) < 2000 then return end
	local custom = J.GetUserHeroConfig(bot)
	if custom ~= nil and custom.PurchaseList ~= nil then return end

	local _, hasComponents = Item.GetMissingPurchaseComponents(bot, current)
	if hasComponents then return end

	if J.GetPosition(bot) >= 4 then
		-- Finish the first affordable save instead of displacing it with a team aura.
		if current == 'item_force_staff' or current == 'item_glimmer_cape' or current == 'item_aeon_disk' then return end
		if (botName == 'npc_dota_hero_warlock' or botName == 'npc_dota_hero_shadow_shaman')
			and currentTime >= (J.IsModeTurbo() and 780 or 1080)
			and currentTime - previousSupportBurst <= 145 and currentTime - recentSupportBurst <= 70 then
			local _, _, glimmer = Item.GetMissingPurchaseComponents(bot, 'item_glimmer_cape')
			local _, _, force = Item.GetMissingPurchaseComponents(bot, 'item_force_staff')
			local _, _, disk = Item.GetMissingPurchaseComponents(bot, 'item_aeon_disk')
			if (glimmer or force) and not disk then
				for i = index - 1, 1, -1 do
					if queue[i] == 'item_aeon_disk' then table.remove(queue, i); break end
				end
				queue[#queue + 1] = 'item_aeon_disk'
				return true
			end
		end
	end

	local mustKeepAttacking = J.GetPosition(bot) <= 3 and currentTime - previousControl <= 95
		and currentTime - recentControl <= 48 and Item.HasBuyBoots(bot)
	if current == 'item_blink' and not mustKeepAttacking then return end
	local suggested = AdvancedItemStrategy:GetVisibleCounterItems()
	if mustKeepAttacking then table.insert(suggested, 1, 'item_black_king_bar') end
	for _, counter in ipairs(suggested) do
		if adaptiveCounters[counter] then
			local _, _, owned = Item.GetMissingPurchaseComponents(bot, counter)
			if not owned then
				for candidate = index - 1, 1, -1 do
					if queue[candidate] == counter then
						table.remove(queue, candidate)
						queue[#queue + 1] = counter
						return true
					end
				end
				if counter == 'item_black_king_bar' and mustKeepAttacking then
					queue[index + 1] = counter
					return true
				end
			end
		end
	end
end

local function ProcessPurchaseQueue()
	local queue = bot.purchaseListInReverseOrder
	local newTarget = bot.currBuyingItemInPurchaseList == nil
	if currentTime >= nextCounterReview then
		nextCounterReview = currentTime + 3
		if not newTarget and not buyingBundle and not skippedTarget and PreferVisibleCounter(queue) then
			_resetCurrentTarget()
			newTarget = true
		end
	end
	if newTarget then
		if queue[#queue] == 'item_boots' and (Item.HasBuyBoots(bot)
			or Item.HasItem(bot, 'item_guardian_greaves') or Item.HasItem(bot, 'item_travel_boots')
			or Item.HasItem(bot, 'item_travel_boots_2') or Item.HasItem(bot, 'item_boots_of_bearing')) then
			queue[#queue] = nil
			bot:SetNextItemPurchaseValue(0)
			return
		end
		PreferVisibleCounter(queue)
		bot.currBuyingItemInPurchaseList = queue[#queue]
		buyingBundle = Item.IsPurchaseBundle(bot.currBuyingItemInPurchaseList)
	end

	local name = bot.currBuyingItemInPurchaseList
	local complete = skippedTarget
	local loneDruid = Utils.GetLoneDruid(bot)
	if bot == loneDruid.hero and loneDruid.bear ~= nil
	and Item.GetItemTotalWorthInSlots(loneDruid.bear) < 28000 then
		complete = complete or Item.IsItemInTargetHero(name, loneDruid.bear)
	end

	if not complete and (newTarget or not buyingBundle) then
		local missing, _, owned = Item.GetMissingPurchaseComponents(bot, name)
		complete = owned
		for i = 1, math.floor(#missing / 2) do
			local j = #missing - i + 1
			missing[i], missing[j] = missing[j], missing[i]
		end
		bot.currBuyingBasicItemList = missing
	end

	if complete or (buyingBundle and #bot.currBuyingBasicItemList == 0)
	or bot.countInvCheck > (GetGameMode() == GAMEMODE_ARDM and 30 or 180) then
		queue[#queue] = nil
		_resetCurrentTarget()
		bot:SetNextItemPurchaseValue(0)
		return
	end

	bot.currBuyingBasicItem = bot.currBuyingBasicItemList[#bot.currBuyingBasicItemList]
	if bot.currBuyingBasicItem == nil then
		-- All observed pieces are already owned. Give the courier or stash time to deliver them.
		bot.SecretShop = false
		bot.lastItemToBuy = nil
		bot:SetNextItemPurchaseValue(0)
		if currentTime > bot.lastInvCheck + 1 and botCourierValue == 0 and botStashValue == 0
		and botGold >= 2000 and botGold > GetItemCost(name) * 2 then
			bot.lastInvCheck = currentTime
			bot.countInvCheck = bot.countInvCheck + 1
		end
		return
	end
	if GetGameMode() == 23 then TurboModeGeneralPurchase() else GeneralPurchase() end
end

function ItemPurchaseThink()
	currentTime = DotaTime()

	-- ARDM: detect stale hero instance and rebuild purchase list on hero swap
	local isStale, freshBot, freshName = J.IsStaleARDMHero(bot, botName)
	if isStale then return end
	if freshName ~= botName then
		if not freshBot:IsAlive() then return end
		print("[ARDM] Item purchase: hero changed from "..botName.." to "..freshName)
		bot = freshBot
		recentControl, previousControl = -math.huge, -math.huge
		botName = freshName

		-- Load new hero's item build
		local heroFile = string.gsub(botName, "npc_dota_", "")
		local ok, newBuild = pcall(dofile, GetScriptDirectory().."/BotLib/"..heroFile)
		if ok and newBuild ~= nil and newBuild['sBuyList'] ~= nil then
			BotBuild = newBuild
			sPurchaseList = newBuild['sBuyList']
			sItemSellList = newBuild['sSellList']
		else
			sPurchaseList = {}
			sItemSellList = {}
		end

		-- Rebuild purchase list, skipping owned items, duplicate boots, early items
		local bHasBoots = Item.HasBuyBoots(bot)
			or Item.HasItem(bot, 'item_guardian_greaves')
			or Item.HasItem(bot, 'item_travel_boots')
			or Item.HasItem(bot, 'item_travel_boots_2')
			or Item.HasItem(bot, 'item_boots_of_bearing')
		local tSkipBoots = {
			item_boots = true, item_phase_boots = true, item_power_treads = true,
			item_tranquil_boots = true, item_arcane_boots = true,
			-- greaves/bearing/travel are intentional upgrades, don't skip
		}

		bot.purchaseListInReverseOrder = {}
		local idx = 0
		for i = #sPurchaseList, 1, -1 do
			local itemName = sPurchaseList[i]
			local bSkip = false
			if Item.IsItemInHero(itemName) then
				bSkip = true
			elseif GetGameMode() == GAMEMODE_ARDM and DotaTime() > 2 * 60 and tARDMNeverRebuy[itemName] then
				bSkip = true
			elseif bHasBoots and tSkipBoots[itemName] then
				bSkip = true
			end
			if not bSkip then
				idx = idx + 1
				bot.purchaseListInReverseOrder[idx] = itemName
			end
		end

		-- Build set of all items/components needed by new build
		local tNewBuildNeeds = {}
		local function protectComponents(itemName)
			if tNewBuildNeeds[itemName] then return end
			tNewBuildNeeds[itemName] = true
			for _, component in ipairs(Item.GetPurchaseRecipe(itemName) or {}) do
				protectComponents(component)
			end
		end
		for _, itemName in ipairs(sPurchaseList) do protectComponents(itemName) end

		local tNeverSell = {
			item_aegis = true, item_rapier = true, item_gem = true,
			item_cheese = true, item_refresher_shard = true,
			item_moon_shard = true, item_tpscroll = true,
			item_famango = true, item_great_famango = true, item_greater_famango = true,
		}

		-- Collect sellable items sorted by cost (cheapest first)
		local tSellable = {}
		for slot = 0, 14 do
			local item = bot:GetItemInSlot(slot)
			if item ~= nil then
				local name = item:GetName()
				if not tNeverSell[name]
				and not tNewBuildNeeds[name]
				and not string.find(name, 'token')
				then
					table.insert(tSellable, { slot = slot, name = name, cost = GetItemCost(name) })
				end
			end
		end
		table.sort(tSellable, function(a, b) return a.cost < b.cost end)

		-- Phase 1: sell recipes and cheap items (< 1000g) not in new build
		local MIN_FREE_SLOTS = 3
		for _, entry in ipairs(tSellable) do
			local item = bot:GetItemInSlot(entry.slot)
			if item ~= nil then
				if string.find(entry.name, 'recipe') or entry.cost < 1000 then
					bot:ActionImmediate_SellItem(item)
					print("[ARDM] Sold: "..entry.name.." (cost: "..entry.cost..")")
				end
			end
		end

		-- Phase 2: sell more if inventory still too full
		local nUsedSlots = 0
		for slot = 0, 8 do
			if bot:GetItemInSlot(slot) ~= nil then nUsedSlots = nUsedSlots + 1 end
		end
		local nFreeSlots = 9 - nUsedSlots
		if nFreeSlots < MIN_FREE_SLOTS then
			for _, entry in ipairs(tSellable) do
				if nFreeSlots >= MIN_FREE_SLOTS then break end
				local item = bot:GetItemInSlot(entry.slot)
				if item ~= nil then
					bot:ActionImmediate_SellItem(item)
					print("[ARDM] Sold (full inv): "..entry.name.." (cost: "..entry.cost..")")
					nFreeSlots = nFreeSlots + 1
				end
			end
		end

		-- Reset purchase state machine
		_resetCurrentTarget()
	end
	if bot:IsAlive() then ObserveCounterPressure() end

	-- Detect position swap from !pos command: rebuild purchase list for new role
	if bot.needPurchaseRebuild then
		local config = J.GetUserHeroConfig(bot)
		if config ~= nil and config.PurchaseList ~= nil then bot.needPurchaseRebuild = nil end
	end
	if bot.needPurchaseRebuild then
		bot.needPurchaseRebuild = nil
		local oldTarget = bot.currBuyingItemInPurchaseList
		local nNewPos = J.GetPosition(bot)
		print("[PosSwap] Item purchase rebuild for "..botName.." -> pos"..nNewPos)

		-- Reload BotBuild to get new role's item list
		local heroFile = string.gsub(botName, "npc_dota_", "")
		local ok, newBuild = pcall(dofile, GetScriptDirectory().."/BotLib/"..heroFile)
		if ok and newBuild ~= nil and newBuild['sBuyList'] ~= nil then
			BotBuild = newBuild
			sPurchaseList = newBuild['sBuyList']
			sItemSellList = newBuild['sSellList']
		end

		-- Rebuild purchase list, skipping:
		-- 1. Items the bot already owns (final item in inventory)
		-- 2. Items whose ALL components the bot already has (final item effectively built)
		-- 3. Duplicate boots if bot already has boots
		if sPurchaseList then
			local bHasBoots = Item.HasBuyBoots(bot)
				or Item.HasItem(bot, 'item_guardian_greaves')
				or Item.HasItem(bot, 'item_travel_boots')
				or Item.HasItem(bot, 'item_travel_boots_2')
				or Item.HasItem(bot, 'item_boots_of_bearing')
			local tSkipBoots = {
				item_boots = true, item_phase_boots = true, item_power_treads = true,
				item_tranquil_boots = true, item_arcane_boots = true,
				-- greaves/bearing/travel are intentional upgrades, don't skip
			}

			bot.purchaseListInReverseOrder = {}
			local idx = 0
			for i = #sPurchaseList, 1, -1 do
				local itemName = sPurchaseList[i]
				local bSkip = false

				-- Already own it
				if Item.IsItemInHero(itemName) then
					bSkip = true
				-- Duplicate boots
				elseif bHasBoots and tSkipBoots[itemName] then
					bSkip = true
				-- Early game items past laning (same as ARDM)
				elseif DotaTime() > 10 * 60 and tARDMNeverRebuy[itemName] then
					bSkip = true
				end

				if not bSkip then
					idx = idx + 1
					bot.purchaseListInReverseOrder[idx] = itemName
				end
			end
		end

		local keepCurrent = false
		if oldTarget ~= nil then
			for i, name in ipairs(bot.purchaseListInReverseOrder) do
				if name == oldTarget then
					local _, hasComponents = Item.GetMissingPurchaseComponents(bot, name)
					if hasComponents then
						table.remove(bot.purchaseListInReverseOrder, i)
						bot.purchaseListInReverseOrder[#bot.purchaseListInReverseOrder + 1] = name
						keepCurrent = true
					end
					break
				end
			end
		end
		if not keepCurrent then _resetCurrentTarget() end
		print("[PosSwap] Purchase list rebuilt with "..#bot.purchaseListInReverseOrder.." items")
	end

	if bot.lastItemPurchaseFrameProcessTime == nil then bot.lastItemPurchaseFrameProcessTime = currentTime end
	if currentTime > 30 and (currentTime - bot.lastItemPurchaseFrameProcessTime < 1) then return end
	bot.lastItemPurchaseFrameProcessTime = currentTime

	if ( GetGameState() ~= GAME_STATE_PRE_GAME and GetGameState() ~= GAME_STATE_GAME_IN_PROGRESS )
	then return	end

	if bot:IsIllusion()
	or bot:HasModifier( 'modifier_arc_warden_tempest_double' )
	or (currentTime > 0 and J.IsMeepoClone(bot))
	or bot:HasModifier('modifier_dazzle_nothl_projection_soul_debuff')
	then
		bot.purchaseListInReverseOrder = {}
		return
	end

	botLevel = bot:GetLevel()
	botGold = bot:GetGold()
	botWorth = bot:GetNetWorth()
	botMode = bot:GetActiveMode()
	botHP	= J.GetHP(bot)
	botCourierValue = bot:GetCourierValue()
	botStashValue = bot:GetStashValue()
	botDistanceFromFountain = bot:DistanceFromFountain()

	-- Recover genuine owned drops, but not low-value items deliberately
	-- discarded to clear slots (or anything we cannot currently carry).
	local dropped = GetDroppedItemList()
	for _, d in pairs(dropped) do
		if ShouldRecoverOwnedDrop(d, bot) then
			local dist = GetUnitToLocationDistance(bot, d.location)
			if dist > 100 and dist < 1000 then
				bot:Action_MoveToLocation(d.location)
			elseif dist <= 100 then
				bot:Action_PickUpItem(d.item)
				return
			end
		end
	end

	if bot == Utils.GetLoneDruid(bot).hero then
		local bear = Utils.GetLoneDruid(bot).bear
		if bear ~= nil then
			local hEnemyList = J.GetNearbyHeroes(bot, 1000, true, BOT_MODE_NONE)
			if #hEnemyList >= 1 then return end
			
			if not bear:IsAlive() or bear:IsChanneling() or bear:IsUsingAbility() or Utils.CountBackpackEmptySpace(bear) <= 0 then return end
			if bear:HasModifier('modifier_item_ultimate_scepter_consumed') then return end

			local bearNetworth = Item.GetItemTotalWorthInSlots(bear)
			if GetUnitToUnitDistance(bot, bear) < 400 then
				for i = 0, 9
				do
					local item = bot:GetItemInSlot( i )
					if item ~= nil
					then
						local itemName = item:GetName()
						if Utils.HasValue(Item['tEarlyConsumableItem'], itemName)
						or Utils.HasValue(Item['item_ultimate_scepter'], itemName)
						or (string.find(itemName, 'boot') and bearNetworth > 600)
						or itemName == 'item_tpscroll' and Item.HasItem(bear, 'item_tpscroll')
						then
							-- do nothing, keep it.
						elseif Utils.CountBackpackEmptySpace(bear) >= 1 then
							bot:Action_DropItem(item, bear:GetLocation())
						end
					end
				end
			end
		end
	end
	if Utils.IsBear(bot) and bot:IsAlive() then
		local dropItemList = GetDroppedItemList()
		for _, tDropItem in pairs( dropItemList )
		do
			if tDropItem.owner == Utils.GetLoneDruid(bot).hero
			and tDropItem.item ~= nil and not tDropItem.item:IsNull()
			and tDropItem.location ~= nil and IsLocationVisible(tDropItem.location)
			and not string.find(tDropItem.item:GetName(), 'token')
			and not (string.find(tDropItem.item:GetName(), 'boot') and Item.HasItemWithName(bot, 'boot')) then
				local distance = GetUnitToLocationDistance(bot, tDropItem.location)
				if distance > 200 and distance < 1000 and tDropItem.owner == bot
				then
					bot:Action_MoveToLocation(tDropItem.location)
				elseif distance <= 100 then
					bot:Action_PickUpItem(tDropItem.item)
					return
				end
			end
		end
	end

	--更新队伍里是否有辅助的定位
	if Role['supportExist'] == nil then Role.UpdateSupportStatus( bot ) end

	-- During laning, value the wave and delivery before spending on optional regeneration.
	if bot.ohaLaneSupply or J.IsInLaningPhase(bot) then
		if LaneSupply.Update(bot) then return end
	elseif J.GetMP(bot) < 0.3 and botDistanceFromFountain > 2000 and botCourierValue == 0
		and GetItemStockCount('item_clarity') > 1 and Item.GetItemCharges(bot, 'item_clarity') <= 0
		and botGold >= GetItemCost('item_clarity') then
		bot:ActionImmediate_PurchaseItem('item_clarity')
	end

	if Detection.Update(bot) then return end

	-- Observer Wards
	if J.GetPosition(bot) == 5 and botWorth < 25000
	then
		local wardType = 'item_ward_observer'

		if GetItemStockCount(wardType) > 1
		and botGold >= GetItemCost(wardType)
		and Item.GetEmptyInventoryAmount(bot) >= 2
		and Item.GetItemCharges(bot, wardType) < 2
		and botCourierValue == 0
		then
			bot:ActionImmediate_PurchaseItem(wardType)
		end
	end

	-- Smoke of Deceit
	if J.GetPosition(bot) == 5 and botWorth < 10000
	and Utils.CountBackpackEmptySpace(bot) >= 2
	and GetItemStockCount('item_smoke_of_deceit') > 1
	and botGold >= GetItemCost('item_smoke_of_deceit')
	and Item.GetEmptyInventoryAmount(bot) >= 3
	and Item.GetItemCharges(bot, 'item_smoke_of_deceit') == 0
	and botCourierValue == 0
	then
		if DotaTime() < 0
		and not initSmoke
		then
			local hasSmoke = false
			for _, allyHero in pairs(GetUnitList(UNIT_LIST_ALLIED_HEROES))
			do
				if J.IsValidHero(allyHero)
				and J.IsNotSelf(bot, allyHero)
				and J.HasItem(allyHero, 'item_smoke_of_deceit')
				then
					hasSmoke = true
				end
			end

			if not hasSmoke
			then
				bot:ActionImmediate_PurchaseItem('item_smoke_of_deceit')
			end
		else
			if not J.IsInLaningPhase()
			then
				bot:ActionImmediate_PurchaseItem('item_smoke_of_deceit')
			end
		end
	end

	-- Blood Grenade
	if J.IsInLaningPhase()
	and (J.GetPosition(bot) == 4 or J.GetPosition(bot) == 5)
	and GetItemStockCount('item_blood_grenade') > 0
	and botLevel < 5
	and botGold >= GetItemCost('item_blood_grenade')
	and Item.GetEmptyInventoryAmount(bot) >= 3
	and Item.GetItemCharges(bot, 'item_blood_grenade') == 0
	and botStashValue > 0
	then
		bot:ActionImmediate_PurchaseItem('item_blood_grenade')
	end

	--为自己购买魔晶
	if not bot.hasBuyShard
		and GetItemStockCount( "item_aghanims_shard" ) > 0
		and botGold >= 1400
	then
		bot.hasBuyShard = true
		bot:ActionImmediate_PurchaseItem( "item_aghanims_shard" )
	end

	--防止非辅助购买魂泪
	if buyRD == false
		and currentTime < 0
	then
		buyRD = true
	end

	--死前如果会损失金钱则购买额外TP
	local tpCost = GetItemCost( "item_tpscroll" )
	if botGold >= tpCost
		and bot:IsAlive()
		and botGold < ( tpCost + botWorth / 40 )
		and botHP < 0.08
		and botHP >= 1
		and bot:WasRecentlyDamagedByAnyHero( 3.1 )
		and not HasSufficientTp()
		and Item.GetItemCharges( bot, 'item_tpscroll' ) <= 2
	then
		bot:ActionImmediate_PurchaseItem( "item_tpscroll" )
	end
	
	--正常买备用tp
	if currentTime > 4 * 60
		and botCourierValue <= 100
		and botGold >= tpCost
		and not HasSufficientTp()
		and botName ~= "npc_dota_hero_meepo" -- don't let meepo buy tp
		and botName ~= "npc_dota_hero_lone_druid_bear"
	then
		local tCharges = Item.GetItemCharges( bot, 'item_tpscroll' )
		if bot:HasModifier("modifier_teleporting") then tCharges = tCharges - 1 end
		if tCharges <= 0 or ( botLevel >= 18 and tCharges <= 1 )
		then
			if botGold >= tpCost * 2 and currentTime > 25 * 60 then
				bot:ActionImmediate_PurchaseItem( "item_tpscroll" )
			end
			bot:ActionImmediate_PurchaseItem( "item_tpscroll" )
		end
	end

	--交换魂泪的位置避免过早被破坏
	if currentTime > 180
		and currentTime < 1800
		and bot.switchTime < currentTime - 5.6
	then
		local raindrop = bot:FindItemSlot( "item_infused_raindrop" )
		local raindropCharge = Item.GetItemCharges( bot, "item_infused_raindrop" )
		local nEnemyHeroes = J.GetNearbyHeroes(bot, 1600, true, BOT_MODE_NONE )
		if ( raindrop >= 0 and raindrop <= 5 )
			and ( nEnemyHeroes[1] ~= nil
				or botMode == BOT_MODE_ROSHAN
				or bot:WasRecentlyDamagedByAnyHero( 3.1 ) )
			and ( raindropCharge == 1 or raindropCharge >= 7 )
		then
			bot.switchTime = currentTime
			bot:ActionImmediate_SwapItems( raindrop, 6 )
		end
	end

	-- Ward slot management for supports (pos 4/5):
	-- Free a main slot for observer-only wards and keep combat sentries accessible.
	if J.GetPosition(bot) >= 4 and currentTime > (bot._lastWardSwapTime or 0) + 3 then
		local bIsWarding = botMode == BOT_MODE_WARD
		local tWardNames = { 'item_ward_observer', 'item_ward_sentry', 'item_ward_dispenser' }

		for _, wardName in ipairs(tWardNames) do
			local wardSlot = bot:FindItemSlot(wardName)
			if wardSlot >= 0 then
				local carryingSentry = Item.GetSentryCharges(bot:GetItemInSlot(wardSlot)) > 0
				if bIsWarding or carryingSentry then
					if wardSlot >= 6 and wardSlot <= 8 then
						for mainSlot = 0, 5 do
							local mainItem = bot:GetItemInSlot(mainSlot)
							if mainItem == nil then
								bot:ActionImmediate_SwapItems(wardSlot, mainSlot)
								bot._lastWardSwapTime = currentTime
								break
							end
						end
					end
				else
					-- Move ward from main inventory (0-5) to backpack if backpack has space
					if wardSlot >= 0 and wardSlot <= 5 then
						for bpSlot = 6, 8 do
							local bpItem = bot:GetItemInSlot(bpSlot)
							if bpItem == nil then
								bot:ActionImmediate_SwapItems(wardSlot, bpSlot)
								bot._lastWardSwapTime = currentTime
								break
							end
						end
					end
				end
			end
		end
	end

	if ( GetGameMode() ~= 23 and botLevel > 6 and currentTime > bot.fullInvCheck + 1.0
		and (botDistanceFromFountain <= 200 or bot:DistanceFromSecretShop() <= 200 ))
		or ( GetGameMode() == 23 and botLevel > 9 and currentTime > bot.fullInvCheck + 1.0 )
	then
		local emptySlot = Item.GetEmptyInventoryAmount( bot )
		local slotToSell = nil

		local preEmpty = 2
		if botLevel <= 17 then preEmpty = 1 end
		if emptySlot <= preEmpty - 1
		then
			for i = 1, #Item['tEarlyItem']
			do
				local itemName = Item['tEarlyItem'][i]
				local itemSlot = bot:FindItemSlot( itemName )
				if itemSlot >= 0 and itemSlot <= 8
				then
					slotToSell = itemSlot
					break
				end
			end
		end


		if botWorth > 10000
			and bot:GetItemInSlot( 6 ) ~= nil
			and bot:GetItemInSlot( 7 ) ~= nil
		then
			local wand = bot:FindItemSlot( "item_magic_wand" )
			local assitItem = bot:FindItemSlot( "item_infused_raindrop" )
			if assitItem < 0 then assitItem = bot:FindItemSlot( "item_bracer" ) end
			if assitItem < 0 then assitItem = bot:FindItemSlot( "item_null_talisman" ) end
			if assitItem < 0 then assitItem = bot:FindItemSlot( "item_wraith_band" ) end
			if assitItem >= 0
				and wand >= 6
				and wand <= 8
			then
				slotToSell = assitItem
			end
		end

		if slotToSell ~= nil
		then
			bot:ActionImmediate_SellItem( bot:GetItemInSlot( slotToSell ) )
		end

		bot.fullInvCheck = currentTime
	end

	--出售过渡装备
	local countEmptyBackpack = Utils.CountBackpackEmptySpace(bot)
	if currentTime > bot.sell_time + 0.5
		and countEmptyBackpack <= 1
		and ( botDistanceFromFountain <= 100 or bot:DistanceFromSecretShop() <= 100 )
	then
		bot.sell_time = currentTime

		-- default list
		SetPairedItems(Item.sSellList)
		-- specific list
		SetPairedItems(sItemSellList)

		if botWorth > 23000 then
			if Item.HasItem( bot, "item_hand_of_midas" ) then
				bot:ActionImmediate_SellItem(bot:GetItemInSlot(bot:FindItemSlot('item_hand_of_midas')))
			end
		end

		if (currentTime > 18 * 60 or botWorth > 20000)
			and ( Item.HasItem( bot, "item_travel_boots" ) or Item.HasItem( bot, "item_travel_boots_2" ) )
		then
			for i = 1, #Item['tEarlyBoots']
			do
				local bootsSlot = bot:FindItemSlot( Item['tEarlyBoots'][i] )
				if bootsSlot >= 0
				then
					bot:ActionImmediate_SellItem( bot:GetItemInSlot( bootsSlot ) )
				end
			end
		end
	end

	if Item.HasItem(bot, 'item_mask_of_madness')
	and Item.HasItem(bot, 'item_satanic')
	then
		bot:ActionImmediate_SellItem(bot:GetItemInSlot(bot:FindItemSlot('item_mask_of_madness')))
	end

	-- Cores drop normal/great lotuses after 30min to free up slots for real items.
	-- Greater lotus (item_greater_famango) is kept by everyone — too valuable to drop.
	if currentTime > 30 * 60 and J.IsCore(bot) then
		local tDropLotus = { 'item_famango', 'item_great_famango' }
		for _, lotusName in ipairs(tDropLotus) do
			local slot = bot:FindItemSlot(lotusName)
			if slot >= 0 then
				local item = bot:GetItemInSlot(slot)
				if item ~= nil then
					bot.ohaDiscardedItems = bot.ohaDiscardedItems or {}
					bot.ohaDiscardedItems[item] = true
					bot:Action_DropItem(item, bot:GetLocation())
					print("[Item] Core "..botName.." discarded "..lotusName.." (past 30min)")
					return -- only one deliberate drop each tick
				end
			end
		end
	end

	if #bot.purchaseListInReverseOrder == 0 then
		_resetCurrentTarget()
		bot:SetNextItemPurchaseValue( 0 )
		return
	end

	ProcessPurchaseQueue()
end

function SetPairedItems(itemList)
	for i = 2 , #itemList, 2
	do
		local nNewSlot = bot:FindItemSlot( itemList[i - 1] )
		local nOldSlot = bot:FindItemSlot( itemList[i] )
		if nNewSlot >= 0 and nOldSlot >= 0
		then
			bot:ActionImmediate_SellItem( bot:GetItemInSlot( nOldSlot ) )
		end
	end
end


X.ItemPurchaseThink = ItemPurchaseThink

return X
