#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC2034
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh"

repo_root="$(enter_repo_root)"

# ── shared paths ──────────────────────────────────────────────
key_dir="$repo_root/.keys"
secrets_key_dir="$repo_root/secrets/keys"
host_key_dir="$secrets_key_dir/hosts"
main_key="$key_dir/main.agekey"
main_pub="$secrets_key_dir/main.age.pub"
recovery_key="$key_dir/recovery.agekey"
recovery_pub="$secrets_key_dir/recovery.age.pub"
rotation_backup_glob="$key_dir/main.agekey.pre-rotate.*"
required_sops_path_rules=(
  '^secrets/common/.*\.yaml$'
  '^secrets/hosts/[^/]+/.*\.yaml$'
  '^secrets/users/[^/]+/.*\.yaml$'
  '^secrets/install/.*\.yaml$'
)

# ── helpers ───────────────────────────────────────────────────
require_main_key() {
  if [ ! -f "$main_key" ]; then
    echo "error: missing $main_key" >&2
    echo "hint: import your existing main key, or run: nix/scripts/admin/sops.sh init --create" >&2
    exit 1
  fi
}

require_main_pub() {
  if [ ! -f "$main_pub" ]; then
    echo "error: missing $main_pub; run: nix/scripts/admin/sops.sh init" >&2
    exit 1
  fi
  if [ -z "$(tr -d '\n' <"$main_pub")" ]; then
    echo "error: empty public key file: $main_pub" >&2
    exit 1
  fi
}

list_rotation_backup_keys() {
  find "$key_dir" -maxdepth 1 -type f -name 'main.agekey.pre-rotate.*' | sort
}

build_identity_file() {
  local identity_file

  identity_file="$(mktemp)"
  chmod 0600 "$identity_file"
  cat "$main_key" >"$identity_file"

  if [ -f "$recovery_key" ]; then
    printf '\n' >>"$identity_file"
    cat "$recovery_key" >>"$identity_file"
  fi

  while IFS= read -r backup_key; do
    [ -n "$backup_key" ] || continue
    printf '\n' >>"$identity_file"
    cat "$backup_key" >>"$identity_file"
  done < <(list_rotation_backup_keys)

  printf '%s\n' "$identity_file"
}

collect_file_age_recipients() {
  local file="${1:-}"

  awk '
    $1 == "recipient:" && $2 ~ /^age1/ { print $2; next }
    $1 == "-" && $2 == "recipient:" && $3 ~ /^age1/ { print $3; next }
  ' "$file" | awk 'NF && !seen[$0]++'
}

