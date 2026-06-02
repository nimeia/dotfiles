#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"

link_item() {
    local rel="$1"
    local src="$repo_dir/home/$rel"
    local dst="$HOME/$rel"

    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
        printf 'skip missing source: %s\n' "$src" >&2
        return
    fi

    mkdir -p -- "$(dirname -- "$dst")"

    if [ -L "$dst" ] && [ "$(readlink -- "$dst")" = "$src" ]; then
        return
    fi

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mkdir -p -- "$backup_dir/$(dirname -- "$rel")"
        mv -- "$dst" "$backup_dir/$rel"
    fi

    ln -s -- "$src" "$dst"
}

install_user() {
    local item

    for item in \
        .bashrc \
        .zshrc \
        .gitconfig \
        .config/doom \
        .config/environment.d \
        .config/fcitx5 \
        .config/fuzzel \
        .config/ghostty \
        .config/mako \
        .config/mimeapps.list \
        .config/niri \
        .config/nvim \
        .config/waybar \
        .config/wlogout \
        .local/share/applications/google-chrome.desktop \
        .local/share/wallpapers/niri-overview.png; do
        link_item "$item"
    done

    install_tmux
    install_doom
    install_python_tool_shims

    for item in "$repo_dir"/home/.local/bin/*; do
        [ -e "$item" ] || continue
        link_item ".local/bin/$(basename -- "$item")"
        chmod +x -- "$HOME/.local/bin/$(basename -- "$item")"
    done
}

install_tmux() {
    local target="$HOME/.local/share/oh-my-tmux"
    local conf_dir="$HOME/.config/tmux"
    local conf="$conf_dir/tmux.conf"
    local upstream="$target/.tmux.conf"

    if [ -d "$target/.git" ]; then
        git -C "$target" pull --ff-only
    elif [ -e "$target" ]; then
        printf 'skip Oh my tmux clone; %s exists and is not a git checkout\n' "$target" >&2
    else
        git clone --single-branch https://github.com/gpakosz/.tmux.git "$target"
    fi

    mkdir -p -- "$conf_dir"
    if [ ! -f "$upstream" ]; then
        printf 'skip tmux upstream link; %s not found\n' "$upstream" >&2
        link_item ".config/tmux/tmux.conf.local"
        return
    fi

    if { [ -e "$conf" ] || [ -L "$conf" ]; } && [ "$(readlink -- "$conf" 2>/dev/null || true)" != "$upstream" ]; then
        mkdir -p -- "$backup_dir/.config/tmux"
        mv -- "$conf" "$backup_dir/.config/tmux/tmux.conf"
    fi
    ln -sfn -- "$upstream" "$conf"

    link_item ".config/tmux/tmux.conf.local"
}

install_doom() {
    local target="$HOME/.config/emacs"

    if [ -d "$target/.git" ]; then
        git -C "$target" pull --ff-only
    elif [ -e "$target" ]; then
        printf 'skip Doom clone; %s exists and is not a git checkout\n' "$target" >&2
    else
        git clone --depth 1 https://github.com/doomemacs/doomemacs "$target"
    fi

    mkdir -p -- "$HOME/.local/bin"
    if [ -x "$target/bin/doom" ]; then
        ln -sfn -- "$target/bin/doom" "$HOME/.local/bin/doom"
    fi
}

install_doom_profile() {
    install_user
    run_doom_install
}

run_doom_install() {
    if [ ! -x "$HOME/.config/emacs/bin/doom" ]; then
        printf 'Doom executable not found; check ~/.config/emacs.\n' >&2
        exit 1
    fi

    "$HOME/.config/emacs/bin/doom" install -!
    "$HOME/.config/emacs/bin/doom" env
}

install_npm_globals() {
    if [ ! -x "$(command -v npm 2>/dev/null || true)" ]; then
        printf 'skip npm globals; npm is not installed\n' >&2
        return
    fi

    mkdir -p -- "$HOME/.local"
    xargs -r -a <(grep -vE '^\s*(#|$)' "$repo_dir/packages/npm-global.txt") \
        npm install -g --prefix "$HOME/.local"
}

install_rust_analyzer() {
    local arch
    local tmp
    arch="$(uname -m)"

    if [ "$arch" != "x86_64" ]; then
        printf 'skip rust-analyzer auto-install; unsupported arch: %s\n' "$arch" >&2
        return
    fi

    mkdir -p -- "$HOME/.local/bin"
    tmp="$(mktemp)"
    curl -L --fail --output "$tmp" \
        https://github.com/rust-lang/rust-analyzer/releases/latest/download/rust-analyzer-x86_64-unknown-linux-gnu.gz
    gzip -dc "$tmp" >"$HOME/.local/bin/rust-analyzer"
    chmod +x -- "$HOME/.local/bin/rust-analyzer"
    rm -f -- "$tmp"
}

install_python_tool_shims() {
    mkdir -p -- "$HOME/.local/bin"

    if command -v pyflakes3 >/dev/null 2>&1; then
        ln -sfn -- "$(command -v pyflakes3)" "$HOME/.local/bin/pyflakes"
    fi
    if command -v nosetests3 >/dev/null 2>&1; then
        ln -sfn -- "$(command -v nosetests3)" "$HOME/.local/bin/nosetests"
    fi
}

install_packages() {
    sudo apt update
    sudo xargs -r -a <(grep -vE '^\s*(#|$)' "$repo_dir/packages/apt.txt") apt install -y
    install_npm_globals
    install_rust_analyzer
    install_python_tool_shims
}

install_system() {
    sudo install -D -m 0644 "$repo_dir/system/etc/greetd/config.toml" /etc/greetd/config.toml
    sudo install -D -m 0644 "$repo_dir/system/usr/share/wayland-sessions/niri.desktop" /usr/share/wayland-sessions/niri.desktop
    sudo install -D -m 0755 "$repo_dir/system/usr/local/bin/niri-session" /usr/local/bin/niri-session
}

install_external() {
    "$repo_dir/scripts/install-external.sh"
}

case "${1:-}" in
    --packages)
        install_packages
        ;;
    --external)
        install_external
        ;;
    --niri-source)
        shift
        "$repo_dir/scripts/install-niri-source.sh" "$@"
        exit 0
        ;;
    --system)
        install_user
        install_system
        ;;
    --doom)
        install_doom_profile
        ;;
    --all)
        install_packages
        install_user
        install_system
        run_doom_install
        ;;
    *)
        install_user
        ;;
esac

if [ -d "$backup_dir" ]; then
    printf 'Existing files were backed up to %s\n' "$backup_dir"
fi
printf 'Dotfiles install complete.\n'
