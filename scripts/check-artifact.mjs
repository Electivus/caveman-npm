import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const metadata = JSON.parse(readFileSync('dist/artifact.json', 'utf8'));
const pkg = JSON.parse(readFileSync('package.json', 'utf8'));
const files = readdirSync('dist').filter(file => file.endsWith('.tgz'));
if (files.length !== 1 || files[0] !== metadata.filename || metadata.name !== pkg.name || metadata.version !== pkg.version) throw new Error('Unexpected artifact identity');
const actual = 'sha512-' + createHash('sha512').update(readFileSync(join('dist', files[0]))).digest('base64');
if (actual !== metadata.integrity) throw new Error('Tarball SHA-512 differs from the tested artifact');
if (process.env.GITHUB_REF && process.env.GITHUB_REF !== `refs/tags/v${pkg.version}`) throw new Error('Ref does not match package version');
if (process.argv.includes('--registry')) {
  const response = await fetch(`https://registry.npmjs.org/${encodeURIComponent(pkg.name)}/${pkg.version}`, { signal: AbortSignal.timeout(60000) });
  if (!response.ok) throw new Error(`Registry readback returned HTTP ${response.status}`);
  const remote = await response.json();
  if (remote.dist?.integrity !== actual) throw new Error('Published tarball differs from the tested artifact');
  console.log(`Registry confirmed ${pkg.name}@${pkg.version}: ${actual}`);
} else {
  console.log(`Verified release artifact ${pkg.name}@${pkg.version}: ${actual}`);
}
