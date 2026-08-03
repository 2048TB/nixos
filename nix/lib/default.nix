{ lib }:
let
  attrsLib = import ./attrs.nix { inherit lib; };
  hostLib = import ./host.nix { };
  mkNixosHost = import ./mkNixosHost.nix { inherit lib; };
  mkDarwinHost = import ./mkDarwinHost.nix { inherit lib; };
  displayTopologyLib = import ./display-topology.nix { inherit lib; };
  launchersLib = import ./launchers.nix { inherit lib; };
  validationLib = import ./validation.nix { inherit lib attrsLib; };
  defaultHomeStateVersion = "25.11";
  defaultInitrdAvailableKernelModules = [
    "nvme"
    "xhci_pci"
    "ahci"
    "usbhid"
    "usb_storage"
    "sd_mod"
  ];
in
rec {
  # 全仓库唯一主机清单；条目结构见 nix/hosts/default.nix 顶部注释。
  hosts = import ../hosts;

  inherit mkNixosHost mkDarwinHost;
  inherit (hostLib) hostMetaSchema roleFlags deriveHostCapabilities;
  inherit (displayTopologyLib) primaryDisplay mkNiriOutputs mkNoctaliaMonitorWidgets;
  inherit (attrsLib)
    hasNonEmptyString
    hasPositiveInt
    mapNamesToAttrs
    mergeRecursiveAttrsList
    mergeAttrFromList
    mergeAttrFromListWithExtra
    importIfExists
    mkHostDataEntry
    specsToAttrs
    ;
  inherit (launchersLib) mkLogFilteredLauncher;
  inherit (validationLib)
    assertPathExists
    assertNonEmptyAttrs
    assertRequiredNonEmptyStrings
    assertRequiredPositiveInts
    ;
  inherit defaultHomeStateVersion;

  # Linux/Darwin 共享的高频 CLI 包；单一事实源在 package-groups.nix。
  sharedPackageNames = (import ../home/linux/package-groups.nix).shared;

  resolvePackageByName =
    pkgs: name:
    let
      pkgPath = lib.splitString "." name;
      pkg = lib.attrByPath pkgPath null pkgs;
      exists = pkg != null;
      availabilityCheck =
        if exists
        then builtins.tryEval (lib.meta.availableOn pkgs.stdenv.hostPlatform pkg)
        else {
          success = true;
          value = false;
        };
      available = exists && availabilityCheck.success && availabilityCheck.value;
    in
    {
      inherit name pkg available;
    };

  resolvePackagesByName =
    pkgs: names:
    let
      resolved = map (resolvePackageByName pkgs) names;
    in
    {
      packages = map (item: item.pkg) (builtins.filter (item: item.available) resolved);
      skippedNames = map (item: item.name) (builtins.filter (item: !item.available) resolved);
    };

  allowedUnfreePackageNames = [
    "antigravity"
    "cursor"
    "google-chrome"
    "libcusparse_lt"
    "nvidia-settings"
    "nvidia-x11"
    "p7zip"
    "steam"
    "steam-unwrapped"
    "torch"
    "triton"
    "unrar"
    "vscode"
    "wpsoffice"
    "xow_dongle-firmware" # hardware.xone (Xbox One 无线适配器) 需要
  ];

  allowedUnfreeLicenseNames = [
    "CUDA EULA"
    "cuDNN EULA"
  ];

  hasAllowedUnfreeLicense =
    license:
    if builtins.isList license then
      builtins.any hasAllowedUnfreeLicense license
    else if builtins.isAttrs license then
      builtins.elem (license.shortName or "") allowedUnfreeLicenseNames
      || builtins.elem (license.fullName or "") allowedUnfreeLicenseNames
      || builtins.elem (license.spdxId or "") [ "CUDA-EULA" ]
    else
      false;

  allowUnfreePredicate =
    pkg:
    let
      pkgName = lib.getName pkg;
      pkgLicense = pkg.meta.license or null;
    in
    builtins.elem pkgName allowedUnfreePackageNames
    || hasAllowedUnfreeLicense pkgLicense;

  # Use paths relative to the repository root.
  relativeToRoot = lib.path.append ../../.;

  kvmModulesForVendor = vendor:
    if vendor == "amd" then [ "kvm-amd" ]
    else if vendor == "intel" then [ "kvm-intel" ]
    else [ "kvm-amd" "kvm-intel" ];

  cpuVendorFromHardwareModules =
    moduleNames:
    let
      hasAmd = builtins.elem "common-cpu-amd" moduleNames;
      hasIntel = builtins.elem "common-cpu-intel" moduleNames;
    in
    if hasAmd && !hasIntel then "amd"
    else if hasIntel && !hasAmd then "intel"
    else null;

  mkNixosHardwareModule =
    { extraImports ? [ ]
    , availableKernelModules ? defaultInitrdAvailableKernelModules
    ,
    }:
    { config, lib, cpuVendor, ... }:
    {
      imports = extraImports;

      boot = {
        initrd.availableKernelModules = availableKernelModules;
        initrd.kernelModules = [ ];
        extraModulePackages = [ ];
      };

      hardware = {
        enableRedistributableFirmware = lib.mkDefault true;
      }
      // lib.optionalAttrs (cpuVendor == "amd") {
        cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      }
      // lib.optionalAttrs (cpuVendor == "intel") {
        cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
      };
    };

}
