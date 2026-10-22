#!/usr/bin/env python3
"""Generate an offline GameLingo iOS AppIcon, without third-party packages."""
import json, math, struct, zlib
from pathlib import Path

W = H = 1024
out = Path(__file__).resolve().parents[1] / "ios/GameLingoAI/Assets.xcassets/AppIcon.appiconset"
out.mkdir(parents=True, exist_ok=True)
(out / "Contents.json").write_text(json.dumps({"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}))

def rr(x,y,cx,cy,w,h,r):
    dx=max(abs(x-cx)-w/2+r,0);dy=max(abs(y-cy)-h/2+r,0)
    return math.hypot(dx,dy)-r

def chunk(k,v):
    b=k+v
    return struct.pack("!I",len(v))+b+struct.pack("!I",zlib.crc32(b)&0xffffffff)

z=zlib.compressobj(7)
pixels=bytearray()
for y in range(H):
    row=bytearray(b"\x00")
    for x in range(W):
        radial=max(0,1-math.hypot((x-430)/700,(y-365)/720))
        rgb=[int(4+9*radial),int(12+33*radial),int(30+60*radial)]
        def paint(rgb,color,alpha):
            return [int(a*(1-alpha)+b*alpha) for a,b in zip(rgb,color)]
        ring=math.hypot((x-510)/460,(y-535)/335)
        rgb=paint(rgb,(2,114,232),max(0,1-abs(ring-1)/0.065)*0.2)
        back=rr(x,y,627,548,500,510,110)
        if back<5:
            rgb=paint(rgb,(50,198,222),max(0,min(1,(5-back)/7)))
            if back<-15: rgb=paint(rgb,(16,91,144),0.86)
        main=rr(x,y,440,478,510,515,122)
        if main<8:
            rgb=paint(rgb,(10,221,246),max(0,min(1,(8-main)/12)))
            if main<-19:
                shade=max(0,min(1,(x+y)/1600))
                rgb=paint(rgb,(7+int(10*shade),47+int(78*shade),91+int(103*shade)),0.96)
        if min(rr(x,y,437,485,215,76,25),rr(x,y,437,485,76,215,25))<0 and main<0:
            rgb=paint(rgb,(170,245,255),0.98)
        for height,width in ((431,170),(516,158),(602,125)):
            if rr(x,y,700-(170-width)/2,height,width,25,12)<0 and main>=0:
                rgb=paint(rgb,(128,238,247),0.94)
        row.extend((*rgb,255))
    pixels.extend(z.compress(bytes(row)))
pixels.extend(z.flush())
data=(b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack("!2I5B",W,H,8,6,0,0,0))
      +chunk(b"IDAT",bytes(pixels))+chunk(b"IEND",b""))
(out/"AppIcon.png").write_bytes(data)
print("GameLingo icon generated:",len(data),"bytes")
