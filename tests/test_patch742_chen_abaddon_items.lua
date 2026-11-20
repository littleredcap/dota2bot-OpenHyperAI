-- 7.42 structural regressions for Chen, Abaddon and common items.
-- Actual production function bodies are executed under Lua 5.1 mocks.
-- No real game client, spell damage prediction or real hero build claims.
local function read(path)
    local f = assert(io.open(path, "rb"), "Cannot open " .. path)
    local s = assert(f:read("*a")); f:close()
    return s
end
local function segment(path, startText, endText)
    local source = read(path)
    local a = assert(source:find(startText, 1, true), "Missing begin: " .. startText)
    local b = assert(source:find(endText, a + #startText, true), "Missing end: " .. endText)
    return source:sub(a, b - 1)
end
local function fixture(fragment, prefix, suffix, label)
    local compiled, err = loadstring(prefix .. "\n" .. fragment .. "\n" .. suffix, label)
    assert(compiled, err)
    return compiled()
end
local tests = {}
local function test(name, callback) tests[#tests+1]={name, callback} end
local function eq(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. " got " .. tostring(actual))
end

-- Ensure an obsolete Chen active cannot be invoked when the 7.42 slot is nil.
local chenSource = read("bots/BotLib/hero_chen.lua")
local chenThink = segment("bots/BotLib/hero_chen.lua",
    "function X.SkillsComplement()", "\nfunction X.ConsiderPenitence()")
local makeChen = fixture(chenThink, [[
return function(s)
    local X, J, bot = {}, {}, {}
    local HandOfGod, Penitence, HolyPersuasion, DivineFavor = "hand", "penitence", "persuasion", "favor"
    local botTarget
    local actions={}
    function J.CanNotUseAbility() return s.cannotUse == true end
    function J.GetProperTarget() return "enemy" end
    function bot:Action_UseAbility(ability) actions[#actions+1]=ability end
    function bot:Action_UseAbilityOnEntity(ability, target) actions[#actions+1]=ability end
    function X.ConsiderHandOfGod() return s.hand and 0.8 or 0 end
    function X.ConsiderPenitence() return s.penitence and 0.8 or 0, "enemy" end
    function X.ConsiderHolyPersuasion() return s.persuasion and 0.8 or 0, "creep" end
    function X.ConsiderDivineFavor() return s.favor and 0.8 or 0, "ally" end
]], [[
    return {think=X.SkillsComplement, actions=actions}
end
]], "chen-actual-skills")

local function checkChen(options, expected)
    local x = makeChen(options)
    x.think()
    eq(#x.actions, expected and 1 or 0)
    if expected then eq(x.actions[1], expected) end
end
test("Chen no candidate is safe without old Summon Convert", function()
    checkChen({}, nil)
end)
test("Chen retains original Hand of God precedence", function()
    checkChen({hand=true, penitence=true, favor=true}, "hand")
end)
test("Chen retains original Penitence before Divine Favor", function()
    checkChen({penitence=true, favor=true}, "penitence")
end)
test("Chen retains Holy Persuasion on creep", function()
    checkChen({persuasion=true, favor=true}, "persuasion")
end)
test("Chen retains Divine Favor", function()
    checkChen({favor=true}, "favor")
end)
test("Chen cannot act bypasses remaining actions", function()
    checkChen({cannotUse=true, hand=true}, nil)
end)
test("Chen contains no old active or old Consider function", function()
    assert(not chenSource:find("GetAbilityByName('chen_summon_convert')",1,true))
    assert(not chenSource:find("function X.ConsiderSummonConvert()",1,true))
    assert(not chenSource:find("Action_UseAbility(SummonConvert)",1,true))
end)

-- Mist Coil remains magic damage with or without Shard (Shard now upgrades
-- Aphotic Shield). Do not infer health cost from deprecated self_damage KV.
local abaSource = read("bots/BotLib/hero_abaddon.lua")
local abaConsider = segment("bots/BotLib/hero_abaddon.lua",
    "function X.ConsiderMistCoil()", "\nfunction X.ConsiderAphoticShield()")
local makeAbaddon = fixture(abaConsider, [[
return function(s)
    local bot, X, J = {}, {}, {}
    local enemy={}
    local record = {damage=nil, type=nil}
    function enemy:HasModifier() return false end
    local MistCoil={}
    local DAMAGE_TYPE_MAGICAL, DAMAGE_TYPE_PURE = 2, 4
    local BOT_MODE_NONE, BOT_ACTION_DESIRE_NONE, BOT_ACTION_DESIRE_HIGH = 0,0,0.8
    function MistCoil:IsFullyCastable() return s.castable ~= false end
    function MistCoil:GetCastRange() return 800 end
    function MistCoil:GetSpecialValueInt(key)
        if key ~= "target_damage" then error("old special value used: " .. key) end
        return 200
    end
    function bot:GetAttackDamage() error("old shard attack damage estimate used") end
    function J.GetProperTarget() return enemy end
    function J.GetNearbyHeroes(_, range, getEnemies)
        return getEnemies and {enemy} or {}
    end
    function J.HasAghanimsShard() return s.shard == true end
    function J.IsGoingOnSomeone() return false end
    function J.IsRetreating() return false end
    function J.IsDoingRoshan() return false end
    function J.IsDoingTormentor() return false end
    function J.IsValidHero() return true end
    function J.CanCastOnMagicImmune() return true end
    function J.IsSuspiciousIllusion() return false end
    function J.CanKillTarget(_, damage, damageType)
        record.damage, record.type = damage, damageType
        return true
    end
]], [[
    return {think=X.ConsiderMistCoil, enemy=enemy, record=record}
end
]], "abaddon-actual-mist-coil")

test("Abaddon without Shard estimates base magical spell damage", function()
    local x=makeAbaddon({})
    local desire, target = x.think()
    eq(desire, 0.8); eq(target, x.enemy)
    eq(x.record.damage, 200); eq(x.record.type, 2)
end)
test("Abaddon with Shard does NOT change Mist Coil to pure attack", function()
    local x=makeAbaddon({shard=true})
    local desire, target = x.think()
    eq(desire, 0.8); eq(target, x.enemy)
    eq(x.record.damage, 200); eq(x.record.type, 2)
end)
test("Abaddon uncastable Mist Coil has no candidate", function()
    local x=makeAbaddon({castable=false})
    local desire, target = x.think()
    eq(desire, 0); eq(target, nil)
end)
test("Abaddon obsolete health-cost and Shard damage approximation removed", function()
    assert(not abaSource:find("GetSpecialValueInt('self_damage')",1,true))
    assert(not abaSource:find("nDamage = bot:GetAttackDamage()",1,true))
    assert(not abaSource:find("DAMAGE_TYPE_PURE",1,true))
end)

-- Examine the real sBasicItems initializer, not just a comment/string search.
local items = segment("bots/FunLib/aba_item.lua",
    "Item['sBasicItems'] = {", "\nItem['sSeniorItems'] = {")
local basics = fixture(items, "local Item = {}", "return Item['sBasicItems']", "actual-basic-items")
local set={}
for _, name in ipairs(basics) do set[name]=true end
test("7.42 removed Javelin from basic purchase classifications", function()
    eq(set.item_javelin, nil)
end)
test("retained valid basic components and new Quarterstaff", function()
    eq(set.item_quarterstaff, true)
    eq(set.item_magic_stick, true)
    eq(set.item_blight_stone, true)
end)

-- 7.42 hero KV slots: Chen Ability4=chen_zealot, CK Ability4=
-- chaos_knight_armageddon; both have ultimate in Ability6. Check actual
-- dynamic skill-list code against mock visible/hidden innate variants.
local skill = segment("bots/FunLib/aba_skill.lua",
    "function X.GetAbilityList( bot )", "\nfunction X.GetRandomBuild(")
local getSkillList = fixture(skill, [[
return function(heroSlots)
    local X = {}
    local generic_hidden = "generic_hidden"
    local DOTA_ABILITY_BEHAVIOR_NOT_LEARNABLE = 64
    local Utils = {}
    function Utils.AbilityBehaviorHasFlag(behavior, flag) return behavior == flag end
    local print = function() end
]], [[
    return X.GetAbilityList(heroSlots)
end
]], "actual-skill-list")

local function heroFromSlots(names, innateHidden)
    local abilities={}
    for slot,name in pairs(names) do
        local ab = {name=name, slot=slot}
        function ab:GetName() return self.name end
        function ab:GetBehavior() return (slot == 3 or slot == 6) and 64 or 0 end
        function ab:IsHidden() return innateHidden and (slot == 3 or slot == 6) end
        function ab:IsTalent() return false end
        function ab:IsUltimate() return slot == 5 end
        abilities[slot]=ab
    end
    return {
        GetUnitName=function()return "npc_dota_hero_test" end,
        GetAbilityInSlot=function(_,slot)return abilities[slot] end,
    }
end
test("Chen new innate does not displace original Q/W/E and R upgrade indices", function()
    local x=getSkillList(heroFromSlots({
        [0]="chen_penitence",[1]="chen_holy_persuasion",[2]="chen_divine_favor",
        [3]="chen_zealot",[4]="generic_hidden",[5]="chen_hand_of_god"},false))
    eq(x[1],"chen_penitence");eq(x[2],"chen_holy_persuasion")
    eq(x[3],"chen_divine_favor");eq(x[6],"chen_hand_of_god")
end)
test("Chaos Knight new innate remains separate from original R index", function()
    local x=getSkillList(heroFromSlots({
        [0]="chaos_knight_chaos_bolt",[1]="chaos_knight_reality_rift",
        [2]="chaos_knight_chaos_strike",[3]="chaos_knight_armageddon",
        [4]="generic_hidden",[5]="chaos_knight_phantasm",
        [6]="chaos_knight_armageddons_flank_end"},true))
    eq(x[1],"chaos_knight_chaos_bolt")
    eq(x[2],"chaos_knight_reality_rift")
    eq(x[3],"chaos_knight_chaos_strike")
    eq(x[6],"chaos_knight_phantasm")
end)

local failed=0
for _, entry in ipairs(tests) do
    local ok, err = pcall(entry[2])
    if ok then io.write("PASS: ",entry[1],"\n")
    else failed=failed+1;io.stderr:write("FAIL: ",entry[1],": ",tostring(err),"\n") end
end
if failed>0 then
    io.stderr:write(string.format("%d tests; %d failed\n",#tests,failed))
    os.exit(1)
end
io.write(string.format("%d tests, all passed\n",#tests))
