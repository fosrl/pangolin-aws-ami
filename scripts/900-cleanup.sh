#!/bin/bash
# Remove build-time state, credentials and logs before the AMI is captured.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get -qqy autoremove --purge
apt-get -qqy clean
rm -rf /var/lib/apt/lists/*

# Pangolin per-instance state must start empty.
rm -f /etc/pangolin/setup.env
rm -rf /var/lib/pangolin-ami/* /opt/pangolin/*
rm -f /var/log/pangolin-setup.log

# cloud-init runs again on every new instance (user-data, SSH keys, host keys).
cloud-init clean --logs --seed

# SSH keys: the temporary Packer key and any host keys (regenerated on boot).
rm -f /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys
rm -f /etc/ssh/ssh_host_*

# Unique identity per instance.
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id

# Logs and history.
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
find /var/log -type f \( -name '*.gz' -o -name '*.[0-9]' -o -name '*.old' \) -delete
find /var/log -type f -exec truncate -s 0 {} +
rm -f /root/.bash_history /home/*/.bash_history
rm -rf /tmp/* /var/tmp/*

sync
