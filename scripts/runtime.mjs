#!/usr/bin/env node
import { installBundle, verifyBundle } from '../lib/runtime.mjs';

try {
  const args = process.argv.slice(2);
  if (args.length > 1 || !['install', 'verify', '--help'].includes(args[0] || '--help')) {
    throw new Error('Usage: electivus-caveman-runtime <install|verify>');
  }
  if (args[0] === 'verify') {
    const result = verifyBundle();
    console.log(`Verified ${Object.keys(result.artifacts).length} bundled Windows x64 executables against the upstream signature (${result.release}).`);
  } else if (args[0] === 'install') {
    const result = installBundle();
    console.log(`Caveman runtime ${result.release}: ${result.installed} executable(s) copied to ${result.binDir}; all six verified. No downloads.`);
    if (result.backup) console.log(`Previous files preserved at ${result.backup}`);
    console.log('Next: caveman setup --json (requires @caveman-ai/cli).');
  } else {
    console.log('Usage: electivus-caveman-runtime <install|verify>\nCopies bundled, signed Caveman binaries locally. No network access.\nDestination: CAVEMAN_HOME/bin or %USERPROFILE%/.caveman/bin.');
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
