#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
backup_dir="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
export PATH="$HOME/.local/bin:$PATH"
profile="${DOTFILES_PROFILE:-minimal}"
install_doom_packages="${DOTFILES_INSTALL_DOOM_PACKAGES:-1}"

# shellcheck source=scripts/lib/apt.sh
. "$repo_dir/scripts/lib/apt.sh"

usage() {
    cat <<'EOF'
Usage: ./install.sh [--profile desktop|minimal] [--skip-doom-packages] [--packages|--external|--wallpapers|--nvim|--xwayland-satellite|--niri-source|--system|--system-niri-session|--system-greetd|--doom|--all]

With no arguments, installs user dotfile symlinks, local helper scripts, and tool bootstraps.

Options:
  --profile NAME  Install profile: desktop keeps GDM/GNOME defaults, minimal owns the login stack.
  --skip-doom-packages
                 Do not install Emacs/Doom apt packages or npm globals during --packages.
  --packages     Install apt packages, optional npm globals, rust-analyzer, and shims.
  --external     Install external tools: Chrome, Yazi, swww, fonts, wallpapers.
  --wallpapers   Install or update the Catppuccin wallpaper collection only.
  --nvim         Install Neovim config and lazy.nvim bootstrap only.
  --xwayland-satellite
                 Build/install xwayland-satellite for niri X11 app support.
  --niri-source  Build/install niri from source; extra args are forwarded.
  --system       Install user symlinks and profile-specific system templates.
  --system-niri-session
                 Install the niri session entry without changing the display manager.
  --system-greetd
                 Install greetd templates and switch the default display manager to greetd.
  --doom         Install Doom Emacs config, packages, and env.
  --all          Install packages, external tools, user files, profile system files, Doom.
EOF
}

validate_profile() {
    case "$profile" in
        desktop | minimal)
            ;;
        *)
            printf 'unknown profile: %s\n' "$profile" >&2
            printf 'expected: desktop or minimal\n' >&2
            exit 2
            ;;
    esac
}

validate_doom_package_flag() {
    case "$install_doom_packages" in
        0 | 1)
            ;;
        *)
            printf 'DOTFILES_INSTALL_DOOM_PACKAGES must be 0 or 1, got: %s\n' "$install_doom_packages" >&2
            exit 2
            ;;
    esac
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

without_proxy_env() {
    env \
        -u HTTP_PROXY \
        -u HTTPS_PROXY \
        -u ALL_PROXY \
        -u NO_PROXY \
        -u http_proxy \
        -u https_proxy \
        -u all_proxy \
        -u no_proxy \
        "$@"
}

link_item() {
    local rel="$1"
    local src="$repo_dir/home/$rel"
    local dst="$HOME/$rel"
    local resolved_src
    local resolved_dst

    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
        printf 'skip missing source: %s\n' "$src" >&2
        return
    fi

    ensure_link_parent_dir "$rel"

    resolved_src="$(readlink -f -- "$src" 2>/dev/null || true)"
    resolved_dst="$(readlink -f -- "$dst" 2>/dev/null || true)"
    if [ -n "$resolved_src" ] && [ "$resolved_src" = "$resolved_dst" ]; then
        return
    fi

    if [ -L "$dst" ] && [ "$(readlink -- "$dst")" = "$src" ]; then
        return
    fi

    if [ -e "$dst" ] || [ -L "$dst" ]; then
        mkdir -p -- "$backup_dir/$(dirname -- "$rel")"
        mv -- "$dst" "$backup_dir/$rel"
    fi

    ln -s -- "$src" "$dst"
}

