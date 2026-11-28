// let TS accept these Lua globals
declare function GetScriptDirectory(): string;

import * as jmz from "bots/FunLib/jmz_func";
// Avoid static resolution; mirror Lua's pcall(require(...))
let [okLoc, Localization] = pcall(require, GetScriptDirectory() + "/FunLib/localization");
if (!okLoc) Localization = { Get: (_: string) => "Defend here!" };

// eslint-disable-next-line @typescript-eslint/no-var-requires
import Customize = require("bots/Customize/general");

import { Barracks, BotActionDesire, BotMode, BotModeDesire, Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import { add } from "bots/ts_libs/utils/native-operators";
import { GetLocationToLocationDistance } from "./utils";

Customize.ThinkLess = Customize.Enable ? Customize.ThinkLess : 1;

// == Tunables ==
const PING_DELTA = 5.0;
const SEARCH_RANGE_DEFAULT = 1600;
// const CLOSE_RANGE = 1200;
const MAX_DESIRE_CAP = 0.98;

// Base threat (Ancient defense)
const BASE_THREAT_RADIUS = 2600;
const BASE_LEASH_OUTBOUND = 1200;
const BASE_THREAT_HOLD = 4.0;

// Perf: cache intervals (seconds)
const CACHE_ENEMY_AROUND_LOC_HZ = 0.35; // cache for weighted enemy scans around a location
const CACHE_LASTSEEN_WINDOW = 5.0; // seconds for hero last-seen proximity checks

// == State ==
const nTeam = GetTeam();
// Per-bot state stored on bot object to avoid cross-bot data races.
// Access via (bot as any)._defend.X — initialized in GetDefendDesireHelper.
interface DefendBotState {
    defendLoc: Vector;
    weAreStronger: boolean;
    nInRangeAlly: Unit[];
    nInRangeEnemy: Unit[];
    distanceToLane: Record<Lane, number>;
    waveClearLane?: Lane;
    waveClearReach?: number;
    waveClearTower?: Unit;
    waveClearRearTower?: Unit;
    waveClearCover?: boolean;
    waveClearTeleport?: Vector;
    waveClearRally?: Vector;
    waveClearGather?: Vector;
    waveClearNeedsGlyph?: boolean;
    waveClearScreen?: boolean;
    waveClearTarget?: Unit;
    nextWave?: { lane: Lane; tower: Unit; reach: number; expires: number };
}
function getDefendState(bot: Unit): DefendBotState {
    if (!(bot as any)._defend) {
        (bot as any)._defend = {
            defendLoc: GetLaneFrontLocation(nTeam, Lane.Mid, 0),
            weAreStronger: false,
            nInRangeAlly: [],
            nInRangeEnemy: [],
            distanceToLane: { [Lane.Top]: 0, [Lane.Mid]: 0, [Lane.Bot]: 0 },
        };
    }
    return (bot as any)._defend;
}
let _threatLaneSticky: { lane: Lane; until: number } = { lane: Lane.Mid, until: -1 };

// sticky base-threat window
let baseThreatUntil = -1;

// Travel Boots defender coordination
let fTraveBootsDefendTime = 0;

// == Perf caches ==
type EnemyAroundLocCache = { t: number; count: number };
const _cacheEnemyAroundLoc: Record<string, EnemyAroundLocCache> = {};

/** Performance cache - avoid redundant calculations between GetDefendDesire (300ms) and Think (every frame) */
type CachedDefendGameState = {
    lastUpdate: number;
    currentTime: number;
    gameMode: number;
    team: Team;
    enemyTeam: Team;
    ourAncient: Unit | null;
    enemyAncient: Unit | null;
    aliveAllyCount: number;
    aliveEnemyCount: number;
    isLaningPhase: boolean;
    isEarlyGame: boolean;
    isMidGame: boolean;
    isLateGame: boolean;
    teamFountain: Vector;
    teamFountainTpPoint: Vector;
};

type CachedDefendLocationState = {
    lastUpdate: number;
    laneFronts: Record<Lane, Vector>;
    enemyLaneFronts: Record<Lane, Vector>;
    highGroundEdgeWaitPoints: Record<Lane, Vector>;
};

type CachedDefendUnitState = {
    lastUpdate: number;
    enemyBuildings: Unit[];
    alliedHeroes: Unit[];
    enemyHeroes: Unit[];
    alliedCreeps: Unit[];
    enemyCreeps: Unit[];
    teamMembers: Unit[];
};

const DEFEND_CACHE_TTL = 0.5; // 500ms cache TTL - increased for better performance
// Frame rate limiter removed — caused stale action replay and shared state bugs
let defendGameStateCache: CachedDefendGameState | null = null;
let defendLocationStateCache: CachedDefendLocationState | null = null;
let defendUnitStateCache: CachedDefendUnitState | null = null;

/** Update defend game state cache if needed */
function updateDefendGameStateCache(): CachedDefendGameState {
    const now = DotaTime();
    if (defendGameStateCache && now - defendGameStateCache.lastUpdate < DEFEND_CACHE_TTL) {
        return defendGameStateCache;
    }

    const team = GetTeam();
    const enemyTeam = GetOpposingTeam();
    const currentTime = DotaTime();
    const gameMode = GetGameMode();

    // Adjust time for turbo mode
    const adjustedTime = gameMode === 23 ? currentTime * 1.65 : currentTime;

    defendGameStateCache = {
        lastUpdate: now,
        currentTime: adjustedTime,
        gameMode,
        team,
        enemyTeam,
        ourAncient: GetAncient(team),
        enemyAncient: GetAncient(enemyTeam),
        aliveAllyCount: jmz.GetNumOfAliveHeroes(false),
        aliveEnemyCount: jmz.GetNumOfAliveHeroes(true),
        isLaningPhase: jmz.IsInLaningPhase(),
        isEarlyGame: jmz.IsEarlyGame(),
        isMidGame: jmz.IsMidGame(),
        isLateGame: jmz.IsLateGame(),
        teamFountain: jmz.GetTeamFountain(),
        teamFountainTpPoint: jmz.Utils.GetTeamFountainTpPoint(),
    };

    return defendGameStateCache;
}

/** Update defend location state cache if needed */
function updateDefendLocationStateCache(): CachedDefendLocationState {
    const now = DotaTime();
    if (defendLocationStateCache && now - defendLocationStateCache.lastUpdate < DEFEND_CACHE_TTL) {
        return defendLocationStateCache;
    }

    const team = GetTeam();
    const enemyTeam = GetOpposingTeam();

    defendLocationStateCache = {
        lastUpdate: now,
        laneFronts: {
            [Lane.Top]: GetLaneFrontLocation(team, Lane.Top, 0),
            [Lane.Mid]: GetLaneFrontLocation(team, Lane.Mid, 0),
            [Lane.Bot]: GetLaneFrontLocation(team, Lane.Bot, 0),
        },
        enemyLaneFronts: {
            [Lane.Top]: GetLaneFrontLocation(enemyTeam, Lane.Top, 0),
            [Lane.Mid]: GetLaneFrontLocation(enemyTeam, Lane.Mid, 0),
            [Lane.Bot]: GetLaneFrontLocation(enemyTeam, Lane.Bot, 0),
        },
        highGroundEdgeWaitPoints: {
            [Lane.Top]: GetHighGroundEdgeWaitPoint(team, Lane.Top),
            [Lane.Mid]: GetHighGroundEdgeWaitPoint(team, Lane.Mid),
            [Lane.Bot]: GetHighGroundEdgeWaitPoint(team, Lane.Bot),
        },
    };

    return defendLocationStateCache;
}

/** Update defend unit state cache if needed */
function updateDefendUnitStateCache(): CachedDefendUnitState {
    const now = DotaTime();
    if (defendUnitStateCache && now - defendUnitStateCache.lastUpdate < DEFEND_CACHE_TTL) {
        return defendUnitStateCache;
    }

    const teamMembers: Unit[] = [];
    for (let i = 1; i <= GetTeamPlayers(GetTeam()).length; i++) {
        const member = GetTeamMember(i);
        if (member !== null) {
            teamMembers.push(member);
        }
    }

    defendUnitStateCache = {
        lastUpdate: now,
        enemyBuildings: GetUnitList(UnitType.EnemyBuildings),
        alliedHeroes: GetUnitList(UnitType.AlliedHeroes),
        enemyHeroes: GetUnitList(UnitType.Enemies).filter(u => jmz.IsValidHero(u)),
        alliedCreeps: GetUnitList(UnitType.AlliedCreeps),
        enemyCreeps: GetUnitList(UnitType.Enemies).filter(u => u.IsCreep() || u.IsAncientCreep()),
        teamMembers,
    };

    return defendUnitStateCache;
}

// small utils (keep GC low)
function _q(v: Vector | null | undefined): string {
    return v ? `${math.floor(v.x / 200) * 200}:${math.floor(v.y / 200) * 200}` : "0:0";
}
function _keyLoc(v: Vector, r?: number) {
    return `${_q(v)}|${tostring(math.floor(r || 0))}`;
}

function _recentHeroCountNear(loc: Vector, r: number, window = CACHE_LASTSEEN_WINDOW): number {
    const gameState = updateDefendGameStateCache();
    let cnt = 0;
    for (const id of GetTeamPlayers(gameState.enemyTeam)) {
        if (!IsHeroAlive(id)) continue;
        const info = GetHeroLastSeenInfo(id);
        // NOTE: TS index 0 → Lua index 1
        if (info && info[0] && info[0].time_since_seen <= window && GetLocationToLocationDistance(info[0].location, loc) <= r) {
            cnt += 1;
        }
    }
    return cnt;
}

// == Small helpers ==
function IsValidBuildingTarget(unit: Unit | null): unit is Unit {
    return unit !== null && unit.IsAlive() && unit.IsBuilding();
}
function IsStandingHighGroundBuilding(unit: Unit | null): boolean {
    return unit !== null && !unit.IsNull?.() && IsValidBuildingTarget(unit);
}
function IsBaseThreatActive(): boolean {
    return DotaTime() < (baseThreatUntil || -1);
}

// Lane entrances also lie within the broad Ancient alert radius. Check what
// the visible hero is attacking, or whether it actually entered the inner base.
function GetInnerBaseAttacker(ancient: Unit | null): Unit | undefined {
    if (!IsValidBuildingTarget(ancient)) return;
    const left = GetTower(nTeam, Tower.Base1), right = GetTower(nTeam, Tower.Base2);
    let intruder: Unit | undefined;
    for (const enemy of updateDefendUnitStateCache().enemyHeroes) {
        if (!jmz.IsValidHero(enemy) || jmz.IsSuspiciousIllusion(enemy)
            || GetUnitToUnitDistance(enemy, ancient) > BASE_THREAT_RADIUS) continue;
        const target = enemy.GetAttackTarget();
        if (target && (target === ancient || target === left || target === right)
            && GetUnitToUnitDistance(enemy, target) <= enemy.GetAttackRange() + 125) return enemy;
        if (target && !target.IsNull?.() && target.CanBeSeen() && target.IsBuilding()) continue;
        if (GetUnitToUnitDistance(enemy, ancient) <= 950
            || (IsStandingHighGroundBuilding(left) && GetUnitToUnitDistance(enemy, left!) <= 650)
            || (IsStandingHighGroundBuilding(right) && GetUnitToUnitDistance(enemy, right!) <= 650)) intruder = enemy;
    }
    return intruder;
}

// If any enemy units (weighted) are around location; cached
function WeightedEnemiesAroundLocation(vLoc: Vector, nRadius: number): number {
    const now = DotaTime();
    const key = _keyLoc(vLoc, nRadius);
    const c = _cacheEnemyAroundLoc[key];
    if (c && now - c.t <= CACHE_ENEMY_AROUND_LOC_HZ) return c.count;

    const unitState = updateDefendUnitStateCache();
    let count = 0;
    for (const unit of unitState.enemyHeroes) {
        if (jmz.IsValidHero(unit) && GetUnitToLocationDistance(unit, vLoc) <= nRadius
            && !jmz.IsSuspiciousIllusion(unit)) {
            count += jmz.IsCore(unit) ? 1 : 0.5;
        }
    }
    // The previous function iterated only enemyHeroes; its creep branches
    // were unreachable. Include the actual visible enemy creep collection.
    for (const unit of unitState.enemyCreeps) {
        if (jmz.IsValid(unit) && GetUnitToLocationDistance(unit, vLoc) <= nRadius) {
            const name = unit.GetUnitName();
            if (name.includes("upgraded_mega")) {
                count += 0.6;
            } else if (name.includes("upgraded")) {
                count += 0.4;
            } else if (name.includes("siege")) {
                count += 0.5;
            } else if (name.includes("warlock_golem") || name.includes("lone_druid_bear")) {
                count += 1;
            } else {
                count += 0.2;
            }
        }
    }

    count = math.floor(count);
    _cacheEnemyAroundLoc[key] = { t: now, count };
    return count;
}

function baseCreepPriority(creep: Unit, ancient: Unit, left: Unit | null, right: Unit | null): number {
    if (!jmz.IsValid(creep)) return 0;
    const distance = GetUnitToLocationDistance(creep, ancient.GetLocation());
    if (distance > BASE_THREAT_RADIUS) return 0;
    const target = creep.GetAttackTarget();
    if (target === ancient || (left != null && target === left) || (right != null && target === right)) return 2;
    const name = creep.GetUnitName();
    return distance <= 1800 && name.includes("npc_dota_creep_") && name.includes("_upgraded")
        && (distance <= 950 || creep.IsFacingLocation(ancient.GetLocation(), 55)) ? 1 : 0;
}

function GetBaseCreepAttacker(ancient: Unit | null): Unit | null {
    if (!IsValidBuildingTarget(ancient)) return null;
    const leftT4 = GetTower(nTeam, Tower.Base1);
    const rightT4 = GetTower(nTeam, Tower.Base2);
    let approaching: Unit | null = null;
    for (const creep of updateDefendUnitStateCache().enemyCreeps) {
        const priority = baseCreepPriority(creep, ancient, leftT4, rightT4);
        if (priority === 2) return creep;
        if (priority === 1) approaching = creep;
    }
    return approaching;
}

function GetBaseCreepThreatCount(ancient: Unit | null): number {
    if (!IsValidBuildingTarget(ancient)) return 0;
    const leftT4 = GetTower(nTeam, Tower.Base1);
    const rightT4 = GetTower(nTeam, Tower.Base2);
    let count = 0;
    for (const creep of updateDefendUnitStateCache().enemyCreeps) {
        if (baseCreepPriority(creep, ancient, leftT4, rightT4) > 0) count++;
    }
    return count;
}

// Estimated walk ETA is less misleading than pure distance when hero speeds
// differ. TP pathing is deliberately excluded: actual legal destinations vary.
function GetBaseCreepDefender(ancientLoc: Vector, alreadyAssigned: Unit[]): Unit | null {
    let best: Unit | null = null;
    let bestETA = math.huge;
    for (let i = 1; i <= GetTeamPlayers(nTeam).length; i++) {
        const member = GetTeamMember(i);
        if (member && member.IsBot() && jmz.IsValidHero(member) && !member.IsIllusion()
            && !member.IsStunned() && !member.IsHexed() && !member.IsNightmared()
            && !member.IsDisarmed() && !member.IsChanneling() && !member.HasModifier("modifier_teleporting")) {
            let eligible = true;
            for (const other of alreadyAssigned) {
                if (other.GetPlayerID() === member.GetPlayerID()) eligible = false;
            }
            if (eligible) {
                const distance = GetUnitToLocationDistance(member, ancientLoc);
                const eta = distance / math.max(member.GetCurrentMovementSpeed(), 250);
                if (eta < bestETA) {
                    best = member;
                    bestETA = eta;
                }
            }
        }
    }
    return best;
}

// Both modes ask the same live question; no mode has to run its desire first.
export function GetBaseCreepResponse(bot: Unit, ancient: Unit | null): LuaMultiReturn<[boolean, boolean]> {
    if (!IsValidBuildingTarget(ancient)) return $multi(false, false);
    const attackers = GetBaseCreepThreatCount(ancient);
    if (attackers === 0) return $multi(false, false);
    const ancientHP = ancient.GetHealth() / math.max(ancient.GetMaxHealth(), 1);
    const critical = attackers >= 4 || ancientHP <= 0.45;
    const ancientLoc = ancient.GetLocation();
    if (!critical && GetInnerBaseAttacker(ancient)) return $multi(false, critical);
    let required = 1;
    if (attackers >= 8 || ancientHP <= 0.2) required = 3;
    else if (critical) required = 2;
    const assigned: Unit[] = [];
    for (let i = 0; i < required; i++) {
        const defender = GetBaseCreepDefender(ancientLoc, assigned);
        if (defender === null) break;
        if (defender.GetPlayerID() === bot.GetPlayerID()) return $multi(true, critical);
        assigned.push(defender);
    }
    return $multi(false, critical);
}

// Creep-only responders use mid defense; other lane duties stay available.
function GetCreepBaseDefenseDesire(bot: Unit, lane: Lane, ancient: Unit | null): BotModeDesire | null {
    if (lane !== Lane.Mid) return null;
    const [assigned] = GetBaseCreepResponse(bot, ancient);
    return assigned ? 0.97 as BotModeDesire : null;
}

function GetThreatenedLane(): Lane {
    const lanes: Lane[] = [Lane.Top, Lane.Mid, Lane.Bot];
    let bestLane = lanes[0];
    let bestScore = -1;

    for (const ln of lanes) {
        const [bld, _urgent, tier] = GetFurthestBuildingOnLane(ln);
        // for tier >=3, use lane HG edge; for t1/2, use the building
        const anchor = IsValidBuildingTarget(bld) && tier < 3 ? bld.GetLocation() : GetHighGroundEdgeWaitPoint(nTeam, ln);

        // Hero-first scoring
        const enemyHeroCnt = _recentHeroCountNear(anchor, 1800);
        let score = enemyHeroCnt * 10; // heroes dominate the score

        if (enemyHeroCnt === 0) {
            // don’t let creeps fully tie heroes; smaller radius + cap
            const creepEq = math.min(WeightedEnemiesAroundLocation(anchor, 1200) * 0.4, 0.9);
            score += creepEq;
        }

        if (score > bestScore) {
            bestScore = score;
            bestLane = ln;
        }
    }

    // short stickiness to avoid oscillation
    if (DotaTime() <= _threatLaneSticky.until) {
        return _threatLaneSticky.lane;
    }
    _threatLaneSticky = { lane: bestLane, until: DotaTime() + 1.8 };
    return bestLane;
}

// Closest ally role among a list to given location
function GetClosestAllyPos(tPosList: number[], vLocation: Vector): number {
    let bestPos: number | null = null;
    let bestDist = math.huge;
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (jmz.IsValidHero(m)) {
            const p = jmz.GetPosition(m);
            for (const candidatePos of tPosList) {
                if (p === candidatePos) {
                    const d = GetUnitToLocationDistance(m, vLocation);
                    if (d < bestDist) {
                        bestDist = d;
                        bestPos = p;
                    }
                }
            }
        }
    }
    return bestPos ?? tPosList[0];
}

