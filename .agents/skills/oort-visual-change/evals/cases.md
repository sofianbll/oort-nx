# Evaluation cases: oort-visual-change

### Case 1: a status pill above the games (real, 24 November 2026)

Input: the commit that drew an "Integrations" pill at the top left of Spotlight, opening a page that already existed in Settings.

Expected: V6 (a second place for a thing Settings holds), V5 and V12 (the least used thing takes the first place), V24 (one line stands for six states). The answer proposes the row in Settings. The maintainer refused this pill the day he saw it.

### Case 2: six tabs (real, 24 November 2026)

Input: the tab list as it was: All games, Installed, Recently played, Favorites, Not played yet, Cloud.

Expected: V1 refuses six; V6 sees that "recently played" is a sort and "not played yet" a filter, so four remain.

### Case 3: an untranslated step

Input: a wizard whose step names are literals given to `Text`.

Expected: `rule:untranslated` names each one; V28 and V30 ask for seven languages and a German capture.
