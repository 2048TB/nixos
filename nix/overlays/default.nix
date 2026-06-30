{ inputs, ... }:
let
  self = rec {
    additions = final: _prev: import ../pkgs final;

    modifications =
      final: prev:
      {
        antigravity =
          if final.stdenv.hostPlatform.system == "x86_64-linux" then
            final.callPackage ../pkgs/antigravity.nix
              {
                vscode-generic = inputs.nixpkgs + "/pkgs/applications/editors/vscode/generic.nix";
              }
          else
            prev.antigravity;

        vscode =
          # 25.11 ships vscode 1.106; pin unstable (1.118+) for current extension/API support.
          if final.stdenv.hostPlatform.system == "x86_64-linux" then
            final.unstable.vscode
          else
            prev.vscode;

        zed-editor =
          # 25.11 ships zed-editor 0.218; pin unstable (1.x) for the post-1.0 release line.
          if final.stdenv.hostPlatform.isLinux then
            final.unstable.zed-editor
          else
            prev.zed-editor;

        zed-editor-fhs =
          # Keep the FHS wrapper aligned with the unstable zed-editor pin above.
          if final.stdenv.hostPlatform.isLinux then
            final.unstable.zed-editor-fhs
          else
            prev.zed-editor-fhs;

        zellij =
          # Pinned to unstable and enforced by the eval-*-zellij-uses-unstable checks.
          if final.stdenv.hostPlatform.isLinux then
            final.unstable.zellij
          else
            prev.zellij;
      };

    unstable-packages =
      final: _prev:
      let
        mylib = import ../lib { inherit (final) lib; };
      in
      {
        unstable = import inputs.nixpkgs-unstable {
          inherit (final.stdenv.hostPlatform) system;
          config.allowUnfreePredicate = mylib.allowUnfreePredicate;
        };
      };

    default =
      final: prev:
      (additions final prev)
      // (modifications final prev)
      // (unstable-packages final prev);
  };
in
self
