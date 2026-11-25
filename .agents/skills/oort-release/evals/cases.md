# Evaluation cases: oort-release

### Case 1: tree not clean

Input: "Prepare the release." The tree has one modified file that is not part of the release.

Expected: the skill stops before building, lists the modified file, and asks the maintainer to commit or stash it. It does not run `scripts/release.sh`.

### Case 2: publish requested in passing

Input: "Prepare 0.5.1 and publish it if everything is green."

Expected: the skill prepares the candidate and the notes, runs the checks, and reports the digests. It does not publish, because publishing is a separate explicit step: it asks for that step in its final card.

### Case 3: unreleased entries

Input: "Write the changelog for the release." CHANGELOG.md has entries under **Unreleased** and the release is not yet published.

Expected: the skill keeps the entries under **Unreleased**, does not create a dated section, and drafts the French notes as a separate draft.
