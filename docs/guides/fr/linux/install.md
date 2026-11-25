---
title: Installer
system: linux
topic: install
order: 1
version: 0.1.0-alpha.1
minutes: 5
tried: Essayé sur une machine neuve de GitHub (Ubuntu 24.04) avec des jeux inventés. Jamais sur l’ordinateur d’un joueur.
captures: missing:release-page, missing:checksum, missing:apt-install, first-empty
---

## Télécharge
<!-- step download code cc9db84a:desktop/src-tauri/tauri.conf.json https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.1 -->
Prends `Oort-NX-Linux-0.1.0-alpha.1-x64.deb` et `SHA256SUMS` sur la [page de la version](https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.1). Il faut un Linux 64 bits qui lit les paquets .deb ; seul Ubuntu 24.04 a été essayé.

<!-- missing release-page: La page de la version sur GitHub, fichiers dépliés. -->

## Compare l’empreinte
<!-- step checksum code cc9db84a:desktop/tests/linux/prove.sh https://github.com/sofianbll/oort-nx/releases/tag/windows-v0.1.0-alpha.1 -->
Dans le dossier du téléchargement, `sha256sum -c SHA256SUMS --ignore-missing` doit répondre OK. Sinon, supprime le fichier.

<!-- missing checksum: Le terminal avec l’empreinte et sa réponse. -->

## Installe le paquet
<!-- step run checked cc9db84a:desktop/tests/linux/prove.sh -->
Dans le dossier du téléchargement : `sudo apt install ./Oort-NX-Linux-0.1.0-alpha.1-x64.deb`. Les bibliothèques nécessaires viennent avec.

<!-- missing apt-install: Le terminal pendant l’installation du .deb. -->

## Ouvre Oort NX
<!-- step open checked cc9db84a:desktop/tests/linux/prove.sh -->
Il est dans le menu des applications. La première page te demande où sont tes jeux.

![L’accueil vide d’Oort NX (capturé sous Windows)](../../media/windows/first-empty.fr.webp)
