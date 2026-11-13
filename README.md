# Dockside

<img src="assets/icon-128.png" width="96" height="96" alt="Dockside: a violet desk display with a clock and orange dock base">

A native Mac dashboard for the little screen on your Cabletime ScreenDock.

[Project page](https://ozzgio.github.io/Dockside/) · [Developer previews](https://github.com/ozzgio/Dockside/releases) · [Issues](https://github.com/ozzgio/Dockside/issues)

Large, correctly padded clock digits, live Mac activity, optional focus, seven themes, selectable widgets, and the apps you choose. A separate Control Center handles setup; a menu-bar icon keeps those controls close.

**The source is public, but the license is undecided.** No open-source reuse license is granted yet. This is an independent project, with no affiliation to CABLETIME or EZCast.

**1.3 adds experimental native USB.** Dockside can send its own dashboard directly to the tested `1de1:f201` Cabletime dock, with USB Display stopped. Native mode uses a private macOS virtual-display API and is limited to this 1280 × 720 dashboard; it does not mirror other apps or the Mac menu bar. The supplied USB Display app remains an optional companion-mode fallback. No vendor binary or library is included.

## Getting started

1. Connect the dock and open Dockside.
2. Open **Control Center** using the sliders button, the Dockside menu-bar icon, or **⌘,**.
3. Under **Power and driver**, enable **Use Dockside native USB (experimental)**. Dockside quits USB Display before opening its own video connection. Keep the supplied app installed while evaluating this preview.
4. Choose a layout, theme, widget visibility, clock size, and shortcut apps.

If native USB fails, try **Retry native USB** after reconnecting the cable. **Open USB Display** switches off native USB and opens the supplied driver. In companion mode, allow that app's screen-recording permission if requested, select its **HDMI Extender** display, and use **1280 × 720** to match the tested stream.

## Make it yours

- **Fullscreen:** native USB always fills the panel, without a title bar. In companion mode, macOS fullscreen is available from the dashboard, Control Center, or **Control–⌘–F**. Press **Esc** to leave. The Dockside header and Mac menu-bar behavior have separate settings.
- **Themes:** Midnight, Ocean, Paper, Graphite, Forest, Plum, and Sunset. Theme and clock preferences are saved locally.
- **Layouts and widgets:** start with Quiet clock, At a glance, or Focus. Independently show/hide Mac activity, CPU history, date, app shortcuts, and header battery. Focus is off by default.
- **Clock:** choose 80–115% size; 24-hour time with two-digit hours/minutes, and optional two-digit seconds. Quiet-clock mode is also saved.
- **App buttons:** choose any installed `.app` for Files, Calendar, and Notes. Labels follow your selected apps; the Mac’s global defaults are not modified. Use **Reset** on a row to restore the original app.
- **Focus:** enable it in Widgets when wanted, then choose a duration from 5 to 120 minutes, then start, pause, or reset the timer. Hiding the focus widget pauses a running timer. An active session keeps its current duration until you reset it.
- **Keep awake:** the labeled lightbulb control prevents idle display sleep while Dockside runs. It is **not brightness** and it does not override lid-close or manual sleep. Adjust the panel with the dock’s physical brightness button.
- **Driver setup:** native USB preference is saved; new installations default to companion mode until native is explicitly enabled. The optional USB Display auto-open setting is off by default and disabled in native mode. No driver is installed or downloaded by Dockside.

If the driver or dock disappears, Dockside explains the missing connection on the Mac. Native mode stops on a failed write, lost heartbeat, or factory-app conflict; reconnect and use Retry. Companion mode can return to its preferred display when it reappears. Opening another Dockside copy reuses the existing instance.

## Product updates

**Control Center → Updates & project** checks public GitHub releases on request, including developer previews. Downloads and installation are manual. No updater executes a downloaded file.

A tag such as `v1.3.0` runs the build matrix before the release workflow publishes a developer-preview app ZIP, source ZIP, and checksums. Main-branch pushes and pull requests run the same build/self-check jobs.

The distributed app is **ad-hoc signed, not notarized**. A smooth public downloaded-app installation requires a maintainer’s Apple Developer ID signature and Apple notarization. No signing credential is configured in this repository or its workflows.

## macOS compatibility

The universal executable contains **Apple Silicon and Intel** code with a **macOS 14.0** minimum deployment target. That target is not a claim that every OS/hardware combination has been tested.

- **macOS 27.0.1, Apple Silicon:** local build and live dock/UI testing; the only physical native-USB test configuration so far.
- **macOS 15 Intel and macOS 26 Apple Silicon:** automated build and self-check jobs; check [their current results](https://github.com/ozzgio/Dockside/actions) before relying on them.
- **macOS 14:** deployment target only; needs real-machine verification.
- Native USB on other macOS versions, repeated reconnects, sleep/wake, and other panels require separate hardware testing. The private virtual-display API can change; companion mode remains available.

GitHub’s macOS 14 image is being retired, so CI uses explicit macOS 15 Intel and macOS 26 ARM runners rather than a moving `macos-latest` label. See [GitHub’s runner inventory](https://github.com/actions/runner-images).

## Privacy and measurements

Activity readings stay on the Mac. No accounts, analytics, saved activity history, third-party packages, or screen-recording permission are required by Dockside: native video is rendered from its own SwiftUI dashboard, not captured from the desktop. The virtual display provides mouse hit testing; separate windows and system menus are not streamed. The only network request made by Dockside is an explicit update check to GitHub; your source IP is visible to GitHub. Normal app-shortcut launches are handled by macOS.

CPU/network readings update every second. Memory is an estimate from VM counters; network throughput sums physical `en*` interfaces and includes background traffic. Free storage includes capacity macOS reports as reclaimable for important usage. Display matching is by name; multiple identically named displays are ambiguous.

## Build and package

Install Apple’s Command Line Tools, quit Dockside, and run:

```sh
zsh build.sh
zsh package.sh
```

The build creates `build/Dockside.app`, runs the assert-based self-check, and installs one copy in `~/Applications/Dockside.app`. Run that installed copy. Packaging creates app/source ZIPs and `SHA256SUMS.txt` in `dist/`; it does not include user preferences, vendor software, or credentials.

Checks cover CPU deltas, network counter resets, memory sampling, focus controls, saved/validated preferences, version parsing, and USB report chunk boundaries, malformed H.264 NAL lengths, and leading-zero clock regressions including `20:01`, `20:01:05`, and `00:00:00`.

## Driver interoperability research

The [vendor investigation](research/VENDOR.md) records the original binary inventory and independently confirmed video transport. The [native backend notes](research/native/README.md) explain the wire format, startup ordering, checks, and limitations. Protocol/framing derives from a documented MIT reference; its full [notice](research/native/NOTICE.md) is retained in source and the app bundle. This third-party notice does not choose a license for the rest of Dockside.

Run `zsh research/inspect-vendor.sh` for a sanitized inventory of your installed factory driver. The project-local [vendor-display-research skill](.cursor/skills/vendor-display-research/SKILL.md) defines the workflow. No firmware writes, signature patching, security changes, or vendor redistribution are used.

## Design and distribution

The original icon is in `assets/Dockside.svg`. `make-icon.swift` renders its PNG sizes, and the build creates a proper `.icns` resource. The dashboard uses the same artwork. The project page is static HTML/CSS/JS in `docs/`, published by GitHub Pages; no build service or tracker is needed.

[Release notes](distribution/release-notes.md), [LinkedIn/X drafts](distribution/social-posts.md), and [changelog](CHANGELOG.md) are included. Social drafts have not been posted. Sponsorship/payment integrations are outside this version’s scope.

Created by [ozzo](https://ozzo.blog) · [GitHub](https://github.com/ozzgio) · [LinkedIn](https://www.linkedin.com/in/ozzolagiorgio/) · [X](https://x.com/ozzgio_)
