#!/usr/bin/env bash
# Expects caller to enable strict mode (set -euo pipefail).

VERIFY_PASS_COUNT=0
VERIFY_FAIL_COUNT=0
VERIFY_SKIP_COUNT=0
VERIFY_FAILED_LABELS=()

ensure_verify_globals() {
  : "${CONTEXT7_SERVER_NAME:?CONTEXT7_SERVER_NAME must be set}"
  ((${#SKILL_NAMES[@]} > 0)) || die "SKILL_NAMES must not be empty"
}

reset_verification_counts() {
  VERIFY_PASS_COUNT=0
  VERIFY_FAIL_COUNT=0
  VERIFY_SKIP_COUNT=0
  VERIFY_FAILED_LABELS=()
}

record_check_status() {
  local status="$1"
  local label="$2"
  case "$status" in
    PASS) VERIFY_PASS_COUNT=$((VERIFY_PASS_COUNT + 1)) ;;
    FAIL)
      VERIFY_FAIL_COUNT=$((VERIFY_FAIL_COUNT + 1))
      VERIFY_FAILED_LABELS+=("$label")
      ;;
    SKIP) VERIFY_SKIP_COUNT=$((VERIFY_SKIP_COUNT + 1)) ;;
  esac
}

report_verification_check() {
  local status="$1"
  local label="$2"
  local details="$3"
  record_check_status "$status" "$label"
  report_check "$status" "$label" "$details"
}

verify_skills_static() {
  log "Static verification: skills"

  local tool skill_paths path
  for tool in "$@"; do
    if ! skill_paths="$(tool_skill_static_paths "$tool" 2>/dev/null)"; then
      report_verification_check "SKIP" "skills/$tool" "no documented static skill path mapping"
      continue
    fi

    local -a missing_paths=()
    local found_count=0
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      if [[ -f "$path" ]]; then
        found_count=$((found_count + 1))
      else
        missing_paths+=("$path")
      fi
    done <<< "$skill_paths"

    if ((${#missing_paths[@]} == 0)); then
      report_verification_check "PASS" "skills/$tool" "found all ${found_count} expected skill files"
    else
      report_verification_check "FAIL" "skills/$tool" "missing expected skill file in: $(join_by ', ' "${missing_paths[@]}")"
    fi
  done
}

verify_mcp_static() {
  log "Static verification: MCP"

  if (( DRY_RUN != 0 )); then
    report_verification_check "SKIP" "mcp/global" "dry-run mode does not execute verification commands"
    return 0
  fi

  if (( SKIP_MCP != 0 )); then
    report_verification_check "SKIP" "mcp/global" "MCP installation was skipped"
    return 0
  fi

  local tool
  for tool in "$@"; do
    case "$tool" in
      opencode)
        if grep -q "\"$CONTEXT7_SERVER_NAME\"" "$HOME/.config/opencode/opencode.json" 2>/dev/null && grep -q '"type": "remote"' "$HOME/.config/opencode/opencode.json" 2>/dev/null; then
          report_verification_check "PASS" "mcp/opencode" "OpenCode config contains a direct $CONTEXT7_SERVER_NAME remote server"
        else
          report_verification_check "FAIL" "mcp/opencode" "OpenCode config missing $CONTEXT7_SERVER_NAME"
        fi
        ;;
      claude-code)
        if grep -q '"mcpServers"' "$HOME/.claude.json" 2>/dev/null && grep -q "\"$CONTEXT7_SERVER_NAME\"" "$HOME/.claude.json" 2>/dev/null; then
          report_verification_check "PASS" "mcp/claude-code" "Claude Code config contains $CONTEXT7_SERVER_NAME"
        else
          report_verification_check "FAIL" "mcp/claude-code" "Claude Code config missing $CONTEXT7_SERVER_NAME"
        fi
        ;;
      codex)
        if grep -q "^\[mcp_servers\.$CONTEXT7_SERVER_NAME\]" "$HOME/.codex/config.toml" 2>/dev/null && grep -q "url = \"$CONTEXT7_URL\"" "$HOME/.codex/config.toml" 2>/dev/null; then
          report_verification_check "PASS" "mcp/codex" "Codex config.toml contains $CONTEXT7_SERVER_NAME"
        else
          report_verification_check "FAIL" "mcp/codex" "Codex config.toml missing $CONTEXT7_SERVER_NAME"
        fi
        ;;
      vscode)
        if grep -q "\"$CONTEXT7_SERVER_NAME\"" "$HOME/.config/Code/User/mcp.json" 2>/dev/null && grep -q "\"url\": \"$CONTEXT7_URL\"" "$HOME/.config/Code/User/mcp.json" 2>/dev/null; then
          report_verification_check "PASS" "mcp/vscode" "VS Code mcp.json contains $CONTEXT7_SERVER_NAME"
        else
          report_verification_check "FAIL" "mcp/vscode" "VS Code mcp.json missing $CONTEXT7_SERVER_NAME"
        fi
        ;;
      github-copilot-cli)
        local copilot_home
        copilot_home="${COPILOT_HOME:-$HOME/.copilot}"
        if grep -q '"mcpServers"' "$copilot_home/mcp-config.json" 2>/dev/null && grep -q "\"$CONTEXT7_SERVER_NAME\"" "$copilot_home/mcp-config.json" 2>/dev/null; then
          report_verification_check "PASS" "mcp/github-copilot-cli" "Copilot CLI mcp-config.json contains $CONTEXT7_SERVER_NAME"
        else
          report_verification_check "FAIL" "mcp/github-copilot-cli" "Copilot CLI mcp-config.json missing $CONTEXT7_SERVER_NAME"
        fi
        ;;
      github-copilot)
        report_verification_check "SKIP" "mcp/github-copilot" "use the vscode target for Copilot-in-VS-Code MCP verification"
        ;;
      cline)
        if grep -q '"mcpServers"' "$HOME/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json" 2>/dev/null && grep -q "\"$CONTEXT7_SERVER_NAME\"" "$HOME/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json" 2>/dev/null; then
          report_verification_check "PASS" "mcp/cline" "Cline MCP settings contain $CONTEXT7_SERVER_NAME"
        else
          report_verification_check "FAIL" "mcp/cline" "Cline MCP settings missing $CONTEXT7_SERVER_NAME"
        fi
        ;;
      continue)
        if grep -q "\"$CONTEXT7_SERVER_NAME\"" "$HOME/.continue/mcpServers/$CONTEXT7_SERVER_NAME.json" 2>/dev/null && grep -q "\"url\": \"$CONTEXT7_URL\"" "$HOME/.continue/mcpServers/$CONTEXT7_SERVER_NAME.json" 2>/dev/null; then
          report_verification_check "PASS" "mcp/continue" "Continue MCP config contains $CONTEXT7_SERVER_NAME"
        else
          report_verification_check "FAIL" "mcp/continue" "Continue MCP config missing $CONTEXT7_SERVER_NAME"
        fi
        ;;
      gemini-cli)
        if grep -q '"mcpServers"' "$HOME/.gemini/settings.json" 2>/dev/null && grep -q "\"$CONTEXT7_SERVER_NAME\"" "$HOME/.gemini/settings.json" 2>/dev/null; then
          report_verification_check "PASS" "mcp/gemini-cli" "Gemini CLI settings contain $CONTEXT7_SERVER_NAME"
        else
          report_verification_check "FAIL" "mcp/gemini-cli" "Gemini CLI settings missing $CONTEXT7_SERVER_NAME"
        fi
        ;;
      *)
        report_verification_check "SKIP" "mcp/$tool" "no static MCP verification rule defined"
        ;;
    esac
  done
}

