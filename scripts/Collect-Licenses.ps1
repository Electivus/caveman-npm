[CmdletBinding()]
param([string]$ModuleCache = (Join-Path $env:USERPROFILE 'go/pkg/mod/cache/download'))
$ErrorActionPreference = 'Stop'
$PackageRoot = Split-Path -Parent $PSScriptRoot
$Modules = Get-Content -LiteralPath (Join-Path $PackageRoot 'upstream/go-modules.json') -Raw | ConvertFrom-Json
$BuildInfo = Get-Content -LiteralPath (Join-Path $PackageRoot 'upstream/build-info.json') -Raw | ConvertFrom-Json
$GoVersion = $BuildInfo.'caveman-proxy'.goVersion
$Cache = Join-Path ([IO.Path]::GetTempPath()) 'electivus-caveman-module-zips'
New-Item -ItemType Directory -Path $Cache -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression
$Inventory = @()

foreach ($Module in $Modules) {
  $Escaped = [regex]::Replace($Module.name, '[A-Z]', { param($Match) '!' + $Match.Value.ToLowerInvariant() })
  $ZipPath = Join-Path $ModuleCache "$Escaped/@v/$($Module.version).zip"
  $Url = "https://proxy.golang.org/$Escaped/@v/$($Module.version).zip"
  if (-not (Test-Path -LiteralPath $ZipPath)) {
    $ZipPath = Join-Path $Cache (($Escaped.Replace('/','_')) + '@' + $Module.version + '.zip')
    if (-not (Test-Path -LiteralPath $ZipPath)) { Invoke-WebRequest -Uri $Url -OutFile $ZipPath -TimeoutSec 300 -MaximumRetryCount 3 -RetryIntervalSec 5 }
  }
  $Archive = [IO.Compression.ZipFile]::OpenRead($ZipPath)
  try {
    $Names = [string[]]@($Archive.Entries | Where-Object { $_.Name } | ForEach-Object { $_.FullName })
    [Array]::Sort($Names, [StringComparer]::Ordinal)
    $HashLines = [Text.StringBuilder]::new()
    foreach ($Name in $Names) {
      if ($Name.Contains("`n")) { throw 'Unexpected newline in module filename' }
      $Entry = $Archive.GetEntry($Name)
      $Stream = $Entry.Open()
      try { $Digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Stream)).ToLowerInvariant() }
      finally { $Stream.Dispose() }
      [void]$HashLines.Append("$Digest  $Name`n")
    }
    $Actual = 'h1:' + [Convert]::ToBase64String([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($HashLines.ToString())))
    if ($Actual -ne $Module.sum) { throw "Go module checksum mismatch: $($Module.name)@$($Module.version)" }
    $LicenseEntries = @($Archive.Entries | Where-Object { $_.Name -match '^(LICENSE|LICENCE|COPYING|NOTICE|PATENTS|AUTHORS|COPYRIGHT)([._-].*)?$' })
    if ($LicenseEntries.Count -eq 0) { throw "No license file found in $($Module.name)" }
    $ModuleRoot = Join-Path $PackageRoot ('licenses/modules/' + $Escaped + '@' + $Module.version)
    foreach ($Entry in $LicenseEntries) {
      $Prefix = $Module.name + '@' + $Module.version + '/'
      if (-not $Entry.FullName.StartsWith($Prefix, [StringComparison]::Ordinal)) { throw 'Unexpected Go module ZIP root' }
      $Relative = $Entry.FullName.Substring($Prefix.Length)
      $Destination = [IO.Path]::GetFullPath((Join-Path $ModuleRoot $Relative))
      if (-not $Destination.StartsWith(([IO.Path]::GetFullPath($ModuleRoot) + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe module ZIP entry' }
      New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
      [IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Destination, $true)
    }
    $Inventory += [ordered]@{ name=$Module.name; version=$Module.version; source=$Url; goChecksum=$Actual; licenseFiles=@($LicenseEntries.FullName) }
    Write-Host "$($Module.name)@$($Module.version): verified, $($LicenseEntries.Count) notice(s)"
  } finally { $Archive.Dispose() }
}
$GoLicenseDir = Join-Path $PackageRoot 'licenses/go'
New-Item -ItemType Directory -Path $GoLicenseDir -Force | Out-Null
# Go's release-tagged source is read-only documentation, not a runtime dependency.
Invoke-WebRequest -Uri "https://raw.githubusercontent.com/golang/go/refs/tags/$GoVersion/LICENSE" -OutFile (Join-Path $GoLicenseDir 'LICENSE') -TimeoutSec 60 -MaximumRetryCount 3 -RetryIntervalSec 5
$Utf8 = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $PackageRoot 'licenses/module-inventory.json'), (($Inventory | ConvertTo-Json -Depth 6) + "`n"), $Utf8)
