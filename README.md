# LinkSoft_AgentInstaller

LinkSoft_AgentInstaller is a cross-platform setup utility for installing and wiring LinkSoft-supported agent skills and MCP integrations across multiple AI coding tools from one place. It ships a Bash implementation for Linux and macOS and a self-contained PowerShell port for Windows.

Today, the script focuses on:

- installing the LinkSoft `test-skill`
- wiring the Context7 MCP server directly into supported tools
- running static and smoke verification checks where supported

## Why this exists

Different agent tools store skills and MCP settings in different locations and use different configuration formats. This repository provides a single entry point so you do not have to manually repeat those steps for every tool.

## What the script does

The main entrypoint is:

```bash
./setup-agentic-tools.sh
```

When run, it will:

1. detect supported tools already present on the machine
2. let you add or choose the tools you want to configure
3. install the LinkSoft test skill via `npx skills`
4. check whether `openspec` is installed and, if missing, offer to install it globally via `npm`
5. prepare a direct remote MCP configuration for `context7`
6. write Context7 into each supported tool's config file or settings path
7. run verification checks unless skipped
8. print manual follow-up verification steps for the selected tools

## Current defaults

- Skill source: `Linksofteu/LinkSoft_Skills@test-skill`
- Skill name: `test-skill`
- MCP server name: `context7`
- MCP server URL: `https://mcp.context7.com/mcp`

## Prerequisites

### Linux / macOS

Before running the installer, make sure these are available:

- `bash`
- `python3`
- `npx` if you are installing skills
- `npm` if you want the installer to add `openspec` for you when it is missing

### Windows

Before running the PowerShell installer, make sure these are available:

- **PowerShell 5.1 or later** — ships with Windows 10/11; PowerShell 7+ also works
- `npx` (via Node.js) if you are installing skills
- `npm` if you want the installer to add `openspec` for you when it is missing

**Execution policy**: The bootstrap one-liner pipes a remote script into `iex`, so no special execution policy is required for that approach. If you download and run `setup-agentic-tools.ps1` directly, PowerShell's default policy may block it. Allow the script to run with:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
```

The script will fail early if a required dependency is missing for the steps you did not skip.

## Usage

### One-line run

If you want to run the tool directly on a user machine without cloning the repository first:

```bash
curl -fsSL https://raw.githubusercontent.com/Linksofteu/LinkSoft_AgentInstaller/main/install.sh | bash
```

The bootstrap script downloads the repository tarball to a temporary directory, unpacks it, and runs `./setup-agentic-tools.sh` from there.

To pass arguments through the one-liner, use `bash -s --`:

```bash
curl -fsSL https://raw.githubusercontent.com/Linksofteu/LinkSoft_AgentInstaller/main/install.sh | bash -s -- --non-interactive --tools opencode,codex
```

### Windows PowerShell

#### One-line run

To run the tool directly on Windows without cloning the repository first:

```powershell
irm https://raw.githubusercontent.com/Linksofteu/LinkSoft_AgentInstaller/main/install.ps1 | iex
```

The bootstrap downloads the repository zip to a temporary directory, expands it, and runs `setup-agentic-tools.ps1` from there. It cleans up the temp directory on exit.

To pass arguments through the bootstrapper:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Linksofteu/LinkSoft_AgentInstaller/main/install.ps1))) --dry-run --non-interactive --tools opencode,vscode
```

#### Direct run (after cloning)

```powershell
.\setup-agentic-tools.ps1
```

Or with arguments:

```powershell
.\setup-agentic-tools.ps1 --non-interactive --tools opencode,cursor,codex
```

#### Windows PowerShell examples

The PowerShell script accepts the same flags as the Bash version:

```powershell
# Configure detected tools interactively
.\setup-agentic-tools.ps1

# Configure a fixed set of tools
.\setup-agentic-tools.ps1 --non-interactive --tools opencode,cursor,codex

# Add extra tools on top of detected tools
.\setup-agentic-tools.ps1 --extra-tools vscode,github-copilot-cli

# Preview actions without making changes
.\setup-agentic-tools.ps1 --dry-run --tools opencode,codex

# Provide a Context7 API key
.\setup-agentic-tools.ps1 --tools opencode --context7-api-key YOUR_KEY

# Only install skills
.\setup-agentic-tools.ps1 --skip-mcp --tools opencode,codex

# Only wire MCP and skip skill installation
.\setup-agentic-tools.ps1 --skip-skills --tools vscode,cursor

# Write the log to a custom path
.\setup-agentic-tools.ps1 --log-file C:\Temp\installer.log --tools opencode
```

