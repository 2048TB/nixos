{ lib, pkgs, config, mainUser, mylib, myvars, ... }:
let
  hostCfg = config.my.host;
  roleFlags = mylib.roleFlags hostCfg;
  rawRoleFlags = mylib.roleFlags myvars;
  inherit (roleFlags) enableSteam;
  inherit (config.my.capabilities) hasNvidiaGpu;
in
{
  programs = lib.mkIf enableSteam {
    # 游戏支持
    steam =
      {
        enable = true;
        # 保持 Steam/gamescope 可用，但不把 Steam 注册为登录界面入口。
        gamescopeSession.enable = false;
        protontricks.enable = true;
        extest.enable = true; # Wayland 下将 X11 输入事件转换为 uinput（Steam Input 控制器支持）
        # 局域网传输与 Remote Play 使用时自动放行防火墙端口
        remotePlay.openFirewall = true;
        localNetworkGameTransfers.openFirewall = true;

        # Proton-GE 配置：通过 Steam 的 extraCompatPackages 安装
        # 注意：不能放在 environment.systemPackages（会导致 buildEnv 错误）
        extraCompatPackages = with pkgs; [
          proton-ge-bin
        ];
      }
      // lib.optionalAttrs rawRoleFlags.enableSteam {
        # platformOptimizations 的 option 来自按 gaming role 导入的 nix-gaming module。
        # 这里用主机清单的原始 role 做静态 gating，避免非 gaming host 产生不存在的 option。
        platformOptimizations.enable = true;
      };

    # Gamescope 提升调度优先级，改善帧时间稳定性
    gamescope = {
      enable = true;
      capSysNice = true;
    };

    gamemode.enable = true;
  };

  # === 硬件支持 ===
  hardware = lib.mkIf enableSteam {
    # Steam 控制器 / HTC Vive 等设备 udev 规则
    steam-hardware.enable = true;
    # Xbox 手柄蓝牙驱动
    xpadneo.enable = true;
    # Xbox One 无线适配器驱动
    xone.enable = true;
  };

  # === 内核与性能调优 ===
  boot.kernelParams = lib.mkIf enableSteam [
    # 某些老游戏 / Wine 应用会触发 split lock，内核默认严重惩罚性能
    "nosplit_lock_mitigate"
    # 禁用 USB autosuspend，防止 USB 声卡/耳机休眠导致爆音或断连
    "usbcore.autosuspend=-1"
  ];

  # nix-gaming platformOptimizations 已覆盖：
  #   vm.max_map_count, kernel.split_lock_mitigate, kernel.sched_cfs_bandwidth_slice_us,
  #   net.ipv4.tcp_fin_timeout
  # 以下为补充项：
  boot.kernel.sysctl = lib.mkIf enableSteam {
    # 减少 swap 使用，保持游戏内存热
    "vm.swappiness" = 10;
    # 减少文件缓存回收压力
    "vm.vfs_cache_pressure" = 50;
    # 限制脏页堆积，减少写回 I/O stall 导致的帧卡顿
    "vm.dirty_bytes" = 268435456; # 256MB
    "vm.dirty_background_bytes" = 67108864; # 64MB
    # 禁用 NMI watchdog，减少中断开销
    "kernel.nmi_watchdog" = 0;
  };

  # === PlayStation 手柄触摸板过滤 ===
  # DualShock 4 / DualSense 的触摸板会被识别为鼠标，干扰游戏操作
  services.udev.extraRules = lib.mkIf enableSteam ''
    ATTRS{name}=="Sony Interactive Entertainment Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    ATTRS{name}=="Sony Interactive Entertainment DualSense Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    ATTRS{name}=="Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
    ATTRS{name}=="DualSense Wireless Controller Touchpad", ENV{LIBINPUT_IGNORE_DEVICE}="1"
  '';

  # === Shader Cache 环境变量 ===
  environment.variables = lib.mkIf enableSteam (
    {
      # Mesa shader cache 默认 1GB，频繁换游戏会缓存淘汰导致卡顿重编译
      MESA_SHADER_CACHE_MAX_SIZE = "12G";
    }
    // lib.optionalAttrs hasNvidiaGpu {
      __GL_SHADER_DISK_CACHE_SIZE = "12000000000"; # ~12GB
    }
  );

  # greetd 的 greeter 用户也会拉起一个 user manager；
  # 将仅主用户需要的 user services 绑定到 mainUser，避免 greeter 会话产生误报失败日志。
  systemd.user = lib.mkIf enableSteam {
    services.gamemoded.unitConfig.ConditionUser = mainUser;
  };
}
