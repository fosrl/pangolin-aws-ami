#!/bin/bash
# Patch the base image and install the packages the AMI needs.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get -qqy update
apt-get -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' full-upgrade
apt-get -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install \
    ca-certificates curl gnupg jq dnsutils fail2ban python3-systemd unattended-upgrades
