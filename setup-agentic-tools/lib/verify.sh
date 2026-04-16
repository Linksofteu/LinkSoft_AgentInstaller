#!/usr/bin/env bash
# Expects caller to enable strict mode (set -euo pipefail).

VERIFY_PASS_COUNT=0
VERIFY_FAIL_COUNT=0
VERIFY_SKIP_COUNT=0
VERIFY_FAILED_LABELS=()

ensure_verify_globals() {
  : "${SKILL_NAME:?SKILL_NAME must be set}"
  : "${CONTEXT7_SERVER_NAME:?CONTEXT7_SERVER_NAME must be set}"
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

  local tool skill_paths found_path path resolved_path
  for tool in "$@"; do
    if ! skill_paths="$(tool_skill_static_paths "$tool" 2>/dev/null)"; then
      report_verification_check "SKIP" "skills/$tool" "no documented static skill path mapping"
      continue
    fi

    found_path=""
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      if [[ -f "$path" ]]; then
        found_path="$path"
        break
      fi
    done <<< "$skill_paths"

    if [[ -n "$found_path" ]]; then
      if [[ -L "$found_path" ]]; then
        resolved_path="$(readlink -f "$found_path" 2>/dev/null || true)"
        if [[ -n "$resolved_path" ]]; then
          report_verification_check "PASS" "skills/$tool" "found symlink $found_path -> $resolved_path"
        else
          report_verification_check "PASS" "skills/$tool" "found symlink $found_path"
        fi
      else
        report_verification_check "PASS" "skills/$tool" "found $found_path"
      fi
    else
      local joined_paths="${skill_paths//$'\n'/,}"
      joined_paths="${joined_paths%,}"
      report_verification_check "FAIL" "skills/$tool" "missing expected skill file in: $joined_paths"
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

  local mcpm_servers=""
  if mcpm_servers="$(capture_cmd mcpm ls)"; then
    if grep -qi "$CONTEXT7_SERVER_NAME" <<<"$mcpm_servers"; then
      report_verification_check "PASS" "mcp/global" "mcpm knows about $CONTEXT7_SERVER_NAME"
    else
      report_verification_check "FAIL" "mcp/global" "mcpm ls did not include $CONTEXT7_SERVER_NAME"
    fi
  else
    report_verification_check "FAIL" "mcp/global" "unable to list MCPM servers"
  fi

  local mcpm_clients=""
  mcpm_clients="$(capture_cmd mcpm client ls || true)"

  local tool client_name
  for tool in "$@"; do
    case "$tool" in
      opencode)
        if grep -q '"context7"' "$HOME/.config/opencode/opencode.json" 2>/dev/null; then
          report_verification_check "PASS" "mcp/opencode" "OpenCode config contains context7"
        else
          report_verification_check "FAIL" "mcp/opencode" "OpenCode config missing context7"
        fi
        ;;
      vscode)
        if grep -q 'mcpm_context7' "$HOME/.config/Code/User/mcp.json" 2>/dev/null; then
          report_verification_check "PASS" "mcp/vscode" "VS Code mcp.json contains mcpm_context7"
        else
          report_verification_check "FAIL" "mcp/vscode" "VS Code mcp.json missing mcpm_context7"
        fi
        ;;
      github-copilot-cli)
        local copilot_home
        copilot_home="${COPILOT_HOME:-$HOME/.copilot}"
        if grep -q '"mcpServers"' "$copilot_home/mcp-config.json" 2>/dev/null && grep -q 'mcpm_context7' "$copilot_home/mcp-config.json" 2>/dev/null; then
          report_verification_check "PASS" "mcp/github-copilot-cli" "Copilot CLI mcp-config.json contains mcpm_context7"
        else
          report_verification_check "FAIL" "mcp/github-copilot-cli" "Copilot CLI mcp-config.json missing mcpm_context7"
        fi
        ;;
      github-copilot)
        report_verification_check "SKIP" "mcp/github-copilot" "use the vscode target for Copilot-in-VS-Code MCP verification"
        ;;
      *)
        if client_name="$(mcpm_client_name "$tool" 2>/dev/null)"; then
          if grep -Eiq "${client_name}.*${CONTEXT7_SERVER_NAME}|${tool}.*${CONTEXT7_SERVER_NAME}|${CONTEXT7_SERVER_NAME}.*${client_name}|${CONTEXT7_SERVER_NAME}.*${tool}" <<<"$mcpm_clients"; then
            report_verification_check "PASS" "mcp/$tool" "mcpm client list shows Context7 for $client_name"
          else
            report_verification_check "FAIL" "mcp/$tool" "mcpm client list did not show Context7 for $client_name"
          fi
        else
          report_verification_check "SKIP" "mcp/$tool" "no static MCP verification rule defined"
        fi
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
      if grep -q "$SKILL_NAME" <<<"$output"; then
        if [[ -n "$hint" ]]; then
          report_verification_check "PASS" "skills-cli/$tool" "skills.sh fallback for $agent included $SKILL_NAME; native check available manually via $hint"
        else
          report_verification_check "PASS" "skills-cli/$tool" "skills.sh fallback for $agent included $SKILL_NAME"
        fi
      else
        if [[ -n "$hint" ]]; then
          report_verification_check "FAIL" "skills-cli/$tool" "skills.sh fallback for $agent did not include $SKILL_NAME; native check available manually via $hint"
        else
          report_verification_check "FAIL" "skills-cli/$tool" "skills.sh fallback for $agent did not include $SKILL_NAME"
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
  output="$(capture_cmd mcpm ls || true)"
  if grep -qi "$CONTEXT7_SERVER_NAME" <<<"$output"; then
    report_verification_check "PASS" "mcpm" "mcpm ls included $CONTEXT7_SERVER_NAME"
  else
    report_verification_check "FAIL" "mcpm" "mcpm ls did not include $CONTEXT7_SERVER_NAME"
  fi

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
        elif output="$(capture_cmd opencode mcp list || true)"; then
          if grep -q 'context7' <<<"$output"; then
            report_verification_check "PASS" "mcp-cli/opencode" "opencode mcp list included context7"
          else
            report_verification_check "FAIL" "mcp-cli/opencode" "opencode mcp list did not include context7"
          fi
        else
          report_verification_check "FAIL" "mcp-cli/opencode" "unable to query opencode mcp list"
        fi
        ;;
      claude-code)
        if ! has_cmd claude; then
          report_verification_check "SKIP" "mcp-cli/claude-code" "claude executable not found"
        elif output="$(capture_cmd claude mcp list || true)"; then
          if grep -q 'context7' <<<"$output"; then
            report_verification_check "PASS" "mcp-cli/claude-code" "claude mcp list included context7"
          else
            report_verification_check "FAIL" "mcp-cli/claude-code" "claude mcp list did not include context7"
          fi
        else
          report_verification_check "FAIL" "mcp-cli/claude-code" "unable to query claude mcp list"
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
