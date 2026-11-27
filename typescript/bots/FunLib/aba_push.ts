import * as jmz from "bots/FunLib/jmz_func";
// eslint-disable-next-line @typescript-eslint/no-var-requires
import Customize = require("bots/Customize/general");
import { Barracks, BotMode, BotModeDesire, DamageType, Lane, Team, Tower, Unit, UnitType, Vector } from "bots/ts_libs/dota";
import { IsValidUnit, GetLocationToLocationDistance, RadiantFountainTpPoint, DireFountainTpPoint } from "./utils";
import { getGlobalGameState, getGlobalLocationState, getCachedAlliesNearLoc, getCachedEnemiesNearLoc, autoCleanupCache, getCachedData } from "./global_cache";
import { GetBaseCreepResponse } from "./aba_defend";

Customize.ThinkLess = Customize.Enable ? Customize.ThinkLess : 1;

/**
 * Tunables / thresholds
 * (kept from Lua; comments preserved)
 */
const pingTimeDelta = 5;
const StartToPushTime = 16 * 60; // after X mins, start considering to push.
const BOT_MODE_DESIRE_EXTRA_LOW = 0.02;

/** Module-scoped state (cache-ish). Keep small and intentional. */
let hEnemyAncient: Unit | null = null;

/** Performance cache - avoid redundant calculations between GetPushDesire (300ms) and Think (every frame) */
type CachedGameState = {
    lastUpdate: number;
    currentTime: number;
    gameMode: number;
    team: Team;
    enemyTeam: Team;
    ourAncient: Unit | null;
    enemyAncient: Unit | null;
    aliveAllyCount: number;
    aliveEnemyCount: number;
    aliveAllyCoreCount: number;
    aliveEnemyCoreCount: number;
    teamNetworth: number;
    enemyNetworth: number;
    averageLevel: number;
    hasAegis: boolean;
    isEarlyGame: boolean;
    isMidGame: boolean;
    isLateGame: boolean;
    isLaningPhase: boolean;
};

type CachedLocationState = {
    lastUpdate: number;
    laneFronts: Record<Lane, Vector>;
    teamFountain: Vector;
    enemyFountain: Vector;
    roshanLocation: Vector;
    tormentorLocation: Vector;
    tormentorWaitingLocation: Vector;
};

type CachedUnitState = {
    lastUpdate: number;
    enemyBuildings: Unit[];
    alliedHeroes: Unit[];
    enemyHeroes: Unit[];
    alliedCreeps: Unit[];
    enemyCreeps: Unit[];
};

type CachedBotState = {
    lastUpdate: number;
    botId: number;
    attackRange: number;
    location: Vector;
    hp: number;
    mp: number;
    nearbyTowers: Unit[];
    nearbyLaneCreeps: Unit[];
    nearbyCreeps: Unit[];
    attackTarget: Unit | null;
    distanceToAncient: number;
    distanceToTargetLoc: number;
};

const PUSH_CACHE_TTL = 0.5; // 500ms cache TTL - increased for better performance
const BOT_CACHE_TTL = 0.2; // 200ms cache TTL for bot-specific data - increased for better performance
// Frame rate limiter removed — caused stale action replay and shared state bugs
let gameStateCache: CachedGameState | null = null;
let locationStateCache: CachedLocationState | null = null;
let unitStateCache: CachedUnitState | null = null;
let botStateCache: Record<number, CachedBotState> = {};

/** Update game state cache if needed */
function updateGameStateCache(): CachedGameState {
    const now = DotaTime();
    if (gameStateCache && now - gameStateCache.lastUpdate < PUSH_CACHE_TTL) {
        return gameStateCache;
    }

    const team = GetTeam();
    const enemyTeam = GetOpposingTeam();
    const currentTime = DotaTime();
    const gameMode = GetGameMode();

    // Adjust time for turbo mode
    const adjustedTime = gameMode === 23 ? currentTime * 2 : currentTime;

    gameStateCache = {
        lastUpdate: now,
        currentTime: adjustedTime,
        gameMode,
        team,
        enemyTeam,
        ourAncient: GetAncient(team),
        enemyAncient: GetAncient(enemyTeam),
        aliveAllyCount: jmz.GetNumOfAliveHeroes(false),
        aliveEnemyCount: jmz.GetNumOfAliveHeroes(true),
        aliveAllyCoreCount: jmz.GetAliveCoreCount(false),
        aliveEnemyCoreCount: jmz.GetAliveCoreCount(true),
        teamNetworth: jmz.GetInventoryNetworth()[0],
        enemyNetworth: jmz.GetInventoryNetworth()[1],
        averageLevel: jmz.GetAverageLevel(false),
        hasAegis: jmz.DoesTeamHaveAegis(),
        isEarlyGame: jmz.IsEarlyGame(),
        isMidGame: jmz.IsMidGame(),
        isLateGame: jmz.IsLateGame(),
        isLaningPhase: jmz.IsInLaningPhase(),
    };

    return gameStateCache;
}

/** Update location state cache if needed */
function updateLocationStateCache(): CachedLocationState {
    const now = DotaTime();
    if (locationStateCache && now - locationStateCache.lastUpdate < PUSH_CACHE_TTL) {
        return locationStateCache;
    }

    const team = GetTeam();
    locationStateCache = {
        lastUpdate: now,
        laneFronts: {
            [Lane.Top]: GetLaneFrontLocation(team, Lane.Top, 0),
            [Lane.Mid]: GetLaneFrontLocation(team, Lane.Mid, 0),
            [Lane.Bot]: GetLaneFrontLocation(team, Lane.Bot, 0),
        },
        teamFountain: jmz.GetTeamFountain(),
        enemyFountain: jmz.GetTeamFountain(), // Note: GetEnemyFountain doesn't exist, using GetTeamFountain as fallback
        roshanLocation: jmz.GetCurrentRoshanLocation(),
        tormentorLocation: jmz.GetTormentorLocation(team),
        tormentorWaitingLocation: jmz.GetTormentorWaitingLocation(team),
    };

    return locationStateCache;
}

/** Update unit state cache if needed */
function updateUnitStateCache(): CachedUnitState {
    const now = DotaTime();
    if (unitStateCache && now - unitStateCache.lastUpdate < PUSH_CACHE_TTL) {
        return unitStateCache;
    }

    unitStateCache = {
        lastUpdate: now,
        enemyBuildings: GetUnitList(UnitType.EnemyBuildings),
        alliedHeroes: GetUnitList(UnitType.AlliedHeroes),
        enemyHeroes: GetUnitList(UnitType.Enemies).filter(u => jmz.IsValidHero(u)),
        alliedCreeps: GetUnitList(UnitType.AlliedCreeps),
        enemyCreeps: GetUnitList(UnitType.Enemies).filter(u => u.IsCreep() || u.IsAncientCreep()),
    };

    return unitStateCache;
}

/** Update bot state cache if needed */
function updateBotStateCache(bot: Unit, targetLoc?: Vector): CachedBotState {
    const now = DotaTime();
    const botId = bot.GetPlayerID();
    const cached = botStateCache[botId];

    if (cached && now - cached.lastUpdate < BOT_CACHE_TTL) {
        return cached;
    }

    const location = bot.GetLocation();
    const attackRange = bot.GetAttackRange();
    const gameState = updateGameStateCache();

    botStateCache[botId] = {
        lastUpdate: now,
        botId,
        attackRange,
        location,
        hp: jmz.GetHP(bot),
        mp: jmz.GetMP(bot),
        nearbyTowers: bot.GetNearbyTowers(1200, true),
        nearbyLaneCreeps: bot.GetNearbyLaneCreeps(1200, false),
        nearbyCreeps: bot.GetNearbyCreeps(1600, true),
        attackTarget: bot.GetAttackTarget(),
        distanceToAncient: gameState.enemyAncient ? GetUnitToUnitDistance(bot, gameState.enemyAncient) : Number.POSITIVE_INFINITY,
        distanceToTargetLoc: targetLoc ? GetUnitToLocationDistance(bot, targetLoc) : 0,
    };

    return botStateCache[botId];
}

/**
 * === Objective selection stability (anti-thrash) ===
 * (kept from Lua; comments preserved)
 */
const OBJECTIVE_STICKY_TIME = 1.2; // seconds to keep current target before reconsidering
const SWITCH_SCORE_MARGIN = 0.25; // how much better (lower) the new score must be to switch
const OBJECTIVE_LEASH_RANGE = 2600; // max distance from bot to consider high-ground objectives

// Barracks ≈ 200 from T3, T4 ≈ 800 from barracks; favor inner-ring first
// Lower score is better. Priority: Barracks (melee>ranged) < T3 < T4 < Fillers
const SCORE_BARRACKS_MELEE = 0;
const SCORE_BARRACKS_RANGED = 0.1;
const SCORE_T3 = 0.5;
const SCORE_T4 = 1.8;
// const SCORE_FILLER = 1.9;

const BASE_ANC_RADIUS = 2200;

/**
 * Add per-bot, per-lane objective memory
 * Example: ObjectiveState[playerID][lane] = { target=hUnit, lockUntil=GameTime() }
 */
type LaneState = { target?: Unit | null; lockUntil?: number };
const ObjectiveState: Record<number, Partial<Record<Lane, LaneState>>> = {};

/* -----------------------------------------------------------------------------
 * Desire front-door
 * ---------------------------------------------------------------------------*/
export function GetPushDesire(bot: Unit, lane: Lane): BotModeDesire {
    // 0) quick invalid checks
    if (bot.IsInvulnerable() || !bot.IsHero() || !bot.IsAlive() || !bot.GetUnitName().includes("hero") || bot.IsIllusion()) {
        return BotModeDesire.None;
    }

    if (bot.GetLevel() < 3) {
        return BotModeDesire.None;
    }

    // 1) very small cache by bot+lane for stability
    // const cacheKey = `PushDesire:${bot.GetPlayerID()}:${lane ?? -1}`;
    // const cachedVar = jmz.Utils.GetCachedVars(cacheKey, 0.6);
    // if (cachedVar != null) {
    //     (bot as any).pushDesire = cachedVar;
    //     return cachedVar;
    // }

    // 2) compute and publish
    const res = GetPushDesireHelper(bot, lane);
    // jmz.Utils.SetCachedVars(cacheKey, res);
    (bot as any).pushDesire = res;
    return res;
}

/* -----------------------------------------------------------------------------
 * Desire core
 * ---------------------------------------------------------------------------*/
