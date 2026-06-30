{ lib, mylib }:
rec {
  # Assemble the per-host data map and the merged config views shared by every
  # platform builder. configAttrName is "nixosConfigurations" or
  # "darwinConfigurations"; the result exposes both the raw data (for later
  # mergeAttrFromListWithExtra calls) and the resolved config/user/host views.
  collectHostData =
    { hostNames
    , mkHostData
    , configAttrName
    }:
    let
      data = mylib.mapNamesToAttrs hostNames mkHostData;
      dataWithoutPaths = builtins.attrValues data;
      configurations = mylib.mergeAttrFromList configAttrName dataWithoutPaths;
      mainUsers = mylib.mergeAttrFromList "mainUsers" dataWithoutPaths;
      resolvedHostNames = builtins.attrNames configurations;
    in
    {
      inherit data dataWithoutPaths configurations mainUsers resolvedHostNames;
    };

  mkRegistryState =
    { kind
    , hostsRoot
    , requiredFiles
    , system
    }:
    let
      discoveredHostNames = mylib.discoverHostNamesBy hostsRoot requiredFiles;
      hostNames = mylib.registryHostNamesByKind kind;
      missingInRegistry =
        builtins.filter (name: !(builtins.elem name hostNames)) discoveredHostNames;
      missingOnDisk =
        builtins.filter (name: !(builtins.elem name discoveredHostNames)) hostNames;
      wrongSystemHosts =
        builtins.filter
          (name: ((mylib.hostRegistryEntry kind name).system or "") != system)
          hostNames;
      hostNamePattern = "^[A-Za-z0-9][A-Za-z0-9_-]*$";
      invalidHostNames = mylib.namesNotMatching hostNamePattern hostNames;
    in
    {
      inherit
        discoveredHostNames
        hostNames
        missingInRegistry
        missingOnDisk
        wrongSystemHosts
        hostNamePattern
        invalidHostNames
        ;
    };

  assertRegistryState =
    { state
    , registryKey
    , kindDisplay
    , hostsPath
    , system
    }:
    lib.assertMsg
      (state.invalidHostNames == [ ])
      "Invalid ${kindDisplay} host names under ${hostsPath}: ${lib.concatStringsSep ", " state.invalidHostNames}. Allowed pattern: ${state.hostNamePattern}"
    && lib.assertMsg
      (state.missingInRegistry == [ ])
      "Host directories exist but are not registered in nix/hosts/registry/systems.toml[${registryKey}]: ${lib.concatStringsSep ", " state.missingInRegistry}"
    && lib.assertMsg
      (state.missingOnDisk == [ ])
      "Hosts are registered in nix/hosts/registry/systems.toml[${registryKey}] but required files are missing: ${lib.concatStringsSep ", " state.missingOnDisk}"
    && lib.assertMsg
      (state.wrongSystemHosts == [ ])
      "Hosts registered under ${registryKey} with mismatched system (${system} expected): ${lib.concatStringsSep ", " state.wrongSystemHosts}"
    && lib.assertMsg (state.hostNames != [ ]) "No hosts found under ${hostsPath}";

  mkEvalCheck =
    pkgs:
    { name, ok, message }:
    pkgs.runCommand name { } ''
      if [ "${if ok then "1" else "0"}" != "1" ]; then
        echo "${message}" >&2
        exit 1
      fi
      touch "$out"
    '';

  mapHostValuesByPath =
    path: configurations:
    lib.mapAttrs (_: cfg: lib.attrByPath path null cfg) configurations;

  mapHomeDirectories =
    { configurations
    , mainUsers
    }:
    lib.mapAttrs
      (
        hostName:
        cfg:
        let
          users = cfg.config.home-manager.users or { };
          user = mainUsers.${hostName} or "";
        in
        assert lib.assertMsg (user != "") "No main user recorded for host ${hostName}"
          && lib.assertMsg
          (builtins.hasAttr user users)
          "Home Manager user '${user}' not found for host ${hostName}";
        users.${user}.home.homeDirectory
      )
      configurations;

  mkHomeConfigurations =
    { configurations
    , mainUsers
    , system
    }:
    let
      resolvedHostNames = builtins.attrNames configurations;
    in
    builtins.listToAttrs (
      map
        (
          hostName:
          let
            user = mainUsers.${hostName} or "";
            hmUsers = configurations.${hostName}.config.home-manager.users or { };
          in
          assert lib.assertMsg (user != "")
            "No main user recorded for host ${hostName} (${system})";
          assert lib.assertMsg (builtins.hasAttr user hmUsers)
            "Home Manager user '${user}' not found for host ${hostName} (${system})";
          let
            hmConfig = hmUsers.${user};
          in
          {
            name = "${user}@${hostName}";
            value = {
              config = hmConfig;
              inherit (hmConfig.home) activationPackage;
            };
          }
        )
        resolvedHostNames
    );

  mkExpectedAttrSet =
    hostNames: value:
    builtins.listToAttrs (
      map
        (name: {
          inherit name;
          inherit value;
        })
        hostNames
    );

  mkExpectedHostNames =
    hostNames:
    builtins.listToAttrs (
      map
        (name: {
          inherit name;
          value = name;
        })
        hostNames
    );

  mkExpectedHomeDirectories =
    homeRoot: mainUsers:
    builtins.mapAttrs (_host: user: "${homeRoot}/${user}") mainUsers;

  mkStandardEvalTests =
    { configurations
    , mainUsers
    , hostNames
    , system
    , homeRoot
    , extraTests ? { }
    }:
    {
      hostname =
        mapHostValuesByPath [ "config" "networking" "hostName" ] configurations
        == mkExpectedHostNames hostNames;
      home =
        mapHomeDirectories
          {
            inherit configurations mainUsers;
          }
        == mkExpectedHomeDirectories homeRoot mainUsers;
      platform =
        mapHostValuesByPath [ "pkgs" "stdenv" "hostPlatform" "system" ] configurations
        == mkExpectedAttrSet hostNames system;
    }
    // extraTests;

  mkEvalCheckSpecs =
    prefix: evalTests:
    map
      (name: {
        name = "evaltest-${prefix}${name}";
        ok = evalTests.${name};
        message = "${prefix}${name} eval test failed";
      })
      (builtins.attrNames evalTests);

}
