---
name: oort-change
description: Start here for any change to Oort NX, before writing code. Decides whether it is visual, core or both, loads the matching skill, and gives the checklist to fill in the pull request.
---

# Change Oort NX

## When to use

- Before the first edit of a feature, a fix or a redesign, on any system.
- Not for an issue to sort or a release to prepare: those have their own skills. A page of documentation alone needs G6, G7, G8 and G10 only.

## Steps

1. Write the need in one sentence and the smallest scope that meets it (G1). Touches data, access, the engine or a release: the maintainer agrees on the scope first.
2. Choose the list. When in doubt, both.

   | The diff touches | Skill |
   |---|---|
   | `apps/mac/` screens, a catalog string, an icon, a sound, a token, a menu, a hint, or a screen on a platform branch | [oort-visual-change](../oort-visual-change/SKILL.md) |
   | `core/`, `engines/`, a model or a service, a file format, the network, an engine call, a script that ships | [oort-core-change](../oort-core-change/SKILL.md) |
   | A rule a player sees the effect of: an order, a filter, a default, an error message, a name | both |

3. Read G1–G10 in [change-criteria](../../../docs/working-on-it/change-criteria.md), then the rows of the skill. A row is met, not concerned with its reason, or a gap with its reason. Never blank.
4. Run the base before the change: `scripts/check` and the relevant groups or heavy steps from `scripts/check --list`. For Swift and Mac probes, follow **Test isolation** below. Keep the output.
5. Make the change with the skill open. Two repairs per problem at most, then stop and report.
6. Run the same commands after, with `scripts/check --base <base>`: debt lists only shrink.
7. Fill the checklist below in the pull request.

### Test isolation

- Use `scripts/check swift` and `scripts/check app-probes BATCH` with synthetic data. Verify the checked-out wrapper calls `scripts/trash_guard.py`: revisions with the Trash fix set a temporary `OORT_TRASH` and fail if the real Trash gains an entry.
- On a revision without the guard, skip tests and probes that can touch the real Trash unless an isolated test account is available. A temporary `HOME` alone is not proof. Do not bypass the guarded steps with raw `swift test` or direct probes.

## Proof

Paste this, one line per row that applies:

~~~markdown
### Criteria
Need: … · Kind: visual / core / both
| ID | Met, not concerned, or gap | Proof (command, test, capture) |
|---|---|---|
| G1 | | |

Systems (G5): macOS … · Windows and Linux … · Android … · iPhone and iPad …
Debt: before … → after …
Run: … · Looked at: … · Not tried: …
~~~

## Stop

- Two criteria disagree, or a row would need a decision: quote both, keep what exists, ask.
- A criterion can only be met by raising a debt list. That is the maintainer's decision.
- Nothing is pushed, published, installed or posted without an explicit go.
