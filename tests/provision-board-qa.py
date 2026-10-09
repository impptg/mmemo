"""Provision localhost-only disposable board accounts; never read daily profiles."""
import json,os,secrets,subprocess,uuid
from pathlib import Path
from urllib.parse import urlsplit
ROOT=Path(__file__).resolve().parent.parent
WORK=ROOT/'artifacts/private/board-qa';WORK.mkdir(parents=True,exist_ok=True);WORK.chmod(0o700)
database=os.environ.get('BOARD_QA_DATABASE_URL','postgres://mmemo:local-testing-only@127.0.0.1:55432/mmemo_board_qa')
u=urlsplit(database)
if u.hostname not in ['127.0.0.1','localhost'] or u.path!='/mmemo_board_qa':raise RuntimeError('Board QA requires the localhost mmemo_board_qa database')
code="""import pg from 'pg';const u=new URL(process.env.BOARD_QA_DATABASE_URL);u.pathname='/postgres';const c=new pg.Client({connectionString:u.toString()});await c.connect();if(!(await c.query(\"SELECT 1 FROM pg_database WHERE datname='mmemo_board_qa'\")).rowCount)await c.query('CREATE DATABASE mmemo_board_qa');await c.end();"""
subprocess.run(['node','--input-type=module','-e',code],cwd=ROOT/'apps/server',env={**os.environ,'BOARD_QA_DATABASE_URL':database},check=True)
bootstrap=WORK/'bootstrap.json'
if not bootstrap.exists():bootstrap.write_text(json.dumps({'passwords':{n:secrets.token_urlsafe(32) for n in ['user_pptg','user_mm']},'todos':[]}));bootstrap.chmod(0o600)
config=json.loads(bootstrap.read_text())
subprocess.run(['node','apps/server/dist/bootstrap.js',str(bootstrap)],cwd=ROOT,env={**os.environ,'DATABASE_URL':database},check=True)
for name,uid in [('user_pptg','2100541450115510274'),('user_mm','2100541456125558785')]:
 folder=WORK/'accounts'/name;folder.mkdir(parents=True,exist_ok=True);folder.chmod(0o700)
 path=folder/'server.json'
 if not path.exists():path.write_text(json.dumps({'baseURL':'http://127.0.0.1:18787','username':name,'password':config['passwords'][name],'uid':uid,'deviceId':str(uuid.uuid4())}));path.chmod(0o600)
print('Isolated board QA accounts ready; daily data unchanged.')
