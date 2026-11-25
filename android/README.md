# Oort NX for Android

A launcher for the Switch games that [nx2android](https://github.com/shirai91/nx2android) installed on the
device: a library, a page per game, a controller test and a few settings, driven by a controller first, then touch.
Open source, MIT, local only: it asks Android for **no permission at all** (no network, no storage), collects
nothing, and contains no game, key or emulator.

**State: alpha, `0.1.0-alpha.1`, checked in the Android emulator, never on a real phone.** Every push to `alpha/android`
builds it, runs the unit tests, then drives the R8 release in emulators with made-up games (`tools/emulator_check.py`):
see the Android workflow for what passed, and for the pictures. The identifier
`io.github.sofianbll.oortnx.alpha` is the alpha's own.

```sh
gradle -p android testDebugUnitTest assembleDebug assembleRelease   # no Gradle wrapper jar yet: `gradle wrapper`
```

## What it does

- **Featured.** The last games started from Oort, the chosen one large, Play under the thumb; on its side, a row of covers.
- **Library.** Lists the apps whose package starts with `org.nx2a.` (nx2android's convention), with their own icon as a
  cover, the last started first or by name. Re-reads the list each time it comes to the front.
- **Game page.** Play, its version and package, and Android's own page for the game (storage, Uninstall; the page
  says first that the game's saves go with it).
- **Controllers.** The pads Android sees, as they come and go, swap A and B (Switch layout), and a screen where every
  button lights on a controller drawn in dots.
- **Settings**, two levels: games, sounds and sound pack, buttons, calm cloud, credits and full licences.
- **Pad first.** D-pad, hat axis and both sticks move the focus with the same repeat as the Mac (`DirectionRepeat`);
  The Mac's places: A confirms, B goes back, X opens the game's page, Y opens the controllers, + (Start, Menu,
  Options) the chosen game's options (the settings where no game is chosen), the right stick's click sorts, L1 and R1
  change tab, L2 and R2 jump to the first and last line; Home stays Android's. A long press on a game opens the same
  options. On a phone on its side, a controller takes the whole screen. The system Back gesture works everywhere.
- **What it keeps**, on the device only: its settings, and when each game was last started from Oort.

## What it cannot do, and why

nx2android's apps expose a launcher activity and nothing else: they read no intent extra, offer no content
provider, and keep their settings and saves in `Android/data/<package>/files`, which Android keeps from every other
app (even with All files access, and through the file picker, since Android 11). So this launcher cannot edit a
game's settings or move its saves: those stay in the game's own pause menu. See
`.scratch/oort/mobile/ANDROID.md` in the workspace for the contract, with file and line references.

## Layout

```
android/
  settings.gradle.kts, build.gradle.kts   AGP 9.5.1, Kotlin 2.4.21, Gradle 9.9.2 (no wrapper jar yet: `gradle wrapper`)
  app/src/main/kotlin/io/github/sofianbll/oortnx/
    core/   pure logic and the Android edges: OortCloud, OortSynth, DirectionRepeat, PadKeys, InputRouter,
            GameScanner, GameLauncher, Covers, LastStart, PadShape, PadMonitor, Prefs, SoundPlayer
    ui/     Compose: theme, tokens (generated), cloud backdrop, AppState (what is on screen), one file per screen,
            Rows and OortList (every list, for the finger and the controller alike)
  app/src/test/   JVM tests against numbers the Mac's own Swift code produced (goldens.json)
  tools/    make_goldens.swift, goldens_to_kotlin.py, verify_cloud.py, make_icon.py,
            make_test_games.py (made-up games), emulator_check.py (drives the app with adb)
```

## Making things again

```sh
python3 scripts/generate_oort_android_tokens.py          # OortTokens.kt and oort_colors.xml from design/oort.tokens.json
swiftc -O android/tools/make_goldens.swift Sources/NXLibraryCore/Selene/MoonlightAppearance.swift \
  Sources/NXLibraryCore/Selene/OortSynth.swift -o /tmp/make_goldens
/tmp/make_goldens > android/app/src/test/resources/goldens.json && python3 android/tools/goldens_to_kotlin.py
python3 android/tools/make_icon.py                       # the launcher icon, from Resources/AppIcon.icon
```

## Checks that need no SDK or compiler

```sh
python3 scripts/generate_oort_android_tokens.py --check
python3 -m unittest discover -s Tests/AndroidChecks      # strings in both languages, resources, no permission, brackets
python3 -I android/tools/verify_cloud.py                  # the cloud against the Mac's numbers
```

A demonstration mode exists in debug builds only: `adb shell am start -n io.github.sofianbll.oortnx.alpha/io.github.sofianbll.oortnx.MainActivity --ez demo true`
shows made-up entries, to look at the screens without a game.

Credits: [NOTICE.md](NOTICE.md).