ensure_link_parent_dir() {
    local rel="$1"
    local parent
    local target
    local repo_home

    parent="$HOME/$(dirname -- "$rel")"
    if [ "$parent" = "$HOME/." ]; then
        parent="$HOME"
    fi

    if [ -L "$parent" ]; then
        target="$(readlink -f -- "$parent" 2>/dev/null || true)"
        repo_home="$(readlink -f -- "$repo_dir/home" 2>/dev/null || true)"
        if [ -n "$target" ] && [ -n "$repo_home" ]; then
            case "$target" in
                "$repo_home" | "$repo_home"/*)
                    rm -- "$parent"
                    ;;
            esac
        fi
    fi

    mkdir -p -- "$parent"
}

install_user_files() {
    local item
    local items=(
        .bashrc
        .zshrc
        .gitconfig
        .config/doom
        .config/fcitx5
        .config/fuzzel
        .config/ghostty
        .config/mako
        .config/niri-xdg-terminals.list
        .config/niri
        .config/nvim
        .config/starship.toml
        .config/swaylock
        .config/waybar
        .config/wlogout
        .config/xdg-terminals.list
        .config/xdg-desktop-portal
        .config/xfce4/helpers.rc
        .local/share/applications/dotfiles-terminal.desktop
        .local/share/wallpapers/default.png
        .local/share/wallpapers/niri-overview.png
    )

    if [ "$profile" = "minimal" ]; then
        items+=(
            .config/environment.d
            .config/mimeapps.list
            .local/share/applications/google-chrome.desktop
        )
    fi

    for item in "${items[@]}"; do
        link_item "$item"
    done

    for item in "$repo_dir"/home/.local/bin/*; do
        [ -e "$item" ] || continue
        link_item ".local/bin/$(basename -- "$item")"
        chmod +x -- "$HOME/.local/bin/$(basename -- "$item")"
    done
}

install_user_tools() {
    install_tmux
    install_doom
    install_neovim_lazy
    install_neovim_plugins
    install_emacs_shims
    install_python_tool_shims
}

install_user() {
    install_user_files
    install_user_tools
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
    install_doom_emacs_dir_link
}

install_doom_emacs_dir_link() {
    local target="$HOME/.config/emacs"
    local legacy="$HOME/.emacs.d"
    local resolved_legacy
    local resolved_target

    resolved_target="$(readlink -f -- "$target" 2>/dev/null || true)"
    resolved_legacy="$(readlink -f -- "$legacy" 2>/dev/null || true)"
    if [ -n "$resolved_target" ] && [ "$resolved_legacy" = "$resolved_target" ]; then
        return
    fi

    if [ -e "$legacy" ] || [ -L "$legacy" ]; then
        mkdir -p -- "$backup_dir"
        mv -- "$legacy" "$backup_dir/.emacs.d"
    fi

    ln -s -- "$target" "$legacy"
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

neovim_locked_plugins() {
    local lock="$repo_dir/home/.config/nvim/lazy-lock.json"

    [ -f "$lock" ] || return 0

    if command -v python3 >/dev/null 2>&1; then
        python3 - "$lock" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)

for name in sorted(data):
    print(name)
PY
    else
        sed -n 's/^[[:space:]]*"\([^"]*\)":[[:space:]]*{.*/\1/p' "$lock"
    fi
}

neovim_plugin_complete() {
    local dir="$1"

    [ -d "$dir/.git" ] || return 1
    git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1 || return 1
    git -C "$dir" status --short >/dev/null 2>&1 || return 1
}

repair_incomplete_neovim_plugins() {
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local plugin
    local dir
    local backup

    while IFS= read -r plugin; do
        [ -n "$plugin" ] || continue
        [ "$plugin" != "lazy.nvim" ] || continue

        dir="$data_home/nvim/lazy/$plugin"
        [ -e "$dir" ] || [ -L "$dir" ] || continue

        if ! neovim_plugin_complete "$dir"; then
            backup="$dir.backup-$(date +%Y%m%d-%H%M%S)"
            mv -- "$dir" "$backup"
            printf 'Moved incomplete Neovim plugin checkout to %s\n' "$backup" >&2
        fi
    done < <(neovim_locked_plugins)
}

