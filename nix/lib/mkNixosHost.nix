# 把清单条目（nix/hosts/default.nix）+ 主机目录组装成一个 nixosSystem。
# 元数据字段的取值校验在模块层（modules/core/options.nix + assertions.nix）；
# 这里只断言「目录结构完整」与「身份字段存在」这类组装前提。
{ lib }:
{ inputs
, mylib
, genSpecialArgs
, system
, name
, hostPath ? null
, hostMyvars ? { }
, extraModules ? [ ]
, homeModules ? [ (mylib.relativeToRoot "nix/home/linux") ]
, nixpkgsOverlays ? [ ]
, nixpkgsConfig ? { inherit (mylib) allowUnfreePredicate; }
, ...
}:
let
  inherit (inputs)
    nixpkgs
    nixos-hardware
    preservation
    lanzaboote
    nix-gaming
    disko
    sops-nix
    home-manager
    ;

  manifestLabel = "nix/hosts/default.nix[nixos.${name}]";
  hostDir = "nix/hosts/nixos/${name}";
  hostDefaultPath = mylib.relativeToRoot "${hostDir}/default.nix";
  hostEntryPath =
    if hostPath != null then
      hostPath
    else if builtins.pathExists hostDefaultPath then
      hostDefaultPath
    else
      null;
  hostHardwarePath = mylib.relativeToRoot "${hostDir}/hardware.nix";
  hostHardwareModulesPath = mylib.relativeToRoot "${hostDir}/hardware-modules.nix";
  hostDiskoPath = mylib.relativeToRoot "${hostDir}/disko.nix";
  hostHomePath = mylib.relativeToRoot "${hostDir}/home.nix";
  hostHardwareModuleNames = import hostHardwareModulesPath;
  cpuVendor = mylib.cpuVendorFromHardwareModules hostHardwareModuleNames;
  hostHardwareModules =
    map
      (moduleName:
        lib.attrByPath [ moduleName ] (throw "Unknown nixos-hardware module '${moduleName}' in ${hostDir}/hardware-modules.nix")
          nixos-hardware.nixosModules
      )
      hostHardwareModuleNames;

  resolvedMyvars = hostMyvars // {
    hostname = name;
  };
  roleFlags = mylib.roleFlags resolvedMyvars;
  hasDesktopSession = resolvedMyvars.desktopSession or false;
  secureBootCfg = resolvedMyvars.secureBoot or { };
  enableSecureBoot = secureBootCfg.enable or false;
  mainUser = resolvedMyvars.username;

  baseSpecialArgs = genSpecialArgs system;
  specialArgs = baseSpecialArgs // {
    myvars = resolvedMyvars;
    inherit mainUser cpuVendor;
  };

  resolvedHomeModules = homeModules ++ lib.optionals (builtins.pathExists hostHomePath) [ hostHomePath ];

  nixpkgsModule = {
    nixpkgs = {
      config = nixpkgsConfig;
      overlays = nixpkgsOverlays;
    };
  };

  hostModules = [
    nixpkgsModule
    (mylib.relativeToRoot "nix/modules/core")
    ({ modulesPath, ... }: { imports = [ (modulesPath + "/installer/scan/not-detected.nix") ]; })
    # 这些模块主要声明 options；实际启用由 core/host 配置控制。
    # preservation 与 disko 是当前 NixOS host 布局契约，sops-nix 被 core/secrets.nix 消费。
    preservation.nixosModules.default
    sops-nix.nixosModules.sops
    disko.nixosModules.disko
  ]
  ++ lib.optionals hasDesktopSession [
    # pipewireLowLatency only defines the lowLatency option used by desktop audio;
    # services.pipewire.lowLatency still controls whether it is enabled.
    nix-gaming.nixosModules.pipewireLowLatency
  ]
  ++ lib.optionals roleFlags.enableSteam [
    nix-gaming.nixosModules.platformOptimizations
  ]
  ++ lib.optionals enableSecureBoot [
    # Import lanzaboote only for hosts that explicitly opt in via the manifest.
    lanzaboote.nixosModules.lanzaboote
  ]
  ++ lib.optionals (hostEntryPath != null) [ hostEntryPath ]
  ++ lib.optionals (hostEntryPath == null) [
    hostHardwarePath
    hostDiskoPath
  ]
  ++ hostHardwareModules
  ++ extraModules;

  nixosSystem = nixpkgs.lib.nixosSystem {
    inherit system specialArgs;
    modules =
      hostModules
      ++ lib.optionals (resolvedHomeModules != [ ]) [
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "bak";
            extraSpecialArgs = specialArgs;
            users.${mainUser}.imports = resolvedHomeModules;
          };
        }
      ];
  };

  pkgs = import nixpkgs {
    inherit system;
    config = nixpkgsConfig;
    overlays = nixpkgsOverlays;
  };
in
assert mylib.assertNonEmptyAttrs hostMyvars "Missing or empty manifest entry ${manifestLabel}";
assert mylib.assertRequiredNonEmptyStrings hostMyvars [
  "system"
  "username"
  "timezone"
  "systemStateVersion"
  "homeStateVersion"
  "diskDevice"
]
  manifestLabel;
assert mylib.assertRequiredPositiveInts hostMyvars [ "swapSizeGb" ] manifestLabel;
assert mylib.assertPathExists hostHardwarePath "Missing ${hostDir}/hardware.nix";
assert mylib.assertPathExists hostHardwareModulesPath "Missing ${hostDir}/hardware-modules.nix";
assert mylib.assertPathExists hostDiskoPath "Missing ${hostDir}/disko.nix";
{
  inherit
    name
    system
    mainUser
    cpuVendor
    specialArgs
    nixpkgsConfig
    nixpkgsOverlays
    nixosSystem
    pkgs
    ;
}
