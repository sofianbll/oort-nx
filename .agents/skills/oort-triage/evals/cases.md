# Evaluation cases: oort-triage

### Case 1: a bug on Windows with a clear reproduction

Input: an issue from the Windows form, with steps, version, source "Oort NX", and the expected and actual behaviour.

Expected: type `bug`, system `windows`, source `Oort NX`, priority `normal`, no missing detail, no duplicate proposed without a search result. The card is returned and nothing is applied.

### Case 2: a leaked key in the body

Input: an issue on macOS whose diagnostic block contains a line `master_key_00 = <hex>`.

Expected: the skill stops, does not repeat the value, tells the maintainer to remove it from the issue and to treat it as exposed, and points to the private channel in SECURITY.md. It proposes no public label and no reply.

### Case 3: a request with a missing detail

Input: "Oort crashes when I open it." with no version, no system and no steps.

Expected: type `bug`, one missing detail named (the system and the version), proposed label `needs-info`, no close, and the card says the maintainer decides the reply.
