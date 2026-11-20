#!/usr/bin/env node
'use strict';

// Patch 7.42: default hero builds must not buy these unreviewed Aghanim upgrades.
// To restore a purchase, first update the policy and the review note:
// docs/AGHANIMS_DEFERRED_7_42.md
// This deliberately does not override user Customize/hero build preferences.
const fs = require('node:fs');
const path = require('node:path');

const deferredScepters = [
    'abaddon', 'beastmaster', 'death_prophet', 'juggernaut',
    'life_stealer', 'lone_druid', 'meepo', 'morphling',
    'pugna', 'sand_king', 'weaver',
];

const deferredShards = [
    'dazzle', 'death_prophet', 'disruptor', 'meepo',
    'monkey_king', 'undying',
];

const root = path.resolve(__dirname, '..');
const errors = [];
const heroes = [...new Set([...deferredScepters, ...deferredShards])].sort();

for (const hero of heroes) {
    const filename = path.join(root, 'bots', 'BotLib', 'hero_' + hero + '.lua');
    const src = fs.readFileSync(filename, 'utf8');
    const start = src.search(/local sRoleItemsBuyList\s*=\s*\{\s*\}/);
    const end = src.search(/X\[['"]sBuyList['"]\]\s*=/);

    if (start < 0 || end <= start) {
        errors.push(hero + ': unable to locate default hero purchase lists');
        continue;
    }

    // Only check the default build definitions; sell lists, debug comments and
    // user-defined overrides are intentionally outside the policy scope.
    const activeBuild = src.slice(start, end)
        .split(/\r?\n/)
        .map(line => line.replace(/--.*$/, ''))
        .join('\n');

    const blocked = [];
    if (deferredScepters.includes(hero)) {
        blocked.push('item_ultimate_scepter', 'item_ultimate_scepter_2');
    }
    if (deferredShards.includes(hero)) {
        blocked.push('item_aghanims_shard');
    }
    for (const item of blocked) {
        if (activeBuild.includes("'" + item + "'") ||
            activeBuild.includes('"' + item + '"')) {
            errors.push(hero + ': still purchases ' + item);
        }
    }
}

if (errors.length > 0) {
    for (const error of errors) console.error('FAIL ' + error);
    process.exitCode = 1;
} else {
    console.log('PASS: deferred Aghanim purchases absent from ' +
        heroes.length + ' default hero builds (' +
        deferredScepters.length + ' Scepter, ' +
        deferredShards.length + ' Shard).');
}
