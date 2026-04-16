#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Version = '1.1.0'
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:SkillSource = 'Linksofteu/LinkSoft_Skills@test-skill'
$script:SkillName = 'test-skill'
$script:Context7ServerName = 'context7'
$script:Context7Url = 'https://mcp.context7.com/mcp'
$script:DefaultLogFile = Join-Path $script:ScriptDir 'setup-agentic-tools.log'
$script:KnownTools = @(
  'opencode',
  'claude-code',
  'cursor',
  'windsurf',
  'codex',
  'github-copilot-cli',
  'github-copilot',
  'cline',
  'continue',
  'goose',
  'roo',
  'vscode',
  'gemini-cli'
)

$script:Options = [ordered]@{
  NonInteractive = $false
  CopySkills = $false
  DryRun = $false
  Verbose = $false
  LogFile = ''
  ToolsCsv = ''
  AdditionalToolsCsv = ''
  Context7ApiKey = ''
  SkipSkills = $false
  SkipMcp = $false
  SkipVerify = $false
}

$script:VerifyPassCount = 0
$script:VerifyFailCount = 0
$script:VerifySkipCount = 0
$script:VerifyFailedLabels = @()

function Format-Label([string]$Text) { return $Text }
function Format-Value([string]$Text) { return $Text }

function Append-Log([string]$Text) {
  if ([string]::IsNullOrWhiteSpace($script:Options.LogFile)) { return }
  Add-Content -Path $script:Options.LogFile -Value $Text
}

function Note([string]$Text) {
  Write-Host $Text
  Append-Log $Text
}

function Warn([string]$Text) {
  Write-Warning $Text
  Append-Log ("WARN {0}" -f $Text)
}

function Fail([string]$Text) {
  Append-Log ("ERROR {0}" -f $Text)
  throw $Text
}

function Log([string]$Text) {
  $message = "`n=== {0} ===" -f $Text
  Write-Host $message
  Append-Log $message
}

function Phase([int]$Current, [int]$Total, [string]$Text) {
  $message = "`n[{0}/{1}] {2}" -f $Current, $Total, $Text
  Write-Host $message
  Append-Log $message
}

function Debug-Note([string]$Text) {
  if ($script:Options.Verbose) {
    Write-Host $Text
    Append-Log $Text
  }
}

function Debug-Section([string]$Text) {
  if ($script:Options.Verbose) {
    $message = "`n==> {0}" -f $Text
    Write-Host $message
    Append-Log $message
  }
}

function Join-Items([string]$Separator, [object[]]$Items) {
  $Items = @($Items)
  if (-not $Items -or $Items.Count -eq 0) { return '' }
  return [string]::Join($Separator, [string[]]$Items)
}

function Test-CommandExists([string]$Name) {
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-HomePath {
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { return $env:USERPROFILE }
  return [Environment]::GetFolderPath('UserProfile')
}

function Get-AppDataPath {
  if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) { return $env:APPDATA }
  return [Environment]::GetFolderPath('ApplicationData')
}

function Get-LocalAppDataPath {
  if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { return $env:LOCALAPPDATA }
  return [Environment]::GetFolderPath('LocalApplicationData')
}

function Split-CsvToArray([string]$Csv) {
  $result = @()
  if ([string]::IsNullOrWhiteSpace($Csv)) { return $result }
  foreach ($part in $Csv.Split(',')) {
    $trimmed = $part.Trim()
    if (-not [string]::IsNullOrWhiteSpace($trimmed)) {
      $result += $trimmed
    }
  }
  return $result
}

function Add-UniqueValue {
  param(
    [System.Collections.ArrayList]$List,
    [string]$Value
  )
  if (-not $List.Contains($Value)) {
    [void]$List.Add($Value)
  }
}

function Test-KnownTool([string]$Tool) {
  return $script:KnownTools -contains $Tool
}

function Merge-KnownTools([string[]]$BaseTools, [string[]]$ExtraTools) {
  $merged = [System.Collections.ArrayList]::new()
  foreach ($tool in $BaseTools) { Add-UniqueValue -List $merged -Value $tool }
  foreach ($tool in $ExtraTools) {
    if (Test-KnownTool $tool) {
      Add-UniqueValue -List $merged -Value $tool
    } elseif (-not [string]::IsNullOrWhiteSpace($tool)) {
      Warn "Ignoring unknown tool id: $tool"
    }
  }
  return [string[]]$merged
}

function Validate-KnownTools([string[]]$Tools) {
  $validated = [System.Collections.ArrayList]::new()
  foreach ($tool in $Tools) {
    if (Test-KnownTool $tool) {
      Add-UniqueValue -List $validated -Value $tool
    } elseif (-not [string]::IsNullOrWhiteSpace($tool)) {
      Warn "Ignoring unknown tool id: $tool"
    }
  }
  return [string[]]$validated
}

function Get-OpenCodeConfigPath { Join-Path (Get-AppDataPath) 'opencode\opencode.json' }
function Get-VSCodeMcpPath { Join-Path (Get-AppDataPath) 'Code\User\mcp.json' }
function Get-CopilotConfigPath { Join-Path (Join-Path (Get-HomePath) '.copilot') 'mcp-config.json' }

function Get-ToolSkillStaticPaths([string]$Tool) {
  $userHome = Get-HomePath
  switch ($Tool) {
    'opencode' { return @((Join-Path $userHome ".agents\skills\$($script:SkillName)\SKILL.md")) }
    'codex' { return @((Join-Path $userHome ".agents\skills\$($script:SkillName)\SKILL.md")) }
    'github-copilot-cli' { return @((Join-Path $userHome ".agents\skills\$($script:SkillName)\SKILL.md")) }
    'github-copilot' { return @((Join-Path $userHome ".agents\skills\$($script:SkillName)\SKILL.md")) }
    'cline' { return @((Join-Path $userHome ".agents\skills\$($script:SkillName)\SKILL.md")) }
    'cursor' { return @((Join-Path $userHome ".agents\skills\$($script:SkillName)\SKILL.md")) }
    'gemini-cli' { return @((Join-Path $userHome ".agents\skills\$($script:SkillName)\SKILL.md")) }
    'claude-code' { return @((Join-Path $userHome ".claude\skills\$($script:SkillName)\SKILL.md")) }
    'windsurf' { return @((Join-Path $userHome ".codeium\windsurf\skills\$($script:SkillName)\SKILL.md")) }
    'continue' { return @((Join-Path $userHome ".continue\skills\$($script:SkillName)\SKILL.md")) }
    'goose' { return @((Join-Path $userHome ".config\goose\skills\$($script:SkillName)\SKILL.md")) }
    'roo' { return @((Join-Path $userHome ".roo\skills\$($script:SkillName)\SKILL.md")) }
    'vscode' { return @((Join-Path $userHome ".agents\skills\$($script:SkillName)\SKILL.md")) }
    default { return @() }
  }
}

