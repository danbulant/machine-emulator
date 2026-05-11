# Docker image tag — must match the tag used by the root Makefile's
# build-emulator-image target so the docs image layers on top of an
# emulator built from the local source (kernel/rootfs images in
# tests/dependencies are built against the unreleased branch and may
# require emulator features not in any released base image).
TAG ?= devel

DOCS_IMAGE = cartesi/machine-emulator-docs

# Docker image platform
BUILD_PLATFORM ?=

ifneq ($(BUILD_PLATFORM),)
DOCKER_PLATFORM=--platform $(BUILD_PLATFORM)
endif

DEV_ENV_HAS_DOCGEN ?= no
RECIPES_DIR ?= $(CURDIR)/recipes
REPLACE_CACHE_DIR := $(RECIPES_DIR)/cache
export RECIPES_DIR REPLACE_CACHE_DIR
export LUA_PATH := $(CURDIR)/?.lua;$(RECIPES_DIR)/?.lua;$(LUA_PATH);;

.PHONY: build-docs-image clean
.DELETE_ON_ERROR:

HELLO_ROOTFS_INPUTS := \
    $(RECIPES_DIR)/Dockerfile.hello-rootfs \
    $(RECIPES_DIR)/build-hello-rootfs.sh \
    $(wildcard $(RECIPES_DIR)/hello/*)

$(RECIPES_DIR)/hello-rootfs.ext2: $(HELLO_ROOTFS_INPUTS) | check-docs-image
	cd $(RECIPES_DIR) && TAG=$(TAG) ./build-hello-rootfs.sh

check-docs-image:
	@if docker images $(DOCKER_PLATFORM) -q $(DOCS_IMAGE):$(TAG) 2>/dev/null | grep -q .; then \
		echo "Docker image $(DOCS_IMAGE):$(TAG) exists"; \
	else \
		echo "Docker image $(DOCS_IMAGE):$(TAG) does not exist. Creating:"; \
		$(MAKE) build-docs-image; \
	fi

docs-image-exec: check-docs-image
	docker run --hostname playground --rm \
		-e USER=$$(id -u -n) \
		-e GROUP=$$(id -g -n) \
		-e UID=$$(id -u) \
		-e GID=$$(id -g) \
		-v $(CURDIR):/work \
		-w /work \
		$(DOCS_IMAGE):$(TAG) /bin/bash -c "$(CONTAINER_COMMAND)"

run-docs-image: check-docs-image
	docker run --hostname playground --rm \
		-e USER=$$(id -u -n) \
		-e GROUP=$$(id -g -n) \
		-e UID=$$(id -u) \
		-e GID=$$(id -g) \
		-v $(CURDIR):/work \
		-w /work \
	    -it \
		$(DOCS_IMAGE):$(TAG) \
	    /bin/bash

build-docs-image:
	$(MAKE) -C .. build-emulator-image TAG=$(TAG)
	docker build $(DOCKER_PLATFORM) --build-arg TAG=$(TAG) -t $(DOCS_IMAGE):$(TAG) -f $(CURDIR)/Dockerfile ..

$(REPLACE_CACHE_DIR):
	mkdir -p $@

ifeq ($(DEV_ENV_HAS_DOCGEN),yes)

# Dry-run: scan the template, populate cache directories, and emit one make
# rule per annotated block into template.d. The rendered output IS the .d
# file (pandoc emits the RawBlock that replace.lua builds).
template.d: README.md.template replace.lua | $(REPLACE_CACHE_DIR)
	REPLACE_CACHE_DIR=$(REPLACE_CACHE_DIR) RECIPES_DIR=$(RECIPES_DIR) \
	    pandoc -f markdown -t plain \
	    -M write-user-dependencies=README.md -M default-replace=false \
	    --lua-filter replace.lua README.md.template -o $@

ifeq (,$(filter clean,$(MAKECMDGOALS)))
-include template.d
endif

# Real run: render the document. template.d adds per-cache-file prereqs to
# README.md, so editing a recipe propagates here naturally.
README.md: README.md.template replace.lua alerts.lua template.d
	REPLACE_CACHE_DIR=$(REPLACE_CACHE_DIR) RECIPES_DIR=$(RECIPES_DIR) \
	    pandoc -f markdown -s -t gfm --toc \
	    --lua-filter replace.lua --lua-filter alerts.lua \
	    -M default-replace=false \
	    README.md.template -o $@

else

# Without docgen tools on the host, delegate the whole build to the docs
# container. Inside, DEV_ENV_HAS_DOCGEN=yes activates the rules above and
# evaluates staleness against template.d.
.PHONY: README.md
README.md: $(RECIPES_DIR)/hello-rootfs.ext2
	$(MAKE) docs-image-exec CONTAINER_COMMAND="make README.md DEV_ENV_HAS_DOCGEN=yes"

endif

clean:
	rm -f README.md template.d
	rm -f $(RECIPES_DIR)/hello-rootfs.tar $(RECIPES_DIR)/hello-rootfs.ext2
	rm -rf $(REPLACE_CACHE_DIR)
