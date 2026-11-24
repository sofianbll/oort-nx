<p align="center">
  <img src="Resources/AppIcon-Light.png" alt="Oort NX halftone app icon" width="96" height="96">
</p>

<h1 align="center">Oort NX</h1>

**Oort NX is a fork of [Arcane by Bium23](https://github.com/Bium23/NxLibrary).** Bium23 wrote most of the launcher. Oort NX is maintained separately, without Bium23's involvement or endorsement.

<p align="center"><strong>A home for your games on Mac.</strong></p>

<p align="center">
  Browse and launch games from one Mac library, with controller navigation,<br>
  game artwork and activity. Bring together installed Steam games for Mac and games you’ve ported.
</p>

<p align="center">
  <a href="#project-status"><img src="https://img.shields.io/badge/status-alpha-DB806B?style=flat" alt="Status: alpha"></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/macOS-26%2B-3D4754?style=flat" alt="macOS 26 or later"></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/Apple-silicon-3D4754?style=flat" alt="Apple silicon"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-64816C?style=flat" alt="MIT license"></a>
</p>

<p align="center">
  <a href="https://buymeacoffee.com/bium"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me a Coffee — support Bium23, the author of Arcane" height="40"></a>
  <br>Support Bium23, the author of Arcane.
</p>

<p align="center">
  <a href="https://github.com/sofianbll/NxLibrary/releases/latest">Download</a> ·
  <a href="#getting-started">Get started</a> ·
  <a href="#using-arcane">User guide</a> ·
  <a href="#troubleshooting">Troubleshooting</a> ·
  <a href="CHANGELOG.md">Changelog</a> ·
  <a href="docs/working-on-it/development.md">Development</a>
</p>

<!-- NX-DEMO:START -->
<!-- NX-DEMO:END -->

<!-- NX-SCREENSHOTS:START -->
![Arcane Spotlight with a selected game, artwork, play history and library navigation](docs/media/spotlight.webp)

<p align="center"><strong>Your library, together.</strong><br>Games, artwork and activity in Spotlight.</p>
<!-- NX-SCREENSHOTS:END -->

### What Oort NX adds

- **Oort NX identity.** The Oort palette is the default for profiles without a saved theme. Existing settings and libraries carry over from the fork.
- **Game display.** Set a default screen for ported games and override it per game when the installed build supports it.
- **Fork integrations.** The fork includes optional cloud library and Nextendo features, local profiles, and the PowerA HID fallback.

### What comes from Arcane

- **One library for your Mac games.** Add Mac app shortcuts and installed Steam games alongside games ported with nxnative. Browse in Spotlight or Collection and launch from either view.
- **Steam achievements.** See playtime, achievement rarity and crystal tiers when available. Complete every achievement in a game to reveal the animated Arcane.
- **An interface built for browsing.** Navigate with a controller, keyboard or mouse, and personalise your library with artwork, themes and live backgrounds.

Every release is in the [changelog](CHANGELOG.md).

## Overview

Arcane is an independent game library and launcher for Apple silicon Macs. It brings installed Steam games for Mac and games ported with nxnative into the same interface, inspired by [Selene](https://github.com/mattxslv/Selene). The integrated porting workflow uses [nxnative](https://github.com/seedds/nxnative) to build compatible Mac apps from your own Switch game files.

| Area | What you can do |
|---|---|
| **Library** | Browse Spotlight and Collection, search, favourite, hide and reorder games. |
| **Steam** | Launch installed games for Mac and browse playtime, achievements and related games. |
| **Game options** | Keep each title's launch settings, artwork and metadata together. |
| **Personalisation** | Choose palettes, wallpapers, live backgrounds, interface sounds and controller prompts. |
| **Porting** | Build compatible Switch titles with nxnative, review updates and DLC, and follow build progress. |
| **Ported games** | Manage compatible mods and cheats, back up local saves and preview save imports. |
| **Cloud library** | Archive ported apps and their build caches separately from saves. |

Game files, keys and firmware are not provided. See [Legal and third-party notices](#legal-and-third-party-notices).

### Project status

Oort NX is in alpha. Get the latest published fork build from [Releases](https://github.com/sofianbll/NxLibrary/releases/latest), or [build this version from source](#building-from-source).

Send Oort NX bugs to this fork's maintainer, not to Bium23. GitHub Issues is currently disabled on the fork; if you already have a way to reach the fork maintainer, use it. Report a bug upstream only if you can reproduce it in unmodified Arcane.

Automated checks cover the application code, publication inputs, compilation and development-app packaging. They do not certify game compatibility. Changes are recorded in the [changelog](CHANGELOG.md).

Porting uses nxnative commit `99224562` with Xcode 27.2 and Metal 32023.922. Porting Setup retrieves that commit. Installed game apps use the engine they were built with. See the [engine upgrade notes](docs/history/engine-upgrades/README.md).


## Getting started

### Requirements

| Requirement | Details |
|---|---|
| **Arcane library** | Apple silicon, macOS 26 or later. Steam and each game can require a newer macOS version. |
| **Porting and nxnative game apps** | macOS 26.6 or later for the Mac hosts built by the pinned engine. This is separate from Arcane's own minimum. |
| **Xcode for porting** | 27.2 or later, with the Metal compiler certified for the pinned engine. Browsing the library and using Steam do not require Xcode. |
| **Porting engine** | nxnative at the pinned commit. Setup can prepare the checkout. To select an existing folder, use **Settings → Porting → Setup and engine**. |
| **Porting inputs** | Your own supported game sources and keys, with the rights and permissions needed to use them. |

A packaged app includes Python and its required packages, `zstd` and `glslangValidator`. Homebrew is used to prepare that runtime during development; it is not needed to use a packaged copy. A source build without the bundled runtime uses the engine's virtual environment and tools on `PATH`.

### Building from source

With the [development prerequisites](docs/working-on-it/development.md#development-prerequisites) installed:

~~~bash
git clone https://github.com/sofianbll/NxLibrary.git
cd NxLibrary

bash scripts/bundle_runtime.sh
bash scripts/build_app.sh
open "$HOME/Applications/Oort NX Dev.app"
~~~

Run `bundle_runtime.sh` once, and again when `runtime.lock` changes. `build_app.sh` prepares, signs and verifies the app before installing it atomically in `~/Applications`.

Build options, runtime dependencies, debug builds and release packaging are documented in the [development guide](docs/working-on-it/development.md).

### Installing a packaged release

1. Download the DMG from the fork's [Releases](https://github.com/sofianbll/NxLibrary/releases/latest).
2. Open it and drag **Oort NX** to Applications.
3. Open Oort NX, choose which detected sources to use, and select **Open library**.

The current alpha is ad-hoc signed and not notarised. If macOS blocks first opening, use **System Settings → Privacy & Security → Open Anyway** only for a copy you built or obtained from a source you trust.

Packaged fork releases check this repository for app updates; no GitHub account is needed. Choose **Update** to download, verify, install and reopen Oort NX while keeping your library and preferences. An existing `Arcane.app` is updated in place and keeps its filename. Automatic checks run at most once every 24 hours; **Oort NX → Check for Updates…** in the macOS menu bar and **Settings → About → Check now** check immediately. Both open the same app-style dialog, with scrollable release notes and a visible result even when no update is available. Updates wait while a build, a running game or a save operation requires the app. Development builds can check public releases manually but never replace themselves.

### First-run setup

On first launch, Arcane looks for installed Steam games for Mac and previously ported apps. Choose whether to include Steam and select **Open library**. Use **Settings → Library → Sources** to change your Steam source or refresh it later. Choose **Porting** on the first screen to set up local game builds with nxnative.

To link an app already on your Mac, choose **Add an app…** in Sources or the macOS Game menu, or drop one `.app` on Spotlight or Collection. **Play** hands it to macOS without tracking time or changing the app. Use **Tile options** to pick an image from a file or remove just the tile. If the app moves, use **Locate the app…** when prompted.

**Get ready** shows the engine, build tools and keys. **Install all** prepares the engine checkout and certified Metal compiler. Install Xcode from the App Store and follow its licence and system prompts. Choose **Continue** to proceed. Build requirements can be completed later, and existing game apps remain playable.

**Your games** shows **Game apps**: where to keep existing nxnative games (`.app`) and install new builds. It checks the selected folder before reporting an empty library. Use **Change** to choose another folder, **Choose game file** for NSP, XCI, NSZ or XCZ, or **Choose a folder instead** for a source folder, including supported extracted inputs. A single detected title opens the existing build review; multiple titles require a choice. Selecting sources never starts a build by itself. Cancelling the picker stays on this page.

If games are found, **Open library** takes you to them. **Skip for now** enters the launcher without adding a game and is remembered: the welcome flow does not return automatically just because the library is empty. Add games later from Spotlight's Add Game card or Collection. An interrupted first setup resumes on its current step.

The default Game apps folder is `~/Applications`; first use can prepare this default without an extra picker. Remembered or custom unavailable folders are never recreated automatically. Changing folders does not move installed apps, and a rebuild updates an existing app in its current location. A read-only folder still allows discovery and Play; installing new builds needs write access.

Discovery includes subfolders of **Game apps**, skips app contents and limits the search depth. **Settings → Porting → Game folders → Scan game apps** reports search limits and unreadable folders. If several builds of a title are found, Arcane keeps the registered app while it exists. For a newly discovered title, it uses the most recently modified build.

**Game files** is a separate optional folder choice in **Settings → Porting → Game folders**. Selecting individual files leaves that choice in place. **Reset group** preserves both folders; the **Game apps** row has its own **Reset** button.

Import your `prod.keys` when prompted. Arcane keeps a private copy with mode `0600` and leaves the original file unchanged. Key values are not displayed or logged.

Reopen both setup steps from **Settings → Porting → Setup and engine → Open Setup** whenever needed; this keeps your library and completion state. Arcane never runs `sudo`, accepts the Xcode licence for you or changes `xcode-select`.

To discover existing nxnative game apps, choose **Settings → Porting → Game folders → Scan game apps → Scan**. Play works with the installed app. To rebuild it, attach the original sources.

If an installed app is moved or removed, its library entry stays with a blurred, locked tile and **App not found**. Restore it to its folder or change **Game apps**, then refresh the library. Arcane does not search elsewhere for it. Missing build inputs show **Game files not found** when there is no app to play. An existing app still plays when its source files are missing; only rebuilding is unavailable. To reconnect a game's moved inputs, use **Game Options → Edit details → Attach sources…**.

## Using Arcane

### Cloud library for ported games

In **Settings → Porting → Cloud library**, Oort NX uses an existing rclone or asks before downloading the verified macOS arm64 release directly from [rclone.org](https://rclone.org/downloads/). No copy ships in the app. **Advanced** lets you choose an executable; turning off Drive can move only Oort NX’s own copy to the Trash. If you update from a version with a bundled rclone, your saved connection and transfer queue stay in place while you choose a replacement.

Keep an existing connection or choose **Sign in**. If the build does not include a Google client, enter your own desktop OAuth client ID and secret. rclone opens your browser to ask for full Drive access and stores the credentials in its encrypted configuration; on this Mac, the configuration password is held in the login keychain. **Test connection** verifies access to the approved Drive account and folders without importing or changing files.

On first setup, Arcane looks for an existing library in `Games` and its immediate subfolders. Under the library you choose, it looks for game files in `GameFiles`, then `Switch/Jeux`, then `Switch/Games`. This is a suggestion; your saved game-files folder stays selected. Resuming a 0.3.0 library confirms its saved path in the same step. If an approved folder is replaced by one with the same name, Arcane asks again. You can choose a different path without moving files.

After activation, Arcane adds games from the selected library without downloading their apps or game files. A game can be listed with just its original files: Arcane needs an unambiguous title ID in the folder or file name and reports folders it cannot read or identify. Discovery stays inside the selected library. It checks again at launch; use **Import games from the cloud** under **Connection** to check on demand. Removing an online-only game forgets its entry without touching Drive and prevents reimport.

Choose **Cloud** beside **Options** on a ported game's Details page to manage the app and its build cache. For a newly imported game, **Download** restores the app to your **Game apps** folder and becomes **Play** once it is ready, without the original game files or a rebuild. Transfer progress remains visible in Details when you close the Cloud panel. **Disconnect** removes only the local rclone connection, which may also be used by other tools. It does not remove cloud files or affect game saves.

If only the game files are online, the tile is softened with a cloud icon. You can open Details and choose artwork before downloading. **Download game files** restores the files on this Mac; the tile returns to colour with **Build**, then **Play** after a successful build. In Spotlight and Collection, use **Cloud** to show games without an app or complete game files on this Mac. If Drive does not respond, Arcane keeps the last known cloud indication without claiming that copies match.

To follow a library from another Google account you own, share its Drive folder with your second account as **Viewer** in Google Drive. On the other Mac, paste the folder link or ID under **Cloud library → Reference library**. Arcane imports source-only games from this library too. It uses the account already connected, never changes sharing permissions and sends only to your own library. The Cloud panel identifies reference copies and shows how much a newer copy needs to download. File-based copies reuse matching local files; a legacy archive downloads in full. **Unfollow** removes only reference entries without a local copy and leaves all files in place.

If you download a ported `.app` folder through Google Drive in your browser, unzip it and choose **Add Game → Add ported app**. Arcane repairs its own copy and keeps the original signature if it verifies. Otherwise, it checks the files against available cloud manifests for the title and refuses versions that match none. With no per-file manifest or cloud connection, it can sign the copy ad hoc and shows **Content not verified** in the import result. Only import ports from a source you trust.

### Your library

**Spotlight** places your games in a row of square tiles, with Play, Options and Favourite beside the selected title. **Collection** offers a cover-based view. Both use the same library and support a controller, keyboard or mouse.

![A game page with screenshots, a description and play activity](docs/media/game-details.webp)

<p align="center"><strong>A closer look at each game.</strong><br>Artwork, details and play history in one place.</p>

Scroll down for screenshots, the game description and **More like this** when matching titles are in your library. Steam games can show playtime and an **Achievements** card with rarity, unlocked items and crystal tiers. The animated Arcane appears when every achievement is unlocked.

Use **Find a game** for search, **Game Options** for title-specific actions, and the menu for themes, Settings and running-game controls. Hidden ported apps can be restored under **Settings → Library → Games → Hidden game apps**.

When you quit a game, Arcane comes back to the front, unless you had moved to another app or another game is still open. A **session card** in the top right shows how long you played this time and in total; sessions under 10 seconds show none. Turn it off in **Settings → Library → Games → Session card**.

![The quick menu open over Spotlight, with Theme selected](docs/media/quick-menu.webp)

<p align="center"><strong>Quick access.</strong><br>Open the menu without leaving your library.</p>

### Language and region

Arcane is available in **English, Italiano, Français, Deutsch, Español, Português (Brasil) and 简体中文**. **Settings → Start-up → Language & region** follows the Mac automatically or lets you choose the app language and region separately. Changes apply immediately and are remembered. **Regional formats** controls dates, numbers and sizes. **Game options → Language** controls each supported game's language.

Choose a language directly from its list. Known catalog genres are translated locally, without changing the saved metadata. Descriptions from Nlib are requested in the app language when supported, with cached descriptions shared between regions using the same language. Switching language reuses available artwork and credits; when those are fresh, only the localized description is requested. When the store has no description in your language, **About this game** shows the game's Wikipedia introduction in that language instead, credited with a link to the article (CC BY-SA). Without one, the English text stays with a note. Nothing is machine-translated, and a description you chose is always kept. Personal names, metadata choices, artwork and game settings are preserved.

### Critic scores

The last row in **Details** shows five stars, the original score out of 100 and its source. Public ratings via Wikidata work without a key; games without a verified match or usable score show **Rating unavailable**. Critic scores take priority. When neither IGDB nor Wikidata supplies one, a configured IGDB connection can show its community average, clearly labelled **User score · Users · IGDB**. Community and critic scores are never mixed.

Optional **Settings → Online services → IGDB** accepts your own Twitch application's **Client ID** and **Client Secret**. The dialog includes five short setup steps and a direct link to register an application. **Check and save** verifies access before keeping the credentials in a private file on this Mac. The secret is hidden, and credentials are separate from ordinary settings and the Dev-profile import. **Remove** returns to the keyless source. With IGDB configured, its critic average takes priority, followed by public critic scores via Wikidata and finally the explicitly labelled IGDB user average. Cached scores remain available offline. The same general settings page contains the SteamGridDB key for game artwork; API connections are optional.

The same optional connection adds **IGDB** proposals to **Game options → Edit details → Change metadata** for Switch, Switch 2 and Steam games. Preview descriptions, genres, developers, publishers and platform-specific release dates, then choose each field individually. Automatic and manual choices remain available. Saved proposals work offline, and IGDB descriptions keep their original language.

**LaunchBox** and **TheGamesDB** also provide optional proposals without an API key, based on the game's title and platform. The picker explains missing or ambiguous data and allows a retry. Native Mac entries take priority, and PC alternatives are labelled.

Use the dialog's **Developer portal** and **Setup guide** links to create your credentials.

### Add or rebuild a game

Use this workflow for games you want to port with nxnative. Arcane discovers installed Steam games through **Settings → Library → Sources**.

1. Open **Add game** and choose or drop a supported file or folder.
2. Review the detected base game, update and DLC. Arcane accepts NSP, XCI, NSZ, XCZ and Switch 2 NUP packages, plus supported source folders.
3. Check the destination, disk estimate and game options.
4. Choose **Add and port** to build, or **Add to library only** to keep the entry for later.

For a title already in the library, Review opens with that game's saved options and offers **Rebuild** or **Save changes**.

Rebuild always needs the original game files. With Cloud library enabled, Arcane checks the remote manifest before preparing a workspace. If the cloud cache has no verified local copy, choose **Download cache**, then retry Rebuild. **Rebuild without cache** requires confirmation and uses a fresh temporary cache without deleting the existing one.

Sources stay in place; staged workspaces use symbolic links. New game apps install in the chosen **Game apps** folder. Builds run on the drive the app goes to: with the folder on an external APFS or Mac OS Extended drive, the extracted game, shader cache and new app stay on that drive in a hidden `.nxlibrary-build` folder, so the Mac's disk needs no space for the build and the app is moved into place, not copied. On an exFAT drive or a network share builds keep using the Mac's disk: exFAT keeps Mac file attributes in separate `._` files, which break a built app's signature. Review shows the actual destination, including any filename needed to avoid an unrelated app. Build stages, progress, estimated time and a live log remain available while the operation runs. The first build of a game after an engine update can first move its shader cache into the engine's new format: that shows **Updating shader cache** instead of an ETA and takes longer on a large cache or an external drive. Closing the porting screen leaves the operation running; cancellation is a separate action.

A rebuild of a running game waits to replace its app until it closes. If compilation finishes but installation fails, **Retry** installs the preserved result without compiling again. If the destination folder disconnects, reconnect it before retrying: the ready build keeps its original destination. A library refresh preserves pending installations and failure information.

![A game build in progress in Spotlight, showing its progress and estimated time remaining](docs/media/porting-progress.webp)

<p align="center"><strong>Follow the build.</strong><br>Keep track of porting progress from Spotlight.</p>

### Know which settings apply

| Where | Scope | When it applies |
|---|---|---|
| **Settings → Porting → New games** | Starting values for titles added later. | When a new title is added. Existing titles keep their choices. |
| **Game Options → Next launch** | The selected game. | Its next launch. |
| **Game Options → Use new game defaults** | Copies the current defaults into that game once. | Its next launch. |
| **Add game → Review** | The title being added or rebuilt. | That operation, including its saved language. |
| **Settings → Porting → Cloud saves** | Library-wide preference, subject to advanced game configuration overrides. | Reapplied before each launch, including when Off. |
| **Settings → Look** | The library's presentation. | The app interface; game artwork and launch-screen style have their own controls. |

For games built with nxnative, options can include fullscreen, FPS target, docked mode, language, rumble, render scale, MetalFX upscaling and Metal HUD. **MetalFX upscaling** enlarges the finished picture, including the HUD, to your window or screen. **Game's upscaler** is offered for games that upscale inside the frame, such as Donkey Kong Bananza. Available options depend on the installed build and game.

Arcane groups Settings into **General**, **Library**, **Porting** and **System**. Use **Search** to find a setting and **Changed** to review values you’ve adjusted. Group resets retain the cloud-sync choice and selected sources folder.

### Saves: back up, import, restore

For a ported game, open **Game Options → Saves**. Keep the game closed during backup, import or restore.

| Button | What it does |
|---|---|
| **Open folder** | Opens the current local save in Finder. |
| **Back up now** | Creates a dated, verified copy of all local users, their registry and the device save. |
| **Save type** | Selects the import destination. **User save** is the usual choice; **Device save** is for a separate device save. |
| **Import save…** | Previews an exported save folder or a dated Arcane backup before replacing anything. |
| **Refresh** | Reads save and backup information again. If recovery is needed, offers **Retry recovery**. |
| **Backup folder** | Opens this game's backups in Finder. The row shows the latest backup's date and time. |

**To import:** choose the folder, review the centred **From → To** preview, then confirm. Arcane backs up existing progress first and verifies the result. A successful import shows **Imported successfully**, which disappears after three seconds.

For Ryujinx, choose the numbered game folder under `bis/user/save/`. A folder selected inside that tree is recognised too; Arcane checks its title metadata and imports the complete committed save, including all slots. For other exports, choose the folder containing the complete save.

**To restore:** choose a dated backup folder through **Import save…**. A current backup restores the complete local user group, including missing destinations. Older backups restore only the primary user and device save, preserving additional users. An ordinary folder import replaces only the selected primary-user or device destination.

**Cloud sync and backups have different purposes.** Cloud sync can replace local files, so import and restore require it to be off in the effective configuration. Cloud sync covers only the primary user and device save; additional local users are protected by local backups, not by cloud sync. A backup is a dated copy you manage in Finder. Save compatibility still depends on the game, platform and version; recognising the folder does not guarantee compatibility.

Interrupted replacements must recover before Play. The Saves panel reports what is blocking an operation and keeps the backup folder accessible.

### Cheats

For a ported game, open **Game Options → Cheats**, then choose or drop a matching cheat file. Arcane checks the title and build information. Newly imported cheats start off. Enable the master switch and the individual cheats you want, then launch the game.

Changes apply at the next Play and are written only while the game is closed. An older or unrecognised engine build may require **Rebuild**. The engine's in-game panel, `⌘⇧C`, reads the same files.

Cheats change values while you play, for one game version only. New items, looks or gameplay are mods.

### Multiplayer

Open **Settings → General → Play together** to choose a default: **Offline**, **Local** or **Online**. In **Game Options**, the **Play together** row below **Play** overrides it for that game. Older builds without network settings do not show the row. Existing per-game network choices carry over.

- **Local** uses your local network or your selected VPN: ZeroTier, Tailscale or NetBird. If Arcane cannot select an adapter, it asks before starting on the local network instead. Use **Advanced** to select an adapter, or to force LAN or local wireless. Automatic uses both local modes on builds without Nextendo and local wireless on Nextendo builds, where the engine's automatic mode also enables online services. For a VPN that does not carry room discovery, `DM_NET_DISCOVERY_PEER` in the player's `env.txt` can point to the host's VPN IPv4 address.
- **Online** requires a Nextendo-enabled game build and an account. Nextendo is a free community service, not a Nintendo service. Sign in from **Play together**. Use **Friends** to add by code, manage requests or add recent players when their code is available. Building does not require signing in: a compatible engine needs a public client ID from **Advanced** or the Arcane bundle. Rebuild a game that does not offer Online. The engine pin does not change.
- **Mods in Online:** Arcane leaves code mods off for the session. **Turn off for online play** disables enabled RomFS mods that are not clearly textures or models, without uninstalling them. Switch them back on in **Mods**.

### Mods

Arcane manages RomFS mods and, with an nxnative checkout that supports `--mods`, ExeFS code patches for Mac builds.

- **Mod store.** The **Mods** card in Spotlight opens a store of the GameBanana mods that work with your games: a featured banner, the most popular, a row per category and a row per game, sorted by Popular, Most liked, Newest or Recently updated. Hide the card in **Settings → Spotlight**.
- **A game's Mods band.** Each game page lists popular compatible GameBanana mods and the ones you installed. Choose **Search mods** to enter a name or paste a GameBanana mod link, or **Show more** to browse the next batch of popular mods. Open a mod for its images, author, version and requirements, then press **Install**; **Update** appears when the author replaces the file. If the game's GameBanana page is uncertain, the band asks once, and **Wrong game?** picks another.
- **Your own mods.** Put RomFS mods into the game's mods folder. For a folder with `exefs` containing `.pchtxt` or `.ips` patches, use **Game Options → Mods → Import code mod** to copy it. The original stays in place. Switch mods independently and reorder them within **File mods** or **Code mods**; **Remove** moves an installed copy to the Trash.

RomFS changes apply at the next launch, with the top mod winning when two change the same file. nxnative puts all selected ExeFS patches into one copy of the game code. When playing from Arcane, turn them all off or turn the same set back on without rebuilding. A different non-empty selection or changed patch files show **Rebuild**. Patches must match the game version, and overlapping patches fail the build.

GameBanana archives can contain RomFS, ExeFS, or both side by side under one root for this game. Arcane rejects archives with multiple variants in different roots, replacement modules and mods that require external loaders or tools (exlaunch, Skyline, ARCropolis, mod managers). Install code mods only from sources you trust.

![The mod store with a featured mod, sort choices and rows of popular mods and characters](docs/media/mod-store.webp)

<p align="center"><strong>Mods for your games.</strong><br>Browse what works with the engine and install it in one step.</p>

### Artwork, themes and sound

- **Game Options → Edit details** changes one game's artwork or metadata. Manual artwork choices take priority over automatic images. After choosing an Icon in **Change artwork**, choose **Only here** to keep it inside Arcane or **Use on the Mac** to show it in Finder and the Dock too. This choice is available for every game, including apps with no original icon, and survives restarts and rebuilds. **Only here** restores the original app icon (or its absence) if a custom one was already applied. **Automatic** removes the personal image and uses the game's own icon, then available online artwork, while keeping your location choice. On the Icon tab, **Icon location** changes **Only here** / **Use on the Mac** at any time, including with Automatic selected. If no image is found, the app keeps the standard macOS icon and remains playable; Change artwork explains that no icon is available. The finished build log records the separate icon result.
- **Menu → Theme** opens colors first, then backgrounds. **Oort** is the default; **Arcane** keeps the original blue moonlight. Optional **Arcane Crystal** and **Arcane Flow** offer fine moving light threads, with barely visible ambient light. Background choices include local images, muted looping videos and optional online sources; source credits appear in the picker.
- **Settings → Look** controls wallpaper placement, sizing, brightness, game backgrounds, Reduce Motion and the Halftone/Particles app icon.
- **Settings → Sound & music** controls interface cues and volume. Four interface sounds are bundled; additional sounds and wallpapers can be imported from a Selene theme folder you own.

Online artwork and wallpapers require their providers to be available. Their content and service terms remain those of the respective owners.

![The colour theme picker with palettes and a live library preview](docs/media/color-themes.webp)

<p align="center"><strong>Choose your colours.</strong><br>Preview each palette before applying it.</p>

![The static wallpaper browser with categories, image thumbnails and a library preview](docs/media/static-wallpapers.webp)

<p align="center"><strong>Find a wallpaper.</strong><br>Browse backgrounds and preview them in your library.</p>

![The live background picker with online sources, local videos and a library preview](docs/media/live-wallpapers.webp)

<p align="center"><strong>Add a little motion.</strong><br>Choose a live background or bring your own video.</p>

### Controls

**Settings → Start-up → Start in fullscreen** chooses the launcher window mode at the next opening. It is separate from each game’s Fullscreen option.

The macOS **Game** menu follows the current selection. **Game Details** opens the existing game page in Spotlight or the selected cover’s details in Collection; **Game Options…** opens the same options as the in-app button. Unavailable commands are disabled.

In fullscreen, the pointer hides after three seconds without movement. Moving the mouse reveals it; keyboard/controller navigation, clicks and scrolling do not. Leaving fullscreen, switching apps or opening a native system panel restores it.

| Action | Keyboard | Controller |
|---|---|---|
| Navigate | Arrow keys | D-pad / left stick |
| Select | Return / Space | Confirm button |
| Back | Escape | Back button |
| Control center | `⌘K` | Tap Menu / `+` / Options |
| Settings | `⌘,` | Hold Menu / `+` / Options for 0.5 s |
| Find a game | `⌘F` | Hold View / `−` / touchpad click for 0.5 s |
| Switch library view | `V` | View / `−` / touchpad click |
| Switch tabs / filters | Q / E where shown | LB / RB |

Home has no action in Arcane. Prompts follow the connected controller and supported system remapping. The PowerA **Lic Pro Controller** can use a direct HID fallback with Nintendo prompts when it isn't available through GameController. **Settings → Controllers → Button layout** separates **Library** navigation from **In game** defaults. Game inputs are handled by the engine and can differ in older builds. See the [launcher keymap](docs/how-it-works/keymap.md) for screen-specific bindings.

## Troubleshooting

| What you see | What to do |
|---|---|
| **A Steam game is missing** | Open **Settings → Library → Sources**, verify the Steam folder, then choose **Refresh Steam**. Arcane lists supported titles installed as Mac apps. |
| **Play works, Rebuild is blocked** | Open **Settings → Porting → Setup and engine** and check Compatibility. Existing apps and new builds have separate requirements. |
| **Sources detached / missing** | Use **Attach Sources…** or locate the original files. The installed app remains usable. |
| **Ready build waiting to install** | Close the running game or finish the save operation, then retry the installation if prompted. |
| **Import is unavailable** | Close the game, finish any active operation and follow the cloud-sync or recovery action shown in Saves. |
| **Import fails** | Read the error message, check that the folder contains a complete save and inspect the preview before retrying. |
| **A setting cannot be saved** | Use the dialog's **Retry**. Unreadable preferences are preserved before defaults are written. |
| **Porting fails** | Use the explained failure and its suggested action. Console contains the build log and **Copy diagnostics**. |

Before reporting a problem, review copied diagnostics and remove anything personal. Include your app/macOS versions, the operation and steps to reproduce. Read [SECURITY.md](SECURITY.md) before sharing a suspected vulnerability.

### Compatibility and limitations

- Arcane uses a manually pinned engine and checks its commit, working tree, CLI contract and Metal compiler before new builds. It does not follow upstream `main` automatically. **Settings → Setup and engine → Newest engine** lets you choose `main` yourself before Arcane has tested it: an orange dot marks it, builds are recorded as untested, **Update** moves to a newer `main` when there is one, **Back to tested** returns to the pinned engine, and it is not offered when `main` needs a different Metal compiler.
- The current engine is `99224562` and certifies Metal `32023.922`. **Build anyway with an untested toolchain** requires explicit confirmation and marks the resulting build as untested. A successful launch does not turn it into a certified combination.
- Game compatibility depends on nxnative, the game version and the toolchain.
- Output follows the window/display; native 1440p/4K internal rendering is not supported. Render scale is 50–100% where the build supports it. MetalFX is spatial upscaling.
- Builds run one at a time. iOS/IPA output, automatic engine updates and notarisation are not currently provided.

The [upgrade notes](docs/history/engine-upgrades/README.md) record each engine review and its toolchain requirements.

### Data and cleanup

App data lives in `~/Library/Application Support/NXLibrary/`. Local game data uses `~/Library/Application Support/nxnative/<title ID>/`: RomFS-only mods use `mods/<name>/romfs`, and code or mixed mods use `code-mods/<name>/exefs` (and `romfs` beside it for mixed mods). Backups are stored under `NXLibrary/SaveBackups/<title ID>/`.

**Details → Cloud library** is available for ported games when a trusted, private rclone remote is configured in the `NXLibrary_CloudStorage` preference (`gdrive:Games`, or just the remote name for the `Games` root). Use the Arcane profile's preference domain (`local.nxlibrary` or `local.nxlibrary.development`), then restart Arcane. Leave the preference unset to hide it. rclone owns the credentials; Arcane does not configure the account.

**Send** makes a SHA-256-verified copy of the app and its registered build cache. Arcane refuses to send an app or cache containing excluded data, such as saves, converted packages or obsolete build files. **Free up space** moves one unchanged, fully backed-up local copy to the Trash only after confirmation and remote verification; the Trash still occupies disk space until emptied. **Download** from the Cloud library panel checks an archive before installing it at its registered location and does not overwrite a local copy. Sources and saves are not sent.

**Settings → Porting → Porting storage** shows app, build cache and log sizes for ported games, including hidden ones, with the largest caches first. **Move to Trash** moves one game's build cache or all build caches after confirmation. Apps, original game files, saves and logs stay in place. The next rebuild may take longer. Shared cache confirmations list the other affected entries.

**Settings → Library → Storage** can recalculate sizes, clear logs and open the shared backups folder. **Remove Sources & Build Cache** also moves selected original source files to the Trash, while retaining the installed app and saves. Read that confirmation carefully; it differs from clearing a cache.

## Documentation and development

| Document | Contents |
|---|---|
| [Documentation index](docs/README.md) | What each docs folder holds and where to start. |
| [Changelog](CHANGELOG.md) | User-visible changes and release history. |
| [Development guide](docs/working-on-it/development.md) | Runtime preparation, debug builds, tests, packaging and releases. |
| [Screenshots and demo](docs/media/README.md) | Media inventory and display guidance. |
| [Contributing](CONTRIBUTING.md) | Change and verification guidelines. |
| [Security](SECURITY.md) | Private vulnerability reporting and handling sensitive files. |
| [Technical guide](docs/how-it-works/architecture.md) | How each area works today, in Italian. |
| [How to build](docs/working-on-it/conventions.md) | Where new code goes and the recipes to follow, in Italian. |
| [Flows](docs/how-it-works/flows.md) | End-to-end flows with diagrams, in Italian. |
| [File catalog](docs/working-on-it/file-map.md) | Responsibility of every project file, in Italian. |
| [Steam](docs/how-it-works/steam.md) | Steam integration: files read, game states, launch, playtime, achievements, limits; in Italian. |
| [Engine upgrade notes](docs/history/engine-upgrades/README.md) | Pin changes and their evidence. |

If you would like to support **Bium23, the original author of Arcane**, you can [buy Bium23 a coffee](https://buymeacoffee.com/bium). This supports Bium23, not the Oort NX fork.

## Credits and licences

Arcane is MIT licensed. It uses upstream [nxnative](https://github.com/seedds/nxnative). It began from the MIT nxnative_Launcher codebase, which has been rewritten since; that repository is no longer available and its notice stays in [NOTICE](NOTICE). Adaptations from [NX2Apple](https://github.com/LNPANDY/NX2Apple) cover key checks, failure explanations, diagnostics and updates.

The interface draws from the MIT [Selene](https://github.com/mattxslv/Selene) theme. Bundled fonts, sounds, palettes and runtime components retain their own licences; see [NOTICE](NOTICE), [media notices](Resources/Selene/NOTICE.txt) and [palette notices](Resources/Selene/NOTICE-palettes.txt).

The app icon uses original artwork. See the [generation notes](Resources/IconArtwork.md).

## Legal and third-party notices

**Project scope.** Arcane is an independent macOS game library and launcher. It supports installed Steam games for Mac and provides guided setup and local game builds through nxnative.

**Games and keys.** The project does not provide games, firmware, cryptographic keys or downloadable game packages. Users must supply their own game files and keys and have the rights and permissions required to use them. Do not submit these files through issues, pull requests or support requests.

**Local processing and external services.** Game preparation uses locally supplied files and keys. Arcane checks encrypted game headers using the supplied keys and invokes nxnative to perform the build. Setup, updates and optional artwork features may contact third-party services.

**Permitted use.** Owning a game or console does not necessarily authorise every form of copying, decryption or conversion. Applicable rules vary by jurisdiction. This project does not grant permission to circumvent technological protections or infringe third-party rights. Do not use it to distribute game files, keys or generated packages without the necessary authorisation.

**Third-party software and content.** Arcane does not distribute proprietary Nintendo game code, game assets, firmware or cryptographic keys. Open-source dependencies and bundled resources remain subject to their respective licences and notices. Artwork retrieved from external services remains subject to its owners’ rights and the applicable service terms.

**Trademarks.** Arcane is not affiliated with, sponsored by or endorsed by Nintendo or any other game publisher or platform provider. Product names, game titles and trademarks belong to their respective owners.

**Rights concerns.** If you believe material distributed by this project infringes your rights, contact the maintainer with the relevant material, your rights claim and sufficient information to assess it. Substantiated concerns will be reviewed promptly and addressed as appropriate.

**No warranty.** Arcane is provided “as is”, without warranty, as described in LICENSE. Third-party components are governed by their own licences. See NOTICE for acknowledgements.
