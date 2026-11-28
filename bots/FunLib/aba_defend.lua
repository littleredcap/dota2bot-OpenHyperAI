--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayFilter(self, callbackfn, thisArg)
    local result = {}
    local len = 0
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            len = len + 1
            result[len] = self[i]
        end
    end
    return result
end

local function __TS__StringIncludes(self, searchString, position)
    if not position then
        position = 1
    else
        position = position + 1
    end
    local index = string.find(self, searchString, position, true)
    return index ~= nil
end

local function __TS__ArraySome(self, callbackfn, thisArg)
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            return true
        end
    end
    return false
end

local function __TS__StringStartsWith(self, searchString, position)
    if position == nil or position < 0 then
        position = 0
    end
    return string.sub(self, position + 1, #searchString + position) == searchString
end

local function __TS__New(target, ...)
    local instance = setmetatable({}, target.prototype)
    instance:____constructor(...)
    return instance
end

local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
end

local function __TS__ClassExtends(target, base)
    target.____super = base
    local staticMetatable = setmetatable({__index = base}, base)
    setmetatable(target, staticMetatable)
    local baseMetatable = getmetatable(base)
    if baseMetatable then
        if type(baseMetatable.__index) == "function" then
            staticMetatable.__index = baseMetatable.__index
        end
        if type(baseMetatable.__newindex) == "function" then
            staticMetatable.__newindex = baseMetatable.__newindex
        end
    end
    setmetatable(target.prototype, base.prototype)
    if type(base.prototype.__index) == "function" then
        target.prototype.__index = base.prototype.__index
    end
    if type(base.prototype.__newindex) == "function" then
        target.prototype.__newindex = base.prototype.__newindex
    end
    if type(base.prototype.__tostring) == "function" then
        target.prototype.__tostring = base.prototype.__tostring
    end
end

local Error, RangeError, ReferenceError, SyntaxError, TypeError, URIError
do
    local function getErrorStack(self, constructor)
        if debug == nil then
            return nil
        end
        local level = 1
        while true do
            local info = debug.getinfo(level, "f")
            level = level + 1
            if not info then
                level = 1
                break
            elseif info.func == constructor then
                break
            end
        end
        if __TS__StringIncludes(_VERSION, "Lua 5.0") then
            return debug.traceback(("[Level " .. tostring(level)) .. "]")
        else
            return debug.traceback(nil, level)
        end
    end
    local function wrapErrorToString(self, getDescription)
        return function(self)
            local description = getDescription(self)
            local caller = debug.getinfo(3, "f")
            local isClassicLua = __TS__StringIncludes(_VERSION, "Lua 5.0") or _VERSION == "Lua 5.1"
            if isClassicLua or caller and caller.func ~= error then
                return description
            else
                return (description .. "\n") .. tostring(self.stack)
            end
        end
    end
    local function initErrorClass(self, Type, name)
        Type.name = name
        return setmetatable(
            Type,
            {__call = function(____, _self, message) return __TS__New(Type, message) end}
        )
    end
    local ____initErrorClass_1 = initErrorClass
    local ____class_0 = __TS__Class()
    ____class_0.name = ""
    function ____class_0.prototype.____constructor(self, message)
        if message == nil then
            message = ""
        end
        self.message = message
        self.name = "Error"
        self.stack = getErrorStack(nil, self.constructor.new)
        local metatable = getmetatable(self)
        if metatable and not metatable.__errorToStringPatched then
            metatable.__errorToStringPatched = true
            metatable.__tostring = wrapErrorToString(nil, metatable.__tostring)
        end
    end
    function ____class_0.prototype.__tostring(self)
        return self.message ~= "" and (self.name .. ": ") .. self.message or self.name
    end
    Error = ____initErrorClass_1(nil, ____class_0, "Error")
    local function createErrorClass(self, name)
        local ____initErrorClass_3 = initErrorClass
        local ____class_2 = __TS__Class()
        ____class_2.name = ____class_2.name
        __TS__ClassExtends(____class_2, Error)
        function ____class_2.prototype.____constructor(self, ...)
            ____class_2.____super.prototype.____constructor(self, ...)
            self.name = name
        end
        return ____initErrorClass_3(nil, ____class_2, name)
    end
    RangeError = createErrorClass(nil, "RangeError")
    ReferenceError = createErrorClass(nil, "ReferenceError")
    SyntaxError = createErrorClass(nil, "SyntaxError")
    TypeError = createErrorClass(nil, "TypeError")
    URIError = createErrorClass(nil, "URIError")
end

local function __TS__ObjectGetOwnPropertyDescriptors(object)
    local metatable = getmetatable(object)
    if not metatable then
        return {}
    end
    return rawget(metatable, "_descriptors") or ({})
end

local function __TS__Delete(target, key)
    local descriptors = __TS__ObjectGetOwnPropertyDescriptors(target)
    local descriptor = descriptors[key]
    if descriptor then
        if not descriptor.configurable then
            error(
                __TS__New(
                    TypeError,
                    ((("Cannot delete property " .. tostring(key)) .. " of ") .. tostring(target)) .. "."
                ),
                0
            )
        end
        descriptors[key] = nil
        return true
    end
    target[key] = nil
    return true
end

local function __TS__ObjectKeys(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = key
    end
    return result
end

local function __TS__ArrayForEach(self, callbackFn, thisArg)
    for i = 1, #self do
        callbackFn(thisArg, self[i], i - 1, self)
    end
end
-- End of Lua Library inline imports
local ____exports = {}
local getDefendState, updateDefendGameStateCache, updateDefendLocationStateCache, updateDefendUnitStateCache, _q, _keyLoc, _recentHeroCountNear, IsValidBuildingTarget, IsBaseThreatActive, WeightedEnemiesAroundLocation, GetBaseCreepThreatCount, GetBaseCreepDefender, GetCreepBaseDefenseDesire, GetThreatenedLane, GetClosestAllyPos, IsThereNoTeammateTravelBootsDefender, GetHighGroundEdgeWaitPoint, ConsiderPingedDefend, okLoc, Localization, PING_DELTA, MAX_DESIRE_CAP, BASE_THREAT_RADIUS, BASE_THREAT_HOLD, CACHE_ENEMY_AROUND_LOC_HZ, CACHE_LASTSEEN_WINDOW, nTeam, _threatLaneSticky, baseThreatUntil, fTraveBootsDefendTime, _cacheEnemyAroundLoc, DEFEND_CACHE_TTL, defendGameStateCache, defendLocationStateCache, defendUnitStateCache
local jmz = require(GetScriptDirectory().."/FunLib/jmz_func")
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Barracks = ____dota.Barracks
local BotActionDesire = ____dota.BotActionDesire
local BotMode = ____dota.BotMode
local BotModeDesire = ____dota.BotModeDesire
local Lane = ____dota.Lane
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local ____native_2Doperators = require(GetScriptDirectory().."/ts_libs/utils/native-operators")
local add = ____native_2Doperators.add
local ____utils = require(GetScriptDirectory().."/FunLib/utils")
local GetLocationToLocationDistance = ____utils.GetLocationToLocationDistance
function getDefendState(bot)
    if not bot._defend then
        bot._defend = {
            defendLoc = GetLaneFrontLocation(nTeam, Lane.Mid, 0),
            weAreStronger = false,
            nInRangeAlly = {},
            nInRangeEnemy = {},
            distanceToLane = {[Lane.Top] = 0, [Lane.Mid] = 0, [Lane.Bot] = 0}
        }
    end
    return bot._defend
end
function updateDefendGameStateCache()
    local now = DotaTime()
    if defendGameStateCache and now - defendGameStateCache.lastUpdate < DEFEND_CACHE_TTL then
        return defendGameStateCache
    end
    local team = GetTeam()
    local enemyTeam = GetOpposingTeam()
    local currentTime = DotaTime()
    local gameMode = GetGameMode()
    local adjustedTime = gameMode == 23 and currentTime * 1.65 or currentTime
    defendGameStateCache = {
        lastUpdate = now,
        currentTime = adjustedTime,
        gameMode = gameMode,
        team = team,
        enemyTeam = enemyTeam,
        ourAncient = GetAncient(team),
        enemyAncient = GetAncient(enemyTeam),
        aliveAllyCount = jmz.GetNumOfAliveHeroes(false),
        aliveEnemyCount = jmz.GetNumOfAliveHeroes(true),
        isLaningPhase = jmz.IsInLaningPhase(),
        isEarlyGame = jmz.IsEarlyGame(),
        isMidGame = jmz.IsMidGame(),
        isLateGame = jmz.IsLateGame(),
        teamFountain = jmz.GetTeamFountain(),
        teamFountainTpPoint = jmz.Utils.GetTeamFountainTpPoint()
    }
    return defendGameStateCache
end
function updateDefendLocationStateCache()
    local now = DotaTime()
    if defendLocationStateCache and now - defendLocationStateCache.lastUpdate < DEFEND_CACHE_TTL then
        return defendLocationStateCache
    end
    local team = GetTeam()
    local enemyTeam = GetOpposingTeam()
    defendLocationStateCache = {
        lastUpdate = now,
        laneFronts = {
            [Lane.Top] = GetLaneFrontLocation(team, Lane.Top, 0),
            [Lane.Mid] = GetLaneFrontLocation(team, Lane.Mid, 0),
            [Lane.Bot] = GetLaneFrontLocation(team, Lane.Bot, 0)
        },
        enemyLaneFronts = {
            [Lane.Top] = GetLaneFrontLocation(enemyTeam, Lane.Top, 0),
            [Lane.Mid] = GetLaneFrontLocation(enemyTeam, Lane.Mid, 0),
            [Lane.Bot] = GetLaneFrontLocation(enemyTeam, Lane.Bot, 0)
        },
        highGroundEdgeWaitPoints = {
            [Lane.Top] = GetHighGroundEdgeWaitPoint(team, Lane.Top),
            [Lane.Mid] = GetHighGroundEdgeWaitPoint(team, Lane.Mid),
            [Lane.Bot] = GetHighGroundEdgeWaitPoint(team, Lane.Bot)
        }
    }
    return defendLocationStateCache
end
function updateDefendUnitStateCache()
    local now = DotaTime()
    if defendUnitStateCache and now - defendUnitStateCache.lastUpdate < DEFEND_CACHE_TTL then
        return defendUnitStateCache
    end
    local teamMembers = {}
    do
        local i = 1
        while i <= #GetTeamPlayers(GetTeam()) do
            local member = GetTeamMember(i)
            if member ~= nil then
                teamMembers[#teamMembers + 1] = member
            end
            i = i + 1
        end
    end
    defendUnitStateCache = {
        lastUpdate = now,
        enemyBuildings = GetUnitList(UnitType.EnemyBuildings),
        alliedHeroes = GetUnitList(UnitType.AlliedHeroes),
        enemyHeroes = __TS__ArrayFilter(
            GetUnitList(UnitType.Enemies),
            function(____, u) return jmz.IsValidHero(u) end
        ),
        alliedCreeps = GetUnitList(UnitType.AlliedCreeps),
        enemyCreeps = __TS__ArrayFilter(
            GetUnitList(UnitType.Enemies),
            function(____, u) return u:IsCreep() or u:IsAncientCreep() end
        ),
        teamMembers = teamMembers
    }
    return defendUnitStateCache
end
function _q(v)
    return v and (tostring(math.floor(v.x / 200) * 200) .. ":") .. tostring(math.floor(v.y / 200) * 200) or "0:0"
end
function _keyLoc(v, r)
    return (_q(v) .. "|") .. tostring(math.floor(r or 0))
end
function _recentHeroCountNear(loc, r, window)
    if window == nil then
        window = CACHE_LASTSEEN_WINDOW
    end
    local gameState = updateDefendGameStateCache()
    local cnt = 0
    for ____, id in ipairs(GetTeamPlayers(gameState.enemyTeam)) do
        do
            local __continue19
            repeat
                if not IsHeroAlive(id) then
                    __continue19 = true
                    break
                end
                local info = GetHeroLastSeenInfo(id)
                if info and info[1] and info[1].time_since_seen <= window and GetLocationToLocationDistance(info[1].location, loc) <= r then
                    cnt = cnt + 1
                end
                __continue19 = true
            until true
            if not __continue19 then
                break
            end
        end
    end
    return cnt
end
function IsValidBuildingTarget(unit)
    return unit ~= nil and unit:IsAlive() and unit:IsBuilding()
end
local function IsStandingHighGroundBuilding(unit)
    return unit ~= nil and not (unit.IsNull and unit:IsNull()) and IsValidBuildingTarget(unit)
end
function IsBaseThreatActive()
    return baseThreatUntil >= 0 and DotaTime() < baseThreatUntil
end
local function GetInnerBaseAttacker(ancient)
    if not IsValidBuildingTarget(ancient) then return nil end
    local left, right = GetTower(nTeam, Tower.Base1), GetTower(nTeam, Tower.Base2)
    local intruder
    for _, enemy in ipairs(updateDefendUnitStateCache().enemyHeroes) do
        if jmz.IsValidHero(enemy) and not jmz.IsSuspiciousIllusion(enemy)
            and GetUnitToUnitDistance(enemy, ancient) <= BASE_THREAT_RADIUS then
            local target = enemy:GetAttackTarget()
            if target and (target == ancient or target == left or target == right)
                and GetUnitToUnitDistance(enemy, target) <= enemy:GetAttackRange() + 125 then return enemy end
            local hittingBuilding = target and not (target.IsNull and target:IsNull()) and target:CanBeSeen() and target:IsBuilding()
            if not hittingBuilding and (GetUnitToUnitDistance(enemy, ancient) <= 950
                or IsStandingHighGroundBuilding(left) and GetUnitToUnitDistance(enemy, left) <= 650
                or IsStandingHighGroundBuilding(right) and GetUnitToUnitDistance(enemy, right) <= 650) then intruder = enemy end
        end
    end
    return intruder
end
function WeightedEnemiesAroundLocation(vLoc, nRadius)
    local now = DotaTime()
    local key = _keyLoc(vLoc, nRadius)
    local c = _cacheEnemyAroundLoc[key]
    if c and now - c.t <= CACHE_ENEMY_AROUND_LOC_HZ then
        return c.count
    end
    local unitState = updateDefendUnitStateCache()
    local count = 0
    for ____, unit in ipairs(unitState.enemyHeroes) do
        if jmz.IsValidHero(unit) and GetUnitToLocationDistance(unit, vLoc) <= nRadius and not jmz.IsSuspiciousIllusion(unit) then
            count = count + (jmz.IsCore(unit) and 1 or 0.5)
        end
    end
    for ____, unit in ipairs(unitState.enemyCreeps) do
        if jmz.IsValid(unit) and GetUnitToLocationDistance(unit, vLoc) <= nRadius then
            local name = unit:GetUnitName()
            if __TS__StringIncludes(name, "upgraded_mega") then
                count = count + 0.6
            elseif __TS__StringIncludes(name, "upgraded") then
                count = count + 0.4
            elseif __TS__StringIncludes(name, "siege") then
                count = count + 0.5
            elseif __TS__StringIncludes(name, "warlock_golem") or __TS__StringIncludes(name, "lone_druid_bear") then
                count = count + 1
            else
                count = count + 0.2
            end
        end
    end
    count = math.floor(count)
    _cacheEnemyAroundLoc[key] = {t = now, count = count}
    return count
end
local function baseCreepPriority(creep, ancient, left, right)
    if not jmz.IsValid(creep) then return 0 end
    local distance = GetUnitToLocationDistance(creep, ancient:GetLocation())
    if distance > BASE_THREAT_RADIUS then return 0 end
    local target = creep:GetAttackTarget()
    if target == ancient or left ~= nil and target == left or right ~= nil and target == right then return 2 end
    local name = creep:GetUnitName()
    return distance <= 1800 and string.find(name, "npc_dota_creep_", 1, true)
        and string.find(name, "_upgraded", 1, true)
        and (distance <= 950 or creep:IsFacingLocation(ancient:GetLocation(), 55)) and 1 or 0
end
function GetBaseCreepThreatCount(ancient)
    if not IsValidBuildingTarget(ancient) then
        return 0
    end
    local leftT4 = GetTower(nTeam, Tower.Base1)
    local rightT4 = GetTower(nTeam, Tower.Base2)
    local count = 0
    for ____, creep in ipairs(updateDefendUnitStateCache().enemyCreeps) do
        if baseCreepPriority(creep, ancient, leftT4, rightT4) > 0 then count = count + 1 end
    end
    return count
end
function GetBaseCreepDefender(ancientLoc, alreadyAssigned)
    local best = nil
    local bestETA = math.huge
    do
        local i = 1
        while i <= #GetTeamPlayers(nTeam) do
            local member = GetTeamMember(i)
            if member and member:IsBot() and jmz.IsValidHero(member) and not member:IsIllusion()
                and not member:IsStunned() and not member:IsHexed() and not member:IsNightmared()
                and not member:IsDisarmed() and not member:IsChanneling() and not member:HasModifier("modifier_teleporting") then
                local eligible = true
                for ____, other in ipairs(alreadyAssigned) do
                    if other:GetPlayerID() == member:GetPlayerID() then
                        eligible = false
                    end
                end
                if eligible then
                    local distance = GetUnitToLocationDistance(member, ancientLoc)
                    local eta = distance / math.max(
                        member:GetCurrentMovementSpeed(),
                        250
                    )
                    if eta < bestETA then
                        best = member
                        bestETA = eta
                    end
                end
            end
            i = i + 1
        end
    end
    return best
end
function ____exports.GetBaseCreepResponse(bot, ancient)
    if DotaTime() < 0 or not IsValidBuildingTarget(ancient) then
        return false, false
    end
    local attackers = GetBaseCreepThreatCount(ancient)
    if attackers == 0 then
        return false, false
    end
    local ancientHP = ancient:GetHealth() / math.max(
        ancient:GetMaxHealth(),
        1
    )
    local critical = attackers >= 4 or ancientHP <= 0.45
    local ancientLoc = ancient:GetLocation()
    if not critical and GetInnerBaseAttacker(ancient) then
        return false, critical
    end
    local required = 1
    if attackers >= 8 or ancientHP <= 0.2 then
        required = 3
    elseif critical then
        required = 2
    end
    local assigned = {}
    do
        local i = 0
        while i < required do
            local defender = GetBaseCreepDefender(ancientLoc, assigned)
            if defender == nil then
                break
            end
            if defender:GetPlayerID() == bot:GetPlayerID() then
                return true, critical
            end
            assigned[#assigned + 1] = defender
            i = i + 1
        end
    end
    return false, critical
end
function GetCreepBaseDefenseDesire(bot, lane, ancient)
    if lane ~= Lane.Mid then
        return nil
    end
    local assigned = ____exports.GetBaseCreepResponse(bot, ancient)
    return assigned and 0.97 or nil
end
function GetThreatenedLane()
    local lanes = {Lane.Top, Lane.Mid, Lane.Bot}
    local bestLane = lanes[1]
    local bestScore = -1
    for ____, ln in ipairs(lanes) do
        local bld, _urgent, tier = unpack(____exports.GetFurthestBuildingOnLane(ln))
        local anchor = IsValidBuildingTarget(bld) and tier < 3 and bld:GetLocation() or GetHighGroundEdgeWaitPoint(nTeam, ln)
        local enemyHeroCnt = _recentHeroCountNear(anchor, 1800)
        local score = enemyHeroCnt * 10
        if enemyHeroCnt == 0 then
            local creepEq = math.min(
                WeightedEnemiesAroundLocation(anchor, 1200) * 0.4,
                0.9
            )
            score = score + creepEq
        end
        if score > bestScore then
            bestScore = score
            bestLane = ln
        end
    end
    if DotaTime() <= _threatLaneSticky["until"] then
        return _threatLaneSticky.lane
    end
    _threatLaneSticky = {
        lane = bestLane,
        ["until"] = DotaTime() + 1.8
    }
    return bestLane
end
function GetClosestAllyPos(tPosList, vLocation)
    local bestPos = nil
    local bestDist = math.huge
    do
        local i = 1
        while i <= 5 do
            local m = GetTeamMember(i)
            if jmz.IsValidHero(m) then
                local p = jmz.GetPosition(m)
                for ____, candidatePos in ipairs(tPosList) do
                    if p == candidatePos then
                        local d = GetUnitToLocationDistance(m, vLocation)
                        if d < bestDist then
                            bestDist = d
                            bestPos = p
                        end
                    end
                end
            end
            i = i + 1
        end
    end
    return bestPos or tPosList[1]
end
function ____exports.GetFurthestBuildingOnLane(lane)
    local cacheKey = (("FurthestBuildingOnLane:" .. tostring(nTeam)) .. ":") .. tostring(lane or -1)
    local cachedVar = jmz.Utils.GetCachedVars(cacheKey, 1)
    if cachedVar ~= nil and (cachedVar[3] < 3 or IsStandingHighGroundBuilding(cachedVar[1])) then
        return cachedVar
    end
    local res = ____exports.GetFurthestBuildingOnLaneHelper(lane)
    jmz.Utils.SetCachedVars(cacheKey, res)
    return res
end
function ____exports.GetFurthestBuildingOnLaneHelper(lane)
    local team = nTeam
    local b
    local function hpMul(u, lo, hi, mlo, mhi)
        local nHealth = u:GetHealth() / u:GetMaxHealth()
        return RemapValClamped(
            nHealth,
            lo,
            hi,
            mlo,
            mhi
        )
    end
    if lane == Lane.Top then
        b = GetTower(team, Tower.Top1)
        if IsValidBuildingTarget(b) then
            return {
                b,
                hpMul(
                    b,
                    0.25,
                    1,
                    0.5,
                    1
                ),
                1
            }
        end
        b = GetTower(team, Tower.Top2)
        if IsValidBuildingTarget(b) then
            return {
                b,
                hpMul(
                    b,
                    0.25,
                    1,
                    1,
                    2
                ),
                2
            }
        end
        b = GetTower(team, Tower.Top3)
        if IsValidBuildingTarget(b) then
            return {
                b,
                hpMul(
                    b,
                    0.25,
                    1,
                    1.5,
                    2
                ),
                3
            }
        end
        b = GetBarracks(team, Barracks.TopMelee)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetBarracks(team, Barracks.TopRanged)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetTower(team, Tower.Base1)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetTower(team, Tower.Base2)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetAncient(team)
        if IsValidBuildingTarget(b) then
            return {b, 3, 4}
        end
    elseif lane == Lane.Mid then
        b = GetTower(team, Tower.Mid1)
        if IsValidBuildingTarget(b) then
            return {
                b,
                hpMul(
                    b,
                    0.25,
                    1,
                    0.5,
                    1
                ),
                1
            }
        end
        b = GetTower(team, Tower.Mid2)
        if IsValidBuildingTarget(b) then
            return {
                b,
                hpMul(
                    b,
                    0.25,
                    1,
                    1,
                    2
                ),
                2
            }
        end
        b = GetTower(team, Tower.Mid3)
        if IsValidBuildingTarget(b) then
            return {
                b,
                hpMul(
                    b,
                    0.25,
                    1,
                    1.5,
                    2
                ),
                3
            }
        end
        b = GetBarracks(team, Barracks.MidMelee)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetBarracks(team, Barracks.MidRanged)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetTower(team, Tower.Base1)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetTower(team, Tower.Base2)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetAncient(team)
        if IsValidBuildingTarget(b) then
            return {b, 3, 4}
        end
    else
        b = GetTower(team, Tower.Bot1)
        if IsValidBuildingTarget(b) then
            return {
                b,
                hpMul(
                    b,
                    0.25,
                    1,
                    0.5,
                    1
                ),
                1
            }
        end
        b = GetTower(team, Tower.Bot2)
        if IsValidBuildingTarget(b) then
            return {
                b,
                hpMul(
                    b,
                    0.25,
                    1,
                    1,
                    2
                ),
                2
            }
        end
        b = GetTower(team, Tower.Bot3)
        if IsValidBuildingTarget(b) then
            return {
                b,
                hpMul(
                    b,
                    0.25,
                    1,
                    1.5,
                    2
                ),
                3
            }
        end
        b = GetBarracks(team, Barracks.BotMelee)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetBarracks(team, Barracks.BotRanged)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetTower(team, Tower.Base1)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetTower(team, Tower.Base2)
        if IsValidBuildingTarget(b) then
            return {b, 2.5, 3}
        end
        b = GetAncient(team)
        if IsValidBuildingTarget(b) then
            return {b, 3, 4}
        end
    end
    return {nil, 1, 0}
end
function IsThereNoTeammateTravelBootsDefender(bot)
    local unitState = updateDefendUnitStateCache()
    for ____, m in ipairs(unitState.teamMembers) do
        if bot ~= m and jmz.IsValidHero(m) and m.travel_boots_defender == true then
            return false
        end
    end
    return true
end
function GetHighGroundEdgeWaitPoint(team, lane)
    local ____temp_3
    if lane == Lane.Top then
        ____temp_3 = GetTower(team, Tower.Top3)
    else
        local ____temp_2
        if lane == Lane.Mid then
            ____temp_2 = GetTower(team, Tower.Mid3)
        else
            ____temp_2 = GetTower(team, Tower.Bot3)
        end
        ____temp_3 = ____temp_2
    end
    local t3 = ____temp_3
    local ____temp_5
    if lane == Lane.Top then
        ____temp_5 = GetBarracks(team, Barracks.TopMelee)
    else
        local ____temp_4
        if lane == Lane.Mid then
            ____temp_4 = GetBarracks(team, Barracks.MidMelee)
        else
            ____temp_4 = GetBarracks(team, Barracks.BotMelee)
        end
        ____temp_5 = ____temp_4
    end
    local raxM = ____temp_5
    local ____temp_7
    if lane == Lane.Top then
        ____temp_7 = GetBarracks(team, Barracks.TopRanged)
    else
        local ____temp_6
        if lane == Lane.Mid then
            ____temp_6 = GetBarracks(team, Barracks.MidRanged)
        else
            ____temp_6 = GetBarracks(team, Barracks.BotRanged)
        end
        ____temp_7 = ____temp_6
    end
    local raxR = ____temp_7
    local anc = GetAncient(team)
    local ____jmz_IsValidBuilding_result_10
    if jmz.IsValidBuilding(t3) then
        ____jmz_IsValidBuilding_result_10 = t3
    else
        local ____jmz_IsValidBuilding_result_9
        if jmz.IsValidBuilding(raxM) then
            ____jmz_IsValidBuilding_result_9 = raxM
        else
            local ____jmz_IsValidBuilding_result_8
            if jmz.IsValidBuilding(raxR) then
                ____jmz_IsValidBuilding_result_8 = raxR
            else
                ____jmz_IsValidBuilding_result_8 = nil
            end
            ____jmz_IsValidBuilding_result_9 = ____jmz_IsValidBuilding_result_8
        end
        ____jmz_IsValidBuilding_result_10 = ____jmz_IsValidBuilding_result_9
    end
    local anchorBuilding = ____jmz_IsValidBuilding_result_10
    if anchorBuilding and jmz.IsValidBuilding(anc) then
        local t = anchorBuilding:GetLocation()
        local a = anc:GetLocation()
        local dir = Vector(a.x - t.x, a.y - t.y, 0)
        local len = math.max(
            1,
            math.sqrt(dir.x * dir.x + dir.y * dir.y)
        )
        return Vector(t.x + dir.x / len * 250, t.y + dir.y / len * 250, 0)
    end
    return jmz.AdjustLocationWithOffsetTowardsFountain(
        GetLaneFrontLocation(team, lane, 0),
        600
    )
end
function ____exports.ShouldDefend(bot, hBuilding, nRadius)
    if not IsValidBuildingTarget(hBuilding) then
        return false
    end
    local gameState = updateDefendGameStateCache()
    local enemyHeroNearby = 0
    for ____, id in ipairs(GetTeamPlayers(gameState.enemyTeam)) do
        if IsHeroAlive(id) then
            local info = GetHeroLastSeenInfo(id)
            if info ~= nil then
                local d = info[1]
                if d ~= nil and d.time_since_seen <= CACHE_LASTSEEN_WINDOW and GetUnitToLocationDistance(hBuilding, d.location) <= 1600 then
                    enemyHeroNearby = enemyHeroNearby + 1
                end
            end
        end
    end
    local unitState = updateDefendUnitStateCache()
    local creepWeights = 0
    for ____, unit in ipairs(unitState.enemyCreeps) do
        if jmz.IsValid(unit) and GetUnitToUnitDistance(hBuilding, unit) <= nRadius then
            local name = unit:GetUnitName()
            if __TS__StringIncludes(name, "siege") and not __TS__StringIncludes(name, "upgraded") then
                creepWeights = creepWeights + 0.5
            elseif __TS__StringIncludes(name, "upgraded_mega") then
                creepWeights = creepWeights + 0.6
            elseif __TS__StringIncludes(name, "upgraded") then
                creepWeights = creepWeights + 0.4
            elseif __TS__StringIncludes(name, "warlock_golem") or __TS__StringIncludes(name, "shadow_shaman_ward") then
                creepWeights = creepWeights + 1
            elseif __TS__StringIncludes(name, "lone_druid_bear") then
                enemyHeroNearby = enemyHeroNearby + 1
            elseif unit:IsCreep() or unit:IsAncientCreep() or unit:IsDominated() or unit:HasModifier("modifier_chen_holy_persuasion") or unit:HasModifier("modifier_dominated") then
                creepWeights = creepWeights + 0.2
            end
        end
    end
    local nNearby = enemyHeroNearby + math.floor(creepWeights)
    if nNearby == 0 then
        return false
    end
    local pos = jmz.GetPosition(bot)
    local result = false
    if nNearby == 1 then
        if pos == 2 or pos == GetClosestAllyPos(
            {4, 5},
            hBuilding:GetLocation()
        ) then
            result = true
        end
    elseif nNearby == 2 then
        if pos == 2 or pos == 3 or pos == GetClosestAllyPos(
            {4, 5},
            hBuilding:GetLocation()
        ) or pos == 1 and GetUnitToUnitDistance(bot, hBuilding) <= 3200 then
            result = true
        end
    elseif nNearby == 3 then
        if pos == 2 or pos == 3 or pos == 4 or pos == 5 or pos == 1 and GetUnitToUnitDistance(bot, hBuilding) <= 3200 then
            result = true
        end
    elseif nNearby >= 4 then
        result = true
    end
    if not result then
        if DotaTime() - fTraveBootsDefendTime >= 20 then
            bot.travel_boots_defender = false
        end
        if bot:GetUnitName() == "npc_dota_hero_tinker" and bot:GetLevel() >= 6 and jmz.CanCastAbility(bot:GetAbilityByName("tinker_keen_teleport")) and IsThereNoTeammateTravelBootsDefender(bot) then
            bot.travel_boots_defender = true
            fTraveBootsDefendTime = DotaTime()
            result = true
        else
            local boots = jmz.GetItem2(bot, "item_travel_boots") or jmz.GetItem2(bot, "item_travel_boots_2")
            if jmz.CanCastAbility(boots) and IsThereNoTeammateTravelBootsDefender(bot) then
                bot.travel_boots_defender = true
                fTraveBootsDefendTime = DotaTime()
                result = true
            end
        end
        if not result and pos == GetClosestAllyPos(
            {2, 3},
            hBuilding:GetLocation()
        ) then
            result = true
        end
    end
    local underFire = bot:WasRecentlyDamagedByAnyHero(5)
    if underFire and result then
        local closestPos = GetClosestAllyPos(
            {2, 3, 4, 5},
            hBuilding:GetLocation()
        )
        if jmz.GetPosition(bot) ~= closestPos then
            return false
        end
    end
    return result
end
function ConsiderPingedDefend(bot, lane, desire, building, tier, nEffAllies, nEnemies)
    local gameState = updateDefendGameStateCache()
    if gameState.isLaningPhase or gameState.aliveAllyCount == 0 then
        return
    end
    if not IsValidBuildingTarget(building) then
        return
    end
    if tier < 2 or desire <= 0.5 then
        return
    end
    if not ____exports.ShouldDefend(bot, building, 1600) then
        return
    end
    jmz.Utils.GameStates = jmz.Utils.GameStates or ({})
    jmz.Utils.GameStates.defendPings = jmz.Utils.GameStates.defendPings or ({pingedTime = GameTime()})
    local defendPings = jmz.Utils.GameStates.defendPings
    if nEffAllies >= 1 and nEffAllies >= nEnemies then
        return
    end
    if GameTime() - defendPings.pingedTime <= 6 then
        return
    end
    local saferLoc = add(
        jmz.AdjustLocationWithOffsetTowardsFountain(
            building:GetLocation(),
            850
        ),
        RandomVector(50)
    )
    local retreaters = jmz.GetRetreatingAlliesNearLoc(saferLoc, 1600)
    if #retreaters == 0 then
        bot:ActionImmediate_Chat(
            Localization.Get("say_come_def"),
            false
        )
        bot:ActionImmediate_Ping(saferLoc.x, saferLoc.y, false)
        defendPings.pingedTime = GameTime()
        defendPings.lane = lane
    end
end
local function GetPrimaryTowerSiege(highGround, earlyResponse)
    local selectedLane, selectedThreat, selectedScore = nil, nil, 0
    for _, candidate in ipairs({Lane.Mid, Lane.Top, Lane.Bot}) do
        local tower, _, tier = unpack(____exports.GetFurthestBuildingOnLane(candidate))
        if (tier >= 3) == highGround and IsValidBuildingTarget(tower) then
            local threat = jmz.GetOuterTowerThreat(tower, candidate)
            -- A visible escorted mid wave can cost two towers. Pre-position
            -- before the first hit, but do not override an active group siege elsewhere.
            local score = threat.score + (not highGround and threat.middleGroup and threat.towerHP > 0.15 and 10 or 0)
            if score > 0 and (not earlyResponse or jmz.IsHighGroundResponseThreat(threat))
                and (selectedThreat == nil or score > selectedScore
                or (score == selectedScore and threat.eta < selectedThreat.eta)) then
                selectedLane, selectedThreat, selectedScore = candidate, threat, score
            end
        end
    end
    return selectedLane, selectedThreat
end

function ____exports.GetDefendDesireHelper(bot, lane)
    if DotaTime() < 0 then return BotModeDesire.None end
    if bot.laneToDefend == nil then
        bot.laneToDefend = lane
    end
    if bot.DefendLaneDesire == nil then
        bot.DefendLaneDesire = {0, 0, 0}
    end
    local gameState = updateDefendGameStateCache()
    local locationState = updateDefendLocationStateCache()
    local team = gameState.team
    local ancient = gameState.ourAncient
    local ds = getDefendState(bot)
    if ds.waveClearLane == lane then
        ds.waveClearLane = nil
        ds.waveClearTower = nil
        ds.waveClearRearTower = nil
        if not bot:HasModifier("modifier_teleporting") then ds.waveClearTeleport = nil end
        ds.waveClearRally = nil
        ds.waveClearGather = nil
        ds.waveClearNeedsGlyph = nil
        ds.waveClearScreen = nil
        bot.ohaOuterTowerHoldUntil = nil
    end
    local trade = bot.ohaOuterTowerTrade
    if trade and trade.expires <= DotaTime() then bot.ohaOuterTowerTrade = nil end
    ds.defendLoc = locationState.laneFronts[lane]
    local distanceToDefendLoc = GetUnitToLocationDistance(bot, ds.defendLoc)
    local creepBaseDesire = GetCreepBaseDefenseDesire(bot, lane, ancient)
    if creepBaseDesire ~= nil then
        if creepBaseDesire > 0.9 and ancient then
            bot._ohaCreepDefenseUntil = DotaTime() + BASE_THREAT_HOLD
            bot.ohaHighGroundResponse = nil
            ds.defendLoc = ancient:GetLocation()
            bot.laneToDefend = Lane.Mid
        end
        return creepBaseDesire
    end
    if GetInnerBaseAttacker(ancient) then baseThreatUntil = DotaTime() + BASE_THREAT_HOLD end
    if ancient and IsBaseThreatActive() then
        if lane ~= Lane.Mid then return BotModeDesire.VeryLow end
        bot.ohaHighGroundResponse, bot.ohaMidCover = nil, nil
        bot.ohaInnerHeroDefenseUntil = baseThreatUntil
        bot.laneToDefend = lane
        ds.defendLoc = ancient:GetLocation()
        return 0.97
    end
    local siegeLane, siege
    if not gameState.isLaningPhase then siegeLane, siege = GetPrimaryTowerSiege(true, true) end
    if siege then
        if lane ~= Lane.Mid and (bot._ohaCreepDefenseUntil or -1) > DotaTime() and ____exports.GetBaseCreepResponse(bot, ancient) then
            return BotModeDesire.VeryLow
        end
        local tower, assignedStage = siege.tower, nil
        local reach, cover = bot:GetAttackRange(), false
        local role, plan
        if jmz.GetPostFightDuty then role, plan = jmz.GetPostFightDuty(bot) end
        if role and plan then
            local building, _, tier = unpack(____exports.GetFurthestBuildingOnLane(plan.lane))
            if building == plan.building and tier >= 3
                and (building == tower or jmz.GetOuterTowerThreat(building, plan.lane).underAttack) then
                tower, siegeLane = building, plan.lane
                cover = role == "cover"
                assignedStage = cover and plan.hold or plan.primary.staging or plan.hold
                if not cover then reach = plan.primary.reach end
            end
        end
        if lane ~= siegeLane then
            if bot.ohaHighGroundResponse and bot.ohaHighGroundResponse.lane == lane then bot.ohaHighGroundResponse = nil end
            return BotModeDesire.VeryLow
        end
        if siege.underAttack and not role and (not plan or plan.building == tower and not plan.primary) then
            local _, orders = jmz.GetOuterTowerResponse(tower:GetLocation(), siege, nil, true)
            local duty = orders[bot:GetPlayerID()]
            if duty then
                reach, cover = duty.reach, duty.cover
                assignedStage = plan and plan.hold or jmz.AdjustLocationWithOffsetTowardsFountain(tower:GetLocation(), 550)
            end
        end
        local rear = ancient and jmz.AdjustLocationWithOffsetTowardsFountain(ancient:GetLocation(), 350)
        local stage = jmz.AdjustLocationWithOffsetTowardsFountain(tower:GetLocation(), 1450)
        local duty = "reserve"
        if assignedStage and IsLocationPassable(assignedStage) and jmz.CanCommitToLaneTeleport(bot, assignedStage, true, 650) then
            stage = assignedStage
            duty = cover and "cover" or "clear"
        elseif not IsLocationPassable(stage) or #jmz.GetLastSeenEnemiesNearLoc(stage, 850) > 0
            or #jmz.GetEnemiesNearLoc(stage, 850) > 0 then stage = rear or stage end
        if not cover then
            local threat = siege.tower == tower and siege or jmz.GetOuterTowerThreat(tower, siegeLane)
            local firing = jmz.GetSiegeFiringPosition(bot, tower, threat, stage)
            if firing then
                stage, duty = firing, "fire"
            elseif not assignedStage then
                local support = jmz.GetSiegeSupportPosition(bot, tower, threat, stage)
                if support then stage, duty = support, "support" end
            end
        end
        bot.ohaHighGroundResponse = {lane = lane, tower = tower, stage = stage, rear = rear, reach = reach, cover = cover, duty = duty, expires = DotaTime() + 1}
        bot.laneToDefend = lane
        ds.defendLoc = stage
        return 0.96
    elseif bot.ohaHighGroundResponse and bot.ohaHighGroundResponse.lane == lane then
        bot.ohaHighGroundResponse = nil
    end
    if jmz.GetExposedMidCover and not IsBaseThreatActive() then
        local role, plan
        if jmz.GetPostFightDuty then role, plan = jmz.GetPostFightDuty(bot) end
        local guard, building, reach, staging
        if plan and role then
            if lane ~= (plan.lane or Lane.Mid) then return BotModeDesire.VeryLow end
            guard, building, reach = bot, plan.building, role == 'clear' and plan.primary.reach or bot:GetAttackRange()
            staging = role == 'clear' and (plan.primary.staging or plan.hold) or nil
        elseif not plan and lane == Lane.Mid then
            guard, building, reach = jmz.GetExposedMidCover(team)
        end
        if guard == bot then
            bot.ohaMidCover = {tower = building, lane = lane, reach = reach, cover = role == 'cover', staging = staging, expires = DotaTime() + 1}
            bot.laneToDefend = lane
            return role == 'cover' and 0.80 or 0.83
        end
        if bot.ohaMidCover and bot.ohaMidCover.lane == lane then bot.ohaMidCover = nil end
        if plan and jmz.HasAssignedWaveDefense(plan, lane) then return BotModeDesire.VeryLow end
    end
    local botLevel = bot:GetLevel()
    if bot:GetAssignedLane() ~= lane and distanceToDefendLoc > 3000 and (jmz.GetPosition(bot) == 1 and botLevel < 6 or jmz.GetPosition(bot) == 2 and botLevel < 6 or jmz.GetPosition(bot) == 3 and botLevel < 5 or jmz.GetPosition(bot) == 4 and botLevel < 4 or jmz.GetPosition(bot) == 5 and botLevel < 4) then
        return BotModeDesire.None
    end
    if botLevel < 3 then
        return BotModeDesire.None
    end
    local teamIsPushing = false
    do
        local i = 1
        while i <= #GetTeamPlayers(nTeam) do
            local member = GetTeamMember(i)
            if member and member ~= bot and member:IsAlive() then
                local mode = member:GetActiveMode()
                if mode == BotMode.PushTowerTop or mode == BotMode.PushTowerMid or mode == BotMode.PushTowerBot then
                    local alliesNear = jmz.GetAlliesNearLoc(
                        member:GetLocation(),
                        1600
                    )
                    if #alliesNear >= 3 then
                        teamIsPushing = true
                        break
                    end
                end
            end
            i = i + 1
        end
    end
    local recentlyHit = bot:WasRecentlyDamagedByAnyHero(5) or bot:WasRecentlyDamagedByTower(5)
    local enemiesAtAncient = ancient and jmz.Utils.CountEnemyHeroesNear(ancient:GetLocation(), 2200) or 0
    local laneAlarm = not recentlyHit and jmz.Utils.CountEnemyHeroesOnHighGround(gameState.team) >= 2
    if laneAlarm then
        local siegeLane = GetPrimaryTowerSiege(true)
        if lane ~= (siegeLane or GetThreatenedLane()) then return BotModeDesire.VeryLow end
        bot.laneToDefend = lane
        ds.defendLoc = GetHighGroundEdgeWaitPoint(team, lane)
    elseif jmz.Utils.GetLocationToLocationDistance(gameState.teamFountainTpPoint, ds.defendLoc) < 3000 then
        local enemyLaneFront = locationState.enemyLaneFronts[lane]
        local eNear = jmz.GetLastSeenEnemiesNearLoc(enemyLaneFront, 1600)
        local aNear = jmz.GetAlliesNearLoc(enemyLaneFront, 1600)
        if GetUnitToLocationDistance(bot, enemyLaneFront) > bot:GetAttackRange() and #eNear <= #aNear + 1 then
            ds.defendLoc = enemyLaneFront
        end
    end
    ds.distanceToLane[lane] = GetUnitToLocationDistance(bot, ds.defendLoc)
    ds.nInRangeAlly = jmz.GetNearbyHeroes(bot, 1600, false, BotMode.None)
    ds.nInRangeEnemy = jmz.GetLastSeenEnemiesNearLoc(
        bot:GetLocation(),
        1600
    )
    ds.weAreStronger = jmz.WeAreStronger(bot, 2500)
    local furthestBuilding, urgentMul, buildingTier = unpack(____exports.GetFurthestBuildingOnLane(lane))
    if not IsValidBuildingTarget(furthestBuilding) then return BotModeDesire.None end
    local hub = furthestBuilding:GetLocation()
    local lEnemies = jmz.GetLastSeenEnemiesNearLoc(hub, 2500)

    local pingFloor = 0
    local human, humanPing = jmz.GetHumanPing()
    if human and humanPing and not humanPing.normal_ping and DotaTime() > 0 then
        local isPinged, pingedLane = jmz.IsPingCloseToValidTower(gameState.team, humanPing, 800, 5)
        if isPinged and lane == pingedLane and GameTime() < humanPing.time + PING_DELTA then
            bot.laneToDefend = lane
            pingFloor = 0.95
        end
    end

    local highGround = buildingTier >= 3
    if pingFloor == 0 and (highGround or not laneAlarm) then
        local primaryLane, threat = GetPrimaryTowerSiege(highGround)
        local nextWave = ds.nextWave
        if nextWave and nextWave.lane == lane and nextWave.tower == furthestBuilding and DotaTime() < nextWave.expires
            and primaryLane == nil then
            ds.waveClearLane = lane
            ds.waveClearTower = nextWave.tower
            ds.waveClearReach = nextWave.reach
            ds.waveClearCover = false
            ds.waveClearTeleport = nil
            bot.ohaOuterTowerTrade = nil
            bot.ohaOuterTowerHoldUntil = nextWave.expires
            bot.laneToDefend = lane
            return 0.84
        end
        if primaryLane == lane then
            local fallback, rearTower
            if not highGround then
                local nextTower = GetTower(team, buildingTier == 1
                    and (lane == Lane.Top and Tower.Top2 or (lane == Lane.Mid and Tower.Mid2 or Tower.Bot2))
                    or (lane == Lane.Top and Tower.Top3 or (lane == Lane.Mid and Tower.Mid3 or Tower.Bot3)))
                if IsValidBuildingTarget(nextTower) then
                    rearTower = nextTower
                    fallback = jmz.AdjustLocationWithOffsetTowardsFountain(nextTower:GetLocation(), 350)
                end
            end
            local delay, assignments = jmz.GetOuterTowerResponse(hub, threat, fallback, highGround)
            if delay then
                local assignment = assignments[bot:GetPlayerID()]
                if assignment ~= nil and (assignment.rally or highGround or jmz.GetHP(furthestBuilding) > 0.15) then
                    ds.waveClearLane = lane
                    ds.waveClearTower = furthestBuilding
                    ds.waveClearRearTower = assignment.rally and rearTower or nil
                    ds.waveClearReach = assignment.reach
                    ds.waveClearCover = assignment.cover
                    ds.waveClearTeleport = assignment.teleport
                    ds.waveClearRally = assignment.rally
                    ds.waveClearGather = assignment.gather
                    ds.waveClearNeedsGlyph = assignment.needsGlyph
                    ds.waveClearScreen = assignment.screen
                    bot.ohaOuterTowerTrade = nil
                    local keepNext = not assignment.gather or assignment.screen or assignment.reach >= 1050
                    if rearTower and not assignment.cover and keepNext and (assignment.rally or threat.count >= 3) and threat.waveSize > 0 then
                        local march = GetUnitToUnitDistance(furthestBuilding, rearTower) / 300
                        ds.nextWave = {lane = lane, tower = rearTower, reach = assignment.reach, expires = DotaTime() + math.min(22, march + 9)}
                    end
                    bot.ohaOuterTowerHoldUntil = DotaTime() + 3
                    bot.laneToDefend = lane
                    if highGround then return 0.96 end
                    if assignment.gather then
                        if lane == Lane.Mid and buildingTier == 1 then return 0.93 end
                        return 0.89
                    end
                    if assignment.rally or assignment.teleport or threat.siege and threat.count <= 1 then return 0.84 end
                    return BotModeDesire.High
                elseif not highGround then
                    bot.ohaOuterTowerTrade = {lane = lane, location = hub, expires = DotaTime() + 6}
                    return BotModeDesire.VeryLow
                end
            elseif trade and trade.lane == lane then
                bot.ohaOuterTowerTrade = nil
            end
        elseif primaryLane ~= nil and not highGround then
            local localThreat = jmz.GetOuterTowerThreat(furthestBuilding, lane)
            if bot:GetAssignedLane() ~= lane or GetUnitToUnitDistance(bot, furthestBuilding) > 1600
                or localThreat.score <= 0 or localThreat.waveSize == 0 then return BotModeDesire.VeryLow end
        end
    end
    if buildingTier <= 2 and not laneAlarm and pingFloor == 0 then
        -- Only the explicit assignments above can send a remote responder.
        local walkReach = 450 + 8 * math.max(250, bot:GetCurrentMovementSpeed())
        if GetUnitToLocationDistance(bot, hub) > walkReach then return BotModeDesire.None end
        if teamIsPushing then return BotModeDesire.VeryLow end
    end
    local pos = jmz.GetPosition(bot)
    local bMyLane = bot:GetAssignedLane() == lane
    if not laneAlarm and #ds.nInRangeEnemy > #ds.nInRangeAlly + 1 and not ds.weAreStronger or not bMyLane and pos == 1 and gameState.isLaningPhase or jmz.IsDoingRoshan(bot) and #jmz.GetAlliesNearLoc(
        jmz.GetCurrentRoshanLocation(),
        2800
    ) >= 3 or jmz.IsDoingTormentor(bot) and (#jmz.GetAlliesNearLoc(
        jmz.GetTormentorLocation(team),
        1600
    ) >= 2 or #jmz.GetAlliesNearLoc(
        jmz.GetTormentorWaitingLocation(team),
        2500
    ) >= 2) and enemiesAtAncient == 0 then
        return BotModeDesire.VeryLow
    end
    local shouldDef = ____exports.ShouldDefend(bot, furthestBuilding, 1600)
    if not shouldDef then
        local dist = ds.distanceToLane[lane]
        local tp = jmz.Utils.GetItemFromFullInventory(bot, "item_tpscroll")
        local nearEnemiesAtBuilding = jmz.GetLastSeenEnemiesNearLoc(
            furthestBuilding:GetLocation(),
            1200
        )
        if not jmz.CanCastAbility(tp) and dist and dist > 4000 and #nearEnemiesAtBuilding == 0 or #nearEnemiesAtBuilding == 0 and #jmz.GetAlliesNearLoc(
            furthestBuilding:GetLocation(),
            1600
        ) >= 1 then
            return BotModeDesire.VeryLow
        end
    end
    local nDefendDesire = GetDefendLaneDesire(lane)
    local nDefendAllies = jmz.GetAlliesNearLoc(hub, 2500)
    local nEffAllies = #nDefendAllies + #jmz.Utils.GetAllyIdsInTpToLocation(hub, 2500)
    if #lEnemies == 0 and (jmz.IsAnyAllyDefending(bot, lane) or not shouldDef) then
        return BotModeDesire.VeryLow
    end
    if #lEnemies == 1 and (nEffAllies > #lEnemies or jmz.IsAnyAllyDefending(bot, lane) and jmz.GetAverageLevel(false) >= jmz.GetAverageLevel(true)) then
        return BotModeDesire.VeryLow
    end
    local capBoost = shouldDef and 0.1 or 0
    local maxDesire = (buildingTier >= 3 and nEffAllies >= #lEnemies and 1 or MAX_DESIRE_CAP) + capBoost
    maxDesire = math.min(maxDesire, 1)
    local baseFloor = shouldDef and BotActionDesire.Low or BotActionDesire.VeryLow
    nDefendDesire = RemapValClamped(
        jmz.GetHP(bot),
        0.75,
        0.2,
        RemapValClamped(
            nDefendDesire * urgentMul,
            0,
            1,
            baseFloor,
            maxDesire
        ),
        BotActionDesire.Low
    )
    if shouldDef and buildingTier <= 2 and pos ~= 1 and #lEnemies >= 2 and not recentlyHit
        and jmz.GetHP(bot) >= 0.55 and GetUnitToLocationDistance(bot, hub) <= 2700
        and #nDefendAllies >= math.min(2, #lEnemies - 1) then
        nDefendDesire = math.max(nDefendDesire, 0.68)
    end
    do
        local dist = ds.distanceToLane[lane]
        if dist and dist < 1600 and #ds.nInRangeEnemy > #ds.nInRangeAlly and not ds.weAreStronger then
            nDefendDesire = RemapValClamped(
                nDefendDesire,
                0,
                1,
                BotActionDesire.VeryLow,
                BotActionDesire.High
            )
        end
    end
    local botTarget = jmz.GetProperTarget(bot)
    if jmz.IsValidHero(botTarget) and jmz.GetHP(botTarget) < 0.6 and jmz.GetHP(bot) > jmz.GetHP(botTarget) and GetUnitToUnitDistance(bot, botTarget) < 1500 then
        nDefendDesire = nDefendDesire * 0.4
    end
    do
        local tp = jmz.Utils.GetItemFromFullInventory(bot, "item_tpscroll")
        local dist = ds.distanceToLane[lane]
        if not jmz.CanCastAbility(tp) and dist and dist > 4000 then
            local nearEnemies = jmz.GetLastSeenEnemiesNearLoc(
                furthestBuilding:GetLocation(),
                1200
            )
            if #nearEnemies == 0 or bot:WasRecentlyDamagedByAnyHero(2) then
                nDefendDesire = nDefendDesire * 0.5
            end
            nDefendDesire = RemapValClamped(
                dist / 4000,
                0,
                2,
                nDefendDesire,
                BotActionDesire.VeryLow
            )
        end
    end
    if IsValidBuildingTarget(furthestBuilding) and furthestBuilding ~= ancient then
        local hp = jmz.GetHP(furthestBuilding)
        if buildingTier == 1 and hp <= 0.15 or buildingTier == 2 and hp <= 0.1 then
            return BotModeDesire.None
        end
    end
    if laneAlarm then
        nDefendDesire = math.max(nDefendDesire, 0.96)
    end
    if pingFloor > 0 then
        nDefendDesire = math.max(nDefendDesire, pingFloor)
    end
    ConsiderPingedDefend(
        bot,
        lane,
        nDefendDesire,
        furthestBuilding,
        buildingTier,
        nEffAllies,
        #lEnemies
    )
    if recentlyHit then
        nDefendDesire = nDefendDesire * 0.4
        if #ds.nInRangeEnemy >= #ds.nInRangeAlly and not ds.weAreStronger then
            nDefendDesire = math.min(nDefendDesire, BotActionDesire.Low)
        end
    end
    if nDefendDesire > 0.7 then
        jmz.Utils.GameStates = jmz.Utils.GameStates or ({})
        jmz.Utils.GameStates.recentDefendTime = DotaTime()
        bot.laneToDefend = lane
    end
    return nDefendDesire
end
okLoc, Localization = pcall(
    require,
    GetScriptDirectory() .. "/FunLib/localization"
)
if not okLoc then
    Localization = {Get = function(_) return "Defend here!" end}
end
local Customize = require(GetScriptDirectory().."/Customize/general")
local ____Customize_1 = Customize
local ____Customize_Enable_0
if Customize.Enable then
    ____Customize_Enable_0 = Customize.ThinkLess
else
    ____Customize_Enable_0 = 1
end
____Customize_1.ThinkLess = ____Customize_Enable_0
PING_DELTA = 5
local SEARCH_RANGE_DEFAULT = 1600
MAX_DESIRE_CAP = 0.98
BASE_THREAT_RADIUS = 2600
local BASE_LEASH_OUTBOUND = 1200
BASE_THREAT_HOLD = 4
CACHE_ENEMY_AROUND_LOC_HZ = 0.35
CACHE_LASTSEEN_WINDOW = 5
nTeam = GetTeam()
_threatLaneSticky = {lane = Lane.Mid, ["until"] = -1}
baseThreatUntil = -1
fTraveBootsDefendTime = 0
_cacheEnemyAroundLoc = {}
DEFEND_CACHE_TTL = 0.5
defendGameStateCache = nil
defendLocationStateCache = nil
defendUnitStateCache = nil
local function GetBaseCreepAttacker(ancient)
    if not IsValidBuildingTarget(ancient) then
        return nil
    end
    local leftT4 = GetTower(nTeam, Tower.Base1)
    local rightT4 = GetTower(nTeam, Tower.Base2)
    local approaching
    for _, creep in ipairs(updateDefendUnitStateCache().enemyCreeps) do
        local priority = baseCreepPriority(creep, ancient, leftT4, rightT4)
        if priority == 2 then return creep end
        if priority == 1 then approaching = creep end
    end
    return approaching
end
function ____exports.GetDefendDesire(bot, lane)
    if bot:IsInvulnerable() or not bot:IsHero() or not bot:IsAlive() or not __TS__StringIncludes(
        bot:GetUnitName(),
        "hero"
    ) or bot:IsIllusion() then
        return BotModeDesire.None
    end
    local res = ____exports.GetDefendDesireHelper(bot, lane)
    bot.defendDesire = res
    return res
end
local function AttackHighGroundWaveFromHere(bot, tower, rear)
    if not rear or bot:IsDisarmed() or GetUnitToLocationDistance(bot, rear) > GetUnitToLocationDistance(tower, rear)
        or (GetUnitToUnitDistance(bot, tower) > 1300 and GetUnitToLocationDistance(bot, rear) > 1500)
        or jmz.GetHP(bot) < 0.55 or bot:WasRecentlyDamagedByAnyHero(2) then return false end
    local current, target = bot:GetAttackTarget(), nil
    for _, creep in ipairs(bot:GetNearbyLaneCreeps(bot:GetAttackRange(), true)) do
        if jmz.IsValid(creep) and creep:CanBeSeen() and jmz.CanBeAttacked(creep)
            and (GetUnitToUnitDistance(creep, tower) <= 950 or GetUnitToLocationDistance(creep, rear) <= 1500) then
            if creep == current then target = creep; break end
            if not target or creep:GetAttackTarget() == tower then target = creep end
        end
    end
    if not target or not jmz.CanCommitToLaneTeleport(bot, bot:GetLocation(), true, 850) then return false end
    return jmz.IssueTowerDefenseAttack(bot, target)
end

function ____exports.DefendThink(bot, lane)
    local now = DotaTime()
    if now < 0 or jmz.CanNotUseAction(bot) then
        return
    end
    local response = bot.ohaHighGroundResponse
    if response and not IsStandingHighGroundBuilding(response.tower) then
        bot.ohaHighGroundResponse, response = nil, nil
    end
    if response and response.lane == lane and now < response.expires then
        if bot:HasModifier("modifier_teleporting") or bot:IsChanneling() or bot:IsCastingAbility()
            or bot:IsUsingAbility() then return end
        if AttackHighGroundWaveFromHere(bot, response.tower, response.rear) then return end
        if GetUnitToLocationDistance(bot, response.stage) > 350 then
            local point = jmz.GetHighGroundWalkPoint(bot, response.stage, response.rear)
            if (not point or GetUnitToLocationDistance(bot, point) <= 180)
                and (bot.ohaIdleReplanUntil or 0) > now and response.rear then
                point = jmz.GetHighGroundWalkPoint(bot, response.rear)
            end
            if point and GetUnitToLocationDistance(bot, point) > 180 then
                bot:Action_MoveToLocation(point)
            elseif not point and bot:GetCurrentActionType() == BOT_ACTION_TYPE_MOVE_TO then
                bot:Action_ClearActions(true)
            end
            return
        end
        jmz.RunOuterTowerHold(bot, response.tower:GetLocation(), response.reach, response.cover, response.stage)
        return
    end
    local guard = bot.ohaMidCover
    if guard and lane == (guard.lane or Lane.Mid) and now < guard.expires and not IsBaseThreatActive()
        and (bot._ohaCreepDefenseUntil or -1) <= now and jmz.IsValidBuilding(guard.tower) then
        local stage = guard.staging
        if stage and not jmz.CanCommitToLaneTeleport(bot, stage, true, 650) then stage = nil end
        jmz.RunOuterTowerHold(bot, guard.tower:GetLocation(), guard.reach, guard.cover, stage, guard)
        return
    end
    if jmz.Utils.IsBotThinkingMeaningfulAction(bot, Customize.ThinkLess, "defend") then
        return
    end
    local botLocation = bot:GetLocation()
    local pathCacheKey = (("pathEnemies_" .. tostring(bot:GetPlayerID())) .. "_") .. tostring(math.floor(now * 2))
    local pathEnemies
    if not bot[pathCacheKey] then
        pathEnemies = jmz.GetLastSeenEnemiesNearLoc(botLocation, 1600)
        bot[pathCacheKey] = pathEnemies
        __TS__ArrayForEach(
            __TS__ObjectKeys(bot),
            function(____, key)
                if __TS__StringStartsWith(key, "pathEnemies_") and key ~= pathCacheKey then
                    __TS__Delete(bot, key)
                end
            end
        )
    else
        pathEnemies = bot[pathCacheKey]
    end
    local ds = getDefendState(bot)
    if bot:WasRecentlyDamagedByAnyHero(5) and #pathEnemies > #ds.nInRangeEnemy then
        local safe = jmz.AdjustLocationWithOffsetTowardsFountain(
            bot:GetLocation(),
            700
        )
        bot:Action_MoveToLocation(add(
            safe,
            jmz.RandomForwardVector(120)
        ))
        return
    end
    if IsBaseThreatActive() or (bot._ohaCreepDefenseUntil or -1) > now then
        local ancient = GetAncient(nTeam)
        local anchor = jmz.AdjustLocationWithOffsetTowardsFountain(
            ancient:GetLocation(),
            200
        )
        local intruder = GetInnerBaseAttacker(ancient)
        if intruder and jmz.CanBeAttacked(intruder) and jmz.IsInRange(bot, intruder, bot:GetAttackRange()) then
            jmz.IssueTowerDefenseAttack(bot, intruder)
            return
        end
        local toAnc = GetUnitToUnitDistance(bot, ancient)
        if toAnc > BASE_LEASH_OUTBOUND then
            local moveLoc = add(
                anchor,
                jmz.RandomForwardVector(250)
            )
            bot:Action_MoveToLocation(moveLoc)
            return
        end
        local nSearchRange = 1400
        local ancientLoc = ancient:GetLocation()
        local enemiesCacheKey = "ancientEnemies_" .. tostring(math.floor(now * 5))
        local enemiesNear
        if not jmz.Utils[enemiesCacheKey] then
            enemiesNear = jmz.GetEnemiesNearLoc(ancientLoc, nSearchRange)
            jmz.Utils[enemiesCacheKey] = enemiesNear
            local utils = jmz.Utils
            __TS__ArrayForEach(
                __TS__ObjectKeys(utils),
                function(____, key)
                    if type(key) == "string" and __TS__StringStartsWith(key, "ancientEnemies_") and key ~= enemiesCacheKey then
                        __TS__Delete(utils, key)
                    end
                end
            )
        else
            enemiesNear = jmz.Utils[enemiesCacheKey]
        end
        local baseCreep = GetBaseCreepAttacker(ancient)
        if baseCreep and (bot._ohaCreepDefenseUntil or -1) > now and GetUnitToUnitDistance(bot, baseCreep) <= BASE_THREAT_RADIUS then
            bot:Action_AttackUnit(baseCreep, true)
            return
        end
        if jmz.IsValidHero(enemiesNear[1]) and jmz.IsInRange(bot, enemiesNear[1], nSearchRange) then
            bot:Action_AttackUnit(enemiesNear[1], true)
            return
        end
        if baseCreep and GetUnitToUnitDistance(bot, baseCreep) <= BASE_THREAT_RADIUS then
            bot:Action_AttackUnit(baseCreep, true)
            return
        end
        local attackMoveLoc = add(
            anchor,
            jmz.RandomForwardVector(300)
        )
        bot:Action_AttackMove(attackMoveLoc)
        return
    end
    local attackRange = bot:GetAttackRange()
    local nSearchRange = attackRange < 900 and 900 or math.min(attackRange, SEARCH_RANGE_DEFAULT)
    if not ds.defendLoc then
        ds.defendLoc = GetLaneFrontLocation(nTeam, lane, 0)
    end
    local bld, _, buildingTier = unpack(____exports.GetFurthestBuildingOnLane(lane))
    local hub = ds.defendLoc
    if IsValidBuildingTarget(bld) then
        hub = bld:GetLocation()
    end
    if not hub then
        hub = GetLaneFrontLocation(nTeam, lane, 0)
    end

    if ds.waveClearLane == lane then
        local primaryLane, threat = GetPrimaryTowerSiege(buildingTier >= 3)
        local nextWave = ds.nextWave
        local following = primaryLane == nil and nextWave and nextWave.lane == lane and nextWave.tower == bld and now < nextWave.expires
        if bld ~= ds.waveClearTower or (primaryLane ~= lane and not following)
            or (bot.ohaOuterTowerHoldUntil or 0) <= now then
            ____exports.OnEnd(bot, lane)
            bot.ohaOuterTowerHoldUntil = nil
            ds.waveClearLane = nil
            return
        end
        local holdTower = ds.waveClearRearTower
        local holdLocation = holdTower and jmz.IsValidBuilding(holdTower) and holdTower:GetLocation() or hub
        local issued
        if ds.waveClearGather and threat then
            issued = jmz.RunOuterTowerContest(bot, bld, threat, ds)
        else
            issued = jmz.RunOuterTowerHold(bot, holdLocation, ds.waveClearReach or attackRange, ds.waveClearCover)
        end
        if issued then
            bot.ohaIssuedOuterHold = lane
        end
        return
    end
    if buildingTier >= 3 then
        local edgeInside = GetHighGroundEdgeWaitPoint(nTeam, lane)
        if IsStandingHighGroundBuilding(bld) then
            local threat = jmz.GetOuterTowerThreat(bld, lane)
            local stage = jmz.GetSiegeFiringPosition(bot, bld, threat, edgeInside)
            jmz.RunOuterTowerHold(bot, bld:GetLocation(), attackRange, false, stage or edgeInside)
        else
            jmz.RunOuterTowerHold(bot, edgeInside, attackRange, false)
        end
        return
    end
    local released = bot.ohaOuterTowerTrade
    if released and released.lane == lane and now < released.expires then
        ____exports.OnEnd(bot, lane)
        if GetUnitToLocationDistance(bot, hub) < 1500 and #jmz.GetLastSeenEnemiesNearLoc(hub, 1600) >= 2 then
            bot:Action_MoveToLocation(jmz.AdjustLocationWithOffsetTowardsFountain(hub, 1650))
        end
        return
    end
    local enemiesAtHub = jmz.GetEnemiesNearLoc(hub, SEARCH_RANGE_DEFAULT)
    if IsValidBuildingTarget(bld) and #enemiesAtHub >= 3
        and jmz.GetAvailableFightAllies(bot, hub, 1500) < math.max(2, #enemiesAtHub - 2) then
        -- No scripted contest was assigned: hold behind the tower instead of
        -- letting the first melee defender start a fight before the backline.
        jmz.RunOuterTowerHold(bot, hub, attackRange, false, jmz.AdjustLocationWithOffsetTowardsFountain(hub, 650))
        return
    end
    if #enemiesAtHub >= 2 and not ds.weAreStronger then
        if jmz.IsValidHero(enemiesAtHub[1]) and jmz.IsInRange(bot, enemiesAtHub[1], attackRange) then
            bot:Action_AttackUnit(enemiesAtHub[1], true)
        else
            bot:Action_MoveToLocation(jmz.AdjustLocationWithOffsetTowardsFountain(hub, 250))
        end
        return
    end
    if jmz.IsValidHero(enemiesAtHub[1]) and jmz.IsInRange(bot, enemiesAtHub[1], ds.weAreStronger and nSearchRange or attackRange) then
        bot:Action_AttackUnit(enemiesAtHub[1], true)
        return
    end
    local nEnemyHeroes = bot:GetNearbyHeroes(SEARCH_RANGE_DEFAULT, true, BotMode.None)
    if jmz.IsValidHero(nEnemyHeroes[1]) and jmz.IsInRange(bot, nEnemyHeroes[1], ds.weAreStronger and nSearchRange or attackRange) then
        bot:Action_AttackUnit(nEnemyHeroes[1], true)
        return
    end
    local creeps = bot:GetNearbyCreeps(900, true)
    if creeps and #creeps > 0 and (not enemiesAtHub or #enemiesAtHub == 0) then
        local best = nil
        local bestDmg = -1
        for ____, c in ipairs(creeps) do
            if jmz.IsValid(c) and jmz.CanBeAttacked(c) then
                local dmg = c:GetAttackDamage()
                if dmg > bestDmg then
                    best = c
                    bestDmg = dmg
                end
            end
        end
        if best then
            bot:Action_AttackUnit(best, true)
            return
        end
    end
    if bld and ____exports.ShouldDefend(bot, bld, 1600) then
        local attackMoveLoc = add(
            hub,
            jmz.RandomForwardVector(300)
        )
        bot:Action_AttackMove(attackMoveLoc)
        return
    end
    local dist = ds.distanceToLane[lane] or GetUnitToLocationDistance(bot, hub)
    if (ds.weAreStronger or #ds.nInRangeAlly >= #ds.nInRangeEnemy) and dist < SEARCH_RANGE_DEFAULT then
        local attackMoveLoc = add(
            hub,
            jmz.RandomForwardVector(300)
        )
        bot:Action_AttackMove(attackMoveLoc)
    elseif dist > SEARCH_RANGE_DEFAULT * 1.7 then
        local moveLoc = add(
            hub,
            jmz.RandomForwardVector(300)
        )
        bot:Action_MoveToLocation(moveLoc)
    else
        local moveLoc = add(
            hub,
            jmz.RandomForwardVector(1000)
        )
        bot:Action_MoveToLocation(moveLoc)
    end
end
function ____exports.OnEnd(bot, lane)
    local ds = bot._defend
    if ds and ds.waveClearLane == lane then ds.waveClearTarget = nil end
    if bot.ohaIssuedOuterHold ~= lane then return end
    bot.ohaIssuedOuterHold = nil
    if not bot:IsUsingAbility() and not bot:IsCastingAbility() and not bot:IsChanneling() then
        bot:Action_ClearActions(true)
    end
end
return ____exports
