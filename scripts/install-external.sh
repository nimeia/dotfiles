#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
force=0
wallpapers_only=0
export PATH="$HOME/.local/bin:$PATH"

# shellcheck source=scripts/lib/apt.sh
. "$repo_dir/scripts/lib/apt.sh"

usage() {
    cat <<'EOF'
Usage: scripts/install-external.sh [--force] [--wallpapers-only]

Installs external or non-apt items used by this dotfiles setup:
  - Google Chrome from the official .deb
  - Yazi from the latest GitHub release
  - swww from the latest tagged GitHub source release
  - Symbols Nerd Font from the latest Nerd Fonts release
  - Catppuccin wallpaper collection under ~/Pictures/Wallpapers
  - Ghostty from apt when available
  - libnotify-bin and orca from apt

niri is intentionally check-only here because this setup expects it at
/usr/local/bin/niri and its build/install flow is separate from these dotfiles.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --force)
            force=1
            ;;
        --wallpapers-only)
            wallpapers_only=1
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            printf 'unknown option: %s\n\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

log() {
    printf '==> %s\n' "$*"
}

warn() {
    printf 'WARN: %s\n' "$*" >&2
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

have() {
    command -v "$1" >/dev/null 2>&1
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
        log "retry $attempt/$attempts failed; waiting ${delay}s: $*"
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

require_x86_64() {
    [ "$(uname -m)" = "x86_64" ] || die "this script currently supports x86_64 only"
}

apt_has_package() {
    apt-cache show "$1" >/dev/null 2>&1
}

install_apt_dependencies() {
    local required=(
        ca-certificates
        curl
        fontconfig
        git
        gzip
        jq
        liblz4-dev
        libnotify-bin
        libwayland-dev
        orca
        tar
        unzip
        wayland-protocols
        xdg-utils
    )

    log "install apt prerequisites and optional desktop helpers"
    apt_update
    apt_install "${required[@]}"

    if apt_has_package ghostty; then
        apt_install ghostty
    else
        warn "ghostty is not available from apt on this system; the local Ghostty bundle is still supported if installed under ~/.local/ghostty"
    fi
}

download() {
    local url="$1"
    local output="$2"
    curl -fL --retry 5 --retry-delay 2 --connect-timeout 20 -o "$output" "$url"
}

set_chrome_as_default() {
    mkdir -p -- "$HOME/.config"

    if have xdg-mime; then
        xdg-mime default google-chrome.desktop text/html || true
        xdg-mime default google-chrome.desktop x-scheme-handler/http || true
        xdg-mime default google-chrome.desktop x-scheme-handler/https || true
        xdg-mime default google-chrome.desktop x-scheme-handler/about || true
        xdg-mime default google-chrome.desktop x-scheme-handler/unknown || true
    fi

    if have xdg-settings; then
        xdg-settings set default-web-browser google-chrome.desktop >/dev/null 2>&1 || true
    fi
}

install_chrome() {
    if have google-chrome-stable && [ "$force" -eq 0 ]; then
        log "Google Chrome already installed"
        set_chrome_as_default
        return
    fi

    local tmp
    tmp="$(mktemp -d)"
    log "download and install Google Chrome"
    download "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" "$tmp/google-chrome.deb"
    apt_install "$tmp/google-chrome.deb"
    rm -rf -- "$tmp"
    set_chrome_as_default
}

github_latest_asset_url() {
    local repo="$1"
    local pattern="$2"

    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 20 \
        "https://api.github.com/repos/$repo/releases/latest" |
        jq -r --arg pattern "$pattern" '[.assets[] | select(.name | test($pattern)) | .browser_download_url][0] // empty'
}

install_yazi() {
    if [ -x "$HOME/.local/bin/yazi" ] && [ "$force" -eq 0 ]; then
        log "Yazi already installed"
        return
    fi

    local url
    local tmp
    local archive
    local extracted_dir
    local install_dir

    url="$(github_latest_asset_url "sxyazi/yazi" 'yazi-x86_64-unknown-linux-gnu\.zip$')"
    [ -n "$url" ] || die "could not find a Yazi x86_64 Linux release asset"

    tmp="$(mktemp -d)"
    archive="$tmp/yazi.zip"
    install_dir="$HOME/.local/yazi"

    log "download and install Yazi"
    download "$url" "$archive"
    unzip -q "$archive" -d "$tmp/extract"
    extracted_dir="$(find "$tmp/extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    [ -n "$extracted_dir" ] || die "Yazi archive did not contain an extracted directory"

    rm -rf -- "$install_dir"
    mkdir -p -- "$(dirname -- "$install_dir")" "$HOME/.local/bin"
    mv -- "$extracted_dir" "$install_dir"
    chmod +x -- "$install_dir/yazi" "$install_dir/ya"
    ln -sfn -- "$install_dir/yazi" "$HOME/.local/bin/yazi"
    ln -sfn -- "$install_dir/ya" "$HOME/.local/bin/ya"
    rm -rf -- "$tmp"
}

install_swww() {
    if have swww && have swww-daemon && [ "$force" -eq 0 ]; then
        log "swww already installed"
        return
    fi

    have cargo || die "cargo is required to install swww; run ./install.sh --packages first"

    local ref="${SWWW_REF:-v0.11.2}"

    log "install swww from GitHub source: $ref"
    export CARGO_NET_GIT_FETCH_WITH_CLI="${CARGO_NET_GIT_FETCH_WITH_CLI:-true}"
    retry_cmd 3 5 cargo install --locked --git https://github.com/LGFae/swww.git --tag "$ref" swww
    retry_cmd 3 5 cargo install --locked --git https://github.com/LGFae/swww.git --tag "$ref" swww-daemon
    mkdir -p -- "$HOME/.local/bin"
    ln -sfn -- "$HOME/.cargo/bin/swww" "$HOME/.local/bin/swww"
    ln -sfn -- "$HOME/.cargo/bin/swww-daemon" "$HOME/.local/bin/swww-daemon"
}

install_symbols_nerd_font() {
    if have fc-match &&
        fc-match -f '%{family}\n' 'Symbols Nerd Font Mono' | grep -qx 'Symbols Nerd Font Mono' &&
        [ "$force" -eq 0 ]; then
        log "Symbols Nerd Font already installed"
        return
    fi

    local url
    local tmp
    local archive
    local install_dir

    url="$(github_latest_asset_url "ryanoasis/nerd-fonts" 'NerdFontsSymbolsOnly\.tar\.xz$')"
    [ -n "$url" ] || die "could not find a NerdFontsSymbolsOnly release asset"

    tmp="$(mktemp -d)"
    archive="$tmp/NerdFontsSymbolsOnly.tar.xz"
    install_dir="$HOME/.local/share/fonts/NerdFontsSymbolsOnly"

    log "download and install Symbols Nerd Font"
    download "$url" "$archive"
    rm -rf -- "$install_dir"
    mkdir -p -- "$install_dir"
    tar -xJf "$archive" -C "$install_dir"
    if have fc-cache; then
        fc-cache -f "$HOME/.local/share/fonts"
    fi
    rm -rf -- "$tmp"
}

install_wallpaper_collection() {
    have git || die "git is required to install wallpapers; run ./install.sh --packages first"

    local repo="${WALLPAPER_REPO_URL:-https://github.com/zhichaoh/catppuccin-wallpapers.git}"
    local target="${WALLPAPER_REPO_DIR:-$HOME/Pictures/Wallpapers/catppuccin-wallpapers}"
    local sparse_paths=()
    read -r -a sparse_paths <<<"${WALLPAPER_SPARSE_PATHS:-gradients landscapes minimalistic misc patterns waves}"

    apply_wallpaper_sparse_checkout() {
        if ! git_remote -C "$target" sparse-checkout set "${sparse_paths[@]}"; then
            warn "sparse checkout failed; falling back to full checkout"
            git -C "$target" sparse-checkout disable
        fi
    }

    if [ -d "$target/.git" ]; then
        log "update wallpaper collection: $target"
        git_remote -C "$target" pull --ff-only
        apply_wallpaper_sparse_checkout
        return
    fi

    if [ -e "$target" ]; then
        warn "wallpaper target exists and is not a git checkout: $target"
        warn "leaving it untouched; set WALLPAPER_REPO_DIR to another path or move it aside"
        return
    fi

    log "clone Catppuccin wallpaper collection"
    mkdir -p -- "$(dirname -- "$target")"
    git_remote clone --depth 1 --filter=blob:none --sparse "$repo" "$target"
    apply_wallpaper_sparse_checkout
}

check_niri() {
    if have niri || [ -x /usr/local/bin/niri ]; then
        log "niri already installed"
        return
    fi

    warn "niri is not installed. Build/install niri first so /usr/local/bin/niri exists, then run ./install.sh --system."
}

check_result() {
    log "external dependency status"
    for cmd in google-chrome-stable ghostty yazi ya swww swww-daemon notify-send orca direnv; do
        if have "$cmd"; then
            printf '  ok      %s -> %s\n' "$cmd" "$(command -v "$cmd")"
        else
            printf '  missing %s\n' "$cmd"
        fi
    done

    if have niri || [ -x /usr/local/bin/niri ]; then
        printf '  ok      niri\n'
    else
        printf '  missing niri\n'
    fi

    if have fc-match &&
        fc-match -f '%{family}\n' 'Symbols Nerd Font Mono' | grep -qx 'Symbols Nerd Font Mono'; then
        printf '  ok      Symbols Nerd Font Mono\n'
    else
        printf '  missing Symbols Nerd Font Mono\n'
    fi

    local wallpaper_target="${WALLPAPER_REPO_DIR:-$HOME/Pictures/Wallpapers/catppuccin-wallpapers}"
    if [ -d "$wallpaper_target/.git" ]; then
        printf '  ok      wallpapers -> %s\n' "$wallpaper_target"
    else
        printf '  missing wallpapers -> %s\n' "$wallpaper_target"
    fi
}

if [ "$wallpapers_only" -eq 1 ]; then
    install_wallpaper_collection
    check_result
    exit 0
fi

require_x86_64
install_apt_dependencies
install_chrome
install_yazi
install_swww
install_symbols_nerd_font
install_wallpaper_collection
check_niri
check_result
