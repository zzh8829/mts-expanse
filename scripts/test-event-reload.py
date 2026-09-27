#!/usr/bin/env python3
"""Reproduce saved event-ID drift, then check actual invasions after loading the fix."""
import io
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ENGINE = Path(os.environ.get('FACTORIO', str(Path.home() / 'Library/Application Support/Steam/steamapps/common/Factorio/factorio.app/Contents/MacOS/factorio')))
MTS = Path(os.environ.get('MTS_MOD_ZIP', str(Path.home() / 'Library/Application Support/factorio/mods/multi-team-support_0.6.6.zip')))
BASELINE = '94a61968a86f3dd8af5761eaf4813a776f87c152'


def instrument(mod, mts, shift, bootstrap):
    main = mod / 'maps/expanse/main.lua'
    source = main.read_text()
    pos = source.rindex('return Public')
    main.write_text(source[:pos] + """
Public.test_registered_events = expanse.events or require('maps.expanse.events')
function Public.test_events() return Public.test_registered_events end
function Public.test_state(name) return state_from_force_name(name) end
""" + source[pos:])
    control = mod / 'control.lua'
    control.write_text(f'for i = 1, {shift} do local unused = script.generate_event_name() end\n' + control.read_text()
        + f"\nrequire('event_reload_probe').install(Expanse, {str(mts).lower()}, {str(bootstrap).lower()})\n")
    shutil.copyfile(ROOT / 'scripts/event-reload-probe.lua', mod / 'event_reload_probe.lua')


def install(path, mts, shift, fixed=False, upgrade=False):
    mod = path / 'mods/mts-expanse'
    if mod.exists(): shutil.rmtree(mod)
    if fixed:
        shutil.copytree(ROOT, mod, ignore=shutil.ignore_patterns('.git', 'scripts', '*.zip', '__pycache__', '.DS_Store'))
    else:
        mod.mkdir()
        archive = subprocess.check_output(['git', 'archive', '--format=zip', BASELINE], cwd=ROOT)
        with zipfile.ZipFile(io.BytesIO(archive)) as z: z.extractall(mod)
    info = json.loads((mod / 'info.json').read_text())
    info['version'] = '0.1.20' if upgrade else '0.1.19'
    (mod / 'info.json').write_text(json.dumps(info))
    instrument(mod, mts, shift, shift == 0)


def run_case(name, space, mts):
    path = Path(tempfile.mkdtemp(prefix=f'mts-event-reload-{name}-'))
    print(f'{name}: {path}', flush=True)
    (path / 'mods').mkdir()
    if mts: (path / 'mods' / MTS.name).symlink_to(MTS)
    mods = [{'name': n, 'enabled': True} for n in ['base', 'mts-expanse']]
    mods += [{'name': n, 'enabled': space} for n in ['quality', 'elevated-rails', 'space-age']]
    if mts: mods.append({'name': 'multi-team-support', 'enabled': True})
    (path / 'mods/mod-list.json').write_text(json.dumps({'mods': mods}))
    (path / 'write-data/saves').mkdir(parents=True)
    (path / 'config.ini').write_text(f'[path]\nread-data={ENGINE.parent.parent}/data\nwrite-data={path}/write-data\n[general]\nlocale=en\n')
    save = path / 'before.zip'

    def run(label, args):
        with (path / f'{label}.log').open('w') as f:
            command = [str(ENGINE), '--config', str(path / 'config.ini'),
                '--mod-directory', str(path / 'mods'), *args]
            if label == 'establish':
                result = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=f, stderr=subprocess.STDOUT, text=True)
                deadline = time.monotonic() + 60
                try:
                    while result.poll() is None and time.monotonic() < deadline:
                        saved = path / 'write-data/saves/event-before.zip'
                        if saved.exists() and zipfile.is_zipfile(saved): break
                        time.sleep(0.1)
                    # Headless Factorio shuts down on SIGINT, not an in-game /quit command.
                    if result.poll() is None: result.send_signal(signal.SIGINT)
                    result.wait(timeout=15)
                finally:
                    if result.poll() is None:
                        result.kill()
                        result.wait()
            else:
                result = subprocess.run(command, stdout=f, stderr=subprocess.STDOUT, timeout=150)
        log = (path / f'{label}.log').read_text()
        assert result.returncode == 0 or (label == 'establish' and result.returncode == -signal.SIGINT), log[-6000:]
        engine_log = (path / 'write-data/factorio-current.log').read_text()
        (path / f'{label}-engine.log').write_text(engine_log)
        return log + engine_log

    install(path, mts, 0)
    created = run('create', ['--create', str(save)])
    assert 'stack traceback:' not in created, created[-6000:]
    server_settings = json.loads((ENGINE.parent.parent / 'data/server-settings.example.json').read_text())
    server_settings.update({'name': 'Disposable event regression',
        'visibility': {'public': False, 'lan': False}, 'require_user_verification': False,
        'auto_pause': False, 'autosave_interval': 0})
    (path / 'server-settings.json').write_text(json.dumps(server_settings))
    established = run('establish', ['--start-server', str(save), '--server-settings', str(path / 'server-settings.json'),
        '--bind', '127.0.0.1', '--port', '34389', '--until-tick', '610'])
    assert 'stack traceback:' not in established, established[-6000:]
    save = path / 'write-data/saves/event-before.zip'
    assert save.exists(), established[-6000:]
    fixture = json.loads((path / 'write-data/script-output/event-fixture.json').read_text())
    shift = fixture['shift']
    assert shift > 0, fixture
    phases = [('broken', False, False), ('reload', True, False), ('upgrade', True, True)]
    for phase, fixed, upgrade in phases:
        install(path, mts, shift, fixed, upgrade)
        report_path = path / 'write-data/script-output/event-result.json'
        if report_path.exists(): report_path.unlink()
        log = run(phase, ['--benchmark', str(save), '--benchmark-ticks', '300', '--benchmark-runs', '1', '--benchmark-sanitize'])
        assert report_path.exists(), log[-6000:]
        report = json.loads(report_path.read_text())
        (path / f'{phase}-result.json').write_text(json.dumps(report, indent=2))
        failed = [key for key, value in report['checks'].items() if not value]
        print(json.dumps({'case': name, 'phase': phase, 'shift': shift, 'failed': failed,
            'teams': report['teams'], 'configuration_changed': report['configuration_changed']}), flush=True)
        if fixed:
            assert 'stack traceback:' not in log, log[-6000:]
            assert not failed, report
            assert report['configuration_changed'] == upgrade, report
        else:
            assert "to 'get_player' (string expected, got nil)" in log, 'Did not reproduce the supplied log'
            assert any(key.endswith(':enemies_spawned') for key in failed), report
            assert all((team['tracker'].get('triggered_events', 0) > 0) for team in report['teams'].values()), report
    print(f'PASS {name}', flush=True)


if __name__ == '__main__':
    cases = {'mts-space': (True, True), 'mts-vanilla': (False, True),
        'standalone-space': (True, False), 'standalone-vanilla': (False, False)}
    for name in os.environ.get('EVENT_RELOAD_CASES', ','.join(cases)).split(','):
        run_case(name, *cases[name])