join_csv() {
  if [ "$#" -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "$@" | paste -sd, -
}

trim_line() {
  tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

primary_user_name() {
  if [ -n "${SOPS_USER:-}" ]; then
    printf '%s\n' "$SOPS_USER"
    return 0
  fi

  if [ -n "${USER:-}" ] && [ "$USER" != "root" ]; then
    printf '%s\n' "$USER"
    return 0
  fi

  awk -F'"' '
    /^[[:space:]]*username[[:space:]]*=/ {
      print $2
      exit
    }
  ' "$repo_root/nix/hosts/nixos/_shared/vars-common.nix"
}

collect_age_recipients() {
  local item host_file host_rec
  local ssh_to_age_stderr=""
  local ssh_to_age_stderr_file=""
  local -a recipients=()

  if [ -f "$main_pub" ]; then
    item="$(read_first_meaningful_line "$main_pub")"
    [ -n "$item" ] && recipients+=("$item")
  fi

  if [ -f "$recovery_pub" ]; then
    item="$(read_first_meaningful_line "$recovery_pub")"
    [ -n "$item" ] && recipients+=("$item")
  fi

  if [ -d "$host_key_dir" ]; then
    while IFS= read -r host_file; do
      ssh_to_age_stderr_file="$(mktemp)"
      if ! host_rec="$(run_ssh_to_age <"$host_file" 2>"$ssh_to_age_stderr_file" | trim_line)"; then
        ssh_to_age_stderr="$(tr '\n' ' ' <"$ssh_to_age_stderr_file" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//')"
        rm -f "$ssh_to_age_stderr_file"
        echo "error: invalid host recipient file: $host_file" >&2
        if [ -n "$ssh_to_age_stderr" ]; then
          echo "hint: ssh-to-age said: $ssh_to_age_stderr" >&2
        fi
        return 1
      fi
      rm -f "$ssh_to_age_stderr_file"
      if [ -z "$host_rec" ]; then
        echo "error: empty host recipient derived from: $host_file" >&2
        return 1
      fi
      recipients+=("$host_rec")
    done < <(find "$host_key_dir" -maxdepth 1 -type f -name '*.pub' | sort)
  fi

  if [ "${#recipients[@]}" -eq 0 ]; then
    echo "error: no age recipients resolved" >&2
    return 1
  fi

  printf '%s\n' "${recipients[@]}" | awk 'NF && !seen[$0]++'
}

collect_age_recipients_csv() {
  local recipient=""
  local recipients_text=""
  local -a recipients=()

  if ! recipients_text="$(collect_age_recipients)"; then
    return 1
  fi

  while IFS= read -r recipient; do
    [ -n "$recipient" ] && recipients+=("$recipient")
  done <<<"$recipients_text"

  if [ "${#recipients[@]}" -eq 0 ]; then
    echo "error: no age recipients resolved" >&2
    return 1
  fi
  join_csv "${recipients[@]}"
}

ensure_sops_secret_path_rule() {
  local sops_cfg="$repo_root/.sops.yaml"
  local expected found rule
  local -a path_rules

  if [ ! -f "$sops_cfg" ]; then
    echo "error: missing $sops_cfg" >&2
    return 1
  fi

  mapfile -t path_rules < <(
    awk '
      /^[[:space:]]*-[[:space:]]*path_regex:[[:space:]]*/ {
        sub(/^[[:space:]]*-[[:space:]]*path_regex:[[:space:]]*/, "", $0)
        print
        next
      }
      /^[[:space:]]*path_regex:[[:space:]]*/ {
        sub(/^[[:space:]]*path_regex:[[:space:]]*/, "", $0)
        print
      }
    ' "$sops_cfg"
  )

  for rule in "${path_rules[@]}"; do
    if [ "$rule" = '^secrets/.*\.yaml$' ]; then
      echo "error: $sops_cfg still uses the legacy catch-all secret rule: $rule" >&2
      echo "hint: use common/hosts/users/install path-specific rules instead" >&2
      return 1
    fi
  done

  for expected in "${required_sops_path_rules[@]}"; do
    found=0
    for rule in "${path_rules[@]}"; do
      if [ "$rule" = "$expected" ]; then
        found=1
        break
      fi
    done
    if [ "$found" -ne 1 ]; then
      echo "error: missing creation_rules.path_regex in $sops_cfg: '$expected'" >&2
      return 1
    fi
  done
}

encrypt_yaml_to_target() {
  local target="${1:?target file required}"
  local recipients_csv="${2:?recipient csv required}"

  run_sops_encrypt_yaml "$recipients_csv" "$target"
}

run_mkpasswd() {
  run_command_with_nix_fallback nixpkgs#mkpasswd mkpasswd "$@"
}

# Rewrite the &main / &recovery anchors in .sops.yaml to the current public
# keys. Required after generating new keys, otherwise later `sops` edits would
# re-encrypt secrets to the old (lost) recipients.
update_sops_anchors() {
  local sops_cfg="$repo_root/.sops.yaml"
  local new_main new_recovery tmp

  if [ ! -f "$sops_cfg" ]; then
    echo "error: missing $sops_cfg" >&2
    return 1
  fi

  new_main="$(read_first_meaningful_line "$main_pub")"
  new_recovery="$(read_first_meaningful_line "$recovery_pub")"
  if [ -z "$new_main" ] || [ -z "$new_recovery" ]; then
    echo "error: empty main/recovery public key while updating .sops.yaml" >&2
    return 1
  fi

  tmp="$(mktemp)"
  sed -E \
    -e "s/(&main[[:space:]]+)age1[a-z0-9]+/\1${new_main}/" \
    -e "s/(&recovery[[:space:]]+)age1[a-z0-9]+/\1${new_recovery}/" \
    "$sops_cfg" >"$tmp"

  if ! grep -q "$new_main" "$tmp" || ! grep -q "$new_recovery" "$tmp"; then
    rm -f "$tmp"
    echo "error: failed to update .sops.yaml anchors (pattern not found)" >&2
    return 1
  fi
  mv "$tmp" "$sops_cfg"
  echo "updated .sops.yaml anchors (&main, &recovery)"
}

# ── subcommands ───────────────────────────────────────────────

cmd_init() {
  local mode="default"
  local assume_yes=0
  local backup_key=""
  local temp_main_dir=""
  local temp_main_key=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
    --create)
      mode="create"
      shift
      ;;
    --rotate)
      mode="rotate"
      shift
      ;;
    --yes)
      assume_yes=1
      shift
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
    esac
  done

  mkdir -p "$key_dir" "$secrets_key_dir"

  case "$mode" in
  default)
    if [ ! -f "$main_key" ]; then
      echo "error: missing $main_key" >&2
      echo "hint: import your existing main key first, then rerun." >&2
      echo "      use --create only for the very first bootstrap." >&2
      exit 1
    fi
    ;;
  create)
    if [ ! -f "$main_key" ]; then
      run_age_keygen -o "$main_key" >/dev/null
      echo "created new main key: $main_key"
    fi
    ;;
  rotate)
    require_main_key
    require_main_pub
    confirm_destructive_action \
      "ROTATE SOPS MAIN KEY" \
      "warning: this will generate a new main age identity, keep a backup of the old key for rekey, and update $main_pub" \
      "$assume_yes"
    backup_key="$key_dir/main.agekey.pre-rotate.$(date +%Y%m%d%H%M%S)"
    temp_main_dir="$(mktemp -d "$key_dir/.main.agekey.new.XXXXXX")"
    temp_main_key="$temp_main_dir/main.agekey"
    # shellcheck disable=SC2064
    trap "safe_rm_rf_under '$key_dir' '$temp_main_dir'" RETURN
    run_age_keygen -o "$temp_main_key" >/dev/null
    cp "$main_key" "$backup_key"
    chmod 0400 "$backup_key"
    mv "$temp_main_key" "$main_key"
    trap - RETURN
    rmdir "$temp_main_dir"
    echo "rotated main key: $main_key"
    echo "backup kept for decrypt/rekey: $backup_key"
    echo "warning: run 'nix/scripts/admin/sops.sh rekey' before next deployment, then remove obsolete backups from $rotation_backup_glob."
    ;;
  esac

  chmod 0400 "$main_key"
  run_age_keygen -y "$main_key" >"$main_pub"

  echo "sops key ready:"
  echo "- private: $main_key"
  echo "- public : $main_pub"
}

