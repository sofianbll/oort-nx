---
title: Dépannage
system: linux
topic: troubleshooting
order: 12
version: 0.1.0-alpha.1
minutes: 4
tried: Essayé sur une machine neuve de GitHub (Ubuntu 24.04) avec des jeux inventés. Jamais sur l’ordinateur d’un joueur.
captures: settings-home, damaged, crash, home, settings-about
---

## Il manque un jeu
<!-- step missing checked cc9db84a:desktop/ui/app.js cc9db84a:Sources/OortCompanion/Companion.swift -->
**Réglages › Accueil › Relire**. Pour une recompilation, vérifie que son dossier contient `recomplauncher.json`.

![Réglages › Accueil (capturé sous Windows)](../../media/windows/settings-home.fr.webp)

## Le jeu est marqué illisible
<!-- step unreadable checked cc9db84a:desktop/ui/app.js cc9db84a:desktop/tests/walk.js -->
Son `recomplauncher.json` est abîmé ou demande un lanceur plus récent. Reprends-le dans le projet.

![Un jeu inventé abîmé (capturé sous Windows)](../../media/windows/damaged.fr.webp)

## Le jeu s’arrête
<!-- step crash checked cc9db84a:desktop/src-tauri/src/lib.rs cc9db84a:desktop/tests/play.js -->
Oort montre le message que le jeu a laissé. Vérifie ensuite que le jeu démarre seul, hors d’Oort.

![Le message d’un jeu inventé qui s’arrête (capturé sous Windows)](../../media/windows/crash.fr.webp)

## La manette n’est pas vue
<!-- step pad code cc9db84a:desktop/src-tauri/src/pad.rs cc9db84a:desktop/ui/nav.js -->
Appuie sur un bouton avec la fenêtre d’Oort devant, puis débranche et rebranche-la. Pas essayé avec une vraie manette.

![L’accueil avec des jeux inventés](../../media/linux/home.fr.webp)

## Raconte le problème
<!-- step report code cc9db84a:SECURITY.md cc9db84a:CONTRIBUTING.md -->
[Ouvre un signalement](https://github.com/sofianbll/oort-nx/issues) : ce que tu faisais, ce que tu as vu, ta version. N’y joins ni jeu, ni clé, ni sauvegarde.

![Réglages › Informations (capturé sous Windows)](../../media/windows/settings-about.fr.webp)
