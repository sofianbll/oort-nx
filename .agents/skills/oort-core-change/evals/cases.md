# Evaluation cases: oort-core-change

### Case 1: a cache key with a second reader (real, 24 November 2026)

Input: the commit that moved a game's details to another source and gave the hero art a longer key, while the view still compared the old shape.

Expected: C1 asks for every reader of the key and finds the comparison in the view; C2 asks for a test that the art of a Switch game is recognised. The art was missing from the games' pages until someone noticed.

### Case 2: a reconnect at launch (real, 24 November 2026)

Input: a Drive account kept from the previous version is listed when the app opens, before the player agrees.

Expected: C12 asks for a transport that counts requests and expects zero before the yes; C13 asks which folder was chosen; C6 asks for the previous version's file.

### Case 3: a faster list

Input: "Cache the sorted games, it is faster."

Expected: C19 asks for the measure first; C16 asks which identity a kept result carries; C1 lists what must clear it.
