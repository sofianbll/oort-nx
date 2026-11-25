#!/usr/bin/env python3
"""Independent Python port of OortCloudPoint.field(), checked against the numbers the Swift source gives
(android/app/src/test/resources/goldens.json, made by make_goldens.swift). The Kotlin port in
core/OortCloud.kt is a line-by-line copy of this one: same float32 steps, same order of operations.
"""
import json
import math
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
GOLDENS = HERE.parent / "app/src/test/resources/goldens.json"


def f(x):  # round to float32, as Swift's Float and Kotlin's Float do after each operation
    return struct.unpack("f", struct.pack("f", x))[0]


PI = f(math.pi)


def field():
    seed = 5
    m = f(2147483647)  # 2147483648 once rounded, as Swift warns

    def random():
        nonlocal seed
        seed = seed * 16807 % 2147483647
        return f(f(seed) / m)

    points = []

    def add(x, y, z, kind, nx, ny, nz):
        points.append((x, y, z, kind, nx, ny, nz))

    shell = 9800
    golden = f(PI * f(3 - f(math.sqrt(5))))
    for i in range(shell):
        y = f(1 - f(f(2 * f(f(i) + f(0.5))) / f(shell)))
        r = f(math.sqrt(f(1 - f(y * y))))
        a = f(math.fmod(f(f(i) * golden), f(2 * PI)))
        x = f(f(math.cos(a)) * r)
        z = f(f(math.sin(a)) * r)
        if z > f(0.1):
            continue
        k = f(f(0.9) + f(f(0.1) * random()))
        add(f(x * k), f(y * k), f(z * k), 0.0, x, y, z)
    for j in range(9):
        r = f(1 - f(f(j) * f(0.0165)))
        count = 330 - j * 16
        for i in range(count):
            a = f(f(f(f(f(i) / f(count)) * 2) * PI) + f(f(j) * f(0.02)))
            side = f(math.cos(a))
            if side < f(0.15) and f(j) > f(f(f(3 + f(side * 3)) + 3)):
                continue
            add(f(f(math.cos(a)) * r), f(f(math.sin(a)) * r), f(f(0.1) - f(f(j) * f(0.003))), 1.0, 0.0, 0.0, 1.0)
    for k in range(30):
        t = f(f(0.16) + f(f(k) * f(0.0262)))
        count = int(math.floor(f(t * 150) + 0.5))
        thickness = f(f(0.004) + f(f(0.085) * f(math.pow(t, f(2.8)))))
        layers = max(1, int(math.floor(f(thickness / f(0.016)) + 0.5)))
        for j in range(layers):
            h = 0.0 if layers == 1 else f(f(f(f(j) / f(layers - 1)) - f(0.5)) * 2 * thickness)
            for i in range(count):
                a = f(f(f(f(i) + f(f((k + j) % 2) * f(0.5))) / f(count)) * 2 * PI)
                add(f(f(math.cos(a)) * t), h, f(f(math.sin(a)) * t), 2.0, 0.0, -1.0 if h < 0 else 1.0, 0.0)
    return points


def main():
    gold = json.loads(GOLDENS.read_text())["cloud"]
    pts = field()
    bad = []
    if len(pts) != gold["count"]:
        bad.append(f"count {len(pts)} != {gold['count']}")
    for kind, want in gold["kinds"].items():
        part = [p for p in pts if int(p[3]) == int(kind)]
        if len(part) != want["count"]:
            bad.append(f"kind {kind}: {len(part)} points != {want['count']}")
        for axis in range(3):
            got = sum(p[axis] for p in part)
            if abs(got - want["sum"][axis]) > 1.0:  # thousands of points, each phase within a float32 ulp of Swift's
                bad.append(f"kind {kind} axis {axis}: sum {got:.4f} != {want['sum'][axis]}")
    for s in gold["samples"]:
        got = pts[s["index"]] if s["index"] < len(pts) else None
        if got is None or any(abs(a - b) > 2e-3 for a, b in zip(got, s["point"])):
            bad.append(f"sample {s['index']}: {got} != {s['point']}")
    if bad:
        print("\n".join(bad))
        return 1
    print(f"cloud OK: {len(pts)} points, kinds {[v['count'] for v in gold['kinds'].values()]}, {len(gold['samples'])} samples within 2e-3 (a float32 ulp of the golden angle moves a point by up to 4e-4)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
