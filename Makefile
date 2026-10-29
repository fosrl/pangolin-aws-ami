BUILDS ?= community-amd64 community-arm64 enterprise-amd64 enterprise-arm64
empty :=
space := $(empty) $(empty)
comma := ,
ONLY = $(subst $(space),$(comma),$(strip $(addprefix pangolin.amazon-ebs.,$(BUILDS))))

.PHONY: init validate fmt lint build clean

init:
	packer init .

fmt:
	packer fmt .

validate: init
	packer fmt -check .
	packer validate .

lint:
	shellcheck files/usr/local/sbin/pangolin-setup files/etc/update-motd.d/99-pangolin \
		files/etc/profile.d/pangolin-setup.sh scripts/*.sh examples/launch.sh

# make build                         # all four AMIs
# make build BUILDS=community-arm64  # just one
build: init
	packer build -only='$(ONLY)' .

clean:
	rm -f manifest.json
