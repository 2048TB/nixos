# Docker mode and rootless-linger gating.
ctx:
let
  inherit (ctx) pkgs name hasExpectedDockerMode hasExpectedRootlessDockerLinger;
in
{
  "eval-${name}-docker-mode" = pkgs.runCommand "eval-${name}-docker-mode" { } ''
    test "${if hasExpectedDockerMode then "1" else "0"}" = "1"
    touch "$out"
  '';
  "eval-${name}-rootless-docker-linger" = pkgs.runCommand "eval-${name}-rootless-docker-linger" { } ''
    test "${if hasExpectedRootlessDockerLinger then "1" else "0"}" = "1"
    touch "$out"
  '';
}
