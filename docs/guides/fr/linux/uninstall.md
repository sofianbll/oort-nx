---
title: Désinstaller
system: linux
topic: uninstall
order: 11
version: 0.1.0-alpha.1
minutes: 2
tried: Essayé sur une machine neuve de GitHub (Ubuntu 24.04) avec des jeux inventés. Jamais sur l’ordinateur d’un joueur.
captures: missing:uninstall, missing:data-folder
---

## Retire l’app
<!-- step remove checked cc9db84a:desktop/tests/linux/prove.sh -->
`sudo apt remove oort-nx`. Tes jeux ne sont pas touchés.

<!-- missing uninstall: La page ou le terminal de désinstallation. -->

## Efface ta bibliothèque si tu veux
<!-- step library checked cc9db84a:desktop/tests/linux/prove.sh cc9db84a:desktop/src-tauri/src/lib.rs -->
Elle reste dans `~/.local/share/io.github.sofianbll.oort-nx.desktop`. Supprime ce dossier pour oublier tes réglages et ton temps de jeu.

<!-- missing data-folder: Le dossier de données, avec une bibliothèque inventée. -->
