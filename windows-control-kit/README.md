[![Download for Windows](../docs/assets/download-windows.svg)](https://github.com/Sujeeth-Sai/tablink/releases/download/v1.4.0-preview.1/TabLink-Windows-Control-Setup.zip)

# Tablet control setup for Windows

This package is for **Windows 10/11 on Intel/AMD 64-bit PCs** and an Android 11+
tablet. It bundles the official scrcpy 5.0.1 Windows release and setup/connection
scripts. It is a Windows control kit, **not a Windows port of the native Mac
TabLink app**. Automatic screen-edge switching and Command + Shift + P are not
included. Use **Left Alt** to release the cursor.

## Install

1. Copy `TabLink-Windows-Control-Setup.zip` to the Windows PC.
2. Right-click the ZIP, choose **Extract All**, and open the extracted folder.
3. Double-click **Setup.cmd**. It checks the files, installs into
   `%LOCALAPPDATA%\Programs\TabLink-Windows-Control`, and creates desktop and
   Start menu shortcuts. The application copy does not require administrator rights.
4. Keep the extracted folder until setup finishes. You can also use
   `Start-USB.cmd`, `Connect-WiFi.cmd`, or `Open-Menu.cmd` directly without installing.

## First USB connection

1. On the tablet, enable **Developer options**. Usually this means opening
   **Settings > About tablet** and tapping **Build number** seven times.
2. Enable **USB debugging** in Developer options.
3. Connect the unlocked tablet to the Windows PC with a **USB data cable**.
4. Approve **Allow USB debugging** on the tablet. A Windows PC needs its own
   authorization even if you previously authorized your Mac.
5. Open the desktop shortcut **TabLink - USB**.
6. Click the small **Tablet control** window to capture input. Look at and use
   the tablet's physical screen.

Video and audio forwarding are disabled. The small Windows capture window
contains an icon, not a mirror of the tablet. Keep this window open and focused
while controlling the tablet. The provided launchers use scrcpy's documented
[control-only mode](https://github.com/Genymobile/scrcpy/blob/v5.0.1/doc/control.md).

## Switch between Windows and the tablet

- **Return to Windows:** press **Left Alt**, then click the Windows app you want.
- **Resume tablet control:** click the **Tablet control** window again.
- **Disconnect:** release the cursor with Left Alt, then close the control window.
- **Keyboard layout:** if symbols are wrong, open the tablet's physical-keyboard
  settings and choose the layout matching your PC keyboard.

The backend captures the PC mouse while controlling the tablet; its pointer
appears on Android. Left Alt releases that capture. See the upstream
[mouse-control documentation](https://github.com/Genymobile/scrcpy/blob/v5.0.1/doc/mouse.md).

## Wi-Fi setup

1. Connect the Windows PC and tablet to the **same private Wi-Fi network**.
2. On the tablet, enable **Developer options > Wireless debugging** and approve
   the network if Android asks.
3. Open **TabLink - WiFi** on the PC. Already paired tablets are discovered and
   connected automatically.
4. For the first connection to this PC, choose **Pair device with pairing code**
   on the tablet. When the Windows launcher asks, press Enter and enter the
   tablet's **six-digit code**.
5. The script discovers the pairing and connection ports itself and starts
   tablet control. You do not enter an IP address or a port.
6. On later connections, use **TabLink - WiFi** again. Keep Wireless debugging
   enabled. If Android disables it after a restart or network change, enable it again.

Pairing is specific to this Windows PC. Android requires initial authorization;
this kit does not copy your Mac's pairing credentials. Wireless setup follows
[Android's ADB pairing flow](https://developer.android.com/tools/adb#connect-to-a-device-over-wi-fi).

## If something does not connect

- **Unauthorized:** unlock the tablet and approve the USB debugging prompt.
- **No USB device:** try another data cable/USB port. Check Device Manager. If
  an ADB driver is missing, use Windows Update or your tablet manufacturer's
  official driver. Android maintains an
  [OEM driver guide](https://developer.android.com/studio/run/oem-usb).
- **Wi-Fi discovery finds nothing:** keep the pairing-code screen open during
  initial pairing. If Windows asks about `adb`, allow it on your trusted
  **Private** network. Guest/company Wi-Fi may block discovery.
- **Several tablets:** choose the tablet by number when prompted. For initial
  pairing, leave the pairing screen open on only the tablet you want.
- **Still stuck:** open **TabLink - Menu**, choose **Diagnostics**, and read the
  device authorization state. No database, MySQL, Java or Android Studio setup
  is required for this kit.

## Remove

Close the control window. Run **Uninstall.cmd** and type **YES** to move the
installed files and matching shortcuts to the Recycle Bin. Shared Android ADB
pairing keys are retained. To revoke the PC's tablet access, forget that PC in
Android's Wireless debugging paired-device list.

## What was verified

The bundled Windows archive was downloaded from the official project and checked
against its published SHA-256. Packaged runtime files are unchanged. Script
syntax and connection-parsing/argument-quoting checks are recorded in
`VERIFICATION.txt`. **A Windows PC is not attached here, so installation and live
Windows keyboard/mouse control have not been tested.**

Official backend: [scrcpy 5.0.1 release](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1).

## Build this kit from source

On Windows PowerShell 5.1 or newer:

```powershell
cd windows-control-kit
.\scripts\Get-Runtime.ps1
.\scripts\New-FileManifest.ps1
.\tests\Test-Scripts.ps1
.\Setup.cmd
```

The release ZIP already includes runtime files; these extra fetch steps are for source checkouts.
