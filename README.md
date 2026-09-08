# Electivus runtime package for Caveman — Windows x64

Install the six Caveman runtime executables through **npm only**, including on
networks where GitHub release downloads are unavailable. The `.exe` files are
inside the npm tarball. The install script makes **no network requests**, has no
runtime dependencies, and requires no Go compiler or Administrator privileges.

This is an independent Electivus redistribution of unmodified binaries from
[Caveman bin-v1.1.6](https://github.com/JuliusBrussee/caveman/releases/tag/bin-v1.1.6),
not an official or endorsed Caveman distribution channel. Caveman is a trademark
of Julius Brussee. The bundled runtime remains under **BSL 1.1**, including its
Additional Use Grant; it is not relicensed as MIT.

## Install on Windows 11 x64

Requires Node.js 22.13 or newer. Run in PowerShell:

```powershell
npm install -g @caveman-ai/cli@1.3.3 @electivus/caveman-runtime-win32-x64@1.1.6
caveman setup --json
```

If the Caveman CLI is already installed, install only the second package.
`caveman setup --json` should report `ready: true` with all six binary paths.
Do not add `--install`: upstream's `setup --install` can download from GitHub
when its pinned release differs from the installed manifest.

The npm postinstall script verifies the upstream checksum signature and each
executable's SHA-256 and Windows x64 PE header, then installs into:

```text
%USERPROFILE%\.caveman\bin
```

It honors `CAVEMAN_HOME` (destination: `$env:CAVEMAN_HOME\bin`) and writes the
upstream-compatible `.bin-manifest.json`. No PATH or agent settings are changed.
The official CLI already searches this directory. The executables are
`caveman-proxy`, `caveman-engine`, `caveman-mcp`, `cavemem`, `caveman-browse`, and
`caveman-shrink`.

### If npm lifecycle scripts are disabled

```powershell
npm install -g --ignore-scripts @electivus/caveman-runtime-win32-x64@1.1.6
electivus-caveman-runtime install
```

`electivus-caveman-runtime verify` checks the bundled files without installing.
Installation is idempotent. Changed destination files are preserved in a
`.electivus-backup-<id>` directory inside the destination `bin` directory.
Close running Caveman sessions before replacing binaries. Installation failures
restore replaced files; any incomplete rollback reports its backup location.

This package supplies the runtime only. Agent setup, login, browser engines and
provider traffic remain separate operations with their own network needs.

## Offline transfer

On a machine with access to the npm registry:

```powershell
npm pack @electivus/caveman-runtime-win32-x64@1.1.6
```

Transfer the resulting `.tgz` through an approved channel, then:

```powershell
npm install -g --offline --no-audit --no-fund .\electivus-caveman-runtime-win32-x64-1.1.6.tgz
```

The CLI must already be available for `caveman` commands. Neither the offline
install nor its postinstall needs to contact GitHub or npm.

## Origin and licensing

Source revision: `b36219e2b196869100df0d5c29bd57c50d9b906d` in
`JuliusBrussee/caveman`, tag `bin-v1.1.6`. Official CLI tested: `1.3.3`.
The original binaries report `dev` in some version commands; their provenance
is established by the upstream signature, asset digests and embedded clean Git
revision, not by rewriting that version string.

- `upstream/`: original signed checksums, pinned public key, release metadata,
  embedded Go build settings and module inventory.
- `licenses/upstream/`: original BSL terms, licensing guide, trademark policy,
  pixel/font and browser notices.
- `licenses/modules/`: dependency notices from exact Go module archives,
  verified against the `h1:` checksums embedded in the signed executables.
- `licenses/go/`: Go runtime license.
- `LICENSE`: split licensing statement; MIT applies only to Electivus packaging.

## Updating and publishing

See `MAINTAINING.md` included in the package for the reproducible Windows preparation,
offline verification and release steps. Installing an npm update does not run
this preparation process: only maintainers retrieve upstream artifacts.

## Removal and rollback

`npm uninstall -g @electivus/caveman-runtime-win32-x64` removes the npm package
and helper command. It intentionally leaves the installed runtime in
`CAVEMAN_HOME\bin`, since the independent Caveman CLI may still use it.
To remove the runtime, close Caveman sessions and delete only the six listed
executables and `.bin-manifest.json` from that directory. Keep databases,
credentials and other Caveman data. To roll back an update, restore the files
from the backup directory printed by the installer.
