#!/usr/bin/env bash
set -euo pipefail

# bootstrap-install.sh — 一条命令完成 Live ISO 安装的友好包装器。
#
# 它只做两件事：
#   1. 飞行前检查：用大白话确认 repo、磁盘、sops key、密码 secret 都就位，
#      缺什么就直接给出要执行的命令，而不是让你在装盘途中撞见难懂的报错。
#   2. 把真正会清空磁盘的步骤交给 install-live.sh（确认与 key 校验都在那里，
#      此脚本不重复实现，也不会自动改动加密的密码文件）。

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$script_dir/common.sh"

usage() {
  cat <<'EOF'
usage:
  bootstrap-install.sh --host <name> --disk <device> [--repo <path>] [--yes]

examples:
  bash nix/scripts/admin/bootstrap-install.sh --host zly --disk /dev/nvme0n1

说明：
  - --host   目标主机名（如 zly / zky / zl / zzly）
  - --disk   目标磁盘（如 /dev/nvme0n1）；会被清空
  - --repo   仓库路径，默认当前目录
  - --yes    跳过确认（自动化场景）；交给 install-live.sh 处理
  - --reset-secrets  没有 sops key 时，生成新 key 并重建密码/aria2 secret
                     （丢失 key 的恢复场景；会提示你输入新密码）
EOF
}

host=""
disk=""
repo="${NIXOS_CONFIG_REPO:-$PWD}"
repo_explicit=0
assume_yes=0
age_key_rel=".keys/main.agekey"
reset_secrets=0

while [ "$#" -gt 0 ]; do
  case "$1" in
  --host)
    [ "$#" -ge 2 ] || {
      echo "error: --host requires a value" >&2
      exit 2
    }
    host="$2"
    shift 2
    ;;
  --disk)
    [ "$#" -ge 2 ] || {
      echo "error: --disk requires a value" >&2
      exit 2
    }
    disk="$2"
    shift 2
    ;;
  --repo)
    [ "$#" -ge 2 ] || {
      echo "error: --repo requires a value" >&2
      exit 2
    }
    repo="$2"
    repo_explicit=1
    shift 2
    ;;
  --yes)
    assume_yes=1
    shift
    ;;
  --reset-secrets)
    reset_secrets=1
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "error: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

if [ -z "$host" ] || [ -z "$disk" ]; then
  echo "error: --host and --disk are required" >&2
  usage >&2
  exit 2
fi

if ! is_valid_host_name "$host"; then
  echo "error: invalid host name '$host'" >&2
  exit 2
fi

if [ "$repo_explicit" -eq 1 ] || [ -n "${NIXOS_CONFIG_REPO:-}" ]; then
  repo="$(resolve_repo_path "$repo")"
else
  repo="$(resolve_repo_path)"
fi

fail_with_hint() {
  echo "" >&2
  echo "✗ 飞行前检查未通过：$1" >&2
  shift
  for line in "$@"; do
    echo "  $line" >&2
  done
  exit 1
}

# 1. repo 必须是 Git checkout（install-live.sh 用 tracked-file allowlist 同步）。
if ! git -C "$repo" rev-parse --show-toplevel >/dev/null 2>&1; then
  fail_with_hint "仓库不是 Git checkout：$repo" \
    "请用 git clone 得到仓库，再在仓库目录内运行本脚本。"
fi

# 2. 主机注册检查：host 必须在 vars.nix 存在。
if [ ! -f "$repo/nix/hosts/nixos/$host/vars.nix" ]; then
  fail_with_hint "未找到主机 '$host' 的配置：nix/hosts/nixos/$host/vars.nix" \
    "可用主机：$(find "$repo/nix/hosts/nixos" -maxdepth 1 -mindepth 1 -type d ! -name '_*' -printf '%f ' 2>/dev/null)"
fi

# 3. sops main.agekey：能找到就用；找不到则在确认后生成新 key 并重建 secret。
key_found=""
for cand in "$PWD/$age_key_rel" "$repo/$age_key_rel" "${HOME:-}/$age_key_rel"; do
  [ -n "$cand" ] || continue
  if [ -f "$cand" ]; then
    key_found="$cand"
    break
  fi
done

did_reset=0
if [ -z "$key_found" ]; then
  do_reset="$reset_secrets"
  if [ "$do_reset" -ne 1 ]; then
    if [ -t 0 ]; then
      echo "未找到 sops 私钥 main.agekey。" >&2
      printf '是否生成新 key 并重建密码/aria2 secret？这会让旧 secret 永久作废。[y/N] ' >&2
      IFS= read -r ans
      case "$ans" in
      y | Y | yes | YES) do_reset=1 ;;
      *) do_reset=0 ;;
      esac
    fi
  fi
  if [ "$do_reset" -eq 1 ]; then
    echo ">>> 运行 sops.sh reset（会提示你输入新密码）"
    NIXOS_CONFIG_REPO="$repo" bash "$script_dir/sops.sh" reset --yes
    did_reset=1
    key_found="$repo/$age_key_rel"
  else
    fail_with_hint "未找到 sops 私钥 main.agekey" \
      "把与 secrets/keys/main.age.pub 匹配的私钥放到以下任一路径：" \
      "  ./$age_key_rel  或  $repo/$age_key_rel  或  ~/$age_key_rel" \
      "或加 --reset-secrets 生成新 key 并重建 secret（旧 secret 会作废）。"
  fi
fi

# 4. 密码 secret 必须存在（若刚 reset 过，已一并重建）。
if [ "$did_reset" -ne 1 ]; then
  missing_password=0
  for f in user-password.yaml root-password.yaml; do
    [ -f "$repo/secrets/common/passwords/$f" ] || missing_password=1
  done
  if [ "$missing_password" -eq 1 ]; then
    fail_with_hint "缺少密码 secret（secrets/common/passwords/*.yaml）" \
      "用 --reset-secrets 可在装机时一并重建，或先手动创建：" \
      "  bash nix/scripts/admin/sops.sh reset" \
      "详见 docs/README.md 第 5 节。"
  fi
fi

echo "✓ 飞行前检查通过"
echo "  host = $host"
echo "  disk = $disk"
echo "  repo = $repo"
echo "  key  = $key_found"
echo ""
echo ">>> 交给 install-live.sh（它会再次确认并校验 key，然后清空磁盘并安装）"

install_args=(--host "$host" --disk "$disk" --repo "$repo")
if [ "$assume_yes" -eq 1 ]; then
  install_args+=(--yes)
fi
exec bash "$script_dir/install-live.sh" "${install_args[@]}"
