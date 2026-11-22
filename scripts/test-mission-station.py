#!/usr/bin/env python3
"""Exercise the mission cargo station, part-load launches and command guards in Factorio."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FACTORIO = Path(os.environ.get('FACTORIO', str(Path.home() / 'Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio')))
MTS = Path(os.environ.get('MTS_MOD_ZIP', str(Path.home() / 'Library/Application Support/factorio/mods/multi-team-support_0.6.6.zip')))
VERSION = json.loads((ROOT / 'info.json').read_text())['version']


def run_case(name, mts=False, ticks=9000):
    path = Path(tempfile.mkdtemp(prefix=f'mts-expanse-station-{name}-'))
    print(f'{name}: {path}', flush=True)
    mod = path / 'mods' / f'mts-expanse_{VERSION}'
    shutil.copytree(ROOT, mod, ignore=shutil.ignore_patterns('.git', 'scripts', '*.zip', '__pycache__', '.DS_Store'))
    main = mod / 'maps/expanse/main.lua'
    text = main.read_text()
    pos = text.rindex('return Public')
    main.write_text(text[:pos] + "Public.test_state = state_from_force_name\nPublic.test_reset_target = state_from_command\n" + text[pos:])
    control = mod / 'control.lua'
    control.write_text(control.read_text() + f"\nrequire('station_probe').install(Expanse,{str(mts).lower()})\n")
    shutil.copyfile(ROOT / 'scripts/mission-station-probe.lua', mod / 'station_probe.lua')
    mods = [{'name': n, 'enabled': True} for n in ['base', 'elevated-rails', 'space-age', 'mts-expanse']]
    mods.append({'name': 'quality', 'enabled': name != 'no-quality'})
    if mts:
        (path / 'mods' / MTS.name).symlink_to(MTS)
        mods.append({'name': 'multi-team-support', 'enabled': True})
    (path / 'mods/mod-list.json').write_text(json.dumps({'mods': mods}))
    (path / 'write-data').mkdir()
    (path / 'config.ini').write_text(f'[path]\nread-data={FACTORIO.parent.parent}/data\nwrite-data={path}/write-data\n[general]\nlocale=en\n')
    save = path / 'test.zip'
    runs = [('create', ['--create', str(save)]),
            ('benchmark', ['--benchmark', str(save), '--benchmark-ticks', str(ticks), '--benchmark-runs', '1', '--benchmark-sanitize'])]
    for label, args in runs:
        with (path / f'{label}.log').open('w') as output:
            result = subprocess.run([str(FACTORIO), '--config', str(path / 'config.ini'), '--mod-directory', str(path / 'mods'), *args],
                                    stdout=output, stderr=subprocess.STDOUT, timeout=300)
        log = (path / f'{label}.log').read_text() + (path / 'write-data/factorio-current.log').read_text()
        if result.returncode or 'stack traceback:' in log:
            raise AssertionError(log[-6500:])
    report = path / 'write-data/script-output/station-result.json'
    assert report.exists(), f'The probe did not finish within {ticks} ticks: {path}'
    checks = json.loads(report.read_text())
    assert all(checks.values()), checks
    print(f'PASS {name}: {len(checks)} checks', flush=True)


if __name__ == '__main__':
    cases = {'nonorbit': False, 'no-quality': False, 'mts': True}
    for name in os.environ.get('STATION_CASES', ','.join(cases)).split(','):
        run_case(name, cases[name])
