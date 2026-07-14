#!/bin/bash
# Recreate the nvidia-persistenced system user and start the daemon.
# Needed after a driver reinstall/update drops the user, which makes
# nvidia-persistenced.service fail and leaves persistence mode Off.
set -e

if ! getent passwd nvidia-persistenced >/dev/null; then
    adduser --system --group \
            --home /var/run/nvidia-persistenced/ \
            --gecos 'NVIDIA Persistence Daemon' \
            --no-create-home \
            nvidia-persistenced
fi

systemctl enable --now nvidia-persistenced.service
nvidia-smi --query-gpu=index,name,persistence_mode --format=csv
