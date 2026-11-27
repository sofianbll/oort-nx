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
   | `apps/mac/OortMac/Views`, a string of the catalog, an icon, a sound, a token, a menu, a hint, `desktop/ui`, `android/.../ui`, `mobile` screens | [oort-visual-change](../oort-visual-change/SKILL.md) |
   | `OortCore`, `OortLibrary`, `ArcanePorting`, a model or a service, a file format, the network, an engine call, a script that ships | [oort-core-change](../oort-core-change/SKILL.md) |
   | A rule a player sees the effect of: an order, a filter, a default, an error message, a name | both |

3. Read G1–G10 in [change-criteria](../../../docs/working-on-it/change-criteria.md), then the rows of the skill. A row is met, not concerned with its reason, or a gap with its reason. Never blank.
4. Run the base before the change: `scripts/check` and the tests of the area. Keep the output.
5. Make the change with the skill open. Two repairs per problem at most, then stop and report.
6. Run the same commands after, with `scripts/check --base <base>`: debt lists only shrink.
7. Fill the checklist below in the pull request.

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
