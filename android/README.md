# Oort NX for Android

A launcher for the Switch games that [nx2android](https://github.com/shirai91/nx2android) installed on the
device: a library, a page per game, a controller test and a few settings, driven by a controller first, then touch.
Open source, MIT, local only: it asks Android for **no permission at all** (no network, no storage), collects
nothing, and contains no game, key or emulator.

**State: builds, never run.** On 2026-11-25 it was built for real (JDK 21, Gradle 9.9.2, AGP 9.5.1, Kotlin 2.4.21,
compileSdk 37.1): 34 unit tests pass, the debug APK is 33.4 MB and the R8 release APK 1.8 MB. It has **never been
installed or started** (no device or emulator was available): no screen has been seen, nothing was tried with a real
controller.

```sh
gradle -p android testDebugUnitTest assembleDebug assembleRelease   # no Gradle wrapper jar yet: `gradle wrapper`
```

## What it does

- **Library.** Lists the apps whose package starts with `org.nx2a.` (nx2android's convention), with their icon,
  name and version, over the Oort cloud and its Sun. Re-reads the list each time it comes to the front.
- **Game page.** Play, Android's own settings page for the game, and Uninstall (Android asks to confirm; the page
  says first that the game's saves go with it).
- **Controllers.** The pads Android sees, as they come and go, and the last button pressed.
- **Settings.** Sounds on or off, the sound pack, swap A and B (Switch layout), calm cloud.
- **Pad first.** D-pad, hat axis and both sticks move the focus with the same repeat as the Mac
  (`DirectionRepeat`); A confirms, B goes back, L1 and R1 change section, the system Back gesture works.

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
            GameScanner, GameLauncher, Prefs, SoundPlayer
    ui/     Compose: theme, tokens (generated), cloud backdrop, library, game page, controllers, settings
  app/src/test/   JVM tests against numbers the Mac's own Swift code produced (goldens.json)
  tools/    make_goldens.swift, goldens_to_kotlin.py, verify_cloud.py, make_icon.py
```

## Making things again

```sh
python3 scripts/generate_oort_android_tokens.py          # OortTokens.kt and oort_colors.xml from design/oort.tokens.json
swiftc -O android/tools/make_goldens.swift Sources/NXLibraryCore/Selene/MoonlightAppearance.swift \
  Sources/NXLibraryCore/Selene/OortSynth.swift -o /tmp/make_goldens
/tmp/make_goldens > android/app/src/test/resources/goldens.json && python3 android/tools/goldens_to_kotlin.py
python3 android/tools/make_icon.py                       # the provisional icon
```

## Checks that need no SDK or compiler

```sh
python3 scripts/generate_oort_android_tokens.py --check
python3 -m unittest discover -s Tests/AndroidChecks      # strings in both languages, resources, no permission, brackets
python3 -I android/tools/verify_cloud.py                  # the cloud against the Mac's numbers
```

A demonstration mode exists in debug builds only: `adb shell am start -n io.github.sofianbll.oortnx/.MainActivity --ez demo true`
shows made-up entries, to look at the screens without a game.

Credits: [NOTICE.md](NOTICE.md).
