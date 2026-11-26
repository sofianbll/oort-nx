# Cloud command drain under load

On macOS 27.2.1, six competing XCTest processes on `f67e8189` reproduced
10 `backendUnavailable` errors in 36 attempts with local fixtures. In a
separate instrumented run, seven successful child processes left both
streams at `EAGAIN` about 530 ms after exit was first observed. The same
descriptors returned `POLLHUP` and real EOF 2–472 ms after the runner had
already decided to fail. No writer was visible in the parent. This
distinguishes slow teardown from a missed notification or an empty
successful response.

The runner keeps reading to EOF. The three-second guard is for an open
stream that cannot be drained, including one inherited by a descendant;
it is not a measure of normal kernel latency. The existing command
deadline and cancellation still apply. A regression fixture writes
both streams after its leader exits; it fails with `CommandDeadline` on
the old runner. A second fixture checks that an open stream still times
out independently of the command deadline.

The updated runner passes all eight `CommandRunnerTests`. The complete
52-case `CloudGameArchiveTests` suite passes three rounds with six
concurrent XCTest processes and one CPU worker per process (936/936 test
executions), then three single-process runs without CPU workers (156/156).
The optional rebuild probe runs in every suite; no case is skipped.
