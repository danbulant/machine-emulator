SHELL     := /bin/bash
TEMPLATE  := ../README.md.template
CACHE_DIR ?= $(CURDIR)/cache
export CACHE_DIR

SCRIPTS := $(wildcard cache.*.sh)
DEPS    := $(SCRIPTS:%=%.d)

.PHONY: all clean
.DELETE_ON_ERROR:
.NOTPARALLEL:
all:

clean:
	rm -rf $(CACHE_DIR) $(DEPS) template.d

$(CACHE_DIR):
	mkdir -p $@

# docgen.lua emits a standard make rule "all: <cache files>", augmenting
# the prereq list of the .PHONY all target above (Half 1).
template.d: $(TEMPLATE) ../docgen.lua
	DEPS_FILE=$@ CACHE_DIR=$(CACHE_DIR) pandoc -f markdown -t plain \
	    --lua-filter ../docgen.lua $< -o /dev/null

# Each script emits its own .d via --emit-deps (mirrors gcc -MMD).
# The .d is a standard make rule the Makefile imports verbatim.
%.sh.d: %.sh lib.sh
	bash $< --emit-deps > $@

# Recipe for single-output cache files. Their .d is a pure prereq
# declaration (gcc-style, no recipe); this pattern rule supplies the
# command. Multi-output scripts embed their own recipe in the .d (required
# by &: syntax in GNU make), so the explicit rule there wins over this pattern.
$(CACHE_DIR)/%.out: | $(CACHE_DIR)
	bash $<

-include template.d
-include $(DEPS)
