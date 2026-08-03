# Docs

本文是当前仓库的唯一事实源。其余文档只做入口、主题说明或代理规则，不重复维护完整事实。

## 文档地图

| 文档 | 职责 |
|------|------|
| `README.md` | 仓库根入口与最短提示 |
| 本文档 | 权威手册：流程、脚本行为、约束、FAQ |
| `docs/GETTING-STARTED.md` | 新手上手指南：仓库怎么读、怎么改、怎么加机器 |
| `docs/NIX-COMMANDS.md` | 纯命令速查 |
| `docs/ENV-USAGE.md` | 环境差异 |
| `docs/KEYBINDINGS.md` | 快捷键摘要 |
| `nix/hosts/README.md` | hosts 目录、主机清单与结构入口 |
| `nix/home/README.md` | Home Manager 结构入口 |
| `secrets/keys/README.md` | 公钥目录与 key 操作入口 |
| `AGENTS.md` / `CLAUDE.md` | 代理规则与文档同步要求 |

## 1. 仓库现状

当前仓库只保留少量运维脚本入口：

- `nix/scripts/admin/bootstrap-install.sh`
- `nix/scripts/admin/install-live.sh`
- `nix/scripts/admin/print-flake-repo.sh`
- `nix/scripts/admin/update-flake.sh`
- `nix/scripts/admin/sops.sh`
- `nix/scripts/admin/guard-secrets.sh`
- `nix/scripts/admin/check-format-sanity.sh`
- `nix/scripts/admin/common.sh`

常用 update / switch / upgrade / clean 入口通过 `just` 暴露，检查以本地命令为准。
GitHub workflow 执行轻量 `self-check` 与 secrets guard，仍不能替代本地 `validate-local`。
其中 `switch` / `upgrade` / `clean` 现通过 `nh` 执行，但仍保留仓库自己的 filtered flake repo 与显式 `host` / `repo` 约束。
系统同时启用 `programs.nh` 与 `programs.nh.clean`，作为默认 `nh` 入口和自动清理来源。

推荐验证基线：

- 进入开发环境：`nix develop`
- 轻量自检：`just self-check`
- 快速基线：`just validate-local`
- 包含 check build：直接执行 `nix flake check --all-systems`

## 2. 全局约定

- 危险操作必须显式写 `host=...`、`disk=...` 或 `--repo <path>`
- 显式传入的 `--repo` / `NIXOS_CONFIG_REPO` 若无效，脚本会直接失败，不会静默回退
- read-only `eval` / `show` / `build` 优先通过 filtered flake repo，避免直接触碰不可读的 `.keys/main.agekey`
- `sops.sh` 与 `guard-secrets.sh` 可以从仓库外直接调用
- 已安装 NixOS host 的默认 repo 路径仍是 `/persistent/nixos-config`；需要不同磁盘布局时，在 `nix/hosts/default.nix` 对应主机条目里设置 `configRepoPath`
- `/bin/bash` 兼容链接由 `systemd.tmpfiles.rules` 声明为 `/run/current-system/sw/bin/bash`，不再通过 activation script 命令式创建
- `nix/hosts/default.nix` 是主机清单与 host metadata 的唯一事实源
- `displays` metadata 是 monitor topology 的事实源；不要再在别处重复手写 connector facts
- Noctalia GUI 配置写入 `~/.local/state/noctalia/config`；Home Manager 会从 `nix/home/configs/noctalia/` 首次 seed 缺失文件，后续 GUI 改动不会写回 tracked config；需要把 GUI 结果变成共享默认值时，显式复制 runtime config 回 `nix/home/configs/noctalia/` 后再提交
- Home Manager 当前会把 `~/.local/share/mise/shims` 放进 session `PATH`；`code` / `antigravity` 还会额外通过 `~/.local/bin/` wrapper 过滤已知 Electron/Chromium 参数告警；`mise upgrade` 默认手动执行，只有主机显式设置 `my.host.miseAutoUpgrade = true` 时才启用 `systemd --user` timer
- greetd 会话启动前只导入 HM/GUI 基础变量；`WAYLAND_DISPLAY` / `DISPLAY` 等显示变量由 Niri `spawn-at-startup` 的 `wayland-session-env-sync` 在 compositor 启动后再导入 systemd user / D-Bus activation 环境
- Noctalia 由 Niri `spawn-at-startup` 拉起，notifications 是当前桌面 notification provider；`udiskie.notify` 依赖该 provider，`Mod+Ctrl+B` 会同时清理 `noctalia-shell` 与实际运行的 `quickshell` 进程后再重启
- `wsdd` 不放入默认 desktop package group；Mullvad lockdown 下 GVfs 自动 WS-Discovery 会被防火墙拦截并产生日志噪音，SMB 直连仍通过 GVfs smb backend 处理
- 启用 hibernate 的主机会安装 `swapfile-resume-check.service`；swapfile size 或 resume offset 异常会体现在 unit 失败状态与 journal，而不是只出现在 activation 输出中
- 启用 `"vpn"` role 的 NixOS 主机使用 Mullvad app / daemon 最小集成：NixOS 启用 `services.mullvad-vpn`，将 service package 设为 `pkgs.mullvad-vpn` 以同时提供 CLI 和 GUI，启用 `systemd-resolved`，系统包保留 `pkgs.wireguard-tools`，impermanence 持久化 `/etc/mullvad-vpn` 与 `/var/cache/mullvad-vpn`；连接、地区选择、恢复和 kill switch 交给 Mullvad app / daemon 自己管理

