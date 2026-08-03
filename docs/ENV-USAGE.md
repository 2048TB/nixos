# 多环境使用手册

本文只写环境差异。通用流程、脚本行为与 FAQ 见 `docs/README.md`。

## 通用约定

- 已安装系统上的推荐 repo 路径：`/persistent/nixos-config`
- NixOS host 可在 `nix/hosts/default.nix` 对应主机条目里用 `configRepoPath = "...";` 覆盖运行时 repo 路径
- Live ISO / 临时环境可在任意可写 checkout 中工作
- 只读 flake 操作优先走 filtered repo

## 1. Live ISO

适用场景：

- 首次安装 NixOS
- 救援环境中重新跑 `install-live.sh`

差异点：

- 往往需要先执行 `export NIX_CONFIG="experimental-features = nix-command flakes"`
- 安装和 secrets bootstrap 优先直接调用 `nix/scripts/admin/*.sh`
- 当前 checkout 不一定在 `/persistent/nixos-config`
- 安装前必须确认 `disk=`，因为命令会清盘

最短命令：

```bash
cd ~/nixos
export NIX_CONFIG="experimental-features = nix-command flakes"
bash nix/scripts/admin/bootstrap-install.sh --host zly --disk /dev/nvme0n1
```

手动脚本调用（底层装盘，bootstrap 最终委托给它）：

```bash
cd ~/nixos
export NIX_CONFIG="experimental-features = nix-command flakes"
bash nix/scripts/admin/install-live.sh --host zly --disk /dev/nvme0n1 --repo "$PWD"
```

key 相关差异：

- 搜索顺序：`./.keys/main.agekey` -> `<repo>/.keys/main.agekey` -> `~/.keys/main.agekey`
- 现在会校验找到的 private key 是否匹配 `<repo>/secrets/keys/main.age.pub`
- 需要非交互安装时，显式传 `--yes`
- key 已丢失且无法解开旧 secret 时，给 `bootstrap-install.sh` 加 `--reset-secrets`（或交互确认），会生成新 key 并重建密码/aria2 secret

## 2. 已安装 NixOS

适用场景：

- 日常 `update` / `switch` / `upgrade`
- secrets 维护
- read-only eval / build / `flake-check`

差异点：

- 默认 repo 应位于 `/persistent/nixos-config`；如 host 设置了 `configRepoPath`，`programs.nh.flake`、`/etc/nixos` 与 `~/nixos` 会使用该路径
- `switch` / `upgrade` 会直接改系统状态
- `upgrade` 会先在指定 repo 上更新 Linux NixOS 相关 inputs，再执行 `switch`
- `sops.sh` / `guard-secrets.sh` 可以从任意目录直接调用
- 系统默认启用 `programs.nh.clean` 自动清理；`just clean` 对齐自动清理保留策略并保留 30 天/15 个 generation
- `mise upgrade` 默认手动执行；只有 host 显式设置 `my.host.miseAutoUpgrade = true` 才会启用 user timer；其中 `python` 当前固定在 `3.12`，部分个人 CLI（如 `btop` / `duf` / `dust` / `fastfetch` / `gitui` / `sd` / `taplo` / `yamllint`）也由全局 `mise` 管理
- Linux 会话不再全局导出 `LD_LIBRARY_PATH` / `OPENSSL_*`；CUDA pip wheels 的 `libcuda.so.1` 路径在 `ml` devShell 内注入
- Noctalia notifications 是当前桌面 notification provider；`udiskie.notify` 依赖它，`Mod+Ctrl+B` 会同时清理 `noctalia-shell` 与实际运行的 `quickshell` 进程后再重启
- Noctalia GUI 配置持久化在 `~/.local/state/noctalia/config`；`nix/home/configs/noctalia/` 只是新环境缺失文件时的 seed，GUI 改动需要手动复制回仓库后才会成为共享默认值
- 默认 desktop package group 不安装 `wsdd`；Mullvad lockdown 下 GVfs 自动 WS-Discovery 可能产生日志噪音，SMB 直连仍通过 GVfs smb backend 使用
- 启用 `"vpn"` role 的主机使用 Mullvad app / daemon；`services.mullvad-vpn.package` 使用 `pkgs.mullvad-vpn` 同时提供 CLI 和 GUI，系统仍保留 `wireguard-tools` 便于底层排查；日常连接、地区选择、恢复和 kill switch 由 Mullvad 自己管理，命令见 `docs/NIX-COMMANDS.md`

常用命令：

```bash
cd /persistent/nixos-config
nix develop
just self-check
just validate-local
just update
just host=zly switch
just host=zly upgrade
bash nix/scripts/admin/sops.sh recipients
bash nix/scripts/admin/sops.sh rekey
mullvad status
```

需要包含 check build 时：

```bash
cd /persistent/nixos-config
nix flake check --all-systems
```

手动触发 `mise` 升级：

```bash
mise upgrade --yes
```

## 3. GUI 应用与交互式 shell 的差异

适用场景：

- 从桌面直接启动 `VSCode` / `Antigravity`
- 依赖 `mise` 管理的 `go` / `gopls` / `node` 等工具链和部分个人 CLI

差异点：

- GUI 进程不会读取交互式 `zshrc`
- 因此不能只依赖 `mise activate zsh` 把工具链注入 `PATH`
- 当前仓库通过 Home Manager 把 `~/.local/share/mise/shims` 放进 session `PATH`
- 当前仓库通过 Home Manager 在 `~/.local/bin/code` 与 `~/.local/bin/antigravity` 安装 wrapper
- wrapper 还会导出 `CHECKPOINTING=false`，绕过当前 `Gemini Code Assist` 扩展的 checkpointing 启动问题
- 全局 `mise` 工具的远端更新默认由 `mise upgrade --yes` 手动执行；自动 timer 是 host opt-in

应用方式：

```bash
cd /persistent/nixos-config
just host=zly switch
```

然后完全退出相关 GUI 应用再重开。

## 4. 其他环境中的只读 flake 操作

适用场景：

- 非 NixOS 主机
- 临时 shell
- 只想做 `show` / `eval` / `no-build` 检查

差异点：

- 不需要可写系统环境
- 若 checkout 含不可读 `.keys/main.agekey`，不要直接对原 repo 做 read-only eval

推荐流程：

```bash
REPO=/persistent/nixos-config
flake_repo="$(bash "$REPO/nix/scripts/admin/print-flake-repo.sh" "$REPO")"
nix flake show "path:$flake_repo"
nix flake check --all-systems --no-build "path:$flake_repo"
```

## 5. 手动安装与恢复

只有在你明确不想用 `install-live.sh` 时，才手动拼装 `disko`、`nixos-install` 和 repo 同步流程。完整行为准则仍以 `docs/README.md` 为准；本文不再重复整套手动安装脚本。
