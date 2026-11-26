local J = require(GetScriptDirectory()..'/FunLib/jmz_func')
local U = require(GetScriptDirectory()..'/FunLib/minion_lib/utils')

local X = {}

function X.Think(bot, hMinionUnit)
	local thisMinionAttackRange = hMinionUnit:GetAttackRange()
	local siege = bot.ohaSerpentWardSiegeTarget
	if J.IsValidBuilding(siege) and J.CanBeAttacked(siege)
		and not siege:HasModifier('modifier_fountain_glyph')
		and not siege:HasModifier('modifier_backdoor_protection_active')
		and not siege:HasModifier('modifier_backdoor_protection_in_base')
		and GetUnitToUnitDistance(hMinionUnit, siege) <= thisMinionAttackRange then
		hMinionUnit:Action_AttackUnit(siege, true)
		return
	end

	local target = U.GetWeakestHero(thisMinionAttackRange, hMinionUnit)
	if target == nil
	then
		target = U.GetWeakestCreep(thisMinionAttackRange, hMinionUnit)
		if target == nil
		then
			target = U.GetWeakestTower(thisMinionAttackRange, hMinionUnit)
		end
	end

	if target ~= nil and not U.IsNotAllowedToAttack(target)
	then
		hMinionUnit:Action_AttackUnit(target, true)
		return
	end
end

return X
