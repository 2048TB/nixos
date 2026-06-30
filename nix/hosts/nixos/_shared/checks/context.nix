# Shared context for the per-host NixOS check groups.
# Computes every derived value the split check files under ./checks/ consume,
# so each group file stays a pure function of this attrset.
{ lib
, mylib
, pkgs
, name
, mainUser
, nixosSystem
, expectedLuksName ? null
, expectedVideoDrivers ? null
, expectedResumeOffset ? null
, expectedHostname ? name
, expectedDockerMode ? null
, expectedTrustedUsers ? null
, expectedTrustedSubstituters ? null
, expectedKvmModules ? null
, cpuVendor ? null
, ...
}:
let
  nixCache = import ../../../../lib/nix-cache.nix;
  inherit (nixCache) cacheSubstituters trustedUsers;
  cfg = nixosSystem.config;
  hostCfg = cfg.my.host;
  hostRoles = hostCfg.roles or [ ];
  hasGamingRole = builtins.elem "gaming" hostRoles;
  secureBootEnabled = hostCfg.secureBoot.enable or false;
  hasDesktopSession = cfg.my.capabilities.hasDesktopSession or false;
  hasGpuVendor = vendor: builtins.elem vendor hostCfg.gpuVendors;
  hasExpectedGpuVendorsForMode =
    if hostCfg.gpuMode == "none" then hostCfg.gpuVendors == [ ]
    else if hostCfg.gpuMode == "modesetting" then !(hasGpuVendor "amd") && !(hasGpuVendor "nvidia")
    else if hostCfg.gpuMode == "amdgpu" then (hasGpuVendor "amd") && !(hasGpuVendor "nvidia")
    else if hostCfg.gpuMode == "nvidia" then (hasGpuVendor "nvidia") && !(hasGpuVendor "amd")
    else if hostCfg.gpuMode == "amd-nvidia-hybrid" then (hasGpuVendor "amd") && (hasGpuVendor "nvidia")
    else false;
  declaredPrimaryDisplays = builtins.filter (display: display.primary or false) hostCfg.displays;
  hasExpectedPrimaryDisplayCount =
    hostCfg.displays == [ ] || builtins.length declaredPrimaryDisplays == 1;
  hasExpectedDesktopMetadata =
    (hostCfg.desktopSession && hostCfg.desktopProfile != "none")
    || (!hostCfg.desktopSession && hostCfg.desktopProfile == "none");
  hasExpectedHybridMetadata =
    hostCfg.gpuMode != "amd-nvidia-hybrid"
    || (hostCfg.amdgpuBusId != null && hostCfg.nvidiaBusId != null);
  hasExpectedGamingRoleMetadata =
    !hasGamingRole || hostCfg.desktopSession;
  usesNiri = hostCfg.desktopProfile == "niri";
  resolvedExpectedLuksName =
    if expectedLuksName != null then expectedLuksName else hostCfg.luksName;
  resolvedExpectedResumeOffset =
    if expectedResumeOffset != null then expectedResumeOffset else hostCfg.resumeOffset or null;
  resolvedExpectedTrustedUsers =
    if expectedTrustedUsers != null then expectedTrustedUsers else trustedUsers;
  resolvedExpectedVideoDrivers =
    if expectedVideoDrivers != null then
      expectedVideoDrivers
    else if !hasDesktopSession then
      null
    else if hostCfg.gpuMode == "nvidia" then
      [ "nvidia" ]
    else if hostCfg.gpuMode == "amdgpu" then
      [ "amdgpu" ]
    else if hostCfg.gpuMode == "amd-nvidia-hybrid" then
      [ "nvidia" "amdgpu" ]
    else
      [ "modesetting" ];
  resolvedExpectedDockerMode =
    if expectedDockerMode != null then
      expectedDockerMode
    else if builtins.elem "container" hostRoles then
      hostCfg.dockerMode or "rootless"
    else
      "disabled";

  resolvedExpectedKvmModules =
    if expectedKvmModules != null then expectedKvmModules
    else if cpuVendor != null then mylib.kvmModulesForVendor cpuVendor
    else null;
  expectedDisplayManagerSessionNames = lib.optionals hasDesktopSession [
    hostCfg.desktopProfile
  ];
  hasVpnRole = builtins.elem "vpn" hostRoles;
  hmCfg = cfg.home-manager.users.${mainUser};
  expectedHome = "/home/${mainUser}";
  preservedDirectories = cfg.preservation.preserveAt."/persistent".directories or [ ];
  preservedDirectoryPaths = map (entry: entry.directory or entry) preservedDirectories;

  getNames = pkgList: lib.unique (map (pkg: builtins.unsafeDiscardStringContext (lib.getName pkg)) pkgList);
  excludeAllowed = allowed: names: builtins.filter (n: !(builtins.elem n allowed)) names;

  allSystemPackageOutPaths = map (pkg: pkg.outPath) cfg.environment.systemPackages;
  systemPackageOutPaths = lib.unique allSystemPackageOutPaths;
  homePackageOutPaths = lib.unique (map (pkg: pkg.outPath) hmCfg.home.packages);
  systemHomeOverlapOutPaths = lib.intersectLists systemPackageOutPaths homePackageOutPaths;
  systemHomeOverlapPkgs =
    lib.filter (pkg: builtins.elem pkg.outPath systemHomeOverlapOutPaths) cfg.environment.systemPackages;
  systemHomeOverlapNames = getNames systemHomeOverlapPkgs;
  systemPackageNames = getNames cfg.environment.systemPackages;
  homePackageNames = getNames hmCfg.home.packages;
  homeZellijPackages = builtins.filter (pkg: lib.getName pkg == "zellij") hmCfg.home.packages;
  homeZellijOutPaths = map (pkg: pkg.outPath) homeZellijPackages;
  expectedZellijOutPath = pkgs.unstable.zellij.outPath;
  hasExpectedZellijPackage =
    pkgs.zellij.outPath == expectedZellijOutPath
    && homeZellijOutPaths == [ expectedZellijOutPath ];
  unexpectedOverlapByName = lib.intersectLists systemPackageNames homePackageNames;
  outPathKey = builtins.unsafeDiscardStringContext;
  systemDuplicateOutPaths =
    builtins.attrNames (
      lib.filterAttrs
        (_outPath: instances: builtins.length instances > 1)
        (builtins.groupBy outPathKey allSystemPackageOutPaths)
    );
  systemDuplicatePkgs =
    lib.filter
      (pkg: builtins.elem (outPathKey pkg.outPath) systemDuplicateOutPaths)
      cfg.environment.systemPackages;
  systemDuplicateNames = getNames systemDuplicatePkgs;
  # 当前各主机（按 outPath 语义）真实出现的重复项白名单。
  # 保持最小集合；新增项前应先定位上游来源并记录理由。
  allowedSystemDuplicateNames = [
    "dosfstools" # 磁盘/恢复工具链的交叉依赖
    "fuse" # 用户态文件系统依赖链
    "gnome-keyring" # 桌面与 secrets 依赖链
    "iptables" # firewall/container 栈中的兼容工具
    "less" # 显式工具与传递依赖并存
    "niri" # compositor 依赖链与显式声明并存
    "shadow" # 用户管理工具链依赖
    "zsh" # 默认 shell 与显式工具链并存
  ];
  unexpectedSystemDuplicateNames = excludeAllowed allowedSystemDuplicateNames systemDuplicateNames;
  # 当前各主机 system/home 真实重叠项白名单（按 outPath 与 by-name 双重检查）。
  # 保持最小集合，避免“误放行”掩盖新增漂移。
  allowedSystemHomeOverlapNames = [
    "man-db"
    "nix-zsh-completions"
    "shared-mime-info"
    "xdg-desktop-portal"
    "xdg-desktop-portal-gtk"
    "zsh"
  ];
  unexpectedSystemHomeOverlapNames = excludeAllowed allowedSystemHomeOverlapNames systemHomeOverlapNames;
  unexpectedOverlapByNameFiltered = excludeAllowed allowedSystemHomeOverlapNames unexpectedOverlapByName;

  expectedResumeKernelParam =
    if resolvedExpectedResumeOffset == null then null else "resume_offset=${toString resolvedExpectedResumeOffset}";
  expectsHibernate = resolvedExpectedResumeOffset != null;
  hasResumeKernelParam =
    builtins.any (param: lib.hasPrefix "resume=" param) cfg.boot.kernelParams;
  hasExpectedResumeKernelParam =
    if expectedResumeKernelParam == null then true else builtins.elem expectedResumeKernelParam cfg.boot.kernelParams;
  hasExpectedResumeKernelParamState =
    if expectsHibernate then hasResumeKernelParam else !hasResumeKernelParam;
  hasExpectedResumeOffsetKernelParamState =
    if expectsHibernate then hasExpectedResumeKernelParam else !(
      builtins.any (param: lib.hasPrefix "resume_offset=" param) cfg.boot.kernelParams
    );
  hasExpectedResumeDeviceState =
    if expectsHibernate then (cfg.boot.resumeDevice or "") != "" else (cfg.boot.resumeDevice or "") == "";
  hasExpectedAcceptFlakeConfig =
    !(cfg.nix.settings.accept-flake-config or false);
  resolvedExpectedTrustedSubstituters =
    if expectedTrustedSubstituters != null then
      expectedTrustedSubstituters
    else
      cacheSubstituters;
  sortedTrustedUsers = builtins.sort builtins.lessThan (cfg.nix.settings.trusted-users or [ ]);
  sortedExpectedTrustedUsers = builtins.sort builtins.lessThan resolvedExpectedTrustedUsers;
  hasExpectedTrustedUsers = sortedTrustedUsers == sortedExpectedTrustedUsers;
  sortedTrustedSubstituters = builtins.sort builtins.lessThan (cfg.nix.settings.trusted-substituters or [ ]);
  sortedExpectedTrustedSubstituters =
    if resolvedExpectedTrustedSubstituters == null then [ ]
    else builtins.sort builtins.lessThan resolvedExpectedTrustedSubstituters;
  hasExpectedTrustedSubstituters =
    if resolvedExpectedTrustedSubstituters == null then true
    else sortedTrustedSubstituters == sortedExpectedTrustedSubstituters;
  actualDockerMode =
    if (cfg.virtualisation.docker.rootless.enable or false)
    then "rootless"
    else if (cfg.virtualisation.docker.enable or false)
    then "rootful"
    else "disabled";
  hasExpectedDockerMode = actualDockerMode == resolvedExpectedDockerMode;
  expectsRootlessDockerLinger = resolvedExpectedDockerMode == "rootless";
  hasExpectedRootlessDockerLinger =
    if expectsRootlessDockerLinger
    then (cfg.users.users.${mainUser}.linger or false)
    else true;
  actualKvmModules = builtins.filter (m: lib.hasPrefix "kvm-" m) cfg.boot.kernelModules;
  sessionVariables = hmCfg.home.sessionVariables or { };
  hasGlobalMlRuntimeLibraryPath = builtins.hasAttr "LD_LIBRARY_PATH" sessionVariables;
  hasGlobalOpenSslBuildEnv =
    builtins.any
      (name': builtins.hasAttr name' sessionVariables)
      [
        "OPENSSL_INCLUDE_DIR"
        "OPENSSL_LIB_DIR"
        "OPENSSL_DIR"
      ];
  miseAutoUpgradeEnabled = cfg.my.host.miseAutoUpgrade or false;
  aria2EnableRpc = cfg.my.host.aria2.enableRpc or true;
  aria2RpcSecretPath = cfg.my.host.aria2.rpcSecretPath or mylib.hostMetaSchema.defaultAria2RpcSecretPath;
  hasMiseUpgradeTimer = hmCfg.systemd.user.timers ? mise-upgrade;
  tmpfilesRules = cfg.systemd.tmpfiles.rules or [ ];
  hasBinBashTmpfilesLink =
    builtins.elem "d /bin 0755 root root -" tmpfilesRules
    && builtins.elem "L+ /bin/bash - - - - /run/current-system/sw/bin/bash" tmpfilesRules;
  hasLegacyBinBashActivation = cfg.system.activationScripts ? binbash;
  swapfileResumeCheckEnabled = cfg.systemd.services ? swapfile-resume-check;
  niriConfigSource = hmCfg.xdg.configFile."niri/config.kdl".source or null;
  codeWrapperSource = hmCfg.home.file.".local/bin/code".source or null;
  antigravityWrapperSource = hmCfg.home.file.".local/bin/antigravity".source or null;
  hasNoctaliaConfigEntry = hmCfg.xdg.configFile ? "noctalia";
  noctaliaConfigSource =
    if hasNoctaliaConfigEntry then hmCfg.xdg.configFile."noctalia".source else null;
  noctaliaConfigSourcePath =
    if noctaliaConfigSource == null then "" else toString noctaliaConfigSource;
  noctaliaRuntimeConfigDir = "${hmCfg.home.homeDirectory}/.local/state/noctalia/config";
  hasNoctaliaSeedActivation = hmCfg.home.activation ? seedNoctaliaConfig;
  noctaliaSeedActivation =
    if hasNoctaliaSeedActivation then hmCfg.home.activation.seedNoctaliaConfig else null;
  noctaliaSeedActivationData =
    if noctaliaSeedActivation == null then "" else noctaliaSeedActivation.data;
  hasNoctaliaSeedActivationOrder =
    hasNoctaliaSeedActivation
    && builtins.elem "writeBoundary" noctaliaSeedActivation.after
    && builtins.elem "linkGeneration" noctaliaSeedActivation.before;
  hasNoctaliaRuntimeConfigPersistence =
    !usesNiri
    || (
      hasNoctaliaConfigEntry
      && hasNoctaliaSeedActivation
      && hasNoctaliaSeedActivationOrder
      && lib.hasInfix noctaliaRuntimeConfigDir noctaliaSeedActivationData
      && lib.hasInfix "${hostCfg.configRepoPath}/nix/home/configs/noctalia" noctaliaSeedActivationData
    );

  mkNonEmptyCheck = name': items: msg:
    pkgs.runCommand name' { } ''
      if [ ${toString (builtins.length items)} -ne 0 ]; then
        echo "${msg}: ${lib.concatStringsSep ", " items}" >&2
        exit 1
      fi
      touch "$out"
    '';
