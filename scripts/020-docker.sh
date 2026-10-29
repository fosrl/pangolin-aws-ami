#!/bin/bash
# Install Docker Engine and the compose plugin from Docker's repository.
set -euo pipefail

curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
sh /tmp/get-docker.sh
rm -f /tmp/get-docker.sh

systemctl enable docker containerd
docker compose version
