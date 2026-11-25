# Player guides

One guide per system and subject, in French and English, with a picture per step. The site reads these files; nothing is written twice. [features.json](../features.json) says what each system can do.

```
docs/features.json                     the matrix: feature, system, state, version, proof
docs/guides/<fr|en>/<system>/<topic>.md
docs/guides/media/<system>/<name>.<fr|en>.webp    or <name>.webp when one picture serves both languages
```

Systems: `mac`, `windows`, `linux`, `android`, `ios`. Topics: `install`, `first-launch`, `add-…` (one per kind of game), `play`, `controls`, `settings`, `cloud`, `saves`, `updates`, `uninstall`, `troubleshooting`, `data`. Every system answers all of them, except `cloud`.

## A guide

```
---
title: Installer
system: windows
topic: install
order: 1
version: 0.1.0-alpha.2
minutes: 5
tried: One sentence: what was tried, and what was not.
captures: first-empty, missing:smartscreen
---

## Step title
<!-- step open checked f18e2119:desktop/tests/windows/prove.ps1 -->
One to three short sentences. In French, say “tu”. The app's own words are in bold.

![What the picture shows](../../media/windows/first-empty.fr.webp)
```

| Part | Rule |
|---|---|
| `captures` | The picture of each step, in order, the same in both languages. `missing:id` when there is none yet; the step then has `<!-- missing id: what it must show -->` instead of a picture. |
| `step id state proofs…` | The same in both languages. |
| `played` | A person did it on a real machine. |
| `checked` | An automatic check did it with invented games, or drew the screen. |
| `code` | Read in the published code or guide, not tried. |
| `elsewhere` | Another project's page, never tried by us. Needs its https address. |
| A proof | `commit:path` (eight letters, the published commit), a file of this repository, or an https address. |

## Pictures

Invented games only: no real cover, name, account, key or personal path. WebP, at most 200 KB, a stable name. Crop nothing that changes the meaning.

| Pictures | From |
|---|---|
| `mac/` | The probes of `Tests/CatalogAppChecks` at `bf0c3410`, in a throwaway home. In the copies that drew them, the probe's test gradient was replaced by the app's own night colours, and the tour and the save question were drawn a second time in English. `dmg` is a Finder picture of an earlier trial of the same window. |
| `windows/`, `linux/` | The proofs of `desktop/tests` at `f18e2119`. Linux steps without a picture of their own use the Windows one, and say so. |
| `android/` | `android/tools/emulator_check.py` at `1aaff5c0`, Android 16. |
| `ios/` | `mobile/UITests` at `e3cd6df1`, simulator. |

## After a release

1. Change the version and commit of the system in `features.json`, look at each of its cells again, then write the new version in them.
2. Do the same for its guides.
3. Run `python3 scripts/check_guides.py --strict`. `--json <file>` writes everything the site needs.
