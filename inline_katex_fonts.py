#!/usr/bin/env python3
"""Write Resources/vendor/katex.css from a KaTeX dist directory, embedding the woff2 fonts as data URIs.
The reader's CSP allows fonts only from data: URIs. Usage: python3 inline_katex_fonts.py <katex>/dist"""
from pathlib import Path
import base64,re,sys
dist=Path(sys.argv[1]); out=Path(__file__).resolve().parent/'Resources/vendor/katex.css'
def face(m):
    srcs=re.findall(r'url\(fonts/([^)]+\.woff2)\) format\("woff2"\)',m[0])
    data=base64.b64encode((dist/'fonts'/srcs[0]).read_bytes()).decode()
    return re.sub(r'src:[^;}]+',f'src:url(data:font/woff2;base64,{data}) format("woff2")',m[0])
css=re.sub(r'@font-face\{[^}]*\}',face,(dist/'katex.min.css').read_text())
assert 'url(fonts/' not in css
out.write_text(css); print(out,len(css))