export function GetPushDesireHelper(bot: Unit, lane: Lane): BotModeDesire {
    const gameState = getGlobalGameState();
    const ourAncient = gameState.ourAncient;
    if (!ourAncient) return BotModeDesire.None;
    const [baseResponder, criticalBaseCreeps] = GetBaseCreepResponse(bot, ourAncient);
    if (baseResponder) return BotModeDesire.None;

    // Keep the intent: avoid pushing too early or when other team jobs override.
    if ((bot as any).laneToPush == null) (bot as any).laneToPush = lane;

    // Update global caches
    autoCleanupCache();
    const locationState = getGlobalLocationState();
    // const unitState = updateUnitStateCache(); // Not used in this function

    let nMaxDesire = 0.82;
    const botActiveMode = bot.GetActiveMode();
    const nModeDesire = bot.GetActiveModeDesire();
    const bMyLane = bot.GetAssignedLane() === lane;
    const isMidOrEarlyGame = gameState.isEarlyGame || gameState.isMidGame;

    hEnemyAncient = gameState.enemyAncient;

    // Current, LOCAL threat picture around the bot (not reused across Think)
    const alliesHere = getCachedAlliesNearLoc(bot.GetLocation(), 1600);
    const enemiesHere = getCachedEnemiesNearLoc(bot.GetLocation(), 1600);

    // --- Strong base-defense gate for push ---
    const team = gameState.team;
    const teamAncientLoc = ourAncient.GetLocation();
    const enemiesAtAncient = jmz.Utils.CountEnemyHeroesNear(teamAncientLoc, BASE_ANC_RADIUS);
    // If Ancient under direct pressure → strongly deprioritize pushes
    if (enemiesAtAncient >= 1) return BotModeDesire.ExtraLow;
    if (((bot as any).ohaOuterTowerHoldUntil ?? 0) > DotaTime()) return BotModeDesire.None;
    const tradeLane = !criticalBaseCreeps && GetPreferredCounterPushLane(bot, gameState.enemyTeam);
    if (tradeLane) {
        if (tradeLane !== lane) return BotModeDesire.VeryLow;
        (bot as any).ohaPostFightPushLane = undefined;
        (bot as any).ohaOuterTowerPush = undefined;
        (bot as any).ohaCounterPushLane = lane;
        (bot as any).laneToPush = lane;
        return 0.82 as BotModeDesire;
    }
    const nEffAlliesNearAncient = jmz.GetAlliesNearLoc(teamAncientLoc, 4500).length
        + jmz.Utils.GetAllyIdsInTpToLocation(teamAncientLoc, 4500).length;
    const baseDefenseLimited = jmz.GetEnemiesAroundLoc(teamAncientLoc, 4500) > 0 && nEffAlliesNearAncient < 1;
    const activeDefense = jmz.IsDefending(bot) && nModeDesire >= 0.8;
    const currentTime = gameState.currentTime;
    const [nH] = jmz.Utils.NumHumanBotPlayersInTeam(GetOpposingTeam());
    const outsideCoreLane = !bMyLane && jmz.IsCore(bot) && gameState.isLaningPhase;
    const states = (jmz.Utils as any).GameStates ||= {};
    states.defendPings ||= { pingedTime: GameTime() };
    const recentDefendPing = GameTime() - states.defendPings.pingedTime <= 5;
    if (!outsideCoreLane && !recentDefendPing && !criticalBaseCreeps && !baseDefenseLimited
        && !(hEnemyAncient && CanFinishAncient(bot, hEnemyAncient))) {
        const plan = GetPostFightPushPlan(gameState);
        if (plan && plan.ready[bot.GetPlayerID()]) {
            if (plan.lane !== lane) return BotModeDesire.VeryLow;
            const waitingForDamage = plan.highGround && hEnemyAncient && !HasHighGroundCover(bot, hEnemyAncient, lane);
            if (waitingForDamage) {
                const point = bot.GetLocation();
                const direction = team === Team.Radiant ? 1 : -1;
                const advanced = (GetAmountAlongLane(lane, point).amount - GetAmountAlongLane(lane, plan.staging).amount) * direction;
                if (advanced > 0.025 || GetHeightLevel(plan.staging) > GetHeightLevel(point)) return BotModeDesire.VeryLow;
            }
            (bot as any).ohaPostFightPushLane = lane;
            (bot as any).ohaCounterPushLane = undefined;
            (bot as any).ohaOuterTowerPush = undefined;
            (bot as any).laneToPush = lane;
            if ("waveTarget" in plan) return 0.84 as BotModeDesire;
            if (waitingForDamage) return 0.76 as BotModeDesire;
            return 0.88 as BotModeDesire;
        }
    }
    const earlyMidChip = lane === Lane.Mid && currentTime >= 240 && currentTime <= 780
        && bot.GetAssignedLane() === Lane.Mid && bot.GetAttackRange() >= 550;
    if ((earlyMidChip || nH === 0 || currentTime > StartToPushTime) && !outsideCoreLane && !recentDefendPing
        && !criticalBaseCreeps && !baseDefenseLimited && !activeDefense) {
        const opportunity = GetOuterTowerOpportunity(bot, lane, gameState);
        if (opportunity && (opportunity.earlyMidChip || nH === 0 || currentTime > StartToPushTime)) {
            const tower = opportunity.tower;
            (bot as any).ohaOuterTowerPush = { lane, tower, earlyMidChip: opportunity.earlyMidChip };
            (bot as any).laneToPush = lane;
            return (GetUnitToUnitDistance(bot, tower) <= 1600 ? 0.8 : 0.76) as BotModeDesire;
        }
    }
    if (hEnemyAncient && !HasHighGroundCover(bot, hEnemyAncient, lane)) return BotModeDesire.VeryLow;
    // Use observed hero counts only. Enemy buybacks/cooldowns are not known.
    const decisivePushWindow = gameState.currentTime >= StartToPushTime
        && gameState.aliveEnemyCount <= 2
        && gameState.aliveAllyCount >= 3
        && gameState.aliveAllyCoreCount >= 1
        && gameState.aliveAllyCount >= gameState.aliveEnemyCount + 2
        && jmz.GetHP(bot) >= 0.6
        && enemiesHere.length === 0
        && !activeDefense && !baseDefenseLimited && !criticalBaseCreeps;

    // --- Push safety gates ---
    // Never push alone when 3+ enemies alive
    if (alliesHere.length <= 1 && gameState.aliveEnemyCount >= 3) {
        return BotModeDesire.None;
    }
    // Never push with 2+ hero count disadvantage
    if (gameState.aliveAllyCount <= gameState.aliveEnemyCount - 2) {
        return BotModeDesire.None;
    }
    // Don't push deep (past T2 toward enemy base) when alone or outnumbered
    const enemyFountain = gameState.team === Team.Radiant ? DireFountainTpPoint : RadiantFountainTpPoint;
    const laneFront = GetLaneFrontLocation(gameState.team, lane, 0);
    // Going to regroup is different from committing alone at high ground.
    const safeClosingWindow = decisivePushWindow
        && (GetUnitToLocationDistance(bot, enemyFountain) >= 3200
            || alliesHere.length >= 2 || bot.GetNearbyLaneCreeps(1100, false).length >= 2);
    if (safeClosingWindow) nMaxDesire = 0.88;
    if (GetLocationToLocationDistance(laneFront, enemyFountain) < 5000) {
        if ((!safeClosingWindow && alliesHere.length < 3) || gameState.aliveAllyCount < gameState.aliveEnemyCount) {
            nMaxDesire = math.min(nMaxDesire, 0.08);
        }
    }
    // Reduce desire when low HP
    if (jmz.GetHP(bot) < 0.5) {
        nMaxDesire = math.min(nMaxDesire, 0.25);
    }
    // Caution when all enemies alive and no advantage
    if (gameState.aliveEnemyCount >= 5 && gameState.aliveAllyCount <= gameState.aliveEnemyCount) {
        nMaxDesire = math.min(nMaxDesire, 0.41);
    }
    // Cap push desire when enemy heroes are very close — bot should fight, not push
    const closeEnemies = getCachedEnemiesNearLoc(bot.GetLocation(), 900);
    if (closeEnemies.length > 0 && alliesHere.length >= closeEnemies.length) {
        nMaxDesire = math.min(nMaxDesire, 0.3);
    }

    // Sync lane selection with hard bot modes
    if (botActiveMode === BotMode.PushTowerTop) {
        (bot as any).laneToPush = Lane.Top;
    } else if (botActiveMode === BotMode.PushTowerMid) {
        (bot as any).laneToPush = Lane.Mid;
    } else if (botActiveMode === BotMode.PushTowerBot) {
        (bot as any).laneToPush = Lane.Bot;
    }

    // Ignore push if someone just pinged "defend" recently
    if (recentDefendPing) {
        return BotModeDesire.None;
    }

    // Early laning rules & neutral objectives that override pushing
    if (
        outsideCoreLane ||
        jmz.IsDoingRoshan(bot) || jmz.IsDoingTormentor(bot)
    ) {
        return BOT_MODE_DESIRE_EXTRA_LOW as BotModeDesire;
    }

    // Limit ordinary pushes while a teammate is still very low level.
    for (let i = 1; i <= GetTeamPlayers(team).length; i++) {
        const member = GetTeamMember(i);
        if (member !== null && member.GetLevel() < 6) {
            return BotModeDesire.None;
        }
    }

    // Human opponents → delay high-commit pushes before a certain time
    if (nH > 0 && currentTime <= StartToPushTime) {
        return BOT_MODE_DESIRE_EXTRA_LOW as BotModeDesire;
    }

    // If we are actively defending, cap the max desire slightly lower
    if (activeDefense) {
        nMaxDesire = math.min(nMaxDesire, 0.75);
    }

    // Respect allied "attack here" human ping on a tower if it matches lane
    const [human, humanPing] = jmz.GetHumanPing();
    if (!criticalBaseCreeps && human !== null && humanPing !== null && !humanPing.normal_ping && DotaTime() > 0) {
        const [isPinged, pingedLane] = jmz.IsPingCloseToValidTower(GetOpposingTeam(), humanPing, 700, 5.0);
        if (isPinged && lane === pingedLane && GameTime() < humanPing.time + pingTimeDelta) {
            return 0.9 as BotModeDesire;
        }
    }

    // If we're off doing Tormentor far from enemy ancient, lower desire
    if (hEnemyAncient && hEnemyAncient !== null) {
        if (jmz.IsDoingTormentor(bot) && GetUnitToUnitDistance(bot, hEnemyAncient) > 4000) {
            return BOT_MODE_DESIRE_EXTRA_LOW as BotModeDesire;
        }
    }

    // Team state snapshot (used for several gates below) - using cached values
    const aAliveCount = gameState.aliveAllyCount;
    const eAliveCount = gameState.aliveEnemyCount;
    const aAliveCoreCount = gameState.aliveAllyCoreCount;
    const eAliveCoreCount = gameState.aliveEnemyCoreCount;

    // Base push desire calculation - missing function implementation
    let nPushDesire = 0.5; // Default base desire
    //   const allyKills = jmz.GetNumOfTeamTotalKills(false) + 1;
    //   const enemyKills = jmz.GetNumOfTeamTotalKills(true) + 1;
    //   const teamKillsRatio = allyKills / enemyKills; // (not used later but retained)

    // If enemies are at our ancient and we have few allies nearby → cap desire
    if (baseDefenseLimited) {
        nMaxDesire = math.min(nMaxDesire, 0.65);
    }

    // Enhanced local threat assessment - consider team advantages
    const networthAdvantage = gameState.teamNetworth - gameState.enemyNetworth;
    const enemyAverageLevel = jmz.GetAverageLevel(true);
    const levelAdvantage = gameState.averageLevel - enemyAverageLevel;
    const hasSignificantAdvantage = networthAdvantage > 15000 || levelAdvantage > 2;

    // If outnumbered in *local* area, desire is very low (avoid feed)
    // But be more lenient when team has significant advantages
    if (alliesHere.length < enemiesHere.length && alliesHere.length <= eAliveCount - 1 && aAliveCount < eAliveCount) {
        if (hasSignificantAdvantage && alliesHere.length >= enemiesHere.length - 1) {
            // Allow pushing when team has big advantage even if slightly outnumbered locally
            nMaxDesire = Math.min(nMaxDesire, 0.6); // Reduce but don't eliminate
        } else {
            return BotModeDesire.VeryLow;
        }
    }

    // If critical items/spells are cooling down near the push location → be cautious
    const vEnemyLaneFrontLocation = GetLaneFrontLocation(gameState.enemyTeam, lane, 0);
    const waitForSpells = ShouldWaitForImportantItemsSpells(vEnemyLaneFrontLocation);
    if (waitForSpells && eAliveCount >= aAliveCount && eAliveCoreCount >= aAliveCoreCount) {
        nMaxDesire = Math.min(nMaxDesire, 0.5);
    }

    // If already targeting a building that is backdoored, kill desire immediately
    const botTarget = bot.GetAttackTarget();
    if (jmz.IsValidBuilding(botTarget) && !botTarget!.GetUnitName().includes("tower1") && !botTarget!.GetUnitName().includes("tower2")) {
        if (HasBackdoorProtect(botTarget!)) {
            return BOT_MODE_DESIRE_EXTRA_LOW as BotModeDesire;
        }
    }

    const pushLane = WhichLaneToPush(bot, lane);
    const isCurrentLanePushLane = pushLane === lane;
    if (decisivePushWindow && !isCurrentLanePushLane) return BotModeDesire.VeryLow;

    // Score a finish here; issue attack orders only from the active Think.
    if (
        !criticalBaseCreeps && !baseDefenseLimited && !activeDefense
        && (!decisivePushWindow || safeClosingWindow) && hEnemyAncient && CanFinishAncient(bot, hEnemyAncient) &&
        !bot.WasRecentlyDamagedByAnyHero(1) &&
        jmz.GetHP(bot) > 0.5
    ) {
        return RemapValClamped(jmz.GetHP(bot), 0, 0.5, BotModeDesire.None, 0.98) as BotModeDesire;
    }

    // Enhanced group push logic - more aggressive when team has advantages
    if ((!jmz.IsCore(bot) && isCurrentLanePushLane) || (jmz.IsCore(bot) && ((jmz.IsLateGame() && isCurrentLanePushLane) || isMidOrEarlyGame))) {
        // More flexible conditions for allowing pushes when team has advantages

        // Allow pushes more easily when we have significant advantages
        const allowNumbers =
            eAliveCount === 0 ||
            aAliveCoreCount >= eAliveCoreCount ||
            (aAliveCoreCount >= 1 && aAliveCount >= eAliveCount + 2) ||
            // New: Allow pushes with networth advantage even if slightly outnumbered
            (networthAdvantage > 8000 && aAliveCount >= eAliveCount - 1) ||
            // New: Allow pushes with level advantage
            (levelAdvantage > 2 && aAliveCount >= eAliveCount - 1);

        if (allowNumbers) {
            // Aegis bonus
            if (gameState.hasAegis) {
                nPushDesire = nPushDesire + 0.3;
            }

            // Enhanced networth advantage calculation - more aggressive scaling
            if (aAliveCount >= eAliveCount - 1) {
                // Allow even when slightly outnumbered
                const networthBonus = RemapValClamped(networthAdvantage, 3000, 20000, 0.0, 1.5);
                nPushDesire = nPushDesire + networthBonus;
            }

            // New: Level advantage bonus
            if (levelAdvantage > 0) {
                const levelBonus = RemapValClamped(levelAdvantage, 0, 8, 0.0, 0.8);
                nPushDesire = nPushDesire + levelBonus;
            }

            // New: Group size advantage bonus
            if (aAliveCount > eAliveCount) {
                const groupBonus = RemapValClamped(aAliveCount - eAliveCount, 1, 3, 0.1, 0.4);
                nPushDesire = nPushDesire + groupBonus;
            }

            const desire = RemapValClamped(nPushDesire * jmz.GetHP(bot), 0, 1, 0, nMaxDesire);
            return (safeClosingWindow ? Math.min(nMaxDesire, Math.max(desire, 0.88)) : desire) as BotModeDesire;
        }
    }

    // Default: prefer mid as the soft fallback
    return lane === Lane.Mid ? BotModeDesire.VeryLow : (BOT_MODE_DESIRE_EXTRA_LOW as BotModeDesire);
}

