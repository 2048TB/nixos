# hosts 目录

本目录决定"有哪些主机"和"每台主机的全部参数"。全仓库通用行为与流程仍以 `docs/README.md` 为准，新手请先读 `docs/GETTING-STARTED.md`。

## 结构

```text
nix/hosts/
├── default.nix       # 主机清单：唯一事实源，每台机器一个条目
├── nixos/<host>/     # NixOS 主机目录（硬件与磁盘描述）
├── nixos/_shared/    # 共享磁盘模板、checks、workarounds
├── darwin/<host>/    # macOS 主机目录
└── outputs/          # flake 输出聚合
```

一台机器 = `default.nix` 里的一个条目 + 一个主机目录。清单条目集中所有"参数"（用户名、磁盘、GPU、roles、显示器……），主机目录只放"描述硬件"的文件。

## 事实源

- 主机清单与全部 host metadata：`nix/hosts/default.nix`
- NixOS 主机目录模板：`nix/hosts/nixos/README.md`
- flake outputs 聚合：`nix/hosts/outputs/README.md`

## 什么时候改这里

- 新增/删除主机 → `default.nix` + 主机目录
- 改某台主机的参数（swap、roles、应用开关、显示器…）→ `default.nix` 对应条目
- 改 host-only 硬件导入、`disko`、resume、bus ID → 主机目录 + `default.nix`

如果改的是通用模块、role 逻辑、桌面行为或 Home Manager，优先去：

- `nix/modules/core/`
- `nix/home/`
- `nix/lib/`

## 主机最小文件集

NixOS 主机目录（`nix/hosts/nixos/<host>/`）：

- `hardware.nix`
- `hardware-modules.nix`
- `disko.nix`

可选：

- `home.nix`（host-only Home Manager 追加）
- `checks.nix`（host-only eval checks）
- 其它 host-only module（由 `hardware.nix` 显式 import）

Darwin 主机目录（`nix/hosts/darwin/<host>/`）：

- `default.nix`

可选：`home.nix`、`checks.nix`。

## 新增主机

```bash
# 1. 复制一个最接近的主机目录
cp -a nix/hosts/nixos/zzly nix/hosts/nixos/devbox
# 2. 在 nix/hosts/default.nix 里复制对应条目并改名/改参数
# 3. 检查复制残留
rg -n 'zzly' nix/hosts/nixos/devbox
```

新增后验证：

```bash
just self-check
just validate-local
```

## 清单字段约束

字段取值由 `nix/modules/core/options.nix`（`types.enum`）与 `assertions.nix` 校验，写错会在 `nix flake check` / rebuild 时报错。

- `roles` 是功能开关（`gaming` / `vpn` / `virt` / `container`），不是 machine topology 容器
- `vpn` role 当前表示 Mullvad app / daemon 集成
- `tags` 只保留无法稳定派生的事实（`fingerprint-reader` / `docked`）
- `displays` 是 monitor topology 的唯一事实源
- `desktopProfile` 当前 Linux 只支持 `niri`，macOS 为 `aqua`；无桌面写 `"none"`
- `gpuMode` 取值：`none` / `modesetting` / `amdgpu` / `nvidia` / `amd-nvidia-hybrid`
- `gpuVendors` 必须与 `gpuMode` 匹配；hybrid 模式还必须声明 `amdgpuBusId` / `nvidiaBusId`
- 声明 `displays` 时必须且只能有一个 `primary = true`
- `gaming` role 必须搭配 `desktopSession = true`

## 验证

read-only 验证优先用 filtered repo：

```bash
REPO=/persistent/nixos-config
flake_repo="$(bash "$REPO/nix/scripts/admin/print-flake-repo.sh" "$REPO")"
nix eval "path:$flake_repo#nixosConfigurations" --apply builtins.attrNames
```

改动清单或主机目录后，至少补跑：

```bash
just self-check
just validate-local
```

命令细节与系统级流程见 `docs/README.md`。
