if NeutralItems == nil
then
    NeutralItems = {}
end

local isTierOneDone   = false
local isTierTwoDone   = false
local isTierThreeDone = false
local isTierFourDone  = false
-- 7.42 has no fifth neutral tier.
local DOTA_ITEM_NEUTRAL_SLOT = 16

-- Current 7.42 artifacts and enhancements (source: d2vpkr neutral_items.txt).
-- Buff mode intentionally distributes a random valid item per tier.

local Tier1NeutralItems = {
    "item_chipped_vest",
    "item_ash_legion_shield",
    "item_possessed_mask",
    "item_dormant_curio",
    "item_red_ledger",
    "item_weighted_dice",
    "item_polliwog_charm",
    "item_seeds_of_serenity",
    "item_foragers_kit",
    "item_kobold_cup",
    "item_stonefeather_satchel",
    "item_pogo_stick",
}

local Tier2NeutralItems = {
    "item_psychic_headband",
    "item_safety_bubble",
    "item_metamorphic_mandible",
    "item_jidi_pollen_bag",
    "item_brick",
    "item_crippling_crossbow",
    "item_imp_claw",
    "item_gunpowder_gauntlets",
    "item_defiant_shell",
    "item_partisans_brand",
    "item_spellslinger",
    "item_mana_draught",
}

local Tier3NeutralItems = {
    "item_prophets_pendulum",
    "item_dandelion_amulet",
    "item_idol_of_screeauk",
    "item_balmhook",
    "item_rattlecage",
    "item_stormcrafter",
    "item_enchanters_bauble",
    "item_ceremonial_robe",
    "item_harmonizer",
    "item_vile_phial",
    "item_serrated_shiv",
    "item_revenants_brooch",
}

local Tier4NeutralItems = {
    "item_fallen_sky",
    "item_flicker",
    "item_minotaur_horn",
    "item_mind_breaker",
    "item_divine_regalia",
    "item_heavy_blade",
    "item_helm_of_the_hivemind",
    "item_dezun_bloodrite",
    "item_conjurers_catalyst",
    "item_giants_ring",
    "item_demonicon",
    "item_riftshadow_prism",
}

