-- OHA decision diagnostics: disabled by default, Lua 5.1 compatible.
-- Read-only observation of our own bot and visible targets. No HTTP or files.
local Trace = {}
local function loadConfig()
    local ok, config = pcall(require, "game/Customize/decision_trace")
    if ok and type(config) == "table" then return config end
    if type(GetScriptDirectory) == "function" then
        ok, config = pcall(require, GetScriptDirectory() .. "/Customize/decision_trace")
        if ok and type(config) == "table" then return config end
    end
    return { Enable = false }
end
local config = loadConfig()
local lastReasonAt = {}

local function listed(names, value)
    if type(names) ~= "table" or #names == 0 then return true end
    for _, name in ipairs(names) do
        if name == value then return true end
    end
    return false
end

function Trace.Enabled(bot)
    if config.Enable ~= true then return false end
    if bot == nil then return false end
    return listed(config.WatchHeroes, bot:GetUnitName())
end

local function safe(value)
    local str = tostring(value)
    return (str:gsub("[\r\n\t ]+", "_"):gsub("[^%w_%-%./:=]", "?"):sub(1, 80))
end

-- Emit one machine-greppable line. Same reason is throttled; reason changes
-- are emitted immediately. Information in details MUST be legally visible.
function Trace.Record(bot, system, action, verdict, reason, details)
    if not Trace.Enabled(bot) then return end
    local now = DotaTime()
    local id = bot:GetPlayerID()
    local key = tostring(id) .. "|" .. tostring(system) .. "|" .. tostring(action) .. "|" .. tostring(verdict) .. "|" .. tostring(reason)
    local minInterval = tonumber(config.ReasonInterval) or 12
    if lastReasonAt[key] and now - lastReasonAt[key] < minInterval then return end
    lastReasonAt[key] = now
    local line = "[OHA_DECISION] t=" .. safe(math.floor(now * 10) / 10)
        .. " pid=" .. safe(id) .. " hero=" .. safe(bot:GetUnitName())
        .. " system=" .. safe(system) .. " action=" .. safe(action)
        .. " verdict=" .. safe(verdict) .. " reason=" .. safe(reason)
    if type(details) == "table" then
        for _, keyName in ipairs({"intent", "target", "focus", "chasing", "cooldown", "mana", "note"}) do
            if details[keyName] ~= nil then
                line = line .. " " .. keyName .. "=" .. safe(details[keyName])
            end
        end
    end
    print(line)
end

-- Status is not a cast decision. READY means only that the engine reports
-- the ability as usable, not that a target or tactical reason was present.
local function observe(bot, action, ability, category)
    local status, details = "MISSING", {}
    if ability ~= nil then
        if ability.IsHidden and ability:IsHidden() then
            status = "HIDDEN"
        elseif category == "ABILITY" and ability.GetLevel and ability:GetLevel() == 0 then
            status = "UNLEARNED"
        else
            local remaining = ability.GetCooldownTimeRemaining and ability:GetCooldownTimeRemaining() or 0
            local manaCost = ability.GetManaCost and ability:GetManaCost() or 0
            if remaining > 0 then
                status = "COOLDOWN"
                details.cooldown = math.floor(remaining * 10) / 10
            elseif manaCost > bot:GetMana() then
                status = "NO_MANA"
                details.mana = math.floor(bot:GetMana())
            elseif ability.IsFullyCastable and ability:IsFullyCastable() then
                status = "READY"
            else
                status = "UNAVAILABLE"
            end
        end
    end
    Trace.Record(bot, category, action, "STATUS", status, details)
end

-- Cast-gate status explains why a READY spell still cannot be proposed.
-- NONE means no obvious engine state blocker, NOT that the AI should cast.
local function observeBotCastGate(bot)
    local reason = "NO_OBVIOUS_BLOCK"
    if bot.IsChanneling and bot:IsChanneling() then reason = "CHANNELING"
    elseif bot.IsUsingAbility and bot:IsUsingAbility() then reason = "USING_ABILITY"
    elseif bot.IsStunned and bot:IsStunned() then reason = "STUNNED"
    elseif bot.IsHexed and bot:IsHexed() then reason = "HEXED"
    elseif bot.IsSilenced and bot:IsSilenced() then reason = "SILENCED" end
    Trace.Record(bot, "BOT", "cast_gate", "STATUS", reason)
end

function Trace.Observe(bot)
    if not Trace.Enabled(bot) then return end
    local now = DotaTime()
    local sampleInterval = math.max(tonumber(config.SampleInterval) or 5, 1)
    if bot._ohaNextDecisionSample and now < bot._ohaNextDecisionSample then return end
    bot._ohaNextDecisionSample = now + sampleInterval
    observeBotCastGate(bot)

    -- Optional whole-hero scanning: include learned/unlearned active slots,
    -- but exclude talents, passive skills and generic_hidden placeholders.
    -- When both explicit and auto watched, emit only once per name.
    local seen = {}
    if config.WatchAllActiveAbilities == true and bot.GetAbilityInSlot then
        for slot = 0, 10 do
            local ability = bot:GetAbilityInSlot(slot)
            if ability and ability.GetName
                and not (ability.IsTalent and ability:IsTalent())
                and not (ability.IsPassive and ability:IsPassive()) then
                local name = ability:GetName()
                if name and name ~= "generic_hidden" and not seen[name] then
                    seen[name] = true
                    observe(bot, name, ability, "ABILITY")
                end
            end
        end
    end
    for _, abilityName in ipairs(config.WatchAbilities or {}) do
        if not seen[abilityName] then
            seen[abilityName] = true
            observe(bot, abilityName, bot:GetAbilityByName(abilityName), "ABILITY")
        end
    end
    for _, itemName in ipairs(config.WatchItems or {}) do
        local found = nil
        for slot = 0, 16 do
            if slot <= 8 or slot >= 15 then
                local item = bot:GetItemInSlot(slot)
                if item and item:GetName() == itemName then
                    found = item
                    break
                end
            end
        end
        observe(bot, itemName, found, "ITEM")
    end
end

return Trace
