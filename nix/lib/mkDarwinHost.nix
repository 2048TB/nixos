# 把清单条目（nix/hosts/default.nix）+ 主机目录组装成一个 darwinSystem。
{ lib }:
{ inputs
, mylib
, genSpecialArgs
, system
, name
, hostPath ? null
, hostMyvars ? { }
, extraModules ? [ ]
, homeModules ? [ (mylib.relativeToRoot "nix/home/darwin") ]
, ...
}:
let
  inherit (inputs) nix-darwin nixpkgs-darwin home-manager;

  manifestLabel = "nix/hosts/default.nix[darwin.${name}]";
  hostDir = "nix/hosts/darwin/${name}";
  hostHomePath = mylib.relativeToRoot "${hostDir}/home.nix";
  resolvedHomeModules = homeModules ++ lib.optionals (builtins.pathExists hostHomePath) [ hostHomePath ];

  baseSpecialArgs = genSpecialArgs system;
  resolvedMyvars = hostMyvars // { hostname = name; };
  mainUser = resolvedMyvars.username;
  hasNixHomebrew = builtins.hasAttr "nix-homebrew" inputs;
  nixHomebrewTaps =
    (lib.optionalAttrs (builtins.hasAttr "homebrew-core" inputs) {
      "homebrew/homebrew-core" = inputs."homebrew-core";
    })
    // (lib.optionalAttrs (builtins.hasAttr "homebrew-cask" inputs) {
      "homebrew/homebrew-cask" = inputs."homebrew-cask";
    })
    // (lib.optionalAttrs (builtins.hasAttr "homebrew-bundle" inputs) {
      "homebrew/homebrew-bundle" = inputs."homebrew-bundle";
    });
  darwinBootstrapModules = lib.optionals hasNixHomebrew [
    inputs."nix-homebrew".darwinModules.nix-homebrew
    (
      { config, ... }:
      {
        nix-homebrew = {
          enable = true;
          user = mainUser;
          autoMigrate = true;
          mutableTaps = false;
          taps = nixHomebrewTaps;
        };

        # Keep nix-darwin taps aligned with nix-homebrew when taps are immutable.
        homebrew.taps = builtins.attrNames config.nix-homebrew.taps;
      }
    )
  ];

  specialArgs = baseSpecialArgs // {
    myvars = resolvedMyvars;
    inherit mainUser;
  };

  darwinSystem = nix-darwin.lib.darwinSystem {
    inherit system specialArgs;
    modules =
      darwinBootstrapModules
      ++ [ (mylib.relativeToRoot "nix/modules/darwin") ]
      ++ lib.optionals (hostPath != null) [ hostPath ]
      ++ extraModules
      ++ [
        (
          _:
          {
            nixpkgs.pkgs = import nixpkgs-darwin {
              inherit system;
              config.allowUnfreePredicate = mylib.allowUnfreePredicate;
            };
          }
        )
        {
          # home-manager's nix-darwin bridge resolves home.homeDirectory from
          # users.users.<name>.home; ensure it is defined.
          users.users.${mainUser}.home = lib.mkDefault "/Users/${mainUser}";
        }
      ]
      ++ lib.optionals (resolvedHomeModules != [ ]) [
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "bak";
            extraSpecialArgs = specialArgs;
            users.${mainUser} = {
              imports = resolvedHomeModules;
              # Keep Darwin HM user attrs defined at the assembly layer to avoid
              # null defaults leaking into eval-time checks.
              home = {
                username = lib.mkDefault mainUser;
                homeDirectory = lib.mkDefault "/Users/${mainUser}";
                stateVersion = lib.mkDefault (
                  resolvedMyvars.homeStateVersion or mylib.defaultHomeStateVersion
                );
              };
            };
          };
        }
      ];
  };

  pkgs = import nixpkgs-darwin {
    inherit system;
    config.allowUnfreePredicate = mylib.allowUnfreePredicate;
  };
in
assert mylib.assertNonEmptyAttrs hostMyvars "Missing or empty manifest entry ${manifestLabel}";
assert mylib.assertRequiredNonEmptyStrings hostMyvars [
  "system"
  "username"
  "timezone"
  "homeStateVersion"
]
  manifestLabel;
{
  inherit
    name
    system
    mainUser
    specialArgs
    darwinSystem
    pkgs
    ;
}
