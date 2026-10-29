packer {
  required_plugins {
    amazon = {
      version = ">= 1.3.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "Region the AMIs are built in."
}

# Every region that is enabled by default on AWS accounts. Opt-in regions
# (e.g. ap-east-1, me-south-1, af-south-1) must be enabled in the publishing
# account before they can be added. The build region is skipped automatically.
variable "ami_regions" {
  type = list(string)
  default = [
    "us-east-1",
    "us-east-2",
    "us-west-1",
    "us-west-2",
    "ca-central-1",
    "sa-east-1",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "eu-central-1",
    "eu-north-1",
    "ap-south-1",
    "ap-northeast-1",
    "ap-northeast-2",
    "ap-northeast-3",
    "ap-southeast-1",
    "ap-southeast-2",
  ]
  description = "Regions the AMIs are published to. Set to [] to keep the AMIs in the build region only."
}

variable "ami_public" {
  type        = bool
  default     = false
  description = "Make the AMIs public. Requires block public access for AMIs to be disabled in each region."
}

variable "ami_users" {
  type        = list(string)
  default     = []
  description = "AWS account IDs to share the AMIs with (e.g. for testing before publishing)."
}

variable "ami_version" {
  type        = string
  default     = ""
  description = "Version label for the AMI build. Defaults to a UTC timestamp. This is the AMI version, not the Pangolin version."
}

variable "ubuntu_release" {
  type    = string
  default = "24.04"
}

variable "ubuntu_codename" {
  type    = string
  default = "noble"
}

variable "instance_type_amd64" {
  type    = string
  default = "t3.small"
}

variable "instance_type_arm64" {
  type    = string
  default = "t4g.small"
}

variable "volume_size" {
  type        = number
  default     = 20
  description = "Root volume size in GiB. This becomes the minimum volume size for instances launched from the AMI."
}

variable "subnet_id" {
  type        = string
  default     = null
  description = "Subnet for the build instance. Defaults to the default VPC."
}

# ---------------------------------------------------------------------------
# Locals
# ---------------------------------------------------------------------------

locals {
  version = var.ami_version != "" ? var.ami_version : formatdate("YYYYMMDDhhmm", timestamp())

  # The AMI is created in the build region; copy it everywhere else.
  copy_regions = [for r in var.ami_regions : r if r != var.region]

  editions = {
    community  = "Community Edition"
    enterprise = "Enterprise Edition"
  }

  common_tags = {
    "Application"          = "Pangolin"
    "pangolin:ami-version" = local.version
    "pangolin:os"          = "ubuntu-${var.ubuntu_release}"
    "pangolin:source-ami"  = "{{ .SourceAMI }}"
    "pangolin:source-name" = "{{ .SourceAMIName }}"
  }
}

# ---------------------------------------------------------------------------
# Sources (one per architecture; editions are set in the build block)
# ---------------------------------------------------------------------------

source "amazon-ebs" "amd64" {
  region        = var.region
  instance_type = var.instance_type_amd64
  subnet_id     = var.subnet_id

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-${var.ubuntu_codename}-${var.ubuntu_release}-amd64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
      architecture        = "x86_64"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  ssh_username            = "ubuntu"
  temporary_key_pair_type = "ed25519"

  ami_regions   = local.copy_regions
  ami_groups    = var.ami_public ? ["all"] : []
  ami_users     = var.ami_users
  ena_support   = true
  sriov_support = true
  imds_support  = "v2.0"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  run_tags = {
    Name = "packer-pangolin-build"
  }
}

source "amazon-ebs" "arm64" {
  region        = var.region
  instance_type = var.instance_type_arm64
  subnet_id     = var.subnet_id

  source_ami_filter {
    filters = {
      name                = "ubuntu/images/hvm-ssd-gp3/ubuntu-${var.ubuntu_codename}-${var.ubuntu_release}-arm64-server-*"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
      architecture        = "arm64"
    }
    owners      = ["099720109477"] # Canonical
    most_recent = true
  }

  ssh_username            = "ubuntu"
  temporary_key_pair_type = "ed25519"

  ami_regions   = local.copy_regions
  ami_groups    = var.ami_public ? ["all"] : []
  ami_users     = var.ami_users
  ena_support   = true
  sriov_support = true
  imds_support  = "v2.0"

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
  }

  run_tags = {
    Name = "packer-pangolin-build"
  }
}

# ---------------------------------------------------------------------------
# Build: {community, enterprise} x {amd64, arm64}
#
# Build a single image with e.g.:
#   packer build -only='pangolin.amazon-ebs.community-amd64' .
# ---------------------------------------------------------------------------

build {
  name = "pangolin"

  source "source.amazon-ebs.amd64" {
    name            = "community-amd64"
    ami_name        = "pangolin-community-ubuntu-${var.ubuntu_release}-amd64-${local.version}"
    ami_description = "Pangolin ${local.editions.community} on Ubuntu ${var.ubuntu_release} (amd64). Installs the latest Pangolin release on first boot."
    tags            = merge(local.common_tags, { Name = "pangolin-community-amd64-${local.version}", "pangolin:edition" = "community", "pangolin:arch" = "amd64" })
    snapshot_tags   = merge(local.common_tags, { Name = "pangolin-community-amd64-${local.version}" })
  }

  source "source.amazon-ebs.arm64" {
    name            = "community-arm64"
    ami_name        = "pangolin-community-ubuntu-${var.ubuntu_release}-arm64-${local.version}"
    ami_description = "Pangolin ${local.editions.community} on Ubuntu ${var.ubuntu_release} (arm64). Installs the latest Pangolin release on first boot."
    tags            = merge(local.common_tags, { Name = "pangolin-community-arm64-${local.version}", "pangolin:edition" = "community", "pangolin:arch" = "arm64" })
    snapshot_tags   = merge(local.common_tags, { Name = "pangolin-community-arm64-${local.version}" })
  }

  source "source.amazon-ebs.amd64" {
    name            = "enterprise-amd64"
    ami_name        = "pangolin-enterprise-ubuntu-${var.ubuntu_release}-amd64-${local.version}"
    ami_description = "Pangolin ${local.editions.enterprise} on Ubuntu ${var.ubuntu_release} (amd64). Installs the latest Pangolin release on first boot."
    tags            = merge(local.common_tags, { Name = "pangolin-enterprise-amd64-${local.version}", "pangolin:edition" = "enterprise", "pangolin:arch" = "amd64" })
    snapshot_tags   = merge(local.common_tags, { Name = "pangolin-enterprise-amd64-${local.version}" })
  }

  source "source.amazon-ebs.arm64" {
    name            = "enterprise-arm64"
    ami_name        = "pangolin-enterprise-ubuntu-${var.ubuntu_release}-arm64-${local.version}"
    ami_description = "Pangolin ${local.editions.enterprise} on Ubuntu ${var.ubuntu_release} (arm64). Installs the latest Pangolin release on first boot."
    tags            = merge(local.common_tags, { Name = "pangolin-enterprise-arm64-${local.version}", "pangolin:edition" = "enterprise", "pangolin:arch" = "arm64" })
    snapshot_tags   = merge(local.common_tags, { Name = "pangolin-enterprise-arm64-${local.version}" })
  }

  provisioner "shell" {
    inline = [
      "cloud-init status --wait || true",
      "mkdir -p /tmp/pangolin-ami-files",
    ]
  }

  provisioner "file" {
    source      = "${path.root}/files/"
    destination = "/tmp/pangolin-ami-files"
  }

  provisioner "shell" {
    execute_command = "chmod +x {{ .Path }}; sudo -E env {{ .Vars }} bash '{{ .Path }}'"
    environment_vars = [
      "PANGOLIN_EDITION=${split("-", source.name)[0]}",
      "AMI_VERSION=${local.version}",
      "DEBIAN_FRONTEND=noninteractive",
    ]
    scripts = [
      "${path.root}/scripts/010-base.sh",
      "${path.root}/scripts/020-docker.sh",
      "${path.root}/scripts/030-pangolin.sh",
      "${path.root}/scripts/040-hardening.sh",
      "${path.root}/scripts/900-cleanup.sh",
    ]
  }

  post-processor "manifest" {
    output     = "${path.root}/manifest.json"
    strip_path = true
    custom_data = {
      edition     = split("-", source.name)[0]
      arch        = split("-", source.name)[1]
      ami_version = local.version
    }
  }
}
