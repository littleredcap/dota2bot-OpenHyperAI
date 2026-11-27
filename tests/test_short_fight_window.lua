local R = dofile('bots/FunLib/short_fight_window.lua')
assert(R.Hits(3, 0, 1, 0.35) == 3)
assert(R.Hits(3, 2.9, 1, 0.35) == 0)
local p = R.Profile({horizon = 3, attack = 50, contact = 1, period = 1, windup = 0.35, unknownSpell = 150})
assert(p.low <= p.typical and p.typical < p.high and p.typical == 100)
assert(R.TowerDamage(false, 100, 1, 3).high == 0)
assert(R.TowerDamage(true, 100, 1, 3).typical == 100)
local trade = {locked = true, attackers = 2, unseen = 0, enemyHealth = 200,
    damage = {low = 120, typical = 245, high = 290}, incomingHigh = 210,
    selfHealth = 190, canRiskSupport = true, targetWorthwhile = true}
assert(R.CanTrade(trade), 'valuable limited trade')
trade.targetWorthwhile = false
assert(not R.CanTrade(trade), 'do not sacrifice for an equivalent target')
trade.incomingHigh = 100
assert(R.CanTrade(trade), 'short counterdamage can be safe without a sacrifice')
trade.locked = false
assert(not R.CanTrade(trade), 'drop the play when aggro changes')
print('PASS: short fight windows keep uncertainty and reevaluate a bounded tower trade.')

local spells = {
    {eta = 0, cast = 0.4, cost = 70, damage = 120},
    {eta = 0.8, cast = 0.4, cost = 60, damage = 140},
    {eta = 4, cast = 0.3, cost = 0, damage = 500},
}
local budget, busy = R.SpellBudget(spells, 100, 3)
assert(budget == 120 and busy == 0.4, 'do not spend the same mana twice or count a late spell')
budget, busy = R.SpellBudget(spells, 130, 3)
assert(budget == 260 and math.abs(busy-1.2)<0.001, 'combine skills only after cooldown and windup')
local raw = R.Profile({horizon=3,attack=100,contact=4,period=1,windup=.3})
assert(raw.high==0,'out of range for the whole window')
local uncertain = R.Profile({horizon=3,attack=100,contact=4,period=1,windup=.3,unknownSpell=250})
assert(uncertain.low==0 and uncertain.typical==0 and uncertain.high==250,'unknown spell risk is not certain damage')

-- Use the production builder: rooted casters cannot count a walk into spell range.
local f=assert(io.open('bots/FunLib/jmz_func.lua','rb'))
local src=f:read('*a');f:close()
local a=assert(src:find('local function ShortDamageProfile',1,true))
local b=assert(src:find('function J.HasRecentlySeenFightUltimate',a,true))
local main=assert(loadstring(src:sub(a,b-1)..'\nreturn ShortDamageProfile'))
local no=function() return false end
local yes=function() return true end
local spell={GetCastRange=function() return 300 end,GetManaCost=function() return 75 end,
    GetDamageType=function() return 2 end,GetAbilityDamage=function() return 200 end,
    GetCastPoint=function() return .2 end,GetCooldownTimeRemaining=function() return 0 end,GetBehavior=function() return 1 end}
local x, rooted=500,true
local hero={GetAttackRange=function()return 150 end,GetCurrentMovementSpeed=function()return 300 end,
    IsRooted=function()return rooted end,IsSilenced=no,IsDisarmed=no,GetAttackDamage=function()return 30 end,
    GetMana=function()return 100 end,GetSecondsPerAttack=function()return 1.4 end,GetAttackPoint=function()return .3 end,
    GetAbilityInSlot=function(_,slot)return slot==0 and spell or nil end}
local target={IsMagicImmune=no,GetActualIncomingDamage=function(_,amount,kind) return amount * (kind==2 and .75 or .8) end}
local build=setfenv(main,setmetatable({GetUnitToUnitDistance=function()return x end,
    J={CanCastAbilitySoon=function(sp) return sp~=nil end,Utils={AbilityBehaviorHasFlag=yes}},
    GetShortFightWindow=function()return R end,DAMAGE_TYPE_PHYSICAL=1,DAMAGE_TYPE_MAGICAL=2,DAMAGE_TYPE_PURE=4,
    ABILITY_BEHAVIOR_UNIT_TARGET=1},{__index=_G}))()
assert(build(hero,target,2.7,0,true).high==0,'root blocks nonexistent move-to-cast contact')
x=250
local contact=build(hero,target,2.7,0,true)
assert(contact.typical>=100 and contact.low==0,'root does not block a legal spell cast from current position')
x=500; rooted=false
assert(build(hero,target,2.7,0,true).typical>=100,'mobile caster can close a legal short cast gap')
print('PASS: production fight adapter respects rooted spell reach.')
