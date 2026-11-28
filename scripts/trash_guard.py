#!/usr/bin/env python3
"""Run a command so that it cannot use the user's Trash, and fail if it did anyway.

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
    """(name, inode) of each entry; an unreadable or missing Trash is an empty one."""
    try:
        return {(entry.name, entry.inode()) for entry in os.scandir(folder)}
    except OSError:
        return set()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--trash", default=str(Path.home() / ".Trash"), help="the Trash to watch (default ~/.Trash)")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args(argv)
    command = args.command[1:] if args.command[:1] == ["--"] else args.command
    if not command:
        parser.error("no command")
    before = entries(args.trash)
    own = tempfile.mkdtemp(prefix="oort-trash-")
    try:
        status = subprocess.run(command, env=dict(os.environ, OORT_TRASH=own)).returncode
    finally:
        shutil.rmtree(own, ignore_errors=True)
    added = sorted(name for name, _ in entries(args.trash) - before)
    for name in added:
        print(f"trash_guard: {args.trash} gained {name!r}; a test or a probe used the user's Trash", file=sys.stderr)
    return 1 if added else status


if __name__ == "__main__":
    sys.exit(main())
