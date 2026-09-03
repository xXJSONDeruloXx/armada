#!/usr/bin/env bash

set -euo pipefail

if [[ $# -ne 2 ]]; then
    printf 'usage: %s OGUI_SOURCE_DIR OUTPUT_DIR\n' "$0" >&2
    exit 2
fi

root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_dir="$1"
output_dir="$2"
expected_commit="b149644f46b71e175a2ad223e84c18361596691e"
builder_image="ghcr.io/shadowblip/opengamepadui-builder:latest"

git -C "$source_dir" rev-parse --git-dir >/dev/null 2>&1 || {
    printf 'OGUI source is not a git checkout: %s\n' "$source_dir" >&2
    exit 1
}
[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$expected_commit" ]] || {
    printf 'OGUI source must be pinned to %s\n' "$expected_commit" >&2
    exit 1
}

apply_once() {
    local patch_file="$1"
    if git -C "$source_dir" apply --check "$patch_file"; then
        git -C "$source_dir" apply "$patch_file"
    elif git -C "$source_dir" apply --reverse --check "$patch_file"; then
        return 0
    else
        printf 'patch does not apply cleanly: %s\n' "$patch_file" >&2
        exit 1
    fi
}

apply_once "$root/hardware_manager.patch"
apply_once "$root/plugin_manager.patch"
apply_once "$root/normal-ui-godot47.patch"
apply_once "$root/text-input-default.patch"

mkdir -p "$source_dir/plugins/armada-control" "$output_dir"
cp "$root"/{backend.gd,ogui-body-label.tres,overlay.gd,overlay.tscn,plugin.gd,plugin.json,quick_bar.gd} \
    "$source_dir/plugins/armada-control/"

if [[ "${ARMADA_OGUI_IN_BUILDER:-0}" == 1 ]]; then
    env HOME=/home/build TARGET_ARCH=aarch64 PKG_CONFIG_SYSROOT_DIR=/usr/aarch64-linux-gnu \
        make -C "$source_dir" -B GODOT=/usr/bin/godot build
else
    docker run --rm --platform linux/amd64 \
        -v "$source_dir:/src" \
        --mount type=volume,source=armada-ogui-godot-cache,target=/home/build/.local/share/godot \
        --workdir /src \
        -e HOME=/home/build -e PWD=/src -e TARGET_ARCH=aarch64 \
        -e PKG_CONFIG_SYSROOT_DIR=/usr/aarch64-linux-gnu \
        "$builder_image" make -B GODOT=/usr/bin/godot build
fi

cp "$source_dir/build/opengamepad-ui.aarch64" "$output_dir/"
cp "$source_dir/build/opengamepad-ui.pck" "$output_dir/"
cp "$source_dir/addons/core/bin/libopengamepadui-core.linux.template_release.aarch64.so" "$output_dir/"
"$root/build-plugin.sh" "$output_dir/armada-control.zip"
unzip -t "$output_dir/armada-control.zip" >/dev/null
sha256sum "$output_dir"/{opengamepad-ui.aarch64,opengamepad-ui.pck,libopengamepadui-core.linux.template_release.aarch64.so,armada-control.zip}
