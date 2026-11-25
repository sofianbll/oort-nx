---
title: A game’s pictures and information
system: linux
topic: settings-pictures
order: 9
version: 0.1.0-alpha.2
minutes: 3
tried: Tried on a fresh GitHub machine (Ubuntu 24.04), with invented games and an invented Steam. Never on a player’s computer.
captures: pictures, pictures, online-asked, online-found, online-results, integrations-on
---

## Open the page
<!-- step open code f18e2119:desktop/ui/app.js f18e2119:Sources/OortCompanion/Companion+Own.swift -->
On a game: **Options › Pictures and information**.

![An invented program’s pictures and information (picture in French) (captured on Windows)](../../media/windows/pictures.fr.webp)

## Choose your own pictures
<!-- step own code f18e2119:desktop/ui/app.js f18e2119:Sources/OortCompanion/Companion+Own.swift f18e2119:Tests/OortCompanionTests/OwnTests.swift -->
Cover, icon, background or logo: a PNG, JPEG or WebP file. It is copied into Oort’s folder; the original does not change.

![An invented program’s pictures and information (picture in French) (captured on Windows)](../../media/windows/pictures.fr.webp)

## Look online, if you say yes
<!-- step ask code f18e2119:desktop/ui/app.js f18e2119:Sources/OortCompanion/Online.swift -->
Oort sends the game’s name or its Steam number, and your language, to the Steam store, Wikidata and Wikipedia. Checked with invented services, never with the real ones.

![The question before looking online (picture in French) (captured on Windows)](../../media/windows/online-asked.fr.webp)

## See what was found
<!-- step found code f18e2119:desktop/ui/app.js f18e2119:Sources/OortCompanion/Online.swift -->
Cover, description, year and genres come by themselves. Wikipedia limits requests: it is mostly the Steam store that answers.

![The invented program, with what was found (captured on Windows)](../../media/windows/online-found.en.webp)

## Correct it
<!-- step right code f18e2119:desktop/ui/app.js f18e2119:Sources/OortCompanion/Online.swift -->
Wrong game? **Information online**, then the right one. **None of these** removes what came from the internet for that game.

![Choosing the right game (picture in French) (captured on Windows)](../../media/windows/online-results.fr.webp)

## Turn it off or erase it
<!-- step off code f18e2119:desktop/ui/app.js f18e2119:Sources/OortCompanion/Online.swift -->
**Settings › Integrations** turns information online off and deletes everything that was found. Your own pictures stay.

![Settings › Integrations, information online on (picture in French) (captured on Windows)](../../media/windows/integrations-on.fr.webp)
