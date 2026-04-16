#!/usr/bin/env bash
# Expects caller to enable strict mode (set -euo pipefail).

ensure_install_globals() {
  : "${SKILL_SOURCE:?SKILL_SOURCE must be set}"
  : "${CONTEXT7_SERVER_NAME:?CONTEXT7_SERVER_NAME must be set}"
  : "${CONTEXT7_URL:?CONTEXT7_URL must be set}"
}

ensure_prereqs() {
  if (( SKIP_SKILLS == 0 )); then
    has_cmd npx || die "npx is required"
  fi
  if (( SKIP_MCP == 0 )); then
    has_cmd mcpm || die "mcpm is required. Install it first, then rerun this script."
  fi
  has_cmd python3 || die "python3 is required"
}

ensure_openspec() {
  if has_cmd openspec; then
    note "$(format_label "OpenSpec:") $(format_value "installed at $(command -v openspec)")"
    return 0
  fi

  warn "openspec is not installed"

  if (( NON_INTERACTIVE )); then
    warn "Non-interactive mode cannot prompt to install openspec. Install it manually with: npm install -g openspec"
    return 0
  fi

  if ! has_cmd npm; then
    warn "npm is not available, so openspec cannot be installed automatically. Install npm first, then run: npm install -g openspec"
    return 0
  fi

  local install_openspec
  read -r -p "openspec is missing. Install it globally with npm now? [y/N]: " install_openspec </dev/tty
  case "$install_openspec" in
    y|Y|yes|YES)
      log "Installing openspec globally"
      run_cmd npm install -g openspec
      ;;
    *)
      note "Skipping openspec installation"
      ;;
  esac
}

