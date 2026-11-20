# Colerm's project-aware zsh runtime metadata extension.

_colerm_report_runtime_metadata() {
  builtin emulate -L zsh -o no_aliases

  builtin local project_dir="$PWD"
  builtin local runtime_name="" runtime_path="" json encoded

  while [[ "$project_dir" != "/" ]]; do
    if [[ -f "$project_dir/bun.lock" || -f "$project_dir/bun.lockb" ]]; then
      runtime_name="Bun"
      runtime_path="$(builtin command -v bun 2>/dev/null)"
      break
    elif [[ -f "$project_dir/deno.json" || -f "$project_dir/deno.jsonc" ]]; then
      runtime_name="Deno"
      runtime_path="$(builtin command -v deno 2>/dev/null)"
      break
    elif [[ -f "$project_dir/package.json" || -f "$project_dir/pnpm-lock.yaml" ||
            -f "$project_dir/yarn.lock" || -f "$project_dir/package-lock.json" ]]; then
      runtime_name="Node"
      runtime_path="$(builtin command -v node 2>/dev/null)"
      break
    elif [[ -f "$project_dir/pyproject.toml" || -f "$project_dir/uv.lock" ||
            -f "$project_dir/requirements.txt" ]]; then
      runtime_name="Python"
      runtime_path="$(builtin command -v python3 2>/dev/null)"
      break
    elif [[ -f "$project_dir/Package.swift" ]]; then
      runtime_name="Swift"
      runtime_path="$(builtin command -v swift 2>/dev/null)"
      break
    elif [[ -f "$project_dir/Cargo.toml" ]]; then
      runtime_name="Rust"
      runtime_path="$(builtin command -v rustc 2>/dev/null)"
      break
    elif [[ -f "$project_dir/go.mod" ]]; then
      runtime_name="Go"
      runtime_path="$(builtin command -v go 2>/dev/null)"
      break
    fi
    project_dir="${project_dir:h}"
  done

  runtime_name="${runtime_name//$'\n'/}"
  runtime_path="${runtime_path//$'\n'/}"

  if [[ -n "$runtime_name" && "$runtime_path" == /* &&
        "$runtime_name$runtime_path" != *['"\\']* ]]; then
    json="{\"runtime\":{\"name\":\"$runtime_name\",\"path\":\"$runtime_path\"}}"
  else
    json='{"runtime":null}'
  fi

  [[ "$json" == "${_colerm_last_runtime_json:-}" ]] && return 0
  encoded="$(builtin print -rn -- "$json" | /usr/bin/base64 | /usr/bin/tr -d '\n')" || return 0
  [[ -n "$encoded" ]] || return 0

  builtin printf '\033]777;notify;colerm;1:%s\007' "$encoded" >&${_ghostty_fd:-1}
  typeset -g _colerm_last_runtime_json="$json"
}

_colerm_report_command_start() {
  builtin emulate -L zsh -o no_aliases
  builtin local cmd="${3:-${1:-}}" encoded=""
  cmd="${cmd[1,512]}"
  if [[ -n "$cmd" ]]; then
    encoded="$(builtin print -rn -- "$cmd" | /usr/bin/base64 | /usr/bin/tr -d '\n' 2>/dev/null)" || encoded=""
  fi
  builtin printf '\033]777;notify;colerm;2:%s\007' "$encoded" >&${_ghostty_fd:-1}
}

typeset -ag preexec_functions
if (( ${preexec_functions[(I)_colerm_report_command_start]} == 0 )); then
  preexec_functions+=(_colerm_report_command_start)
fi

if (( $+functions[_ghostty_precmd] )); then
  functions[_ghostty_precmd]+="
        _colerm_report_runtime_metadata"
else
  typeset -ag precmd_functions
  precmd_functions+=(_colerm_report_runtime_metadata)
  _colerm_report_runtime_metadata
fi

_colerm_should_wrap_claude() {
  builtin emulate -L zsh -o no_aliases
  [[ -n "${COLERM_STATUS_DIR:-}" && -d "${COLERM_STATUS_DIR:-}" &&
     -n "${COLERM_AGENT_HOOK:-}" && -x "${COLERM_AGENT_HOOK:-}" &&
     -n "${COLERM_CLAUDE_HOOKS_FILE:-}" && -f "${COLERM_CLAUDE_HOOKS_FILE:-}" ]] || return 1

  builtin local arg expect_value=0 first_positional=""
  for arg in "$@"; do
    if (( expect_value )); then
      expect_value=0
      continue
    fi
    case "$arg" in
      --)
        break
        ;;
      -h|--help|-v|--version|--settings|--settings=*)
        return 1
        ;;
      --model|--agent|--fallback-model|--output-format|--input-format|--json-schema|--max-budget-usd|--system-prompt|--append-system-prompt|--permission-mode|--setting-sources|--session-id|--agents|--allowedTools|--allowed-tools|--tools|--disallowedTools|--disallowed-tools|--mcp-config|--add-dir|--betas|--plugin-dir)
        expect_value=1
        ;;
      -*)
        ;;
      *)
        if [[ -z "$first_positional" ]]; then
          first_positional="$arg"
        fi
        ;;
    esac
  done

  case "$first_positional" in
    mcp|plugin|plugins|setup-token|doctor|update|install|uninstall|migrate-installer|config|auth|login|logout|help)
      return 1
      ;;
  esac
  return 0
}

_colerm_should_wrap_codex() {
  builtin emulate -L zsh -o no_aliases
  [[ -n "${COLERM_STATUS_DIR:-}" && -d "${COLERM_STATUS_DIR:-}" &&
     -n "${COLERM_AGENT_HOOK:-}" && -x "${COLERM_AGENT_HOOK:-}" ]] || return 1

  builtin local codex_config="${CODEX_HOME:-$HOME/.codex}/config.toml"
  if [[ -r "$codex_config" ]] && /usr/bin/grep -Eq '^[[:space:]]*notify[[:space:]]*=' "$codex_config" 2>/dev/null; then
    return 1
  fi

  builtin local arg expect_config=0 expect_value=0 first_positional=""
  for arg in "$@"; do
    if (( expect_config )); then
      expect_config=0
      [[ "$arg" == notify=* || "$arg" == notify\ =* ]] && return 1
      continue
    fi
    if (( expect_value )); then
      expect_value=0
      continue
    fi
    case "$arg" in
      --)
        break
        ;;
      -h|--help|-V|--version)
        return 1
        ;;
      -c|--config)
        expect_config=1
        ;;
      --config=notify=*|-cnotify=*)
        return 1
        ;;
      -m|--model|-p|--profile|-s|--sandbox|-a|--ask-for-approval|-C|--cd|--add-dir|-i|--image|--enable|--disable|--local-provider|--oss-provider)
        expect_value=1
        ;;
      -*)
        ;;
      *)
        if [[ -z "$first_positional" ]]; then
          first_positional="$arg"
        fi
        ;;
    esac
  done

  case "$first_positional" in
    login|logout|mcp|plugin|mcp-server|app-server|remote-control|app|completion|update|doctor|sandbox|debug|apply|a|archive|delete|unarchive|cloud|exec-server|features|help)
      return 1
      ;;
  esac
  return 0
}

if (( ! $+functions[claude] )); then
  claude() {
    if _colerm_should_wrap_claude "$@"; then
      builtin command claude --settings "$COLERM_CLAUDE_HOOKS_FILE" "$@"
    else
      builtin command claude "$@"
    fi
  }
fi

if (( ! $+functions[codex] )); then
  codex() {
    if _colerm_should_wrap_codex "$@"; then
      builtin local escaped_hook="${COLERM_AGENT_HOOK//\\/\\\\}"
      escaped_hook="${escaped_hook//\"/\\\"}"
      builtin command codex -c "notify=[\"${escaped_hook}\",\"codex\",\"notify\"]" "$@"
    else
      builtin command codex "$@"
    fi
  }
fi
