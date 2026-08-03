# AGENTS.md

面向人类贡献者与自动化代理。

## 事实源

仓库事实、脚本行为、环境差异与 FAQ 统一以 `docs/README.md` 为准。不要在本文件重复维护仓库事实。

主题入口：

- `docs/README.md`
- `docs/GETTING-STARTED.md`
- `docs/ENV-USAGE.md`
- `docs/NIX-COMMANDS.md`
- `docs/KEYBINDINGS.md`
- `nix/hosts/README.md`
- `nix/hosts/nixos/README.md`
- `nix/home/README.md`
- `secrets/keys/README.md`

## 代理工作规则

- 最小改动优先，不做无关重构
- 先验证事实源，再动共享接口
- 文档涉及命令入口时，先以 `justfile` 与 `nix/scripts/admin/*.sh` 为事实源再更新文案
- read-only `eval` / `show` / `build` 优先走 `print-flake-repo.sh`
- 显式传入的 `--repo` / `NIXOS_CONFIG_REPO` 若无效，应直接视为错误
- 不提交私钥、token、明文密码
- `secrets/` 下加密后的 `*.yaml` 可提交，`.keys/*.agekey` 不可提交

## 文档同步规则

改动以下内容时，必须同步相应文档：

- 运维流程、脚本语义、风险边界：`docs/README.md`
- 环境差异：`docs/ENV-USAGE.md`
- `just` 命令与速查：`docs/NIX-COMMANDS.md`
- 快捷键：`docs/KEYBINDINGS.md`
- VPN / Mullvad app：`docs/README.md`、`docs/NIX-COMMANDS.md`
- hosts 结构或 metadata：`nix/hosts/README.md`、必要时 `nix/hosts/nixos/README.md`
- Home Manager 结构：`nix/home/README.md`
- key 流程：`secrets/keys/README.md`
- 代理规则：`AGENTS.md`、`CLAUDE.md`

## 提交与验证

- Conventional Commit：`feat:`、`fix:`、`docs:`、`refactor:`
- 每次提交只做一个主题
- 仓库当前以本地验证为准；推送前至少执行 `just self-check` 与 `just validate-local`
- 需要包含 check build 时执行 `nix flake check --all-systems`
- 文档批量改动后，至少执行一次过时关键词检索（如旧 `just` 命令、`validate-local-full`、旧 secrets 路径）确认无漂移残留
- 用户要求同步时，验证通过后提交并执行 `git push origin HEAD`
- 不要在没有验证证据时声称完成
