# Boot, impermanence, LUKS, Secure Boot and hibernation/swap storage checks.
ctx:
let
  inherit (ctx)
    pkgs name cfg hostCfg mainUser secureBootEnabled
    resolvedExpectedLuksName tmpfilesRules
    hasBinBashTmpfilesLink hasLegacyBinBashActivation
    expectsHibernate hasExpectedResumeDeviceState
    hasExpectedResumeKernelParamState hasExpectedResumeOffsetKernelParamState
    swapfileResumeCheckEnabled;
in
{
  "eval-${name}-impermanence-flag" = pkgs.runCommand "eval-${name}-impermanence-flag" { } ''
    test "${if cfg.preservation.enable then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-luks-name" = pkgs.runCommand "eval-${name}-luks-name" { } ''
    test "${cfg.my.host.luksName}" = "${resolvedExpectedLuksName}"
    touch "$out"
  '';

  "eval-${name}-config-repo-path" = pkgs.runCommand "eval-${name}-config-repo-path" { } ''
    test -n "${hostCfg.configRepoPath}"
    test "${cfg.programs.nh.flake}" = "${hostCfg.configRepoPath}"
    test "${if builtins.elem "d ${hostCfg.configRepoPath} 0755 ${mainUser} ${mainUser} -" tmpfilesRules then "1" else "0"}" = "1"
    test "${if builtins.elem "L+ /etc/nixos - - - - ${hostCfg.configRepoPath}" tmpfilesRules then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-binbash-tmpfiles" = pkgs.runCommand "eval-${name}-binbash-tmpfiles" { } ''
    test "${if hasBinBashTmpfilesLink then "1" else "0"}" = "1"
    test "${if !hasLegacyBinBashActivation then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-secure-boot-gating" = pkgs.runCommand "eval-${name}-secure-boot-gating" { } ''
    test "${if (cfg.boot.lanzaboote.enable or false) == secureBootEnabled then "1" else "0"}" = "1"
    if [ "${if secureBootEnabled then "1" else "0"}" = "0" ]; then
      test "${if cfg.boot.loader.systemd-boot.enable or false then "1" else "0"}" = "1"
    fi
    touch "$out"
  '';

  "eval-${name}-resume-device" = pkgs.runCommand "eval-${name}-resume-device" { } ''
    if [ "${if expectsHibernate then "1" else "0"}" = "1" ]; then
      test "${cfg.boot.resumeDevice or ""}" = "/dev/mapper/${resolvedExpectedLuksName}"
    else
      test "${cfg.boot.resumeDevice or ""}" = ""
    fi
    test "${if hasExpectedResumeDeviceState then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-resume-kernel-param" = pkgs.runCommand "eval-${name}-resume-kernel-param" { } ''
    test "${if hasExpectedResumeKernelParamState then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-resume-offset-kernel-param" = pkgs.runCommand "eval-${name}-resume-offset-kernel-param" { } ''
    test "${if hasExpectedResumeOffsetKernelParamState then "1" else "0"}" = "1"
    touch "$out"
  '';

  "eval-${name}-swapfile-resume-check-service" = pkgs.runCommand "eval-${name}-swapfile-resume-check-service" { } ''
    if [ "${if expectsHibernate then "1" else "0"}" = "1" ]; then
      test "${if swapfileResumeCheckEnabled then "1" else "0"}" = "1"
    else
      test "${if !swapfileResumeCheckEnabled then "1" else "0"}" = "1"
    fi
    touch "$out"
  '';

  "eval-${name}-swap-device" = pkgs.runCommand "eval-${name}-swap-device" { } ''
    test "${cfg.fileSystems."/swap".device}" = "/dev/mapper/${resolvedExpectedLuksName}"
    touch "$out"
  '';
}
