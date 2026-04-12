#!/usr/bin/env bash

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

strip_ansi_text() {
  python3 -c 'import re, sys; text = sys.stdin.read(); text = re.sub(r"\x1b\[[0-9;?]*[ -/]*[@-~]", "", text); text = text.replace("\r", ""); sys.stdout.write(text)' 2>/dev/null
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

  printf '  %s%s%s %s' "$COLOR_MAGENTA" "${frames[0]}" "$COLOR_RESET" "$message" > "$UI_OUT"
  while kill -0 "$pid" 2>/dev/null; do
    i=$(( (i + 1) % ${#frames[@]} ))
    printf '\r  %s%s%s %s' "$COLOR_MAGENTA" "${frames[$i]}" "$COLOR_RESET" "$message" > "$UI_OUT"
    sleep 0.12
  done
}

finish_spinner() {
  local exit_code="$1"
  local message="$2"
  if [[ "$exit_code" -eq 0 ]]; then
    printf '\r  %s✓%s %s\n' "$COLOR_GREEN" "$COLOR_RESET" "$message" > "$UI_OUT"
  else
    printf '\r  %s✗%s %s\n' "$COLOR_RED" "$COLOR_RESET" "$message" > "$UI_OUT"
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
  if ! contains "$value" "${target_ref[@]}"; then
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
    read -r -p "$prompt [$default_value]: " answer
    answer="${answer:-$default_value}"
  else
    read -r -p "$prompt: " answer
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
  : > "$LOG_FILE"
  note "$(format_label "Log file:") $(format_value "$LOG_FILE")"
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
  local message="Working..."
  if [[ ${#cmd[@]} -gt 0 ]]; then
    message="${cmd[0]}"
    if [[ ${#cmd[@]} -gt 1 ]]; then
      message+=" ${cmd[1]}"
    fi
  fi

  append_log "RUN: $(printf '%q ' "${cmd[@]}")"
  "${cmd[@]}" >"$tmp_file" 2>&1 &
  local cmd_pid=$!
  draw_spinner_until_done "$cmd_pid" "$message"
  wait "$cmd_pid"
  local exit_code=$?
  finish_spinner "$exit_code" "$message"

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
