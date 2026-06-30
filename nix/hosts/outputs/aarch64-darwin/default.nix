{ lib, mylib, inputs, system, ... }@args:
let
  common = import ../common.nix { inherit lib mylib; };
  hostsRoot = mylib.relativeToRoot "nix/hosts/darwin";
  registryState = common.mkRegistryState {
    kind = "darwin";
    inherit hostsRoot system;
    requiredFiles = [
      "default.nix"
      "vars.nix"
    ];
  };
  inherit (registryState) hostNames;

  mkHostData =
    name:
    let
      hostDir = "nix/hosts/darwin/${name}";
      hostPath = mylib.relativeToRoot "${hostDir}/default.nix";
      hostVarsPath = mylib.relativeToRoot "${hostDir}/vars.nix";
      hostChecksPath = mylib.relativeToRoot "${hostDir}/checks.nix";
      hostMyvars = import hostVarsPath;
      hostRegistry = mylib.hostRegistryEntry "darwin" name;
      hostCtx = mylib.mkDarwinHost (args // {
        inherit name hostPath hostMyvars hostRegistry;
      });
      hostChecks = mylib.importIfExists hostChecksPath (hostCtx // { inherit (args) lib mylib; });
    in
    mylib.mkHostDataEntry {
      configAttrName = "darwinConfigurations";
      hostSystemAttr = "darwinSystem";
      inherit hostCtx hostChecks;
    };

  hostData = common.collectHostData {
    inherit hostNames mkHostData;
    configAttrName = "darwinConfigurations";
  };
  inherit (hostData) data dataWithoutPaths mainUsers resolvedHostNames;
  darwinConfigurations = hostData.configurations;
  homeConfigurations = common.mkHomeConfigurations {
    configurations = darwinConfigurations;
    inherit mainUsers system;
  };
  hostEvalTests = common.mkStandardEvalTests {
    configurations = darwinConfigurations;
    inherit mainUsers system;
    hostNames = resolvedHostNames;
    homeRoot = "/Users";
  };
  pkgs = import inputs.nixpkgs-darwin {
    inherit system;
    config.allowUnfreePredicate = mylib.allowUnfreePredicate;
  };
  mkEvalCheck = common.mkEvalCheck pkgs;
  evalCheckSpecs = common.mkEvalCheckSpecs "darwin-" hostEvalTests;
  evalTestChecks.${system} = mylib.specsToAttrs evalCheckSpecs mkEvalCheck;
in
assert common.assertRegistryState
{
  state = registryState;
  registryKey = "darwin";
  kindDisplay = "Darwin";
  hostsPath = "nix/hosts/darwin";
  inherit system;
};
{
  inherit data;
  registeredHosts = resolvedHostNames;
  inherit darwinConfigurations homeConfigurations;
  apps = { };
  checks = mylib.mergeAttrFromListWithExtra "checks" dataWithoutPaths [ evalTestChecks ];
  devShells = mylib.mergeAttrFromListWithExtra "devShells" dataWithoutPaths [ ];
  formatter = mylib.mergeAttrFromListWithExtra "formatter" dataWithoutPaths [ ];
}
