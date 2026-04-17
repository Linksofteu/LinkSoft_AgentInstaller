#!/usr/bin/env bash

set -Eeuo pipefail

VERSION="1.1.0"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=setup-agentic-tools/lib/common.sh
source "$SCRIPT_DIR/setup-agentic-tools/lib/common.sh"
# shellcheck source=setup-agentic-tools/lib/tooling.sh
source "$SCRIPT_DIR/setup-agentic-tools/lib/tooling.sh"
# shellcheck source=setup-agentic-tools/lib/install.sh
source "$SCRIPT_DIR/setup-agentic-tools/lib/install.sh"
# shellcheck source=setup-agentic-tools/lib/verify.sh
source "$SCRIPT_DIR/setup-agentic-tools/lib/verify.sh"

SKILL_SOURCES=(
  "Linksofteu/LinkSoft_Skills@test-skill"
  "Linksofteu/LinkSoft_Skills@ddd-application-slice"
  "Linksofteu/LinkSoft_Skills@creating-linksoft-skills"
)
SKILL_NAMES=(
  "test-skill"
  "ddd-application-slice"
  "creating-linksoft-skills"
)
CONTEXT7_SERVER_NAME="context7"
CONTEXT7_URL="https://mcp.context7.com/mcp"
FIGMA_SERVER_NAME="figma"
FIGMA_URL="https://mcp.figma.com/mcp"
FIGMA_REGISTER_URL="https://api.figma.com/v1/oauth/mcp/register"
FIGMA_OPENCODE_REDIRECT_URI="http://127.0.0.1:19876/mcp/oauth/callback"
FIGMA_CLAUDE_CODE_REDIRECT_URI="http://localhost:19876/callback"
BROWSER_MCP_SERVER_NAME="browsermcp"
BROWSER_MCP_PACKAGE="@browsermcp/mcp@latest"
BROWSER_MCP_EXTENSION_URL="https://chromewebstore.google.com/detail/browser-mcp-automate-your/bjfgambnhccakkhmkepdoekmckoijdlc?pli=1"
DEFAULT_LOG_FILE="$(default_log_file_path)"

NON_INTERACTIVE=0
COPY_SKILLS=0
DRY_RUN=0
VERBOSE=0
LOG_FILE=""
TOOLS_CSV=""
ADDITIONAL_TOOLS_CSV=""
CONTEXT7_API_KEY_INPUT=""
ENABLE_FIGMA=1
FIGMA_CLIENT_ID_INPUT=""
FIGMA_CLIENT_SECRET_INPUT=""
SKIP_SKILLS=0
SKIP_MCP=0
SKIP_VERIFY=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Installs the default LinkSoft skills via npx skills, installs/configures Context7,
optionally wires Figma MCP for supported tools, then runs static and smoke
verification where supported.

Version: $VERSION

Options:
  --tools CSV              Final tool ids to configure
  --extra-tools CSV        Additional tool ids to merge with detected tools
  --context7-api-key KEY   Optional Context7 API key
  --figma                  Enable Figma MCP wiring where supported (default)
  --figma-client-id ID     Pre-registered Figma OAuth client id
  --figma-client-secret S  Pre-registered Figma OAuth client secret
  --log-file PATH          Log file path (default: $DEFAULT_LOG_FILE)
  --copy-skills            Use --copy instead of symlinks for skills installation
  --skip-skills            Skip the npx skills installation step
  --skip-mcp               Skip the MCP/Context7 installation step
  --skip-verify            Skip post-install verification
  --non-interactive        Do not prompt the user
  -v, --verbose            Enable detailed command logging
  --dry-run                Print actions without executing them (implies non-interactive preview)
  -h, --help               Show this help

