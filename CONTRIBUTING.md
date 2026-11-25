# Contributing to Oort NX

Thank you for helping. Oort NX is an independent app that organizes and launches Switch games through the nxnative engine. It is derived from [Arcane by Bium23](https://github.com/Bium23/NxLibrary) and is maintained on its own. Participation follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Start here

1. Read the [README](README.md) to know what the app does today.
2. Search the [issues](https://github.com/sofianbll/oort-nx/issues) for your problem or idea before you open one.
3. Choose the form that fits:

| You have… | Use |
|---|---|
| A bug on macOS, Windows, Linux, Android or iPhone/iPad | The bug form for that system |
| An idea or a need | The idea form. Describe the need before the solution |
| A game that starts, plays or fails | The game form (no game files) |
| A controller that does not work as expected | The controller form |
| A wrong or unclear translation | An issue with the language, current wording and a suggested correction |
| A security problem or a possible leak | [SECURITY.md](SECURITY.md), privately. Never in a public issue |

Keep a first pull request small: one behaviour, one reason. For a change that touches data, access, the engine or releases, open an issue first and agree on the scope.

## Pick your system

| System | Where the code is | Status |
|---|---|---|
| macOS | `main`: `Sources/NXLibrary` (app), `Sources/NXLibraryCore`, `Sources/ArcanePorting`, `Sources/OortCore` | Main product |
| Windows and Linux | `alpha/windows` branch (`desktop/`) | Alpha. Ask in an issue before a pull request |
| Android | `alpha/android` branch (`android/`) | Alpha. Ask in an issue before a pull request |
| iPhone and iPad | `alpha/ios` branch (`mobile/`) | Alpha. Ask in an issue before a pull request |

The core rules for every system live in `Sources/OortCore` (Foundation only) and `Sources/NXLibraryCore`. The allowed dependencies between modules are in the [architecture map](docs/working-on-it/architecture-map.md). Check them with `python3 scripts/check_module_boundaries.py`.

Read before you change code:

1. [AGENTS.md](AGENTS.md): the project rules.
2. [Architecture](docs/how-it-works/architecture.md) and [architecture map](docs/working-on-it/architecture-map.md).
3. [Conventions](docs/working-on-it/conventions.md): where new code goes, with one recipe per kind of change.
4. [File map](docs/working-on-it/file-map.md): one row per file. Update it in the same change.

## Set up

- macOS with Xcode 27.2. Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for Swift commands.
- Python 3 for the scripts in `scripts/`. No package install is needed for the checks.
- Never patch the engine checkout on your Mac. The engine is pinned by URL and commit. See the [development guide](docs/working-on-it/development.md).

## Test before you open a pull request

Start any change with the [oort-change](.agents/skills/oort-change/SKILL.md) list: it picks the [criteria](docs/working-on-it/change-criteria.md) that apply. Then run the same checks as CI:

~~~sh
python3 scripts/check_publication.py
python3 scripts/check_localizations.py
python3 scripts/generate_oort_tokens.py --check
python3 scripts/check_selene_tokens.py --base main
python3 scripts/check_module_boundaries.py
python3 scripts/check_ui_rules.py --base main
python3 scripts/check_vocabulary.py
python3 scripts/check_guides.py
python3 -m unittest discover -s Tests/PublicationChecks
python3 -m unittest discover -s Tests/ModuleChecks
python3 -m unittest discover -s Tests/SkillChecks
python3 -m unittest discover -s Tests/CIChecks
python3 -m unittest discover -s Tests/UIRulesChecks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --jobs 6
~~~

Durations below come from the GitHub Actions history of 25 November 2026. They are not a guarantee.

| Check | Where it runs | Duration seen |
|---|---|---|
| Mac: checks and Swift tests | `Mac / checks` and `Mac / Swift tests` jobs, `xcode-27` | About 22 min (one run) |
| Windows and Linux: core and packages | `Desktop` workflow, alpha branch | About 20 min (median of 8) |
| Android: checks, unit tests, APK | `Android` workflow, alpha branch | About 32 min (median of 7) |
| iPhone and iPad: tests, simulators | `iPhone and iPad` workflow, alpha branch | About 42 min (median of 6) |

| Script | What it holds | Its tests |
|---|---|---|
| `check_module_boundaries.py` | The order of the modules | `Tests/ModuleChecks` |
| `check_ui_rules.py` | Interface rules a script can measure; the debt in `scripts/ui-rules.json` only shrinks | `Tests/UIRulesChecks` |
| `check_vocabulary.py` | The same words on every system; the debt in `design/vocabulary-debt.json` only shrinks | `Tests/PublicationChecks` |
| `check_guides.py` | Player guides and the feature matrix | `Tests/PublicationChecks` |

Passing checks prove the code builds and that the automated rules hold. They do not replace a manual check of the app, a controller or a real game. Say which checks you ran and which manual check is still needed.

Use synthetic fixtures in tests. Never commit a game, a key, a save, an extracted file or a personal path.

## Screenshots

- Use synthetic data only: the headless harness and the fixtures in `Tests/`.
- Crop to the changed screen. Remove personal paths, account names, serial numbers and notifications.
- For a visual change, show each changed screen before and after, in French and in English when the text changed.
- Prepare publishable images as described in [docs/media](docs/media/README.md). Do not commit a screenshot unless it illustrates the documentation.

## Credits and licences

- The code is under the [MIT licence](LICENSE). Your contribution is under the same licence.
- Keep the notices in [NOTICE](NOTICE) and each licence of the code you reuse.
- Credit [Arcane by Bium23](https://github.com/Bium23/NxLibrary) for work it contains, and [Selene by Matthew Silva](https://github.com/mattxslv/Selene) for the design system. Credit [Josef Nemec and Playnite](https://github.com/JosefNemec/Playnite) for any picker work taken from Playnite.
- A licence on code is not permission to use branding or other assets.
- Every project, service, font or symbol in use has its entry in [design/credits.json](design/credits.json), the only list: run `python3 scripts/generate_credits.py` after editing it.
- A new dependency needs a compatible licence, an entry in `design/credits.json` and `NOTICE` and, for the engine runtime, an entry in `runtime.lock`.

### Importing from Arcane

Oort NX does not merge or follow Arcane automatically. Start from an Oort NX need, then check the Arcane commit, its author, its licence, its dependencies and a test that shows the benefit.

- Import one commit at a time with `git cherry-pick -x` when it applies cleanly.
- For an adaptation, keep the original author, link the full source commit and explain the changes.
- If an import takes more than half a day, discuss it in an issue first.
- Offer reusable fixes upstream, following [Arcane's guide](https://github.com/Bium23/NxLibrary/blob/main/CONTRIBUTING.md).

## Interface translations

The shared source is `Sources/NXLibraryCore/Resources/Localizable.xcstrings`. It covers en, it, fr, de, es, pt-BR and zh-Hans.

- Keep keys stable and every typed placeholder.
- Provide quantity variants where the text counts things.
- Leave product names, technical identifiers and user content unchanged.
- Record the language in the pull request and whether a fluent speaker reviewed it.

Run `python3 scripts/check_localizations.py` after any edit.

## What we refuse

- Games, ROMs, dumps, firmware, extracted game content and other people's save files.
- Keys, tokens, passwords, certificates and any credential. Do not paste them in issues or commits.
- Personal paths, raw diagnostic files and logs that were not reviewed.
- Nintendo artwork, except the two reviewed platform marks listed in `scripts/check_publication.py`.
- Code that bypasses the compatibility gate, patches a user's engine checkout or follows an engine branch without a pin.
- Circumvention of copy protection, or instructions for it.
- Data collection or telemetry without a clear opt-in and a review.
- Harassment, personal attacks or sharing someone else's private information.

## Pull requests

- Name the branch `feat/`, `fix/`, `docs/` or `chore/` followed by the topic.
- Use the [pull request template](.github/PULL_REQUEST_TEMPLATE.md), criteria list included. French or English is fine.
- State the problem, the change, the checks you ran and the manual check that remains.
- Record a user-visible change under **Unreleased** in [CHANGELOG.md](CHANGELOG.md), focused on the resulting behaviour.
- The maintainer reviews, decides and merges. Passing checks are not approval to publish or install.
- Releases go through `scripts/release.sh` and only the maintainer runs them. See [branch rules](docs/working-on-it/branch-rules.md).