install_skill() {
  ensure_install_globals
  local -a selected_tools=("$@")
  local -a skill_agents=()
  collect_skill_agents skill_agents "${selected_tools[@]}"

  if ((${#skill_agents[@]} == 0)); then
    warn "No valid skills.sh targets selected; skipping skill installation"
    return 0
  fi

  ensure_openspec

  local -a cmd=(npx -y skills add "$SKILL_SOURCE" -g -y)
  (( COPY_SKILLS )) && cmd+=(--copy)

  local agent
  for agent in "${skill_agents[@]}"; do
    cmd+=(-a "$agent")
  done

  log "Installing LinkSoft test skill"
  debug "skills.sh targets: $(join_by ', ' "${skill_agents[@]}")"
  run_cmd "${cmd[@]}"
}

install_context7_server() {
  ensure_install_globals
  local api_key="$1"

  log "Installing Context7 in MCPM"

  if (( DRY_RUN )); then
    note "Would ensure MCPM server '$CONTEXT7_SERVER_NAME' exists"
  elif mcpm ls 2>/dev/null | grep -Eq "^[[:space:]]*${CONTEXT7_SERVER_NAME}([[:space:]].*)?$"; then
    note "Context7 already exists in MCPM"
  elif ! run_cmd mcpm install "$CONTEXT7_SERVER_NAME" --force; then
    warn "mcpm registry install failed; falling back to manual MCPM server definition"
    run_cmd mcpm new "$CONTEXT7_SERVER_NAME" --type remote --url "$CONTEXT7_URL" --force
  fi

  if [[ -n "$api_key" ]]; then
    run_cmd mcpm edit "$CONTEXT7_SERVER_NAME" --url "$CONTEXT7_URL" --headers "CONTEXT7_API_KEY=$api_key" --force
  fi
}

configure_opencode() {
  ensure_install_globals
  log "Configuring OpenCode to use MCPM-managed Context7"
  if (( DRY_RUN )); then
    note "Would update ~/.config/opencode/opencode.json"
    return 0
  fi

  local mcpm_bin
  mcpm_bin="$(command -v mcpm)"

  MCPM_BIN="$mcpm_bin" python3 - <<'PY' || die "Failed to configure OpenCode"
import json
import os
import shutil
import time


def strip_jsonc(text: str) -> str:
    result = []
    in_string = False
    string_char = ""
    escaped = False
    in_line_comment = False
    in_block_comment = False
    i = 0

    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                result.append(ch)
            i += 1
            continue

        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue

        if in_string:
            result.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == string_char:
                in_string = False
            i += 1
            continue

        if ch in ('"', "'"):
            in_string = True
            string_char = ch
            result.append(ch)
            i += 1
            continue

        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue

        result.append(ch)
        i += 1

    cleaned = "".join(result)
    compact = []
    in_string = False
    string_char = ""
    escaped = False
    i = 0
    while i < len(cleaned):
        ch = cleaned[i]
        if in_string:
            compact.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == string_char:
                in_string = False
            i += 1
            continue
        if ch in ('"', "'"):
            in_string = True
            string_char = ch
            compact.append(ch)
            i += 1
            continue
        if ch == ",":
            j = i + 1
            while j < len(cleaned) and cleaned[j] in " \t\r\n":
                j += 1
            if j < len(cleaned) and cleaned[j] in "]}":
                i += 1
                continue
        compact.append(ch)
        i += 1
    return "".join(compact)


path = os.path.expanduser("~/.config/opencode/opencode.json")
os.makedirs(os.path.dirname(path), exist_ok=True)

data = {}
if os.path.exists(path):
    with open(path, "r", encoding="utf-8") as f:
        raw = f.read()
    shutil.copy2(path, f"{path}.bak.{int(time.time())}")
    stripped = strip_jsonc(raw).strip()
    if stripped:
        data = json.loads(stripped)

data.setdefault("$schema", "https://opencode.ai/config.json")
data.setdefault("mcp", {})
data["mcp"]["context7"] = {
    "type": "local",
    "command": [os.environ["MCPM_BIN"], "run", "context7"],
    "enabled": True,
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

configure_vscode() {
  ensure_install_globals
  log "Configuring VS Code MCP file"
  if (( DRY_RUN )); then
    note "Would update ~/.config/Code/User/mcp.json"
    return 0
  fi

  local mcpm_bin
  mcpm_bin="$(command -v mcpm)"

  MCPM_BIN="$mcpm_bin" python3 - <<'PY' || die "Failed to configure VS Code"
import json
import os
import shutil
import time


def strip_jsonc(text: str) -> str:
    result = []
    in_string = False
    string_char = ""
    escaped = False
    in_line_comment = False
    in_block_comment = False
    i = 0

    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                result.append(ch)
            i += 1
            continue

        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue

        if in_string:
            result.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == string_char:
                in_string = False
            i += 1
            continue

        if ch in ('"', "'"):
            in_string = True
            string_char = ch
            result.append(ch)
            i += 1
            continue

        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue

        result.append(ch)
        i += 1

    cleaned = "".join(result)
    compact = []
    in_string = False
    string_char = ""
    escaped = False
    i = 0
    while i < len(cleaned):
        ch = cleaned[i]
        if in_string:
            compact.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == string_char:
                in_string = False
            i += 1
            continue
        if ch in ('"', "'"):
            in_string = True
            string_char = ch
            compact.append(ch)
            i += 1
            continue
        if ch == ",":
            j = i + 1
            while j < len(cleaned) and cleaned[j] in " \t\r\n":
                j += 1
            if j < len(cleaned) and cleaned[j] in "]}":
                i += 1
                continue
        compact.append(ch)
        i += 1
    return "".join(compact)

path = os.path.expanduser("~/.config/Code/User/mcp.json")
os.makedirs(os.path.dirname(path), exist_ok=True)

data = {}
if os.path.exists(path):
    shutil.copy2(path, f"{path}.bak.{int(time.time())}")
    with open(path, "r", encoding="utf-8") as f:
        raw = strip_jsonc(f.read()).strip()
    if raw:
        data = json.loads(raw)

data.setdefault("servers", {})
data.setdefault("inputs", [])
data["servers"]["mcpm_context7"] = {
    "type": "stdio",
    "command": os.environ["MCPM_BIN"],
    "args": ["run", "context7"],
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

configure_github_copilot_cli() {
  ensure_install_globals
  log "Configuring GitHub Copilot CLI MCP file"
  if (( DRY_RUN )); then
    note "Would update ~/.copilot/mcp-config.json"
    return 0
  fi

  local mcpm_bin
  mcpm_bin="$(command -v mcpm)"

  MCPM_BIN="$mcpm_bin" python3 - <<'PY' || die "Failed to configure GitHub Copilot CLI"
import json
import os
import shutil
import time


def strip_jsonc(text: str) -> str:
    result = []
    in_string = False
    string_char = ""
    escaped = False
    in_line_comment = False
    in_block_comment = False
    i = 0

    while i < len(text):
        ch = text[i]
        nxt = text[i + 1] if i + 1 < len(text) else ""

        if in_line_comment:
            if ch == "\n":
                in_line_comment = False
                result.append(ch)
            i += 1
            continue

        if in_block_comment:
            if ch == "*" and nxt == "/":
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue

        if in_string:
            result.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == string_char:
                in_string = False
            i += 1
            continue

        if ch in ('"', "'"):
            in_string = True
            string_char = ch
            result.append(ch)
            i += 1
            continue

        if ch == "/" and nxt == "/":
            in_line_comment = True
            i += 2
            continue

        if ch == "/" and nxt == "*":
            in_block_comment = True
            i += 2
            continue

        result.append(ch)
        i += 1

    cleaned = "".join(result)
    compact = []
    in_string = False
    string_char = ""
    escaped = False
    i = 0
    while i < len(cleaned):
        ch = cleaned[i]
        if in_string:
            compact.append(ch)
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == string_char:
                in_string = False
            i += 1
            continue
        if ch in ('"', "'"):
            in_string = True
            string_char = ch
            compact.append(ch)
            i += 1
            continue
        if ch == ",":
            j = i + 1
            while j < len(cleaned) and cleaned[j] in " \t\r\n":
                j += 1
            if j < len(cleaned) and cleaned[j] in "]}":
                i += 1
                continue
        compact.append(ch)
        i += 1
    return "".join(compact)

copilot_home = os.environ.get("COPILOT_HOME", os.path.expanduser("~/.copilot"))
path = os.path.join(copilot_home, "mcp-config.json")
os.makedirs(os.path.dirname(path), exist_ok=True)

data = {}
if os.path.exists(path):
    shutil.copy2(path, f"{path}.bak.{int(time.time())}")
    with open(path, "r", encoding="utf-8") as f:
        raw = strip_jsonc(f.read()).strip()
    if raw:
        data = json.loads(raw)

legacy_servers = data.pop("servers", None)
data.setdefault("mcpServers", {})
if isinstance(legacy_servers, dict):
    for key, value in legacy_servers.items():
        data["mcpServers"].setdefault(key, value)

data["mcpServers"]["mcpm_context7"] = {
    "type": "local",
    "command": os.environ["MCPM_BIN"],
    "args": ["run", "context7"],
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

wire_context7_to_tool() {
  ensure_install_globals
  local tool="$1"
  local client_name

  case "$tool" in
    opencode)
      configure_opencode
      ;;
    vscode)
      configure_vscode
      ;;
    github-copilot-cli)
      configure_github_copilot_cli
      ;;
    github-copilot)
      warn "No standalone GitHub Copilot MCP file is configured here; use the 'vscode' target for Copilot-in-VS-Code MCP wiring"
      ;;
    *)
      if client_name="$(mcpm_client_name "$tool" 2>/dev/null)"; then
        log "Adding Context7 to $tool via MCPM client '$client_name'"
        if ! run_cmd mcpm client edit "$client_name" --add-server "$CONTEXT7_SERVER_NAME" --force; then
          warn "Failed to wire Context7 into MCPM client '$client_name' for tool '$tool'"
        fi
      else
        warn "No MCP wiring strategy is defined for $tool"
      fi
      ;;
  esac
}

wire_context7_to_tools() {
  local tool
  for tool in "$@"; do
    wire_context7_to_tool "$tool"
  done
}
