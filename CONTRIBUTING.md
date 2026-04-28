<!-- omit in toc -->
# Contribution Guide

LinkSoft_AgentInstaller is a cross-platform installer that wires LinkSoft skills and supported MCP servers into multiple AI coding tools from one entry point.

This repository is licensed under MIT.

<!-- omit in toc -->
## Table of Contents

- [I Have a Question](#i-have-a-question)
- [Contributing Changes](#contributing-changes)
  - [Before You Start](#before-you-start)
  - [Repository Structure](#repository-structure)
  - [Contribution Expectations](#contribution-expectations)
  - [Validation Before PR](#validation-before-pr)
- [Bug Reports and Enhancements](#bug-reports-and-enhancements)
  - [Submitting a Bug Report](#submitting-a-bug-report)
  - [Suggesting Enhancements](#suggesting-enhancements)
- [Code of Conduct](#code-of-conduct)
- [Attribution](#attribution)

## I Have a Question

Before opening a question, please check:

- Existing repository issues
- `README.md`
- `AGENTS.md` / `CLAUDE.md` for repository-specific implementation notes

If your question is still unanswered, open an issue and include:

- What you are trying to do
- What you expected to happen
- What happened instead
- Relevant environment details such as OS, shell, tool being configured, and Node/npm/npx versions

## Contributing Changes

<!-- omit in toc -->
### Before You Start

Please open an issue first for major changes, including:

- Support for a new tool
- Changes to installer behavior or defaults
- New MCP wiring behavior
- Significant restructuring of script organization

For small fixes such as typos, documentation improvements, or narrow bug fixes, you may open a PR directly.

<!-- omit in toc -->
### Repository Structure

Core Bash implementation:

- `setup-agentic-tools.sh` - entrypoint, argument parsing, orchestration
- `setup-agentic-tools/lib/common.sh` - logging, wrappers, helpers
- `setup-agentic-tools/lib/tooling.sh` - tool definitions, detection, mappings
- `setup-agentic-tools/lib/install.sh` - skill and MCP installation logic
- `setup-agentic-tools/lib/verify.sh` - static and smoke verification

PowerShell implementation:

- `setup-agentic-tools.ps1` - self-contained PowerShell port of the Bash implementation

Bootstrap scripts:

- `install.sh`
- `install.ps1`

Important repository rule:

- The PowerShell script must stay functionally aligned with the Bash implementation when behavior changes apply to both platforms.

When adding a new supported tool, update the relevant detection, mapping, install, verification, and documentation locations described in `AGENTS.md`.

<!-- omit in toc -->
### Contribution Expectations

A good contribution should:

- Keep behavior clear and predictable for both interactive and non-interactive modes
- Preserve backup behavior before config file edits
- Respect dry-run behavior
- Avoid introducing hidden prerequisites
- Update documentation when user-visible behavior changes
- Keep Bash and PowerShell behavior in sync where applicable

Please also ensure:

- No secrets, tokens, or local machine paths are committed unless they are clearly intended examples
- New examples use supported tools and current option names
- Error messages and logs remain actionable for end users

<!-- omit in toc -->
### Validation Before PR

This repository does not use a formal build, lint, or test suite. Please validate changes manually before opening a PR.

Recommended validation:

- Use `--dry-run` to confirm the expected flow without modifying user config
- Run the changed installer path locally when safe to do so
- Review generated config changes carefully
- Confirm post-install verification output still makes sense

Examples:

```bash
./setup-agentic-tools.sh --dry-run --tools opencode,codex
./setup-agentic-tools.sh --non-interactive --tools opencode,vscode
```

```powershell
.\setup-agentic-tools.ps1 --dry-run --tools opencode,codex
.\setup-agentic-tools.ps1 --non-interactive --tools opencode,vscode
```

If your change affects a specific tool, please validate at least one realistic path for that tool.

For new tool support, verify all of the following where applicable:

- Detection works
- Skills are installed to the correct location
- MCP config is written in the correct format and path
- Static verification recognizes the tool correctly
- Manual verification instructions are updated

## Bug Reports and Enhancements

### Submitting a Bug Report

Open an issue with:

- Clear title
- Reproduction steps
- Expected vs actual behavior
- Affected script or tool
- Relevant logs or config snippets if available

Helpful environment details include:

- OS/platform
- Shell or PowerShell version
- Node/npm/npx versions
- Which target tools were selected
- Whether `--dry-run`, `--skip-skills`, or `--skip-mcp` was used

### Suggesting Enhancements

Open an issue with:

- The problem you are solving
- Proposed behavior
- Which tool(s) the change affects
- Any config path or format constraints you already know about

For new tool support, include the expected skill location, MCP config location, and any known authentication limitations if possible.

## Code of Conduct

This project and everyone participating in it is governed by the
[LinkSoft Code of Conduct](https://github.com/Linksofteu/.github/blob/main/CODE_OF_CONDUCT.md).

Please report unacceptable behavior to <opensource@linksoft.cz>.

## Attribution

This guide was adapted from the LinkSoft_Skills contribution guide and tailored for the installer repository.
