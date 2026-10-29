#!/usr/bin/env bash
# Launch a Pangolin instance with the AWS CLI and print the setup token when
# it is ready.
#
#   EDITION=community ARCH=arm64 BASE_DOMAIN=example.com EMAIL=admin@example.com \
#   SUBNET_ID=subnet-... SECURITY_GROUP_ID=sg-... KEY_NAME=my-key ./launch.sh
#
# The security group must allow TCP 80, 443 and UDP 51820, 21820 (and 22 for SSH).
set -euo pipefail

: "${BASE_DOMAIN:?}" "${EMAIL:?}" "${SUBNET_ID:?}" "${SECURITY_GROUP_ID:?}"
EDITION=${EDITION:-community}
ARCH=${ARCH:-arm64}
AMI_OWNER=${AMI_OWNER:-self}
DASHBOARD_DOMAIN=${DASHBOARD_DOMAIN:-pangolin.$BASE_DOMAIN}
if [[ $ARCH == arm64 ]]; then INSTANCE_TYPE=${INSTANCE_TYPE:-t4g.small}; else INSTANCE_TYPE=${INSTANCE_TYPE:-t3.small}; fi

AMI_ID=$(aws ec2 describe-images --owners "$AMI_OWNER" \
    --filters "Name=name,Values=pangolin-ubuntu-*-${ARCH}-*" "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text)
echo "AMI: $AMI_ID"

USER_DATA=$(printf 'PANGOLIN_EDITION=%s\nPANGOLIN_BASE_DOMAIN=%s\nPANGOLIN_DASHBOARD_DOMAIN=%s\nPANGOLIN_EMAIL=%s\n' \
    "$EDITION" "$BASE_DOMAIN" "$DASHBOARD_DOMAIN" "$EMAIL")

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
    --subnet-id "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" \
    ${KEY_NAME:+--key-name "$KEY_NAME"} \
    --user-data "$USER_DATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=pangolin}]" \
    --query 'Instances[0].InstanceId' --output text)
echo "Instance: $INSTANCE_ID"

aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
ALLOCATION_ID=$(aws ec2 allocate-address --domain vpc --query AllocationId --output text)
aws ec2 associate-address --instance-id "$INSTANCE_ID" --allocation-id "$ALLOCATION_ID" >/dev/null
PUBLIC_IP=$(aws ec2 describe-addresses --allocation-ids "$ALLOCATION_ID" --query 'Addresses[0].PublicIp' --output text)

cat <<MSG

Create these DNS records now:
  A  ${DASHBOARD_DOMAIN}  ->  ${PUBLIC_IP}
  A  *.${BASE_DOMAIN}  ->  ${PUBLIC_IP}

The instance installs Pangolin once ${DASHBOARD_DOMAIN} resolves to ${PUBLIC_IP}.
Waiting for the setup token (Ctrl+C to stop; re-run the command below later)...
  aws ec2 get-console-output --instance-id ${INSTANCE_ID} --latest --output text | grep 'Setup token'
MSG

while true; do
    TOKEN=$(aws ec2 get-console-output --instance-id "$INSTANCE_ID" --latest --output text 2>/dev/null |
        sed -n 's/.*Setup token:[[:space:]]*\([^[:space:]<]\{1,\}\).*/\1/p' | tail -n1 || true)
    if [[ -n $TOKEN ]]; then
        echo
        echo "Setup token: $TOKEN"
        echo "Finish setup at: https://${DASHBOARD_DOMAIN}/auth/initial-setup"
        break
    fi
    sleep 30
done
