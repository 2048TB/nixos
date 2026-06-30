{ pkgs
, pkgsCherryStudio
, lib
, mylib
, myvars
, osConfig ? null
, ...
}:
let
  hostCfg = import ../base/resolve-host.nix { inherit myvars osConfig; };
  roleFlags = mylib.roleFlags hostCfg;
  hasDesktopSession = hostCfg.desktopSession or false;
  packageGroups = import ./package-groups.nix;
  packageGroupOrder =
    [
      "shared"
      "cli"
      "dev"
      "archive"
    ]
    ++ lib.optionals hasDesktopSession [
      "desktop"
      "media"
    ];
  inherit (roleFlags) enableSteam enableLibvirtd enableDocker;
  # App toggles stay in host vars and are consumed only by Home Manager.
  enableWpsOffice = myvars.enableWpsOffice or false;
  enableZathura = myvars.enableZathura or false;
  enableSplayer = myvars.enableSplayer or false;
  enableTelegramDesktop = myvars.enableTelegramDesktop or false;
  enableLocalSend = myvars.enableLocalSend or false;
  enableAntigravity = myvars.enableAntigravity or false;
  wpsOfficePackage = pkgs.wpsoffice;

  # 仅在混合显卡（amd-nvidia-hybrid）时安装 GPU 加速相关软件
  gpuChoice = hostCfg.gpuMode or "modesetting";
  isHybridGpu = gpuChoice == "amd-nvidia-hybrid";
  hashcatPkg = pkgs.hashcat or null;
  hybridPackages = lib.optionals isHybridGpu (
    lib.optional (hashcatPkg != null) hashcatPkg
  );

  cherryStudioPackage = pkgsCherryStudio.cherry-studio or null;
  gamingPackages = with pkgs; [
    mangohud
    goverlay # MangoHud / vkBasalt 图形配置工具
    vkbasalt # Vulkan 后处理层（CAS 锐化、FXAA 等）
    umu-launcher
    bbe
    wineWowPackages.stable # 原：stagingFull（避免触发本地编译）
    winetricks
    protonplus
    heroic # Epic Games / GOG 启动器
    # GPU 诊断工具（仅 gaming 主机需要）
    libva-utils
    vdpauinfo
    nvitop
  ];
  virtualisationPackages = with pkgs; [
    virt-viewer
    spice-gtk
    qemu_kvm
  ];
  dockerPackages = with pkgs; [
    docker-compose # Docker 编排工具
    dive # Docker 镜像分析
    lazydocker # Docker TUI 管理器
  ];
  # 仅将 MinGW 交叉编译器的可执行文件加入 user profile，避免与本机 gcc 的文档路径冲突告警。
  mingwToolchainBinOnly = pkgs.buildEnv {
    name = "mingw-w64-toolchain-bin-only";
    paths = [ pkgs.pkgsCross.mingwW64.stdenv.cc ];
    pathsToLink = [ "/bin" ];
  };
  # clang-wrapper 会提供 cc/c++/cpp 通用别名，和 gcc-wrapper 在 HM buildEnv 中冲突。
  # 这里保留 clang/clang++ 等专用入口，只移除通用兼容名，避免牺牲任一工具链。
  clangWithoutCompatAliases = pkgs.symlinkJoin {
    name = "clang-without-compat-aliases";
    paths = [ pkgs.clang ];
    postBuild = ''
      rm -f "$out/bin/cc" "$out/bin/c++" "$out/bin/cpp"
    '';
  };
  devToolchainPackages = [
    pkgs.neovim
    mingwToolchainBinOnly
    clangWithoutCompatAliases
    pkgs.gcc
  ];

  basePackageNames = lib.flatten (
    map (groupName: packageGroups.${groupName}) packageGroupOrder
  );
  basePackageSelection = mylib.resolvePackagesByName pkgs basePackageNames;
  basePackages = basePackageSelection.packages ++ lib.optional (cherryStudioPackage != null) cherryStudioPackage;
in
{
  warnings = lib.optionals (basePackageSelection.skippedNames != [ ]) [
    "Linux skipped unavailable packages: ${lib.concatStringsSep ", " basePackageSelection.skippedNames}"
  ];

  home = {
    packages = basePackages
      ++ devToolchainPackages
      ++ hybridPackages
      ++ lib.optional (hasDesktopSession && enableLocalSend) pkgs.localsend
      ++ lib.optional (hasDesktopSession && enableZathura) pkgs.zathura
      ++ lib.optional (hasDesktopSession && enableSplayer) pkgs.splayer
      ++ lib.optional (hasDesktopSession && enableTelegramDesktop) pkgs.telegram-desktop
      ++ lib.optional (hasDesktopSession && enableWpsOffice) wpsOfficePackage
      ++ lib.optional (hasDesktopSession && enableAntigravity) pkgs.antigravity
      ++ lib.optionals enableSteam gamingPackages
      ++ lib.optionals enableLibvirtd virtualisationPackages
      ++ lib.optionals enableDocker dockerPackages;
  };
}
