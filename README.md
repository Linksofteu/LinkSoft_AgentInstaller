# LinkSoft_AgentInstaller

LinkSoft_AgentInstaller is a Bash-based setup utility for installing and wiring LinkSoft-supported agent skills and MCP integrations across multiple AI coding tools from one place.

Today, the script focuses on:

- installing the LinkSoft `test-skill`
- installing/configuring the Context7 MCP server through `mcpm`
- wiring that MCP server into selected tools
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
5. install the `context7` MCP server in `mcpm`
6. wire Context7 into each selected tool using the tool's supported config path or MCPM client integration
7. run verification checks unless skipped
8. print manual follow-up verification steps for the selected tools

## Current defaults

- Skill source: `Linksofteu/LinkSoft_Skills@test-skill`
- Skill name: `test-skill`
- MCP server name: `context7`
- MCP server URL: `https://mcp.context7.com/mcp`

## Prerequisites

Before running the installer, make sure these are available:

- `bash`
- `python3`
- `npx` if you are installing skills
- `npm` if you want the installer to add `openspec` for you when it is missing
- `mcpm` if you are installing or wiring MCP

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

To run the tool directly on Windows without cloning the repository first:

```powershell
irm https://raw.githubusercontent.com/Linksofteu/LinkSoft_AgentInstaller/main/install.ps1 | iex
```

To pass arguments through the PowerShell bootstrapper:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Linksofteu/LinkSoft_AgentInstaller/main/install.ps1))) --dry-run --non-interactive --tools opencode,vscode
```

The Windows bootstrap downloads the repository zip to a temporary directory, expands it, and runs `./setup-agentic-tools.ps1` from there.

### Interactive mode

```bash
./setup-agentic-tools.sh
```

This mode:

- detects installed tools
- prompts for additional tool ids
- lets you confirm the final tool selection
- offers to install `openspec` globally via `npm` when it is missing
- optionally prompts for a Context7 API key

### Non-interactive mode

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

Support level varies by tool. Some have direct config-file handling in this repository, while others are wired through `mcpm client edit`.

## Tool-specific notes

### Skills installation

Skills are installed through:

```bash
npx -y skills add Linksofteu/LinkSoft_Skills@test-skill -g -y
```

The script maps selected tool ids to the correct skills agent target where possible.

### Context7 MCP wiring

Context7 is installed into MCPM first, then connected to selected tools.

Special handling exists for:

- **OpenCode**: updates `~/.config/opencode/opencode.json`
- **VS Code**: updates `~/.config/Code/User/mcp.json`
- **GitHub Copilot CLI**: updates `~/.copilot/mcp-config.json`

Other supported tools are wired through `mcpm client edit` when a matching MCPM client name is defined.

For `github-copilot`, MCP wiring is not done directly by this script; use the `vscode` target when configuring Copilot inside VS Code.

## Verification

Unless `--skip-verify` is used, the script runs:

- static skill checks
- static MCP checks
- smoke checks against `skills.sh`
- smoke checks against MCP CLIs where supported

After that, it also prints manual verification instructions for each selected tool.

## Logging

By default, the script writes a log file to:

```text
./setup-agentic-tools.log
```

You can override it with:

```bash
./setup-agentic-tools.sh --log-file /path/to/custom.log
```

## Repository layout

```text
.
├── README.md
├── setup-agentic-tools.sh
└── setup-agentic-tools/
    └── lib/
        ├── common.sh
        ├── install.sh
        ├── tooling.sh
        └── verify.sh
```

## Notes and limitations

- The current script is centered on installing the LinkSoft `test-skill`, not an arbitrary skill catalog.
- Detection is based on known config directories and/or executables for supported tools.
- Verification coverage differs by tool because not every tool exposes the same CLI or config surface.
- Some configuration files are backed up before being rewritten.

## License

This project is licensed under the MIT License. See [LICENSE](./LICENSE).
