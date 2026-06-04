#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
export PATH="$HOME/.local/bin:$PATH"

# shellcheck source=scripts/lib/apt.sh
. "$repo_dir/scripts/lib/apt.sh"

usage() {
    cat <<'EOF'
Usage: ./install.sh [--packages|--external|--wallpapers|--nvim|--xwayland-satellite|--niri-source|--system|--doom|--all]

With no arguments, installs user dotfile symlinks and local helper scripts.

Options:
  --packages     Install apt packages, npm globals, rust-analyzer, and shims.
  --external     Install external tools: Chrome, Yazi, swww, fonts, wallpapers.
  --wallpapers   Install or update the Catppuccin wallpaper collection only.
  --nvim         Install Neovim config and lazy.nvim bootstrap only.
  --xwayland-satellite
                 Build/install xwayland-satellite for niri X11 app support.
  --niri-source  Build/install niri from source; extra args are forwarded.
  --system       Install user files and system greetd/niri session templates.
  --doom         Install user files and Doom Emacs packages/env.
  --all          Install packages, external tools, user files, system files, Doom.
EOF
}

retry_cmd() {
    local attempts="$1"
    local delay="$2"
    local status
    local attempt=1
    shift 2

    until "$@"; do
        status=$?
        if [ "$attempt" -ge "$attempts" ]; then
            return "$status"
        fi
        printf 'retry %s/%s failed; waiting %ss: %s\n' "$attempt" "$attempts" "$delay" "$*"
        sleep "$delay"
        attempt=$((attempt + 1))
        delay=$((delay * 2))
    done
}

git_remote() {
    retry_cmd 5 3 git \
        -c http.version=HTTP/1.1 \
        -c http.lowSpeedLimit=1024 \
        -c http.lowSpeedTime=30 \
        "$@"
}

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
        .config/starship.toml \
        .config/swaylock \
        .config/waybar \
        .config/wlogout \
        .config/xdg-desktop-portal \
        .local/share/applications/google-chrome.desktop \
        .local/share/wallpapers/default.png \
        .local/share/wallpapers/niri-overview.png; do
        link_item "$item"
    done

    install_tmux
    install_doom
    install_neovim_lazy
    install_emacs_shims
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
        git_remote -C "$target" pull --ff-only
    elif [ -e "$target" ]; then
        printf 'skip Oh my tmux clone; %s exists and is not a git checkout\n' "$target" >&2
    else
        git_remote clone --single-branch https://github.com/gpakosz/.tmux.git "$target"
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
        git_remote -C "$target" pull --ff-only
    elif [ -e "$target" ]; then
        printf 'skip Doom clone; %s exists and is not a git checkout\n' "$target" >&2
    else
        git_remote clone --depth 1 https://github.com/doomemacs/doomemacs "$target"
    fi

    mkdir -p -- "$HOME/.local/bin"
    if [ -x "$target/bin/doom" ]; then
        ln -sfn -- "$target/bin/doom" "$HOME/.local/bin/doom"
    fi
}

install_neovim_lazy() {
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local target="$data_home/nvim/lazy/lazy.nvim"
    local lazy_module="$target/lua/lazy/init.lua"
    local backup

    if [ -f "$lazy_module" ]; then
        return
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        backup="$target.backup-$(date +%Y%m%d-%H%M%S)"
        mv -- "$target" "$backup"
        printf 'Moved incomplete lazy.nvim checkout to %s\n' "$backup" >&2
    fi

    mkdir -p -- "$(dirname -- "$target")"
    git_remote clone --filter=blob:none --branch=stable https://github.com/folke/lazy.nvim.git "$target"
}

install_neovim() {
    link_item ".config/nvim"
    install_neovim_lazy
}

install_emacs_shims() {
    mkdir -p -- "$HOME/.local/bin"

    if [ -x /usr/bin/emacs ]; then
        ln -sfn -- /usr/bin/emacs "$HOME/.local/bin/emacs"
    fi
    if [ -x /usr/bin/emacsclient ]; then
        ln -sfn -- /usr/bin/emacsclient "$HOME/.local/bin/emacsclient"
    fi
}

require_apt_emacs() {
    if [ ! -x /usr/bin/emacs ]; then
        printf 'apt Emacs was not found at /usr/bin/emacs; run ./install.sh --packages before Doom setup.\n' >&2
        printf 'This avoids running Doom through the snap emacs wrapper, which can fail under confinement.\n' >&2
        exit 1
    fi

    install_emacs_shims
}

refresh_doom_recipe_repositories() {
    local repos_dir="$HOME/.config/emacs/.local/straight/repos"
    local repo
    local dir
    local recipe_repos=(
        melpa
        nongnu-elpa
        gnu-elpa-mirror
        el-get
        emacsmirror-mirror
        org
    )

    [ -d "$repos_dir" ] || return 0

    for repo in "${recipe_repos[@]}"; do
        dir="$repos_dir/$repo"
        [ -d "$dir/.git" ] || continue
        git_remote -C "$dir" pull --ff-only
    done
}

