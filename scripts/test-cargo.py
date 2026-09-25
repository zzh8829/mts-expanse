#!/usr/bin/env python3
"""Exercise real request compilation, shared capacity and pod delivery in Factorio."""
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


def run_case(name, mts=False, platform=False):
    path = Path(tempfile.mkdtemp(prefix=f'mts-expanse-cargo-{name}-'))
    print(f'{name}: {path}', flush=True)
    mod = path / 'mods' / f'mts-expanse_{VERSION}'
    shutil.copytree(ROOT, mod, ignore=shutil.ignore_patterns('.git', 'scripts', '*.zip', '__pycache__', '.DS_Store'))
    main = mod / 'maps/expanse/main.lua'
    text = main.read_text(); pos = text.rindex('return Public')
    main.write_text(text[:pos]+"function Public.test_state(name) return state_from_force_name(name) end\n"+text[pos:])
    control = mod / 'control.lua'; text = control.read_text()
    if platform:
        text = text.replace("local Expanse = require 'maps.expanse.main'", "require('utils.event').on_init(function() settings.global['mts-expanse-use-space-platform']={value=true} end)\nlocal Expanse = require 'maps.expanse.main'")
    control.write_text(text+f"\nrequire('cargo_probe').install(Expanse,{str(mts).lower()},{str(platform).lower()})\n")
    shutil.copyfile(ROOT/'scripts/cargo-probe.lua',mod/'cargo_probe.lua')
    mods = [{'name':n,'enabled':True} for n in ['base','quality','elevated-rails','space-age','mts-expanse']]
    if mts:
        (path/'mods'/MTS.name).symlink_to(MTS);mods.append({'name':'multi-team-support','enabled':True})
    (path/'mods/mod-list.json').write_text(json.dumps({'mods':mods}))
    (path/'write-data').mkdir()
    (path/'config.ini').write_text(f'[path]\nread-data={FACTORIO.parent.parent}/data\nwrite-data={path}/write-data\n[general]\nlocale=en\n')
    save=path/'test.zip'
    for label,args in [('create',['--create',str(save)]),('benchmark',['--benchmark',str(save),'--benchmark-ticks','14000','--benchmark-runs','1','--benchmark-sanitize'])]:
        with (path/f'{label}.log').open('w') as f:
            p=subprocess.run([str(FACTORIO),'--config',str(path/'config.ini'),'--mod-directory',str(path/'mods'),*args],stdout=f,stderr=subprocess.STDOUT,timeout=180)
        log=(path/f'{label}.log').read_text()+(path/'write-data/factorio-current.log').read_text()
        if p.returncode or 'stack traceback:' in log: raise AssertionError(log[-6500:])
    checks=json.loads((path/'write-data/script-output/cargo-result.json').read_text())
    assert all(checks.values()),checks
    print(f'PASS {name}: {len(checks)} checks',flush=True)


if __name__=='__main__':
    cases={'nonorbit':(False,False),'platform':(False,True),'mts':(True,False),'mts-platform':(True,True)}
    for name in os.environ.get('CARGO_CASES',','.join(cases)).split(','):
        run_case(name,*cases[name])
