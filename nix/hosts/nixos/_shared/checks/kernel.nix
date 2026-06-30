# Kernel-level checks: KVM modules and nix-ld library hygiene.
ctx:
let
  inherit (ctx) lib pkgs name cfg resolvedExpectedKvmModules actualKvmModules;
in
{
  "eval-${name}-nix-ld-libraries-not-hardcoded-store-paths" = pkgs.runCommand "eval-${name}-nix-ld-libraries-not-hardcoded-store-paths" { } ''
    if [ "${if cfg.programs.nix-ld.enable or false then "1" else "0"}" = "1" ]; then
      test "${if (builtins.length cfg.programs.nix-ld.libraries) > 0 then "1" else "0"}" = "1"
      test "${if builtins.all lib.isDerivation cfg.programs.nix-ld.libraries then "1" else "0"}" = "1"
      # 负向匹配：禁止字面量 string/path 混入 libraries（例如硬编码 /nix/store/...）。
      test "${if builtins.any builtins.isString cfg.programs.nix-ld.libraries then "1" else "0"}" = "0"
      test "${if builtins.any builtins.isPath cfg.programs.nix-ld.libraries then "1" else "0"}" = "0"
    fi
    touch "$out"
  '';
}
  // lib.optionalAttrs (resolvedExpectedKvmModules != null) {
  "eval-${name}-kvm-modules" = pkgs.runCommand "eval-${name}-kvm-modules" { } ''
    test "${builtins.toJSON actualKvmModules}" = "${builtins.toJSON resolvedExpectedKvmModules}"
    touch "$out"
  '';
}
