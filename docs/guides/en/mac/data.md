---
title: What Oort reads, writes and sends
system: mac
topic: data
order: 15
version: 0.5.0-beta.3
minutes: 3
tried: Checked automatically with invented games. No real game started, no real Drive transfer and no real controller with this version.
captures: settings-integrations, settings-storage, settings-about, settings-cloud
---

## Reads
<!-- step reads code bf0c3410:docs/how-it-works/steam.md bf0c3410:docs/how-it-works/architecture.md -->
The folders you choose. If you turn it on, Steam’s game lists. If you build, your files and your keys, on this Mac.

![Settings › Integrations](../../media/mac/settings-integrations.en.webp)

## Writes
<!-- step writes code bf0c3410:docs/how-it-works/architecture.md bf0c3410:Sources/NXLibraryCore/App/AppDataProfile.swift -->
`~/Library/Application Support/Oort NX`, the apps it builds, and the settings and mods of built games. Nothing in Steam. Only you can read the copy of your keys.

![Settings › Storage](../../media/mac/settings-storage.en.webp)

## Sends, by itself
<!-- step alone code bf0c3410:Sources/NXLibraryCore/Resources/Localizable.xcstrings bf0c3410:docs/how-it-works/architecture.md -->
It asks GitHub whether a newer version exists. It looks for pictures, scores and descriptions with your games’ name or number: Nlib, GameTDB, Steam, Wikidata, Wikipedia and other public sources.

![Settings › About](../../media/mac/settings-about.en.webp)

## Sends, if you ask
<!-- step asked code bf0c3410:Sources/NXLibraryCore/Resources/Localizable.xcstrings bf0c3410:PLAYER-GUIDE.md -->
Google Drive, Nextendo, GameBanana mods, SteamGridDB, IGDB: only once turned on, with your own account where one is needed. Building sends no game file and no key.

![Settings › Cloud library](../../media/mac/settings-cloud.en.webp)
