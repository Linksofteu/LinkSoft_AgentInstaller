#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoOwner = 'Linksofteu'
$repoName = 'LinkSoft_AgentInstaller'
$repoRef = 'main'
$archiveUrl = "https://github.com/$repoOwner/$repoName/archive/refs/heads/$repoRef.zip"

$tempDir = $null
$bootstrapLogFile = $null

function Get-DefaultLogRoot {
  if (-not [string]::IsNullOrWhiteSpace($env:XDG_STATE_HOME)) {
    return (Join-Path $env:XDG_STATE_HOME 'linksoft-agent-installer/logs')
  }

  $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
  if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
    return (Join-Path $localAppData 'linksoft-agent-installer/logs')
  }

  return (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.linksoft-agent-installer/logs')
}

function Get-DefaultLogFile {
  return (Join-Path (Get-DefaultLogRoot) ('setup-agentic-tools-{0}.log' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))))
}

function Add-BootstrapLog([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($bootstrapLogFile)) { return }
  $parent = Split-Path -Parent $bootstrapLogFile
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  Add-Content -Path $bootstrapLogFile -Value $Text
}

function Get-LogFileArgument([string[]]$Arguments) {
  for ($i = 0; $i -lt $Arguments.Count; $i++) {
    if ($Arguments[$i] -eq '--log-file' -and $i + 1 -lt $Arguments.Count) {
      return $Arguments[$i + 1]
    }
  }
  return $null
}

function Cleanup {
  if ($null -ne $tempDir -and (Test-Path $tempDir)) {
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
  }
}

try {
  $forwardedArgs = [System.Collections.Generic.List[string]]::new()
  foreach ($arg in $args) { $forwardedArgs.Add($arg) }
  $bootstrapLogFile = Get-LogFileArgument $forwardedArgs
  if ([string]::IsNullOrWhiteSpace($bootstrapLogFile)) {
    $bootstrapLogFile = Get-DefaultLogFile
    $forwardedArgs.Add('--log-file')
    $forwardedArgs.Add($bootstrapLogFile)
  }
  Add-BootstrapLog ("=== install.ps1 session started {0} ===" -f ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')))
  Write-Host ("Log file: {0}" -f $bootstrapLogFile)
  $tempDir = Join-Path ([IO.Path]::GetTempPath()) ([IO.Path]::GetRandomFileName())
  New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

  $archivePath = Join-Path $tempDir 'LinkSoft_AgentInstaller.zip'
  Write-Host "Downloading $repoOwner/$repoName ($repoRef)..."
  Add-BootstrapLog ("Downloading $repoOwner/$repoName ($repoRef)")
  Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath

  Write-Host 'Expanding archive...'
  Add-BootstrapLog ("Expanding archive to $tempDir")
  Expand-Archive -Path $archivePath -DestinationPath $tempDir -Force

  $entrypoint = Join-Path $tempDir "$repoName-$repoRef\setup-agentic-tools.ps1"
  if (-not (Test-Path $entrypoint)) {
    throw "Expected entrypoint not found: $entrypoint"
  }

  & $entrypoint @forwardedArgs
  exit $LASTEXITCODE
} catch {
  Add-BootstrapLog ("ERROR {0}" -f $_.Exception.Message)
  Write-Error $_
  if (-not [string]::IsNullOrWhiteSpace($bootstrapLogFile)) {
    Write-Host ("Log file: {0}" -f $bootstrapLogFile)
  }
  exit 1
} finally {
  Cleanup
}