/* -----------------------------------------------------------------------------
 * Lane selection helpers
 * ---------------------------------------------------------------------------*/

/** Ally presence should make a lane cheaper (more attractive) */
function presence_adjust(score: number, loc: Vector): number {
    const allies = jmz.GetAlliesNearLoc(loc, 1600).length;
    // pull toward lanes with allies; 0.25 is mild and safe
    return score / (1 + 0.25 * allies);
}

function UnitIsValidObjective(u: Unit | null): u is Unit {
    return !!u && jmz.IsValidBuilding(u) && jmz.CanBeAttacked(u) && !HasBackdoorProtect(u);
}

function GetFirstOuterTower(lane: Lane, enemyTeam: Team, isAvailable: (building: Unit | null) => boolean): Unit | undefined {
    const tierOne = lane === Lane.Top ? Tower.Top1 : lane === Lane.Mid ? Tower.Mid1 : Tower.Bot1;
    const tierTwo = lane === Lane.Top ? Tower.Top2 : lane === Lane.Mid ? Tower.Mid2 : Tower.Bot2;
    let tower = GetTower(enemyTeam, tierOne);
    if (!isAvailable(tower)) tower = GetTower(enemyTeam, tierTwo);
    return tower && isAvailable(tower) ? tower : undefined;
}

function GetOuterTowerTarget(bot: Unit, lane: Lane, enemyTeam: Team, maxDistance: number): Unit | undefined {
    const tower = GetFirstOuterTower(lane, enemyTeam, jmz.IsValidBuilding);
    if (!tower || !jmz.CanBeAttacked(tower)) return;
    const distance = GetUnitToUnitDistance(bot, tower);
    if (distance > maxDistance) return;

    const location = tower.GetLocation();
    if (!jmz.CanCommitToLaneTeleport(bot, location, true)) return;
    return tower;
}

type OuterTowerPlan = { tower: Unit; staging?: Vector; waveFront?: Vector; lane?: Lane; earlyMidChip?: boolean };

function GetLaneStaging(location: Vector, lane: Lane, offset: number): Vector | undefined {
    const amount = GetAmountAlongLane(lane, location).amount;
    const behind = Math.max(0, Math.min(1, amount + (GetTeam() === Team.Radiant ? -0.05 : 0.05)));
    const span = GetLocationToLocationDistance(GetLocationAlongLane(lane, amount), GetLocationAlongLane(lane, behind));
    if (span < 1) return;
    return GetLocationAlongLane(lane, Math.max(0, Math.min(1, amount + (behind - amount) * offset / span)));
}

function GetOuterWaveStaging(tower: Unit, lane: Lane): OuterTowerPlan | undefined {
    const location = tower.GetLocation();
    return getCachedData(`outerWaveStaging:${lane}:${location.x}:${location.y}`, 0.3, () => {
        const track = GetAmountAlongLane(lane, location).amount;
        const direction = GetTeam() === Team.Radiant ? 1 : -1;
        const wave: { point: Vector; distance: number }[] = [];
        for (const creep of GetUnitList(UnitType.AlliedCreeps)) {
            if (!jmz.IsValid(creep) || !(jmz.IsKeyWordUnit("npc_dota_creep_", creep) || jmz.IsKeyWordUnit("_siege", creep))) continue;
            const point = creep.GetLocation();
            const path = GetAmountAlongLane(lane, point);
            const distance = GetUnitToLocationDistance(creep, location);
            if (distance <= 5200 && path.distance <= 440 && (track - path.amount) * direction >= 0) wave.push({ point, distance });
        }
        wave.sort((a, b) => a.distance - b.distance);
        for (let i = 0; i < wave.length - 2; i++) {
            const front = wave[i];
            if (wave[i + 2].distance - front.distance > 800) continue;
            let staging = GetLaneStaging(front.point, lane, 325);
            if (staging && GetUnitToLocationDistance(tower, staging) < 900) staging = GetLaneStaging(location, lane, 950);
            if (staging && IsLocationPassable(staging)) return { tower, staging, waveFront: front.point, lane };
        }
        return undefined;
    });
}

function CanEscortOuterWave(bot: Unit, tower: Unit, lane: Lane, travel: number): boolean {
    const point = tower.GetLocation();
    const distance = GetUnitToUnitDistance(bot, tower);
    const remoteSupport = distance > 2200 && !jmz.IsCore(bot);
    if (remoteSupport && travel > 8) return false;
    let accounted = 0;
    for (const id of GetTeamPlayers(GetOpposingTeam())) {
        if (!IsHeroAlive(id)) { accounted++; continue; }
        const seen = GetHeroLastSeenInfo(id)?.[0];
        if (seen && seen.time_since_seen < 5 && jmz.GetLocationToLocationDistance(seen.location, point) > 3200 + travel * 160) accounted++;
    }
    if (accounted < (distance > 3000 || remoteSupport ? 4 : 2)) return false;
    const halfway = jmz.VectorTowards(bot.GetLocation(), point, distance / 2);
    if (!jmz.CanCommitToLaneTeleport(bot, halfway, true)) return false;
    // Only one hero needs to rotate. Allies already on the wave can still hit the tower.
    for (const ally of jmz.GetAlliesNearLoc(point, distance + 500)) {
        if (ally === bot || !jmz.IsValidHero(ally) || ally.IsIllusion() || jmz.GetHP(ally) < 0.6 || jmz.IsRetreating(ally)
            || ally.HasModifier("modifier_teleporting") || ally.IsChanneling() || ally.IsDisarmed() || ally.WasRecentlyDamagedByAnyHero(2) || ally.WasRecentlyDamagedByTower(2)
            || jmz.IsDoingRoshan(ally) || jmz.IsDoingTormentor(ally) || ((ally as any).ohaOuterTowerHoldUntil ?? 0) > DotaTime()
            || (jmz.IsInLaningPhase(ally) && jmz.IsCore(ally) && ally.GetAssignedLane() !== lane)) continue;
        const gap = GetUnitToUnitDistance(ally, tower);
        const eta = Math.max(0, gap - ally.GetAttackRange()) / Math.max(1, ally.GetCurrentMovementSpeed());
        if ((gap <= 2200 || jmz.IsCore(ally) || (accounted >= 4 && eta <= 8))
            && (eta < travel || (eta === travel && ally.GetPlayerID() < bot.GetPlayerID()))
            && jmz.GetEnemiesNearLoc(ally.GetLocation(), 1400).length === 0
            && jmz.CanCommitToLaneTeleport(ally, jmz.VectorTowards(ally.GetLocation(), point, gap / 2), true)) return false;
    }
    return true;
}

function GetEarlyMidTowerChip(bot: Unit, lane: Lane, gameState: ReturnType<typeof getGlobalGameState>): OuterTowerPlan | undefined {
    const now = gameState.currentTime;
    if (lane !== Lane.Mid || now < 240 || now > 960 || bot.GetAssignedLane() !== Lane.Mid
        || bot.GetAttackRange() < 550 || !jmz.IsCore(bot) || jmz.GetHP(bot) < 0.65 || bot.IsDisarmed()
        || jmz.IsRetreating(bot) || bot.WasRecentlyDamagedByAnyHero(2) || bot.WasRecentlyDamagedByTower(2)) return;
    const tower = GetTower(gameState.enemyTeam, Tower.Mid1);
    if (!tower || !jmz.IsValidBuilding(tower) || !tower.CanBeSeen()
        || tower.HasModifier("modifier_fountain_glyph") || HasBackdoorProtect(tower)
        || ((bot as any).ohaLaningAttackTarget && jmz.HasPendingLaningLastHit(bot))) return;
    const gap = GetUnitToUnitDistance(bot, tower) - bot.GetAttackRange();
    if (gap > 260 || (now > 780 && gap > 0)) return;
    const tank = tower.GetAttackTarget();
    if (!tank || !jmz.IsValid(tank) || tank.GetTeam() !== bot.GetTeam() || !jmz.IsKeyWordUnit("npc_dota_creep_", tank)
        || tank.GetHealth() <= Math.max(100, tower.GetAttackDamage())) return;
    let count = 0;
    let siege = false;
    for (const creep of bot.GetNearbyLaneCreeps(1400, false)) {
        if (jmz.IsValid(creep) && jmz.IsInRange(creep, tower, 850)) {
            count++;
            siege = siege || jmz.IsKeyWordUnit("_siege", creep);
        }
    }
    if (count < 2 || jmz.GetLastSeenEnemiesNearLoc(tower.GetLocation(), 1200).length > 1) return;
    for (const enemy of jmz.GetEnemiesNearLoc(tower.GetLocation(), 1650)) {
        if (jmz.IsInRange(bot, enemy, Math.max(725, enemy.GetAttackRange() + 150))) return;
    }
    if (gap > 0) {
        if (!siege || tank.GetHealth() <= 2 * Math.max(100, tower.GetAttackDamage())
            || bot.GetNearbyLaneCreeps(1000, true).length > 0) return;
        const origin = bot.GetLocation();
        const staging = jmz.VectorTowards(origin, tower.GetLocation(), gap + 25);
        const halfway = jmz.VectorTowards(origin, tower.GetLocation(), (gap + 25) / 2);
        if (!IsLocationPassable(staging) || !IsLocationVisible(staging)
            || !jmz.CanCommitToLaneTeleport(bot, tower.GetLocation(), true, 1650)
            || !jmz.CanCommitToLaneTeleport(bot, staging, true, 1400)
            || !jmz.CanCommitToLaneTeleport(bot, halfway, true, 1200)) return;
        return { tower, staging, earlyMidChip: true };
    }
    return { tower, earlyMidChip: true };
}

