#!/usr/bin/env python3
"""Small GitHub REST client. Credentials stay in memory, never in output or URLs."""
import json
import os
import subprocess
import urllib.request


def token():
    value = os.environ.get('GH_TOKEN') or os.environ.get('GITHUB_TOKEN')
    if value:
        return value
    result = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n', text=True, capture_output=True, check=True)
    fields = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    if not fields.get('password'):
        raise RuntimeError('No GitHub credential. Authenticate Git or set GH_TOKEN.')
    return fields['password']


def request(path, method='GET', body=None, raw=None, content_type='application/json'):
    url = path if path.startswith('https://uploads.github.com/') else 'https://api.github.com' + path
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method, headers={
        'Authorization': 'Bearer ' + token(), 'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': content_type})
    with urllib.request.urlopen(req, timeout=120) as response:
        payload = response.read()
        return json.loads(payload) if payload else None
