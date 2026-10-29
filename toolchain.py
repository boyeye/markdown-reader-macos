"""Shared swiftc invocation for build.py and test.py."""
from pathlib import Path
import os,re,subprocess
ROOT=Path(__file__).resolve().parent
VERSION='1.1'
BUILD='11'

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
