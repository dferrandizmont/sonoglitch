# Creates the Google Play upload key and android/key.properties.
#
# Run it yourself in a PowerShell window from the repository root:
#   powershell -ExecutionPolicy Bypass -File tool/release/setup_upload_key.ps1
#
# The key is created OUTSIDE the repository (default: %USERPROFILE%\claves, next to the other apps).
# The passwords are typed here, never stored in the repository history, and
# android/key.properties is ignored by git. Back up the .jks file and the
# passwords (password manager plus an offline copy): without them you cannot
# update the app unless Google support resets the upload key.

$ErrorActionPreference = 'Stop'

function Find-Keytool {
  $cmd = Get-Command keytool -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @()
  if ($env:JAVA_HOME) { $candidates += (Join-Path $env:JAVA_HOME 'bin\keytool.exe') }
  $candidates += 'C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe'
  $candidates += 'C:\Program Files\Android\Android Studio\jre\bin\keytool.exe'
  foreach ($path in $candidates) { if (Test-Path $path) { return $path } }
  throw 'keytool not found. Install a JDK or Android Studio, or set JAVA_HOME.'
}

function Read-Secret($prompt) {
  $secure = Read-Host $prompt -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$propsPath = Join-Path $root 'android\key.properties'
if (Test-Path $propsPath) {
  throw "android/key.properties already exists. Remove it first if you really want a new key (Play would reject a different upload key)."
}

$keytool = Find-Keytool
$dir = Join-Path $env:USERPROFILE 'claves'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$store = Join-Path $dir 'sonoglitch-upload.jks'
if (Test-Path $store) { throw "$store already exists. Move it away or reuse it." }

$name = Read-Host 'Your name for the certificate (e.g. Daniel Mont)'
$password = Read-Secret 'Choose a password (at least 8 characters)'
$again = Read-Secret 'Repeat the password'
if ($password -ne $again -or $password.Length -lt 8) { throw 'Passwords differ or are too short.' }

& $keytool -genkeypair -v -keystore $store -alias upload -keyalg RSA -keysize 4096 `
  -validity 10000 -storepass $password -keypass $password `
  -dname "CN=$name, O=Sonoglitch, C=ES"
if ($LASTEXITCODE -ne 0) { throw 'keytool failed.' }

$storeForProps = $store -replace '\\', '/'
@(
  "storeFile=$storeForProps",
  "storePassword=$password",
  "keyAlias=upload",
  "keyPassword=$password"
) | Set-Content -Path $propsPath -Encoding ASCII

Write-Host ''
Write-Host "Key created: $store"
Write-Host "Wrote android/key.properties (ignored by git)."
Write-Host 'NOW back up the .jks file and the password. Never commit or share them.'
