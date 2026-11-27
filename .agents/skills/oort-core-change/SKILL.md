---
name: oort-core-change
description: Apply the core criteria of Oort NX to logic: contracts, tests first, data and compatibility, errors and recovery, network, concurrency, modules, performance, security. Use with oort-change.
---

# Core change

## When to use

- A rule, model, service, file format, request, process, engine call or migration is added or changed.

## Steps

1. **Contract (C1, C20).** Write inputs, outputs, errors and the owner. Then list every reader of what changes: search the key, the case, the file name, the notification, in all modules, tests, probes and ports. Change a format with all its readers, or not at all.
2. **Fail first (C2, C3).** A test that shows the need, and one per way it can go wrong: cancelled, interrupted, offline, late, full disk, unreadable, concurrent. Keep the red output.
3. **Place (C4, C5).** The lowest module that can hold it. No interface import below `OortMac`; nothing new in `AppViewModel`.
4. **Data (C6–C9).** Open a file of the previous version. Write aside, check, swap. Trash, never delete. `AppData` only.
5. **Errors and return (C10, C11, C23).** Typed, seen, with a next step. Cut the work at each step and start again.
6. **Network and access (C12–C14, C18).** Count the requests before the player's yes: zero. Bound sizes, hosts, paths, links. Nothing secret in a log.
7. **Concurrency (C15–C17).** Build with complete checking before and after; compare the warnings. A result carries the identity it was asked for.
8. **Cost (C19).** Measure before and after, or do not say faster.
9. **Engine (C21) and honesty (C22).** Exact pin, no patch, no hidden delay.
10. A player sees the effect: use oort-visual-change too.

## Proof

- The list of readers, with file and line.
- Red then green output of the new tests, then the area's suite, in a throwaway home.
- `check_oort_core.py`, `check_publication.py`, and `check_module_boundaries.py` where it exists.
- Concurrency warnings before and after.
- For data: the old file, the new file, the way back. For network: the count of requests.

## Stop

- A real library, save, key, account or preference domain would be opened: use a copy made of synthetic data.
- A reader cannot be changed in the same commit: keep the old format beside the new one and say until when.
- The failure is not understood after two repairs: report the cause you suspect and what would prove it.
