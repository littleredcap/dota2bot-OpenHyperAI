local Defend = require( GetScriptDirectory()..'/FunLib/aba_defend')

local Trace = require( GetScriptDirectory()..'/FunLib/oha_decision_trace' )
local bot = GetBot()
local botName = bot:GetUnitName()

if bot:IsInvulnerable() or not bot:IsHero() or not string.find(botName, "hero") or bot:IsIllusion() then
	return
end

function GetDesire()
    local desire = Defend.GetDefendDesire(bot, LANE_MID)
    if desire >= 0.97 and (bot._ohaCreepDefenseUntil or -1) > DotaTime() then
        Trace.Record(bot, "DEFEND", "ancient_creeps", "SELECT", "BASE_CREEP_ATTACKING")
    end
    return desire
end
function Think() Defend.DefendThink(bot, LANE_MID) end
