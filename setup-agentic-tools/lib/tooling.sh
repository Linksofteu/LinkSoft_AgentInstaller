#!/usr/bin/env bash

KNOWN_TOOLS=(
  "opencode"
  "claude-code"
  "cursor"
  "windsurf"
  "codex"
  "github-copilot-cli"
  "github-copilot"
  "cline"
  "continue"
  "goose"
  "roo"
  "vscode"
  "gemini-cli"
)

is_known_tool() {
  local tool="$1"
  contains "$tool" "${KNOWN_TOOLS[@]}"
}

detect_tool() {
  local tool="$1"
  case "$tool" in
    opencode) [[ -d "$HOME/.config/opencode" ]] || has_cmd opencode ;;
    claude-code) [[ -d "$HOME/.claude" ]] || has_cmd claude ;;
    cursor) [[ -d "$HOME/.cursor" ]] || has_cmd cursor ;;
    windsurf) [[ -d "$HOME/.codeium/windsurf" ]] || has_cmd windsurf ;;
    codex) [[ -d "$HOME/.codex" ]] || has_cmd codex ;;
    github-copilot-cli) has_cmd copilot || [[ -d "$HOME/.copilot" ]] ;;
    github-copilot) [[ -d "$HOME/.config/Code/User" ]] || has_cmd code ;;
    cline) [[ -d "$HOME/.cline" || -d "$HOME/.config/Code/User/globalStorage/saoudrizwan.claude-dev" ]] ;;
    continue) [[ -d "$HOME/.continue" ]] ;;
    goose) [[ -d "$HOME/.config/goose" ]] || has_cmd goose ;;
    roo) [[ -d "$HOME/.roo" ]] ;;
    vscode) has_cmd code || [[ -d "$HOME/.config/Code/User" ]] ;;
    gemini-cli) [[ -d "$HOME/.gemini" ]] || has_cmd gemini ;;
    *) return 1 ;;
  esac
}

detect_installed_tools() {
  local -n out_ref=$1
  out_ref=()
  local tool
  for tool in "${KNOWN_TOOLS[@]}"; do
    if detect_tool "$tool"; then
      out_ref+=("$tool")
    fi
  done
}

merge_known_tools() {
  local -n target_ref=$1
  shift
  local tool
  for tool in "$@"; do
    if is_known_tool "$tool"; then
      append_unique "$tool" target_ref
    elif [[ -n "$tool" ]]; then
      warn "Ignoring unknown tool id: $tool"
    fi
  done
}

validate_known_tools() {
  local -n out_ref=$1
  shift
  out_ref=()
  local tool
  for tool in "$@"; do
    if is_known_tool "$tool"; then
      append_unique "$tool" out_ref
    else
      warn "Ignoring unknown tool id: $tool"
    fi
  done
}

skills_agent_name() {
  local tool="$1"
  case "$tool" in
    opencode) printf 'opencode' ;;
    claude-code) printf 'claude-code' ;;
    cursor) printf 'cursor' ;;
    windsurf) printf 'windsurf' ;;
    codex) printf 'codex' ;;
    github-copilot-cli) printf 'github-copilot' ;;
    github-copilot) printf 'github-copilot' ;;
    cline) printf 'cline' ;;
    continue) printf 'continue' ;;
    goose) printf 'goose' ;;
    roo) printf 'roo' ;;
    gemini-cli) printf 'gemini-cli' ;;
    *) return 1 ;;
  esac
}

skill_agent_for_tool() {
  local tool="$1"
  if [[ "$tool" == "vscode" ]]; then
    printf 'github-copilot'
    return 0
  fi
  skills_agent_name "$tool"
}

collect_skill_agents() {
  local -n out_ref=$1
  shift
  out_ref=()
  local tool agent
  for tool in "$@"; do
    if [[ "$tool" == "vscode" ]]; then
      debug "'vscode' is treated as an IDE/MCP target; using 'github-copilot' as the skills target"
    fi
    if agent="$(skill_agent_for_tool "$tool" 2>/dev/null)"; then
      append_unique "$agent" out_ref
    fi
  done
}

skill_global_dir_for_agent() {
  local agent="$1"
  case "$agent" in
    opencode) printf '%s/.config/opencode/skills' "$HOME" ;;
    claude-code) printf '%s/.claude/skills' "$HOME" ;;
    cursor) printf '%s/.cursor/skills' "$HOME" ;;
    windsurf) printf '%s/.codeium/windsurf/skills' "$HOME" ;;
    codex) printf '%s/.codex/skills' "$HOME" ;;
    github-copilot) printf '%s/.copilot/skills' "$HOME" ;;
    cline) printf '%s/.agents/skills' "$HOME" ;;
    continue) printf '%s/.continue/skills' "$HOME" ;;
    goose) printf '%s/.config/goose/skills' "$HOME" ;;
    roo) printf '%s/.roo/skills' "$HOME" ;;
    gemini-cli) printf '%s/.gemini/skills' "$HOME" ;;
    *) return 1 ;;
  esac
}

tool_supports_agents_skill_dir() {
  local tool="$1"
  case "$tool" in
    opencode|codex|github-copilot|cline|cursor|gemini-cli) return 0 ;;
    *) return 1 ;;
  esac
}

