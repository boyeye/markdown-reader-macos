#!/usr/bin/env python3
"""Run Tests/Harness.swift against real WebKit and report Tests/results.json."""
from pathlib import Path
import json,shutil,subprocess,sys
from toolchain import ROOT,swiftc
APP=ROOT/'.build/Harness.app'
shutil.rmtree(APP,ignore_errors=True)
(APP/'Contents/MacOS').mkdir(parents=True)
shutil.copytree(ROOT/'Resources',APP/'Contents/Resources')
swiftc([ROOT/'Reader.swift',ROOT/'Tests/Harness.swift'],APP/'Contents/MacOS/Harness','-D','TESTING')
results=ROOT/'Tests/results.json'; results.unlink(missing_ok=True)
subprocess.run([str(APP/'Contents/MacOS/Harness')],timeout=120,check=True)
data=json.loads(results.read_text())
print(json.dumps(data,ensure_ascii=False,indent=2))
sys.exit(0 if data.get('passed') else 1)
