#!/usr/bin/env bash
set -euo pipefail

force=0

usage() {
    cat <<'EOF'
Usage: scripts/install-external.sh [--force]

Installs external or non-apt items used by this dotfiles setup:
  - Google Chrome from the official .deb
  - Yazi from the latest GitHub release
  - swww via cargo
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
        gzip
        jq
        libnotify-bin
        orca
        tar
        unzip
        xdg-utils
    )

    log "install apt prerequisites and optional desktop helpers"
    sudo apt update
    sudo apt install -y "${required[@]}"

    if apt_has_package ghostty; then
        sudo apt install -y ghostty
    else
        warn "ghostty is not available from apt on this system; the local Ghostty bundle is still supported if installed under ~/.local/ghostty"
    fi
}

download() {
    local url="$1"
    local output="$2"
    curl -fL --retry 3 --connect-timeout 20 -o "$output" "$url"
}

set_chrome_as_default() {
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
    sudo apt install -y "$tmp/google-chrome.deb"
    rm -rf -- "$tmp"
    set_chrome_as_default
}

github_latest_asset_url() {
    local repo="$1"
    local pattern="$2"

    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
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

    log "install swww with cargo"
    cargo install --locked swww
    mkdir -p -- "$HOME/.local/bin"
    ln -sfn -- "$HOME/.cargo/bin/swww" "$HOME/.local/bin/swww"
    ln -sfn -- "$HOME/.cargo/bin/swww-daemon" "$HOME/.local/bin/swww-daemon"
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
    for cmd in google-chrome-stable ghostty yazi ya swww swww-daemon notify-send orca; do
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
}

require_x86_64
install_apt_dependencies
install_chrome
install_yazi
install_swww
check_niri
check_result
