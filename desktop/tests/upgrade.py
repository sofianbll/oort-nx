#!/usr/bin/env python3
"""Write a synthetic library with alpha.2; read the very same data after the update. No game runs."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import subprocess
import sys
import time

phase, core, folder = sys.argv[1:]
root = Path(folder).resolve()
home = root / 'upgrade-home'
home.mkdir(exist_ok=True)
args = [core, '--data', str(root / 'upgrade-data'), '--system', 'linux', '--home', str(home)]


@contextmanager
def connect():
    with subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
                          env={**os.environ, 'HOME': str(home)}) as child:
        def ask(method, **params):
            child.stdin.write(json.dumps({'id': 1, 'method': method, 'params': params}) + '\n')
            child.stdin.flush()
            reply = json.loads(child.stdout.readline())
            assert 'error' not in reply, reply
            return reply['result']

        yield ask
        child.stdin.close()
        assert child.wait() == 0


expected = {'before': '0.1.0-alpha.2', 'after': '0.1.0-alpha.3'}[phase]
if phase == 'before':
    with connect() as ask:
        assert ask('hello')['version'] == expected
        ask('folders.add', path=str(root / 'games'))
        ask('programs.add', program=str(root / 'emulator'), name='Old program')
        game = next(g for g in ask('library')['games'] if g['name'] == 'Lunar Observatory')
        ask('game.favorite', id=game['id'], on=True)
        session = ask('session.start', id=game['id'])
        time.sleep(1)
        ask('session.end', session=session)
        ask('settings.set', id='colorThemeID', value='nord')
        ask('settings.save')
        ask('guide', seen=True)

# Compare two readings from disk: the live core has subsecond dates that its store does not keep.
with connect() as ask:
    hello = ask('hello')
    assert hello['version'] == expected, hello['version']
    games = sorted([g['id'], g['name'], g['favorite'], g['seconds'], g['last']] for g in ask('library')['games'])
    sources = ask('folders')

palette = hello['view']['palette']
assert palette == 'nord', palette
state = {'games': games, 'sources': sources, 'palette': palette}
saved = root / 'upgrade-library.json'
if phase == 'before':
    assert len(games) > 20 and any(g[1] == 'Old program' for g in games)
    assert any(g[1] == 'Lunar Observatory' and g[2] and g[3] > 0 and g[4] for g in games)
    assert len(sources['folders']) == 1 and sources['folders'][0]['found'], sources
    saved.write_text(json.dumps(state), encoding='utf8')
else:
    before = json.loads(saved.read_text(encoding='utf8'))
    for key, value in state.items():
        assert before[key] == value, f'{key} changed after the update'
print(phase, expected, len(games), 'games')
