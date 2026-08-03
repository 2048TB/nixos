{ lib, mylib, inputs, system, ... }@args:
let
  common = import ../common.nix { inherit lib mylib; };
  # 主机来源 = 清单（nix/hosts/default.nix）中 system 匹配的条目。
  platformHosts = lib.filterAttrs (_: host: (host.system or "") == system) mylib.hosts.darwin;
  hostNames = builtins.attrNames platformHosts;

  mkHostData =
    name:
    let
      hostDir = "nix/hosts/darwin/${name}";
      hostPath = mylib.relativeToRoot "${hostDir}/default.nix";
      hostChecksPath = mylib.relativeToRoot "${hostDir}/checks.nix";
      hostMyvars = platformHosts.${name};
      hostCtx = mylib.mkDarwinHost (args // {
        inherit name hostPath hostMyvars;
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
  inherit (hostData) dataWithoutPaths mainUsers resolvedHostNames;
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
{
  inherit darwinConfigurations homeConfigurations;
  apps = { };
  checks = mylib.mergeAttrFromListWithExtra "checks" dataWithoutPaths [ evalTestChecks ];
  devShells = mylib.mergeAttrFromListWithExtra "devShells" dataWithoutPaths [ ];
  formatter = mylib.mergeAttrFromListWithExtra "formatter" dataWithoutPaths [ ];
}
