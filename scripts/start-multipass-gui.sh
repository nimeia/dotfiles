#!/usr/bin/env bash
set -euo pipefail

vm_name="dotfiles-u2604"
memory_mb="4096"
cpus="2"
mac_address="52:54:00:e0:e2:69"
ssh_port="2222"
display_backend="gtk"
use_direct_disk=0
keep_overlay=0
autologin=0
restore_greetd=0

usage() {
    cat <<'EOF'
Usage: scripts/start-multipass-gui.sh [options]

Start a stopped Multipass VM disk with a normal QEMU GUI window.

Options:
  --vm NAME           Multipass instance name. Default: dotfiles-u2604
  --memory MB         QEMU memory size. Default: 4096
  --cpus N            QEMU CPU count. Default: 2
  --mac ADDRESS       Guest NIC MAC. Default matches dotfiles-u2604 netplan.
  --ssh-port PORT     Host port forwarded to guest port 22. Default: 2222
  --display BACKEND   QEMU display backend. Default: gtk
  --direct            Write directly to the Multipass disk. Not recommended.
  --keep-overlay      Keep the temporary overlay after QEMU exits.
  --autologin         Before GUI boot, enable temporary greetd autologin for ubuntu.
  --restore-greetd    Restore /etc/greetd/config.toml from the autologin backup.
  -h, --help          Show this help.

Examples:
  scripts/start-multipass-gui.sh --autologin
  scripts/start-multipass-gui.sh --keep-overlay
  scripts/start-multipass-gui.sh --restore-greetd
EOF
}

log() {
    printf '==> %s\n' "$*"
}

warn() {
    printf 'warning: %s\n' "$*" >&2
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --vm)
            vm_name="${2:?missing value for --vm}"
            shift 2
            ;;
        --memory)
            memory_mb="${2:?missing value for --memory}"
            shift 2
            ;;
        --cpus)
            cpus="${2:?missing value for --cpus}"
            shift 2
            ;;
        --mac)
            mac_address="${2:?missing value for --mac}"
            shift 2
            ;;
        --ssh-port)
            ssh_port="${2:?missing value for --ssh-port}"
            shift 2
            ;;
        --display)
            display_backend="${2:?missing value for --display}"
            shift 2
            ;;
        --direct)
            use_direct_disk=1
            shift
            ;;
        --keep-overlay)
            keep_overlay=1
            shift
            ;;
        --autologin)
            autologin=1
            shift
            ;;
        --restore-greetd)
            restore_greetd=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown option: $1"
            ;;
    esac
done

[ "$(id -u)" -ne 0 ] || die "run this script as your normal desktop user, not root"
command -v multipass >/dev/null 2>&1 || die "multipass is not installed"
command -v qemu-system-x86_64 >/dev/null 2>&1 || die "qemu-system-x86_64 is not installed"
command -v qemu-img >/dev/null 2>&1 || die "qemu-img is not installed"
command -v setfacl >/dev/null 2>&1 || die "setfacl is not installed"

if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    die "no DISPLAY or WAYLAND_DISPLAY found; run this from a graphical terminal"
fi

instance_dir="/var/snap/multipass/common/data/multipassd/vault/instances/$vm_name"
base_image="$(sudo find "$instance_dir" -maxdepth 1 -type f -name '*.img' | head -n 1)"
[ -n "$base_image" ] || die "cannot find Multipass disk image under $instance_dir"

cloud_init_iso=""
if sudo test -f "$instance_dir/cloud-init-config.iso"; then
    cloud_init_iso="$instance_dir/cloud-init-config.iso"
fi

ovmf=""
for candidate in /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF_CODE_4M.fd /snap/multipass/current/bin/OVMF.fd; do
    if [ -f "$candidate" ]; then
        ovmf="$candidate"
        break
    fi
done
[ -n "$ovmf" ] || die "cannot find OVMF firmware"

grant_read_access() {
    local path="$1"
    local dir
    local current
    local parts=()

    dir="$(dirname "$path")"
    current="$dir"
    while [ "$current" != "/" ]; do
        parts=("$current" "${parts[@]}")
        current="$(dirname "$current")"
    done

    for current in "${parts[@]}"; do
        sudo setfacl -m "u:$USER:x" "$current" >/dev/null
    done
    sudo setfacl -m "u:$USER:r" "$path" >/dev/null
}

vm_state() {
    multipass info "$vm_name" | awk -F: '/^State:/ {gsub(/^[ \t]+/, "", $2); print $2}'
}

