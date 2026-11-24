local function no() return false end
local function yes() return true end
local function empty() return {} end
local NONE, HIGH = 0, 0.9

local function tormentorDesire(time, turbo, lastKill)
    local members = {}
    for i = 1, 5 do
        local pos = i
        members[i] = {
            IsAlive = yes, IsBot = yes, CanBeSeen = yes, GetLocation = empty,
            GetAttackDamage = function() return 500 end, GetAttackSpeed = function() return 1 end,
            GetLevel = function() return 18 end, GetPlayerID = function() return pos end,
        }
    end
    local bot = members[4]
    bot.tormentor_kill_time = lastKill
    local extinctSite = {}
    local ancient = {GetLocation = empty}
    local j = {
        Utils = {
            IsTeamPushingSecondTierOrHighGround = no,
            CountEnemyHeroesNear = function() return 0 end,
            GameStates = {defendPings = {pingedTime = 0}},
        },
        GetCoresAverageNetworth = function() return 12000 end,
        GetTormentorLocation = function() return extinctSite end,
        GetTormentorWaitingLocation = empty,
        GetAlliesNearLoc = empty, GetEnemiesNearLoc = empty, GetLastSeenEnemiesNearLoc = empty,
        GetProperTarget = function() end, IsTormentor = no, IsDoingTormentor = no, IsDoingRoshan = no,
        IsModeTurbo = function() return turbo end,
        IsCore = function(unit) return unit:GetPlayerID() <= 3 end,
        DoesUnitHaveTemporaryBuff = no, GetPosition = function(unit) return unit:GetPlayerID() end,
        GetFirstBotInTeam = function() return members[1] end,
        IsValidHero = yes, IsRealInvisible = no,
    }
    local env = setmetatable({
        GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
        require = function() return j end,
        DotaTime = function() return time end, GameTime = function() return time end,
        GetTeam = function() return 2 end, GetOpposingTeam = function() return 3 end,
        GetTeamPlayers = function() return {1, 2, 3, 4, 5} end,
        GetTeamMember = function(i) return members[i] end,
        GetAncient = function() return ancient end, GetTower = function() return {} end,
        GetUnitToUnitDistance = function() return 5000 end,
        GetUnitToLocationDistance = function(unit)
            return unit == bot and 2000 or 2400
        end,
        IsLocationVisible = no,
        BOT_MODE_DESIRE_NONE = NONE, BOT_MODE_DESIRE_VERYHIGH = HIGH,
    }, {__index = _G})
    setfenv(assert(loadfile('bots/mode_side_shop_generic.lua')), env)()
    return env.GetDesire()
end

assert(tormentorDesire(899.9, false, 0) == NONE)
assert(tormentorDesire(900, false, 0) == HIGH, 'normal game did not start scouting at 15:00')
assert(tormentorDesire(599.9, true, 0) == NONE)
assert(tormentorDesire(600, true, 0) == HIGH, 'changed the existing Turbo first-spawn behavior')
assert(tormentorDesire(1499.9, false, 900) == NONE)
assert(tormentorDesire(1500, false, 900) == HIGH, 'changed the existing normal respawn interval')
print('PASS: Tormentor scouts at the updated normal spawn time and preserves the existing respawn interval')

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