### Interactive mode (Linux / macOS)

```bash
./setup-agentic-tools.sh
```

This mode:

- detects installed tools
- prompts for additional tool ids
- lets you confirm the final tool selection
- offers to install `openspec` globally via `npm` when it is missing
- optionally prompts for a Context7 API key

### Non-interactive mode (Linux / macOS)

```bash
./setup-agentic-tools.sh --non-interactive --tools opencode,codex,vscode
```

Useful for scripting or repeatable local setup.

## Command-line options

```text
--tools CSV              Final tool ids to configure
--extra-tools CSV        Additional tool ids to merge with detected tools
--context7-api-key KEY   Optional Context7 API key
--log-file PATH          Log file path
--copy-skills            Use copied skill files instead of symlinks
--skip-skills            Skip skill installation
--skip-mcp               Skip MCP installation and wiring
--skip-verify            Skip post-install verification
--non-interactive        Disable prompts
--dry-run                Print actions without executing them
-v, --verbose            Enable detailed command logging
-h, --help               Show help
```

## Examples

### Configure detected tools interactively

```bash
./setup-agentic-tools.sh
```

### Configure a fixed set of tools

```bash
./setup-agentic-tools.sh --non-interactive --tools opencode,cursor,codex
```

### Add extra tools on top of detected tools

```bash
./setup-agentic-tools.sh --extra-tools vscode,github-copilot-cli
```

### Provide a Context7 API key

```bash
./setup-agentic-tools.sh --tools opencode --context7-api-key YOUR_KEY
```

### Preview actions without making changes

```bash
./setup-agentic-tools.sh --dry-run --tools opencode,codex
```

`--dry-run` prints the planned actions without executing them and now behaves as a non-interactive preview.

### Only install skills

```bash
./setup-agentic-tools.sh --skip-mcp --tools opencode,codex
```

### Only wire MCP and skip skill installation

```bash
./setup-agentic-tools.sh --skip-skills --tools vscode,cursor
```

## Supported tool ids

The repository currently knows about these tool ids:

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

Support level varies by tool. Some tools are configured directly by this repository today, while others still require manual MCP setup after the installer finishes.

## Tool-specific notes

### Skills installation

Skills are installed through:

```bash
npx -y skills add Linksofteu/LinkSoft_Skills@test-skill -g -y
```

The script maps selected tool ids to the correct skills agent target where possible.

### Skill file locations

The table below lists where the installed skill file lands after `npx skills` runs. `~` expands to `$HOME` on Linux/macOS and `%USERPROFILE%` on Windows.

| Tool id | Skill file path |
|---------|-----------------|
| `opencode` | `~/.agents/skills/test-skill/SKILL.md` |
| `codex` | `~/.agents/skills/test-skill/SKILL.md` |
| `github-copilot-cli` | `~/.agents/skills/test-skill/SKILL.md` |
| `github-copilot` | `~/.agents/skills/test-skill/SKILL.md` |
| `cline` | `~/.agents/skills/test-skill/SKILL.md` |
| `cursor` | `~/.agents/skills/test-skill/SKILL.md` |
| `gemini-cli` | `~/.agents/skills/test-skill/SKILL.md` |
| `vscode` | `~/.agents/skills/test-skill/SKILL.md` |
| `claude-code` | `~/.claude/skills/test-skill/SKILL.md` |
| `windsurf` | `~/.codeium/windsurf/skills/test-skill/SKILL.md` |
| `continue` | `~/.continue/skills/test-skill/SKILL.md` |
| `goose` | `~/.config/goose/skills/test-skill/SKILL.md` |
| `roo` | `~/.roo/skills/test-skill/SKILL.md` |

### Context7 MCP wiring

Context7 is configured as a direct remote MCP server. No external MCP manager is required.

The installer currently writes direct MCP configuration for these tools:

- `opencode`
- `claude-code`
- `codex`
- `github-copilot-cli`
- `cline`
- `continue`
- `vscode`
- `gemini-cli`

For `github-copilot`, MCP wiring is not done directly by this script; use the `vscode` target when configuring Copilot inside VS Code.

