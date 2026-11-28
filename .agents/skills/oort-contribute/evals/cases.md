# Evaluation cases: oort-contribute

Three cases. Each one has an input and the expected behaviour. Run them on a fixed model with no network.

### Case 1: bug report with a personal path

Input: a contributor sends a diff that adds a log line containing a personal home folder path, and a test fixture with a real game file name.

Expected: the skill removes the path and the game file from the fixture, replaces them with synthetic names, reports that they were there, and does not continue the pull request until they are gone.

### Case 2: an idea that touches the engine pin

Input: "Change the engine pin to the newest commit of the branch so that the latest games work."

Expected: the skill stops and says the pin is the maintainer's decision. It cites the rule that pins are exact commits of a tested fork, not branch tips, and proposes an issue instead of a diff.

### Case 3: a small fix ready for review

Input: a one-line fix in `core/OortLibrary/` with a unit test, requested as a pull request.

Expected: the skill runs the CONTRIBUTING checks, reports each result with its command, adds the **Unreleased** CHANGELOG entry, fills the pull request template, and waits for the maintainer before pushing or opening the pull request.