run_neovim_lazy_restore() {
    env \
        GIT_TERMINAL_PROMPT=0 \
        GIT_CONFIG_COUNT=3 \
        GIT_CONFIG_KEY_0=http.version \
        GIT_CONFIG_VALUE_0=HTTP/1.1 \
        GIT_CONFIG_KEY_1=http.lowSpeedLimit \
        GIT_CONFIG_VALUE_1=1024 \
        GIT_CONFIG_KEY_2=http.lowSpeedTime \
        GIT_CONFIG_VALUE_2=30 \
        nvim --headless '+Lazy! restore' +qa
}

install_neovim_plugins() {
    if ! command -v nvim >/dev/null 2>&1; then
        printf 'skip Neovim plugin restore; nvim is not installed\n' >&2
        return
    fi
    if [ ! -e "$HOME/.config/nvim/init.lua" ] && [ ! -L "$HOME/.config/nvim/init.lua" ]; then
        printf 'skip Neovim plugin restore; ~/.config/nvim is not installed\n' >&2
        return
    fi

    install_neovim_lazy
    repair_incomplete_neovim_plugins
    if retry_cmd 3 10 run_neovim_lazy_restore; then
        return
    fi

    repair_incomplete_neovim_plugins
    retry_cmd 2 10 run_neovim_lazy_restore
}

repair_incomplete_doom_straight() {
    local target="$HOME/.config/emacs/.local/straight/repos/straight.el"
    local straight_module="$target/straight.el"
    local backup

    if [ -f "$straight_module" ]; then
        return 0
    fi

    if [ -e "$target" ] || [ -L "$target" ]; then
        backup="$target.backup-$(date +%Y%m%d-%H%M%S)"
        mv -- "$target" "$backup"
        printf 'Moved incomplete straight.el checkout to %s\n' "$backup" >&2
    fi
}

ensure_doom_straight_bootstrap() {
    local target="$HOME/.config/emacs/.local/straight/repos/straight.el"
    local straight_module="$target/straight.el"

    if [ -f "$straight_module" ]; then
        return 0
    fi

    repair_incomplete_doom_straight
    mkdir -p -- "$(dirname -- "$target")"
    git_remote clone --single-branch --branch develop https://github.com/radian-software/straight.el "$target"
}

install_neovim() {
    link_item ".config/nvim"
    install_neovim_lazy
    install_neovim_plugins
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
    )

    [ -d "$repos_dir" ] || return 0

    for repo in "${recipe_repos[@]}"; do
        dir="$repos_dir/$repo"
        [ -d "$dir/.git" ] || continue
        git_remote -C "$dir" pull --ff-only
    done
}

install_doom_profile() {
    link_item ".config/doom"
    install_doom
    install_emacs_shims
    run_doom_install
}

run_doom_install() {
    local doom="$HOME/.config/emacs/bin/doom"
    local profile="$HOME/.config/emacs/.local/cache/profiles.@.el"
    local straight_module="$HOME/.config/emacs/.local/straight/repos/straight.el/straight.el"

    if [ ! -x "$HOME/.config/emacs/bin/doom" ]; then
        printf 'Doom executable not found; check ~/.config/emacs.\n' >&2
        exit 1
    fi

    require_apt_emacs
    ensure_doom_straight_bootstrap
    if [ -f "$profile" ]; then
        refresh_doom_recipe_repositories
        if ! "$doom" sync -u; then
            if [ ! -f "$straight_module" ]; then
                ensure_doom_straight_bootstrap
                refresh_doom_recipe_repositories
                "$doom" sync -u
            else
                return 1
            fi
        fi
    else
        if ! "$doom" install -!; then
            if [ ! -f "$straight_module" ]; then
                ensure_doom_straight_bootstrap
                "$doom" install -!
            else
                return 1
            fi
        fi
    fi
    without_proxy_env "$doom" env
    write_doom_config_stamp
}

doom_config_fingerprint() {
    local file
    local files=(
        "$repo_dir/home/.config/doom/init.el"
        "$repo_dir/home/.config/doom/packages.el"
    )

    for file in "${files[@]}"; do
        [ -f "$file" ] || continue
        sha256sum "$file"
    done | sha256sum | awk '{print $1}'
}

