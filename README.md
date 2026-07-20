# Dotfiles

Nix-managed personal environment for **macOS** (nix-darwin + Home Manager) and **Linux Mint / work** (Home Manager only).

Shared pieces live in `home.nix` (shell, packages, WezTerm). Mac-only system bits live in `darwin.nix`.

| File | Role |
|------|------|
| `flake.nix` | Entrypoints: `.#mac` (both Macs) and `.#brianallen` (Linux desktop HM) |
| `darwin.nix` | macOS system packages, Homebrew casks (WezTerm), Nix Apps sync |
| `home.nix` | User packages, zsh, WezTerm config; nixpkgs WezTerm on Linux only |
| `wezterm.lua` | Full WezTerm config (theme, keys, wallpapers) |
| `flake.lock` | Pinned nixpkgs / darwin / home-manager |

Username is hard-coded as `brianallen`. Change `home.username` / `home.homeDirectory` in `home.nix` (and the flake attribute / Darwin user) if a machine uses a different login.

---

## What’s managed

- **zsh** — completions, autosuggestions, syntax highlighting, aliases
- **nvm** — loads an existing install (does not install Node itself)
- **Packages** — git, starship (Mac also: git/tmux via nix-darwin; WezTerm via Homebrew cask)
- **tmux** — mouse, indexed windows; epic sessions attached from WezTerm
- **WezTerm** — Catppuccin Macchiato, wallpapers, tmux epic picker; config from this repo
  - **Mac:** signed Homebrew cask (`/Applications/WezTerm.app`) so OS notifications can work
  - **Linux:** nixpkgs package via Home Manager
- **Mac only** — Homebrew PATH on login, Proton Pass SSH (`vssh`), `SSH_AUTH_SOCK`

---

## Prerequisites

### 1. Install Nix (both platforms)

Use the Determinate Systems installer (what this machine used):

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Or the upstream multi-user installer:

```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

Then open a **new** shell and confirm:

```bash
nix --version
```

Flakes should already be enabled with Determinate. If `nix flake` fails, enable them:

```bash
mkdir -p ~/.config/nix
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

### 2. Clone this repo

```bash
git clone <YOUR_REPO_URL> ~/dotfiles
cd ~/dotfiles
```

---

## macOS (Apple Silicon)

### First-time apply

From the repo root:

```bash
sudo darwin-rebuild switch --flake .#mac
```

After that, the zsh alias works from this directory (or with a full path):

```bash
rebuild-env
# same as: sudo darwin-rebuild switch --flake .#mac
```

### What that does

- Builds the nix-darwin system (`darwin.nix`)
- Runs Home Manager for `brianallen` (`home.nix`)
- Ensures Homebrew cask **wezterm** is installed (signed → `/Applications/WezTerm.app`)
- Symlinks WezTerm config + wallpapers into `~/.config/wezterm/`

**Launch the Brew app** (`/Applications/WezTerm.app`), not an old copy under `~/Applications/Nix Apps`.

**Sudo:** `darwin-rebuild` still needs `sudo`. Using Brew for WezTerm does **not** remove that — nix-darwin activates the whole system (and runs `brew bundle` for listed casks) as root. Linux Mint stays `home-manager switch` without sudo.

**Brew cleanup:** we do **not** enable `homebrew.onActivation.cleanup = "uninstall"`, so your other Homebrew packages are left alone.

### Optional Mac extras (not Nix)

- **Homebrew** — PATH is wired in zsh if brew exists
- **nvm** — install yourself; Home Manager only sources it
- **Proton Pass CLI** — used by `vssh` on Darwin only

Restart WezTerm (or open a new window) after rebuilds so config reloads.

---

## Linux Mint / work computer

There is **no** nix-darwin on Linux. Only Home Manager applies `home.nix`.

The flake output assumes:

- login user: `brianallen`
- architecture: `x86_64-linux`

If your work box is ARM or a different username, edit `flake.nix` / `home.nix` first.

### First-time apply

```bash
cd ~/dotfiles
nix run home-manager/master -- switch --flake .#brianallen
```

Later rebuilds (once `home-manager` is on your PATH from the profile):

```bash
home-manager switch --flake .#brianallen
```

Or without relying on PATH:

```bash
nix run home-manager/master -- switch --flake .#brianallen
```

### Notes for Mint / work

- Proton Pass / `vssh` / Homebrew PATH are **skipped** on Linux (`isDarwin` guards).
- WezTerm is installed via `programs.wezterm.enable`.
- Make zsh your login shell if it isn’t already:

  ```bash
  chsh -s "$(which zsh)"
  ```

  After Home Manager runs, zsh may live under `~/.nix-profile/bin/zsh` — use that path with `chsh` if needed.
