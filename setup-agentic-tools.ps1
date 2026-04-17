#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Version = '1.1.0'
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:SkillSources = @(
  'Linksofteu/LinkSoft_Skills@test-skill',
  'Linksofteu/LinkSoft_Skills@ddd-application-slice',
  'Linksofteu/LinkSoft_Skills@creating-linksoft-skills'
)
$script:SkillNames = @(
  'test-skill',
  'ddd-application-slice',
  'creating-linksoft-skills'
)
$script:Context7ServerName = 'context7'
$script:Context7Url = 'https://mcp.context7.com/mcp'
$script:FigmaServerName = 'figma'
$script:FigmaUrl = 'https://mcp.figma.com/mcp'
$script:FigmaRegisterUrl = 'https://api.figma.com/v1/oauth/mcp/register'
$script:FigmaOpenCodeRedirectUri = 'http://127.0.0.1:19876/mcp/oauth/callback'
$script:BrowserMcpExtensionUrl = 'https://chromewebstore.google.com/detail/browser-mcp-automate-your/bjfgambnhccakkhmkepdoekmckoijdlc?pli=1'
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
  EnableFigma = $true
  FigmaClientId = ''
  FigmaClientSecret = ''
  SkipSkills = $false
  SkipMcp = $false
  SkipVerify = $false
}

$script:VerifyPassCount = 0
$script:VerifyFailCount = 0
$script:VerifySkipCount = 0
$script:VerifyFailedLabels = @()

function Get-DefaultLogRoot {
  if (-not [string]::IsNullOrWhiteSpace($env:XDG_STATE_HOME)) {
    return (Join-Path $env:XDG_STATE_HOME 'linksoft-agent-installer/logs')
  }

  $localAppData = Get-LocalAppDataPath
  if (-not [string]::IsNullOrWhiteSpace($localAppData)) {
    return (Join-Path $localAppData 'linksoft-agent-installer/logs')
  }

  return (Join-Path (Get-HomePath) '.linksoft-agent-installer/logs')
}