// == Core building selection ==
// Returns: furthestBuilding, urgencyMultiplier, tier (1..4)
export function GetFurthestBuildingOnLane(lane: Lane): [Unit | any, number, number] {
    const cacheKey = `FurthestBuildingOnLane:${nTeam}:${lane ?? -1}`;
    const cachedVar = jmz.Utils.GetCachedVars(cacheKey, 1) as [Unit, number, number] | undefined;
    if (cachedVar != null && (cachedVar[2] < 3 || IsStandingHighGroundBuilding(cachedVar[0]))) {
        return cachedVar;
    }

    const res = GetFurthestBuildingOnLaneHelper(lane);
    jmz.Utils.SetCachedVars(cacheKey, res);
    return res;
}

// Returns: furthestBuilding, urgencyMultiplier, tier (1..4)
export function GetFurthestBuildingOnLaneHelper(lane: Lane): [Unit | any, number, number] {
    const team = nTeam;
    let b: Unit | null;

    function hpMul(u: Unit, lo: number, hi: number, mlo: number, mhi: number) {
        const nHealth = u.GetHealth() / u.GetMaxHealth();
        return RemapValClamped(nHealth, lo, hi, mlo, mhi);
    }

    if (lane === Lane.Top) {
        b = GetTower(team, Tower.Top1);
        if (IsValidBuildingTarget(b)) return [b, hpMul(b, 0.25, 1, 0.5, 1), 1];
        b = GetTower(team, Tower.Top2);
        if (IsValidBuildingTarget(b)) return [b, hpMul(b, 0.25, 1, 1.0, 2), 2];
        b = GetTower(team, Tower.Top3);
        if (IsValidBuildingTarget(b)) return [b, hpMul(b, 0.25, 1, 1.5, 2), 3];
        b = GetBarracks(team, Barracks.TopMelee);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetBarracks(team, Barracks.TopRanged);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetTower(team, Tower.Base1);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetTower(team, Tower.Base2);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetAncient(team);
        if (IsValidBuildingTarget(b)) return [b, 3.0, 4];
    } else if (lane === Lane.Mid) {
        b = GetTower(team, Tower.Mid1);
        if (IsValidBuildingTarget(b)) return [b, hpMul(b, 0.25, 1, 0.5, 1), 1];
        b = GetTower(team, Tower.Mid2);
        if (IsValidBuildingTarget(b)) return [b, hpMul(b, 0.25, 1, 1.0, 2), 2];
        b = GetTower(team, Tower.Mid3);
        if (IsValidBuildingTarget(b)) return [b, hpMul(b, 0.25, 1, 1.5, 2), 3];
        b = GetBarracks(team, Barracks.MidMelee);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetBarracks(team, Barracks.MidRanged);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetTower(team, Tower.Base1);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetTower(team, Tower.Base2);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetAncient(team);
        if (IsValidBuildingTarget(b)) return [b, 3.0, 4];
    } else {
        b = GetTower(team, Tower.Bot1);
        if (IsValidBuildingTarget(b)) return [b, hpMul(b, 0.25, 1, 0.5, 1), 1];
        b = GetTower(team, Tower.Bot2);
        if (IsValidBuildingTarget(b)) return [b, hpMul(b, 0.25, 1, 1.0, 2), 2];
        b = GetTower(team, Tower.Bot3);
        if (IsValidBuildingTarget(b)) return [b, hpMul(b, 0.25, 1, 1.5, 2), 3];
        b = GetBarracks(team, Barracks.BotMelee);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetBarracks(team, Barracks.BotRanged);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetTower(team, Tower.Base1);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetTower(team, Tower.Base2);
        if (IsValidBuildingTarget(b)) return [b, 2.5, 3];
        b = GetAncient(team);
        if (IsValidBuildingTarget(b)) return [b, 3.0, 4];
    }

    return [null as any, 1.0, 0];
}

