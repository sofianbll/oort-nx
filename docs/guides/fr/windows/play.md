---
title: Jouer et revenir
system: windows
topic: play
order: 6
version: 0.1.0-alpha.2
minutes: 3
tried: Essayé sur une machine neuve de GitHub, avec des jeux inventés, un faux Steam et de faux services. Un joueur a lancé un jeu sur son PC avec l’alpha.1, pas encore avec celle-ci.
captures: launch, session-card, running
---

## Lance
<!-- step play checked f18e2119:desktop/src-tauri/src/lib.rs f18e2119:desktop/tests/windows/prove.ps1 -->
Choisis **Jouer**. L’écran montre le jeu, puis Oort se réduit.

![L’écran de lancement](../../media/windows/launch.fr.webp)

## Reviens
<!-- step back checked f18e2119:desktop/src-tauri/src/lib.rs f18e2119:desktop/tests/windows/prove.ps1 -->
Quitte le jeu comme d’habitude : Oort revient devant et affiche le temps de ta partie.

![La fiche de session, en haut à droite](../../media/windows/session-card.fr.webp)

## Ferme un jeu bloqué
<!-- step close checked f18e2119:desktop/ui/app.js f18e2119:desktop/tests/play.js -->
Reviens à la fenêtre d’Oort : **Fermer le jeu** apparaît au bout de quatre secondes. Ce qui n’est pas enregistré est perdu. Le bouton Home n’est pas encore pris en charge en jeu.

![Le bouton Fermer le jeu](../../media/windows/running.fr.webp)
