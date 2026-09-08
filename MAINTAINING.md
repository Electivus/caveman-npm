# Maintainer guide (Windows / PowerShell)

The npm tarball carries all six original Windows x64 executables. This Git
repository carries the packaging, signed upstream metadata, licenses and tests.
Executables and `.tgz` files are excluded from Git. Do not substitute a local
build, modify executable bytes, or remove signature verification.

## Reproduce 1.1.6

Use a clone of `JuliusBrussee/caveman` or an unchanged fork that contains tag
`bin-v1.1.6`, source revision `b36219e2b196869100df0d5c29bd57c50d9b906d`.
Requires PowerShell 7.4+, Node.js 22.13+, npm, Git, and authenticated GitHub CLI.
No Administrator access or Go compiler is required.

```powershell
.\scripts\Prepare-Package.ps1 -SourceRepo C:\Users\you\git\caveman
npm test
New-Item -ItemType Directory -Force .\dist | Out-Null
.\scripts\Pack-Package.ps1
.\scripts\Smoke-Package.ps1 -Tarball .\dist\electivus-caveman-runtime-win32-x64-1.1.6.tgz
```

The preparation script downloads official release assets on the maintainer
machine. If those executables are already available through an approved channel,
add `-BinaryDirectory C:\path\to\verified-binaries`. Their hashes must still
match the official GitHub release and the signed checksum manifest. No checks are
relaxed for local inputs. Small upstream manifests are downloaded in either case.

It extracts source notices from the exact pinned Git commit. Go module notices
come from cached module ZIPs or `proxy.golang.org`; their `h1:` checksums are
recomputed and compared with the metadata inside the signed binaries. Corporate
TLS verification remains enabled through PowerShell's normal certificate trust.

`Smoke-Package.ps1` requires the official Caveman CLI on PATH. It installs the
packed artifact into a fresh temporary npm prefix with an empty cache,
`--offline`, and an unavailable registry. It sets a temporary `CAVEMAN_HOME`,
checks all six resolved paths, and runs the installed proxy. It leaves isolated
artifacts under the printed Windows temporary directory for inspection. Existing
user binaries and configuration are not touched.

## Publish through protected GitHub Actions

The public repository is `Electivus/caveman-npm`. Submit packaging changes by
pull request and wait for the required Windows verification check before merging.
Create `v<package.json version>` on a tested `main` commit. The tag triggers
`.github/workflows/release.yml`, which checks main ancestry, runs the Windows
pipeline, and passes its exact tarball to the npm publishing job.

Approve the `npm-publish` GitHub environment deployment. The publishing job
exchanges a short-lived GitHub OIDC identity with npm, publishes with provenance,
compares registry integrity with the tested tarball, and attaches the artifact
to a GitHub release. It never rebuilds or repacks in the publish job.

Configure npm trusted publishing once, as an organization package owner:

```powershell
npm whoami
npm org ls electivus
npm trust github @electivus/caveman-runtime-win32-x64 --repository Electivus/caveman-npm --file release.yml --environment npm-publish --allow-publish
npm view @electivus/caveman-runtime-win32-x64@1.1.6 dist.integrity dist.tarball
```

Finish npm's browser / two-factor confirmation if requested. Never put tokens,
OTP codes, `.npmrc`, or local credentials in this repository. Publishing requires
an npm organization role that can publish packages under `@electivus`.

If npm requires the package to exist before a trusted publisher can be registered,
the first release needs a one-time authenticated bootstrap. Use the exact
Windows-CI-tested tarball, then configure OIDC for subsequent releases. Do not
store the maintainer's login token in Actions. Record any bootstrap exception in
the release notes; do not claim it has CI provenance.

Install the published registry artifact into another isolated prefix with a fresh
npm cache and `CAVEMAN_HOME`, then repeat runtime and CLI discovery checks. Compare
the registry's SHA-512 integrity with the exact tarball verified before publish.
The release workflow attaches the tarball to the corresponding GitHub release.

## Update policy

Package `1.1.6` contains upstream `bin-v1.1.6`. For a new upstream binary release,
review and update the tag and source revision in `lib/runtime.mjs` and
`scripts/Prepare-Package.ps1`, the package version, and the README. The public key
is pinned independently; any upstream key rotation needs explicit source review.
Refresh notices from the new source and linked module versions. Delete obsolete
license entries deliberately when modules disappear; never carry an unverified
binary from the previous release.

For packaging-only changes to the same binaries, use the next available patch
package version and clearly keep the upstream release separate in documentation.
Do not overwrite an npm version or a GitHub release asset. There is no scheduled
upstream update. npm publishing runs only for an explicit version tag or a manual
release workflow dispatched against that same version tag.

Windows ARM64, macOS and Linux require separate packages and validation. This
package declares `os: win32` and `cpu: x64` and checks both again at installation.
