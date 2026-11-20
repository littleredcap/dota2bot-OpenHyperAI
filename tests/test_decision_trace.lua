-- Diagnostic core: Lua 5.1 tests, no Dota client.
GetScriptDirectory = function() return "bots" end
package.path = "./?.lua;" .. package.path
DotaTime = function() return _G.testClock or 100 end
local cfg = assert(dofile("bots/Customize/decision_trace.lua"))
assert(cfg.Enable == false, "Must be off by default")
cfg.Enable = true
cfg.WatchHeroes = {"npc_dota_hero_obsidian_destroyer"}
cfg.ReasonInterval = 12
cfg.SampleInterval = 5
package.loaded["bots/Customize/decision_trace"] = cfg
local Trace = assert(dofile("bots/FunLib/oha_decision_trace.lua"))
local stdout, realPrint = {}, print
print = function(s) stdout[#stdout + 1] = s end
local function actor(name)
    local bot = {name=name, mana=40, spells={}, items={}}
    function bot:GetUnitName() return self.name end
    function bot:GetPlayerID() return 1 end
    function bot:GetMana() return self.mana end
    function bot:GetAbilityByName(n) return self.spells[n] end
    function bot:GetAbilityInSlot(slot) return self.slots and self.slots[slot] end
    function bot:GetItemInSlot(slot) return self.items[slot] end
    return bot
end
local function spell(remaining, manaCost, ready)
    return {
        GetLevel=function() return 1 end,
        GetCooldownTimeRemaining=function() return remaining end,
        GetManaCost=function() return manaCost end,
        IsFullyCastable=function() return ready end,
        IsHidden=function() return false end,
    }
end
local tests={}
local function test(name,f) tests[#tests+1]={name,f} end
local function clear() for i=#stdout,1,-1 do stdout[i]=nil end end
test("records reason codes, bot and target without newlines",function()
    clear()
    local b=actor("npc_dota_hero_obsidian_destroyer")
    Trace.Record(b,"BANISH","astral","BLOCK","ALLIED_DAMAGE",{intent="NORMAL",target="enemy\nName",focus=2})
    assert(#stdout==1 and stdout[1]:find("reason=ALLIED_DAMAGE",1,true))
    assert(stdout[1]:find("target=enemy_Name",1,true))
end)
test("same reason is throttled, changed reason immediate",function()
    clear()
    local b=actor("npc_dota_hero_obsidian_destroyer")
    Trace.Record(b,"BANISH","eul","BLOCK","FOCUS")
    Trace.Record(b,"BANISH","eul","BLOCK","FOCUS")
    Trace.Record(b,"BANISH","eul","ALLOW","ESCAPE")
    assert(#stdout==2)
end)
test("watch sample captures spell cooldown and item mana state",function()
    clear()
    local b=actor("npc_dota_hero_obsidian_destroyer")
    b.spells["obsidian_destroyer_astral_imprisonment"]=spell(9.1,10,false)
    b.items[1]=spell(0,80,false)
    b.items[1].GetName=function() return "item_cyclone" end
    _G.testClock=120
    Trace.Observe(b)
    assert(table.concat(stdout,"\n"):find("reason=COOLDOWN",1,true))
    assert(table.concat(stdout,"\n"):find("reason=NO_MANA",1,true))
end)
test("not ready status is not confused with a tactical rejection",function()
    clear()
    local b=actor("npc_dota_hero_obsidian_destroyer")
    b.spells["obsidian_destroyer_astral_imprisonment"]=spell(0,20,true)
    _G.testClock=130
    Trace.Observe(b)
    assert(table.concat(stdout,"\n"):find("verdict=STATUS reason=READY",1,true))
    assert(not table.concat(stdout,"\n"):find("verdict=BLOCK",1,true))
end)
test("hero filter and disabled flag are fail-closed for logging",function()
    clear()
    local b=actor("npc_dota_hero_axe")
    Trace.Record(b,"BANISH","astral","ALLOW","CHECK")
    assert(#stdout==0)
    cfg.Enable=false
    Trace.Record(actor("npc_dota_hero_obsidian_destroyer"),"BANISH","astral","ALLOW","CHECK")
    assert(#stdout==0)
    cfg.Enable=true
end)
test("sampling avoids repeating the expensive inventory scan every frame",function()
    clear()
    _G.testClock=145
    local b=actor("npc_dota_hero_obsidian_destroyer")
    local n=0
    b.GetItemInSlot=function() n=n+1; return nil end
    Trace.Observe(b)
    local scanned=n
    Trace.Observe(b)
    assert(n==scanned and n>0)
end)

test("whole-hero opt-in records unlisted active cooldowns and missing levels",function()
    clear()
    local b=actor("npc_dota_hero_obsidian_destroyer")
    local ready=spell(7.3,20,false)
    ready.GetName=function() return "obsidian_destroyer_arcane_orb" end
    local unlearned=spell(0,0,false)
    unlearned.GetName=function() return "obsidian_destroyer_untrained_active" end
    unlearned.GetLevel=function() return 0 end
    b.slots={[0]=ready,[1]=unlearned}
    cfg.WatchAllActiveAbilities=true
    _G.testClock=170
    Trace.Observe(b)
    local out=table.concat(stdout,"\n")
    assert(out:find("action=obsidian_destroyer_arcane_orb verdict=STATUS reason=COOLDOWN",1,true))
    assert(out:find("action=obsidian_destroyer_untrained_active verdict=STATUS reason=UNLEARNED",1,true))
    cfg.WatchAllActiveAbilities=false
end)

test("whole-hero scanner excludes passive skills, talents and generic_hidden",function()
    clear()
    local b=actor("npc_dota_hero_obsidian_destroyer")
    local passive=spell(0,0,true)
    passive.GetName=function() return "obsidian_destroyer_passive" end
    passive.IsPassive=function() return true end
    local talent=spell(0,0,true)
    talent.GetName=function() return "special_bonus_damage" end
    talent.IsTalent=function() return true end
    local hidden=spell(0,0,false)
    hidden.GetName=function() return "generic_hidden" end
    b.slots={[0]=passive,[1]=talent,[2]=hidden}
    cfg.WatchAllActiveAbilities=true
    _G.testClock=190
    Trace.Observe(b)
    local out=table.concat(stdout,"\n")
    assert(not out:find("action=obsidian_destroyer_passive",1,true))
    assert(not out:find("action=special_bonus_damage",1,true))
    assert(not out:find("action=generic_hidden",1,true))
    cfg.WatchAllActiveAbilities=false
end)

test("cast gate distinguishes silence from ready spell state",function()
    clear()
    local b=actor("npc_dota_hero_obsidian_destroyer")
    b.IsSilenced=function() return true end
    b.spells["obsidian_destroyer_astral_imprisonment"]=spell(0,20,true)
    _G.testClock=210
    Trace.Observe(b)
    local out=table.concat(stdout,"\n")
    assert(out:find("system=BOT action=cast_gate verdict=STATUS reason=SILENCED",1,true))
    assert(out:find("verdict=STATUS reason=READY",1,true))
    assert(not out:find("verdict=BLOCK",1,true))
end)

test("explicit watched ability is not sampled twice when discovered from slots",function()
    clear()
    local b=actor("npc_dota_hero_obsidian_destroyer")
    local a=spell(0,20,true)
    a.GetName=function() return "obsidian_destroyer_astral_imprisonment" end
    b.slots={[1]=a}
    b.GetAbilityByName=function(_,name)
        if name=="obsidian_destroyer_astral_imprisonment" then error("must use already-discovered handle") end
        return nil
    end
    cfg.WatchAllActiveAbilities=true
    _G.testClock=230
    Trace.Observe(b)
    assert(table.concat(stdout,"\n"):find("action=obsidian_destroyer_astral_imprisonment",1,true))
    cfg.WatchAllActiveAbilities=false
end)
local failed=0
for _,t in ipairs(tests) do
    local ok,err=pcall(t[2])
    if ok then io.write("PASS: ",t[1],"\n")
    else failed=failed+1;io.stderr:write("FAIL: ",t[1]," :: ",tostring(err),"\n") end
end
print=realPrint
if failed>0 then os.exit(1) end
io.write(string.format("%d tests, all passed\n",#tests))
