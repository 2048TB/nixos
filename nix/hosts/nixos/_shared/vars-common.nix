{
  # Identity
  username = "z";
  timezone = "Asia/Shanghai";
  locale = "zh_CN.UTF-8";

  # State versions (all current NixOS hosts share these; override per host if needed)
  systemStateVersion = "25.11";
  homeStateVersion = "25.11";

  # Storage / Hibernate
  diskDevice = "/dev/nvme0n1";
  swapSizeGb = 32;

  # Default app toggles
  enableWpsOffice = false;
  enableZathura = false;
  enableSplayer = false;
  enableTelegramDesktop = false;
  enableLocalSend = false;

}
