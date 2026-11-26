# Build and verification

Keep the platform boundaries explicit: `macos/` is the native app;
`windows-control-kit/` is a scrcpy-based launcher kit. Do not describe the
Windows kit as having the Mac app's edge-handoff or global shortcut features.

## macOS

```sh
cd macos
python3 scripts/fetch-resources.py
./scripts/build-all.sh
./scripts/check-watchdog-disarm.py
```

The build runs core tests and independent protocol vectors before compiling.
The watchdog test interposes cursor-restoration functions, so it does not
change real input state. Live hardware tests need an authorized Android tablet
and macOS input permission; they are not part of unattended CI.

## Windows

```powershell
cd windows-control-kit
.\scripts\Get-Runtime.ps1
.\scripts\New-FileManifest.ps1
.\tests\Test-Scripts.ps1
.\scripts\Install.ps1
```

Use Windows PowerShell 5.1 as the compatibility baseline. Runtime downloads
are pinned to official upstream SHA-256 values. Regenerate `FILES.sha256`
after changing package files and before testing Setup.cmd.

## Publishing

Installers belong in GitHub Releases. Do not commit `.build`, `build`, runtime
executables, local pairing keys, private certificates, environment files or raw
device logs. Publish checksums alongside releases and label unverified
hardware behavior accurately. Update the root and per-platform download
buttons together when changing release tags or filenames.