write_doom_config_stamp() {
    local state_dir="$HOME/.config/emacs/.local/state"

    mkdir -p -- "$state_dir"
    doom_config_fingerprint >"$state_dir/dotfiles-doom.sha256"
}

install_npm_globals() {
    if [ ! -x "$(command -v npm 2>/dev/null || true)" ]; then
        printf 'skip npm globals; npm is not installed\n' >&2
        return
    fi

    local packages=()
    local npm_proxy_value="${DOTFILES_NPM_PROXY:-}"
    local http_proxy_value="${DOTFILES_NPM_HTTP_PROXY:-$npm_proxy_value}"
    local https_proxy_value="${DOTFILES_NPM_HTTPS_PROXY:-$npm_proxy_value}"
    local npm_args=(
        install
        -g
        --prefix "$HOME/.local"
        --progress=false
        --loglevel=warn
        --fetch-retries=5
        --fetch-retry-mintimeout=10000
        --fetch-retry-maxtimeout=120000
        --fetch-timeout=120000
    )

    if [ -z "$http_proxy_value" ]; then
        http_proxy_value="${HTTP_PROXY:-${http_proxy:-${ALL_PROXY:-${all_proxy:-}}}}"
    fi
    if [ -z "$https_proxy_value" ]; then
        https_proxy_value="${HTTPS_PROXY:-${https_proxy:-$http_proxy_value}}"
    fi

    if [ -n "${DOTFILES_NPM_REGISTRY:-}" ]; then
        npm_args+=(--registry "$DOTFILES_NPM_REGISTRY")
    fi
    if [ -n "$http_proxy_value" ]; then
        npm_args+=(--proxy "$http_proxy_value")
    fi
    if [ -n "$https_proxy_value" ]; then
        npm_args+=(--https-proxy "$https_proxy_value")
    fi

    mkdir -p -- "$HOME/.local"
    mapfile -t packages < <(grep -vE '^\s*(#|$)' "$repo_dir/packages/npm-global.txt")
    if [ "${#packages[@]}" -eq 0 ]; then
        return
    fi

    retry_cmd 3 10 npm "${npm_args[@]}" "${packages[@]}"
}

install_rust_analyzer() {
    local arch
    local tmp
    local speed_limit="${DOTFILES_DOWNLOAD_SPEED_LIMIT:-1024}"
    local speed_time="${DOTFILES_DOWNLOAD_SPEED_TIME:-60}"
    arch="$(uname -m)"

    if [ "$arch" != "x86_64" ]; then
        printf 'skip rust-analyzer auto-install; unsupported arch: %s\n' "$arch" >&2
        return
    fi

    mkdir -p -- "$HOME/.local/bin"
    tmp="$(mktemp)"
    retry_cmd 5 3 curl -L --fail \
        --retry 5 \
        --retry-delay 2 \
        --retry-all-errors \
        --connect-timeout 20 \
        --speed-limit "$speed_limit" \
        --speed-time "$speed_time" \
        --continue-at - \
        --output "$tmp" \
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

package_files() {
    local kind="$1"
    local files=()
    local file

    case "$kind" in
        apt)
            files=(
                "$repo_dir/packages/apt.txt"
            )
            if [ "$profile" = "minimal" ]; then
                files+=("$repo_dir/packages/apt-minimal-session.txt")
            fi
            if [ "$install_doom_packages" -eq 1 ]; then
                files+=("$repo_dir/packages/apt-doom.txt")
            fi
            ;;
        apt-no-recommends)
            files=(
                "$repo_dir/packages/apt-no-recommends.txt"
            )
            ;;
        *)
            printf 'unknown package list kind: %s\n' "$kind" >&2
            return 2
            ;;
    esac

    for file in "${files[@]}"; do
        [ -f "$file" ] || continue
        printf '%s\n' "$file"
    done
}

package_list() {
    local kind="$1"
    local file

    while IFS= read -r file; do
        grep -vE '^\s*(#|$)' "$file"
    done < <(package_files "$kind")
}