ensure_stopped() {
    local state
    state="$(vm_state)"
    if [ "$state" = "Stopped" ]; then
        return
    fi

    log "stopping Multipass VM $vm_name"
    multipass stop "$vm_name"
    state="$(vm_state)"
    [ "$state" = "Stopped" ] || die "$vm_name is $state, expected Stopped"
}

enable_autologin() {
    log "enabling temporary greetd autologin for ubuntu"
    multipass start "$vm_name"
    multipass exec "$vm_name" -- bash -lc '
set -euo pipefail
if [ -f /etc/greetd/config.toml ] && [ ! -f /etc/greetd/config.toml.multipass-gui.bak ]; then
    sudo cp /etc/greetd/config.toml /etc/greetd/config.toml.multipass-gui.bak
fi
sudo tee /etc/greetd/config.toml >/dev/null <<'"'"'EOF'"'"'
[terminal]
vt = 7

[initial_session]
command = "/usr/local/bin/niri-session"
user = "ubuntu"

[default_session]
command = "/usr/bin/tuigreet --time --remember --remember-session --sessions /usr/share/wayland-sessions --cmd /usr/local/bin/niri-session"
user = "_greetd"
EOF
'
    multipass stop "$vm_name"
}

restore_greetd_config() {
    log "restoring greetd config from /etc/greetd/config.toml.multipass-gui.bak"
    multipass start "$vm_name"
    multipass exec "$vm_name" -- bash -lc '
set -euo pipefail
if [ ! -f /etc/greetd/config.toml.multipass-gui.bak ]; then
    echo "no backup found: /etc/greetd/config.toml.multipass-gui.bak" >&2
    exit 1
fi
sudo cp /etc/greetd/config.toml.multipass-gui.bak /etc/greetd/config.toml
sudo rm -f /etc/greetd/config.toml.multipass-gui.bak
'
    multipass stop "$vm_name"
}

if [ "$restore_greetd" -eq 1 ]; then
    restore_greetd_config
    log "greetd config restored"
    exit 0
fi

if [ "$autologin" -eq 1 ]; then
    enable_autologin
fi

ensure_stopped
grant_read_access "$base_image"
if [ -n "$cloud_init_iso" ]; then
    grant_read_access "$cloud_init_iso"
fi

disk="$base_image"
overlay=""
cleanup_overlay() {
    if [ -n "$overlay" ] && [ "$keep_overlay" -eq 0 ] && [ -f "$overlay" ]; then
        rm -f "$overlay"
    fi
}
trap cleanup_overlay EXIT

if [ "$use_direct_disk" -eq 0 ]; then
    overlay="$(mktemp "${TMPDIR:-/tmp}/${vm_name}-gui-overlay.XXXXXX.qcow2")"
    rm -f "$overlay"
    log "creating temporary overlay $overlay"
    qemu-img create -f qcow2 -F qcow2 -b "$base_image" "$overlay" >/dev/null
    disk="$overlay"
else
    warn "direct disk mode is enabled; QEMU will write to the Multipass disk"
fi

if command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$ssh_port" >/dev/null 2>&1; then
    die "host SSH forward port $ssh_port is already in use; choose another with --ssh-port"
fi

log "starting QEMU GUI for $vm_name"
log "close the QEMU window to stop the GUI VM"
if [ "$use_direct_disk" -eq 0 ] && [ "$keep_overlay" -eq 0 ]; then
    log "temporary overlay will be removed after QEMU exits"
fi

qemu_args=(
    -name "$vm_name-gui"
    -machine "type=q35,accel=kvm"
    -cpu host
    -smp "$cpus"
    -m "$memory_mb"
    -bios "$ovmf"
    -device virtio-vga
    -display "$display_backend"
    -device virtio-scsi-pci,id=scsi0
    -drive "file=$disk,if=none,format=qcow2,discard=unmap,id=hda"
    -device scsi-hd,drive=hda,bus=scsi0.0
    -nic "user,model=virtio-net-pci,mac=$mac_address,hostfwd=tcp:127.0.0.1:$ssh_port-:22"
    -device qemu-xhci,id=xhci
    -device usb-tablet,bus=xhci.0
    -serial null
)

if [ -n "$cloud_init_iso" ]; then
    qemu_args+=(-cdrom "$cloud_init_iso")
fi

qemu-system-x86_64 "${qemu_args[@]}"
