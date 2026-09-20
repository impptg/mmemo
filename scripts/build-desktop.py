#!/usr/bin/env python3
"""Build a clean arm64 app. Only release builds can use the production feed."""
import argparse
import importlib.util
import json
import plistlib
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('sparkle', ROOT / 'scripts/fetch-sparkle.py')
sparkle = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sparkle)


def build(output, account=None, release=False, version=None, number=None, main=None, qa=False, feed_base=None):
    config = json.loads((ROOT / 'config/release.json').read_text())
    framework = sparkle.fetch()
    output = Path(output).resolve()
    if output.suffix != '.app' or ROOT not in output.parents:
        raise ValueError('Build output must be an .app below this checkout')
    if output.exists():
        shutil.rmtree(output)
    contents = output / 'Contents'
    (contents / 'MacOS').mkdir(parents=True)
    (contents / 'Frameworks').mkdir()
    resources = contents / 'Resources'
    shutil.copytree(ROOT / 'apps/desktop/web', resources / 'web')
    (resources / 'Licenses').mkdir()
    shutil.copy2(framework / 'LICENSE', resources / 'Licenses/Sparkle.txt')
    (resources / 'web/assets').mkdir(exist_ok=True)
    for name in ['avatar-pair-love-white.png', 'avatar-raccoon.png', 'raccoon-edge-blink-ui.apng', 'pp-edge-assistant-blink.apng']:
        shutil.copy2(ROOT / 'design/assets' / name, resources / 'web/assets' / name)
    subprocess.run(['swift', str(ROOT / 'apps/desktop/icons.swift'), str(resources / 'web/icons')], check=True)
    subprocess.run(['ditto', str(framework / 'Sparkle.framework'), str(contents / 'Frameworks/Sparkle.framework')], check=True)
    sources = [str(ROOT / 'apps/desktop' / name) for name in ['Store.swift', 'AI.swift', 'Cloud.swift', 'Updates.swift']]
    sources.append(str(main or ROOT / 'apps/desktop/main.swift'))
    subprocess.run(['swiftc', '-O', '-target', 'arm64-apple-macos13.0', *(['-D', 'MMEMO_UPDATE_QA'] if qa else []), *sources,
                    '-o', str(contents / 'MacOS/mmemo'), '-F', str(framework), '-framework', 'Sparkle',
                    '-framework', 'AppKit', '-framework', 'WebKit', '-Xlinker', '-rpath', '-Xlinker', '@executable_path/../Frameworks'], check=True)
    bundle = 'local.mmemo.desktop' + ('.' + account.replace('_', '-') if account else '')
    if qa:
        bundle = 'local.mmemo.update-qa.' + (account or 'local').replace('_', '-')
    info = dict(CFBundleExecutable='mmemo', CFBundleIdentifier=bundle, CFBundleName='mmemo' + (' ' + account if account else ''),
                CFBundleVersion=str(number or config['build']), CFBundleShortVersionString=version or config['version'],
                CFBundlePackageType='APPL', LSMinimumSystemVersion='13.0', LSUIElement=True, NSHighResolutionCapable=True,
                CFBundleDevelopmentRegion='zh_CN', CFBundleLocalizations=['zh_CN', 'en'], MMemoUpdatesEnabled=release,
                SUPublicEDKey=config['publicKey'], SUScheduledCheckInterval=21600,
                SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
                SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True)
    if account:
        info['MMemoAccount'] = account
    if release:
        if not account:
            raise ValueError('Release requires an explicit account variant')
        info['SUFeedURL'] = (feed_base or config['feedBaseURL']).rstrip('/') + '/' + account + '.xml'
    if qa:
        info['SUEnableAutomaticChecks'] = False
        info['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking': True}
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    # Internal distribution: retain Sparkle's signed helpers; sign the host ad hoc.
    subprocess.run(['codesign', '--force', '--sign', '-', str(output)], check=True)
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(output)], check=True)
    return output


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('--output', default=str(ROOT / 'dist/mmemo.app'))
    p.add_argument('--account', choices=['user_pptg', 'user_mm'])
    p.add_argument('--release', action='store_true')
    p.add_argument('--qa', action='store_true')
    p.add_argument('--version')
    p.add_argument('--build', type=int)
    p.add_argument('--main', type=Path)
    p.add_argument('--feed-base')
    a = p.parse_args()
    print(build(a.output, a.account, a.release, a.version, a.build, a.main, a.qa, a.feed_base))
