#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

copy_dir() {
    local rel="$1"
    shift
    mkdir -p -- "$repo_dir/home/$(dirname -- "$rel")"
    rsync -a --delete "$@" "$HOME/$rel/" "$repo_dir/home/$rel/"
}

copy_file() {
    local rel="$1"
    install -D -m 0644 "$HOME/$rel" "$repo_dir/home/$rel"
}

copy_file_if_exists() {
    local rel="$1"
    [ -f "$HOME/$rel" ] || return 0
    copy_file "$rel"
}

copy_local_bin_if_exists() {
    local name="$1"
    [ -f "$HOME/.local/bin/$name" ] || return 0
    install -D -m 0755 "$HOME/.local/bin/$name" "$repo_dir/home/.local/bin/$name"
}

copy_dir .config/niri --exclude '*.backup-*'
copy_dir .config/waybar --exclude '*.backup-*' --exclude 'config.jsonc' --exclude 'scripts/playerctl-status-new'
copy_dir .config/fcitx5 --exclude '*.backup-*' --exclude 'conf/cached_layouts' --exclude 'conf/chttrans.conf'
copy_dir .config/doom --exclude '.local/' --exclude '*.elc'
copy_dir .config/fuzzel --exclude '*.backup-*'
copy_dir .config/wlogout --exclude '*.backup-*'
copy_dir .config/environment.d
copy_dir .config/ghostty
copy_dir .config/mako
copy_dir .config/nvim --exclude '.git/'
copy_file_if_exists .config/mimeapps.list

if [ -f "$HOME/.config/tmux/tmux.conf.local" ]; then
    install -D -m 0644 "$HOME/.config/tmux/tmux.conf.local" "$repo_dir/home/.config/tmux/tmux.conf.local"
fi

if [ -f "$HOME/.local/share/applications/google-chrome.desktop" ]; then
    install -D -m 0644 "$HOME/.local/share/applications/google-chrome.desktop" \
        "$repo_dir/home/.local/share/applications/google-chrome.desktop"
fi

copy_file_if_exists .zshrc
copy_file_if_exists .gitconfig

install -D -m 0644 /dev/null "$repo_dir/home/.bashrc"
if [ -f "$HOME/.bashrc" ]; then
    sed '/^export HTTP_PROXY=/d;/^export HTTPS_PROXY=/d;/^export ALL_PROXY=/d;/^export http_proxy=/d;/^export https_proxy=/d;/^export all_proxy=/d' \
        "$HOME/.bashrc" >"$repo_dir/home/.bashrc"
fi

mkdir -p -- "$repo_dir/home/.local/bin"
copy_local_bin_if_exists ghostty
copy_local_bin_if_exists niri-quit
copy_local_bin_if_exists niri-overview-wallpaper
copy_local_bin_if_exists niri-settings-menu
copy_local_bin_if_exists niri-shortcuts-grid
copy_local_bin_if_exists wallpaper-random
for item in "$repo_dir"/home/.local/bin/*; do
    [ -e "$item" ] || continue
    chmod +x "$item"
done

for wallpaper in default.png niri-overview.png; do
    if [ -f "$HOME/.local/share/wallpapers/$wallpaper" ]; then
        install -D -m 0644 "$HOME/.local/share/wallpapers/$wallpaper" \
            "$repo_dir/home/.local/share/wallpapers/$wallpaper"
    fi
done

if [ -r /etc/greetd/config.toml ]; then
    install -D -m 0644 /etc/greetd/config.toml "$repo_dir/system/etc/greetd/config.toml"
fi
if [ -r /usr/share/wayland-sessions/niri.desktop ]; then
    install -D -m 0644 /usr/share/wayland-sessions/niri.desktop "$repo_dir/system/usr/share/wayland-sessions/niri.desktop"
fi
if [ -r /usr/local/bin/niri-session ]; then
    install -D -m 0755 /usr/local/bin/niri-session "$repo_dir/system/usr/local/bin/niri-session"
fi

printf 'Dotfiles synced from current machine.\n'
