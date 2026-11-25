---
title: Troubleshooting
system: windows
topic: troubleshooting
order: 12
version: 0.1.0-alpha.1
minutes: 4
tried: Tried on a fresh GitHub machine with invented games, and by one player on their PC (one game started, 25 November 2026).
captures: settings-home, damaged, crash, home, settings-about
---

## A game is missing
<!-- step missing checked cc9db84a:desktop/ui/app.js cc9db84a:Sources/OortCompanion/Companion.swift -->
**Settings › Home › Look again**. For a recompilation, check that its folder holds `recomplauncher.json`.

![Settings › Home](../../media/windows/settings-home.en.webp)

## The game is marked unreadable
<!-- step unreadable checked cc9db84a:desktop/ui/app.js cc9db84a:desktop/tests/walk.js -->
Its `recomplauncher.json` is damaged or asks for a newer launcher. Take it again from the project.

![A damaged invented game](../../media/windows/damaged.en.webp)

## The game stops
<!-- step crash checked cc9db84a:desktop/src-tauri/src/lib.rs cc9db84a:desktop/tests/play.js -->
Oort shows the message the game left. Then check that the game starts on its own, outside Oort.

![The message of an invented game that stops (picture in French)](../../media/windows/crash.fr.webp)

## The controller is not seen
<!-- step pad code cc9db84a:desktop/src-tauri/src/pad.rs cc9db84a:desktop/ui/nav.js -->
Press a button with the Oort window in front, then unplug it and plug it in again. Not tried with a real controller.

![The home screen with invented games](../../media/windows/home.en.webp)

## Tell us
<!-- step report code cc9db84a:SECURITY.md cc9db84a:CONTRIBUTING.md -->
[Open a report](https://github.com/sofianbll/oort-nx/issues): what you were doing, what you saw, your version. Attach no game, key or save.

![Settings › About](../../media/windows/settings-about.en.webp)
