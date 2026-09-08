$ErrorActionPreference = 'Stop'
$PackageRoot = Split-Path -Parent $PSScriptRoot
Push-Location $PackageRoot
try {
  & node ./scripts/runtime.mjs verify
  if ($LASTEXITCODE -ne 0) { throw 'Bundle verification failed' }
  New-Item -ItemType Directory -Path ./dist -Force | Out-Null
  $Raw = & npm pack --ignore-scripts --json --pack-destination ./dist
  if ($LASTEXITCODE -ne 0) { throw 'npm pack failed' }
  $Pack = @($Raw | ConvertFrom-Json)[0]
  $ExeFiles = @($Pack.files | Where-Object { $_.path -like 'bin/*.exe' })
  if ($ExeFiles.Count -ne 6) { throw 'Tarball must include exactly six executables' }
  foreach ($File in $Pack.files) {
    if ($File.path -notmatch '^(bin/[^/]+\.exe|lib/[^/]+\.mjs|scripts/runtime\.mjs|licenses/.+|upstream/.+|LICENSE|README\.md|MAINTAINING\.md|package\.json)$') {
      throw "Unexpected npm payload: $($File.path)"
    }
  }
  $Bytes = [IO.File]::ReadAllBytes((Join-Path $PackageRoot "dist/$($Pack.filename)"))
  $Integrity = 'sha512-' + [Convert]::ToBase64String([Security.Cryptography.SHA512]::HashData($Bytes))
  if ($Integrity -ne $Pack.integrity) { throw 'Packed tarball integrity mismatch' }
  $Manifest = [ordered]@{ name=$Pack.name; version=$Pack.version; filename=$Pack.filename; integrity=$Integrity; size=$Pack.size; unpackedSize=$Pack.unpackedSize; files=$Pack.files }
  [IO.File]::WriteAllText((Join-Path $PackageRoot 'dist/artifact.json'), (($Manifest | ConvertTo-Json -Depth 5) + "`n"), [Text.UTF8Encoding]::new($false))
  Write-Host "Packed $($Pack.filename): $($Pack.size) bytes, six executables, $($Pack.entryCount) files; $Integrity"
} finally { Pop-Location }
