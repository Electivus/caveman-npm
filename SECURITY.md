# Security policy

Report packaging vulnerabilities privately through GitHub's **Report a
vulnerability** action for this repository. Do not include npm credentials,
provider keys or user traffic in a public issue. For vulnerabilities in the
underlying runtime, use the upstream Caveman security contact as well.

## Trust boundary

This repository redistributes exact upstream artifacts. An npm release must:

1. Match the upstream checksum manifest signed by the independently pinned key.
2. Match the clean source revision embedded in each Windows x64 executable.
3. Include upstream and third-party license notices from verified source inputs.
4. Pass Windows tests and a real offline install of the final npm tarball.
5. Publish that exact tarball, checked by SHA-512 before and after publication.

Publication uses GitHub OIDC for this repository, `release.yml`, and the
`npm-publish` environment. No persistent npm token is stored in Actions.
The publish job alone receives `id-token: write`; GitHub release creation uses
a separate job with `contents: write`. Third-party Actions are pinned by full
commit SHA. Pull requests never receive npm publishing permissions.
CodeQL default setup scans JavaScript/TypeScript and Actions workflows; secret
scanning, push protection, dependency alerts and private vulnerability reporting
are enabled. GitHub maintains CodeQL's automatic scan schedule.

`main` requires a pull request and the Windows verification check. Force pushes
and branch/tag deletion are blocked by repository rules. Release tags must
match `package.json` and point to a commit on `main`. The protected npm
environment requires maintainer approval. Repository settings, npm trust and
actual CI results remain authoritative; these statements describe the intended
controls and must be checked during each release.

This package has no JavaScript runtime dependencies. The bundled Go programs
have their own dependencies, recorded under `upstream/`; no claim is made that
their upstream code is free of vulnerabilities. Monitor upstream releases and
advisories, then refresh the signed runtime through the documented process.