// Travel Boots defender dedupe
function IsThereNoTeammateTravelBootsDefender(bot: Unit): boolean {
    const unitState = updateDefendUnitStateCache();
    for (const m of unitState.teamMembers) {
        if (bot !== m && jmz.IsValidHero(m) && (m as any).travel_boots_defender === true) {
            return false;
        }
    }
    return true;
}

// Compute a “high-ground edge” wait point a bit outside the T3 toward lane
function GetHighGroundEdgeWaitPoint(team: Team, lane: Lane): Vector {
    const t3 = lane === Lane.Top ? GetTower(team, Tower.Top3) : lane === Lane.Mid ? GetTower(team, Tower.Mid3) : GetTower(team, Tower.Bot3);

    // try lane rax if T3 is gone
    const raxM =
        lane === Lane.Top ? GetBarracks(team, Barracks.TopMelee) : lane === Lane.Mid ? GetBarracks(team, Barracks.MidMelee) : GetBarracks(team, Barracks.BotMelee);
    const raxR =
        lane === Lane.Top ? GetBarracks(team, Barracks.TopRanged) : lane === Lane.Mid ? GetBarracks(team, Barracks.MidRanged) : GetBarracks(team, Barracks.BotRanged);

    const anc = GetAncient(team);

    // choose a lane HG anchor: T3 > any rax > last-resort fallback
    const anchorBuilding = (jmz.IsValidBuilding(t3) ? t3 : jmz.IsValidBuilding(raxM) ? raxM : jmz.IsValidBuilding(raxR) ? raxR : undefined) as Unit | undefined;

    if (anchorBuilding && jmz.IsValidBuilding(anc)) {
        const t = anchorBuilding.GetLocation();
        const a = (anc as Unit).GetLocation();
        const dir = Vector(a.x - t.x, a.y - t.y, 0);
        const len = math.max(1, math.sqrt(dir.x * dir.x + dir.y * dir.y));
        return Vector(t.x + (dir.x / len) * 250, t.y + (dir.y / len) * 250, 0);
    }

    // safer fallback: deeper inside base so HG hero clumps get counted
    return jmz.AdjustLocationWithOffsetTowardsFountain(GetLaneFrontLocation(team, lane, 0), 600);
}

