#!/usr/bin/env python3
"""Measure native mission production through actual pod arrival on a cleared pad."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path(os.environ.get('FACTORIO', str(Path.home() / 'Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio')))
MTS = Path(os.environ.get('MTS_MOD_ZIP', str(Path.home() / 'Library/Application Support/factorio/mods/multi-team-support_0.6.6.zip')))
VERSION = json.loads((ROOT / 'info.json').read_text())['version']


def run_case(name, platform=False, endgame=False, requests=False, blocked=False):
    path = Path(tempfile.mkdtemp(prefix=f'mts-throughput-{name}-'))
    print(f'{name}: {path}', flush=True)
    mod = path / 'mods' / f'mts-expanse_{VERSION}'
    shutil.copytree(ROOT, mod, ignore=shutil.ignore_patterns('.git', 'scripts', '*.zip', '__pycache__', '.DS_Store'))
    main = mod / 'maps/expanse/main.lua'
    source = main.read_text(); pos = source.rindex('return Public')
    main.write_text(source[:pos] + "function Public.test_state(name) return state_from_force_name(name) end\n" + source[pos:])
    control = mod / 'control.lua'; source = control.read_text()
    if platform:
        source = source.replace("local Expanse = require 'maps.expanse.main'", "require('utils.event').on_init(function() settings.global['mts-expanse-use-space-platform']={value=true} end)\nlocal Expanse = require 'maps.expanse.main'")
    config = dict(platform=platform, endgame=endgame, requests=requests, blocked=blocked, drain_every=int(os.environ.get('DRAIN_EVERY', '60')), cycles=int(os.environ.get('CYCLES', '6')))
    control.write_text(source + "\nrequire('throughput_probe').install(Expanse,helpers.json_to_table([===[" + json.dumps(config) + "]===]))\n")
    shutil.copyfile(ROOT / 'scripts/cargo-throughput-probe.lua', mod / 'throughput_probe.lua')
    (path / 'mods' / MTS.name).symlink_to(MTS)
    (path / 'mods/mod-list.json').write_text(json.dumps({'mods': [{'name':n,'enabled':True} for n in ['base','quality','elevated-rails','space-age','mts-expanse','multi-team-support']]}))
    (path / 'write-data').mkdir()
    (path / 'config.ini').write_text(f'[path]\nread-data={ENGINE.parent.parent}/data\nwrite-data={path}/write-data\n[general]\nlocale=en\n')
    save = path / 'test.zip'
    for label,args in [('create',['--create',str(save)]),('benchmark',['--benchmark',str(save),'--benchmark-ticks',str(10800+config['cycles']*3600+60),'--benchmark-runs','1','--benchmark-sanitize'])]:
        with (path / f'{label}.log').open('w') as f:
            p = subprocess.run([str(ENGINE),'--config',str(path/'config.ini'),'--mod-directory',str(path/'mods'),*args],stdout=f,stderr=subprocess.STDOUT,timeout=240)
        log = (path / f'{label}.log').read_text()
        if p.returncode or 'stack traceback:' in log:
            raise AssertionError(log[-6000:])
    report = json.loads((path / 'write-data/script-output/throughput.json').read_text())
    assert report['done'], report
    print(json.dumps({'case':name,'rates_per_minute':report['rates'],'received':report['received'],'expected':report['expected'],'generated':report['generated'],'matched':report['matched'],'cycles_checked':len(report['cycles']),'source_hatches':report['source_hatches'],'pad_hatches':report['pad_hatches']}), flush=True)
    if not os.environ.get('MEASURE_ONLY'):
        assert report['matched'], f'Arrival rate fell behind: {path}/write-data/script-output/throughput.json'


if __name__ == '__main__':
    cases = {'m4': (False,False,False), 'endgame': (False,True,False), 'requested': (False,True,True), 'platform': (True,True,False), 'blocked': (False,True,False,True)}
    for name in os.environ.get('THROUGHPUT_CASES', ','.join(cases)).split(','):
        run_case(name, *cases[name])
