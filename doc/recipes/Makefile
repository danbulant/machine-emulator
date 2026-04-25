TEMPLATE  := ../README.md.template
CACHE_DIR ?= $(CURDIR)/cache
export CACHE_DIR

NEEDED_KEYS := $(shell { \
    grep -oE '\$$CACHE_DIR/[A-Za-z0-9._-]+\.out' $(TEMPLATE); \
    grep -oE 'cache=[A-Za-z0-9._-]+\.out' $(TEMPLATE); \
  } | sed 's|.*CACHE_DIR/||;s|cache=||;s|\.out$$||' | sort -u)
CACHE_FILES := $(addprefix $(CACHE_DIR)/,$(addsuffix .out,$(NEEDED_KEYS)))

.PHONY: all
all: $(CACHE_FILES)

$(CACHE_DIR):
	mkdir -p $@

$(CACHE_DIR)/%.out: cache.%.sh | $(CACHE_DIR)
	bash $<

define ADD_DEPS
$(CACHE_DIR)/$(patsubst cache.%.sh,%,$(1)).out: \
  $(addprefix $(CACHE_DIR)/,$(addsuffix .out,\
    $(shell grep -oE '\$$CACHE_DIR/[A-Za-z0-9._-]+\.out' $(1) \
            | sed 's|.*CACHE_DIR/||;s|\.out$$||' | sort -u)))
endef
$(foreach s,$(wildcard cache.*.sh),$(eval $(call ADD_DEPS,$(s))))

$(CACHE_DIR)/host.cmdline.rolling-ioctl-echo-loop-server.out \
$(CACHE_DIR)/host.cmdline.rolling-ioctl-echo-loop-client.out &: \
        cache.host.cmdline.rolling-ioctl-echo-loop.sh | $(CACHE_DIR)
	bash $<

$(CACHE_DIR)/host.cmdline.rolling-calc-template.template.out \
$(CACHE_DIR)/host.cmdline.rolling-calc-template.server.out \
$(CACHE_DIR)/host.cmdline.rolling-calc-template.client.out &: \
        cache.host.cmdline.rolling-calc-template.sh | $(CACHE_DIR)
	bash $<

$(CACHE_DIR)/host.cmdline.remote-client.out \
$(CACHE_DIR)/host.cmdline.remote-server.out &: \
        cache.host.cmdline.remote.sh | $(CACHE_DIR)
	bash $<

$(CACHE_DIR)/host.cmdline.remote-end-client.out \
$(CACHE_DIR)/host.cmdline.remote-begin-end-server.out &: \
        cache.host.cmdline.remote-end.sh | $(CACHE_DIR)
	bash $<

$(CACHE_DIR)/host.lua.remote-client.out \
$(CACHE_DIR)/host.lua.remote-server.out &: \
        cache.host.lua.remote.sh | $(CACHE_DIR)
	bash $<
