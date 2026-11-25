---
title: Jouer et revenir
system: linux
topic: play
order: 6
version: 0.1.0-alpha.2
minutes: 3
tried: Essayé sur une machine neuve de GitHub (Ubuntu 24.04), avec des jeux inventés et un faux Steam. Jamais sur l’ordinateur d’un joueur.
captures: launch, back, running
---

## Lance
<!-- step play checked f18e2119:desktop/src-tauri/src/lib.rs f18e2119:desktop/tests/linux/prove.sh -->
Choisis **Jouer**. L’écran montre le jeu, puis Oort se réduit.

![L’écran de lancement](../../media/linux/launch.fr.webp)

## Reviens
<!-- step back checked f18e2119:desktop/src-tauri/src/lib.rs f18e2119:desktop/tests/linux/prove.sh -->
Quitte le jeu comme d’habitude : Oort revient devant et affiche le temps de ta partie.

![Oort après la partie](../../media/linux/back.fr.webp)

## Ferme un jeu bloqué
<!-- step close checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/play.js -->
Reviens à la fenêtre d’Oort : **Fermer le jeu** apparaît au bout de quatre secondes. Ce qui n’est pas enregistré est perdu. Le bouton Home n’est pas encore pris en charge en jeu.

![Le bouton Fermer le jeu (capturé sous Windows)](../../media/windows/running.fr.webp)