install_doom_profile() {
    install_user
    run_doom_install
}

run_doom_install() {
    local doom="$HOME/.config/emacs/bin/doom"
    local profile="$HOME/.config/emacs/.local/cache/profiles.@.el"

    if [ ! -x "$HOME/.config/emacs/bin/doom" ]; then
        printf 'Doom executable not found; check ~/.config/emacs.\n' >&2
        exit 1
    fi

    require_apt_emacs
    if [ -f "$profile" ]; then
        refresh_doom_recipe_repositories
        "$doom" sync -u
    else
        "$doom" install -!
    fi
    "$doom" env
}

install_npm_globals() {
    if [ ! -x "$(command -v npm 2>/dev/null || true)" ]; then
        printf 'skip npm globals; npm is not installed\n' >&2
        return
    fi

    mkdir -p -- "$HOME/.local"
    grep -vE '^\s*(#|$)' "$repo_dir/packages/npm-global.txt" |
        xargs -r npm install -g --prefix "$HOME/.local"
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

ensure_backlight_access() {
    if ! getent group video >/dev/null 2>&1; then
        return
    fi

    if id -nG "$USER" | tr ' ' '\n' | grep -qx video; then
        return
    fi

    sudo usermod -aG video "$USER"
    printf 'Added %s to the video group for backlight controls. Log out and back in for it to apply.\n' "$USER"
}

install_python_tool_shims() {
    mkdir -p -- "$HOME/.local/bin"

    if command -v fdfind >/dev/null 2>&1; then
        ln -sfn -- "$(command -v fdfind)" "$HOME/.local/bin/fd"
    fi
    if command -v pyflakes3 >/dev/null 2>&1; then
        ln -sfn -- "$(command -v pyflakes3)" "$HOME/.local/bin/pyflakes"
    fi
    if command -v nosetests3 >/dev/null 2>&1; then
        ln -sfn -- "$(command -v nosetests3)" "$HOME/.local/bin/nosetests"
    fi
}

install_packages() {
    local packages=()

    apt_update
    mapfile -t packages < <(grep -vE '^\s*(#|$)' "$repo_dir/packages/apt.txt")
    if [ "${#packages[@]}" -gt 0 ]; then
        apt_install "${packages[@]}"
    fi

    if [ -f "$repo_dir/packages/apt-no-recommends.txt" ]; then
        packages=()
        mapfile -t packages < <(grep -vE '^\s*(#|$)' "$repo_dir/packages/apt-no-recommends.txt")
        if [ "${#packages[@]}" -gt 0 ]; then
            apt_install_no_recommends "${packages[@]}"
        fi
    fi
    install_xwayland_satellite --skip-deps
    ensure_backlight_access
    install_npm_globals
    install_neovim_lazy
    install_emacs_shims
    install_rust_analyzer
    install_python_tool_shims
}

install_system() {
    sudo install -D -m 0644 "$repo_dir/system/etc/greetd/config.toml" /etc/greetd/config.toml
    sudo install -D -m 0644 "$repo_dir/system/usr/share/wayland-sessions/niri.desktop" /usr/share/wayland-sessions/niri.desktop
    sudo install -D -m 0755 "$repo_dir/system/usr/local/bin/niri-session" /usr/local/bin/niri-session

    if [ -x /usr/sbin/greetd ]; then
        printf '/usr/sbin/greetd\n' | sudo tee /etc/X11/default-display-manager >/dev/null
    fi

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl disable gdm3.service gdm.service >/dev/null 2>&1 || true
        sudo systemctl enable greetd.service >/dev/null
    fi
}

install_external() {
    "$repo_dir/scripts/install-external.sh"
}

install_wallpapers() {
    "$repo_dir/scripts/install-external.sh" --wallpapers-only
}

install_xwayland_satellite() {
    "$repo_dir/scripts/install-xwayland-satellite.sh" "$@"
}

case "${1:-}" in
    -h | --help)
        usage
        exit 0
        ;;
    --packages)
        install_packages
        ;;
    --external)
        install_external
        ;;
    --wallpapers)
        install_wallpapers
        ;;
    --nvim)
        install_neovim
        ;;
    --xwayland-satellite)
        shift
        install_xwayland_satellite "$@"
        exit 0
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
        install_external
        install_user
        install_system
        run_doom_install
        ;;
    "")
        install_user
        ;;
    *)
        printf 'unknown option: %s\n\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac

if [ -d "$backup_dir" ]; then
    printf 'Existing files were backed up to %s\n' "$backup_dir"
fi
printf 'Dotfiles install complete.\n'
