#!/usr/bin/env python3
"""Build an offline Apple Silicon macOS reader using Command Line Tools."""
from pathlib import Path
import plistlib,subprocess,shutil
from toolchain import swiftc,VERSION,BUILD
ROOT=Path(__file__).resolve().parent
APP=ROOT/'MarkdownReader.app'
contents=APP/'Contents'; binary=contents/'MacOS'; resources=contents/'Resources'
binary.mkdir(parents=True,exist_ok=True);resources.mkdir(exist_ok=True)
swiftc([ROOT/'Reader.swift'],binary/'MarkdownReader','-O')
shutil.copytree(ROOT/'Resources',resources,dirs_exist_ok=True)
shutil.copy2(ROOT/'Assets/AppIcon-D-down.icns',resources/'AppIcon.icns')
info={'CFBundleInfoDictionaryVersion':'6.0','CFBundleExecutable':'MarkdownReader','CFBundleIdentifier':'local.philips.markdownreader','CFBundleName':'MarkdownReader','CFBundleDisplayName':'Markdown 查看器','CFBundlePackageType':'APPL','CFBundleVersion':BUILD,'CFBundleShortVersionString':VERSION,'LSMinimumSystemVersion':'13.0','NSHighResolutionCapable':True,'CFBundleIconFile':'AppIcon.icns','CFBundleDocumentTypes':[{'CFBundleTypeName':'Markdown 文档','CFBundleTypeRole':'Viewer','LSHandlerRank':'Alternate','LSItemContentTypes':['net.daringfireball.markdown','public.plain-text'],'CFBundleTypeExtensions':['md','markdown','mdown','mkd','txt']}],'UTImportedTypeDeclarations':[{'UTTypeIdentifier':'net.daringfireball.markdown','UTTypeDescription':'Markdown 文档','UTTypeConformsTo':['public.plain-text'],'UTTypeTagSpecification':{'public.filename-extension':['md','markdown','mdown','mkd'],'public.mime-type':'text/markdown'}}]}
(contents/'Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['codesign','--force','--sign','-',str(APP)],check=True)
subprocess.run(['codesign','--verify','--strict','--verbose=2',str(APP)],check=True)
print(APP)
