local function no() return false end
local function yes() return true end
local function empty() return {} end
local NONE, HIGH = 0, 0.9

local function tormentorFixture(time, turbo, lastKill)
    local state = {time = time, orders = {}}
    local objective = {GetUnitName = function() return 'npc_dota_miniboss' end}
    local members = {}
    for i = 1, 5 do
        local pos = i
        members[i] = {
            IsAlive = function() return state.dead ~= pos end, IsBot = yes, CanBeSeen = yes, GetLocation = empty,
            GetAttackDamage = function() return 500 end, GetAttackSpeed = function() return 1 end,
            GetLevel = function() return 18 end, GetPlayerID = function() return pos end,
            GetNearbyNeutralCreeps = function() return state.bossVisible and {objective} or {} end,
            GetAttackTarget = function() return pos == 4 and state.target or nil end,
        }
    end
    local bot = members[4]
    bot.tormentor_kill_time = lastKill
    bot.GetAttackRange = function() return 600 end
    bot.HasModifier = no
    bot.Action_AttackUnit = function(_, target)
        assert(target == objective, 'wrong objective target')
        state.target = target
        state.orders[#state.orders + 1] = 'attack'
    end
    bot.Action_ClearActions = function()
        state.target = nil
        state.orders[#state.orders + 1] = 'cancel'
    end
    bot.Action_MoveToLocation = function() state.orders[#state.orders + 1] = 'move' end
    local site, waiting = {}, {}
    local ancient = {GetLocation = empty}
    local j = {
        Utils = {
            IsTeamPushingSecondTierOrHighGround = no,
            CountEnemyHeroesNear = function() return 0 end,
            GameStates = {defendPings = {pingedTime = 0}},
            IsBotThinkingMeaningfulAction = no,
        },
        GetCoresAverageNetworth = function() return 12000 end,
        GetTormentorLocation = function() return site end,
        GetTormentorWaitingLocation = function() return waiting end,
        GetAlliesNearLoc = function(point)
            local allies = {}
            if state.nearby and (point == site or point == waiting) then
                for i, member in ipairs(members) do
                    if member:IsAlive() and state.away ~= i and (not state.spread or member == bot) then
                        allies[#allies + 1] = member
                    end
                end
            end
            return allies
        end,
        GetEnemiesNearLoc = function(point) return point == site and state.contested and {{}} or {} end,
        GetLastSeenEnemiesNearLoc = empty,
        GetProperTarget = function(unit) return unit:GetAttackTarget() end,
        IsTormentor = function(unit) return unit == objective end,
        IsAttacking = function(unit) return unit:GetAttackTarget() == objective end,
        IsDoingTormentor = no, IsDoingRoshan = no,
        IsModeTurbo = function() return turbo end,
        IsCore = function(unit) return unit:GetPlayerID() <= 3 end,
        DoesUnitHaveTemporaryBuff = no, GetPosition = function(unit) return unit:GetPlayerID() end,
        GetFirstBotInTeam = function() return members[1] end,
        IsValidHero = yes, IsRealInvisible = no, CanNotUseAction = no,
        IsValid = function(unit) return unit == objective or (unit ~= nil and unit:IsAlive()) end,
        GetHP = function(unit) return unit == state.lowHealth and 0.4 or 0.9 end,
        GetNumOfAliveHeroes = function() return state.dead and 4 or 5 end,
    }
    local env = setmetatable({
        GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
        require = function() return j end,
        DotaTime = function() return state.time end, GameTime = function() return state.time end,
        GetTeam = function() return 2 end, GetOpposingTeam = function() return 3 end,
        GetTeamPlayers = function() return {1, 2, 3, 4, 5} end,
        GetTeamMember = function(i) return members[i] end,
        GetAncient = function() return ancient end, GetTower = function() return {} end,
        GetUnitToUnitDistance = function(_, unit) return unit == objective and 100 or 5000 end,
        GetUnitToLocationDistance = function(unit)
            if state.nearby and state.away ~= unit:GetPlayerID() and (not state.spread or unit == bot) then return 100 end
            return unit == bot and 2000 or 2400
        end,
        IsLocationVisible = function() return state.bossVisible end,
        BOT_MODE_DESIRE_NONE = NONE, BOT_MODE_DESIRE_VERYHIGH = HIGH,
    }, {__index = _G})
    setfenv(assert(loadfile('bots/mode_side_shop_generic.lua')), env)()
    return state, env, members
end

local function tormentorDesire(time, turbo, lastKill)
    local _, mode = tormentorFixture(time, turbo, lastKill)
    return mode.GetDesire()
end

assert(tormentorDesire(899.9, false, 0) == NONE)
assert(tormentorDesire(900, false, 0) == HIGH, 'normal game did not start scouting at 15:00')
assert(tormentorDesire(599.9, true, 0) == NONE)
assert(tormentorDesire(600, true, 0) == HIGH, 'changed the existing Turbo first-spawn behavior')
assert(tormentorDesire(1499.9, false, 900) == NONE)
assert(tormentorDesire(1500, false, 900) == HIGH, 'changed the existing normal respawn interval')
print('PASS: Tormentor scouts at the updated normal spawn time and preserves the existing respawn interval')

do
    local state, mode, members = tormentorFixture(960, false, 0)
    state.nearby, state.bossVisible = true, true
    state.lowHealth = members[2]
    assert(mode.GetDesire() == NONE, 'wait for the team to recover before starting Tormentor')
    mode.Think()
    assert(#state.orders == 0, 'do not approach or attack with a rejected desire')
    state.lowHealth = nil
    assert(mode.GetDesire() == HIGH, 'commit once a healthy team can attend')
    mode.Think()
    assert(state.orders[1] == 'attack')
    state.lowHealth = members[2]
    assert(mode.GetDesire() == NONE, 'team health must be evaluated again after committing')
    mode.OnEnd()
    assert(state.orders[2] == 'cancel', 'stop the persistent attack order when mode ends')
    state.lowHealth = nil
    assert(mode.GetDesire() == HIGH)
    mode.Think()
    state.contested = true
    assert(mode.GetDesire() == NONE, 'visible enemies at the pit cancel the objective desire')
    mode.Think()
    assert(state.orders[3] == 'attack' and state.orders[4] == 'cancel')
    state.contested = false
    assert(mode.GetDesire() == HIGH)
    mode.Think()
    state.spread = true
    mode.Think()
    assert(state.orders[5] == 'attack' and state.orders[6] == 'cancel', 'stop attacking once allies have dispersed')
end

do
    local state, mode = tormentorFixture(960, false, 0)
    state.nearby, state.bossVisible = true, true
    assert(mode.GetDesire() == HIGH)
    state.dead, state.away = 5, 2
    assert(mode.GetDesire() == NONE, 'a departed core must not remain in the readiness count')
end
print('PASS: Tormentor commits with healthy support and stops on a threat or loss of nearby allies')

local file = assert(io.open('bots/ability_item_usage_generic.lua', 'rb'))
local source = file:read('*a')
file:close()
local first = assert(source:find('local function UseGlyph()', 1, true))
local last = assert(source:find('function ItemUsageThink()', first, true))
local glyphCode = assert(loadstring(source:sub(first, last - 1) .. '\nreturn UseGlyph'))
local glyphs = 0
local glyphBot = {
    IsBot = yes,
    ActionImmediate_Glyph = function() glyphs = glyphs + 1 end,
}
local roster = {glyphBot, glyphBot, glyphBot, glyphBot}
local ancient = {GetHealth = function() return 40 end, GetMaxHealth = function() return 100 end}
local env = setmetatable({
    bot = glyphBot,
    X = {IsTargetedByEnemy = yes},
    DotaTime = function() return 100 end,
    GetGlyphCooldown = function() return 0 end,
    GetAncient = function() return ancient end,
    GetTeamMember = function(i) return roster[i] end,
}, {__index = _G})
local useGlyph = setfenv(glyphCode, env)()
useGlyph()
assert(glyphs == 0, 'spent glyph with an uninitialized roster')
roster[5] = {IsBot = no}
useGlyph()
assert(glyphs == 0, 'spent glyph in a mixed human/Bot team')
roster[5] = glyphBot
useGlyph()
assert(glyphs == 1, 'did not defend the threatened Ancient in a full Bot roster')
print('PASS: Glyph tolerates missing teammates and preserves full-Bot defense')