// Role-aware defend decision (cached)
export function ShouldDefend(bot: Unit, hBuilding: Unit | null, nRadius: number): boolean {
    if (!IsValidBuildingTarget(hBuilding)) return false;
    // const cacheKey = `ShouldDefend:${bot.GetPlayerID()}:${hBuilding.GetLocation() ?? -1}:${nRadius}`;
    // const cachedVar = jmz.Utils.GetCachedVars(cacheKey, 0.6);
    // if (cachedVar != null) {
    //     return cachedVar;
    // }

    // Count enemies near building (recent seen heroes + weighted creeps)
    const gameState = updateDefendGameStateCache();
    let enemyHeroNearby = 0;
    for (const id of GetTeamPlayers(gameState.enemyTeam)) {
        if (IsHeroAlive(id)) {
            const info = GetHeroLastSeenInfo(id);
            if (info != null) {
                const d = info[0]; // TS 0-index
                if (d != null && d.time_since_seen <= CACHE_LASTSEEN_WINDOW && GetUnitToLocationDistance(hBuilding, d.location) <= 1600) {
                    enemyHeroNearby = enemyHeroNearby + 1;
                }
            }
        }
    }

    const unitState = updateDefendUnitStateCache();
    let creepWeights = 0;
    for (const unit of unitState.enemyCreeps) {
        if (jmz.IsValid(unit) && GetUnitToUnitDistance(hBuilding, unit) <= nRadius) {
            const name = unit.GetUnitName();
            if (name.includes("siege") && !name.includes("upgraded")) {
                creepWeights += 0.5;
            } else if (name.includes("upgraded_mega")) {
                creepWeights += 0.6;
            } else if (name.includes("upgraded")) {
                creepWeights += 0.4;
            } else if (name.includes("warlock_golem") || name.includes("shadow_shaman_ward")) {
                creepWeights += 1.0;
            } else if (name.includes("lone_druid_bear")) {
                enemyHeroNearby = enemyHeroNearby + 1;
            } else if (
                unit.IsCreep() ||
                unit.IsAncientCreep() ||
                unit.IsDominated() ||
                unit.HasModifier("modifier_chen_holy_persuasion") ||
                unit.HasModifier("modifier_dominated")
            ) {
                creepWeights += 0.2;
            }
        }
    }

    const nNearby = enemyHeroNearby + math.floor(creepWeights);
    if (nNearby === 0) return false;
    const pos = jmz.GetPosition(bot);

    let result = false;
    if (nNearby === 1) {
        if (pos === 2 || pos === GetClosestAllyPos([4, 5], hBuilding.GetLocation())) {
            result = true;
        }
    } else if (nNearby === 2) {
        if (pos === 2 || pos === 3 || pos === GetClosestAllyPos([4, 5], hBuilding.GetLocation()) || (pos === 1 && GetUnitToUnitDistance(bot, hBuilding) <= 3200)) {
            result = true;
        }
    } else if (nNearby === 3) {
        if (pos === 2 || pos === 3 || pos === 4 || pos === 5 || (pos === 1 && GetUnitToUnitDistance(bot, hBuilding) <= 3200)) {
            result = true;
        }
    } else if (nNearby >= 4) {
        result = true;
    }

    // Travel Boots/Tinker escalation (one defender at a time)
    if (!result) {
        if (DotaTime() - fTraveBootsDefendTime >= 20.0) {
            (bot as any).travel_boots_defender = false;
        }
        if (
            bot.GetUnitName() === "npc_dota_hero_tinker" &&
            bot.GetLevel() >= 6 &&
            jmz.CanCastAbility(bot.GetAbilityByName("tinker_keen_teleport")) &&
            IsThereNoTeammateTravelBootsDefender(bot)
        ) {
            (bot as any).travel_boots_defender = true;
            fTraveBootsDefendTime = DotaTime();
            result = true;
        } else {
            const boots = jmz.GetItem2(bot, "item_travel_boots") || jmz.GetItem2(bot, "item_travel_boots_2");
            if (jmz.CanCastAbility(boots) && IsThereNoTeammateTravelBootsDefender(bot)) {
                (bot as any).travel_boots_defender = true;
                fTraveBootsDefendTime = DotaTime();
                result = true;
            }
        }

        if (!result && pos === GetClosestAllyPos([2, 3], hBuilding.GetLocation())) {
            result = true;
        }
    }

    const underFire = bot.WasRecentlyDamagedByAnyHero(5);
    if (underFire && result) {
        // Only the closest appropriate role should commit while under fire
        const closestPos = GetClosestAllyPos([2, 3, 4, 5], hBuilding.GetLocation());
        if (jmz.GetPosition(bot) !== closestPos) {
            return false;
        }
    }

    // jmz.Utils.SetCachedVars(cacheKey, result);
    return result;
}

// Ping teammates to defend (rate-limited; role-aware)
function ConsiderPingedDefend(bot: Unit, lane: Lane, desire: number, building: Unit | null, tier: number, nEffAllies: number, nEnemies: number) {
    const gameState = updateDefendGameStateCache();
    if (gameState.isLaningPhase || gameState.aliveAllyCount === 0) return;
    if (!IsValidBuildingTarget(building)) return;
    if (tier < 2 || desire <= 0.5) return;
    if (!ShouldDefend(bot, building, 1600)) return;

    (jmz.Utils as any)["GameStates"] = (jmz.Utils as any)["GameStates"] || {};
    (jmz.Utils as any)["GameStates"]["defendPings"] = (jmz.Utils as any)["GameStates"]["defendPings"] || { pingedTime: GameTime() };
    const defendPings = (jmz.Utils as any)["GameStates"]["defendPings"];

    if (nEffAllies >= 1 && nEffAllies >= nEnemies) return;
    if (GameTime() - defendPings.pingedTime <= 6.0) return;

    const saferLoc = add(jmz.AdjustLocationWithOffsetTowardsFountain(building.GetLocation(), 850), RandomVector(50));

    const retreaters = jmz.GetRetreatingAlliesNearLoc(saferLoc, 1600);
    if (retreaters.length === 0) {
        bot.ActionImmediate_Chat(Localization.Get("say_come_def"), false);
        bot.ActionImmediate_Ping(saferLoc.x, saferLoc.y, false);
        defendPings.pingedTime = GameTime();
        defendPings.lane = lane;
    }
}


export function GetDefendDesire(bot: Unit, lane: Lane): BotModeDesire {
    // 0) quick invalid checks
    if (bot.IsInvulnerable() || !bot.IsHero() || !bot.IsAlive() || !bot.GetUnitName().includes("hero") || bot.IsIllusion()) {
        return BotModeDesire.None;
    }

    // (pre) compute dynamic TTL and include threatened lane in key when base/HG pressure is present
    // const baseThreatNow = IsBaseThreatActive();
    // const enemiesOnHGNow = jmz.Utils.CountEnemyHeroesOnHighGround(nTeam);
    // const threatenedLaneNow = baseThreatNow || enemiesOnHGNow >= 1 ? GetThreatenedLane() : lane;

    // const cacheTTL = baseThreatNow || enemiesOnHGNow >= 1 ? 0.2 : 0.6;
    // const cacheKey = `DefendDesire:${bot.GetPlayerID()}:${lane ?? -1}:${threatenedLaneNow}`;

    // const cachedVar = jmz.Utils.GetCachedVars(cacheKey, cacheTTL);
    // if (cachedVar != null) {
    //     (bot as any).defendDesire = cachedVar;
    //     return cachedVar;
    // }

    // 2) compute and publish
    const res = GetDefendDesireHelper(bot, lane);
    // jmz.Utils.SetCachedVars(cacheKey, res);
    (bot as any).defendDesire = res;
    return res;
}

function GetPrimaryTowerSiege(highGround: boolean, earlyResponse = false): LuaMultiReturn<[Lane | undefined, jmz.OuterTowerThreat | undefined]> {
    let selectedLane: Lane | undefined;
    let selectedThreat: jmz.OuterTowerThreat | undefined;
    let selectedScore = 0;
    for (const candidate of [Lane.Mid, Lane.Top, Lane.Bot]) {
        const [tower, , tier] = GetFurthestBuildingOnLane(candidate);
        if ((tier >= 3) === highGround && IsValidBuildingTarget(tower)) {
            const threat = jmz.GetOuterTowerThreat(tower, candidate);
            const score = threat.score + (!highGround && threat.middleGroup && threat.towerHP > 0.15 ? 10 : 0);
            if (score > 0 && (!earlyResponse || jmz.IsHighGroundResponseThreat(threat))
                && (selectedThreat === undefined || score > selectedScore
                || (score === selectedScore && threat.eta < selectedThreat.eta))) {
                selectedLane = candidate;
                selectedThreat = threat;
                selectedScore = score;
            }
        }
    }
    return $multi(selectedLane, selectedThreat);
}

