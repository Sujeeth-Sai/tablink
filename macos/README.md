# TabLink for macOS

[![Download for macOS](../docs/assets/download-macos.svg)](https://github.com/Sujeeth-Sai/tablink/releases/download/v1.4.0-preview.1/TabLink-macOS-1.4.dmg)

Native Swift/AppKit/SwiftUI development build **1.4** for Apple silicon and
macOS 13+. Control the physical Android tablet with the Mac keyboard and
trackpad. The server runs with `video=false audio=false`; no tablet mirror is
opened on the Mac.

## Install and connect

1. Download and mount the DMG. Copy **TabLink.app** into `~/Applications`.
2. Unlock the Android tablet. Enable Developer options and **USB debugging**.
3. Connect a USB data cable and approve the tablet's authorization prompt.
4. Open TabLink. Enable its **Accessibility** grant when macOS requests it.
   Newer macOS versions call this **Device Control and Data Access**.
5. Click **Connect & control**. Mac keyboard and trackpad input then goes to
   the tablet's own screen.

This preview is ad-hoc signed, not Developer ID signed/notarized. Gatekeeper
may block it on another Mac. Source builds are available below. Rebuilding may
require macOS to refresh its input-control permission.

## Switch control

- **Command + Shift + P:** toggle between Mac and tablet control.
- **Control + Option + Command + Escape:** emergency return to the Mac.
- **Control + Option + Command + T:** previous toggle remains available.
- **Edges:** select the tablet's side in Settings. Right is the default. Pause
  at the matching Mac edge to enter; push back across the adjoining tablet
  edge or pause at a tablet corner to return.

The Android mouse remains registered during a connection. Input is forwarded
only while the tablet owns control. The hidden Mac pointer is anchored and
independent watchdogs restore input after a failure.

Edge and shortcut logic is implemented, but the final rebuilt binary's live
handoff acceptance remains unverified. See [verification](../docs/VERIFICATION.md).

## Wi-Fi

Keep both devices on the same private Wi-Fi. Enable Android **Wireless
debugging**, then click **Connect over Wi-Fi** in TabLink. Android may require
one pairing code for this Mac. TabLink resolves addresses and ports internally.
Allow **Local Network** access if macOS asks.

## Build from source

Use macOS with Swift 5.9+ and Python 3. The release was built using Swift 6.4.2.

```sh
cd macos
python3 scripts/fetch-resources.py
./scripts/build-all.sh
./scripts/install.sh
```

`fetch-resources.py` downloads pinned ADB 37.0.3 and the unmodified Apache-2.0
scrcpy 3.3.4 Android server, verifying SHA-256 before use. Java and the Android
SDK are not required on the computer.

```sh
./scripts/test-core.sh
./scripts/check-watchdog-disarm.py
```

The normal control app does not instantiate the retained historical video
decoder/mirror code. The wire contract is documented in
[protocol/PROTOCOL.md](protocol/PROTOCOL.md).