cmd_password_set() {
  if [ $# -ne 1 ]; then
    echo "usage: sops.sh password-set '<sha512-hash>'" >&2
    exit 2
  fi

  local password_hash="$1"
  local user_secret="$repo_root/secrets/common/passwords/user-password.yaml"
  local root_secret="$repo_root/secrets/common/passwords/root-password.yaml"
  local recipients_csv

  require_main_pub
  recipients_csv="$(collect_age_recipients_csv)"

  encrypt_yaml_to_target "$user_secret" "$recipients_csv" <<EOF_HASH
value: "$password_hash"
EOF_HASH

  encrypt_yaml_to_target "$root_secret" "$recipients_csv" <<EOF_HASH
value: "$password_hash"
EOF_HASH

  echo "updated sops password secrets:"
  echo "- $user_secret"
  echo "- $root_secret"
}

cmd_ssh_key_set() {
  local private_src="$repo_root/.keys/github_id_ed25519"
  local public_src="$repo_root/.keys/github_id_ed25519.pub"
  local target_user
  local private_secret
  local public_secret
  local recipients_csv

  target_user="$(primary_user_name)"
  if [ -z "$target_user" ]; then
    echo "error: could not determine SOPS target user; set SOPS_USER explicitly" >&2
    exit 1
  fi
  private_secret="$repo_root/secrets/users/$target_user/ssh/github_id_ed25519.yaml"
  public_secret="$repo_root/secrets/users/$target_user/ssh/github_id_ed25519_pub.yaml"

  if [ ! -f "$private_src" ]; then
    echo "error: missing $private_src" >&2
    echo "hint: place your SSH private key at .keys/github_id_ed25519 first" >&2
    exit 1
  fi

  if [ ! -f "$public_src" ]; then
    run_ssh_keygen -y -f "$private_src" >"$public_src"
  fi

  chmod 0600 "$private_src"
  chmod 0644 "$public_src"

  require_main_pub
  recipients_csv="$(collect_age_recipients_csv)"

  {
    echo "value: |"
    sed 's/^/  /' "$private_src"
  } | encrypt_yaml_to_target "$private_secret" "$recipients_csv"

  {
    echo "value: |"
    sed 's/^/  /' "$public_src"
  } | encrypt_yaml_to_target "$public_secret" "$recipients_csv"

  echo "updated sops ssh key secrets:"
  echo "- $private_secret"
  echo "- $public_secret"
}

cmd_recovery_init() {
  local force=0
  if [ "${1:-}" = "--force" ]; then
    force=1
    shift
  fi
  if [ "$#" -ne 0 ]; then
    echo "error: unexpected arguments for recovery-init" >&2
    exit 2
  fi

  mkdir -p "$key_dir" "$secrets_key_dir"

  if [ "$force" -eq 1 ] || [ ! -f "$recovery_key" ]; then
    run_age_keygen -o "$recovery_key" >/dev/null
    echo "recovery identity ready: $recovery_key"
  fi
  chmod 0400 "$recovery_key"
  run_age_keygen -y "$recovery_key" >"$recovery_pub"
  echo "recovery recipient updated: $recovery_pub"
}

cmd_host_add() {
  local host="${1:-}"
  local pub_src="${2:-/etc/ssh/ssh_host_ed25519_key.pub}"

  if [ -z "$host" ]; then
    echo "error: host name is required" >&2
    exit 2
  fi
  if ! is_valid_host_name "$host"; then
    echo "error: invalid host name '$host'" >&2
    exit 2
  fi
  if [ ! -f "$pub_src" ]; then
    echo "error: missing host public key: $pub_src" >&2
    exit 1
  fi

  local first_field second_field
  first_field="$(awk '{print $1}' "$pub_src" | head -n 1)"
  second_field="$(awk '{print $2}' "$pub_src" | head -n 1)"
  if [ "$first_field" != "ssh-ed25519" ] || [ -z "$second_field" ]; then
    echo "error: invalid ssh-ed25519 public key file: $pub_src" >&2
    exit 1
  fi

  mkdir -p "$host_key_dir"
  local target="$host_key_dir/${host}.ssh_host_ed25519.pub"
  cp "$pub_src" "$target"
  chmod 0644 "$target"
  echo "host recipient updated: $target"
}

cmd_recipients() {
  mkdir -p "$host_key_dir"
  echo "recipient files:"
  if [ -f "$main_pub" ]; then
    echo "- secrets/keys/main.age.pub"
  fi
  if [ -f "$recovery_pub" ]; then
    echo "- secrets/keys/recovery.age.pub"
  fi
  find "$host_key_dir" -maxdepth 1 -type f -name '*.pub' -print |
    sed "s|^$repo_root/|- |" |
    sort

  echo ""
  echo "resolved age recipients:"
  collect_age_recipients | sed 's/^/- /'
}

cmd_rekey() {
  local recipients_csv file identity_file recipient
  local -a desired_recipients_raw desired_recipients current_recipients add_age rm_age rotate_cmd

  require_main_key
  require_main_pub
  ensure_sops_secret_path_rule
  recipients_csv="$(collect_age_recipients_csv)"
  IFS=, read -r -a desired_recipients_raw <<<"$recipients_csv"
  for recipient in "${desired_recipients_raw[@]}"; do
    [ -n "$recipient" ] && desired_recipients+=("$recipient")
  done
  identity_file="$(build_identity_file)"
  # shellcheck disable=SC2064
  trap "command rm -f -- '$identity_file'" RETURN

  export SOPS_AGE_KEY_FILE="$identity_file"

  while IFS= read -r file; do
    current_recipients=()
    add_age=()
    rm_age=()
    rotate_cmd=(run_sops rotate -i)

    while IFS= read -r recipient; do
      [ -n "$recipient" ] && current_recipients+=("$recipient")
    done < <(collect_file_age_recipients "$file")

    for recipient in "${desired_recipients[@]}"; do
      if [[ ! " ${current_recipients[*]} " =~ [[:space:]]${recipient}[[:space:]] ]]; then
        add_age+=("$recipient")
      fi
    done

    for recipient in "${current_recipients[@]}"; do
      if [[ ! " ${desired_recipients[*]} " =~ [[:space:]]${recipient}[[:space:]] ]]; then
        rm_age+=("$recipient")
      fi
    done

    if [ "${#add_age[@]}" -gt 0 ]; then
      rotate_cmd+=(--add-age "$(join_csv "${add_age[@]}")")
    fi

    if [ "${#rm_age[@]}" -gt 0 ]; then
      rotate_cmd+=(--rm-age "$(join_csv "${rm_age[@]}")")
    fi

    rotate_cmd+=("$file")
    "${rotate_cmd[@]}"
    echo "rekeyed: $file"
  done < <(find "$repo_root/secrets" -type f -name '*.yaml' | sort)

  trap - RETURN
  echo "rekey completed."
}

# Lost-key recovery. Both main and recovery private keys are gone, so the old
# secrets are unrecoverable; generate fresh keys and rebuild the secrets that
# must exist for a host to boot (passwords + aria2). Prompts for a new password
# interactively; password generation can never be silently automated.
cmd_reset() {
  local assume_yes=0
  if [ "${1:-}" = "--yes" ]; then
    assume_yes=1
    shift
  fi
  if [ "$#" -ne 0 ]; then
    echo "error: unexpected arguments for reset" >&2
    exit 2
  fi

  confirm_destructive_action \
    "RESET SOPS KEYS" \
    "warning: this generates brand new main + recovery age keys and rebuilds password/aria2 secrets. Old secrets stay unrecoverable. Back up the new recovery key afterwards." \
    "$assume_yes"

  mkdir -p "$key_dir" "$secrets_key_dir"

  # 1. New main + recovery key pairs (overwrite any stale/partial files).
  run_age_keygen -o "$main_key" >/dev/null
  chmod 0400 "$main_key"
  run_age_keygen -y "$main_key" >"$main_pub"
  run_age_keygen -o "$recovery_key" >/dev/null
  chmod 0400 "$recovery_key"
  run_age_keygen -y "$recovery_key" >"$recovery_pub"
  echo "generated new main + recovery keys"

  # 2. Point .sops.yaml at the new recipients.
  update_sops_anchors

  local recipients_csv
  recipients_csv="$(collect_age_recipients_csv)"

  # 3. Prompt for a new login password (used for both user and root) and hash it.
  local pw1="" pw2=""
  if [ ! -t 0 ]; then
    echo "error: reset needs an interactive terminal to read the new password" >&2
    exit 1
  fi
  while :; do
    printf 'New login password (user + root): ' >&2
    IFS= read -rs pw1
    printf '\n' >&2
    printf 'Repeat new password: ' >&2
    IFS= read -rs pw2
    printf '\n' >&2
    if [ -z "$pw1" ]; then
      echo "password must not be empty; try again" >&2
      continue
    fi
    if [ "$pw1" != "$pw2" ]; then
      echo "passwords did not match; try again" >&2
      continue
    fi
    break
  done

  local password_hash=""
  password_hash="$(printf '%s' "$pw1" | run_mkpasswd -m sha-512 -s)"
  pw1=""
  pw2=""
  if [ -z "$password_hash" ]; then
    echo "error: failed to generate password hash" >&2
    exit 1
  fi

  local user_secret="$repo_root/secrets/common/passwords/user-password.yaml"
  local root_secret="$repo_root/secrets/common/passwords/root-password.yaml"
  encrypt_yaml_to_target "$user_secret" "$recipients_csv" <<EOF_HASH
value: "$password_hash"
EOF_HASH
  encrypt_yaml_to_target "$root_secret" "$recipients_csv" <<EOF_HASH
value: "$password_hash"
EOF_HASH
  echo "rebuilt password secrets (user + root)"

  # 4. Regenerate the aria2 RPC token (its value is an opaque random secret).
  local aria2_secret="$repo_root/secrets/common/services/aria2-rpc-secret.yaml"
  local aria2_token=""
  aria2_token="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 48 || true)"
  if [ "${#aria2_token}" -ne 48 ]; then
    echo "error: failed to generate aria2 RPC token" >&2
    exit 1
  fi
  encrypt_yaml_to_target "$aria2_secret" "$recipients_csv" <<EOF_ARIA2
value: "$aria2_token"
EOF_ARIA2
  echo "regenerated aria2 RPC secret"

  echo ""
  echo "reset complete. next steps:"
  echo "  - BACK UP the new recovery key somewhere safe: $recovery_key"
  echo "  - after install, commit the updated .sops.yaml + secrets/ from the target"
}

# ── usage ─────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
usage: sops.sh <command> [args]

commands:
  init [--create|--rotate] [--yes]  Initialize/sync main age key
  reset [--yes]                  Lost-key recovery: new main+recovery keys,
                                 rewrite .sops.yaml, prompt new password,
                                 regenerate aria2 secret
  password-set <sha512-hash>     Encrypt password hash for user + root
  ssh-key-set                    Encrypt .keys/github_id_ed25519 via sops (SOPS_USER overrides target user)
  recovery-init [--force]        Create/update recovery key pair
  host-add <host> [pub-path]     Register host SSH public key as recipient
  recipients                     List current recipient key files
  rekey                          Re-encrypt all secrets/*.yaml
EOF
}

# ── dispatch ──────────────────────────────────────────────────
cmd="${1:-}"
if [ -z "$cmd" ]; then
  usage >&2
  exit 2
fi
shift

case "$cmd" in
init) cmd_init "$@" ;;
reset) cmd_reset "$@" ;;
password-set) cmd_password_set "$@" ;;
ssh-key-set) cmd_ssh_key_set "$@" ;;
recovery-init) cmd_recovery_init "$@" ;;
host-add) cmd_host_add "$@" ;;
recipients) cmd_recipients "$@" ;;
rekey) cmd_rekey "$@" ;;
-h | --help)
  usage
  exit 0
  ;;
*)
  echo "error: unknown command '$cmd'" >&2
  usage >&2
  exit 2
  ;;
esac
