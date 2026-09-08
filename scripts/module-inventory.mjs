import { readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { binaries, packageRoot, revision, verifyBundle } from '../lib/runtime.mjs';

verifyBundle();
const modules = new Map();
const buildInfo = {};
for (const name of binaries) {
  const bytes = readFileSync(join(packageRoot, 'bin', `${name}.exe`));
  const offset = bytes.indexOf(Buffer.from('\xff Go buildinf:', 'latin1'));
  if (offset < 0 || !(bytes[offset + 15] & 2)) throw new Error(`Unsupported Go build-info format: ${name}`);
  let cursor = offset + 32;
  function string() {
    let size = 0;
    let shift = 0;
    let byte;
    do {
      byte = bytes[cursor++];
      if (byte === undefined || shift > 28) throw new Error('Invalid build-info string');
      size += (byte & 127) * 2 ** shift;
      shift += 7;
    } while (byte & 128);
    const result = bytes.subarray(cursor, cursor + size);
    cursor += size;
    return result;
  }
  const goVersion = string().toString('utf8');
  const raw = string();
  const lines = raw.subarray(16, -16).toString('utf8').split('\n');
  const settings = Object.fromEntries(lines.filter(line => line.startsWith('build\t')).map(line => {
    const [key, ...value] = line.slice(6).split('=');
    return [key, value.join('=')];
  }));
  if (settings['vcs.revision'] !== revision || settings['vcs.modified'] !== 'false' || settings.GOOS !== 'windows' || settings.GOARCH !== 'amd64') {
    throw new Error(`Unexpected source revision or target in ${name}`);
  }
  buildInfo[name] = { goVersion, settings };
  for (const line of lines.filter(line => line.startsWith('dep\t'))) {
    const [, module, version, sum] = line.split('\t');
    const existing = modules.get(module);
    if (existing && (existing.version !== version || existing.sum !== sum)) throw new Error(`Conflicting dependency: ${module}`);
    modules.set(module, { name: module, version, sum });
  }
}
writeFileSync(join(packageRoot, 'upstream/go-modules.json'), JSON.stringify([...modules.values()].sort((a, b) => a.name.localeCompare(b.name)), null, 2) + '\n');
writeFileSync(join(packageRoot, 'upstream/build-info.json'), JSON.stringify(buildInfo, null, 2) + '\n');
console.log(`Recorded the embedded build metadata and ${modules.size} dependency versions from the six signed executables.`);
