# Manual or External Installs

These items are part of the current setup but are not restored by `apt.txt`.

- Run `./install.sh --external` to install the external items that can be automated: Google Chrome, Yazi, swww, Ghostty from apt when available, `libnotify-bin`, and `orca`.
- `niri`: currently installed at `/usr/local/bin/niri`; run `./install.sh --niri-source` to build and install it from source. You can pass `--ref <tag-or-commit>` after the command, for example `./install.sh --niri-source --ref v26.04`. Add `--with-gnome-portal` if you need screencasting and accept the larger GNOME portal dependency set. After that, run `./install.sh --system` to reapply the tracked greetd/niri-session templates.
- `Google Chrome`: `./install.sh --external` installs the official package from `https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb`; it installs `google-chrome-stable` and configures the Google Chrome apt source at `/etc/apt/sources.list.d/google-chrome.sources`. The tracked `~/.local/share/applications/google-chrome.desktop` adds Wayland and input-method flags for niri.
- `Oh my tmux`: `install.sh` clones `https://github.com/gpakosz/.tmux` into `~/.local/share/oh-my-tmux` and links `~/.config/tmux/tmux.conf` to it.
- `Doom Emacs`: this repo tracks `~/.config/doom`, not the upstream framework. `install.sh` clones `https://github.com/doomemacs/doomemacs` into `~/.config/emacs`; run `./install.sh --doom` after `./install.sh --packages`.
- `rust-analyzer`: `install.sh --packages` downloads the official x86_64 Linux binary into `~/.local/bin`.
- `ghostty`: this repo tracks the wrapper at `~/.local/bin/ghostty`, but not the bundled Ghostty files under `~/.local/ghostty`. The wrapper falls back to `/usr/bin/ghostty`, and `./install.sh --external` installs the apt package when it is available.
- `swww` and `swww-daemon`: used by `wallpaper-random`; `./install.sh --external` installs them with `cargo install swww` and links them into `~/.local/bin`.
- Nerd Font archive installed under `~/.local/share/fonts/JetBrainsMonoNerd` is not tracked because system JetBrains Mono and Noto fonts are available through apt.
- Large downloaded app bundles such as Zed, Codex, and local devtools are intentionally not tracked. Yazi is restored by `./install.sh --external` from the latest GitHub release.
