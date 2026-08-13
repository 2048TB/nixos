#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh"

usage() {
  cat <<'EOF'
usage:
  install-live.sh --host <name> --disk <device> [--repo <path>] [--yes]

  --disk must match the diskDevice declared for the host in
  nix/hosts/default.nix; disko partitions the manifest value, so a mismatch
  is rejected instead of silently erasing a different disk.

examples:
  install-live.sh --host zly --disk /dev/nvme0n1
  install-live.sh --host zky --disk /dev/nvme0n1 --repo /path/to/repo
EOF
}

host=""
disk=""
repo="${NIXOS_CONFIG_REPO:-$PWD}"
assume_yes=0
repo_explicit=0
key_dir_rel=".keys"
age_key_rel="$key_dir_rel/main.agekey"
main_pub_rel="secrets/keys/main.age.pub"

run_nix_flake() {
  nix --extra-experimental-features 'nix-command flakes' "$@"
}

# disko partitions config.my.host.diskDevice from the host manifest, not the
# --disk argument. Refuse to continue when they disagree, otherwise the
# confirmation prompt would name one disk while disko erases another.
require_disk_matches_manifest() {
  local host_name="${1:?host name required}"
  local requested_disk="${2:?disk path required}"
  local manifest_disk=""

  if ! manifest_disk="$(run_nix_flake eval --raw \
    "path:${flake_repo}#nixosConfigurations.${host_name}.config.my.host.diskDevice")"; then
    echo "error: failed to read diskDevice for host '$host_name' from the manifest" >&2
    return 1
  fi

  if [ "$manifest_disk" != "$requested_disk" ]; then
    echo "error: --disk does not match the disk declared for host '$host_name'" >&2
    echo "  --disk   : $requested_disk" >&2
    echo "  manifest : $manifest_disk" >&2
    echo "hint: disko erases the manifest disk. Either pass --disk $manifest_disk," >&2
    echo "      or update nix/hosts/default.nix[nixos.$host_name].diskDevice first." >&2
    return 1
  fi
}

require_mountpoint() {
  local mountpoint="${1:?mountpoint required}"
  local mount_info=""

  if ! mount_info="$(findmnt "$mountpoint" 2>/dev/null)"; then
    echo "error: required mountpoint is not mounted: $mountpoint" >&2
    return 1
  fi

  printf '%s\n' "$mount_info"
}

cleanup_target_flake_tmp() {
  local status=$?

  if [ -n "${TARGET_FLAKE_TMP:-}" ] && sudo test -e "$TARGET_FLAKE_TMP"; then
    if ! sudo_safe_rm_rf_under /mnt/persistent "$TARGET_FLAKE_TMP"; then
      echo "warning: failed to remove temporary flake directory: $TARGET_FLAKE_TMP" >&2
    fi
  fi

  return "$status"
}

is_age_private_key_file() {
  local path="${1:-}"
  [ -r "$path" ] || return 1
  local first_data_line=""

  first_data_line="$(read_first_meaningful_line "$path")"
  [[ "$first_data_line" == AGE-SECRET-KEY-* ]]
}

read_repo_main_pub() {
  local repo_pub="${repo}/${main_pub_rel}"

  if [ ! -r "$repo_pub" ]; then
    echo "error: missing repo main age public key: $repo_pub" >&2
    return 1
  fi

  read_first_meaningful_line "$repo_pub"
}

age_key_matches_repo_pub() {
  local key_path="${1:-}"
  local candidate_pub=""
  local repo_pub=""
  local age_stderr=""
  local age_stderr_file=""

  repo_pub="$(read_repo_main_pub)" || return 1
  age_stderr_file="$(mktemp)"
  if ! candidate_pub="$(run_age_keygen -y "$key_path" 2>"$age_stderr_file" | awk 'NF { print; exit }')"; then
    age_stderr="$(tr '\n' ' ' <"$age_stderr_file" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
    rm -f "$age_stderr_file"
    echo "error: failed to derive public key from candidate age key: $key_path" >&2
    if [ -n "$age_stderr" ]; then
      echo "hint: age-keygen said: $age_stderr" >&2
    fi
    return 1
  fi
  rm -f "$age_stderr_file"
  [ -n "$candidate_pub" ] && [ "$candidate_pub" = "$repo_pub" ]
}

resolve_age_key_src() {
  declare -A seen=()
  local candidates=(
    "$PWD/$age_key_rel"
    "$repo/$age_key_rel"
  )
  local candidate

  if [ -n "${HOME:-}" ]; then
    candidates+=("$HOME/$age_key_rel")
  fi

  for candidate in "${candidates[@]}"; do
    [ -n "$candidate" ] || continue
    if [ -n "${seen[$candidate]:-}" ]; then
      continue
    fi
    seen[$candidate]=1
    [ -f "$candidate" ] || continue
    if is_age_private_key_file "$candidate"; then
      if age_key_matches_repo_pub "$candidate"; then
        printf '%s\n' "$candidate"
        return 0
      fi
      echo "error: age key does not match ${repo}/${main_pub_rel}: $candidate" >&2
      return 1
    fi
    echo "error: invalid age key file (expected AGE-SECRET-KEY-*): $candidate" >&2
    return 1
  done
  return 1
}

require_git_checkout_repo() {
  local src_repo="${1:?source repo required}"
  if ! git -C "$src_repo" rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "error: repo sync requires a Git checkout to enforce tracked-file allowlist: $src_repo" >&2
    return 1
  fi
}

