let
  common = import ../_shared/vars-common.nix;
in
common // {
  # zky 独立主机变量（保持与 zly 同结构，便于对比与后续分化）

  # Storage / Hibernate
  resumeOffset = 2990172;

  # Hardware
  gpuMode = "nvidia";
  nvidiaOpen = true;

  # Roles
  roles = [
    "vpn"
  ];

  # Credentials are managed by sops secrets:
  # - secrets/common/passwords/user-password.yaml
  # - secrets/common/passwords/root-password.yaml
}
