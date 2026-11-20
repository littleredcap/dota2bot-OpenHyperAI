-- Issue #170: avoid cancelling allied damage while retaining escape/peel intent.
-- No enemy hidden state, future spell trajectories or global combat model.
local Banish = {}
-- Returns (hold, reason); intent is supplied by the proposing Consider().
-- PEEL is only appropriate for a verified ally/self retreat-defense candidate.
function Banish.ShouldHoldEnemyBanish(bot, target, J, intent)
    if not bot or not target or not J or not J.IsValidHero(target) then
        return false, "INVALID_TARGET"
    end
    if target:GetTeam() == bot:GetTeam() then
        return false, "ALLY_SAVE"
    end
    if not target:CanBeSeen() then
        return false, "TARGET_UNSEEN"
    end
    -- Verify interrupts against current target state instead of trusting an intent label.
    if target:IsChanneling() or J.IsCastingUltimateAbility(target) then
        return false, "CHANNEL_INTERRUPT"
    end
    if intent == "PEEL" then
        return false, "DEFENSIVE_PEEL"
    end
    local focus = 0
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
            if active then focus = focus + 1 end
        end
    end
    if focus >= 2 then
        return true, "ALLIED_FOCUS_2PLUS"
    end
    if focus >= 1 and J.IsDisabled(target) then
        return true, "EXISTING_DISABLE"
    end
    if focus >= 1 and J.GetHP(target) <= 0.55 then
        return true, "LOW_HP_ALLIED_DPS"
    end
    if intent == "STOP_ESCAPE" and focus == 0 then
        return false, "ESCAPE_NO_ACTIVE_DPS"
    end
    return false, "NO_CONFLICT"
end
return Banish
