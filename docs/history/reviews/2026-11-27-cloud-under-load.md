# Cloud library under load

After the [drain fix](2026-11-26-cloud-command-drain.md), cloud checks still failed on a busy Mac:
`run_library_refresh.py` ended with `CloudLibraryFailure.unavailable` and “one rclone lives: 0”
(GitHub run 45925629364, one job in four, and once locally during PC renders). Load was
reproduced with `creneau.py` (utility QoS, nice 15) facing 18 to 36 `yes` at normal priority.
Three causes were found, each with its own trace. No deadline was raised, no assertion relaxed,
no case skipped.

## 1. Orphan sweep against a folder being created

`reapOrphans` treats an empty, unleased `arcane-rc-XXXXXX` folder as abandoned and removes it.
`launch` created the folder with `mkdtemp` and leased it a moment later, so a sweep (this
process’s first one, or another process’s) could remove it in between. Trace on the old code:
`sweep claimed arcane-rc-4b1D25`, then `launch: claim arcane-rc-4b1D25 errno=2 exists=false`,
`rc/noop launch failed`, 30 s of back-off, and every read went to single commands that the
probe’s fake rclone refuses, which is the CI signature. Creating and leasing a folder, like
leasing and removing one during the sweep, now happens under one `flock` on `arcane-rc.lock`,
which every Oort process of this user shares and the kernel releases if one dies. The lock must be a regular file of this user without group or other access, or the daemon is not used. An older Oort running at the same time does not take this lock.
`testOrphanSweepNeverTakesAFolderBeingCreated` loses 366 to 724 folders out of 2,000 on the old
code, and none after.

## 2. Two-second start limit for `rcd`

`rclone rcd` 1.75.2 binds its socket in 0.06 s idle, but in 3.5 to 9.5 s under this load
(18 of 18 starts above 2 s; the Python fixture took 0.9 to 2.8 s). The remote control stopped a
live daemon that had not bound after 2 s and backed off for 30 s. Under load, the full suite on
the old code had three failures with the same trace, `rcd not ready at readyBy, alive=true`:
`testRCConfigMutationTransfersParametersOverStdinToLocalFixture`,
`testCancellingRemoteControlReadKeepsDaemonReusable` and
`testCancellationBeforePublicationCleansStaging`. The daemon has failed only when it exits. The
wait for its socket now shares the request’s existing budget (60 s, 300 s for OAuth), and curl
gets what remains (at least 1 s), so a request lasts no longer than before. The separate limit is gone. A daemon that stays alive without ever binding now delays the fallback up to that budget. rclone exits when it cannot listen, and no such case was seen.
`testRemoteControlWaitsForADaemonThatIsStillStarting`, with a daemon that starts 2.5 s late,
records `["rcd", "lsjson", "lsjson"]` on the old code and only `["rcd"]` after.

## 3. Probes shared one preferences domain

`audit_probe_host.py` named every probe binary `probe`. Standard preferences are named after
the executable and kept by `cfprefsd` in the real `~/Library/Preferences`, whatever
`CFFIXED_USER_HOME` says: two probes run at once read each other’s settings, so one launched
the other’s fake rclone (“one rclone lives: 2” beside “one rclone lives: 0”). A standalone
check showed the same: process A read the value written by B. Each probe now has its own name
and removes its domain and file afterwards.

The refresh probe also stopped waiting too little. The approval starts a Drive scope check
that is not part of the refreshes measured later. Under load, its `listremotes` and `about` fell
into the “offline asks nothing” window. The probe now awaits `scopeTask`, which the model
exposes for reading.

## Verification

Three rounds on the final tree: `run_library_refresh.py` 36/36 (three at once, 18 `yes`);
under 36 `yes`, `RcloneConfigurationTests` 18/18,
`testAppIsPublishedToReferenceWhileCacheIsStillTransferring` 18/18, and both new regressions
18/18. The full parallel suite passes 2,597/2,597 under 24 `yes` (three failures on the old code
under the same load), and again idle. Under 36 `yes`, `testCancellationBeforePublicationCleansStaging`
still fails 13 of 18 runs. It allows 4 s for the first progress line of a real `rclone copyto`,
while rclone alone takes 3.5 to 9.5 s to start under that load. This limit belongs to the test
and was left as it is.

## Not reproduced

- `testAppIsPublishedToReferenceWhileCacheIsStillTransferring` → `backendUnavailable`: alone
  under load 60/60 green, and absent from the whole archive suite (6 × 37 cases) and from the full
  parallel suite under load on the old code. No trace ties it to the causes above.
- 25 `CloudGameArchiveTests` in `invalidResponse` (Hydrogen branch): every fixture call,
  including those that must fail, returned 0 with output that was not JSON, so the script did
  not run as written in that session. The full `ArcanePortingTests` bundle without
  `NX_TEST_ENGINE_*` passes 1,534 of 1,534. This is an environment of that session, not load.