in
{
  inherit
    lib pkgs name mainUser cfg hostCfg expectedHostname expectedHome
    hasGamingRole secureBootEnabled hasDesktopSession hasVpnRole usesNiri
    hasExpectedGpuVendorsForMode hasExpectedPrimaryDisplayCount
    hasExpectedDesktopMetadata hasExpectedHybridMetadata hasExpectedGamingRoleMetadata
    resolvedExpectedLuksName resolvedExpectedVideoDrivers resolvedExpectedKvmModules
    expectedDisplayManagerSessionNames hmCfg preservedDirectoryPaths
    systemPackageNames homePackageNames hasExpectedZellijPackage
    unexpectedSystemHomeOverlapNames unexpectedOverlapByNameFiltered unexpectedSystemDuplicateNames
    expectsHibernate hasExpectedResumeKernelParamState hasExpectedResumeOffsetKernelParamState
    hasExpectedResumeDeviceState hasExpectedAcceptFlakeConfig
    hasExpectedTrustedUsers hasExpectedTrustedSubstituters
    hasExpectedDockerMode hasExpectedRootlessDockerLinger actualKvmModules
    hasGlobalMlRuntimeLibraryPath hasGlobalOpenSslBuildEnv
    miseAutoUpgradeEnabled aria2EnableRpc aria2RpcSecretPath hasMiseUpgradeTimer
    tmpfilesRules hasBinBashTmpfilesLink hasLegacyBinBashActivation swapfileResumeCheckEnabled
    niriConfigSource codeWrapperSource antigravityWrapperSource
    hasNoctaliaConfigEntry noctaliaConfigSourcePath noctaliaRuntimeConfigDir
    hasNoctaliaRuntimeConfigPersistence
    mkNonEmptyCheck
    ;
}
