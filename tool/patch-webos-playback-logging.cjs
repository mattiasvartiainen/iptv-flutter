'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { fileURLToPath, pathToFileURL } = require('node:url');

const pin = '3a742bb86b04e261044f0864f9b1f71acf0bbad3';
const packagePath = 'packages/video_player_drm';
const logPath = `${packagePath}/webos/log.cc`;
const originalDestructor = `Log::~Log() {
  init();
  logCb_(level_,tag_.c_str(),out_.str().c_str());
}`;
const safeDestructor = `Log::~Log() {
  // Plugin messages may contain stream URLs, credentials or media events.
}`;

function git(repo, ...args) {
  return execFileSync('git', ['-C', repo, ...args], {
    encoding: 'utf8',
    maxBuffer: 16 * 1024 * 1024,
  });
}

function blobHash(data) {
  return crypto.createHash('sha1')
    .update(`blob ${data.length}\0`)
    .update(data)
    .digest('hex');
}

function safeLogSource(original) {
  const first = original.indexOf(originalDestructor);
  if (first < 0 || first !== original.lastIndexOf(originalDestructor)) {
    throw new Error('unexpected native logging implementation');
  }
  return original.replace(originalDestructor, safeDestructor);
}

function patchPlugin(repo, ref) {
  if (git(repo, 'rev-parse', 'HEAD').trim() !== ref) {
    throw new Error('plugin checkout does not match the pinned commit');
  }
  const tree = git(repo, 'ls-tree', '-r', '-z', ref, '--', packagePath);
  const entries = tree.split('\0').filter(Boolean).map((entry) => {
    const match = /^(100644|100755) blob ([0-9a-f]{40})\t(.+)$/.exec(entry);
    if (!match) throw new Error('unexpected plugin tree entry');
    return { hash: match[2], file: match[3] };
  });
  if (!entries.some((entry) => entry.file === logPath)) {
    throw new Error('native logging source is absent from the pinned tree');
  }

  const original = git(repo, 'show', `${ref}:${logPath}`);
  const patched = safeLogSource(original);
  const repoReal = fs.realpathSync(repo);
  const expectedFiles = new Set(entries.map((entry) => entry.file));
  function checkUnexpectedFiles(directory, relative) {
    for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
      const file = `${relative}/${entry.name}`;
      const filename = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        checkUnexpectedFiles(filename, file);
      } else if (!expectedFiles.has(file)) {
        throw new Error(`unexpected plugin source: ${file}`);
      }
    }
  }
  checkUnexpectedFiles(path.join(repo, ...packagePath.split('/')), packagePath);
  for (const { file, hash } of entries) {
    const filename = path.join(repo, ...file.split('/'));
    const real = fs.realpathSync(filename);
    if (!real.startsWith(repoReal + path.sep)) {
      throw new Error(`plugin file escapes its isolated checkout: ${file}`);
    }
    const data = fs.readFileSync(filename);
    if (blobHash(data) !== hash &&
        !(file === logPath && data.equals(Buffer.from(patched)))) {
      throw new Error(`plugin source differs from pinned commit: ${file}`);
    }
  }
  fs.writeFileSync(path.join(repo, ...logPath.split('/')), patched);
}

function main() {
  const project = fs.realpathSync(process.cwd());
  const cache = path.join(project, '.dart_tool', 'webos-pub-cache');
  if (!process.env.PUB_CACHE ||
      path.resolve(process.env.PUB_CACHE) !== cache ||
      fs.realpathSync(cache) !== cache) {
    throw new Error('PUB_CACHE is not the isolated webOS build cache');
  }
  const configPath = path.join(project, '.dart_tool', 'package_config.json');
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const plugin = config.packages.find((entry) => entry.name === 'video_player_drm');
  if (!plugin) throw new Error('video_player_drm is absent from package config');
  const root = fs.realpathSync(fileURLToPath(new URL(plugin.rootUri, pathToFileURL(configPath))));
  if (!root.startsWith(cache + path.sep)) {
    throw new Error('resolved plugin is outside the isolated webOS cache');
  }
  const repo = fs.realpathSync(git(root, 'rev-parse', '--show-toplevel').trim());
  if (!repo.startsWith(cache + path.sep) ||
      root !== path.join(repo, ...packagePath.split('/'))) {
    throw new Error('unexpected resolved plugin checkout');
  }
  patchPlugin(repo, pin);
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(`[build-webos] ERROR: ${error.message}`);
    process.exitCode = 1;
  }
}

module.exports = { blobHash, patchPlugin, safeLogSource };
