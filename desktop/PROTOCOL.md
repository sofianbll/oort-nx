# oort-core, the companion

`oort-core` (Swift 6, `Sources/OortCompanion`, `Sources/oort-core`) holds the desktop app's logic. The window starts it and talks over its standard input and output: one JSON request per line, one JSON reply per line, in order. It ends when its input closes.

```
→ {"id":7,"method":"game","params":{"id":"…"}}
← {"id":7,"result":{…}}          or  {"id":7,"error":"inputs-missing"}
```

An `error` is a short code the window puts into words; `disk` comes with a `detail`. The companion opens no connection and starts no process: when information online is on, it says which address to read, and the host reads it. It writes in `--data`, and in the settings files a game's manifest declares (`Places.mayWrite`).

| Methods | What they do |
|---|---|
| `hello`, `view` | What the window needs to draw itself; `hello` takes the system's `languages` |
| `library`, `library.rescan` | Games of a tab, searched and sorted (`LibraryQuery`) |
| `folders`, `folders.add`, `folders.remove`, `programs.add`, `programs.remove`, `programs.rename`, `programs.about` | Where games are; what a program says of itself |
| `game`, `game.favorite`, `game.input`, `game.setting`, `game.option`, `game.folder`, `game.link` | One game: its files, its settings, its setup choices, and checks for HTTPS links from games in the library |
| `game.art`* | The path of one of a game's pictures (`cover`, `icon`, `hero`, `logo`, and `mark`, its program's icon) |
| `game.picture` | A picture the player chose, copied into the app's folder, or put away |
| `guide` | The first steps: open or not, at which page, done |
| `steam`, `steam.set`, `steam.where`*, `steam.updating`* | The games Steam installed. A launch plan of one is `{steam, folder}`: the host hands Steam the number |
| `online`, `online.set`, `online.clear`, `online.none` | Information online: on, off, put away, none for this game |
| `integrations`, `integrations.act`, `integrations.keep` | The rows about integrations, each as the core decides it: `title`, `value`, `sub`, `help` as `[key, count?, args…]`; `checked` for a switch; `open` for a page of the app; `confirm` to ask first; a `token` when A asks something. `integrations {at}`: Settings › Integrations (`sections`), or Steam's row in the first steps (`guide`), Add game (`add`) or the activity center (`activity`) (`entries`). `integrations.act {at, id, token}` does the row's request if the row is still the one shown and was not done since, else `stale`; it answers the rows again, with `rescan` when the library changes. `integrations.keep {on}`: the first steps go on and keep Steam's switch as shown, if Steam is here and it changes the choice |
| `online.start`*, `online.answer`* | One lookup: `{get, save?, limit}` for each address, then `{done}`. A picture is left at `save` + `.part`; the companion checks it before it is kept |
| `launch.plan`*, `prepare.plan`*, `prepare.line`*, `prepare.end`* | What to start, what a setup step prints, how it ended |
| `session.start`*, `session.beat`*, `session.end`* | Play time, per profile |
| `settings`, `settings.set`, `settings.save`, `settings.discard`, `settings.reset`, `settings.remember` | The Mac app's settings (`AppSettings`), tried then saved |
| `profiles`, `profiles.add`, `profiles.select`, `profiles.rename`, `profiles.pin` | Local profiles |
| `files`, `sound`, `prompts`, `pad` | Names in a folder, a WAV (OortSynth), button names, the controller in hand |

\* Asked by the host only; the page cannot.

## What of recomplauncher.json is read

Format 1, from the RecompLauncher SDK (Ripalda, MIT): `inputs` (and the older `game`), `start`, `prepare` with its options and progress, `config` (TOML, INI, JSON), `settings` with choices and sliders, `games`, `folders`, `exit_codes`, `actions` that open a folder. Refused with a reason, not half done: files to place or unpack in the game's folder (`into`, `destination`, `extract`) and files to download (`nvidia.dlss`). Not done: checks by disc serial, build ID or CRC32 (said beside the file), `saves` copies, `bindings`, `looks`, `mods`, actions that clear a folder.
