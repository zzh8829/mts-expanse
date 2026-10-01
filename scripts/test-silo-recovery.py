#!/usr/bin/env python3
"""Exercise actual native rockets through soft reset, recovery and mission credit."""
import concurrent.futures
import importlib.util
from pathlib import Path
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('cargo_test', Path(__file__).with_name('test-cargo.py'))
cargo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cargo)

def run(case):
    name, mts, platform = case
    cargo.run_case('silos-' + name, mts, platform, probe='silo-recovery-probe.lua', ticks=7200)

if __name__ == '__main__':
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(run, [('nonorbit', False, False), ('mts', True, False), ('platform', False, True)]))
