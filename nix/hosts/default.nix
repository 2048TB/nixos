# ============================================================================
# 全仓库唯一主机清单（单一事实源）
#
# 每台机器 = 这里的一个条目 + nix/hosts/<平台>/<主机名>/ 目录。
#
# 新增 NixOS 主机只需两步：
#   1. 复制下面任意一台的条目，改名并覆盖差异字段
#   2. 建目录 nix/hosts/nixos/<主机名>/
#      （hardware.nix / hardware-modules.nix / disko.nix，模板见该目录 README）
#
# 字段含义与允许值见 nix/hosts/README.md。字段写错不用担心：
# nix/modules/core/options.nix（types.enum）与 assertions.nix 会在
# `just validate-local` / `nix flake check` 时直接报错拦下。
# ============================================================================
let
  # 所有 NixOS 主机的共享默认值；每台主机用 `nixosDefaults // { … }` 覆盖差异项。
  nixosDefaults = {
    system = "x86_64-linux";

    # 身份 / 地区
    username = "z";
    timezone = "Asia/Shanghai";
    locale = "zh_CN.UTF-8";

    # 首次安装该主机时的 NixOS / Home Manager 版本；装好之后不要再改
    systemStateVersion = "25.11";
    homeStateVersion = "25.11";

    # 安装目标盘（会被 disko 清空重建）与 swapfile 大小
    diskDevice = "/dev/nvme0n1";
    swapSizeGb = 32;

    # 机器形态与桌面
    kind = "workstation"; # workstation / server / vm
    formFactor = "desktop"; # desktop / laptop / handheld / headless
    desktopSession = true; # false 表示无桌面（headless）
    desktopProfile = "niri"; # Linux 桌面当前仅支持 niri；无桌面时写 "none"
    tags = [ ]; # 可选："fingerprint-reader" / "docked"

    # 可选应用开关（默认全关，按主机打开）
    enableWpsOffice = false;
    enableZathura = false;
    enableSplayer = false;
    enableTelegramDesktop = false;
    enableLocalSend = false;
  };
in
{
  nixos = {
    # 笔记本：Intel CPU + NVIDIA 独显
    zky = nixosDefaults // {
      formFactor = "laptop";
      gpuVendors = [ "nvidia" ];
      gpuMode = "nvidia";
      nvidiaOpen = true; # Turing 及更新的显卡用开源内核模块
      resumeOffset = 2990172; # btrfs swapfile 休眠偏移，见 docs/README.md
      roles = [ "vpn" ];
      displays = [
        { name = "eDP-1"; primary = true; }
      ];
    };

    # 台式机：AMD CPU + AMD/NVIDIA 双显卡（PRIME hybrid）
    zly = nixosDefaults // {
      gpuVendors = [ "amd" "nvidia" ];
      gpuMode = "amd-nvidia-hybrid";
      # PRIME 总线 ID，NixOS 官方格式 PCI:<bus>@<domain>:<device>:<function>（十进制）。
      # 例：lspci 显示 0000:01:00.0 → 写 PCI:1@0:0:0
      amdgpuBusId = "PCI:18@0:0:0";
      nvidiaBusId = "PCI:1@0:0:0";
      nvidiaOpen = true;
      resumeOffset = 7182282;
      dockerMode = "rootless";
      roles = [ "gaming" "vpn" "virt" "container" ];
      enableWpsOffice = true;
      enableZathura = true;
      enableSplayer = true;
      enableTelegramDesktop = true;
      enableLocalSend = true;
      enableAntigravity = true;
      displays = [
        {
          name = "DP-1";
          match = "HKC OVERSEAS LIMITED MG27Q 0000000000001";
          width = 2560;
          height = 1440;
          refresh = 165;
          scale = 1.25;
          primary = true;
          workspaceSet = [ 1 2 3 4 5 6 7 8 9 ];
        }
      ];
    };

    # 台式机：纯 AMD（5950X + 6900XT），128G 内存，不启用休眠
    zl = nixosDefaults // {
      swapSizeGb = 128;
      gpuVendors = [ "amd" ];
      gpuMode = "amdgpu";
      dockerMode = "rootless";
      roles = [ "gaming" "vpn" "virt" "container" ];
      enableWpsOffice = true;
      enableZathura = true;
      enableSplayer = true;
      enableTelegramDesktop = true;
      enableLocalSend = true;
      displays = [
        {
          name = "DP-1";
          match = "HKC OVERSEAS LIMITED MG27Q 0000000000001";
          width = 2560;
          height = 1440;
          refresh = 165;
          scale = 1.25;
          primary = true;
          workspaceSet = [ 1 2 3 4 5 6 7 8 9 ];
        }
      ];
    };

    # 台式机：纯 AMD
    zzly = nixosDefaults // {
      gpuVendors = [ "amd" ];
      gpuMode = "amdgpu";
      resumeOffset = 1513128;
      roles = [ "vpn" ];
      displays = [ ];
    };
  };

  darwin = {
    # MacBook（Apple Silicon）
    zly-mac = {
      system = "aarch64-darwin";
      username = "z";
      timezone = "Asia/Shanghai";
      homeStateVersion = "25.11";
      kind = "workstation";
      formFactor = "laptop";
      desktopSession = true;
      desktopProfile = "aqua";
      tags = [ ];
      gpuVendors = [ ];
      displays = [ ];
    };
  };
}
