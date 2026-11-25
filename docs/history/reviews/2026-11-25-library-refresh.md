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

Three causes. Every rclone command first proved the account and each folder with commands of its own: about ten processes for one listing. The library was walked one game and one folder at a time, each record downloaded again, then walked a second time by the catalog check. The button never reached the cloud: the import was refused while the local scan it had just started was running.

Not established: the real Drive, its quotas, another network, a release build, a real library's disks, and an interactive hand. The first picture of the window was not timed, only the model it draws.
