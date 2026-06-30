# secrets/keys

本目录只放可提交到 Git 的 public keys。完整流程与脚本行为见 `docs/README.md`。

## 文件含义

- `main.age.pub`：主运维 public key
- `recovery.age.pub`：恢复 public key
- `hosts/*.ssh_host_ed25519.pub`：各主机 SSH host public keys

## 绝对不能放这里的内容

- 私钥（`*.agekey`）
- 明文密码
- 私有 token

私钥只能放在本地 `.keys/` 或运行时的 `/persistent/keys/`。

## 常用命令

```bash
bash nix/scripts/admin/sops.sh init
bash nix/scripts/admin/sops.sh init --create
bash nix/scripts/admin/sops.sh init --rotate
bash nix/scripts/admin/sops.sh reset
bash nix/scripts/admin/sops.sh recovery-init
bash nix/scripts/admin/sops.sh host-add zly /etc/ssh/ssh_host_ed25519_key.pub
bash nix/scripts/admin/sops.sh recipients
bash nix/scripts/admin/sops.sh rekey
bash nix/scripts/admin/guard-secrets.sh
bash nix/scripts/admin/guard-secrets.sh --all-tracked
```

非交互 rotate：

```bash
bash nix/scripts/admin/sops.sh init --rotate --yes
bash nix/scripts/admin/sops.sh rekey
```

## 当前 key 流程

- `init --create`：创建新的 `main.agekey` 与 `main.age.pub`
- `init --rotate`：生成新的 `main.agekey`，并保留旧 key 为 `.keys/main.agekey.pre-rotate.<timestamp>`
- `reset`：丢失 key 的恢复入口；生成新的 `main` + `recovery` key，改写 `.sops.yaml` 锚点，提示输入新密码并重建密码/aria2 secret（旧 secret 永久作废）
- `rekey`：使用当前 key、recovery key 与 backup keys，把所有 secrets recipients 同步到最新集合
- `install-live.sh`：安装时只接受“与 `main.age.pub` 匹配”的 private key

secret 路径分层：

- `secrets/common/...`：共享 secret
- `secrets/hosts/<hostname>/...`：主机级 secret 预留路径
- `secrets/users/<username>/...`：用户级 secret
- `secrets/install/...`：安装 / 恢复流程 secret

key 搜索顺序：

- `./.keys/main.agekey`
- `<repo>/.keys/main.agekey`
- `~/.keys/main.agekey`

## 额外约束

- `nix/scripts/admin/sops.sh` 可从仓库外直接调用
- `hosts/*.ssh_host_ed25519.pub` 若内容无效，`recipients` / `rekey` 会直接失败
- `guard-secrets.sh` 默认检查 staged，`--all-tracked` 用于全量巡检
