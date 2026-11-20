-- Regressions for forest0xia/dota2bot-OpenHyperAI#155.
-- Run from root: lua5.1 tests/test_issue155_drop_pickup.lua
-- Extracts and executes production Lua functions under narrow Bot API mocks.
local function read(path)
    local f = assert(io.open(path, "rb"), "Missing " .. path)
    local data = assert(f:read("*a"))
    f:close()
    return data
end

local function extract(path, beginMarker, nextMarker)
    local source = read(path)
    local a = assert(source:find(beginMarker, 1, true), "Missing " .. beginMarker)
    local b = assert(source:find(nextMarker, a + #beginMarker, true), "Missing " .. nextMarker)
    return source:sub(a, b - 1)
end

local discardSource = extract("bots/mode_team_roam_generic.lua",
    "function TrySellOrDropItem()", "\nfunction J.FindLeastExpensiveItemSlot()")
local recoverSource = extract("bots/item_purchase_generic.lua",
    "local function ShouldRecoverOwnedDrop(drop, hero)", "\nfunction ItemPurchaseThink()")

local makeItem = function(name)
    return {
        GetName = function() return name end,
        IsNull = function() return false end,
    }
end

local makeDiscard = assert(loadstring([[
return function(opts)
    local now = 10
    local lastCheckBotToDropTime = 0
    local slots = opts.slots or {}
    local actions = {}
    local bot = {
        ohaDiscardedItems = nil,
        GetLevel = function() return opts.level or 12 end,
        GetNetWorth = function() return opts.worth or 15000 end,
        DistanceFromFountain = function() return opts.distance or 3500 end,
        GetLocation = function() return {x=0,y=0} end,
        FindItemSlot = function(_, name)
            for slot = 0, 8 do
                local item = slots[slot]
                if item ~= nil and item:GetName() == name then
                    return slot
                end
            end
            return -1
        end,
        GetItemInSlot = function(_, slot) return slots[slot] end,
        ActionImmediate_SellItem = function(_, item)
            actions[#actions + 1] = {kind="sell", item=item}
        end,
        Action_DropItem = function(_, item)
            actions[#actions + 1] = {kind="drop", item=item}
        end,
    }
    local Item = {tEarlyConsumableItem = {
        "item_magic_wand", "item_quelling_blade", "item_magic_stick"
    }}
    local Utils = {CountBackpackEmptySpace=function() return opts.empty or 0 end}
    local function DotaTime() return now end
]] .. discardSource .. [[
    return {
        run = function(t) now=t or now; TrySellOrDropItem() end,
        bot = bot,
        actions = actions,
        slots = slots
    }
end
]], "issue155-discard"))()

local shouldRecover = assert(loadstring([[
local Item = {
    GetEmptyInventoryAmount = function(hero)
        local n = 0
        for slot = 0, 8 do
            if hero:GetItemInSlot(slot) == nil then n = n + 1 end
        end
        return n
    end
}
]] .. recoverSource .. [[
return ShouldRecoverOwnedDrop
]], "issue155-recover"))()

local tests = {}
local function test(name, fn)
    tests[#tests+1] = {name=name, fn=fn}
end
local function eq(actual, expected, message)
    if actual ~= expected then
        error(message .. " (wanted="..tostring(expected)..", got="..tostring(actual)..")", 2)
    end
end

local function dropped(hero, item)
    return {owner=hero, item=item, location={x=10,y=10}}
end

test("late-game disposable item is marked before being dropped", function()
    local wand = makeItem("item_magic_wand")
    local d = makeDiscard({slots={[6]=wand}})
    d.run()
    eq(#d.actions, 1, "One action")
    eq(d.actions[1].kind, "drop", "Action type")
    eq(d.bot.ohaDiscardedItems[wand], true, "Persist item-specific discard marker")
end)

test("marked discard is not picked up even when an inventory slot exists", function()
    local stick = makeItem("item_magic_stick")
    local d = makeDiscard({slots={[7]=stick}})
    d.run()
    -- Simulate a completed drop: backpack slot is freed.
    d.slots[7] = nil
    eq(shouldRecover(dropped(d.bot, stick), d.bot), false,
        "Do not retrieve an item we intentionally discarded")
end)

test("important accidental self-drop remains recoverable with free capacity", function()
    local good = makeItem("item_rapier")
    local d = makeDiscard({slots={}})
    eq(shouldRecover(dropped(d.bot, good), d.bot), true,
        "Genuine owned drop should be recovered")
end)

test("no free inventory slot means no pickup command", function()
    local good = makeItem("item_rapier")
    local slots = {}
    for i=0,8 do slots[i] = makeItem("item_branches") end
    local d = makeDiscard({slots=slots})
    eq(shouldRecover(dropped(d.bot, good), d.bot), false,
        "Cannot pick up an item with a completely full inventory")
end)

test("ignore enemy drops, invalid handles, nil drops and tokens", function()
    local d = makeDiscard({})
    local other = makeDiscard({})
    eq(shouldRecover(nil, d.bot), false, "Nil drop")
    eq(shouldRecover({owner=d.bot,item=nil}, d.bot), false, "No item")
    eq(shouldRecover({owner=other.bot,item=makeItem("item_blink")}, d.bot), false, "Other owner")
    eq(shouldRecover({owner=d.bot,item={IsNull=function() return true end}}, d.bot), false, "Null item")
    eq(shouldRecover(dropped(d.bot, makeItem("item_tier1_token")), d.bot), false, "Token exception")
end)

test("only one item is dropped per tick instead of conflicting action spam", function()
    local wand = makeItem("item_magic_wand")
    local blade = makeItem("item_quelling_blade")
    local d = makeDiscard({slots={[6]=wand,[7]=blade}})
    d.run()
    eq(#d.actions, 1, "One item operation in a single tick")
    eq(d.actions[1].item, wand, "First eligible item")
end)

test("near fountain the item is sold, not marked as discard", function()
    local wand = makeItem("item_magic_wand")
    local d = makeDiscard({distance=200, slots={[6]=wand}})
    d.run()
    eq(#d.actions, 1, "One sale")
    eq(d.actions[1].kind, "sell", "Sell near fountain")
    eq(d.bot.ohaDiscardedItems, nil, "No discard marker for a sold item")
end)

test("backpack pressure and minimum level/worth gates remain", function()
    local wand = makeItem("item_magic_wand")
    for _,opts in ipairs({
        {level=5, worth=15000,empty=0},
        {level=12,worth=13000,empty=0},
        {level=12,worth=15000,empty=2},
    }) do
        opts.slots={[6]=wand}
        local d=makeDiscard(opts)
        d.run()
        eq(#d.actions,0,"Pressure/level/worth guard")
    end
end)

test("lotus intentional drops use the same marker as early items", function()
    local src = read("bots/item_purchase_generic.lua")
    local start = assert(src:find("local tDropLotus = {", 1, true))
    local ending = assert(src:find("\n\tif #bot.purchaseListInReverseOrder == 0", start, true))
    local block = src:sub(start, ending)
    assert(block:find("bot.ohaDiscardedItems[item] = true", 1, true),
        "Lotus discard must register the item handle")
    assert(block:find("bot:Action_DropItem(item, bot:GetLocation())", 1, true),
        "Lotus must use the marked handle")
end)

-- Run the real team-roam selection and execution paths, not just the
-- purchase loop. A queued item must be rechecked after it is discarded.
local roamFile = "bots/mode_team_roam_generic.lua"
local roam = read(roamFile)
local roamGuard = ""
if roam:find("local function CanConsiderDroppedItem(drop)", 1, true) then
    roamGuard = extract(roamFile, "local function CanConsiderDroppedItem(drop)", "\nfunction ItemOpsDesire()")
end
local itemOps = extract(roamFile, "function ItemOpsDesire()", "\n-- Swap smoke after killing Roshan")
local runRoam = assert(loadstring([[
return function(opts)
    local bot = {GetLocation = function() return {} end}
    local item = {GetName = function() return "item_healing_lotus" end, IsNull = function() return false end}
    local drop = {item = item, owner = bot, location = {}}
    if opts.marked then bot.ohaDiscardedItems = {[item] = true} end
    if opts.missing then drop.item = nil end
    local ConsiderDroppedTime, minPickItemCost, tryPickCount = 0, 0, 0
    local PickedItem, ignorePickupList, pickup
    local function noop() end
    local Utils = {SetContains=function() return false end, HasValue=function() return false end}
    local J = {Utils=Utils, Item={GetEmptyInventoryAmount=function() return 1 end}}
    local Item = {tEarlyConsumableItem={}}
    Utils.GetLocationToLocationDistance = function() return 0 end
    local function DotaTime() return 3 end
    local function GetDroppedItemList() return {drop} end
    local function GetItemCost() return 100 end
    local function GetUnitToLocationDistance() return 0 end
    local function RemapValClamped() return 0.8 end
    local function TrySellOrDropItem() end
    local function SwapSmokeSupport() end
    local TrySwapInvItemForCheese, TrySwapInvItemForRefresherShard, TrySwapInvItemForClarity = noop, noop, noop
    local TrySwapInvItemForFlask, TrySwapInvItemForSmoke, TrySwapInvItemForMoonshard = noop, noop, noop
    function bot:Action_PickUpItem() pickup = true end
]] .. roamGuard .. "\n" .. itemOps .. [[
    local desire = ItemOpsDesire()
    if opts.markAfterDesire then bot.ohaDiscardedItems = {[item] = true} end
    ItemOpsThink()
    return desire, pickup
end
]], "issue155-team-roam"))()

test("team roam ignores a deliberate lotus discard at selection", function()
    local desire, pickup = runRoam({marked=true})
    eq(desire, nil, "No desire for deliberately discarded lotus")
    eq(pickup, nil, "No pickup for deliberately discarded lotus")
end)

test("team roam rechecks a pending pickup after a deliberate discard", function()
    local desire, pickup = runRoam({markAfterDesire=true})
    eq(desire, 0.8, "Genuine owned item was originally eligible")
    eq(pickup, nil, "Do not execute the stale pickup")
end)

test("team roam still recovers a genuine owned item", function()
    local desire, pickup = runRoam({})
    eq(desire, 0.8, "Eligible owned item still creates pickup desire")
    eq(pickup, true, "Eligible owned item is picked up")
end)

test("team roam ignores a ground record without an item handle", function()
    local desire, pickup = runRoam({missing=true})
    eq(desire, nil, "No desire for invalid handle")
    eq(pickup, nil, "No pickup for invalid handle")
end)

local failures = 0
for _,t in ipairs(tests) do
    local ok, err = pcall(t.fn)
    if ok then
        io.write("PASS: ", t.name, "\n")
    else
        failures = failures + 1
        io.stderr:write("FAIL: ", t.name, " :: ", tostring(err), "\n")
    end
end
if #tests == 0 or failures > 0 then
    io.stderr:write(string.format("%d tests, %d failed\n", #tests, failures))
    os.exit(1)
end
io.write(string.format("%d tests, all passed\n", #tests))
