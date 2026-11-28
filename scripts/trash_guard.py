#!/usr/bin/env python3
"""Give a command a private Trash and check that the watched Trash gains no entry.

The command gets a Trash of its own (OORT_TRASH, a new temporary folder that OortSystem.currentTrash reads). The
user's Trash (~/.Trash, or --trash) is listed before and after: an entry that appears meanwhile fails the run, and
nothing in that Trash is ever moved or deleted here.

Usage: trash_guard.py [--trash DIR] -- COMMAND...
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def entries(folder):
    """(name, inode) of each entry; only an absent Trash counts as empty."""
    try:
        with os.scandir(folder) as contents:
            return {(entry.name, entry.inode()) for entry in contents}
    except FileNotFoundError:
        return set()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--trash", default=str(Path.home() / ".Trash"), help="the Trash to watch (default ~/.Trash)")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("no command")
    try:
        before = entries(args.trash)
    except OSError as error:
        print(f"trash_guard: cannot observe Trash before the command: {error}", file=sys.stderr)
        return 1
    own = tempfile.mkdtemp(prefix="oort-trash-")
    try:
        status = subprocess.run(command, env=dict(os.environ, OORT_TRASH=own)).returncode
    finally:
        shutil.rmtree(own, ignore_errors=True)
    try:
        added = entries(args.trash) - before
    except OSError as error:
        print(f"trash_guard: cannot observe Trash after the command: {error}", file=sys.stderr)
        return 1
    if added:
        print(f"trash_guard: {len(added)} new entry or entries in the watched Trash", file=sys.stderr)
        return 1
    return status


if __name__ == "__main__":
    sys.exit(main())
