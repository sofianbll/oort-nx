---
title: What Oort reads, writes and sends
system: ios
topic: data
order: 13
version: 0.1.0-alpha.1
minutes: 2
tried: Tried only in a simulator (iPhone and iPad, iOS 27.2) with invented games. Never on a real device.
captures: picker, settings, settings
---

## Reads
<!-- step reads code e3cd6df1:mobile/Sources/OortMobile/FrameworkImport.swift e3cd6df1:mobile/PROVENANCE.md -->
The games you add, and the folders in Files you choose.

![Apple’s Files](../../media/ios/picker.en.webp)

## Writes
<!-- step writes code e3cd6df1:mobile/Sources/OortMobile/FrameworkImport.swift e3cd6df1:mobile/Sources/ShellHost/PlayHistoryStore.swift -->
Its own folder, visible in Files: games, saves, settings and play time. Plus the save folder you chose.

![The Settings page](../../media/ios/settings.en.webp)

## Sends
<!-- step sends code e3cd6df1:mobile/PROVENANCE.md e3cd6df1:mobile/Sources/OortMobile/Resources/Localizable.xcstrings -->
Nothing: no network request, no account. The tool that signs the app does talk to Apple with your account.

![The Settings page](../../media/ios/settings.en.webp)
