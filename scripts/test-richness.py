#!/usr/bin/env python3
"""Check resource richness on native Expanse maps and an upgrade from 0.1.25."""
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
MAC_SUPPORT = Path.home() / 'Library/Application Support'
MODS = MAC_SUPPORT / 'factorio/mods'
LEGACY = '85c48644a62442da245decc7cab428fa29f39feb'
NAUVIS = {'iron-ore': 2.5, 'coal': 0.5, 'crude-oil': 4, 'uranium-ore': 3}
PLANETS = {'tungsten_ore': 4, 'vulcanus_coal': 1.5, 'calcite': 0,
           'scrap': 0.25, 'gleba_stone': 2, 'aquilo_crude_oil': 0.75}


def find_engine():
    if 'FACTORIO' in os.environ:
        return Path(os.environ['FACTORIO']).expanduser().resolve()
    executable = Path('factorio.app/Contents/MacOS/factorio')
    for directory in [Path('/Applications'), MAC_SUPPORT / 'Steam/steamapps/common/Factorio']:
        engine = directory / executable
        if engine.is_file():
            return engine
    raise FileNotFoundError('Set FACTORIO to the Factorio executable.')


def install(path, mts, legacy, native, space):
    mods = path / ('old-mods' if legacy else 'mods')
    version = '0.1.25' if legacy else json.loads((ROOT / 'info.json').read_text())['version']
    mod = mods / f'mts-expanse_{version}'
    if legacy:
        data = subprocess.check_output(['git', 'archive', '--format=zip', LEGACY], cwd=ROOT)
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            archive.extractall(mod)
    else:
        shutil.copytree(ROOT, mod, ignore=shutil.ignore_patterns('.git', 'scripts', '*.zip', '__pycache__'))
    main = mod / 'maps/expanse/main.lua'
    source = main.read_text()
    start = source.rindex('return Public')
    main.write_text(source[:start] + 'Public.test_richness_state = state_from_force_name\n' + source[start:])
    shutil.copyfile(ROOT / 'scripts/richness-probe.lua', mod / 'richness_probe.lua')
    with (mod / 'control.lua').open('a') as control:
        control.write(f"\nrequire('richness_probe')(Expanse, {str(mts).lower()}, {str(legacy).lower()})\n")
    if native:
        with (mod / 'settings.lua').open('a') as settings:
            settings.write("\ndata.raw['bool-setting']['mts-expanse-override-nauvis'].default_value = false\n")
    enabled = ['base', 'mts-expanse']
    if space:
        enabled.extend(['elevated-rails', 'recycler', 'space-age'])
    if mts:
        if 'MTS_MOD_ZIP' in os.environ:
            package = Path(os.environ['MTS_MOD_ZIP']).resolve()
        else:
            package = max(MODS.glob('multi-team-support_*.zip'),
                          key=lambda p: tuple(map(int, p.stem.split('_')[-1].split('.'))))
        (mods / package.name).symlink_to(package)
        enabled.append('multi-team-support')
    names = sorted(set(enabled) | {'space-age', 'quality', 'elevated-rails', 'recycler'})
    mod_list = [{'name': name, 'enabled': name in enabled} for name in names]
    (mods / 'mod-list.json').write_text(json.dumps({'mods': mod_list}))
    return mods


def run(name, preset=None, mts=False, legacy=False, native=False, space=True):
    engine = find_engine()
    data_dir = next(parent / 'data' for parent in engine.parents if (parent / 'data/core').is_dir())
    with tempfile.TemporaryDirectory(prefix='mts-expanse-richness-') as temp:
        path = Path(temp)
        (path / 'write').mkdir()
        config = path / 'config.ini'
        config.write_text(f'[path]\nread-data={data_dir}\nwrite-data={path}/write\n')
        mods = install(path, mts, False, native, space)
        create_mods = install(path, mts, True, native, space) if legacy else mods
        map_args = ['--map-gen-seed', '61616']
        if preset:
            map_args += ['--preset', preset]
        else:
            setting_file = path / 'map.json'
            settings = {**NAUVIS, **PLANETS} if space else NAUVIS
            controls = {key: {'richness': value} for key, value in settings.items()}
            setting_file.write_text(json.dumps({'autoplace_controls': controls}))
            map_args += ['--map-gen-settings', str(setting_file)]
        save = str(path / 'world.zip')
        steps = [
            (create_mods, [*map_args, '--create', save]),
            (mods, ['--benchmark', save, '--benchmark-ticks', '10', '--benchmark-runs', '1']),
        ]
        for folder, args in steps:
            command = [str(engine), '--config', str(config), '--mod-directory', str(folder), *args]
            result = subprocess.run(command, capture_output=True, text=True, timeout=180)
            log_file = path / 'write/factorio-current.log'
            log = log_file.read_text() if log_file.exists() else result.stderr
            if result.returncode or 'stack traceback:' in log:
                raise AssertionError(f'{name}: {result.stdout[-1500:]}\n{log[-3500:]}')
        report = json.loads((path / 'write/script-output/richness-result.json').read_text())
        if native and not mts:
            assert (path / 'write/script-output/richness-toggle-ok').read_text() == 'passed'
        expected_iron = {'default': 1, 'rich-resources': 2}.get(preset, NAUVIS['iron-ore'])
        assert report == {'teams': 2 if mts else 1, 'iron': expected_iron}, report
        print(f'PASS {name}: {report}', flush=True)


if __name__ == '__main__':
    run('default', preset='default')
    run('rich resources', preset='rich-resources')
    run('mixed')
    run('two MTS teams', mts=True)
    run('native source', native=True)
    run('two vanilla MTS teams', mts=True, space=False)
    run('two vanilla MTS teams, native source', mts=True, native=True, space=False)
    run('0.1.25 upgrade', legacy=True)
