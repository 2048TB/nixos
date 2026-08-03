# Justfile for minimal NixOS repository operations

default:
    @just --list

host := ""
repo := env_var_or_default("NIXOS_CONFIG_REPO", justfile_directory())
script_repo := justfile_directory()
nix_cmd := "nix --extra-experimental-features 'nix-command flakes'"
nixos_update_inputs := "nixpkgs nixpkgs-unstable home-manager nixos-hardware noctalia lanzaboote nix-gaming preservation disko sops-nix"

# ========== 私有 helpers ==========

[private]
nh-os action:
    @if [ -z "{{host}}" ]; then echo "error: 需要指定主机. 用法: just host=<hostname> {{action}}" >&2; exit 2; fi
    @flake_repo="$(bash "{{script_repo}}/nix/scripts/admin/print-flake-repo.sh" "{{repo}}")" && {{nix_cmd}} shell nixpkgs#nh -c nh os {{action}} "path:$flake_repo" -H "{{host}}"

[private]
_flake-check:
    @flake_repo="$(bash "{{script_repo}}/nix/scripts/admin/print-flake-repo.sh" "{{repo}}")" && {{nix_cmd}} flake check --all-systems --no-build "path:$flake_repo"

[private]
_guard-secrets-all:
    @NIXOS_CONFIG_REPO="{{repo}}" bash "{{script_repo}}/nix/scripts/admin/guard-secrets.sh" --all-tracked

# ========== 日常入口 ==========

update:
    @bash "{{script_repo}}/nix/scripts/admin/update-flake.sh" "{{repo}}"

upgrade:
    @if [ -z "{{host}}" ]; then echo "error: 需要指定主机. 用法: just host=zly upgrade" >&2; exit 2; fi
    @bash "{{script_repo}}/nix/scripts/admin/update-flake.sh" "{{repo}}" {{nixos_update_inputs}}
    @just repo="{{repo}}" host="{{host}}" switch

switch: (nh-os "switch")

clean:
    @{{nix_cmd}} shell nixpkgs#nh -c nh clean all --keep-since 30d --keep 15

# ========== 验证入口 ==========

self-check:
    @echo ">>> justfile"
    @just --list >/dev/null
    @echo ">>> bash syntax"
    @bash -n "{{script_repo}}"/nix/scripts/admin/*.sh "{{script_repo}}"/.githooks/pre-commit
    @echo ">>> shellcheck"
    @if command -v shellcheck >/dev/null 2>&1; then shellcheck "{{script_repo}}"/nix/scripts/admin/*.sh "{{script_repo}}"/.githooks/pre-commit; else echo "warning: shellcheck not found; skipping shellcheck" >&2; fi
    @echo ">>> shfmt"
    @if command -v shfmt >/dev/null 2>&1; then shfmt -i 2 -d "{{script_repo}}"/nix/scripts/admin/*.sh "{{script_repo}}"/.githooks/pre-commit; else echo "warning: shfmt not found; skipping shfmt" >&2; fi
    @echo ">>> format sanity"
    @NIXOS_CONFIG_REPO="{{repo}}" bash "{{script_repo}}/nix/scripts/admin/check-format-sanity.sh" --repo "{{repo}}"

validate-local:
    @just repo="{{repo}}" self-check
    @just repo="{{repo}}" _guard-secrets-all
    @just repo="{{repo}}" _flake-check
