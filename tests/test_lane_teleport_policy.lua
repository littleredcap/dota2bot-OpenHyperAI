local P = dofile('bots/FunLib/lane_teleport_policy.lua')
local function test(expected, changes)
    local f = { observed = true, pressure = true, arrival = 5, timeToFall = 15 }
    for key, val in pairs(changes) do f[key] = val end
    local allowed, reason = P.Defense(f)
    assert(reason == expected, 'expected ' .. expected .. ', got ' .. tostring(reason))
    assert(allowed == (expected == 'live-defense'))
end
test('no-live-pressure', { observed = false })
test('no-live-pressure', { pressure = false })
test('too-late', { arrival = 11 })
test('too-late', { timeToFall = 6 })
test('already-covered', { covered = true })
test('live-defense', { covered = true, secondNeeded = true, urgent = true })
test('keep-source-wave', { sourceValuable = true })
test('live-defense', { sourceValuable = true, urgent = true })
test('avoid-reversal', { reversing = true })
test('live-defense', { reversing = true, urgent = true })
test('live-defense', {})
local returnTrip = { started = true, fromBase = true, healthy = true, safeAnchor = true,
    distance = 5900, minimum = 4600 }
assert(P.ReturnToLane(returnTrip), 'healthy respawn can TP to its own protected tower')
for _, field in ipairs({'started', 'fromBase', 'healthy', 'safeAnchor'}) do
    returnTrip[field] = false
    assert(not P.ReturnToLane(returnTrip), field .. ' must be true')
    returnTrip[field] = true
end
returnTrip.distance = 2100
assert(not P.ReturnToLane(returnTrip), 'nearby tower is not worth a scroll')

local late = P.ActionETA(5, 1100, 250, 300)
assert(not P.CoversDeadline(late, 6), 'a channel landing 1100 away cannot cover a tower falling in 6s')
assert(P.CoversDeadline(P.ActionETA(2, 450, 450, 300), 6), 'a timely channel still prevents duplicate response')
local candidates = {{id = 1, canClear = true, arrival = 9}}
assert(not P.TimelyClearer(candidates, 5), 'do not reserve a clearer that misses the first deadline')
candidates[1].arrival = 6
assert(P.TimelyClearer(candidates, 8).id == 1, 'the same unclaimed clearer can cover the second lane')
candidates[1].arrival = 4
assert(P.TimelyClearer(candidates, 5).id == 1, 'when reachable, the most urgent lane still receives the clearer')

print('PASS: lane TP rejects empty/covered/late trips and preserves actionable defense.')
