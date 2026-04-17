# LinkSoft_AgentInstaller

Install LinkSoft skills and supported MCPs across AI coding tools from one command.

## Install now

### Linux / macOS

```bash
curl -fsSL https://raw.githubusercontent.com/Linksofteu/LinkSoft_AgentInstaller/main/install.sh | bash
```

### Windows PowerShell

```powershell
irm https://raw.githubusercontent.com/Linksofteu/LinkSoft_AgentInstaller/main/install.ps1 | iex
```

## What you get

- default LinkSoft skills installed
- all supported MCPs installed by default
- one installer for multiple tools
- built-in verification
- config backups before changes

## Default installs

### Skills

- `test-skill`
- `ddd-application-slice`
- `creating-linksoft-skills`

### MCPs

- `context7`
- `figma` where native CLI OAuth is supported

## Current important notes

- Figma MCP is currently automated for **OpenCode**
- Browser MCP requires the browser extension install shown by the installer at the end
- no Figma workaround auth is used for tools that do not support native CLI/browser auth
- by default, installer logs are written to `~/.local/state/linksoft-agent-installer/logs/` on Linux/macOS

## Example

```bash
curl -fsSL https://raw.githubusercontent.com/Linksofteu/LinkSoft_AgentInstaller/main/install.sh | bash -s -- --non-interactive --tools opencode,vscode
```

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Linksofteu/LinkSoft_AgentInstaller/main/install.ps1))) --non-interactive --tools opencode,vscode
```

## Supported tools

- `opencode`
- `claude-code`
- `cursor`
- `windsurf`
- `codex`
- `github-copilot-cli`
- `github-copilot`
- `cline`
- `continue`
- `goose`
- `roo`
- `vscode`
- `gemini-cli`

## Common options

```text
--tools CSV
--extra-tools CSV
--context7-api-key KEY
--figma
--figma-client-id ID
--figma-client-secret SECRET
--skip-skills
--skip-mcp
--skip-verify
--non-interactive
--dry-run
```

## Requirements

### Linux / macOS

- `bash`
- `python3`
- `npx`

### Windows

- PowerShell 5.1+
- `npx`

If PowerShell blocks direct script execution, use:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

If npm global package installation fails with a permissions error, configure a user-owned npm global directory and retry:

```bash
mkdir -p "$HOME/.npm-global"
npm config set prefix "$HOME/.npm-global"
export PATH="$HOME/.npm-global/bin:$PATH"
```

Then add the `export PATH=...` line to your shell profile and restart your shell.

## Local run

```bash
./setup-agentic-tools.sh
```

```powershell
.\setup-agentic-tools.ps1
```
