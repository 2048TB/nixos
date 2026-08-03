_:
{
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.z.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPhqRZRhyOdP8+cS1rnoGA5vBT4HqArKOs6jaId/DB1h zly-mac-to-nixos"
  ];
}