## 3. 最常用命令

```bash
just update
just self-check
just validate-local
just host=zly switch
just host=zly upgrade
just clean
```

命令细表见 `docs/NIX-COMMANDS.md`。

## 4. Read-Only Flake 使用

如果真实 checkout 中存在不可读的 `.keys/main.agekey`，不要直接对原始 `path:/persistent/nixos-config` 做 read-only 操作。先取 filtered repo：

```bash
REPO=/persistent/nixos-config
flake_repo="$(bash "$REPO/nix/scripts/admin/print-flake-repo.sh" "$REPO")"
nix flake show "path:$flake_repo"
```

`print-flake-repo.sh` 的当前行为：

- 输出可用于 flake 操作的 repo path；只有存在不可读的 `.keys/main.agekey` 时才复制出 filtered repo
- 复制 filtered repo 时会显式排除 `.keys/`、`.git/`、`.cache/`、`.serena/` 与 `result*`
- 适合 `nix flake show`、`nix eval`、`nix build`、`nix flake check --no-build`
- 对显式传错的 repo 路径直接报错

## 5. 安装流程

### 5.1 Live ISO 最短流程

最简单的方式是用 `bootstrap-install.sh`：它先做飞行前检查（repo、主机名、密码 secret、sops key 是否就位），缺什么就直接告诉你要跑哪条命令，全部就位后再把清空磁盘 + 安装交给 `install-live.sh`：

```bash
git clone https://github.com/2048TB/nixos-config.git ~/nixos
cd ~/nixos
export NIX_CONFIG="experimental-features = nix-command flakes"
bash nix/scripts/admin/bootstrap-install.sh --host zly --disk /dev/nvme0n1
```

- 重装已有主机：密码 secret 仓库里已有，只需把 `main.agekey` 放到 `./.keys/`、`<repo>/.keys/` 或 `~/.keys/` 任一处即可。
- 首次从零 bootstrap：脚本会在缺 key / 缺密码 secret 时停下并给出对应命令（见下）。
- 丢失 key 恢复：若 `main.agekey` 已丢失（且无 recovery key 可解开旧 secret），加 `--reset-secrets`，脚本会生成新 key、改写 `.sops.yaml`、提示你输入新密码并重建密码/aria2 secret：

```bash
bash nix/scripts/admin/bootstrap-install.sh --host zly --disk /dev/nvme0n1 --reset-secrets
```

  交互运行时也可不加该参数——脚本检测到缺 key 会询问是否重建。重建后请**备份新的 recovery.agekey**，并在装好的系统上 commit 更新后的 `.sops.yaml` 与 `secrets/`。

首次 bootstrap 需要先建立 sops key 与密码 secret。可以一步到位用 `sops.sh reset`（生成 main+recovery key、提示输入密码、重建密码/aria2 secret）：

```bash
bash nix/scripts/admin/sops.sh reset
```

或分步手动：

```bash
bash nix/scripts/admin/sops.sh init --create
bash nix/scripts/admin/sops.sh recovery-init
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#mkpasswd -c mkpasswd -m sha-512
# 用上一步得到的哈希，通过 sops 写入 secrets/common/passwords/{user,root}-password.yaml
```

若已有旧 `main.agekey`，先放到以下任一位置，再执行 `bash nix/scripts/admin/sops.sh init`：

- `./.keys/main.agekey`
- `<repo>/.keys/main.agekey`
- `~/.keys/main.agekey`

### 5.2 `install-live.sh` 的当前行为

```bash
bash nix/scripts/admin/install-live.sh --host zly --disk /dev/nvme0n1 --repo "$PWD"
```