function GetOuterTowerOpportunity(bot: Unit, lane: Lane, gameState: ReturnType<typeof getGlobalGameState>): OuterTowerPlan | undefined {
    const chip = GetEarlyMidTowerChip(bot, lane, gameState);
    if (chip) return chip;
    if (jmz.GetHP(bot) < 0.6 || jmz.IsRetreating(bot) || jmz.IsDoingTormentor(bot) || jmz.IsDoingRoshan(bot)
        || bot.IsDisarmed() || bot.WasRecentlyDamagedByTower(2) || bot.WasRecentlyDamagedByAnyHero(2)
        || jmz.GetEnemiesNearLoc(bot.GetLocation(), 1400).length > 0) return;
    const tower = GetOuterTowerTarget(bot, lane, gameState.enemyTeam, 6500);
    if (!tower || tower.GetAttackTarget() === bot || jmz.GetLastSeenEnemiesNearLoc(tower.GetLocation(), 1700).length > 0) return;
    const [wave, eta, thirdETA, siegeETA, attacking] = jmz.GetLaneWaveAtBuilding(tower, lane);
    const tank = tower.GetAttackTarget();
    const distance = GetUnitToUnitDistance(bot, tower);
    const travel = Math.max(0, distance - bot.GetAttackRange()) / Math.max(1, bot.GetCurrentMovementSpeed());
    if (wave < 2 && eta > 7) {
        if (DotaTime() < 12 * 60) return;
        const preparation = GetOuterWaveStaging(tower, lane);
        if (!preparation?.staging || GetUnitToLocationDistance(bot, preparation.staging) > 2200
            || !jmz.CanCommitToLaneTeleport(bot, preparation.staging, true)) return;
        // Open the lane from our side while an ally can cover the shoving hero.
        const friendly = GetFirstOuterTower(lane, bot.GetTeam(), jmz.IsValidBuilding);
        if (friendly && GetUnitToLocationDistance(friendly, preparation.staging) <= 1500
            && jmz.GetAvailableFightAllies(bot, preparation.staging, 1450) >= 1) return preparation;
        if (distance <= 4500 && CanEscortOuterWave(bot, tower, lane, travel)) return preparation;
        return;
    }
    const covered = tank ? jmz.IsValid(tank) && tank.IsCreep() && tank.GetTeam() === bot.GetTeam() : attacking >= 2;
    const protectedTower = HasBackdoorProtect(tower);
    if (!protectedTower && covered && wave >= 2 && travel <= (wave >= 3 ? 3.5 : 1.8)) return { tower };

    const postFight = DotaTime() >= 8 * 60 && gameState.aliveAllyCount > gameState.aliveEnemyCount && gameState.aliveAllyCoreCount >= 1;
    const canApproach = gameState.aliveAllyCount >= 3 && gameState.aliveEnemyCount <= 2;
    if (postFight && distance <= (canApproach ? 3000 : 1600)
        && (jmz.GetAvailableFightAllies(bot, tower.GetLocation(), 1600) >= 1
            || (distance > 1600 && jmz.GetAvailableFightAllies(bot, bot.GetLocation(), 1600) >= 1))
        && (jmz.CanFinishOuterTowerInWindow(bot, tower, lane, gameState.reinforcementWindow)
            || (gameState.reinforcementWindow >= 5 && wave >= 2 && distance <= bot.GetAttackRange() + 150))) {
        if (!protectedTower && wave >= 2 && distance <= 1600) return { tower };
        const staging = GetLaneStaging(tower.GetLocation(), lane, 950);
        if (staging && IsLocationPassable(staging) && jmz.CanCommitToLaneTeleport(bot, staging, true)) return { tower, staging };
    }
    if (thirdETA > 7 || travel > thirdETA + (siegeETA <= 7 || wave >= 5 ? 16 : 7)
        || !CanEscortOuterWave(bot, tower, lane, travel)) return;
    const staging = GetLaneStaging(tower.GetLocation(), lane, 950 + thirdETA * 325);
    if (staging && IsLocationPassable(staging) && jmz.CanCommitToLaneTeleport(bot, staging, true)) return { tower, staging };
}

function GetCounterPushTarget(bot: Unit, lane: Lane, enemyTeam: Team): OuterTowerPlan | undefined {
    const trade = (bot as any).ohaOuterTowerTrade;
    if (!trade || trade.lane === lane || trade.expires <= DotaTime() || DotaTime() < 8 * 60
        || jmz.GetHP(bot) < 0.6 || jmz.IsRetreating(bot) || bot.WasRecentlyDamagedByAnyHero(2)
        || bot.WasRecentlyDamagedByTower(2) || bot.IsDisarmed() || bot.IsChanneling()
        || jmz.IsDoingRoshan(bot) || jmz.IsDoingTormentor(bot)) return;
    const visiblePushers = jmz.GetEnemiesNearLoc(trade.location, 2250).length;
    const support = !jmz.IsCore(bot);
    if (visiblePushers < (support ? 4 : 3)) return;
    const tower = GetOuterTowerTarget(bot, lane, enemyTeam, visiblePushers >= 4 ? 6100 : 3600);
    if (!tower || tower.GetAttackTarget() === bot || GetUnitToLocationDistance(tower, trade.location) < 3200) return;
    const [wave, , thirdETA] = jmz.GetLaneWaveAtBuilding(tower, lane);
    const distance = GetUnitToUnitDistance(bot, tower);
    if (jmz.GetEnemiesNearLoc(bot.GetLocation(), 1500).length > 0) return;
    const travel = Math.max(0, distance - bot.GetAttackRange()) / Math.max(1, bot.GetCurrentMovementSpeed());
    if (support && distance > 1600 && !CanEscortOuterWave(bot, tower, lane, travel)) return;
    if (wave < 3 && (visiblePushers < 4 || thirdETA > 6)) {
        const preparation = GetOuterWaveStaging(tower, lane);
        if (!preparation?.staging || GetUnitToLocationDistance(bot, preparation.staging) > (support ? 1700 : 2500)
            || !jmz.CanCommitToLaneTeleport(bot, preparation.staging, true)) return;
        const halfway = jmz.VectorTowards(bot.GetLocation(), preparation.staging, GetUnitToLocationDistance(bot, preparation.staging) / 2);
        if (!jmz.CanCommitToLaneTeleport(bot, halfway, true)) return;
        return preparation;
    }
    if (distance > 1600 || wave < 3 || HasBackdoorProtect(tower)) {
        const staging = GetLaneStaging(tower.GetLocation(), lane, 950 + thirdETA * 325);
        if (!staging || !IsLocationPassable(staging)
            || !jmz.CanCommitToLaneTeleport(bot, staging, true)) return;
        return { tower, staging };
    }
    return { tower };
}

function GetPreferredCounterPushLane(bot: Unit, enemyTeam: Team): Lane | undefined {
    const trade = (bot as any).ohaOuterTowerTrade;
    if (!trade || trade.expires <= DotaTime()) return;
    let best: Lane | undefined;
    let bestScore = Infinity;
    for (const lane of [Lane.Mid, Lane.Top, Lane.Bot]) {
        const plan = GetCounterPushTarget(bot, lane, enemyTeam);
        if (plan) {
            const toWave = plan.staging ? GetUnitToLocationDistance(bot, plan.staging) : 0;
            const score = toWave + GetUnitToUnitDistance(bot, plan.tower) * 0.5;
            if (score < bestScore) {
                best = lane;
                bestScore = score;
            }
        }
    }
    return best;
}

function IsStandingBuilding(building: Unit | null | undefined): building is Unit {
    return !!building && building.IsAlive();
}

function GetHighGroundObjective(lane: Lane, enemyTeam: Team): Unit | undefined {
    const tower = GetTower(enemyTeam, lane === Lane.Top ? Tower.Top3 : lane === Lane.Mid ? Tower.Mid3 : Tower.Bot3);
    const barracks = lane === Lane.Top ? Barracks.TopMelee : lane === Lane.Mid ? Barracks.MidMelee : Barracks.BotMelee;
    let building = tower && tower.IsAlive() ? tower : GetBarracks(enemyTeam, barracks);
    if (!building || !building.IsAlive()) {
        building = GetBarracks(enemyTeam, lane === Lane.Top ? Barracks.TopRanged : lane === Lane.Mid ? Barracks.MidRanged : Barracks.BotRanged);
    }
    return building && building.IsAlive() ? building : undefined;
}

type PostFightPushPlan = { lane: Lane; tower: Unit; staging: Vector; highGround: boolean; ready: Record<number, Unit>; waveFront: Vector };

type PostFightWavePlan = { lane: Lane; staging: Vector; waveTarget: Unit; ready: Record<number, Unit>; highGround?: false };
type PostFightPlan = PostFightPushPlan | PostFightWavePlan;

// Use a nearby, visible wave when no building can be reached together.
function GetPostFightWavePlan(gameState: ReturnType<typeof getGlobalGameState>, ready: Unit[], availableTime: number): PostFightWavePlan | false {
    if (availableTime < 6) return false;
    let best: PostFightWavePlan | false = false;
    let bestScore = Infinity;
    const direction = gameState.team === Team.Radiant ? 1 : -1;
    const enemies = GetUnitList(UnitType.EnemyCreeps);
    for (const lane of [Lane.Mid, Lane.Top, Lane.Bot]) {
        const tower = GetFirstOuterTower(lane, gameState.enemyTeam, IsStandingBuilding) || GetHighGroundObjective(lane, gameState.enemyTeam);
        for (const creep of enemies) {
            if (!jmz.IsValid(creep) || !jmz.CanBeAttacked(creep)) continue;
            const name = creep.GetUnitName();
            if (!name.includes("npc_dota_creep_") && !name.includes("_siege")) continue;
            const point = creep.GetLocation();
            const track = GetAmountAlongLane(lane, point);
            const staging = GetLaneStaging(point, lane, 360);
            const beforeTower = !tower || ((GetAmountAlongLane(lane, tower.GetLocation()).amount - track.amount) * direction > 0
                && GetUnitToLocationDistance(tower, point) > 1250);
            if (track.distance > 460 || !beforeTower
                || (gameState.enemyAncient && GetUnitToLocationDistance(gameState.enemyAncient, point) <= 3400)
                || !staging || !IsLocationPassable(staging)) continue;
            const candidates: { ally: Unit; eta: number }[] = [];
            for (const ally of ready) {
                const eta = GetUnitToLocationDistance(ally, staging) / Math.max(1, ally.GetCurrentMovementSpeed());
                if (eta <= Math.min(8, availableTime - 4) && !ally.IsRooted()
                    && !ally.WasRecentlyDamagedByAnyHero(2)
                    && GetHeightLevel(point) <= GetHeightLevel(ally.GetLocation())
                    && jmz.CanCommitToLaneTeleport(ally, point, true, 1200)
                    && jmz.CanCommitToLaneTeleport(ally, staging, true, 1000)) {
                    candidates.push({ ally, eta });
                }
            }
            for (let i = 0; i < candidates.length; i++) {
                for (let j = i + 1; j < candidates.length; j++) {
                    const [a, b] = [candidates[i], candidates[j]];
                    const [aId, bId] = [a.ally.GetPlayerID(), b.ally.GetPlayerID()];
                    const score = Math.max(a.eta, b.eta) + (a.eta + b.eta) * 0.15
                        + (aId + bId) * 0.0001 + Math.min(aId, bId) * 0.000001;
                    if (score < bestScore && (jmz.IsCore(a.ally) || jmz.IsCore(b.ally))) {
                        bestScore = score;
                        best = { lane, staging, waveTarget: creep, ready: { [aId]: a.ally, [bId]: b.ally } };
                    }
                }
            }
        }
    }
    return best;
}

