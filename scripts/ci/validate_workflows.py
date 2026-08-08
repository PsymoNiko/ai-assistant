#!/usr/bin/env python3
"""Validate all JSON workflow exports under workflows/ by parsing them.
Exits with code 1 if any file is invalid JSON.
"""
import json
import glob
import sys

paths = sorted(glob.glob('workflows/*.json'))
if not paths:
    print('No workflow JSON files found.')
    sys.exit(0)

ok = True
for p in paths:
    try:
        with open(p, 'r', encoding='utf-8') as f:
            json.load(f)
        print(f'OK: {p}')
    except Exception as e:
        print(f'ERROR: {p}: {e}', file=sys.stderr)
        ok = False

if not ok:
    print('One or more workflow JSON files are invalid.', file=sys.stderr)
    sys.exit(1)

print('All workflow JSON files validated successfully.')
