"""Shared swiftc invocation for build.py and test.py."""
from pathlib import Path
import os,re,subprocess
ROOT=Path(__file__).resolve().parent
VERSION='1.2'
BUILD='12'

def sdk_path():
    """Command Line Tools ship no SwiftUI macro plugin, but macOS 27+ SDKs implement @State as a macro.
    Without Xcode, fall back to the newest installed pre-27 SDK. READER_SDK overrides the choice."""
    if os.environ.get('READER_SDK'): return os.environ['READER_SDK']
    dev=Path(subprocess.run(['xcode-select','-p'],capture_output=True,text=True,check=True).stdout.strip())
    default=Path(subprocess.run(['xcrun','--show-sdk-path'],capture_output=True,text=True,check=True).stdout.strip())
    plugins=dev/'usr/lib/swift/host/plugins'
    if 'CommandLineTools' not in str(dev) or any(plugins.glob('*SwiftUIMacros*')): return str(default)
    versions=[]
    for sdk in (dev/'SDKs').glob('MacOSX*.*.sdk'):
        m=re.fullmatch(r'MacOSX(\d+)\.(\d+)\.sdk',sdk.name)
        if m and int(m[1])<27: versions.append(((int(m[1]),int(m[2])),sdk))
    return str(max(versions)[1]) if versions else str(default)

def swiftc(sources,output,*flags):
    subprocess.run(['xcrun','swiftc','-sdk',sdk_path(),'-parse-as-library','-target','arm64-apple-macos13.0','-module-cache-path',str(ROOT/'ModuleCache'),*flags,*map(str,sources),'-o',str(output)],check=True)

TOKENS=['__NONCE__','__MARKED__','__PURIFY__','__HIGHLIGHT__','__KATEX_CSS__','__KATEX__','__MERMAID__']
def check_template():
    """Reader.swift fills these tokens by plain string replacement, so no bundled file may contain one and
    each content token must appear exactly once in the template."""
    html=(ROOT/'Resources/reader.html').read_text()
    for t in TOKENS[1:]: assert html.count(t)==1, f'reader.html must contain {t} exactly once'
    for f in (ROOT/'Resources/vendor').iterdir():
        if f.suffix in ('.js','.css'):
            text=f.read_text(errors='ignore')
            assert not any(t in text for t in TOKENS), f'{f.name} contains a template token'