function GetPostFightPushPlan(gameState: ReturnType<typeof getGlobalGameState>): PostFightPlan | false | undefined {
    if (gameState.currentTime < StartToPushTime || gameState.aliveEnemyCount > 3
        || gameState.aliveAllyCount < gameState.aliveEnemyCount + 2 || gameState.aliveAllyCoreCount === 0) return;
    return getCachedData<PostFightPlan | false>("postFightPushPlan", 0.35, () => {
        const ready: Record<number, Unit> = {};
        const [reserve] = jmz.GetExposedMidCover(gameState.team);
        for (let slot = 1; slot <= GetTeamPlayers(gameState.team).length; slot++) {
            const ally = GetTeamMember(slot);
            if (ally && ally !== reserve && jmz.IsValidHero(ally) && ally.IsBot() && !ally.IsIllusion() && jmz.GetHP(ally) >= 0.55
                && !jmz.IsRetreating(ally) && !ally.IsChanneling() && !ally.HasModifier("modifier_teleporting")
                && !ally.IsStunned() && !ally.IsHexed() && !ally.IsNightmared() && !ally.IsDisarmed()
                && !jmz.IsDoingRoshan(ally) && !jmz.IsDoingTormentor(ally)
                && ((ally as any).ohaOuterTowerHoldUntil ?? 0) <= DotaTime()
                && !(jmz.IsDefending(ally) && ally.GetActiveModeDesire() >= 0.8)) {
                const [baseResponder] = GetBaseCreepResponse(ally, gameState.ourAncient);
                if (!baseResponder) ready[ally.GetPlayerID()] = ally;
            }
        }
        const participants = Object.values(ready);
        if (participants.length < 2) return false;

        const creeps = GetUnitList(UnitType.AlliedCreeps);
        const direction = gameState.team === Team.Radiant ? 1 : -1;
        const availableTime = Math.max(0, gameState.reinforcementWindow - 1.5);
        let best: PostFightPushPlan | false = false;
        let bestTime = Infinity;
        for (const lane of [Lane.Mid, Lane.Top, Lane.Bot]) {
            const outer = GetFirstOuterTower(lane, gameState.enemyTeam, IsStandingBuilding);
            const highGround = !outer;
            const tower = outer || GetHighGroundObjective(lane, gameState.enemyTeam);
            if (!IsStandingBuilding(tower)) continue;
            const location = tower.GetLocation();
            const front = GetLaneFrontLocation(gameState.team, lane, 0);
            const targetProgress = GetAmountAlongLane(lane, location).amount * direction;
            let wave: Vector | undefined;
            let waveProgress = -Infinity;
            let firstCreepETA = Infinity;
            let secondCreepETA = Infinity;
            for (const creep of creeps) {
                if (!jmz.IsValid(creep) || GetUnitToLocationDistance(creep, front) > 1600) continue;
                const name = creep.GetUnitName();
                if (!name.includes("npc_dota_creep_") && !name.includes("_siege")) continue;
                const point = creep.GetLocation();
                const track = GetAmountAlongLane(lane, point);
                const progress = track.amount * direction;
                if (track.distance > 550 || progress > targetProgress + 0.04) continue;
                const eta = Math.max(0, GetUnitToLocationDistance(creep, location) - 775) / Math.max(1, creep.GetCurrentMovementSpeed());
                if (eta < firstCreepETA) { secondCreepETA = firstCreepETA; firstCreepETA = eta; }
                else if (eta < secondCreepETA) secondCreepETA = eta;
                if (progress > waveProgress) { wave = point; waveProgress = progress; }
            }
            if (!wave || secondCreepETA > availableTime) continue;
            const waveDistance = GetLocationToLocationDistance(wave, location);
            const staging = (waveDistance <= 1200 && GetLaneStaging(location, lane, 900)) || GetLaneStaging(wave, lane, 280);
            if (!staging || !IsLocationPassable(staging)) continue;
            let first = Infinity;
            let second = Infinity;
            let core = Infinity;
            const arriving: Record<number, Unit> = {};
            for (const ally of participants) {
                const reach = Math.max(0, GetUnitToUnitDistance(ally, tower) - ally.GetAttackRange());
                if (ally.IsRooted() && reach > 0) continue;
                const distance = reach === 0 ? 0 : Math.max(reach, GetUnitToLocationDistance(ally, staging));
                const eta = distance / Math.max(1, ally.GetCurrentMovementSpeed());
                if (eta <= availableTime) arriving[ally.GetPlayerID()] = ally;
                if (eta < first) { second = first; first = eta; }
                else if (eta < second) second = eta;
                if (jmz.IsCore(ally)) core = Math.min(core, eta);
            }
            // First creep or arrival at the staging point alone cannot start the siege.
            const arrival = Math.max(second, core, secondCreepETA);
            const time = arrival + (highGround ? 6 : 0)
                + jmz.GetLastSeenEnemiesNearLoc(location, 1600).length * 6;
            if (arrival <= availableTime && time < bestTime) {
                bestTime = time;
                best = { lane, tower, staging, highGround, ready: arriving, waveFront: wave };
            }
        }
        return best || GetPostFightWavePlan(gameState, participants, availableTime);
    });
}

function HasHighGroundCover(bot: Unit, ancient: Unit, lane: Lane): boolean {
    const enemyTeam = GetOpposingTeam();
    const objective = (!CanFinishAncient(bot, ancient) && GetHighGroundObjective(lane, enemyTeam)) || ancient;
    if (GetUnitToUnitDistance(bot, ancient) >= 3000) {
        if (GetUnitToUnitDistance(bot, objective) > 1900) return true;
        const outer = GetTower(enemyTeam, lane === Lane.Top ? Tower.Top2 : lane === Lane.Mid ? Tower.Mid2 : Tower.Bot2);
        if (outer && outer.IsAlive()) return true;
    }
    const location = bot.GetLocation();
    const allies = jmz.GetAvailableFightAllies(bot, location, 1600);
    const enemies = Math.max(jmz.GetEnemiesNearLoc(location, 1600).length,
        jmz.GetEnemiesNearLoc(ancient.GetLocation(), 1600).length, jmz.GetEnemiesNearLoc(objective.GetLocation(), 1600).length);
    if (allies < 1 || jmz.GetHP(bot) < 0.35 || enemies >= allies + 1
        || (enemies > 0 && !jmz.WeAreStronger(bot, 1800))) return false;
    if (enemies === 0 && allies >= 2 && jmz.GetNumOfAliveHeroes(true) <= 1
        && CanFinishAncient(bot, ancient) && jmz.GetHP(ancient) <= 0.35) return true;
    const [wave] = jmz.GetLaneWaveAtBuilding(objective, lane);
    return wave >= 2 && jmz.HasSiegeDamageInRange(bot, objective.GetLocation(), lane);
}

function CanFinishAncient(bot: Unit, ancient: Unit): boolean {
    return GetUnitToUnitDistance(bot, ancient) < 1000 && UnitIsValidObjective(ancient)
        && (GetAllyHeroesAttackingUnit(ancient).length >= 2 || GetAllyCreepsAttackingUnit(ancient).length >= 2
            || jmz.GetAvailableFightAllies(bot, ancient.GetLocation(), 1600) >= 2 || jmz.GetHP(ancient) <= 0.35);
}

function UnitIsBarracks(u: Unit): boolean {
    const n = u != null ? u.GetUnitName() : "";
    return n.includes("rax");
}
function UnitIsMeleeBarracks(u: Unit): boolean {
    return UnitIsBarracks(u) && !!u && u.GetUnitName().includes("melee");
}
function UnitIsRangedBarracks(u: Unit): boolean {
    return UnitIsBarracks(u) && !!u && u.GetUnitName().includes("ranged");
}
function UnitIsT3(u: Unit): boolean {
    return u === GetTower(GetOpposingTeam(), Tower.Top3) || u === GetTower(GetOpposingTeam(), Tower.Mid3) || u === GetTower(GetOpposingTeam(), Tower.Bot3);
}
function UnitIsT4(u: Unit): boolean {
    return (
        u === GetTower(GetOpposingTeam(), Tower.Base1) || u === GetTower(GetOpposingTeam(), Tower.Base2) || GetUnitToUnitDistance(u, GetAncient(GetOpposingTeam())) < 500
    );
}
// function UnitIsFiller(u: Unit): boolean {
//     // Fillers/other inner-base buildings, exclude barracks/towers
//     return jmz.IsValidBuilding(u) && !UnitIsBarracks(u) && !UnitIsT3(u) && !UnitIsT4(u);
// }

/**
 * Compute a score for an objective; lower is better.
 * Base priority + mild distance terms; prefer closer to the bot and to approach targetLoc.
 */
function ObjectiveScore(bot: Unit, u: Unit | null, targetLoc?: Vector | null): number {
    if (!UnitIsValidObjective(u)) return Number.POSITIVE_INFINITY;

    const base =
        (UnitIsMeleeBarracks(u) && SCORE_BARRACKS_MELEE) ||
        (UnitIsRangedBarracks(u) && SCORE_BARRACKS_RANGED) ||
        (UnitIsT3(u) && SCORE_T3) ||
        // (UnitIsFiller(u) && SCORE_FILLER) ||
        (UnitIsT4(u) && SCORE_T4) ||
        2.0; // anything unknown → worst

    const dBot = GetUnitToUnitDistance(bot, u);
    if (dBot > OBJECTIVE_LEASH_RANGE) return Number.POSITIVE_INFINITY;

    // Distance nudges (kept light so priority dominates)
    const d1 = dBot / 2000.0; // 0 .. ~1.3
    const d2 = targetLoc ? GetUnitToLocationDistance(u, targetLoc) / 2500.0 : 0;

    return base + 0.35 * d1 + 0.2 * d2;
}

