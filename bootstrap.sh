#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export PATH="$HOME/.local/bin:$PATH"

dry_run=0
skip_packages=0
skip_external=0
skip_niri_source=0
skip_system=0
skip_check=0
with_doom=1
profile="${DOTFILES_PROFILE:-auto}"
detected_base="unknown"
niri_ref="${NIRI_REF:-}"
sudo_ready=0
ran_steps=0

usage() {
    cat <<'EOF'
Usage: ./bootstrap.sh [options]

One-click bootstrap for the niri desktop dotfiles. The script detects the
current Ubuntu environment and installed tools, then only runs missing phases.

Options:
  --dry-run           Print the detected plan without changing the system.
  --profile NAME      Install profile: auto, desktop, or minimal.
                      auto uses desktop when ubuntu-desktop is installed.
  --with-doom         Run Doom Emacs install after the desktop is configured.
  --skip-doom         Do not install or sync Doom Emacs packages/env.
  --niri-ref REF      Build a specific niri ref, such as v26.04 or a commit.
  --skip-packages     Do not install apt packages or base tool shims.
  --skip-external     Do not install Chrome/Yazi/swww/fonts/wallpapers.
  --skip-niri-source  Do not build or install niri from source.
  --skip-system       Do not install profile-specific system templates.
  --skip-check        Do not run ./check.sh at the end.
  -h, --help          Show this help.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)
            dry_run=1
            ;;
        --profile)
            [ "$#" -ge 2 ] || {
                printf 'missing value for --profile\n' >&2
                exit 2
            }
            profile="$2"
            shift
            ;;
        --with-doom)
            with_doom=1
            ;;
        --skip-doom)
            with_doom=0
            ;;
        --niri-ref)
            [ "$#" -ge 2 ] || {
                printf 'missing value for --niri-ref\n' >&2
                exit 2
            }
            niri_ref="$2"
            shift
            ;;
        --skip-packages)
            skip_packages=1
            ;;
        --skip-external)
            skip_external=1
            ;;
        --skip-niri-source)
            skip_niri_source=1
            ;;
        --skip-system)
            skip_system=1
            ;;
        --skip-check)
            skip_check=1
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

validate_profile_arg() {
    case "$profile" in
        auto | desktop | minimal)
            ;;
        *)
            printf 'unknown profile: %s\n' "$profile" >&2
            printf 'expected: auto, desktop, or minimal\n' >&2
            exit 2
            ;;
    esac
}

print_command() {
    printf 'DRY RUN:'
    printf ' %q' "$@"
    printf '\n'
}

run_cmd() {
    if [ "$dry_run" -eq 1 ]; then
        print_command "$@"
    else
        "$@"
    fi
}

ensure_sudo() {
    if [ "$dry_run" -eq 1 ] || [ "$sudo_ready" -eq 1 ]; then
        return
    fi

    have sudo || die "sudo is required for package and system template installation"
    if sudo -n true 2>/dev/null; then
        sudo_ready=1
        return
    fi

    sudo -v
    sudo_ready=1
}

run_step() {
    local title="$1"
    local needs_sudo="$2"
    shift 2

    ran_steps=1
    log "$title"
    if [ "$needs_sudo" -eq 1 ]; then
        ensure_sudo
    fi
    run_cmd "$@"
}

os_value() {
    local key="$1"
    local value
    value="$(awk -F= -v key="$key" '$1 == key { gsub(/^"|"$/, "", $2); print $2; exit }' /etc/os-release 2>/dev/null || true)"
    printf '%s\n' "${value:-unknown}"
}

package_installed() {
    dpkg-query -W -f='${db:Status-Abbrev}' "$1" 2>/dev/null | grep -q '^ii '
}

collect_missing_packages() {
    local file="$1"
    local package

    [ -f "$file" ] || return 0
    while IFS= read -r package; do
        if ! package_installed "$package"; then
            missing_packages+=("$package")
        fi
    done < <(grep -vE '^[[:space:]]*(#|$)' "$file")
}

