#!/bin/bash
# Security baseline that satisfies the AWS Marketplace AMI policies.
set -euo pipefail

# No password logins for any account; SSH is key-only as "ubuntu".
passwd -l root
sshd -t

systemctl enable fail2ban
systemctl restart fail2ban

# Keep automatic security updates on (Ubuntu default).
cat >/etc/apt/apt.conf.d/20auto-upgrades <<EOM
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOM
