{ lib, mylib, inputs, system, ... }@args:
let
  common = import ../common.nix { inherit lib mylib; };
  hostsRoot = mylib.relativeToRoot "nix/hosts/nixos";
  registryState = common.mkRegistryState {
    kind = "nixos";
    inherit hostsRoot system;
    requiredFiles = [
      "hardware.nix"
      "hardware-modules.nix"
      "disko.nix"
      "vars.nix"
    ];
  };
  inherit (registryState) hostNames;

  mkHostData =
    name:
    let
      hostDir = "nix/hosts/nixos/${name}";
      hostVarsPath = mylib.relativeToRoot "${hostDir}/vars.nix";
      hostChecksPath = mylib.relativeToRoot "${hostDir}/checks.nix";
      sharedChecksPath = mylib.relativeToRoot "nix/hosts/nixos/_shared/checks.nix";
      generatedDesktopChecksPath = mylib.relativeToRoot "nix/hosts/nixos/_shared/generated-desktop-checks.nix";
      hostMyvars = import hostVarsPath;
      hostRegistry = mylib.hostRegistryEntry "nixos" name;
      hostCtx = mylib.mkNixosHost (args // {
        inherit name hostMyvars hostRegistry;
      });
      hostCheckArgs = hostCtx // { inherit (args) lib mylib; };
      hostChecks =
        (import sharedChecksPath hostCheckArgs)
        // (import generatedDesktopChecksPath hostCheckArgs)
        // (mylib.importIfExists hostChecksPath hostCheckArgs);
    in
    mylib.mkHostDataEntry {
      configAttrName = "nixosConfigurations";
      hostSystemAttr = "nixosSystem";
      inherit hostCtx hostChecks;
    };

  hostData = common.collectHostData {
    inherit hostNames mkHostData;
    configAttrName = "nixosConfigurations";
  };
  inherit (hostData) data dataWithoutPaths mainUsers resolvedHostNames;
  nixosConfigurations = hostData.configurations;
  homeConfigurations = common.mkHomeConfigurations {
    configurations = nixosConfigurations;
    inherit mainUsers system;
  };

  hostEvalTests = common.mkStandardEvalTests {
    configurations = nixosConfigurations;
    inherit mainUsers system;
    hostNames = resolvedHostNames;
    homeRoot = "/home";
    extraTests = {
      kernel =
        common.mapHostValuesByPath [ "config" "boot" "kernelPackages" "kernel" "system" ] nixosConfigurations
        == common.mkExpectedAttrSet resolvedHostNames system;
    };
  };

  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfreePredicate = mylib.allowUnfreePredicate;
  };

  extraEvalTests = import ../eval-tests.nix { inherit lib mylib common args; };
  lintChecks = import ../lint-checks.nix { inherit inputs system pkgs mylib; };
  mlShell = import ../ml-shell.nix { inherit inputs system mylib; };

  mkEvalCheck = common.mkEvalCheck pkgs;
  evalCheckSpecs = common.mkEvalCheckSpecs "" (hostEvalTests // extraEvalTests);
  evalTestChecks.${system} = mylib.specsToAttrs evalCheckSpecs mkEvalCheck;
  platformChecks.${system} = lintChecks.checks;

  defaultHost = builtins.head resolvedHostNames;
  platformDevShells.${system} = {
    default = pkgs.mkShell {
      name = "nixos-config-dev";
      packages = with pkgs; [
        nix-tree
        just
        check-jsonschema
        shellcheck
        shfmt
        nixpkgs-fmt
        statix
        deadnix
      ] ++ lintChecks.preCommitCheck.enabledPackages;
      shellHook = ''
        ${lintChecks.preCommitCheck.shellHook}
        export OPENSSL_INCLUDE_DIR="${pkgs.openssl.dev}/include"
        export OPENSSL_LIB_DIR="${pkgs.openssl.out}/lib"
        export OPENSSL_DIR="${pkgs.openssl.dev}"
        if [ -d .githooks ] && [ "$(git config core.hooksPath 2>/dev/null)" != ".githooks" ]; then
          git config core.hooksPath .githooks
        fi
        echo "NixOS config dev shell"
        echo "nixos-rebuild switch --flake .#${defaultHost}"
        echo "nixos-rebuild test --flake .#${defaultHost}"
      '';
    };

    ml = mlShell;
  };

  platformFormatter.${system} = pkgs.nixpkgs-fmt;
in
assert common.assertRegistryState
{
  state = registryState;
  registryKey = "nixos";
  kindDisplay = "NixOS";
  hostsPath = "nix/hosts/nixos";
  inherit system;
};
{
  inherit data;
  registeredHosts = resolvedHostNames;
  inherit nixosConfigurations homeConfigurations;
  apps = { };
  checks = mylib.mergeAttrFromListWithExtra "checks" dataWithoutPaths [
    evalTestChecks
    platformChecks
  ];
  devShells = mylib.mergeAttrFromListWithExtra "devShells" dataWithoutPaths [ platformDevShells ];
  formatter = mylib.mergeAttrFromListWithExtra "formatter" dataWithoutPaths [ platformFormatter ];
}
