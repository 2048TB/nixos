{ config
, pkgs
, lib
, mylib
, ...
}:
let
  hostCfg = config.my.host;
  roleFlags = mylib.roleFlags hostCfg;
  inherit (roleFlags) enableMullvadVpn enableLibvirtd enableDocker useRootfulDocker;
  inherit (config.my.capabilities) hasDesktopSession hasFingerprintReader;
  enableFlatpak = hasDesktopSession;
  hibernateEnabled = hostCfg.resumeOffset != null;
  swapfileResumeCheck = pkgs.writeShellScript "swapfile-resume-check" ''
    set -eu

    status=0
    target_size_bytes=$(( ${toString hostCfg.swapSizeGb} * 1024 * 1024 * 1024 ))

    if [ ! -f /swap/swapfile ]; then
      echo "ERROR: /swap/swapfile is missing on host ${hostCfg.hostname}; hibernate resume is configured but cannot be verified." >&2
      exit 1
    fi

    current_size_bytes="$(${pkgs.coreutils}/bin/stat -c %s /swap/swapfile 2>/dev/null || echo 0)"
    if [ "$current_size_bytes" -ne "$target_size_bytes" ]; then
      echo "ERROR: /swap/swapfile size ($current_size_bytes bytes) != configured ${toString hostCfg.swapSizeGb}GiB ($target_size_bytes bytes) on host ${hostCfg.hostname}." >&2
      echo "ERROR: recreate swapfile and refresh my.host.resumeOffset before relying on hibernate." >&2
      status=1
    fi

    configured_resume_offset="${if hostCfg.resumeOffset != null then toString hostCfg.resumeOffset else ""}"
    if [ -n "$configured_resume_offset" ]; then
      actual_resume_offset="$(${pkgs.btrfs-progs}/bin/btrfs inspect-internal map-swapfile -r /swap/swapfile 2>/dev/null | ${pkgs.coreutils}/bin/head -n 1 || true)"
      case "$actual_resume_offset" in
        ""|*[!0-9]*)
          echo "ERROR: failed to read actual /swap/swapfile resume offset on host ${hostCfg.hostname}." >&2
          status=1
          ;;
        *)
          if [ "$actual_resume_offset" != "$configured_resume_offset" ]; then
            echo "ERROR: my.host.resumeOffset ($configured_resume_offset) != actual swapfile resume offset ($actual_resume_offset) on host ${hostCfg.hostname}." >&2
            echo "ERROR: update nix/hosts/default.nix (nixos.${hostCfg.hostname}): resumeOffset = $actual_resume_offset;" >&2
            status=1
          fi
          ;;
      esac
    fi

    exit "$status"
  '';
in
{
  preservation.enable = true;
  preservation.preserveAt = {
    "/persistent" = {
      directories = [
        "/root"
        "/etc/NetworkManager/system-connections"
        "/etc/ssh"
        "/etc/secureboot"

        "/var/log"
        "/var/cache/fontconfig"
        "/var/lib/nixos"
        "/var/lib/systemd"
        "/var/lib/NetworkManager"
        "/var/lib/bluetooth"
      ]
      ++ lib.optionals enableLibvirtd [
        "/var/lib/libvirt"
      ]
      ++ lib.optionals (enableDocker && useRootfulDocker) [
        "/var/lib/docker"
      ]
      ++ lib.optionals enableMullvadVpn [
        "/etc/mullvad-vpn"
        "/var/cache/mullvad-vpn"
      ]
      ++ lib.optionals enableFlatpak [
        "/var/lib/flatpak"
      ]
      ++ lib.optionals hasFingerprintReader [
        "/var/lib/fprint"
      ];
      files = [
        {
          file = "/etc/machine-id";
          inInitrd = true;
        }
      ];
    };
  };

  # /etc/machine-id 已持久化到 /persistent；systemd-machine-id-commit 仅适用于临时 machine-id。
  # 保留该服务会在 switch 阶段误报失败并导致 nixos-rebuild 返回非零。
  systemd.services.systemd-machine-id-commit.enable = lib.mkForce false;

  fileSystems = {
    "/" = lib.mkForce {
      device = "tmpfs";
      fsType = "tmpfs";
      options = [
        "relatime"
        "mode=755"
        "size=8G"
      ];
    };

    "/swap" = lib.mkForce {
      device =
        if config.fileSystems ? "/nix" && config.fileSystems."/nix" ? device
        then config.fileSystems."/nix".device
        else hostCfg.luksMapperDevice;
      fsType = "btrfs";
      options = [
        "subvol=@swap"
        "noatime"
        "nodatacow"
        "compress=no"
      ];
    };

    "/persistent" = {
      neededForBoot = lib.mkDefault true;
    };

    "/home" = {
      neededForBoot = lib.mkDefault true;
    };
  };

  swapDevices = [{ device = "/swap/swapfile"; }];

  # 全局内存调优（gaming role 用更低的 swappiness=10 覆盖）
  boot.kernel.sysctl."vm.swappiness" = lib.mkDefault 20;

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    priority = 100;
    memoryPercent = 50;
  };

  system.activationScripts = {
    createSwapfileIfMissing = {
      text = ''
        if [ -d /swap ] && [ ! -f /swap/swapfile ]; then
          ${pkgs.btrfs-progs}/bin/btrfs filesystem mkswapfile \
            --size ${toString hostCfg.swapSizeGb}g \
            --uuid clear \
            /swap/swapfile
          chmod 600 /swap/swapfile
        fi
      '';
      deps = [ "specialfs" ];
    };
  };

  systemd.services.swapfile-resume-check = lib.mkIf hibernateEnabled {
    description = "Check swapfile size and resume offset for hibernate";
    wantedBy = [ "multi-user.target" ];
    after = [
      "local-fs.target"
      "swap-swapfile.swap"
    ];
    wants = [ "swap-swapfile.swap" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${swapfileResumeCheck}";
    };
  };
}