install_packages() {
    local packages=()

    apt_update
    mapfile -t packages < <(package_list apt)
    if [ "${#packages[@]}" -gt 0 ]; then
        apt_install "${packages[@]}"
    fi

    if package_files apt-no-recommends >/dev/null; then
        packages=()
        mapfile -t packages < <(package_list apt-no-recommends)
        if [ "${#packages[@]}" -gt 0 ]; then
            apt_install_no_recommends "${packages[@]}"
        fi
    fi
    install_xwayland_satellite --skip-deps
    ensure_backlight_access
    if [ "$install_doom_packages" -eq 1 ]; then
        install_npm_globals
    fi
    install_neovim_lazy
    install_emacs_shims
    install_rust_analyzer
    install_python_tool_shims
}

install_niri_session_entry() {
    sudo install -D -m 0644 "$repo_dir/system/usr/share/wayland-sessions/niri.desktop" /usr/share/wayland-sessions/niri.desktop
    sudo install -D -m 0755 "$repo_dir/system/usr/local/bin/niri-session" /usr/local/bin/niri-session
}

set_gdm_default_session() {
    [ "$profile" = "desktop" ] || return 0
    [ -d /var/lib/AccountsService/users ] || return 0

    sudo python3 - "$USER" <<'PY'
from pathlib import Path
import sys

user = sys.argv[1]
path = Path("/var/lib/AccountsService/users") / user
text = path.read_text(encoding="utf-8") if path.exists() else ""
lines = text.splitlines()

out = []
in_user = False
seen_user = False
wrote_session = False

for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        if in_user and not wrote_session:
            out.append("Session=niri")
            wrote_session = True
        in_user = stripped == "[User]"
        seen_user = seen_user or in_user
        out.append(line)
        continue

    if in_user and stripped.startswith("Session="):
        if not wrote_session:
            out.append("Session=niri")
            wrote_session = True
        continue

    out.append(line)

if not seen_user:
    out.insert(0, "Session=niri")
    out.insert(0, "[User]")
elif in_user and not wrote_session:
    out.append("Session=niri")

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text("\n".join(out) + "\n", encoding="utf-8")
path.chmod(0o600)
PY

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl try-restart accounts-daemon.service >/dev/null 2>&1 || true
    fi
}

install_greetd_system() {
    sudo install -D -m 0644 "$repo_dir/system/etc/greetd/config.toml" /etc/greetd/config.toml
    install_niri_session_entry

    if [ -x /usr/sbin/greetd ]; then
        printf '/usr/sbin/greetd\n' | sudo tee /etc/X11/default-display-manager >/dev/null
    fi

    if command -v systemctl >/dev/null 2>&1; then
        sudo systemctl disable gdm3.service gdm.service >/dev/null 2>&1 || true
        sudo systemctl enable greetd.service >/dev/null
    fi
}

install_system() {
    if [ "$profile" = "desktop" ]; then
        install_niri_session_entry
        set_gdm_default_session
    else
        install_greetd_system
    fi
}

install_external() {
    DOTFILES_PROFILE="$profile" "$repo_dir/scripts/install-external.sh"
}

install_wallpapers() {
    DOTFILES_PROFILE="$profile" "$repo_dir/scripts/install-external.sh" --wallpapers-only
}

install_xwayland_satellite() {
    "$repo_dir/scripts/install-xwayland-satellite.sh" "$@"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --profile)
            [ "$#" -ge 2 ] || {
                printf 'missing value for --profile\n' >&2
                exit 2
            }
            profile="$2"
            shift 2
            ;;
        --skip-doom-packages)
            install_doom_packages=0
            shift
            ;;
        --with-doom-packages)
            install_doom_packages=1
            shift
            ;;
        *)
            break
            ;;
    esac
done

validate_profile
validate_doom_package_flag

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
        install_user_files
        install_system
        ;;
    --system-niri-session)
        install_niri_session_entry
        ;;
    --system-greetd)
        install_greetd_system
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
