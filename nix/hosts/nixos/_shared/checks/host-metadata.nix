# Host metadata + capability + role/desktop-metadata checks.
ctx:
let
  inherit (ctx)
    lib pkgs name cfg hostCfg
    hasExpectedGpuVendorsForMode hasExpectedDesktopMetadata hasExpectedHybridMetadata
    hasExpectedPrimaryDisplayCount hasExpectedGamingRoleMetadata hasGamingRole;
in
{
  "eval-${name}-host-kind" = pkgs.runCommand "eval-${name}-host-kind" { } ''
    case "${cfg.my.host.kind}" in
      workstation|server|vm) ;;
      *)
        echo "unexpected host kind: ${cfg.my.host.kind}" >&2
        exit 1
        ;;
    esac
    touch "$out"
  '';

  "eval-${name}-host-form-factor" = pkgs.runCommand "eval-${name}-host-form-factor" { } ''
    case "${cfg.my.host.formFactor}" in
      desktop|laptop|handheld|headless) ;;
      *)
        echo "unexpected host formFactor: ${cfg.my.host.formFactor}" >&2
        exit 1
        ;;
    esac
    touch "$out"
  '';

  "eval-${name}-host-tags" = pkgs.runCommand "eval-${name}-host-tags" { } ''
    test "${if lib.hasPrefix "[" (builtins.toJSON cfg.my.host.tags) then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-host-gpu-vendors" = pkgs.runCommand "eval-${name}-host-gpu-vendors" { } ''
    test "${if lib.hasPrefix "[" (builtins.toJSON cfg.my.host.gpuVendors) then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-host-gpu-mode-vendors" = pkgs.runCommand "eval-${name}-host-gpu-mode-vendors" { } ''
    if [ "${if hasExpectedGpuVendorsForMode then "1" else "0"}" != "1" ]; then
      echo "host ${name}: gpuMode=${hostCfg.gpuMode} is incompatible with gpuVendors=${builtins.toJSON hostCfg.gpuVendors}" >&2
      exit 1
    fi
    touch "$out"
  '';

  "eval-${name}-host-desktop-metadata" = pkgs.runCommand "eval-${name}-host-desktop-metadata" { } ''
    if [ "${if hasExpectedDesktopMetadata then "1" else "0"}" != "1" ]; then
      echo "host ${name}: desktopSession=${toString hostCfg.desktopSession} requires matching desktopProfile metadata, got ${hostCfg.desktopProfile}" >&2
      exit 1
    fi
    touch "$out"
  '';

  "eval-${name}-host-hybrid-gpu-metadata" = pkgs.runCommand "eval-${name}-host-hybrid-gpu-metadata" { } ''
    if [ "${if hasExpectedHybridMetadata then "1" else "0"}" != "1" ]; then
      echo "host ${name}: gpuMode=amd-nvidia-hybrid requires amdgpuBusId and nvidiaBusId" >&2
      exit 1
    fi
    touch "$out"
  '';

  "eval-${name}-host-primary-display-count" = pkgs.runCommand "eval-${name}-host-primary-display-count" { } ''
    if [ "${if hasExpectedPrimaryDisplayCount then "1" else "0"}" != "1" ]; then
      echo "host ${name}: displays must declare exactly one primary=true entry when display metadata exists" >&2
      exit 1
    fi
    touch "$out"
  '';

  "eval-${name}-host-role-metadata" = pkgs.runCommand "eval-${name}-host-role-metadata" { } ''
    if [ "${if hasExpectedGamingRoleMetadata then "1" else "0"}" != "1" ]; then
      echo "host ${name}: role 'gaming' requires desktopSession=true" >&2
      exit 1
    fi
    touch "$out"
  '';

  "eval-${name}-capability-kind" = pkgs.runCommand "eval-${name}-capability-kind" { } ''
    test "${if cfg.my.capabilities.isWorkstation == (cfg.my.host.kind == "workstation") then "1" else "0"}" = "1"
    test "${if cfg.my.capabilities.isServer == (cfg.my.host.kind == "server") then "1" else "0"}" = "1"
    test "${if cfg.my.capabilities.isVm == (cfg.my.host.kind == "vm") then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-capability-form-factor" = pkgs.runCommand "eval-${name}-capability-form-factor" { } ''
    test "${if cfg.my.capabilities.isDesktop == (cfg.my.host.formFactor == "desktop") then "1" else "0"}" = "1"
    test "${if cfg.my.capabilities.isLaptop == (cfg.my.host.formFactor == "laptop") then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-capability-desktop-session" = pkgs.runCommand "eval-${name}-capability-desktop-session" { } ''
    test "${if cfg.my.capabilities.hasDesktopSession == cfg.my.host.desktopSession then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-capability-gpu" = pkgs.runCommand "eval-${name}-capability-gpu" { } ''
    test "${if cfg.my.capabilities.hasAmdGpu == (builtins.elem "amd" cfg.my.host.gpuVendors) then "1" else "0"}" = "1"
    test "${if cfg.my.capabilities.hasIntelGpu == (builtins.elem "intel" cfg.my.host.gpuVendors) then "1" else "0"}" = "1"
    test "${if cfg.my.capabilities.hasNvidiaGpu == (builtins.elem "nvidia" cfg.my.host.gpuVendors) then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-capability-display-topology" = pkgs.runCommand "eval-${name}-capability-display-topology" { } ''
    test "${if cfg.my.capabilities.hasMultipleDisplays == ((builtins.length cfg.my.host.displays) > 1) then "1" else "0"}" = "1"
    test "${if cfg.my.capabilities.hasHiDpiDisplay == (builtins.any (display: let scale = display.scale or null; in if scale == null then false else scale > 1.0) cfg.my.host.displays) then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-steam-role-gating" = pkgs.runCommand "eval-${name}-steam-role-gating" { } ''
    test "${if (cfg.programs.steam.enable or false) == hasGamingRole then "1" else "0"}" = "1"
    test "${if (cfg.programs.steam.platformOptimizations.enable or false) == hasGamingRole then "1" else "0"}" = "1"
    touch "$out"
  '';
}
