# Per-host NixOS eval checks.
#
# The shared derived values live in ./checks/context.nix; cohesive check
# groups live in ./checks/<group>.nix. This file stays a thin re-export that
# computes the context once and merges every group, preserving the original
# flat attrset of `eval-<host>-*` derivations.
args:
let
  ctx = import ./checks/context.nix args;
  groups = [
    ./checks/host-metadata.nix
    ./checks/boot.nix
    ./checks/kernel.nix
    ./checks/gpu-display.nix
    ./checks/secrets.nix
    ./checks/docker.nix
    ./checks/home-manager.nix
  ];
in
builtins.foldl' (acc: group: acc // (import group ctx)) { } groups
