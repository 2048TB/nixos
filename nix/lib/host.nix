# 主机元数据模式（允许值、默认值）+ role / 能力派生。
# 清单条目（nix/hosts/default.nix）里的字段最终由 modules/core/options.nix
# 按这里的 allowed* 列表做 types.enum 校验。
_:
rec {
  hostMetaSchema = {
    defaultRoles = [ ];
    defaultDockerMode = "rootless";
    defaultConfigRepoPath = "/persistent/nixos-config";
    defaultAria2RpcSecretPath = "/run/secrets/services/aria2-rpc";

    allowedGpuModes = [
      "none"
      "amdgpu"
      "nvidia"
      "modesetting"
      "amd-nvidia-hybrid"
    ];

    allowedDockerModes = [
      "rootless"
      "rootful"
    ];

    allowedKinds = [
      "workstation"
      "server"
      "vm"
    ];

    allowedFormFactors = [
      "desktop"
      "laptop"
      "handheld"
      "headless"
    ];

    allowedGpuVendors = [
      "amd"
      "intel"
      "nvidia"
    ];

    allowedDesktopProfiles = [
      "none"
      "niri"
      "aqua"
    ];

    allowedHostTags = [
      "fingerprint-reader"
      "docked"
    ];

    knownHostRoles = [
      "gaming"
      "vpn"
      "virt"
      "container"
    ];
  };

  roleFlags = host:
    let
      hostRoles = host.roles or hostMetaSchema.defaultRoles;
      hasRole = role: builtins.elem role hostRoles;
      dockerMode = host.dockerMode or hostMetaSchema.defaultDockerMode;
    in
    {
      inherit hostRoles hasRole dockerMode;
      enableMullvadVpn = hasRole "vpn";
      enableLibvirtd = hasRole "virt";
      enableDocker = hasRole "container";
      enableSteam = hasRole "gaming";
      useRootfulDocker = dockerMode == "rootful";
      useRootlessDocker = dockerMode == "rootless";
    };

  deriveHostCapabilities =
    host:
    let
      kind = host.kind or "workstation";
      formFactor = host.formFactor or "desktop";
      desktopSession = host.desktopSession or false;
      desktopProfile = host.desktopProfile or "none";
      gpuVendors = host.gpuVendors or [ ];
      tags = host.tags or [ ];
      displays = host.displays or [ ];
      primaryDisplays = builtins.filter (display: display.primary or false) displays;
      resolvedPrimaryDisplay =
        if primaryDisplays != [ ] then builtins.head primaryDisplays
        else if displays != [ ] then builtins.head displays
        else null;
      displayScales = map
        (
          display:
          let
            scale = display.scale or null;
          in
          if scale == null then 1.0 else scale
        )
        displays;
    in
    {
      isWorkstation = kind == "workstation";
      isServer = kind == "server";
      isVm = kind == "vm";
      isDesktop = formFactor == "desktop";
      isLaptop = formFactor == "laptop";
      hasDesktopSession = desktopSession;
      usesNiri = desktopProfile == "niri";
      hasMultipleDisplays = builtins.length displays > 1;
      hasDisplayTopology = displays != [ ];
      hasHiDpiDisplay = builtins.any (scale: scale > 1.0) displayScales;
      primaryDisplayName = if resolvedPrimaryDisplay == null then null else (resolvedPrimaryDisplay.name or null);
      hasFingerprintReader = builtins.elem "fingerprint-reader" tags;
      hasAmdGpu = builtins.elem "amd" gpuVendors;
      hasIntelGpu = builtins.elem "intel" gpuVendors;
      hasNvidiaGpu = builtins.elem "nvidia" gpuVendors;
    };
}
