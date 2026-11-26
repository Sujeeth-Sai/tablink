#!/usr/bin/env python3
"""Check native watchdog disarm and failure paths without changing user input."""
import json, os, pathlib, subprocess, tempfile, time
ROOT=pathlib.Path(__file__).resolve().parents[1]
EXE=ROOT/'build/TabLink.app/Contents/MacOS/TabLinkWatchdog'
C_SOURCE='#include <CoreGraphics/CoreGraphics.h>\n#include <unistd.h>\nstatic CGError test_associate(boolean_t connected) {if(connected)write(1,"associate\\n",10);return kCGErrorSuccess;}\nstatic CGError test_show(CGDirectDisplayID display) {write(1,"show\\n",5);return kCGErrorSuccess;}\n__attribute__((used)) static const struct {const void *replacement;const void *original;} hooks[] __attribute__((section("__DATA,__interpose")))={\n {(void *)test_associate,(void *)CGAssociateMouseAndMouseCursorPosition},\n {(void *)test_show,(void *)CGDisplayShowCursor}\n};\n'
if not EXE.is_file(): raise SystemExit('Build TabLink first with scripts/build-all.sh')
with tempfile.TemporaryDirectory(prefix='tablink-watchdog-') as tmp:
    folder=pathlib.Path(tmp); source=folder/'interpose.c'; library=folder/'interpose.dylib'
    source.write_text(C_SOURCE)
    subprocess.run(['clang','-dynamiclib',str(source),'-framework','CoreGraphics','-o',str(library)],check=True)
    env={**os.environ,'DYLD_INSERT_LIBRARIES':str(library)}
    def start():
        return subprocess.Popen([str(EXE),str(os.getpid())],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,env=env)
    for cycle in range(100):
        p=start();p.stdin.write(bytes([1,2]));p.stdin.flush();p.stdin.close();p.wait(timeout=2)
        assert p.returncode==0 and p.stdout.read()==b'', 'Disarmed watchdog restored cursor'
    p=start();p.stdin.write(bytes([1]));p.stdin.flush();p.stdin.close();p.wait(timeout=2)
    assert p.stdout.read()==b'associate\nshow\n', 'EOF did not restore cursor'
    p=start();p.stdin.write(bytes([1]));p.stdin.flush();before=time.monotonic();p.wait(timeout=2)
    elapsed=time.monotonic()-before
    assert p.stdout.read()==b'associate\nshow\n' and elapsed<1.2, 'Stall recovery failed'
    print(json.dumps({'disarmed_handoffs':100,'eof_restored':True,'stall_restored':True,'stall_seconds':round(elapsed,3)},indent=2))
