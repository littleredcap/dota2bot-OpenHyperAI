local M = {}

function M.ShouldUse(f)
    if not f.ready or f.fight or f.coveredWave or f.towerUnderAttack then return false end
    if f.hasNextWave and f.waveETA <= f.returnETA + 4 then return false end
    return f.waited >= 10 and f.safe and f.campConfirmed
end

return M