- The `rebuild-env` alias still points at `darwin-rebuild`; on Linux use `home-manager switch --flake .#brianallen` (or add a Linux-specific alias later).

---

## WezTerm

Config file in the repo: `wezterm.lua`  
Installed path: `~/.config/wezterm/wezterm.lua`

Theme is **Catppuccin Macchiato** (dark only). Default font is WezTerm’s built-in; no Nerd Font required yet.

### Keybindings

| Keys | Action |
|------|--------|
| `Ctrl+a` then `t` | tmux session picker |
| `Cmd+Shift+t` | Same picker |
| `Ctrl+a` then `n` | New tmux session by name |
| `Cmd+p` | Command palette |
| `Cmd+e` | Rename WezTerm tab |
| `Ctrl+Alt+b` / `Ctrl+Alt+n` | Cycle wallpaper / folder |
| `Ctrl+[` `]` `{` `}` / `Ctrl+o` | Opacity / tint / transparency |

**Inside a tmux epic tab** (prefix `Ctrl+b`, then the key):

| Keys | Action |
|------|--------|
| `Ctrl+b` then `c` | New tmux window (story) |
| `Ctrl+b` then `,` | Rename window |
| `Ctrl+b` then `%` / `"` | Split pane left-right / top-bottom |
| `Ctrl+b` then `n` / `p` | Next / previous window |
| `Ctrl+b` then `x` | Close pane |

Do **not** use old WezTerm `Ctrl+a` `\|` / `=` for splits inside an epic — those were WezTerm panes (outside tmux) and are removed so they don’t confuse things.

### Notifications

- Background WezTerm tab gets output → macOS toast + `•` on the tab (allow WezTerm in **System Settings → Notifications** if nothing appears)
- `printf '\a'` still fires a toast (BEL)
- Claude/Pi do **not** auto-notify unless they print BEL or you’re watching another WezTerm tab while they write output

### Persistence

Closing WezTerm drops GUI tabs. **tmux sessions can still be alive** — reopen WezTerm → picker → attach the same name. Pane layouts inside tmux survive that; WezTerm-only splits did not (and shouldn’t be used). Full reboot restore needs tmux-resurrect (not wired yet).

### Wallpapers

Images live in the **repo** under `wallpaper/` and are synced by Home Manager to `~/.config/wezterm/wallpaper`.

```text
wallpaper/                 # commit these
  nature/
    lake.jpg
    forest.png
  abstract/
    grid.webp
```

After `darwin-rebuild` / `home-manager switch`, WezTerm reads them from:

```text
~/.config/wezterm/wallpaper/<folder>/<image>
```

- Put images in **subfolders** (category = folder name).
- `Ctrl+n` cycles folders; `Ctrl+b` cycles images in the current folder.
- Empty dir is fine — solid theme background until you add images.
- Keep files reasonable for GitHub (large binaries = slow clones; Git LFS if needed later).

### Background overlay (the tint on top of images)

In `wezterm.lua`, near the top:

| Knob | Default | What it does |
|------|---------|--------------|
| `THEME.overlay` | `#0f172a` | Color of the tint layer over the wallpaper |
| `DEFAULT_OVERLAY_OPACITY` | `0.95` | How strong that tint is (`0` = invisible, `1` = solid) |
| `DEFAULT_BACKGROUND_OPACITY` | `0.95` | Opacity of the **image** layer (also adjusted live with `Ctrl+[` / `]`) |

`0.95` overlay is very heavy — drop it (e.g. `0.4`–`0.6`) if you want the picture to show through more.

---

## Day-to-day workflow

1. Edit files in `~/dotfiles`
2. Rebuild:
   - **Mac:** `rebuild-env` or `sudo darwin-rebuild switch --flake .#mac`
   - **Linux:** `home-manager switch --flake .#brianallen`
3. Restart WezTerm (or reload config) if you changed `wezterm.lua`

Useful aliases from `home.nix`:

| Alias | Command |
|-------|---------|
| `ll` | `ls -la` |
| `gs` | `git status` |
| `rebuild-env` | Darwin rebuild (Mac only) |

---

## Troubleshooting

**Flakes disabled**

```bash
echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
```

**WezTerm still on old config**

Confirm the symlink:

```bash
ls -l ~/.config/wezterm/wezterm.lua
```

It should point into this repo. Fully quit WezTerm and reopen.

**Wrong architecture on Linux**

In `flake.nix`, change `x86_64-linux` to `aarch64-linux` (or add a second `homeConfigurations` attribute).

**Username mismatch**

Update `home.username`, `home.homeDirectory`, Darwin `users.users.*`, and the flake `home-manager.users.*` / `homeConfigurations` name to match the machine login.
