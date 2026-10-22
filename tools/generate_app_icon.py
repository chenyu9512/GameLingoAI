#!/usr/bin/env python3
"""Generate the bundled 1024px GameLingo icon using only Python standard library."""
from pathlib import Path
import json, math, struct, zlib
ROOT=Path(__file__).resolve().parents[1]
folder=ROOT/'ios/GameLingoAI/Assets.xcassets/AppIcon.appiconset'
folder.mkdir(parents=True,exist_ok=True)
(folder/'Contents.json').write_text(json.dumps({'images':[{'filename':'AppIcon.png','idiom':'universal','platform':'ios','size':'1024x1024'}],'info':{'author':'xcode','version':1}}))
SIZE=1024

def rr(x,y,cx,cy,w,h,r):
    dx=max(abs(x-cx)-w/2+r,0)
    dy=max(abs(y-cy)-h/2+r,0)
    return math.sqrt(dx*dx+dy*dy)-r

def blend(c,t,k):
    return int(c*(1-k)+t*k)

def chunk(t,p):
    data=t+p
    return struct.pack('!I',len(p))+data+struct.pack('!I',zlib.crc32(data)&0xffffffff)

compressor=zlib.compressobj(7)
data=bytearray()
for y in range(SIZE):
    row=bytearray(b'\x00')
    for x in range(SIZE):
        radial=max(0,1-math.hypot((x-430)/700,(y-365)/720))
        c=[int(4+9*radial),int(12+33*radial),int(30+60*radial)]
        # orbital flare and soft cyan illumination
        d=math.hypot((x-510)/460,(y-535)/335)
        lum=max(0,1-abs(d-1)/0.065)*0.20
        for i,v in enumerate((2,114,232)):
            c[i]=blend(c[i],v,lum)
        # back text card
        back=rr(x,y,627,548,500,510,110)
        if back<5:
            edge=max(0,min(1,(5-back)/7))
            for i,v in enumerate((50,198,222)):
                c[i]=blend(c[i],v,edge)
            if back<-15:
                for i,v in enumerate((16,91,144)):
                    c[i]=blend(c[i],v,0.86)
        # blue main conversation tile
        main=rr(x,y,440,478,510,515,122)
        if main<8:
            edge=max(0,min(1,(8-main)/12))
            for i,v in enumerate((10,221,246)):
                c[i]=blend(c[i],v,edge)
            if main<-19:
                shade=max(0,min(1,(x+y)/1600))
                for i,v in enumerate((7+int(10*shade),47+int(78*shade),91+int(103*shade))):
                    c[i]=blend(c[i],v,0.96)
        # D-pad crossed rectangles, simplified to survive small app icon sizes
        horizontal=rr(x,y,437,485,215,76,25)
        vertical=rr(x,y,437,485,76,215,25)
        if min(horizontal,vertical)<0 and main<0:
            for i,v in enumerate((170,245,255)):
                c[i]=blend(c[i],v,0.98)
        # clean translation bars on the right card
        for bar,wide in ((431,170),(516,158),(602,125)):
            line=rr(x,y,700-(170-wide)/2,bar,wide,25,12)
            if line<0 and main>=0:
                for i,v in enumerate((128,238,247)):
                    c[i]=blend(c[i],v,0.94)
        row.extend((c[0],c[1],c[2],255))
    data.extend(compressor.compress(bytes(row)))
data.extend(compressor.flush())
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('!2I5B',SIZE,SIZE,8,6,0,0,0))+chunk(b'IDAT',bytes(data))+chunk(b'IEND',b'')
(folder/'AppIcon.png').write_bytes(png)
print('Generated GameLingo iOS app icon:',len(png),'bytes')
