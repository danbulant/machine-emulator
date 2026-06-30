#!/bin/bash
# Copyright Cartesi and individual authors (see AUTHORS)
# SPDX-License-Identifier: LGPL-3.0-or-later
#
# Generates the coverage report from .gcda files and uarch PC traces.
#
# This script is designed to run either natively (when the RISC-V toolchain
# is available) or inside the toolchain Docker container (when it is not).
# Running inside the container ensures riscv64-unknown-elf-addr2line is
# available for the uarch PC resolution.
#
# Usage: generate-coverage-report.sh <uarch-elf> <pcs-dir>
#   Must be run from the tests/ directory.

set -e

UARCH_ELF="$1"
PCS_DIR="$2"

if [ -z "$UARCH_ELF" ] || [ -z "$PCS_DIR" ]; then
    echo "Usage: $0 <uarch-elf> <pcs-dir>" >&2
    exit 1
fi

SRC_DIR=../src
COVERAGE_DIR=build/coverage/gcc

# Step 1: generate merged .gcov files from .gcda data
lua5.4 ./scripts/run-gcov.lua "$SRC_DIR" gcov

# Step 2: merge uarch PC coverage into .gcov files
lua5.4 ./scripts/uarch-pcs-to-gcov.lua "$UARCH_ELF" "$PCS_DIR" "$SRC_DIR"

# Step 3: generate the HTML report and text summary
mkdir -p "$COVERAGE_DIR"
SRC_ABS=$(cd "$SRC_DIR" && pwd)
UARCH_ABS=$(cd "$SRC_DIR/../uarch" && pwd)
cd "$SRC_DIR"
gcovr --gcov-ignore-parse-errors --use-gcov-files \
    --root . \
    --filter "$SRC_ABS" \
    --filter "$UARCH_ABS" \
    --html-details "../tests/$COVERAGE_DIR/index.html" \
    --txt "../tests/$COVERAGE_DIR/../coverage.txt" \
    --print-summary
