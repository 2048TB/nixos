{ lib, pkgs, mylib, mainUser, ... }:
let
  configFiles = import ../base/config-files.nix;
  homeDir = "/Users/${mainUser}";
  brewPath = "/opt/homebrew/bin:/usr/local/bin";

  darwinExtraNames = [
    "neovim"

    # CLI tools
    "delta"
    "tealdeer"
    "procs"
  ];

  desiredPackageNames = mylib.sharedPackageNames ++ darwinExtraNames;
  packageSelection = mylib.resolvePackagesByName pkgs desiredPackageNames;
  sourceConfigFiles =
    lib.mapAttrs (_: source: { inherit source; })
      (configFiles.sharedSourceFiles // configFiles.darwinSourceFiles);
in
{
  imports = [
    ../base
  ];

  warnings = lib.optionals (packageSelection.skippedNames != [ ]) [
    "Darwin skipped unsupported packages: ${lib.concatStringsSep ", " packageSelection.skippedNames}"
  ];

  home = {
    # 与 Linux 侧保持一致：release 检查始终开启（原先的 enableHmReleaseCheck 键无主机使用）。
    enableNixpkgsReleaseCheck = true;
    username = mainUser;
    homeDirectory = homeDir;

    sessionPath = [
      "/opt/homebrew/bin"
      "/usr/local/bin"
    ];

    inherit (packageSelection) packages;
  };

  programs = {
    zsh.envExtra = ''
      export PATH="$PATH:${brewPath}"
    '';

    bash = {
      enable = true;
      bashrcExtra = ''
        export PATH="$PATH:${brewPath}"
      '';
    };
  };

  xdg.configFile = sourceConfigFiles;
}
