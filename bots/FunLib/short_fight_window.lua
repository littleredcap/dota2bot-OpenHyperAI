-- A bounded contact estimate, not a probability of a teamfight win.
local X = {}

function X.Hits(window, contact, period, windup)
    local left = window - math.max(0, contact) - math.max(0, windup)
    if left < 0 then return 0 end
    return 1 + math.floor(left / math.max(0.2, period))
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
