#!/usr/bin/env python3
"""Live safety check: briefly holds virtual Shift, then stops heartbeat pulses.
Requires an authorized Android tablet. Destroys only its own test HID devices.
"""
import json,pathlib,re,socket,struct,subprocess,time,sys
root=pathlib.Path(__file__).resolve().parents[1];adb=str(root/'Resources/adb')
serial=sys.argv[1] if len(sys.argv)>1 else None
if not serial:
 for line in subprocess.check_output([adb,'devices']).decode().splitlines()[1:]:
  p=line.split()
  if len(p)>1 and p[1]=='device':serial=p[0];break
if not serial:raise SystemExit('Connect and authorize the tablet first.')
def run(*args):return subprocess.check_output([adb,'-s',serial,*args],stderr=subprocess.STDOUT,timeout=10).decode()
def exact(s,n):
 b=b''
 while len(b)<n:
  x=s.recv(n-len(b))
  if not x:raise EOFError()
  b+=x
 return b
scid='2b3c4d5e';remote='/data/local/tmp/tablink-'+scid+'.jar';marker='/data/local/tmp/tablink-'+scid+'.alive'
run('push',str(root/'Resources/scrcpy-server.jar'),remote)
port=int(run('forward','tcp:0','localabstract:scrcpy_'+scid).strip())
options=f'3.3.4 scid={scid} audio=false video=false tunnel_forward=true clipboard_autosync=false'
command=f"touch {marker}; CLASSPATH={remote} app_process / com.genymobile.scrcpy.Server {options} & child=$!; (while kill -0 $child 2>/dev/null; do sleep 1; now=$(date +%s); stamp=$(stat -c %Y {marker} 2>/dev/null || echo 0); if [ $((now-stamp)) -ge 3 ]; then kill $child; break; fi; done) & guardpid=$!; trap 'kill $child $guardpid 2>/dev/null; rm -f {marker} {remote}' EXIT HUP INT TERM; wait $child"
p=subprocess.Popen([adb,'-s',serial,'shell',command],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
s=None;results={}
try:
 for _ in range(35):
  try:
   s=socket.create_connection(('127.0.0.1',port),timeout=2);s.settimeout(6)
   if exact(s,1)==b'\0':break
   s.close()
  except (OSError,EOFError):time.sleep(.1)
 exact(s,64)
 source=(root/'Sources/TabLinkCore/Protocol.swift').read_text()
 for id,label,key in [(1,'Mouse','mouse'),(2,'Keyboard','keyboard')]:
  desc=bytes(int(x.strip(),0) for x in re.search(r'public static let '+key+r' = Data\(\[([^]]+)\]',source)[1].split(','))
  name=('TabLink Guard Check '+label).encode()
  s.sendall(bytes([12])+struct.pack('>HHHB',id,0,0,len(name))+name+struct.pack('>H',len(desc))+desc)
 time.sleep(.3)
 s.sendall(bytes([13])+struct.pack('>HH',2,8)+bytes([2,0,0,0,0,0,0,0]))
 before=run('shell','dumpsys','input')
 results['hid_present_before_loss']='TabLink Guard Check Keyboard' in before
 run('shell','touch',marker);start=time.monotonic()
 # Stop pulses, keep the control socket open: only the Android watchdog can release input.
 p.wait(timeout=6);results['server_exit_after_heartbeat_loss_seconds']=round(time.monotonic()-start,3)
 after=run('shell','dumpsys','input')
 results['test_hid_removed_after_loss']='TabLink Guard Check Keyboard' not in after and 'TabLink Guard Check Mouse' not in after
 try:results['control_socket_closed']=s.recv(1)==b''
 except (ConnectionResetError,OSError):results['control_socket_closed']=True
 results['passed']=results['hid_present_before_loss'] and results['test_hid_removed_after_loss'] and results['control_socket_closed'] and results['server_exit_after_heartbeat_loss_seconds']<4.5
 print(json.dumps(results,indent=2))
 if not results['passed']:raise SystemExit(1)
finally:
 if s:s.close()
 if p.poll() is None:p.terminate()
 run('forward','--remove','tcp:'+str(port))
 run('shell','rm','-f',marker,remote)