- 用法：`install-live.sh --host <name> --disk <device> [--repo <path>] [--yes]`
- 会要求确认；自动化环境可用 `--yes`
- 会清空目标盘并运行 `disko`
- 会把仓库同步到目标系统的 `/persistent/nixos-config`
- 仅同步 Git tracked 文件（allowlist，同步前要求 `--repo` 是 Git checkout）
- 会把 `/etc/nixos` 链接到 `/persistent/nixos-config`
- 会执行一次 `nixos-rebuild dry-build`
- 安装 `main.agekey` 前，会校验该 private key 派生出的 public key 是否与 `<repo>/secrets/keys/main.age.pub` 一致

`install-live.sh` 的 key 搜索顺序仍是：

- `./.keys/main.agekey`
- `<repo>/.keys/main.agekey`
- `~/.keys/main.agekey`

但现在只有“与仓库 `main.age.pub` 匹配”的 key 才会被接受；找到了无关键也会直接失败。

环境差异和手动安装路径见 `docs/ENV-USAGE.md`。

## 6. Lock / Eval / Build / Switch

更新输入：

```bash
just update
```

- `update` 会全量更新 `flake.lock` 的 root inputs
- `upgrade` 会先更新 Linux NixOS 日常相关 inputs，再执行 `switch`，避免刷新 Darwin/Homebrew inputs
- 需要更新指定 input 时，直接调用 `nix/scripts/admin/update-flake.sh <repo> <input...>`

只读信息：

```bash
just self-check
just validate-local
```

开发环境：

```bash
nix develop
nix develop .#ml
```

- `ml` 当前覆盖主训练栈：`PyTorch`、`Transformers`、`Datasets`、`Accelerate`、`PEFT`、`TRL`
- shell 会显式注入 `CUDA/cuDNN/NCCL`、OpenSSL build env、`/run/opengl-driver/lib` 与常用 cache 目录
- `ml` 当前优先使用 `torch-bin` / `triton-bin`，并在进入 shell 时依赖较长的网络超时完成官方 wheel 下载；这样比本地编译 `magma` 更稳妥
- Linux 用户会话不再全局导出 `LD_LIBRARY_PATH` / `OPENSSL_*`；pip CUDA wheels 需要的 `libcuda.so.1` 解析路径收敛到 `ml` devShell
- `bitsandbytes`、`vLLM`、`llama.cpp` 暂不放进默认入口；它们会显著放大闭包或引入额外源码构建，按需单独处理更稳

系统级入口：

```bash
just host=zly switch
just host=zly upgrade
```

当前行为说明：

- `switch` 现在通过 `nh os switch` 执行，并继续先取 filtered repo
- `upgrade` 现在会保留外层 `repo={{repo}}`，先在指定 repo 上更新 Linux NixOS 相关 inputs，再执行 `switch`
- 需要 `build` / `boot` / `test` / Home Manager switch 时，直接用 `nh` 或 `nix` 命令；这些不再作为公开 `just` 入口
- `format-sanity` 是 flake check 中的轻量格式/解析防回归检查，对应 `nix/scripts/admin/check-format-sanity.sh`；shell shebang、YAML/JSON 解析、Markdown trailing whitespace、`justfile` 解析和疑似 Nix 注释吞代码都会失败
- `self-check` 会检查 `justfile`、admin/hook shell 语法、可用时的 `shellcheck` / `shfmt -d`、YAML/JSON 解析、Markdown trailing whitespace 和格式 sanity
- `validate-local` 会先执行 `self-check`，再串行执行 secrets 全量巡检和 `nix flake check --all-systems --no-build`（主机清单字段校验包含在 flake check 的模块断言与 eval checks 中）

清理相关：

```bash
just clean
```

```bash
sudo nix store gc
sudo nix store optimise
```

- `clean` 现在通过 `nh clean all --keep-since 30d --keep 15` 执行
- 自动清理由 `programs.nh.clean` 执行：每周一 `03:15`，参数为 `--keep-since 30d --keep 15`
- `nix.gc.automatic` 已关闭，避免与 `programs.nh.clean` 冲突
- systemd-boot 最多展示 15 个配置项；可启动的旧 NixOS 版本来自系统 profile generation，不等同于 `/nix/store` 缓存
- 如果明确要删除所有旧 profile generation，直接手动运行 `nh clean all --keep-since 0h --keep 0`，注意这可能同时移除 boot menu 中的回滚入口

## 7. Secrets 与 Git 安全

### 7.1 常用入口

