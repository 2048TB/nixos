#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh"

usage() {
  cat <<'EOF'
usage: check-format-sanity.sh [--repo <path>]

Checks parse-level formatting risks that can break this repository:
- shell scripts must keep the shebang isolated on the first line
- YAML files must parse
- JSON files must parse
- Markdown files must not contain trailing whitespace
- justfile must parse via just --summary
- suspicious Nix comment/code collisions fail the check
EOF
}

repo_arg=""
while [ "$#" -gt 0 ]; do
  case "$1" in
  --repo)
    if [ "$#" -lt 2 ]; then
      echo "error: --repo requires a value" >&2
      exit 2
    fi
    repo_arg="$2"
    shift 2
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [ -n "$repo_arg" ]; then
  repo_root="$(resolve_repo_path "$repo_arg")"
else
  repo_root="$(resolve_repo_path)"
fi
cd "$repo_root"

failures=0
comment_hits="$(mktemp)"
trap 'rm -f "$comment_hits"' EXIT

fail() {
  echo "ERROR: $*" >&2
  failures=1
}

repo_has_git() {
  git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

repo_file_path() {
  local file="${1:?file path required}"
  case "$file" in
  /*) printf '%s\n' "$file" ;;
  *) printf '%s/%s\n' "$repo_root" "$file" ;;
  esac
}

display_path() {
  local file="${1:?file path required}"
  file="${file#"$repo_root"/}"
  printf '%s\n' "$file"
}

find_repo_files() {
  local name_pattern="${1:?name pattern required}"
  find "$repo_root" \
    \( -path "$repo_root/.git" \
    -o -path "$repo_root/.cache" \
    -o -path "$repo_root/.direnv" \
    -o -path "$repo_root/result" \
    -o -path "$repo_root/result-*" \) -prune \
    -o -type f -name "$name_pattern" -print0
}

list_shell_files() {
  if repo_has_git; then
    git -C "$repo_root" ls-files -z -- '*.sh'
  else
    find_repo_files '*.sh'
  fi
}

list_nix_files() {
  if repo_has_git; then
    git -C "$repo_root" ls-files -z -- '*.nix'
  else
    find_repo_files '*.nix'
  fi
}

list_yaml_files() {
  if repo_has_git; then
    git -C "$repo_root" ls-files -z -- '*.yaml' '*.yml'
  else
    find_repo_files '*.yaml'
    find_repo_files '*.yml'
  fi
}

list_json_files() {
  if repo_has_git; then
    git -C "$repo_root" ls-files -z -- '*.json'
  else
    find_repo_files '*.json'
  fi
}

list_markdown_files() {
  if repo_has_git; then
    git -C "$repo_root" ls-files -z -- '*.md'
  else
    find_repo_files '*.md'
  fi
}

check_shell_shebangs() {
  local file path first_line shown

  while IFS= read -r -d '' file; do
    path="$(repo_file_path "$file")"
    shown="$(display_path "$path")"
    if [ ! -f "$path" ]; then
      continue
    fi

    first_line=""
    if ! IFS= read -r first_line <"$path"; then
      fail "$shown is empty or unreadable"
      continue
    fi

    if [ "$first_line" != "#!/usr/bin/env bash" ]; then
      fail "$shown first line must be exactly '#!/usr/bin/env bash'"
    fi

    if [[ "$first_line" == *"set -euo pipefail"* ]]; then
      fail "$shown shebang line contains script body"
    fi
  done < <(list_shell_files)
}

yaml_parser=""

# Pick the YAML parser once so a missing parser is reported as a missing tool
# instead of surfacing as "every YAML file is broken".
resolve_yaml_parser() {
  if [ -n "$yaml_parser" ]; then
    return 0
  fi

  if command -v yq >/dev/null 2>&1; then
    yaml_parser="yq"
  elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
    yaml_parser="python3"
  elif command -v ruby >/dev/null 2>&1; then
    yaml_parser="ruby"
  else
    return 1
  fi
}

parse_yaml_file() {
  local file="${1:?file path required}"

  case "$yaml_parser" in
  yq)
    yq '.' "$file" >/dev/null
    ;;
  python3)
    python3 - "$file" <<'PY'
import sys
import yaml

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    yaml.safe_load(handle)
PY
    ;;
  ruby)
    ruby -e 'require "yaml"; YAML.load_file(ARGV.fetch(0))' "$file"
    ;;
  *)
    return 127
    ;;
  esac
}

check_yaml_files() {
  local file path shown sops_file

  sops_file="$repo_root/.sops.yaml"
  if [ ! -f "$sops_file" ]; then
    fail ".sops.yaml is missing"
  fi

  if ! resolve_yaml_parser; then
    fail "yq, python3 with PyYAML, or ruby is required to parse YAML files"
    return
  fi

  while IFS= read -r -d '' file; do
    path="$(repo_file_path "$file")"
    shown="$(display_path "$path")"
    if [ ! -f "$path" ]; then
      continue
    fi

    if ! parse_yaml_file "$path"; then
      fail "$shown does not parse as YAML"
    fi
  done < <(list_yaml_files)
}

check_json_files() {
  local file path shown

  if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
    fail "jq or python3 is required to parse JSON files"
    return
  fi

  while IFS= read -r -d '' file; do
    path="$(repo_file_path "$file")"
    shown="$(display_path "$path")"
    if [ ! -f "$path" ]; then
      continue
    fi

    if command -v jq >/dev/null 2>&1; then
      if ! jq empty "$path" >/dev/null; then
        fail "$shown does not parse as JSON"
      fi
    elif ! python3 -m json.tool "$path" >/dev/null; then
      fail "$shown does not parse as JSON"
    fi
  done < <(list_json_files)
}

check_markdown_trailing_whitespace() {
  local file path shown hits

  while IFS= read -r -d '' file; do
    path="$(repo_file_path "$file")"
    shown="$(display_path "$path")"
    if [ ! -f "$path" ]; then
      continue
    fi

    hits="$(awk '/[ \t]$/ { print FNR }' "$path")"
    if [ -n "$hits" ]; then
      fail "$shown contains trailing whitespace on line(s): $(printf '%s' "$hits" | paste -sd, -)"
    fi
  done < <(list_markdown_files)
}

check_justfile() {
  if ! command -v just >/dev/null 2>&1; then
    fail "just is required to parse justfile"
    return
  fi

  if ! just --summary >/dev/null; then
    fail "justfile does not parse via just --summary"
  fi
}

check_nix_comment_collisions() {
  local file path

  : >"$comment_hits"
  while IFS= read -r -d '' file; do
    path="$(repo_file_path "$file")"
    if [ ! -f "$path" ]; then
      continue
    fi

    awk '
      (($0 ~ /\{[[:space:]]*#/) || ($0 ~ /;[[:space:]]*#/)) &&
      ($0 ~ /#[^#]*[A-Za-z_][A-Za-z0-9_.-]*[[:space:]]*=/) {
        print FILENAME ":" FNR ":" $0
      }
    ' "$path" >>"$comment_hits"
  done < <(list_nix_files)

  while IFS= read -r hit; do
    fail "possible Nix comment/code collision: $(display_path "$hit")"
  done <"$comment_hits"
}

check_shell_shebangs
check_yaml_files
check_json_files
check_markdown_trailing_whitespace
check_justfile
check_nix_comment_collisions

if [ "$failures" -ne 0 ]; then
  exit 1
fi

echo "format-sanity: OK"
