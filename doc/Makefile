# Docker image tag
TAG ?= 0.5.0

PLAYGROUND_IMAGE = cartesi/machine-emulator-docs-playground

# Docker image platform
BUILD_PLATFORM ?=

ifneq ($(BUILD_PLATFORM),)
DOCKER_PLATFORM=--platform $(BUILD_PLATFORM)
endif

DEV_ENV_HAS_DOCGEN ?= no
CACHE_DIR ?= $(CURDIR)/recipes/cache
export CACHE_DIR

.PHONY: build-playground clean

check-playground:
	@if docker images $(DOCKER_PLATFORM) -q $(PLAYGROUND_IMAGE):$(TAG) 2>/dev/null | grep -q .; then \
		echo "Docker image $(PLAYGROUND_IMAGE):$(TAG) exists"; \
	else \
		echo "Docker image $(PLAYGROUND_IMAGE):$(TAG) does not exist. Creating:"; \
		$(MAKE) build-playground; \
	fi

playground-exec: check-playground
	docker run --hostname playground --rm \
		-e USER=$$(id -u -n) \
		-e GROUP=$$(id -g -n) \
		-e UID=$$(id -u) \
		-e GID=$$(id -g) \
		-v $(CURDIR):/work \
		-w /work \
		$(PLAYGROUND_IMAGE):$(TAG) /bin/bash -c "$(CONTAINER_COMMAND)"

build-playground:
	docker build $(DOCKER_PLATFORM) --build-arg TAG=$(TAG) -t $(PLAYGROUND_IMAGE):$(TAG) -f Dockerfile .

README.md: README.md.template docgen.lua
	@if [ "$(DEV_ENV_HAS_DOCGEN)" = "yes" ]; then \
		$(MAKE) -C recipes/ && \
		CACHE_DIR=$(CACHE_DIR) pandoc -f markdown -s -t gfm --toc --lua-filter docgen.lua README.md.template -o README.md; \
	else \
		$(MAKE) playground-exec CONTAINER_COMMAND="make README.md DEV_ENV_HAS_DOCGEN=yes"; \
	fi

clean:
	rm -f README.md
	$(MAKE) -C recipes clean
