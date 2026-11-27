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
            IsDisarmed = no, IsHexed = no, HasModifier = no,
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
        IsDoingTormentor = no, IsDoingRoshan = no, IsRetreating = no,
        IsModeTurbo = function() return turbo end,
        IsCore = function(unit) return unit:GetPlayerID() <= 3 end,
        DoesUnitHaveTemporaryBuff = yes, GetPosition = function(unit) return unit:GetPlayerID() end,
        GetFirstBotInTeam = function() return members[1] end,
        IsValidHero = yes, IsRealInvisible = no, CanNotUseAction = no,
        IsValid = function(unit) return unit == objective or (unit ~= nil and unit:IsAlive()) end,
        GetHP = function(unit) return unit == state.lowHealth and 0.4 or 0.9 end,
        GetNumOfAliveHeroes = function() return state.dead and 4 or 5 end,
        GetAliveAllyCoreCount = function() return state.dead and state.dead <= 3 and 2 or 3 end,
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

do
    local state, mode, members = tormentorFixture(1800, false, 900)
    state.nearby, state.bossVisible = true, true
    members[1].GetAttackDamage = function() return 1000 end
    members[2].GetAttackDamage = function() return 200 end
    members[3].GetAttackDamage = function() return 200 end
    assert(mode.GetDesire() == HIGH)
    mode.Think()
    assert(state.orders[1] == 'attack', 'temporary effects do not disqualify cores that can attack')
    state.away = 1
    mode.Think()
    assert(state.orders[2] == 'cancel', 'enough damage in the roster is insufficient if the main attacker leaves the pit')
    state.away = nil
    mode.Think()
    assert(state.orders[3] == 'attack', 'resume with enough actual attackers nearby')
    for _, member in ipairs(members) do member.GetAttackDamage = function() return 10 end end
    mode.Think()
    assert(state.orders[4] == 'cancel', 'stop an attack when current damage drops before the next desire update')
    assert(mode.GetDesire() == NONE, 'a prior Tormentor kill does not justify attempting another with too little damage')
end
print('PASS: Tormentor commits with healthy support and stops on a threat or loss of nearby allies')