function Get-DefaultLogFile {
  return (Join-Path (Get-DefaultLogRoot) ('setup-agentic-tools-{0}.log' -f ([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ'))))
}

$script:DefaultLogFile = Get-DefaultLogFile

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

function Show-LogHint {
  if (-not [string]::IsNullOrWhiteSpace($script:Options.LogFile)) {
    Write-Host ("Log file: {0}" -f $script:Options.LogFile)
  }
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
function Get-ClaudeCodeConfigPath { Join-Path (Get-HomePath) '.claude.json' }
function Get-CodexConfigPath { Join-Path (Join-Path (Get-HomePath) '.codex') 'config.toml' }
function Get-ClineMcpPath { Join-Path (Get-AppDataPath) 'Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json' }
function Get-ContinueMcpPath { Join-Path (Join-Path (Get-HomePath) '.continue\mcpServers') "$($script:Context7ServerName).json" }
function Get-GeminiSettingsPath { Join-Path (Join-Path (Get-HomePath) '.gemini') 'settings.json' }

function Get-ToolSkillStaticPaths([string]$Tool) {
  $userHome = Get-HomePath
  $basePath = $null
  switch ($Tool) {
    'opencode' { $basePath = Join-Path $userHome '.agents\skills' }
    'codex' { $basePath = Join-Path $userHome '.agents\skills' }
    'github-copilot-cli' { $basePath = Join-Path $userHome '.agents\skills' }
    'github-copilot' { $basePath = Join-Path $userHome '.agents\skills' }
    'cline' { $basePath = Join-Path $userHome '.agents\skills' }
    'cursor' { $basePath = Join-Path $userHome '.agents\skills' }
    'gemini-cli' { $basePath = Join-Path $userHome '.agents\skills' }
    'claude-code' { $basePath = Join-Path $userHome '.claude\skills' }
    'windsurf' { $basePath = Join-Path $userHome '.codeium\windsurf\skills' }
    'continue' { $basePath = Join-Path $userHome '.continue\skills' }
    'goose' { $basePath = Join-Path $userHome '.config\goose\skills' }
    'roo' { $basePath = Join-Path $userHome '.roo\skills' }
    'vscode' { $basePath = Join-Path $userHome '.agents\skills' }
    default { return @() }
  }

  return @($script:SkillNames | ForEach-Object { Join-Path $basePath ("{0}\SKILL.md" -f $_) })
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
  return @('opencode', 'claude-code', 'codex', 'gemini-cli') -contains $Tool
}

function Test-ToolSupportsFigmaMcp([string]$Tool) {
  return @('opencode') -contains $Tool
}

function Test-SelectedToolsSupportFigma([string[]]$Tools) {
  foreach ($tool in $Tools) {
    if (Test-ToolSupportsFigmaMcp $tool) { return $true }
  }
  return $false
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

Installs the default LinkSoft skills via npx skills, installs/configures Context7,
optionally wires Figma MCP for supported tools, then runs static and smoke
verification where supported.

Version: $($script:Version)

Options:
  --tools CSV              Final tool ids to configure
  --extra-tools CSV        Additional tool ids to merge with detected tools
  --context7-api-key KEY   Optional Context7 API key
  --figma                  Enable Figma MCP wiring where supported (default)
  --figma-client-id ID     Pre-registered Figma OAuth client id
  --figma-client-secret S  Pre-registered Figma OAuth client secret
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
      '--figma' {
        $script:Options.EnableFigma = $true
        $i += 1
        continue
      }
      '--figma-client-id' {
        if ($i + 1 -ge $CliArgs.Count) { Fail '--figma-client-id requires a value' }
        $script:Options.FigmaClientId = $CliArgs[$i + 1]
        $script:Options.EnableFigma = $true
        $i += 2
        continue
      }
      '--figma-client-secret' {
        if ($i + 1 -ge $CliArgs.Count) { Fail '--figma-client-secret requires a value' }
        $script:Options.FigmaClientSecret = $CliArgs[$i + 1]
        $script:Options.EnableFigma = $true
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
    Append-Log ("FAIL({0}): {1}" -f $exitCode, $rendered)
    Fail "Command failed with exit code ${exitCode}: $rendered"
  }
  Append-Log ("OK: {0}" -f $rendered)
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
}

function Show-NpmUserPrefixGuidance {
  $homePath = Get-HomePath
  Note 'To avoid sudo for global npm packages, configure npm to use a user-owned directory:'
  Note ("  mkdir -p `"{0}/.npm-global`"" -f $homePath)
  Note ("  npm config set prefix `"{0}/.npm-global`"" -f $homePath)
  Note ("  export PATH=`"{0}/.npm-global/bin:`$PATH`"" -f $homePath)
  Note 'Then add that export line to your shell profile (for example ~/.bashrc), reload your shell, and rerun this installer.'
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
    $result = Invoke-CaptureCommandOutput @('npm', 'install', '-g', 'openspec')
    if (-not $result.Success) {
      if (-not [string]::IsNullOrWhiteSpace($result.Output)) {
        Write-Host $result.Output
      }
      Warn 'Automatic openspec installation failed. This is commonly caused by npm global install permissions.'
      Show-NpmUserPrefixGuidance
      Fail 'Unable to install openspec automatically'
    }
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

  for ($i = 0; $i -lt $script:SkillSources.Count; $i++) {
    $command = New-Object System.Collections.Generic.List[string]
    foreach ($item in @('npx', '-y', 'skills', 'add', $script:SkillSources[$i], '-g', '-y')) { $command.Add($item) }
    if ($script:Options.CopySkills) { $command.Add('--copy') }
    foreach ($agent in $skillAgents) {
      $command.Add('-a')
      $command.Add($agent)
    }

    Log ("Installing LinkSoft skill: {0}" -f $script:SkillNames[$i])
    Debug-Note ("skills.sh targets: {0}" -f (Join-Items ', ' $skillAgents))
    [void](Invoke-ExternalCommand -Command ([string[]]$command))
  }
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
    Copy-Item -Path $Path -Destination ("{0}.bak.{1}" -f $Path, [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()) -Force
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

function New-Context7Headers([string]$ApiKey) {
  if ([string]::IsNullOrWhiteSpace($ApiKey)) { return $null }
  return [ordered]@{ CONTEXT7_API_KEY = $ApiKey }
}

function Configure-JsonContext7Server([string]$Path, [string]$Mode, [string]$ApiKey) {
  $parent = Split-Path -Parent $Path
  if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  Backup-FileIfPresent $Path
  $headers = New-Context7Headers $ApiKey
  $data = Read-JsoncDocument $Path

  switch ($Mode) {
    'opencode' {
      Set-JsonPropertyValue $data '$schema' 'https://opencode.ai/config.json'
      $mcp = Ensure-JsonObjectProperty $data 'mcp'
      $value = [ordered]@{
        type = 'remote'
        url = $script:Context7Url
        enabled = $true
      }
      if ($null -ne $headers) { $value['headers'] = $headers }
      Set-JsonPropertyValue $mcp $script:Context7ServerName ([pscustomobject]$value)
    }
    'vscode' {
      $servers = Ensure-JsonObjectProperty $data 'servers'
      $inputs = Get-JsonPropertyValue $data 'inputs'
      if ($null -eq $inputs) { Set-JsonPropertyValue $data 'inputs' @() }
      $value = [ordered]@{
        type = 'http'
        url = $script:Context7Url
      }
      if ($null -ne $headers) { $value['headers'] = $headers }
      Set-JsonPropertyValue $servers $script:Context7ServerName ([pscustomobject]$value)
    }
    'copilot-cli' {
      $legacyServers = Get-JsonPropertyValue $data 'servers'
      $mcpServers = Ensure-JsonObjectProperty $data 'mcpServers'
      if (Test-JsonObject $legacyServers) {
        foreach ($prop in $legacyServers.PSObject.Properties) {
          if ($null -eq (Get-JsonPropertyValue $mcpServers $prop.Name)) {
            Set-JsonPropertyValue $mcpServers $prop.Name $prop.Value
          }
        }
      }
      $value = [ordered]@{
        type = 'http'
        url = $script:Context7Url
        tools = @('*')
      }
      if ($null -ne $headers) { $value['headers'] = $headers }
      Set-JsonPropertyValue $mcpServers $script:Context7ServerName ([pscustomobject]$value)
    }
    'claude-code' {
      $mcpServers = Ensure-JsonObjectProperty $data 'mcpServers'
      $value = [ordered]@{
        type = 'http'
        url = $script:Context7Url
      }
      if ($null -ne $headers) { $value['headers'] = $headers }
      Set-JsonPropertyValue $mcpServers $script:Context7ServerName ([pscustomobject]$value)
    }
    'cline' {
      $mcpServers = Ensure-JsonObjectProperty $data 'mcpServers'
      $value = [ordered]@{
        url = $script:Context7Url
        disabled = $false
      }
      if ($null -ne $headers) { $value['headers'] = $headers }
      Set-JsonPropertyValue $mcpServers $script:Context7ServerName ([pscustomobject]$value)
    }
    'continue' {
      $server = [ordered]@{
        type = 'http'
        url = $script:Context7Url
      }
      if ($null -ne $headers) { $server['headers'] = $headers }
      $data = [ordered]@{ mcpServers = [ordered]@{ $script:Context7ServerName = [pscustomobject]$server } }
    }
    'gemini' {
      $mcpServers = Ensure-JsonObjectProperty $data 'mcpServers'
      $value = [ordered]@{
        httpUrl = $script:Context7Url
        timeout = 600000
      }
      if ($null -ne $headers) { $value['headers'] = $headers }
      Set-JsonPropertyValue $mcpServers $script:Context7ServerName ([pscustomobject]$value)
    }
    default {
      Fail "Unsupported JSON config mode: $Mode"
    }
  }

  Write-JsonDocument $Path $data
}

function Configure-OpenCodeFigma([string]$ClientId, [string]$ClientSecret) {
  Log 'Configuring OpenCode with direct Figma MCP'
  $path = Get-OpenCodeConfigPath
  if ($script:Options.DryRun) {
    Note "Would update $path with a Figma remote MCP entry"
    return
  }

  Backup-FileIfPresent $path
  $data = Read-JsoncDocument $path
  Set-JsonPropertyValue $data '$schema' 'https://opencode.ai/config.json'
  $mcp = Ensure-JsonObjectProperty $data 'mcp'
  $value = [ordered]@{
    enabled = $true
    type = 'remote'
    url = $script:FigmaUrl
  }
  if (-not [string]::IsNullOrWhiteSpace($ClientId) -or -not [string]::IsNullOrWhiteSpace($ClientSecret)) {
    $oauth = [ordered]@{}
    if (-not [string]::IsNullOrWhiteSpace($ClientId)) {
      $oauth.clientId = $ClientId
    }
    if (-not [string]::IsNullOrWhiteSpace($ClientSecret)) {
      $oauth.clientSecret = $ClientSecret
    }
    $value.oauth = [pscustomobject]$oauth
  }
  Set-JsonPropertyValue $mcp $script:FigmaServerName ([pscustomobject]$value)
  Write-JsonDocument $path $data
}

function Register-FigmaOpenCodeClient {
  $body = [ordered]@{
    client_name = 'LinkSoft Agent Installer (opencode)'
    redirect_uris = @($script:FigmaOpenCodeRedirectUri)
    grant_types = @('authorization_code', 'refresh_token')
    response_types = @('code')
    token_endpoint_auth_method = 'none'
  } | ConvertTo-Json -Depth 10

  if ($script:Options.DryRun) {
    Note "Would register a Figma OAuth client for OpenCode using callback $($script:FigmaOpenCodeRedirectUri)"
    return
  }

  try {
    $rawResponse = Invoke-WebRequest -Method Post -Uri $script:FigmaRegisterUrl -ContentType 'application/json' -Body $body
  } catch {
    Fail "Failed to register Figma OAuth client for OpenCode: $($_.Exception.Message)"
  }

  try {
    $response = $rawResponse.Content | ConvertFrom-Json
  } catch {
    Fail "Failed to parse Figma OAuth registration response for OpenCode: $($_.Exception.Message). Raw response: $($rawResponse.Content)"
  }

  if ([string]::IsNullOrWhiteSpace($response.client_id) -or [string]::IsNullOrWhiteSpace($response.client_secret)) {
    Fail "Figma OAuth registration response did not include client_id and client_secret. Raw response: $($rawResponse.Content)"
  }

  $script:Options.FigmaClientId = $response.client_id
  $script:Options.FigmaClientSecret = $response.client_secret
  Note "Registered a Figma OAuth client for OpenCode using callback $($script:FigmaOpenCodeRedirectUri)"
}

function Ensure-FigmaOpenCodeCredentials {
  if (-not [string]::IsNullOrWhiteSpace($script:Options.FigmaClientId) -and -not [string]::IsNullOrWhiteSpace($script:Options.FigmaClientSecret)) {
    return
  }
  Register-FigmaOpenCodeClient
}

function Clear-OpenCodeFigmaAuthCache {
  if ($script:Options.DryRun) {
    Note "Would remove the '$($script:FigmaServerName)' entry from ~/.local/share/opencode/mcp-auth.json if present"
    return
  }

  $path = Join-Path $HOME '.local/share/opencode/mcp-auth.json'
  if (-not (Test-Path -LiteralPath $path)) {
    return
  }

  try {
    $data = Read-JsonDocument $path
  } catch {
    return
  }

  if ($null -eq $data -or $null -eq ($data.PSObject.Properties[$script:FigmaServerName])) {
    return
  }

  Backup-FileIfPresent $path
  $data.PSObject.Properties.Remove($script:FigmaServerName)
  Write-JsonDocument $path $data
  Note "Cleared any cached OpenCode auth state for '$($script:FigmaServerName)'"
}

function Invoke-OpenCodeFigmaAuth {
  if ($script:Options.DryRun) {
    Note "Would clear cached OpenCode auth state for '$($script:FigmaServerName)'"
    Note "Would run: opencode mcp auth $($script:FigmaServerName)"
    return
  }

  if (-not (Test-CommandExists 'opencode')) {
    Warn 'OpenCode executable not found; skipping automatic Figma OAuth login'
    return
  }

  Clear-OpenCodeFigmaAuthCache
  [void](Invoke-ExternalCommand -Command @('opencode', 'mcp', 'logout', $script:FigmaServerName) -IgnoreExitCode)
  Note 'Starting OpenCode OAuth login for Figma using pre-registered client credentials; your browser may open for consent'
  [void](Invoke-ExternalCommand -Command @('opencode', 'mcp', 'auth', $script:FigmaServerName))
}

function Configure-OpenCode([string]$ApiKey) {
  Log 'Configuring OpenCode with direct Context7 MCP'
  $path = Get-OpenCodeConfigPath
  if ($script:Options.DryRun) { Note "Would update $path"; return }
  Configure-JsonContext7Server -Path $path -Mode 'opencode' -ApiKey $ApiKey
}

function Configure-ClaudeCode([string]$ApiKey) {
  Log 'Configuring Claude Code MCP settings'
  $path = Get-ClaudeCodeConfigPath
  if ($script:Options.DryRun) { Note "Would update $path"; return }
  Configure-JsonContext7Server -Path $path -Mode 'claude-code' -ApiKey $ApiKey
}

function Configure-Codex([string]$ApiKey) {
  Log 'Configuring Codex MCP settings'
  $path = Get-CodexConfigPath
  if ($script:Options.DryRun) { Note "Would update $path"; return }

  Backup-FileIfPresent $path
  $parent = Split-Path -Parent $path
  if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
  $content = if (Test-Path $path) { Get-Content -Path $path -Raw } else { '' }

  $section = @("[mcp_servers.$($script:Context7ServerName)]", "url = `"$($script:Context7Url)`"")
  if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
    $section += "http_headers = { CONTEXT7_API_KEY = `"$ApiKey`" }"
  }
  $sectionText = (($section -join [Environment]::NewLine) + [Environment]::NewLine)

  $pattern = "(?ms)^\[mcp_servers\.$([regex]::Escape($script:Context7ServerName))\]\r?\n.*?(?=^\[|\z)"
  if ($content -match $pattern) {
    $updated = [regex]::Replace($content, $pattern, $sectionText).TrimEnd() + [Environment]::NewLine
  } else {
    $updated = $content.TrimEnd()
    if (-not [string]::IsNullOrWhiteSpace($updated)) {
      $updated += [Environment]::NewLine + [Environment]::NewLine
    }
    $updated += $sectionText
  }

  Set-Content -Path $path -Value $updated -Encoding UTF8
}

function Configure-VSCode([string]$ApiKey) {
  Log 'Configuring VS Code MCP file'
  $path = Get-VSCodeMcpPath
  if ($script:Options.DryRun) { Note "Would update $path"; return }
  Configure-JsonContext7Server -Path $path -Mode 'vscode' -ApiKey $ApiKey
}

function Configure-GitHubCopilotCli([string]$ApiKey) {
  Log 'Configuring GitHub Copilot CLI MCP file'
  $path = Get-CopilotConfigPath
  if ($script:Options.DryRun) { Note "Would update $path"; return }
  Configure-JsonContext7Server -Path $path -Mode 'copilot-cli' -ApiKey $ApiKey
}

function Configure-Cline([string]$ApiKey) {
  Log 'Configuring Cline MCP settings'
  $path = Get-ClineMcpPath
  if ($script:Options.DryRun) { Note "Would update $path"; return }
  Configure-JsonContext7Server -Path $path -Mode 'cline' -ApiKey $ApiKey
}

function Configure-Continue([string]$ApiKey) {
  Log 'Configuring Continue MCP settings'
  $path = Get-ContinueMcpPath
  if ($script:Options.DryRun) { Note "Would update $path"; return }
  Configure-JsonContext7Server -Path $path -Mode 'continue' -ApiKey $ApiKey
}

function Configure-GeminiCli([string]$ApiKey) {
  Log 'Configuring Gemini CLI MCP settings'
  $path = Get-GeminiSettingsPath
  if ($script:Options.DryRun) { Note "Would update $path"; return }
  Configure-JsonContext7Server -Path $path -Mode 'gemini' -ApiKey $ApiKey
}

function Install-Context7Server([string]$ApiKey) {
  Log 'Preparing direct Context7 MCP configuration'

  if ($script:Options.DryRun) {
    Note "Would configure supported tools with a direct remote MCP entry for '$($script:Context7ServerName)'"
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) {
      Note 'Would include a Context7 API key header in supported tool configurations'
    }
    return
  }

  Note 'No standalone MCP manager is used; supported tools are configured directly'
}

function Install-FigmaServer {
  Log 'Preparing direct Figma MCP configuration'

  if ($script:Options.DryRun) {
    Note "Would configure supported tools with a direct remote MCP entry for '$($script:FigmaServerName)'"
    Note 'Would use each tool''s native OAuth/browser flow when available'
    return
  }

  Note 'Figma MCP is only wired for tools with a documented native OAuth/browser flow'
}

function Wire-Context7ToTool([string]$Tool, [string]$ApiKey) {
  switch ($Tool) {
    'opencode' { Configure-OpenCode $ApiKey; return }
    'claude-code' { Configure-ClaudeCode $ApiKey; return }
    'codex' { Configure-Codex $ApiKey; return }
    'vscode' { Configure-VSCode $ApiKey; return }
    'github-copilot-cli' { Configure-GitHubCopilotCli $ApiKey; return }
    'cline' { Configure-Cline $ApiKey; return }
    'continue' { Configure-Continue $ApiKey; return }
    'gemini-cli' { Configure-GeminiCli $ApiKey; return }
    'github-copilot' {
      Warn "No standalone GitHub Copilot MCP file is configured here; use the 'vscode' target for Copilot-in-VS-Code MCP wiring"
      return
    }
    default {
      Warn "No direct MCP wiring strategy is defined for $Tool"
      return
    }
  }
}

function Wire-Context7ToTools([string]$ApiKey, [string[]]$Tools) {
  foreach ($tool in $Tools) {
    Wire-Context7ToTool $tool $ApiKey
  }
}

function Wire-FigmaToTool([string]$Tool) {
  switch ($Tool) {
    'opencode' {
      Ensure-FigmaOpenCodeCredentials
      Configure-OpenCodeFigma $script:Options.FigmaClientId $script:Options.FigmaClientSecret
      Invoke-OpenCodeFigmaAuth
      return
    }
    'github-copilot' {
      Warn 'Figma MCP is not wired automatically for GitHub Copilot here; use a tool with a native CLI OAuth flow'
      return
    }
    default {
      Warn "No native Figma MCP wiring strategy is defined for $Tool"
      return
    }
  }
}

function Wire-FigmaToTools([string[]]$Tools) {
  foreach ($tool in $Tools) {
    Wire-FigmaToTool $tool
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

    $missingPaths = New-Object System.Collections.Generic.List[string]
    $foundCount = 0
    foreach ($path in $paths) {
      if (Test-Path $path) {
        $foundCount += 1
      } else {
        $missingPaths.Add($path) | Out-Null
      }
    }

    if ($missingPaths.Count -eq 0) {
      Report-VerificationCheck 'PASS' "skills/$tool" "found all $foundCount expected skill files"
    } else {
      Report-VerificationCheck 'FAIL' "skills/$tool" ("missing expected skill file in: {0}" -f (Join-Items ', ' $missingPaths))
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

  $escapedServerName = [regex]::Escape("`"$($script:Context7ServerName)`"")
  $escapedFigmaName = [regex]::Escape("`"$($script:FigmaServerName)`"")
  $escapedUrl = [regex]::Escape($script:Context7Url)
  foreach ($tool in $Tools) {
    switch ($tool) {
      'opencode' {
        $path = Get-OpenCodeConfigPath
        $content = if (Test-Path $path) { Get-Content -Path $path -Raw } else { $null }
        if ($content -and ($content -match $escapedServerName) -and ($content -match '"type":\s*"remote"')) {
          Report-VerificationCheck 'PASS' 'mcp/opencode' "OpenCode config contains a direct $($script:Context7ServerName) remote server"
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/opencode' "OpenCode config missing $($script:Context7ServerName)"
        }
        if ($script:Options.EnableFigma) {
          if ($content -and ($content -match $escapedFigmaName) -and ($content -match '"clientId"')) {
            Report-VerificationCheck 'PASS' 'mcp-figma/opencode' "OpenCode config contains a direct $($script:FigmaServerName) remote server"
          } else {
            Report-VerificationCheck 'FAIL' 'mcp-figma/opencode' "OpenCode config missing $($script:FigmaServerName)"
          }
        }
        continue
      }
      'claude-code' {
        $path = Get-ClaudeCodeConfigPath
        $content = if (Test-Path $path) { Get-Content -Path $path -Raw } else { $null }
        if ($content -and ($content -match '"mcpServers"') -and ($content -match $escapedServerName)) {
          Report-VerificationCheck 'PASS' 'mcp/claude-code' "Claude Code config contains $($script:Context7ServerName)"
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/claude-code' "Claude Code config missing $($script:Context7ServerName)"
        }
        continue
      }
      'codex' {
        $path = Get-CodexConfigPath
        $content = if (Test-Path $path) { Get-Content -Path $path -Raw } else { $null }
        $tomlSection = '(?m)^\[mcp_servers\.' + [regex]::Escape($script:Context7ServerName) + '\]'
        $tomlUrl = 'url = "' + $escapedUrl + '"'
        if ($content -and ($content -match $tomlSection) -and ($content -match $tomlUrl)) {
          Report-VerificationCheck 'PASS' 'mcp/codex' "Codex config.toml contains $($script:Context7ServerName)"
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/codex' "Codex config.toml missing $($script:Context7ServerName)"
        }
        continue
      }
      'vscode' {
        $path = Get-VSCodeMcpPath
        $content = if (Test-Path $path) { Get-Content -Path $path -Raw } else { $null }
        if ($content -and ($content -match $escapedServerName) -and ($content -match ('"url":\s*"' + $escapedUrl + '"'))) {
          Report-VerificationCheck 'PASS' 'mcp/vscode' "VS Code mcp.json contains $($script:Context7ServerName)"
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/vscode' "VS Code mcp.json missing $($script:Context7ServerName)"
        }
        continue
      }
      'github-copilot-cli' {
        $path = Get-CopilotConfigPath
        $content = if (Test-Path $path) { Get-Content -Path $path -Raw } else { $null }
        if ($content -and ($content -match '"mcpServers"') -and ($content -match $escapedServerName)) {
          Report-VerificationCheck 'PASS' 'mcp/github-copilot-cli' "Copilot CLI mcp-config.json contains $($script:Context7ServerName)"
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/github-copilot-cli' "Copilot CLI mcp-config.json missing $($script:Context7ServerName)"
        }
        continue
      }
      'github-copilot' {
        Report-VerificationCheck 'SKIP' 'mcp/github-copilot' 'use the vscode target for Copilot-in-VS-Code MCP verification'
        continue
      }
      'cline' {
        $path = Get-ClineMcpPath
        $content = if (Test-Path $path) { Get-Content -Path $path -Raw } else { $null }
        if ($content -and ($content -match '"mcpServers"') -and ($content -match $escapedServerName)) {
          Report-VerificationCheck 'PASS' 'mcp/cline' "Cline MCP settings contain $($script:Context7ServerName)"
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/cline' "Cline MCP settings missing $($script:Context7ServerName)"
        }
        continue
      }
      'continue' {
        $path = Get-ContinueMcpPath
        $content = if (Test-Path $path) { Get-Content -Path $path -Raw } else { $null }
        if ($content -and ($content -match $escapedServerName) -and ($content -match ('"url":\s*"' + $escapedUrl + '"'))) {
          Report-VerificationCheck 'PASS' 'mcp/continue' "Continue MCP config contains $($script:Context7ServerName)"
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/continue' "Continue MCP config missing $($script:Context7ServerName)"
        }
        continue
      }
      'gemini-cli' {
        $path = Get-GeminiSettingsPath
        $content = if (Test-Path $path) { Get-Content -Path $path -Raw } else { $null }
        if ($content -and ($content -match '"mcpServers"') -and ($content -match $escapedServerName)) {
          Report-VerificationCheck 'PASS' 'mcp/gemini-cli' "Gemini CLI settings contain $($script:Context7ServerName)"
        } else {
          Report-VerificationCheck 'FAIL' 'mcp/gemini-cli' "Gemini CLI settings missing $($script:Context7ServerName)"
        }
        continue
      }
    }

    Report-VerificationCheck 'SKIP' "mcp/$tool" 'no static MCP verification rule defined'
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
      $missingSkills = @($script:SkillNames | Where-Object { $result.Output -notmatch [regex]::Escape($_) })
      if ($missingSkills.Count -eq 0) {
        $details = "skills.sh fallback for $agent included $(Join-Items ', ' $script:SkillNames)"
        if (-not [string]::IsNullOrWhiteSpace($hint)) { $details += "; native check available manually via $hint" }
        Report-VerificationCheck 'PASS' "skills-cli/$tool" $details
      } else {
        $details = "skills.sh fallback for $agent is missing $(Join-Items ', ' $missingSkills)"
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

  foreach ($tool in $Tools) {
    if (-not (Test-ToolHasMcpCliCheck $tool)) {
      Report-VerificationCheck 'SKIP' "mcp-cli/$tool" 'no documented CLI check found'
      continue
    }

    $escapedName = [regex]::Escape($script:Context7ServerName)
    switch ($tool) {
      'opencode' {
        if (-not (Test-CommandExists 'opencode')) {
          Report-VerificationCheck 'SKIP' 'mcp-cli/opencode' 'opencode executable not found'
        } else {
          $result = Invoke-CaptureCommandOutput @('opencode', 'mcp', 'list')
          if ($result.Success -and $result.Output -match $escapedName) {
            Report-VerificationCheck 'PASS' 'mcp-cli/opencode' "opencode mcp list included $($script:Context7ServerName)"
          } elseif ($result.Success) {
            Report-VerificationCheck 'FAIL' 'mcp-cli/opencode' "opencode mcp list did not include $($script:Context7ServerName)"
          } else {
            Report-VerificationCheck 'FAIL' 'mcp-cli/opencode' 'unable to query opencode mcp list'
          }
          if ($script:Options.EnableFigma) {
            $escapedFigmaCliName = [regex]::Escape($script:FigmaServerName)
            if ($result.Success -and $result.Output -match $escapedFigmaCliName) {
              Report-VerificationCheck 'PASS' 'mcp-cli-figma/opencode' "opencode mcp list included $($script:FigmaServerName)"
            } elseif ($result.Success) {
              Report-VerificationCheck 'FAIL' 'mcp-cli-figma/opencode' "opencode mcp list did not include $($script:FigmaServerName)"
            } else {
              Report-VerificationCheck 'FAIL' 'mcp-cli-figma/opencode' "unable to query opencode mcp list for $($script:FigmaServerName)"
            }
          }
        }
      }
      'claude-code' {
        if (-not (Test-CommandExists 'claude')) {
          Report-VerificationCheck 'SKIP' 'mcp-cli/claude-code' 'claude executable not found'
        } else {
          $result = Invoke-CaptureCommandOutput @('claude', 'mcp', 'list')
          if ($result.Success -and $result.Output -match $escapedName) {
            Report-VerificationCheck 'PASS' 'mcp-cli/claude-code' "claude mcp list included $($script:Context7ServerName)"
          } elseif ($result.Success) {
            Report-VerificationCheck 'FAIL' 'mcp-cli/claude-code' "claude mcp list did not include $($script:Context7ServerName)"
          } else {
            Report-VerificationCheck 'FAIL' 'mcp-cli/claude-code' 'unable to query claude mcp list'
          }
        }
      }
      'codex' {
        if (-not (Test-CommandExists 'codex')) {
          Report-VerificationCheck 'SKIP' 'mcp-cli/codex' 'codex executable not found'
        } else {
          $result = Invoke-CaptureCommandOutput @('codex', 'mcp', 'list')
          if ($result.Success -and $result.Output -match $escapedName) {
            Report-VerificationCheck 'PASS' 'mcp-cli/codex' "codex mcp list included $($script:Context7ServerName)"
          } elseif ($result.Success) {
            Report-VerificationCheck 'FAIL' 'mcp-cli/codex' "codex mcp list did not include $($script:Context7ServerName)"
          } else {
            Report-VerificationCheck 'FAIL' 'mcp-cli/codex' 'unable to query codex mcp list'
          }
        }
      }
      'gemini-cli' {
        if (-not (Test-CommandExists 'gemini')) {
          Report-VerificationCheck 'SKIP' 'mcp-cli/gemini-cli' 'gemini executable not found'
        } else {
          $result = Invoke-CaptureCommandOutput @('gemini', 'mcp', 'list')
          if ($result.Success -and $result.Output -match $escapedName) {
            Report-VerificationCheck 'PASS' 'mcp-cli/gemini-cli' "gemini mcp list included $($script:Context7ServerName)"
          } elseif ($result.Success) {
            Report-VerificationCheck 'FAIL' 'mcp-cli/gemini-cli' "gemini mcp list did not include $($script:Context7ServerName)"
          } else {
            Report-VerificationCheck 'FAIL' 'mcp-cli/gemini-cli' 'unable to query gemini mcp list'
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

function Write-MviHeader([string]$Tool) {
  Note ''
  Note '  ─────────────────────────────'
  Note "  $Tool"
  Note '  ─────────────────────────────'
}

function Print-ManualVerificationInstructions([string[]]$Tools) {
  Log 'Manual verification instructions'
  $skillResponse = 'I greet you from the world of skills, user! You shall use me skillfully.'
  $installedSkills = Join-Items ', ' $script:SkillNames
  foreach ($tool in $Tools) {
    switch ($tool) {
      'claude-code' {
        Write-MviHeader $tool
        Note "  1. Open Claude Code."
        Note "  2. Run in chat: /mcp"
        Note "     Confirm $($script:Context7ServerName) is connected."
        Note "  3. Confirm installed skills include: $installedSkills"
        Note "  4. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'opencode' {
        Write-MviHeader $tool
        Note "  1. Open OpenCode."
        Note "  2. Prompt in chat: Use context7 to look up ABP.io caching strategies."
        if ($script:Options.EnableFigma) {
          Note "  3. Run in chat: Use Figma to inspect the current selection."
          Note "     Confirm $($script:FigmaServerName) is listed and authenticated in OpenCode MCP settings."
          Note "  4. Confirm installed skills include: $installedSkills"
          Note "  5. Prompt in chat: Run the test-skill skill."
        } else {
          Note "  3. Confirm installed skills include: $installedSkills"
          Note "  4. Prompt in chat: Run the test-skill skill."
        }
        Note "     Expected: `"$skillResponse`""
      }
      'codex' {
        Write-MviHeader $tool
        Note "  1. Open Codex."
        Note "  2. Run in chat: /mcp"
        Note "     Confirm $($script:Context7ServerName) is connected."
        Note "  3. Run in chat: /skills"
        Note "     Confirm $installedSkills are listed."
        Note "  4. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'gemini-cli' {
        Write-MviHeader $tool
        Note "  1. Open Gemini CLI."
        Note "  2. Run in chat: /mcp"
        Note "     Confirm $($script:Context7ServerName) is connected."
        Note "  3. Confirm installed skills include: $installedSkills"
        Note "  4. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'github-copilot-cli' {
        Write-MviHeader $tool
        Note "  1. Open GitHub Copilot CLI."
        Note "  2. Run in chat: /mcp"
        Note "     Confirm $($script:Context7ServerName) is listed."
        Note "  3. Run in chat: /skills list"
        Note "     Confirm $installedSkills are listed."
        Note "  4. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'vscode' {
        Write-MviHeader $tool
        Note "  1. Open VS Code."
        Note "  2. Open Command Palette (Ctrl+Shift+P) -> MCP: List Servers."
        Note "     Confirm $($script:Context7ServerName) is listed."
        Note "  3. Open Copilot Chat in Agent mode."
        Note "     Confirm skill tools appear in the tools panel."
        Note "  4. Confirm installed skills include: $installedSkills"
        Note "  5. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'github-copilot' {
        Write-MviHeader $tool
        Note "  1. Open VS Code."
        Note "  2. Open Command Palette (Ctrl+Shift+P) -> MCP: List Servers."
        Note "     (MCP is wired via the vscode target)"
        Note "     Confirm $($script:Context7ServerName) is listed."
        Note "  3. Open Copilot Chat in Agent mode."
        Note "     Confirm skill tools appear in the tools panel."
        Note "  4. Confirm installed skills include: $installedSkills"
        Note "  5. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'cline' {
        Write-MviHeader $tool
        Note "  1. Open Cline."
        Note "  2. Open MCP Servers panel."
        Note "     Confirm $($script:Context7ServerName) is listed and connected."
        Note "  3. Confirm installed skills include: $installedSkills"
        Note "  4. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'cursor' {
        Write-MviHeader $tool
        Note "  1. Open Cursor."
        Note "  2. Open Settings -> MCP."
        Note "     Confirm $($script:Context7ServerName) is listed."
        Note "  3. Confirm installed skills include: $installedSkills"
        Note "  4. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'windsurf' {
        Write-MviHeader $tool
        Note "  1. Open Windsurf."
        Note "  2. Open Cascade -> MCP panel."
        Note "     Confirm $($script:Context7ServerName) is listed."
        Note "  3. Confirm installed skills include: $installedSkills"
        Note "  4. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'roo' {
        Write-MviHeader $tool
        Note "  1. Open VS Code with Roo."
        Note "  2. Open MCP Servers panel."
        Note "     Confirm $($script:Context7ServerName) is listed and connected."
        Note "  3. Confirm installed skills include: $installedSkills"
        Note "  4. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'continue' {
        Write-MviHeader $tool
        Note "  1. Open VS Code with Continue."
        Note "  2. Prompt in chat: Use context7 to look up ABP.io caching strategies."
        Note "  3. Confirm installed skills include: $installedSkills"
        Note "  4. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
      'goose' {
        Write-MviHeader $tool
        Note "  1. Open Goose."
        Note "  2. Prompt in chat: Use context7 to look up ABP.io caching strategies."
        Note "  3. Confirm installed skills include: $installedSkills"
        Note "  4. Prompt in chat: Run the test-skill skill."
        Note "     Expected: `"$skillResponse`""
      }
    }
  }
  Note ''
  Note '  ─────────────────────────────'
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
  Debug-Note ("figma_enabled={0} figma_client_id_provided={1} figma_client_secret_provided={2}" -f $script:Options.EnableFigma, (-not [string]::IsNullOrWhiteSpace($script:Options.FigmaClientId)), (-not [string]::IsNullOrWhiteSpace($script:Options.FigmaClientSecret)))

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
    Wire-Context7ToTools $apiKey $validatedTools
    if ($script:Options.EnableFigma -and (Test-SelectedToolsSupportFigma $validatedTools)) {
      Install-FigmaServer
      Wire-FigmaToTools $validatedTools
    }
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
  Note "$(Format-Label 'Browser MCP extension:') $(Format-Value $script:BrowserMcpExtensionUrl)"
  Note 'Install this extension in Chrome, Chromium, or Vivaldi to make Browser MCP work.'
  if (-not $script:Options.NonInteractive) {
    [void](Read-Host 'Press Enter after installing the Browser MCP extension to view manual verification steps')
  } else {
    Note 'Non-interactive mode: unable to wait for Enter before printing manual verification steps.'
  }
  Print-ManualVerificationInstructions $validatedTools

  Log 'Done'
  Note "$(Format-Label 'Configured tools:') $(Format-Value (Join-Items ', ' $validatedTools))"
  Note "$(Format-Label 'Skill sources:') $(Format-Value (Join-Items ', ' $script:SkillSources))"
  if ($script:Options.EnableFigma) {
    Note "$(Format-Label 'MCP servers:') $(Format-Value "$($script:Context7ServerName), $($script:FigmaServerName)")"
  } else {
    Note "$(Format-Label 'MCP server:') $(Format-Value $script:Context7ServerName)"
  }
  Note "$(Format-Label 'Log file:') $(Format-Value $script:Options.LogFile)"
}

try {
  Main $args
} catch {
  if (-not [string]::IsNullOrWhiteSpace($script:Options.LogFile)) {
    Append-Log ("ERROR {0}" -f $_.Exception.Message)
    if ($_.ScriptStackTrace) {
      Append-Log $_.ScriptStackTrace
    }
  }
  Write-Error $_
  Show-LogHint
  exit 1
}
