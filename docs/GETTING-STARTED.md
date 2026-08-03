# 新手上手指南

这一页帮第一次接触本仓库（或第一次接触 NixOS flake 配置）的人建立整体图景：仓库怎么读、日常怎么改、新机器怎么加。流程与命令的权威事实源仍是 `docs/README.md`，本页只负责"看懂"。

## 1. 这个仓库是什么

一个多主机 Nix 配置仓库，用一份代码同时管理：

- 若干台 NixOS 机器（`nixosConfigurations`）
- 一台 macOS 机器（`darwinConfigurations`，通过 nix-darwin）
- 每台机器上的用户环境（home-manager，跟随系统一起构建）

核心理念：**机器的一切（装什么、怎么分区、什么桌面、哪些服务）都写在仓库里**；改配置 = 改文件 + `just host=<主机名> switch`，回滚 = 选上一代 boot 条目或 `nh` 回滚。

## 2. 心智模型：一台机器由什么组成

```text
nix/hosts/default.nix          ← 主机清单：这台机器的"全部参数"（唯一事实源）
nix/hosts/nixos/<host>/        ← 这台机器的"硬件描述"
├── hardware.nix               ← 硬件基线（薄包装，引 _shared 的公共 workaround）
├── hardware-modules.nix       ← nixos-hardware 模块名列表（CPU 厂商由此推导）
└── disko.nix                  ← 磁盘分区（默认引用共享 LUKS+btrfs 模板）
```

其余目录是所有机器共享的实现：

```text
nix/modules/core/   ← 系统层共享模块（启动、桌面、服务、安全、roles）
nix/home/           ← 用户层（home-manager）：包、shell、桌面配置文件
nix/lib/            ← 少量自建函数：清单组装、显示器拓扑、主题
nix/hosts/outputs/  ← 把清单聚合成 flake outputs（一般不用动）
secrets/            ← sops 加密的密码等（配套脚本 nix/scripts/admin/sops.sh）
```

读代码的推荐顺序：`nix/hosts/default.nix` → 你机器的 `nix/hosts/nixos/<host>/` → `nix/modules/core/options.nix`（所有 `my.host.*` 选项的定义和允许值）→ 想改哪个行为就查对应模块。

## 3. 清单条目怎么读

`nix/hosts/default.nix` 顶部是 `nixosDefaults`（共享默认值），每台主机 `nixosDefaults // { … }` 只写差异：

| 字段 | 作用 |
|------|------|
| `username` / `timezone` / `locale` | 主用户与地区 |
| `diskDevice` / `swapSizeGb` / `resumeOffset` | 安装盘、swap 大小、休眠偏移（可选） |
| `kind` / `formFactor` | 机器类别（workstation/server/vm）与形态（desktop/laptop/…） |
| `desktopSession` / `desktopProfile` | 要不要桌面、用哪个桌面（Linux 当前是 niri） |
| `gpuVendors` / `gpuMode` / `nvidiaOpen` / `*BusId` | 显卡厂商与驱动模式（hybrid 才需要 BusId） |
| `roles` | 功能开关：`gaming`（Steam）/ `vpn`（Mullvad）/ `virt`（libvirtd）/ `container`（Docker） |
| `enable*` | 单个应用的开关（WPS、Telegram 等） |
| `displays` | 显示器拓扑（niri 输出布局与 Noctalia 小部件由此生成） |

写错值不用担心：所有字段在 `nix/modules/core/options.nix` 里有 `types.enum` 类型约束，`assertions.nix` 还会检查组合是否自洽（例如 `gpuMode = "amd-nvidia-hybrid"` 必须同时给出两个 BusId），`nix flake check` / rebuild 时会直接报错并告诉你哪里不对。

## 4. 日常操作

```bash
# 进开发环境（带 just、格式化、lint 工具）
nix develop

# 改完配置后应用到本机
just host=zly switch

# 更新所有输入（nixpkgs 等）到最新
just update

# 更新 + 应用（只刷新 Linux 常用输入）
just host=zly upgrade

# 推送前本地验证
just self-check
just validate-local

# 清理旧 generation
just clean
```

常见改动怎么落位：

- **给某台机器开/关一个应用** → `nix/hosts/default.nix` 里改 `enable*` 或 `roles`
- **给所有机器加一个 CLI 工具** → `nix/home/linux/package-groups.nix`
- **改 shell / 终端 / 桌面配置** → `nix/home/configs/` 下对应目录
- **改系统服务行为** → `nix/modules/core/` 对应模块

## 5. 新增一台机器

1. 在 `nix/hosts/default.nix` 复制一个最接近的条目，改名、改参数
2. 复制主机目录：`cp -a nix/hosts/nixos/zzly nix/hosts/nixos/<新名字>`，按硬件改 `hardware-modules.nix`（CPU 厂商）和清单里的 `gpuVendors`/`gpuMode`
3. `rg -n '旧名字' nix/hosts/nixos/<新名字>` 检查复制残留
4. `just validate-local` 验证
5. 装机：Live ISO 里 `bash nix/scripts/admin/bootstrap-install.sh --host <新名字> --disk /dev/nvme0n1`（详见 `docs/README.md` 第 5 节）

## 6. secrets 怎么回事

- 登录密码等敏感值用 sops + age 加密存在 `secrets/`，密文可以提交
- 私钥 `.keys/main.agekey` **永远不进 Git**（`.gitignore` + guard 脚本双保险）
- 常用操作都封装在 `bash nix/scripts/admin/sops.sh <子命令>`；丢 key 的恢复路径见 `docs/README.md` 7.2

## 7. 卡住了怎么办

- 报错信息带 `nix/hosts/default.nix[...]` → 清单条目缺字段或值非法，按提示补
- `nix eval` 报 `.keys/main.agekey: Permission denied` → 先 `print-flake-repo.sh` 取 filtered repo（`docs/README.md` FAQ 9.1）
- 想确认改动没破坏别的机器 → `just validate-local`（会 eval 所有主机）
- 更多 FAQ：`docs/README.md` 第 9 节
