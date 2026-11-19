-- Issue #170: avoid cancelling allied damage while retaining escape/peel intent.
-- No enemy hidden state, future spell trajectories or global combat model.
local Banish = {}
local Trace
do
    local dir = type(GetScriptDirectory) == "function" and GetScriptDirectory() or "bots"
    local ok, m = pcall(require, dir .. "/FunLib/oha_decision_trace")
    if ok then Trace = m end
end
local function done(bot, target, intent, action, held, reason, focus, chasing)
    if Trace then
        Trace.Record(bot, "BANISH", action or "banish", held and "BLOCK" or "ALLOW", reason, {
            intent = intent,
            target = target and target.GetUnitName and target:GetUnitName() or "unknown",
            focus = focus, chasing = chasing,
        })
    end
    return held, reason
end

-- Returns (hold, reason); ctx.intent is supplied by the proposing Consider().
-- PEEL is only appropriate for a verified ally/self retreat-defense candidate.
function Banish.ShouldHoldEnemyBanish(bot, target, J, ctx)
    ctx = ctx or {}
    local intent = ctx.intent or "NORMAL_CONTROL"
    local action = ctx.action or "banish"
    if not bot or not target or not J or not J.IsValidHero(target) then
        return false, "INVALID_TARGET"
    end
    if target:GetTeam() == bot:GetTeam() then
        return done(bot,target,intent,action,false,"ALLY_SAVE",0,0)
    end
    if not target:CanBeSeen() then
        return done(bot,target,intent,action,false,"TARGET_UNSEEN",0,0)
    end
    -- A caller cannot bypass focus protection merely by labelling a cast.
    if target:IsChanneling() or J.IsCastingUltimateAbility(target) then
        return done(bot,target,intent,action,false,"CHANNEL_INTERRUPT",0,0)
    end
    if intent == "PEEL" then
        return done(bot,target,intent,action,false,"DEFENSIVE_PEEL",0,0)
    end
    local focus, chasing = 0, 0
    for _, ally in pairs(J.GetAlliesNearLoc(target:GetLocation(), 900) or {}) do
        if J.IsValidHero(ally)
            and ally:GetPlayerID() ~= bot:GetPlayerID()
            and not ally:IsIllusion()
            and ally:GetAttackTarget() == target
        then
            -- A stored attack target is not proof of active damage.
            local active = true
            if ally.GetAttackRange and J.IsInRange then
                active = J.IsInRange(ally, target, ally:GetAttackRange() + 125)
            end
            if ally.IsDisarmed and ally:IsDisarmed() then active = false end
            if ally.IsChanneling and ally:IsChanneling() then active = false end
            if active then focus = focus + 1 else chasing = chasing + 1 end
        end
    end
    if focus >= 2 then
        return done(bot,target,intent,action,true,"ALLIED_FOCUS_2PLUS",focus,chasing)
    end
    if focus >= 1 and J.IsDisabled(target) then
        return done(bot,target,intent,action,true,"EXISTING_DISABLE",focus,chasing)
    end
    if focus >= 1 and J.GetHP(target) <= 0.55 then
        return done(bot,target,intent,action,true,"LOW_HP_ALLIED_DPS",focus,chasing)
    end
    if intent == "STOP_ESCAPE" and focus == 0 then
        return done(bot,target,intent,action,false,"ESCAPE_NO_ACTIVE_DPS",focus,chasing)
    end
    return done(bot,target,intent,action,false,"NO_CONFLICT",focus,chasing)
end
return Banish
