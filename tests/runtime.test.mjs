import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { binaries, installBundle, packageRoot, release, verifyBundle } from '../lib/runtime.mjs';

function scratch(t) {
  const dir = mkdtempSync(join(tmpdir(), 'electivus-caveman-test-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

function fakeBundle(t) {
  const root = scratch(t);
  mkdirSync(join(root, 'upstream'));
  mkdirSync(join(root, 'bin'));
  for (const file of ['checksums.txt', 'checksums.txt.keysig']) copyFileSync(join(packageRoot, 'upstream', file), join(root, 'upstream', file));
  return root;
}

test('all six real PE executables match the original signed release', () => {
  const result = verifyBundle();
  assert.equal(result.release, release);
  assert.deepEqual(Object.keys(result.artifacts), binaries);
});

test('tampered signed manifest and executable fail before creating an installation', t => {
  const root = fakeBundle(t);
  const home = join(root, 'destination');
  writeFileSync(join(root, 'bin', 'caveman-proxy.exe'), 'corrupt');
  assert.throws(() => installBundle({ root, home }), /Checksum mismatch/);
  assert.equal(existsSync(home), false);
  writeFileSync(join(root, 'upstream', 'checksums.txt'), 'corrupt manifest');
  assert.throws(() => installBundle({ root, home }), /signature verification failed/);
  assert.equal(existsSync(home), false);
});

test('real install preserves previous files, writes the CLI manifest, and is idempotent', t => {
  const home = scratch(t);
  mkdirSync(join(home, 'bin'));
  writeFileSync(join(home, 'bin', 'caveman-proxy.exe'), 'previous binary');
  writeFileSync(join(home, 'credentials'), 'unrelated user data');
  const first = installBundle({ home });
  assert.equal(first.installed, 6);
  assert.equal(readFileSync(join(first.backup, 'caveman-proxy.exe'), 'utf8'), 'previous binary');
  assert.deepEqual(JSON.parse(readFileSync(join(home, 'bin', '.bin-manifest.json'), 'utf8')), verifyBundle());
  assert.equal(readFileSync(join(home, 'credentials'), 'utf8'), 'unrelated user data');
  const second = installBundle({ home });
  assert.equal(second.installed, 0);
  assert.equal(second.backup, null);
  const version = spawnSync(join(home, 'bin', 'caveman-proxy.exe'), ['version', '--json'], { encoding: 'utf8', timeout: 15000 });
  assert.equal(version.status, 0, version.stderr);
  assert.ok(JSON.parse(version.stdout).capabilities.includes('native_runtime_v1'));
});

test('a Windows junction cannot redirect the installer outside its destination', t => {
  const home = scratch(t);
  const outside = scratch(t);
  symlinkSync(outside, join(home, 'bin'), 'junction');
  assert.throws(() => installBundle({ home }), /linked installation path/);
  assert.deepEqual(readdirSync(outside), []);
});

test('locked Windows binary rolls back files already replaced', async t => {
  const home = scratch(t);
  const binDir = join(home, 'bin');
  mkdirSync(binDir);
  for (const name of binaries) writeFileSync(join(binDir, `${name}.exe`), `previous ${name}`);
  const lockScript = join(home, 'hold-lock.ps1');
  writeFileSync(lockScript, '$stream = [IO.File]::Open($args[0], [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)\ntry { [Console]::WriteLine("locked"); [Console]::Out.Flush(); [Console]::ReadLine() | Out-Null } finally { $stream.Dispose() }\n');
  const child = spawn('pwsh', ['-NoProfile', '-File', lockScript, join(binDir, 'caveman-engine.exe')], { stdio: ['pipe', 'pipe', 'pipe'] });
  t.after(() => { if (child.exitCode === null) child.kill(); });
  await new Promise((resolve, reject) => {
    child.stdout.once('data', resolve);
    child.once('error', reject);
    child.once('exit', code => reject(new Error(`lock helper exited ${code}`)));
  });
  try {
    assert.throws(() => installBundle({ home }), /Installation failed/);
  } finally {
    child.stdin.end('\n');
    await new Promise(resolve => child.once('exit', resolve));
  }
  for (const name of binaries) assert.equal(readFileSync(join(binDir, `${name}.exe`), 'utf8'), `previous ${name}`);
  assert.equal(existsSync(join(binDir, '.bin-manifest.json')), false);
  assert.equal(existsSync(join(binDir, '.electivus-install.lock')), false);
  assert.ok(!readdirSync(binDir).some(name => name.startsWith('.electivus-stage-')));
});
