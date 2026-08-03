# NixOS eval-test：防止 headless 主机泄漏 GUI 栈。
# 取 zly 的清单条目改造成 headless 变体，验证桌面服务/GUI 配置/GUI 包
# 全部随 desktopSession=false 关闭。每个属性是一个布尔断言，
# 后续被转成 check derivation。
{ lib, mylib, args }:
let
  headlessHostCtx = mylib.mkNixosHost (args // {
    name = "zly";
    hostMyvars = mylib.hosts.nixos.zly // {
      kind = "server";
      formFactor = "headless";
      desktopSession = false;
      desktopProfile = "none";
      tags = [ ];
      gpuVendors = [ ];
      gpuMode = "none";
      displays = [ ];
      roles = [ ];
      enableWpsOffice = false;
      enableZathura = false;
      enableSplayer = false;
      enableTelegramDesktop = false;
      enableLocalSend = false;
      enableAntigravity = false;
    };
  });
  headlessHmCfg = headlessHostCtx.nixosSystem.config.home-manager.users.${headlessHostCtx.mainUser};
  headlessServices = headlessHmCfg.systemd.user.services or { };
  headlessConfigFiles = headlessHmCfg.xdg.configFile or { };
  headlessPackageNames = map (pkg: builtins.unsafeDiscardStringContext (lib.getName pkg)) headlessHmCfg.home.packages;
  unexpectedHeadlessGuiPackages = lib.intersectLists
    headlessPackageNames
    [
      "google-chrome"
      "vscode"
      "nautilus"
      "ghostty"
      "foot"
      "fuzzel"
      "pavucontrol"
    ];
in
{
  headless-home-no-gui-services =
    !(builtins.hasAttr "playerctld" headlessServices)
    && !(builtins.hasAttr "udiskie" headlessServices)
    && !(builtins.hasAttr "polkit-gnome-authentication-agent-1" headlessServices)
    && !(builtins.hasAttr "aria2" headlessServices);
  headless-home-no-noctalia =
    !(headlessHmCfg.programs.noctalia-shell.enable or false);
  headless-home-no-portal =
    !(headlessHmCfg.xdg.portal.enable or false);
  headless-home-no-niri-noctalia-configs =
    !(builtins.hasAttr "niri/config.kdl" headlessConfigFiles)
    && !(builtins.hasAttr "niri/outputs.kdl" headlessConfigFiles)
    && !(builtins.hasAttr "noctalia" headlessConfigFiles);
  headless-home-no-gui-packages =
    unexpectedHeadlessGuiPackages == [ ];
}