local enhancements = {
    -- Tier 1 (0:00)
    {name="item_enhancement_quickened", tier=1, roles={1,1,1,2,1}, realName="Quickened Enhancement"},
    {name="item_enhancement_vital", tier=1, roles={1,1,1,1,1}, realName="Vital Enhancement"},
    {name="item_enhancement_brawny", tier=1, roles={1,1,3,2,2}, realName="Brawny Enhancement"},
    {name="item_enhancement_tough", tier=1, roles={1,1,2,2,1}, realName="Tough Enhancement"},
    {name="item_enhancement_alert", tier=1, roles={1,2,1,1,1}, realName="Alert Enhancement"},
    {name="item_enhancement_mystical", tier=1, roles={1,1,1,1,1}, realName="Mystical Enhancement"},

    -- Tier 2 (15:00)
    {name="item_enhancement_quickened", tier=2, roles={1,1,1,2,1}, realName="Quickened Enhancement"},
    {name="item_enhancement_vital", tier=2, roles={1,1,1,1,1}, realName="Vital Enhancement"},
    {name="item_enhancement_brawny", tier=2, roles={1,1,3,2,2}, realName="Brawny Enhancement"},
    {name="item_enhancement_tough", tier=2, roles={1,1,2,2,1}, realName="Tough Enhancement"},
    {name="item_enhancement_crude", tier=2, roles={1,1,1,1,1}, realName="Crude Enhancement"},
    {name="item_enhancement_alert", tier=2, roles={1,2,1,1,1}, realName="Alert Enhancement"},
    {name="item_enhancement_nimble", tier=2, roles={1,1,1,1,1}, realName="Nimble Enhancement"},
    {name="item_enhancement_mystical", tier=2, roles={1,1,1,1,1}, realName="Mystical Enhancement"},
    {name="item_enhancement_keen_eyed", tier=2, roles={1,1,1,1,2}, realName="Keen Eyed Enhancement"},
    {name="item_enhancement_titanic", tier=2, roles={1,1,1,1,1}, realName="Titanic Enhancement"},

    -- Tier 3 (30:00)
    {name="item_enhancement_quickened", tier=3, roles={1,1,1,2,1}, realName="Quickened Enhancement"},
    {name="item_enhancement_greedy", tier=3, roles={1,1,1,2,2}, realName="Greedy Enhancement"},
    {name="item_enhancement_brawny", tier=3, roles={1,1,3,2,2}, realName="Brawny Enhancement"},
    {name="item_enhancement_tough", tier=3, roles={1,1,2,2,1}, realName="Tough Enhancement"},
    {name="item_enhancement_crude", tier=3, roles={1,1,1,1,1}, realName="Crude Enhancement"},
    {name="item_enhancement_alert", tier=3, roles={1,2,1,1,1}, realName="Alert Enhancement"},
    {name="item_enhancement_nimble", tier=3, roles={1,1,1,1,1}, realName="Nimble Enhancement"},
    {name="item_enhancement_mystical", tier=3, roles={1,1,1,1,1}, realName="Mystical Enhancement"},
    {name="item_enhancement_keen_eyed", tier=3, roles={1,1,1,1,2}, realName="Keen Eyed Enhancement"},
    {name="item_enhancement_titanic", tier=3, roles={1,1,1,1,1}, realName="Titanic Enhancement"},

    -- Tier 4 (50:00)
    {name="item_enhancement_timeless", tier=4, roles={1,1,1,1,1}, realName="Timeless Enhancement"},
    {name="item_enhancement_evolved", tier=4, roles={1,1,1,1,1}, realName="Evolved Enhancement"},
    {name="item_enhancement_fleetfooted", tier=4, roles={1,1,1,1,1}, realName="Fleetfooted Enhancement"},
    {name="item_enhancement_vampiric", tier=4, roles={1,1,1,1,1}, realName="Vampiric Enhancement"},
    {name="item_enhancement_hulking", tier=4, roles={1,1,1,1,1}, realName="Hulking Enhancement"},
    {name="item_enhancement_audacious", tier=4, roles={1,1,1,1,1}, realName="Audacious Enhancement"},
    {name="item_enhancement_feverish", tier=4, roles={1,1,1,1,1}, realName="Feverish Enhancement"},
    {name="item_enhancement_manic", tier=4, roles={1,1,1,1,1}, realName="Manic Enhancement"},

}