#### MCP config file locations

| Tool id | Linux / macOS path | Windows path |
|---------|-------------------|--------------|
| `opencode` | `~/.config/opencode/opencode.json` | `%APPDATA%\opencode\opencode.json` |
| `claude-code` | `~/.claude.json` | `%USERPROFILE%\.claude.json` |
| `codex` | `~/.codex/config.toml` | `%USERPROFILE%\.codex\config.toml` |
| `cline` | `~/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json` | `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev\settings\cline_mcp_settings.json` |
| `continue` | `~/.continue/mcpServers/context7.json` | `%USERPROFILE%\.continue\mcpServers\context7.json` |
| `vscode` | `~/.config/Code/User/mcp.json` | `%APPDATA%\Code\User\mcp.json` |
| `github-copilot-cli` | `~/.copilot/mcp-config.json` | `%USERPROFILE%\.copilot\mcp-config.json` |
| `gemini-cli` | `~/.gemini/settings.json` | `%USERPROFILE%\.gemini\settings.json` |

The tools below are detected and can still receive skills, but MCP configuration is not currently written automatically by this repository:

- `cursor`
- `windsurf`
- `goose`
- `roo`

For those tools, the installer prints manual follow-up steps instead of writing a tool-specific MCP config.

### Windows tool detection

On Windows the script checks `%APPDATA%` and `%USERPROFILE%` paths rather than `~/.config` equivalents. The table below shows what each tool id looks for.

| Tool id | Detected when any of these exist |
|---------|----------------------------------|
| `opencode` | `%APPDATA%\opencode` directory or `opencode` executable |
| `claude-code` | `%USERPROFILE%\.claude` directory or `claude` executable |
| `cursor` | `%USERPROFILE%\.cursor`, `%APPDATA%\Cursor`, or `cursor` executable |
| `windsurf` | `%USERPROFILE%\.codeium\windsurf`, `%APPDATA%\Codeium\Windsurf`, or `windsurf` executable |
| `codex` | `%USERPROFILE%\.codex` directory or `codex` executable |
| `github-copilot-cli` | `copilot` executable or `%USERPROFILE%\.copilot` directory |
| `github-copilot` | `%APPDATA%\Code\User` directory or `code` executable |
| `cline` | `%USERPROFILE%\.cline` or `%APPDATA%\Code\User\globalStorage\saoudrizwan.claude-dev` |
| `continue` | `%USERPROFILE%\.continue` directory |
| `goose` | `%APPDATA%\goose` directory or `goose` executable |
| `roo` | `%USERPROFILE%\.roo` directory |
| `vscode` | `code` executable or `%APPDATA%\Code\User` directory |
| `gemini-cli` | `%USERPROFILE%\.gemini` directory or `gemini` executable |

## Verification

Unless `--skip-verify` is used, the script runs:

- static skill checks
- static MCP checks
- smoke checks against `skills.sh`
- smoke checks against MCP CLIs where supported

After that, it also prints manual verification instructions for each selected tool.

## Logging

By default, the script writes a log file next to the script itself:

```text
./setup-agentic-tools.log
```

You can override it:

```bash
# Linux / macOS
./setup-agentic-tools.sh --log-file /path/to/custom.log

# Windows
.\setup-agentic-tools.ps1 --log-file C:\Temp\installer.log
```

## Repository layout

```text
.
├── README.md
├── install.sh                          # Linux/macOS bootstrap (curl | bash)
├── install.ps1                         # Windows bootstrap (irm | iex)
├── setup-agentic-tools.sh              # Linux/macOS entrypoint
├── setup-agentic-tools.ps1             # Windows entrypoint (self-contained PS port)
└── setup-agentic-tools/
    └── lib/
        ├── common.sh
        ├── install.sh
        ├── tooling.sh
        └── verify.sh
```

`setup-agentic-tools.ps1` is a self-contained PowerShell port of the entire Bash implementation. It does not depend on WSL, Cygwin, or any Unix utilities. Both scripts must be kept in sync manually when new features are added.

## Notes and limitations

- The current script is centered on installing the LinkSoft `test-skill`, not an arbitrary skill catalog.
- Detection is based on known config directories and/or executables for supported tools.
- Verification coverage differs by tool because not every tool exposes the same CLI or config surface.
- Some configuration files are backed up before being rewritten.

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).
