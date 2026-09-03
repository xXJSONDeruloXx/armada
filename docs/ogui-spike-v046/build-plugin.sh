#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 1 ]]; then
    printf 'usage: %s OUTPUT.zip\n' "$0" >&2
    exit 2
fi

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
output="$1"
if [[ "$output" != /* ]]; then
    output="$PWD/$output"
fi

stage="$(mktemp -d -t armada-ogui-plugin.XXXXXX)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/plugins/armada-control"
cp "$root"/{backend.gd,ogui-body-label.tres,overlay.gd,overlay.tscn,plugin.gd,plugin.json,quick_bar.gd} \
    "$stage/plugins/armada-control/"
mkdir -p "$(dirname -- "$output")"
(cd "$stage" && zip -q -r "$output" plugins)
