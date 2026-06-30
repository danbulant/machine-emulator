#!/bin/bash

set -e

cartesi_machine=${1:-cartesi-machine}

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT
snapshot_dir="$tmp_dir/save_and_load_test"

bash -c "$cartesi_machine --max-mcycle=0 --store=$snapshot_dir"
bash -c "$cartesi_machine --load=$snapshot_dir"