/** Decide whether to keep current target or switch to a better one */
function SelectOrStickHGTarget(bot: Unit, lane: Lane, targetLoc?: Vector | null): Unit | null {
    const pid = bot.GetPlayerID();
    ObjectiveState[pid] = ObjectiveState[pid] || {};
    ObjectiveState[pid][lane] = ObjectiveState[pid][lane] || {};

    const state = ObjectiveState[pid][lane] as LaneState;
    const now = GameTime();
    const current = state.target || null;

    const currentScore = current ? ObjectiveScore(bot, current, targetLoc) : Number.POSITIVE_INFINITY;
    if (current && currentScore < Number.POSITIVE_INFINITY && now < (state.lockUntil ?? 0)) {
        return current;
    }

    // Scan candidates
    const unitState = updateUnitStateCache();
    let best: Unit | null = null;
    let bestScore = Number.POSITIVE_INFINITY;
    for (const b of unitState.enemyBuildings) {
        const sc = ObjectiveScore(bot, b, targetLoc);
        if (sc < bestScore) {
            best = b;
            bestScore = sc;
        }
    }

    // Only switch if clearly better
    if (current && currentScore < Number.POSITIVE_INFINITY) {
        if (best && bestScore + SWITCH_SCORE_MARGIN < currentScore) {
            state.target = best;
            state.lockUntil = now + OBJECTIVE_STICKY_TIME;
            return best;
        } else {
            state.lockUntil = now + 0.6;
            return current;
        }
    }

    // Adopt best if nothing valid
    if (best) {
        state.target = best;
        state.lockUntil = now + OBJECTIVE_STICKY_TIME;
        return best;
    }

    state.target = null;
    state.lockUntil = undefined;
    return null;
}

export function WhichLaneToPush(_bot: Unit, _lane: Lane): Lane {
    //   print("WhichLaneToPush for: ", bot.GetUnitName(), lane);

    // Update location cache
    const locationState = updateLocationStateCache();
    const gameState = updateGameStateCache();

    // Score smaller = better
    let topLaneScore = 0;
    let midLaneScore = 0;
    let botLaneScore = 0;

    const vTop = locationState.laneFronts[Lane.Top];
    const vMid = locationState.laneFronts[Lane.Mid];
    const vBot = locationState.laneFronts[Lane.Bot];

    // Prefer lanes closer to humans/cores; de-prioritize supports' solo pushes
    const teamMembers = GetUnitList(UnitType.AlliedHeroes);
    for (const member of teamMembers) {
        if (jmz.IsValidHero(member)) {
            let topDist = GetUnitToLocationDistance(member, vTop);
            let midDist = GetUnitToLocationDistance(member, vMid);
            let botDist = GetUnitToLocationDistance(member, vBot);

            if (jmz.IsCore(member) && member && !member.IsBot()) {
                topDist *= 0.2;
                midDist *= 0.2;
                botDist *= 0.2;
            } else if (!jmz.IsCore(member)) {
                topDist *= 1.5;
                midDist *= 1.5;
                botDist *= 1.5;
            }

            topLaneScore += topDist;
            midLaneScore += midDist;
            botLaneScore += botDist;
        }
    }

    // Enemy last seen / incoming TPs near their lane fronts → inflate that lane score
    let countTop = 0,
        countMid = 0,
        countBot = 0;

    for (const id of GetTeamPlayers(gameState.enemyTeam)) {
        if (IsHeroAlive(id)) {
            const info = GetHeroLastSeenInfo(id);
            if (info && info !== null) {
                const dInfo = info[0];
                if (dInfo && dInfo.time_since_seen < 5) {
                    if (jmz.GetLocationToLocationDistance(vTop, dInfo.location) <= 1600) countTop++;
                    else if (jmz.GetLocationToLocationDistance(vMid, dInfo.location) <= 1600) countMid++;
                    else if (jmz.GetLocationToLocationDistance(vBot, dInfo.location) <= 1600) countBot++;
                }
            }
        }
    }

    const hTeleports = GetIncomingTeleports();
    for (const tp of hTeleports) {
        if (tp && tp.location && IsLocationVisible(tp.location) && IsEnemyTP(tp.playerid)) {
            if (jmz.GetLocationToLocationDistance(vTop, tp.location) <= 1600) countTop++;
            else if (jmz.GetLocationToLocationDistance(vMid, tp.location) <= 1600) countMid++;
            else if (jmz.GetLocationToLocationDistance(vBot, tp.location) <= 1600) countBot++;
        }
    }

    topLaneScore *= 0.05 * countTop + 1;
    midLaneScore *= 0.05 * countMid + 1;
    botLaneScore *= 0.05 * countBot + 1;

    // Prefer lanes with lower-tier outer buildings first. Start mid slightly.
    const topTier = GetLaneBuildingTier(Lane.Top);
    const midTier = GetLaneBuildingTier(Lane.Mid);
    const botTier = GetLaneBuildingTier(Lane.Bot);

    if (Math.min(topTier, midTier, botTier) < 4) {
        if (topTier === 4) topLaneScore = Number.POSITIVE_INFINITY;
        if (midTier === 4) midLaneScore = Number.POSITIVE_INFINITY;
        if (botTier === 4) botLaneScore = Number.POSITIVE_INFINITY;
    }

    if (midTier < topTier && midTier < botTier) {
        midLaneScore *= 0.5;
        if (!jmz.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Mid)) midLaneScore *= 0.5;
    } else if (topTier < midTier && topTier < botTier) {
        topLaneScore *= 0.5;
        if (!jmz.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Top)) topLaneScore *= 0.5;
    } else if (botTier < topTier && botTier < midTier) {
        botLaneScore *= 0.5;
        if (!jmz.Utils.IsAnyBarracksOnLaneAlive(false, Lane.Bot)) botLaneScore *= 0.5;
    }

    // Pull toward lanes where allies already are
    topLaneScore = presence_adjust(topLaneScore, vTop);
    midLaneScore = presence_adjust(midLaneScore, vMid);
    botLaneScore = presence_adjust(botLaneScore, vBot);

    if (topLaneScore < midLaneScore && topLaneScore < botLaneScore) return Lane.Top;
    if (midLaneScore < topLaneScore && midLaneScore < botLaneScore) return Lane.Mid;
    if (botLaneScore < topLaneScore && botLaneScore < midLaneScore) return Lane.Bot;

    if (midLaneScore <= topLaneScore && midLaneScore <= botLaneScore) return Lane.Mid;
    return topLaneScore <= botLaneScore ? Lane.Top : Lane.Bot;
}

/* -----------------------------------------------------------------------------
 * Think loop
 * ---------------------------------------------------------------------------*/
let fNextMovementTime = 0;

export function CancelPushOrder(bot: Unit, lane?: Lane): void {
    if (lane !== undefined && (bot as any).ohaOuterTowerPush?.lane === lane) (bot as any).ohaOuterTowerPush = undefined;
    if (lane !== undefined && (bot as any).ohaPostFightPushLane === lane) (bot as any).ohaPostFightPushLane = undefined;
    if (lane !== undefined && (bot as any).ohaCounterPushLane === lane) (bot as any).ohaCounterPushLane = undefined;
    if (!(bot as any)._ohaIssuedPushOrder) return;
    if (!jmz.CanNotUseAction(bot)) bot.Action_ClearActions(true);
    (bot as any)._ohaIssuedPushOrder = false;
}

function RunOuterTowerPlan(bot: Unit, plan: OuterTowerPlan): void {
    if (plan.staging) {
        if (plan.waveFront && plan.lane !== undefined) {
            const range = Math.min(1500, Math.max(550, bot.GetAttackRange() + 120));
            for (const creep of bot.GetNearbyLaneCreeps(range, true)) {
                if (jmz.IsValid(creep) && jmz.CanBeAttacked(creep) && jmz.IsInRange(bot, creep, range)
                    && GetUnitToLocationDistance(creep, plan.waveFront) <= 700 && GetUnitToUnitDistance(creep, plan.tower) > 950
                    && GetAmountAlongLane(plan.lane, creep.GetLocation()).distance <= 460) {
                    (bot as any)._ohaIssuedPushOrder = true;
                    if (bot.GetAttackTarget() !== creep) bot.Action_AttackUnit(creep, false);
                    return;
                }
            }
        }
        const blockers = bot.GetNearbyLaneCreeps(Math.min(1600, bot.GetAttackRange() + 100), true);
        for (const creep of blockers) {
            if (!jmz.IsValid(creep) || !jmz.CanBeAttacked(creep) || GetUnitToUnitDistance(creep, plan.tower) <= 850
                || GetUnitToLocationDistance(creep, plan.staging) > 1100) continue;
            for (const ally of bot.GetNearbyLaneCreeps(1600, false)) {
                if (creep.GetAttackTarget() === ally || ally.GetAttackTarget() === creep) {
                    (bot as any)._ohaIssuedPushOrder = true;
                    if (bot.GetAttackTarget() !== creep) bot.Action_AttackUnit(creep, false);
                    return;
                }
            }
        }
        if (GetUnitToLocationDistance(bot, plan.staging) <= 120) {
            CancelPushOrder(bot);
            return;
        }
        (bot as any)._ohaIssuedPushOrder = true;
        bot.Action_MoveToLocation(plan.staging);
    } else if (bot.GetAttackTarget() !== plan.tower) {
        (bot as any)._ohaIssuedPushOrder = true;
        bot.Action_AttackUnit(plan.tower, false);
    }
}

