# Builds the Google Play app bundle (AAB) signed with the upload key.
#
#   powershell -ExecutionPolicy Bypass -File tool/release/build_play_bundle.ps1
#
# It refuses to build without android/key.properties (a debug-signed bundle
# would be rejected by Play) and never passes DONATION_URL: the Play build has
# no donation link. The version comes from pubspec.yaml (`version: 0.1.0+N`).
# Pass -AppVersion to change the label shown in About (default: 0.1.0-alpha.N).

param([string]$AppVersion = '')

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $root

if (-not (Test-Path 'android\key.properties')) {
  throw 'android/key.properties is missing. Run tool/release/setup_upload_key.ps1 first.'
}
$match = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\d+\.\d+\.\d+)\+(\d+)' | Select-Object -First 1
if (-not $match) { throw 'Cannot read the version from pubspec.yaml.' }
$name = $match.Matches[0].Groups[1].Value
$code = $match.Matches[0].Groups[2].Value
if (-not $AppVersion) { $AppVersion = "$name-alpha.$code" }

flutter build appbundle --release --build-name=$name --build-number=$code `
  --dart-define=APP_VERSION=$AppVersion
if ($LASTEXITCODE -ne 0) { throw 'flutter build failed.' }

$aab = Join-Path $root 'build\app\outputs\bundle\release\app-release.aab'
Write-Host ''
Write-Host "AAB: $aab"
Write-Host ("SHA-256: " + (Get-FileHash $aab -Algorithm SHA256).Hash)

$manifest = Get-ChildItem -Recurse -Path 'build\app\intermediates\merged_manifests\release' -Filter AndroidManifest.xml -ErrorAction SilentlyContinue | Select-Object -First 1
if ($manifest) {
  Write-Host ''
  Write-Host 'Merged manifest (must show es.sonoglitch.app, CAMERA and RECORD_AUDIO only, no INTERNET):'
  Select-String -Path $manifest.FullName -Pattern 'package=|uses-permission|versionCode' | ForEach-Object { '  ' + $_.Line.Trim() }
}
Write-Host ''
Write-Host "Upload this file in Play Console -> Testing -> Closed testing -> Create new release (versionCode $code)."
