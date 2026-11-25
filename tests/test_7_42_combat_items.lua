local function no() return false end
local function yes() return true end
local function empty() return {} end
local function zero() return 0 end
local function pos(x) return {x = x} end
local function distance(a, b) return math.abs(a.x - b.x) end
local detection = {}
do
    local file = assert(io.open('bots/FunLib/jmz_func.lua', 'r'))
    local source = file:read('*a')
    file:close()
    local start = assert(source:find('function J.HasItemConcealment(unit)', 1, true))
    local finish = assert(source:find('function J.HasInvisCounterBuff(unit)', start, true))
    setfenv(assert(loadstring(source:sub(start, finish - 1))), {J = detection})()
end

local function ability(name, flags, range, mana, values)
    local h = {cooldown = 0}
    function h:GetName() return name end
    function h:GetBehavior() return flags end
    function h:GetCastRange() return range end
    function h:GetManaCost() return mana end
    function h:GetSpecialValueInt(key) return (values or {})[key] or 0 end
    h.GetSpecialValueFloat = h.GetSpecialValueInt
    h.IsNull, h.IsHidden, h.IsTrained, h.IsActivated = no, no, yes, yes
    h.GetCastPoint = function() return 0.2 end
    function h:GetCooldownTimeRemaining() return self.cooldown end
    return h
end