export function PushThink(bot: Unit, lane: Lane): void {
    const now = DotaTime();

    // 1) baseline action gates
    if (jmz.CanNotUseAction(bot)) return;
    if (jmz.Utils.IsBotThinkingMeaningfulAction(bot, Customize.ThinkLess, "push")) return;

    // An active push mode can still think before the next desire arbitration.
    const ourAncient = GetAncient(GetTeam());
    const [baseResponder, criticalBaseCreeps] = GetBaseCreepResponse(bot, ourAncient);
    if (baseResponder || (ourAncient && jmz.Utils.CountEnemyHeroesNear(ourAncient.GetLocation(), BASE_ANC_RADIUS) > 0)
        || jmz.ShouldRetreatFromEnemyReinforcements(bot)) {
        CancelPushOrder(bot, lane);
        return;
    }

    if ((bot as any).ohaCounterPushLane === lane) {
        const plan = !criticalBaseCreeps && ((bot as any).ohaOuterTowerHoldUntil ?? 0) <= now
            ? GetCounterPushTarget(bot, lane, GetOpposingTeam()) : undefined;
        if (!plan) {
            (bot as any).ohaCounterPushLane = undefined;
            CancelPushOrder(bot);
            if (bot.WasRecentlyDamagedByTower(2)) bot.Action_MoveToLocation(jmz.AdjustLocationWithOffsetTowardsFountain(bot.GetLocation(), 350));
            return;
        }
        RunOuterTowerPlan(bot, plan);
        return;
    }

    // Update global caches
    autoCleanupCache();
    const gameState = getGlobalGameState();
    const locationState = getGlobalLocationState();
    if ((bot as any).ohaPostFightPushLane === lane && gameState.enemyAncient && CanFinishAncient(bot, gameState.enemyAncient)) {
        (bot as any).ohaPostFightPushLane = undefined;
    }
    if ((bot as any).ohaPostFightPushLane === lane) {
        const advance = !criticalBaseCreeps && ((bot as any).ohaOuterTowerHoldUntil ?? 0) <= now && GetPostFightPushPlan(gameState);
        if (!advance || advance.lane !== lane || !advance.ready[bot.GetPlayerID()] || jmz.GetHP(bot) < 0.55
            || !jmz.CanCommitToLaneTeleport(bot, advance.staging)) {
            CancelPushOrder(bot, lane);
            return;
        }
        if ("waveTarget" in advance) {
            const target = advance.waveTarget;
            if (!jmz.IsValid(target) || !jmz.CanBeAttacked(target) || bot.WasRecentlyDamagedByTower(2)
                || !jmz.CanCommitToLaneTeleport(bot, target.GetLocation(), true, 1200)) {
                CancelPushOrder(bot, lane);
                return;
            }
            const paired = Object.values(advance.ready).some(ally => ally.GetPlayerID() !== bot.GetPlayerID() && jmz.IsValidHero(ally)
                && jmz.GetHP(ally) >= 0.55 && !jmz.IsRetreating(ally) && !ally.IsStunned() && !ally.HasModifier("modifier_teleporting")
                && GetUnitToUnitDistance(ally, target) <= 1100 && GetUnitToUnitDistance(ally, bot) <= 1400);
            if (paired && GetUnitToUnitDistance(bot, target) <= Math.max(550, bot.GetAttackRange() + 100)) {
                (bot as any)._ohaIssuedPushOrder = true;
                if (bot.GetAttackTarget() !== target) bot.Action_AttackUnit(target, false);
            } else if (GetUnitToLocationDistance(bot, advance.staging) > 120) {
                (bot as any)._ohaIssuedPushOrder = true;
                bot.Action_MoveToLocation(advance.staging);
            } else {
                CancelPushOrder(bot);
            }
            return;
        }
        const tower = advance.tower;
        if (!IsStandingBuilding(tower)) { CancelPushOrder(bot, lane); return; }
        if (bot.WasRecentlyDamagedByTower(2) || (jmz.IsValidBuilding(tower) && tower.GetAttackTarget() === bot)) {
            CancelPushOrder(bot, lane);
            bot.Action_MoveToLocation(jmz.AdjustLocationWithOffsetTowardsFountain(bot.GetLocation(), 350));
            return;
        }
        const [wave] = jmz.GetLaneWaveAtBuilding(tower, lane);
        const canAttack = wave >= 2 && GetUnitToUnitDistance(bot, tower) <= 1600 && UnitIsValidObjective(tower)
            && jmz.CanCommitToLaneTeleport(bot, tower.GetLocation())
            && (!advance.highGround || (gameState.enemyAncient && HasHighGroundCover(bot, gameState.enemyAncient, lane)));
        if (advance.highGround && !canAttack && GetHeightLevel(advance.staging) > GetHeightLevel(bot.GetLocation())) {
            CancelPushOrder(bot, lane);
            return;
        }
        RunOuterTowerPlan(bot, { tower, lane, waveFront: advance.waveFront, staging: canAttack ? undefined : advance.staging });
        return;
    }
    const plan = (bot as any).ohaOuterTowerPush;
    if (plan?.lane === lane) {
        if (jmz.IsValidBuilding(plan.tower)
            && (plan.tower.GetAttackTarget() === bot || bot.WasRecentlyDamagedByTower(2))) {
            CancelPushOrder(bot, lane);
            bot.Action_MoveToLocation(jmz.AdjustLocationWithOffsetTowardsFountain(bot.GetLocation(), 350));
            return;
        }
        const opportunity = !criticalBaseCreeps && ((bot as any).ohaOuterTowerHoldUntil ?? 0) <= now
            ? GetOuterTowerOpportunity(bot, lane, gameState) : undefined;
        if (!opportunity || opportunity.tower !== plan.tower || (plan.earlyMidChip && !opportunity.earlyMidChip)) {
            CancelPushOrder(bot, lane);
            return;
        }
        if (opportunity.earlyMidChip) {
            (bot as any)._ohaIssuedPushOrder = true;
            if (opportunity.staging) bot.Action_MoveToLocation(opportunity.staging);
            else if (bot.GetAttackTarget() !== opportunity.tower) bot.Action_AttackUnit(opportunity.tower, true);
            return;
        }
        RunOuterTowerPlan(bot, opportunity);
        return;
    }
    hEnemyAncient = gameState.enemyAncient;
    if (hEnemyAncient && !HasHighGroundCover(bot, hEnemyAncient, lane)) {
        CancelPushOrder(bot);
        bot.Action_MoveToLocation(jmz.VectorTowards(bot.GetLocation(), locationState.teamFountain, 850));
        return;
    }

    // 2) Use cached bot state instead of fresh calculations
    const botState = updateBotStateCache(bot);
    const botLocation = botState.location;

    // Use global cached threat picture
    const alliesHere = getCachedAlliesNearLoc(botLocation, 1600);
    const enemiesHere = getCachedEnemiesNearLoc(botLocation, 1600);

    // 3) Build a lane-front offset depending on our HP and attack range
    const botAttackRange = botState.attackRange;
    const botHp = botState.hp;
    let fDeltaFromFront =
        Math.min(botHp, 0.7) * 800 -
        500 + // healthier → stand a bit closer
        RemapValClamped(botAttackRange, 300, 700, 0, -300); // longer range → stand further back
    fDeltaFromFront = Math.max(Math.min(fDeltaFromFront, 250), -200); // Reduced minimum retreat from -600 to -200

    // 4) Use cached tower & creep context
    const nEnemyTowers = botState.nearbyTowers;
    const nAllyCreeps = botState.nearbyLaneCreeps;

    // 4) Enhanced retreat logic - less conservative when team has advantages
    const protectedObjective = IsAnyTargetBackdooredAt(bot, lane);
    if (alliesHere.length < enemiesHere.length || protectedObjective) {
        let longestRange = 0;
        for (const enemyHero of enemiesHere) {
            if (jmz.IsValidHero(enemyHero) && !jmz.IsSuspiciousIllusion(enemyHero)) {
                const r = enemyHero.GetAttackRange();
                if (r > longestRange) longestRange = r;
            }
        }

        // Consider team advantages when deciding retreat distance
        const gameState = getGlobalGameState();
        const networthAdvantage = gameState.teamNetworth - gameState.enemyNetworth;
        const enemyAverageLevel = jmz.GetAverageLevel(true);
        const levelAdvantage = gameState.averageLevel - enemyAverageLevel;
        const hasTeamAdvantage = networthAdvantage > 5000 || levelAdvantage > 1;

        // More aggressive positioning when team has advantages
        if (enemiesHere.length >= alliesHere.length + 1 || botHp < 0.3) {
            if (hasTeamAdvantage && botHp > 0.4) {
                // Less retreat when team has advantage and bot is healthy
                fDeltaFromFront = Math.max(-200, -80 - 0.25 * longestRange);
            } else {
                fDeltaFromFront = Math.max(-300, -120 - 0.35 * longestRange);
            }
        } else {
            if (hasTeamAdvantage && botHp > 0.5) {
                // Stay closer when team has advantage
                fDeltaFromFront = Math.max(-50, -20 - 0.1 * longestRange);
            } else {
                fDeltaFromFront = Math.max(-100, -50 - 0.2 * longestRange);
            }
        }
    }

    // 5) Compute our approach waypoint for this lane
    const targetLoc = GetLaneFrontLocation(gameState.team, lane, fDeltaFromFront);

    // Update bot cache with target location for distance calculations (only if needed)
    if (!botState.distanceToTargetLoc || Math.abs(botState.distanceToTargetLoc - GetUnitToLocationDistance(bot, targetLoc)) > 50) {
        updateBotStateCache(bot, targetLoc);
    }

    // 6) If the nearest enemy tower is shooting (or just shot) us → kite back
    if (
        jmz.IsValidBuilding(nEnemyTowers[0]) &&
        (nEnemyTowers[0].GetAttackTarget() === bot || (nEnemyTowers[0].GetAttackTarget() !== bot && bot.WasRecentlyDamagedByTower(nAllyCreeps.length <= 2 ? 4.0 : 2.0)))
    ) {
        const nDamage = nEnemyTowers[0].GetAttackDamage() * nEnemyTowers[0].GetAttackSpeed() * 5.0 - bot.GetHealthRegen() * 5.0;
        if (bot.GetActualIncomingDamage(nDamage, DamageType.Physical) / bot.GetHealth() > 0.15 || nAllyCreeps.length > 2) {
            const retreat = Math.min(fDeltaFromFront - 200, -300);
            const retreatLoc = GetLaneFrontLocation(gameState.team, lane, retreat);
            (bot as any)._ohaIssuedPushOrder = false;
            bot.Action_MoveToLocation(retreatLoc);
            return;
        }
    }

    // 7) Ancient-endgame logic: if we're in range and it's hittable, do it
    if (!criticalBaseCreeps && hEnemyAncient && CanFinishAncient(bot, hEnemyAncient)) {
        (bot as any)._ohaIssuedPushOrder = true;
        bot.Action_AttackUnit(hEnemyAncient, true);
        return;
    }

    // 8) Find attackable creeps to thin out while we approach (prefer those not under tower)
    let nRange = Math.min(700 + botAttackRange, 1600);
    if (hEnemyAncient && botState.distanceToAncient < 2600) {
        // bump the search radius when we're near high ground / base
        nRange = 1600;
    }

    // Use cached creeps with global cache
    let nCreeps = botState.nearbyCreeps;
    const creepCacheKey = `specialCreeps_${bot.GetPlayerID()}_${Math.floor(now * 5)}`;
    nCreeps = getCachedData(creepCacheKey, 0.2, () => GetSpecialUnitsNearby(bot, nCreeps, nRange));

    const vTeamFountain = locationState.teamFountain;
    const bTowerNearby = jmz.IsValidBuilding(nEnemyTowers[0]); // only consider creeps "in front" of tower
    const towerDistanceToFountain = bTowerNearby ? GetUnitToLocationDistance(nEnemyTowers[0], vTeamFountain) : 0;

    for (const creep of nCreeps) {
        if (!jmz.IsValid(creep) || !jmz.CanBeAttacked(creep)) continue;
        if (jmz.IsTormentor(creep) || jmz.IsRoshan(creep)) continue;

        if (bTowerNearby && GetUnitToLocationDistance(creep, vTeamFountain) >= towerDistanceToFountain) continue;

        (bot as any)._ohaIssuedPushOrder = true;
        bot.Action_AttackUnit(creep, true);
        return;
    }

    // 9) High-ground building priorities: barracks → towers → fillers
    // Unified high-ground objective selection with stickiness (prevents thrash)
    const hgTarget = SelectOrStickHGTarget(bot, lane, targetLoc);
    if (hgTarget) {
        (bot as any)._ohaIssuedPushOrder = true;
        if (jmz.IsInRange(bot, hgTarget, botAttackRange + 150)) {
            bot.Action_AttackUnit(hgTarget, true);
        } else {
            bot.Action_MoveToLocation(hgTarget.GetLocation());
        }
        return;
    }

    if (protectedObjective) {
        CancelPushOrder(bot);
        bot.Action_MoveToLocation(targetLoc);
        return;
    }

    // 10) Movement fallback: path to approach point, then do small attack-move jitter to hold space
    if (botState.distanceToTargetLoc > 500) {
        (bot as any)._ohaIssuedPushOrder = true;
        bot.Action_MoveToLocation(targetLoc);
        return;
    } else {
        if (DotaTime() >= fNextMovementTime) {
            const attackMoveLoc = jmz.GetRandomLocationWithinDist(targetLoc, 0, 400);
            (bot as any)._ohaIssuedPushOrder = true;
            bot.Action_AttackMove(attackMoveLoc);
            fNextMovementTime = DotaTime() + RandomFloat(0.05, 0.3);
            return;
        }
    }
}

/* -----------------------------------------------------------------------------
 * High-ground cross-lane clearing
 * ---------------------------------------------------------------------------*/
