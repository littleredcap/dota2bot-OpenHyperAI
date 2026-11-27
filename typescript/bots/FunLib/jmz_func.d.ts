import { Ability, BotMode, Lane, Ping, Talent, Team, Unit, Vector } from "bots/ts_libs/dota";
import { BotRole, TalentTreeBuild } from "bots/ts_libs/bots";
import * as Util from "bots/FunLib/utils";

/** @noSelf **/
interface ISkill {
    GetRandomBuild(builds: number[][]): number[];

    GetTalentBuild(talents: TalentTreeBuild): number[];

    GetTalentList(bot: Unit): Talent[];

    GetAbilityList(bot: Unit): string[];

    GetSkillList(abilities: string[], abilityBuild: number[], talentList: Talent[], talentBuild: number[]): string[];
}

/** @noSelf **/
interface IItem {
    GetRoleItemsBuyList(bot: Unit): BotRole;
}

declare function IsInTeamFight(bot: Unit, radius: number): boolean;

declare function IsRetreating(bot: Unit): boolean;

declare function IsGoingOnSomeone(bot: Unit): boolean;

declare function CanNotUseAbility(bot: Unit): boolean;
declare function CanNotUseAction(bot: Unit): boolean;

declare function GetMP(bot: Unit): number;

declare function GetHP(bot: Unit): number;
declare function GetTeamFountain(): Vector;

declare function GetMostDefendLaneDesire(): LuaMultiReturn<[Lane, number]>;

declare function GetLastSeenEnemiesNearLoc(location: Vector, radius: number): Unit[];

declare function AdjustLocationWithOffsetTowardsFountain(vector: Vector, distance: number): Vector;
declare function VectorTowards(start: Vector, destination: Vector, distance: number): Vector;

declare function GetNearbyLocationToTp(location: Vector): Vector;

declare function GetPosition(bot: Unit | null): number;

declare function IsInLaningPhase(unit?: Unit): boolean;

declare function IsDoingRoshan(bot: Unit): boolean;

declare function IsDoingTormentor(bot: Unit): boolean;

declare function GetTormentorLocation(team: Team): Vector;

declare function GetAlliesNearLoc(location: Vector, radius: number): Unit[];

declare function GetEnemiesAroundAncient(bot: Unit, radius: number | null): number;

declare function GetProperTarget(bot: Unit): Unit;

declare function IsPingCloseToValidTower(team: Team, ping: Ping, radius: number, duration: number): LuaMultiReturn<[false, null] | [true, Lane]>;

declare function GetNumOfAliveHeroes(isEnemy: boolean): number;

declare function IsValid(target: Unit): boolean;

declare function GetHeroesNearLocation(enemy: boolean, location: Vector, radius: number): Unit[];

declare function CanBeAttacked(unit: Unit): boolean;

