#!/usr/bin/env python3
"""Check soft-reset enemy removal, inventories, and crafting queues in isolated Factorio profiles."""
import concurrent.futures
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
WORK = Path(tempfile.mkdtemp(prefix='mts-expanse-forfeit-'))


def run_case(case):
    name, mts, space = case
    path = WORK / name
    mod = path / 'mods' / f'mts-expanse_{VERSION}'
    shutil.copytree(ROOT, mod, ignore=shutil.ignore_patterns('.git', 'scripts', '*.zip', '__pycache__', '.DS_Store'))
    main = mod / 'maps/expanse/main.lua'
    source = main.read_text()
    pos = source.rindex('return Public')
    main.write_text(source[:pos] + "function Public.test_state(name) return state_from_force_name(name or 'player') end\n" + source[pos:])
    control = mod / 'control.lua'
    control.write_text(control.read_text() + "\nrequire('forfeit_probe').install(Expanse)\n")
    shutil.copyfile(ROOT / 'scripts/forfeit-probe.lua', mod / 'forfeit_probe.lua')
    mods = [{'name': n, 'enabled': True} for n in ['base', 'mts-expanse']]
    mods += [{'name': n, 'enabled': space} for n in ['space-age', 'quality', 'elevated-rails']]
    if mts:
        (path / 'mods' / MTS.name).symlink_to(MTS)
        mods.append({'name': 'multi-team-support', 'enabled': True})
    (path / 'mods/mod-list.json').write_text(json.dumps({'mods': mods}))
    (path / 'write-data').mkdir()
    (path / 'config.ini').write_text(f'[path]\nread-data={FACTORIO.parent.parent}/data\nwrite-data={path}/write-data\n[general]\nlocale=en\n')
    for label, args in [('create', ['--create', str(path / 'test.zip')]), ('benchmark', ['--benchmark', str(path / 'test.zip'), '--benchmark-ticks', '1260', '--benchmark-runs', '1', '--benchmark-sanitize'])]:
        with (path / f'{label}.log').open('w') as log:
            subprocess.run([str(FACTORIO), '--config', str(path / 'config.ini'), '--mod-directory', str(path / 'mods'), *args], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
        assert 'stack traceback:' not in (path / f'{label}.log').read_text(), path / f'{label}.log'
        engine_log = path / 'write-data/factorio-current.log'
        assert 'stack traceback:' not in engine_log.read_text(), engine_log
    results = json.loads((path / 'write-data/script-output/forfeit-result.json').read_text())
    assert all(results.values()), (name, [key for key, value in results.items() if not value])
    return f'{name}: {len(results)} checks'


if __name__ == '__main__':
    print(f'Isolated profiles: {WORK}', flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for result in pool.map(run_case, [('standalone', False, False), ('space-age', False, True), ('mts', True, True), ('mts-vanilla', True, False)]):
            print('PASS ' + result, flush=True)
