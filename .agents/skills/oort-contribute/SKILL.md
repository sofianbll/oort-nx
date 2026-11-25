---
name: oort-contribute
description: Prepare a contribution to Oort NX: pick the right system, run the checks from CONTRIBUTING.md, keep private data out, and draft the pull request. Use when someone wants to fix a bug, add a change or open a pull request on this repository. Never pushes, opens or comments.
---

# Prepare a contribution to Oort NX

## When to use

- A contributor or the maintainer wants a change ready for review.
- Do not use it to publish, to triage issues (see `oort-triage`) or to release (see `oort-release`).

## Steps

1. Read [CONTRIBUTING.md](../../../CONTRIBUTING.md), [AGENTS.md](../../../AGENTS.md) and the area in [architecture-map](../../../docs/working-on-it/architecture-map.md).
2. Check for an existing issue with the same symptom. If one exists, link it. Do not duplicate it.
3. Keep the change to one behaviour. If it touches data, access, the engine or releases, stop and ask the maintainer for the scope first.
4. Put code in the module the map names. Keep the layer order: `OortCore` < `NXLibraryCore` < `ArcanePorting` < `NXLibrary`.
5. Run the checks listed in CONTRIBUTING.md, "Test before you open a pull request". Record the results and the exact command. Do not claim a check passed if it did not run.
6. For a visible change, capture each changed screen with synthetic data only. Remove paths, account names and notifications.
7. Update the same change: the row in [file-map](../../../docs/working-on-it/file-map.md) for any new file, and an **Unreleased** entry in [CHANGELOG.md](../../../CHANGELOG.md) for a user-visible change.
8. Write the pull request body with [the template](../../../.github/PULL_REQUEST_TEMPLATE.md). Name the manual check that remains.

## Proof

- The list of commands run, with results.
- The diff summary: files, and why each one changed.
- The captures, or "no visible change".

## Stop

- A secret, a key, a game file, a save or a personal path appears in the diff: remove it, report that it was there, and stop.
- A check fails twice after a fix: report the attempts and the likely cause. Do not keep patching.
- Pushing, opening the pull request and commenting need the maintainer's explicit go. Prepare the draft and wait.
