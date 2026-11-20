#!/usr/bin/env node
'use strict';

const { readdirSync } = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const root = path.resolve(__dirname, '..');
const compiler = process.env.LUAC || 'luac5.1';
const interpreter = process.env.LUA || 'lua5.1';

function run(bin, args) {
    const result = spawnSync(bin, args, { cwd: root, encoding: 'utf8', windowsHide: true });
    if (result.error) throw new Error(`${bin}: ${result.error.message}`);
    return result;
}

function requireLua51(bin) {
    const result = run(bin, ['-v']);
    if (result.status !== 0 || !/\bLua 5\.1(?:\.\d+)?\b/.test(result.stdout + result.stderr)) {
        throw new Error(`${bin} must be Lua 5.1 (set LUA and LUAC to the right executables).`);
    }
}

function luaFiles(dir) {
    return readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap(entry => {
        const filename = path.join(dir, entry.name);
        if (entry.isDirectory()) return luaFiles(filename);
        return entry.isFile() && entry.name.endsWith('.lua') ? [filename] : [];
    }).sort();
}

try {
    requireLua51(compiler);
    requireLua51(interpreter);
    const tests = luaFiles('tests');
    const files = [...luaFiles('bots'), ...luaFiles('game'), ...tests];
    const failures = [];
    for (const file of files) {
        const result = run(compiler, ['-p', file]);
        if (result.status !== 0) failures.push(result.stderr.trim() || file);
    }
    if (failures.length) throw new Error(failures.join('\n'));
    console.log(`PASS: ${files.length} files parsed by Lua 5.1.`);

    // Run only explicit test entry points; a Lua helper is not a test program.
    for (const file of tests.filter(file => path.basename(file).startsWith('test_'))) {
        const result = run(interpreter, [file]);
        if (result.stdout) process.stdout.write(result.stdout);
        if (result.stderr) process.stderr.write(result.stderr);
        if (result.status !== 0) throw new Error(`Lua regression failed: ${file}`);
    }
} catch (error) {
    console.error(`FAIL: ${error.message}`);
    process.exitCode = 1;
}