export function GetDefendDesireHelper(bot: Unit, lane: Lane): BotModeDesire {
    if ((bot as any).laneToDefend == null) (bot as any).laneToDefend = lane;
    if ((bot as any).DefendLaneDesire == null) (bot as any).DefendLaneDesire = [0, 0, 0];

    // Update caches
    const gameState = updateDefendGameStateCache();
    const locationState = updateDefendLocationStateCache();
    // const unitState = updateDefendUnitStateCache(); // Not used in this function

    // currentTime = gameState.currentTime; // Using cached value directly
    const team = gameState.team;
    const ancient = gameState.ourAncient;

    // Per-bot state — avoids cross-bot data races from module-level vars
    const ds = getDefendState(bot);
    if (ds.waveClearLane === lane) {
        ds.waveClearLane = undefined;
        ds.waveClearTower = undefined;
        ds.waveClearRearTower = undefined;
        if (!bot.HasModifier("modifier_teleporting")) ds.waveClearTeleport = undefined;
        ds.waveClearRally = undefined;
        ds.waveClearGather = undefined;
        ds.waveClearNeedsGlyph = undefined;
        ds.waveClearScreen = undefined;
        (bot as any).ohaOuterTowerHoldUntil = undefined;
    }
    const trade = (bot as any).ohaOuterTowerTrade;
    if (trade && trade.expires <= DotaTime()) (bot as any).ohaOuterTowerTrade = undefined;
    ds.defendLoc = locationState.laneFronts[lane];
    const distanceToDefendLoc = GetUnitToLocationDistance(bot, ds.defendLoc);

    // This must precede the normal "keep pushing" and hero-only early
    // returns. Otherwise creeps can destroy Ancient while nobody defends.
    const creepBaseDesire = GetCreepBaseDefenseDesire(bot, lane, ancient);
    if (creepBaseDesire !== null) {
        if (creepBaseDesire > 0.9 && ancient) {
            // Creep-only emergency is per defender, not a global base leash.
            // Global baseThreatUntil is reserved for the ordinary hero-threat path.
            (bot as any)._ohaCreepDefenseUntil = DotaTime() + BASE_THREAT_HOLD;
            (bot as any).ohaHighGroundResponse = undefined;
            ds.defendLoc = ancient.GetLocation();
            (bot as any).laneToDefend = Lane.Mid;
        }
        return creepBaseDesire;
    }

    if (GetInnerBaseAttacker(ancient)) baseThreatUntil = DotaTime() + BASE_THREAT_HOLD;
    if (ancient && IsBaseThreatActive()) {
        if (lane !== Lane.Mid) return BotModeDesire.VeryLow;
        (bot as any).ohaHighGroundResponse = undefined;
        (bot as any).ohaMidCover = undefined;
        (bot as any).ohaInnerHeroDefenseUntil = baseThreatUntil;
        bot.laneToDefend = lane;
        ds.defendLoc = ancient.GetLocation();
        return 0.97 as BotModeDesire;
    }
    let siegeLane: Lane | undefined;
    let siege: jmz.OuterTowerThreat | undefined;
    if (!gameState.isLaningPhase) [siegeLane, siege] = GetPrimaryTowerSiege(true, true);
    if (siege) {
        if (lane !== Lane.Mid && ((bot as any)._ohaCreepDefenseUntil ?? -1) > DotaTime() && GetBaseCreepResponse(bot, ancient)) {
            return BotModeDesire.VeryLow;
        }
        let tower = siege.tower;
        let assignedStage: Vector | undefined;
        let reach = bot.GetAttackRange();
        let cover = false;
        const [role, plan] = jmz.GetPostFightDuty(bot);
        if (role && plan) {
            const [building, , tier] = GetFurthestBuildingOnLane(plan.lane);
            if (building === plan.building && tier >= 3
                && (building === tower || jmz.GetOuterTowerThreat(building, plan.lane).underAttack)) {
                tower = building;
                siegeLane = plan.lane;
                cover = role === "cover";
                assignedStage = cover ? plan.hold : plan.primary!.staging ?? plan.hold;
                if (!cover) reach = plan.primary!.reach;
            }
        }
        if (lane !== siegeLane) {
            if ((bot as any).ohaHighGroundResponse?.lane === lane) (bot as any).ohaHighGroundResponse = undefined;
            return BotModeDesire.VeryLow;
        }
        if (siege.underAttack && !role && (!plan || plan.building === tower && !plan.primary)) {
            const [, orders] = jmz.GetOuterTowerResponse(tower.GetLocation(), siege, undefined, true);
            const duty = orders[bot.GetPlayerID()];
            if (duty) {
                reach = duty.reach;
                cover = duty.cover;
                assignedStage = plan?.hold ?? jmz.AdjustLocationWithOffsetTowardsFountain(tower.GetLocation(), 550);
            }
        }
        const rear = ancient && jmz.AdjustLocationWithOffsetTowardsFountain(ancient.GetLocation(), 350);
        let stage = jmz.AdjustLocationWithOffsetTowardsFountain(tower.GetLocation(), 1450);
        let duty = "reserve";
        if (assignedStage && IsLocationPassable(assignedStage) && jmz.CanCommitToLaneTeleport(bot, assignedStage, true, 650)) {
            stage = assignedStage;
            duty = cover ? "cover" : "clear";
        } else if (!IsLocationPassable(stage) || jmz.GetLastSeenEnemiesNearLoc(stage, 850).length > 0
            || jmz.GetEnemiesNearLoc(stage, 850).length > 0) stage = rear || stage;
        if (!cover) {
            const threat = siege.tower === tower ? siege : jmz.GetOuterTowerThreat(tower, siegeLane);
            const firing = jmz.GetSiegeFiringPosition(bot, tower, threat, stage);
            if (firing) {
                stage = firing;
                duty = "fire";
            } else if (!assignedStage) {
                const support = jmz.GetSiegeSupportPosition(bot, tower, threat, stage);
                if (support) { stage = support; duty = "support"; }
            }
        }
        (bot as any).ohaHighGroundResponse = {lane, tower, stage, rear, reach, cover, duty, expires: DotaTime() + 1};
        bot.laneToDefend = lane;
        ds.defendLoc = stage;
        return 0.96;
    } else if ((bot as any).ohaHighGroundResponse?.lane === lane) {
        (bot as any).ohaHighGroundResponse = undefined;
    }
    if (!IsBaseThreatActive()) {
        const [role, plan] = jmz.GetPostFightDuty(bot);
        if (role && plan) {
            if (lane !== plan.lane) return BotModeDesire.VeryLow;
            const reach = role === "clear" ? plan.primary!.reach : bot.GetAttackRange();
            const staging = role === "clear" ? plan.primary?.staging ?? plan.hold : undefined;
            (bot as any).ohaMidCover = {tower: plan.building, lane, reach, cover: role === "cover", staging, expires: DotaTime() + 1};
            bot.laneToDefend = lane;
            return (role === "cover" ? 0.80 : 0.83) as BotModeDesire;
        }
        if ((bot as any).ohaMidCover?.lane === lane) (bot as any).ohaMidCover = undefined;
        if (plan && jmz.HasAssignedWaveDefense(plan, lane)) return BotModeDesire.VeryLow;
    }
    const botLevel = bot.GetLevel();
    if (
        bot.GetAssignedLane() !== lane &&
        distanceToDefendLoc > 3000 &&
        ((jmz.GetPosition(bot) === 1 && botLevel < 6) ||
            (jmz.GetPosition(bot) === 2 && botLevel < 6) ||
            (jmz.GetPosition(bot) === 3 && botLevel < 5) ||
            (jmz.GetPosition(bot) === 4 && botLevel < 4) ||
            (jmz.GetPosition(bot) === 5 && botLevel < 4))
    ) {
        return BotModeDesire.None;
    }

    // -- 如果等级低，不防守
    if (botLevel < 3) {
        return BotModeDesire.None;
    }

    // Don't abandon a team push to defend a tower from creeps.
    // If 3+ allies are grouped together pushing, defend desire is very low.
    let teamIsPushing = false;
    for (let i = 1; i <= GetTeamPlayers(nTeam).length; i++) {
        const member = GetTeamMember(i);
        if (member && member !== bot && member.IsAlive()) {
            const mode = member.GetActiveMode();
            if (mode === BotMode.PushTowerTop || mode === BotMode.PushTowerMid || mode === BotMode.PushTowerBot) {
                const alliesNear = jmz.GetAlliesNearLoc(member.GetLocation(), 1600);
                if (alliesNear.length >= 3) {
                    teamIsPushing = true;
                    break;
                }
            }
        }
    }

    const recentlyHit = bot.WasRecentlyDamagedByAnyHero(5) || bot.WasRecentlyDamagedByTower(5);

    const enemiesAtAncient = ancient ? jmz.Utils.CountEnemyHeroesNear(ancient.GetLocation(), 2200) : 0;
    const laneAlarm = !recentlyHit && jmz.Utils.CountEnemyHeroesOnHighGround(gameState.team) >= 2;
    if (laneAlarm) {
        const [siegeLane] = GetPrimaryTowerSiege(true);
        if (lane !== (siegeLane ?? GetThreatenedLane())) return BotModeDesire.VeryLow;
        bot.laneToDefend = lane;
        ds.defendLoc = GetHighGroundEdgeWaitPoint(team, lane);
    } else if (jmz.Utils.GetLocationToLocationDistance(gameState.teamFountainTpPoint, ds.defendLoc) < 3000) {
        const enemyLaneFront = locationState.enemyLaneFronts[lane];
        const eNear = jmz.GetLastSeenEnemiesNearLoc(enemyLaneFront, 1600);
        const aNear = jmz.GetAlliesNearLoc(enemyLaneFront, 1600);
        if (GetUnitToLocationDistance(bot, enemyLaneFront) > bot.GetAttackRange() && eNear.length <= aNear.length + 1) {
            ds.defendLoc = enemyLaneFront;
        }
    }

    ds.distanceToLane[lane] = GetUnitToLocationDistance(bot, ds.defendLoc);
    ds.nInRangeAlly = jmz.GetNearbyHeroes(bot, 1600, false, BotMode.None);
    ds.nInRangeEnemy = jmz.GetLastSeenEnemiesNearLoc(bot.GetLocation(), 1600);

    ds.weAreStronger = jmz.WeAreStronger(bot, 2500);
    const [furthestBuilding, urgentMul, buildingTier] = GetFurthestBuildingOnLane(lane);
    if (!IsValidBuildingTarget(furthestBuilding)) return BotModeDesire.None;
    const hub = furthestBuilding.GetLocation();
    const lEnemies = jmz.GetLastSeenEnemiesNearLoc(hub, 2500);

    // Human priority ping (use a hint floor instead of early-return).
    let pingFloor = 0;
    const [human, humanPing] = jmz.GetHumanPing();
    if (human && humanPing && !humanPing.normal_ping && DotaTime() > 0) {
        const [isPinged, pingedLane] = jmz.IsPingCloseToValidTower(gameState.team, humanPing, 800, 5.0);
        if (isPinged && lane === pingedLane && GameTime() < humanPing.time + PING_DELTA) {
            (bot as any).laneToDefend = lane;
            pingFloor = 0.95;
        }
    }

    const highGround = buildingTier >= 3;
    if (pingFloor === 0 && (highGround || !laneAlarm)) {
        const [primaryLane, threat] = GetPrimaryTowerSiege(highGround);
        const next = ds.nextWave;
        if (next && next.lane === lane && next.tower === furthestBuilding && DotaTime() < next.expires
            && primaryLane === undefined) {
            ds.waveClearLane = lane;
            ds.waveClearTower = next.tower;
            ds.waveClearReach = next.reach;
            ds.waveClearCover = false;
            ds.waveClearTeleport = undefined;
            (bot as any).ohaOuterTowerTrade = undefined;
            (bot as any).ohaOuterTowerHoldUntil = next.expires;
            (bot as any).laneToDefend = lane;
            return 0.84 as BotModeDesire;
        }
        if (primaryLane === lane && threat) {
            let fallback: Vector | undefined;
            let rearTower: Unit | undefined;
            if (!highGround) {
                const towerId = buildingTier === 1
                    ? (lane === Lane.Top ? Tower.Top2 : lane === Lane.Mid ? Tower.Mid2 : Tower.Bot2)
                    : (lane === Lane.Top ? Tower.Top3 : lane === Lane.Mid ? Tower.Mid3 : Tower.Bot3);
                const nextTower = GetTower(team, towerId);
                if (IsValidBuildingTarget(nextTower)) {
                    rearTower = nextTower;
                    fallback = jmz.AdjustLocationWithOffsetTowardsFountain(nextTower.GetLocation(), 350);
                }
            }
            const [delay, assignments] = jmz.GetOuterTowerResponse(hub, threat, fallback, highGround);
            if (delay) {
                const assignment = assignments[bot.GetPlayerID()];
                if (assignment !== undefined && (assignment.rally || highGround || jmz.GetHP(furthestBuilding) > 0.15)) {
                    ds.waveClearLane = lane;
                    ds.waveClearTower = furthestBuilding;
                    ds.waveClearRearTower = assignment.rally ? rearTower : undefined;
                    ds.waveClearReach = assignment.reach;
                    ds.waveClearCover = assignment.cover;
                    ds.waveClearTeleport = assignment.teleport;
                    ds.waveClearRally = assignment.rally;
                    ds.waveClearGather = assignment.gather;
                    ds.waveClearNeedsGlyph = assignment.needsGlyph;
                    ds.waveClearScreen = assignment.screen;
                    (bot as any).ohaOuterTowerTrade = undefined;
                    const keepNext = !assignment.gather || assignment.screen || assignment.reach >= 1050;
                    if (rearTower && !assignment.cover && keepNext && (assignment.rally || threat.count >= 3) && threat.waveSize > 0) {
                        const march = GetUnitToUnitDistance(furthestBuilding!, rearTower) / 300;
                        ds.nextWave = { lane, tower: rearTower, reach: assignment.reach, expires: DotaTime() + math.min(22, march + 9) };
                    }
                    (bot as any).ohaOuterTowerHoldUntil = DotaTime() + 3;
                    (bot as any).laneToDefend = lane;
                    if (highGround) return 0.96 as BotModeDesire;
                    if (assignment.gather) return (lane === Lane.Mid && buildingTier === 1 ? 0.93 : 0.89) as BotModeDesire;
                    if (assignment.rally || assignment.teleport || (threat.siege && threat.count <= 1)) return 0.84 as BotModeDesire;
                    return BotModeDesire.High;
                } else if (!highGround) {
                    (bot as any).ohaOuterTowerTrade = { lane, location: hub, expires: DotaTime() + 6 };
                    return BotModeDesire.VeryLow;
                }
            } else if (trade && trade.lane === lane) {
                (bot as any).ohaOuterTowerTrade = undefined;
            }
        } else if (primaryLane !== undefined && !highGround) {
            const localThreat = jmz.GetOuterTowerThreat(furthestBuilding!, lane);
            if (bot.GetAssignedLane() !== lane || GetUnitToUnitDistance(bot, furthestBuilding!) > 1600
                || localThreat.score <= 0 || localThreat.waveSize === 0) return BotModeDesire.VeryLow;
        }
    }
    if (teamIsPushing && !laneAlarm && buildingTier < 3 && pingFloor === 0) {
        return BotModeDesire.VeryLow;
    }

    // Bail-outs to avoid feed / conflicts
    const pos = jmz.GetPosition(bot);
    const bMyLane = bot.GetAssignedLane() === lane;
    if (
        (!laneAlarm && ds.nInRangeEnemy.length > ds.nInRangeAlly.length + 1 && !ds.weAreStronger) ||
        (!bMyLane && pos === 1 && gameState.isLaningPhase) || // keep carry safe early
        (jmz.IsDoingRoshan(bot) && jmz.GetAlliesNearLoc(jmz.GetCurrentRoshanLocation(), 2800).length >= 3) ||
        (jmz.IsDoingTormentor(bot) &&
            (jmz.GetAlliesNearLoc(jmz.GetTormentorLocation(team), 1600).length >= 2 || jmz.GetAlliesNearLoc(jmz.GetTormentorWaitingLocation(team), 2500).length >= 2) &&
            enemiesAtAncient === 0)
    ) {
        return BotModeDesire.VeryLow;
    }

    // Use ShouldDefend to gate/dampen
    const shouldDef = ShouldDefend(bot, furthestBuilding, 1600);
    if (!shouldDef) {
        const dist = ds.distanceToLane[lane];
        const tp = jmz.Utils.GetItemFromFullInventory(bot, "item_tpscroll");
        const nearEnemiesAtBuilding = jmz.GetLastSeenEnemiesNearLoc(furthestBuilding.GetLocation(), 1200);
        if (
            (!jmz.CanCastAbility(tp) && dist && dist > 4000 && nearEnemiesAtBuilding.length === 0) ||
            (nearEnemiesAtBuilding.length === 0 && jmz.GetAlliesNearLoc(furthestBuilding.GetLocation(), 1600).length >= 1)
        ) {
            return BotModeDesire.VeryLow;
        }
    }

    let nDefendDesire = GetDefendLaneDesire(lane);

    // Avoid dogpile if enemies absent & allies/core already covering
    const nDefendAllies = jmz.GetAlliesNearLoc(hub, 2500);
    const nEffAllies = nDefendAllies.length + jmz.Utils.GetAllyIdsInTpToLocation(hub, 2500).length;

    if (lEnemies.length === 0 && (jmz.IsAnyAllyDefending(bot, lane) || !shouldDef)) {
        return BotModeDesire.VeryLow;
    }
    if (lEnemies.length === 1 && (nEffAllies > lEnemies.length || (jmz.IsAnyAllyDefending(bot, lane) && jmz.GetAverageLevel(false) >= jmz.GetAverageLevel(true)))) {
        return BotModeDesire.VeryLow;
    }

    // Cap & floor via ShouldDefend & tier
    const capBoost = shouldDef ? 0.1 : 0.0;
    let maxDesire = (buildingTier >= 3 && nEffAllies >= lEnemies.length ? 1.0 : MAX_DESIRE_CAP) + capBoost;
    maxDesire = math.min(maxDesire, 1.0);
    const baseFloor = shouldDef ? BotActionDesire.Low : BotActionDesire.VeryLow;

    nDefendDesire = RemapValClamped(jmz.GetHP(bot), 0.75, 0.2, RemapValClamped(nDefendDesire * urgentMul, 0, 1, baseFloor, maxDesire), BotActionDesire.Low);

    if (shouldDef && buildingTier <= 2 && pos !== 1 && lEnemies.length >= 2 && !recentlyHit &&
        jmz.GetHP(bot) >= 0.55 && GetUnitToLocationDistance(bot, hub) <= 2700 &&
        nDefendAllies.length >= math.min(2, lEnemies.length - 1)) {
        nDefendDesire = math.max(nDefendDesire, 0.68) as BotModeDesire;
    }

    // Be cautious if outnumbered near destination and not stronger
    {
        const dist = ds.distanceToLane[lane];
        if (dist && dist < 1600 && ds.nInRangeEnemy.length > ds.nInRangeAlly.length && !ds.weAreStronger) {
            nDefendDesire = RemapValClamped(nDefendDesire, 0, 1, BotActionDesire.VeryLow, BotActionDesire.High);
        }
    }

    // Don’t abandon defend for a low-HP chase
    const botTarget = jmz.GetProperTarget(bot);
    if (jmz.IsValidHero(botTarget) && jmz.GetHP(botTarget) < 0.6 && jmz.GetHP(bot) > jmz.GetHP(botTarget) && GetUnitToUnitDistance(bot, botTarget) < 1500) {
        nDefendDesire = nDefendDesire * 0.4;
    }

    // TP/distance sanity
    {
        const tp = jmz.Utils.GetItemFromFullInventory(bot, "item_tpscroll");
        const dist = ds.distanceToLane[lane];
        if (!jmz.CanCastAbility(tp) && dist && dist > 4000) {
            const nearEnemies = jmz.GetLastSeenEnemiesNearLoc(furthestBuilding.GetLocation(), 1200);
            if (nearEnemies.length === 0 || bot.WasRecentlyDamagedByAnyHero(2)) {
                nDefendDesire = nDefendDesire * 0.5;
            }
            nDefendDesire = RemapValClamped(dist / 4000, 0, 2, nDefendDesire, BotActionDesire.VeryLow);
        }
    }

    // Don’t throw bodies at doomed low-HP T1/T2
    if (IsValidBuildingTarget(furthestBuilding) && furthestBuilding !== ancient) {
        const hp = jmz.GetHP(furthestBuilding);
        if ((buildingTier === 1 && hp <= 0.15) || (buildingTier === 2 && hp <= 0.1)) {
            return BotModeDesire.None;
        }
    }

    // Apply floors (panic/ping) after all dampeners
    if (laneAlarm) nDefendDesire = math.max(nDefendDesire, 0.96);
    if (pingFloor > 0) nDefendDesire = math.max(nDefendDesire, pingFloor);

    // Ask for help if needed
    ConsiderPingedDefend(bot, lane, nDefendDesire, furthestBuilding, buildingTier, nEffAllies, lEnemies.length);

    if (recentlyHit) {
        // Cut desire and favor regrouping when outnumbered
        nDefendDesire = nDefendDesire * 0.4;
        if (ds.nInRangeEnemy.length >= ds.nInRangeAlly.length && !ds.weAreStronger) {
            nDefendDesire = math.min(nDefendDesire, BotActionDesire.Low);
        }
    }

    if (nDefendDesire > 0.7) {
        (jmz.Utils as any).GameStates = (jmz.Utils as any).GameStates || {};
        (jmz.Utils as any).GameStates["recentDefendTime"] = DotaTime();
        (bot as any).laneToDefend = lane;
    }

    return nDefendDesire as BotModeDesire;
}

