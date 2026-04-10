#!/bin/zsh

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

icon_name="${ICON_NAME:-AppIcon}"
developer_dir="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
output_dir="${OUTPUT_DIR:-$project_root/Packaging}"

export DEVELOPER_DIR="$developer_dir"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

master_png="$work_dir/${icon_name}-master.png"
iconset_dir="$work_dir/${icon_name}.iconset"

swift "$script_dir/generate-app-icon.swift" "$master_png"
mkdir -p "$iconset_dir" "$output_dir"

for base_size in 16 32 128 256 512; do
    retina_size=$((base_size * 2))
    sips -z "$base_size" "$base_size" "$master_png" --out "$iconset_dir/icon_${base_size}x${base_size}.png" >/dev/null
    sips -z "$retina_size" "$retina_size" "$master_png" --out "$iconset_dir/icon_${base_size}x${base_size}@2x.png" >/dev/null
done

cp "$master_png" "$output_dir/${icon_name}-preview.png"
iconutil -c icns "$iconset_dir" -o "$output_dir/${icon_name}.icns"

echo "Generated app icon assets:"
echo "  Preview: $output_dir/${icon_name}-preview.png"
echo "  ICNS: $output_dir/${icon_name}.icns"
