-- Exercise Tinker's normal spell dispatcher with visible threats and changing handles.
local NONE, HIGH = 0, 0.8
local function no() return false end
local function yes() return true end
local function empty() return {} end
local function one() return 1 end

local spells, orders, enemies = {}, {}, {}
local retreating, chasing, goingOnSomeone = false, false, false
local bot = {
    GetAbilityByName = function(_, name) return spells[name] end,
    GetLocation = empty, HasModifier = no, GetNearbyLaneCreeps = empty,
    Action_UseAbility = function(_, spell) table.insert(orders, {spell}) end,
    Action_UseAbilityOnLocation = function(_, spell, loc) table.insert(orders, {spell, loc}) end,
}
local enemyLoc = {}
local attackTarget
local enemy = {
    GetLocation = function() return enemyLoc end,
    GetAttackTarget = function() return attackTarget end,
}
local rearm = {GetChannelTime = function() return 2 end, IsInAbilityPhase = no}
local laser = {IsTrained = yes, GetCooldownTimeRemaining = function() return 4 end}
local turrets = {GetCastRange = function() return 600 end, GetManaCost = one}
spells.tinker_rearm = rearm
spells.tinker_laser = laser
spells.tinker_defense_matrix = turrets
spells.unrelated_slot = turrets

local J = {
    Skill = {
        GetTalentList = empty, GetAbilityList = function() return {'laser', 'march', 'unrelated_slot'} end,
        GetRandomBuild = empty, GetTalentBuild = empty, GetSkillList = empty,
    },
    Item = {GetRoleItemsBuyList = function() return 'pos_2' end},
    Role = {IsPvNMode = no, IsAllShadow = no},
    SetUserHeroInit = function(...) return ... end,
    CanNotUseAbility = no, CanCastAbility = function(handle) return handle ~= nil end,
    GetProperTarget = function() return enemy end, IsValidTarget = yes, IsInRange = yes,
    GetHP = one, GetMP = one, IsInLaningPhase = no, GetEnemiesNearLoc = function() return enemies end,
    IsRetreating = function() return retreating end,
    IsChasingTarget = function() return chasing end,
    IsGoingOnSomeone = function() return goingOnSomeone end,
    CanBlinkDagger = no, IsDoingRoshan = no, IsDoingTormentor = no,
    IsPushing = no, IsDefending = no, IsFarming = no,
    GetProperCastRange = function(_, _, range) return range end,
    GetNearbyHeroes = empty, IsInTeamFight = no, GetManaAfter = one,
}

local env = setmetatable({
    GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
    require = function() return J end, dofile = empty, DotaTime = one,
    BOT_ACTION_DESIRE_NONE = NONE, BOT_ACTION_DESIRE_HIGH = HIGH,
}, {__index = _G})
local hero = setfenv(assert(loadfile('bots/BotLib/hero_tinker.lua')), env)()
for _, spell in ipairs({'Laser', 'MarchOfTheMachines', 'WarpFlare', 'KeenConveyance'}) do
    hero['Consider' .. spell] = function() return NONE end
end

local function expectSpell(spell, location)
    orders = {}
    hero.SkillsComplement()
    if spell == nil then
        assert(#orders == 0, 'unexpected spell order')
    else
        assert(#orders == 1 and orders[1][1] == spell and orders[1][2] == location, 'wrong spell order')
    end
end

expectSpell(rearm)
enemies = {enemy}
attackTarget = bot
expectSpell(nil) -- Ready cooldown refresh, but a visible hero is attacking Tinker.
attackTarget = nil
retreating, chasing = true, true
expectSpell(nil)
retreating, chasing = false, false
expectSpell(rearm) -- Nearby enemy without a direct threat does not block the refresh.

spells.tinker_laser = nil
goingOnSomeone = true
expectSpell(nil) -- Missing March and an unavailable Blink do not justify a refresh.
spells.tinker_defense_matrix = nil
expectSpell(nil) -- No named Turrets: a different handle in the build's slot 3 is still invalid.
spells.tinker_deploy_turrets = turrets
expectSpell(turrets, enemyLoc)

print('PASS: Tinker Rearm under visible pressure and exact Deploy Turrets dispatch')
