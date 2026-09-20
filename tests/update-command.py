#!/usr/bin/env python3
"""Send a command to the explicitly compiled QA app, never a release app."""
import json,sys,time,uuid
from pathlib import Path
account=sys.argv[1]
assert account in ('user_pptg','user_mm')
p=Path.home()/'Library/Application Support/mmemo/update-qa'/account
command=json.loads(sys.argv[2]);command['request']=str(uuid.uuid4())
temp=p/'command.tmp';temp.write_text(json.dumps(command));temp.replace(p/'command.json')
for _ in range(150):
 try:
  result=json.loads((p/'result.json').read_text())
  if result.get('request')==command['request']:
   print(json.dumps(result,ensure_ascii=False));sys.exit(0 if result.get('ok') else 1)
 except (FileNotFoundError,json.JSONDecodeError):pass
 time.sleep(.1)
raise SystemExit('QA command timeout')