Known tool ids:
  $(printf '%s ' "${KNOWN_TOOLS[@]}")
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --tools)
        [[ $# -ge 2 ]] || die "--tools requires a value"
        TOOLS_CSV="$2"
        shift 2
        ;;
      --extra-tools)
        [[ $# -ge 2 ]] || die "--extra-tools requires a value"
        ADDITIONAL_TOOLS_CSV="$2"
        shift 2
        ;;
      --context7-api-key)
        [[ $# -ge 2 ]] || die "--context7-api-key requires a value"
        CONTEXT7_API_KEY_INPUT="$2"
        shift 2
        ;;
      --figma)
        ENABLE_FIGMA=1
        shift
        ;;
      --figma-client-id)
        [[ $# -ge 2 ]] || die "--figma-client-id requires a value"
        FIGMA_CLIENT_ID_INPUT="$2"
        ENABLE_FIGMA=1
        shift 2
        ;;
      --figma-client-secret)
        [[ $# -ge 2 ]] || die "--figma-client-secret requires a value"
        FIGMA_CLIENT_SECRET_INPUT="$2"
        ENABLE_FIGMA=1
        shift 2
        ;;
      --log-file)
        [[ $# -ge 2 ]] || die "--log-file requires a value"
        LOG_FILE="$2"
        shift 2
        ;;
      --copy-skills)
        COPY_SKILLS=1
        shift
        ;;
      --skip-skills)
        SKIP_SKILLS=1
        shift
        ;;
      --skip-mcp)
        SKIP_MCP=1
        shift
        ;;
      --skip-verify)
        SKIP_VERIFY=1
        shift
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -v|--verbose)
        VERBOSE=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  if (( DRY_RUN != 0 && NON_INTERACTIVE == 0 )); then
    NON_INTERACTIVE=1
  fi
  ensure_log_file
  enable_error_reporting
  note "$(format_label "Version:") $(format_value "$VERSION")"
  if (( DRY_RUN != 0 )); then
    note "$(format_label "Mode:") $(format_value "dry-run (non-interactive preview)")"
  fi
  ensure_prereqs

  printf '\n%s%sAgentic Tools Setup v%s%s\n' "$COLOR_BOLD" "$COLOR_BLUE" "$VERSION" "$COLOR_RESET"
  section_divider

  debug_section "Environment"
  debug "script_dir=$SCRIPT_DIR"
  debug "log_file=$LOG_FILE"
  debug "non_interactive=$NON_INTERACTIVE dry_run=$DRY_RUN verbose=$VERBOSE copy_skills=$COPY_SKILLS skip_skills=$SKIP_SKILLS skip_mcp=$SKIP_MCP skip_verify=$SKIP_VERIFY"
  debug "tools_csv=${TOOLS_CSV:-<empty>}"
  debug "extra_tools_csv=${ADDITIONAL_TOOLS_CSV:-<empty>}"
  debug "context7_api_key_provided=$([[ -n "$CONTEXT7_API_KEY_INPUT" ]] && printf yes || printf no)"
  debug "figma_enabled=$ENABLE_FIGMA figma_client_id_provided=$([[ -n "$FIGMA_CLIENT_ID_INPUT" ]] && printf yes || printf no) figma_client_secret_provided=$([[ -n "$FIGMA_CLIENT_SECRET_INPUT" ]] && printf yes || printf no)"

  local -a detected_tools=()
  detect_installed_tools detected_tools

  if ((${#detected_tools[@]})); then
    note "$(format_label "Detected tools:") $(format_value "$(join_by ', ' "${detected_tools[@]}")")"
  else
    note "$(format_label "Detected tools:") $(format_value "(none)")"
  fi

  note "$(format_label "Available tool ids:") $(join_by ', ' "${KNOWN_TOOLS[@]}")"

  debug_section "Detected tools"
  if ((${#detected_tools[@]})); then
    debug "$(join_by ', ' "${detected_tools[@]}")"
  else
    debug "(none detected)"
  fi

  printf '\n'
  section_divider
  printf '\n'

  local -a validated_tools=()
  while true; do
    local additional_csv="$ADDITIONAL_TOOLS_CSV"
    local skipped_manual_selection=0
    phase 1 5 "Selecting tools"
    if (( NON_INTERACTIVE == 0 )) && [[ -z "$additional_csv" ]]; then
      additional_csv="$(prompt_csv "Enter any additional tool ids to configure (comma-separated, or blank for none)")"
    fi

    local -a additional_tools=()
    parse_csv_into_array "$additional_csv" additional_tools

    local -a invalid_additional_tools=()
    local tool
    for tool in "${additional_tools[@]}"; do
      if ! is_known_tool "$tool"; then
        invalid_additional_tools+=("$tool")
      fi
    done

    if ((${#invalid_additional_tools[@]})); then
      warn "The following tool ids are not recognised and will be skipped: $(join_by ', ' "${invalid_additional_tools[@]}")"
      note "$(format_label "Known tool ids:") $(join_by ', ' "${KNOWN_TOOLS[@]}")"
    fi

    local -a merged_tools=("${detected_tools[@]}")
    merge_known_tools merged_tools "${additional_tools[@]}"

    local merged_default
    merged_default="$(join_by ',' "${merged_tools[@]}")"

    note "$(format_label "Default selected tools:") $(format_value "${merged_default:-<none>}")"

    local final_csv="$TOOLS_CSV"
    if [[ -z "$final_csv" ]]; then
      if (( NON_INTERACTIVE )); then
        final_csv="$merged_default"
      elif [[ -z "$additional_csv" ]]; then
        final_csv="$merged_default"
        skipped_manual_selection=1
      else
        final_csv="$(prompt_csv "Choose tools to install into" "$merged_default")"
      fi
    fi

    local -a selected_tools=()
    parse_csv_into_array "$final_csv" selected_tools

    validated_tools=()
    validate_known_tools validated_tools "${selected_tools[@]}"
    ((${#validated_tools[@]})) || die "No valid tools selected"

    note "$(format_label "Selected tools:") $(format_value "$(join_by ', ' "${validated_tools[@]}")")"

    if (( skipped_manual_selection )); then
      debug "Skipped manual tool selection because no additional tools were entered"
    fi

    if (( NON_INTERACTIVE )); then
      break
    fi

    local confirm_install
    printf 'Tools to configure:\n' > /dev/tty
    for tool in "${validated_tools[@]}"; do
      printf '  • %s\n' "$tool" > /dev/tty
    done
    read -r -p "Proceed with installation? [y/N]: " confirm_install </dev/tty
    case "$confirm_install" in
      y|Y|yes|YES)
        break
        ;;
      *)
        note "Restarting tool selection..."
        TOOLS_CSV=""
        ADDITIONAL_TOOLS_CSV=""
        printf '\n'
        ;;
    esac
  done

  local api_key="$CONTEXT7_API_KEY_INPUT"
  if (( NON_INTERACTIVE == 0 )) && [[ -z "$api_key" ]]; then
    read -r -s -p "Optional Context7 API key (press Enter to skip): " api_key </dev/tty
    printf '\n' > /dev/tty
  fi

  if (( SKIP_SKILLS == 0 )); then
    phase 2 5 "Installing skills"
    install_skill "${validated_tools[@]}"
  else
    log "Skipping skills installation"
  fi

  if (( SKIP_MCP == 0 )); then
    phase 3 5 "Installing and wiring MCP"
    install_context7_server "$api_key"
    wire_context7_to_tools "$api_key" "${validated_tools[@]}"
    if (( ENABLE_FIGMA )) && selected_tools_support_figma "${validated_tools[@]}"; then
      install_figma_server
      wire_figma_to_tools "$FIGMA_CLIENT_ID_INPUT" "$FIGMA_CLIENT_SECRET_INPUT" "${validated_tools[@]}"
    fi
    if selected_tools_support_browser_mcp "${validated_tools[@]}"; then
      install_browser_server
      wire_browser_to_tools "${validated_tools[@]}"
    fi
  else
    log "Skipping MCP installation"
  fi

  if (( SKIP_VERIFY == 0 )); then
    phase 4 5 "Running verification"
    run_verification "${validated_tools[@]}"
  else
    log "Skipping verification"
  fi

  phase 5 5 "Printing manual follow-up steps"
  note "$(format_label "Browser MCP extension:") $(format_value "$BROWSER_MCP_EXTENSION_URL")"
  note "Install this extension in Chrome, Chromium, or Vivaldi to make Browser MCP work."
  if (( NON_INTERACTIVE == 0 )); then
    read -r -p "Press Enter after installing the Browser MCP extension to view manual verification steps..." </dev/tty
  else
    note "Non-interactive mode: unable to wait for Enter before printing manual verification steps."
  fi
  print_manual_verification_instructions "${validated_tools[@]}"

  log "Done"
  note "$(format_label "Configured tools:") $(format_value "$(join_by ', ' "${validated_tools[@]}")")"
  note "$(format_label "Skill sources:") $(format_value "$(join_by ', ' "${SKILL_SOURCES[@]}")")"
  local -a configured_servers=("$CONTEXT7_SERVER_NAME")
  if (( ENABLE_FIGMA )) && selected_tools_support_figma "${validated_tools[@]}"; then
    configured_servers+=("$FIGMA_SERVER_NAME")
  fi
  if selected_tools_support_browser_mcp "${validated_tools[@]}"; then
    configured_servers+=("$BROWSER_MCP_SERVER_NAME")
  fi
  note "$(format_label "MCP servers:") $(format_value "$(join_by ', ' "${configured_servers[@]}")")"
  note "$(format_label "Log file:") $(format_value "$LOG_FILE")"
}

main "$@"
