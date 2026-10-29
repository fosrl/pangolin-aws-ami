# Pangolin AWS AMIs

## Finding the AMI

AMI IDs are different in every region, so look up the ID in the region you launch in. The AMIs are published to all [supported regions](#supported-regions). Images are named `pangolin-<edition>-ubuntu-24.04-<arch>-<version>`, where edition is `community` or `enterprise` and arch is `amd64` or `arm64`.

**Latest AMI ID with the AWS CLI:**

```bash
PANGOLIN_OWNER=<PANGOLIN_ACCOUNT_ID>   # AWS account that publishes the Pangolin AMIs
EDITION=community                     # community | enterprise
ARCH=arm64                            # arm64 (Graviton, e.g. t4g) | amd64 (x86, e.g. t3)

aws ec2 describe-images --region us-east-1 --owners "$PANGOLIN_OWNER" \
  --filters "Name=name,Values=pangolin-${EDITION}-ubuntu-*-${ARCH}-*" "Name=state,Values=available" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' --output text
```

**All four editions and architectures with their latest IDs:**

```bash
aws ec2 describe-images --region us-east-1 --owners "$PANGOLIN_OWNER" \
  --filters 'Name=name,Values=pangolin-*' 'Name=state,Values=available' \
  --query 'reverse(sort_by(Images, &CreationDate))[].[Name, ImageId, Architecture, CreationDate]' \
  --output table
```

**In the AWS console:**

1. Switch to the region you want to launch in.
2. Open **EC2 → Images → AMIs** and change the filter from **Owned by me** to **Public images**.
3. Search for `pangolin-community` or `pangolin-enterprise`, and add the filter **Owner = `<PANGOLIN_ACCOUNT_ID>`** so you only see official images.
4. Sort by **Creation date**, pick the newest image for your architecture, and click **Launch instance from AMI**.

**From AWS Marketplace:** search for **Pangolin** in [AWS Marketplace](https://aws.amazon.com/marketplace), choose the Community or Enterprise listing, and subscribe. The listing shows the AMI ID for each region and offers the CloudFormation one-click launch.

Every AMI installs the latest Pangolin release when it is set up, so the newest AMI only matters for OS and Docker patches.

## Launching Pangolin

### Requirements

- **DNS:** an A record for the dashboard domain and a wildcard `*.<base domain>`, both pointing to the instance's public IP. Use an Elastic IP.
- **Security group:** TCP 80, 443 and UDP 51820 (sites), 21820 (clients), UDP 443 (HTTP/3, optional), and TCP 22 from your IP.
- **Instance size:** `t3.small` or `t4g.small` or larger. The Graviton (`t4g`) AMIs are the cheaper choice.

### Option A: CloudFormation (one click)

[`cloudformation/pangolin.yaml`](cloudformation/pangolin.yaml) creates the security group, instance and Elastic IP. If you give it a Route 53 hosted zone ID, it also creates both DNS records.

```bash
aws cloudformation deploy --stack-name pangolin \
  --template-file cloudformation/pangolin.yaml \
  --parameter-overrides \
    ImageId=ami-0123456789abcdef0 InstanceType=t4g.small \
    BaseDomain=example.com LetsEncryptEmail=admin@example.com \
    HostedZoneId=Z0123456789ABC KeyName=my-key \
    VpcId=vpc-... SubnetId=subnet-... SSHLocation=203.0.113.10/32

aws cloudformation describe-stacks --stack-name pangolin --query 'Stacks[0].Outputs'
```

The `SetupTokenCommand` output prints the token once installation finishes.

### Option B: EC2 API / CLI with user-data

Pass the settings as user-data. Two formats are accepted:

**Plain `KEY=VALUE` lines** (simplest; [`examples/user-data.env`](examples/user-data.env)):

```
PANGOLIN_BASE_DOMAIN=example.com
PANGOLIN_EMAIL=admin@example.com
```

**cloud-config** that writes `/etc/pangolin/setup.env` ([`examples/user-data.yaml`](examples/user-data.yaml)). Use this form to combine the settings with other cloud-init configuration.

```bash
aws ec2 run-instances --image-id ami-... --instance-type t4g.small \
  --subnet-id subnet-... --security-group-ids sg-... --key-name my-key \
  --user-data file://examples/user-data.env
```

[`examples/launch.sh`](examples/launch.sh) does the full flow: it looks up the newest AMI, launches it, attaches an Elastic IP, prints the DNS records to create, and waits for the setup token.

### Option C: SSH wizard

Launch without user-data, then SSH in:

```bash
ssh ubuntu@<public-ip>
```

On login you're offered the setup wizard (or run `sudo pangolin-setup`). It asks for the domains, email, tunneling and optional SMTP, checks DNS, and then installs. The edition is fixed by the AMI.

### Settings

| Key | Required | Default | Used for |
| --- | --- | --- | --- |
| `PANGOLIN_BASE_DOMAIN` | yes¹ | derived from the dashboard domain | `domains.domain1.base_domain` (resources are served under it) |
| `PANGOLIN_DASHBOARD_DOMAIN` | no | `pangolin.<base domain>` | `app.dashboard_url`, `gerbil.base_endpoint`, CORS origin |
| `PANGOLIN_EMAIL` | yes | — | Let's Encrypt account (alias: `PANGOLIN_LETSENCRYPT_EMAIL`) |
| `PANGOLIN_INSTALL_GERBIL` | no | `true` | WireGuard tunneling. `false` makes Pangolin a plain reverse proxy |
| `PANGOLIN_ENABLE_IPV6` | no | `true` if the instance has IPv6 | IPv6 on the Docker network |
| `PANGOLIN_ENABLE_MAXMIND` | no | `true` | GeoLite2 country/ASN databases for geo-blocking |
| `PANGOLIN_SMTP_HOST`, `_PORT`, `_USER`, `_PASS`, `_NO_REPLY` | no | port `587` | Email. Enabled when `SMTP_HOST` is set |
| `PANGOLIN_WAIT_FOR_DNS` | no | `true` | Wait for the dashboard domain to resolve before installing |
| `PANGOLIN_DNS_TIMEOUT` | no | `1800` | Seconds to wait for DNS before installing anyway |
| `PANGOLIN_INSTALLER_URL` | no | latest release | Override the installer binary (testing) |

¹ Give either `PANGOLIN_BASE_DOMAIN` or `PANGOLIN_DASHBOARD_DOMAIN`. If only the dashboard domain is given, the base domain is that domain with its first label removed (`pangolin.example.com` → `example.com`). Set the base domain explicitly if that is wrong for you.

User-data can be read by any process on the instance through IMDS. Prefer adding SMTP credentials afterwards in `/opt/pangolin/config/config.yml` over passing them in user-data.

### After launch

```bash
pangolin-setup status        # pending | needs-input | waiting-dns | installing | complete | failed
sudo pangolin-setup token    # initial admin setup token
sudo tail -f /var/log/pangolin-setup.log
```

The setup token is also written to the serial console, so you can read it without SSH:

```bash
aws ec2 get-console-output --instance-id i-... --latest --output text | grep 'Setup token'
```

Open `https://<dashboard domain>/auth/initial-setup`, paste the token, and create the admin account. On the **Enterprise** AMI, activate your license under **Server Admin → License** (`/admin/license`).

### Updating Pangolin

```bash
cd /opt/pangolin
sudo docker compose pull && sudo docker compose up -d
```

See the [update guide](https://docs.pangolin.net/self-host/how-to-update) for version-specific notes.

### Troubleshooting

- **Stuck in `waiting-dns`:** check that `dig +short pangolin.example.com @1.1.1.1` returns the instance's public IP. Setup continues anyway after `PANGOLIN_DNS_TIMEOUT`. If you're behind a load balancer, set `PANGOLIN_WAIT_FOR_DNS=false`.
- **Certificate errors:** after fixing DNS, run `cd /opt/pangolin && sudo docker compose restart traefik`.
- **`failed`:** read `/var/log/pangolin-setup.log`, fix the cause, then run `sudo pangolin-setup`. If a partial install left `/opt/pangolin/config/config.yml` behind, remove `/opt/pangolin/*` first.

Packer pipeline that builds Amazon Machine Images for [Pangolin](https://github.com/fosrl/pangolin) in two editions and two architectures:

| Build              | Edition            | Architecture      | Default instance |
| ------------------ | ------------------ | ----------------- | ---------------- |
| `community-amd64`  | Community Edition  | x86_64            | `t3.small`       |
| `community-arm64`  | Community Edition  | arm64 (Graviton)  | `t4g.small`      |
| `enterprise-amd64` | Enterprise Edition | x86_64            | `t3.small`       |
| `enterprise-arm64` | Enterprise Edition | arm64 (Graviton)  | `t4g.small`      |

**The AMIs do not pin a Pangolin version.** They contain Ubuntu 24.04, Docker and a first-boot setup tool. When an instance is configured, it downloads the latest Pangolin installer, which pulls the matching latest Pangolin, Gerbil and Traefik images. New Pangolin releases need no AMI rebuild. Rebuild only to refresh the OS and Docker layer (CI does this monthly).

### Supported regions

By default, the AMIs are published to every region that AWS enables on all accounts:

| Area | Regions |
| --- | --- |
| North America | `us-east-1` (N. Virginia, build region), `us-west-1` (N. California), `ca-central-1` (Canada Central) |
| South America | `sa-east-1` (São Paulo) |
| Europe | `eu-west-1` (Ireland), `eu-central-1` (Frankfurt), `eu-north-1` (Stockholm) |
| Asia Pacific | `ap-south-1` (Mumbai), `ap-northeast-1` (Tokyo), `ap-southeast-1` (Singapore), |

In a region that isn't published, users can copy a public AMI into their own account:

```bash
aws ec2 copy-image --source-region us-east-1 --source-image-id ami-... \
  --region af-south-1 --name pangolin-community-arm64
```

## How it works

```
 launch instance ──► cloud-init writes /etc/pangolin/setup.env (from user-data)
                          │
                          ▼
 pangolin-firstboot.service ── settings found? ──no──► state: needs-input
                          │ yes                        (SSH in → setup wizard)
                          ▼
        wait until the dashboard domain resolves to this instance
                          │
                          ▼
        download latest installer → installer --non-interactive ...
                          │
                          ▼
        stack running · setup token on the serial console + `sudo pangolin-setup token`
```

| Path on the instance | Purpose |
| --- | --- |
| `/usr/local/sbin/pangolin-setup` | Setup tool: `--auto` (first boot), interactive wizard, `status`, `token` |
| `/etc/systemd/system/pangolin-firstboot.service` | Runs `pangolin-setup --auto` on boot until `/opt/pangolin/config/config.yml` exists |
| `/etc/pangolin/ami.env` | Baked at build time: edition and AMI version. User-data cannot override the edition |
| `/etc/pangolin/setup.env` | Per-instance settings (0600), from user-data or the wizard |
| `/opt/pangolin` | Pangolin install directory (`docker compose`) |
| `/var/log/pangolin-setup.log` | Setup log |

> **Installer dependency:** the AMI runs the installer with `--non-interactive` and answer flags such as `--base-domain` and `--enterprise`. These were added in `pangolin/install` (`flags.go`). Instances will fail setup with a clear error until a Pangolin release ships an installer with these flags. To test before that, set `PANGOLIN_INSTALLER_URL` to a locally built installer binary.

---

## Building the AMIs with Packer

### Prerequisites

- [Packer](https://developer.hashicorp.com/packer/install) 1.10 or newer
- AWS credentials for the target account, as environment variables, an `AWS_PROFILE`, or SSO. The minimum permissions are in [`iam/packer-policy.json`](iam/packer-policy.json).
- A default VPC in the build region, or pass `subnet_id` (a public subnet) for the temporary build instance
- Optional: `make` and `shellcheck`

### 1. Initialize the Amazon plugin

```bash
cd pangolin-aws-ami
packer init .
```

### 2. Validate the template

```bash
packer fmt -check .
packer validate .
```

### 3. Build

All four AMIs, in parallel:

```bash
export AWS_PROFILE=pangolin-build   # or AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
export AWS_REGION=us-east-1

packer build .
```

A single AMI, or a subset (`-only` takes a comma-separated list or globs):

```bash
packer build -only='pangolin.amazon-ebs.community-amd64' .
packer build -only='pangolin.amazon-ebs.enterprise-*' .
packer build -only='pangolin.amazon-ebs.*-arm64' .
```

Or with `make`:

```bash
make validate
make build                                    # all four
make build BUILDS="community-arm64 enterprise-arm64"
```

Each build runs a temporary instance in the build region, provisions it with `scripts/`, snapshots it, terminates it, and copies the AMI to every region in `ami_regions` ([all default regions](#supported-regions)). The build itself takes about 8–12 minutes. Copying to all regions adds roughly 15–30 minutes, and the copies run in parallel. For a quick test build, skip the copies with `-var 'ami_regions=[]'`. Results are written to `manifest.json`, with one `region:ami-id` entry per region:

```bash
jq -r '.builds[] | "\(.custom_data.edition)-\(.custom_data.arch): \(.artifact_id)"' manifest.json
# community-amd64: us-east-1:ami-0123456789abcdef0
```

### Build variables

Set them with `-var`, a `*.auto.pkrvars.hcl` file (git-ignored), or `PKR_VAR_<name>` environment variables.

| Variable | Default | Description |
| --- | --- | --- |
| `region` | `us-east-1` | Region to build in |
| `ami_regions` | [all default regions](#supported-regions) | Regions the AMIs are published to. The build region is skipped automatically. Use `[]` for the build region only |
| `ami_public` | `false` | Make the AMIs public (see [Publishing](#publishing)) |
| `ami_users` | `[]` | Account IDs to share the AMIs with |
| `ami_version` | UTC timestamp | AMI version label used in names and tags (not the Pangolin version) |
| `instance_type_amd64` / `instance_type_arm64` | `t3.small` / `t4g.small` | Build instance types |
| `volume_size` | `20` | Root volume GiB. This is also the minimum for instances launched from the AMI |
| `subnet_id` | default VPC | Subnet for the build instance |
| `ubuntu_release` / `ubuntu_codename` | `24.04` / `noble` | Canonical base image |

Example `release.auto.pkrvars.hcl`:

```hcl
ami_version = "2026.10.1"
ami_public  = true
# ami_regions defaults to every supported region; override to publish to fewer:
# ami_regions = ["us-east-1", "eu-central-1"]
```

AMI names follow `pangolin-<edition>-ubuntu-<release>-<arch>-<version>`, for example `pangolin-enterprise-ubuntu-24.04-arm64-2026.10.1`.

### Debugging a build

```bash
PACKER_LOG=1 packer build -only='pangolin.amazon-ebs.community-amd64' .
packer build -on-error=ask -only='pangolin.amazon-ebs.community-amd64' .   # keep the instance for inspection
```