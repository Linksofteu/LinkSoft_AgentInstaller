#!/usr/bin/env bash
# Expects caller to enable strict mode (set -euo pipefail).

setup_colors() {
  if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]] && [[ "${NO_COLOR:-}" != "1" ]]; then
    COLOR_RESET=$'\033[0m'
    COLOR_BOLD=$'\033[1m'
    COLOR_DIM=$'\033[2m'
    COLOR_BLUE=$'\033[38;5;39m'
    COLOR_CYAN=$'\033[38;5;45m'
    COLOR_GREEN=$'\033[38;5;42m'
    COLOR_YELLOW=$'\033[38;5;220m'
    COLOR_RED=$'\033[38;5;196m'
    COLOR_MAGENTA=$'\033[38;5;141m'
    COLOR_GRAY=$'\033[38;5;245m'
  else
    COLOR_RESET=''
    COLOR_BOLD=''
    COLOR_DIM=''
    COLOR_BLUE=''
    COLOR_CYAN=''
    COLOR_GREEN=''
    COLOR_YELLOW=''
    COLOR_RED=''
    COLOR_MAGENTA=''
    COLOR_GRAY=''
  fi
}

setup_colors

if [[ -w /dev/tty ]]; then
  UI_OUT=/dev/tty
else
  UI_OUT=/dev/stdout
fi

default_log_root() {
  if [[ -n "${XDG_STATE_HOME:-}" ]]; then
    printf '%s/linksoft-agent-installer/logs' "$XDG_STATE_HOME"
  elif [[ -n "${HOME:-}" ]]; then
    printf '%s/.local/state/linksoft-agent-installer/logs' "$HOME"
  else
    printf '%s' "${SCRIPT_DIR:-.}"
  fi
}

default_log_file_path() {
  local root
  root="$(default_log_root)"
  printf '%s/setup-agentic-tools-%s.log' "$root" "$(date -u '+%Y%m%dT%H%M%SZ')"
}

print_log_hint() {
  [[ -n "${LOG_FILE:-}" ]] || return 0
  printf '%sSee log:%s %s\n' "$COLOR_DIM" "$COLOR_RESET" "$LOG_FILE" >&2
}

report_unhandled_error() {
  local exit_code="$1"
  local line_no="$2"
  local command_text="$3"
  append_log "ERROR unexpected exit code ${exit_code} at line ${line_no}: ${command_text}"
  printf '%sERROR%s Installer aborted at line %s while running: %s\n' "$COLOR_RED" "$COLOR_RESET" "$line_no" "$command_text" >&2
  print_log_hint
}

enable_error_reporting() {
  trap 'exit_code=$?; report_unhandled_error "$exit_code" "${BASH_LINENO[0]:-${LINENO}}" "${BASH_COMMAND:-unknown}"' ERR
}

strip_ansi_text() {
  python3 -c 'import re, sys; text = sys.stdin.read(); text = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text); text = text.replace("\r", ""); sys.stdout.write(text)'
}

append_log() {
  [[ -n "${LOG_FILE:-}" ]] || return 0
  local text="$1"
  local cleaned
  cleaned="$(printf '%s\n' "$text" | strip_ansi_text)"
  printf '%s\n' "$cleaned" >> "$LOG_FILE"
}

section_divider() {
  printf '%s%s─────────────────────────────%s\n' "$COLOR_DIM" "$COLOR_GRAY" "$COLOR_RESET"
}

format_label() {
  printf '%s%s%s' "$COLOR_BOLD" "$1" "$COLOR_RESET"
}

format_value() {
  printf '%s%s%s' "$COLOR_CYAN" "$1" "$COLOR_RESET"
}

log() {
  printf '\n%s%s◆%s %s%s%s\n' "$COLOR_BOLD" "$COLOR_BLUE" "$COLOR_RESET" "$COLOR_BOLD" "$1" "$COLOR_RESET"
  append_log "\n◆ $1"
}

phase() {
  local current="$1"
  local total="$2"
  local message="$3"
  printf '\n%s[%s/%s]%s %s%s%s\n' \
    "$COLOR_MAGENTA" "$current" "$total" "$COLOR_RESET" \
    "$COLOR_BOLD" "$message" "$COLOR_RESET"
  append_log "[$current/$total] $message"
}

warn() {
  printf '%sWARN%s %s\n' "$COLOR_YELLOW" "$COLOR_RESET" "$1" >&2
  append_log "WARN $1"
}

