# Repo-wide lint checks (pre-commit + format-sanity), extracted from
# x86_64-linux/default.nix. `preCommitCheck` is exported so the default
# devShell can reuse its hooks/packages without rebuilding the spec.
{ inputs, system, pkgs, mylib }:
let
  preCommitCheck = inputs.pre-commit-hooks.lib.${system}.run {
    src = mylib.relativeToRoot ".";
    hooks = {
      nixpkgs-fmt.enable = true;
      statix.enable = true;
      deadnix.enable = true;
    };
  };
  formatSanityCheck = pkgs.runCommand "format-sanity"
    {
      nativeBuildInputs = [
        pkgs.just
        pkgs.ripgrep
        (pkgs.python3.withPackages (ps: [ ps.pyyaml ]))
      ];
    } ''
    cp -R ${mylib.relativeToRoot "."} repo
    bash repo/nix/scripts/admin/check-format-sanity.sh --repo "$PWD/repo"
    touch "$out"
  '';
in
{
  inherit preCommitCheck;
  checks = {
    pre-commit-check = preCommitCheck;
    format-sanity = formatSanityCheck;
  };
}
