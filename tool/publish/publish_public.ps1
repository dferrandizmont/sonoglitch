# Publishes one release of the private development repository to the public
# repository as a single commit (a snapshot of the tagged tree) plus its tag.
#
#   pwsh tool/publish/publish_public.ps1 -Tag v0.1.0-alpha.16 -DryRun
#   pwsh tool/publish/publish_public.ps1 -Tag v0.1.0-alpha.16
#
# The development history, branches, issues of the private repository and
# everything ignored by git (.local/, key.properties, keystores, .env) never
# leave this machine: only `git archive <tag>` is exported, minus the paths
# listed in tool/publish/exclude.txt, and it is scanned for secrets first.
# Pushing the tag to the public repository starts its "Release APK" workflow,
# which builds, signs (if the four signing secrets are set there) and publishes
# the GitHub release. -DryRun builds the snapshot in a temporary folder and
# stops: nothing is cloned, committed or pushed.

param(
  [Parameter(Mandatory = $true)][string]$Tag,
  [string]$PublicRepo = 'dferrandizmont/sonoglitch',
  [string]$WorkDir = (Join-Path $env:USERPROFILE 'sonoglitch-public'),
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
Set-Location $root

function Run-Git {
  & git @args
  if ($LASTEXITCODE -ne 0) { throw "git $($args -join ' ') failed" }
}

$commit = (& git rev-parse --verify "refs/tags/$Tag^{commit}" 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $commit) { throw "Tag $Tag does not exist in this repository." }

$target = if ($DryRun) {
  Join-Path ([IO.Path]::GetTempPath()) ("sonoglitch-public-dryrun-" + [guid]::NewGuid().ToString('N'))
} else { $WorkDir }

if ($DryRun) {
  New-Item -ItemType Directory -Force -Path $target | Out-Null
} elseif (-not (Test-Path (Join-Path $target '.git'))) {
  Run-Git clone "https://github.com/$PublicRepo.git" $target
}

# Empty the work tree (keep .git) and extract the snapshot (`git archive` only exports tracked files).
Get-ChildItem -Force -Path $target | Where-Object { $_.Name -ne '.git' } | Remove-Item -Recurse -Force
$zip = Join-Path ([IO.Path]::GetTempPath()) ("snapshot-" + [guid]::NewGuid().ToString('N') + '.zip')
try {
  Run-Git archive --format=zip --output=$zip $Tag
  Expand-Archive -Path $zip -DestinationPath $target -Force
} finally {
  Remove-Item -Force -ErrorAction SilentlyContinue $zip
}

# Excluded paths (one per line, relative to the repository root, # comments).
$excludeFile = Join-Path $PSScriptRoot 'exclude.txt'
if (Test-Path $excludeFile) {
  foreach ($line in Get-Content $excludeFile) {
    $entry = $line.Trim()
    if (-not $entry -or $entry.StartsWith('#')) { continue }
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $target $entry)
  }
}

# Secret scan of everything that would become public.
$namePatterns = @('*.jks', '*.keystore', 'key.properties', '.env', '.env.*', '*.pem', 'google-services.json', 'GoogleService-Info.plist')
$contentPatterns = @(
  '-----BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
  'ghp_[A-Za-z0-9]{30,}', 'github_pat_[A-Za-z0-9_]{30,}', 'gho_[A-Za-z0-9]{30,}',
  'AKIA[0-9A-Z]{16}', 'xox[baprs]-[A-Za-z0-9-]{10,}', 'sk-[A-Za-z0-9]{32,}',
  '^\s*(storePassword|keyPassword)=\S+'
)
$problems = @()
foreach ($pattern in $namePatterns) {
  $problems += Get-ChildItem -Recurse -Force -File -Path $target -Filter $pattern -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '\\\.git\\' } | ForEach-Object { "file name: $($_.FullName.Substring($target.Length + 1))" }
}
$textFiles = Get-ChildItem -Recurse -Force -File -Path $target | Where-Object {
  $_.FullName -notmatch '\\\.git\\' -and $_.Length -lt 2MB -and $_.Extension -notin '.png', '.jpg', '.jpeg', '.webp', '.ttf', '.otf', '.so', '.jar', '.zip', '.bin'
}
foreach ($file in $textFiles) {
  foreach ($pattern in $contentPatterns) {
    if (Select-String -Path $file.FullName -Pattern $pattern -Quiet -ErrorAction SilentlyContinue) {
      $problems += "content ($pattern): $($file.FullName.Substring($target.Length + 1))"
    }
  }
}
if ($problems.Count -gt 0) {
  $problems | ForEach-Object { Write-Host "  $_" }
  throw 'Possible secrets in the snapshot. Nothing was published. Review the files above (a documentation example may be a false positive: reword it).'
}

$count = (Get-ChildItem -Recurse -Force -File -Path $target | Where-Object { $_.FullName -notmatch '\\\.git\\' }).Count
Write-Host "Snapshot of $Tag ($($commit.Substring(0, 8))): $count files, secret scan clean."

if ($DryRun) {
  Write-Host "Dry run: snapshot left in $target (delete it when you have looked)."
  return
}

Push-Location $target
try {
  Run-Git checkout -B main
  Run-Git add -A
  & git diff --cached --quiet
  if ($LASTEXITCODE -eq 0) { throw 'The snapshot is identical to the public repository: nothing to publish.' }
  if (& git tag --list $Tag) { throw "The public repository already has the tag $Tag." }
  Run-Git commit -q -m "Release $Tag"
  Run-Git tag $Tag
  Run-Git push origin HEAD:main
  Run-Git push origin $Tag
} finally {
  Pop-Location
}
Write-Host "Published. Follow the release build at https://github.com/$PublicRepo/actions"
