#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

bash -n \
    "$repo_dir/install.sh" \
    "$repo_dir/sync.sh" \
    "$repo_dir/check.sh" \
    "$repo_dir/scripts/install-external.sh" \
    "$repo_dir/scripts/install-niri-source.sh"

python3 -m py_compile \
    "$repo_dir/home/.local/bin/niri-shortcuts-grid" \
    "$repo_dir/home/.local/bin/window-opacity"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck_files=(
        "$repo_dir/install.sh"
        "$repo_dir/sync.sh"
        "$repo_dir/check.sh"
        "$repo_dir/scripts/install-external.sh"
        "$repo_dir/scripts/install-niri-source.sh"
        "$repo_dir/home/.local/bin/niri-overview-wallpaper"
        "$repo_dir/home/.local/bin/niri-settings-menu"
        "$repo_dir/home/.local/bin/wallpaper-random"
        "$repo_dir/home/.local/bin/ghostty"
    )
    existing_shellcheck_files=()
    for file in "${shellcheck_files[@]}"; do
        if [ -e "$file" ] || [ -L "$file" ]; then
            existing_shellcheck_files+=("$file")
        fi
    done
    if [ "${#existing_shellcheck_files[@]}" -gt 0 ]; then
        shellcheck "${existing_shellcheck_files[@]}"
    fi
fi

if command -v niri >/dev/null 2>&1; then
    niri validate -c "$repo_dir/home/.config/niri/config.kdl"
fi

if command -v fuzzel >/dev/null 2>&1; then
    fuzzel --check-config --config="$repo_dir/home/.config/fuzzel/fuzzel.ini"
fi

if command -v desktop-file-validate >/dev/null 2>&1; then
    desktop-file-validate "$repo_dir/home/.local/share/applications/google-chrome.desktop"
fi

python3 -m json.tool "$repo_dir/home/.config/waybar/config-common" >/dev/null
python3 -m json.tool "$repo_dir/home/.config/waybar/config-common-tiling" >/dev/null
python3 -m json.tool "$repo_dir/home/.config/waybar/config-niri" >/dev/null

required_repo_files=(
    "$repo_dir/home/.local/bin/niri-overview-wallpaper"
    "$repo_dir/home/.local/bin/niri-settings-menu"
    "$repo_dir/home/.local/bin/niri-shortcuts-grid"
    "$repo_dir/home/.local/bin/wallpaper-random"
    "$repo_dir/home/.local/bin/window-opacity"
    "$repo_dir/home/.local/share/applications/google-chrome.desktop"
    "$repo_dir/home/.local/share/wallpapers/default.png"
    "$repo_dir/home/.local/share/wallpapers/niri-overview.png"
)
for file in "${required_repo_files[@]}"; do
    if [ ! -e "$file" ] && [ ! -L "$file" ]; then
        printf 'Required tracked install source is missing: %s\n' "$file" >&2
        exit 1
    fi
done

if grep -nE '^export (HTTP|HTTPS|ALL|http|https|all)_PROXY=' "$repo_dir/home/.bashrc"; then
    printf 'Machine-local proxy exports should not be tracked in home/.bashrc.\n' >&2
    exit 1
fi

secret_pattern='password|passwd|token|secret|api[_-]?key|authorization|cookie|BEGIN .*KEY'
if command -v rg >/dev/null 2>&1; then
    secret_hits="$(rg -n "$secret_pattern" "$repo_dir/home" "$repo_dir/system" || true)"
else
    secret_hits="$(grep -RInE \
        --exclude='*.png' \
        --exclude='*.jpg' \
        --exclude='*.jpeg' \
        --exclude='*.webp' \
        --exclude='*.gif' \
        "$secret_pattern" "$repo_dir/home" "$repo_dir/system" || true)"
fi
if [ -n "$secret_hits" ]; then
    printf '%s\n' "$secret_hits"
    printf 'Potential secret-like text found; review before pushing.\n' >&2
    exit 1
fi

printf 'Dotfiles checks passed.\n'