local file = assert(io.open('bots/ability_item_usage_generic.lua', 'rb'))
local source = file:read('*a')
file:close()
local first = assert(source:find('local function HasGlyphPressure(', 1, true))
local last = assert(source:find('function ItemUsageThink()', first, true))
local glyphCode = assert(loadstring(source:sub(first, last - 1) .. '\nreturn UseGlyph'))
local glyphs = 0
local glyphBot = {
    IsBot = yes,
    ActionImmediate_Glyph = function() glyphs = glyphs + 1 end,
}
local roster = {glyphBot, glyphBot, glyphBot, glyphBot}
local ancientHP, tierOne, clearers, wave, teleports = 40, nil, {}, {}, {}
local towerHP, damageRate = 48, 10
local ancient = {GetHealth = function() return ancientHP end, GetMaxHealth = function() return 100 end}
local env = setmetatable({
    bot = glyphBot,
    X = {IsTargetedByEnemy = function(building) return building == ancient end},
    J = {GetAlliesNearLoc = function() return clearers end, IsValid = yes,
        GetOuterTowerThreat = function() return {count = 3, damageRate = damageRate} end,
        GetLocationToLocationDistance = function(a,b) return math.abs(a.x-b.x) end},
    DotaTime = function() return 100 end,
    GetGlyphCooldown = function() return 0 end,
    GetAncient = function() return ancient end,
    GetTower = function(_, id) return id == 2 and tierOne or nil end,
    GetBarracks = function() end,
    GetUnitList = function() return wave end,
    GetUnitToLocationDistance = function(ally) return ally.distance or 900 end,
    GetIncomingTeleports = function() return teleports end,
    TOWER_TOP_1=1, TOWER_MID_1=2, TOWER_BOT_1=3, TOWER_TOP_2=4, TOWER_MID_2=5, TOWER_BOT_2=6,
    TOWER_TOP_3=7, TOWER_MID_3=8, TOWER_BOT_3=9, TOWER_BASE_1=10, TOWER_BASE_2=11,
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
ancientHP = 100
tierOne = {GetHealth = function() return towerHP end, GetMaxHealth = function() return 100 end,
    GetLocation = function() return {x = 0} end, CanBeSeen = yes}
tierOne.HasModifier = no
local creep = {GetAttackTarget = function() return tierOne end, GetUnitName = function() return 'npc_dota_creep_badguys_melee' end}
wave = {creep, creep, creep}
useGlyph()
assert(glyphs == 1, 'save glyph when no one can make use of the outer tower delay')
clearers[1] = {_defend = {waveClearTower = tierOne}, ohaOuterTowerHoldUntil = 103,
    GetCurrentMovementSpeed = function() return 300 end}
useGlyph()
assert(glyphs == 2, 'glyph a pressured tower before it becomes unsavable if a clearer is almost there')
damageRate = 1
useGlyph()
assert(glyphs == 2, 'a chipped tower and a slow ordinary wave do not warrant early Glyph')
damageRate = 10
clearers[1].distance = 5000
clearers[1].GetPlayerID = function() return 4 end
clearers[1]._defend.waveClearTeleport = {x = 550}
useGlyph()
assert(glyphs == 2, 'a defensive TP plan alone does not justify Glyph')
teleports = {{playerid = 4, location = {x = 550}, time_remaining = 2.5}}
useGlyph()
assert(glyphs == 3, 'an arriving defensive TP can clear within the Glyph window')
clearers[1]._defend.waveClearRearTower = {}
useGlyph()
assert(glyphs == 3, 'the clearer assigned to the rear tower cannot help the front one')
clearers[1]._defend.waveClearRearTower = nil
clearers[1]._defend.waveClearGather = {x = 550}
clearers[1]._defend.waveClearNeedsGlyph = true
clearers[2] = {_defend = {waveClearTower = tierOne, waveClearGather = {x = 550}},
    ohaOuterTowerHoldUntil = 103, distance = 300, GetCurrentMovementSpeed = function() return 300 end}
useGlyph()
assert(glyphs == 3, 'do not Glyph for an incomplete fighting group')
clearers[3] = {_defend = {waveClearTower = tierOne, waveClearGather = {x = 550}},
    ohaOuterTowerHoldUntil = 103, distance = 1400, GetCurrentMovementSpeed = function() return 300 end}
useGlyph()
assert(glyphs == 4, 'Glyph buys time for the confirmed group and an incoming defensive teleport')
tierOne.HasModifier = yes
useGlyph()
assert(glyphs == 4, 'do not spend another charge during the same fortification')
tierOne.HasModifier = no
towerHP, damageRate = 62, 18
clearers[1]._defend.waveClearGather = nil
clearers[2], clearers[3] = nil, nil
useGlyph()
assert(glyphs == 5, 'use Glyph above half HP when damage rate says a committed TP would land too late')
damageRate = 1
useGlyph()
assert(glyphs == 5, 'do not Glyph a healthy tower without imminent damage')
towerHP, damageRate = 50, 10
clearers[1]._defend.waveClearGather = {x = 550}
clearers[1]._defend.waveClearNeedsGlyph = false
clearers[2] = {_defend = {waveClearTower = tierOne, waveClearGather = {x = 550}}, ohaOuterTowerHoldUntil = 103,
    distance = 1150, GetCurrentMovementSpeed = function() return 300 end}
clearers[3] = {_defend = {waveClearTower = tierOne, waveClearGather = {x = 550}, waveClearNeedsGlyph = true},
    ohaOuterTowerHoldUntil = 103, distance = 2050, GetCurrentMovementSpeed = function() return 300 end}
useGlyph()
assert(glyphs == 6, 'use Glyph when the third real defender is six seconds out but the tower has five seconds left')
clearers[3].distance = 3500
useGlyph()
assert(glyphs == 6, 'do not Glyph if the group cannot reach through the extended window')
print('PASS: Glyph tolerates missing teammates and preserves full-Bot defense')

do
    local bought, remaining = 0, 30
    local ancient = {GetLocation = empty, hp = 0.25}
    local bot = {GetLevel = function() return 22 end, IsAlive = no, HasModifier = no, HasBuyback = yes,
        GetRespawnTime = function() return remaining end,
        ActionImmediate_Buyback = function() bought = bought + 1 end}
    local j = {IsMeepoClone = no, Role = {ShouldBuyBack = yes}, GetHP = function(u) return u.hp end,
        GetEnemiesAroundLoc = function() return 3 end, GetAlliesNearLoc = empty}
    local env = setmetatable({bot=bot, J=j, X={SetTalkMessage=no}, DotaTime=function() return 1800 end,
        GetTeam=function() return 2 end, GetAncient=function() return ancient end}, {__index = _G})
    local first = assert(source:find('local function BuybackUsageComplement()', 1, true))
    local last = assert(source:find('local nCourierLastActionTime', first, true))
    local runBuyback = setfenv(assert(loadstring(source:sub(first, last - 1) .. '\nreturn BuybackUsageComplement')), env)()
    remaining = 12
    runBuyback()
    assert(bought == 0, 'wait for a respawn that is already close')
    remaining = 30
    runBuyback()
    assert(bought == 1, 'buy back when the Ancient is low and no defenders can reach it')
end
print('PASS: the emergency buyback uses Ancient health ratio and the actual remaining respawn time')

do
    local file = assert(io.open('bots/FunLib/jmz_func.lua', 'rb'))
    local source = file:read('*a')
    file:close()
    local first = assert(source:find('local inventorySeen = ', 1, true))
    local last = assert(source:find('function J.FindEnemyUnit(', first, true))
    local function hero(id, cost, visible)
        return {cost=cost, visible=visible, GetPlayerID=function() return id end,
            GetUnitName=function() return 'npc_dota_hero_test' end, HasModifier=no,
            GetItemInSlot=function(self, slot)
                assert(self.visible, 'cannot inspect an unseen enemy inventory')
                if slot == 0 then return {GetName=function() return self.cost end} end
            end}
    end
    local ally, firstEnemy, secondEnemy = hero(1, 6000, true), hero(6, 950, true), hero(7, 1100, false)
    local now = 300
    local J = {IsValidHero=function(h) return h.visible end, IsSuspiciousIllusion=no, IsMeepoClone=no}
    local env = setmetatable({J=J, GetTeam=function() return 2 end, GetOpposingTeam=function() return 3 end,
        GetTeamPlayers=function(team) return team == 2 and {1} or {6, 7} end, GetTeamMember=function() return ally end,
        GetUnitList=function() return {firstEnemy, secondEnemy} end, GetItemCost=function(name) return name end,
        DotaTime=function() return now end}, {__index = _G})
    setfenv(assert(loadstring(source:sub(first, last - 1))), env)()
    local own, enemy = J.GetInventoryNetworth()
    assert(own == 6000 and enemy == own, 'partial visibility cannot create a strategic lead')
    now, secondEnemy.visible = 303, true
    own, enemy = J.GetInventoryNetworth()
    assert(own == 6000 and enemy == 2050, 'compare current items with complete observations')
    now, secondEnemy.visible, ally.cost = 408, false, 4100
    own, enemy = J.GetInventoryNetworth()
    assert(own == 4100 and enemy == own, 'expire old opponent intel and use the current own inventory')
end
