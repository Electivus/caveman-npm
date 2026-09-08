[CmdletBinding()]
param([Parameter(Mandatory)][string]$Tarball)
$ErrorActionPreference = 'Stop'
$ResolvedTarball = (Resolve-Path -LiteralPath $Tarball).Path
$SmokeRoot = Join-Path ([IO.Path]::GetTempPath()) ('electivus-caveman-smoke-' + [Guid]::NewGuid().ToString('N'))
$Prefix = Join-Path $SmokeRoot 'npm'
$RuntimeHome = Join-Path $SmokeRoot 'runtime'
$Cache = Join-Path $SmokeRoot 'empty-cache'
New-Item -ItemType Directory -Path $SmokeRoot | Out-Null
$PreviousCavemanHome = $env:CAVEMAN_HOME
try {
  $env:CAVEMAN_HOME = $RuntimeHome
  # Empty npm cache, offline mode, and an unusable registry. There is no
  # registry or GitHub fallback; postinstall must use the tarball's payload.
  & npm install --global --prefix $Prefix --cache $Cache --offline --registry http://127.0.0.1:9 --no-audit --no-fund --foreground-scripts $ResolvedTarball
  if ($LASTEXITCODE -ne 0) { throw 'Offline npm install failed' }
  & node (Join-Path $Prefix 'node_modules/@electivus/caveman-runtime-win32-x64/scripts/runtime.mjs') verify
  if ($LASTEXITCODE -ne 0) { throw 'Installed npm bundle failed verification' }
  $Proxy = Join-Path $RuntimeHome 'bin/caveman-proxy.exe'
  $Version = & $Proxy version --json | ConvertFrom-Json
  if ($LASTEXITCODE -ne 0 -or $Version.capabilities -notcontains 'native_runtime_v1') { throw 'Installed proxy failed the runtime capability probe' }
  $SetupJson = & caveman setup --json
  if ($LASTEXITCODE -ne 0) { throw 'Caveman CLI rejected the installed runtime' }
  $Setup = $SetupJson | ConvertFrom-Json
  if (-not $Setup.ready -or $Setup.binaries.Count -ne 6) { throw 'Caveman setup did not find six executables' }
  foreach ($Binary in $Setup.binaries) {
    if (-not $Binary.path.StartsWith($RuntimeHome, [StringComparison]::OrdinalIgnoreCase)) { throw "CLI resolved an existing binary outside the isolated installation: $($Binary.name)" }
  }
  Write-Host "PASS: offline tarball install, six signed binaries, proxy capability, and CLI discovery. Artifacts: $SmokeRoot"
} finally {
  $env:CAVEMAN_HOME = $PreviousCavemanHome
}
