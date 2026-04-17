#!/usr/bin/env bash
# Expects caller to enable strict mode (set -euo pipefail).

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

tool_skill_static_paths() {
  local tool="$1"
  local skill_name
  case "$tool" in
    opencode|codex|github-copilot-cli|github-copilot|cline|cursor|gemini-cli)
      for skill_name in "${SKILL_NAMES[@]}"; do
        printf '%s/.agents/skills/%s/SKILL.md\n' "$HOME" "$skill_name"
      done
      ;;
    claude-code)
      for skill_name in "${SKILL_NAMES[@]}"; do
        printf '%s/.claude/skills/%s/SKILL.md\n' "$HOME" "$skill_name"
      done
      ;;
    windsurf)
      for skill_name in "${SKILL_NAMES[@]}"; do
        printf '%s/.codeium/windsurf/skills/%s/SKILL.md\n' "$HOME" "$skill_name"
      done
      ;;
    continue)
      for skill_name in "${SKILL_NAMES[@]}"; do
        printf '%s/.continue/skills/%s/SKILL.md\n' "$HOME" "$skill_name"
      done
      ;;
    goose)
      for skill_name in "${SKILL_NAMES[@]}"; do
        printf '%s/.config/goose/skills/%s/SKILL.md\n' "$HOME" "$skill_name"
      done
      ;;
    roo)
      for skill_name in "${SKILL_NAMES[@]}"; do
        printf '%s/.roo/skills/%s/SKILL.md\n' "$HOME" "$skill_name"
      done
      ;;
    vscode)
      for skill_name in "${SKILL_NAMES[@]}"; do
        printf '%s/.agents/skills/%s/SKILL.md\n' "$HOME" "$skill_name"
      done
      ;;
    *)
      return 1
      ;;
  esac
}

tool_mcp_static_paths() {
  local tool="$1"
  case "$tool" in
    opencode)
      printf '%s/.config/opencode/opencode.json\n' "$HOME"
      ;;
    claude-code)
      printf '%s/.claude.json\n' "$HOME"
      ;;
    codex)
      printf '%s/.codex/config.toml\n' "$HOME"
      ;;
    github-copilot-cli)
      printf '%s/.copilot/mcp-config.json\n' "$HOME"
      ;;
    cline)
      printf '%s/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json\n' "$HOME"
      ;;
    continue)
      printf '%s/.continue/mcpServers/%s.json\n' "$HOME" "$CONTEXT7_SERVER_NAME"
      ;;
    vscode)
      printf '%s/.config/Code/User/mcp.json\n' "$HOME"
      ;;
    gemini-cli)
      printf '%s/.gemini/settings.json\n' "$HOME"
      ;;
    *)
      return 1
      ;;
  esac
}

tool_has_mcp_cli_check() {
  local tool="$1"
  case "$tool" in
    opencode|claude-code|codex|gemini-cli) return 0 ;;
    *) return 1 ;;
  esac
}

tool_supports_figma_mcp() {
  local tool="$1"
  case "$tool" in
    opencode|claude-code) return 0 ;;
    *) return 1 ;;
  esac
}

tool_supports_browser_mcp() {
  local tool="$1"
  case "$tool" in
    opencode|claude-code) return 0 ;;
    *) return 1 ;;
  esac
}

selected_tools_support_figma() {
  local tool
  for tool in "$@"; do
    if tool_supports_figma_mcp "$tool"; then
      return 0
    fi
  done
  return 1
}

selected_tools_support_browser_mcp() {
  local tool
  for tool in "$@"; do
    if tool_supports_browser_mcp "$tool"; then
      return 0
    fi
  done
  return 1
}