function Get-McpmClientName([string]$Tool) {
  switch ($Tool) {
    'claude-code' { return 'claude-code' }
    'cursor' { return 'cursor' }
    'windsurf' { return 'windsurf' }
    'codex' { return 'codex-cli' }
    'cline' { return 'cline' }
    'continue' { return 'continue' }
    'goose' { return 'goose-cli' }
    'roo' { return 'roo-code' }
    'gemini-cli' { return 'gemini-cli' }
    default { return $null }
  }
}

function Get-SkillAgentForTool([string]$Tool) {
  switch ($Tool) {
    'opencode' { return 'opencode' }
    'claude-code' { return 'claude-code' }
    'cursor' { return 'cursor' }
    'windsurf' { return 'windsurf' }
    'codex' { return 'codex' }
    'github-copilot-cli' { return 'github-copilot' }
    'github-copilot' { return 'github-copilot' }
    'cline' { return 'cline' }
    'continue' { return 'continue' }
    'goose' { return 'goose' }
    'roo' { return 'roo' }
    'vscode' { return 'github-copilot' }
    'gemini-cli' { return 'gemini-cli' }
    default { return $null }
  }
}

function Get-NativeSkillsCheckHint([string]$Tool) {
  switch ($Tool) {
    'github-copilot-cli' { return '/skills in Copilot Chat or /skills list in Copilot CLI' }
    'github-copilot' { return '/skills in Copilot Chat or /skills list in Copilot CLI' }
    'vscode' { return '/skills in Copilot Chat or /skills list in Copilot CLI' }
    'codex' { return '/skills in Codex CLI/TUI' }
    'claude-code' { return 'direct /skill-name invocation or asking "What skills are available?" in Claude Code' }
    'opencode' { return 'the native skill tool / available_skills in OpenCode sessions' }
    default { return $null }
  }
}

function Test-ToolHasMcpCliCheck([string]$Tool) {
  return @('opencode', 'claude-code') -contains $Tool
}

function Detect-Tool([string]$Tool) {
  $userHome = Get-HomePath
  $appData = Get-AppDataPath
  switch ($Tool) {
    'opencode' { return (Test-Path (Split-Path (Get-OpenCodeConfigPath) -Parent)) -or (Test-CommandExists 'opencode') }
    'claude-code' { return (Test-Path (Join-Path $userHome '.claude')) -or (Test-CommandExists 'claude') }
    'cursor' { return (Test-Path (Join-Path $userHome '.cursor')) -or (Test-Path (Join-Path $appData 'Cursor')) -or (Test-CommandExists 'cursor') }
    'windsurf' { return (Test-Path (Join-Path $userHome '.codeium\windsurf')) -or (Test-Path (Join-Path $appData 'Codeium\Windsurf')) -or (Test-CommandExists 'windsurf') }
    'codex' { return (Test-Path (Join-Path $userHome '.codex')) -or (Test-CommandExists 'codex') }
    'github-copilot-cli' { return (Test-CommandExists 'copilot') -or (Test-Path (Join-Path $userHome '.copilot')) }
    'github-copilot' { return (Test-Path (Join-Path $appData 'Code\User')) -or (Test-CommandExists 'code') }
    'cline' { return (Test-Path (Join-Path $userHome '.cline')) -or (Test-Path (Join-Path $appData 'Code\User\globalStorage\saoudrizwan.claude-dev')) }
    'continue' { return (Test-Path (Join-Path $userHome '.continue')) }
    'goose' { return (Test-Path (Join-Path $appData 'goose')) -or (Test-CommandExists 'goose') }
    'roo' { return (Test-Path (Join-Path $userHome '.roo')) }
    'vscode' { return (Test-CommandExists 'code') -or (Test-Path (Join-Path $appData 'Code\User')) }
    'gemini-cli' { return (Test-Path (Join-Path $userHome '.gemini')) -or (Test-CommandExists 'gemini') }
    default { return $false }
  }
}

function Get-DetectedTools {
  $detected = New-Object System.Collections.Generic.List[string]
  foreach ($tool in $script:KnownTools) {
    if (Detect-Tool $tool) {
      $detected.Add($tool)
    }
  }
  return [string[]]$detected
}

