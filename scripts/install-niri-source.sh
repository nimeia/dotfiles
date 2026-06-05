#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"

# shellcheck source=scripts/lib/apt.sh
. "$repo_dir/scripts/lib/apt.sh"

niri_repo="https://github.com/niri-wm/niri.git"
niri_ref="${NIRI_REF:-}"
source_dir="${NIRI_SOURCE_DIR:-$HOME/.local/src/niri}"
skip_deps=0
build_only=0
force=0
with_gnome_portal=0

usage() {
    cat <<'EOF'
Usage: scripts/install-niri-source.sh [options]

Build and install niri from source.

Options:
  --ref REF          Git ref to build, such as v26.04, main, or a commit.
                     Defaults to the latest GitHub release tag.
  --repo URL         Source repository URL. Defaults to niri-wm/niri.
  --source-dir DIR   Checkout directory. Defaults to ~/.local/src/niri.
  --skip-deps        Do not install apt build/runtime dependencies.
  --with-gnome-portal
                     Also install xdg-desktop-portal-gnome for screencasting.
                     Installed without recommended packages to avoid a full GNOME session.
  --build-only       Build but do not install system files.
  --force            Remove a non-git source directory if it blocks clone.
  -h, --help         Show this help.

After installation, run ./install.sh --system if you want to reapply the
tracked greetd/niri-session templates from this dotfiles repo.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --ref)
            [ "$#" -ge 2 ] || {
                printf 'missing value for --ref\n' >&2
                exit 2
            }
            niri_ref="$2"
            shift
            ;;
        --repo)
            [ "$#" -ge 2 ] || {
                printf 'missing value for --repo\n' >&2
                exit 2
            }
            niri_repo="$2"
            shift
            ;;
        --source-dir)
            [ "$#" -ge 2 ] || {
                printf 'missing value for --source-dir\n' >&2
                exit 2
            }
            source_dir="$2"
            shift
            ;;
        --skip-deps)
            skip_deps=1
            ;;
        --with-gnome-portal)
            with_gnome_portal=1
            ;;
        --build-only)
            build_only=1
            ;;
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

install_dependencies() {
    local packages=(
        build-essential
        ca-certificates
        cargo
        clang
        curl
        gcc
        git
        jq
        libdbus-1-dev
        libdisplay-info-dev
        libegl1-mesa-dev
        libgbm-dev
        libinput-dev
        libpango1.0-dev
        libpipewire-0.3-dev
        libseat-dev
        libsystemd-dev
        libudev-dev
        libwayland-dev
        libwayland-server0
        libxkbcommon-dev
        pkg-config
        rustc
        xdg-desktop-portal
        xdg-desktop-portal-gtk
        xwayland
    )

    log "install niri build and recommended runtime dependencies"
    apt_update
    apt_install "${packages[@]}"

    if [ "$with_gnome_portal" -eq 1 ]; then
        apt_install_no_recommends xdg-desktop-portal-gnome
    fi
}

resolve_ref() {
    if [ -n "$niri_ref" ]; then
        printf '%s\n' "$niri_ref"
        return
    fi

    have curl || die "curl is required to resolve the latest niri release"
    have jq || die "jq is required to resolve the latest niri release"

    niri_ref="$(
        curl -fsSL \
            --retry 5 \
            --retry-delay 2 \
            --retry-all-errors \
            --connect-timeout 20 \
            --speed-limit "${DOTFILES_DOWNLOAD_SPEED_LIMIT:-1024}" \
            --speed-time "${DOTFILES_DOWNLOAD_SPEED_TIME:-60}" \
            "https://api.github.com/repos/niri-wm/niri/releases/latest" |
            jq -r '.tag_name // empty'
    )"

    [ -n "$niri_ref" ] || die "could not resolve latest niri release tag"
    printf '%s\n' "$niri_ref"
}

clone_source() {
    local ref="$1"

    log "clone niri source"
    mkdir -p -- "$(dirname -- "$source_dir")"
    if git_remote clone --depth 1 --branch "$ref" "$niri_repo" "$source_dir"; then
        return
    fi

    warn "shallow clone failed; retrying with blob filtering"
    rm -rf -- "$source_dir"
    git_remote clone --filter=blob:none "$niri_repo" "$source_dir"
}