```bash
git config core.hooksPath .githooks
bash nix/scripts/admin/guard-secrets.sh
bash nix/scripts/admin/guard-secrets.sh --all-tracked
bash nix/scripts/admin/sops.sh init
bash nix/scripts/admin/sops.sh init --create
bash nix/scripts/admin/sops.sh init --rotate
bash nix/scripts/admin/sops.sh reset
bash nix/scripts/admin/sops.sh recovery-init
bash nix/scripts/admin/sops.sh recipients
bash nix/scripts/admin/sops.sh rekey
bash nix/scripts/admin/sops.sh ssh-key-set
bash nix/scripts/admin/sops.sh password-set '<sha512-hash>'
```

### 7.2 `sops.sh` 的当前行为

- `init`：同步已有 `main.agekey`
- `init --create`：创建新的 `main.agekey`
- `init --rotate [--yes]`：生成新的 `main.agekey`，更新 `secrets/keys/main.age.pub`，并保留旧 key 为 `.keys/main.agekey.pre-rotate.<timestamp>`
- `reset [--yes]`：丢失 key 的恢复入口（旧 main+recovery 都无法解密时使用）。生成新的 `main` + `recovery` key，把 `.sops.yaml` 的 `&main`/`&recovery` 锚点改写为新公钥，交互提示输入新登录密码（`mkpasswd -m sha-512`，写入 user + root），并重建 `aria2-rpc-secret.yaml`；旧 secret 内容永久作废。完成后需备份新的 `recovery.agekey`，并在装好的系统上提交更新后的 `.sops.yaml` 与 `secrets/`
- `rekey`：先校验 `.sops.yaml` 必须包含 `secrets/common/`、`secrets/hosts/<host>/`、`secrets/users/<user>/`、`secrets/install/`，且不得退回 `^secrets/.*\.yaml$` catch-all；再基于当前 `main.agekey`、`recovery.agekey` 和现存 rotation backup keys 构造 identity file，然后对每个 secret 执行 `sops rotate -i --add-age/--rm-age`
- `recipients`：列出当前收件人
- `host-add`：把 host SSH public key 同步到 `secrets/keys/hosts/`
- `ssh-key-set`：默认把 `.keys/github_id_ed25519` 写入当前主用户的 `secrets/users/<user>/ssh/`；需要覆盖目标用户时设置 `SOPS_USER=<user>`

注意：

- 需要非交互确认时，直接调用 `nix/scripts/admin/sops.sh init --rotate --yes`
- rotation 完成后，旧 backup key 仍需保留到 `rekey` 和系统切换完成
- `run_sops_encrypt_yaml` 现在先写临时文件，再原子替换，避免加密失败时截断原 secret

当前 secret 路径约定：

- `secrets/common/...`：跨 host / user 共用 secret，例如 `passwords/` 与 `services/`
- `secrets/hosts/<hostname>/...`：预留 host-specific secret；后续可按 host SSH recipient 细化
- `secrets/users/<username>/...`：用户级 secret，例如 SSH key
- `secrets/install/...`：安装、恢复或 Live ISO bootstrap 场景

### 7.3 私钥与公钥边界

- `secrets/keys/` 只放可提交的 public keys
- `.keys/*.agekey` 不可提交
- `.keys/*.agekey` 与明文 password/token/private key 不得进入 Git；加密后的 `secrets/**/*.yaml` 需符合 `.sops.yaml` 规则
- 运行时主密钥目标路径：`/persistent/keys/main.agekey`
- `guard-secrets.sh` 应作为提交前 guard，而不是事后补救；默认检查 staged 内容，可用 `--all-tracked` 做全量巡检
- 当前会拦截私钥内容、常见 token 前缀和明显的明文 `token/password/apiKey/secret` 赋值

## 8. Host Metadata 与桌面约束

- host metadata 事实源：`nix/hosts/default.nix`（主机清单，每台主机一个条目）
- 常见字段：`system`、`kind`、`formFactor`、`desktopSession`、`desktopProfile`、`tags`、`gpuVendors`、`displays`
- 字段取值由 `nix/modules/core/options.nix`（`types.enum`）与 `assertions.nix` 校验，写错会在 `nix flake check` / rebuild 时报错
- `roles` 是功能开关；不要重新引入旧 `profiles` 模型
- `tags` 只保留无法稳定派生的事实；`multi-monitor` / `hidpi` 不再手写
- `displays.primary` 现在必须是 `bool`
- `displays.match` 现在必须是 `string` 或 `null`
- 若声明了 `displays`，必须且只能有一个 `primary = true`
- `gpuVendors` 必须与 `gpuMode` 语义匹配；例如 `amd-nvidia-hybrid` 必须同时声明 `amd` 与 `nvidia`
- hybrid GPU 主机必须声明 `amdgpuBusId` 与 `nvidiaBusId`
- `gaming` role 必须运行在 `desktopSession = true` 的 host 上
- Linux `desktopProfile` 当前只支持 `niri`
- `nix/home/configs/noctalia/` 是 Noctalia runtime config 的 seed；GUI 修改持久化到 `~/.local/state/noctalia/config`，不要再依赖 GUI 直接改 tracked config；seed 提交流程见 `docs/NIX-COMMANDS.md`
- 修改 host metadata 后运行 `just self-check` 和 `just validate-local`
- 修改脚本入口后运行 `just self-check` 或至少 `bash -n nix/scripts/admin/*.sh`；可用时再运行 `shellcheck nix/scripts/admin/*.sh` 与 `shfmt -i 2 -d nix/scripts/admin/*.sh`
- 修改 Nix 模块或 flake 聚合后运行 `just validate-local`，需要执行 check build 时直接运行 `nix flake check --all-systems`

