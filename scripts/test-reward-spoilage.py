#!/usr/bin/env python3
"""Load legacy clogged buffers, then check recovery and native reward spoilage."""
import concurrent.futures
import importlib.util
import os
from pathlib import Path
import sys

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('cargo_test', Path(__file__).with_name('test-cargo.py'))
cargo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cargo)


def run(name):
    cases = {'nonorbit': (False, False), 'platform': (False, True),
             'mts': (True, False), 'mts-platform': (True, True)}
    cargo.run_case('spoilage-' + name, *cases[name], probe='reward-spoilage-probe.lua', ticks=18000)


if __name__ == '__main__':
    cases = os.environ.get('SPOILAGE_CASES', 'nonorbit,platform,mts,mts-platform').split(',')
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        list(pool.map(run, cases))
