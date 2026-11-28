-- Estimate what a visible opponent can do before a move or channel completes.
local M = {}
local observed = {}

local rootEffects = {'root', 'frostbite', 'overgrowth', 'rod_of_atos', 'gungir', 'searing_chains', 'ensnare'}
local silenceEffects = {'silence', 'orchid_malevolence_debuff', 'bloodthorn_debuff', 'ancient_seal', 'waning_rift'}

local function restrictionTime(enemy, effects)
    local longest = 0
    for i = 0, enemy:NumModifiers() - 1 do
        local name = enemy:GetModifierName(i) or ''
        for _, effect in ipairs(effects) do
            if name:find(effect, 1, true) then
                longest = math.max(longest, enemy:GetModifierRemainingDuration(i) or 0)
                break
            end
        end
    end
    -- A status with no identifiable expiry cannot guarantee a safe channel.
    return longest
end

local function travelTime(distance, reach, enemy, rooted)
    if distance <= reach then return 0 end
    return rooted + (distance - reach) / math.max(1, enemy:GetCurrentMovementSpeed())
end

local function spellWindow(J, enemy, distance, seconds, rooted, silence, checkInterrupt, immune)
    local earliest, physicalSpell, interrupt = math.huge, math.huge, false
    local mana = enemy:GetMana()
    local hasStun = checkInterrupt and (enemy:GetStunDuration(true) > 0 or enemy:IsSilenced())
    local now = DotaTime()
    local id = enemy:GetPlayerID()
    local spent = observed[id] or {}
    observed[id] = spent
    if enemy:IsUsingAbility() and not enemy:IsCastingAbility() then
        local cast = enemy:GetCurrentActiveAbility()
        if cast and not cast:IsNull() and not cast:IsPassive() and not enemy:IsChanneling() then
            -- Only discount a cast we actually witnessed, and only briefly.
            if not cast:GetName():find('^item_') and cast:GetSpecialValueInt('max_charges') == 0 then
                spent[cast:GetName()] = now + math.min(4, math.max(0, cast:GetCooldown()) * 0.5)
            end
        end
    end
    for slot = 0, 8 do
        local spell = enemy:GetAbilityInSlot(slot)
        if spell and not spell:IsNull() and spell:IsTrained() and not spell:IsHidden()
            and not spell:IsPassive() and mana >= spell:GetManaCost() then
            local behavior = spell:GetBehavior()
            local unitTarget = J.Utils.AbilityBehaviorHasFlag(behavior, ABILITY_BEHAVIOR_UNIT_TARGET)
            local aimed = J.Utils.AbilityBehaviorHasFlag(behavior, ABILITY_BEHAVIOR_POINT)
            local hostile = J.Utils.AbilityBehaviorHasFlag(spell:GetTargetTeam(), ABILITY_TARGET_TEAM_ENEMY or DOTA_UNIT_TARGET_TEAM_ENEMY or 2)
            local radius = spell:GetAOERadius() or 0
            if hostile or aimed or (not unitTarget and radius > 0) then
                local reach = math.max(0, spell:GetCastRange()) + (unitTarget and not aimed and 0 or radius)
                local cast = math.max(0, spell:GetCastPoint())
                local contact = travelTime(distance, reach, enemy, rooted)
                local ready = math.max(silence, contact, (spent[spell:GetName()] or now) - now)
                if ready + cast < seconds then
                    earliest = math.min(earliest, ready)
                    if spell.GetDamageType and spell:GetDamageType() == DAMAGE_TYPE_PHYSICAL
                        and (spell:GetAbilityDamage() or 0) > 0 then
                        physicalSpell = math.min(physicalSpell, ready)
                    end
                    if checkInterrupt and (not immune or J.Utils.AbilityBehaviorHasFlag(spell:GetTargetFlags(),
                        ABILITY_TARGET_FLAG_MAGIC_IMMUNE_ENEMIES or 16)) then
                        local name = spell:GetName()
                        local stun = J.IsStunProjectileSpell(name) or spell:GetSpecialValueFloat('stun_duration') > 0
                        local otherControl = name == 'shadow_shaman_shackles' or name == 'shadow_shaman_voodoo'
                            or name == 'lion_voodoo' or spell:GetSpecialValueFloat('root_duration') > 0
                        -- Do not query individual enemy cooldowns. The API's available stun estimate
                        -- and visible mana restrict the controls that can actually stop the channel.
                        if (stun and hasStun) or otherControl then interrupt = true end
                    end
                end
            end
        end
    end
    return earliest, physicalSpell, interrupt
end

function M.Evaluate(J, bot, enemies, point, seconds, checkInterrupt)
    local damage, interrupt, contacts = 0, false, 0
    for _, enemy in ipairs(enemies) do
        if enemy:CanBeSeen() and J.IsValidHero(enemy) and not J.IsSuspiciousIllusion(enemy) then
            local distance = GetUnitToLocationDistance(enemy, point)
            local delay = J.GetFightHardControlRemaining(enemy)
            local available = seconds - delay
            if available > 0 then
                local rooted = enemy:IsRooted() and math.max(0, restrictionTime(enemy, rootEffects) - delay) or 0
                local attackTime = travelTime(distance, enemy:GetAttackRange(), enemy, rooted)
                local physicalWindow = available - attackTime
                local physical = 0
                if not enemy:IsDisarmed() and physicalWindow >= enemy:GetAttackPoint() then
                    physical = bot:GetActualIncomingDamage(enemy:GetAttackDamage(), DAMAGE_TYPE_PHYSICAL)
                        * (1 + math.floor((physicalWindow - enemy:GetAttackPoint()) / math.max(0.25, enemy:GetSecondsPerAttack())))
                end
                local estimate, stop = 0, false
                local silence = enemy:IsSilenced() and math.max(0, restrictionTime(enemy, silenceEffects) - delay) or 0
                if silence < available then
                    local spellTime, physicalSpell
                    spellTime, physicalSpell, stop = spellWindow(J, enemy, distance, available, rooted, silence, checkInterrupt, bot:IsMagicImmune())
                    if spellTime < available then
                        local window = available - spellTime
                        estimate = enemy:GetEstimatedDamageToTarget(true, bot, window, DAMAGE_TYPE_MAGICAL + DAMAGE_TYPE_PURE)
                        if physicalSpell < available then
                            physical = math.max(physical, enemy:GetEstimatedDamageToTarget(true, bot, available - physicalSpell, DAMAGE_TYPE_PHYSICAL))
                        end
                    end
                end
                if physical + estimate > 0 or stop then contacts = contacts + 1 end
                damage, interrupt = damage + physical + estimate, interrupt or stop
            end
        end
    end
    return damage, interrupt, contacts
end

return M