declare function IsSuspiciousIllusion(unit: Unit): boolean;
declare function IsEarlyGame(): boolean;
declare function IsMidGame(): boolean;
declare function IsLateGame(): boolean;
declare function GetEnemiesNearLoc(location: Vector, radius: number): Unit[];
declare function GetAvailableFightAllies(bot: Unit, location: Vector, radius: number): number;
declare function HasSiegeDamageInRange(bot: Unit, location: Vector, lane?: Lane): boolean;
declare function IsKeyWordUnit(keyword: string, unit: Unit): boolean;
declare function GetLaneWaveAtBuilding(building: Unit, lane: Lane): LuaMultiReturn<[number, number, number, number, number]>;
declare function GetEnemyReinforcementWindow(): number;
declare function CanFinishOuterTowerInWindow(bot: Unit, tower: Unit, lane: Lane, window: number): boolean;
interface OuterTowerThreat {
    tower: Unit;
    lane: Lane;
    enemies: Unit[];
    underAttack: boolean;
    damageRate: number;
    siegeAttacking: boolean;
    heroAttacking: boolean;
    count: number;
    near: number;
    waveSize: number;
    waveHP: number;
    siege: boolean;
    eta: number;
    towerHP: number;
    briefHold?: boolean;
    score: number;
}
declare function GetOuterTowerThreat(tower: Unit, lane: Lane): OuterTowerThreat;
declare function GetExposedMidCover(team: Team): LuaMultiReturn<[Unit | undefined, Unit | undefined, number | undefined]>;
declare function GetOuterTowerResponse(location: Vector, threat: OuterTowerThreat, fallback?: Vector, highGround?: boolean): LuaMultiReturn<[boolean, Record<number, {reach: number, cover: boolean, teleport?: Vector, rally?: Vector, gather?: Vector, screen?: boolean, needsGlyph?: boolean} | undefined>]>;
declare function RunOuterTowerHold(bot: Unit, location: Vector, reach: number, cover: boolean): boolean;
declare function RunOuterTowerContest(bot: Unit, tower: Unit, threat: OuterTowerThreat, state: {waveClearGather?: Vector, waveClearReach?: number}): boolean;
declare function HasPendingLaningLastHit(bot: Unit): boolean;
declare function CanCommitToLaneTeleport(bot: Unit, location: Vector, requireClear?: boolean, radius?: number): boolean;
export function IsHighGroundResponseThreat(threat: OuterTowerThreat): boolean;
export function GetHighGroundWalkPoint(bot: Unit, stage: Vector, rear?: Vector): Vector | undefined;
export function GetHighGroundResponseTeleport(bot: Unit, stage: Vector, anchors: Unit[]): Vector | undefined;
declare function ShouldRetreatFromEnemyReinforcements(bot: Unit): boolean;
declare function GetAlliesNearLoc(location: Vector, radius: number): Unit[];
declare function IsCore(bot: Unit): boolean;
declare function IsSupport(bot: Unit): boolean;
declare function IsPvNMode(): boolean;
declare function GetMostPushLaneDesire(): Lane;
declare function GetMostDefendLaneDesire(): Lane;
declare function GetNumOfTeamTotalKills(isEnemy: boolean): number;
declare function GetNumOfAliveCore(isEnemy: boolean): number;
declare function GetAliveCoreCount(isEnemy: boolean): number;
declare function GetNumOfTeamTotalKills(isEnemy: boolean): number;
declare function GetNumOfAliveCore(isEnemy: boolean): number;
declare function GetAliveCoreCount(isEnemy: boolean): number;
declare function GetCurrentRoshanLocation(): Vector;
declare function GetTormentorWaitingLocation(team: Team): Vector;
declare function IsDefending(bot: Unit): boolean;
declare function GetHumanPing(): LuaMultiReturn<[any, any]>;
declare function GetEnemiesAroundLoc(location: Vector, radius: number): number;
declare function DoesTeamHaveAegis(): boolean;
declare function GetAverageLevel(bEnemy: boolean): number;
declare function GetInventoryNetworth(): LuaMultiReturn<[any, any]>;
declare function IsValidBuilding(unit: any): boolean;
declare function IsValidHero(unit: any): boolean;
declare function IsCore(unit: any): boolean;
declare function GetDistance(location1: Vector, location2: Vector): number;
declare function IsTormentor(unit: any): boolean;
declare function IsRoshan(unit: any): boolean;
declare function IsInRange(unit: any, target: any, range: number): boolean;
declare function GetRandomLocationWithinDist(location: Vector, minDist: number, maxDist: number): Vector;
declare function GetRandomLocationWithinDist(location: Vector, minDist: number, maxDist: number): Vector;
declare function IsChasingTarget(unit: any, target: any): boolean;
declare function IsMeepoClone(unit: any): boolean;
declare function GetAllyHeroesAttackingUnit(unit: any): Unit[];
declare function GetAllyCreepsAttackingUnit(unit: any): Unit[];
declare function GetLaneBuildingTier(lane: Lane): number;
declare function ShouldWaitForImportantItemsSpells(location: Vector): boolean;
declare function HasBackdoorProtect(target: any): boolean;
declare function IsAnyTargetBackdooredAt(bot: any, lane: Lane): boolean;
declare function CanCastAbility(ability: any): boolean;
declare function GetItem2(bot: Unit, itemName: string): any;
declare function GetRetreatingAlliesNearLoc(location: Vector, radius: number): Unit[];
declare function GetNearbyHeroes(unit: Unit, radius: number, includeEnemies: boolean, mode: BotMode): Unit[];
declare function WeAreStronger(bot: Unit, radius: number): boolean;
declare function IsAnyAllyDefending(bot: Unit, lane: Lane): boolean;
declare function RandomForwardVector(distance: number): Vector;

declare const Skill: ISkill;
declare const Item: IItem;
declare const Utils: typeof Util;
