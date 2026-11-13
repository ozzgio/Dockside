---
name: vendor-display-research
description: Investigates the Cabletime ScreenDock USB Display driver for interoperability using local signatures, USB descriptors, symbols, and controlled observations. Use when explicitly researching a replacement driver or software control of this dock.
---

# Vendor display research

Read `research/VENDOR.md` from the project root before investigating. Work on the user's own dock and installed USB Display app. Dockside 1.2 is a companion app; 1.3 has an experimental native backend. Read `research/native/README.md` and `NOTICE.md` for the known wire protocol and confirmed independent-video proof. Do not infer full driver compatibility from one successful video test.

Run `zsh research/inspect-vendor.sh` from the project root for a read-only, sanitized inventory. The script validates the expected bundle identifier and prints only relevant code-signing, architecture, configuration, and symbol information. It does not send USB commands or change the vendor app.

Separate observations from hypotheses. A symbol name is evidence of an implementation path, not a specification for the protocol. Record the exact app version/hash and reproducible checks with each finding. Do not include USB serial numbers, user desktop captures, vendor binaries, or decompiled vendor code in the public repository.

Start with the smallest unanswered interoperability question: descriptors and endpoints, session handshake, video framing, then known display-control commands. For a dynamic experiment, state which process or interface it affects and preserve the user's working display path. Capture only a synthetic clock/test pattern; logs or packet captures may otherwise contain desktop content.

Do not guess hardware writes, send firmware-update commands, flash firmware, patch signatures, change macOS security settings, or redistribute the vendor app. Stop an experiment if the USB device resets unexpectedly or the display fails to recover. Restore the original driver path and document the result.

For a robust replacement beyond the experimental native preview, verify: vendor processes stopped; independently generated test frame reaches the physical screen; disconnect/reconnect recovers; CPU/latency measurement; and no vendor library embedded in the implementation.
