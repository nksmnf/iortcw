#!/usr/bin/env python3
"""Fail the build if Loc.swift declares the same key twice.

Swift traps on a dictionary literal with a duplicate key -- a fatalError inside
the one-time initialiser, so the process dies the first time anything asks for
a translation. That is the launcher's first draw, which means the application
does not start at all, and the crash report names Loc.s rather than the line at
fault.

Nothing in the compiler catches this: the literal builds without a warning. So
it is checked here, where a duplicate costs a build error rather than an
install that cannot be opened.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.normpath(os.path.join(HERE, '..', 'Launcher', 'Loc.swift'))

# Each dictionary is checked on its own: the same key may legitimately appear
# in `table` and in `notes`, which are looked up separately.
DICT_START = re.compile(r'^\s+(?:private\s+)?static\s+let\s+(\w+)\s*:\s*\[')
ENTRY = re.compile(r'^\s+"((?:[^"\\]|\\.)+)"\s*:')


def main():
    with open(SOURCE, encoding='utf-8') as handle:
        lines = handle.read().split('\n')

    failures = []
    name = None
    seen = {}

    for number, line in enumerate(lines, 1):
        opening = DICT_START.match(line)
        if opening:
            name = opening.group(1)
            seen = {}
            continue

        if name is None:
            continue

        if line.strip() == ']':
            name = None
            continue

        entry = ENTRY.match(line)
        if not entry:
            continue

        key = entry.group(1)
        if key in seen:
            failures.append((name, key, seen[key], number))
        else:
            seen[key] = number

    for table, key, first, again in failures:
        print(f'{SOURCE}:{again}: error: duplicate key "{key}" in {table}, '
              f'first declared on line {first}', file=sys.stderr)

    if failures:
        print(f'{len(failures)} duplicate key(s) -- Swift would trap on the '
              f'first lookup and the launcher would never draw.', file=sys.stderr)
        return 1

    return 0


if __name__ == '__main__':
    sys.exit(main())
