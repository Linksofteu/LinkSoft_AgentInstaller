#!/usr/bin/env bash

set -Eeuo pipefail

REPO_OWNER="Linksofteu"
REPO_NAME="LinkSoft_AgentInstaller"
REPO_REF="main"
ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_REF}.tar.gz"
BOOTSTRAP_LOG_FILE=""

default_log_root() {
  if [[ -n "${XDG_STATE_HOME:-}" ]]; then
    printf '%s/linksoft-agent-installer/logs' "$XDG_STATE_HOME"
  elif [[ -n "${HOME:-}" ]]; then
    printf '%s/.local/state/linksoft-agent-installer/logs' "$HOME"
  else
    printf '%s' "."
  fi
}

append_log() {
  [[ -n "${BOOTSTRAP_LOG_FILE:-}" ]] || return 0
  mkdir -p "$(dirname "$BOOTSTRAP_LOG_FILE")"
  printf '%s\n' "$1" >> "$BOOTSTRAP_LOG_FILE"
}

init_log_file() {
  if [[ -z "${BOOTSTRAP_LOG_FILE:-}" ]]; then
    BOOTSTRAP_LOG_FILE="$(default_log_root)/setup-agentic-tools-$(date -u '+%Y%m%dT%H%M%SZ').log"
  fi
  mkdir -p "$(dirname "$BOOTSTRAP_LOG_FILE")"
  printf '=== install.sh session started %s ===\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$BOOTSTRAP_LOG_FILE"
}

print_log_hint() {
  [[ -n "${BOOTSTRAP_LOG_FILE:-}" ]] || return 0
  printf 'Log file: %s\n' "$BOOTSTRAP_LOG_FILE" >&2
}

report_bootstrap_error() {
  local exit_code="$1"
  local line_no="$2"
  local command_text="$3"
  append_log "ERROR bootstrap failed with exit code ${exit_code} at line ${line_no}: ${command_text}"
  printf 'Error: bootstrap failed at line %s while running: %s\n' "$line_no" "$command_text" >&2
  print_log_hint
}

extract_log_file_arg() {
  local prev_is_log_file=0
  local arg
  for arg in "$@"; do
    if (( prev_is_log_file )); then
      BOOTSTRAP_LOG_FILE="$arg"
      return 0
    fi
    if [[ "$arg" == "--log-file" ]]; then
      prev_is_log_file=1
    fi
  done
}

ensure_log_arg() {
  local -n args_ref=$1
  local arg
  for arg in "${args_ref[@]}"; do
    if [[ "$arg" == "--log-file" ]]; then
      return 0
    fi
  done
  args_ref+=(--log-file "$BOOTSTRAP_LOG_FILE")
}

cleanup() {
  if [[ -n "${TMP_DIR:-}" && -d "${TMP_DIR:-}" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Error: required command not found: %s\n' "$1" >&2
    exit 1
  }
}

main() {
  trap 'exit_code=$?; report_bootstrap_error "$exit_code" "${BASH_LINENO[0]:-${LINENO}}" "${BASH_COMMAND:-unknown}"' ERR
  require_cmd bash
  require_cmd curl
  require_cmd tar
  require_cmd mktemp

  local -a forwarded_args=("$@")
  extract_log_file_arg "${forwarded_args[@]}"
  init_log_file
  ensure_log_arg forwarded_args
  printf 'Log file: %s\n' "$BOOTSTRAP_LOG_FILE"
  append_log "Downloading ${REPO_OWNER}/${REPO_NAME} (${REPO_REF})"

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT

  printf 'Downloading %s/%s (%s)...\n' "$REPO_OWNER" "$REPO_NAME" "$REPO_REF"
  local archive_path="$TMP_DIR/${REPO_NAME}-${REPO_REF}.tar.gz"
  curl -fsSL "$ARCHIVE_URL" -o "$archive_path" >> "$BOOTSTRAP_LOG_FILE" 2>&1
  append_log "Downloaded archive to $archive_path"
  tar -xzf "$archive_path" -C "$TMP_DIR" >> "$BOOTSTRAP_LOG_FILE" 2>&1
  append_log "Expanded archive into $TMP_DIR"

  local extracted_dir="$TMP_DIR/${REPO_NAME}-${REPO_REF}"
  local entrypoint="$extracted_dir/setup-agentic-tools.sh"

  if [[ ! -f "$entrypoint" ]]; then
    printf 'Error: expected entrypoint not found: %s\n' "$entrypoint" >&2
    exit 1
  fi

  exec bash "$entrypoint" "${forwarded_args[@]}"
}

main "$@"