export function TryClearingOtherLaneHighGround(_bot: Unit, vLocation: Vector): Unit | null {
    //   print("TryClearingOtherLaneHighGround for: ", bot.GetUnitName(), vLocation);

    const gameState = updateGameStateCache();
    const unitState = updateUnitStateCache();
    const unitList = unitState.enemyBuildings;

    function IsValid(building: Unit | null): building is Unit {
        return jmz.IsValidBuilding(building) && jmz.CanBeAttacked(building!) && !HasBackdoorProtect(building!);
    }

    // Prefer closest barracks first
    let hBarrackTarget: Unit | null = null;
    let best = Number.POSITIVE_INFINITY;
    for (const barrack of unitList) {
        if (
            IsValid(barrack) &&
            (barrack === GetBarracks(gameState.enemyTeam, Barracks.TopMelee) ||
                barrack === GetBarracks(gameState.enemyTeam, Barracks.TopRanged) ||
                barrack === GetBarracks(gameState.enemyTeam, Barracks.MidMelee) ||
                barrack === GetBarracks(gameState.enemyTeam, Barracks.MidRanged) ||
                barrack === GetBarracks(gameState.enemyTeam, Barracks.BotMelee) ||
                barrack === GetBarracks(gameState.enemyTeam, Barracks.BotRanged))
        ) {
            const d = GetUnitToLocationDistance(barrack, vLocation);
            if (d < best) {
                hBarrackTarget = barrack;
                best = d;
            }
        }
    }
    if (hBarrackTarget) return hBarrackTarget;

    // Then closest T3 tower
    let hTowerTarget: Unit | null = null;
    best = Number.POSITIVE_INFINITY;
    for (const tower of unitList) {
        if (
            IsValid(tower) &&
            (tower === GetTower(gameState.enemyTeam, Tower.Top3) ||
                tower === GetTower(gameState.enemyTeam, Tower.Mid3) ||
                tower === GetTower(gameState.enemyTeam, Tower.Bot3))
        ) {
            const d = GetUnitToLocationDistance(tower, vLocation);
            if (d < best) {
                hTowerTarget = tower;
                best = d;
            }
        }
    }
    if (hTowerTarget) return hTowerTarget;

    return null;
}

/* -----------------------------------------------------------------------------
 * Utility helpers (validation, backdoor checks, etc.)
 * ---------------------------------------------------------------------------*/

export function CanBeAttacked(building: Unit | null): boolean {
    return !!building && building.CanBeSeen() && !building.IsInvulnerable();
}

export function IsEnemyTP(nID: number): boolean {
    const gameState = updateGameStateCache();
    for (const id of GetTeamPlayers(gameState.enemyTeam)) {
        if (id === nID) return true;
    }
    return false;
}

/** Estimate if staying in a tower's zone is too dangerous over fDuration seconds */
export function IsInDangerWithinTower(hUnit: Unit, fThreshold: number, fDuration: number): boolean {
    const unitState = updateUnitStateCache();
    let totalDamage = 0;
    for (const enemy of unitState.enemyHeroes) {
        if (jmz.IsValid(enemy) && jmz.IsInRange(hUnit, enemy, 1600) && (enemy.GetAttackTarget() === hUnit || jmz.IsChasingTarget(enemy, hUnit))) {
            totalDamage += hUnit.GetActualIncomingDamage(enemy.GetAttackDamage() * enemy.GetAttackSpeed() * fDuration, DamageType.Physical);
        }
    }
    return (totalDamage / hUnit.GetHealth()) * 1.2 > fThreshold;
}

/** Include micro-summons & dominated units into "nearby creeps" for push thinning */
export function GetSpecialUnitsNearby(bot: Unit, hUnitList: Unit[], nRadius: number): Unit[] {
    const unitState = updateUnitStateCache();
    const hCreepList: Unit[] = [...hUnitList];

    for (const unit of unitState.enemyHeroes) {
        if (IsValidUnit(unit) && jmz.IsInRange(bot, unit, nRadius)) {
            const s = unit.GetUnitName();
            if (
                s.includes("invoker_forge_spirit") ||
                s.includes("lycan_wolf") ||
                s.includes("eidolon") ||
                s.includes("beastmaster_boar") ||
                s.includes("beastmaster_greater_boar") ||
                s.includes("furion_treant") ||
                s.includes("broodmother_spiderling") ||
                s.includes("skeleton_warrior") ||
                s.includes("warlock_golem") ||
                unit.HasModifier("modifier_dominated") ||
                unit.HasModifier("modifier_chen_holy_persuasion")
            ) {
                hCreepList.push(unit);
            }
        }
    }

    return hCreepList;
}

export function IsHealthyInsideFountain(hUnit: Unit): boolean {
    return hUnit.HasModifier("modifier_fountain_aura_buff") && jmz.GetHP(hUnit) > 0.9 && jmz.GetMP(hUnit) > 0.85;
}

export function GetAllyHeroesAttackingUnit(hUnit: Unit): Unit[] {
    const unitState = updateUnitStateCache();
    const out: Unit[] = [];
    for (const ally of unitState.alliedHeroes) {
        if (jmz.IsValidHero(ally) && !jmz.IsSuspiciousIllusion(ally) && !jmz.IsMeepoClone(ally) && ally.GetAttackTarget() === hUnit) {
            out.push(ally);
        }
    }
    return out;
}

export function GetAllyCreepsAttackingUnit(hUnit: Unit): Unit[] {
    const unitState = updateUnitStateCache();
    const out: Unit[] = [];
    for (const creep of unitState.alliedCreeps) {
        if (jmz.IsValid(creep) && creep.GetAttackTarget() === hUnit) {
            out.push(creep);
        }
    }
    return out;
}

/** Returns 1..4 for the highest structure on that lane that is still alive on the enemy team */
export function GetLaneBuildingTier(nLane: Lane): number {
    const gameState = updateGameStateCache();
    const enemyTeam = gameState.enemyTeam;

    if (nLane === Lane.Top) {
        if (GetTower(enemyTeam, Tower.Top1) !== null) return 1;
        else if (GetTower(enemyTeam, Tower.Top2) !== null) return 2;
        else if (GetTower(enemyTeam, Tower.Top3) !== null || GetBarracks(enemyTeam, Barracks.TopMelee) !== null || GetBarracks(enemyTeam, Barracks.TopRanged) !== null)
            return 3;
        else return 4;
    } else if (nLane === Lane.Mid) {
        if (GetTower(enemyTeam, Tower.Mid1) !== null) return 1;
        else if (GetTower(enemyTeam, Tower.Mid2) !== null) return 2;
        else if (GetTower(enemyTeam, Tower.Mid3) !== null || GetBarracks(enemyTeam, Barracks.MidMelee) !== null || GetBarracks(enemyTeam, Barracks.MidRanged) !== null)
            return 3;
        else return 4;
    } else if (nLane === Lane.Bot) {
        if (GetTower(enemyTeam, Tower.Bot1) !== null) return 1;
        else if (GetTower(enemyTeam, Tower.Bot2) !== null) return 2;
        else if (GetTower(enemyTeam, Tower.Bot3) !== null || GetBarracks(enemyTeam, Barracks.BotMelee) !== null || GetBarracks(enemyTeam, Barracks.BotRanged) !== null)
            return 3;
        else return 4;
    }
    return 1;
}

export function ShouldWaitForImportantItemsSpells(vLocation: Vector): boolean {
    const gameState = updateGameStateCache();
    if (gameState.isMidGame || gameState.isLateGame) {
        if (jmz.Utils.HasTeamMemberWithCriticalItemInCooldown(vLocation)) return true;
        if (jmz.Utils.HasTeamMemberWithCriticalSpellInCooldown(vLocation)) return true;
    }
    return false;
}

export function HasBackdoorProtect(target: Unit): boolean {
    return (
        target.HasModifier("modifier_fountain_glyph") ||
        target.HasModifier("modifier_backdoor_protection_active")
    );
}

/* -----------------------------------------------------------------------------
 * New targeted helpers to reduce thrash/jitter
 * ---------------------------------------------------------------------------*/

/**
 * Returns true if the *nearest* intended target around the enemy lane-front
 * is currently backdoored/glyphed.
 */
export function IsAnyTargetBackdooredAt(_bot: Unit, lane: Lane): boolean {
    const locationState = updateLocationStateCache();
    const unitState = updateUnitStateCache();

    const lf = locationState.laneFronts[lane];
    let nearest: Unit | null = null;
    let best = Number.POSITIVE_INFINITY;
    for (const b of unitState.enemyBuildings) {
        if (jmz.IsValidBuilding(b)) {
            const d = GetUnitToLocationDistance(b, lf);
            if (d < best) {
                nearest = b;
                best = d;
            }
        }
    }
    return !!(nearest && HasBackdoorProtect(nearest));
}

/**
 * Picks best high-ground objective with strict priority:
 *   1) Barracks: melee > ranged (closest of each class)
 *   2) Tier-3 towers (closest)
 *   3) Fillers/others (closest)
 * Radius is the max distance from the bot; tie-breaker favors closer to targetLoc.
 */
export function FindBestHGTarget(bot: Unit, radius: number, targetLoc?: Vector | null): Unit | null {
    const gameState = updateGameStateCache();
    const unitState = updateUnitStateCache();

    const isBarracks = (u: Unit) => u.GetUnitName().includes("rax");
    const isMeleeBarracks = (u: Unit) => u.GetUnitName().includes("melee");
    const isRangedBarracks = (u: Unit) => u.GetUnitName().includes("ranged");
    const isT3Tower = (u: Unit) =>
        u === GetTower(gameState.enemyTeam, Tower.Top3) || u === GetTower(gameState.enemyTeam, Tower.Mid3) || u === GetTower(gameState.enemyTeam, Tower.Bot3);
    const isT4Tower = (u: Unit) => u === GetTower(gameState.enemyTeam, Tower.Base1) || u === GetTower(gameState.enemyTeam, Tower.Base2);

    let bestMelee: Unit | null = null,
        bestMeleeD = Number.POSITIVE_INFINITY;
    let bestRanged: Unit | null = null,
        bestRangedD = Number.POSITIVE_INFINITY;
    let bestT3: Unit | null = null,
        bestT3D = Number.POSITIVE_INFINITY;
    let bestT4: Unit | null = null,
        bestT4D = Number.POSITIVE_INFINITY;
    let bestOther: Unit | null = null,
        bestOtherD = Number.POSITIVE_INFINITY;

    for (const b of unitState.enemyBuildings) {
        if (jmz.IsValidBuilding(b) && jmz.CanBeAttacked(b) && !HasBackdoorProtect(b)) {
            const dBot = GetUnitToUnitDistance(bot, b);
            if (dBot <= radius) {
                // prefer closer to our approach point when bot-distance is similar
                const dLoc = targetLoc ? GetUnitToLocationDistance(b, targetLoc) : 0;

                if (isBarracks(b)) {
                    if (isMeleeBarracks(b)) {
                        if (dBot < bestMeleeD || (dBot === bestMeleeD && dLoc < (bestMelee ? GetUnitToLocationDistance(bestMelee, targetLoc!) : dLoc))) {
                            bestMelee = b;
                            bestMeleeD = dBot;
                        }
                    } else if (isRangedBarracks(b)) {
                        if (dBot < bestRangedD || (dBot === bestRangedD && dLoc < (bestRanged ? GetUnitToLocationDistance(bestRanged, targetLoc!) : dLoc))) {
                            bestRanged = b;
                            bestRangedD = dBot;
                        }
                    }
                } else if (isT3Tower(b)) {
                    if (dBot < bestT3D || (dBot === bestT3D && dLoc < (bestT3 ? GetUnitToLocationDistance(bestT3, targetLoc!) : dLoc))) {
                        bestT3 = b;
                        bestT3D = dBot;
                    }
                } else if (isT4Tower(b)) {
                    if (dBot < bestT4D || (dBot === bestT4D && dLoc < (bestT4 ? GetUnitToLocationDistance(bestT4, targetLoc!) : dLoc))) {
                        bestT4 = b;
                        bestT4D = dBot;
                    }
                } else {
                    if (dBot < bestOtherD || (dBot === bestOtherD && dLoc < (bestOther ? GetUnitToLocationDistance(bestOther, targetLoc!) : dLoc))) {
                        bestOther = b;
                        bestOtherD = dBot;
                    }
                }
            }
        }
    }

    return bestMelee || bestRanged || bestT3 || bestOther;
}
