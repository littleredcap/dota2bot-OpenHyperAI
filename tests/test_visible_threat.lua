local function value(n) return function() return n end end
local no, yes = value(false), value(true)
local now = 277.6
local env = setmetatable({
    DotaTime=function() return now end, GetUnitToLocationDistance=function(e, p) return math.abs(e.x-p) end,
    DAMAGE_TYPE_PHYSICAL=1, DAMAGE_TYPE_MAGICAL=2, DAMAGE_TYPE_PURE=4,
    ABILITY_BEHAVIOR_UNIT_TARGET=8, ABILITY_BEHAVIOR_POINT=16, ABILITY_TARGET_TEAM_ENEMY=2,
}, {__index=_G})
local threat = setfenv(assert(loadfile('bots/FunLib/visible_threat.lua')), env)()
local j = {IsValidHero=yes, IsSuspiciousIllusion=no, IsStunProjectileSpell=function(n) return n=='dragon_knight_dragon_tail' end,
    GetFightHardControlRemaining=function(e) return e.disabled or 0 end,
    Utils={AbilityBehaviorHasFlag=function(n,flag) return n==flag end}}
local bot = {GetLocation=value(0), IsMagicImmune=no, GetActualIncomingDamage=function(_, raw) return raw * 0.75 end,
    GetHealth=value(341), GetHealthRegen=value(4)}
local function caster(id, x, mana, range, cost, name)
    local ability={GetName=value(name), IsNull=no, IsTrained=yes, IsHidden=no, IsPassive=no,
        GetManaCost=value(cost), GetBehavior=value(8), GetTargetTeam=value(2), GetTargetFlags=value(0), GetCastRange=value(range),
        GetCastPoint=value(0.2), GetAOERadius=value(0), GetDamageType=value(2), GetAbilityDamage=value(70),
        GetSpecialValueFloat=value(0), GetSpecialValueInt=value(0), GetCooldown=value(12), IsItem=no}
    local e={x=x,mana=mana,visible=true,GetPlayerID=value(id),CanBeSeen=function(self) return self.visible end,
        IsRooted=no,IsSilenced=no,IsCastingAbility=no,IsChanneling=no,IsUsingAbility=no,IsDisarmed=no,
        NumModifiers=function(self) return self.effect and 1 or 0 end,
        GetModifierName=function(self) return self.effect end,GetModifierRemainingDuration=function(self) return self.duration end,
        GetCurrentMovementSpeed=value(290),GetAttackDamage=value(62),GetSecondsPerAttack=value(1.5),
        GetAttackPoint=value(0.45), GetAttackRange=value(150),GetMana=function(self) return self.mana end,
        GetStunDuration=value(1.5), GetAbilityInSlot=function(_, slot) if slot==0 then return ability end end,
        GetCurrentActiveAbility=value(ability),GetEstimatedDamageToTarget=function(self, available, _, t, types)
            assert(available and t>0 and types==6);return self.magic or 40
        end}
    return e
end
local dk = caster(7,692,196,150,70,'dragon_knight_dragon_tail')
local enemies = {dk}
local f=assert(io.open('bots/FunLib/jmz_func.lua','rb'));local src=f:read('*a');f:close()
local a=assert(src:find('function J.GetVisibleThreatAt',1,true))
local b=assert(src:find('function J.IsLaningUnderPressure',a,true))
env.J,env.VisibleThreat=j,threat
setfenv(assert(loadstring(src:sub(a,b-1))),env)()
j.GetNearbyHeroes=function() return enemies end
j.IsStunProjectileIncoming=no
assert(not j.CanStartTeleportHere(bot),'4:37: a nonlethal melee stun can arrive during the scroll')
bot.IsMagicImmune=yes
assert(j.CanStartTeleportHere(bot),'debuff immunity protects the channel against a non-piercing stun')
dk:GetAbilityInSlot(0).GetTargetFlags=value(16)
assert(not j.CanStartTeleportHere(bot),'keep respecting a control that pierces debuff immunity')
dk:GetAbilityInSlot(0).GetTargetFlags=value(0)
bot.IsMagicImmune=no
dk.mana=69
assert(j.CanStartTeleportHere(bot),'the same low-mana opponent can neither stun nor kill')
j.IsStunProjectileIncoming=yes
assert(not j.CanStartTeleportHere(bot),'a stun already in flight remains dangerous after the caster spent its mana')
j.IsStunProjectileIncoming=no
dk.mana,dk.x=196,1200
assert(j.CanStartTeleportHere(bot),'the control cannot reach before the channel finishes')
dk.x,dk.IsRooted=692,yes
dk.effect,dk.duration='modifier_rooted',4
assert(j.CanStartTeleportHere(bot),'an immobilized melee opponent cannot close the gap')
dk.IsRooted,dk.IsSilenced=no,yes
dk.effect='modifier_silence'
assert(j.CanStartTeleportHere(bot),'a silenced enemy cannot cast a stun')
dk.duration=0.3
assert(not j.CanStartTeleportHere(bot),'a short silence wears off before the enemy reaches stun range')
dk.IsSilenced,dk.GetStunDuration=no,value(0)
assert(j.CanStartTeleportHere(bot),'spent stun with enough mana still permits escape')
dk.GetStunDuration,dk.IsUsingAbility=value(1.5),yes
assert(j.CanStartTeleportHere(bot),'a witnessed spell release does not become a fresh interrupt')
now=now+6;dk.IsUsingAbility=no
local wl=caster(8,854,347,700,110,'warlock_shadow_word')
dk.x,dk.magic,wl.magic=572,75,170
enemies={dk,wl}
local damage,_,contacts=j.GetVisibleThreatAt(bot,enemies,0,4)
assert(damage>=334 and contacts==2,'at the exposed wave two visible opponents can exhaust 334 HP')
dk.mana,wl.mana=0,0
assert(j.GetVisibleThreatAt(bot,enemies,0,4)<334,'out-of-mana opponents still contribute their reachable physical hits')
dk.visible,wl.visible=false,false
assert(j.GetVisibleThreatAt(bot,enemies,0,4)==0,'no enemy combat information from fog')
dk.visible,wl.visible,dk.mana,wl.mana,dk.magic,wl.magic=true,true,200,350,200,240
dk.GetTeam,bot.GetTeam=value(3),value(2)
dk.GetLocation=function(self) return self.x end
bot.GetAttackRange=value(150)
j.IsGoingOnSomeone,j.IsChasingTarget=yes,yes
j.VectorTowards=function(origin, dest, step) return origin+step end
env.GetUnitToUnitDistance=function(_, target) return target.x end
j.GetEnemiesNearLoc=function(point) assert(point==422);return {dk,wl} end
assert(j.IsLethalChaseStep(bot,dk),'do not continue following a target into lethal visible spell ranges')
dk.mana,wl.mana=0,0
assert(not j.IsLethalChaseStep(bot,dk),'the same route remains available when the visible attackers lack mana')
dk.x=120
assert(not j.IsLethalChaseStep(bot,dk),'a hit already in range is not a chase into new ground')
print('PASS: visible mana, available control, cast time, movement and damage at a proposed position')
