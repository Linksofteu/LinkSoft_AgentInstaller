#!/usr/bin/env bash
# Expects caller to enable strict mode (set -euo pipefail).

ensure_install_globals() {
  : "${CONTEXT7_SERVER_NAME:?CONTEXT7_SERVER_NAME must be set}"
  : "${CONTEXT7_URL:?CONTEXT7_URL must be set}"
  : "${FIGMA_SERVER_NAME:?FIGMA_SERVER_NAME must be set}"
  : "${FIGMA_URL:?FIGMA_URL must be set}"
  : "${FIGMA_REGISTER_URL:?FIGMA_REGISTER_URL must be set}"
  : "${FIGMA_OPENCODE_REDIRECT_URI:?FIGMA_OPENCODE_REDIRECT_URI must be set}"
  : "${FIGMA_CLAUDE_CODE_REDIRECT_URI:?FIGMA_CLAUDE_CODE_REDIRECT_URI must be set}"
  : "${BROWSER_MCP_SERVER_NAME:?BROWSER_MCP_SERVER_NAME must be set}"
  : "${BROWSER_MCP_PACKAGE:?BROWSER_MCP_PACKAGE must be set}"
  ((${#SKILL_SOURCES[@]} > 0)) || die "SKILL_SOURCES must not be empty"
  ((${#SKILL_NAMES[@]} > 0)) || die "SKILL_NAMES must not be empty"
  ((${#SKILL_SOURCES[@]} == ${#SKILL_NAMES[@]})) || die "SKILL_SOURCES and SKILL_NAMES must stay in sync"
}

ensure_prereqs() {
  if (( SKIP_SKILLS == 0 )); then
    has_cmd npx || die "npx is required"
  fi
  has_cmd python3 || die "python3 is required"
}

print_npm_user_prefix_guidance() {
  note "To avoid sudo for global npm packages, configure npm to use a user-owned directory:"
  note "  mkdir -p \"$HOME/.npm-global\""
  note "  npm config set prefix \"$HOME/.npm-global\""
  note "  export PATH=\"$HOME/.npm-global/bin:\$PATH\""
  note "Then add that export line to your shell profile (for example ~/.bashrc), reload your shell, and rerun this installer."
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
      if ! run_cmd npm install -g openspec; then
        warn "Automatic openspec installation failed. This is commonly caused by npm global install permissions."
        print_npm_user_prefix_guidance
        die "Unable to install openspec automatically"
      fi
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

  local i skill_source skill_name agent
  for i in "${!SKILL_SOURCES[@]}"; do
    skill_source="${SKILL_SOURCES[$i]}"
    skill_name="${SKILL_NAMES[$i]}"

    local -a cmd=(npx -y skills add "$skill_source" -g -y)
    (( COPY_SKILLS )) && cmd+=(--copy)

    for agent in "${skill_agents[@]}"; do
      cmd+=(-a "$agent")
    done

    log "Installing LinkSoft skill: $skill_name"
    debug "skills.sh targets: $(join_by ', ' "${skill_agents[@]}")"
    run_cmd "${cmd[@]}"
  done
}

install_context7_server() {
  ensure_install_globals
  local api_key="$1"

  log "Preparing direct Context7 MCP configuration"

  if (( DRY_RUN )); then
    note "Would configure supported tools with a direct remote MCP entry for '$CONTEXT7_SERVER_NAME'"
    if [[ -n "$api_key" ]]; then
      note "Would include a Context7 API key header in supported tool configurations"
    fi
    return 0
  fi

  note "No standalone MCP manager is used; supported tools are configured directly"
}

install_figma_server() {
  ensure_install_globals

  log "Preparing direct Figma MCP configuration"

  if (( DRY_RUN )); then
    note "Would configure supported tools with a direct remote MCP entry for '$FIGMA_SERVER_NAME'"
    note "Would use each tool's native OAuth/browser flow when available"
    return 0
  fi

  note "Figma MCP is only wired for tools with a documented native OAuth/browser flow"
}

install_browser_server() {
  ensure_install_globals

  log "Preparing Browser MCP configuration"

  if (( DRY_RUN )); then
    note "Would configure supported tools with a local Browser MCP server entry for '$BROWSER_MCP_SERVER_NAME'"
    return 0
  fi

  note "Browser MCP server entries are wired directly for supported tools; the browser extension still must be installed manually"
}

write_context7_json_config() {
  local path="$1"
  local mode="$2"
  local api_key="${3:-}"

  TARGET_PATH="$path" CONFIG_MODE="$mode" CONTEXT7_API_KEY="$api_key" CONTEXT7_SERVER_NAME="$CONTEXT7_SERVER_NAME" CONTEXT7_URL="$CONTEXT7_URL" python3 - <<'PY'
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


def load_jsonc(path: str):
    data = {}
    if os.path.exists(path):
        shutil.copy2(path, f"{path}.bak.{time.time_ns()}")
        with open(path, "r", encoding="utf-8") as f:
            raw = strip_jsonc(f.read()).strip()
        if raw:
            data = json.loads(raw)
    return data


def clean_none(value):
    if isinstance(value, dict):
        return {k: clean_none(v) for k, v in value.items() if v is not None}
    if isinstance(value, list):
        return [clean_none(v) for v in value]
    return value


path = os.path.expanduser(os.environ["TARGET_PATH"])
mode = os.environ["CONFIG_MODE"]
server_name = os.environ["CONTEXT7_SERVER_NAME"]
url = os.environ["CONTEXT7_URL"]
api_key = os.environ.get("CONTEXT7_API_KEY", "")
headers = {"CONTEXT7_API_KEY": api_key} if api_key else None

parent = os.path.dirname(path)
if parent:
    os.makedirs(parent, exist_ok=True)
data = load_jsonc(path)

if mode == "opencode":
    data.setdefault("$schema", "https://opencode.ai/config.json")
    data.setdefault("mcp", {})
    data["mcp"][server_name] = clean_none(
        {
            "type": "remote",
            "url": url,
            "headers": headers,
            "enabled": True,
        }
    )
elif mode == "vscode":
    data.setdefault("servers", {})
    data.setdefault("inputs", [])
    data["servers"][server_name] = clean_none(
        {
            "type": "http",
            "url": url,
            "headers": headers,
        }
    )
elif mode == "copilot-cli":
    legacy_servers = data.pop("servers", None)
    data.setdefault("mcpServers", {})
    if isinstance(legacy_servers, dict):
        for key, value in legacy_servers.items():
            data["mcpServers"].setdefault(key, value)
    data["mcpServers"][server_name] = clean_none(
        {
            "type": "http",
            "url": url,
            "headers": headers,
            "tools": ["*"],
        }
    )
elif mode == "claude-code":
    data.setdefault("mcpServers", {})
    data["mcpServers"][server_name] = clean_none(
        {
            "type": "http",
            "url": url,
            "headers": headers,
        }
    )
elif mode == "cline":
    data.setdefault("mcpServers", {})
    data["mcpServers"][server_name] = clean_none(
        {
            "url": url,
            "headers": headers,
            "disabled": False,
        }
    )
elif mode == "continue":
    data = {
        "mcpServers": {
            server_name: clean_none(
                {
                    "type": "http",
                    "url": url,
                    "headers": headers,
                }
            )
        }
    }
elif mode == "gemini":
    data.setdefault("mcpServers", {})
    data["mcpServers"][server_name] = clean_none(
        {
            "httpUrl": url,
            "headers": headers,
            "timeout": 600000,
        }
    )
else:
    raise SystemExit(f"Unsupported config mode: {mode}")

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

write_figma_opencode_json_config() {
  local path="$1"
  local client_id="$2"
  local client_secret="$3"

  TARGET_PATH="$path" FIGMA_SERVER_NAME="$FIGMA_SERVER_NAME" FIGMA_URL="$FIGMA_URL" FIGMA_CLIENT_ID="$client_id" FIGMA_CLIENT_SECRET="$client_secret" python3 - <<'PY'
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


path = os.path.expanduser(os.environ["TARGET_PATH"])
server_name = os.environ["FIGMA_SERVER_NAME"]
url = os.environ["FIGMA_URL"]
client_id = os.environ["FIGMA_CLIENT_ID"]
client_secret = os.environ["FIGMA_CLIENT_SECRET"]

parent = os.path.dirname(path)
if parent:
    os.makedirs(parent, exist_ok=True)

data = {}
if os.path.exists(path):
    shutil.copy2(path, f"{path}.bak.{time.time_ns()}")
    with open(path, "r", encoding="utf-8") as f:
        raw = strip_jsonc(f.read()).strip()
    if raw:
        data = json.loads(raw)

data.setdefault("$schema", "https://opencode.ai/config.json")
data.setdefault("mcp", {})
data["mcp"][server_name] = {
    "enabled": True,
    "type": "remote",
    "url": url,
    "oauth": {
        "clientId": client_id,
        "clientSecret": client_secret,
    },
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

write_browser_opencode_json_config() {
  local path="$1"

  TARGET_PATH="$path" BROWSER_MCP_SERVER_NAME="$BROWSER_MCP_SERVER_NAME" BROWSER_MCP_PACKAGE="$BROWSER_MCP_PACKAGE" python3 - <<'PY'
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


path = os.path.expanduser(os.environ["TARGET_PATH"])
server_name = os.environ["BROWSER_MCP_SERVER_NAME"]
package = os.environ["BROWSER_MCP_PACKAGE"]

parent = os.path.dirname(path)
if parent:
    os.makedirs(parent, exist_ok=True)

data = {}
if os.path.exists(path):
    shutil.copy2(path, f"{path}.bak.{time.time_ns()}")
    with open(path, "r", encoding="utf-8") as f:
        raw = strip_jsonc(f.read()).strip()
    if raw:
        data = json.loads(raw)

data.setdefault("$schema", "https://opencode.ai/config.json")
data.setdefault("mcp", {})
data["mcp"][server_name] = {
    "enabled": True,
    "type": "local",
    "command": ["npx", "-y", package],
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

write_browser_claude_code_json_config() {
  local path="$1"

  TARGET_PATH="$path" BROWSER_MCP_SERVER_NAME="$BROWSER_MCP_SERVER_NAME" BROWSER_MCP_PACKAGE="$BROWSER_MCP_PACKAGE" python3 - <<'PY'
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


path = os.path.expanduser(os.environ["TARGET_PATH"])
server_name = os.environ["BROWSER_MCP_SERVER_NAME"]
package = os.environ["BROWSER_MCP_PACKAGE"]

parent = os.path.dirname(path)
if parent:
    os.makedirs(parent, exist_ok=True)

data = {}
if os.path.exists(path):
    shutil.copy2(path, f"{path}.bak.{time.time_ns()}")
    with open(path, "r", encoding="utf-8") as f:
        raw = strip_jsonc(f.read()).strip()
    if raw:
        data = json.loads(raw)

data.setdefault("mcpServers", {})
data["mcpServers"][server_name] = {
    "command": "npx",
    "args": ["-y", package],
}

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

register_figma_opencode_oauth_client() {
  ensure_install_globals

  local response client_id client_secret

  response="$(capture_cmd curl -sS -X POST "$FIGMA_REGISTER_URL" -H "Content-Type: application/json" -d '{
      "client_name": "Claude Code (figma)",
      "redirect_uris": ["http://127.0.0.1:19876/mcp/oauth/callback"],
      "grant_types": ["authorization_code", "refresh_token"],
      "response_types": ["code"],
      "token_endpoint_auth_method": "none"
    }')" || die "Failed to register Figma OAuth client for OpenCode"

  client_id="$(RESPONSE_JSON="$response" python3 - <<'PY'
import json
import os

raw = os.environ.get("RESPONSE_JSON", "")
try:
    data = json.loads(raw)
except Exception:
    print("")
else:
    print(data.get("client_id", ""))
PY
)"
  client_secret="$(RESPONSE_JSON="$response" python3 - <<'PY'
import json
import os

raw = os.environ.get("RESPONSE_JSON", "")
try:
    data = json.loads(raw)
except Exception:
    print("")
else:
    print(data.get("client_secret", ""))
PY
)"

  [[ -n "$client_id" ]] || die "Figma OAuth registration response did not include client_id. Raw response: $response"
  [[ -n "$client_secret" ]] || die "Figma OAuth registration response did not include client_secret. Raw response: $response"

  FIGMA_CLIENT_ID_INPUT="$client_id"
  FIGMA_CLIENT_SECRET_INPUT="$client_secret"

  note "Registered a Figma OAuth client for OpenCode using callback $FIGMA_OPENCODE_REDIRECT_URI"
}

ensure_figma_opencode_credentials() {
  ensure_install_globals
  if [[ -n "${FIGMA_CLIENT_ID_INPUT:-}" && -n "${FIGMA_CLIENT_SECRET_INPUT:-}" ]]; then
    return 0
  fi

  if ! has_cmd curl; then
    die "curl is required to register the Figma OAuth client for OpenCode"
  fi

  register_figma_opencode_oauth_client
}

register_figma_claude_code_oauth_client() {
  ensure_install_globals

  local response client_id client_secret

  response="$(capture_cmd curl -sS -X POST "$FIGMA_REGISTER_URL" -H "Content-Type: application/json" -d '{
      "client_name": "Claude Code (figma)",
      "redirect_uris": ["http://localhost:19876/callback"],
      "grant_types": ["authorization_code", "refresh_token"],
      "response_types": ["code"],
      "token_endpoint_auth_method": "none"
    }')" || die "Failed to register Figma OAuth client for Claude Code"

  client_id="$(RESPONSE_JSON="$response" python3 - <<'PY'
import json
import os

raw = os.environ.get("RESPONSE_JSON", "")
try:
    data = json.loads(raw)
except Exception:
    print("")
else:
    print(data.get("client_id", ""))
PY
)"
  client_secret="$(RESPONSE_JSON="$response" python3 - <<'PY'
import json
import os

raw = os.environ.get("RESPONSE_JSON", "")
try:
    data = json.loads(raw)
except Exception:
    print("")
else:
    print(data.get("client_secret", ""))
PY
)"

  [[ -n "$client_id" ]] || die "Figma OAuth registration response did not include client_id. Raw response: $response"
  [[ -n "$client_secret" ]] || die "Figma OAuth registration response did not include client_secret. Raw response: $response"

  FIGMA_CLIENT_ID_INPUT="$client_id"
  FIGMA_CLIENT_SECRET_INPUT="$client_secret"

  note "Registered a Figma OAuth client for Claude Code using callback $FIGMA_CLAUDE_CODE_REDIRECT_URI"
}

ensure_figma_claude_code_credentials() {
  ensure_install_globals
  if [[ -n "${FIGMA_CLIENT_ID_INPUT:-}" && -n "${FIGMA_CLIENT_SECRET_INPUT:-}" ]]; then
    return 0
  fi

  if ! has_cmd curl; then
    die "curl is required to register the Figma OAuth client for Claude Code"
  fi

  register_figma_claude_code_oauth_client
}

configure_figma_opencode() {
  ensure_install_globals
  local client_id="$1"
  local client_secret="$2"

  log "Configuring OpenCode with direct Figma MCP"
  if (( DRY_RUN )); then
    note "Would update ~/.config/opencode/opencode.json with a Figma remote MCP entry"
    return 0
  fi

  [[ -n "$client_id" ]] || die "Cannot configure OpenCode Figma MCP without client_id"
  [[ -n "$client_secret" ]] || die "Cannot configure OpenCode Figma MCP without client_secret"

  write_figma_opencode_json_config "~/.config/opencode/opencode.json" "$client_id" "$client_secret" || die "Failed to configure OpenCode for Figma MCP"
}

configure_figma_claude_code() {
  ensure_install_globals
  local client_id="$1"
  local client_secret="$2"

  log "Configuring Claude Code with direct Figma MCP"
  if (( DRY_RUN )); then
    note "Would add a Claude Code Figma MCP entry with pre-registered OAuth credentials"
    return 0
  fi

  [[ -n "$client_id" ]] || die "Cannot configure Claude Code Figma MCP without client_id"
  [[ -n "$client_secret" ]] || die "Cannot configure Claude Code Figma MCP without client_secret"

  if ! has_cmd claude; then
    warn "Claude executable not found; skipping automatic Claude Code Figma configuration"
    return 0
  fi

  capture_cmd claude mcp remove "$FIGMA_SERVER_NAME" >/dev/null || true
  local config_json
  config_json=$(python3 - <<'PY'
import json

print(json.dumps({
    "type": "http",
    "url": "https://mcp.figma.com/mcp",
    "oauth": {
        "clientId": "__CLIENT_ID__",
        "callbackPort": 19876,
    },
}))
PY
)
  config_json="${config_json/__CLIENT_ID__/$client_id}"
  MCP_CLIENT_SECRET="$client_secret" run_cmd claude mcp add-json --scope user "$FIGMA_SERVER_NAME" "$config_json" --client-secret
}

configure_browser_opencode() {
  ensure_install_globals

  log "Configuring OpenCode with Browser MCP"
  if (( DRY_RUN )); then
    note "Would update ~/.config/opencode/opencode.json with a Browser MCP local entry"
    return 0
  fi

  write_browser_opencode_json_config "~/.config/opencode/opencode.json" || die "Failed to configure OpenCode for Browser MCP"
}

configure_browser_claude_code() {
  ensure_install_globals

  log "Configuring Claude Code with Browser MCP"
  if (( DRY_RUN )); then
    note "Would update ~/.claude.json with a Browser MCP local entry"
    return 0
  fi

  write_browser_claude_code_json_config "~/.claude.json" || die "Failed to configure Claude Code for Browser MCP"
}

clear_figma_opencode_auth_cache() {
  ensure_install_globals

  if (( DRY_RUN )); then
    note "Would remove the '$FIGMA_SERVER_NAME' entry from ~/.local/share/opencode/mcp-auth.json if present"
    return 0
  fi

  TARGET_PATH="~/.local/share/opencode/mcp-auth.json" FIGMA_SERVER_NAME="$FIGMA_SERVER_NAME" python3 - <<'PY'
import json
import os
import shutil
import time

path = os.path.expanduser(os.environ["TARGET_PATH"])
server_name = os.environ["FIGMA_SERVER_NAME"]

if not os.path.exists(path):
    raise SystemExit(0)

with open(path, "r", encoding="utf-8") as f:
    raw = f.read().strip()

if not raw:
    raise SystemExit(0)

try:
    data = json.loads(raw)
except Exception:
    raise SystemExit(0)

if not isinstance(data, dict) or server_name not in data:
    raise SystemExit(0)

shutil.copy2(path, f"{path}.bak.{time.time_ns()}")
del data[server_name]

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

  note "Cleared any cached OpenCode auth state for '$FIGMA_SERVER_NAME'"
}

authenticate_figma_opencode() {
  ensure_install_globals
  if (( DRY_RUN )); then
    note "Would clear cached OpenCode auth state for '$FIGMA_SERVER_NAME'"
    note "Would run: opencode mcp auth $FIGMA_SERVER_NAME"
    return 0
  fi

  if ! has_cmd opencode; then
    warn "OpenCode executable not found; skipping automatic Figma OAuth login"
    return 0
  fi

  clear_figma_opencode_auth_cache
  capture_cmd opencode mcp logout "$FIGMA_SERVER_NAME" >/dev/null || true
  note "Starting OpenCode OAuth login for Figma using pre-registered client credentials; your browser may open for consent"
  run_cmd opencode mcp auth "$FIGMA_SERVER_NAME"
}

configure_opencode() {
  ensure_install_globals
  local api_key="${1:-}"
  log "Configuring OpenCode with direct Context7 MCP"
  if (( DRY_RUN )); then
    note "Would update ~/.config/opencode/opencode.json"
    return 0
  fi

  write_context7_json_config "~/.config/opencode/opencode.json" "opencode" "$api_key" || die "Failed to configure OpenCode"
}

configure_claude_code() {
  ensure_install_globals
  local api_key="${1:-}"
  log "Configuring Claude Code MCP settings"
  if (( DRY_RUN )); then
    note "Would update ~/.claude.json"
    return 0
  fi

  write_context7_json_config "~/.claude.json" "claude-code" "$api_key" || die "Failed to configure Claude Code"
}

configure_codex() {
  ensure_install_globals
  local api_key="${1:-}"
  log "Configuring Codex MCP settings"
  if (( DRY_RUN )); then
    note "Would update ~/.codex/config.toml"
    return 0
  fi

  CONTEXT7_API_KEY="$api_key" CONTEXT7_SERVER_NAME="$CONTEXT7_SERVER_NAME" CONTEXT7_URL="$CONTEXT7_URL" python3 - <<'PY' || die "Failed to configure Codex"
import os
import re
import shutil
import time


path = os.path.expanduser("~/.codex/config.toml")
os.makedirs(os.path.dirname(path), exist_ok=True)

content = ""
if os.path.exists(path):
    shutil.copy2(path, f"{path}.bak.{time.time_ns()}")
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

server_name = os.environ["CONTEXT7_SERVER_NAME"]
url = os.environ["CONTEXT7_URL"]
api_key = os.environ.get("CONTEXT7_API_KEY", "")

section_lines = [
    f"[mcp_servers.{server_name}]",
    f'url = "{url}"',
]
if api_key:
    section_lines.append(f'http_headers = {{ CONTEXT7_API_KEY = "{api_key}" }}')
section = "\n".join(section_lines) + "\n"

pattern = re.compile(rf'(?ms)^\[mcp_servers\.{re.escape(server_name)}\]\n.*?(?=^\[|\Z)')
if pattern.search(content):
    updated = pattern.sub(section, content).rstrip() + "\n"
else:
    updated = content.rstrip()
    if updated:
        updated += "\n\n"
    updated += section

with open(path, "w", encoding="utf-8") as f:
    f.write(updated)
PY
}

configure_vscode() {
  ensure_install_globals
  local api_key="${1:-}"
  log "Configuring VS Code MCP file"
  if (( DRY_RUN )); then
    note "Would update ~/.config/Code/User/mcp.json"
    return 0
  fi

  write_context7_json_config "~/.config/Code/User/mcp.json" "vscode" "$api_key" || die "Failed to configure VS Code"
}

configure_github_copilot_cli() {
  ensure_install_globals
  local api_key="${1:-}"
  log "Configuring GitHub Copilot CLI MCP file"
  if (( DRY_RUN )); then
    note "Would update ~/.copilot/mcp-config.json"
    return 0
  fi

  write_context7_json_config "${COPILOT_HOME:-$HOME/.copilot}/mcp-config.json" "copilot-cli" "$api_key" || die "Failed to configure GitHub Copilot CLI"
}

configure_cline() {
  ensure_install_globals
  local api_key="${1:-}"
  log "Configuring Cline MCP settings"
  if (( DRY_RUN )); then
    note "Would update ~/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json"
    return 0
  fi

  write_context7_json_config "~/.config/Code/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json" "cline" "$api_key" || die "Failed to configure Cline"
}

configure_continue() {
  ensure_install_globals
  local api_key="${1:-}"
  log "Configuring Continue MCP settings"
  if (( DRY_RUN )); then
    note "Would update ~/.continue/mcpServers/${CONTEXT7_SERVER_NAME}.json"
    return 0
  fi

  write_context7_json_config "~/.continue/mcpServers/${CONTEXT7_SERVER_NAME}.json" "continue" "$api_key" || die "Failed to configure Continue"
}

configure_gemini_cli() {
  ensure_install_globals
  local api_key="${1:-}"
  log "Configuring Gemini CLI MCP settings"
  if (( DRY_RUN )); then
    note "Would update ~/.gemini/settings.json"
    return 0
  fi

  write_context7_json_config "~/.gemini/settings.json" "gemini" "$api_key" || die "Failed to configure Gemini CLI"
}

wire_context7_to_tool() {
  ensure_install_globals
  local tool="$1"
  local api_key="${2:-}"

  case "$tool" in
    opencode)
      configure_opencode "$api_key"
      ;;
    claude-code)
      configure_claude_code "$api_key"
      ;;
    codex)
      configure_codex "$api_key"
      ;;
    github-copilot-cli)
      configure_github_copilot_cli "$api_key"
      ;;
    cline)
      configure_cline "$api_key"
      ;;
    continue)
      configure_continue "$api_key"
      ;;
    vscode)
      configure_vscode "$api_key"
      ;;
    gemini-cli)
      configure_gemini_cli "$api_key"
      ;;
    github-copilot)
      warn "No standalone GitHub Copilot MCP file is configured here; use the 'vscode' target for Copilot-in-VS-Code MCP wiring"
      ;;
    *)
      warn "No direct MCP wiring strategy is defined for $tool"
      ;;
  esac
}

