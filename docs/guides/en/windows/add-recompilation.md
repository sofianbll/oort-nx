---
title: Add a recompilation
system: windows
topic: add-recompilation
order: 4
version: 0.1.0-alpha.2
minutes: 5
tried: Tried on a fresh GitHub machine, with invented games, an invented Steam and invented services. A player started a game on their PC with alpha.1, not yet with this one.
captures: folder-picker, needs-files, file-chosen, prepare
---

## Choose the folder
<!-- step folder checked f18e2119:desktop/ui/app.js f18e2119:Sources/OortCompanion/Manifest.swift -->
**+** tile › **A folder of games**. Each game there is a folder with its `recomplauncher.json` file.

![Choosing a folder](../../media/windows/folder-picker.en.webp)

## See what is missing
<!-- step needs checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/walk.js -->
If a game asks for files, its button becomes **Choose files**.

![An invented game asking for a file](../../media/windows/needs-files.en.webp)

## Give your copy
<!-- step files checked f18e2119:Sources/OortCompanion/Companion.swift f18e2119:desktop/tests/play.js -->
On its page, choose your own file. Oort only remembers where it is, without copying it.

![The page with a file chosen (picture in French)](../../media/windows/file-chosen.fr.webp)

## Get it ready if needed
<!-- step prepare checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/play.js -->
**Get ready** runs the step the project planned. If it needs files copied or downloaded, do it in the project itself.

![The Get ready step (picture in French)](../../media/windows/prepare.fr.webp)