local function fixture(itemNames, heroName)
    local state = {time = 20, orders = {}, mana = 200, hp = 0.85}
    local bot = {x = 0, side = 2, id = 1, mods = {}, incoming = {}}
    local ally = {x = 200, side = 2, id = 2, mods = {}, incoming = {}, hp = 0.35, direction = -1}
    local enemies = {}
    for i = 1, 4 do enemies[i] = {x = 400 + 50 * i, side = 3, id = 4 + i, mods = {}, incoming = {}, hidden = true} end
    local roster = {bot, ally, unpack(enemies)}
    for _, unit in ipairs(roster) do
        unit.GetLocation = function(self) return pos(self.x) end
        unit.GetTeam = function(self) return self.side end
        unit.GetPlayerID = function(self) return self.id end
        unit.GetAttackTarget = function(self) return self.attacking end
        unit.GetAttackRange = function(self) return self.attackRange or 200 end
        unit.GetAttackProjectileSpeed = function(self) return self.projectileSpeed or 0 end
        unit.GetAttackDamage = function(self) return self.side == 2 and 70 or 125 end
        unit.GetCurrentMovementSpeed = function() return 400 end
        unit.GetIncomingTrackingProjectiles = function(self) return self.incoming end
        unit.HasModifier = function(self, name)
            return self.mods[name] ~= nil or (self.fading == true and name == 'modifier_item_invisibility_edge_windwalk')
        end
        unit.IsInvisible = function(self) return self.invisible == true end
        unit.IsSilenced = function(self) return self.silenced == true end
        unit.IsRooted = function(self) return self.rooted == true end
        unit.IsDisarmed = function(self) return self.disarmed == true end
        unit.WasRecentlyDamagedByHero = function(self) return self.hurt == true end
        unit.IsAlive, unit.IsHero, unit.IsFacingLocation = yes, yes, yes
        unit.IsChanneling = function(self) return self.channeling == true end
        unit.IsUsingAbility = no
        unit.IsCastingAbility = function(self) return self.casting ~= nil end
        unit.GetCurrentActiveAbility = function(self) return self.casting end
        unit.IsMuted = function(self) return self.muted == true end
        unit.IsMagicImmune, unit.IsInvulnerable, unit.IsIllusion = no, no, no
        unit.IsHexed, unit.IsStunned = no, no
        unit.NumQueuedActions = zero
        unit.GetNearbyTowers = function(self) return self.tower and {self.tower} or {} end
    end
    bot.GetUnitName = function() return heroName or 'npc_dota_hero_faceless_void' end
    bot.GetMana = function() return state.mana end
    bot.GetActiveMode = zero
    bot.GetActiveModeDesire = function() return 0.9 end
    bot.GetHealth = function() return state.hp * 1000 end
    bot.OriginalGetHealth = bot.GetHealth
    bot.OriginalGetMaxHealth = function() return 1000 end
    bot.WasRecentlyDamagedByAnyHero = function() return state.hurt end
    bot.FindAoELocation = function() return state.chronoArea or {count = 0} end
    local walk = ability('faceless_void_time_walk', 16, 650, 40, {range = 650})
    local chrono = ability('faceless_void_chronosphere', 16, 650, 100, {radius = 375})
    local stun = ability('sven_storm_bolt', 8, 650, 100)
    local soft = ability('soft_projectile', 8, 650, 100)
    local ground = ability('area_projectile', 16, 650, 100)
    bot.GetAbilityByName = function(_, name)
        if name == walk:GetName() then return walk end
        if name == chrono:GetName() then return chrono end
    end
    local items = {
        item_black_king_bar = ability('item_black_king_bar', 4, 0, 50),
        item_force_staff = ability('item_force_staff', 8, 550, 150, {push_length = 600, enemy_cast_range = 850}),
        item_caduceus = ability('item_caduceus', 8, 550, 150, {push_length = 600, enemy_cast_range = 850}),
        item_hurricane_pike = ability('item_hurricane_pike', 8, 650, 150, {push_length = 600, cast_range_enemy = 425, enemy_length = 425}),
        item_invis_sword = ability('item_invis_sword', 4, 0, 75, {windwalk_fade_time = 0.3}),
        item_silver_edge = ability('item_silver_edge', 4, 0, 75, {windwalk_fade_time = 0.3}),
        item_glimmer_cape = ability('item_glimmer_cape', 8, 600, 125, {initial_fade_delay = 0.5}),
        item_lotus_orb = ability('item_lotus_orb', 8, 900, 175),
        item_dust = ability('item_dust', 4, 1050, 0, {radius = 1050, duration = 12}),
        item_ghost = ability('item_ghost', 4, 0, 0),
        item_satanic = ability('item_satanic', 4, 0, 0),
        item_ethereal_blade = ability('item_ethereal_blade', 8, 800, 50),
        item_armlet = ability('item_armlet', 4, 0, 0),
    }
    items.item_armlet.GetToggleState = no
    local slots = {}
    for i, name in ipairs(itemNames) do slots[6 - i] = items[name] end
    bot.GetItemInSlot = function(_, slot) return slots[slot] end
    bot.Action_UseAbility = function(_, h) state.orders[#state.orders + 1] = {h:GetName()} end
    bot.Action_UseAbilityOnEntity = function(_, h, target) state.orders[#state.orders + 1] = {h:GetName(), target} end
    bot.ActionQueue_UseAbilityOnLocation = function(_, h, location) state.orders[#state.orders + 1] = {h:GetName(), location} end

    local function near(units, point, radius)
        local result = {}
        for _, unit in ipairs(units) do
            if not unit.hidden and distance(unit, point) <= radius then result[#result + 1] = unit end
        end
        return result
    end
    local j = {
        IsStaleARDMHero = function() return false, bot, bot:GetUnitName() end, GetUserHeroConfig = function() end,
        IsNoItemIllution = no, GetProperTarget = function(unit) return unit.attacking end,
        IsItemAvailable = function() end, CanCastAbility = function(h) return h ~= nil and h.cooldown == 0 end,
        GetNearbyHeroes = function(unit, radius) return near(enemies, unit, radius) end,
        GetEnemiesNearLoc = function(point, radius) return near(enemies, point, radius) end,
        GetAlliesNearLoc = function(point, radius) return near({bot, ally}, point, radius) end,
        GetHeroesTargetingUnit = function(units, target)
            local result = {}
            for _, unit in ipairs(units) do if unit.attacking == target then result[#result + 1] = unit end end
            return result
        end,
        GetHP = function(unit) return unit == bot and state.hp or unit.hp or 1 end,
        GetModifierTime = function(unit, name) return unit.mods[name] or 0 end,
        IsStunProjectileSpell = function(name) return name == 'sven_storm_bolt' end,
        IsValidHero = function(unit) return unit ~= nil and unit.id ~= nil and not unit.hidden end,
        IsSuspiciousIllusion = no, IsDisabled = function(unit) return unit:IsRooted() end,
        IsRetreating = function(unit) return unit.retreating == true end,
        ShouldRetreatFromEnemyReinforcements = function(unit) return unit == bot and state.reinforcements == true end,
        IsGoingOnSomeone = function(unit) return unit == bot and state.fighting end,
        GetAvailableFightAllies = function() return state.backup and 1 or 0 end,
        GetEscapeLoc = function() return pos(-1400) end,
        IsLocationInChrono = no, IsLocationInBlackHole = no, IsLocationInArena = no,
        GetFaceTowardDistanceLocation = function(unit, range) return pos(unit.x + (unit.direction or 1) * range) end,
        IsInRange = function(a, b, range) return distance(a, b) <= range end,
        GetDistance = distance, IsValidBuilding = function(unit) return unit and unit.isTower end,
        IsStuck = no, CanBeAttacked = yes, CanCastOnMagicImmune = yes, CanCastOnNonMagicImmune = yes, CanCastOnTargetAdvanced = yes,
        IsValid = function(unit) return unit ~= nil and unit.id ~= nil end,
        IsInEtherealForm = function(unit) return unit:HasModifier('modifier_ghost_state') end,
        HasItemConcealment = detection.HasItemConcealment, IsUnitWillGoInvisible = detection.IsUnitWillGoInvisible,
        HasInvisCounterBuff = function(unit) return unit.revealed == true end,
        IsClosestToDustLocation = yes, CheckBitfieldFlag = function(a, b) return a == b end,
        Item = {IsSpecifiedItem = no},
        Chat = {GetNormName = function() return 'test hero' end},
        Site = {GetXUnitsTowardsLocation = function(unit, goal, range) return pos(unit.x + (goal.x < unit.x and -range or range)) end},
    }
    local env = setmetatable({
        GetBot = function() return bot end, GetScriptDirectory = function() return 'bots' end,
        GetTeam = function() return 2 end, Vector = empty, RandomInt = function(first) return first end,
        require = function(name) return name == 'bots/FunLib/jmz_func' and j or {} end,
        dofile = function() return {sSkillList = {}} end,
        DotaTime = function() return state.time end, IsHeroAlive = yes, IsLocationVisible = yes,
        IsLocationPassable = function(point) return not state.blocked or point.x >= 0 end,
        GetUnitToUnitDistance = distance, GetUnitToLocationDistance = distance,
        BOT_ACTION_DESIRE_NONE = 0, BOT_ACTION_DESIRE_HIGH = 0.8, BOT_MODE_NONE = 0, BOT_MODE_DESIRE_MODERATE = 0.4,
        ABILITY_BEHAVIOR_UNIT_TARGET = 8, DAMAGE_TYPE_MAGICAL = 2,
    }, {__index = _G})
    local usage = setfenv(assert(loadfile('bots/ability_item_usage_generic.lua')), env)()
    local function tick()
        state.orders = {}
        state.time = state.time + 0.25
        usage.ItemUsageThink()
        return state.orders
    end
    local function chase(target)
        for _, enemy in ipairs(enemies) do enemy.hidden, enemy.attacking = false, target end
    end
    return state, bot, ally, enemies, tick, chase, walk, stun, soft, ground, items
end

do
    local state, bot, _, enemies, tick, chase, walk, stun, soft = fixture({'item_dust', 'item_black_king_bar'})
    bot.mods.modifier_silencer_curse_of_the_silent = 6
    enemies[1].hidden = false
    bot.incoming = {{ability = soft, caster = enemies[1], location = pos(60)}}
    assert(#tick() == 0, 'isolated Arcane Curse or a low-impact projectile does not spend BKB')
    bot.incoming = {}
    bot.silenced, bot.retreating = true, true
    bot.mods.modifier_silencer_global_silence = 3
    chase(bot)
    walk.cooldown = 5
    assert(#tick() == 0, 'four physical pursuers alone do not justify BKB without an escape')
    walk.cooldown, state.blocked = 0, true
    assert(#tick() == 0, 'no BKB combo with an unsafe landing')
    state.blocked, state.mana = false, 75
    assert(#tick() == 0, 'reserve the mana needed for Time Walk after activating BKB')
    state.mana = 200
    bot.mods.modifier_item_mask_of_madness_berserk = 2
    assert(#tick() == 0, 'BKB cannot make Time Walk available during Mask of Madness')
    bot.mods.modifier_item_mask_of_madness_berserk = nil
    enemies[1].fading, state.hurt = true, true
    local orders = tick()
    assert(#orders == 2 and orders[1][1] == 'item_black_king_bar' and orders[2][1] == 'faceless_void_time_walk'
        and orders[2][2].x == -650, 'BKB plus safe Time Walk outranks dust in another slot')
    enemies[1].fading = false
    for i, enemy in ipairs(enemies) do enemy.x = 1000 + i * 30 end
    bot.mods.modifier_silencer_global_silence = 0.5
    assert(#tick() == 0, 'wait when silence ends before the pursuers can reach the hero')
    bot.silenced = false
    bot.incoming = {{ability = stun, caster = enemies[1], location = pos(60)}}
    assert(tick()[1][1] == 'item_black_king_bar', 'pre-empt an identified hard stun when a retreat route exists')
    bot.incoming = {}
    enemies[1].x, enemies[1].casting = 450, ability('lion_voodoo', 8, 600, 100)
    assert(tick()[1][1] == 'item_black_king_bar', 'pre-empt a visible, in-range targeted disable without a projectile')
end

do
    local state, bot, ally, enemies, tick, chase = fixture({'item_black_king_bar'})
    chase(ally)
    ally.x, state.backup = -200, true
    state.fighting, state.chronoArea = true, {count = 3, targetloc = pos(500)}
    bot.silenced, bot.attacking = true, enemies[1]
    bot.mods.modifier_silencer_global_silence = 3
    local orders = tick()
    assert(#orders == 2 and orders[2][1] == 'faceless_void_chronosphere', 'counter-initiate through a known silence')
    ally.x = 520
    assert(#tick() == 0, 'hold BKB when the proposed counter-initiation traps a teammate')
end

do
    local _, _, ally, _, tick, chase = fixture({'item_glimmer_cape', 'item_force_staff'})
    chase(ally)
    ally.retreating = true
    assert(tick()[1][1] == 'item_force_staff', 'prefer a safe displacement over concealment')
    ally.direction = 1
    local order = tick()[1]
    assert(order[1] == 'item_glimmer_cape' and order[2] == ally, 'do not push the ally toward the pursuers')
    ally.direction, ally.channeling = -1, true
    ally.mods.modifier_item_glimmer_cape_fade = 0.3
    assert(#tick() == 0, 'hold force on a channeling ally and avoid duplicate glimmer')
    ally.channeling = false
    ally.tower = {x = -400, isTower = true, GetAttackRange = function() return 700 end}
    assert(#tick() == 0, 'reject a landing under an enemy tower')
end

do
    local _, _, ally, _, tick, chase = fixture({'item_caduceus'})
    chase(ally)
    ally.retreating = true
    local order = tick()[1]
    assert(order[1] == 'item_caduceus' and order[2] == ally, 'Caduceus uses the same safe ally push')
    ally.mods.modifier_item_nullifier_mute = 3
    assert(#tick() == 0, 'do not rely on a full Caduceus push when it is reduced by Nullifier')
end

do
    local _, _, ally, enemies, tick, chase, _, stun = fixture({'item_glimmer_cape'})
    ally.retreating, ally.revealed = true, true
    chase(ally)
    assert(#tick() == 0, 'concealment has no value against an existing reveal')
    ally.incoming = {{ability = stun, caster = enemies[1], location = pos(240)}}
    assert(tick()[1][2] == ally, 'the magic barrier can still protect a revealed ally')
end

do
    local _, _, ally, enemies, tick, chase, _, stun, _, ground = fixture({'item_lotus_orb'})
    ally.silenced = true
    ally.mods.modifier_silencer_global_silence = 2
    assert(#tick() == 0, 'hold Lotus when the dispel has no immediate use')
    chase(ally)
    assert(tick()[1][2] == ally, 'dispel a pressured ally')
    ally.silenced = false
    ally.incoming = {{ability = ground, caster = enemies[1], location = pos(230)}}
    assert(#tick() == 0, 'do not reflect an area projectile')
    ally.incoming[1].ability = stun
    assert(tick()[1][2] == ally, 'reflect a legal incoming unit spell')
    ally.mods.modifier_item_sphere_target = 3
    assert(#tick() == 0, 'hold pure reflection if the target already has spell block')
    ally.mods.modifier_item_sphere_target = nil
    ally.mods.modifier_black_king_bar_immune = 3
    assert(#tick() == 0, 'do not add Lotus merely to reflect a stun that BKB already covers')
end

do
    local state, _, ally, enemies, tick = fixture({'item_dust'})
    local enemy = enemies[1]
    enemy.hidden = false
    assert(#tick() == 0)
    enemy.hidden, state.fighting = true, true
    assert(#tick() == 0, 'ordinary disappearance is insufficient evidence for dust')
    enemy.hidden = false
    enemy.mods.modifier_sandking_sand_storm = 3
    assert(#tick() == 0, 'Sand Storm alone is insufficient evidence for dust')
    enemy.mods.modifier_sandking_sand_storm = nil
    enemy.mods.modifier_item_silver_edge = -1
    enemy.mods.modifier_item_invisibility_edge = -1
    enemy.mods.modifier_item_glimmer_cape = -1
    assert(#tick() == 0, 'invisibility item stats do not reveal an active fade or justify dust')
    state.fighting, enemy.hidden, enemy.fading = false, false, true
    assert(#tick() == 0)
    enemy.hidden, state.fighting = true, true
    ally.ohaDustCoverage = {location = pos(50), radius = 1000, untilTime = state.time + 2}
    assert(#tick() == 0, 'do not overlap an allied dust zone')
    ally.ohaDustCoverage = nil
    assert(tick()[1][1] == 'item_dust', 'use a recent observed invisibility transition inside range')
    assert(#tick() == 0, 'do not spend dust twice in the same zone')
end

do
    local state, _, _, enemies, tick = fixture({'item_dust'})
    local enemy = enemies[1]
    enemy.x, enemy.hidden, enemy.fading = 1000, false, true
    assert(#tick() == 0)
    enemy.hidden, state.fighting = true, true
    assert(#tick() == 0, 'hold dust when a vanished target could already be outside its radius')
    enemy.x, enemy.hidden, state.fighting = 500, false, false
    assert(#tick() == 0)
    enemy.hidden, state.fighting, state.time = true, true, state.time + 1
    assert(#tick() == 0, 'forget stale invisibility evidence')
end
do
    local state, bot, _, _, tick = fixture({'item_invis_sword'}, 'npc_dota_hero_drow_ranger')
    bot.retreating = true
    assert(#tick() == 0, 'do not use Shadow Blade merely because retreat mode is active')
    state.reinforcements = true
    assert(tick()[1][1] == 'item_invis_sword', 'use Shadow Blade to leave a visible reinforcement ambush before contact')
end

do
    local state, bot, _, enemies, tick, chase, _, _, _, _, items =
        fixture({'item_hurricane_pike', 'item_invis_sword', 'item_silver_edge'}, 'npc_dota_hero_drow_ranger')
    bot.retreating = true
    bot.mods.modifier_item_invisibility_edge = -1
    bot.mods.modifier_item_silver_edge = -1
    chase(bot)
    assert(tick()[1][1] == 'item_invis_sword', 'Drow starts a retreat with Shadow Blade when Pike has no safe use')
    items.item_invis_sword.cooldown = 20
    enemies[1].x = 300
    assert(#tick() == 0, 'do not issue a second item order while Shadow Blade is fading and the modifier is not visible yet')
    bot.invisible = true
    bot.mods.modifier_item_invisibility_edge_windwalk = 6
    assert(#tick() == 0, 'a safe Pike still should not break effective Shadow Blade invisibility')
    bot.revealed, state.blocked = true, true
    assert(#tick() == 0, 'reject Pike into an unsafe landing even when Drow is revealed')
    state.blocked = false
    local order = tick()[1]
    assert(order[1] == 'item_hurricane_pike' and order[2] == enemies[1], 'allow a safe Pike when Drow is revealed and actively pursued')
end

do
    local _, bot, _, enemies, tick, chase, _, stun =
        fixture({'item_hurricane_pike', 'item_invis_sword', 'item_black_king_bar'}, 'npc_dota_hero_drow_ranger')
    bot.retreating = true
    chase(bot)
    enemies[1].x = 300
    assert(tick()[1][1] == 'item_hurricane_pike', 'take an immediately useful safe Pike before entering stealth')
    bot.mods.modifier_item_silver_edge_windwalk, bot.invisible = 5, true
    bot.incoming = {{ability = stun, caster = enemies[1], location = pos(45)}}
    assert(tick()[1][1] == 'item_black_king_bar', 'break concealment to stop a confirmed hard disable already in flight')
end

do
    local state, bot, ally, enemies, tick = fixture({'item_hurricane_pike'}, 'npc_dota_hero_drow_ranger')
    local enemy = enemies[1]
    state.fighting, bot.attackRange, bot.projectileSpeed, bot.attacking = true, 600, 1250, enemy
    enemy.hidden, enemy.x, enemy.attacking, ally.attacking = false, 300, bot, enemy
    assert(#tick() == 0, 'do not Pike an enemy out of a nearby melee ally attack range')
    ally.attacking = nil
    assert(tick()[1][2] == enemy, 'preserve offensive Pike to space a melee attacker during a ranged duel')
end

do
    local _, _, ally, enemies, tick, chase, _, stun = fixture({'item_glimmer_cape'})
    chase(ally)
    ally.retreating = true
    ally.mods.modifier_item_glimmer_cape = -1
    ally.mods.modifier_item_invisibility_edge_windwalk = 4
    assert(#tick() == 0, 'do not layer Glimmer just for concealment on an ally fading from Shadow Blade')
    ally.incoming = {{ability = stun, caster = enemies[1], location = pos(240)}}
    assert(tick()[1][2] == ally, 'a Glimmer barrier can complement existing concealment')
end

do
    local state, _, ally, _, tick, chase = fixture({'item_force_staff', 'item_caduceus'})
    chase(ally)
    ally.retreating = true
    assert(tick()[1][1] == 'item_force_staff', 'first safe push is selected')
    assert(#tick() == 0, 'do not issue another push while the previous displacement is in progress')
    state.time = state.time + 0.5
    ally.mods.modifier_item_forcestaff_active = 0.1
    assert(#tick() == 0, 'an observed displacement still suppresses a second push after the order window')
end

do
    local state, bot, _, enemies, tick, chase, _, stun = fixture({'item_ghost'})
    chase(bot)
    local enemy = enemies[1]
    state.hp, bot.attacking, bot.hurt, enemy.x = 0.4, enemy, true, 250
    bot.mods.modifier_item_satanic_unholy = 4
    assert(#tick() == 0, 'Ghost Scepter would interrupt a viable Satanic attack')
    bot.mods.modifier_item_satanic_unholy = nil
    bot.incoming = {{ability = stun, caster = enemy, location = pos(45)}}
    assert(#tick() == 0, 'do not increase the danger of a magic projectile using Ghost Scepter')
    bot.incoming = {}
    assert(tick()[1][1] == 'item_ghost', 'Ghost Scepter still answers dangerous physical attacks')
end

do
    local state, bot, ally, enemies, tick = fixture({'item_ethereal_blade'})
    local enemy = enemies[1]
    state.fighting, enemy.hidden, bot.attacking, ally.attacking = true, false, enemy, enemy
    assert(#tick() == 0, 'do not make an enemy immune to the attacks of a nearby ally')
    ally.attacking = nil
    assert(tick()[1][1] == 'item_ethereal_blade', 'use Ethereal Blade when it does not block committed attacks')
end

do
    local state, bot, _, enemies, tick = fixture({'item_satanic'})
    state.hp, enemies[1].hidden = 0.4, false
    bot.mods.modifier_ghost_state = 3
    assert(#tick() == 0, 'do not use Satanic while unable to attack in Ghost Form')
    bot.mods.modifier_ghost_state = nil
    bot.disarmed = true
    assert(#tick() == 0, 'do not use Satanic while disarmed')
    bot.disarmed = false
    assert(tick()[1][1] == 'item_satanic', 'use Satanic when attacks are available again')
end

do
    local state, bot, _, _, tick = fixture({'item_armlet'})
    state.hp, state.hurt, bot.invisible = 0.4, true, true
    bot.mods.modifier_item_invisibility_edge_windwalk = 5
    assert(tick()[1][1] == 'item_armlet', 'Armlet may add temporary health without breaking invisibility in 7.42')
end

print('PASS: combat item timing, concealment, displacement, conflicting effects and cross-slot priority')
