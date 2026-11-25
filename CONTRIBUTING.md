# Contributing to Oort NX

Oort NX is an independent fork of [Arcane by Bium23](https://github.com/Bium23/NxLibrary).
Use the Oort NX bug or idea form after checking for an existing issue. For a
security issue or possible leak, follow [SECURITY.md](SECURITY.md) instead.

Describe what you expected, what happened, and how to reproduce it. For translation
feedback, include the language, the current wording and a suggested correction.

## Triage

- Handle suspected data loss, leaked credentials and release tampering first. Keep sensitive reports private.
- Mark the type, then add at most one priority (`blocking` or `normal`) and one source (`nxnative`, `nextendo` or `steam`) when known. If details are missing, use `needs-info` and ask for one specific detail. Do not close automatically while waiting.
- Link the original before marking a `duplicate`. Use `upstream` only when the owner is clear. Send a case to Arcane only if it also happens in unmodified Arcane, or to nxnative if it reproduces with the engine alone.
- Review changes to data, access, the engine or the release process explicitly. The maintainer decides, replies and merges. Passing checks are not approval to publish or install.

Keep discussions about the work. Harassment, personal attacks and sharing someone
else's private information are not welcome. Report abuse privately to a
maintainer or use GitHub's report tools.

## Maintainer workflow

Start with [README](README.md), [AGENTS.md](AGENTS.md),
[architecture](docs/how-it-works/architecture.md) and [conventions](docs/working-on-it/conventions.md).

Keep changes small and preserve Play for existing apps. Never patch the user's
nxnative checkout, silently follow upstream main, or bypass the compatibility
gate. Engine upgrades use the [upgrade checklist](docs/history/engine-upgrades/README.md).

Before submitting:

~~~sh
python3 scripts/check_publication.py
python3 scripts/check_localizations.py
python3 scripts/check_selene_tokens.py
python3 -m unittest discover -s Tests/PublicationChecks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --jobs 6
~~~

Use Xcode 27.2 to match the checks. For interface changes, follow the
[development guide](docs/working-on-it/development.md#verification) and show the affected Selene screens with synthetic data. Interactive app and game checks are performed manually. Describe which checks
you performed, including the engine/compiler combination and whether the
untested-toolchain override was used. Compilation alone does not verify a game.

Do not include games, keys, extracted content, personal configuration or raw
diagnostic files. Use synthetic fixtures in tests. Review copied diagnostics
before sharing them, and remove anything personal that remains.

Use scripts/release.sh for packaged releases. Publishing is an explicit
maintainer action; the CI only checks the code and does not publish anything.

Record user-visible changes under **Unreleased** in [CHANGELOG.md](CHANGELOG.md).
Keep the description focused on the resulting behaviour. Move entries into a
dated version section when that release is actually published; unreleased work
must not appear as an already available release.

## Importing from Arcane

Oort NX does not automatically merge or follow Arcane. Start with an Oort NX need
and get the scope reviewed. Check the Arcane commit, author, licence, dependencies
and a test that demonstrates the benefit. Import one commit at a time with
`git cherry-pick -x` when it fits without changes. For an adaptation, keep the
original author credited, link the full source commit and explain what changed.

Credit [Arcane by Bium23](https://github.com/Bium23/NxLibrary) and
[Selene by Matthew Silva](https://github.com/mattxslv/Selene) for work based on
them. Credit [Josef Nemec and Playnite](https://github.com/JosefNemec/Playnite)
for any picker work taken from Playnite, and preserve each applicable licence and
notice. A code licence is not permission to reuse branding or other assets.
Every project, service, font or symbol in use has its entry in
[design/credits.json](design/credits.json), the only list: run
`python3 scripts/generate_credits.py` after editing it.
If an import needs more than half a day, discuss it separately. Offer reusable
fixes upstream according to [Arcane's guide](https://github.com/Bium23/NxLibrary/blob/main/CONTRIBUTING.md).

## Interface translations

The shared source is `Sources/NXLibraryCore/Resources/Localizable.xcstrings`. It includes en, it, fr, de, es, pt-BR and zh-Hans. Keep keys stable, preserve every typed placeholder, provide quantity variants, and leave product names, technical identifiers and user-provided content unchanged. Record the language and whether a fluent speaker reviewed the change.

Run `python3 scripts/check_localizations.py` and the publication regressions after editing the catalog. A development build also checks its compiled resources. The initial translations await maintainer validation; no external translation-hosting service is required.