package_files() {
    local kind="$1"
    local files=()
    local file

    case "$kind" in
        apt)
            files=("$repo_dir/packages/apt.txt")
            if [ "$profile" = "minimal" ]; then
                files+=("$repo_dir/packages/apt-minimal-session.txt")
            fi
            if [ "$with_doom" -eq 1 ]; then
                files+=("$repo_dir/packages/apt-doom.txt")
            fi
            ;;
        apt-no-recommends)
            files=("$repo_dir/packages/apt-no-recommends.txt")
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

npm_globals_ready() {
    local package

    have npm || return 1
    [ -f "$repo_dir/packages/npm-global.txt" ] || return 0

    while IFS= read -r package; do
        npm list -g --prefix "$HOME/.local" "$package" >/dev/null 2>&1 || return 1
    done < <(grep -vE '^[[:space:]]*(#|$)' "$repo_dir/packages/npm-global.txt")
}

video_group_ready() {
    if ! getent group video >/dev/null 2>&1; then
        return 0
    fi

    id -nG "$USER" | tr ' ' '\n' | grep -qx video
}

font_ready() {
    have fc-match &&
        fc-match -f '%{family}\n' 'Symbols Nerd Font Mono' | grep -qx 'Symbols Nerd Font Mono'
}

neovim_lazy_ready() {
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    [ -f "$data_home/nvim/lazy/lazy.nvim/lua/lazy/init.lua" ]
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

neovim_plugin_ready() {
    local dir="$1"

    [ -d "$dir/.git" ] || return 1
    git -C "$dir" rev-parse --verify HEAD >/dev/null 2>&1 || return 1
    git -C "$dir" status --short >/dev/null 2>&1 || return 1
}

neovim_plugins_ready() {
    local data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
    local plugin
    local dir

    neovim_lazy_ready || return 1

    while IFS= read -r plugin; do
        [ -n "$plugin" ] || continue
        [ "$plugin" != "lazy.nvim" ] || continue

        dir="$data_home/nvim/lazy/$plugin"
        neovim_plugin_ready "$dir" || return 1
    done < <(neovim_locked_plugins)
}

doom_ready() {
    local doom_dir="$HOME/.config/doom"
    local doom_src="$repo_dir/home/.config/doom"
    local emacs_dir="$HOME/.config/emacs"
    local profile="$emacs_dir/.local/cache/profiles.@.el"
    local stamp="$emacs_dir/.local/state/dotfiles-doom.sha256"

    [ -x "$emacs_dir/bin/doom" ] || return 1
    [ -f "$emacs_dir/.local/env" ] || return 1
    [ -f "$profile" ] || return 1
    [ -L "$doom_dir" ] && [ "$(readlink -- "$doom_dir")" = "$doom_src" ] || return 1
    [ -f "$stamp" ] || return 1
    [ "$(doom_config_fingerprint)" = "$(cat "$stamp")" ]
}

doom_config_fingerprint() {
    local doom_src="$repo_dir/home/.config/doom"
    local file
    local files=(
        "$doom_src/init.el"
        "$doom_src/packages.el"
    )

    for file in "${files[@]}"; do
        [ -f "$file" ] || continue
        sha256sum "$file"
    done | sha256sum | awk '{print $1}'
}

external_tools_ready() {
    have google-chrome-stable &&
        have yazi &&
        have swww &&
        have swww-daemon &&
        font_ready &&
        [ -d "$HOME/Pictures/Wallpapers/catppuccin-wallpapers/.git" ]
}

user_config_ready() {
    local rel
    local src
    local dst
    local tracked_items=(
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
        tracked_items+=(
            .config/environment.d
            .config/mimeapps.list
            .local/share/applications/google-chrome.desktop
        )
    fi

    for rel in "${tracked_items[@]}"; do
        src="$repo_dir/home/$rel"
        dst="$HOME/$rel"
        [ -e "$src" ] || [ -L "$src" ] || continue
        [ -L "$dst" ] && [ "$(readlink -- "$dst")" = "$src" ] || return 1
    done

    for src in "$repo_dir"/home/.local/bin/*; do
        [ -e "$src" ] || continue
        rel=".local/bin/$(basename -- "$src")"
        dst="$HOME/$rel"
        [ -L "$dst" ] && [ "$(readlink -- "$dst")" = "$src" ] || return 1
    done
}

system_templates_ready() {
    [ -x /usr/local/bin/niri ] || return 1
    [ -x /usr/local/bin/niri-session ] || return 1
    [ -f /usr/share/wayland-sessions/niri.desktop ] || return 1

    cmp -s "$repo_dir/system/usr/local/bin/niri-session" /usr/local/bin/niri-session || return 1
    cmp -s "$repo_dir/system/usr/share/wayland-sessions/niri.desktop" /usr/share/wayland-sessions/niri.desktop || return 1

    if [ "$profile" = "desktop" ]; then
        gdm_default_session_ready
        return
    fi

    [ -f /etc/greetd/config.toml ] || return 1
    cmp -s "$repo_dir/system/etc/greetd/config.toml" /etc/greetd/config.toml || return 1

    [ -r /etc/X11/default-display-manager ] || return 1
    grep -qx '/usr/sbin/greetd' /etc/X11/default-display-manager
}

gdm_default_session_ready() {
    local file="/var/lib/AccountsService/users/$USER"

    if [ -r "$file" ]; then
        grep -qx 'Session=niri' "$file"
        return
    fi

    have sudo || return 1
    sudo -n grep -qx 'Session=niri' "$file" 2>/dev/null
}

resolve_profile() {
    if [ "$profile" = "auto" ]; then
        if [ "$detected_base" = "desktop" ]; then
            profile="desktop"
        else
            profile="minimal"
        fi
    fi

    log "install profile: $profile"
    if [ "$profile" = "desktop" ]; then
        printf '  system: keep the existing display manager and only add the niri session entry\n'
        printf '  system: set the current user default GDM session to niri\n'
        printf '  user: skip global environment.d, mimeapps, and Chrome default-browser overrides\n'
    else
        printf '  system: install greetd templates and switch the default display manager to greetd\n'
        printf '  user: link the full user configuration set\n'
    fi
}

print_environment_summary() {
    local os_id
    local os_version
    local arch
    local base
    local session

    os_id="$(os_value ID)"
    os_version="$(os_value VERSION_ID)"
    arch="$(uname -m)"
    base="unknown"
    session="${XDG_CURRENT_DESKTOP:-unknown}/${XDG_SESSION_TYPE:-unknown}"

    if package_installed ubuntu-desktop || package_installed ubuntu-desktop-minimal || package_installed gdm3 || package_installed gdm; then
        base="desktop"
    elif package_installed ubuntu-server; then
        base="server"
    fi

    log "detected environment"
    printf '  os: %s %s\n' "$os_id" "$os_version"
    printf '  arch: %s\n' "$arch"
    printf '  base: %s\n' "$base"
    printf '  session: %s\n' "$session"
    detected_base="$base"

    if [ "$os_id" != "ubuntu" ]; then
        warn "this bootstrap is tuned for Ubuntu; continuing because most checks are tool-based"
    fi
    if [ "$arch" != "x86_64" ]; then
        warn "some external installers currently only support x86_64"
    fi
}

if [ "$(id -u)" -eq 0 ]; then
    die "run this script as the target desktop user, not as root"
fi

have apt || die "apt is required; this bootstrap currently targets Ubuntu/Debian-style systems"
have dpkg-query || die "dpkg-query is required to detect installed packages"

validate_profile_arg
print_environment_summary
resolve_profile

missing_packages=()
while IFS= read -r package_file; do
    collect_missing_packages "$package_file"
done < <(package_files apt)
while IFS= read -r package_file; do
    collect_missing_packages "$package_file"
done < <(package_files apt-no-recommends)

need_packages=0
if [ "${#missing_packages[@]}" -gt 0 ] || ! have rust-analyzer || ! video_group_ready; then
    need_packages=1
fi
if [ "$with_doom" -eq 1 ] && ! npm_globals_ready; then
    need_packages=1
fi

package_args=(--profile "$profile")
if [ "$with_doom" -eq 0 ]; then
    package_args+=(--skip-doom-packages)
fi

if [ "$skip_packages" -eq 0 ] && [ "$need_packages" -eq 1 ]; then
    if [ "${#missing_packages[@]}" -gt 0 ]; then
        printf '  missing apt packages: %s\n' "${missing_packages[*]}"
    fi
    run_step "install base packages and tool shims" 1 "$repo_dir/install.sh" "${package_args[@]}" --packages
elif [ "$skip_packages" -eq 1 ]; then
    warn "skipping package installation by request"
else
    log "base packages and tool shims already look installed"
fi

if [ "$skip_packages" -eq 0 ] && [ "$need_packages" -eq 0 ] && ! have xwayland-satellite; then
    run_step "install xwayland-satellite" 1 "$repo_dir/install.sh" --xwayland-satellite
fi

if [ "$skip_external" -eq 0 ] && ! external_tools_ready; then
    run_step "install external desktop tools" 1 "$repo_dir/install.sh" --profile "$profile" --external
elif [ "$skip_external" -eq 1 ]; then
    warn "skipping external tools by request"
else
    log "external desktop tools already look installed"
fi

if [ "$skip_niri_source" -eq 0 ]; then
    if [ -n "$niri_ref" ] || [ ! -x /usr/local/bin/niri ]; then
        niri_args=(--niri-source)
        if [ -n "$niri_ref" ]; then
            niri_args+=(--ref "$niri_ref")
        fi
        run_step "build and install niri from source" 1 "$repo_dir/install.sh" "${niri_args[@]}"
    else
        log "niri already installed at /usr/local/bin/niri"
    fi
else
    warn "skipping niri source build by request"
fi

if [ "$skip_system" -eq 0 ]; then
    if system_templates_ready && user_config_ready; then
        log "user config and system templates already look installed"
    elif [ -x /usr/local/bin/niri ] || [ "$dry_run" -eq 1 ]; then
        if [ "$profile" = "desktop" ]; then
            run_step "install user config and niri session entry" 1 "$repo_dir/install.sh" --profile "$profile" --system
        else
            run_step "install user config and greetd/niri system templates" 1 "$repo_dir/install.sh" --profile "$profile" --system
        fi
    else
        warn "niri is not installed; skipping system templates to avoid a broken login session"
        if ! user_config_ready; then
            run_step "install user config only" 0 "$repo_dir/install.sh" --profile "$profile"
        fi
    fi
else
    warn "skipping system templates by request"
    if ! user_config_ready; then
        run_step "install user config only" 0 "$repo_dir/install.sh" --profile "$profile"
    fi
fi

if have nvim; then
    if neovim_plugins_ready; then
        log "Neovim plugins already look installed"
    else
        run_step "install Neovim config and plugins" 0 "$repo_dir/install.sh" --profile "$profile" --nvim
    fi
else
    warn "skipping Neovim plugin restore; nvim is not installed"
fi

if [ "$with_doom" -eq 1 ]; then
    if doom_ready; then
        log "Doom Emacs packages and env already look installed"
    else
        run_step "install Doom Emacs packages and env" 0 "$repo_dir/install.sh" --profile "$profile" --doom
    fi
else
    warn "skipping Doom Emacs package/env sync by request; run ./install.sh --profile $profile --doom before starting Emacs"
fi

if [ "$skip_check" -eq 0 ]; then
    run_step "validate dotfiles" 0 "$repo_dir/check.sh"
fi

if [ "$ran_steps" -eq 0 ]; then
    log "nothing to do"
fi

log "bootstrap complete"
if [ "$profile" = "desktop" ]; then
    printf 'Log out after first install and choose the Niri session from the existing display manager.\n'
else
    printf 'Restart the session after first install so greetd, niri, portals, groups, and XWayland integration reload cleanly.\n'
fi
