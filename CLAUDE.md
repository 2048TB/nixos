# CLAUDE.md

AI/自动化工具专用。

## 事实源

仓库事实统一以 `docs/README.md` 为准；本文件只保留代理执行规则，不重复维护流程事实。

关联入口：

- `docs/README.md`
- `docs/GETTING-STARTED.md`
- `docs/ENV-USAGE.md`
- `docs/NIX-COMMANDS.md`
- `docs/KEYBINDINGS.md`
- `nix/hosts/README.md`
- `nix/hosts/nixos/README.md`
- `nix/home/README.md`
- `secrets/keys/README.md`
- `AGENTS.md`

## 工作边界

- 只做用户明确要求的改动
- 默认最小 diff
- 优先复用现有脚本、模块和文档入口
- 文档涉及命令入口时，先以 `justfile` 与 `nix/scripts/admin/*.sh` 为事实源
- 对共享接口先读调用点，再动实现

## 文档同步

只要改动了用户可见行为、脚本语义、命令入口或目录职责，就同步对应文档；`docs/README.md` 是第一同步目标。VPN / Mullvad app 变更需同步 `docs/README.md` 与 `docs/NIX-COMMANDS.md`。

## 安全规则

- 禁止提交私钥、token、明文密码
- `secrets/` 下加密后的 `*.yaml` 可提交，`.keys/*.agekey` 不可提交
- 安装、分区、`switch`、`boot`、`test`、`upgrade` 属于危险操作
- `hosts/*.ssh_host_ed25519.pub` 无效时，`sops` 相关操作应直接失败

## 验证要求

- 文档改动至少做一致性检查与过时表述搜索
- 脚本或配置改动必须做对应执行验证
- 推送前至少执行 `just self-check` 与 `just validate-local`
- 需要包含 check build 时执行 `nix flake check --all-systems`
- 文档批量改动后，至少执行一次过时关键词检索（如旧 `just` 命令、`validate-local-full`、旧 secrets 路径）
- read-only `eval` / `show` / `build` 优先走 `print-flake-repo.sh`
- 没有足够证据时，不要声称完成

## 执行提醒

- 显式传入的 `--repo` / `NIXOS_CONFIG_REPO` 必须有效
- 当前仓库只保留少量 `nix/scripts/admin/*.sh` 入口；日常 update / switch / upgrade / clean 通过 `just` 暴露
- 未被要求时不主动推送；用户要求同步时，验证通过后再执行 commit 和 `git push origin HEAD`
