local M = dofile('bots/FunLib/lane_resource_window.lua')
local function check(result, changes)
    local facts = {ready=true, waited=11, safe=true, campConfirmed=true, returnETA=4}
    for k,v in pairs(changes) do facts[k]=v end
    assert(M.ShouldUse(facts) == result)
end
check(true, {})
check(false, {waited=9})
check(false, {ready=false})
check(false, {fight=true})
check(false, {coveredWave=true})
check(false, {towerUnderAttack=true})
check(false, {hasNextWave=true, waveETA=8})
check(true, {hasNextWave=true, waveETA=10})
check(false, {safe=false})
check(false, {campConfirmed=false})
print('PASS: sheltered core takes a confirmed safe local camp only after a persistent empty hold and returns for waves.')
