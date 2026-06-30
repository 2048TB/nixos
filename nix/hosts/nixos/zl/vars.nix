let
  common = import ../_shared/vars-common.nix;
in
common // {
  # Storage
  # 128GB RAM; 台式机不启用 hibernate，不设 resumeOffset
  swapSizeGb = 128;

  # Hardware
  # Pure AMD (5950X + 6900XT): gpuMode defaults to "amdgpu" via hardware-modules.nix.
  dockerMode = "rootless";

  # Roles
  roles = [
    "gaming"
    "vpn"
    "virt"
    "container"
  ];

  # App toggles (zl)
  enableWpsOffice = true;
  enableZathura = true;
  enableSplayer = true;
  enableTelegramDesktop = true;
  enableLocalSend = true;

  # Credentials are managed by sops secrets:
  # - secrets/common/passwords/user-password.yaml
  # - secrets/common/passwords/root-password.yaml
}
