-- Cross-PR 7.42 smoke test: validate the INTEGRATED sources rather than
-- assuming independently green pull requests imply compatibility.
-- Lua 5.1 only; no actual Dota engine, gameplay outcome or item service.
local count = 0
local function check(label, fn)
    local ok, err = pcall(fn)
    if not ok then io.stderr:write("FAIL "..label..": "..tostring(err).."\n"); os.exit(1) end
    count=count+1
    io.write("PASS "..label.."\n")
end
local function read(path)
    local f = assert(io.open(path, "rb"), "missing "..path)
    local s=assert(f:read("*a")); f:close();return s
end

check("unified item library loads with removed item unavailable", function()
    -- Isolate true module initialization while returning realistic recipe tables.
    local oldRequire, oldDir, oldComp = require, GetScriptDirectory, GetItemComponents
    GetScriptDirectory=function() return "bots" end
    require=function(name)
        if name=="bots/FunLib/aba_role" then return {} end
        if name=="bots/FunLib/aba_global_overrides" then return {} end
        return oldRequire(name)
    end
    local asked={}
    GetItemComponents=function(name)
        asked[name]=(asked[name] or 0)+1
        if name=="item_helm_of_the_overlord" or name=="item_javelin" then
            error("obsolete item recipe requested: "..name)
        end
        return {{"mock_recipe_"..name}}
    end
    local ok, item=pcall(dofile,"bots/FunLib/aba_item.lua")
    require,GetScriptDirectory,GetItemComponents=oldRequire,oldDir,oldComp
    assert(ok, "item-library module initialization failed: "..tostring(item))
    assert(type(item)=="table", "Item module must return table")
    assert(type(item.sBasicItems)=="table", "Item must publish sBasicItems")
    for _, name in ipairs(item.sBasicItems) do
        assert(name~="item_javelin", "obsolete item in basic-items array")
    end
    assert(item["item_helm_of_the_overlord"]==nil,
           "obsolete recipe remains in item component mapping")
    assert(item["item_helm_of_the_dominator"]~=nil,
           "valid Helm of the Dominator mapping was lost")
    assert(asked["item_helm_of_the_overlord"]==nil,
           "removed Overlord API should never be called at load")
end)

check("combined source preserves unrelated Chen decisions", function()
    local chen=read("bots/BotLib/hero_chen.lua")
    assert(chen:find("function X.ConsiderHandOfGod()",1,true))
    assert(chen:find("function X.ConsiderPenitence()",1,true))
    assert(chen:find("function X.ConsiderHolyPersuasion()",1,true))
    assert(chen:find("function X.ConsiderDivineFavor()",1,true))
    assert(not chen:find("SummonConvert:IsFullyCastable()",1,true))
    assert(not chen:find("Action_UseAbility(SummonConvert)",1,true))
end)

check("passive Furion and no false Abaddon pure-damage branch",function()
    local furion=read("bots/BotLib/hero_furion.lua")
    assert(not furion:find("ActionQueue_UseAbility(CurseOfTheOldGrowth)",1,true))
    assert(furion:find("X.ConsiderWrathOfNature()",1,true))
    local abaddon=read("bots/BotLib/hero_abaddon.lua")
    assert(abaddon:find("function X.ConsiderMistCoil()",1,true))
    assert(not abaddon:find("nDamageType = DAMAGE_TYPE_PURE",1,true))
    assert(not abaddon:find("GetSpecialValueInt('self_damage')",1,true))
end)

check("Meepo / Leshrac / Roshan integrated branches were retained",function()
    local meepo=read("bots/BotLib/hero_meepo.lua")
    assert(not meepo:find("bot:GetAbilityByName('meepo_megameepo')",1,true))
    assert(not meepo:find("MegaMeepo:IsFullyCastable()",1,true))
    local leshrac=read("bots/BotLib/hero_leshrac.lua")
    assert(not leshrac:find("GetAttackProjectileDamageByRange(bot, 1200)",1,true))
    local jmz=read("bots/FunLib/jmz_func.lua")
    assert(jmz:find("GetRoshanKillTime()",1,true))
    assert(jmz:find("function J.IsRoshanAlive()",1,true))
end)

check("five existing production-function regression suites exist",function()
    for _, path in ipairs({
        "tests/test_patch742_compat.lua",
        "tests/test_patch742_roshan_respawn.lua",
        "tests/test_patch742_leshrac_nihilism.lua",
        "tests/test_patch742_furion_passive.lua",
        "tests/test_patch742_chen_abaddon_items.lua",
    }) do assert(#read(path)>100, "missing suite "..path) end
end)

print(string.format("%d integrated assertions passed",count))
