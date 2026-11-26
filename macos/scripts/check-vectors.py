#!/usr/bin/env python3
"""Independent decoder checks against shared protocol fixtures."""
from pathlib import Path
import struct
root=Path(__file__).resolve().parents[1]/'protocol/vectors'
def vector(name): return bytes.fromhex((root/(name+'.hex')).read_text())
b=vector('key-a-down');assert b[0]==0 and struct.unpack('>BiII',b[1:])==(0,29,0,0)
b=vector('text-hello');assert b[0]==1 and struct.unpack('>I',b[1:5])[0]==5 and b[5:].decode()=='hello'
b=vector('clipboard-unicode');assert b[0]==9 and struct.unpack('>QB',b[1:10])==(42,1) and b[14:].decode()=='Hi 🌍' and struct.unpack('>I',b[10:14])[0]==len(b[14:])
b=vector('mouse-relative');assert b[0]==13 and struct.unpack('>HH',b[1:5])==(1,7) and struct.unpack('<Bhhbb',b[5:])==(1,-300,500,-1,2)
b=vector('touch-down');assert b[:2]==bytes([2,0]) and struct.unpack('>QiiHHHII',b[2:])==(2**64-1,100,200,1920,1080,65535,1,1)
b=vector('scroll');assert b[0]==3 and struct.unpack('>iiHHhhI',b[1:])==(100,200,1920,1080,2048,-2048,0)
print('6 shared protocol vectors passed (independent Python decoder).')