## 9. FAQ

### 9.1 `nix eval path:/persistent/nixos-config#...` 报 `.keys/main.agekey: Permission denied`

先执行：

```bash
flake_repo="$(bash /persistent/nixos-config/nix/scripts/admin/print-flake-repo.sh /persistent/nixos-config)"
```

再对 `path:$flake_repo#...` 执行 `eval` / `show` / `build`。

### 9.2 `just update` / `just host=<host> upgrade` 失败

确认 repo 可写，且 `flake.lock` 不是只读。`update-flake.sh` 会在需要时先更新 filtered repo，再同步回真实仓库。

### 9.3 传了 `--repo` 仍操作错仓库

按当前实现，不会。显式传错路径会直接失败；若行为看起来异常，优先检查你传入的 `--repo` / `NIXOS_CONFIG_REPO`。

### 9.4 找不到 `main.agekey`

放到以下任一位置：

- `./.keys/main.agekey`
- `<repo>/.keys/main.agekey`
- `~/.keys/main.agekey`

### 9.5 如何做非交互 rotate

```bash
bash nix/scripts/admin/sops.sh init --rotate --yes
bash nix/scripts/admin/sops.sh rekey
```

### 9.6 如何防止密钥泄露

```bash
git config core.hooksPath .githooks
bash nix/scripts/admin/guard-secrets.sh
bash nix/scripts/admin/guard-secrets.sh --all-tracked
```

### 9.7 推送前最低验证是什么

```bash
nix develop
just self-check
just validate-local
```

如果本次改动涉及 `checks` 产物或你想额外确认执行链路，再跑：

```bash
nix flake check --all-systems
```

### 9.8 从桌面启动的 `VSCode` / `Antigravity` 找不到 `go` / `gopls`

GUI 进程不会读取交互式 `zshrc`，因此不能依赖 `mise activate zsh` 给 `PATH` 注入语言工具链。

当前仓库的处理方式是：

- 通过 Home Manager 把 `~/.local/share/mise/shims` 放进 session `PATH`
- 通过 Home Manager 在 `~/.local/bin/code` 与 `~/.local/bin/antigravity` 安装 wrapper
- wrapper 同时导出 `CHECKPOINTING=false`，绕过当前 `Gemini Code Assist` 扩展在 checkpointing 启动链路中的 `git` 探测问题

应用方式：

```bash
cd /persistent/nixos-config
just host=zly switch
```

然后完全退出 `VSCode` / `Antigravity` 再重开。

### 9.9 `mise` 写成 `latest` 后为什么还需要显式升级

`mise` 官方语义里，config 文件中的 `latest` 默认只表示“当前已安装版本中的最新”，不会自动跟踪远端最新版本。因此仅把 `~/.config/mise/config.toml` 写成 `latest` 还不够，需要按需显式执行 `mise upgrade`。

当前仓库的处理方式是：

- 全局 `mise` 配置默认使用 rolling channel（如 `latest` / `stable`），但 `python` 固定在 `3.12`
- 个人 CLI 中的 `btop` / `duf` / `dust` / `fastfetch` / `gitui` / `sd` / `taplo` / `yamllint` 也由全局 `mise` 管理，不再放入默认 Home Manager package group
- 默认不自动升级，避免 flake 外状态静默漂移
- 手动入口是 `mise upgrade --yes`
- 若某台主机确实需要自动升级，显式设置 `my.host.miseAutoUpgrade = true` 后才会启用 `systemd --user` timer
- opt-in timer 调度为每周一 `04:30:00`，附加 `RandomizedDelaySec=1h`，且 `Persistent=true`

手动触发：

```bash
mise upgrade --yes
```
