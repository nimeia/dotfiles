#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

bash -n \
    "$repo_dir/install.sh" \
    "$repo_dir/sync.sh" \
    "$repo_dir/check.sh" \
    "$repo_dir/scripts/install-external.sh" \
    "$repo_dir/scripts/install-niri-source.sh"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck \
        "$repo_dir/install.sh" \
        "$repo_dir/sync.sh" \
        "$repo_dir/check.sh" \
        "$repo_dir/scripts/install-external.sh" \
        "$repo_dir/scripts/install-niri-source.sh" \
        "$repo_dir/home/.local/bin/ghostty" \
        "$repo_dir/home/.local/bin/niri-settings-menu"
fi

if command -v niri >/dev/null 2>&1; then
    niri validate -c "$repo_dir/home/.config/niri/config.kdl"
fi

if command -v fuzzel >/dev/null 2>&1; then
    fuzzel --check-config --config="$repo_dir/home/.config/fuzzel/fuzzel.ini"
fi

python3 -m json.tool "$repo_dir/home/.config/waybar/config-common" >/dev/null
python3 -m json.tool "$repo_dir/home/.config/waybar/config-common-tiling" >/dev/null
python3 -m json.tool "$repo_dir/home/.config/waybar/config-niri" >/dev/null

if rg -n 'password|passwd|token|secret|api[_-]?key|authorization|cookie|BEGIN .*KEY' "$repo_dir/home" "$repo_dir/system"; then
    printf 'Potential secret-like text found; review before pushing.\n' >&2
    exit 1
fi

printf 'Dotfiles checks passed.\n'
