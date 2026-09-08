import { createHash, createPublicKey, randomUUID, verify } from 'node:crypto';
import { closeSync, copyFileSync, lstatSync, mkdirSync, openSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const binaries = Object.freeze(['caveman-proxy', 'caveman-engine', 'caveman-mcp', 'cavemem', 'caveman-browse', 'caveman-shrink']);
export const release = 'bin-v1.1.6';
export const revision = 'b36219e2b196869100df0d5c29bd57c50d9b906d';
// Pinned independently of the downloaded metadata. Same release key as the
// upstream CLI at the recorded source revision; never learn a key from a server.
const publicKey = '-----BEGIN PUBLIC KEY-----\nMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEKR5zq0dz0mTUtkiX0b6jqtyG3uQV\n89PGD2n9UBV1ikbhu0f1c+vHtcN9mk6wKzyBLdEPudI/Jnvci+8OAen/vw==\n-----END PUBLIC KEY-----\n';
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

function regularFile(path) {
  const stat = lstatSync(path);
  if (stat.isSymbolicLink() || !stat.isFile()) throw new Error(`Refusing non-regular file: ${path}`);
}

function present(path) {
  try { lstatSync(path); return true; }
  catch (error) { if (error.code === 'ENOENT') return false; throw error; }
}

export function verifyBundle(root = packageRoot) {
  const checksums = readFileSync(join(root, 'upstream', 'checksums.txt'));
  const signature = JSON.parse(readFileSync(join(root, 'upstream', 'checksums.txt.keysig'), 'utf8'));
  const message = signature.messageSignature;
  if (signature.mediaType !== 'application/vnd.dev.sigstore.bundle.v0.3+json' ||
      message?.messageDigest?.algorithm !== 'SHA2_256' ||
      message.messageDigest.digest !== createHash('sha256').update(checksums).digest('base64') ||
      !verify('sha256', checksums, createPublicKey(publicKey), Buffer.from(message.signature, 'base64'))) {
    throw new Error('Upstream checksum signature verification failed; nothing installed.');
  }
  const digests = new Map();
  for (const line of checksums.toString('utf8').split('\n').filter(Boolean)) {
    const match = /^([a-f0-9]{64})  ([A-Za-z0-9._-]+)$/.exec(line);
    if (!match || digests.has(match[2])) throw new Error('Invalid or duplicate upstream checksum entry.');
    digests.set(match[2], match[1]);
  }
  const artifacts = {};
  for (const name of binaries) {
    const path = join(root, 'bin', `${name}.exe`);
    regularFile(path);
    const bytes = readFileSync(path);
    const digest = sha256(bytes);
    if (digest !== digests.get(`${name}_win32_amd64`)) throw new Error(`Checksum mismatch: ${name}.exe; nothing installed.`);
    // Validate the actual PE architecture, independently of the filename.
    const pe = bytes.length >= 64 ? bytes.readUInt32LE(60) : -1;
    if (bytes.toString('ascii', 0, 2) !== 'MZ' || pe < 0 || pe + 6 > bytes.length ||
        bytes.readUInt32LE(pe) !== 0x4550 || bytes.readUInt16LE(pe + 4) !== 0x8664) {
      throw new Error(`Not a Windows x64 PE executable: ${name}.exe`);
    }
    artifacts[name] = digest;
  }
  return { release, artifacts };
}

export function cavemanHome(env = process.env) {
  return resolve(env.CAVEMAN_HOME || join(env.USERPROFILE || homedir(), '.caveman'));
}

function ensureDirectory(path) {
  // Check every existing ancestor, including Windows junctions. Do not follow
  // a reparse point into an unexpected installation location.
  let cursor = resolve(path);
  while (true) {
    try {
      const stat = lstatSync(cursor);
      if (stat.isSymbolicLink() || !stat.isDirectory()) throw new Error(`Refusing non-directory or linked installation path: ${cursor}`);
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    const parent = dirname(cursor);
    if (parent === cursor) break;
    cursor = parent;
  }
  mkdirSync(path, { recursive: true });
}

export function installBundle({ root = packageRoot, home = cavemanHome() } = {}) {
  if (process.platform !== 'win32' || process.arch !== 'x64') throw new Error('This package supports Windows x64 only.');
  const manifest = verifyBundle(root); // Verify everything before modifying the destination.
  const binDir = join(resolve(home), 'bin');
  ensureDirectory(binDir);
  const lock = join(binDir, '.electivus-install.lock');
  let lockFd;
  try { lockFd = openSync(lock, 'wx'); }
  catch (error) { throw new Error(`Cannot lock ${lock}. Another installation may be active. If it crashed, remove only this lock and retry.`, { cause: error }); }
  const id = randomUUID();
  const stage = join(binDir, `.electivus-stage-${id}`);
  const backup = join(binDir, `.electivus-backup-${id}`);
  const changed = [];
  const completed = [];
  let keepBackup = false;
  try {
    mkdirSync(stage);
    for (const name of binaries) {
      const filename = `${name}.exe`;
      const target = join(binDir, filename);
      if (present(target)) {
        regularFile(target);
        if (sha256(readFileSync(target)) === manifest.artifacts[name]) continue;
      }
      copyFileSync(join(root, 'bin', filename), join(stage, filename));
      if (sha256(readFileSync(join(stage, filename))) !== manifest.artifacts[name]) throw new Error(`Staged checksum mismatch: ${filename}`);
      changed.push(filename);
    }
    const manifestName = '.bin-manifest.json';
    const manifestBytes = JSON.stringify(manifest, null, 2) + '\n';
    const manifestTarget = join(binDir, manifestName);
    if (present(manifestTarget)) regularFile(manifestTarget);
    if (!present(manifestTarget) || readFileSync(manifestTarget, 'utf8') !== manifestBytes) {
      writeFileSync(join(stage, manifestName), manifestBytes, { flag: 'wx' });
      changed.push(manifestName);
    }
    if (changed.length) mkdirSync(backup);
    for (const filename of changed) {
      const target = join(binDir, filename);
      const prior = present(target);
      if (prior) renameSync(target, join(backup, filename));
      const step = { filename, prior, installed: false };
      completed.push(step);
      renameSync(join(stage, filename), target);
      step.installed = true;
    }
    keepBackup = completed.some(step => step.prior);
    return { release, binDir, installed: changed.filter(name => name.endsWith('.exe')).length, backup: keepBackup ? backup : null };
  } catch (error) {
    const rollbackErrors = [];
    for (const step of completed.reverse()) {
      try {
        const target = join(binDir, step.filename);
        if (step.installed) rmSync(target);
        if (step.prior) renameSync(join(backup, step.filename), target);
      } catch (rollbackError) { rollbackErrors.push(rollbackError.message); }
    }
    keepBackup = rollbackErrors.length > 0;
    throw new Error(`Installation failed: ${error.message}. Close running Caveman processes and retry.${rollbackErrors.length ? ` Rollback incomplete; preserve ${backup}: ${rollbackErrors.join('; ')}` : ' Previous files restored.'}`, { cause: error });
  } finally {
    rmSync(stage, { recursive: true, force: true });
    if (!keepBackup) rmSync(backup, { recursive: true, force: true });
    closeSync(lockFd);
    rmSync(lock);
  }
}