function Ensure-LogFile {
  if ([string]::IsNullOrWhiteSpace($script:Options.LogFile)) {
    $script:Options.LogFile = $script:DefaultLogFile
  }
  $parent = Split-Path -Parent $script:Options.LogFile
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  if (Test-Path $script:Options.LogFile) {
    Warn "Overwriting existing log file: $($script:Options.LogFile)"
  }
  Set-Content -Path $script:Options.LogFile -Value ("=== setup-agentic-tools session started {0} ===" -f ([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')))
  Note "$(Format-Label 'Log file:') $(Format-Value $script:Options.LogFile)"
}

function Show-Usage {
  @"
Usage: setup-agentic-tools.ps1 [options]

Installs the LinkSoft test skill via npx skills, installs/configures Context7,
then runs static and smoke verification where supported.

Version: $($script:Version)

Options:
  --tools CSV              Final tool ids to configure
  --extra-tools CSV        Additional tool ids to merge with detected tools
  --context7-api-key KEY   Optional Context7 API key
  --log-file PATH          Log file path (default: $($script:DefaultLogFile))
  --copy-skills            Use --copy instead of symlinks for skills installation
  --skip-skills            Skip the npx skills installation step
  --skip-mcp               Skip the MCP/Context7 installation step
  --skip-verify            Skip post-install verification
  --non-interactive        Do not prompt the user
  --dry-run                Print actions without executing them (implies non-interactive preview)
  -v, --verbose            Enable detailed command logging
  -h, --help               Show this help

Known tool ids:
  $(Join-Items ' ' $script:KnownTools)
"@ | Write-Host
}

function Parse-Args([string[]]$CliArgs) {
  $i = 0
  while ($i -lt $CliArgs.Count) {
    $arg = $CliArgs[$i]
    switch ($arg) {
      '--tools' {
        if ($i + 1 -ge $CliArgs.Count) { Fail '--tools requires a value' }
        $script:Options.ToolsCsv = $CliArgs[$i + 1]
        $i += 2
        continue
      }
      '--extra-tools' {
        if ($i + 1 -ge $CliArgs.Count) { Fail '--extra-tools requires a value' }
        $script:Options.AdditionalToolsCsv = $CliArgs[$i + 1]
        $i += 2
        continue
      }
      '--context7-api-key' {
        if ($i + 1 -ge $CliArgs.Count) { Fail '--context7-api-key requires a value' }
        $script:Options.Context7ApiKey = $CliArgs[$i + 1]
        $i += 2
        continue
      }
      '--log-file' {
        if ($i + 1 -ge $CliArgs.Count) { Fail '--log-file requires a value' }
        $script:Options.LogFile = $CliArgs[$i + 1]
        $i += 2
        continue
      }
      '--copy-skills' { $script:Options.CopySkills = $true; $i += 1; continue }
      '--skip-skills' { $script:Options.SkipSkills = $true; $i += 1; continue }
      '--skip-mcp' { $script:Options.SkipMcp = $true; $i += 1; continue }
      '--skip-verify' { $script:Options.SkipVerify = $true; $i += 1; continue }
      '--non-interactive' { $script:Options.NonInteractive = $true; $i += 1; continue }
      '--dry-run' { $script:Options.DryRun = $true; $i += 1; continue }
      '-v' { $script:Options.Verbose = $true; $i += 1; continue }
      '--verbose' { $script:Options.Verbose = $true; $i += 1; continue }
      '-h' { Show-Usage; exit 0 }
      '--help' { Show-Usage; exit 0 }
      default { Fail "Unknown argument: $arg" }
    }
  }
}

function Format-Command([string[]]$Command) {
  return ($Command | ForEach-Object {
    if ($_ -match '[\s"]') {
      '"{0}"' -f ($_.Replace('"', '\"'))
    } else {
      $_
    }
  }) -join ' '
}

function Invoke-ExternalCommand {
  param(
    [string[]]$Command,
    [switch]$IgnoreExitCode
  )

  $rendered = Format-Command $Command
  if ($script:Options.Verbose) {
    Write-Host "`n$ $rendered"
  }
  Append-Log ("RUN: {0}" -f $rendered)

  if ($script:Options.DryRun) {
    Note '[dry-run] command not executed'
    return $true
  }

  $exe = $Command[0]
  $cmdArgs = @()
  if ($Command.Count -gt 1) {
    $cmdArgs = $Command[1..($Command.Count - 1)]
  }

  try {
    & $exe @cmdArgs
    $exitCode = $LASTEXITCODE
  } catch {
    if ($IgnoreExitCode) { return $false }
    throw
  }

  if ($null -eq $exitCode) { $exitCode = 0 }
  if ($exitCode -ne 0 -and -not $IgnoreExitCode) {
    Fail "Command failed with exit code ${exitCode}: $rendered"
  }
  return ($exitCode -eq 0)
}

function Invoke-CaptureCommandOutput {
  param([string[]]$Command)

  $rendered = Format-Command $Command
  Append-Log ("RUN: {0}" -f $rendered)
  $exe = $Command[0]
  $cmdArgs = @()
  if ($Command.Count -gt 1) {
    $cmdArgs = $Command[1..($Command.Count - 1)]
  }

  $output = & $exe @cmdArgs 2>&1
  $exitCode = $LASTEXITCODE
  $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
  Append-Log $text
  return [pscustomobject]@{
    Success = ($exitCode -eq 0)
    Output = $text
    ExitCode = $exitCode
  }
}

function Ensure-Prereqs {
  if (-not $script:Options.SkipSkills -and -not (Test-CommandExists 'npx')) {
    Fail 'npx is required'
  }
  if (-not $script:Options.SkipMcp -and -not (Test-CommandExists 'mcpm')) {
    Fail 'mcpm is required. Install it first, then rerun this script.'
  }
}

function Ensure-OpenSpec {
  if (Test-CommandExists 'openspec') {
    $path = (Get-Command 'openspec').Source
    Note "$(Format-Label 'OpenSpec:') $(Format-Value "installed at $path")"
    return
  }

  Warn 'openspec is not installed'

  if ($script:Options.NonInteractive) {
    Warn 'Non-interactive mode cannot prompt to install openspec. Install it manually with: npm install -g openspec'
    return
  }

  if (-not (Test-CommandExists 'npm')) {
    Warn 'npm is not available, so openspec cannot be installed automatically. Install npm first, then run: npm install -g openspec'
    return
  }

  $answer = Read-Host 'openspec is missing. Install it globally with npm now? [y/N]'
  if ($answer -match '^(?i:y|yes)$') {
    Log 'Installing openspec globally'
    [void](Invoke-ExternalCommand -Command @('npm', 'install', '-g', 'openspec'))
  } else {
    Note 'Skipping openspec installation'
  }
}

function Collect-SkillAgents([string[]]$SelectedTools) {
  $agents = [System.Collections.ArrayList]::new()
  foreach ($tool in $SelectedTools) {
    if ($tool -eq 'vscode') {
      Debug-Note "'vscode' is treated as an IDE/MCP target; using 'github-copilot' as the skills target"
    }
    $agent = Get-SkillAgentForTool $tool
    if (-not [string]::IsNullOrWhiteSpace($agent)) {
      Add-UniqueValue -List $agents -Value $agent
    }
  }
  return [string[]]$agents
}

function Install-Skill([string[]]$SelectedTools) {
  $skillAgents = @(Collect-SkillAgents $SelectedTools)
  if (-not $skillAgents -or $skillAgents.Count -eq 0) {
    Warn 'No valid skills.sh targets selected; skipping skill installation'
    return
  }

  Ensure-OpenSpec

  $command = New-Object System.Collections.Generic.List[string]
  foreach ($item in @('npx', '-y', 'skills', 'add', $script:SkillSource, '-g', '-y')) { $command.Add($item) }
  if ($script:Options.CopySkills) { $command.Add('--copy') }
  foreach ($agent in $skillAgents) {
    $command.Add('-a')
    $command.Add($agent)
  }

  Log 'Installing LinkSoft test skill'
  Debug-Note ("skills.sh targets: {0}" -f (Join-Items ', ' $skillAgents))
  [void](Invoke-ExternalCommand -Command ([string[]]$command))
}

function Remove-JsonCommentsAndTrailingCommas([string]$Text) {
  $chars = $Text.ToCharArray()
  $result = New-Object System.Text.StringBuilder
  $inString = $false
  $stringChar = [char]0
  $escaped = $false
  $inLineComment = $false
  $inBlockComment = $false

  for ($i = 0; $i -lt $chars.Length; $i++) {
    $ch = $chars[$i]
    $next = if ($i + 1 -lt $chars.Length) { $chars[$i + 1] } else { [char]0 }

    if ($inLineComment) {
      if ($ch -eq "`n") {
        $inLineComment = $false
        [void]$result.Append($ch)
      }
      continue
    }

    if ($inBlockComment) {
      if ($ch -eq '*' -and $next -eq '/') {
        $inBlockComment = $false
        $i += 1
      }
      continue
    }

    if ($inString) {
      [void]$result.Append($ch)
      if ($escaped) {
        $escaped = $false
      } elseif ($ch -eq '\\') {
        $escaped = $true
      } elseif ($ch -eq $stringChar) {
        $inString = $false
      }
      continue
    }

    if ($ch -eq '"' -or $ch -eq "'") {
      $inString = $true
      $stringChar = $ch
      [void]$result.Append($ch)
      continue
    }

    if ($ch -eq '/' -and $next -eq '/') {
      $inLineComment = $true
      $i += 1
      continue
    }

    if ($ch -eq '/' -and $next -eq '*') {
      $inBlockComment = $true
      $i += 1
      continue
    }

    [void]$result.Append($ch)
  }

  $cleaned = $result.ToString()
  $chars = $cleaned.ToCharArray()
  $compact = New-Object System.Text.StringBuilder
  $inString = $false
  $stringChar = [char]0
  $escaped = $false

  for ($i = 0; $i -lt $chars.Length; $i++) {
    $ch = $chars[$i]

    if ($inString) {
      [void]$compact.Append($ch)
      if ($escaped) {
        $escaped = $false
      } elseif ($ch -eq '\\') {
        $escaped = $true
      } elseif ($ch -eq $stringChar) {
        $inString = $false
      }
      continue
    }

    if ($ch -eq '"' -or $ch -eq "'") {
      $inString = $true
      $stringChar = $ch
      [void]$compact.Append($ch)
      continue
    }

    if ($ch -eq ',') {
      $j = $i + 1
      while ($j -lt $chars.Length -and [char]::IsWhiteSpace($chars[$j])) {
        $j += 1
      }
      if ($j -lt $chars.Length -and ($chars[$j] -eq '}' -or $chars[$j] -eq ']')) {
        continue
      }
    }

    [void]$compact.Append($ch)
  }

  return $compact.ToString()
}

function New-JsonObject { return [pscustomobject]@{} }

function Test-JsonObject($Value) {
  return ($Value -is [System.Collections.IDictionary]) -or ($Value -is [pscustomobject])
}

function Get-JsonPropertyValue($Object, [string]$Name) {
  if ($null -eq $Object) { return $null }
  if ($Object -is [System.Collections.IDictionary]) {
    if ($Object.Contains($Name)) { return $Object[$Name] }
    return $null
  }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -ne $prop) { return $prop.Value }
  return $null
}

function Set-JsonPropertyValue($Object, [string]$Name, $Value) {
  if ($Object -is [System.Collections.IDictionary]) {
    $Object[$Name] = $Value
    return
  }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -ne $prop) {
    $prop.Value = $Value
  } else {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

function Ensure-JsonObjectProperty($Object, [string]$Name) {
  $current = Get-JsonPropertyValue $Object $Name
  if (-not (Test-JsonObject $current)) {
    $current = New-JsonObject
    Set-JsonPropertyValue $Object $Name $current
  }
  return $current
}

function Read-JsoncDocument([string]$Path) {
  if (-not (Test-Path $Path)) {
    return New-JsonObject
  }

  $raw = Get-Content -Path $Path -Raw -Encoding UTF8
  $stripped = Remove-JsonCommentsAndTrailingCommas $raw
  if ([string]::IsNullOrWhiteSpace($stripped)) {
    return New-JsonObject
  }

  $parsed = $stripped | ConvertFrom-Json
  if ($null -eq $parsed) {
    return New-JsonObject
  }
  return $parsed
}

function Backup-FileIfPresent([string]$Path) {
  if (Test-Path $Path) {
    Copy-Item -Path $Path -Destination ("{0}.bak.{1}" -f $Path, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()) -Force
  }
}

function Write-JsonDocument([string]$Path, $Data) {
  $parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
  }
  $json = $Data | ConvertTo-Json -Depth 30
  Set-Content -Path $Path -Value ($json + [Environment]::NewLine) -Encoding UTF8
}

function Configure-OpenCode {
  Log 'Configuring OpenCode to use MCPM-managed Context7'
  $path = Get-OpenCodeConfigPath
  if ($script:Options.DryRun) {
    Note "Would update $path"
    return
  }

  $mcpmBin = (Get-Command 'mcpm').Source
  Backup-FileIfPresent $path
  $data = Read-JsoncDocument $path
  Set-JsonPropertyValue $data '$schema' 'https://opencode.ai/config.json'
  $mcp = Ensure-JsonObjectProperty $data 'mcp'
  Set-JsonPropertyValue $mcp 'context7' ([pscustomobject]@{
    type = 'local'
    command = @($mcpmBin, 'run', 'context7')
    enabled = $true
  })
  Write-JsonDocument $path $data
}

function Configure-VSCode {
  Log 'Configuring VS Code MCP file'
  $path = Get-VSCodeMcpPath
  if ($script:Options.DryRun) {
    Note "Would update $path"
    return
  }

  $mcpmBin = (Get-Command 'mcpm').Source
  Backup-FileIfPresent $path
  $data = Read-JsoncDocument $path
  $servers = Ensure-JsonObjectProperty $data 'servers'
  Set-JsonPropertyValue $servers 'mcpm_context7' ([pscustomobject]@{
    type = 'stdio'
    command = $mcpmBin
    args = @('run', 'context7')
  })
  Write-JsonDocument $path $data
}

function Configure-GitHubCopilotCli {
  Log 'Configuring GitHub Copilot CLI MCP file'
  $path = Get-CopilotConfigPath
  if ($script:Options.DryRun) {
    Note "Would update $path"
    return
  }

  $mcpmBin = (Get-Command 'mcpm').Source
  Backup-FileIfPresent $path
  $data = Read-JsoncDocument $path

  $legacyServers = Get-JsonPropertyValue $data 'servers'
  $mcpServers = Ensure-JsonObjectProperty $data 'mcpServers'
  if (Test-JsonObject $legacyServers) {
    foreach ($prop in $legacyServers.PSObject.Properties) {
      if ($null -eq (Get-JsonPropertyValue $mcpServers $prop.Name)) {
        Set-JsonPropertyValue $mcpServers $prop.Name $prop.Value
      }
    }
    if ($legacyServers -is [System.Collections.IDictionary]) {
      foreach ($key in $legacyServers.Keys) {
        if ($null -eq (Get-JsonPropertyValue $mcpServers $key)) {
          Set-JsonPropertyValue $mcpServers $key $legacyServers[$key]
        }
      }
    }
  }

  Set-JsonPropertyValue $mcpServers 'mcpm_context7' ([pscustomobject]@{
    type = 'local'
    command = $mcpmBin
    args = @('run', 'context7')
  })
  Write-JsonDocument $path $data
}

function Install-Context7Server([string]$ApiKey) {
  Log 'Installing Context7 in MCPM'

  if ($script:Options.DryRun) {
    Note "Would ensure MCPM server '$($script:Context7ServerName)' exists"
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
      Note "Would configure MCPM server '$($script:Context7ServerName)' with a Context7 API key header"
    }
    return
  }

  $listResult = Invoke-CaptureCommandOutput @('mcpm', 'ls')
  if ($listResult.Success -and $listResult.Output -match "(?im)^\s*$($script:Context7ServerName)(\s+.*)?$") {
    Note 'Context7 already exists in MCPM'
  } else {
    $installed = Invoke-ExternalCommand -Command @('mcpm', 'install', $script:Context7ServerName, '--force') -IgnoreExitCode
    if (-not $installed) {
      Warn 'mcpm registry install failed; falling back to manual MCPM server definition'
      [void](Invoke-ExternalCommand -Command @('mcpm', 'new', $script:Context7ServerName, '--type', 'remote', '--url', $script:Context7Url, '--force'))
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    [void](Invoke-ExternalCommand -Command @('mcpm', 'edit', $script:Context7ServerName, '--url', $script:Context7Url, '--headers', ("CONTEXT7_API_KEY={0}" -f $ApiKey), '--force'))
  }
}

function Wire-Context7ToTool([string]$Tool) {
  switch ($Tool) {
    'opencode' { Configure-OpenCode; return }
    'vscode' { Configure-VSCode; return }
    'github-copilot-cli' { Configure-GitHubCopilotCli; return }
    'github-copilot' {
      Warn "No standalone GitHub Copilot MCP file is configured here; use the 'vscode' target for Copilot-in-VS-Code MCP wiring"
      return
    }
  }

  $clientName = Get-McpmClientName $Tool
  if ([string]::IsNullOrWhiteSpace($clientName)) {
    Warn "No MCP wiring strategy is defined for $Tool"
    return
  }

  Log "Adding Context7 to $Tool via MCPM client '$clientName'"
  $success = Invoke-ExternalCommand -Command @('mcpm', 'client', 'edit', $clientName, '--add-server', $script:Context7ServerName, '--force') -IgnoreExitCode
  if (-not $success) {
    Warn "Failed to wire Context7 into MCPM client '$clientName' for tool '$Tool'"
  }
}

function Wire-Context7ToTools([string[]]$Tools) {
  foreach ($tool in $Tools) {
    Wire-Context7ToTool $tool
  }
}

function Reset-VerificationCounts {
  $script:VerifyPassCount = 0
  $script:VerifyFailCount = 0
  $script:VerifySkipCount = 0
  $script:VerifyFailedLabels = @()
}

function Record-CheckStatus([string]$Status, [string]$Label) {
  switch ($Status) {
    'PASS' { $script:VerifyPassCount += 1 }
    'FAIL' {
      $script:VerifyFailCount += 1
      $script:VerifyFailedLabels += $Label
    }
    'SKIP' { $script:VerifySkipCount += 1 }
  }
}

function Report-VerificationCheck([string]$Status, [string]$Label, [string]$Details) {
  Record-CheckStatus $Status $Label
  $line = "[{0}] {1}: {2}" -f $Status, $Label, $Details
  if ($Status -eq 'FAIL') {
    Warn $line
  } else {
    Note $line
  }
}

function Verify-SkillsStatic([string[]]$Tools) {
  Log 'Static verification: skills'
  foreach ($tool in $Tools) {
    $paths = @(Get-ToolSkillStaticPaths $tool)
    if (-not $paths -or $paths.Count -eq 0) {
      Report-VerificationCheck 'SKIP' "skills/$tool" 'no documented static skill path mapping'
      continue
    }

    $foundPath = $null
    foreach ($path in $paths) {
      if (Test-Path $path) {
        $foundPath = $path
        break
      }
    }

    if ($null -ne $foundPath) {
      Report-VerificationCheck 'PASS' "skills/$tool" "found $foundPath"
    } else {
      Report-VerificationCheck 'FAIL' "skills/$tool" ("missing expected skill file in: {0}" -f (Join-Items ', ' $paths))
    }
  }
}

function Verify-McpStatic([string[]]$Tools) {
  Log 'Static verification: MCP'

  if ($script:Options.DryRun) {
    Report-VerificationCheck 'SKIP' 'mcp/global' 'dry-run mode does not execute verification commands'
    return
  }

  if ($script:Options.SkipMcp) {
    Report-VerificationCheck 'SKIP' 'mcp/global' 'MCP installation was skipped'
    return
  }

  $mcpmServers = Invoke-CaptureCommandOutput @('mcpm', 'ls')
  if ($mcpmServers.Success) {
    if ($mcpmServers.Output -match [regex]::Escape($script:Context7ServerName)) {
      Report-VerificationCheck 'PASS' 'mcp/global' "mcpm knows about $($script:Context7ServerName)"
    } else {
      Report-VerificationCheck 'FAIL' 'mcp/global' "mcpm ls did not include $($script:Context7ServerName)"
    }
  } else {
    Report-VerificationCheck 'FAIL' 'mcp/global' 'unable to list MCPM servers'
  }

  $mcpmClients = Invoke-CaptureCommandOutput @('mcpm', 'client', 'ls')
  foreach ($tool in $Tools) {
    switch ($tool) {
      'opencode' {
        $path = Get-OpenCodeConfigPath
        if ((Test-Path $path) -and ((Get-Content -Path $path -Raw) -match '"context7"')) {
          Report-VerificationCheck 'PASS' 'mcp/opencode' 'OpenCode config contains context7'
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/opencode' 'OpenCode config missing context7'
        }
        continue
      }
      'vscode' {
        $path = Get-VSCodeMcpPath
        if ((Test-Path $path) -and ((Get-Content -Path $path -Raw) -match 'mcpm_context7')) {
          Report-VerificationCheck 'PASS' 'mcp/vscode' 'VS Code mcp.json contains mcpm_context7'
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/vscode' 'VS Code mcp.json missing mcpm_context7'
        }
        continue
      }
      'github-copilot-cli' {
        $path = Get-CopilotConfigPath
        if ((Test-Path $path) -and ((Get-Content -Path $path -Raw) -match '"mcpServers"') -and ((Get-Content -Path $path -Raw) -match 'mcpm_context7')) {
          Report-VerificationCheck 'PASS' 'mcp/github-copilot-cli' 'Copilot CLI mcp-config.json contains mcpm_context7'
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/github-copilot-cli' 'Copilot CLI mcp-config.json missing mcpm_context7'
        }
        continue
      }
      'github-copilot' {
        Report-VerificationCheck 'SKIP' 'mcp/github-copilot' 'use the vscode target for Copilot-in-VS-Code MCP verification'
        continue
      }
    }

    $clientName = Get-McpmClientName $tool
    if ([string]::IsNullOrWhiteSpace($clientName)) {
      Report-VerificationCheck 'SKIP' "mcp/$tool" 'no static MCP verification rule defined'
    } elseif ($mcpmClients.Output -match [regex]::Escape($clientName) -and $mcpmClients.Output -match [regex]::Escape($script:Context7ServerName)) {
      Report-VerificationCheck 'PASS' "mcp/$tool" "mcpm client list shows Context7 for $clientName"
    } else {
      Report-VerificationCheck 'FAIL' "mcp/$tool" "mcpm client list did not show Context7 for $clientName"
    }
  }
}

function Verify-SkillsSmoke([string[]]$Tools) {
  Log 'Smoke verification: skills CLI'

  if ($script:Options.DryRun) {
    Report-VerificationCheck 'SKIP' 'skills-cli/global' 'dry-run mode does not execute verification commands'
    return
  }

  foreach ($tool in $Tools) {
    $agent = Get-SkillAgentForTool $tool
    if ([string]::IsNullOrWhiteSpace($agent)) {
      Report-VerificationCheck 'SKIP' "skills-cli/$tool" 'no documented skills CLI mapping'
      continue
    }

    $hint = Get-NativeSkillsCheckHint $tool
    $result = Invoke-CaptureCommandOutput @('npx', '-y', 'skills', 'ls', '-g', '-a', $agent)
    if ($result.Success) {
      if ($result.Output -match [regex]::Escape($script:SkillName)) {
        $details = "skills.sh fallback for $agent included $($script:SkillName)"
        if (-not [string]::IsNullOrWhiteSpace($hint)) { $details += "; native check available manually via $hint" }
        Report-VerificationCheck 'PASS' "skills-cli/$tool" $details
      } else {
        $details = "skills.sh fallback for $agent did not include $($script:SkillName)"
        if (-not [string]::IsNullOrWhiteSpace($hint)) { $details += "; native check available manually via $hint" }
        Report-VerificationCheck 'FAIL' "skills-cli/$tool" $details
      }
    } else {
      Report-VerificationCheck 'FAIL' "skills-cli/$tool" "unable to query skills.sh fallback for $agent"
    }
  }
}

function Verify-McpSmoke([string[]]$Tools) {
  Log 'Smoke verification: MCP CLIs'

  if ($script:Options.DryRun) {
    Report-VerificationCheck 'SKIP' 'mcp-cli/global' 'dry-run mode does not execute verification commands'
    return
  }

  $mcpm = Invoke-CaptureCommandOutput @('mcpm', 'ls')
  if ($mcpm.Output -match [regex]::Escape($script:Context7ServerName)) {
    Report-VerificationCheck 'PASS' 'mcpm' "mcpm ls included $($script:Context7ServerName)"
  } else {
    Report-VerificationCheck 'FAIL' 'mcpm' "mcpm ls did not include $($script:Context7ServerName)"
  }

  foreach ($tool in $Tools) {
    if (-not (Test-ToolHasMcpCliCheck $tool)) {
      Report-VerificationCheck 'SKIP' "mcp-cli/$tool" 'no documented CLI check found'
      continue
    }

    switch ($tool) {
      'opencode' {
        if (-not (Test-CommandExists 'opencode')) {
          Report-VerificationCheck 'SKIP' 'mcp-cli/opencode' 'opencode executable not found'
        } else {
          $result = Invoke-CaptureCommandOutput @('opencode', 'mcp', 'list')
          if ($result.Success -and $result.Output -match 'context7') {
            Report-VerificationCheck 'PASS' 'mcp-cli/opencode' 'opencode mcp list included context7'
          } elseif ($result.Success) {
            Report-VerificationCheck 'FAIL' 'mcp-cli/opencode' 'opencode mcp list did not include context7'
          } else {
            Report-VerificationCheck 'FAIL' 'mcp-cli/opencode' 'unable to query opencode mcp list'
          }
        }
      }
      'claude-code' {
        if (-not (Test-CommandExists 'claude')) {
          Report-VerificationCheck 'SKIP' 'mcp-cli/claude-code' 'claude executable not found'
        } else {
          $result = Invoke-CaptureCommandOutput @('claude', 'mcp', 'list')
          if ($result.Success -and $result.Output -match 'context7') {
            Report-VerificationCheck 'PASS' 'mcp-cli/claude-code' 'claude mcp list included context7'
          } elseif ($result.Success) {
            Report-VerificationCheck 'FAIL' 'mcp-cli/claude-code' 'claude mcp list did not include context7'
          } else {
            Report-VerificationCheck 'FAIL' 'mcp-cli/claude-code' 'unable to query claude mcp list'
          }
        }
      }
    }
  }
}

function Run-Verification([string[]]$SelectedTools) {
  Reset-VerificationCounts
  Verify-SkillsStatic $SelectedTools
  Verify-McpStatic $SelectedTools
  Verify-SkillsSmoke $SelectedTools
  Verify-McpSmoke $SelectedTools

  Log 'Verification summary'
  Note "$(Format-Label 'Results:') $(Format-Value "$($script:VerifyPassCount) passed, $($script:VerifyFailCount) failed, $($script:VerifySkipCount) skipped")"
  if ($script:VerifyFailCount -gt 0) {
    Note "$(Format-Label 'Failed checks:') $(Format-Value (Join-Items ', ' $script:VerifyFailedLabels))"
  }
}

function Print-ManualVerificationInstructions([string[]]$Tools) {
  Log 'Manual verification instructions'
  foreach ($tool in $Tools) {
    switch ($tool) {
      'github-copilot-cli' {
        Note @"
- github-copilot-cli:
  1. Start Copilot CLI by running: copilot
  2. Run: /skills list
  3. Run: /mcp and confirm context7 is configured.
  4. Invoke /test-skill or ask Copilot to use context7 in a prompt.
"@
      }
      'vscode' {
        Note @"
- vscode:
  1. Open VS Code in the target workspace.
  2. Open Command Palette (Ctrl+Shift+P) and run: MCP: List Servers.
  3. Open Copilot Chat in Agent mode and inspect the tools list.
  4. If context7 is present but unavailable, open the VS Code user mcp.json file and verify the command path.
"@
      }
      'github-copilot' {
        Note @"
- github-copilot:
  1. Verify the skill exists in ~/.agents/skills, ~/.claude/skills, or ~/.copilot/skills.
  2. In Copilot CLI, run: /skills list
  3. In VS Code Agent mode, type /skills and confirm the skill appears.
  4. For MCP in VS Code, also select the 'vscode' target and run MCP: List Servers.
"@
      }
      'cline' {
        Note @"
- cline:
  1. Verify the skill exists in ~/.agents/skills/$($script:SkillName)/SKILL.md.
  2. Inspect the Cline MCP settings file in VS Code global storage.
  3. Open Cline and run a prompt that explicitly says to use context7.
  4. Run another prompt that explicitly invokes or depends on the installed skill.
"@
      }
      'claude-code' {
        Note @"
- claude-code:
  1. Run: claude mcp list
  2. Inside Claude Code, run: /mcp
  3. Invoke /test-skill or ask: What skills are available?
"@
      }
      'opencode' {
        Note @"
- opencode:
  1. Run: opencode mcp list
  2. Optionally run: opencode mcp debug context7
  3. Open an OpenCode session and inspect the available skills / invoke the installed skill in a task.
"@
      }
      'codex' {
        Note @"
- codex:
  1. Open Codex CLI or TUI.
  2. Run /mcp in the TUI, or inspect the Codex config file for the configured server.
  3. Run /skills and confirm the skill is listed.
  4. Invoke the skill explicitly with the Codex skill picker or prompt.
"@
      }
      'cursor' {
        Note @"
- cursor:
  1. Inspect the tool's MCP/skills settings UI or config file.
  2. Confirm the test skill folder and Context7 server entry are present.
  3. Run one prompt that explicitly asks the tool to use context7 and another that invokes the installed skill.
"@
      }
      'windsurf' {
        Note @"
- windsurf:
  1. Inspect the tool's MCP/skills settings UI or config file.
  2. Confirm the test skill folder and Context7 server entry are present.
  3. Run one prompt that explicitly asks the tool to use context7 and another that invokes the installed skill.
"@
      }
      'continue' {
        Note @"
- continue:
  1. Inspect the tool's MCP/skills settings UI or config file.
  2. Confirm the test skill folder and Context7 server entry are present.
  3. Run one prompt that explicitly asks the tool to use context7 and another that invokes the installed skill.
"@
      }
      'goose' {
        Note @"
- goose:
  1. Inspect the tool's MCP/skills settings UI or config file.
  2. Confirm the test skill folder and Context7 server entry are present.
  3. Run one prompt that explicitly asks the tool to use context7 and another that invokes the installed skill.
"@
      }
      'roo' {
        Note @"
- roo:
  1. Inspect the tool's MCP/skills settings UI or config file.
  2. Confirm the test skill folder and Context7 server entry are present.
  3. Run one prompt that explicitly asks the tool to use context7 and another that invokes the installed skill.
"@
      }
      'gemini-cli' {
        Note @"
- gemini-cli:
  1. Inspect the tool's MCP/skills settings UI or config file.
  2. Confirm the test skill folder and Context7 server entry are present.
  3. Run one prompt that explicitly asks the tool to use context7 and another that invokes the installed skill.
"@
      }
    }
  }
}

function Select-Tools {
  $detectedTools = Get-DetectedTools

  if ($detectedTools.Count -gt 0) {
    Note "$(Format-Label 'Detected tools:') $(Format-Value (Join-Items ', ' $detectedTools))"
  } else {
    Note "$(Format-Label 'Detected tools:') $(Format-Value '(none)')"
  }

  Note "$(Format-Label 'Available tool ids:') $(Join-Items ', ' $script:KnownTools)"

  Debug-Section 'Detected tools'
  if ($detectedTools.Count -gt 0) {
    Debug-Note (Join-Items ', ' $detectedTools)
  } else {
    Debug-Note '(none detected)'
  }

  while ($true) {
    $additionalCsv = $script:Options.AdditionalToolsCsv
    $skippedManualSelection = $false
    Phase 1 5 'Selecting tools'

    if (-not $script:Options.NonInteractive -and [string]::IsNullOrWhiteSpace($additionalCsv)) {
      $additionalCsv = Read-Host 'Enter any additional tool ids to configure (comma-separated, or blank for none)'
    }

    $additionalTools = Split-CsvToArray $additionalCsv
    $invalidTools = @($additionalTools | Where-Object { -not (Test-KnownTool $_) })
    if ($invalidTools.Count -gt 0) {
      Warn ("The following tool ids are not recognised and will be skipped: {0}" -f (Join-Items ', ' $invalidTools))
      Note "$(Format-Label 'Known tool ids:') $(Join-Items ', ' $script:KnownTools)"
    }

    $mergedTools = Merge-KnownTools $detectedTools $additionalTools
    $mergedDefault = Join-Items ',' $mergedTools
    $defaultValue = if ([string]::IsNullOrWhiteSpace($mergedDefault)) { '<none>' } else { $mergedDefault }
    Note "$(Format-Label 'Default selected tools:') $(Format-Value $defaultValue)"

    $finalCsv = $script:Options.ToolsCsv
    if ([string]::IsNullOrWhiteSpace($finalCsv)) {
      if ($script:Options.NonInteractive) {
        $finalCsv = $mergedDefault
      } elseif ([string]::IsNullOrWhiteSpace($additionalCsv)) {
        $finalCsv = $mergedDefault
        $skippedManualSelection = $true
      } else {
        $prompt = "Choose tools to install into [{0}]" -f $mergedDefault
        $manual = Read-Host $prompt
        $finalCsv = if ([string]::IsNullOrWhiteSpace($manual)) { $mergedDefault } else { $manual }
      }
    }

    $validatedTools = Validate-KnownTools (Split-CsvToArray $finalCsv)
    if ($validatedTools.Count -eq 0) {
      Fail 'No valid tools selected'
    }

    Note "$(Format-Label 'Selected tools:') $(Format-Value (Join-Items ', ' $validatedTools))"
    if ($skippedManualSelection) {
      Debug-Note 'Skipped manual tool selection because no additional tools were entered'
    }

    if ($script:Options.NonInteractive) {
      return $validatedTools
    }

    Write-Host 'Tools to configure:'
    foreach ($tool in $validatedTools) {
      Write-Host "  - $tool"
    }
    $confirm = Read-Host 'Proceed with installation? [y/N]'
    if ($confirm -match '^(?i:y|yes)$') {
      return $validatedTools
    }

    Note 'Restarting tool selection...'
    $script:Options.ToolsCsv = ''
    $script:Options.AdditionalToolsCsv = ''
  }
}

function Main([string[]]$CliArgs) {
  Parse-Args $CliArgs
  if ($script:Options.DryRun -and -not $script:Options.NonInteractive) {
    $script:Options.NonInteractive = $true
  }

  Ensure-LogFile
  Note "$(Format-Label 'Version:') $(Format-Value $script:Version)"
  if ($script:Options.DryRun) {
    Note "$(Format-Label 'Mode:') $(Format-Value 'dry-run (non-interactive preview)')"
  }
  Ensure-Prereqs

  Write-Host "`nAgentic Tools Setup v$($script:Version)"
  Debug-Section 'Environment'
  Debug-Note "script_dir=$($script:ScriptDir)"
  Debug-Note "log_file=$($script:Options.LogFile)"
  Debug-Note ("non_interactive={0} dry_run={1} verbose={2} copy_skills={3} skip_skills={4} skip_mcp={5} skip_verify={6}" -f $script:Options.NonInteractive, $script:Options.DryRun, $script:Options.Verbose, $script:Options.CopySkills, $script:Options.SkipSkills, $script:Options.SkipMcp, $script:Options.SkipVerify)
  Debug-Note "tools_csv=$($script:Options.ToolsCsv)"
  Debug-Note "extra_tools_csv=$($script:Options.AdditionalToolsCsv)"
  Debug-Note ("context7_api_key_provided={0}" -f (-not [string]::IsNullOrWhiteSpace($script:Options.Context7ApiKey)))

  $validatedTools = Select-Tools

  $apiKey = $script:Options.Context7ApiKey
  if (-not $script:Options.NonInteractive -and [string]::IsNullOrWhiteSpace($apiKey)) {
    $apiKey = Read-Host 'Optional Context7 API key (press Enter to skip)'
  }

  if (-not $script:Options.SkipSkills) {
    Phase 2 5 'Installing skills'
    Install-Skill $validatedTools
  } else {
    Log 'Skipping skills installation'
  }

  if (-not $script:Options.SkipMcp) {
    Phase 3 5 'Installing and wiring MCP'
    Install-Context7Server $apiKey
    Wire-Context7ToTools $validatedTools
  } else {
    Log 'Skipping MCP installation'
  }

  if (-not $script:Options.SkipVerify) {
    Phase 4 5 'Running verification'
    Run-Verification $validatedTools
  } else {
    Log 'Skipping verification'
  }

  Phase 5 5 'Printing manual follow-up steps'
  Print-ManualVerificationInstructions $validatedTools

  Log 'Done'
  Note "$(Format-Label 'Configured tools:') $(Format-Value (Join-Items ', ' $validatedTools))"
  Note "$(Format-Label 'Skill source:') $(Format-Value $script:SkillSource)"
  Note "$(Format-Label 'MCP server:') $(Format-Value $script:Context7ServerName)"
  Note "$(Format-Label 'Log file:') $(Format-Value $script:Options.LogFile)"
}

try {
  Main $args
} catch {
  Write-Error $_
  exit 1
}
