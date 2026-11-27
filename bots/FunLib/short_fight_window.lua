-- A bounded contact estimate, not a probability of a teamfight win.
local X = {}

function X.Hits(window, contact, period, windup)
    local left = window - math.max(0, contact) - math.max(0, windup)
    if left < 0 then return 0 end
    return 1 + math.floor(left / math.max(0.2, period))
end

-- Find a small feasible chain. One handle is counted once in the short
-- horizon; recasts, charges and unregistered effects stay unresolved.
function X.SpellBudget(spells, mana, horizon)
    local chosen, spentTime, damage = {}, 0, 0
    for _, spell in ipairs(spells) do
        local finish = math.max(spentTime, spell.eta) + spell.cast
        if #chosen < 2 and spell.cost <= mana and finish <= horizon then
            chosen[#chosen+1] = spell
            spentTime, mana, damage = finish, mana - spell.cost, damage + spell.damage
        end
    end
    return damage, spentTime
end

function X.Profile(row)
    local h = row.horizon
    local n = X.Hits(h, row.contact, row.period, row.windup)
    local floorHits = X.Hits(h, row.contact + 0.60, row.period, row.windup)
    local ceilingHits = X.Hits(h, math.max(0, row.contact - 0.15), row.period, row.windup)
    local low, typical, high = floorHits * row.attack * 0.75, n * row.attack, ceilingHits * row.attack * 1.20
    if row.spell ~= nil then
        -- A spell consumes time otherwise spent attacking. Do not add an
        -- engine estimate that already includes attacks on top of those attacks.
        local delay = math.max(row.spell.eta, row.contact)
        local opportunity = X.Hits(h, row.contact, row.period, row.windup + row.spell.cast)
        typical = math.max(typical, opportunity * row.attack + row.spell.damage * (delay <= h - 0.5 and 0.75 or 0.5))
        high = math.max(high, ceilingHits * row.attack + row.spell.damage)
    end
    if row.spells then
        local damage, busy = X.SpellBudget(row.spells, math.max(0, row.mana or 0), h)
        if damage > 0 then
            local attacks = X.Hits(h, math.max(row.contact, busy), row.period, row.windup)
            typical = math.max(typical, attacks * row.attack + damage * 0.70)
            high = math.max(high, attacks * row.attack * 1.20 + damage)
        end
    end
    if row.unknownSpell then high = high + math.max(0, row.unknownSpell) end
    return {low = low, typical = typical, high = math.max(typical, high)}
end

-- Aggro must already belong to this hero. Possible switches and incoming
-- waves can only shorten future contact, never credit guaranteed extra hits.
function X.TowerDamage(locked, hit, period, window)
    if not locked then return {low = 0, typical = 0, high = 0} end
    local nextHits = X.Hits(math.min(window, 1.65), 0, period, 0.35)
    return {low = 0, typical = math.min(1, nextHits) * hit, high = nextHits * hit}
end

function X.CanTrade(row)
    if not row.locked or row.attackers < 2 or row.unseen >= 2 or row.enemyHealth <= 0 then return false end
    -- Only bounded, locally executable trades, not a permission to chase.
    local credibleKill = row.damage.typical >= row.enemyHealth
        and row.damage.low >= row.enemyHealth * 0.50
    local badExchange = row.exposedCore and row.incomingHigh >= row.exposedCore * 0.80
    if not credibleKill or badExchange then return false end
    return row.incomingHigh < row.selfHealth * 0.90
        or row.canRiskSupport and row.targetWorthwhile and row.damage.typical >= row.enemyHealth * 1.12
end

return X
