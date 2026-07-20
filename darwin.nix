{ pkgs, config, ... }:

{
  nix.enable = false;

  # CLI tools still from Nix. WezTerm GUI comes from Homebrew (signed → Mac notifications).
  environment.systemPackages = with pkgs; [
    git
    tmux
  ];

  # Declarative Homebrew (Brew itself must already be installed — you have it).
  # Only lists what nix-darwin should ensure; does NOT uninstall your other Brew packages
  # unless you set homebrew.onActivation.cleanup = "uninstall" (we don't).
  homebrew = {
    enable = true;
    casks = [
      "wezterm"
    ];
  };

  users.users.brianallen = {
    name = "brianallen";
    home = "/Users/brianallen";
  };

  # Required by nix-darwin when using homebrew.* (activation runs as root)
  system.primaryUser = "brianallen";

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 4;

  # Sync Nix .app bundles to ~/Applications/Nix Apps (WezTerm no longer among them)
  system.activationScripts.applications.text = ''
    echo "Setting up /Users/brianallen/Applications/Nix Apps..." >&2
    srcDir="${config.system.build.applications}/Applications/"
    targetDir="/Users/brianallen/Applications/Nix Apps"
    mkdir -p "$targetDir"
    ${pkgs.rsync}/bin/rsync --archive --checksum --chmod=-w --copy-unsafe-links --delete "$srcDir" "$targetDir"
  '';
}
