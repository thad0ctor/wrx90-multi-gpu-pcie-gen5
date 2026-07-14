#!/bin/bash
# Install the multi-GPU / PCIe Gen5 configuration onto an AMD WRX90 system.
# Read README.md first. Run from inside this directory:  sudo ./apply.sh
#
# This will:
#   - install a custom GRUB entry (filling in your root UUID + kernel version)
#   - install the boot-time PCIe Gen5 retrain service + script
#   - install the NVIDIA modprobe options and nouveau blacklist
#   - (re)create the nvidia-persistenced user and start the daemon
#   - run update-grub
#
# IMPORTANT: edit BRIDGES in usr/local/bin/pcie-gen5-fix.sh for your board first
# (see comments in that file). The GRUB flags are platform-general; the bridge IDs are not.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ "$(id -u)" -ne 0 ]; then
    echo "Run with sudo: sudo ./apply.sh" >&2
    exit 1
fi

ROOT_UUID="$(findmnt -no UUID /)"
KVER="$(uname -r)"
echo "Detected root UUID: $ROOT_UUID"
echo "Detected kernel:    $KVER"
echo

echo "==> Installing GRUB custom entry (multigpu-pcie)"
sed -e "s/__ROOT_UUID__/$ROOT_UUID/g" -e "s/__KERNEL_VERSION__/$KVER/g" \
    "$HERE"/etc/grub.d/09_multigpu-pcie > /etc/grub.d/09_multigpu-pcie
chmod 0755 /etc/grub.d/09_multigpu-pcie

echo "==> Installing PCIe Gen5 force service + script"
install -m 0755 "$HERE"/usr/local/bin/pcie-gen5-fix.sh /usr/local/bin/pcie-gen5-fix.sh
install -m 0644 "$HERE"/etc/systemd/system/pcie-gen5-fix.service /etc/systemd/system/pcie-gen5-fix.service

echo "==> Installing NVIDIA modprobe configs"
install -m 0644 "$HERE"/etc/modprobe.d/nvidia-drm.conf        /etc/modprobe.d/nvidia-drm.conf
install -m 0644 "$HERE"/etc/modprobe.d/nvidia-profiler.conf   /etc/modprobe.d/nvidia-profiler.conf
install -m 0644 "$HERE"/etc/modprobe.d/blacklist-nouveau.conf /etc/modprobe.d/blacklist-nouveau.conf

echo "==> nvidia-persistenced user + daemon"
install -m 0755 "$HERE"/usr/local/bin/fix-nvidia-persistenced.sh /usr/local/bin/fix-nvidia-persistenced.sh
/usr/local/bin/fix-nvidia-persistenced.sh || true

echo "==> Enabling services"
systemctl daemon-reload
systemctl enable pcie-gen5-fix.service

echo "==> Set 'multigpu-pcie' as default and regenerate GRUB"
if ! grep -q '^GRUB_DEFAULT="multigpu-pcie"' /etc/default/grub; then
    echo "  NOTE: to boot it by default, set  GRUB_DEFAULT=\"multigpu-pcie\"  in /etc/default/grub"
fi
update-grub

echo
echo "Done. Reboot and choose 'Ubuntu - Multi-GPU PCIe Gen5' (or set it default above)."
echo "Verify:  cat /proc/cmdline  &&  nvidia-smi"
