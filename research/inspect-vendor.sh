#!/bin/zsh
set -euo pipefail
app=${1:-"$HOME/Applications/USB Display.app"}
if [[ ! -d "$app" && -d '/Applications/USB Display.app' ]]; then app='/Applications/USB Display.app'; fi
info="$app/Contents/Info.plist"
[[ -f "$info" ]] || { print -u2 'USB Display is not installed at the selected path.'; exit 1; }
identifier=$(plutil -extract CFBundleIdentifier raw "$info")
[[ "$identifier" == com.winnerwave.USBDisplay ]] || { print -u2 'Unexpected app identifier; refusing inspection.'; exit 1; }
binary="$app/Contents/MacOS/USB Display"
print 'USB Display read-only interoperability inventory'
plutil -extract CFBundleShortVersionString raw "$info"
shasum -a 256 "$binary" | awk '{print "SHA-256: " $1}'
file "$binary" | sed "s|$binary|Executable|g"
codesign --verify --deep --strict "$app"
codesign -d --verbose=2 "$app" 2>&1 | rg 'Identifier=|Authority=|TeamIdentifier='
print 'Device matching and feature flags:'
plutil -p "$app/Contents/Resources/app.plist" | rg 'idProduct|idVendor|default-mirror|host-control|framerate|bitrate'
print 'Relevant implementation symbols (names only):'
strings "$binary" | rg '^(AMUSBDevice|AMHIDDevice|MirrorSession|H264Encoder|EZVirtualDisplay|VirtualDisplayFactory|sendH264Data|sendBulkCommand|writeBulkData)' | sort -u | awk 'NR <= 60'