function NeutralItems:GetRandomEnhanByTier(tier)
    local filtered = {}
    for _, enh in ipairs(enhancements) do
        if enh.tier == tier then
            table.insert(filtered, enh)
        end
    end

    if #filtered == 0 then
        return nil  -- No enhancement found for this tier
    end

    -- Return a random enhancement from the filtered list.
    return filtered[math.random(#filtered)]
end


-- Just give out random for now.
-- Will work out a decent algorithm later to better assign suitable items.
function NeutralItems.GiveNeutralItems(TeamRadiant, TeamDire)
    local isTurboMode = Helper.IsTurboMode()

    -- Tier 1 Neutral Items
    if (isTurboMode and Helper.DotaTime() >= 0 or Helper.DotaTime() >= 0)
    and not isTierOneDone
    then
        GameRules:SendCustomMessage('Bots receiving Tier 1 Neutral Items...', 0, 0)

        for _, h in pairs(TeamRadiant) do
            NeutralItems.GiveItem(Tier1NeutralItems[RandomInt(1, #Tier1NeutralItems)], h, isTierOneDone, 1)
        end

        for _, h in pairs(TeamDire) do
            NeutralItems.GiveItem(Tier1NeutralItems[RandomInt(1, #Tier1NeutralItems)], h, isTierOneDone, 1)
        end

        isTierOneDone = true
    end

    -- Tier 2 Neutral Items
    if (isTurboMode and Helper.DotaTime() >= 7.5 * 60 or Helper.DotaTime() >= 15 * 60)
    and not isTierTwoDone
    then
        GameRules:SendCustomMessage('Bots receiving Tier 2 Neutral Items...', 0, 0)

        for _, h in pairs(TeamRadiant) do
            NeutralItems.GiveItem(Tier2NeutralItems[RandomInt(1, #Tier2NeutralItems)], h, isTierOneDone, 2)
        end

        for _, h in pairs(TeamDire) do
            NeutralItems.GiveItem(Tier2NeutralItems[RandomInt(1, #Tier2NeutralItems)], h, isTierOneDone, 2)
        end

        isTierTwoDone = true
    end

    -- Tier 3 Neutral Items
    if (isTurboMode and Helper.DotaTime() >= 15 * 60 or Helper.DotaTime() >= 30 * 60)
    and not isTierThreeDone
    then
        GameRules:SendCustomMessage('Bots receiving Tier 3 Neutral Items...', 0, 0)

        for _, h in pairs(TeamRadiant) do
            NeutralItems.GiveItem(Tier3NeutralItems[RandomInt(1, #Tier3NeutralItems)], h, isTierTwoDone, 3)
        end

        for _, h in pairs(TeamDire) do
            NeutralItems.GiveItem(Tier3NeutralItems[RandomInt(1, #Tier3NeutralItems)], h, isTierTwoDone, 3)
        end

        isTierThreeDone = true
    end

    -- Tier 4 Neutral Items
    if (isTurboMode and Helper.DotaTime() >= 25 * 60 or Helper.DotaTime() >= 50 * 60)
    and not isTierFourDone
    then
        GameRules:SendCustomMessage('Bots receiving Tier 4 Neutral Items...', 0, 0)

        for _, h in pairs(TeamRadiant) do
            NeutralItems.GiveItem(Tier4NeutralItems[RandomInt(1, #Tier4NeutralItems)], h, isTierThreeDone, 4)
        end

        for _, h in pairs(TeamDire) do
            NeutralItems.GiveItem(Tier4NeutralItems[RandomInt(1, #Tier4NeutralItems)], h, isTierThreeDone, 4)
        end

        isTierFourDone = true
    end

end

function NeutralItems.GiveItem(itemName, hero, isTierDone, nTier)
    NeutralItems:RemoveEnhan(hero)
    if hero:HasRoomForItem(itemName, true, true)
    then
        local item = CreateItem(itemName, hero, hero)
        item:SetPurchaseTime(0)

        if NeutralItems.HasNeutralItem(hero)
        and isTierDone
        then
            hero:RemoveItem(hero:GetItemInSlot(DOTA_ITEM_NEUTRAL_SLOT))
            NeutralItems:RemoveEnhan(hero)
            hero:AddItem(item)
        else
            hero:AddItem(item)
        end
        local enhancement = NeutralItems:GetRandomEnhanByTier(nTier)
        if enhancement then
            local enha = CreateItem(enhancement.name, hero, hero)
            enha:SetPurchaseTime(0)
            hero:AddItem(enha)
        end
    end
end

function NeutralItems:RemoveEnhan(unit)
	for idx = 1, 20 do
		local currentItem = unit:GetItemInSlot(idx)
		if currentItem ~= nil then
			if string.find(currentItem:GetName(), "item_enhancement") then
				unit:RemoveItem(currentItem)
				-- return
			end
		end
	end
end

function NeutralItems.HasNeutralItem(hero)
    if not hero then
        return false
    end

    local item = hero:GetItemInSlot(DOTA_ITEM_NEUTRAL_SLOT)
    if item then
        return true
    end

    return false
end

return NeutralItems