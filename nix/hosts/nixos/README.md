# NixOS 主机模板

本页只描述 `nix/hosts/nixos/<host>/` 的最小结构，不重复全仓库事实。host metadata 与流程规则见 `nix/hosts/README.md` 和 `docs/README.md`。

## 新增 NixOS 主机时至少要产出

1. `vars.nix`
2. `hardware.nix`
3. `hardware-modules.nix`
4. `disko.nix`
5. `nix/hosts/registry/systems.toml` 中对应条目

可选：

- 额外 host-only module：例如 `ml-stack.nix`，再由 `hardware.nix` 或其它 host module 显式 `import`

## 最小模板

### `vars.nix`

```nix
let
  common = import ../_shared/vars-common.nix;
in
common // {
  # systemStateVersion / homeStateVersion 默认在 _shared/vars-common.nix；
  # 仅当某台主机需要不同版本时才在此覆盖。

  # Storage / Hibernate
  # Optional: set only when enabling hibernate with a btrfs swapfile.
  # resumeOffset = 1234567;

  # Hardware
  # CPU vendor is inferred from hardware-modules.nix.
  gpuMode = "amdgpu";   # or "nvidia" / "amd-nvidia-hybrid"

  # Only for hybrid GPU
  # amdgpuBusId = "PCI:18@0:0:0";
  # nvidiaBusId = "PCI:1@0:0:0";

  # Optional for NVIDIA / container setup
  # nvidiaOpen = true;
  # dockerMode = "rootless";

  # Roles
  roles = [
    "vpn" # Mullvad app / daemon
  ];
}
```

说明：`../_shared/vars-common.nix` 只放稳定共享默认值；运行时差异仍建议在每台主机里显式定义。

### `hardware-modules.nix`

```nix
[
  "common-pc"
  "common-pc-ssd"
  "common-cpu-amd"
]
```

### `hardware.nix`

```nix
args@{ mylib, ... }:
(mylib.mkNixosHardwareModule {
  extraImports = [ ../_shared/hardware-workarounds-common.nix ];
}) args
```

说明：`hardware.nix` 通常保持薄包装；共享基线优先在 helper 或 `_shared/` 中集中维护。

如果该主机需要本地 workaround，再额外创建 `hardware-workarounds.nix`：

```nix
{ ... }:
{
  imports = [ ../_shared/hardware-workarounds-common.nix ];

  # host-only overrides go here
}
```

如果是 hybrid GPU 主机：

```nix
args@{ mylib, ... }:
(mylib.mkNixosHardwareModule {
  extraImports = [
    ../_shared/hardware-workarounds-common.nix
    ./hardware-gpu-hybrid.nix
  ];
}) args
```

### `systems.toml`

```toml
[nixos.<new-host>]
system = "x86_64-linux"
desktopSession = true
desktopProfile = "niri"
kind = "workstation"
formFactor = "desktop"
tags = []
gpuVendors = ["amd"]
displays = []
```

说明：

- Linux `desktopProfile` 当前只支持 `niri`
- `vpn` role 当前启用 Mullvad app / daemon
- `displays` 是 monitor topology 的唯一事实源；不要再用 `tags` 表达 `multi-monitor` / `hidpi`
- 声明 `displays` 时必须且只能有一个 `primary = true`
- `gpuVendors` 必须与 `gpuMode` 匹配；例如 `amd-nvidia-hybrid` 必须同时声明 `amd` 与 `nvidia`
- hybrid GPU 主机必须在 `vars.nix` 中声明 `amdgpuBusId` 与 `nvidiaBusId`
- `gaming` role 必须搭配 `desktopSession = true`

## 实际数据入口

不要在 README 中抄写当前主机参数；以下文件才是事实源：

- 主机注册与 metadata：`nix/hosts/registry/systems.toml`
- 某台主机运行时参数：`nix/hosts/nixos/<host>/vars.nix`
- NixOS 主机共享默认值：`nix/hosts/nixos/_shared/vars-common.nix`
- 某台主机硬件模块清单：`nix/hosts/nixos/<host>/hardware-modules.nix`
- 某台主机额外硬件 import：`nix/hosts/nixos/<host>/hardware.nix`

read-only 验证时，若 checkout 中存在不可读的 `.keys/main.agekey`，先通过 `nix/scripts/admin/print-flake-repo.sh` 获取 filtered repo。

共享校验入口 `nix/hosts/nixos/_shared/checks.nix` 现在是薄重导出：派生值集中在 `_shared/checks/context.nix`，各内聚检查组拆分到 `_shared/checks/<group>.nix`（host-metadata、boot、kernel、gpu-display、secrets、docker、home-manager），`checks.nix` 计算一次 context 后合并所有组。新增检查时归入对应组文件，并保持 `checks.nix` 的对外导入入口不变。

## 磁盘布局共性

当前各台 NixOS 主机的 `disko.nix` 默认都直接 import `../_shared/disko-luks-btrfs.nix`，其共享布局为：

- GPT
- `ESP` 分区大小 `512M`
- 剩余空间为 `LUKS2`
- LUKS 内文件系统为 `btrfs`
- 子卷：`@root`、`@nix`、`@persistent`、`@home`、`@snapshots`、`@tmp`、`@swap`

如果新主机沿用现有布局，通常只需重新确认：

- `diskDevice`
- `swapSizeGb`
- `resumeOffset`（仅在启用 hibernate 时需要）
