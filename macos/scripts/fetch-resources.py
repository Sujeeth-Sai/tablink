#!/usr/bin/env python3
"""Fetch the exact public upstream binaries used by this development build."""
from pathlib import Path
import hashlib,io,json,os,urllib.request,zipfile
ROOT=Path(__file__).resolve().parents[1]
RES=ROOT/'Resources'
META=json.loads((RES/'dependencies.json').read_text())
def download(url,expected):
    req=urllib.request.Request(url,headers={'User-Agent':'TabLink-build'})
    data=urllib.request.urlopen(req,timeout=90).read()
    if hashlib.sha256(data).hexdigest()!=expected:
        raise SystemExit('Checksum mismatch; refusing dependency: '+url)
    return data
jar=META['scrcpy-server']
server=RES/'scrcpy-server.jar'
if not server.exists() or hashlib.sha256(server.read_bytes()).hexdigest()!=jar['sha256']:
    server.write_bytes(download(jar['url'],jar['sha256']))
adb=META['adb'];target=RES/'adb';lib=RES/'lib64/libc++.dylib'
if (not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest()!=adb['sha256']
    or not lib.exists() or hashlib.sha256(lib.read_bytes()).hexdigest()!=adb['libcxx_sha256']):
    data=download(adb['url'],adb['archive_sha256'])
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        executable=archive.read('platform-tools/adb');library=archive.read('platform-tools/lib64/libc++.dylib')
    assert hashlib.sha256(executable).hexdigest()==adb['sha256']
    assert hashlib.sha256(library).hexdigest()==adb['libcxx_sha256']
    target.write_bytes(executable);lib.parent.mkdir(exist_ok=True);lib.write_bytes(library)
    target.chmod(0o755);lib.chmod(0o755)
print('Pinned Android server and macOS platform tools verified.')
