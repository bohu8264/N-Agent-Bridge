#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
project_dir=${script_dir:h}
capture_dir="$project_dir/hardware-captures"
mkdir -p "$capture_dir"
capture_stamp=$(date -u +%Y%m%dT%H%M%SZ)

system_profiler SPUSBDataType -json > "$capture_dir/$capture_stamp-usb.json"
system_profiler SPBluetoothDataType -json > "$capture_dir/$capture_stamp-bluetooth.json"
ioreg -a -r -c IOHIDDevice > "$capture_dir/$capture_stamp-iohid.plist"
hidutil list > "$capture_dir/$capture_stamp-hidutil.txt"

cd "$project_dir"
swift build --product Air75HIDInspector
"$project_dir/.build/debug/Air75HIDInspector" > "$capture_dir/$capture_stamp-air75.json"

echo "Air75 diagnostic capture: $capture_dir/$capture_stamp-*"
