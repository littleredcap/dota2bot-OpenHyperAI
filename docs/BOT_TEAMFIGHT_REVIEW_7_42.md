# Teamfight priorities and formation (7.42)

## Evidence from mirror replay 9107102358

Radiant OpenHyperAI lost in 52:34 despite 42–29 in hero kills (towers 5–10, barracks 0–4). Mid T2 at 42:10 is a positive example: all five rotated from a successful defense and converted quickly. After another favorable fight at 42:31–42:42, the enemy Sniper returned around 42:53; high-ground damage only started at 43:16 and totaled 210 in that attack. This is not evidence to force high ground when the wave or cover is late.

At 50:14 all five OHA heroes approached mid. After 50:24 Warlock drifted toward bottom while four stayed in the mid fight. Enemy Warlock visibly linked OHA Sniper and Dragon Knight at 51:02 and cast Rain of Chaos in that exchange. Shaman, Sniper and Dragon Knight died at roughly 50:50, 51:03 and 51:15. Final death attribution and positions establish the sequence, not which OHA mode or exact stun affected each hero. Keep a short supporting distance, rather than equating spreading with splitting across lanes.

## Changes

- Focus: among reachable targets, weigh known major control, visible non-TP channeling, damage, exposed health, and a short immediately reachable physical damage estimate. Allow a real switch off a tank only when at least one ready ally can attack the alternative and the fight is already underway. Exclude known protected/unattackable targets; the bot does not read hidden enemy cooldowns or assume an instant kill. Enabling escape/control for specific hero scripts is not changed.
- Spread: preserve an anchor and move a ranged ally by a short sideways/rear step when a known area-control hero is visible in a local fight. Recheck passability, sight, height, enemy tower/exposure, peer distance and attack reach. Avoid interrupting attack wind-up, casts, channels, or an in-range enemy channel opportunity.
- Approach: when visible movement predicts that walking will not close the gap, or the exposed walk is uphill/under tower without pressure, don't blindly run at the target. Try a bounded covered step, otherwise withhold the chase. Keep attacks already in range and quick same-height openings. This is a local staging policy, not an automatic smoke rotation or long flank.
- Scope: shared Lua helpers, team-roam focus and regular hero-target orders, and the project’s explicit attack override. Early-lane timing, emergency rescue, the reinforcement retreat guard, and deferred Scepter/Shard policies retain priority. Engine fallback modes and unsupported hero-specific casts are not claimed as covered.

## Three review passes and next client gate

1. Replay and code trace: establish positive control (41–42m coordinated conversion), late failure (50–51m split), and the existing movement/target entry points. Separate observed actions from possible causes.
2. Target and geometry boundaries: reverse input ordering, silence/fog/unavailable helpers, secured or blocked sidesteps including old route invalidation, actual attack contact versus exposed chase. Preserve channeling, finishing attack, retreat and rescue.
3. Cross-mode regression: exercise production team-roam desire/Think/cleanup path and the full Lua 5.1 offline suite; retain the existing attack-override integration tests. Compare fixed conditions in a fresh local mirror and a lineup with explicit area control (e.g. Tidehunter or Enigma) before loosening objectives.

Track time between target selection and first contact, focus convergence and visible casts prevented, allies caught by each observed major cast, and kills/deaths within 20 seconds of first contact. Also record cases of safe opportunities abandoned, mid T2 conversion and whether spreading took a core/support out of reach. Compare event times using the replay game clock, with unchanged difficulty, roster and game rules per comparison group; 4× can shorten the run but should be noted. Do not claim better win rate until there are repeat runs.
