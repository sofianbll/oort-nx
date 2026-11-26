# Cloud assistant: cost of finding both folders — 2026-11-25

`CloudAssistantNetworkTests` compares the previous path (`ecfc72b4`, seven folders opened to reach the same libraries) with the assistant’s automatic suggestions. Both use the same synthetic Drive: one built game, fifteen ROM folders and 200 ms of injected delay per simulated request. Times are cumulative from the start of the test and exclude player think time.

| Milestone | Processes before → after | Requests before → after | Time before → after |
|---|---:|---:|---:|
| Both folders shown | 105 → 3 | 48 → 21 | 28.1 → 2.1 s |
| Access verified | 113 → 11 | 52 → 25 | 29.5 → 2.9 s |

In the separate browsing test, reopening two previously read folders added no requests (0.0 s rounded). The cache is for display only. The ready step still verifies access without that cache.

To repeat the current measurement, set `OORT_MEASURE_CLOUD` to a fresh output path and run `swift test --filter CloudAssistantNetworkTests` with an isolated home. This measures fixture processes and simulated requests, not real Drive latency or the shared rclone session after integration.