prepare_source() {
    local ref="$1"

    if [ -d "$source_dir/.git" ]; then
        log "update existing niri source checkout"
        if ! git -C "$source_dir" rev-parse --git-dir >/dev/null 2>&1; then
            warn "existing niri source checkout is incomplete; recloning"
            rm -rf -- "$source_dir"
            clone_source "$ref"
        elif ! git_remote -C "$source_dir" fetch --tags --prune --depth 1 origin "$ref"; then
            git_remote -C "$source_dir" fetch --tags --prune origin
        fi
    elif [ -e "$source_dir" ]; then
        if [ "$force" -eq 1 ]; then
            log "remove non-git source directory: $source_dir"
            rm -rf -- "$source_dir"
            clone_source "$ref"
        else
            die "$source_dir exists and is not a git checkout; pass --force to replace it"
        fi
    else
        clone_source "$ref"
    fi

    log "checkout niri ref: $ref"
    git -C "$source_dir" checkout --detach "$ref"
}

build_niri() {
    local commit
    commit="$(git -C "$source_dir" rev-parse --short HEAD)"
    export NIRI_BUILD_COMMIT="$commit"

    have cargo || die "cargo is required; run ./install.sh --packages or install Rust first"

    log "build niri release binary"
    export CARGO_NET_GIT_FETCH_WITH_CLI="${CARGO_NET_GIT_FETCH_WITH_CLI:-true}"
    retry_cmd 3 10 cargo build --release --locked --manifest-path "$source_dir/Cargo.toml"
}

install_if_exists() {
    local mode="$1"
    local src="$2"
    local dst="$3"

    if [ -e "$src" ]; then
        sudo install -D -m "$mode" "$src" "$dst"
    else
        warn "skip missing resource: $src"
    fi
}

install_niri() {
    local binary="$source_dir/target/release/niri"
    [ -x "$binary" ] || die "built niri binary not found: $binary"

    log "install niri binary and upstream resources"
    sudo install -D -m 0755 "$binary" /usr/local/bin/niri

    install_if_exists 0755 "$source_dir/resources/niri-session" /usr/local/bin/niri-session.upstream
    install_if_exists 0644 "$source_dir/resources/niri.desktop" /usr/local/share/wayland-sessions/niri.desktop
    install_if_exists 0644 "$source_dir/resources/niri-portals.conf" /usr/local/share/xdg-desktop-portal/niri-portals.conf
    install_if_exists 0644 "$source_dir/resources/niri.service" /etc/systemd/user/niri.service
    install_if_exists 0644 "$source_dir/resources/niri-shutdown.target" /etc/systemd/user/niri-shutdown.target

    if [ -f "$repo_dir/system/usr/local/bin/niri-session" ]; then
        log "apply dotfiles niri-session wrapper"
        sudo install -D -m 0755 "$repo_dir/system/usr/local/bin/niri-session" /usr/local/bin/niri-session
    elif [ -f "$source_dir/resources/niri-session" ]; then
        sudo install -D -m 0755 "$source_dir/resources/niri-session" /usr/local/bin/niri-session
    fi

    if [ -f "$repo_dir/system/usr/share/wayland-sessions/niri.desktop" ]; then
        log "apply dotfiles display-manager session entry"
        sudo install -D -m 0644 "$repo_dir/system/usr/share/wayland-sessions/niri.desktop" /usr/share/wayland-sessions/niri.desktop
    elif [ -f "$source_dir/resources/niri.desktop" ]; then
        sudo install -D -m 0644 "$source_dir/resources/niri.desktop" /usr/share/wayland-sessions/niri.desktop
    fi

    systemctl --user daemon-reload >/dev/null 2>&1 || true
}

check_runtime_recommendations() {
    if ! have xwayland-satellite; then
        warn "xwayland-satellite is not in PATH; run ./install.sh --xwayland-satellite so niri can run X11 applications"
    fi

    if ! dpkg-query -W -f='${db:Status-Abbrev}' xdg-desktop-portal-gnome 2>/dev/null | grep -q '^ii '; then
        warn "xdg-desktop-portal-gnome is not installed; run ./install.sh --packages or pass --with-gnome-portal if you need screencasting"
    fi
}

print_status() {
    log "niri install status"
    if [ -x /usr/local/bin/niri ]; then
        /usr/local/bin/niri --version || true
    fi

    printf '  source: %s\n' "$source_dir"
    printf '  binary: /usr/local/bin/niri\n'
    printf '  session wrapper: /usr/local/bin/niri-session\n'
    printf '  systemd user unit: /etc/systemd/user/niri.service\n'
}

if [ "$skip_deps" -eq 0 ]; then
    install_dependencies
fi

ref="$(resolve_ref)"
prepare_source "$ref"
build_niri

if [ "$build_only" -eq 0 ]; then
    install_niri
fi

check_runtime_recommendations
print_status