die() {
  printf '%sERROR%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$1" >&2
  append_log "ERROR $1"
  exit 1
}

note() {
  printf '%s\n' "$1"
  append_log "$1"
}

draw_spinner_until_done() {
  local pid="$1"
  local message="$2"
  local frames=("◰" "◳" "◲" "◱")
  local i=0
  local start_ts elapsed

  start_ts="$(date +%s)"

  printf '  %s%s%s %s (0s)' "$COLOR_MAGENTA" "${frames[0]}" "$COLOR_RESET" "$message" > "$UI_OUT"
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % ${#frames[@]} ))
    elapsed=$(( $(date +%s) - start_ts ))
    printf '\r  %s%s%s %s (%ss)' "$COLOR_MAGENTA" "${frames[$i]}" "$COLOR_RESET" "$message" "$elapsed" > "$UI_OUT"
    sleep 0.12
  done
}

finish_spinner() {
  local exit_code="$1"
  local message="$2"
  local elapsed="${3:-}"
  if [[ "$exit_code" -eq 0 ]]; then
    printf '\r  %s✓%s %s%s\n' "$COLOR_GREEN" "$COLOR_RESET" "$message" "${elapsed:+ (${elapsed}s)}" > "$UI_OUT"
  else
    printf '\r  %s✗%s %s%s\n' "$COLOR_RED" "$COLOR_RESET" "$message" "${elapsed:+ (${elapsed}s)}" > "$UI_OUT"
  fi
}

debug() {
  if (( VERBOSE )); then
    printf '%s\n' "$1"
    append_log "$1"
  fi
}

debug_section() {
  if (( VERBOSE )); then
    printf '\n==> %s\n' "$1"
    append_log "\n==> $1"
  fi
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

trim() {
  local s="$1"
  s="${s#${s%%[![:space:]]*}}"
  s="${s%${s##*[![:space:]]}}"
  printf '%s' "$s"
}

contains() {
  local needle="$1"
  shift || true
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

append_unique() {
  local value="$1"
  shift
  local -n target_ref=$1
  if ! contains "$value" "${target_ref[@]+${target_ref[@]}}"; then
    target_ref+=("$value")
  fi
}

join_by() {
  local sep="$1"
  shift || true
  local first=1
  local item
  for item in "$@"; do
    if (( first )); then
      printf '%s' "$item"
      first=0
    else
      printf '%s%s' "$sep" "$item"
    fi
  done
}

prompt_csv() {
  local prompt="$1"
  local default_value="${2:-}"
  local answer
  if [[ -n "$default_value" ]]; then
    read -r -p "$prompt [$default_value]: " answer </dev/tty
    answer="${answer:-$default_value}"
  else
    read -r -p "$prompt: " answer </dev/tty
  fi
  printf '%s' "$answer"
}

parse_csv_into_array() {
  local csv="$1"
  local -n out_ref=$2
  out_ref=()
  local raw part
  IFS=',' read -r -a raw <<< "$csv"
  for part in "${raw[@]}"; do
    part="$(trim "$part")"
    [[ -z "$part" ]] && continue
    out_ref+=("$part")
  done
}

ensure_log_file() {
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE="$DEFAULT_LOG_FILE"
  fi

  mkdir -p "$(dirname "$LOG_FILE")"
  if [[ -f "$LOG_FILE" ]]; then
    warn "Overwriting existing log file: $LOG_FILE"
  fi
  printf '=== setup-agentic-tools session started %s ===\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" > "$LOG_FILE"
  note "$(format_label "Log file:") $(format_value "$LOG_FILE")"
}

cleanup_spinner_line() {
  printf '\n' > "$UI_OUT"
}

cleanup_run_cmd() {
  local tmp_file="$1"
  local cmd_pid="${2:-}"
  cleanup_spinner_line
  if [[ -n "$cmd_pid" ]]; then
    kill "$cmd_pid" 2>/dev/null || true
  fi
  rm -f "$tmp_file"
}

command_message() {
  local -a cmd=("$@")
  local i token
  for ((i = 0; i < ${#cmd[@]}; i++)); do
    token="${cmd[$i]}"
    case "$token" in
      npx)
        for ((i += 1; i < ${#cmd[@]}; i++)); do
          token="${cmd[$i]}"
          [[ "$token" == -* ]] && continue
          if [[ "$token" == "skills" ]]; then
            printf 'Installing skill via npx'
            return 0
          fi
          break
        done
        printf 'Running npx command'
        return 0
        ;;
      opencode)
        printf 'Checking OpenCode MCP configuration'
        return 0
        ;;
      claude)
        printf 'Checking Claude MCP configuration'
        return 0
        ;;
    esac
  done
  printf 'Working...'
}

run_cmd() {
  local -a cmd=("$@")
  if (( DRY_RUN )); then
    if (( VERBOSE )); then
      printf '\n$ '
      printf '%q ' "${cmd[@]}"
      printf '\n'
    fi
    note "[dry-run] command not executed"
    append_log "DRY-RUN: $(printf '%q ' "${cmd[@]}")"
    return 0
  fi
  if (( VERBOSE )); then
    printf '\n$ '
    printf '%q ' "${cmd[@]}"
    printf '\n'
    if "${cmd[@]}"; then
      note "[ok] command succeeded"
      return 0
    fi
    local exit_code=$?
    warn "[fail] command exited with code $exit_code"
    return "$exit_code"
  fi

  local tmp_file
  tmp_file="$(mktemp)"
  local message
  message="$(command_message "${cmd[@]}")"
  local cmd_pid=""
  local start_ts elapsed
  start_ts="$(date +%s)"

  trap 'cleanup_run_cmd "$tmp_file" "$cmd_pid"; trap - INT TERM; exit 130' INT TERM

  append_log "RUN: $(printf '%q ' "${cmd[@]}")"
  "${cmd[@]}" >"$tmp_file" 2>&1 &
  cmd_pid=$!
  draw_spinner_until_done "$cmd_pid" "$message"
   local exit_code
   if wait "$cmd_pid"; then
     exit_code=0
   else
     exit_code=$?
   fi
   elapsed=$(( $(date +%s) - start_ts ))
   finish_spinner "$exit_code" "$message" "$elapsed"
   trap - INT TERM

  if [[ "$exit_code" -eq 0 ]]; then
    append_log "OK: $(printf '%q ' "${cmd[@]}")"
    rm -f "$tmp_file"
    return 0
  fi
  append_log "FAIL($exit_code): $(printf '%q ' "${cmd[@]}")"
  append_log "$(cat "$tmp_file")"
  printf '\n$ '
  printf '%q ' "${cmd[@]}"
  printf '\n'
  cat "$tmp_file"
  rm -f "$tmp_file"
  warn "[fail] command exited with code $exit_code"
  print_log_hint
  return "$exit_code"
}

capture_cmd() {
  local -a cmd=("$@")
  if (( DRY_RUN )); then
    if (( VERBOSE )); then
      printf '\n$ '
      printf '%q ' "${cmd[@]}"
      printf '\n'
      note "[dry-run] command not executed"
    fi
    append_log "DRY-RUN: $(printf '%q ' "${cmd[@]}")"
    printf '[dry-run output]\n'
    return 0
  fi
  local output
  append_log "RUN: $(printf '%q ' "${cmd[@]}")"
  if (( VERBOSE )); then
    printf '\n$ '
    printf '%q ' "${cmd[@]}"
    printf '\n'
  fi
  if output="$("${cmd[@]}" 2>&1)"; then
    printf '%s\n' "$output"
    if (( VERBOSE )); then
      note "[ok] command succeeded"
    fi
    append_log "OK: $(printf '%q ' "${cmd[@]}")"
    return 0
  fi
  local exit_code=$?
  printf '%s\n' "$output"
  append_log "FAIL($exit_code): $(printf '%q ' "${cmd[@]}")"
  append_log "$output"
  warn "[fail] command exited with code $exit_code"
  return "$exit_code"
}

report_check() {
  local status="$1"
  local label="$2"
  local details="$3"
  local status_color="$COLOR_GRAY"
  local status_icon="•"
  case "$status" in
    PASS)
      status_color="$COLOR_GREEN"
      status_icon="✓"
      ;;
    FAIL)
      status_color="$COLOR_RED"
      status_icon="✗"
      ;;
    SKIP)
      status_color="$COLOR_YELLOW"
      status_icon="↷"
      ;;
  esac
  printf '%s[%s %s]%s %s%s%s %s%s%s\n' \
    "$status_color" "$status_icon" "$status" "$COLOR_RESET" \
    "$COLOR_BOLD" "$label" "$COLOR_RESET" \
    "$COLOR_DIM" "$details" "$COLOR_RESET"
  append_log "[$status] $label - $details"
}
