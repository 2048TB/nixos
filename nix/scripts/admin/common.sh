#!/usr/bin/env bash

# Shared helper functions for repository scripts.
# Intentionally does not set shell options; caller scripts are responsible.

is_valid_host_name() {
  local name="${1:-}"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]
}

read_first_meaningful_line() {
  local file_path="${1:?file path required}"

  awk '
    {
      line = $0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line == "" || line ~ /^#/) {
        next
      }
      print line
      exit
    }
  ' "$file_path"
}

resolve_repo_path() {
  local candidate=""
  local explicit_candidate=0
  local repo_root=""
  local script_repo=""

  if [ "$#" -gt 0 ]; then
    candidate="${1:-}"
    explicit_candidate=1
  elif [ "${NIXOS_CONFIG_REPO+x}" = "x" ]; then
    candidate="$NIXOS_CONFIG_REPO"
    # NIXOS_CONFIG_REPO is user-supplied explicit intent; never silently fallback.
    explicit_candidate=1
  else
    candidate="$PWD"
  fi

  if [ -z "$candidate" ]; then
    echo "error: empty repo path" >&2
    return 1
  fi

  if [ -f "$candidate/flake.nix" ]; then
    (cd "$candidate" && pwd -P)
    return 0
  fi

  if repo_root="$(git -C "$candidate" rev-parse --show-toplevel 2>/dev/null)"; then
    if [ -f "$repo_root/flake.nix" ]; then
      printf '%s\n' "$repo_root"
      return 0
    fi
  fi

  if [ "$explicit_candidate" -eq 1 ]; then
    echo "error: flake.nix not found in repo: $candidate" >&2
    return 1
  fi

  script_repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
  if [ -f "$script_repo/flake.nix" ]; then
    printf '%s\n' "$script_repo"
    return 0
  fi

  echo "error: flake.nix not found in repo: $candidate" >&2
  return 1
}

needs_filtered_flake_repo() {
  local repo_root="${1:?repo root required}"
  local key_path="$repo_root/.keys/main.agekey"
  [ -e "$key_path" ] && [ ! -r "$key_path" ]
}

