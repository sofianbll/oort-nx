# Oort NX

<img src="Resources/AppIcon-Light.png" alt="Oort NX halftone icon" width="96" height="96">

**Your games, together on Mac.** Browse Mac app shortcuts, installed Steam games for Mac and games built with nxnative in one library. Pick a game and play with a controller, keyboard or mouse. Your game files are yours to manage.

**[See it in motion](https://sofianbll.github.io/oort-nx/en/)** · [Player guide](PLAYER-GUIDE.md) · [Français](README.fr.md) · [Changelog](CHANGELOG.md)

## Get started

- **Apple silicon · macOS 26 or later.** Steam and individual games may need a newer system.
- **Download** the DMG from [Releases](https://github.com/sofianbll/oort-nx/releases) and drag Oort NX to Applications. The app is not notarised: open it once, then choose **Open Anyway** in **System Settings → Privacy & Security**. Coming from 0.3.0? Install this DMG once: your library is copied and the earlier one stays untouched.
- **Beta.** Versions follow semantic versioning. Real Drive transfers and games have not been tried with this build.
- **Building a game?** Open **Settings → Switch → Engine**. New builds need compatible game files you have permission to use, nxnative and its matching Xcode and Metal compiler. Games, keys and firmware are not included. You do not need the build tools to play an existing game app.

For a source build, see the [development guide](docs/working-on-it/development.md). For help, see [Contributing](CONTRIBUTING.md); report vulnerabilities [privately](SECURITY.md).

## Platform support

This app runs on macOS. **Ryujinx-Nextendo** is the engine target for future Windows work; there is no Windows build or compatibility claim. Nextendo on Mac is unchanged and remains optional. The iPhone and iPad sources are in `mobile/`; no build is published.

## Credits

Oort NX builds on [Arcane by Bium23](https://github.com/Bium23/NxLibrary) and the [Selene theme by Matthew Silva](https://github.com/mattxslv/Selene). The artwork picker takes inspiration from [Playnite by Josef Nemec](https://github.com/JosefNemec/Playnite). The iPhone and iPad app's host layer comes from [NX2Apple by LNPANDY](https://github.com/LNPANDY/NX2Apple) (MIT). Thanks to [nxnative](https://github.com/seedds/nxnative) and [Nextendo](https://github.com/eyasbzour/nxnative-online) contributors.

[MIT license](LICENSE) · [Third-party notices](NOTICE) · [Support Bium23](https://buymeacoffee.com/bium)
