local R = dofile('bots/FunLib/short_fight_window.lua')
assert(R.Hits(3, 0, 1, 0.35) == 3)
assert(R.Hits(3, 2.9, 1, 0.35) == 0)
local p = R.Profile({horizon = 3, attack = 50, contact = 1, period = 1, windup = 0.35, unknownSpell = 150})
assert(p.low <= p.typical and p.typical < p.high and p.typical == 100)
assert(R.TowerDamage(false, 100, 1, 3).high == 0)
assert(R.TowerDamage(true, 100, 1, 3).typical == 100)
local trade = {locked = true, attackers = 2, unseen = 0, enemyHealth = 200,
    damage = {low = 120, typical = 245, high = 290}, incomingHigh = 210,
    selfHealth = 190, canRiskSupport = true, targetWorthwhile = true}
assert(R.CanTrade(trade), 'valuable limited trade')
trade.targetWorthwhile = false
assert(not R.CanTrade(trade), 'do not sacrifice for an equivalent target')
trade.incomingHigh = 100
assert(R.CanTrade(trade), 'short counterdamage can be safe without a sacrifice')
trade.locked = false
assert(not R.CanTrade(trade), 'drop the play when aggro changes')
print('PASS: short fight windows keep uncertainty and reevaluate a bounded tower trade.')
