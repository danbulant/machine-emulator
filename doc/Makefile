# Docker image tag
TAG ?= devel

PLAYGROUND_IMAGE = cartesi/machine-emulator-playground

# Docker image platform
BUILD_PLATFORM ?=

ifneq ($(BUILD_PLATFORM),)
DOCKER_PLATFORM=--platform $(BUILD_PLATFORM)
endif

.PHONY: images build-playground

images:

check-playground:
	@if docker images $(DOCKER_PLATFORM) -q cartesi/machine-emulator-playground:$(TAG) 2>/dev/null | grep -q .; then \
		echo "Docker image $(PLAYGROUND_IMAGE):$(TAG) exists"; \
	else \
		echo "Docker image $(PLAYGROUND_IMAGE):$(TAG) does not exist. Creating:"; \
		$(MAKE) build-playground; \
	fi

playground-exec: check-playground
	@docker run --hostname linux-env --rm \
		-e USER=$$(id -u -n) \
		-e GROUP=$$(id -g -n) \
		-e UID=$$(id -u) \
		-e GID=$$(id -g) \
		-v `pwd`:/opt/cartesi/machine-emulator \
		-w /opt/cartesi/machine-emulator \
		cartesi/machine-emulator:linux-env /bin/bash -c "$(CONTAINER_COMMAND)"

build-playground: images
	docker build $(DOCKER_PLATFORM) --build-arg TAG=$(TAG) -t $(PLAYGROUND_IMAGE):$(TAG) -f Dockerfile .

README.md: README.md.template docgen.lua $(wildcard host-replacements/*.sh) $(wildcard target-replacements/*.sh)
	pandoc -f gfm+attributes -s -t gfm --toc --lua-filter docgen.lua README.md.template -o README.md
