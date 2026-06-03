# Manual or External Installs

These items are part of the current setup but are not restored by `apt.txt`.

- Run `./install.sh --external` to install the external items that can be automated: Google Chrome, Yazi, swww, the Catppuccin wallpaper collection, Ghostty from apt when available, `libnotify-bin`, and `orca`.
- `wallpapers`: `./install.sh --wallpapers` shallow-clones `https://github.com/zhichaoh/catppuccin-wallpapers.git` into `~/Pictures/Wallpapers/catppuccin-wallpapers`. Override with `WALLPAPER_REPO_URL`, `WALLPAPER_REPO_DIR`, or `WALLPAPER_SPARSE_PATHS` if needed.
- `niri`: currently installed at `/usr/local/bin/niri`; run `./install.sh --niri-source` to build and install it from source. You can pass `--ref <tag-or-commit>` after the command, for example `./install.sh --niri-source --ref v26.04`. After that, run `./install.sh --system` to reapply the tracked greetd/niri-session templates.
- `xwayland-satellite`: run `./install.sh --xwayland-satellite` to build and install it from the latest upstream release. `./install.sh --packages` also runs this automatically so niri can launch X11 applications such as Warp Terminal.
- `Google Chrome`: `./install.sh --external` installs the official package from `https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb`; it installs `google-chrome-stable` and configures the Google Chrome apt source at `/etc/apt/sources.list.d/google-chrome.sources`. The tracked `~/.local/share/applications/google-chrome.desktop` adds Wayland and input-method flags for niri.
- `Oh my tmux`: `install.sh` clones `https://github.com/gpakosz/.tmux` into `~/.local/share/oh-my-tmux` and links `~/.config/tmux/tmux.conf` to it.
- `Doom Emacs`: this repo tracks `~/.config/doom`, not the upstream framework. `install.sh` clones `https://github.com/doomemacs/doomemacs` into `~/.config/emacs`; run `./install.sh --doom` after `./install.sh --packages`.
- `rust-analyzer`: `install.sh --packages` downloads the official x86_64 Linux binary into `~/.local/bin`.
- `ghostty`: this repo tracks the Ghostty config and uses the apt package when available. `./install.sh --external` installs `ghostty` from apt if the distribution provides it.
- `swww` and `swww-daemon`: used by `wallpaper-random`; `./install.sh --external` installs both packages from `https://github.com/LGFae/swww.git` at `${SWWW_REF:-v0.11.2}` and links them into `~/.local/bin`.
- Nerd Font archive installed under `~/.local/share/fonts/JetBrainsMonoNerd` is not tracked because system JetBrains Mono and Noto fonts are available through apt.
- Large downloaded app bundles such as Zed, Codex, and local devtools are intentionally not tracked. Yazi is restored by `./install.sh --external` from the latest GitHub release.
