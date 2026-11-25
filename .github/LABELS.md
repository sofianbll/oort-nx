# Proposed labels

Proposal only: nothing is created or changed on GitHub. The maintainer creates the labels below before the templates use them, then applies them.

Existing labels on the repository are kept as they are, with their colours.

## Kind of work

| Label | Colour | Meaning | Applied by |
|---|---|---|---|
| `bug` (exists) | `#d73a4a` | Something does not work as expected | Form, triage |
| `enhancement` (exists) | `#a2eeef` | An idea or a need | Form, triage |
| `documentation` (exists) | `#0075ca` | Docs, guides, translations of docs | Triage |
| `question` (exists) | `#d876e3` | More information requested | Triage |
| `game` (new) | `#5319e7` | Compatibility report for one game | Form |
| `controller` (new) | `#1d76db` | Controller or input | Form |
| `translation` (new) | `#0e8a16` | Wording in one of the interface languages | Triage |
| `dependencies` (new) | `#0366d6` | Dependabot update | Dependabot |
| `duplicate` (exists) | `#cfd3d7` | Already reported; link the original | Triage |
| `invalid` (exists) | `#e4e669` | Does not match the project | Triage |
| `wontfix` (exists) | `#ffffff` | Will not be done | Maintainer |
| `good first issue` (exists) | `#7057ff` | Small, well defined, good for a first contribution | Maintainer |
| `help wanted` (exists) | `#008672` | The maintainer welcomes a contribution | Maintainer |

## Triage

| Label | Colour | Meaning |
|---|---|---|
| `blocking` (new) | `#b60205` | Stops a main use. Handled before `normal` |
| `normal` (new) | `#c2e0c6` | Everything else that needs handling |
| `needs-info` (new) | `#fbca04` | One specific detail is missing. Do not close while waiting |
| `upstream` (new) | `#bfd4f2` | The owner upstream is clear; the case is sent there |

Priority rule: at most one of `blocking` or `normal`. Data loss, leaked credentials and release tampering are handled first, in private.

## Source

| Label | Colour | Meaning |
|---|---|---|
| `nxnative` (new) | `#006b75` | The engine alone shows it |
| `nextendo` (new) | `#006b75` | The Nextendo integration |
| `steam` (new) | `#006b75` | The Steam integration |

## Platform

| Label | Colour | Meaning |
|---|---|---|
| `macos` (new) | `#ededed` | Mac app |
| `windows` (new) | `#ededed` | Windows alpha |
| `linux` (new) | `#ededed` | Linux alpha |
| `android` (new) | `#ededed` | Android alpha |
| `iphone-ipad` (new) | `#ededed` | iPhone and iPad alpha |

## Automation

| Label | Colour | Meaning |
|---|---|---|
| `ci:full` (new) | `#0052cc` | Runs the proof jobs (installed packages, emulator, simulators) on a pull request. Set by the maintainer only |
| `accessibility` (exists) | `#f143ab` | Barrier affecting people with disabilities |
