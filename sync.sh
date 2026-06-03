#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

copy_dir() {
    local rel="$1"
    local src="$HOME/$rel"
    local dst="$repo_dir/home/$rel"
    local resolved_src
    local resolved_dst

    shift
    [ -d "$src" ] || [ -L "$src" ] || return 0
    resolved_src="$(readlink -f -- "$src" 2>/dev/null || true)"
    resolved_dst="$(readlink -m -- "$dst" 2>/dev/null || printf '%s' "$dst")"
    if [ -n "$resolved_src" ] && [ "$resolved_src" = "$resolved_dst" ]; then
        return 0
    fi

    mkdir -p -- "$repo_dir/home/$(dirname -- "$rel")"
    rsync -a --delete "$@" "$src/" "$dst/"
}

copy_file() {
    local rel="$1"
    local src="$HOME/$rel"
    local dst="$repo_dir/home/$rel"
    local resolved_src
    local resolved_dst

    resolved_src="$(readlink -f -- "$src" 2>/dev/null || true)"
    resolved_dst="$(readlink -m -- "$dst" 2>/dev/null || printf '%s' "$dst")"
    if [ -n "$resolved_src" ] && [ "$resolved_src" = "$resolved_dst" ]; then
        return 0
    fi

    install -D -m 0644 "$src" "$dst"
}

copy_file_if_exists() {
    local rel="$1"
    [ -f "$HOME/$rel" ] || [ -L "$HOME/$rel" ] || return 0
    copy_file "$rel"
}

copy_local_bin_if_exists() {
    local name="$1"
    local src="$HOME/.local/bin/$name"
    local dst="$repo_dir/home/.local/bin/$name"
    local resolved_src
    local resolved_dst

    [ -f "$src" ] || [ -L "$src" ] || return 0
    resolved_src="$(readlink -f -- "$src" 2>/dev/null || true)"
    resolved_dst="$(readlink -m -- "$dst" 2>/dev/null || printf '%s' "$dst")"
    if [ -n "$resolved_src" ] && [ "$resolved_src" = "$resolved_dst" ]; then
        return 0
    fi

    install -D -m 0755 "$src" "$dst"
}

copy_bashrc() {
    local src="$HOME/.bashrc"
    local dst="$repo_dir/home/.bashrc"
    local resolved_src
    local resolved_dst
    local tmp

    resolved_src="$(readlink -f -- "$src" 2>/dev/null || true)"
    resolved_dst="$(readlink -m -- "$dst" 2>/dev/null || printf '%s' "$dst")"
    if [ -n "$resolved_src" ] && [ "$resolved_src" = "$resolved_dst" ]; then
        return 0
    fi

    if [ ! -f "$src" ]; then
        install -D -m 0644 /dev/null "$dst"
        return 0
    fi

    tmp="$(mktemp)"
    sed '/^export HTTP_PROXY=/d;/^export HTTPS_PROXY=/d;/^export ALL_PROXY=/d;/^export http_proxy=/d;/^export https_proxy=/d;/^export all_proxy=/d' \
        "$src" >"$tmp"
    install -D -m 0644 "$tmp" "$dst"
    rm -f -- "$tmp"
}

copy_dir .config/niri --exclude '*.backup-*'
copy_dir .config/waybar --exclude '*.backup-*' --exclude 'config.jsonc' --exclude 'scripts/playerctl-status-new'
copy_dir .config/swaylock --exclude '*.backup-*'
copy_dir .config/fcitx5 --exclude '*.backup-*' --exclude 'conf/cached_layouts' --exclude 'conf/chttrans.conf'
copy_dir .config/doom --exclude '.local/' --exclude '*.elc'
copy_dir .config/fuzzel --exclude '*.backup-*'
copy_dir .config/wlogout --exclude '*.backup-*'
copy_dir .config/environment.d
copy_dir .config/ghostty
copy_dir .config/mako
copy_dir .config/nvim --exclude '.git/'
copy_file_if_exists .config/mimeapps.list
copy_file_if_exists .config/starship.toml

if [ -f "$HOME/.config/tmux/tmux.conf.local" ]; then
    install -D -m 0644 "$HOME/.config/tmux/tmux.conf.local" "$repo_dir/home/.config/tmux/tmux.conf.local"
fi

copy_file_if_exists .local/share/applications/google-chrome.desktop

copy_file_if_exists .zshrc
copy_file_if_exists .gitconfig

copy_bashrc

mkdir -p -- "$repo_dir/home/.local/bin"
copy_local_bin_if_exists ghostty
copy_local_bin_if_exists niri-layout
copy_local_bin_if_exists niri-quit
copy_local_bin_if_exists niri-fullscreen
copy_local_bin_if_exists niri-overview-wallpaper
copy_local_bin_if_exists niri-settings-menu
copy_local_bin_if_exists niri-shortcuts-grid
copy_local_bin_if_exists screen-brightness
copy_local_bin_if_exists wallpaper-random
copy_local_bin_if_exists window-opacity
for item in "$repo_dir"/home/.local/bin/*; do
    [ -f "$item" ] || continue
    chmod +x "$item"
done

for wallpaper in default.png niri-overview.png; do
    copy_file_if_exists ".local/share/wallpapers/$wallpaper"
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
