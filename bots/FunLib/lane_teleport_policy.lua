local M = {}

-- A safe landing is not itself a reason to leave lane. Inputs describe
-- observed pressure, the time to act, and friendly coverage.
function M.Defense(f)
    if not f.observed or not f.pressure then return false, 'no-live-pressure' end
    if f.arrival > 9 or f.arrival + 1 >= f.timeToFall then return false, 'too-late' end
    if f.covered and not f.secondNeeded then return false, 'already-covered' end
    if f.sourceValuable and not f.urgent then return false, 'keep-source-wave' end
    if f.reversing and not f.urgent then return false, 'avoid-reversal' end
    return true, 'live-defense'
end

function M.ReturnToLane(f)
    return f.started and f.fromBase and f.healthy and f.safeAnchor and f.distance >= f.minimum
end

function M.ActionETA(channel, distance, reach, speed)
    return channel + math.max(0, distance - reach) / math.max(speed, 250) * 1.15
end

function M.CoversDeadline(eta, timeToFall)
    return eta <= 9 and eta + 1 < timeToFall
end

function M.TimelyClearer(rows, deadline)
    for _, row in ipairs(rows) do
        if row.canClear and row.arrival <= deadline then return row end
    end
end

return M
