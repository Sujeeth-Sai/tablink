# TabLink

[![Platform checks](https://github.com/Sujeeth-Sai/tablink/actions/workflows/ci.yml/badge.svg)](https://github.com/Sujeeth-Sai/tablink/actions/workflows/ci.yml)

Use your computer's keyboard and mouse on an Android tablet's **own screen**.
Video mirroring is disabled in both packages.

**Development preview.** The macOS app and Windows control kit have different
interfaces and shortcuts. See [verification status](docs/VERIFICATION.md) before use.

[![Download for macOS](docs/assets/download-macos.svg)](https://github.com/Sujeeth-Sai/tablink/releases/download/v1.4.0-preview.1/TabLink-macOS-1.4.dmg)
[![Download for Windows](docs/assets/download-windows.svg)](https://github.com/Sujeeth-Sai/tablink/releases/download/v1.4.0-preview.1/TabLink-Windows-Control-Setup.zip)

[All release files and checksums](https://github.com/Sujeeth-Sai/tablink/releases/tag/v1.4.0-preview.1)

| | macOS app | Windows control kit |
|---|---|---|
| Computer | Apple silicon, macOS 13+ | Intel/AMD x64, Windows 10/11 |
| Tablet | Android 11+ recommended | Android 11+ |
| USB / Wi-Fi | Both | Both |
| Control | Native Swift app | PowerShell launchers + official scrcpy |
| Switch devices | **Command + Shift + P** | **Left Alt**, then select the PC app |
| Edge handoff | Implemented; final live acceptance pending | Not included |
| Tablet video on computer | Disabled | Disabled; an icon-only capture window remains |
| Setup | [macOS guide](macos/README.md) | [Windows guide](windows-control-kit/README.md) |

## Start here

**macOS:** download the DMG, copy TabLink to your Applications folder, then follow
the [macOS permission and connection guide](macos/README.md). The preview is
locally ad-hoc signed and is not Developer ID notarized.

**Windows:** extract the ZIP and run **Setup.cmd**. Enable USB debugging on the
tablet, approve that PC, and open **TabLink - USB**. For wireless use, open
**TabLink - WiFi**; it discovers addresses and ports and requests Android's
one-time pairing code when needed.

Keep one computer's control session active at a time.

## Source layout

```text
macos/                 Native Swift/AppKit/SwiftUI app and watchdog
windows-control-kit/   Windows setup, connection scripts and tests
docs/                  Download artwork, verification and release notes
.github/workflows/     macOS and Windows checks
```

Runtime dependencies are pinned and downloaded for source builds. Complete
runtime files are included in the downloadable packages, rather than committed
as executable blobs to the source repository.

See [CONTRIBUTING.md](CONTRIBUTING.md) for build and test commands,
[verification](docs/VERIFICATION.md) for what has been checked, and
[release notes](docs/RELEASE-NOTES.md) for the scope of this preview.

## Licenses

The macOS client is under [Apache-2.0](LICENSE). Windows launcher scripts use
[MIT](windows-control-kit/LICENSE-launcher.txt). Bundled scrcpy, ADB and runtime
libraries retain their upstream licenses and notices in each package. This
project is independent of the scrcpy maintainers.
