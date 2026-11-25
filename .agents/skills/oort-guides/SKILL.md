---
name: oort-guides
description: Write or correct an Oort NX guide or doc page so it matches the code: present tense, verified claims, same-change updates to the file map and architecture pages, and no appended dated sections. Use when a doc is wrong, missing or out of date after a change.
---

# Write or correct an Oort NX doc

## When to use

- A behaviour, a flow or a module changed and its doc did not.
- A new guide or a translation of a guide is requested.

## Steps

1. Read [AGENTS.md](../../../AGENTS.md), section "Documentation", and [docs/README.md](../../../docs/README.md) to pick the right folder.
2. Verify every claim against the code before writing it. Name real files and types.
3. Write in present tense. Put history in CHANGELOG.md, in `docs/history/`, or in git. Keep the *why* in one sentence next to the choice.
4. In the same change, update: the file-map row, the area in `architecture.md` (or the area's own page), `flows.md` if a flow changed, and `validation.md` if something awaits the maintainer's check.
5. Use short paragraphs, lists and tables. Link to the file, not to a copy of it.
6. Repository docs are in English. Keep a French text only when the maintainer asks for it, or for a player-facing guide that already exists in French.
7. Check the links you added resolve to existing files.

## Proof

- The list of claims checked, with the file and line for each.
- The list of pages updated in the same change.

## Stop

- Do not add a dated section at the end of a guide. Do not describe a planned feature as if it exists.
- Do not put private notes, product ideas or research in `docs/`. They stay in the private folder.
- If the code and the doc disagree and the code looks wrong, report it instead of documenting the bug.
