#!/usr/bin/env bash

set -euo pipefail

REPO_OWNER="Linksofteu"
REPO_NAME="LinkSoft_AgentInstaller"
REPO_REF="main"
ARCHIVE_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_REF}.tar.gz"

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
  require_cmd bash
  require_cmd curl
  require_cmd tar
  require_cmd mktemp

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT

  printf 'Downloading %s/%s (%s)...\n' "$REPO_OWNER" "$REPO_NAME" "$REPO_REF"
  curl -fsSL "$ARCHIVE_URL" | tar -xzf - -C "$TMP_DIR"

  local extracted_dir="$TMP_DIR/${REPO_NAME}-${REPO_REF}"
  local entrypoint="$extracted_dir/setup-agentic-tools.sh"

  if [[ ! -f "$entrypoint" ]]; then
    printf 'Error: expected entrypoint not found: %s\n' "$entrypoint" >&2
    exit 1
  fi

  exec bash "$entrypoint" "$@"
}

main "$@"
