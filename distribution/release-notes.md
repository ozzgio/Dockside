**1.4.1** fixes green-stripe corruption on the panel when the pointer left the dock screen in 1.4.0.

Dockside 1.4 adds a **Today** page and a calmer, simpler dashboard for the tested Cabletime ScreenDock (`1de1:f201`).

**Today** shows today's agenda and reminders (read-only, after you allow access), a second-timezone clock, optional Open-Meteo weather by city name, Mac sound volume, and a picture dimmer. Each piece is optional in **Settings → Utilities**.

The dashboard has one bottom bar: your app shortcuts with their real icons, **Overview / Clock / Today**, and a single labeled **Settings** button. Control Center is now called **Settings**, and the duplicate layout and fullscreen controls are gone. There's a new app icon and a matching menu-bar icon.

Native USB fixes:
- The panel's virtual screen is placed to the right of your Mac displays, so the Mac Dock stays on your main screen and can't cover the dashboard and catch its clicks.
- Opening a menu, picker or permission prompt no longer pauses the heartbeat and video, which used to drop the dock to "Connecting signal".
- The panel cursor is larger, and it's hidden while the pointer is on another screen.

This is a developer preview, ad-hoc signed and **not notarized**. The universal build targets macOS 14+; physical native USB testing is limited to macOS 27 Apple Silicon and one dock. Native mode uses a private Apple virtual-display API that may change. Keep the factory USB Display app installed as a fallback.

Source is public; the project license is undecided. The MIT notice for the protocol reference is included in the source and app bundle. No vendor software is redistributed.