wire_context7_to_tools() {
  local api_key="$1"
  shift
  ensure_install_globals
  local tool
  for tool in "$@"; do
    wire_context7_to_tool "$tool" "$api_key"
  done
}

wire_figma_to_tool() {
  ensure_install_globals
  local tool="$1"
  local client_id="$2"
  local client_secret="$3"

  case "$tool" in
    opencode)
      if [[ -z "$client_id" || -z "$client_secret" ]]; then
        ensure_figma_opencode_credentials
        client_id="$FIGMA_CLIENT_ID_INPUT"
        client_secret="$FIGMA_CLIENT_SECRET_INPUT"
      fi
      configure_figma_opencode "$client_id" "$client_secret"
      authenticate_figma_opencode
      ;;
    claude-code)
      if [[ -z "$client_id" || -z "$client_secret" ]]; then
        ensure_figma_claude_code_credentials
        client_id="$FIGMA_CLIENT_ID_INPUT"
        client_secret="$FIGMA_CLIENT_SECRET_INPUT"
      fi
      configure_figma_claude_code "$client_id" "$client_secret"
      ;;
    github-copilot)
      warn "Figma MCP is not wired automatically for GitHub Copilot here; use a tool with a native CLI OAuth flow"
      ;;
    *)
      warn "No native Figma MCP wiring strategy is defined for $tool"
      ;;
  esac
}

wire_figma_to_tools() {
  local client_id="$1"
  local client_secret="$2"
  shift 2
  ensure_install_globals
  local tool
  for tool in "$@"; do
    wire_figma_to_tool "$tool" "$client_id" "$client_secret"
  done
}

wire_browser_to_tool() {
  ensure_install_globals
  local tool="$1"

  case "$tool" in
    opencode)
      configure_browser_opencode
      ;;
    claude-code)
      configure_browser_claude_code
      ;;
    *)
      warn "No Browser MCP wiring strategy is defined for $tool"
      ;;
  esac
}

wire_browser_to_tools() {
  ensure_install_globals
  local tool
  for tool in "$@"; do
    wire_browser_to_tool "$tool"
  done
}
