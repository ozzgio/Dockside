# Dockside

<img src="assets/icon-128.png" width="96" height="96" alt="Dockside: a violet desk display with a clock and orange dock base">

A native Mac dashboard for the little screen on your Cabletime ScreenDock.

[Project page](https://ozzgio.github.io/Dockside/) · [Developer previews](https://github.com/ozzgio/Dockside/releases) · [Issues](https://github.com/ozzgio/Dockside/issues)

Large, correctly padded clock digits, live Mac activity, a focus timer, seven themes, and the apps you choose. A separate Control Center handles setup; a menu-bar icon keeps those controls close.

**The source is public, but the license is undecided.** No open-source reuse license is granted yet. This is an independent project, with no affiliation to CABLETIME or EZCast.

**USB Display is still required.** Dockside supplies the dashboard; the vendor app supplies the USB video connection. The bundled vendor binary is not part of this repository or its downloads.

## Getting started

1. Connect the dock and open its supplied USB Display app. Give that app screen-recording permission if macOS requests it.
2. Open Dockside. It finds the display named **HDMI Extender**, or choose another display in Control Center.
3. For the tested ScreenDock, set its display resolution to **1280 × 720** in System Settings. That matches the observed driver output and avoids downscaling a 1080p virtual desktop.
4. Open **Control Center** using the dashboard’s sliders button, the Dockside menu-bar icon, or **⌘,**.

## Make it yours

- **Fullscreen:** native macOS fullscreen, available from the dashboard, Control Center, or **Control–⌘–F**. Press **Esc** to leave. The Dockside header and Mac menu-bar behavior have separate settings.
- **Themes:** Midnight, Ocean, Paper, Graphite, Forest, Plum, and Sunset. Theme and clock preferences are saved locally.
- **Clock:** 24-hour time with two-digit hours/minutes, and optional two-digit seconds. Quiet-clock mode is also saved.
- **App buttons:** choose any installed `.app` for Files, Calendar, and Notes. Labels follow your selected apps; the Mac’s global defaults are not modified. Use **Reset** on a row to restore the original app.
- **Focus:** choose a duration from 5 to 120 minutes, then start, pause, or reset the timer. An active session keeps its current duration until you reset it.
- **Keep awake:** the labeled lightbulb control prevents idle display sleep while Dockside runs. It is **not brightness** and it does not override lid-close or manual sleep. Adjust the panel with the dock’s physical brightness button.
- **Driver setup:** optionally open USB Display when Dockside launches. This is off by default. There is also an explicit reconnect button; the driver is never installed or silently downloaded.

If the driver or dock disappears, Dockside explains the missing connection on the Mac. When the preferred display reappears, it can return to the dock. Opening another Dockside copy reuses the existing instance.

## Product updates

**Control Center → Updates & project** checks public GitHub releases on request, including developer previews. Downloads and installation are manual. No updater executes a downloaded file.

A tag such as `v1.2.0` runs the build matrix before the release workflow publishes a developer-preview app ZIP, source ZIP, and checksums. Main-branch pushes and pull requests run the same build/self-check jobs.

The distributed app is **ad-hoc signed, not notarized**. A smooth public downloaded-app installation requires a maintainer’s Apple Developer ID signature and Apple notarization. No signing credential is configured in this repository or its workflows.

## macOS compatibility

The universal executable contains **Apple Silicon and Intel** code with a **macOS 14.0** minimum deployment target. That target is not a claim that every OS/hardware combination has been tested.

- **macOS 27.0.1, Apple Silicon:** local build and live dock/UI testing.
- **macOS 15 Intel and macOS 26 Apple Silicon:** automated build and self-check jobs; check [their current results](https://github.com/ozzgio/Dockside/actions) before relying on them.
- **macOS 14:** deployment target only; needs real-machine verification.
- Vendor-driver compatibility, physical reconnects, lid-close sleep, and older physical panels require separate hardware testing.

GitHub’s macOS 14 image is being retired, so CI uses explicit macOS 15 Intel and macOS 26 ARM runners rather than a moving `macos-latest` label. See [GitHub’s runner inventory](https://github.com/actions/runner-images).

## Privacy and measurements

Activity readings stay on the Mac. No accounts, analytics, saved activity history, third-party packages, or screen-recording permission are required by Dockside. The only network request made by Dockside is an explicit update check to GitHub; your source IP is visible to GitHub. Normal app-shortcut launches are handled by macOS.

CPU/network readings update every second. Memory is an estimate from VM counters; network throughput sums physical `en*` interfaces and includes background traffic. Free storage includes capacity macOS reports as reclaimable for important usage. Display matching is by name; multiple identically named displays are ambiguous.

## Build and package

Install Apple’s Command Line Tools, quit Dockside, and run:

```sh
zsh build.sh
zsh package.sh
```

The build creates `build/Dockside.app`, runs the assert-based self-check, and installs one copy in `~/Applications/Dockside.app`. Run that installed copy. Packaging creates app/source ZIPs and `SHA256SUMS.txt` in `dist/`; it does not include user preferences, vendor software, or credentials.

Checks cover CPU deltas, network counter resets, memory sampling, focus controls, saved/validated preferences, version parsing, and leading-zero clock regressions including `20:01`, `20:01:05`, and `00:00:00`.

## Driver interoperability research

The initial read-only [vendor investigation](research/VENDOR.md) records the observed USB IDs, virtual-display/capture pipeline, H.264/USB symbol evidence, and the unanswered protocol questions. **No replacement driver has been implemented.**

Run `zsh research/inspect-vendor.sh` for a sanitized inventory of your installed driver. The project-local [vendor-display-research skill](.cursor/skills/vendor-display-research/SKILL.md) defines a bounded workflow for future work. It avoids firmware writes, signature patching, and redistribution of vendor code.

## Design and distribution

The original icon is in `assets/Dockside.svg`. `make-icon.swift` renders its PNG sizes, and the build creates a proper `.icns` resource. The dashboard uses the same artwork. The project page is static HTML/CSS/JS in `docs/`, published by GitHub Pages; no build service or tracker is needed.

[Release notes](distribution/release-notes.md), [LinkedIn/X drafts](distribution/social-posts.md), and [changelog](CHANGELOG.md) are included. Social drafts have not been posted. Sponsorship/payment integrations are outside this version’s scope.

Created by [ozzo](https://ozzo.blog) · [GitHub](https://github.com/ozzgio) · [LinkedIn](https://www.linkedin.com/in/ozzolagiorgio/) · [X](https://x.com/ozzgio_)