function AttackHighGroundWaveFromHere(bot: Unit, tower: Unit, rear: Vector | undefined): boolean {
    if (!rear || bot.IsDisarmed() || GetUnitToLocationDistance(bot, rear) > GetUnitToLocationDistance(tower, rear)
        || (GetUnitToUnitDistance(bot, tower) > 1300 && GetUnitToLocationDistance(bot, rear) > 1500)
        || jmz.GetHP(bot) < 0.55 || bot.WasRecentlyDamagedByAnyHero(2)) return false;
    const current = bot.GetAttackTarget();
    let target: Unit | undefined;
    for (const creep of bot.GetNearbyLaneCreeps(bot.GetAttackRange(), true)) {
        if (jmz.IsValid(creep) && creep.CanBeSeen() && jmz.CanBeAttacked(creep)
            && (GetUnitToUnitDistance(creep, tower) <= 950 || GetUnitToLocationDistance(creep, rear) <= 1500)) {
            if (creep === current) { target = creep; break; }
            if (!target || creep.GetAttackTarget() === tower) target = creep;
        }
    }
    if (!target || !jmz.CanCommitToLaneTeleport(bot, bot.GetLocation(), true, 850)) return false;
    if (target !== current) bot.Action_AttackUnit(target, true);
    return true;
}

