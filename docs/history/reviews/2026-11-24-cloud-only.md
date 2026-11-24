# Cloud-only library entries — 24 November 2026

The Swift fixtures distinguish a source-only manifest, names with title IDs, missing IDs, ambiguous names or titles, unreadable folders and a failed Drive listing. They check that a removed title stays excluded and unfollowing retains a local copy. The query checks that Cloud uses remote availability and still excludes hidden games.

The synthetic `run_cloud_screens.py` scenario opens a source-only page, saves a local artwork pick and a favourite before downloading, and reopens the catalog with the Drive connector offline. It checks the softened tile, the Cloud filter and the verified queue transfer. The final app-ready state is a catalog fixture, not a game build or a launch. The four French captures show the tile, Details, the Cloud filter and the import result.

The added Drive reads are non-recursive `lsjson <scoped-directory> --no-modtime --no-mimetype`, with the existing directory stat for an empty listing. The reference label stats the bound root directly instead of enumerating shared folders. Discovery does not request hashes or file contents. Only an explicit download lists the selected directory with `--hash` and copies its verified files to local staging. No part of discovery or forgetting an entry writes to Drive.

The fixtures neither exercise the real Drive account nor establish behaviour with physical mouse, keyboard or controller input. See the [manual checks](../../working-on-it/validation.md).
