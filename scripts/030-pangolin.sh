#!/bin/bash
# Install the Pangolin first-boot tooling. Pangolin itself is NOT installed
# here: the latest installer is fetched when an instance is configured, so the
# AMI does not pin a Pangolin version. The edition (community or enterprise)
# is chosen per instance through PANGOLIN_EDITION, not baked into the AMI.
set -euo pipefail

: "${AMI_VERSION:?AMI_VERSION must be set}"

# Files uploaded by Packer to /tmp/pangolin-ami-files mirror the target paths.
cp -a /tmp/pangolin-ami-files/. /
rm -rf /tmp/pangolin-ami-files

chown -R root:root /usr/local/sbin/pangolin-setup /etc/pangolin /etc/systemd/system/pangolin-firstboot.service \
    /etc/profile.d/pangolin-setup.sh /etc/update-motd.d/99-pangolin /etc/docker/daemon.json \
    /etc/ssh/sshd_config.d/60-pangolin.conf /etc/fail2ban/jail.local
chmod 0755 /usr/local/sbin/pangolin-setup /etc/update-motd.d/99-pangolin
chmod 0644 /etc/systemd/system/pangolin-firstboot.service /etc/profile.d/pangolin-setup.sh \
    /etc/docker/daemon.json /etc/ssh/sshd_config.d/60-pangolin.conf /etc/fail2ban/jail.local
chmod 0755 /etc/pangolin

cat >/etc/pangolin/ami.env <<EOM
# Baked into the AMI at build time. Do not edit.
PANGOLIN_AMI_VERSION=${AMI_VERSION}
PANGOLIN_AMI_BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOM
chmod 0644 /etc/pangolin/ami.env

mkdir -p /opt/pangolin /var/lib/pangolin-ami
chmod 0755 /opt/pangolin /var/lib/pangolin-ami

# Quieter login banner so the Pangolin status is visible.
chmod -x /etc/update-motd.d/10-help-text /etc/update-motd.d/50-motd-news 2>/dev/null || true

systemctl daemon-reload
systemctl enable pangolin-firstboot.service
systemctl restart docker

bash -n /usr/local/sbin/pangolin-setup
/usr/local/sbin/pangolin-setup --help >/dev/null
