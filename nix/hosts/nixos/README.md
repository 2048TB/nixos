# NixOS 主机目录模板

本页只描述 `nix/hosts/nixos/<host>/` 的最小结构。主机参数统一放在清单 `nix/hosts/default.nix`（字段约束见 `nix/hosts/README.md`），本目录只放"描述硬件"的文件。

## 新增 NixOS 主机时至少要产出

1. `nix/hosts/default.nix` 中的清单条目（复制现有条目改）
2. `hardware.nix`
3. `hardware-modules.nix`
4. `disko.nix`

可选：

- `home.nix`：host-only Home Manager 追加
- `checks.nix`：host-only eval checks
- 额外 host-only module：例如 `ml-stack.nix`，再由 `hardware.nix` 或其它 host module 显式 `import`

## 最小模板

### 清单条目（`nix/hosts/default.nix`）

```nix
nixos = {
  # 共享默认值在文件顶部 nixosDefaults；这里只写差异。
  devbox = nixosDefaults // {
    gpuVendors = [ "amd" ];
    gpuMode = "amdgpu"; # 或 "nvidia" / "amd-nvidia-hybrid" / "modesetting" / "none"
    roles = [ "vpn" ]; # 功能开关：gaming / vpn / virt / container

    # 启用 hibernate（btrfs swapfile）时才需要：
    # resumeOffset = 1234567;

    # hybrid GPU 才需要：
    # amdgpuBusId = "PCI:18@0:0:0";
    # nvidiaBusId = "PCI:1@0:0:0";

    # NVIDIA 主机需要显式声明内核模块形态：
    # nvidiaOpen = true;

    displays = [ ];
  };
};
```

### `hardware-modules.nix`

nixos-hardware 模块名列表；CPU vendor（microcode / KVM 模块）由此推导：

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

### `disko.nix`

沿用共享 LUKS + btrfs 布局时：

```nix
import ../_shared/disko-luks-btrfs.nix
```

## 实际数据入口

不要在 README 中抄写当前主机参数；以下文件才是事实源：

- 主机清单与全部参数：`nix/hosts/default.nix`
- 某台主机硬件模块清单：`nix/hosts/nixos/<host>/hardware-modules.nix`
- 某台主机额外硬件 import：`nix/hosts/nixos/<host>/hardware.nix`

read-only 验证时，若 checkout 中存在不可读的 `.keys/main.agekey`，先通过 `nix/scripts/admin/print-flake-repo.sh` 获取 filtered repo。

共享校验入口 `nix/hosts/nixos/_shared/checks.nix` 是薄重导出：派生值集中在 `_shared/checks/context.nix`，各内聚检查组拆分到 `_shared/checks/<group>.nix`（host-metadata、boot、kernel、gpu-display、secrets、docker、home-manager），`checks.nix` 计算一次 context 后合并所有组。新增检查时归入对应组文件，并保持 `checks.nix` 的对外导入入口不变。

## 磁盘布局共性

当前各台 NixOS 主机的 `disko.nix` 默认都直接 import `../_shared/disko-luks-btrfs.nix`，其共享布局为：

- GPT
- `ESP` 分区大小 `512M`
- 剩余空间为 `LUKS2`
- LUKS 内文件系统为 `btrfs`
- 子卷：`@root`、`@nix`、`@persistent`、`@home`、`@snapshots`、`@tmp`、`@swap`

如果新主机沿用现有布局，通常只需在清单条目里重新确认：

- `diskDevice`
- `swapSizeGb`
- `resumeOffset`（仅在启用 hibernate 时需要）
