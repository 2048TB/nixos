{
  # Linux/Darwin 共享的高频 CLI 包，统一来源以减少平台漂移。
  shared = [
    "git"
    "gh"
    "mise"
    "tmux"
    "television"
    "zellij"
    "yazi"
    "bat"
    "fd"
    "eza"
    "ripgrep"
    "jq"
    "wget"
    "just"
  ];

  cli = [
    "bubblewrap"
    "ripgrep-all"
    "procs"
    "yq"
    "check-jsonschema"
    "tealdeer"
    "sshpass"
    "pciutils"
    "brightnessctl"
    "xdg-user-dirs"
  ];

  dev = [
    "gnumake"
    "cmake"
    "ninja"
    "pkg-config"
    "openssl"
    "autoconf"
    "gettext"
    "libtool"
    "automake"
    "ccache"
    "meson"
    "delta"
    "tokei"
    "nix-output-monitor"
    "nix-tree"
    "nix-melt"
    "cachix"
    "nil"
    "nixpkgs-fmt"
    "statix"
    "deadnix"
    "nix-index"
    "shellcheck"
    "git-lfs"
  ];

  desktop = [
    "google-chrome"
    "vscode"
    "zed-editor-fhs"
    "remmina"
    "nomacs"
    "nautilus"
    "file-roller"
    "ghostty"
    "foot"
    "papirus-icon-theme"
    "wl-clipboard"
    "cliphist"
    "satty"
    "wl-screenrec"
    "gnome-text-editor"
    "fuzzel"
    "gnome-calculator"
    "qt6Packages.qt6ct"
    "app2unit"
    "polkit_gnome"
    "networkmanagerapplet"
  ];

  media = [
    "pavucontrol"
    "pulsemixer"
    "imv"
    "vulkan-tools"
    "mesa-demos"
  ];

  archive = [
    "p7zip-rar"
    "unar"
    "zip"
    "unzip"
  ];
}