tool_skill_static_paths() {
  local tool="$1"
  case "$tool" in
    opencode|codex|github-copilot-cli|github-copilot|cline|cursor|gemini-cli)
      printf '%s/.agents/skills/%s/SKILL.md\n' "$HOME" "$SKILL_NAME"
      ;;
    claude-code)
      printf '%s/.claude/skills/%s/SKILL.md\n' "$HOME" "$SKILL_NAME"
      ;;
    windsurf)
      printf '%s/.codeium/windsurf/skills/%s/SKILL.md\n' "$HOME" "$SKILL_NAME"
      ;;
    continue)
      printf '%s/.continue/skills/%s/SKILL.md\n' "$HOME" "$SKILL_NAME"
      ;;
    goose)
      printf '%s/.config/goose/skills/%s/SKILL.md\n' "$HOME" "$SKILL_NAME"
      ;;
    roo)
      printf '%s/.roo/skills/%s/SKILL.md\n' "$HOME" "$SKILL_NAME"
      ;;
    vscode)
      printf '%s/.agents/skills/%s/SKILL.md\n' "$HOME" "$SKILL_NAME"
      ;;
    *)
      return 1
      ;;
  esac
}

mcpm_client_name() {
  local tool="$1"
  case "$tool" in
    claude-code) printf 'claude-code' ;;
    cursor) printf 'cursor' ;;
    windsurf) printf 'windsurf' ;;
    codex) printf 'codex-cli' ;;
    cline) printf 'cline' ;;
    continue) printf 'continue' ;;
    goose) printf 'goose-cli' ;;
    roo) printf 'roo-code' ;;
    gemini-cli) printf 'gemini-cli' ;;
    *) return 1 ;;
  esac
}

tool_has_mcp_cli_check() {
  local tool="$1"
  case "$tool" in
    opencode|claude-code) return 0 ;;
    *) return 1 ;;
  esac
}

tool_has_native_skills_shell_check() {
  local tool="$1"
  case "$tool" in
    *) return 1 ;;
  esac
}

tool_native_skills_check_hint() {
  local tool="$1"
  case "$tool" in
      github-copilot-cli|github-copilot|vscode)
        printf '/skills in Copilot Chat or /skills list in Copilot CLI'
        ;;
    codex)
      printf '/skills in Codex CLI/TUI'
      ;;
    claude-code)
      printf 'direct /skill-name invocation or asking "What skills are available?" in Claude Code'
      ;;
    opencode)
      printf 'the native skill tool / available_skills in OpenCode sessions'
      ;;
    *)
      return 1
      ;;
  esac
}

print_manual_verification_instructions() {
  log "Manual verification instructions"
  local tool
  for tool in "$@"; do
    case "$tool" in
      github-copilot-cli)
        note "$(cat <<'EOF'
- github-copilot-cli:
  1. Start Copilot CLI by running: copilot
  2. Run: /skills list
  3. Run: /mcp and confirm context7 is configured.
  4. Invoke /test-skill or ask Copilot to use context7 in a prompt.
EOF
)"
        ;;
      vscode)
        note "$(cat <<'EOF'
- vscode:
  1. Open VS Code in the target workspace.
  2. Open Command Palette (Ctrl+Shift+P) and run: MCP: List Servers.
  3. Open Copilot Chat in Agent mode and inspect the tools list.
  4. If context7 is present but unavailable, open ~/.config/Code/User/mcp.json and verify the command path.
EOF
)"
        ;;
      github-copilot)
        note "$(cat <<'EOF'
- github-copilot:
  1. Verify the skill exists in ~/.agents/skills, ~/.claude/skills, or ~/.copilot/skills.
  2. In Copilot CLI, run: /skills list
  3. In VS Code Agent mode, type /skills and confirm the skill appears.
  4. For MCP in VS Code, also select the 'vscode' target and run MCP: List Servers.
EOF
)"
        ;;
      cline)
        note "$(cat <<'EOF'
- cline:
  1. Verify the skill exists in ~/.agents/skills/test-skill/SKILL.md.
  2. Inspect ~/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json.
  3. Open Cline and run a prompt that explicitly says to use context7.
  4. Run another prompt that explicitly invokes or depends on the installed skill.
EOF
)"
        ;;
      claude-code)
        note "$(cat <<'EOF'
- claude-code:
  1. Run: claude mcp list
  2. Inside Claude Code, run: /mcp
  3. Invoke /test-skill or ask: What skills are available?
EOF
)"
        ;;
      opencode)
        note "$(cat <<'EOF'
- opencode:
  1. Run: opencode mcp list
  2. Optionally run: opencode mcp debug context7
  3. Open an OpenCode session and inspect the available skills / invoke the installed skill in a task.
EOF
)"
        ;;
      codex)
        note "$(cat <<'EOF'
- codex:
  1. Open Codex CLI or TUI.
  2. Run /mcp in the TUI, or inspect ~/.codex/config.toml for the configured server.
  3. Run /skills and confirm the skill is listed.
  4. Invoke the skill explicitly with the Codex skill picker or prompt.
EOF
)"
        ;;
      cursor|windsurf|continue|goose|roo|gemini-cli)
        note "$(cat <<EOF
- $tool:
  1. Inspect the tool's MCP/skills settings UI or config file.
  2. Confirm the test skill folder and Context7 server entry are present.
  3. Run one prompt that explicitly asks the tool to use context7 and another that invokes the installed skill.
EOF
)"
        ;;
    esac
  done
}
