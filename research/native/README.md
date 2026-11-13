# Native USB backend

The macOS transport in `NativeDisplay.swift` uses public IOHID and VideoToolbox APIs. The optional virtual desktop uses runtime lookup of private CoreGraphics classes in `NativeVirtualDisplay.m`; it can break on a future macOS update. It is not an App Store driver, kernel extension, firmware patch, or redistributed vendor binary.

## Evidence and scope

- Tested device: Cabletime ScreenDock, `Actions_MAC`, USB `1de1:f201`.
- Two HID interfaces with output-report maxima 4096 and 12288 bytes. Video must use full **12288-byte reports** on this macOS device, report ID 2 (12272 payload bytes after its 16-byte header); JSON-RPC control uses 4096-byte reports, report ID 1. Short 4096-byte video writes returned success but produced severe green/blue partial-frame corruption. The owner confirmed the dashboard became clean after matching the advertised 12288-byte video size.
- The integrated native dashboard was physically verified by the owner after the video-report-size correction. Process inspection showed one Dockside instance and no USB Display process.
- An independently generated 1280 × 720 color pattern reached the physical panel with every USB Display process stopped. The owner confirmed a visible pattern; that early check did not establish image quality. Full-frame quality was confirmed later with the corrected integrated dashboard.
- The integrated backend creates its own virtual display for Mac mouse hit testing and renders only Dockside's SwiftUI dashboard. It does not capture or mirror other applications, system menus, or separate windows. Control Center opens on the main Mac display.
- Video uses native VideoToolbox H.264 Baseline, yuv420p, with SPS/PPS and Annex-B NAL framing. There is no ffmpeg dependency in the app. A bounded single-frame queue prevents an accumulating video backlog.
- The app stops native streaming if USB Display starts, a HID write fails, or the device heartbeat is lost. Use **Retry native USB** after reconnecting, or **Open USB Display** for the companion fallback.
- The virtual descriptor uses a nominal 100-DPI desktop size, not the small panel’s physical dimensions: the latter was rejected by macOS during testing. Display activation requires an exact online result of `1` plus discovery through `NSScreen`; an error return of `-1` is not success. A stable Dockside-specific virtual identity preserves display arrangement.
- Native mode successfully stopped and restarted from Control Center without launching USB Display. A sample of the earlier full-dashboard build used about 5% of one CPU core and 262 MiB RSS on the test Mac; this is a spot measurement, not a benchmark. The owner physically unplugged/reconnected the USB cable during development; the cold-start path recovered, and the later full-report-size correction produced a clean dashboard.
- Only one attached `1de1:f201` dock is supported by this preview. The stream is fixed at the verified 1280 × 720 mode, with two video updates per second and separately composited cursor updates.
- Native mode always fills the panel. The Mac menu-bar status item remains available. Full macOS desktop mirroring and software brightness control are outside this backend's scope.

## Handshake

Briefly listen for a device heartbeat and echo its session ID. If none arrives, initiate the reference implementation's cold-start session `100000`; this recovered the panel after the owner physically disconnected/reconnected it. Request `app-launched` and wait for that request ID's acknowledgement. Maintain heartbeats throughout startup. The unsolicited ready announcement is not required on every new session; it may already have been delivered to the previous driver. The Windows/product compatibility strings match the working reference handshake; they do not identify the Mac or change firmware.

Clear the cursor, send the documented display passthrough ID 103 (`AQ==`), request `notify-projection-started`, and send the first video frame before expecting its acknowledgement. The integrated backend validates that acknowledgement within eight seconds; waiting for it before video deadlocks this firmware. Stop with `notify-projection-stopped`. No unknown control, update, reset, or brightness commands are sent.

## Checks

`zsh build.sh` runs protocol chunk-boundary and malformed-NAL self-checks along with the app regressions. They do not touch USB hardware or create a virtual display.

For a local native encoder check after building:

```sh
xcrun swiftc -parse-as-library -import-objc-header NativeVirtualDisplay.h \
  -framework SwiftUI -framework AppKit -framework IOKit -framework VideoToolbox \
  NativeDisplay.swift research/native/EncoderCheck.swift build/NativeVirtualDisplay-arm64.o \
  -o build/EncoderCheck
build/EncoderCheck
```

This writes a synthetic two-band frame to `build/native-encoder-check.h264`, not a desktop capture. On an Intel Mac, use the x86_64 bridge object. Optional `ffprobe` inspection on the test Mac confirmed H.264 Baseline, 1280 × 720, yuv420p.


## Sources

- [Actions Micro protocol and MIT reference](https://github.com/N7le/powerology-actions-usb-display-linux-driver), pinned revision and retained license in [NOTICE.md](NOTICE.md).
- [Chromium's virtual-display API declarations](https://chromium.googlesource.com/chromium/src/+/HEAD/ui/display/mac/test/virtual_display_util_mac.mm), consulted for the private Objective-C API shape. Dockside looks up those classes at runtime and returns an error if unavailable.
- [Apple VideoToolbox](https://developer.apple.com/documentation/videotoolbox/vtcompressionsession-api-collection) and [SwiftUI ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer).
