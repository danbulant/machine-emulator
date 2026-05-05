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
CACHE_DIR := $(RECIPES_DIR)/cache
export RECIPES_DIR CACHE_DIR
export LUA_PATH := $(CURDIR)/?.lua;$(LUA_PATH);;

.PHONY: build-docs-image clean

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

README.md: README.md.template replace.lua alerts.lua
	@if [ "$(DEV_ENV_HAS_DOCGEN)" = "yes" ]; then \
		$(MAKE) -C recipes/ && \
		CACHE_DIR=$(CACHE_DIR) RECIPES_DIR=$(RECIPES_DIR) pandoc -f markdown -s -t gfm --toc --lua-filter replace.lua --lua-filter alerts.lua -M default-replace=false README.md.template -o README.md; \
	else \
		$(MAKE) docs-image-exec CONTAINER_COMMAND="make README.md DEV_ENV_HAS_DOCGEN=yes"; \
	fi

clean:
	rm -f README.md
	$(MAKE) -C recipes clean
