#!/usr/bin/env python3
"""Verify a launcher checkpoint and extract it to a new, private folder. Never restores in place."""
import argparse
import hashlib
import os
import plistlib
from pathlib import Path
import stat

MAXIMUM_BYTES = 128 * 1024 * 1024
PREFERENCES = "preferences-du-lanceur.plist"


def extract(source: Path, destination: Path) -> list[str]:
    with os.fdopen(os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("la copie n'est pas un fichier ordinaire")
        encoded = stream.read(MAXIMUM_BYTES + 1)
    if len(encoded) > MAXIMUM_BYTES:
        raise ValueError("copie trop volumineuse")
    snapshot = plistlib.loads(encoded)
    if snapshot["generation"] != 1:
        raise ValueError("génération inconnue")
    items = snapshot["files"].copy()
    if len(items) > 8192 or PREFERENCES in items:
        raise ValueError("inventaire invalide")
    if "preferences" in snapshot:
        items[PREFERENCES] = snapshot["preferences"]
    occupied = set()
    for relative, item in items.items():
        parts = relative.split("/")
        if (len(parts) > 5 or any(part in ("", ".", "..") or "\x00" in part for part in parts)
                or Path(relative).is_absolute()
                or any("/".join(parts[:i]) in items for i in range(1, len(parts)))):
            raise ValueError(f"chemin invalide : {relative!r}")
        if relative.casefold() in occupied:
            raise ValueError(f"nom en double : {relative!r}")
        occupied.add(relative.casefold())
        if hashlib.sha256(item["data"]).digest() != item["sha256"]:
            raise ValueError(f"empreinte invalide : {relative!r}")

    destination.mkdir(mode=0o700)  # Existing folders are intentionally refused.
    for relative, item in items.items():
        target = destination / relative
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with target.open("xb") as stream:
            os.fchmod(stream.fileno(), 0o600)
            stream.write(item["data"])
    return sorted(items)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        print("\n".join(extract(args.source, args.destination)))
    except (OSError, KeyError, TypeError, ValueError) as error:
        parser.exit(1, f"Extraction refusée : {error}\n")
