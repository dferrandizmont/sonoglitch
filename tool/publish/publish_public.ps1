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
#
# Identity: the public commit and the tag are always made by
# "Daniel Mont Ferrandiz <dev@mainshai.com>" (author, committer and tagger),
# whatever the global or local git config says. Override it with the
# PUBLIC_AUTHOR_NAME and PUBLIC_AUTHOR_EMAIL environment variables. The script
# refuses to publish anything that contains a Gmail address: not in the identity,
# the commit message, the tag or any file of the snapshot.

param(
  [Parameter(Mandatory = $true)][string]$Tag,
  [string]$PublicRepo = 'dferrandizmont/sonoglitch',
  [string]$PublicUrl = "https://github.com/$PublicRepo.git",
  [string]$WorkDir = (Join-Path $env:USERPROFILE 'sonoglitch-public'),
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# The only identity that may appear in the public repository.
$AuthorName = if ($env:PUBLIC_AUTHOR_NAME) { $env:PUBLIC_AUTHOR_NAME } else { 'Daniel Mont Ferrandiz' }
$AuthorEmail = if ($env:PUBLIC_AUTHOR_EMAIL) { $env:PUBLIC_AUTHOR_EMAIL } else { 'dev@mainshai.com' }

# A Gmail mailbox, but not a longer domain that only begins with "gmail.com".
$GmailPattern = '[A-Za-z0-9._%+\-]+@gmail\.com(?![A-Za-z0-9\-])(?!\.[A-Za-z0-9\-])'
if ($AuthorEmail -match $GmailPattern -or $AuthorName -match $GmailPattern) {
  throw 'PUBLIC_AUTHOR_NAME / PUBLIC_AUTHOR_EMAIL may not be a Gmail address.'
}
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
  Run-Git clone $PublicUrl $target
}

if (-not $DryRun) {
  # A clone kept from a previous run must start from what the remote has now.
  Push-Location $target
  try {
    Run-Git fetch origin --tags --prune
    & git rev-parse --verify --quiet refs/remotes/origin/main *> $null
    if ($LASTEXITCODE -eq 0) { Run-Git checkout -B main origin/main }
  } finally {
    Pop-Location
  }
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
  '^\s*(storePassword|keyPassword)=\S+',
  $GmailPattern
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
$identityVariables = 'GIT_AUTHOR_NAME', 'GIT_AUTHOR_EMAIL', 'GIT_COMMITTER_NAME', 'GIT_COMMITTER_EMAIL'
$savedIdentity = @{}
foreach ($name in $identityVariables) { $savedIdentity[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
  Run-Git checkout -B main
  Run-Git add -A
  & git diff --cached --quiet
  if ($LASTEXITCODE -eq 0) { throw 'The snapshot is identical to the public repository: nothing to publish.' }
  if (& git tag --list $Tag) { throw "The public repository already has the tag $Tag." }

  # Author, committer and tagger are fixed here, so the global git config is never used.
  $env:GIT_AUTHOR_NAME = $AuthorName
  $env:GIT_AUTHOR_EMAIL = $AuthorEmail
  $env:GIT_COMMITTER_NAME = $AuthorName
  $env:GIT_COMMITTER_EMAIL = $AuthorEmail
  Run-Git -c "user.name=$AuthorName" -c "user.email=$AuthorEmail" commit -q -m "Release $Tag"
  Run-Git -c "user.name=$AuthorName" -c "user.email=$AuthorEmail" tag -a $Tag -m "Release $Tag"

  # Last check before anything leaves this machine.
  $expected = "$AuthorName <$AuthorEmail>"
  $commitInfo = (& git log -1 --format='%an <%ae>|%cn <%ce>' HEAD)
  if ($commitInfo -ne "$expected|$expected") {
    throw "The public commit has the wrong identity ($commitInfo). Nothing was pushed."
  }
  $commitText = (& git cat-file commit HEAD) -join "`n"
  $tagText = (& git cat-file tag $Tag) -join "`n"
  if ($commitText -match $GmailPattern) { throw 'The public commit contains a Gmail address. Nothing was pushed.' }
  if ($tagText -match $GmailPattern) { throw 'The public tag contains a Gmail address. Nothing was pushed.' }
  if ($tagText -notmatch [regex]::Escape("tagger $expected ")) { throw 'The public tag has the wrong tagger. Nothing was pushed.' }

  Run-Git push origin HEAD:main
  Run-Git push origin $Tag
} finally {
  foreach ($name in $identityVariables) { [Environment]::SetEnvironmentVariable($name, $savedIdentity[$name]) }
  Pop-Location
}
Write-Host "Published. Follow the release build at https://github.com/$PublicRepo/actions"
