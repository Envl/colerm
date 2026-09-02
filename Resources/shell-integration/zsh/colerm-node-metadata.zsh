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
  builtin printf '\033]777;notify;colerm;2:\007' >&${_ghostty_fd:-1}
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
