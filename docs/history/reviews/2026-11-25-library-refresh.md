# One library refresh — 25 November 2026

Synthetic data: 16 games (400 files per app), 15 game folders of which one holds 101 files, 1 to 40 cloud apps whose records list 1,200 files each. The real rclone 1.75.2 spoke to a fake Drive on this Mac that answers each request after 150 ms; a wrapper counted its launches. Debug build, on a Mac shared with other builds (load 20 to 190), one run each. Base: `ecfc72b4`.

| Cloud apps | Measure | Before | After |
|---|---|---|---|
| any | Process start → library model ready | 0.06–0.10 s | 0.10–0.13 s |
| 1 | Cold launch → cloud up to date | 122.6 s · 580 rclone · 543 requests | 2.6 s · 4 rclone · 16 requests |
| 16 | Cold launch → cloud up to date | 424.2 s · 1,780 rclone · 1,983 requests · 5.5 MB | not measured after |
| 40 | Cold launch → cloud up to date | 1,243.8 s · 3,945 rclone · 4,479 requests · 15.7 MB | 4.2 s · 4 rclone · 94 requests · 5.1 MB |
| 1 / 16 | Warm launch → cloud up to date | 119.4 s / 435.1 s | 1.8 s / not measured |
| 40 | Warm launch → cloud up to date | not measured (stopped) | 2.2 s · 4 rclone · 14 requests · 0.1 MB |
| 1 / 40 | Warm button → everything up to date | never: 0 requests to the cloud | 1.0 s / 1.1 s · 1 rclone · 8 requests |
| 40 | Main thread, cold launch | 10.5 s | 0.19 s |

Three costs:

- Each Drive command repeated the account and folder checks. At 40 apps, 1,975 of the 3,945 processes only listed the configured remotes; another 395 ran `about`.
- Discovery listed folders serially; the catalog check then covered the same ground. At 40 apps the baseline ran 1,495 `lsjson` processes and read 80 records (two per app). The grouped cold run downloaded 40 records; the warm run reused them.
- The local refresh kept reconciling game icons, with individual saves of the whole catalog on the main thread (0.43 s CPU on the 40-app baseline button run, versus 0.25 s on the warm button run after). A no-change scan now skips its catalog save; icon reconciliation batches pending marks. The old button also never reached Drive: it attempted no refresh, and even a subsequent import is refused while the local scan is running.

At 40 apps, for cold launch the fixture counted 793 → 935 file opens, 36,058 → 9,378 metadata operations and 259 → 771 directory reads in the launcher (not bytes read from disk). For the warm button it counted 760 opens, 7,894 metadata operations and 2 directory reads. These totals include work underway in the host and are not counts of unique files. No general incremental ROM directory scanner or Drive Changes feed is used.

Daemon lifetime: the headless probe observes a running fake daemon before it aborts or kills the owning process. Before the fix the daemon survives both signals; afterwards it exits in every case (normal close, SIGABRT, SIGKILL), within the probe's three-second deadline and without restarting Oort.

Not established: the real Drive, its quotas, another network, a release build, a real library's disks, and an interactive hand. The first picture of the window was not timed, only the model it draws.
