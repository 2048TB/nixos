# GPU video-driver expectations and desktop-session (greetd / Wayland / niri)
# wiring checks. The desktop-session group only applies on hosts with a session.
ctx:
let
  inherit (ctx)
    lib pkgs name cfg expectedHome
    resolvedExpectedVideoDrivers hasDesktopSession
    expectedDisplayManagerSessionNames niriConfigSource
    systemPackageNames codeWrapperSource antigravityWrapperSource;
in
lib.optionalAttrs (resolvedExpectedVideoDrivers != null)
  {
    "eval-${name}-video-drivers" = pkgs.runCommand "eval-${name}-video-drivers" { } ''
      test "${builtins.toJSON cfg.services.xserver.videoDrivers}" = "${builtins.toJSON resolvedExpectedVideoDrivers}"
      touch "$out"
    '';
  }
  // lib.optionalAttrs hasDesktopSession {
  "eval-${name}-greetd-session-command-not-home-bound" = pkgs.runCommand "eval-${name}-greetd-session-command-not-home-bound" { } ''
    if grep -Fq "${expectedHome}/.wayland-session" "${cfg.services.greetd.settings.default_session.command}"; then
      echo "greetd session wrapper still depends on ${expectedHome}/.wayland-session" >&2
      exit 1
    fi
    touch "$out"
  '';

  "eval-${name}-greetd-session-command-imports-gui-vars" = pkgs.runCommand "eval-${name}-greetd-session-command-imports-gui-vars" { } ''
    session_wrapper="$(
      grep -o '/nix/store/[^[:space:]]*-wayland-session' "${cfg.services.greetd.settings.default_session.command}" \
        | head -n1
    )"

    if [ -z "$session_wrapper" ]; then
      echo "failed to locate greetd wayland-session wrapper" >&2
      exit 1
    fi

    for expected_var in \
      NIXOS_OZONE_WL \
      QT_QPA_PLATFORMTHEME \
      NIX_XDG_DESKTOP_PORTAL_DIR \
      XDG_SESSION_TYPE
    do
      if ! grep -Fq "$expected_var" "$session_wrapper"; then
        echo "greetd wayland-session wrapper does not import $expected_var" >&2
        exit 1
      fi
    done

    touch "$out"
  '';

  "eval-${name}-wayland-session-env-sync-autostart" = pkgs.runCommand "eval-${name}-wayland-session-env-sync-autostart" { } ''
    test "${if builtins.elem "wayland-session-env-sync" systemPackageNames then "1" else "0"}" = "1"
    niri_config="${if niriConfigSource == null then "" else niriConfigSource}"
    test -n "$niri_config"
    grep -F 'spawn-at-startup "wayland-session-env-sync"' "$niri_config" >/dev/null
    touch "$out"
  '';

  "eval-${name}-display-manager-session-names" = pkgs.runCommand "eval-${name}-display-manager-session-names" { } ''
    test "${builtins.toJSON cfg.services.displayManager.sessionData.sessionNames}" = "${builtins.toJSON expectedDisplayManagerSessionNames}"
    touch "$out"
  '';

  "eval-${name}-gui-cli-wrappers" = pkgs.runCommand "eval-${name}-gui-cli-wrappers" { } ''
    code_wrapper="${if codeWrapperSource == null then "" else codeWrapperSource}"
    antigravity_wrapper="${if antigravityWrapperSource == null then "" else antigravityWrapperSource}"

    test -n "$code_wrapper"
    test -f "$code_wrapper"
    test -n "$antigravity_wrapper"
    test -f "$antigravity_wrapper"

    grep -F '${lib.getExe pkgs.vscode}' "$code_wrapper" >/dev/null
    for wrapper in "$code_wrapper" "$antigravity_wrapper"; do
      grep -F 'target executable not found or not executable' "$wrapper" >/dev/null
      grep -F 'refusing to execute wrapper recursively' "$wrapper" >/dev/null
      grep -F '${pkgs.coreutils}/bin/readlink' "$wrapper" >/dev/null
      grep -F 'ozone-platform-hint' "$wrapper" >/dev/null
    done

    touch "$out"
  '';
}
