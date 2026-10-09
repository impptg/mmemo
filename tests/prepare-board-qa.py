"""Build real disposable account apps without touching daily account configuration."""
import importlib.util
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
work=ROOT/'artifacts/private/board-qa';work.mkdir(parents=True,exist_ok=True)
main=(ROOT/'apps/desktop/main.swift').read_text().replace('app.run()', (ROOT/'tests/board-agent.swift').read_text()+'\napp.run()')
(work/'main.swift').write_text(main)
spec=importlib.util.spec_from_file_location('builder',ROOT/'scripts/build-desktop.py');builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)
for account in ['user_pptg','user_mm']:
 builder.build(work/f'mmemo-{account}.app',account,main=work/'main.swift',board_qa=True)
