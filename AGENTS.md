# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository does

LinkSoft_AgentInstaller is a cross-platform installer that wires the LinkSoft `test-skill` and the Context7 MCP server into multiple AI coding tools from a single entry point. It handles the fact that each tool stores skills and MCP config in different locations and formats.

## Running the installer

```bash
# Interactive (detects installed tools, prompts for the rest)
./setup-agentic-tools.sh

# Non-interactive with explicit tool list
./setup-agentic-tools.sh --non-interactive --tools opencode,codex,vscode

# Preview without making changes
./setup-agentic-tools.sh --dry-run --tools opencode,codex

# Skip individual phases
./setup-agentic-tools.sh --skip-mcp --tools opencode,codex   # skills only
./setup-agentic-tools.sh --skip-skills --tools vscode,cursor  # MCP only

# Windows equivalent
./setup-agentic-tools.ps1 --non-interactive --tools opencode,vscode
```

There is no build step, no test suite, and no linting configuration in the repository. Manual validation is done via `--dry-run` and the post-install verification phase built into the script itself.

## Architecture

The Bash implementation is split into a thin entrypoint and four sourced libraries:

| File | Responsibility |
|------|---------------|
| `setup-agentic-tools.sh` | Globals, argument parsing, `main()` orchestration |
| `setup-agentic-tools/lib/common.sh` | Logging helpers (`log`, `warn`, `die`, `note`), spinner, `run_cmd` / `capture_cmd` wrappers, CSV/array utilities |
| `setup-agentic-tools/lib/tooling.sh` | Tool detection, `KNOWN_TOOLS` list, skill path mappings, and documented MCP config paths |
| `setup-agentic-tools/lib/install.sh` | Skill installation via `npx skills`, direct Context7 config generation, and per-tool MCP wiring for the tools that have known config formats |
| `setup-agentic-tools/lib/verify.sh` | Static and smoke verification checks, summary counters |

`setup-agentic-tools.ps1` is a self-contained PowerShell port of the entire Bash implementation with the same options, phases, and logic. It must be kept in sync manually with the Bash version.

`install.sh` / `install.ps1` are thin bootstrap scripts that download the repository archive and exec into `setup-agentic-tools.sh` / `setup-agentic-tools.ps1`. They are not sourced by the main scripts.

## Key design patterns

**`run_cmd` vs `capture_cmd`**: `run_cmd` runs a command with a spinner and streams output on failure; `capture_cmd` runs silently and returns output as a string. Both respect `DRY_RUN` and `VERBOSE` flags.

**Per-tool dispatch**: Tools with known config formats are wired directly by the installer. Bash uses embedded Python for JSON/TOML rewrites where convenient, and PowerShell uses native JSON helpers plus small text transforms for TOML.

**Config file backup**: Before rewriting any JSON config, a timestamped `.bak.<epoch>` copy is created alongside the original.

**Tool detection**: Each tool is detected by checking for a known config directory and/or executable. Detection is used to build the default tool list; users can override with `--tools` or extend with `--extra-tools`.

**`vscode` vs `github-copilot`**: `vscode` is the MCP wiring target (writes `~/.config/Code/User/mcp.json`); `github-copilot` is treated as skills-only and maps to the `github-copilot` agent name. Using both together covers the full Copilot-in-VS-Code setup.

## Adding a new tool

1. Add the tool id to `KNOWN_TOOLS` in `tooling.sh` and `$script:KnownTools` in `setup-agentic-tools.ps1`.
2. Add detection logic in `detect_tool()` / `Detect-Tool`.
3. Map the skills agent name in `skills_agent_name()` / `Get-SkillAgentForTool`.
4. Add the skill static path in `tool_skill_static_paths()` / `Get-ToolSkillStaticPaths`.
5. Add a direct `configure_<tool>()` function (or equivalent PowerShell function) for the tool's MCP config format and path.
6. Add manual verification instructions to `print_manual_verification_instructions()` / `Print-ManualVerificationInstructions`.
7. Add static MCP verification logic to `verify_mcp_static()` / `Verify-McpStatic` if applicable.
