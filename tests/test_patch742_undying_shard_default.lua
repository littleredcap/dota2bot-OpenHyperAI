-- 7.42 Undying: verify the REAL role-based default purchase setup from
-- the production hero Lua, without blocking user-defined Shard purchases.
-- This tests buy-list policy, not whether Dota buys/uses an item in game.
local function read(path)
    local f = assert(io.open(path, "rb"), "cannot open: " .. path)
    local source = assert(f:read("*a"))
    f:close()
    return source
end

local source = read("bots/BotLib/hero_undying.lua")
local begin = assert(source:find("local sUtility =", 1, true))
local ending = assert(source:find("\nfunction X.MinionThink(", begin, true))
local realPurchaseSetup = source:sub(begin, ending - 1)

local prefix = [[
return function(role, customBuy, pvn)
    local X = {}
    local sRole = role
    local J = {Role={}, Skill={}}
    local sTalentList = {"talent_mock"}
    local sAbilityList = {"skill_mock"}
    local nAbilityBuildList = {1,3,1}
    local nTalentBuildList = {10,0}
    local RandomInt = function(a,b) return a end

    function J.Role.IsPvNMode() return pvn == true end
    function J.Role.IsAllShadow() return false end

    function J.SetUserHeroInit(abilities, talents, buys, sells)
        -- Model the existing customization contract: a user's item list
        -- replaces the defaults AFTER they are generated.
        return abilities, talents, customBuy or buys, sells
    end
    function J.Skill.GetSkillList()
        return {"unchanged skill build"}
    end
]]
local suffix = [[
    return {
        buy = X.sBuyList,
        sell = X.sSellList,
        skill = X.sSkillList,
        defaultAbility = X.bDeafaultAbility,
        defaultItem = X.bDeafaultItem,
    }
end
]]
local compiled, errorText = loadstring(prefix .. "\n" .. realPurchaseSetup .. suffix,
                                       "Undying production buy list")
assert(compiled, errorText)
local make = compiled()

local function contains(list, needle)
    for _, v in ipairs(list) do if v == needle then return true end end
    return false
end
local function count(list, needle)
    local n = 0
    for _, v in ipairs(list) do if v == needle then n=n+1 end end
    return n
end
local completed=0
local function test(title, fn)
    local ok, why=pcall(fn)
    if not ok then io.stderr:write("FAIL "..title..": "..tostring(why).."\n"); os.exit(1) end
    completed=completed+1
    print("PASS "..title)
end

for _, role in ipairs({"pos_1","pos_2","pos_3","pos_4","pos_5"}) do
    test(role.." has no unimplemented Zombie Bite default Shard purchase", function()
        local result=make(role)
        assert(type(result.buy)=="table" and #result.buy > 4,
               "role buy list unexpectedly empty")
        assert(count(result.buy,"item_aghanims_shard")==0)
    end)
end

test("pos_2 inherits unchanged pos_1 purchase chain", function()
    local first=make("pos_1").buy
    local mid=make("pos_2").buy
    assert(#first==#mid)
    for i=1,#first do assert(first[i]==mid[i], "pos_2 differs at item "..i) end
end)

test("pos_1 core combat items stay in their existing order", function()
    local buy=make("pos_1").buy
    assert(buy[1]=="item_bristleback_outfit")
    assert(buy[2]=="item_blade_mail")
    assert(contains(buy,"item_black_king_bar"))
    assert(contains(buy,"item_ultimate_scepter"))
    assert(contains(buy,"item_travel_boots"))
end)

test("pos_3 utility and Scepter path remain", function()
    local buy=make("pos_3").buy
    assert(buy[1]=="item_tank_outfit")
    assert(buy[2]=="item_hand_of_midas")
    assert(contains(buy,"item_crimson_guard"))
    assert(contains(buy,"item_ultimate_scepter"))
end)

test("pos_4 support core purchases remain", function()
    local buy=make("pos_4").buy
    assert(buy[1]=="item_blood_grenade")
    assert(contains(buy,"item_arcane_boots"))
    assert(contains(buy,"item_guardian_greaves"))
    assert(contains(buy,"item_ultimate_scepter_2"))
end)

test("pos_5 existing no-Shard build remains intact", function()
    local buy=make("pos_5").buy
    assert(buy[1]=="item_blood_grenade")
    assert(contains(buy,"item_glimmer_cape"))
    assert(contains(buy,"item_boots_of_bearing"))
    assert(contains(buy,"item_ultimate_scepter"))
end)

test("user-customized purchases can still explicitly include Shard", function()
    local chosen={"item_blood_grenade","item_aghanims_shard","item_lotus_orb"}
    local result=make("pos_3",chosen).buy
    assert(#result==3)
    for i=1,3 do assert(result[i]==chosen[i]) end
end)

test("PvN special shop override retains original behavior", function()
    local result=make("pos_4",nil,true).buy
    assert(#result==1 and result[1]=="PvN_antimage")
end)

test("sell rules and manual skill/ability defaults are unaffected", function()
    local result=make("pos_1")
    assert(result.sell[1]=="item_power_treads")
    assert(result.sell[2]=="item_quelling_blade")
    assert(result.defaultAbility==false and result.defaultItem==false)
    assert(result.skill[1]=="unchanged skill build")
end)

test("no invented Zombie Bite action or restrictions were added", function()
    assert(not source:find("GetAbilityByName('undying_bite')",1,true))
    assert(not source:find("ConsiderZombieBite",1,true))
    assert(source:find("function X.ConsiderTombstone()",1,true))
    assert(source:find("function X.ConsiderSoulRip()",1,true))
    assert(source:find("function X.ConsiderFleshGolem()",1,true))
end)

print(string.format("%d Undying production-buy regressions passed",completed))
