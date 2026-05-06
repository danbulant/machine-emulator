SHELL       := /bin/bash
TEMPLATE    := ../README.md.template
RECIPES_DIR ?= $(CURDIR)
REPLACE_CACHE_DIR   := $(RECIPES_DIR)/cache
export RECIPES_DIR REPLACE_CACHE_DIR
export LUA_PATH := $(RECIPES_DIR)/?.lua;$(LUA_PATH);;

.PHONY: all clean
.DELETE_ON_ERROR:
#.NOTPARALLEL:
all:

clean:
	rm -rf $(REPLACE_CACHE_DIR) template.d

$(REPLACE_CACHE_DIR):
	mkdir -p $@

# replace.lua's dry-run scans the template, hashes each key= block's resolved
# body, writes $(REPLACE_CACHE_DIR)/<hash>/body.<ext>, and emits a self-contained
# makefile fragment with one rule per script (multi-output scripts emit a
# primary rule plus sibling rules depending on the primary with empty
# recipe -- portable to GNU Make 3.81). The order-only $(REPLACE_CACHE_DIR) prereq
# ensures the cache directory exists before any rule from template.d runs.
template.d: $(TEMPLATE) ../replace.lua | $(REPLACE_CACHE_DIR)
	REPLACE_CACHE_DIR=$(REPLACE_CACHE_DIR) RECIPES_DIR=$(RECIPES_DIR) pandoc -f markdown -t plain \
	    -M write-user-dependencies=$@ -M default-replace=false --lua-filter ../replace.lua $< -o /dev/null

ifeq (,$(filter clean,$(MAKECMDGOALS)))
-include template.d
endif
