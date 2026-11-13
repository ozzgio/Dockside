# Changelog

## 1.4.0 — Today page and dashboard redesign

- Today page: read-only calendar agenda and reminders, second-timezone clock, optional Open-Meteo weather, Mac sound volume, and a picture dimmer, each optional in Settings → Utilities.
- One bottom bar: app shortcuts with real app icons, Overview / Clock / Today, and a single labeled Settings button. Control Center renamed Settings; duplicate layout and fullscreen controls removed.
- New display-and-dock icon generated from one shape list for the app, project page, and a matching menu-bar template icon.
- Native USB: the virtual screen is parked to the right of the desktop so the Mac Dock can't move under the dashboard and block clicks; the dashboard window sits above the Dock layer on the panel.
- Native USB: heartbeat, video, cursor, and clock timers run in common run-loop modes, so menus, pickers, and permission prompts no longer drop the dock to "Connecting signal".
- Native USB: 2× panel cursor aligned to its hotspot, hidden while the pointer is on another screen.

## 1.3.0 — experimental native USB preview

- Independent IOHID video transport and native VideoToolbox H.264 encoding for the tested 1280 × 720 Cabletime dock; USB Display is stopped in native mode.
- Dashboard-only virtual display for mouse controls, direct SwiftUI rendering, hardware cursor updates, and explicit factory-driver fallback.
- Mac-specific full 12-KiB video reports fix green/blue partial-frame corruption; control remains 4 KiB.
- Cold-start session initiation, heartbeats throughout startup, first-frame acknowledgement ordering, and bounded frame queuing.
- Optional focus widget, off by default; disabling it pauses an active timer.
- Quiet clock, At a glance, and Focus layouts; toggles for activity, history, date, shortcuts, and battery; 80–115% clock size.
- Retained MIT protocol attribution in source and app downloads; protocol/parser regression checks and a local native-encoder check.

Native USB is experimental, uses a private macOS virtual-display API, and does not mirror arbitrary desktop windows. Physical native-mode coverage is limited to macOS 27.0.1 Apple Silicon and one dock. Signing remains ad hoc; the project license is still pending.

## 1.2.0 — developer preview

- Native fullscreen, independent header/menu-bar settings, and a menu-bar control.
- Separate Control Center with seven saved themes, clock seconds, preferred display, and focus duration.
- Configurable app shortcuts for Files, Calendar, and Notes.
- Fixed two-digit minutes and seconds, with clock regression checks.
- Replaced the ambiguous sun button with a labeled keep-awake control and explicit brightness explanation.
- New violet/orange clock-and-dock app icon, packaged as a macOS icon resource.
- Manual GitHub release checks; no automatic download/install.
- Public-source repository and project page, with the license still undecided.
- Universal builds and a macOS build/self-check matrix.
- Initial read-only vendor-driver interoperability report and reusable project skill.

USB Display remains required. Release binaries are not notarized.

## 1.1.0

- Higher-contrast dashboard, original icon assets, offline guidance, driver reconnect button, and duplicate-launch prevention.

## 1.0.0

- Clock, live Mac stats, 25-minute focus timer, app shortcuts, and keep-awake mode.