verify_skills_smoke() {
  log "Smoke verification: skills CLI"

  if (( DRY_RUN != 0 )); then
    report_verification_check "SKIP" "skills-cli/global" "dry-run mode does not execute verification commands"
    return 0
  fi

  local tool agent output
  for tool in "$@"; do
    if tool_has_native_skills_shell_check "$tool"; then
      report_verification_check "SKIP" "skills-cli/$tool" "native shell-based skills check not yet implemented for $tool"
      continue
    fi

    if ! agent="$(skill_agent_for_tool "$tool" 2>/dev/null)"; then
      report_verification_check "SKIP" "skills-cli/$tool" "no documented skills CLI mapping"
      continue
    fi

    local hint=""
    hint="$(tool_native_skills_check_hint "$tool" 2>/dev/null || true)"
    if output="$(capture_cmd npx -y skills ls -g -a "$agent" || true)"; then
      local -a missing_skills=()
      local skill_name
      for skill_name in "${SKILL_NAMES[@]}"; do
        if ! grep -q "$skill_name" <<<"$output"; then
          missing_skills+=("$skill_name")
        fi
      done

      if ((${#missing_skills[@]} == 0)); then
        if [[ -n "$hint" ]]; then
          report_verification_check "PASS" "skills-cli/$tool" "skills.sh fallback for $agent included $(join_by ', ' "${SKILL_NAMES[@]}"); native check available manually via $hint"
        else
          report_verification_check "PASS" "skills-cli/$tool" "skills.sh fallback for $agent included $(join_by ', ' "${SKILL_NAMES[@]}")"
        fi
      else
        if [[ -n "$hint" ]]; then
          report_verification_check "FAIL" "skills-cli/$tool" "skills.sh fallback for $agent is missing $(join_by ', ' "${missing_skills[@]}"); native check available manually via $hint"
        else
          report_verification_check "FAIL" "skills-cli/$tool" "skills.sh fallback for $agent is missing $(join_by ', ' "${missing_skills[@]}")"
        fi
      fi
    else
      report_verification_check "FAIL" "skills-cli/$tool" "unable to query skills.sh fallback for $agent"
    fi
  done
}

verify_mcp_smoke() {
  log "Smoke verification: MCP CLIs"

  if (( DRY_RUN != 0 )); then
    report_verification_check "SKIP" "mcp-cli/global" "dry-run mode does not execute verification commands"
    return 0
  fi

  local output
  local tool
  for tool in "$@"; do
    if ! tool_has_mcp_cli_check "$tool"; then
      report_verification_check "SKIP" "mcp-cli/$tool" "no documented CLI check found"
      continue
    fi

    case "$tool" in
      opencode)
        if ! has_cmd opencode; then
          report_verification_check "SKIP" "mcp-cli/opencode" "opencode executable not found"
        elif output="$(capture_cmd opencode mcp list)"; then
          if grep -q "$CONTEXT7_SERVER_NAME" <<<"$output"; then
            report_verification_check "PASS" "mcp-cli/opencode" "opencode mcp list included $CONTEXT7_SERVER_NAME"
          else
            report_verification_check "FAIL" "mcp-cli/opencode" "opencode mcp list did not include $CONTEXT7_SERVER_NAME"
          fi
        else
          report_verification_check "FAIL" "mcp-cli/opencode" "unable to query opencode mcp list"
        fi
        ;;
      claude-code)
        if ! has_cmd claude; then
          report_verification_check "SKIP" "mcp-cli/claude-code" "claude executable not found"
        elif output="$(capture_cmd claude mcp list)"; then
          if grep -q "$CONTEXT7_SERVER_NAME" <<<"$output"; then
            report_verification_check "PASS" "mcp-cli/claude-code" "claude mcp list included $CONTEXT7_SERVER_NAME"
          else
            report_verification_check "FAIL" "mcp-cli/claude-code" "claude mcp list did not include $CONTEXT7_SERVER_NAME"
          fi
        else
          report_verification_check "FAIL" "mcp-cli/claude-code" "unable to query claude mcp list"
        fi
        ;;
      codex)
        if ! has_cmd codex; then
          report_verification_check "SKIP" "mcp-cli/codex" "codex executable not found"
        elif output="$(capture_cmd codex mcp list)"; then
          if grep -q "$CONTEXT7_SERVER_NAME" <<<"$output"; then
            report_verification_check "PASS" "mcp-cli/codex" "codex mcp list included $CONTEXT7_SERVER_NAME"
          else
            report_verification_check "FAIL" "mcp-cli/codex" "codex mcp list did not include $CONTEXT7_SERVER_NAME"
          fi
        else
          report_verification_check "FAIL" "mcp-cli/codex" "unable to query codex mcp list"
        fi
        ;;
      gemini-cli)
        if ! has_cmd gemini; then
          report_verification_check "SKIP" "mcp-cli/gemini-cli" "gemini executable not found"
        elif output="$(capture_cmd gemini mcp list)"; then
          if grep -q "$CONTEXT7_SERVER_NAME" <<<"$output"; then
            report_verification_check "PASS" "mcp-cli/gemini-cli" "gemini mcp list included $CONTEXT7_SERVER_NAME"
          else
            report_verification_check "FAIL" "mcp-cli/gemini-cli" "gemini mcp list did not include $CONTEXT7_SERVER_NAME"
          fi
        else
          report_verification_check "FAIL" "mcp-cli/gemini-cli" "unable to query gemini mcp list"
        fi
        ;;
    esac
  done
}

run_verification() {
  ensure_verify_globals
  local -a selected_tools=("$@")
  reset_verification_counts

  verify_skills_static "${selected_tools[@]}"
  verify_mcp_static "${selected_tools[@]}"
  verify_skills_smoke "${selected_tools[@]}"
  verify_mcp_smoke "${selected_tools[@]}"

  log "Verification summary"
  note "$(format_label "Results:") $(format_value "$VERIFY_PASS_COUNT passed, $VERIFY_FAIL_COUNT failed, $VERIFY_SKIP_COUNT skipped")"
  if (( VERIFY_FAIL_COUNT > 0 )); then
    note "$(format_label "Failed checks:") $(format_value "$(join_by ', ' "${VERIFY_FAILED_LABELS[@]}")")"
  fi
}
