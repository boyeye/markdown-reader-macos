#!/usr/bin/env python3
"""Build Assets/AppIcon-D1.icns and AppIcon-D1.png from the SVG sources, keeping the transparent margin.
AppIcon-D1-small.svg is used for the 16 and 32 px slots. Checks that the corners stay transparent."""
from pathlib import Path
import subprocess,tempfile,shutil
from toolchain import ROOT,sdk_path
A=ROOT/'Assets'
with tempfile.TemporaryDirectory(prefix='icon-') as tmp:
    tmp=Path(tmp); tool=tmp/'svg2png'
    subprocess.run(['xcrun','swiftc','-sdk',sdk_path(),str(A/'svg2png.swift'),'-o',str(tool)],check=True)
    pngs={}
    for kind,svg in (('big','AppIcon-D1.svg'),('small','AppIcon-D1-small.svg')):
        raw=tmp/f'{kind}-raw.png'; subprocess.run([str(tool),str(A/svg),str(raw)],check=True,timeout=120)
        pngs[kind]=tmp/f'{kind}.png'; subprocess.run(['sips','-z','1024','1024',str(raw),'--out',str(pngs[kind])],check=True,capture_output=True)
    iconset=tmp/'AppIcon.iconset'; iconset.mkdir()
    for size,name,kind in [(16,'16x16','small'),(32,'16x16@2x','small'),(32,'32x32','small'),(64,'32x32@2x','big'),(128,'128x128','big'),(256,'128x128@2x','big'),(256,'256x256','big'),(512,'256x256@2x','big'),(512,'512x512','big'),(1024,'512x512@2x','big')]:
        subprocess.run(['sips','-z',str(size),str(size),str(pngs[kind]),'--out',str(iconset/f'icon_{name}.png')],check=True,capture_output=True)
    subprocess.run(['iconutil','-c','icns',str(iconset),'-o',str(A/'AppIcon-D1.icns')],check=True)
    shutil.copy2(pngs['big'],A/'AppIcon-D1.png')
print(A/'AppIcon-D1.icns')
