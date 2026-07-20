{ config, pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
in
{
  # Change these values to match your system login name
  home.username = "brianallen";
  home.homeDirectory = if isDarwin then "/Users/brianallen" else "/home/brianallen";
  home.stateVersion = "25.05";

  # User-installed tools (claude, etc.) — not managed by Nix
  home.sessionPath = [ "$HOME/.local/bin" ];

  # Proton Pass SSH agent socket (personal Macs only)
  home.sessionVariables = lib.mkIf isDarwin {
    SSH_AUTH_SOCK = "$HOME/.ssh/proton-pass-agent.sock";
  };

  # Software to install universally across Mac and Linux
  home.packages = with pkgs; [
    git
    starship
  ];

  # tmux: epic sessions live here; WezTerm tabs attach with -A -s <name>
  programs.tmux = {
    enable = true;
    mouse = true;
    baseIndex = 1;
    clock24 = true;
    terminal = "tmux-256color";
    extraConfig = ''
      set -g renumber-windows on
      set -g set-titles on
      set -g set-titles-string '#S · #W'
      set -g history-limit 50000
      # WezTerm already shows the epic name on the tab — hide tmux's bottom bar
      set -g status off
      # Keep default prefix Ctrl+b (WezTerm leader is Ctrl+a — no clash)
      setw -g automatic-rename on
    '';
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -la";
      gs = "git status";
      rebuild-env = "sudo darwin-rebuild switch --flake .#mac";
    };

    # Login shell: Homebrew PATH (Mac only — does nothing on Linux Mint)
    profileExtra = lib.optionalString isDarwin ''
      if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
      elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
      fi
    '';

    # Non-interactive shells (Cursor Agent, etc.) still need node
    envExtra = ''
      if [[ -n "$CURSOR_AGENT" ]] || [[ "$COMPOSER_NO_INTERACTION" == "1" ]] || [[ "$PAGER" == "head -n 10000 | cat" ]]; then
        export NVM_DIR="''${NVM_DIR:-$HOME/.nvm}"
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        nvm use 22 2>/dev/null || nvm use default 2>/dev/null || true
      fi
    '';

    # Interactive shell: load existing nvm install (does NOT reinstall nvm)
    initContent = ''
      export NVM_DIR="$HOME/.nvm"
      if command -v brew >/dev/null 2>&1 && [ -s "$(brew --prefix nvm 2>/dev/null)/nvm.sh" ]; then
        source "$(brew --prefix nvm)/nvm.sh"
      elif [ -s "$NVM_DIR/nvm.sh" ]; then
        source "$NVM_DIR/nvm.sh"
      fi

      autoload -U add-zsh-hook
      load-nvmrc() {
        local nvmrc_path="$(nvm_find_nvmrc)"

        if [ -n "$nvmrc_path" ]; then
          local nvmrc_node_version=$(nvm version "$(cat "''${nvmrc_path}")")

          if [ "$nvmrc_node_version" = "N/A" ]; then
            nvm install
          elif [ "$nvmrc_node_version" != "$(nvm version)" ]; then
            nvm use
          fi
        elif [ -n "$(PWD=$OLDPWD nvm_find_nvmrc)" ] && [ "$(nvm version)" != "$(nvm version default)" ]; then
          nvm use default
        fi
      }
      add-zsh-hook chpwd load-nvmrc
      load-nvmrc
    '' + lib.optionalString isDarwin ''
      vssh() {
        echo "🔐 Initializing Proton Pass SSH Agent in background..."
        pass-cli ssh-agent start >/dev/null 2>&1 &

        sleep 0.5

        echo "🔑 Loading keys from vault..."
        if ! pass-cli ssh-agent load; then
          echo "⚠️  Load failed. Attempting to log in..."
          pass-cli login

          echo "🔑 Retrying key load..."
          pass-cli ssh-agent load
        fi

        ssh "$@"

        echo "🔒 Stopping Proton Pass SSH Agent..."
        pass-cli ssh-agent stop >/dev/null 2>&1
      }
    '';
  };

  # WezTerm config (both platforms). Package install differs:
  #   Mac  → Homebrew cask (signed app) via darwin.nix
  #   Linux → nixpkgs via programs.wezterm
  # Out-of-store symlink so editing wezterm.lua applies without a rebuild.
  programs.wezterm.enable = !isDarwin;
  xdg.configFile."wezterm/wezterm.lua".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/dotfiles/wezterm.lua";
  xdg.configFile."wezterm/wallpaper".source = ./wallpaper;
}
