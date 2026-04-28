SHELL       := /bin/bash
TEMPLATE    := ../README.md.template
RECIPES_DIR ?= $(CURDIR)
CACHE_DIR   := $(RECIPES_DIR)/cache
export RECIPES_DIR CACHE_DIR

.PHONY: all clean
.DELETE_ON_ERROR:
.NOTPARALLEL:
all:

clean:
	rm -rf $(CACHE_DIR) template.d

$(CACHE_DIR):
	mkdir -p $@

# docgen.lua's dry-run scans the template, hashes each key= block's resolved
# body, writes $(CACHE_DIR)/<hash>/script.sh, and emits a self-contained
# makefile fragment with one rule per script (multi-output scripts emit a
# primary rule plus sibling rules depending on the primary with empty
# recipe -- portable to GNU Make 3.81). The order-only $(CACHE_DIR) prereq
# ensures the cache directory exists before any rule from template.d runs.
template.d: $(TEMPLATE) ../docgen.lua | $(CACHE_DIR)
	DEPS_FILE=$@ CACHE_DIR=$(CACHE_DIR) RECIPES_DIR=$(RECIPES_DIR) pandoc -f markdown -t plain \
	    --lua-filter ../docgen.lua $< -o /dev/null

-include template.d
