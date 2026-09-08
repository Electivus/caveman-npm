# Releases

## 1.1.7

- Publish through the protected GitHub Actions environment using npm trusted
  publishing (OIDC) and provenance, without a stored npm token.
- Include CodeQL setup in the reproducible repository configuration.
- Resolve the offline smoke-test tarball from its verified artifact manifest,
  so package updates do not need to edit the workflow filename.
- Runtime remains the six unmodified upstream `bin-v1.1.6` Windows x64 binaries.

## 1.1.6 — initial package registration

First complete Windows x64 bundle, including all six executables, upstream
signature verification, rollback-safe local installation and third-party notices.

The first version was published with the maintainer's local npm login because
npm requires an existing package before it allows trusted publishing to be
configured. No login token was stored in GitHub. This initial version does not
claim npm provenance. Its exact tarball was produced and tested by
[Windows CI run 34262561237](https://github.com/Electivus/caveman-npm/actions/runs/34262561237)
at source revision `13334764a33476a8c9d4ad1284d35abb2cec7749`.

Verified npm integrity:

```text
sha512-BaGYKfftPPubLnBzTwC7rXP6GjJjDd4uNxAdHvNm63pfk7VDkhLiO0sraxH6EVTpi7KWq3p9k9tweNKyg6ym0w==
```
