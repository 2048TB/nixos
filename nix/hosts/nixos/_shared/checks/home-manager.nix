# Home Manager user-level checks (home dir, aria2, zellij, mise, noctalia, zsh)
# plus the system/home package overlap and duplicate guards.
ctx:
let
  inherit (ctx)
    pkgs name cfg hmCfg expectedHome expectedHostname
    aria2EnableRpc aria2RpcSecretPath hasMiseUpgradeTimer miseAutoUpgradeEnabled
    hasExpectedZellijPackage hasGlobalMlRuntimeLibraryPath hasGlobalOpenSslBuildEnv
    usesNiri hasNoctaliaConfigEntry noctaliaConfigSourcePath noctaliaRuntimeConfigDir
    hasNoctaliaRuntimeConfigPersistence mkNonEmptyCheck
    unexpectedSystemHomeOverlapNames unexpectedOverlapByNameFiltered unexpectedSystemDuplicateNames;
in
{
  "eval-${name}-hostname" = pkgs.runCommand "eval-${name}-hostname" { } ''
    test "${cfg.networking.hostName}" = "${name}"
    touch "$out"
  '';

  "eval-${name}-home-directory" = pkgs.runCommand "eval-${name}-home-directory" { } ''
    test "${hmCfg.home.homeDirectory}" = "${expectedHome}"
    touch "$out"
  '';

  "eval-${name}-hostname-env" = pkgs.runCommand "eval-${name}-hostname-env" { } ''
    test "${hmCfg.home.sessionVariables.NIX_HOSTNAME or ""}" = "${expectedHostname}"
    touch "$out"
  '';

  "eval-${name}-noctalia-runtime-config-persistence" = pkgs.runCommand "eval-${name}-noctalia-runtime-config-persistence" { } ''
    if [ "${if usesNiri then "1" else "0"}" != "1" ]; then
      touch "$out"
      exit 0
    fi

    if [ "${if hasNoctaliaConfigEntry then "1" else "0"}" != "1" ]; then
      echo "missing Home Manager xdg.configFile.noctalia entry" >&2
      exit 1
    fi

    if [ ! -L "${noctaliaConfigSourcePath}" ]; then
      echo "Noctalia config source is not an out-of-store symlink: ${noctaliaConfigSourcePath}" >&2
      exit 1
    fi

    actual_source="$(${pkgs.coreutils}/bin/readlink "${noctaliaConfigSourcePath}")"
    expected_source="${noctaliaRuntimeConfigDir}"
    if [ "$actual_source" != "$expected_source" ]; then
      echo "Noctalia config source points to $actual_source, expected $expected_source" >&2
      exit 1
    fi

    if [ "${if hasNoctaliaRuntimeConfigPersistence then "1" else "0"}" != "1" ]; then
      echo "Noctalia runtime config persistence activation is missing, misordered, or points at the wrong seed/runtime path" >&2
      exit 1
    fi

    touch "$out"
  '';

  "eval-${name}-aria2-rpc-config" = pkgs.runCommand "eval-${name}-aria2-rpc-config" { } ''
    test "${if (hmCfg.programs.aria2.enable or false) then "1" else "0"}" = "1"
    test "${if (hmCfg.programs.aria2.settings."enable-rpc" or false) == aria2EnableRpc then "1" else "0"}" = "1"
    if [ "${if aria2EnableRpc then "1" else "0"}" = "1" ]; then
      test "${toString (hmCfg.programs.aria2.settings."rpc-listen-port" or 0)}" = "6800"
      test "${if (hmCfg.programs.aria2.settings."rpc-listen-all" or false) then "1" else "0"}" = "0"
      test "${if (hmCfg.programs.aria2.settings."rpc-allow-origin-all" or false) then "1" else "0"}" = "1"
    else
      test "${if builtins.hasAttr "rpc-listen-port" hmCfg.programs.aria2.settings then "1" else "0"}" = "0"
      test "${if builtins.hasAttr "rpc-listen-all" hmCfg.programs.aria2.settings then "1" else "0"}" = "0"
      test "${if builtins.hasAttr "rpc-allow-origin-all" hmCfg.programs.aria2.settings then "1" else "0"}" = "0"
    fi
    touch "$out"
  '';

  "eval-${name}-aria2-user-service" = pkgs.runCommand "eval-${name}-aria2-user-service" { } ''
    test "${if hmCfg.systemd.user.services ? aria2 then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-aria2-user-service-scripts-use-store-tools" = pkgs.runCommand "eval-${name}-aria2-user-service-scripts-use-store-tools" { } ''
    prepare_script="${hmCfg.systemd.user.services.aria2.Service.ExecStartPre or ""}"
    start_script="${builtins.elemAt (hmCfg.systemd.user.services.aria2.Service.ExecStart or [ "" ]) 0}"

    test -n "$prepare_script"
    test -f "$prepare_script"
    test -n "$start_script"
    test -f "$start_script"

    grep -F '${pkgs.coreutils}/bin/mkdir' "$prepare_script" >/dev/null
    grep -F '${pkgs.coreutils}/bin/touch' "$prepare_script" >/dev/null
    if [ "${if aria2EnableRpc then "1" else "0"}" = "1" ]; then
      grep -F '${pkgs.coreutils}/bin/cat' "$start_script" >/dev/null
      grep -F 'aria2 RPC is enabled but secret is not readable: ${aria2RpcSecretPath}' "$start_script" >/dev/null
      grep -F 'exit 1' "$start_script" >/dev/null
      grep -F -- '--rpc-secret=$rpc_secret' "$start_script" >/dev/null
    else
      if grep -Fq -- '--rpc-secret' "$start_script"; then
        echo "aria2 RPC is disabled but start script still passes --rpc-secret" >&2
        exit 1
      fi
    fi
    touch "$out"
  '';

  "eval-${name}-session-env-no-global-ml-runtime-libs" = pkgs.runCommand "eval-${name}-session-env-no-global-ml-runtime-libs" { } ''
    test "${if !hasGlobalMlRuntimeLibraryPath then "1" else "0"}" = "1"
    test "${if !hasGlobalOpenSslBuildEnv then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-zellij-uses-unstable" = pkgs.runCommand "eval-${name}-zellij-uses-unstable" { } ''
    test "${if hasExpectedZellijPackage then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-mise-upgrade-auto-opt-in" = pkgs.runCommand "eval-${name}-mise-upgrade-auto-opt-in" { } ''
    test "${if hasMiseUpgradeTimer == miseAutoUpgradeEnabled then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-system-zsh-enabled" = pkgs.runCommand "eval-${name}-system-zsh-enabled" { } ''
    test "${if cfg.programs.zsh.enable or false then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-system-home-package-overlap" = mkNonEmptyCheck
    "eval-${name}-system-home-package-overlap"
    unexpectedSystemHomeOverlapNames
    "Unexpected system/home package overlaps";

  "eval-${name}-system-home-package-overlap-by-name" = mkNonEmptyCheck
    "eval-${name}-system-home-package-overlap-by-name"
    unexpectedOverlapByNameFiltered
    "Unexpected system/home package overlaps by name";

  "eval-${name}-system-package-duplicates" = mkNonEmptyCheck
    "eval-${name}-system-package-duplicates"
    unexpectedSystemDuplicateNames
    "Unexpected duplicate packages in environment.systemPackages";
}