assert_safe_child_path() {
  local base="${1:?base path required}"
  local target="${2:?target path required}"
  local base_real=""
  local target_parent=""
  local target_parent_real=""
  local target_name=""

  if [[ "$base" != /* ]]; then
    echo "error: safe delete base must be absolute: $base" >&2
    return 1
  fi

  if [[ "$target" != /* ]]; then
    echo "error: safe delete target must be absolute: $target" >&2
    return 1
  fi

  if [ ! -d "$base" ]; then
    echo "error: safe delete base is not a directory: $base" >&2
    return 1
  fi

  target_parent="$(dirname -- "$target")"
  target_name="$(basename -- "$target")"
  if [ -z "$target_name" ] || [ "$target_name" = "." ] || [ "$target_name" = "/" ]; then
    echo "error: unsafe delete target: $target" >&2
    return 1
  fi

  if ! base_real="$(cd "$base" && pwd -P)"; then
    echo "error: failed to resolve safe delete base: $base" >&2
    return 1
  fi
  if [ ! -d "$target_parent" ]; then
    echo "error: safe delete target parent is not a directory: $target_parent" >&2
    return 1
  fi
  if ! target_parent_real="$(cd "$target_parent" && pwd -P)"; then
    echo "error: failed to resolve safe delete target parent: $target_parent" >&2
    return 1
  fi

  if [ "$target_parent_real" != "$base_real" ] && [[ "$target_parent_real" != "$base_real"/* ]]; then
    echo "error: refusing to delete outside $base_real: $target" >&2
    return 1
  fi
}

safe_rm_rf_under() {
  local base="${1:?base path required}"
  local target="${2:?target path required}"

  assert_safe_child_path "$base" "$target" || return 1
  command rm -rf -- "$target"
}

sudo_safe_rm_rf_under() {
  local base="${1:?base path required}"
  local target="${2:?target path required}"

  assert_safe_child_path "$base" "$target" || return 1
  sudo -- rm -rf -- "$target"
}

prepare_flake_repo_path() {
  local repo_root="${1:?repo root required}"
  local cache_key=""
  local cache_base=""
  local cache_root=""

  # shellcheck disable=SC2034
  PREPARED_FLAKE_REPO="$repo_root"

  if ! needs_filtered_flake_repo "$repo_root"; then
    return 0
  fi

  cache_key="$(printf '%s' "$repo_root" | cksum | awk '{print $1}')"
  if mkdir -p "${repo_root}/.cache/nixos-config" 2>/dev/null; then
    cache_base="${repo_root}/.cache/nixos-config"
  elif [ -n "${XDG_CACHE_HOME:-}" ] && mkdir -p "${XDG_CACHE_HOME}/nixos-config" 2>/dev/null; then
    cache_base="${XDG_CACHE_HOME}/nixos-config"
  elif [ -n "${HOME:-}" ] && mkdir -p "${HOME}/.cache/nixos-config" 2>/dev/null; then
    cache_base="${HOME}/.cache/nixos-config"
  else
    cache_base="${TMPDIR:-/tmp}"
  fi
  if ! find "$cache_base" -mindepth 1 -maxdepth 1 -type d -name "flake-$(id -u)-${cache_key}-*" -mmin +120 -exec rm -rf {} + >/dev/null 2>&1; then
    echo "warning: failed to prune stale filtered flake repos under cache: $cache_base" >&2
  fi
  # Use a per-process cache dir so concurrent script runs do not delete each
  # other's prepared flake repo while a command is still evaluating it.
  cache_root="${cache_base}/flake-$(id -u)-${cache_key}-$$"

  mkdir -p "$cache_root"
  safe_rm_rf_under "$cache_base" "$cache_root/repo"
  mkdir -p "$cache_root/repo"

  if ! rsync -a --delete \
    --exclude '.git/' \
    --exclude '.cache/' \
    --exclude '.keys/' \
    --exclude '.serena/' \
    --exclude 'result' \
    --exclude 'result-*' \
    "$repo_root/" "$cache_root/repo/"; then
    echo "error: failed to prepare filtered flake repo from $repo_root into $cache_root/repo" >&2
    return 1
  fi

  # shellcheck disable=SC2034
  PREPARED_FLAKE_REPO="$cache_root/repo"
}

enter_repo_root() {
  local repo_root
  if [ "$#" -gt 0 ]; then
    repo_root="$(resolve_repo_path "$1")" || return 1
  else
    repo_root="$(resolve_repo_path)" || return 1
  fi
  cd "$repo_root" || return 1
  printf '%s\n' "$repo_root"
}

run_age_keygen() {
  run_command_with_nix_fallback nixpkgs#age age-keygen "$@"
}

run_ssh_keygen() {
  run_command_with_nix_fallback nixpkgs#openssh ssh-keygen "$@"
}

run_ssh_to_age() {
  run_command_with_nix_fallback nixpkgs#ssh-to-age ssh-to-age "$@"
}

run_sops() {
  run_command_with_nix_fallback nixpkgs#sops sops "$@"
}

run_command_with_nix_fallback() {
  local fallback_package="${1:?fallback package required}"
  local command_name="${2:?command name required}"
  shift 2

  if command -v "$command_name" >/dev/null 2>&1; then
    "$command_name" "$@"
  else
    nix --extra-experimental-features "nix-command flakes" shell "$fallback_package" -c "$command_name" "$@"
  fi
}

# Encrypt YAML from stdin to target path with selected age recipients.
# Usage: run_sops_encrypt_yaml <recipient-csv> <target-file>
run_sops_encrypt_yaml() {
  local recipients="${1:-}"
  local target_file="${2:-}"
  local target_dir=""
  local temp_file=""

  if [ -z "$recipients" ]; then
    echo "error: empty sops recipient list" >&2
    return 1
  fi

  if [ -z "$target_file" ]; then
    echo "error: empty sops target file path" >&2
    return 1
  fi

  target_dir="$(dirname "$target_file")"
  mkdir -p "$target_dir"
  temp_file="$(mktemp "$target_dir/.tmp.$(basename "$target_file").XXXXXX")"

  # shellcheck disable=SC2094  # stdin and stdout target are distinct fds
  if ! run_sops \
    --encrypt \
    --filename-override "$target_file" \
    --age "$recipients" \
    --input-type yaml \
    --output-type yaml \
    /dev/stdin >"$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi

  if ! mv "$temp_file" "$target_file"; then
    rm -f "$temp_file"
    return 1
  fi
}

confirm_destructive_action() {
  local token="${1:?confirmation token required}"
  local message="${2:-}"
  local assume_yes="${3:-0}"
  local answer=""

  if [ "$assume_yes" = "1" ]; then
    return 0
  fi

  if [ -n "$message" ]; then
    printf '%s\n' "$message" >&2
  fi

  if [ ! -t 0 ]; then
    echo "error: destructive action requires confirmation; rerun with --yes if intended" >&2
    return 1
  fi

  printf 'Type "%s" to continue: ' "$token" >&2
  IFS= read -r answer
  if [ "$answer" != "$token" ]; then
    echo "error: confirmation token mismatch" >&2
    return 1
  fi
}

validate_block_device_path() {
  local disk="${1:-}"

  if [[ "$disk" != /dev/* ]]; then
    echo "error: disk path must start with /dev/: $disk" >&2
    return 1
  fi

  if [ ! -b "$disk" ]; then
    echo "error: disk path is not a block device: $disk" >&2
    return 1
  fi
}

resolve_target_owner_from_rootfs() {
  local rootfs="${1:?rootfs required}"
  local username="${2:?username required}"
  local uid=""
  local gid=""
  local passwd_file="${rootfs}/etc/passwd"

  if [ ! -r "$passwd_file" ]; then
    echo "error: target passwd file is not readable: $passwd_file" >&2
    return 1
  fi

  uid="$(
    awk -F: -v user="$username" '$1 == user { print $3; exit }' "$passwd_file"
  )"
  gid="$(
    awk -F: -v user="$username" '$1 == user { print $4; exit }' "$passwd_file"
  )"

  if [ -z "$uid" ] || [ -z "$gid" ]; then
    echo "error: user '$username' not found in target passwd file: $passwd_file" >&2
    return 1
  fi

  printf '%s:%s\n' "$uid" "$gid"
}
