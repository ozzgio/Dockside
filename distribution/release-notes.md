Dockside 1.3 adds experimental native USB for the tested Cabletime ScreenDock (`1de1:f201`), alongside more dashboard customization.

Enable **Control Center → Power and driver → Use Dockside native USB (experimental)** to send Dockside directly to the panel with USB Display stopped. This mode renders the 1280 × 720 dashboard, supports mouse controls, and uses native H.264 encoding. It does not stream arbitrary applications or the Mac menu bar. **Open USB Display** remains the explicit companion-mode fallback.

Focus is optional and off by default. Three starting layouts, individual widget toggles, clock sizing, seven themes, and custom app shortcuts are saved locally. The padded clock regression checks remain in place.

This is a developer preview, ad-hoc signed and **not notarized**. The universal build targets macOS 14+; physical native USB testing is limited to macOS 27.0.1 Apple Silicon and one dock. The native virtual display uses a private Apple API that may change. Sleep/wake and older physical systems are not yet verified. Keep the factory app installed while evaluating native USB.

Source is public; the project license is undecided. The MIT notice for the protocol reference is included in the source and app bundle. No vendor software is redistributed.
