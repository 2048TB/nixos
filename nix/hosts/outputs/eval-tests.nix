# NixOS-specific eval-test builders, extracted from x86_64-linux/default.nix.
# Each attribute is a boolean eval assertion later turned into a check derivation.
{ lib, mylib, common, args }:
let
  hostRegistryLib = import ../../lib/host-registry.nix { inherit lib; };

  registryRequiredKeyCheck =
    let
      incompleteState = hostRegistryLib.mkRegistryState {
        hostRegistry = {
          system = "x86_64-linux";
          desktopSession = false;
          desktopProfile = "none";
          kind = "server";
          formFactor = "headless";
        };
        hostMyvars = {
          gpuMode = "none";
        };
      };
      requiredFailure = builtins.tryEval (
        hostRegistryLib.assertCommonRegistry {
          registryPath = "nix/hosts/registry/systems.toml";
          hostDir = "nix/hosts/nixos/evaltest-missing-required";
          hostName = "nixos.evaltest-missing-required";
          state = incompleteState;
        }
      );
    in
    {
      required-key-list =
        incompleteState.missingRequiredRegistryKeys == [
          "tags"
          "gpuVendors"
          "displays"
        ];
      required-keys =
        !requiredFailure.success;
    };

  missingHomeUserCheck =
    let
      missingHomeConfigurations = common.mkHomeConfigurations {
        system = "x86_64-linux";
        mainUsers.evalhost = "alice";
        configurations.evalhost.config.home-manager.users = { };
      };
      missingHomeUserNamesResult = builtins.tryEval (builtins.attrNames missingHomeConfigurations);
      missingHomeUserResult = builtins.tryEval
        missingHomeConfigurations."alice@evalhost".config.home.activationPackage;
      presentHomeConfigurations = common.mkHomeConfigurations {
        system = "x86_64-linux";
        mainUsers.evalhost = "alice";
        configurations.evalhost.config.home-manager.users.alice.home.activationPackage = "ok";
      };
    in
    {
      home-config-missing-user =
        !missingHomeUserNamesResult.success
        && !missingHomeUserResult.success;
      home-config-output-name =
        builtins.hasAttr "alice@evalhost" presentHomeConfigurations;
    };

  headlessHomeCheck =
    let
      baseHeadlessMyvars = import (mylib.relativeToRoot "nix/hosts/nixos/zly/vars.nix");
      headlessHostCtx = mylib.mkNixosHost (args // {
        name = "zly";
        hostMyvars = baseHeadlessMyvars // {
          roles = [ ];
          gpuMode = "none";
          enableWpsOffice = false;
          enableZathura = false;
          enableSplayer = false;
          enableTelegramDesktop = false;
          enableLocalSend = false;
          enableAntigravity = false;
        };
        hostRegistry = {
          system = "x86_64-linux";
          desktopSession = false;
          desktopProfile = "none";
          kind = "server";
          formFactor = "headless";
          tags = [ ];
          gpuVendors = [ ];
          displays = [ ];
        };
      });
      headlessHmCfg = headlessHostCtx.nixosSystem.config.home-manager.users.${headlessHostCtx.mainUser};
      headlessServices = headlessHmCfg.systemd.user.services or { };
      headlessConfigFiles = headlessHmCfg.xdg.configFile or { };
      headlessPackageNames = map (pkg: builtins.unsafeDiscardStringContext (lib.getName pkg)) headlessHmCfg.home.packages;
      unexpectedHeadlessGuiPackages = lib.intersectLists
        headlessPackageNames
        [
          "google-chrome"
          "vscode"
          "nautilus"
          "ghostty"
          "foot"
          "fuzzel"
          "pavucontrol"
        ];
    in
    {
      headless-home-no-gui-services =
        !(builtins.hasAttr "playerctld" headlessServices)
        && !(builtins.hasAttr "udiskie" headlessServices)
        && !(builtins.hasAttr "polkit-gnome-authentication-agent-1" headlessServices)
        && !(builtins.hasAttr "aria2" headlessServices);
      headless-home-no-noctalia =
        !(headlessHmCfg.programs.noctalia-shell.enable or false);
      headless-home-no-portal =
        !(headlessHmCfg.xdg.portal.enable or false);
      headless-home-no-niri-noctalia-configs =
        !(builtins.hasAttr "niri/config.kdl" headlessConfigFiles)
        && !(builtins.hasAttr "niri/outputs.kdl" headlessConfigFiles)
        && !(builtins.hasAttr "noctalia" headlessConfigFiles);
      headless-home-no-gui-packages =
        unexpectedHeadlessGuiPackages == [ ];
    };
in
registryRequiredKeyCheck
// missingHomeUserCheck
  // headlessHomeCheck
