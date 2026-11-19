-- Enable temporarily for diagnosis, then turn off. Copy to
-- game/dota/scripts/vscripts/game/Customize/decision_trace.lua to
-- keep changes when Workshop updates. Never enable on shared servers.
return {
    Enable = false,
    -- Empty WatchHeroes monitors every bot. Restrict by hero for lower overhead.
    WatchHeroes = {
        "npc_dota_hero_obsidian_destroyer",
        "npc_dota_hero_shadow_demon",
    },
    -- Opt-in for ALL active skill slots of the selected heroes, including
    -- unlearned active skills; avoids manually listing each ability name.
    -- Off by default to minimize console noise and runtime overhead.
    WatchAllActiveAbilities = false,
    WatchAbilities = {
        "obsidian_destroyer_astral_imprisonment",
        "shadow_demon_disruption",
    },
    WatchItems = { "item_cyclone" },
    SampleInterval = 5,   -- minimum game seconds between inventory scans
    ReasonInterval = 12, -- repeated identical reasons are throttled
}
