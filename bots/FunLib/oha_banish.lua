-- OHA-Next: conservative common guard for *offensive* banishment.
-- Source: forest0xia/dota2bot-OpenHyperAI#170. This only uses legal visible
-- state and current allied attack targets; it cannot predict all incoming spells.
local Banish = {}

function Banish.ShouldHoldEnemyBanish(bot, target, J)
    if bot == nil or target == nil or J == nil
    or not J.IsValidHero(target)
    or target:GetTeam() == bot:GetTeam()
    or not target:CanBeSeen()
    then
        return false -- protect friendly saves and invalid/unknown targets
    end

    -- Interrupting an enemy channel/ultimate can be more urgent than
    -- keeping physical DPS on target. Do not block those cases here.
    if target:IsChanneling() or J.IsCastingUltimateAbility(target) then
        return false
    end

    local focus = 0
    for _, ally in pairs(J.GetAlliesNearLoc(target:GetLocation(), 900) or {}) do
        if J.IsValidHero(ally)
        and ally:GetPlayerID() ~= bot:GetPlayerID()
        and not ally:IsIllusion()
        and ally:GetAttackTarget() == target
        then
            focus = focus + 1
        end
    end

    -- Strong current allied focus is a cost to any banish.
    -- One ally's low-HP kill or already-disabled target also matters.
    if focus >= 2 then
        return true
    end
    if focus >= 1 and (J.GetHP(target) <= 0.55 or J.IsDisabled(target)) then
        return true
    end

    return false
end

return Banish
