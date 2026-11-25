---
title: Désinstaller
system: linux
topic: uninstall
order: 12
version: 0.1.0-alpha.2
minutes: 2
tried: Essayé sur une machine neuve de GitHub (Ubuntu 24.04), avec des jeux inventés et un faux Steam. Jamais sur l’ordinateur d’un joueur.
captures: missing:uninstall, missing:data-folder
---

## Retire l’app
<!-- step remove checked f18e2119:desktop/tests/linux/prove.sh -->
`sudo apt remove oort-nx`. Tes jeux ne sont pas touchés.

<!-- missing uninstall: La page ou le terminal de désinstallation. -->

## Efface ta bibliothèque si tu veux
<!-- step library checked f18e2119:desktop/tests/linux/prove.sh f18e2119:desktop/src-tauri/src/lib.rs -->
Elle reste dans `~/.local/share/io.github.sofianbll.oort-nx.desktop`. Supprime ce dossier pour oublier tes réglages et ton temps de jeu.

<!-- missing data-folder: Le dossier de données, avec une bibliothèque inventée. -->
