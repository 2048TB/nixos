# Nix trust settings, credential hygiene (keyring/uid/ssh) and VPN integration.
# The VPN group only applies on hosts carrying the "vpn" role.
ctx:
let
  inherit (ctx)
    lib pkgs name cfg mainUser hasVpnRole
    hasExpectedAcceptFlakeConfig hasExpectedTrustedUsers hasExpectedTrustedSubstituters
    systemPackageNames homePackageNames preservedDirectoryPaths;
in
{
  "eval-${name}-user-uid-unset" = pkgs.runCommand "eval-${name}-user-uid-unset" { } ''
    test "${if (cfg.users.users.${mainUser}.uid or null) == null then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-group-gid-unset" = pkgs.runCommand "eval-${name}-group-gid-unset" { } ''
    test "${if (cfg.users.groups.${mainUser}.gid or null) == null then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-accept-flake-config" = pkgs.runCommand "eval-${name}-accept-flake-config" { } ''
    test "${if hasExpectedAcceptFlakeConfig then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-warn-dirty-enabled" = pkgs.runCommand "eval-${name}-warn-dirty-enabled" { } ''
    test "${if (cfg.nix.settings."warn-dirty" or true) then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-passwd-keyring-disabled" = pkgs.runCommand "eval-${name}-passwd-keyring-disabled" { } ''
    test "${if !(cfg.security.pam.services.passwd.enableGnomeKeyring or false) then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-trusted-users" = pkgs.runCommand "eval-${name}-trusted-users" { } ''
    test "${if hasExpectedTrustedUsers then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-trusted-substituters" = pkgs.runCommand "eval-${name}-trusted-substituters" { } ''
    test "${if hasExpectedTrustedSubstituters then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-ensure-user-ssh-dir-uses-store-tools" = pkgs.runCommand "eval-${name}-ensure-user-ssh-dir-uses-store-tools" { } ''
    script='${cfg.system.activationScripts.ensureUserSshDir.text or ""}'

    test -n "$script"
    printf '%s\n' "$script" | grep -F '${pkgs.coreutils}/bin/install -d -m 0700 -o ' >/dev/null
    if printf '%s\n' "$script" | grep -qE '(^|[[:space:];|&])install[[:space:]]+-d[[:space:]]+-m[[:space:]]+0700($|[[:space:];|&])'; then
      echo "ensureUserSshDir activation script should not invoke bare 'install'" >&2
      exit 1
    fi
    touch "$out"
  '';
}
  // lib.optionalAttrs hasVpnRole {
  "eval-${name}-mullvad-vpn-integration" = pkgs.runCommand "eval-${name}-mullvad-vpn-integration" { } ''
    test "${if cfg.services.resolved.enable or false then "1" else "0"}" = "1"
    test "${if cfg.services.mullvad-vpn.enable or false then "1" else "0"}" = "1"
    test "${if (cfg.networking.wg-quick.interfaces or { }) == { } then "1" else "0"}" = "1"
    test "${if cfg.system.activationScripts ? wireguardVpnActiveLinks then "1" else "0"}" = "0"
    test "${if lib.hasInfix "NIXOS_WG_KILLSWITCH" (cfg.networking.firewall.extraCommands or "") then "1" else "0"}" = "0"
    test "${if builtins.elem "vpn-list" systemPackageNames then "1" else "0"}" = "0"
    test "${if builtins.elem "vpn-switch" systemPackageNames then "1" else "0"}" = "0"
    test "${if builtins.elem "vpn-select" systemPackageNames then "1" else "0"}" = "0"
    test "${if builtins.elem "vpn-status" systemPackageNames then "1" else "0"}" = "0"
    test "${if builtins.elem "vpn-stop-all" systemPackageNames then "1" else "0"}" = "0"
    test "${if builtins.elem "wireguard-tools" systemPackageNames then "1" else "0"}" = "1"
    test "${builtins.unsafeDiscardStringContext (lib.getName cfg.services.mullvad-vpn.package)}" = "mullvad-vpn"
    test "${if builtins.elem "mullvad-vpn" systemPackageNames then "1" else "0"}" = "1"
    test "${if builtins.elem "mullvad-vpn" homePackageNames then "1" else "0"}" = "0"
    test "${if builtins.elem "/etc/mullvad-vpn" preservedDirectoryPaths then "1" else "0"}" = "1"
    test "${if builtins.elem "/var/cache/mullvad-vpn" preservedDirectoryPaths then "1" else "0"}" = "1"
    touch "$out"
  '';
}
