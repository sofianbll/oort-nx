---
name: oort-release
description: Prepare an Oort NX release for the maintainer: clean tree, checks, pinned engine, French notes, CHANGELOG move and artifact digests. Use when the maintainer asks for a release candidate or a package check. Never publishes, tags or pushes without an explicit request for that exact step.
---

# Prepare an Oort NX release

## When to use

- The maintainer asks to prepare, verify or describe a release.
- Do not use it to publish. Publishing is a separate, explicit action by the maintainer.

## Steps

1. Read [development.md, Release packaging](../../../docs/working-on-it/development.md#release-packaging) and [branch rules](../../../docs/working-on-it/branch-rules.md).
2. Check the tree is clean and on `main`: `git status --short` is empty. `scripts/release.sh` refuses a dirty tree.
3. Check the version in `VERSION` matches the intended release, and that the engine pin is an exact commit of a tested fork, never a branch.
4. Run the checks in CONTRIBUTING.md, including `python3 scripts/check_publication.py`. Record each result.
5. Move the **Unreleased** entries of [CHANGELOG.md](../../../CHANGELOG.md) into a dated section only for a release that is actually published. Until then, keep them under Unreleased.
6. Draft the French notes from [perso-release-notes.md](../../../docs/working-on-it/perso-release-notes.md). Link the engine commit and the known limits.
7. Build the package with `scripts/release.sh` without publishing. Record the SHA-256 of each artifact.
8. List what remains for the maintainer: manual checks, notarisation, the release decision.

## Proof

- Tree state, version, engine pin and each check with its result.
- SHA-256 digests of the local artifacts.
- The draft notes, in French.

## Stop

- Never run `--publish`, create a tag, or push without an explicit request for that step.
- A check that fails blocks the release. Report it with its output; do not skip it.
- Changing the engine pin or the signing identity is the maintainer's decision.
