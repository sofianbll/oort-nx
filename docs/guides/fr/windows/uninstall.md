---
title: Désinstaller
system: windows
topic: uninstall
order: 12
version: 0.1.0-alpha.2
minutes: 2
tried: Essayé sur une machine neuve de GitHub, avec des jeux inventés, un faux Steam et de faux services. Un joueur a lancé un jeu sur son PC avec l’alpha.1, pas encore avec celle-ci.
captures: missing:uninstall, missing:data-folder
---

## Retire l’app
<!-- step remove checked f18e2119:desktop/tests/windows/prove.ps1 -->
**Paramètres Windows › Applications › Oort NX › Désinstaller**. Tes jeux ne sont pas touchés.

<!-- missing uninstall: La page ou le terminal de désinstallation. -->

## Efface ta bibliothèque si tu veux
<!-- step library checked f18e2119:desktop/tests/windows/prove.ps1 f18e2119:desktop/src-tauri/src/lib.rs -->
Elle reste dans `%LOCALAPPDATA%\io.github.sofianbll.oort-nx.desktop`. Supprime ce dossier pour oublier tes réglages et ton temps de jeu.

<!-- missing data-folder: Le dossier de données, avec une bibliothèque inventée. -->
