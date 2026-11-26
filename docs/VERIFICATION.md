# Verification status

This is a development preview, not a claim that every release gate has passed.

## macOS 1.4

Observed locally on Apple silicon:

- Native release build and code-signature integrity passed.
- 25 core tests / 143 assertions and six independent protocol vectors passed.
- 100 native watchdog disarm/close checks passed. EOF and stalled-parent
  recovery remained available.
- Cursor-overlay lifecycle and foreground-ownership checks were exercised.
- Earlier input-only builds completed physical tablet-corner and Wi-Fi checks.
  Those earlier results do not certify the final rebuilt app.

**Still unverified:** final binary's live edge and Command + Shift + P
acceptance, Developer ID/notarization, Intel/older-OS coverage, measured latency,
and an eight-hour soak. The downloadable macOS binary is arm64 and ad-hoc signed.

## Windows control kit 1.0.0

Before publication:

- The official scrcpy 5.0.1 Windows archive matched its published SHA-256.
- All 16 bundled runtime files matched the upstream archive byte-for-byte.
- The client was confirmed to be an x64 Windows PE executable.
- 52 PowerShell parser, endpoint/device/service parsing, argument-quoting,
  process-pipe and timeout assertions passed on macOS with PowerShell 7.7.
- The setup archive and per-file manifest were verified.

Hosted [platform checks passed on 26 November 2026](https://github.com/Sujeeth-Sai/tablink/actions/runs/45758080841):

- macOS: pinned runtime retrieval, core/protocol tests, release build and watchdog regression.
- Windows: PowerShell 5.1 checks, native ADB/scrcpy startup, per-user installation
  and all three desktop shortcuts.

**Still unverified:** physical Windows keyboard/mouse capture and Windows
Wi-Fi pairing. A hosted runner does not replace testing with a physical tablet.

## Records

Raw device logs, desktop captures, local credential files and personal machine
paths are excluded. Tests and reproduction commands are included in source.
