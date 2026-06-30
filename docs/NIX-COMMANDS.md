# Nix 命令速查

只列命令，不写背景。行为说明与风险边界见 `docs/README.md`，环境差异见 `docs/ENV-USAGE.md`。

## 1. 日常 `just` 入口

```bash
just update
just host=zly upgrade
just host=zly switch
just clean
just self-check
just validate-local
```

## 2. 安装

```bash
# 引导式一键安装（飞行前检查 + 委托 install-live.sh；丢失 key 时加 --reset-secrets）
bash /persistent/nixos-config/nix/scripts/admin/bootstrap-install.sh --host zly --disk /dev/nvme0n1
bash /persistent/nixos-config/nix/scripts/admin/install-live.sh --host zly --disk /dev/nvme0n1 --repo /persistent/nixos-config
```

## 3. 手动 flake / lock 操作

```bash
REPO=/persistent/nixos-config
flake_repo="$(bash "$REPO/nix/scripts/admin/print-flake-repo.sh" "$REPO")"

nix flake show "path:$flake_repo"
nix flake check --all-systems --no-build "path:$flake_repo"
nix flake check --all-systems "path:$flake_repo"
nix build "path:$flake_repo#checks.x86_64-linux.pre-commit-check"
nix build "path:$flake_repo#checks.x86_64-linux.format-sanity"
nix eval "path:$flake_repo#nixosConfigurations" --apply builtins.attrNames
```

```bash
bash "$REPO/nix/scripts/admin/update-flake.sh" "$REPO"
bash "$REPO/nix/scripts/admin/update-flake.sh" "$REPO" nixpkgs
bash "$REPO/nix/scripts/admin/check-format-sanity.sh" --repo "$REPO"
bash "$REPO/nix/scripts/admin/host-meta-schema-sync.sh"
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#check-jsonschema -c check-jsonschema --schemafile "$REPO/nix/hosts/registry/systems.schema.json" "$REPO/nix/hosts/registry/systems.toml"
```

## 4. 系统切换与清理

```bash
just host=zly switch
just host=zly upgrade
just clean
```

```bash
flake_repo="$(bash /persistent/nixos-config/nix/scripts/admin/print-flake-repo.sh /persistent/nixos-config)"
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#nh -c nh os switch "path:$flake_repo" -H zly
nix --extra-experimental-features 'nix-command flakes' shell nixpkgs#nh -c nh clean all --keep-since 30d --keep 15
sudo nix store gc
sudo nix store optimise
```

`clean` 保留最近 30 天且至少 15 个 generation，和
`boot.loader.systemd-boot.configurationLimit = 15` 对齐。

## 5. `sops`

```bash
bash /persistent/nixos-config/nix/scripts/admin/sops.sh init
bash /persistent/nixos-config/nix/scripts/admin/sops.sh init --create
bash /persistent/nixos-config/nix/scripts/admin/sops.sh init --rotate
bash /persistent/nixos-config/nix/scripts/admin/sops.sh reset
bash /persistent/nixos-config/nix/scripts/admin/sops.sh recovery-init
bash /persistent/nixos-config/nix/scripts/admin/sops.sh host-add zly /etc/ssh/ssh_host_ed25519_key.pub
bash /persistent/nixos-config/nix/scripts/admin/sops.sh recipients
bash /persistent/nixos-config/nix/scripts/admin/sops.sh rekey
bash /persistent/nixos-config/nix/scripts/admin/sops.sh password-set '<sha512-hash>'
bash /persistent/nixos-config/nix/scripts/admin/sops.sh ssh-key-set
```

非交互 rotate：

```bash
bash /persistent/nixos-config/nix/scripts/admin/sops.sh init --rotate --yes
bash /persistent/nixos-config/nix/scripts/admin/sops.sh rekey
```

## 6. Git Secrets Guard

```bash
git config core.hooksPath .githooks
git check-ignore .keys/main.agekey
bash /persistent/nixos-config/nix/scripts/admin/guard-secrets.sh
bash /persistent/nixos-config/nix/scripts/admin/guard-secrets.sh --all-tracked
```

## 7. Noctalia

```bash
noctalia-shell ipc call state all | jq .settings
jq empty "$HOME/.local/state/noctalia/config"/*.json
cp -a "$HOME/.local/state/noctalia/config/." /persistent/nixos-config/nix/home/configs/noctalia/
jq empty /persistent/nixos-config/nix/home/configs/noctalia/*.json
git -C /persistent/nixos-config diff --check -- nix/home/configs/noctalia
```

`~/.local/state/noctalia/config` 是 GUI runtime config；`nix/home/configs/noctalia/` 只作为新环境 seed。提交前先 review `git diff -- nix/home/configs/noctalia`。

## 8. Mullvad VPN

启用 `"vpn"` role 的主机通过 `services.mullvad-vpn.package = pkgs.mullvad-vpn` 安装 Mullvad CLI/GUI 并启用 `mullvad-daemon`。连接、地区选择、恢复和 kill switch 交给 Mullvad app / daemon 管理。

```bash
mullvad status
mullvad account get
mullvad relay list
mullvad relay set location jp
mullvad lockdown-mode get
mullvad dns get
mullvad lan get
mullvad connect
mullvad disconnect
mullvad reconnect
wg --version
```
