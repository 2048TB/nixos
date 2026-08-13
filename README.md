# nixos-config

最小脚本 surface 的 Nix 配置仓库。

本页不是事实源。实际流程、脚本行为、风险边界与 FAQ 统一见 `docs/README.md`。

## 文档入口

- 新手上手：`docs/GETTING-STARTED.md`
- 权威手册：`docs/README.md`
- 环境差异：`docs/ENV-USAGE.md`
- 命令速查：`docs/NIX-COMMANDS.md`
- 快捷键摘要：`docs/KEYBINDINGS.md`
- 主机清单与目录：`nix/hosts/default.nix`、`nix/hosts/README.md`
- Home Manager 结构：`nix/home/README.md`
- 公钥与 secrets 流程：`secrets/keys/README.md`
- 代理规则：`AGENTS.md`、`CLAUDE.md`

## 当前保留入口

- 安装（引导式一键入口）：`nix/scripts/admin/bootstrap-install.sh`
- 安装（底层装盘）：`nix/scripts/admin/install-live.sh`
- filtered flake repo：`nix/scripts/admin/print-flake-repo.sh`
- `flake.lock` 更新：`nix/scripts/admin/update-flake.sh`
- secrets / sops：`nix/scripts/admin/sops.sh`
- Git secrets guard：`nix/scripts/admin/guard-secrets.sh`
- 格式/解析 sanity：`nix/scripts/admin/check-format-sanity.sh`
- `just`：update / switch / upgrade / clean / 本地验证的主要入口

## 常用命令

```bash
just update
just self-check
just validate-local
just host=zly switch
just host=zly upgrade
just clean
```

## 本地验证基线

仓库以本地验证为准。GitHub workflow（`.github/workflows/secret-guard.yml`）只跑轻量 `self-check` 与 secrets 全量巡检，不能替代本地验证。推送前至少执行：

```bash
nix develop
just self-check
just validate-local
```

需要额外执行 check build 时再跑：

```bash
nix flake check --all-systems
```

## 风险提示

- `install-live.sh` 会清盘；被清空的是 `nix/hosts/default.nix` 里该主机的 `diskDevice`，`--disk` 与之不一致时脚本直接报错退出
- `sops.sh reset` / `bootstrap-install.sh --reset-secrets` 会生成新 key 并重建密码/aria2 secret（旧 secret 作废）
- `switch` / `upgrade` 会直接改系统状态
- `sops.sh init --rotate` 会生成新 `main.agekey`
- `mise upgrade --yes` 会更新用户目录中的 flake 外工具版本
- Noctalia GUI 配置写入 `~/.local/state/noctalia/config`；该目录由 Home Manager 从 `nix/home/configs/noctalia/` 首次 seed，后续 GUI 改动不会写回 tracked config；需要更新默认 seed 时，显式复制 runtime config 回 `nix/home/configs/noctalia/` 后再提交
- `.keys/*.agekey` 不可提交；启用本地 hook 可执行 `git config core.hooksPath .githooks`

其余细节不在本页展开，统一以 `docs/README.md` 为准。
