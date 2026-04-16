#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoOwner = 'Linksofteu'
$repoName = 'LinkSoft_AgentInstaller'
$repoRef = 'main'
$archiveUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$repoRef.zip"

$tempDir = $null

function Cleanup {
  if ($null -ne $tempDir -and (Test-Path $tempDir)) {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

try {
  $tempDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

  $archivePath = Join-Path $tempDir 'LinkSoft_AgentInstaller.zip'
  Write-Host "Downloading $repoOwner/$repoName ($repoRef)..."
  Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath

  Write-Host 'Expanding archive...'
  Expand-Archive -Path $archivePath -DestinationPath $tempDir -Force

  $entrypoint = Join-Path $tempDir "$repoName-$repoRef\setup-agentic-tools.ps1"
  if (-not (Test-Path $entrypoint)) {
    throw "Expected entrypoint not found: $entrypoint"
  }

  & $entrypoint @args
  exit $LASTEXITCODE
} finally {
  Cleanup
}
