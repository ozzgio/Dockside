#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
APP="$PWD/build/Dockside.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/Dockside.iconset
xcrun swift make-icon.swift assets
cp assets/Dockside.svg docs/icon.svg
cp assets/icon-128.png docs/icon.png
for size in 16 32 128 256 512; do
    cp "assets/icon-$size.png" "build/Dockside.iconset/icon_${size}x${size}.png"
    doubled=$((size * 2))
    cp "assets/icon-$doubled.png" "build/Dockside.iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns build/Dockside.iconset -o "$APP/Contents/Resources/DocksideApp.icns"
cp assets/icon-128.png "$APP/Contents/Resources/DocksideMark.png"
for arch in arm64 x86_64; do
    xcrun clang -target "$arch-apple-macos14.0" -fobjc-arc -c NativeVirtualDisplay.m -o "build/NativeVirtualDisplay-$arch.o"
    xcrun swiftc -parse-as-library -O -target "$arch-apple-macos14.0" \
        -import-objc-header NativeVirtualDisplay.h -framework SwiftUI -framework AppKit -framework IOKit -framework VideoToolbox -framework EventKit -framework CoreAudio Dockside.swift ControlCenter.swift NativeDisplay.swift DeskUtilities.swift TodayView.swift "build/NativeVirtualDisplay-$arch.o" -o "build/Dockside-$arch"
done
lipo -create build/Dockside-arm64 build/Dockside-x86_64 -output "$APP/Contents/MacOS/Dockside"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Dockside</string>
<key>CFBundleIdentifier</key><string>local.ozzo.Dockside</string>
<key>CFBundleName</key><string>Dockside</string>
<key>CFBundleDisplayName</key><string>Dockside</string>
<key>CFBundleIconFile</key><string>DocksideApp.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.4.0</string>
<key>CFBundleVersion</key><string>5</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSCalendarsFullAccessUsageDescription</key><string>Show today’s events on your Dockside screen. Dockside does not create or edit calendar events.</string>
<key>NSRemindersFullAccessUsageDescription</key><string>Show unfinished reminders on your Dockside screen. Dockside does not create or edit reminders.</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict></plist>
PLIST
cp research/native/NOTICE.md "$APP/Contents/Resources/ThirdPartyNotices.txt"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/Dockside" --self-test
mkdir -p "$HOME/Applications"
ditto "$APP" "$HOME/Applications/Dockside.app"
echo "Built universal Dockside and installed in $HOME/Applications."
