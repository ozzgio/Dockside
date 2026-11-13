#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP=build/Dockside.app
test -x "$APP/Contents/MacOS/Dockside" || { echo "Run zsh build.sh first."; exit 1; }
version=$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/Dockside-$version-macOS.zip"
zip -q -r "dist/Dockside-$version-source.zip" Dockside.swift ControlCenter.swift NativeDisplay.swift NativeVirtualDisplay.h NativeVirtualDisplay.m make-icon.swift build.sh package.sh README.md CHANGELOG.md .gitignore assets .cursor research distribution .github docs
unzip -tqq "dist/Dockside-$version-macOS.zip"
unzip -tqq "dist/Dockside-$version-source.zip"
shasum -a 256 "dist/Dockside-$version-macOS.zip" "dist/Dockside-$version-source.zip" > dist/SHA256SUMS.txt
echo "Packaged Dockside $version app, source, and checksums in dist/."