tool_has_native_skills_shell_check() {
  return 1
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

_mvi_header() {
  local tool="$1"
  section_divider
  note "$(format_label "  $tool")"
  section_divider
}

print_manual_verification_instructions() {
  log "Manual verification instructions"
  local tool
  local skill_response="I greet you from the world of skills, user! You shall use me skillfully."
  local installed_skills="$(join_by ', ' "${SKILL_NAMES[@]}")"
  for tool in "$@"; do
    case "$tool" in
      claude-code)
        _mvi_header "$tool"
        note "  1. Open Claude Code."
        note "  2. Run in chat: /mcp"
        note "     Confirm ${CONTEXT7_SERVER_NAME} is connected."
        if (( ENABLE_FIGMA )); then
          note "     Confirm ${FIGMA_SERVER_NAME} is listed. Authenticate it from /mcp if prompted."
        fi
        note "     Confirm ${BROWSER_MCP_SERVER_NAME} is listed after you install/connect the browser extension."
        note "  3. Confirm installed skills include: ${installed_skills}"
        note "  4. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      opencode)
        _mvi_header "$tool"
        note "  1. Open OpenCode."
        note "  2. Prompt in chat: Use context7 to look up ABP.io caching strategies."
        if (( ENABLE_FIGMA )); then
          note "  3. Run in chat: Use Figma to inspect the current selection."
          note "     Confirm ${FIGMA_SERVER_NAME} is listed and authenticated in OpenCode MCP settings."
          note "     Confirm ${BROWSER_MCP_SERVER_NAME} is listed after you install/connect the browser extension."
          note "  4. Confirm installed skills include: ${installed_skills}"
          note "  5. Prompt in chat: Run the test-skill skill."
        else
          note "  3. Confirm ${BROWSER_MCP_SERVER_NAME} is listed after you install/connect the browser extension."
          note "  4. Confirm installed skills include: ${installed_skills}"
          note "  5. Prompt in chat: Run the test-skill skill."
        fi
        note "     Expected: \"${skill_response}\""
        ;;
      codex)
        _mvi_header "$tool"
        note "  1. Open Codex."
        note "  2. Run in chat: /mcp"
        note "     Confirm ${CONTEXT7_SERVER_NAME} is connected."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for Codex in this installer yet.)"
        fi
        note "  3. Run in chat: /skills"
        note "     Confirm ${installed_skills} are listed."
        note "  4. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      gemini-cli)
        _mvi_header "$tool"
        note "  1. Open Gemini CLI."
        note "  2. Run in chat: /mcp"
        note "     Confirm ${CONTEXT7_SERVER_NAME} is connected."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for Gemini CLI in this installer yet.)"
        fi
        note "  3. Confirm installed skills include: ${installed_skills}"
        note "  4. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      github-copilot-cli)
        _mvi_header "$tool"
        note "  1. Open GitHub Copilot CLI."
        note "  2. Run in chat: /mcp"
        note "     Confirm ${CONTEXT7_SERVER_NAME} is listed."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for GitHub Copilot CLI in this installer yet.)"
        fi
        note "  3. Run in chat: /skills list"
        note "     Confirm ${installed_skills} are listed."
        note "  4. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      vscode)
        _mvi_header "$tool"
        note "  1. Open VS Code."
        note "  2. Open Command Palette (Ctrl+Shift+P) → MCP: List Servers."
        note "     Confirm ${CONTEXT7_SERVER_NAME} is listed."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for VS Code in this installer yet.)"
        fi
        note "  3. Open Copilot Chat in Agent mode."
        note "     Confirm skill tools appear in the tools panel."
        note "  4. Confirm installed skills include: ${installed_skills}"
        note "  5. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      github-copilot)
        _mvi_header "$tool"
        note "  1. Open VS Code."
        note "  2. Open Command Palette (Ctrl+Shift+P) → MCP: List Servers."
        note "     (MCP is wired via the vscode target)"
        note "     Confirm ${CONTEXT7_SERVER_NAME} is listed."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for GitHub Copilot in this installer yet.)"
        fi
        note "  3. Open Copilot Chat in Agent mode."
        note "     Confirm skill tools appear in the tools panel."
        note "  4. Confirm installed skills include: ${installed_skills}"
        note "  5. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      cline)
        _mvi_header "$tool"
        note "  1. Open Cline."
        note "  2. Open MCP Servers panel."
        note "     Confirm ${CONTEXT7_SERVER_NAME} is listed and connected."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for Cline in this installer yet.)"
        fi
        note "  3. Confirm installed skills include: ${installed_skills}"
        note "  4. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      cursor)
        _mvi_header "$tool"
        note "  1. Open Cursor."
        note "  2. Open Settings → MCP."
        note "     Confirm ${CONTEXT7_SERVER_NAME} is listed."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for Cursor in this installer yet.)"
        fi
        note "  3. Confirm installed skills include: ${installed_skills}"
        note "  4. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      windsurf)
        _mvi_header "$tool"
        note "  1. Open Windsurf."
        note "  2. Open Cascade → MCP panel."
        note "     Confirm ${CONTEXT7_SERVER_NAME} is listed."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for Windsurf in this installer yet.)"
        fi
        note "  3. Confirm installed skills include: ${installed_skills}"
        note "  4. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      roo)
        _mvi_header "$tool"
        note "  1. Open VS Code with Roo."
        note "  2. Open MCP Servers panel."
        note "     Confirm ${CONTEXT7_SERVER_NAME} is listed and connected."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for Roo in this installer yet.)"
        fi
        note "  3. Confirm installed skills include: ${installed_skills}"
        note "  4. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      continue)
        _mvi_header "$tool"
        note "  1. Open VS Code with Continue."
        note "  2. Prompt in chat: Use context7 to look up ABP.io caching strategies."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for Continue in this installer yet.)"
        fi
        note "  3. Confirm installed skills include: ${installed_skills}"
        note "  4. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
      goose)
        _mvi_header "$tool"
        note "  1. Open Goose."
        note "  2. Prompt in chat: Use context7 to look up ABP.io caching strategies."
        if (( ENABLE_FIGMA )); then
          note "     (Figma MCP is not wired automatically for Goose in this installer yet.)"
        fi
        note "  3. Confirm installed skills include: ${installed_skills}"
        note "  4. Prompt in chat: Run the test-skill skill."
        note "     Expected: \"${skill_response}\""
        ;;
    esac
  done
  section_divider
}
