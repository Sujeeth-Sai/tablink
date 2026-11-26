# Version 1.1 active mode: input only

The normal app now launches with `video=false audio=false`. It opens exactly
one CONTROL socket. That socket first yields a dummy NUL byte and 64-byte
NUL-padded device name, then uses the control messages documented below.
There is no video header, frame stream, screen encoder or Mac mirror window.
Screen geometry comes from the main INTERNAL logical viewport in `dumpsys input`,
polled alongside the one-second ADB heartbeat. Rotation rescales the tracked
pointer position while preserving REMOTE state. The video section below is
retained only to document the historical 1.0 diagnostic implementation.

# TabLink wire contract

This executable intentionally uses the pinned **scrcpy 3.3.4** server and its actual protocol. It does not claim wire compatibility with the PDF's proposed TabLink v1 server. See docs/decisions/001-server-reuse.md. Never replace the server jar with another version independently of this client.

Upstream source of truth: https://github.com/Genymobile/scrcpy/tree/v3.3.4/server/src/main/java/com/genymobile/scrcpy/control
Server SHA-256: `8588238c9a5a00aa542906b6ec7e6d5541d9ffb9b5d0f6e1bc0e365e2303079e`.

All outer integers are big endian. HID report contents are little endian, as specified by USB HID.

## Connection

Push the server jar to a unique `/data/local/tmp/tablink-<scid>.jar`. Allocate `adb forward tcp:0 localabstract:scrcpy_<scid>`. Launch `app_process / com.genymobile.scrcpy.Server 3.3.4` with `audio=false tunnel_forward=true`. VIDEO connects first, consumes a dummy NUL byte, then CONTROL connects. VIDEO then receives 64-byte NUL-padded UTF-8 device name, codec u32 (`h264`), width u32, height u32. Sockets bind only to loopback on the Mac and an abstract local socket on Android.

## Video

Each packet is flags/PTS u64, payload length u32, Annex B payload. Bit 63 is codec config, bit 62 is keyframe, low 62 bits are microsecond PTS. Length is restricted to 32 MiB. Codec config carries SPS/PPS. Rotation produces new SPS/PPS, whose dimensions replace the old display size; there is no custom bit-61 reset packet in this implementation. VideoToolbox decodes every reference frame. Only stale **decoded** frames are dropped before display.

## Mac to tablet

| Type | Message | Payload |
|---|---|---|
| 0 | KEY | action u8 (0 down, 1 up), keycode i32, repeat u32, metastate u32 |
| 1 | TEXT | UTF-8 byte count u32, bytes; at most 300 bytes |
| 2 | TOUCH | action u8, pointer u64, x i32, y i32, width u16, height u16, pressure u16, actionButton u32, buttons u32 |
| 3 | SCROLL | x i32, y i32, width u16, height u16, hscroll i16, vscroll i16, buttons u32 |
| 4 | BACK_OR_SCREEN_ON | action u8 |
| 8 | GET_CLIPBOARD | copyKey u8 |
| 9 | SET_CLIPBOARD | sequence u64, paste u8, UTF-8 length u32, bytes (maximum 262130) |
| 10 | SET_DISPLAY_POWER | on u8 |
| 11 | ROTATE_DEVICE | empty |
| 12 | UHID_CREATE | id u16, vendor u16, product u16, name length u8, name, descriptor length u16, descriptor |
| 13 | UHID_INPUT | id u16, size u16, report |
| 14 | UHID_DESTROY | id u16 |
| 17 | RESET_VIDEO | empty |

SCROLL is signed fixed point: one notch = 2048, representable range [-16,16). This differs from the PDF's proposed 1/16-notch units. Pressure 0xffff represents full pressure. Mouse report: buttons u8; dx i16 LE; dy i16 LE; vertical wheel i8; horizontal pan i8. Keyboard: modifier u8, reserved u8, six USB usages; LED output is accepted from the server.

## Tablet to Mac

0 CLIPBOARD: length u32, UTF-8. 1 CLIPBOARD_ACK: sequence u64. 2 UHID_OUTPUT: id u16, size u16, report. Unknown types terminate the session safely. Clipboard is bounded at 256 KiB and never written to diagnostics.

## Liveness and cleanup

There is no protocol HEARTBEAT type in upstream 3.3.4. The Mac touches a unique Android heartbeat file every second through ADB. An independent Android shell watchdog kills the specific Java server PID after three seconds without a pulse; process exit closes UHID file descriptors and releases held input. The Mac restores local routing on any failed heartbeat (800ms timeout), device removal, socket closure, app termination, disabled event tap, or emergency shortcut. A separate native watchdog process restores cursor association after parent death, EOF, or a 900ms parent stall. It never captures input.

## Shared vectors

`vectors/*.hex` are independently generated, unspaced lowercase bytes. XCTest compares client encoders against them. `scripts/check-vectors.py` decodes them independently using Python struct. The reused Java reader is upstream-tested; a custom Java/JUnit suite is not included and is not claimed.
