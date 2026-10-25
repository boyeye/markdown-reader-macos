#!/usr/bin/env python3
from pathlib import Path
import tempfile,subprocess,plistlib,hashlib
root=Path(__file__).resolve().parent
out=root/'dist';out.mkdir(exist_ok=True)
dmg=out/'MarkdownViewer-1.0-arm64.dmg'
if dmg.exists(): raise SystemExit('DMG already exists; move it aside before rebuilding.')
with tempfile.TemporaryDirectory(prefix='markdown-dmg-') as tmp:
    stage=Path(tmp)
    subprocess.run(['ditto',str(root/'MarkdownReader.app'),str(stage/'Markdown 查看器.app')],check=True)
    (stage/'Applications').symlink_to('/Applications',target_is_directory=True)
    (stage/'使用说明.txt').write_text('''Markdown 查看器 1.0

安装：将 Markdown 查看器.app 拖入 Applications（应用程序），再从应用程序打开。
适用于 Apple Silicon（M 系列）Mac，macOS 13 或更新版本。Intel Mac 不适用。
未使用付费 Developer ID 签名，未经 Apple 公证；若首次启动被拦截，在尝试打开后前往“系统设置 → 隐私与安全性 → 仍要打开”，仅对你信任的本安装包操作。

功能：打开或拖入 .md/.markdown/.txt；Finder 打开方式；目录导航；代码高亮；表格与任务列表；本地图片；查找；源码查看；主题和字号；最近打开；PDF 导出。
快捷键：⌘O 打开，⌘F 查找，⌘R 重新载入。文档修改后手动重新载入。
本地图片支持文档目录及其子目录中的 PNG/JPG/GIF/WebP/HEIC/AVIF；不加载远程图片、SVG 或目录外图片。网页链接交由系统浏览器打开。
仅阅读，不修改源文件。单文件上限 5 MB，本地单张图片上限 20 MB。
第三方组件与许可证位于应用包 Contents/Resources/vendor。
''')
    subprocess.run(['hdiutil','create','-volname','Markdown 查看器','-srcfolder',str(stage),'-format','UDZO','-o',str(dmg)],check=True)
subprocess.run(['hdiutil','verify',str(dmg)],check=True)
result=subprocess.run(['hdiutil','attach','-readonly','-nobrowse','-plist',str(dmg)],check=True,capture_output=True)
mounts=[e['mount-point'] for e in plistlib.loads(result.stdout)['system-entities'] if 'mount-point' in e]
try:
    for m in mounts:
        app=Path(m)/'Markdown 查看器.app'
        assert (app/'Contents/Resources/vendor/purify.js').is_file()
        assert (app/'Contents/Resources/reader.html').is_file()
        assert (Path(m)/'Applications').is_symlink()
        subprocess.run(['codesign','--verify','--strict','--verbose=2',str(app)],check=True)
finally:
    for m in mounts: subprocess.run(['hdiutil','detach',m],check=True)
sha=hashlib.sha256(dmg.read_bytes()).hexdigest()
(dmg.with_suffix('.dmg.sha256')).write_text(sha+'  '+dmg.name+'\n')
print('READY',dmg, 'bytes',dmg.stat().st_size)
