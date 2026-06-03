#!/usr/bin/env bash
set -euo pipefail

xwayland_satellite_repo="${XWAYLAND_SATELLITE_REPO:-https://github.com/Supreeeme/xwayland-satellite.git}"
xwayland_satellite_ref="${XWAYLAND_SATELLITE_REF:-}"
source_dir="${XWAYLAND_SATELLITE_SOURCE_DIR:-$HOME/.local/src/xwayland-satellite}"
skip_deps=0
build_only=0
force=0

usage() {
    cat <<'EOF'
Usage: scripts/install-xwayland-satellite.sh [options]

Build and install xwayland-satellite from source.

Options:
  --ref REF          Git ref to build, such as v0.8.1, main, or a commit.
                     Defaults to the latest GitHub release tag.
  --repo URL         Source repository URL. Defaults to Supreeeme/xwayland-satellite.
  --source-dir DIR   Checkout directory. Defaults to ~/.local/src/xwayland-satellite.
  --skip-deps        Do not install apt build/runtime dependencies.
  --build-only       Build but do not install the binary.
  --force            Remove a non-git source directory if it blocks clone.
  -h, --help         Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --ref)
            [ "$#" -ge 2 ] || {
                printf 'missing value for --ref\n' >&2
                exit 2
            }
            xwayland_satellite_ref="$2"
            shift
            ;;
        --repo)
            [ "$#" -ge 2 ] || {
                printf 'missing value for --repo\n' >&2
                exit 2
            }
            xwayland_satellite_repo="$2"
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

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

have() {
    command -v "$1" >/dev/null 2>&1
}

install_dependencies() {
    local packages=(
        ca-certificates
        cargo
        clang
        curl
        git
        jq
        libxcb1-dev
        libxcb-cursor-dev
        pkg-config
        rustc
        xwayland
    )

    log "install xwayland-satellite build and runtime dependencies"
    sudo apt update
    sudo apt install -y "${packages[@]}"
}

resolve_ref() {
    if [ -n "$xwayland_satellite_ref" ]; then
        printf '%s\n' "$xwayland_satellite_ref"
        return
    fi

    have curl || die "curl is required to resolve the latest xwayland-satellite release"
    have jq || die "jq is required to resolve the latest xwayland-satellite release"

    xwayland_satellite_ref="$(
        curl -fsSL "https://api.github.com/repos/Supreeeme/xwayland-satellite/releases/latest" |
            jq -r '.tag_name // empty'
    )"

    [ -n "$xwayland_satellite_ref" ] || die "could not resolve latest xwayland-satellite release tag"
    printf '%s\n' "$xwayland_satellite_ref"
}

prepare_source() {
    local ref="$1"

    if [ -d "$source_dir/.git" ]; then
        log "update existing xwayland-satellite source checkout"
        git -C "$source_dir" fetch --tags --prune origin
    elif [ -e "$source_dir" ]; then
        if [ "$force" -eq 1 ]; then
            log "remove non-git source directory: $source_dir"
            rm -rf -- "$source_dir"
            git clone "$xwayland_satellite_repo" "$source_dir"
        else
            die "$source_dir exists and is not a git checkout; pass --force to replace it"
        fi
    else
        log "clone xwayland-satellite source"
        mkdir -p -- "$(dirname -- "$source_dir")"
        git clone "$xwayland_satellite_repo" "$source_dir"
    fi

    log "checkout xwayland-satellite ref: $ref"
    git -C "$source_dir" checkout --detach "$ref"
}

build_xwayland_satellite() {
    have cargo || die "cargo is required; run ./install.sh --packages or install Rust first"

    log "build xwayland-satellite release binary"
    cargo build --release --locked --features systemd --manifest-path "$source_dir/Cargo.toml"
}

install_xwayland_satellite() {
    local binary="$source_dir/target/release/xwayland-satellite"
    [ -x "$binary" ] || die "built xwayland-satellite binary not found: $binary"

    log "install xwayland-satellite binary"
    sudo install -D -m 0755 "$binary" /usr/local/bin/xwayland-satellite
}

print_status() {
    log "xwayland-satellite install status"
    if have xwayland-satellite; then
        printf '  installed: %s\n' "$(command -v xwayland-satellite)"
        printf '  version: %s\n' "$(xwayland-satellite -version)"
    fi

    if [ -d "$source_dir/.git" ]; then
        printf '  ref: %s\n' "$(git -C "$source_dir" describe --tags --always --dirty)"
    fi

    printf '  source: %s\n' "$source_dir"
    printf '  binary: /usr/local/bin/xwayland-satellite\n'
    printf '  niri: restart the niri session to enable automatic X11 integration\n'
}

if [ "$skip_deps" -eq 0 ]; then
    install_dependencies
fi

ref="$(resolve_ref)"
prepare_source "$ref"
build_xwayland_satellite

if [ "$build_only" -eq 0 ]; then
    install_xwayland_satellite
fi

print_status
