[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$SourceRepo,
  [string]$BinaryDirectory
)
$ErrorActionPreference = 'Stop'
$PackageRoot = Split-Path -Parent $PSScriptRoot
$Release = 'bin-v1.1.6'
$Revision = 'b36219e2b196869100df0d5c29bd57c50d9b906d'
$Utf8 = [Text.UTF8Encoding]::new($false)

function Write-Utf8([string]$Path, [string]$Text) {
  New-Item -ItemType Directory -Path (Split-Path -Parent $Path) -Force | Out-Null
  [IO.File]::WriteAllText($Path, $Text, $Utf8)
}
function Export-SourceFile([string]$Source, [string]$Destination) {
  $Content = & git -C $SourceRepo show "${Revision}:$Source"
  if ($LASTEXITCODE -ne 0) { throw "Cannot read $Source at $Revision" }
  Write-Utf8 $Destination (($Content -join "`n") + "`n")
}

$TagRevision = & git -C $SourceRepo rev-list -n 1 $Release
if ($LASTEXITCODE -ne 0 -or $TagRevision -ne $Revision) { throw "Source tag does not match pinned revision $Revision" }
$ReleaseJson = & gh api "repos/JuliusBrussee/caveman/releases/tags/$Release"
if ($LASTEXITCODE -ne 0) { throw 'Cannot read upstream release metadata' }
$Metadata = $ReleaseJson | ConvertFrom-Json
if ($Metadata.tag_name -ne $Release -or $Metadata.draft -or $Metadata.prerelease) { throw 'Unexpected upstream release' }
New-Item -ItemType Directory -Force -Path (Join-Path $PackageRoot 'upstream'), (Join-Path $PackageRoot 'bin') | Out-Null
$SelectedAssets = @($Metadata.assets | Where-Object { $_.name -match '_win32_amd64$|^checksums\.txt(\.keysig)?$' })
if ($SelectedAssets.Count -ne 8) { throw 'Expected six Windows x64 assets and two signature files' }
foreach ($Asset in $SelectedAssets) {
  if ($Asset.digest -notmatch '^sha256:[a-f0-9]{64}$') { throw "Missing upstream digest for $($Asset.name)" }
  if ($Asset.name -like '*_win32_amd64') {
    $Filename = $Asset.name.Replace('_win32_amd64', '.exe')
    $Destination = Join-Path $PackageRoot "bin/$Filename"
    if ($BinaryDirectory) {
      Copy-Item -LiteralPath (Join-Path $BinaryDirectory $Filename) -Destination $Destination
    } else {
      Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $Destination -TimeoutSec 300 -MaximumRetryCount 3 -RetryIntervalSec 5
    }
  } else {
    $Destination = Join-Path $PackageRoot "upstream/$($Asset.name)"
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $Destination -TimeoutSec 60 -MaximumRetryCount 3 -RetryIntervalSec 5
  }
  $Actual = 'sha256:' + (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($Actual -ne $Asset.digest) { throw "GitHub asset digest mismatch: $($Asset.name)" }
}
$Provenance = [ordered]@{
  repository = 'https://github.com/JuliusBrussee/caveman'
  release = $Release
  sourceRevision = $Revision
  publishedAt = $Metadata.published_at
  url = $Metadata.html_url
  assets = @($SelectedAssets | Select-Object name, size, digest, browser_download_url)
}
Write-Utf8 (Join-Path $PackageRoot 'upstream/release.json') (($Provenance | ConvertTo-Json -Depth 5) + "`n")
foreach ($Source in @('LICENSE','LICENSE.BSL','LICENSING.md','TRADEMARKS.md','browse/NOTICE','engine/pixel/NOTICE','engine/pixel/assets/SPLEEN_LICENSE.txt','engine/pixel/assets/UNIFONT_LICENSE.txt')) {
  Export-SourceFile $Source (Join-Path $PackageRoot "licenses/upstream/$Source")
}
Export-SourceFile 'packages/cli/BINARY_SIGNING_PUBKEY.pub' (Join-Path $PackageRoot 'upstream/release-key.pub')
& node (Join-Path $PSScriptRoot 'runtime.mjs') verify
if ($LASTEXITCODE -ne 0) { throw 'Upstream signature or executable verification failed' }
& node (Join-Path $PSScriptRoot 'module-inventory.mjs')
if ($LASTEXITCODE -ne 0) { throw 'Go module inventory failed' }
& (Join-Path $PSScriptRoot 'Collect-Licenses.ps1')
Write-Host 'Package inputs prepared and verified. Run npm test, then npm pack.'