sync_tracked_repo_payload() {
  local src_repo="${1:?source repo required}"
  local dst_dir="${2:?destination directory required}"
  local tracked_list=""
  local status=0

  require_git_checkout_repo "$src_repo"

  tracked_list="$(mktemp)"
  if ! git -C "$src_repo" ls-files -z >"$tracked_list"; then
    echo "error: failed to enumerate tracked files for repo sync: $src_repo" >&2
    rm -f "$tracked_list"
    return 1
  fi

  if [ ! -s "$tracked_list" ]; then
    echo "error: no tracked files found under repo: $src_repo" >&2
    rm -f "$tracked_list"
    return 1
  fi

  if sudo rsync -a --delete --from0 --files-from="$tracked_list" "$src_repo/" "$dst_dir/"; then
    :
  else
    status=$?
    echo "error: failed to sync tracked repo payload from $src_repo to $dst_dir" >&2
  fi

  rm -f "$tracked_list"
  return "$status"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
  --host)
    if [ "$#" -lt 2 ]; then
      echo "error: --host requires a value" >&2
      exit 2
    fi
    host="$2"
    shift 2
    ;;
  --disk)
    if [ "$#" -lt 2 ]; then
      echo "error: --disk requires a value" >&2
      exit 2
    fi
    disk="$2"
    shift 2
    ;;
  --repo)
    if [ "$#" -lt 2 ]; then
      echo "error: --repo requires a value" >&2
      exit 2
    fi
    repo="$2"
    repo_explicit=1
    shift 2
    ;;
  --yes)
    assume_yes=1
    shift
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

if [ -z "$host" ] || [ -z "$disk" ]; then
  echo "error: --host and --disk are required" >&2
  usage >&2
  exit 2
fi

if ! is_valid_host_name "$host"; then
  echo "error: invalid host name '$host'" >&2
  exit 2
fi

if [ "$repo_explicit" -eq 1 ] || [ -n "${NIXOS_CONFIG_REPO:-}" ]; then
  repo="$(resolve_repo_path "$repo")"
else
  repo="$(resolve_repo_path)"
fi
require_git_checkout_repo "$repo"
prepare_flake_repo_path "$repo"
flake_repo="$PREPARED_FLAKE_REPO"
validate_block_device_path "$disk"
require_disk_matches_manifest "$host" "$disk"
confirm_destructive_action \
  "INSTALL ${host} ${disk}" \
  "warning: this will erase disk ${disk} and install host ${host} from repo ${repo}" \
  "$assume_yes"

echo ">>> host=$host disk=$disk"

# 1. Run disko
disko_script="$(run_nix_flake build --impure --no-link --print-out-paths "path:${flake_repo}#nixosConfigurations.${host}.config.system.build.diskoScript")"
echo ">>> disko_script=$disko_script"
sudo "$disko_script"

# 2. Verify mounts
require_mountpoint /mnt/boot
require_mountpoint /mnt/persistent

# 3. Install sops age key
if age_key_src="$(resolve_age_key_src)"; then
  sudo install -D -m 0400 -o root -g root "$age_key_src" /mnt/persistent/keys/main.agekey
  echo ">>> sops key installed: $age_key_src -> /mnt/persistent/keys/main.agekey"
else
  echo "error: sops key not found (or invalid / mismatched) in search paths below:" >&2
  echo "  - $PWD/$age_key_rel" >&2
  echo "  - $repo/$age_key_rel" >&2
  if [ -n "${HOME:-}" ]; then
    echo "  - $HOME/$age_key_rel" >&2
  fi
  echo "hint: place the AGE private key matching $repo/$main_pub_rel into one of these paths, then retry." >&2
  exit 1
fi

# 4. Run nixos-install (from source repo)
sudo nixos-install --impure --flake "path:${flake_repo}#$host"

# 5. Sync flake into target /persistent/nixos-config (atomic replace)
TARGET_FLAKE_DIR="/mnt/persistent/nixos-config"
TARGET_FLAKE_TMP="${TARGET_FLAKE_DIR}.tmp.$$"
if ! sudo findmnt /mnt/persistent >/dev/null 2>&1; then
  echo "error: /mnt/persistent is not mounted. refusing to sync flake" >&2
  exit 1
fi

trap cleanup_target_flake_tmp EXIT
sudo_safe_rm_rf_under /mnt/persistent "$TARGET_FLAKE_TMP"
sudo mkdir -p "$TARGET_FLAKE_TMP"
# Sync only Git tracked files to avoid copying local/private/untracked data.
sync_tracked_repo_payload "$repo" "$TARGET_FLAKE_TMP"
# Keep decrypt key in repo copy for post-install sops workflows.
sudo install -D -m 0400 -o root -g root "$age_key_src" "$TARGET_FLAKE_TMP/.keys/main.agekey"
if [ ! -f "$TARGET_FLAKE_TMP/flake.nix" ]; then
  echo "error: synced target flake is incomplete: missing flake.nix" >&2
  exit 1
fi

target_user="$(run_nix_flake eval --raw "path:${flake_repo}#nixosConfigurations.${host}.config.my.host.username")"
target_owner="$(resolve_target_owner_from_rootfs /mnt "$target_user")"
sudo chown -R "$target_owner" "$TARGET_FLAKE_TMP"
sudo_safe_rm_rf_under /mnt/persistent "$TARGET_FLAKE_DIR"
sudo mv "$TARGET_FLAKE_TMP" "$TARGET_FLAKE_DIR"
trap - EXIT

# 6. Ensure target /etc/nixos points to persistent repo
sudo_safe_rm_rf_under /mnt/etc /mnt/etc/nixos
sudo ln -sfn /persistent/nixos-config /mnt/etc/nixos

# 7. Verify target flake (dry-build)
sudo env NIX_CONFIG='experimental-features = nix-command flakes' nixos-rebuild dry-build --flake /mnt/persistent/nixos-config#"$host"

echo ">>> github ssh key will be provisioned by sops secrets on first boot (if configured)"
echo "done: reboot into the installed system"
