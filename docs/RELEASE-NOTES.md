# v1.4.0-preview.1

First organized public preview containing two distinct packages.

## macOS: native TabLink 1.4

- Input-only control of the physical Android tablet; video/audio disabled.
- Command + Shift + P toggle and the existing emergency return shortcut.
- Timer-driven edge entry and tablet-position feedback for adjoining-edge return.
- Cursor-overlay ownership, foreground capture and watchdog handback fixes.
- Wi-Fi discovery and one-time Android pairing-code flow.

The final rebuilt binary still requires live handoff acceptance testing and
Developer ID/notarization. It is provided as an ad-hoc-signed development build.

## Windows: control kit 1.0.0

- Official scrcpy 5.0.1 runtime with no video/audio forwarding.
- Per-user Setup.cmd, USB/Wi-Fi launchers and uninstall support.
- Automatic endpoint discovery and one-time pairing-code input.
- Left Alt releases mouse capture; the icon-only control window remains open.

This is not a native Windows port of TabLink. Mac edge crossing and Command +
Shift + P are not included. Windows hardware control has not been verified. Hosted Windows script, executable
startup, installer and shortcut checks passed; see the verification record.

## Downloads

The release contains a macOS DMG, complete Windows setup ZIP, clean source
snapshot, and SHA256SUMS.txt. Source checkouts fetch runtime dependencies using
pinned checksums; downloaded installers already include their required runtime.
