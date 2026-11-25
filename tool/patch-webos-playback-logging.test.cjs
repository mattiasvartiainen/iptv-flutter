'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');
const { fileURLToPath, pathToFileURL } = require('node:url');
const test = require('node:test');
const { patchPlugin, safeLogSource } = require('./patch-webos-playback-logging.cjs');

const pin = '3a742bb86b04e261044f0864f9b1f71acf0bbad3';
const project = process.cwd();
const config = JSON.parse(fs.readFileSync('.dart_tool/package_config.json', 'utf8'));
const entry = config.packages.find((p) => p.name === 'video_player_drm');
const plugin = fileURLToPath(new URL(entry.rootUri, pathToFileURL(path.resolve('.dart_tool/package_config.json'))));
const sourceRepo = execFileSync('git', ['-C', plugin, 'rev-parse', '--show-toplevel'], { encoding: 'utf8' }).trim();
const helper = path.resolve('tool/patch-webos-playback-logging.cjs');

test('isolated build verifies the pinned checkout and disables all plugin logging', async () => {
  const scratch = fs.mkdtempSync(path.join(project, '.dart_tool', 'webos-patch-test-'));
  try {
    const cache = path.join(scratch, '.dart_tool', 'webos-pub-cache');
    const repo = path.join(cache, 'git', `plugins-${pin}`);
    fs.mkdirSync(path.dirname(repo), { recursive: true });
    execFileSync('git', ['clone', '--quiet', '--shared', '--no-checkout', '-c', 'core.autocrlf=false', sourceRepo, repo]);
    execFileSync('git', ['-C', repo, 'sparse-checkout', 'set', 'packages/video_player_drm']);
    execFileSync('git', ['-C', repo, 'checkout', '--quiet', '--detach', pin]);
    const log = path.join(repo, 'packages', 'video_player_drm', 'webos', 'log.cc');
    const sourceLog = path.join(sourceRepo, 'packages', 'video_player_drm', 'webos', 'log.cc');
    const original = fs.readFileSync(log, 'utf8');
    const sourceBefore = fs.readFileSync(sourceLog);
    const pluginRoot = path.join(repo, 'packages', 'video_player_drm');
    fs.writeFileSync(path.join(scratch, '.dart_tool', 'package_config.json'), JSON.stringify({
      configVersion: 2,
      packages: [{ name: 'video_player_drm', rootUri: pathToFileURL(pluginRoot).href }],
    }));
    const run = (pubCache) => spawnSync(process.execPath, [helper], {
      cwd: scratch, env: { ...process.env, PUB_CACHE: pubCache }, encoding: 'utf8',
    });

    assert.notEqual(run(path.dirname(cache)).status, 0);
    assert.equal(fs.readFileSync(log, 'utf8'), original);
    const result = run(cache);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(fs.readFileSync(log, 'utf8'), safeLogSource(original));
    assert.deepEqual(fs.readFileSync(sourceLog), sourceBefore);
    assert.equal(run(cache).status, 0);

    const unexpected = path.join(pluginRoot, 'webos', 'unexpected.h');
    fs.writeFileSync(unexpected, 'unexpected source');
    assert.notEqual(run(cache).status, 0);
    fs.unlinkSync(unexpected);
    const nativeFile = path.join(pluginRoot, 'webos', 'video_player.cc');
    fs.appendFileSync(nativeFile, '\n// unexpected change\n');
    assert.notEqual(run(cache).status, 0);
    assert.throws(() => patchPlugin(repo, '0000000000000000000000000000000000000000'), /pinned commit/);
    fs.writeFileSync(nativeFile, execFileSync('git', ['-C', repo, 'show', `${pin}:packages/video_player_drm/webos/video_player.cc`]));
    fs.writeFileSync(log, 'modified native logging');
    assert.notEqual(run(cache).status, 0);
    assert.equal(fs.readFileSync(log, 'utf8'), 'modified native logging');
    assert.throws(() => safeLogSource('changed logging implementation'));
  } finally {
    await fs.promises.rm(scratch, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 });
  }
});
