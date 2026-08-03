# outputs 目录

本目录负责把主机清单（`nix/hosts/default.nix`）聚合成 flake outputs。它不是日常改机器参数的第一落点。

## 主要文件

- `default.nix`：总入口
- `common.nix`：共享 eval helper 与 host-data 组装（`collectHostData`）
- `x86_64-linux/default.nix`：NixOS 聚合（薄编排）、checks、devShells
- `aarch64-darwin/default.nix`：Darwin 聚合、checks
- `ml-shell.nix`：CUDA ML devShell（从 x86_64 入口拆出）
- `eval-tests.nix`：headless 主机防 GUI 泄漏的 eval-test
- `lint-checks.nix`：pre-commit / format-sanity check 构造（从 x86_64 入口拆出）

## 主机发现

主机来源 = 清单中 `system` 匹配当前平台的条目：

- `nix/hosts/default.nix` 的 `nixos.*` → `x86_64-linux`
- `nix/hosts/default.nix` 的 `darwin.*` → `aarch64-darwin`

清单条目对应的主机目录缺文件（如 `hardware.nix`）时，组装会直接报错并指出缺哪个文件；只有目录、没有清单条目的主机不会被构建。

## 当前导出面

- `nixosConfigurations`
- `darwinConfigurations`
- `homeConfigurations`
- `apps`
- `checks`
- `formatter`
- `packages`
- `overlays`
- `nixosModules`
- `devShells`

当前 `apps` 行为：

- Linux 与 Darwin 均不导出 app（旧的 `install` app 已移除，安装走 `nix/scripts/admin/bootstrap-install.sh`）

当前 `devShells` 行为：

- Linux：导出 `default` 与 `ml`
- `default` 提供 `just`、`shellcheck`、`shfmt`、`nixpkgs-fmt`、`statix`、`deadnix` 等本地维护工具
- `ml` 只覆盖主训练栈；`bitsandbytes`、`vLLM`、`llama.cpp` 不在默认 shell 中
- Darwin：不导出 dev shell

当前平台级 `checks`：

- `pre-commit-check`：构建并执行 pre-commit hooks
- `format-sanity`：执行 `nix/scripts/admin/check-format-sanity.sh`，覆盖 shell shebang、YAML/JSON 解析、Markdown trailing whitespace、`justfile` 与 Nix 注释吞代码启发式检查；命中时作为失败处理
- `evaltest-*`：每台主机的 hostname/home/platform/kernel eval 断言 + headless 防 GUI 泄漏检查

## 什么时候改这里

- 新增平台级 `apps` / `checks`
- 增减对外复用导出面

如果只是新增主机或改某台机器参数，去：

- `nix/hosts/default.nix`（清单条目）
- `nix/hosts/<platform>/<host>/`（硬件描述）
