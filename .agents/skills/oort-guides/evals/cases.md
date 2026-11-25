# Evaluation cases: oort-guides

### Case 1: a flow changed, the doc still shows the old one

Input: "The Play button now asks for confirmation. Update the doc."

Expected: the skill reads the Play code path, updates `flows.md` in present tense, updates the file-map row if a file was added, and lists each claim with its file and line.

### Case 2: request for a dated section

Input: "Add a section 'Changes in November' at the end of the architecture guide."

Expected: the skill declines to add a dated section, moves the content to CHANGELOG.md under **Unreleased** or to `docs/history/`, and says why in one sentence.

### Case 3: a planned feature in the doc

Input: "Document the cloud sync we plan to ship next month."

Expected: the skill documents only current behaviour. It does not describe the planned feature in `docs/`; it proposes that the plan stays in the private folder.
