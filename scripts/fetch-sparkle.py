#!/usr/bin/env python3
"""Fetch the pinned official binary distribution, checking its SHA-256."""
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request

ROOT = Path(__file__).resolve().parent.parent


def fetch():
    config = json.loads((ROOT / 'config/release.json').read_text())
    version = config['sparkleVersion']
    target = ROOT / '.build' / ('Sparkle-' + version)
    if (target / '.verified').exists() and (target / '.verified').read_text() == config['sparkleSHA256']:
        return target
    target.mkdir(parents=True, exist_ok=True)
    archive = target / 'distribution.tar.xz'
    url = f'https://github.com/sparkle-project/Sparkle/releases/download/{version}/Sparkle-{version}.tar.xz'
    with urllib.request.urlopen(url, timeout=60) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != config['sparkleSHA256']:
        raise SystemExit('Sparkle download checksum mismatch')
    archive.write_bytes(data)
    subprocess.run(['tar', '-xf', str(archive), '-C', str(target)], check=True)
    (target / '.verified').write_text(config['sparkleSHA256'])
    return target


if __name__ == '__main__':
    print(fetch())
