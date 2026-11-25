# The phone library

How a phone reads the library folder the Mac keeps, whatever holds it. Reading and downloading only: no screen uses it yet, and neither
app contains the Drive connector.

## Parts

| Part | Swift | Kotlin | Network |
|---|---|---|---|
| Contract, format, download | `Sources/OortCore/Shelf/` | `android/shelf/` | none |
| Optional Google Drive connector | `mobile/Sources/OortDrive/` | `android/drive/` | three Google hosts |
| Shared cases and fake Drive | `Tests/PhoneLibrary/` | the same files | 127.0.0.1 |

A source is `ShelfSource`: a root, `children(of:)`, `fetch(range:)`. It has no call that writes. Drive, a chosen folder or the Mac over
Wi-Fi are three implementations of it; only Drive exists. `ShelfConnectors` keeps every connector off until the player grants all the
permissions it declares; asking for more in a later version turns it off again; turning it off erases its credential. On Android the
`INTERNET` permission is in the connector's own manifest, so it comes and goes with the module.

## What the phone reads

The Mac's layout is unchanged: `<Name> [TITLEID]/manifests/`, `app/`, `cache/`. The phone checks the Mac's manifests (versions 1 and 2)
with the Mac's own rules and never downloads a Mac app. Builds for phones sit beside them:

```
<Name> [TITLEID]/targets/<ios|android>/<16 digits, ms>-<sha256 of the manifest>.json
                                       <same name>.sig
                                       <inventory_sha256>/<path of each entry>
```

They are not a new artifact kind in the Mac's manifest: the Mac refuses a manifest with a kind it does not know, and drops a key it does
not know at its next upload. In a folder of their own they are invisible to 0.3.0, 0.4.0 and 0.5.0, whose uploads, restores and library
moves leave them as they are. A library move by those versions leaves them in the old folder.

```json
{"format": "oort-target", "version": 1, "title_id": "0100000000010000", "platform": "ios", "game_name": "…", "game_version": "1.0.0",
 "created_at": "2026-11-25T10:00:00Z", "engine": {"commit": "<40 hex>"},
 "requires": {"os": "26.0", "arch": "arm64", "features": ["bc"], "host": 1},
 "package": {"path": "Game.framework"},
 "unpacked_size": 123, "entry_count": 2, "inventory_sha256": "<sha256>",
 "entries": [{"path": "Game.framework/Game", "size": 100, "sha256": "<sha256>"}]}
```

- `inventory_sha256` is the SHA-256 of the entries as the Mac's encoder writes them: sorted keys, no spaces, slashes as they are.
- `requires.features` are words the device must all have (`apple9`, `bc`, `vulkan1.1`…); an unknown word means "does not run here".
  `host` is the launcher-side contract (`DM_GLUE_VERSION` on iOS). `os` is an API level on Android.
- Android's `package` also has `id`, `version_code` and `certificate_sha256`.
- `.sig` is an ECDSA P-256 SHA-256 signature, DER, over `oort-target-1\n` followed by the manifest's bytes.
- A publisher writes the files first, then `.sig`, then the manifest: a manifest whose files are missing is hidden.

The newest build that runs on the device is offered; the others are named with a reason (`notPrepared`, `system`, `graphics`,
`launcher`, `filesMissing`). One damaged game is a problem of that game only. A source that cannot answer stops the list: a partial list
is never shown as a whole one.

## Download

The tree is compared with its manifest before a byte is asked for (names, sizes, the source's own SHA-256). Files come in ranges of one
chunk, into `.incoming`; each file's SHA-256 is checked, then one rename makes the whole build visible. A stopped download asks only for
the ranges that are missing. Space (the build, one chunk, a reserve) and mobile data are checked before every chunk. On iOS everything is
marked out of the backup; on Android the store goes in `noBackupFilesDir`. Transient failures (broken connection, 429, rate-limit 403,
5xx) are tried four times; a quota, a refusal or a missing connection is said at once.

## Access to Drive

- The player's own Google client, in a code the Mac shows: client, library folder, the Mac's public key. No token; a code that holds one
  is refused. The phone signs in by itself, in the system browser, with PKCE, for `drive.readonly` exactly.
- iPhone: an *iOS* client (no secret), back through its reversed identifier. Android: a *desktop* client, back through 127.0.0.1 on a port
  chosen for that sign-in: Google no longer accepts custom schemes on Android, and an *Android* client's package and signature must be
  unique across all Google projects, so players could not each have one for the same APK.
- The access token stays in memory. The refresh token is in the keychain (this device only) or sealed with an Android Keystore key.
  Errors carry a word, never an address, an identifier or a token.
- Turning Drive off erases the phone's token and does not call Google's revocation, which would cut every client of the same project.

## What it defends against

| Threat | Answer |
|---|---|
| The code is photographed | It opens nothing without the player's Google account |
| The phone is lost | Its token reads, cannot write; withdrawn from the account's connections without touching the Mac if the phone has its own Google project |
| Files replaced in the folder | Only builds signed by the player's Mac are shown; each file's SHA-256 is checked |
| Hostile names and paths | Refused: traversal, hidden, key and save names, links, control and direction marks, collisions by case or accent |
| Lying sizes, endless pages or bodies | Every size is checked against the manifest and the range; pages, bodies and trees are bounded |
| Redirections, compressed bodies | Never followed, never expanded |
| Another app takes Google's answer | `state` and the PKCE verifier stay in the process |

An older build signed by the same Mac can be put back by someone who can write in the folder. The signature of the framework itself (same
Apple team) and of the APK (same signer) are checked by the system when it is loaded or installed.

## Checks

`python3 Tests/PhoneLibrary/check.py`, `swift test` in `mobile/`, `gradle -p android testDebugUnitTest`. Both run every file of
`Tests/PhoneLibrary/vectors/` against `fake_drive.py`. `make_vectors.py` rewrites them; `mac/` is what Oort 0.5.0-beta.3 wrote.
