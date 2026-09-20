#!/usr/bin/env python3
"""Build and verify signed internal releases; optionally publish assets before feeds."""
import argparse
import base64
import hashlib
import importlib.util
import json
import plistlib
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = 'impptg/mmemo'
ACCOUNTS = ('user_pptg', 'user_mm')
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


def run(*args):
    return subprocess.check_output(list(map(str, args)), text=True).strip()


def prepare(notes, key):
    config = json.loads((ROOT / 'config/release.json').read_text())
    version, number = config['version'], config['build']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not isinstance(number, int) or number < 1:
        raise RuntimeError('Invalid version or build number')
    if not key.is_file() or key.stat().st_mode & 0o077:
        raise RuntimeError('Signing key must exist and have mode 0600')
    builder = module('desktop_builder', 'build-desktop.py')
    tools = builder.sparkle.fetch() / 'bin'
    out = ROOT / 'dist/releases' / version
    out.mkdir(parents=True, exist_ok=True)
    # Do not silently sign with a different key from the public key embedded in the app.
    public = run('swift', ROOT / 'scripts/update-public-key.swift', key)
    if public != config['publicKey']:
        raise RuntimeError('Signing key does not match config/release.json')
    manifest = {'version': version, 'build': number, 'commit': run('git', 'rev-parse', 'HEAD'), 'accounts': {}}
    for account in ACCOUNTS:
        name = f'mmemo-{account}-{version}-arm64.zip'
        app = builder.build(out / f'mmemo-{account}.app', account=account, release=True)
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        if info['MMemoAccount'] != account or not info['MMemoUpdatesEnabled']:
            raise RuntimeError('Wrong account/update configuration')
        forbidden = {'server.json', 'ai.json', 'server-session.json', 'session.json', 'todos.json', 'composer-draft.json'}
        if any(p.name in forbidden or p.suffix in {'.key', '.p12', '.p8', '.pem'} for p in app.rglob('*')):
            raise RuntimeError('Private file found in app bundle')
        archive = out / name
        if archive.exists():
            archive.unlink()
        run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, archive)
        signature = run(tools / 'sign_update', '-f', key, '-p', archive)
        run(tools / 'sign_update', '--verify', '-f', key, archive, signature)
        download = f'https://github.com/{REPO}/releases/download/v{version}/{name}'
        rss = ET.Element('rss', {'version': '2.0'})
        channel = ET.SubElement(rss, 'channel')
        ET.SubElement(channel, 'title').text = f'mmemo {account}'
        item = ET.SubElement(channel, 'item')
        ET.SubElement(item, 'title').text = f'mmemo {version}'
        ET.SubElement(item, f'{{{NS}}}version').text = str(number)
        ET.SubElement(item, f'{{{NS}}}shortVersionString').text = version
        ET.SubElement(item, f'{{{NS}}}minimumSystemVersion').text = '13.0'
        ET.SubElement(item, 'description', {f'{{{NS}}}format': 'plain-text'}).text = notes
        ET.SubElement(item, 'enclosure', {'url': download, 'length': str(archive.stat().st_size), 'type': 'application/octet-stream', f'{{{NS}}}edSignature': signature})
        feed = out / f'{account}.xml'
        ET.ElementTree(rss).write(feed, encoding='utf-8', xml_declaration=True)
        run(tools / 'sign_update', '-f', key, feed)
        run(tools / 'sign_update', '--verify', '-f', key, feed)
        manifest['accounts'][account] = {'asset': name, 'sha256': hashlib.sha256(archive.read_bytes()).hexdigest(), 'bytes': archive.stat().st_size}
    (out / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (out / 'release-notes.txt').write_text(notes)
    return out


def publish(out):
    api = module('github_api', 'github-api.py')
    manifest = json.loads((out / 'manifest.json').read_text())
    version, number, commit = manifest['version'], manifest['build'], manifest['commit']
    if run('git', 'status', '--porcelain'):
        raise RuntimeError('Commit source and release configuration before publishing')
    if run('git', 'rev-parse', 'HEAD') != commit:
        raise RuntimeError('Rebuild release from current commit before publishing')
    repo = '/repos/' + REPO
    api.request(repo + '/commits/' + commit)  # Source must be recoverable from GitHub.
    # Validate monotonic builds against the published branch, not a potentially stale CDN.
    try:
        pages_ref = api.request(repo + '/git/ref/heads/gh-pages')
        parent = pages_ref['object']['sha']
        parent_commit = api.request(repo + '/git/commits/' + parent)
        base_tree = parent_commit['tree']['sha']
        for account in ACCOUNTS:
            old = api.request(repo + f'/contents/updates/{account}.xml?ref=gh-pages')
            old_root = ET.fromstring(base64.b64decode(old['content']))
            previous = int(old_root.findtext(f'./channel/item/{{{NS}}}version'))
            if number < previous:
                raise RuntimeError('Build must never go backwards')
            if number == previous and base64.b64decode(old['content']) != (out / f'{account}.xml').read_bytes():
                raise RuntimeError('Published build is immutable; increment build and version')
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        parent, base_tree = None, None
    tag = 'v' + version
    try:
        existing_tag = api.request(repo + '/git/ref/tags/' + tag)
        if existing_tag['object']['sha'] != commit:
            raise RuntimeError('Tag already points at different source')
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        api.request(repo + '/git/refs', 'POST', {'ref': 'refs/tags/' + tag, 'sha': commit})
    try:
        release = api.request(repo + '/releases/tags/' + tag)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        release = api.request(repo + '/releases', 'POST', {
            'tag_name': tag, 'target_commitish': commit, 'name': 'mmemo ' + version + ' · Apple 芯片内部版',
            'body': (out / 'release-notes.txt').read_text(), 'draft': True, 'prerelease': False})
    upload_base = release['upload_url'].split('{')[0]
    assets = {a['name']: a for a in release['assets']}
    for name in [v['asset'] for v in manifest['accounts'].values()] + ['manifest.json', 'release-notes.txt']:
        payload = (out / name).read_bytes()
        if name in assets:
            # Never replace published assets; a resumed upload must match existing bytes.
            url = assets[name]['url']
            req = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + api.token(), 'Accept': 'application/octet-stream'})
            with urllib.request.urlopen(req, timeout=120) as response:
                existing = response.read()
            if hashlib.sha256(existing).digest() != hashlib.sha256(payload).digest():
                raise RuntimeError('Existing release asset differs: ' + name)
        else:
            api.request(upload_base + '?name=' + urllib.parse.quote(name), 'POST', raw=payload, content_type='application/octet-stream')
    if release['draft']:
        api.request(repo + '/releases/' + str(release['id']), 'PATCH', {'draft': False})
    # Check anonymously exactly as a client will, before announcing any update.
    for account, item in manifest['accounts'].items():
        url = f'https://github.com/{REPO}/releases/download/{tag}/{item["asset"]}'
        with urllib.request.urlopen(url, timeout=120) as response:
            content = response.read()
        if hashlib.sha256(content).hexdigest() != item['sha256']:
            raise RuntimeError('Public download does not match signed artifact')
    files = {f'updates/{account}.xml': (out / f'{account}.xml').read_bytes() for account in ACCOUNTS}
    files['.nojekyll'] = b''
    files['index.html'] = b'<!doctype html><meta charset="utf-8"><title>mmemo updates</title><a href="https://github.com/impptg/mmemo/releases">mmemo releases</a>'
    entries = []
    for path, data in files.items():
        blob = api.request(repo + '/git/blobs', 'POST', {'content': base64.b64encode(data).decode(), 'encoding': 'base64'})
        entries.append({'path': path, 'mode': '100644', 'type': 'blob', 'sha': blob['sha']})
    tree_body = {'tree': entries}
    if base_tree:
        tree_body['base_tree'] = base_tree
    tree = api.request(repo + '/git/trees', 'POST', tree_body)
    new_commit = api.request(repo + '/git/commits', 'POST', {'message': f'Publish signed update feeds for {tag}', 'tree': tree['sha'], 'parents': [parent] if parent else []})
    if parent:
        api.request(repo + '/git/refs/heads/gh-pages', 'PATCH', {'sha': new_commit['sha'], 'force': False})
    else:
        api.request(repo + '/git/refs', 'POST', {'ref': 'refs/heads/gh-pages', 'sha': new_commit['sha']})
    try:
        pages = api.request(repo + '/pages')
        if pages.get('source') != {'branch': 'gh-pages', 'path': '/'}:
            api.request(repo + '/pages', 'PUT', {'build_type': 'legacy', 'source': {'branch': 'gh-pages', 'path': '/'}})
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        api.request(repo + '/pages', 'POST', {'source': {'branch': 'gh-pages', 'path': '/'}})
    print('Published assets and requested Pages deployment:', 'https://github.com/' + REPO + '/releases/tag/' + tag)
    print('Verify live Pages feeds before considering the release complete.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--notes', type=Path)
    parser.add_argument('--key', type=Path, default=ROOT / '.secrets/mmemo-sparkle.key')
    parser.add_argument('--publish', type=Path, help='Publish an already prepared release directory')
    args = parser.parse_args()
    if args.publish:
        publish(args.publish.resolve())
    else:
        if not args.notes:
            parser.error('--notes is required when preparing a release')
        print(prepare(args.notes.read_text(), args.key.resolve()))
