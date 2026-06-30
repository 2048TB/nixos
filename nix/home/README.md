# home 目录

本目录承载用户级配置。全仓库流程与脚本行为见 `docs/README.md`；这里只描述 Home Manager 结构与常见落点。

## 结构

```text
nix/home/
├── base/default.nix    # 跨平台共享（session 变量、PATH、mise shims、zsh/vim）
├── base/config-files.nix # 跨平台 configFile 映射清单
├── linux/
│   ├── default.nix     # 入口（identity、imports、dconf、assertions）
│   ├── _mixins/default.nix # Linux 模块 auto-import allowlist
│   ├── session.nix     # Linux session vars、activation
│   ├── files.nix       # repo link / wallpapers / user-level dotfiles / GUI wrapper
│   ├── packages.nix    # home.packages（含主账号开发环境）
│   ├── package-groups.nix # Linux 包分类清单（纯数据）
│   ├── programs.nix    # fzf/mpv/lutris 等
│   ├── desktop.nix     # 桌面用户服务、Noctalia 包接入、mise-upgrade service / opt-in timer
│   └── xdg.nix         # portal/mimeApps/configFile
├── darwin/default.nix  # macOS 专用
└── configs/            # 应用配置文件（niri/tmux/zellij/shell/television/...）
```

## 常见修改

| 目标 | 文件 |
|------|------|
| 终端 | `configs/ghostty/`、`configs/foot/`、`configs/shell/` |
| 共享 CLI 包 | `linux/package-groups.nix`（`shared` 组） |
| 跨平台 config file 映射 | `base/config-files.nix` |
| GUI IDE wrapper | `linux/files.nix` |
| Television | `configs/television/` + `base/config-files.nix` + `configs/shell/zshrc` |
| 状态栏 | `configs/niri/config.kdl`（Noctalia autostart） + `linux/desktop.nix`（包接入） |
| 窗口快捷键 | `configs/niri/interaction.kdl` + `configs/niri/appearance.kdl` |
| 窗口外观 | `configs/niri/appearance.kdl` |
| Linux 包分类 | `linux/package-groups.nix` |
| Tmux | `configs/tmux/tmux.conf` |
| Zellij | `configs/zellij/config.kdl` |

额外约束：

- Linux/Darwin 共享 CLI 包事实源在 `nix/home/linux/package-groups.nix` 的 `shared` 组；`nix/lib/default.nix` 的 `sharedPackageNames` 从该组读取并对外暴露
- 跨平台共享 config file 映射在 `nix/home/base/config-files.nix`
- `base/default.nix` 当前会把 `~/.local/share/mise/shims` 放进 session `PATH`
- `linux/session.nix` 只放通用 GUI/input session vars；CUDA/OpenSSL 工具链变量收敛到 devShell
- `configs/mise/config.toml` 当前默认将全局 `python` 固定在 `3.12`；部分个人 CLI（如 `btop` / `duf` / `dust` / `fastfetch` / `gitui` / `sd` / `taplo` / `yamllint`）随全局 `mise` rolling channel 更新
- Linux 侧入口通过 `_mixins` allowlist 收敛导入列表
- `nix/home/configs/noctalia/` 当前只作为 Noctalia runtime config seed；GUI 改动持久化到 `~/.local/state/noctalia/config`，不会直接修改 tracked files；需要更新默认 seed 时，显式复制 runtime config 回该目录并验证 JSON
- Noctalia notifications 是当前桌面 notification provider；`udiskie.notify` 依赖该 provider，避免启动后缺少 `org.freedesktop.Notifications`
- Noctalia 相关 autostart / lock / session / restart 命令会单独取消 `QT_IM_MODULE`，避免 `quickshell` 触发 `fcitx5` Qt input context 崩溃；restart 快捷键会同时处理 `noctalia-shell` wrapper 名称和实际 `quickshell` 进程名
- `wsdd` 不放入默认 desktop package group；Mullvad lockdown 下 GVfs 自动 WS-Discovery 会被防火墙拦截并产生日志噪音，SMB 直连仍通过 GVfs smb backend 处理
- `linux/files.nix` 当前还负责 `~/.local/bin/code` 与 `~/.local/bin/antigravity` wrapper：前置 `mise` shims，并过滤已知 Electron/Chromium 参数告警
- `linux/desktop.nix` 当前还负责 `mise-upgrade.service`；`mise-upgrade.timer` 只有 host 显式设置 `my.host.miseAutoUpgrade = true` 时才安装

read-only 验证时，若 checkout 中存在不可读的 `.keys/main.agekey`，先通过 `nix/scripts/admin/print-flake-repo.sh` 获取 filtered repo。

涉及 Home Manager 行为改动后，建议至少执行：

```bash
just self-check
just validate-local
```

## 文档同步

改了以下文件需同步 `docs/KEYBINDINGS.md`：
- `configs/niri/interaction.kdl`
- `configs/niri/appearance.kdl`
- `configs/tmux/tmux.conf`
- `configs/zellij/config.kdl`

改了以下文件通常不需要同步 `docs/KEYBINDINGS.md`：

- `base/config-files.nix`
- `configs/shell/zshrc`
- `configs/television/*`