export function DefendThink(bot: Unit, lane: Lane) {
    const now = DotaTime();

    if (jmz.CanNotUseAction(bot)) return;
    let response = (bot as any).ohaHighGroundResponse;
    if (response && !IsStandingHighGroundBuilding(response.tower)) {
        (bot as any).ohaHighGroundResponse = undefined;
        response = undefined;
    }
    if (response && response.lane === lane && now < response.expires) {
        if (bot.HasModifier("modifier_teleporting") || bot.IsChanneling() || bot.IsCastingAbility()
            || bot.IsUsingAbility()) return;
        if (AttackHighGroundWaveFromHere(bot, response.tower, response.rear)) return;
        if (GetUnitToLocationDistance(bot, response.stage) > 350) {
            const point = jmz.GetHighGroundWalkPoint(bot, response.stage, response.rear);
            if (point && GetUnitToLocationDistance(bot, point) > 180) {
                bot.Action_MoveToLocation(point);
            } else if (GetUnitToLocationDistance(bot, response.stage) > 850 && !bot.WasRecentlyDamagedByAnyHero(2)) {
                bot.Action_ClearActions(true);
            }
            return;
        }
        jmz.RunOuterTowerHold(bot, response.tower.GetLocation(), response.reach, response.cover, response.stage);
        return;
    }
    const guard = (bot as any).ohaMidCover;
    if (guard && lane === guard.lane && now < guard.expires && !IsBaseThreatActive()
        && ((bot as any)._ohaCreepDefenseUntil ?? -1) <= now && jmz.IsValidBuilding(guard.tower)) {
        const stage = guard.staging && jmz.CanCommitToLaneTeleport(bot, guard.staging, true, 650) ? guard.staging : undefined;
        jmz.RunOuterTowerHold(bot, guard.tower.GetLocation(), guard.reach, guard.cover, stage);
        return;
    }
    if (jmz.Utils.IsBotThinkingMeaningfulAction(bot, Customize.ThinkLess, "defend")) return;

    // a small don't-walk-through-fire guard - use cached enemies when possible
    const botLocation = bot.GetLocation();
    const pathCacheKey = `pathEnemies_${bot.GetPlayerID()}_${Math.floor(now * 2)}`; // 500ms cache
    let pathEnemies: Unit[];
    if (!(bot as any)[pathCacheKey]) {
        pathEnemies = jmz.GetLastSeenEnemiesNearLoc(botLocation, 1600);
        (bot as any)[pathCacheKey] = pathEnemies;
        // Clean old cache entries
        Object.keys(bot).forEach(key => {
            if (key.startsWith("pathEnemies_") && key !== pathCacheKey) {
                delete (bot as any)[key];
            }
        });
    } else {
        pathEnemies = (bot as any)[pathCacheKey];
    }

    const ds = getDefendState(bot);
    if (bot.WasRecentlyDamagedByAnyHero(5) && pathEnemies.length > ds.nInRangeEnemy.length) {
        // step back toward fountain a bit, then re-eval next tick
        const safe = jmz.AdjustLocationWithOffsetTowardsFountain(bot.GetLocation(), 700);
        bot.Action_MoveToLocation(add(safe, jmz.RandomForwardVector(120)));
        return;
    }

    // Base-defense leash: anchor near Ancient, don't drift out
    if (IsBaseThreatActive() || ((bot as any)._ohaCreepDefenseUntil || -1) > now) {
        const ancient = GetAncient(nTeam);
        const anchor = jmz.AdjustLocationWithOffsetTowardsFountain(ancient.GetLocation(), 200);

        const intruder = GetInnerBaseAttacker(ancient);
        if (intruder && jmz.CanBeAttacked(intruder) && jmz.IsInRange(bot, intruder, bot.GetAttackRange())) {
            if (bot.GetAttackTarget() !== intruder) bot.Action_AttackUnit(intruder, true);
            return;
        }
        const toAnc = GetUnitToUnitDistance(bot, ancient);
        if (toAnc > BASE_LEASH_OUTBOUND) {
            const moveLoc = add(anchor, jmz.RandomForwardVector(250));
            bot.Action_MoveToLocation(moveLoc);
            return;
        }

        const nSearchRange = 1400;
        const ancientLoc = ancient.GetLocation();
        // Use a simpler cache approach for Lua compatibility
        const enemiesCacheKey = `ancientEnemies_${Math.floor(now * 5)}`;
        let enemiesNear: Unit[];
        if (!(jmz.Utils as any)[enemiesCacheKey]) {
            enemiesNear = jmz.GetEnemiesNearLoc(ancientLoc, nSearchRange);
            (jmz.Utils as any)[enemiesCacheKey] = enemiesNear;
            // Clean old cache entries
            const utils = jmz.Utils as any;
            Object.keys(utils).forEach(key => {
                if (typeof key === "string" && key.startsWith("ancientEnemies_") && key !== enemiesCacheKey) {
                    delete utils[key];
                }
            });
        } else {
            enemiesNear = (jmz.Utils as any)[enemiesCacheKey];
        }

        const baseCreep = GetBaseCreepAttacker(ancient);
        if (baseCreep && ((bot as any)._ohaCreepDefenseUntil ?? -1) > now && GetUnitToUnitDistance(bot, baseCreep) <= BASE_THREAT_RADIUS) {
            bot.Action_AttackUnit(baseCreep, true);
            return;
        }
        if (jmz.IsValidHero(enemiesNear[0]) && jmz.IsInRange(bot, enemiesNear[0], nSearchRange)) {
            bot.Action_AttackUnit(enemiesNear[0], true);
            return;
        }

        // Hit the actual creep threatening the Ancient/T4 instead of
        // attack-moving randomly within base while it keeps damaging us.
        if (baseCreep && GetUnitToUnitDistance(bot, baseCreep) <= BASE_THREAT_RADIUS) {
            bot.Action_AttackUnit(baseCreep, true);
            return;
        }

        const attackMoveLoc = add(anchor, jmz.RandomForwardVector(300));
        bot.Action_AttackMove(attackMoveLoc);
        return;
    }

    // Normal defend movement/targeting
    const attackRange = bot.GetAttackRange();
    const nSearchRange = (attackRange < 900 && 900) || math.min(attackRange, SEARCH_RANGE_DEFAULT);
    if (!ds.defendLoc) ds.defendLoc = GetLaneFrontLocation(nTeam, lane, 0);

    const [bld, _, buildingTier] = GetFurthestBuildingOnLane(lane);
    let hub = ds.defendLoc;
    if (IsValidBuildingTarget(bld)) hub = bld.GetLocation();
    if (!hub) hub = GetLaneFrontLocation(nTeam, lane, 0);

    if (ds.waveClearLane === lane) {
        const [primaryLane, threat] = GetPrimaryTowerSiege(buildingTier >= 3);
        const next = ds.nextWave;
        const following = primaryLane === undefined && next && next.lane === lane && next.tower === bld && now < next.expires;
        if (bld !== ds.waveClearTower || (primaryLane !== lane && !following) || ((bot as any).ohaOuterTowerHoldUntil ?? 0) <= now) {
            OnEnd(bot, lane);
            (bot as any).ohaOuterTowerHoldUntil = undefined;
            ds.waveClearLane = undefined;
            return;
        }
        const holdTower = ds.waveClearRearTower;
        const holdLocation = holdTower && jmz.IsValidBuilding(holdTower) ? holdTower.GetLocation() : hub;
        const issued = ds.waveClearGather && threat
            ? jmz.RunOuterTowerContest(bot, bld!, threat, ds)
            : jmz.RunOuterTowerHold(bot, holdLocation, ds.waveClearReach ?? attackRange, ds.waveClearCover === true);
        if (issued) {
            (bot as any).ohaIssuedOuterHold = lane;
        }
        return;
    }

    if (buildingTier >= 3) {
        const edgeInside = GetHighGroundEdgeWaitPoint(nTeam, lane);
        if (IsStandingHighGroundBuilding(bld)) {
            const threat = jmz.GetOuterTowerThreat(bld, lane);
            const stage = jmz.GetSiegeFiringPosition(bot, bld, threat, edgeInside);
            jmz.RunOuterTowerHold(bot, bld.GetLocation(), attackRange, false, stage ?? edgeInside);
        } else {
            jmz.RunOuterTowerHold(bot, edgeInside, attackRange, false);
        }
        return;
    }

    const released = (bot as any).ohaOuterTowerTrade;
    if (released && released.lane === lane && now < released.expires) {
        OnEnd(bot, lane);
        if (GetUnitToLocationDistance(bot, hub) < 1500 && jmz.GetLastSeenEnemiesNearLoc(hub, 1600).length >= 2) {
            bot.Action_MoveToLocation(jmz.AdjustLocationWithOffsetTowardsFountain(hub, 1650));
        }
        return;
    }

    // Prefer nearest valid enemy hero within range (cheap local queries first)
    const enemiesAtHub = jmz.GetEnemiesNearLoc(hub, SEARCH_RANGE_DEFAULT);
    if (IsValidBuildingTarget(bld) && enemiesAtHub.length >= 3
        && jmz.GetAvailableFightAllies(bot, hub, 1500) < Math.max(2, enemiesAtHub.length - 2)) {
        // Hold behind the tower until the backline can join.
        jmz.RunOuterTowerHold(bot, jmz.AdjustLocationWithOffsetTowardsFountain(hub, 650), attackRange, false);
        return;
    }
    if (enemiesAtHub.length >= 2 && !ds.weAreStronger) {
        if (jmz.IsValidHero(enemiesAtHub[0]) && jmz.IsInRange(bot, enemiesAtHub[0], attackRange)) {
            bot.Action_AttackUnit(enemiesAtHub[0], true);
        } else {
            bot.Action_MoveToLocation(jmz.AdjustLocationWithOffsetTowardsFountain(hub, 250));
        }
        return;
    }
    if (jmz.IsValidHero(enemiesAtHub[0]) && jmz.IsInRange(bot, enemiesAtHub[0], ds.weAreStronger ? nSearchRange : attackRange)) {
        bot.Action_AttackUnit(enemiesAtHub[0], true);
        return;
    }

    const nEnemyHeroes = bot.GetNearbyHeroes(SEARCH_RANGE_DEFAULT, true, BotMode.None);
    if (jmz.IsValidHero(nEnemyHeroes[0]) && jmz.IsInRange(bot, nEnemyHeroes[0], ds.weAreStronger ? nSearchRange : attackRange)) {
        bot.Action_AttackUnit(nEnemyHeroes[0], true);
        return;
    }

    // Otherwise, clear strongest creep (avoid full scans)
    const creeps = bot.GetNearbyCreeps(900, true);
    if (creeps && creeps.length > 0 && (!enemiesAtHub || enemiesAtHub.length === 0)) {
        let best: Unit | null = null;
        let bestDmg = -1;
        for (const c of creeps) {
            if (jmz.IsValid(c) && jmz.CanBeAttacked(c)) {
                const dmg = c.GetAttackDamage();
                if (dmg > bestDmg) {
                    best = c;
                    bestDmg = dmg;
                }
            }
        }
        if (best) {
            bot.Action_AttackUnit(best, true);
            return;
        }
    }

    // Move with small jitter; prefer assertive move if ShouldDefend says we're the responder
    if (bld && ShouldDefend(bot, bld, 1600)) {
        const attackMoveLoc = add(hub, jmz.RandomForwardVector(300));
        bot.Action_AttackMove(attackMoveLoc);
        return;
    }

    const dist = ds.distanceToLane[lane] || GetUnitToLocationDistance(bot, hub);
    if ((ds.weAreStronger || ds.nInRangeAlly.length >= ds.nInRangeEnemy.length) && dist < SEARCH_RANGE_DEFAULT) {
        const attackMoveLoc = add(hub, jmz.RandomForwardVector(300));
        bot.Action_AttackMove(attackMoveLoc);
    } else if (dist > SEARCH_RANGE_DEFAULT * 1.7) {
        const moveLoc = add(hub, jmz.RandomForwardVector(300));
        bot.Action_MoveToLocation(moveLoc);
    } else {
        const moveLoc = add(hub, jmz.RandomForwardVector(1000));
        bot.Action_MoveToLocation(moveLoc);
    }
}

export function OnEnd(bot: Unit, lane: Lane): void {
    const ds: DefendBotState | undefined = (bot as any)._defend;
    if (ds && ds.waveClearLane === lane) ds.waveClearTarget = undefined;
    if ((bot as any).ohaIssuedOuterHold !== lane) return;
    (bot as any).ohaIssuedOuterHold = undefined;
    if (!bot.IsUsingAbility() && !bot.IsCastingAbility() && !bot.IsChanneling()) bot.Action_ClearActions(true);
    // no-op
}
