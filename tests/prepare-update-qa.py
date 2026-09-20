#!/usr/bin/env python3
import importlib.util,json,subprocess,xml.etree.ElementTree as ET
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
work=ROOT/'artifacts/private/update-qa'
work.mkdir(parents=True,exist_ok=True)
spec=importlib.util.spec_from_file_location('builder',ROOT/'scripts/build-desktop.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
main=(ROOT/'apps/desktop/main.swift').read_text().replace('app.run()', (ROOT/'tests/update-agent.swift').read_text()+'\napp.run()')
(work/'main.swift').write_text(main)
ns='http://www.andymatuschak.org/xml-namespaces/sparkle';ET.register_namespace('sparkle',ns)
tools=builder.sparkle.fetch()/'bin'
for account in ['user_pptg','user_mm']:
 for version,number in [('0.2.0',2),('0.2.1',3)]:
  app=builder.build(work/str(number)/f'mmemo-{account}.app',account,True,version,number,work/'main.swift',True,'http://127.0.0.1:18766')
  if number==3:
   archive=work/f'mmemo-{account}.zip'
   subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(app),str(archive)],check=True)
   sig=subprocess.check_output([str(tools/'sign_update'),'-f',str(ROOT/'.secrets/mmemo-sparkle.key'),'-p',str(archive)],text=True).strip()
   rss=ET.Element('rss',{'version':'2.0'});channel=ET.SubElement(rss,'channel');ET.SubElement(channel,'title').text='mmemo QA'
   item=ET.SubElement(channel,'item');ET.SubElement(item,'title').text='mmemo 0.2.1'
   ET.SubElement(item,f'{{{ns}}}version').text='3';ET.SubElement(item,f'{{{ns}}}shortVersionString').text='0.2.1'
   ET.SubElement(item,'description',{f'{{{ns}}}format':'plain-text'}).text='隔离验收：更新到 0.2.1，保留账号、草稿和本地数据。'
   ET.SubElement(item,'enclosure',{'url':f'http://127.0.0.1:18766/mmemo-{account}.zip','length':str(archive.stat().st_size),'type':'application/octet-stream',f'{{{ns}}}edSignature':sig})
   feed=work/f'{account}.xml';ET.ElementTree(rss).write(feed,encoding='utf-8',xml_declaration=True)
   subprocess.run([str(tools/'sign_update'),'-f',str(ROOT/'.secrets/mmemo-sparkle.key'),str(feed)],check=True)
print(work)
