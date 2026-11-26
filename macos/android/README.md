# Android backend

This native client uses the unmodified scrcpy 3.3.4 server, pinned in
`../Resources/dependencies.json`. Fetch it with `python3 scripts/fetch-resources.py`
from the macOS source directory. Upstream source:
https://github.com/Genymobile/scrcpy/tree/v3.3.4/server

This repository does not claim to contain a separately implemented Gradle APK.
The server is pushed and launched through authorized ADB when connecting.
